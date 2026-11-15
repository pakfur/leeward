class_name MovementResolver
extends RefCounted
## MovementResolver - Resolves plotted movement impulse-by-impulse
## Multi-ship resolution: contested hexes, bearing off, collisions, fouling.
## Ships move simultaneously; contests checked per impulse. Every ship holds two hexes, bow and
## stern; each step enters one hex: an ahead step its new bow hex, a turn its new stern hex.
## A swinging stern may overlap another ship for one segment (6.B); an overlap left uncleared amends
## the turning ship's plot and the resolution is run again (see run()). Two sterns swinging into one
## hex with no further MPs (6.C.1b), or two ships swinging onto each other's bows (6.B.5), contest it:
## the winner turns, the loser's turn is cancelled.

var game_state: Node = null
var hex_grid: HexGrid = null
var _explicit_rng: RandomNumberGenerator = null

# Per-segment overlap bookkeeping (6.B), reset for every resolution pass.
var _seg_start_bows: Dictionary = {}  # ship_id -> bow hex at the start of the segment
var _seg_start_facings: Dictionary = {}  # ship_id -> facing at the start of the segment
var _swings: Dictionary = {}  # ship_id -> {hex, pre_bow, pre_facing, facing}: sterns swung this segment
## ship_id -> {hex, other_id, other_ids, segment, pre_bow, pre_facing, facing, reason}: overlaps made on
## `segment`, checked at the end of the next one.
var _pending_overlaps: Dictionary = {}
## Stern contests lost this pass whose loser must still move ahead to meet its deceleration minimum:
## {ship_id, kind: "contest", segment, other_id, pre_bow, pre_facing, reason, events: {ship_id: [ev]}}.
## They amend the loser's plot like a rollback; `events` (the rolls and STERN_BLOCKED) are put back into
## the final log, where the contest is no longer rolled.
var _contest_amendments: Array = []
## ship_id -> true for ships whose MA-0 turn (and its tacking roll, 5.D.1) an amended plot removed. The
## tacking die is still drawn on segment 0, so the rolls after it are the ones of the first pass, and the
## roll stays in the log.
var _tacks_dropped: Dictionary = {}

var rng: RandomNumberGenerator:
	get:
		if _explicit_rng:
			return _explicit_rng
		if game_state and game_state.get("rng"):
			return game_state.rng
		if not _explicit_rng:
			_explicit_rng = RandomNumberGenerator.new()
		return _explicit_rng


func _init(p_game_state: Node = null, p_rng: RandomNumberGenerator = null) -> void:
	game_state = p_game_state if p_game_state else GameState
	hex_grid = HexGrid.new()
	_explicit_rng = p_rng


## ============================================================================
## Main entry point
## ============================================================================

func run(ships: Array[ShipState], environment: EnvironmentState) -> MovementTypes.ResolutionLog:
	@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
	var log = MovementTypes.ResolutionLog.new(game_state.current_turn if game_state else 0)

	# An overlap that is not cleared on the next segment amends the turning ship's plot (6.B.4: "change
	# all ship logs to reflect the actual moves"), and the whole resolution is run again with the amended
	# plots, from the same RNG state. Every roll made before the rolled-back segment is made again with
	# the same die; a tacking roll whose turn was amended away is still drawn in its place (see
	# _tacks_dropped), so the dice after it stay where they were. Rolls from the rolled-back segment on
	# may differ, since the ships stand elsewhere. Every rollback removes a plotted turn, so this ends.
	var ship_map: Dictionary = {}
	var plotted: Dictionary = {}
	var pass_limit: int = 1
	for ship_state in ships:
		ship_map[ship_state.ship_id] = ship_state
		plotted[ship_state.ship_id] = _get_plotted_steps(ship_state)
		pass_limit += plotted[ship_state.ship_id].size()
	var rng_start: int = rng.state
	var amended: Dictionary = {}  # ship_id -> steps actually resolved
	var rollbacks: Dictionary = {}  # ship_id -> the rollback or lost stern contest that amended its plot
	var outcome: Dictionary = {}
	# All overlaps that fail at the same segment end are rolled back together (they are simultaneous,
	# 6.B.4); the pass then restarts.
	for attempt in range(pass_limit):
		rng.state = rng_start
		outcome = _resolve_pass(ships, ship_map, plotted, amended, environment)
		if outcome.rollbacks.is_empty():
			break
		if attempt == pass_limit - 1:
			push_error("MovementResolver: overlap rollbacks did not settle")
			break
		for rb in outcome.rollbacks:
			var sid: String = rb.ship_id
			amended[sid] = _amended_steps(ship_map[sid], amended.get(sid, plotted[sid]), rb)
			rollbacks[sid] = rb
			Trace.trace_log("MovementResolver", "plot amended", {"ship": sid, "segment": rb.segment,
				"other": rb.other_id, "reason": rb.reason, "steps": amended[sid].size()})

	var results: Dictionary = outcome.results
	log.max_impulses = outcome.max_impulses
	for sid in rollbacks:
		# A rollback found in an earlier pass can go stale: a later rollback of another ship may stop
		# this one before it ever reaches the overlap segment. Its amended plot still stands, but the
		# swing it never made is not logged (or played back).
		if not _reached_segment(results[sid], rollbacks[sid].segment):
			continue
		if rollbacks[sid].get("kind", "") == "contest":
			_record_contest(results, rollbacks[sid], amended[sid].size())
			continue
		_record_rollback(results[sid], rollbacks[sid], amended[sid].size())
		log.max_impulses = maxi(log.max_impulses, rollbacks[sid].segment + 2)
	for sid in results:
		log.add_result(results[sid])

	return log


## One resolution of every ship's steps (`amended` overrides a ship's plot). Returns {"results",
## "max_impulses", "rollbacks"}; when an overlap fails its check the pass stops there and "rollbacks"
## lists the turns to undo.
func _resolve_pass(
	ships: Array[ShipState],
	ship_map: Dictionary,
	plotted: Dictionary,
	amended: Dictionary,
	environment: EnvironmentState
) -> Dictionary:
	var results: Dictionary = {}
	var current_hexes: Dictionary = {}  # ship_id -> bow hex
	var current_facings: Dictionary = {}  # ship_id -> facing
	var stopped: Dictionary = {}
	var steps_by_ship: Dictionary = {}
	var forward_since_turn: Dictionary = {}
	var pivots_this_turn: Dictionary = {}
	_pending_overlaps = {}
	_contest_amendments = []
	_tacks_dropped = {}
	for sid in amended:
		if _find_tacking_impulse(ship_map[sid], plotted[sid]) == 0 \
				and _find_tacking_impulse(ship_map[sid], amended[sid]) != 0:
			_tacks_dropped[sid] = true

	for ship_state in ships:
		var result = MovementTypes.ShipResolutionResult.new(ship_state.ship_id)
		result.final_hex = ship_state.hex_position
		result.final_facing = ship_state.facing
		results[ship_state.ship_id] = result
		current_hexes[ship_state.ship_id] = ship_state.hex_position
		current_facings[ship_state.ship_id] = ship_state.facing
		stopped[ship_state.ship_id] = false
		forward_since_turn[ship_state.ship_id] = 0
		pivots_this_turn[ship_state.ship_id] = 0

		var ship_steps: Array = amended.get(ship_state.ship_id, plotted[ship_state.ship_id])
		if ship_steps.is_empty():
			if _is_in_irons(ship_state, environment):
				if _tacks_dropped.has(ship_state.ship_id):
					result.immobilized = true  # told after its tacking roll, on segment 0
				else:
					_remain_in_irons(ship_state, result, "in irons, no turn plotted")
			elif not amended.has(ship_state.ship_id):  # a plot amended to nothing is told by its rollback
				var ev = MovementTypes.ResolutionEvent.new(
					ship_state.ship_id, 0, MovementTypes.ResolutionEventType.SKIP_NO_PLOT
				)
				ev.from_hex = ship_state.hex_position
				ev.to_hex = ship_state.hex_position
				ev.facing = ship_state.facing
				ev.detail = "no movement plotted"
				result.events.append(ev)
			stopped[ship_state.ship_id] = true
		steps_by_ship[ship_state.ship_id] = ship_steps

	var max_impulses: int = 0
	for sid in steps_by_ship:
		var count: int = steps_by_ship[sid].size()
		if count > max_impulses:
			max_impulses = count

	# One segment past the last step: an overlap made on the last step is checked when nobody moves.
	for impulse in range(max_impulses + 1):
		_resolve_impulse(impulse, ships, ship_map, steps_by_ship, results, current_hexes, current_facings, stopped, environment, forward_since_turn, pivots_this_turn)
		var failed: Array = _check_overlaps(impulse, current_hexes, current_facings)
		# An overlap failing here was made on the previous segment, so it goes first: its rollback may
		# change whether this segment's contests happen at all.
		if failed.is_empty():
			failed = _contest_amendments
		if not failed.is_empty():
			return {"results": results, "max_impulses": max_impulses, "rollbacks": failed}
		_note_overlaps(impulse, results, current_hexes, current_facings)

	return {"results": results, "max_impulses": max_impulses, "rollbacks": []}


