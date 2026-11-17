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
## A ship about to run into another may bear off (6.D): its owner's choice (port, starboard or hold
## course) comes in `bear_off_decisions`; a ship in `prompt_ids` with no decision stops the resolution
## there (the log comes back incomplete, see ResolutionLog.pending_bear_off), any other ship decides
## by StubAI.bear_off_choice. A ship that bears off turns, then moves ahead to its deceleration
## minimum: its plot is amended and the resolution run again, like an overlap rollback.

var game_state: Node = null
var hex_grid: HexGrid = null
var _explicit_rng: RandomNumberGenerator = null
var _plot_validator: MovementValidator = null  # the turning rules for bearing off (see _validator)
## ship_id -> true for poor-maneuvering ships whose turn at MA 0 failed its Poor Maneuvering roll
## this run (6.F.5): the turn fails even if the Tacking roll passes. Set by run().
var _steering_failed_tacks: Dictionary = {}


## One resolution pass (see run()): every ship's steps, pose and progress, and the overlap bookkeeping
## (6.B) carried from segment to segment. A new one for every pass.
class ResolutionPass:
	var ship_map: Dictionary = {}  # ship_id -> ShipState
	var environment: EnvironmentState = null
	var steps_by_ship: Dictionary = {}  # ship_id -> the steps resolved this pass (its plot, or the amended plot)
	var results: Dictionary = {}  # ship_id -> MovementTypes.ShipResolutionResult
	var current_hexes: Dictionary = {}  # ship_id -> bow hex
	var current_facings: Dictionary = {}  # ship_id -> facing
	var stopped: Dictionary = {}  # ship_id -> true once its movement has ended
	var forward_since_turn: Dictionary = {}  # ship_id -> steps ahead since its last turn
	var pivots_this_turn: Dictionary = {}  # ship_id -> turns made
	## ship_id -> {hex, other_id, other_ids, segment, pre_bow, pre_facing, facing, reason}: overlaps made on
	## `segment`, checked at the end of the next one.
	var pending_overlaps: Dictionary = {}
	## Stern contests lost this pass whose loser must still move ahead to meet its deceleration minimum:
	## {ship_id, kind: "contest", segment, other_id, pre_bow, pre_facing, reason, events: {ship_id: [ev]}}.
	## They amend the loser's plot like a rollback; `events` (the rolls and STERN_BLOCKED) are put back
	## into the final log, where the contest is no longer rolled.
	var contest_amendments: Array = []
	## ship_id -> true for ships whose MA-0 turn (and its tacking roll, 5.D.1) an amended plot removed.
	## The tacking die is still drawn on segment 0, so the rolls after it are the ones of the first pass,
	## and the roll stays in the log.
	var tacks_dropped: Dictionary = {}
	## Stern contests rolled this pass: {segment, winner, rolls: {ship_id: [CONTESTED_HEX_ROLL events]}}.
	## A contest whose winner's turn is then rolled back no longer happens in the replay; its rolls are
	## put back into the final log (see run()).
	var contests: Array = []
	## Key (see _segment_hex_key) -> segment: cycles to break by holding the old stern their first group
	## enters (input, from earlier passes).
	var cycle_breaks: Dictionary = {}
	## [{key, segment}] of the cycles that went wrong on a segment: the ship whose old stern the group let
	## go first entered kept its pose, with that bow on its stern.
	var failed_cycles: Array = []
	## Key (see _segment_hex_key) -> {winner, rolls: {ship_id: [CONTESTED_HEX_ROLL events]}}: stern
	## contests settled in an earlier pass whose loser's plot was amended (input). Replayed, such a
	## contest keeps its result among the ships still in it (see _stern_contest).
	var settled_contests: Dictionary = {}
	## ship_id -> {choice, segment}: the owners' answers to potential collisions (input, see run()).
	var bear_off_decisions: Dictionary = {}
	## Ships whose bear-off decision must come from their player (input).
	var prompt_ids: Array = []
	## ship_id -> the bear-off rollback (kind "bear_off") of a ship that bore off in an earlier pass
	## (input): it bears off once per g-t (6.D.5), so a later potential collision is automatic.
	var settled_bear_offs: Dictionary = {}
	## Bear-offs that succeeded this pass: rollbacks of kind "bear_off" that amend the ship's plot.
	var bear_off_amendments: Array = []
	## The first potential collision of a prompted ship with no decision yet; the pass stops at the
	## end of its segment.
	var decision_needed: MovementTypes.BearOffSituation = null


## One segment of a pass: the steps the ships make on it and the hexes held while they make them.
class Segment:
	var impulse: int = 0
	var intended_moves: Dictionary = {}  # ship_id -> {hex, facing}: the step each moving ship makes
	## Hexes held during the segment (see _resolve_impulse): hex -> ship_id.
	var held: Dictionary = {}
	var start_bows: Dictionary = {}  # ship_id -> bow hex at the start of the segment (every ship)
	var start_facings: Dictionary = {}  # ship_id -> facing at the start of the segment
	var swings: Dictionary = {}  # ship_id -> {hex, pre_bow, pre_facing, facing}: sterns swung this segment
	var moves: Dictionary = {}  # ship_id -> the MOVE event of its step this segment, once made
	## ship_id -> true for moving ships whose step is settled: their group has run, or a collision
	## stopped them first. A group entering a moving ship's hex waits for that ship (see _group_ready).
	var resolved: Dictionary = {}
	## The groups let go first to break a cycle this segment: [{key, hex, owners}], `owners` the moving
	## ships whose old stern `hex` is (the ships assumed to leave it).
	var speculations: Array = []

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

## `bear_off_decisions`: ship_id -> {choice, segment} (MovementTypes.BEAR_OFF_*), the owners' answers
## so far; `prompt_ids`: ships whose decision must come from their player. When such a ship meets a
## potential collision with no decision for that segment, the returned log is incomplete
## (`pending_bear_off`); run again with the answer added. Everything before that segment repeats
## exactly, dice included.
func run(ships: Array[ShipState], environment: EnvironmentState, bear_off_decisions: Dictionary = {},
		prompt_ids: Array = []) -> MovementTypes.ResolutionLog:
	@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
	var log = MovementTypes.ResolutionLog.new(game_state.current_turn if game_state else 0)

	# An overlap that is not cleared on the next segment amends the turning ship's plot (6.B.4: "change
	# all ship logs to reflect the actual moves"), and the whole resolution is run again with the amended
	# plots, from the same RNG state. Every roll made before the rolled-back segment is made again with
	# the same die; a tacking roll whose turn was amended away is still drawn in its place (see
	# ResolutionPass.tacks_dropped), so the dice after it stay where they were. Rolls from the
	# rolled-back segment on may differ, since the ships stand elsewhere. Every rollback removes a
	# plotted turn.
	# A cycle of ships each sailing into the next one's old stern is resolved on the assumption that
	# they all move; when one of them is stopped after all (and keeps its stern under the bow of the ship
	# behind), the pass is run again with that cycle broken (see _hold_for_owner). A broken cycle is never
	# let go first again, so it cannot fail twice; a rollback drops the breaks from its segment on (they
	# are found again if still needed).
	# Bound: at most N rollbacks (N = steps that can be resolved; every rollback removes a turn), and
	# between two rollbacks at most N breaks (at most one group let go first per step), so
	# (N + 1) * (N + 1) passes always suffice. In practice it takes a handful.
	var ship_map: Dictionary = {}
	var plotted: Dictionary = {}
	var step_bound: int = 0
	# Poor maneuvering (6.F.3-5) is rolled first, for each turn of each poor-maneuvering ship in ship
	# order, before the passes: a failed roll changes the plot itself (one hex ahead, then the turn, the
	# last MP dropped), so every pass and every rollback starts from that plot, and the replays from
	# rng_start never roll it again. A roll is logged only if the ship reaches that segment.
	var steering: Dictionary = {}  # ship_id -> _roll_poor_maneuvering result
	_steering_failed_tacks = {}
	for ship_state in ships:
		ship_map[ship_state.ship_id] = ship_state
		plotted[ship_state.ship_id] = _get_plotted_steps(ship_state)
		if ship_state.is_poor_maneuvering():
			var pm: Dictionary = _roll_poor_maneuvering(ship_state, plotted[ship_state.ship_id])
			steering[ship_state.ship_id] = pm
			plotted[ship_state.ship_id] = pm.steps
			if pm.tack_failed:
				_steering_failed_tacks[ship_state.ship_id] = true
		# An amended plot is never longer than the plot or the deceleration minimum.
		step_bound += maxi(plotted[ship_state.ship_id].size(), _deceleration_minimum(ship_state))
	var pass_limit: int = (step_bound + 1) * (step_bound + 1)
	var rng_start: int = rng.state
	var amended: Dictionary = {}  # ship_id -> steps actually resolved
	var rollbacks: Dictionary = {}  # ship_id -> the rollback or lost stern contest that amended its plot
	var undone_contests: Array = []  # contests whose winner's turn was rolled back (ResolutionPass.contests)
	var cycle_breaks: Dictionary = {}  # cycle key -> segment (ResolutionPass.cycle_breaks)
	var settled_contests: Dictionary = {}  # ResolutionPass.settled_contests
	var settled_bear_offs: Dictionary = {}  # ResolutionPass.settled_bear_offs
	var outcome: Dictionary = {}
	# All overlaps that fail at the same segment end are rolled back together (they are simultaneous,
	# 6.B.4); the pass then restarts.
	for attempt in range(pass_limit):
		rng.state = rng_start
		outcome = _resolve_pass(ships, ship_map, plotted, amended, cycle_breaks, settled_contests, environment,
			bear_off_decisions, prompt_ids, settled_bear_offs)
		if outcome.rollbacks.is_empty() and outcome.failed_cycles.is_empty():
			break
		if attempt == pass_limit - 1:
			push_error("MovementResolver: overlap rollbacks did not settle")
			break
		for cycle in outcome.failed_cycles:
			cycle_breaks[cycle.key] = cycle.segment
			Trace.trace_log("MovementResolver", "cycle broken", {"cycle": cycle.key})
		for rb in outcome.rollbacks:
			var sid: String = rb.ship_id
			# An amended plot changes the steps from rb.segment on, so a cycle broken there or later may no
			# longer need breaking: drop it; it is found again if it still goes wrong.
			for key in cycle_breaks.keys():
				if cycle_breaks[key] >= rb.segment:
					cycle_breaks.erase(key)
			amended[sid] = _amended_steps(ship_map[sid], amended.get(sid, plotted[sid]), rb)
			rollbacks[sid] = rb
			if rb.get("kind", "") == "contest":
				settled_contests[_segment_hex_key(rb.segment, rb.hex)] = {"winner": rb.other_id, "rolls": rb.rolls}
			if rb.get("kind", "") == "bear_off":
				settled_bear_offs[sid] = rb
			for contest in outcome.contests:
				if rb.get("kind", "") == "" and contest.winner == sid and contest.segment == rb.segment:
					undone_contests.append(contest)
			Trace.trace_log("MovementResolver", "plot amended", {"ship": sid, "segment": rb.segment,
				"other": rb.get("overlapping", [rb.other_id]), "reason": rb.reason, "steps": amended[sid].size()})

	var results: Dictionary = outcome.results
	log.max_impulses = outcome.max_impulses
	log.pending_bear_off = outcome.get("decision")
	for sid in rollbacks:
		# A rollback found in an earlier pass can go stale: a later rollback of another ship may stop
		# this one before it ever reaches the overlap segment. Its amended plot still stands, but the
		# swing it never made is not logged (or played back).
		if not _reached_segment(results[sid], rollbacks[sid].segment):
			continue
		if rollbacks[sid].get("kind", "") == "contest":
			_record_contest(results, rollbacks[sid], amended[sid].size())
			continue
		if rollbacks[sid].get("kind", "") == "bear_off":
			_record_bear_off(results, rollbacks[sid])
			continue
		_record_rollback(results[sid], rollbacks[sid], amended[sid].size())
		log.max_impulses = maxi(log.max_impulses, rollbacks[sid].segment + 2)
	for contest in undone_contests:
		_record_undone_contest(results, contest)
	for sid in steering:
		_record_steering(ship_map[sid], results[sid], steering[sid], amended.get(sid, plotted[sid]), amended.has(sid))
	for sid in results:
		log.add_result(results[sid])

	return log


