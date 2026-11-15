class_name MovementResolver
extends RefCounted
## MovementResolver - Resolves plotted movement impulse-by-impulse
## Multi-ship resolution: contested hexes, bearing off, collisions, fouling.
## Ships move simultaneously; contests checked per impulse. Every ship holds two hexes, bow and
## stern; each step enters one hex: an ahead step its new bow hex, a turn its new stern hex.

var game_state: Node = null
var hex_grid: HexGrid = null
var _explicit_rng: RandomNumberGenerator = null

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

	var results: Dictionary = {}
	var current_hexes: Dictionary = {}  # ship_id -> bow hex
	var current_facings: Dictionary = {}  # ship_id -> facing
	var stopped: Dictionary = {}
	var steps_by_ship: Dictionary = {}
	var forward_since_turn: Dictionary = {}
	var pivots_this_turn: Dictionary = {}

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

		var ship_steps = _get_plotted_steps(ship_state)
		if ship_steps.is_empty():
			if _is_in_irons(ship_state, environment):
				_remain_in_irons(ship_state, result)
			else:
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
	log.max_impulses = max_impulses

	var ship_map: Dictionary = {}
	for ship_state in ships:
		ship_map[ship_state.ship_id] = ship_state

	for impulse in range(max_impulses):
		_resolve_impulse(impulse, ships, ship_map, steps_by_ship, results, current_hexes, current_facings, stopped, environment, forward_since_turn, pivots_this_turn)

	for sid in results:
		log.add_result(results[sid])

	return log


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

	for ship_state in ships:
		var sid = ship_state.ship_id
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
	# old stern hex is released as it moves.
	var held: Dictionary = Occupancy.from_positions(current_hexes, current_facings, intended_moves.keys())
	for sid in intended_moves:
		held[current_hexes[sid]] = sid

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

	# Stern-entries (6.B.4a/b outcome, no overlap allowance yet): a swinging stern may only enter a
	# hex nobody holds or enters. A bow entering the same hex goes ahead as if the stern were not there.
	for entered in stern_targets:
		for sid in stern_targets[entered]:
			var blocker_id: String = _stern_blocker(sid, entered, held, bow_targets, stern_targets)
			if blocker_id != "":
				_cancel_turn(sid, blocker_id, impulse, results, current_hexes, current_facings, stopped)
				held[HexGrid.stern_of(current_hexes[sid], current_facings[sid])] = sid  # it keeps its stern
				continue
			var prev_facing: int = current_facings[sid]
			_apply_move(sid, intended_moves[sid].hex, intended_moves[sid].facing, impulse, results, current_hexes, current_facings)
			_update_turn_tracking(sid, prev_facing, intended_moves[sid].facing, forward_since_turn, pivots_this_turn)

	for target_hex in bow_targets:
		var contesting_ids: Array = []
		for sid in bow_targets[target_hex]:
			if not stopped[sid]:  # a collision earlier in this segment already stopped it
				contesting_ids.append(sid)
		if contesting_ids.is_empty():
			continue

		var occupant_id: String = _find_holder(target_hex, held, contesting_ids)
		if occupant_id != "":
			for sid in contesting_ids:
				_resolve_collision_or_bearoff(
					sid, occupant_id, impulse, ship_map, results, current_hexes, stopped, environment, forward_since_turn, pivots_this_turn
				)
			continue

		if contesting_ids.size() == 1:
			var sid: String = contesting_ids[0]
			var prev_facing: int = current_facings[sid]
			_apply_move(sid, intended_moves[sid].hex, intended_moves[sid].facing, impulse, results, current_hexes, current_facings)
			_update_turn_tracking(sid, prev_facing, intended_moves[sid].facing, forward_since_turn, pivots_this_turn)
			continue

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


## Who stops a stern swinging into `entered`: the ship holding the hex, else a bow entering it, else
## another stern entering it. "" when the hex is free.
func _stern_blocker(sid: String, entered: Vector2i, held: Dictionary, bow_targets: Dictionary, stern_targets: Dictionary) -> String:
	if held.has(entered) and held[entered] != sid:
		return held[entered]
	for other_id in bow_targets.get(entered, []):
		if other_id != sid:
			return other_id
	for other_id in stern_targets.get(entered, []):
		if other_id != sid:
			return other_id
	return ""


## The turn is cancelled: the ship keeps its bow hex and facing and stops for the rest of the turn.
## No collision and no bearing off.
func _cancel_turn(
	sid: String,
	blocker_id: String,
	impulse: int,
	results: Dictionary,
	current_hexes: Dictionary,
	current_facings: Dictionary,
	stopped: Dictionary
) -> void:
	var result: MovementTypes.ShipResolutionResult = results[sid]
	var ev = MovementTypes.ResolutionEvent.new(sid, impulse, MovementTypes.ResolutionEventType.STERN_BLOCKED)
	ev.from_hex = current_hexes[sid]
	ev.to_hex = current_hexes[sid]
	ev.facing = current_facings[sid]
	ev.from_facing = current_facings[sid]
	ev.success = false
	ev.detail = "stern blocked by %s" % blocker_id
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
func _remain_in_irons(ship_state: ShipState, result: MovementTypes.ShipResolutionResult) -> void:
	result.immobilized = true
	var imm_ev = MovementTypes.ResolutionEvent.new(
		ship_state.ship_id, 0, MovementTypes.ResolutionEventType.IMMOBILIZED
	)
	imm_ev.from_hex = ship_state.hex_position
	imm_ev.to_hex = ship_state.hex_position
	imm_ev.facing = ship_state.facing
	imm_ev.detail = "in irons, no turn plotted"
	result.events.append(imm_ev)


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
				var at := _collision_hex(log, result.collided_with, ev)
				turn_log.add(PhaseEvents.Type.COLLISION, phase, sid, {"hex": {"q": at.x, "r": at.y}},
					result.collided_with)
		var planned: int = _get_plotted_steps(ship_state).size()
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
## "other": id} when it bore off to avoid the ship in its way, {"cause": "stern_blocked", "other": id}
## when its turn was cancelled because its stern would swing into that ship, {} when the result names
## no cause.
static func stop_cause(result: MovementTypes.ShipResolutionResult) -> Dictionary:
	if result.collided_with != "":
		return {"cause": "collision", "other": result.collided_with}
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.STOPPED and ev.success:
			return {"cause": "bore_off", "other": result.blocked_by}
		if ev.event_type == MovementTypes.ResolutionEventType.STERN_BLOCKED:
			return {"cause": "stern_blocked", "other": result.blocked_by}
	return {}


## Where the other ship lay when this one ran into it (its own collision event), else where this ship was.
@warning_ignore("shadowed_global_identifier")
func _collision_hex(log: MovementTypes.ResolutionLog, other_id: String, ev: MovementTypes.ResolutionEvent) -> Vector2i:
	var other: MovementTypes.ShipResolutionResult = log.get_result(other_id)
	if other:
		for other_ev in other.events:
			if other_ev.event_type == MovementTypes.ResolutionEventType.COLLISION and other_ev.impulse == ev.impulse:
				return other_ev.from_hex
	return ev.to_hex