## ============================================================================
## Per-impulse resolution
## ============================================================================

func _resolve_impulse(
	impulse: int,
	ships: Array[ShipState],
	ship_map: Dictionary,
	steps_by_ship: Dictionary,
	results: Dictionary,
	current_hexes: Dictionary,
	current_facings: Dictionary,
	stopped: Dictionary,
	environment: EnvironmentState,
	forward_since_turn: Dictionary,
	pivots_this_turn: Dictionary
) -> void:
	var intended_moves: Dictionary = {}
	_swings = {}
	_seg_start_bows = current_hexes.duplicate()
	_seg_start_facings = current_facings.duplicate()

	for ship_state in ships:
		var sid = ship_state.ship_id
		if impulse == 0 and _tacks_dropped.has(sid):
			_redraw_dropped_tack(ship_state, environment, results[sid])
		if stopped[sid]:
			continue

		var ship_steps: Array = steps_by_ship[sid]
		if impulse >= ship_steps.size():
			stopped[sid] = true
			continue

		var step: Dictionary = ship_steps[impulse]
		var step_hex = Vector2i(
			int(step.get("hex", {}).get("q", 0)),
			int(step.get("hex", {}).get("r", 0))
		)
		var step_facing: int = int(step.get("facing", ship_state.facing))

		var tacking_impulse: int = _find_tacking_impulse(ship_state, ship_steps)
		if tacking_impulse >= 0 and impulse == tacking_impulse:
			var result: MovementTypes.ShipResolutionResult = results[sid]
			var tack_success: bool = _roll_tacking(ship_state, environment, result, impulse)
			if not tack_success:
				# The plotted turn is erased (5.D.1): the ship keeps its hex and heading.
				result.final_hex = current_hexes[sid]
				result.final_facing = ship_state.facing
				result.immobilized = true
				result.tacking_failed = true
				stopped[sid] = true
				continue

		intended_moves[sid] = {"hex": step_hex, "facing": step_facing}

	if intended_moves.is_empty():
		return

	# Hexes held during this segment: every hex of a ship that is not moving, and the bow hex of
	# every moving ship (an ahead step turns it into the stern, a turn pivots on it). A moving ship's
	# old stern hex is held too until its own step succeeds; a ship whose step fails keeps it.
	var held: Dictionary = Occupancy.from_positions(current_hexes, current_facings, intended_moves.keys())
	var start_bows: Dictionary = {}
	var start_facings: Dictionary = {}
	# Hex -> ids of the moving ships whose bow (or old stern) it is at the start of the segment. Lists:
	# during an overlap two sterns (or a stern and a bow) share a hex, and a group entering it waits for
	# every one of them.
	var old_stern_owner: Dictionary = {}
	var start_bow_owner: Dictionary = {}
	for sid in intended_moves:
		held[current_hexes[sid]] = sid
		start_bows[sid] = current_hexes[sid]
		start_facings[sid] = current_facings[sid]
		_add_owner(start_bow_owner, current_hexes[sid], sid)
		_add_owner(old_stern_owner, HexGrid.stern_of(current_hexes[sid], current_facings[sid]), sid)

	# Group the entered hexes, bow-entries (ahead) and stern-entries (turns) apart.
	var bow_targets: Dictionary = {}
	var stern_targets: Dictionary = {}
	for sid in intended_moves:
		var move: Dictionary = intended_moves[sid]
		var bow: Vector2i = current_hexes[sid]
		var facing: int = current_facings[sid]
		var entered: Vector2i = _entered_hex(bow, facing, move.hex, move.facing)
		var targets: Dictionary = stern_targets if _is_stern_entry(bow, facing, move.hex, move.facing) else bow_targets
		if not targets.has(entered):
			targets[entered] = []
		targets[entered].append(sid)

	# Resolve the groups (stern-entries first, then bow-entries), but a group entering a hex of a moving
	# ship (its bow, or its old stern) waits until that ship's own group is resolved. All of a segment's
	# movement is done before conflicts are checked (6.A.5): a ship in the way collides with the ship
	# only after that ship's own step, so the result does not depend on ship order, and an old stern is
	# known to be vacated or kept. In a cycle (head-on bows, or each ship entering the next one's old
	# stern) no group is ready and the group holding the lowest ship id goes, so the result does not
	# depend on ship order either.
	var pending: Array = []
	for entered in stern_targets:
		pending.append({"stern": true, "hex": entered, "ids": stern_targets[entered]})
	for entered in bow_targets:
		pending.append({"stern": false, "hex": entered, "ids": bow_targets[entered]})
	var resolved: Dictionary = {}
	while not pending.is_empty():
		var pick: int = -1
		for i in range(pending.size()):
			if _group_ready(pending[i], start_bow_owner, old_stern_owner, resolved):
				pick = i
				break
		if pick < 0:
			pick = _lowest_id_group(pending)
		var group: Dictionary = pending[pick]
		pending.remove_at(pick)
		if group.stern:
			_resolve_stern_entries(group.ids, group.hex, impulse, held, intended_moves, ship_map, steps_by_ship,
				results, current_hexes, current_facings, stopped, forward_since_turn, pivots_this_turn)
		else:
			_resolve_bow_entries(group.ids, group.hex, impulse, held, intended_moves, ship_map, results,
				current_hexes, current_facings, stopped, environment, forward_since_turn, pivots_this_turn)
		for sid in group.ids:
			resolved[sid] = true
			if current_hexes[sid] == start_bows[sid] and current_facings[sid] == start_facings[sid]:
				held[HexGrid.stern_of(start_bows[sid], start_facings[sid])] = sid  # it keeps its stern


## Index of the pending group holding the lowest ship id (cycle tie-break).
func _lowest_id_group(pending: Array) -> int:
	var pick: int = 0
	var lowest: String = ""
	for i in range(pending.size()):
		for sid in pending[i].ids:
			if lowest == "" or String(sid) < lowest:
				lowest = sid
				pick = i
	return pick


func _add_owner(owners: Dictionary, hex: Vector2i, sid: String) -> void:
	if not owners.has(hex):
		owners[hex] = []
	owners[hex].append(sid)