## One resolution of every ship's steps (`amended` overrides a ship's plot; `cycle_breaks` and
## `settled_contests`, see ResolutionPass). Returns {"results", "max_impulses", "rollbacks", "contests",
## "failed_cycles"}; when an overlap fails its check the pass stops there and "rollbacks" lists the
## turns to undo; when a cycle went wrong it stops there and "failed_cycles" lists the cycles to break;
## "contests" lists the stern contests rolled (see ResolutionPass.contests).
func _resolve_pass(
	ships: Array[ShipState],
	ship_map: Dictionary,
	plotted: Dictionary,
	amended: Dictionary,
	cycle_breaks: Dictionary,
	settled_contests: Dictionary,
	environment: EnvironmentState,
	bear_off_decisions: Dictionary = {},
	prompt_ids: Array = [],
	settled_bear_offs: Dictionary = {}
) -> Dictionary:
	var p := ResolutionPass.new()
	p.ship_map = ship_map
	p.environment = environment
	p.cycle_breaks = cycle_breaks
	p.settled_contests = settled_contests
	p.bear_off_decisions = bear_off_decisions
	p.prompt_ids = prompt_ids
	p.settled_bear_offs = settled_bear_offs
	for sid in amended:
		if _find_tacking_impulse(ship_map[sid], plotted[sid]) == 0 \
				and _find_tacking_impulse(ship_map[sid], amended[sid]) != 0:
			p.tacks_dropped[sid] = true

	for ship_state in ships:
		var sid: String = ship_state.ship_id
		var result = MovementTypes.ShipResolutionResult.new(sid)
		result.final_hex = ship_state.hex_position
		result.final_facing = ship_state.facing
		p.results[sid] = result
		p.current_hexes[sid] = ship_state.hex_position
		p.current_facings[sid] = ship_state.facing
		p.stopped[sid] = false
		p.forward_since_turn[sid] = 0
		p.pivots_this_turn[sid] = 0

		var ship_steps: Array = amended.get(sid, plotted[sid])
		if ship_steps.is_empty():
			if _is_in_irons(ship_state, environment):
				if p.tacks_dropped.has(sid):
					result.immobilized = true  # told after its tacking roll, on segment 0
				else:
					_remain_in_irons(ship_state, result, "in irons, no turn plotted")
			p.stopped[sid] = true
		p.steps_by_ship[sid] = ship_steps

	var max_impulses: int = 0
	for sid in p.steps_by_ship:
		var count: int = p.steps_by_ship[sid].size()
		if count > max_impulses:
			max_impulses = count

	# One segment past the last step: an overlap made on the last step is checked when nobody moves.
	for impulse in range(max_impulses + 1):
		var seg: Segment = _resolve_impulse(p, impulse, ships)
		var failed: Array = _check_overlaps(p, impulse)
		# An overlap failing here was made on the previous segment, so it goes first: its rollback may
		# change whether this segment's contests happen at all. A cycle gone wrong comes next: breaking it
		# changes this segment's steps, and so its contests.
		if failed.is_empty() and not p.failed_cycles.is_empty():
			return {"results": p.results, "max_impulses": max_impulses, "rollbacks": [], "contests": p.contests,
				"failed_cycles": p.failed_cycles}
		if failed.is_empty():
			failed = p.contest_amendments + p.bear_off_amendments
		if not failed.is_empty():
			return {"results": p.results, "max_impulses": max_impulses, "rollbacks": failed, "contests": p.contests,
				"failed_cycles": []}
		if p.decision_needed != null:
			return {"results": p.results, "max_impulses": max_impulses, "rollbacks": [], "contests": p.contests,
				"failed_cycles": [], "decision": p.decision_needed}
		_note_overlaps(p, seg)

	return {"results": p.results, "max_impulses": max_impulses, "rollbacks": [], "contests": p.contests,
		"failed_cycles": []}


## ============================================================================
## Per-impulse resolution
## ============================================================================

## Resolve one segment: every ship still moving makes its step. Returns the segment, for the overlap
## bookkeeping at its end.
func _resolve_impulse(p: ResolutionPass, impulse: int, ships: Array[ShipState]) -> Segment:
	var seg := Segment.new()
	seg.impulse = impulse
	seg.start_bows = p.current_hexes.duplicate()
	seg.start_facings = p.current_facings.duplicate()

	for ship_state in ships:
		var sid = ship_state.ship_id
		if impulse == 0 and p.tacks_dropped.has(sid):
			_redraw_dropped_tack(ship_state, p.environment, p.results[sid])
		if p.stopped[sid]:
			continue

		var ship_steps: Array = p.steps_by_ship[sid]
		if impulse >= ship_steps.size():
			p.stopped[sid] = true
			continue

		var step: Dictionary = ship_steps[impulse]
		var step_hex = Vector2i(
			int(step.get("hex", {}).get("q", 0)),
			int(step.get("hex", {}).get("r", 0))
		)
		var step_facing: int = int(step.get("facing", ship_state.facing))

		var tacking_impulse: int = _find_tacking_impulse(ship_state, ship_steps)
		if tacking_impulse >= 0 and impulse == tacking_impulse:
			var result: MovementTypes.ShipResolutionResult = p.results[sid]
			var tack_success: bool = _roll_tacking(ship_state, p.environment, result, impulse)
			if tack_success and _steering_failed_tacks.has(sid):
				# 6.F.5: a poor-maneuvering ship at MA 0 turns only if both rolls succeed.
				tack_success = false
				var imm_ev = MovementTypes.ResolutionEvent.new(sid, impulse,
					MovementTypes.ResolutionEventType.IMMOBILIZED)
				imm_ev.from_hex = p.current_hexes[sid]
				imm_ev.to_hex = p.current_hexes[sid]
				imm_ev.facing = ship_state.facing
				imm_ev.detail = "poor maneuvering failed"
				result.events.append(imm_ev)
			if not tack_success:
				# The plotted turn is erased (5.D.1): the ship keeps its hex and heading.
				result.final_hex = p.current_hexes[sid]
				result.final_facing = ship_state.facing
				result.immobilized = true
				result.tacking_failed = true
				p.stopped[sid] = true
				continue

		seg.intended_moves[sid] = {"hex": step_hex, "facing": step_facing}

	if seg.intended_moves.is_empty():
		return seg

	# Hexes held during this segment: every hex of a ship that is not moving, and the bow hex of
	# every moving ship (an ahead step turns it into the stern, a turn pivots on it). A moving ship's
	# old stern hex is held too until its own step succeeds; a ship whose step fails keeps it.
	seg.held = Occupancy.from_positions(p.current_hexes, p.current_facings, seg.intended_moves.keys())
	# Hex -> ids of the moving ships whose bow (or old stern) it is at the start of the segment. Lists:
	# during an overlap two sterns (or a stern and a bow) share a hex, and a group entering it waits for
	# every one of them.
	var old_stern_owner: Dictionary = {}
	var start_bow_owner: Dictionary = {}
	for sid in seg.intended_moves:
		seg.held[p.current_hexes[sid]] = sid
		_add_owner(start_bow_owner, p.current_hexes[sid], sid)
		_add_owner(old_stern_owner, HexGrid.stern_of(p.current_hexes[sid], p.current_facings[sid]), sid)

	# Group the entered hexes, bow-entries (ahead) and stern-entries (turns) apart.
	var bow_targets: Dictionary = {}
	var stern_targets: Dictionary = {}
	for sid in seg.intended_moves:
		var move: Dictionary = seg.intended_moves[sid]
		var bow: Vector2i = p.current_hexes[sid]
		var facing: int = p.current_facings[sid]
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
	# depend on ship order either. Letting it go assumes the ship whose old stern it enters leaves it;
	# when that ship is stopped after all, the pass is replayed with the cycle broken (see run()).
	var pending: Array = []
	for entered in stern_targets:
		pending.append({"stern": true, "hex": entered, "ids": stern_targets[entered]})
	for entered in bow_targets:
		pending.append({"stern": false, "hex": entered, "ids": bow_targets[entered]})
	while not pending.is_empty():
		var pick: int = -1
		for i in range(pending.size()):
			if _group_ready(pending[i], start_bow_owner, old_stern_owner, seg.resolved):
				pick = i
				break
		if pick < 0:
			pick = _lowest_id_group(pending)
			var key: String = _segment_hex_key(impulse, pending[pick].hex)
			if p.cycle_breaks.has(key):
				_hold_for_owner(seg, pending[pick].hex, old_stern_owner)
			else:
				seg.speculations.append({"key": key, "hex": pending[pick].hex,
					"owners": old_stern_owner.get(pending[pick].hex, [])})
		var group: Dictionary = pending[pick]
		pending.remove_at(pick)
		if group.stern:
			_resolve_stern_entries(p, seg, group.ids, group.hex)
		else:
			_resolve_bow_entries(p, seg, group.ids, group.hex)
		for sid in group.ids:
			_settle(p, seg, sid)
	if not seg.speculations.is_empty():
		p.failed_cycles = _failed_speculations(p, seg)
	return seg


## The ship's step this segment is settled: a ship that did not move keeps its old stern hex.
func _settle(p: ResolutionPass, seg: Segment, sid: String) -> void:
	seg.resolved[sid] = true
	if _kept_pose(p, seg, sid):
		seg.held[HexGrid.stern_of(seg.start_bows[sid], seg.start_facings[sid])] = sid  # it keeps its stern


func _kept_pose(p: ResolutionPass, seg: Segment, sid: String) -> bool:
	return p.current_hexes[sid] == seg.start_bows[sid] and p.current_facings[sid] == seg.start_facings[sid]


## A broken cycle (see run()): the group entering `hex` goes first, but the moving ship whose old
## stern it is no longer counts as leaving it, so the group meets that ship there.
func _hold_for_owner(seg: Segment, hex: Vector2i, old_stern_owner: Dictionary) -> void:
	var owners: Array = old_stern_owner.get(hex, []).duplicate()
	if owners.is_empty() or seg.held.has(hex):
		return
	owners.sort()
	seg.held[hex] = owners[0]


## Old stern hex -> ship for every ship that kept its pose this segment with another ship's bow on its
## old stern, sailed in by an ahead step. Only a cycle can do that (the group let go first assumes the
## next ship leaves its stern, see _resolve_impulse).
func _bows_in_kept_sterns(p: ResolutionPass, seg: Segment) -> Dictionary:
	var found: Dictionary = {}
	for sid in seg.intended_moves:
		if not _kept_pose(p, seg, sid):
			continue
		var kept_stern: Vector2i = HexGrid.stern_of(seg.start_bows[sid], seg.start_facings[sid])
		for other_id in seg.moves:
			var ev: MovementTypes.ResolutionEvent = seg.moves[other_id]
			if other_id != sid and ev.from_hex != ev.to_hex and p.current_hexes[other_id] == kept_stern:
				found[kept_stern] = sid
	return found


## The cycles of this segment that went wrong ([{key, segment}], see ResolutionPass.failed_cycles): only
## those whose assumed-to-leave ship kept its stern under the bow let in, so a cycle that worked in the
## same segment is not broken in the replay. Ships further along a failed cycle meet the kept sterns in
## the replay without their own cycle being broken. Should a bow sit on a kept stern with no speculation
## to blame (not expected), every speculation of the segment is broken, so no overlap is ever kept.
func _failed_speculations(p: ResolutionPass, seg: Segment) -> Array:
	var intruded: Dictionary = _bows_in_kept_sterns(p, seg)
	if intruded.is_empty():
		return []
	var failed: Array = []
	for spec in seg.speculations:
		if intruded.has(spec.hex) and intruded[spec.hex] in spec.owners:
			failed.append({"key": spec.key, "segment": seg.impulse})
	if failed.is_empty():
		for spec in seg.speculations:
			failed.append({"key": spec.key, "segment": seg.impulse})
	return failed


## Key of a hex on a segment, for ResolutionPass.cycle_breaks and .settled_contests.
static func _segment_hex_key(impulse: int, hex: Vector2i) -> String:
	return "%d:%d,%d" % [impulse, hex.x, hex.y]


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
func _resolve_stern_entries(p: ResolutionPass, seg: Segment, ids: Array, entered: Vector2i) -> void:
	var active: Array = []
	for sid in ids:
		if not p.stopped[sid]:  # a collision earlier in this segment already stopped it
			active.append(sid)
	if active.size() > 1 and _all_on_last_step(active, seg.impulse, p.steps_by_ship):
		active = [_stern_contest(p, active, seg.impulse, entered)]
	for sid in active:
		var partner: String = _complete_overlap_partner(p, seg, sid, entered)
		if partner != "":
			var winner: String = _stern_contest(p, [sid, partner], seg.impulse, entered)
			if winner != sid:
				continue
		var move: Dictionary = seg.intended_moves[sid]
		var prev_facing: int = p.current_facings[sid]
		seg.swings[sid] = {"hex": entered, "pre_bow": p.current_hexes[sid], "pre_facing": prev_facing,
			"facing": move.facing}
		_apply_move(p, seg, sid, move.hex, move.facing)
		_update_turn_tracking(p, sid, prev_facing, move.facing)


## Bow-entries into `target_hex`: a hex held by another ship means bear off or collide (6.D, 6.E);
## several bows entering together contest it (6.C.2-6.C.4).
func _resolve_bow_entries(p: ResolutionPass, seg: Segment, ids: Array, target_hex: Vector2i) -> void:
	var contesting_ids: Array = []
	for sid in ids:
		if not p.stopped[sid]:  # a collision earlier in this segment already stopped it
			contesting_ids.append(sid)
	if contesting_ids.is_empty():
		return

	var occupant_id: String = _find_holder(target_hex, seg.held, contesting_ids)
	if occupant_id != "":
		for sid in contesting_ids:
			_resolve_collision_or_bearoff(p, seg, sid, occupant_id)
		return

	if contesting_ids.size() == 1:
		var sid: String = contesting_ids[0]
		var move: Dictionary = seg.intended_moves[sid]
		var prev_facing: int = p.current_facings[sid]
		_apply_move(p, seg, sid, move.hex, move.facing)
		_update_turn_tracking(p, sid, prev_facing, move.facing)
		return

	_resolve_contested_hex(p, seg, contesting_ids, target_hex)


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
func _complete_overlap_partner(p: ResolutionPass, seg: Segment, sid: String, entered: Vector2i) -> String:
	var holder: String = seg.held.get(entered, "")
	if holder == "" or holder == sid or not seg.intended_moves.has(holder) or p.stopped[holder]:
		return ""
	var bow: Vector2i = seg.start_bows[holder]
	var facing: int = seg.start_facings[holder]
	var move: Dictionary = seg.intended_moves[holder]
	if _is_stern_entry(bow, facing, move.hex, move.facing) \
			and _entered_hex(bow, facing, move.hex, move.facing) == seg.start_bows[sid]:
		return holder
	return ""