## True when no moving ship whose bow or old stern lies on the group's hex is still unresolved.
func _group_ready(group: Dictionary, start_bow_owner: Dictionary, old_stern_owner: Dictionary, resolved: Dictionary) -> bool:
	for owners in [start_bow_owner, old_stern_owner]:
		for owner_id in owners.get(group.hex, []):
			if not resolved.has(owner_id) and not owner_id in group.ids:
				return false
	return true


## Stern-entries into `entered`. A swinging stern may enter a hex another ship holds or a bow enters
## in the same segment (6.B.2): the overlap is noted at the end of the segment and must be cleared on
## the next one. A bow entering the same hex goes ahead as if the stern were not there (6.B.4b).
## Two sterns entering together with no further MPs plotted contest the hex (6.C.1b, 6.C.5); if one of
## them has more MPs, both swing in and the 6.B overlap rules apply. A complete overlap (6.B.5) is
## contested too. A lost contest cancels the turn; it is never a collision.
func _resolve_stern_entries(
	ids: Array,
	entered: Vector2i,
	impulse: int,
	held: Dictionary,
	intended_moves: Dictionary,
	ship_map: Dictionary,
	steps_by_ship: Dictionary,
	results: Dictionary,
	current_hexes: Dictionary,
	current_facings: Dictionary,
	stopped: Dictionary,
	forward_since_turn: Dictionary,
	pivots_this_turn: Dictionary
) -> void:
	var active: Array = []
	for sid in ids:
		if not stopped[sid]:  # a collision earlier in this segment already stopped it
			active.append(sid)
	if active.size() > 1 and _all_on_last_step(active, impulse, steps_by_ship):
		active = [_stern_contest(active, impulse, ship_map, results, current_hexes, current_facings, stopped)]
	for sid in active:
		var partner: String = _complete_overlap_partner(sid, entered, held, intended_moves, stopped)
		if partner != "":
			var winner: String = _stern_contest([sid, partner], impulse, ship_map, results, current_hexes,
				current_facings, stopped)
			if winner != sid:
				continue
		var prev_facing: int = current_facings[sid]
		_swings[sid] = {"hex": entered, "pre_bow": current_hexes[sid], "pre_facing": prev_facing,
			"facing": intended_moves[sid].facing}
		_apply_move(sid, intended_moves[sid].hex, intended_moves[sid].facing, impulse, results, current_hexes, current_facings)
		_update_turn_tracking(sid, prev_facing, intended_moves[sid].facing, forward_since_turn, pivots_this_turn)


## Bow-entries into `target_hex`: a hex held by another ship means bear off or collide (6.D, 6.E);
## several bows entering together contest it (6.C.2-6.C.4).
func _resolve_bow_entries(
	ids: Array,
	target_hex: Vector2i,
	impulse: int,
	held: Dictionary,
	intended_moves: Dictionary,
	ship_map: Dictionary,
	results: Dictionary,
	current_hexes: Dictionary,
	current_facings: Dictionary,
	stopped: Dictionary,
	environment: EnvironmentState,
	forward_since_turn: Dictionary,
	pivots_this_turn: Dictionary
) -> void:
	var contesting_ids: Array = []
	for sid in ids:
		if not stopped[sid]:  # a collision earlier in this segment already stopped it
			contesting_ids.append(sid)
	if contesting_ids.is_empty():
		return

	var occupant_id: String = _find_holder(target_hex, held, contesting_ids)
	if occupant_id != "":
		for sid in contesting_ids:
			_resolve_collision_or_bearoff(
				sid, occupant_id, impulse, ship_map, results, current_hexes, stopped, environment, forward_since_turn, pivots_this_turn
			)
		return

	if contesting_ids.size() == 1:
		var sid: String = contesting_ids[0]
		var prev_facing: int = current_facings[sid]
		_apply_move(sid, intended_moves[sid].hex, intended_moves[sid].facing, impulse, results, current_hexes, current_facings)
		_update_turn_tracking(sid, prev_facing, intended_moves[sid].facing, forward_since_turn, pivots_this_turn)
		return

	_resolve_contested_hex(
		contesting_ids, target_hex, impulse, ship_map, results, current_hexes, current_facings, stopped, intended_moves, environment, forward_since_turn, pivots_this_turn
	)


## The one hex a step enters: an ahead step (new hex) its new bow hex; a turn (same hex, new facing)
## the new stern hex its stern swings into.
func _entered_hex(bow: Vector2i, facing: int, step_hex: Vector2i, step_facing: int) -> Vector2i:
	if _is_stern_entry(bow, facing, step_hex, step_facing):
		return HexGrid.stern_of(bow, step_facing)
	return step_hex


func _is_stern_entry(bow: Vector2i, facing: int, step_hex: Vector2i, step_facing: int) -> bool:
	return step_hex == bow and step_facing != facing


## True when the step at `impulse` is the last one plotted for every ship in `ids` (6.C.1b).
func _all_on_last_step(ids: Array, impulse: int, steps_by_ship: Dictionary) -> bool:
	for sid in ids:
		if impulse < steps_by_ship[sid].size() - 1:
			return false
	return true


## The ship holding `entered` when it is swinging its own stern onto this ship's bow this segment, so
## that both turns together would overlap the two ships completely (6.B.5); else "".
func _complete_overlap_partner(sid: String, entered: Vector2i, held: Dictionary, intended_moves: Dictionary, stopped: Dictionary) -> String:
	var holder: String = held.get(entered, "")
	if holder == "" or holder == sid or not intended_moves.has(holder) or stopped[holder]:
		return ""
	var bow: Vector2i = _seg_start_bows[holder]
	var facing: int = _seg_start_facings[holder]
	var move: Dictionary = intended_moves[holder]
	if _is_stern_entry(bow, facing, move.hex, move.facing) \
			and _entered_hex(bow, facing, move.hex, move.facing) == _seg_start_bows[sid]:
		return holder
	return ""


## A contested hex between swinging sterns (6.B.4c, 6.B.5, 6.C.5): roll with the 6.C.2 DRMs (ids sorted,
## so the result does not depend on ship order). Every loser's turn is cancelled and its movement ends
## (STERN_BLOCKED "lost stern contest to <winner>"); one that must still move ahead to meet its
## deceleration minimum is queued in `_contest_amendments` for a replay. Stub rule for 6.B.5 and
## 6.C.3: the winner always chooses to turn itself. Returns the winner.
func _stern_contest(
	contest_ids: Array,
	impulse: int,
	ship_map: Dictionary,
	results: Dictionary,
	current_hexes: Dictionary,
	current_facings: Dictionary,
	stopped: Dictionary
) -> String:
	var ids: Array = contest_ids.duplicate()
	ids.sort()
	var marks: Dictionary = {}
	for sid in ids:
		marks[sid] = (results[sid] as MovementTypes.ShipResolutionResult).events.size()
	var winner: String = _roll_contest(ids, impulse, ship_map, results)
	var losers: Array = []
	for sid in ids:
		if sid == winner:
			continue
		var pre_bow: Vector2i = current_hexes[sid]
		var pre_facing: int = current_facings[sid]
		_cancel_turn(sid, winner, impulse, results, current_hexes, current_facings, stopped,
			"lost stern contest to %s" % winner)
		losers.append({"ship_id": sid, "pre_bow": pre_bow, "pre_facing": pre_facing})
	Trace.trace_log("MovementResolver", "stern contest", {"ships": ids, "winner": winner, "segment": impulse})
	var events_kept := false  # the rolls go back into the final log once per contest
	for loser in losers:
		# The loser made a step on every segment before this one.
		if _deceleration_minimum(ship_map[loser.ship_id]) <= impulse:
			continue
		var events: Dictionary = {}
		if not events_kept:
			for sid in ids:
				events[sid] = (results[sid] as MovementTypes.ShipResolutionResult).events.slice(marks[sid])
			events_kept = true
		# TODO(6.C, 3+ sterns): a replay re-rolls the contest among the ships left, so a third ship's
		# result may differ from the first roll.
		_contest_amendments.append({
			"ship_id": loser.ship_id, "kind": "contest", "segment": impulse, "other_id": winner,
			"pre_bow": loser.pre_bow, "pre_facing": loser.pre_facing, "reason": "lost stern contest",
			"events": events,
		})
	return winner


## ============================================================================
## Temporary overlap (6.B.2-6.B.4)
## ============================================================================

## The two hexes of `sid` in the given bow and facing maps.
func _footprint(sid: String, bows: Dictionary, facings: Dictionary) -> Array[Vector2i]:
	return [bows[sid], HexGrid.stern_of(bows[sid], int(facings[sid]))]


## End of a segment: a stern that swung into a hex another ship now covers too is overlapping it
## (6.B.2). Logs OVERLAP and keeps the overlap pending until the end of the next segment. It is "already
## occupied" (6.B.4a) when the other ship held the hex at the start of the segment, "sterns together"
## when its stern swung into the hex too (one of the two had further MPs, so it was no contest), else a
## bow sailed into it ("bow precedence", 6.B.4b).
func _note_overlaps(impulse: int, results: Dictionary, current_hexes: Dictionary, current_facings: Dictionary) -> void:
	for sid in _swings:
		var swing: Dictionary = _swings[sid]
		var other_ids: Array = []
		var occupied_before := false
		var sterns_together := false
		for other_id in current_hexes:
			if other_id == sid or not swing.hex in _footprint(other_id, current_hexes, current_facings):
				continue
			other_ids.append(other_id)
			occupied_before = occupied_before or swing.hex in _footprint(other_id, _seg_start_bows, _seg_start_facings)
			sterns_together = sterns_together or (_swings.has(other_id) and _swings[other_id].hex == swing.hex)
			var ev = MovementTypes.ResolutionEvent.new(sid, impulse, MovementTypes.ResolutionEventType.OVERLAP)
			ev.from_hex = swing.pre_bow
			ev.to_hex = swing.pre_bow
			ev.from_facing = swing.pre_facing
			ev.facing = swing.facing
			ev.detail = "overlaps %s" % other_id
			(results[sid] as MovementTypes.ShipResolutionResult).events.append(ev)
		if other_ids.is_empty():
			continue
		_pending_overlaps[sid] = {
			"hex": swing.hex, "other_id": other_ids[0], "other_ids": other_ids, "segment": impulse,
			"pre_bow": swing.pre_bow, "pre_facing": swing.pre_facing, "facing": swing.facing,
			"reason": "already occupied" if occupied_before else ("sterns together" if sterns_together else "bow precedence"),
		}


## End of a segment: overlaps made on the previous segment that are still there (the two ships still
## share a hex, 6.B.4). Returns them as rollbacks ({ship_id} added to the pending record); the others
## were cleared and are dropped.
func _check_overlaps(impulse: int, current_hexes: Dictionary, current_facings: Dictionary) -> Array:
	var failed: Array = []
	for sid in _pending_overlaps.keys():
		var overlap: Dictionary = _pending_overlaps[sid]
		if overlap.segment != impulse - 1:
			continue
		_pending_overlaps.erase(sid)
		var mine: Array[Vector2i] = _footprint(sid, current_hexes, current_facings)
		# TODO(6.B, Task 11+): only the first ship still overlapped is named in the rollback.
		for other_id in overlap.other_ids:
			var still_overlapped := false
			for h in _footprint(other_id, current_hexes, current_facings):
				still_overlapped = still_overlapped or h in mine
			if still_overlapped:
				var rollback: Dictionary = overlap.duplicate()
				rollback["ship_id"] = sid
				rollback["other_id"] = other_id
				failed.append(rollback)
				break
	return failed


## The turning ship's plot after a rollback (6.B.4a/b): the steps before the overlap, then as many
## steps ahead on the old heading as its deceleration limit still requires. Those steps are resolved
## like any other, so they may meet a ship and bear off or collide.
func _amended_steps(ship_state: ShipState, steps: Array, rollback: Dictionary) -> Array:
	var kept: Array = steps.slice(0, rollback.segment)
	var minimum: int = _deceleration_minimum(ship_state)
	var bow: Vector2i = rollback.pre_bow
	while kept.size() < minimum:
		bow += HexGrid.DIRECTIONS[rollback.pre_facing]
		kept.append({"hex": {"q": bow.x, "r": bow.y}, "facing": rollback.pre_facing})
	return kept


## The fewest MPs the ship may use this turn, as the plotting validator computes it: last turn's speed
## less its deceleration, 0 when its movement allowance is 0.
func _deceleration_minimum(ship_state: ShipState) -> int:
	if game_state.ship_controller.get_movement_allowance(ship_state.ship_id) == 0:
		return 0
	var maneuverability: String = ship_state.ship.maneuverability if ship_state.ship else "b"
	return maxi(ship_state.speed - DataManager.get_speed_change("deceleration", maneuverability), 0)


## True when the ship executed every step before `segment` in the final pass, so it stood in the
## rollback's pre-turn pose at that segment.
func _reached_segment(result: MovementTypes.ShipResolutionResult, segment: int) -> bool:
	if result.stopped_at_impulse >= 0 and result.stopped_at_impulse < segment:
		return false
	var steps_before := 0
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.MOVE and ev.impulse < segment:
			steps_before += 1
	return steps_before == segment