## A contested hex between swinging sterns (6.B.4c, 6.B.5, 6.C.5): roll with the 6.C.2 DRMs (ids sorted,
## so the result does not depend on ship order). Every loser's turn is cancelled and its movement ends
## (STERN_BLOCKED "lost stern contest to <winner>"); one that must still move ahead to meet its
## deceleration minimum is queued in `p.contest_amendments` for a replay. In that replay a contest
## among the ships left (3+ sterns into `hex`) is not rolled again: it keeps its first winner and rolls.
## Deliberate rule for 6.B.5 and 6.C.3: the winner always enters (turns itself); it never forces the loser
## in (user decision 2026-11-16, feature_diff.md §4). Returns the winner.
func _stern_contest(p: ResolutionPass, contest_ids: Array, impulse: int, hex: Vector2i) -> String:
	var ids: Array = contest_ids.duplicate()
	ids.sort()
	var marks: Dictionary = {}
	for sid in ids:
		marks[sid] = (p.results[sid] as MovementTypes.ShipResolutionResult).events.size()
	var settled: Dictionary = p.settled_contests.get(_segment_hex_key(impulse, hex), {})
	var winner: String = ""
	var rolls: Dictionary = {}
	if not settled.is_empty() and settled.winner in ids:
		winner = settled.winner
		for sid in ids:
			var kept: Array = settled.rolls.get(sid, [])
			(p.results[sid] as MovementTypes.ShipResolutionResult).events.append_array(kept)
			rolls[sid] = kept
	else:
		winner = _roll_contest(p, ids, impulse)
		for sid in ids:
			rolls[sid] = (p.results[sid] as MovementTypes.ShipResolutionResult).events.slice(marks[sid])
	p.contests.append({"segment": impulse, "winner": winner, "rolls": rolls})
	var losers: Array = []
	for sid in ids:
		if sid == winner:
			continue
		var pre_bow: Vector2i = p.current_hexes[sid]
		var pre_facing: int = p.current_facings[sid]
		_cancel_turn(p, sid, winner, impulse, "lost stern contest to %s" % winner)
		losers.append({"ship_id": sid, "pre_bow": pre_bow, "pre_facing": pre_facing})
	Trace.trace_log("MovementResolver", "stern contest", {"ships": ids, "winner": winner, "segment": impulse})
	var events_kept := false  # the rolls go back into the final log once per contest
	for loser in losers:
		# The loser made a step on every segment before this one.
		if _deceleration_minimum(p.ship_map[loser.ship_id], loser.pre_facing) <= impulse:
			continue
		var events: Dictionary = {}
		if not events_kept:
			for sid in ids:
				events[sid] = (p.results[sid] as MovementTypes.ShipResolutionResult).events.slice(marks[sid])
			events_kept = true
		p.contest_amendments.append({
			"ship_id": loser.ship_id, "kind": "contest", "segment": impulse, "other_id": winner,
			"pre_bow": loser.pre_bow, "pre_facing": loser.pre_facing, "reason": "lost stern contest",
			"events": events, "hex": hex, "rolls": rolls,
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
func _note_overlaps(p: ResolutionPass, seg: Segment) -> void:
	for sid in seg.swings:
		var swing: Dictionary = seg.swings[sid]
		var other_ids: Array = []
		var occupied_before := false
		var sterns_together := false
		for other_id in p.current_hexes:
			if other_id == sid or not swing.hex in _footprint(other_id, p.current_hexes, p.current_facings):
				continue
			other_ids.append(other_id)
			occupied_before = occupied_before or swing.hex in _footprint(other_id, seg.start_bows, seg.start_facings)
			sterns_together = sterns_together or (seg.swings.has(other_id) and seg.swings[other_id].hex == swing.hex)
			var ev = MovementTypes.ResolutionEvent.new(sid, seg.impulse, MovementTypes.ResolutionEventType.OVERLAP)
			ev.from_hex = swing.pre_bow
			ev.to_hex = swing.pre_bow
			ev.from_facing = swing.pre_facing
			ev.facing = swing.facing
			ev.detail = "overlaps %s" % other_id
			(p.results[sid] as MovementTypes.ShipResolutionResult).events.append(ev)
		if other_ids.is_empty():
			continue
		p.pending_overlaps[sid] = {
			"hex": swing.hex, "other_id": other_ids[0], "other_ids": other_ids, "segment": seg.impulse,
			"pre_bow": swing.pre_bow, "pre_facing": swing.pre_facing, "facing": swing.facing,
			"reason": "already occupied" if occupied_before else ("sterns together" if sterns_together else "bow precedence"),
		}


## End of a segment: overlaps made on the previous segment that are still there (the two ships still
## share a hex, 6.B.4). Returns them as rollbacks: the pending record with ship_id, other_id (the first
## ship still overlapped) and overlapping (all of them) added; the others were cleared and are dropped.
func _check_overlaps(p: ResolutionPass, impulse: int) -> Array:
	var failed: Array = []
	for sid in p.pending_overlaps.keys():
		var overlap: Dictionary = p.pending_overlaps[sid]
		if overlap.segment != impulse - 1:
			continue
		p.pending_overlaps.erase(sid)
		var mine: Array[Vector2i] = _footprint(sid, p.current_hexes, p.current_facings)
		var overlapping: Array = []
		for other_id in overlap.other_ids:
			for h in _footprint(other_id, p.current_hexes, p.current_facings):
				if h in mine:
					overlapping.append(other_id)
					break
		if not overlapping.is_empty():
			var rollback: Dictionary = overlap.duplicate()
			rollback["ship_id"] = sid
			rollback["other_id"] = overlapping[0]
			rollback["overlapping"] = overlapping  # every ship still overlapped
			failed.append(rollback)
	return failed


## The turning ship's plot after a rollback (6.B.4a/b): the steps before the overlap, then as many
## steps ahead on the old heading as its deceleration limit still requires. Those steps are resolved
## like any other, so they may meet a ship and bear off or collide.
func _amended_steps(ship_state: ShipState, steps: Array, rollback: Dictionary) -> Array:
	var kept: Array = steps.slice(0, rollback.segment)
	if rollback.get("kind", "") == "bear_off":
		# 6.D.4: the ship turns where it bore off, then moves ahead only as far as its deceleration
		# limit requires, on its new heading.
		var turned_bow: Vector2i = rollback.pre_bow
		kept.append({"hex": {"q": turned_bow.x, "r": turned_bow.y}, "facing": rollback.facing})
		var needed: int = _deceleration_minimum(ship_state, rollback.facing)
		while kept.size() < needed:
			turned_bow += HexGrid.DIRECTIONS[rollback.facing]
			kept.append({"hex": {"q": turned_bow.x, "r": turned_bow.y}, "facing": rollback.facing})
		return kept
	var minimum: int = _deceleration_minimum(ship_state, rollback.pre_facing)
	var bow: Vector2i = rollback.pre_bow
	while kept.size() < minimum:
		bow += HexGrid.DIRECTIONS[rollback.pre_facing]
		kept.append({"hex": {"q": bow.x, "r": bow.y}, "facing": rollback.pre_facing})
	return kept


## The fewest MPs the ship may use this turn, as the plotting validator computes it at a point of the
## plot where the ship heads `facing` (its start-of-turn facing when -1): last turn's speed less its
## deceleration, 0 when its movement allowance at that facing is 0.
func _deceleration_minimum(ship_state: ShipState, facing: int = -1) -> int:
	if game_state.ship_controller.get_movement_allowance(ship_state.ship_id, facing) == 0:
		return 0
	var decel: int = game_state.ship_controller.speed_change_limits(ship_state).decel
	return maxi(ship_state.speed - decel, 0)


## True when the ship executed every step before `segment` in the final pass, so it stood in the
## rollback's pre-turn pose at that segment. A ship stopped on `segment` itself still reached it: the
## rollback (or lost contest) is what took the turn out of its plot there, and whatever stopped it on
## that segment (its amended step ahead failing, or a ship running into it) is told after, so the log
## keeps the undone turn as the cause (see stop_cause).
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
	overlap.detail = "overlaps %s" % ", ".join(rollback.get("overlapping", [rollback.other_id]))
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
		if not _has_contest_roll(results[sid], contest.segment):  # a replayed contest logged them already
			_insert_at_segment_start(results[sid], contest.segment, contest.events[sid])
	var loser: MovementTypes.ShipResolutionResult = results[contest.ship_id]
	if loser.blocked_by == "":
		loser.blocked_by = contest.other_id
	if loser.stopped_at_impulse < 0 and steps_resolved <= contest.segment:
		loser.stopped_at_impulse = contest.segment


## Put a successful bear-off back into the final log: its roll, told on its segment before the turn
## the amended plot makes there. Skipped when the ship no longer reaches that segment.
func _record_bear_off(results: Dictionary, bear_off: Dictionary) -> void:
	var result: MovementTypes.ShipResolutionResult = results[bear_off.ship_id]
	if not _reached_segment(result, bear_off.segment):
		return
	# Each insert goes before the segment's other events, so the bear-off roll first, then the contest
	# rolls in front of it.
	_insert_at_segment_start(result, bear_off.segment, bear_off.events)
	for sid in bear_off.contest_rolls:
		if results.has(sid) and not _has_contest_roll(results[sid], bear_off.segment):
			_insert_at_segment_start(results[sid], bear_off.segment, bear_off.contest_rolls[sid])
	if result.blocked_by == "":
		result.blocked_by = bear_off.other_id


## Put back the rolls of a stern contest whose winner's turn was rolled back (6.B.4): in the final pass
## the contest no longer happens, but it was rolled. Skipped when the winner no longer reaches that
## segment, or when the final pass rolled the contest itself.
func _record_undone_contest(results: Dictionary, contest: Dictionary) -> void:
	if not _reached_segment(results[contest.winner], contest.segment):
		return
	for sid in contest.rolls:
		if _has_contest_roll(results[sid], contest.segment):
			return
	for sid in contest.rolls:
		_insert_at_segment_start(results[sid], contest.segment, contest.rolls[sid])


func _has_contest_roll(result: MovementTypes.ShipResolutionResult, segment: int) -> bool:
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL and ev.impulse == segment:
			return true
	return false


## Insert `events` at the start of `segment` in the result, after any tacking roll of that segment.
func _insert_at_segment_start(result: MovementTypes.ShipResolutionResult, segment: int, events: Array) -> void:
	var at: int = 0
	while at < result.events.size() and (result.events[at].impulse < segment \
			or (result.events[at].impulse == segment \
				and result.events[at].event_type == MovementTypes.ResolutionEventType.TACKING_ROLL)):
		at += 1
	for ev in events:
		result.events.insert(at, ev)
		at += 1


## Insert `ev` after the result's last event of the same or an earlier impulse.
func _insert_event(result: MovementTypes.ShipResolutionResult, ev: MovementTypes.ResolutionEvent) -> void:
	var at: int = result.events.size()
	while at > 0 and result.events[at - 1].impulse > ev.impulse:
		at -= 1
	result.events.insert(at, ev)


## The turn is cancelled: the ship keeps its bow hex and facing and stops for the rest of the turn.
## No collision and no bearing off.
func _cancel_turn(p: ResolutionPass, sid: String, blocker_id: String, impulse: int, detail: String = "") -> void:
	var result: MovementTypes.ShipResolutionResult = p.results[sid]
	var ev = MovementTypes.ResolutionEvent.new(sid, impulse, MovementTypes.ResolutionEventType.STERN_BLOCKED)
	ev.from_hex = p.current_hexes[sid]
	ev.to_hex = p.current_hexes[sid]
	ev.facing = p.current_facings[sid]
	ev.from_facing = p.current_facings[sid]
	ev.success = false
	ev.detail = detail if detail != "" else "stern blocked by %s" % blocker_id
	result.events.append(ev)
	result.blocked_by = blocker_id
	result.stopped_at_impulse = impulse
	p.stopped[sid] = true


## ============================================================================
## Contested hex resolution
## ============================================================================

## Deliberate: the winner always enters (6.C.3, user decision 2026-11-16); it never forces the loser in.
func _resolve_contested_hex(p: ResolutionPass, seg: Segment, contesting_ids: Array, target_hex: Vector2i) -> void:
	var winner_id: String = _roll_contest(p, contesting_ids, seg.impulse)

	var prev_facing: int = p.current_facings[winner_id]
	var facing: int = seg.intended_moves[winner_id].facing
	_apply_move(p, seg, winner_id, target_hex, facing)
	_update_turn_tracking(p, winner_id, prev_facing, facing)

	for sid in contesting_ids:
		if sid == winner_id:
			continue
		_resolve_collision_or_bearoff(p, seg, sid, winner_id)


func _roll_contest(p: ResolutionPass, contesting_ids: Array, impulse: int) -> String:
	var results: Dictionary = p.results
	var remaining: Array = contesting_ids.duplicate()

	while remaining.size() > 1:
		var rolls: Dictionary = {}
		for sid in remaining:
			var base_roll: int = rng.randi_range(1, 6)
			var drm: int = _calculate_contest_drm_relative(sid, remaining, p.ship_map, p.steps_by_ship)
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


## 6.C.2 DRMs of `sid` against the other ships in `all_ids`. MPs plotted are counted from
## `steps_by_ship` (the steps a pass resolves: the plot as amended after a rollback, 6.B.4), else from
## the ship's plot.
func _calculate_contest_drm_relative(sid: String, all_ids: Array, ship_map: Dictionary,
		steps_by_ship: Dictionary = {}) -> int:
	var ship_state: ShipState = ship_map[sid]
	var drm: int = 0

	var my_steps: int = _mps_plotted(ship_state, steps_by_ship)
	var my_class: int = ship_state.ship.ship_class if ship_state.ship else 3
	var my_cq_idx: int = _crew_quality_index(ship_state.crew_quality)

	var has_more_mp: bool = true
	var has_fewer_mp: bool = true
	for other_id in all_ids:
		if other_id == sid:
			continue
		var other: ShipState = ship_map[other_id]
		var other_steps: int = _mps_plotted(other, steps_by_ship)
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

## A potential collision (6.D.1): `loser_id` cannot enter the hex `blocker_id` holds. The owner may
## bear off if a turn is legal there (6.D.2): its choice comes from `bear_off_decisions`, from the
## player (a prompted ship with no decision stops the pass at the end of this segment) or from
## StubAI.bear_off_choice. Holding course collides (6.E.1). A successful roll queues a bear-off
## rollback: the plot is amended (turn, then ahead to the deceleration minimum) and the pass re-run.
func _resolve_collision_or_bearoff(p: ResolutionPass, seg: Segment, loser_id: String, blocker_id: String) -> void:
	var impulse: int = seg.impulse
	var loser: ShipState = p.ship_map[loser_id]
	var loser_result: MovementTypes.ShipResolutionResult = p.results[loser_id]
	loser_result.blocked_by = blocker_id

	var situation := bear_off_situation(p, loser_id, blocker_id, impulse)
	if p.settled_bear_offs.has(loser_id) or situation.eligible.is_empty():
		var deny_ev = MovementTypes.ResolutionEvent.new(
			loser_id, impulse, MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED
		)
		deny_ev.from_hex = p.current_hexes[loser_id]
		deny_ev.to_hex = p.current_hexes[loser_id]
		deny_ev.facing = loser_result.final_facing
		deny_ev.success = false
		deny_ev.detail = "already bore off this turn" if p.settled_bear_offs.has(loser_id) \
			else "no legal turn: speed=%d" % loser.speed
		loser_result.events.append(deny_ev)
		_apply_collision(p, seg, loser_id, blocker_id)
		return

	var choice: String = ""
	var decision: Dictionary = p.bear_off_decisions.get(loser_id, {})
	if int(decision.get("segment", -1)) == impulse and str(decision.get("choice", "")) in situation.choices():
		choice = str(decision.choice)
	elif loser_id in p.prompt_ids:
		# The player decides (6.D.3): the ship waits where it is; the pass ends with this segment.
		if p.decision_needed == null:
			p.decision_needed = situation
		loser_result.stopped_at_impulse = impulse
		p.stopped[loser_id] = true
		return
	else:
		choice = StubAI.bear_off_choice(situation, _footprint(blocker_id, p.current_hexes, p.current_facings))

	if choice == MovementTypes.BEAR_OFF_COLLIDE:
		var held_ev = MovementTypes.ResolutionEvent.new(
			loser_id, impulse, MovementTypes.ResolutionEventType.BEARING_OFF_DECLINED
		)
		held_ev.from_hex = p.current_hexes[loser_id]
		held_ev.to_hex = p.current_hexes[loser_id]
		held_ev.facing = loser_result.final_facing
		held_ev.detail = "held course into %s" % blocker_id
		loser_result.events.append(held_ev)
		_apply_collision(p, seg, loser_id, blocker_id)
		return

	# Bearing Off table (6.D.2): d10 (0-9) + DRMs <= the chart number succeeds; NA never does.
	var d10: int = rng.randi_range(0, 9)
	var success: bool = situation.number >= 0 and d10 + situation.drm <= situation.number
	var ev = MovementTypes.ResolutionEvent.new(
		loser_id, impulse, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL
	)
	ev.from_hex = p.current_hexes[loser_id]
	ev.to_hex = p.current_hexes[loser_id]
	ev.facing = loser_result.final_facing
	ev.roll = float(d10)
	ev.threshold = float(situation.number)
	ev.success = success
	ev.detail = "%s crew=%s maneuver=%s d10=%d drm=%+d needed<=%d" % [choice, loser.crew_quality,
		loser.ship.maneuverability if loser.ship else "b", d10, situation.drm, situation.number]
	loser_result.events.append(ev)

	if not success:
		_apply_collision(p, seg, loser_id, blocker_id)
		return

	# 6.D.4: turn, then meet the deceleration minimum. Amend the plot and run the pass again.
	var old_facing: int = p.current_facings[loser_id]
	var new_facing: int = (old_facing + 5) % 6 if choice == MovementTypes.BEAR_OFF_PORT else (old_facing + 1) % 6
	# A contested hex lost on this segment (6.D.1) no longer happens in the replay, where the ship turns
	# instead: its rolls are kept and put back into the final log with the bear-off roll.
	var contest_rolls: Dictionary = {}
	for sid in [loser_id, blocker_id]:
		var rolls: Array = []
		for other_ev in p.results[sid].events:
			if other_ev.event_type == MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL and other_ev.impulse == impulse:
				rolls.append(other_ev)
		if not rolls.is_empty():
			contest_rolls[sid] = rolls
	p.bear_off_amendments.append({"kind": "bear_off", "ship_id": loser_id, "segment": impulse,
		"pre_bow": p.current_hexes[loser_id], "pre_facing": old_facing, "facing": new_facing,
		"other_id": blocker_id, "reason": "bore off %s" % choice, "events": [ev], "contest_rolls": contest_rolls})
	loser_result.stopped_at_impulse = impulse
	p.stopped[loser_id] = true


## The potential collision as its owner sees it (6.D.2): which turns are legal at this point of the
## plot (the turning rules the plotting validator applies, on the steps made so far) and the odds.
func bear_off_situation(p: ResolutionPass, sid: String, blocker_id: String, impulse: int) -> MovementTypes.BearOffSituation:
	var ship_state: ShipState = p.ship_map[sid]
	var situation := MovementTypes.BearOffSituation.new()
	situation.ship_id = sid
	situation.blocker_id = blocker_id
	situation.segment = impulse
	situation.bow = p.current_hexes[sid]
	situation.facing = p.current_facings[sid]
	var path: Array[MovementTypes.PlotStep] = []
	var facing: int = ship_state.facing
	for step in p.steps_by_ship[sid].slice(0, impulse):
		var step_facing: int = int(step.get("facing", facing))
		var hex := Vector2i(int(step.get("hex", {}).get("q", 0)), int(step.get("hex", {}).get("r", 0)))
		var move_type := MovementTypes.MoveType.FORWARD
		if step_facing == (facing + 5) % 6:
			move_type = MovementTypes.MoveType.PORT
		elif step_facing != facing:
			move_type = MovementTypes.MoveType.STARBOARD
		path.append(MovementTypes.PlotStep.new(hex, step_facing, move_type))
		facing = step_facing
	if ship_state.speed > 0:  # a stopped ship cannot turn away (the turning chart has no speed 0 row)
		var moves = _validator().calculate_valid_moves(ship_state, situation.bow, situation.facing, path)
		if moves.valid_hexes.port != null:
			situation.eligible.append(MovementTypes.BEAR_OFF_PORT)
		if moves.valid_hexes.starboard != null:
			situation.eligible.append(MovementTypes.BEAR_OFF_STARBOARD)
	var maneuverability: String = ship_state.ship.maneuverability if ship_state.ship else "b"
	situation.number = DataManager.get_bearing_off_number(ship_state.crew_quality, maneuverability)
	situation.drm = _bearing_off_drm(ship_state, p.steps_by_ship[sid].size())
	situation.chance = 0.0 if situation.number < 0 else clampf((situation.number - situation.drm + 1) / 10.0, 0.0, 1.0)
	for other_id in p.steps_by_ship:
		if other_id == sid or p.stopped.get(other_id, false):
			continue
		var hexes: Array[Vector2i] = []
		for step in p.steps_by_ship[other_id].slice(impulse):
			hexes.append(Vector2i(int(step.get("hex", {}).get("q", 0)), int(step.get("hex", {}).get("r", 0))))
		if not hexes.is_empty():
			situation.other_plots[other_id] = hexes
	return situation


func _validator() -> MovementValidator:
	if _plot_validator == null:
		_plot_validator = MovementValidator.new(game_state)
	return _plot_validator


func _update_turn_tracking(p: ResolutionPass, sid: String, prev_facing: int, new_facing: int) -> void:
	if prev_facing == new_facing:
		p.forward_since_turn[sid] = p.forward_since_turn.get(sid, 0) + 1
	else:
		p.pivots_this_turn[sid] = p.pivots_this_turn.get(sid, 0) + 1
		p.forward_since_turn[sid] = 0


func _apply_collision(p: ResolutionPass, seg: Segment, ship_a_id: String, ship_b_id: String) -> void:
	var impulse: int = seg.impulse
	var result_a: MovementTypes.ShipResolutionResult = p.results[ship_a_id]
	var result_b: MovementTypes.ShipResolutionResult = p.results[ship_b_id]
	var state_a: ShipState = p.ship_map[ship_a_id]
	var state_b: ShipState = p.ship_map[ship_b_id]
	var current_hexes: Dictionary = p.current_hexes

	# 6.E.3: the ship that runs into the other (pointing at it) loses extra rigging; when the two
	# run into one another, both roll.
	var rigging_loss: int = _roll_collision_rigging_loss(state_a)
	var rigging_loss_b: int = _roll_collision_rigging_loss(state_b) if _runs_into(p, seg, ship_b_id, ship_a_id) else 0

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
	if rigging_loss_b > 0:
		col_ev_b.detail += ", rigging_loss=%d" % rigging_loss_b
	result_b.events.append(col_ev_b)

	result_a.collided_with = ship_b_id
	result_b.collided_with = ship_a_id
	result_a.rigging_damage = rigging_loss
	result_b.rigging_damage += rigging_loss_b
	result_a.stopped_at_impulse = impulse
	result_b.stopped_at_impulse = impulse
	p.stopped[ship_a_id] = true
	p.stopped[ship_b_id] = true
	# A moving ship hit before its own group has run never makes its step: it keeps its old stern from
	# now on, so no later group (not even one the cycle fallback lets go) enters that hex.
	if seg.intended_moves.has(ship_b_id) and not seg.resolved.has(ship_b_id):
		_settle(p, seg, ship_b_id)

	if rigging_loss > 0:
		var rig_ev = MovementTypes.ResolutionEvent.new(
			ship_a_id, impulse, MovementTypes.ResolutionEventType.COLLISION_RIGGING_LOSS
		)
		rig_ev.from_hex = current_hexes[ship_a_id]
		rig_ev.detail = "rigging_loss=%d from sail_state=%s" % [rigging_loss, state_a.sail_state]
		result_a.events.append(rig_ev)
	if rigging_loss_b > 0:
		var rig_ev_b = MovementTypes.ResolutionEvent.new(
			ship_b_id, impulse, MovementTypes.ResolutionEventType.COLLISION_RIGGING_LOSS
		)
		rig_ev_b.from_hex = current_hexes[ship_b_id]
		rig_ev_b.detail = "rigging_loss=%d from sail_state=%s" % [rigging_loss_b, state_b.sail_state]
		result_b.events.append(rig_ev_b)

	# Only a free, unfouled pair can foul (as in DriftResolver._try_foul): a ship already fouled
	# with a third ship, before or earlier in this resolution, keeps its partner and no roll is made.
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


## Extra rigging lost in a collision (6.E.3, Collision Resolution chart): d6-1 at FS, d6+1 at MS,
## 2d6 at PS, none under no sail. `d6_a` and `d6_b` are the dice; `d6_b` counts only at PS.
static func collision_rigging_loss(sail_state: String, d6_a: int, d6_b: int) -> int:
	match sail_state.to_upper():
		"FS": return d6_a - 1
		"MS": return d6_a + 1
		"PS": return d6_a + d6_b
	return 0


## Rolls the collision rigging loss with the resolver's own RNG (only the dice the sail state needs).
func _roll_collision_rigging_loss(ship_state: ShipState) -> int:
	if ship_state.is_destroyed():
		return 0  # a wreck takes no damage
	var sail: String = ship_state.sail_state.to_upper()
	if not sail in ["FS", "MS", "PS"]:
		return 0
	var d6_a: int = rng.randi_range(1, 6)
	var d6_b: int = rng.randi_range(1, 6) if sail == "PS" else 0
	return collision_rigging_loss(sail, d6_a, d6_b)


## True when `sid` was itself sailing ahead into `other_id` this segment: its unsettled step is a move
## ahead whose new bow is one of the other ship's hexes (the two ships run into one another, 6.E.3).
func _runs_into(p: ResolutionPass, seg: Segment, sid: String, other_id: String) -> bool:
	if not seg.intended_moves.has(sid) or seg.resolved.has(sid) or p.stopped.get(sid, false):
		return false
	var move: Dictionary = seg.intended_moves[sid]
	if int(move.facing) != p.current_facings[sid] or move.hex == p.current_hexes[sid]:
		return false  # a turn swings the stern; it does not point the bow at anyone
	var other_bow: Vector2i = p.current_hexes[other_id]
	return move.hex == other_bow or move.hex == HexGrid.stern_of(other_bow, p.current_facings[other_id])


## Fouling roll after a collision or a blocked drift (Close Action 1997 Collision Resolution
## chart). True when the two ships foul: d10 (0-9) + modifiers >= 6, where each ship at MS adds 1
## and each ship at PS adds 2. A dismasted ship never fouls (no die drawn).
## Collision (drifting == false): the die is rng.randi_range(0, 9) from the resolver's own RNG,
## keeping movement resolution self-contained and deterministic.
## Drifting: the die comes from game_state.dice and the drifting ship takes a further -1.
func roll_fouling(ship_a: ShipState, ship_b: ShipState, drifting: bool = false) -> bool:
	if ship_a.is_destroyed() or ship_b.is_destroyed():
		return false  # a wreck never fouls (no die drawn)
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

func _apply_move(p: ResolutionPass, seg: Segment, sid: String, target_hex: Vector2i, facing: int) -> void:
	var result: MovementTypes.ShipResolutionResult = p.results[sid]

	var ev = MovementTypes.ResolutionEvent.new(
		sid, seg.impulse, MovementTypes.ResolutionEventType.MOVE
	)
	ev.from_hex = p.current_hexes[sid]
	ev.to_hex = target_hex
	ev.facing = facing
	ev.from_facing = p.current_facings[sid]
	ev.success = true
	result.events.append(ev)
	seg.moves[sid] = ev

	p.current_hexes[sid] = target_hex
	p.current_facings[sid] = facing
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


## The tacking roll of a turn an amended plot removed (see ResolutionPass.tacks_dropped): drawn again from the same
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
## used by the planning screen. `sections` is the number of crew sections at the braces (5.D.2a);
## -1 reads the ship's live T task.
func tacking_chance(ship_state: ShipState, sections: int = -1) -> float:
	var wind_speed: int = game_state.environment.wind_speed if game_state and game_state.environment else 0
	var number: int = _tacking_number(ship_state, wind_speed)
	var drm: int = _calculate_tacking_drm(ship_state, sections)
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


## Tacking DRMs from the chart (5.D.2, 5.D.6). 5.D.2a: the chart assumes 3 crew sections plotted
## to "T"; +2 for each one short, up to +6 (the chart's "up to +8" is a misprint). `sections` is the
## count at the braces; -1 reads the ship's live T task (ShipState.tack_sections()). Reversing tack
## does not exist yet.
func _calculate_tacking_drm(ship_state: ShipState, sections: int = -1) -> int:
	var drm: int = DataManager.combat_tables.skill_modifier(ship_state.crew_quality)
	drm += tack_crew_drm(ship_state.tack_sections() if sections < 0 else sections)

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

	if ship_state.rudder_destroyed:
		drm += 3  # Rudder Destroyed (hull #2)

	return drm


## Bearing Off DRMs (6.D.2): MPs plotted this g-t 4-6 = +1, 7+ = +2. `mps` is the steps the pass
## resolves (the plot as amended after a rollback, 6.B.4: "change all ship logs to reflect the actual
## moves"); -1 counts the ship's plot. Rudder Destroyed or Jammed +3, Poor Maneuvering +1 (so a
## destroyed rudder is +4, spec Q9).
func _bearing_off_drm(ship_state: ShipState, mps: int = -1) -> int:
	if mps < 0:
		mps = _get_plotted_steps(ship_state).size()
	var drm := 0
	if mps >= 7:
		drm = 2
	elif mps >= 4:
		drm = 1
	if ship_state.rudder_destroyed or ship_state.rudder_jam_direction() != ShipState.RUDDER_NOT_JAMMED:
		drm += 3
	if ship_state.is_poor_maneuvering():
		drm += 1
	return drm


## ============================================================================
## Poor maneuvering (6.F)
## ============================================================================

## The Poor Maneuvering roll for each plotted turn (6.F.3): d10 (0-9) <= the chart number (crew
## quality x maneuver type) turns as plotted. A failure moves one hex ahead first and drops the last
## MP plotted; with the rudder destroyed (hull #2) the ship rolls again at each further hex until it
## succeeds, with the wheel shot away (hull #3) it turns after the one hex. A failed turn pushed off
## the end of the plot carries over to the next g-t's first MP (6.F.4), which turns without a roll, as
## does a turn left over from the last g-t (ShipState.pending_turn). A turn at MA 0 also rolls here,
## and must pass both this and the Tacking roll (6.F.5); it never moves ahead.
## Rolls from the resolver's `rng`. Returns {steps, events: [POOR_MANEUVERING_ROLL], carried: the
## turn carried to the next g-t (-1 none), tack_rolled, tack_failed}.
func _roll_poor_maneuvering(ship_state: ShipState, steps: Array) -> Dictionary:
	var out := {"steps": steps, "events": [], "carried": -1, "tack_rolled": false, "tack_failed": false}
	if steps.is_empty():
		return out
	var turns: Array = _step_turns(ship_state, steps)  # -1 ahead, PORT or STARBOARD per step
	var pending: int = ship_state.pending_turn
	if _find_tacking_impulse(ship_state, steps) == 0:
		if pending >= 0 and turns[0] == pending:
			return out  # the turn left over from last g-t needs no roll (6.F.5)
		out.tack_rolled = true
		out.tack_failed = not _roll_steering(ship_state, 0, out.events, "turn at MA 0")
		return out
	var plotted_count: int = turns.size()
	var changed := false
	var i := 0
	while i < turns.size():
		var turn: int = turns[i]
		if turn < 0 or (i == 0 and turn == pending):
			i += 1
			continue
		var carried: bool = i + 1 >= plotted_count
		if _roll_steering(ship_state, i, out.events, "carried over" if carried else "one hex ahead"):
			i += 1
			continue
		turns.insert(i, -1)
		turns.resize(plotted_count)
		changed = true
		if carried:
			out.carried = turn
			break
		# The turn now follows the extra hex: a destroyed rudder rolls for it again there.
		i += 1 if ship_state.rudder_destroyed else 2
	if changed:
		out.steps = _steps_from_turns(ship_state, turns)
	return out


## One Poor Maneuvering roll for the turn on `segment`; logs it in `events` and returns success.
## `on_fail` tells what a failure does ("one hex ahead", "carried over", "turn at MA 0").
func _roll_steering(ship_state: ShipState, segment: int, events: Array, on_fail: String) -> bool:
	var number: int = poor_maneuvering_number(ship_state)
	var d10: int = rng.randi_range(0, 9)
	var ev = MovementTypes.ResolutionEvent.new(ship_state.ship_id, segment,
		MovementTypes.ResolutionEventType.POOR_MANEUVERING_ROLL)
	ev.roll = float(d10)
	ev.threshold = float(number)
	ev.success = d10 <= number
	ev.detail = "" if ev.success else on_fail
	events.append(ev)
	return ev.success


func poor_maneuvering_number(ship_state: ShipState) -> int:
	var maneuverability: String = ship_state.ship.maneuverability if ship_state.ship else "b"
	return DataManager.combat_tables.poor_maneuvering_number(ship_state.crew_quality, maneuverability)


## Chance (0.0-1.0) that a poor-maneuvering ship's plotted turn succeeds on its roll (6.F.3); 1.0
## for a ship that is not poor maneuvering. Pure query, used by the planning screen.
func poor_maneuvering_chance(ship_state: ShipState) -> float:
	if not ship_state.is_poor_maneuvering():
		return 1.0
	return clampf((poor_maneuvering_number(ship_state) + 1) / 10.0, 0.0, 1.0)


## Per step of a plot: -1 for a step ahead, else the side it turns to (PORT or STARBOARD).
func _step_turns(ship_state: ShipState, steps: Array) -> Array:
	var turns: Array = []
	var facing: int = ship_state.facing
	for step in steps:
		var step_facing: int = int(step.get("facing", facing))
		if step_facing == facing:
			turns.append(-1)
		else:
			turns.append(ShipState.PORT if step_facing == (facing + 5) % 6 else ShipState.STARBOARD)
		facing = step_facing
	return turns


## The plot steps (bow hex and facing after each) for a list of -1 / PORT / STARBOARD.
func _steps_from_turns(ship_state: ShipState, turns: Array) -> Array:
	var steps: Array = []
	var bow: Vector2i = ship_state.hex_position
	var facing: int = ship_state.facing
	for turn in turns:
		if turn < 0:
			bow += HexGrid.DIRECTIONS[facing]
		else:
			facing = (facing + 5) % 6 if turn == ShipState.PORT else (facing + 1) % 6
		steps.append({"hex": {"q": bow.x, "r": bow.y}, "facing": facing})
	return steps


## Put a ship's Poor Maneuvering rolls into its final result, each only if the ship reached that
## segment, and set the turn it carries to the next g-t (6.F.4-5): a turn pushed off the end of a plot
## the ship sailed in full, or a turn at MA 0 that failed after a roll; a ship whose left-over turn at
## MA 0 then fails its Tacking roll starts again (6.F.5 "reset").
func _record_steering(ship_state: ShipState, result: MovementTypes.ShipResolutionResult, pm: Dictionary,
		steps: Array, amended: bool) -> void:
	for ev in pm.events:
		if not _reached_segment(result, ev.impulse):
			continue
		var bow: Vector2i = ship_state.hex_position
		var facing: int = ship_state.facing
		for move in result.events:
			if move.event_type == MovementTypes.ResolutionEventType.MOVE and move.impulse < ev.impulse:
				bow = move.to_hex
				facing = move.facing
		ev.from_hex = bow
		ev.to_hex = bow
		ev.facing = facing
		_insert_at_segment_start(result, ev.impulse, [ev])
	if pm.tack_rolled:
		var failed: bool = pm.tack_failed or result.tacking_failed
		result.pending_turn = _step_turns(ship_state, pm.steps)[0] if failed else -1
	elif pm.carried >= 0 and not amended and _reached_segment(result, steps.size()):
		result.pending_turn = pm.carried


## ============================================================================
## Utility
## ============================================================================

func _is_in_irons(ship_state: ShipState, _environment: EnvironmentState) -> bool:
	var wind_facing: String = _get_ship_wind_facing(ship_state)
	return ship_state.speed == 0 and wind_facing == "L"


func _wind_direction() -> int:
	return game_state.environment.wind_direction if game_state and game_state.environment else 0


func _get_ship_wind_facing(ship_state: ShipState) -> String:
	var wind_dir: int = 0
	if game_state and game_state.environment:
		wind_dir = game_state.environment.wind_direction
	return hex_grid.get_wind_facing(ship_state.facing, wind_dir)


## MPs plotted this g-t: the pass's steps for the ship when given, else its plot.
func _mps_plotted(ship_state: ShipState, steps_by_ship: Dictionary) -> int:
	if steps_by_ship.has(ship_state.ship_id):
		return steps_by_ship[ship_state.ship_id].size()
	return _get_plotted_steps(ship_state).size()


func _get_plotted_steps(ship_state: ShipState) -> Array:
	## Fouled, grappled (8.C.7), struck and destroyed ships cannot move: any plot is ignored
	## (defence behind the plotting check).
	if ship_state.is_linked() or ship_state.is_out_of_play():
		return []
	var plot: Array = ship_state.plotted_actions.get("movement", [])
	if plot.is_empty() and not ship_state.plotted_actions.get("movement_plotted", false):
		return DefaultCourse.as_dicts(DefaultCourse.for_ship(game_state, ship_state))  # 6.G.2
	# 6.F: a stored course that breaks a jammed rudder is not executed: the ship holds.
	var path: Array[MovementTypes.PlotStep] = []
	for d in plot:
		path.append(MovementTypes.PlotStep.from_dict(d))
	var jam_error := _validator().rudder_jam_error(ship_state, path)
	if jam_error != "":
		Trace.trace_log("MovementResolver", "course breaks jammed rudder, ship holds",
			{"ship": ship_state.ship_id, "why": jam_error})
		return []
	return plot


## Impulse of a turn plotted at MA=0, which must pass a Tacking roll (5.D.1): tacking from WF=L,
## turning out of irons, or any other turn by a ship whose MA is 0. Such a turn is the ship's first
## (and only) step. -1 when the plot needs no roll.
func _find_tacking_impulse(ship_state: ShipState, steps: Array) -> int:
	if steps.is_empty() or not plots_ma0_turn(ship_state, steps,
			game_state.ship_controller.get_movement_allowance(ship_state.ship_id)):
		return -1
	return 0


## Whether `steps` (a movement plot) begin with a turn and the ship's MA is 0 (5.D.1): the turn
## must pass a Tacking roll. Pure; CrewRules uses it for the Braces (T) station.
static func plots_ma0_turn(ship_state: ShipState, steps: Array, movement_allowance: int) -> bool:
	if steps.is_empty() or movement_allowance != 0:
		return false
	return int(steps[0].get("facing", ship_state.facing)) != ship_state.facing


## 5.D.2a: +2 per crew section short of the 3 the Tacking table assumes, at most +6.
static func tack_crew_drm(sections: int) -> int:
	var assumed: int = int(DataManager.combat_tables.crew_task("T").get("assumed_sections", 3))
	var per_section: int = int(DataManager.combat_tables.crew_task("T").get("drm_per_section_short", 2))
	return per_section * clampi(assumed - sections, 0, assumed)


## ============================================================================
## Apply results to state
## ============================================================================

@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func apply_results(log: MovementTypes.ResolutionLog, ships: Array[ShipState]) -> void:
	if game_state and not game_state.is_server:
		push_error("MovementResolver: Cannot apply movement results on client")
		return
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
			var rudder_irons: bool = _rudder_irons(ship_state, result)
			var last_step: int = _last_step_direction(result)
			if last_step != NO_STEP:
				sc.set_last_step_direction(sid, last_step)
			if ship_state.pending_turn != result.pending_turn:
				sc.set_pending_turn(sid, result.pending_turn)
			sc.set_moved_this_turn(sid, moved_ahead)
			# 8.F.3b / 8.C.1: MPs used this g-t, turns included, whether or not the ship moved ahead.
			sc.set_mp_used(sid, _count_steps_executed(result))
			sc.set_ship_position(sid, result.final_hex)
			sc.set_ship_facing(sid, result.final_facing)
			if result.immobilized:
				sc.set_immobilized(sid, true)
			# A ship with its rudder destroyed that enters WF=L is in irons at once (hull #2): stopped.
			# So is a ship at WF=L in a collision (5.D.5).
			var collision_irons: bool = result.collided_with != "" \
					and hex_grid.get_wind_facing(result.final_facing, _wind_direction()) == "L"
			sc.set_ship_speed(sid, _count_steps_executed(result) if moved_ahead and not rudder_irons \
					and not collision_irons else 0)
			if result.collided_with != "":
				sc.set_collision_this_turn(sid, true)
			if result.fouled_with != "":
				sc.set_fouled_with(sid, result.fouled_with)
			if result.rigging_damage > 0:
				_apply_rigging_damage(sid, result.rigging_damage, sc)
			sc.clear_plotted_actions(sid)
		else:
			push_error("MovementResolver: No ship_controller available")

## _last_step_direction when the ship executed no step.
const NO_STEP := -2

## The direction of the ship's last executed step (-1 ahead, PORT, STARBOARD), NO_STEP if none.
func _last_step_direction(result: MovementTypes.ShipResolutionResult) -> int:
	var direction: int = NO_STEP
	for ev in result.events:
		if ev.event_type != MovementTypes.ResolutionEventType.MOVE:
			continue
		if ev.facing == ev.from_facing:
			direction = -1
		else:
			direction = ShipState.PORT if ev.facing == (ev.from_facing + 5) % 6 else ShipState.STARBOARD
	return direction


## Hull #2: a ship whose rudder is destroyed and which turned into WF=L this g-t is in irons.
## Call before the ship's facing is updated.
func _rudder_irons(ship_state: ShipState, result: MovementTypes.ShipResolutionResult) -> bool:
	if not ship_state.rudder_destroyed or result.final_facing == ship_state.facing:
		return false
	var wind_dir: int = game_state.environment.wind_direction if game_state and game_state.environment else 0
	return hex_grid.get_wind_facing(result.final_facing, wind_dir) == "L"


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
## irons, a collision (logged for the ship that ran into the other), movement cut short of the plot
## (or a plotted turn undone while the ship sailed its full count of steps), and fouling (once per
## pair). Reads each ship's plot, so call it before the plots are cleared.
@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func log_outcomes(log: MovementTypes.ResolutionLog, ships: Array[ShipState], turn_log: PhaseEvents.PhaseLog) -> void:
	if game_state and not game_state.is_server:
		push_error("MovementResolver: Cannot log movement outcomes on client")
		return
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
		elif _rudder_irons(ship_state, result):
			turn_log.add(PhaseEvents.Type.IN_IRONS, phase, sid, {"cause": "rudder"})
		for ev in result.events:
			if ev.event_type == MovementTypes.ResolutionEventType.POOR_MANEUVERING_ROLL:
				turn_log.add(PhaseEvents.Type.POOR_MANEUVERING, phase, sid, {"roll": int(ev.roll),
					"needed": int(ev.threshold), "success": ev.success, "outcome": ev.detail})
		for ev in result.events:
			if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
				turn_log.add(PhaseEvents.Type.BEAR_OFF, phase, sid, {"choice": ev.detail.get_slice(" ", 0),
					"success": ev.success, "roll": int(ev.roll), "needed": int(ev.threshold),
					"drm": _detail_drm(ev.detail)}, result.blocked_by)
			elif ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_DECLINED:
				turn_log.add(PhaseEvents.Type.BEAR_OFF, phase, sid, {"choice": MovementTypes.BEAR_OFF_COLLIDE},
					result.blocked_by)
			if ev.event_type == MovementTypes.ResolutionEventType.COLLISION and ev.detail.begins_with("collided with"):
				var at := _collision_hex(ev)
				turn_log.add(PhaseEvents.Type.COLLISION, phase, sid, {"hex": {"q": at.x, "r": at.y}},
					result.collided_with)
		var planned: int = _get_plotted_steps(ship_state).size()
		if not result.tacking_failed and planned > 0 and _count_steps_executed(result) < planned:
			var data := {"moved": _count_steps_executed(result), "planned": planned}
			var cause := stop_cause(result)
			if not cause.is_empty():
				data["cause"] = cause["cause"]
			_add_contest_rolls(data, result, log.get_result(str(cause.get("other", ""))))
			turn_log.add(PhaseEvents.Type.STOPPED_SHORT, phase, sid, data, str(cause.get("other", "")))
		elif not result.tacking_failed and planned > 0:
			# A rolled-back turn (or one lost in a stern contest) whose deceleration steps ahead bring the
			# step count back to the plotted length: the ship did not stop short, but left its course.
			var undone := stop_cause(result)
			if undone.get("cause", "") in ["overlap", "stern_contest"]:
				var data := {"cause": undone["cause"]}
				_add_contest_rolls(data, result, log.get_result(str(undone.get("other", ""))))
				turn_log.add(PhaseEvents.Type.TURN_UNDONE, phase, sid, data, str(undone.get("other", "")))
		if result.fouled_with != "" and not fouled_logged.has(sid):
			turn_log.add(PhaseEvents.Type.FOULED, phase, sid, {"cause": "collision"}, result.fouled_with)
			fouled_logged[sid] = true
			fouled_logged[result.fouled_with] = true


## For a lost stern contest, the deciding (last) rolls of the loser and the winner, DRMs added, as
## data "roll" and "other_roll".
## The "drm=+1" field of a BEARING_OFF_ROLL detail.
static func _detail_drm(detail: String) -> int:
	for part in detail.split(" "):
		if part.begins_with("drm="):
			return int(part.substr(4))
	return 0


static func _add_contest_rolls(data: Dictionary, loser: MovementTypes.ShipResolutionResult,
		winner: MovementTypes.ShipResolutionResult) -> void:
	if data.get("cause", "") != "stern_contest" or winner == null:
		return
	var mine := _last_contest_roll(loser)
	var theirs := _last_contest_roll(winner)
	if mine and theirs:
		data["roll"] = int(mine.roll + mine.threshold)
		data["other_roll"] = int(theirs.roll + theirs.threshold)


static func _last_contest_roll(result: MovementTypes.ShipResolutionResult) -> MovementTypes.ResolutionEvent:
	var last: MovementTypes.ResolutionEvent = null
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL:
			last = ev
	return last


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
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL and ev.success:
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