## Tell a rolled-back turn in the final result: OVERLAP on the overlap segment (the stern swinging in)
## and OVERLAP_ROLLBACK on the next (swinging back to `pre_facing`). Neither is an executed step.
func _record_rollback(result: MovementTypes.ShipResolutionResult, rollback: Dictionary, steps_resolved: int) -> void:
	var overlap = MovementTypes.ResolutionEvent.new(result.ship_id, rollback.segment, MovementTypes.ResolutionEventType.OVERLAP)
	overlap.from_hex = rollback.pre_bow
	overlap.to_hex = rollback.pre_bow
	overlap.from_facing = rollback.pre_facing
	overlap.facing = rollback.facing
	overlap.detail = "overlaps %s" % rollback.other_id
	_insert_event(result, overlap)
	var back = MovementTypes.ResolutionEvent.new(result.ship_id, rollback.segment + 1, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	back.from_hex = rollback.pre_bow
	back.to_hex = rollback.pre_bow
	back.from_facing = rollback.facing
	back.facing = rollback.pre_facing
	back.success = false
	back.detail = rollback.reason
	_insert_event(result, back)
	if result.blocked_by == "":
		result.blocked_by = rollback.other_id
	if result.stopped_at_impulse < 0 and steps_resolved <= rollback.segment:
		result.stopped_at_impulse = rollback.segment


## Put a lost stern contest that amended the loser's plot back into the final log: the rolls of every
## ship in it and the loser's STERN_BLOCKED, told on the contest segment before that segment's steps.
## Skipped when the winner, too, no longer reaches that segment (the contest never happened).
func _record_contest(results: Dictionary, contest: Dictionary, steps_resolved: int) -> void:
	for sid in contest.events:
		if not _reached_segment(results[sid], contest.segment):
			return
	for sid in contest.events:
		var result: MovementTypes.ShipResolutionResult = results[sid]
		var at: int = 0
		while at < result.events.size() and (result.events[at].impulse < contest.segment \
				or (result.events[at].impulse == contest.segment \
					and result.events[at].event_type == MovementTypes.ResolutionEventType.TACKING_ROLL)):
			at += 1
		for ev in contest.events[sid]:
			result.events.insert(at, ev)
			at += 1
	var loser: MovementTypes.ShipResolutionResult = results[contest.ship_id]
	if loser.blocked_by == "":
		loser.blocked_by = contest.other_id
	if loser.stopped_at_impulse < 0 and steps_resolved <= contest.segment:
		loser.stopped_at_impulse = contest.segment


## Insert `ev` after the result's last event of the same or an earlier impulse.
func _insert_event(result: MovementTypes.ShipResolutionResult, ev: MovementTypes.ResolutionEvent) -> void:
	var at: int = result.events.size()
	while at > 0 and result.events[at - 1].impulse > ev.impulse:
		at -= 1
	result.events.insert(at, ev)


## The turn is cancelled: the ship keeps its bow hex and facing and stops for the rest of the turn.
## No collision and no bearing off.
func _cancel_turn(
	sid: String,
	blocker_id: String,
	impulse: int,
	results: Dictionary,
	current_hexes: Dictionary,
	current_facings: Dictionary,
	stopped: Dictionary,
	detail: String = ""
) -> void:
	var result: MovementTypes.ShipResolutionResult = results[sid]
	var ev = MovementTypes.ResolutionEvent.new(sid, impulse, MovementTypes.ResolutionEventType.STERN_BLOCKED)
	ev.from_hex = current_hexes[sid]
	ev.to_hex = current_hexes[sid]
	ev.facing = current_facings[sid]
	ev.from_facing = current_facings[sid]
	ev.success = false
	ev.detail = detail if detail != "" else "stern blocked by %s" % blocker_id
	result.events.append(ev)
	result.blocked_by = blocker_id
	result.stopped_at_impulse = impulse
	stopped[sid] = true


## ============================================================================
## Contested hex resolution
## ============================================================================

func _resolve_contested_hex(
	contesting_ids: Array,
	target_hex: Vector2i,
	impulse: int,
	ship_map: Dictionary,
	results: Dictionary,
	current_hexes: Dictionary,
	current_facings: Dictionary,
	stopped: Dictionary,
	intended_moves: Dictionary,
	environment: EnvironmentState,
	forward_since_turn: Dictionary,
	pivots_this_turn: Dictionary
) -> void:
	var winner_id: String = _roll_contest(contesting_ids, impulse, ship_map, results)

	var prev_facing: int = current_facings[winner_id]
	_apply_move(winner_id, target_hex, intended_moves[winner_id].facing, impulse, results, current_hexes, current_facings)
	_update_turn_tracking(winner_id, prev_facing, intended_moves[winner_id].facing, forward_since_turn, pivots_this_turn)

	for sid in contesting_ids:
		if sid == winner_id:
			continue
		_resolve_collision_or_bearoff(
			sid, winner_id, impulse, ship_map, results, current_hexes, stopped, environment, forward_since_turn, pivots_this_turn
		)


func _roll_contest(
	contesting_ids: Array,
	impulse: int,
	ship_map: Dictionary,
	results: Dictionary
) -> String:
	var remaining: Array = contesting_ids.duplicate()

	while remaining.size() > 1:
		var rolls: Dictionary = {}
		for sid in remaining:
			var base_roll: int = rng.randi_range(1, 6)
			var drm: int = _calculate_contest_drm_relative(sid, remaining, ship_map)
			var adjusted: int = base_roll + drm
			rolls[sid] = {"base": base_roll, "drm": drm, "adjusted": adjusted}

			var ev = MovementTypes.ResolutionEvent.new(
				sid, impulse, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL
			)
			ev.from_hex = (results[sid] as MovementTypes.ShipResolutionResult).final_hex
			ev.roll = float(base_roll)
			ev.threshold = float(drm)
			ev.detail = "base=%d drm=%d adjusted=%d" % [base_roll, drm, adjusted]
			(results[sid] as MovementTypes.ShipResolutionResult).events.append(ev)

		var max_adjusted: int = -999
		for sid in remaining:
			if rolls[sid].adjusted > max_adjusted:
				max_adjusted = rolls[sid].adjusted

		var tied_at_max: Array = []
		for sid in remaining:
			if rolls[sid].adjusted == max_adjusted:
				tied_at_max.append(sid)

		if tied_at_max.size() == 1:
			for sid in remaining:
				var ev: MovementTypes.ResolutionEvent = (results[sid] as MovementTypes.ShipResolutionResult).events.back()
				ev.success = (sid == tied_at_max[0])
			return tied_at_max[0]

		for sid in remaining:
			var ev: MovementTypes.ResolutionEvent = (results[sid] as MovementTypes.ShipResolutionResult).events.back()
			ev.success = sid in tied_at_max

		remaining = tied_at_max

	return remaining[0]


func _calculate_contest_drm_relative(sid: String, all_ids: Array, ship_map: Dictionary) -> int:
	var ship_state: ShipState = ship_map[sid]
	var drm: int = 0

	var my_steps: int = _get_plotted_steps(ship_state).size()
	var my_class: int = ship_state.ship.ship_class if ship_state.ship else 3
	var my_cq_idx: int = _crew_quality_index(ship_state.crew_quality)

	var has_more_mp: bool = true
	var has_fewer_mp: bool = true
	for other_id in all_ids:
		if other_id == sid:
			continue
		var other: ShipState = ship_map[other_id]
		var other_steps: int = _get_plotted_steps(other).size()
		if other_steps >= my_steps:
			has_more_mp = false
		if other_steps <= my_steps:
			has_fewer_mp = false

		var other_cq_idx: int = _crew_quality_index(other.crew_quality)
		var cq_diff: int = other_cq_idx - my_cq_idx
		if cq_diff > 0:
			drm += cq_diff

		var other_class: int = other.ship.ship_class if other.ship else 3
		# +1 per class larger (6.C.2c); class 1 is the largest, so a lower number is the bigger ship
		var class_diff: int = other_class - my_class
		if class_diff > 0:
			drm += class_diff

	if has_more_mp and not has_fewer_mp:
		drm += 1

	return drm


func _crew_quality_index(quality: String) -> int:
	match quality.to_upper():
		"A": return 0
		"B": return 1
		"C": return 2
		"D": return 3
		"E": return 4
		"F": return 5
		"G": return 6
	return 3


## ============================================================================
## Bearing off & collision
## ============================================================================

func _resolve_collision_or_bearoff(
	loser_id: String,
	blocker_id: String,
	impulse: int,
	ship_map: Dictionary,
	results: Dictionary,
	current_hexes: Dictionary,
	stopped: Dictionary,
	_environment: EnvironmentState,
	forward_since_turn: Dictionary,
	_pivots_this_turn: Dictionary
) -> void:
	var loser: ShipState = ship_map[loser_id]
	var loser_result: MovementTypes.ShipResolutionResult = results[loser_id]
	var maneuverability: String = loser.ship.maneuverability if loser.ship else "b"
	loser_result.blocked_by = blocker_id

	if not _is_bearing_off_pivot_legal(loser, forward_since_turn.get(loser_id, 0)):
		var deny_ev = MovementTypes.ResolutionEvent.new(
			loser_id, impulse, MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED
		)
		deny_ev.from_hex = current_hexes[loser_id]
		deny_ev.to_hex = current_hexes[loser_id]
		deny_ev.facing = loser_result.final_facing
		deny_ev.success = false
		var min_required: int = _get_min_forward_for_pivot(loser)
		deny_ev.detail = "pivot not legal: forward_hexes=%d min_required=%d speed=%d maneuverability=%s" % [
			forward_since_turn.get(loser_id, 0), min_required, loser.speed, maneuverability
		]
		loser_result.events.append(deny_ev)
		_apply_collision(loser_id, blocker_id, impulse, ship_map, results, current_hexes, stopped)
		return

	# Bearing Off table (6.D.2): d10 (0-9) + DRMs <= the chart number succeeds; NA never does.
	var crew_quality: String = loser.crew_quality
	var number: int = DataManager.get_bearing_off_number(crew_quality, maneuverability)
	var drm: int = _bearing_off_drm(loser)
	var d10: int = rng.randi_range(0, 9)
	var success: bool = number >= 0 and d10 + drm <= number
	var roll_value: float = float(d10)
	var threshold: float = float(number)

	var ev = MovementTypes.ResolutionEvent.new(
		loser_id, impulse, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL
	)
	ev.from_hex = current_hexes[loser_id]
	ev.to_hex = current_hexes[loser_id]
	ev.facing = loser_result.final_facing
	ev.roll = roll_value
	ev.threshold = threshold
	ev.success = success
	ev.detail = "crew=%s maneuver=%s d10=%d drm=%+d needed<=%d" % [crew_quality, maneuverability, d10, drm, number]
	loser_result.events.append(ev)

	if success:
		var stop_ev = MovementTypes.ResolutionEvent.new(
			loser_id, impulse, MovementTypes.ResolutionEventType.STOPPED
		)
		stop_ev.from_hex = current_hexes[loser_id]
		stop_ev.to_hex = current_hexes[loser_id]
		stop_ev.facing = loser_result.final_facing
		stop_ev.success = true
		stop_ev.detail = "bore off successfully, movement ends"
		loser_result.events.append(stop_ev)

		loser_result.stopped_at_impulse = impulse
		stopped[loser_id] = true
		return

	_apply_collision(loser_id, blocker_id, impulse, ship_map, results, current_hexes, stopped)


func _update_turn_tracking(
	sid: String,
	prev_facing: int,
	new_facing: int,
	forward_since_turn: Dictionary,
	pivots_this_turn: Dictionary
) -> void:
	if prev_facing == new_facing:
		forward_since_turn[sid] = forward_since_turn.get(sid, 0) + 1
	else:
		pivots_this_turn[sid] = pivots_this_turn.get(sid, 0) + 1
		forward_since_turn[sid] = 0


func _is_bearing_off_pivot_legal(ship_state: ShipState, forward_hexes: int) -> bool:
	var min_required: int = _get_min_forward_for_pivot(ship_state)
	if min_required < 0:
		return false
	return forward_hexes >= min_required


func _get_min_forward_for_pivot(ship_state: ShipState) -> int:
	var maneuverability: String = ship_state.ship.maneuverability if ship_state.ship else "b"
	var ship_speed: int = ship_state.speed
	if ship_speed <= 0:
		return -1
	return DataManager.get_min_heading_change_movement_required(
		"same_direction", ship_speed, maneuverability
	)


func _apply_collision(
	ship_a_id: String,
	ship_b_id: String,
	impulse: int,
	ship_map: Dictionary,
	results: Dictionary,
	current_hexes: Dictionary,
	stopped: Dictionary
) -> void:
	var result_a: MovementTypes.ShipResolutionResult = results[ship_a_id]
	var result_b: MovementTypes.ShipResolutionResult = results[ship_b_id]
	var state_a: ShipState = ship_map[ship_a_id]

	var rigging_loss: int = _collision_rigging_loss(state_a)

	var col_ev_a = MovementTypes.ResolutionEvent.new(
		ship_a_id, impulse, MovementTypes.ResolutionEventType.COLLISION
	)
	col_ev_a.from_hex = current_hexes[ship_a_id]
	col_ev_a.to_hex = current_hexes[ship_a_id]
	col_ev_a.facing = result_a.final_facing
	col_ev_a.detail = "collided with %s, rigging_loss=%d" % [ship_b_id, rigging_loss]
	result_a.events.append(col_ev_a)

	var col_ev_b = MovementTypes.ResolutionEvent.new(
		ship_b_id, impulse, MovementTypes.ResolutionEventType.COLLISION
	)
	col_ev_b.from_hex = current_hexes[ship_b_id]
	col_ev_b.to_hex = current_hexes[ship_b_id]
	col_ev_b.facing = result_b.final_facing
	col_ev_b.detail = "hit by %s" % ship_a_id
	result_b.events.append(col_ev_b)

	result_a.collided_with = ship_b_id
	result_b.collided_with = ship_a_id
	result_a.rigging_damage = rigging_loss
	result_a.stopped_at_impulse = impulse
	result_b.stopped_at_impulse = impulse
	stopped[ship_a_id] = true
	stopped[ship_b_id] = true

	if rigging_loss > 0:
		var rig_ev = MovementTypes.ResolutionEvent.new(
			ship_a_id, impulse, MovementTypes.ResolutionEventType.COLLISION_RIGGING_LOSS
		)
		rig_ev.from_hex = current_hexes[ship_a_id]
		rig_ev.detail = "rigging_loss=%d from sail_state=%s" % [rigging_loss, state_a.sail_state]
		result_a.events.append(rig_ev)

	# Only a free, unfouled pair can foul (as in DriftResolver._try_foul): a ship already fouled
	# with a third ship, before or earlier in this resolution, keeps its partner and no roll is made.
	var state_b: ShipState = ship_map[ship_b_id]
	var either_fouled: bool = state_a.fouled_with != "" or state_b.fouled_with != "" \
			or result_a.fouled_with != "" or result_b.fouled_with != ""
	var fouled: bool = not either_fouled and roll_fouling(state_a, state_b)
	if fouled:
		result_a.fouled_with = ship_b_id
		result_b.fouled_with = ship_a_id

		var foul_ev_a = MovementTypes.ResolutionEvent.new(
			ship_a_id, impulse, MovementTypes.ResolutionEventType.FOULING
		)
		foul_ev_a.from_hex = current_hexes[ship_a_id]
		foul_ev_a.detail = "fouled with %s" % ship_b_id
		result_a.events.append(foul_ev_a)

		var foul_ev_b = MovementTypes.ResolutionEvent.new(
			ship_b_id, impulse, MovementTypes.ResolutionEventType.FOULING
		)
		foul_ev_b.from_hex = current_hexes[ship_b_id]
		foul_ev_b.detail = "fouled with %s" % ship_a_id
		result_b.events.append(foul_ev_b)


func _collision_rigging_loss(ship_state: ShipState) -> int:
	match ship_state.sail_state.to_upper():
		"FS": return 2
		"MS": return 4
		"PS": return 6
	return 0


## Fouling roll after a collision or a blocked drift (Close Action 1997 Collision Resolution
## chart). True when the two ships foul: d10 (0-9) + modifiers >= 6, where each ship at MS adds 1
## and each ship at PS adds 2. A dismasted ship never fouls (no die drawn).
## Collision (drifting == false): the die is rng.randi_range(0, 9) from the resolver's own RNG,
## keeping movement resolution self-contained and deterministic.
## Drifting: the die comes from game_state.dice and the drifting ship takes a further -1.
func roll_fouling(ship_a: ShipState, ship_b: ShipState, drifting: bool = false) -> bool:
	if _is_dismasted(ship_a) or _is_dismasted(ship_b):
		return false
	var modifier: int = _fouling_sail_modifier(ship_a) + _fouling_sail_modifier(ship_b)
	if drifting:
		return game_state.dice.d10() + modifier - 1 >= 6
	return rng.randi_range(0, 9) + modifier >= 6


func _fouling_sail_modifier(ship_state: ShipState) -> int:
	match ship_state.sail_state.to_upper():
		"MS": return 1
		"PS": return 2
	return 0


func _is_dismasted(ship_state: ShipState) -> bool:
	for hp in ship_state.rigging_current_hp:
		if hp > 0:
			return false
	return true


## ============================================================================
## Move application and occupancy helpers
## ============================================================================

func _apply_move(
	sid: String,
	target_hex: Vector2i,
	facing: int,
	impulse: int,
	results: Dictionary,
	current_hexes: Dictionary,
	current_facings: Dictionary
) -> void:
	var result: MovementTypes.ShipResolutionResult = results[sid]

	var ev = MovementTypes.ResolutionEvent.new(
		sid, impulse, MovementTypes.ResolutionEventType.MOVE
	)
	ev.from_hex = current_hexes[sid]
	ev.to_hex = target_hex
	ev.facing = facing
	ev.from_facing = current_facings[sid]
	ev.success = true
	result.events.append(ev)

	current_hexes[sid] = target_hex
	current_facings[sid] = facing
	result.final_hex = target_hex
	result.final_facing = facing


## The ship holding `target_hex` this segment (see `held` in _resolve_impulse), other than the
## ships entering it. "" when nobody holds it.
func _find_holder(target_hex: Vector2i, held: Dictionary, moving_ids: Array) -> String:
	var holder: String = held.get(target_hex, "")
	if holder == "" or holder in moving_ids:
		return ""
	return holder


## ============================================================================
## Tacking and in-irons (per-ship, unchanged from S06)
## ============================================================================

## A ship in irons that plotted no turn stays in irons (5.D.7). Getting out takes a plotted turn,
## which is resolved by the Tacking roll with the in-irons DRM (5.D.6).
func _remain_in_irons(ship_state: ShipState, result: MovementTypes.ShipResolutionResult, detail: String) -> void:
	result.immobilized = true
	var imm_ev = MovementTypes.ResolutionEvent.new(
		ship_state.ship_id, 0, MovementTypes.ResolutionEventType.IMMOBILIZED
	)
	imm_ev.from_hex = ship_state.hex_position
	imm_ev.to_hex = ship_state.hex_position
	imm_ev.facing = ship_state.facing
	imm_ev.detail = detail
	result.events.append(imm_ev)


## The tacking roll of a turn an amended plot removed (see _tacks_dropped): drawn again from the same
## die, so it passes as it did in the pass that found the overlap, and logged. A ship in irons whose
## turn was rolled back stays in irons.
func _redraw_dropped_tack(ship_state: ShipState, environment: EnvironmentState, result: MovementTypes.ShipResolutionResult) -> void:
	_roll_tacking(ship_state, environment, result, 0)
	if _is_in_irons(ship_state, environment):
		_remain_in_irons(ship_state, result, "in irons, turn rolled back")


## Tacking table (5.D.2): d10 (0-9) + DRMs <= the chart number succeeds; a natural 0 always succeeds.
func _roll_tacking(
	ship_state: ShipState,
	environment: EnvironmentState,
	result: MovementTypes.ShipResolutionResult,
	impulse: int
) -> bool:
	var drm: int = _calculate_tacking_drm(ship_state)
	var number: int = _tacking_number(ship_state, environment.wind_speed)

	var d10: int = rng.randi_range(0, 9)
	var success: bool = _tack_succeeds(d10, drm, number)

	var ev = MovementTypes.ResolutionEvent.new(
		ship_state.ship_id, impulse, MovementTypes.ResolutionEventType.TACKING_ROLL
	)
	ev.from_hex = ship_state.hex_position
	ev.to_hex = ship_state.hex_position
	ev.facing = ship_state.facing
	ev.roll = float(d10)
	ev.threshold = float(number)
	ev.success = success
	ev.detail = "d10=%d drm=%+d needed<=%d" % [d10, drm, number]
	result.events.append(ev)

	if not success:
		var imm_ev = MovementTypes.ResolutionEvent.new(
			ship_state.ship_id, impulse, MovementTypes.ResolutionEventType.IMMOBILIZED
		)
		imm_ev.from_hex = ship_state.hex_position
		imm_ev.to_hex = ship_state.hex_position
		imm_ev.facing = ship_state.facing
		imm_ev.detail = "tacking failed"
		result.events.append(imm_ev)

	return success


## Chance (0.0-1.0) that a turn at MA=0 by this ship succeeds now, with the chart DRMs. Pure query,
## used by the planning screen.
func tacking_chance(ship_state: ShipState) -> float:
	var wind_speed: int = game_state.environment.wind_speed if game_state and game_state.environment else 0
	var number: int = _tacking_number(ship_state, wind_speed)
	var drm: int = _calculate_tacking_drm(ship_state)
	var wins: int = 0
	for d10 in range(10):
		if _tack_succeeds(d10, drm, number):
			wins += 1
	return wins / 10.0


func _tacking_number(ship_state: ShipState, wind_speed: int) -> int:
	var maneuverability: String = ship_state.ship.maneuverability if ship_state.ship else "b"
	return DataManager.get_tacking_number(maneuverability, wind_speed)


## d10 (0-9) + DRMs <= the chart number succeeds; a natural 0 always does. No number (calm): never.
func _tack_succeeds(d10: int, drm: int, number: int) -> bool:
	return number >= 0 and (d10 == 0 or d10 + drm <= number)


## Tacking DRMs from the chart (5.D.2, 5.D.6). Leeward has no crew-task plotting, so every ship
## counts as having its crew sections plotted to "T" (no +2s). Reversing tack and rudder damage do
## not exist yet.
func _calculate_tacking_drm(ship_state: ShipState) -> int:
	var drm: int = DataManager.combat_tables.skill_modifier(ship_state.crew_quality)

	if ship_state.ship:
		var rigging_max = ship_state.ship.rigging_hp
		for i in range(4):
			var max_hp: int = rigging_max[i] if i < rigging_max.size() else 0
			var cur_hp: int = ship_state.rigging_current_hp[i] if i < ship_state.rigging_current_hp.size() else 0
			if max_hp > 0 and cur_hp <= 0:
				drm += 2  # each rigging section lost

	var wind_facing: String = _get_ship_wind_facing(ship_state)
	if wind_facing != "L":
		drm -= 2  # ship not at WF=L (errata 5.D.2b)
	elif ship_state.speed == 0:
		drm += 1  # in irons (5.D.6)

	if ship_state.towing:
		drm += 1

	return drm


## Bearing Off DRMs (6.D.2): MPs plotted this g-t 4-6 = +1, 7+ = +2. Rudder damage and poor
## maneuvering need critical hits, which do not exist yet.
# TODO(6.B): reads the original plot size; after an overlap rollback it should count the amended plot.
func _bearing_off_drm(ship_state: ShipState) -> int:
	var mps: int = _get_plotted_steps(ship_state).size()
	if mps >= 7:
		return 2
	if mps >= 4:
		return 1
	return 0


## ============================================================================
## Utility
## ============================================================================

func _is_in_irons(ship_state: ShipState, _environment: EnvironmentState) -> bool:
	var wind_facing: String = _get_ship_wind_facing(ship_state)
	return ship_state.speed == 0 and wind_facing == "L"


func _get_ship_wind_facing(ship_state: ShipState) -> String:
	var wind_dir: int = 0
	if game_state and game_state.environment:
		wind_dir = game_state.environment.wind_direction
	return hex_grid.get_wind_facing(ship_state.facing, wind_dir)


func _get_plotted_steps(ship_state: ShipState) -> Array:
	## Fouled and struck ships cannot move: any plot is ignored (defence behind the plotting check).
	if ship_state.fouled_with != "" or ship_state.is_struck():
		return []
	return ship_state.plotted_actions.get("movement", [])


## Impulse of a turn plotted at MA=0, which must pass a Tacking roll (5.D.1): tacking from WF=L,
## turning out of irons, or any other turn by a ship whose MA is 0. Such a turn is the ship's first
## (and only) step. -1 when the plot needs no roll.
func _find_tacking_impulse(ship_state: ShipState, steps: Array) -> int:
	if steps.is_empty():
		return -1
	if int(steps[0].get("facing", ship_state.facing)) == ship_state.facing:
		return -1
	if game_state.ship_controller.get_movement_allowance(ship_state.ship_id) != 0:
		return -1
	return 0


## ============================================================================
## Apply results to state
## ============================================================================

@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func apply_results(log: MovementTypes.ResolutionLog, ships: Array[ShipState]) -> void:
	var sc = game_state.ship_controller if game_state else null
	if game_state and game_state.get("turn_log") != null:
		log_outcomes(log, ships, game_state.turn_log)  # before the plots are cleared
	for ship_state in ships:
		var result = log.get_result(ship_state.ship_id)
		if result == null:
			continue
		var sid = ship_state.ship_id
		if sc:
			# 5.E.2: speed is the MPs used (turns included) once the ship has moved ahead; a ship that
			# only turns, or does not move, is stopped.
			var moved_ahead: bool = _count_hexes_moved(result) > 0
			sc.set_moved_this_turn(sid, moved_ahead)
			sc.set_ship_position(sid, result.final_hex)
			sc.set_ship_facing(sid, result.final_facing)
			if result.immobilized:
				sc.set_immobilized(sid, true)
			sc.set_ship_speed(sid, _count_steps_executed(result) if moved_ahead else 0)
			if result.collided_with != "":
				sc.set_collision_this_turn(sid, true)
			if result.fouled_with != "":
				sc.set_fouled_with(sid, result.fouled_with)
			if result.rigging_damage > 0:
				_apply_rigging_damage(sid, result.rigging_damage, sc)
			sc.clear_plotted_actions(sid)
		else:
			push_error("MovementResolver: No ship_controller available")

func _apply_rigging_damage(ship_id: String, damage: int, sc: ShipStateController) -> void:
	## Collision rigging loss follows the damage rules (dismasting sets NS and notes a morale
	## check; the loss is logged). The direct fallback is only for resolvers built without one.
	var damage_controller = game_state.get("damage_controller")
	if damage_controller != null and game_state.get("turn_log") != null:
		damage_controller.apply_hits(ship_id, damage, 0, 0, "other",
				TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION)
		return
	var ship_state = game_state.get_ship(ship_id)
	if not ship_state:
		return
	var remaining: int = damage
	for i in range(ship_state.rigging_current_hp.size()):
		if remaining <= 0:
			break
		var can_take: int = ship_state.rigging_current_hp[i]
		var taken: int = min(can_take, remaining)
		sc.apply_rigging_damage(ship_id, i, taken)
		remaining -= taken


func _count_hexes_moved(result: MovementTypes.ShipResolutionResult) -> int:
	var count: int = 0
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.MOVE and ev.from_hex != ev.to_hex:
			count += 1
	return count


## Every executed MOVE step, turns (which stay in their hex) included.
func _count_steps_executed(result: MovementTypes.ShipResolutionResult) -> int:
	var count: int = 0
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.MOVE:
			count += 1
	return count


## Name what happened to each ship in the turn log, in ship order: a failed tack or a ship left in
## irons, a collision (logged for the ship that ran into the other), movement cut short of the plot,
## and fouling (once per pair). Reads each ship's plot, so call it before the plots are cleared.
@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func log_outcomes(log: MovementTypes.ResolutionLog, ships: Array[ShipState], turn_log: PhaseEvents.PhaseLog) -> void:
	var phase := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
	var fouled_logged := {}
	for ship_state in ships:
		var sid := ship_state.ship_id
		var result: MovementTypes.ShipResolutionResult = log.get_result(sid)
		if result == null:
			continue
		if result.tacking_failed:
			turn_log.add(PhaseEvents.Type.IN_IRONS, phase, sid, {"cause": "tack"})
		elif result.immobilized:
			turn_log.add(PhaseEvents.Type.IN_IRONS, phase, sid, {"cause": "irons"})
		for ev in result.events:
			if ev.event_type == MovementTypes.ResolutionEventType.COLLISION and ev.detail.begins_with("collided with"):
				var at := _collision_hex(ev)
				turn_log.add(PhaseEvents.Type.COLLISION, phase, sid, {"hex": {"q": at.x, "r": at.y}},
					result.collided_with)
		var planned: int = _get_plotted_steps(ship_state).size()
		# TODO(6.B): a rollback whose deceleration steps bring the step count back to the plotted length
		# logs no STOPPED_SHORT, although the course changed.
		if not result.tacking_failed and planned > 0 and _count_steps_executed(result) < planned:
			var data := {"moved": _count_steps_executed(result), "planned": planned}
			var cause := stop_cause(result)
			if not cause.is_empty():
				data["cause"] = cause["cause"]
			turn_log.add(PhaseEvents.Type.STOPPED_SHORT, phase, sid, data, str(cause.get("other", "")))
		if result.fouled_with != "" and not fouled_logged.has(sid):
			turn_log.add(PhaseEvents.Type.FOULED, phase, sid, {"cause": "collision"}, result.fouled_with)
			fouled_logged[sid] = true
			fouled_logged[result.fouled_with] = true


## Why a ship's movement ended before its plot did, from its resolution result alone:
## {"cause": "collision", "other": id} when it collided (either ship), {"cause": "bore_off",
## "other": id} when it bore off to avoid the ship in its way, {"cause": "stern_contest", "other": id}
## when it lost a stern contest to that ship (6.C.5), {"cause": "stern_blocked", "other": id} when its
## turn was otherwise cancelled because its stern would swing into that ship, {"cause": "overlap",
## "other": id} when its stern swung into that ship and the turn was rolled back (6.B.4), {} when the
## result names no cause. A cancelled or rolled-back turn after which the ship made no step comes first,
## so a ship run into later is not said to have stopped for that.
static func stop_cause(result: MovementTypes.ShipResolutionResult) -> Dictionary:
	if _undone_turn_ended_movement(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK, 1):
		return {"cause": "overlap", "other": result.blocked_by}
	if _undone_turn_ended_movement(result, MovementTypes.ResolutionEventType.STERN_BLOCKED, 0):
		return _stern_blocked_cause(result)
	if result.collided_with != "":
		return {"cause": "collision", "other": result.collided_with}
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.STOPPED and ev.success:
			return {"cause": "bore_off", "other": result.blocked_by}
		if ev.event_type == MovementTypes.ResolutionEventType.STERN_BLOCKED:
			return _stern_blocked_cause(result)
		if ev.event_type == MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK:
			return {"cause": "overlap", "other": result.blocked_by}
	return {}


static func _stern_blocked_cause(result: MovementTypes.ShipResolutionResult) -> Dictionary:
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.STERN_BLOCKED and ev.detail.begins_with("lost stern contest"):
			return {"cause": "stern_contest", "other": result.blocked_by}
	return {"cause": "stern_blocked", "other": result.blocked_by}


## True when the ship's movement ended with an undone turn (an `event_type` event, logged `lag`
## segments after the turn): it made no step from the turn's segment on (no deceleration steps ahead),
## so anything that happened to it later (another ship running into it) is not why it stopped.
static func _undone_turn_ended_movement(result: MovementTypes.ShipResolutionResult, event_type: int, lag: int) -> bool:
	var turn_segment: int = -1
	for ev in result.events:
		if ev.event_type == event_type:
			turn_segment = ev.impulse - lag
	if turn_segment < 0:
		return false
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.MOVE and ev.impulse >= turn_segment:
			return false
	return true


## The hex this ship ran into: the one ahead of its bow (a collision only ever comes from an ahead
## step), which may be the other ship's bow or its stern.
func _collision_hex(ev: MovementTypes.ResolutionEvent) -> Vector2i:
	return ev.from_hex + HexGrid.DIRECTIONS[ev.facing]
