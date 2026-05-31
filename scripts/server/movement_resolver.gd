class_name MovementResolver
extends RefCounted
## MovementResolver - Resolves plotted movement impulse-by-impulse
## Multi-ship resolution: contested hexes, bearing off, collisions, fouling.
## Ships move simultaneously; contests checked per impulse.

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
	var current_hexes: Dictionary = {}
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
		stopped[ship_state.ship_id] = false
		forward_since_turn[ship_state.ship_id] = 0
		pivots_this_turn[ship_state.ship_id] = 0

		var ship_steps = _get_plotted_steps(ship_state)
		if ship_steps.is_empty():
			if _is_in_irons(ship_state, environment):
				_resolve_in_irons_escape(ship_state, environment, result)
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
		_resolve_impulse(impulse, ships, ship_map, steps_by_ship, results, current_hexes, stopped, environment, forward_since_turn, pivots_this_turn)

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
				result.final_hex = current_hexes[sid]
				result.final_facing = _get_luffing_facing(ship_state, environment)
				result.immobilized = true
				result.tacking_failed = true
				stopped[sid] = true
				continue

		intended_moves[sid] = {"hex": step_hex, "facing": step_facing}

	if intended_moves.is_empty():
		return

	var hex_targets: Dictionary = {}
	for sid in intended_moves:
		var target_hex: Vector2i = intended_moves[sid].hex
		if not hex_targets.has(target_hex):
			hex_targets[target_hex] = []
		hex_targets[target_hex].append(sid)

	for target_hex in hex_targets:
		var contesting_ids: Array = hex_targets[target_hex]

		var occupant_id: String = _find_stationary_occupant(target_hex, current_hexes, stopped, contesting_ids)
		if occupant_id != "":
			for sid in contesting_ids:
				_resolve_collision_or_bearoff(
					sid, occupant_id, impulse, ship_map, results, current_hexes, stopped, environment, forward_since_turn, pivots_this_turn
				)
			continue

		if contesting_ids.size() == 1:
			var sid: String = contesting_ids[0]
			var prev_facing: int = (results[sid] as MovementTypes.ShipResolutionResult).final_facing
			_apply_move(sid, intended_moves[sid].hex, intended_moves[sid].facing, impulse, results, current_hexes)
			_update_turn_tracking(sid, prev_facing, intended_moves[sid].facing, forward_since_turn, pivots_this_turn)
			continue

		_resolve_contested_hex(
			contesting_ids, target_hex, impulse, ship_map, results, current_hexes, stopped, intended_moves, environment, forward_since_turn, pivots_this_turn
		)


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
	stopped: Dictionary,
	intended_moves: Dictionary,
	environment: EnvironmentState,
	forward_since_turn: Dictionary,
	pivots_this_turn: Dictionary
) -> void:
	var winner_id: String = _roll_contest(contesting_ids, impulse, ship_map, results)

	var prev_facing: int = (results[winner_id] as MovementTypes.ShipResolutionResult).final_facing
	_apply_move(winner_id, target_hex, intended_moves[winner_id].facing, impulse, results, current_hexes)
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
		var class_diff: int = my_class - other_class
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

	var crew_quality: String = loser.crew_quality
	var threshold: float = DataManager.get_bearing_off_probability(crew_quality, maneuverability)

	var roll_value: float = rng.randf()
	var success: bool = roll_value <= threshold

	var ev = MovementTypes.ResolutionEvent.new(
		loser_id, impulse, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL
	)
	ev.from_hex = current_hexes[loser_id]
	ev.to_hex = current_hexes[loser_id]
	ev.facing = loser_result.final_facing
	ev.roll = roll_value
	ev.threshold = threshold
	ev.success = success
	ev.detail = "crew=%s maneuver=%s roll=%.3f threshold=%.3f" % [crew_quality, maneuverability, roll_value, threshold]
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

	var fouled: bool = _roll_fouling(state_a, ship_map[ship_b_id])
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


func _roll_fouling(ship_a: ShipState, ship_b: ShipState) -> bool:
	if _is_dismasted(ship_a) or _is_dismasted(ship_b):
		return false
	return rng.randf() <= 0.5


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
	current_hexes: Dictionary
) -> void:
	var result: MovementTypes.ShipResolutionResult = results[sid]

	var ev = MovementTypes.ResolutionEvent.new(
		sid, impulse, MovementTypes.ResolutionEventType.MOVE
	)
	ev.from_hex = current_hexes[sid]
	ev.to_hex = target_hex
	ev.facing = facing
	ev.success = true
	result.events.append(ev)

	current_hexes[sid] = target_hex
	result.final_hex = target_hex
	result.final_facing = facing


func _find_stationary_occupant(
	target_hex: Vector2i,
	current_hexes: Dictionary,
	stopped: Dictionary,
	moving_ids: Array
) -> String:
	for sid in current_hexes:
		if sid in moving_ids:
			continue
		if current_hexes[sid] == target_hex and stopped.get(sid, false):
			return sid
	return ""


## ============================================================================
## Tacking and in-irons (per-ship, unchanged from S06)
## ============================================================================

func _resolve_in_irons_escape(
	ship_state: ShipState,
	environment: EnvironmentState,
	result: MovementTypes.ShipResolutionResult
) -> void:
	var drm: float = _calculate_tacking_drm(ship_state)
	var maneuverability: String = ship_state.ship.maneuverability if ship_state.ship else "b"
	var threshold: float = DataManager.get_tacking_percent(maneuverability, environment.wind_speed)

	var roll_value: float = rng.randf()
	var adjusted: float = roll_value + drm
	var success: bool = adjusted <= threshold

	var ev = MovementTypes.ResolutionEvent.new(
		ship_state.ship_id, 0, MovementTypes.ResolutionEventType.IN_IRONS_ESCAPE_ROLL
	)
	ev.from_hex = ship_state.hex_position
	ev.to_hex = ship_state.hex_position
	ev.facing = ship_state.facing
	ev.roll = roll_value
	ev.threshold = threshold
	ev.success = success
	ev.detail = "drm=%.2f adjusted=%.2f threshold=%.2f" % [drm, adjusted, threshold]
	result.events.append(ev)

	if not success:
		result.immobilized = true
		var imm_ev = MovementTypes.ResolutionEvent.new(
			ship_state.ship_id, 0, MovementTypes.ResolutionEventType.IMMOBILIZED
		)
		imm_ev.from_hex = ship_state.hex_position
		imm_ev.to_hex = ship_state.hex_position
		imm_ev.facing = ship_state.facing
		imm_ev.detail = "in-irons escape failed"
		result.events.append(imm_ev)


func _roll_tacking(
	ship_state: ShipState,
	environment: EnvironmentState,
	result: MovementTypes.ShipResolutionResult,
	impulse: int
) -> bool:
	var drm: float = _calculate_tacking_drm(ship_state)
	var maneuverability: String = ship_state.ship.maneuverability if ship_state.ship else "b"
	var threshold: float = DataManager.get_tacking_percent(maneuverability, environment.wind_speed)

	var roll_value: float = rng.randf()
	var adjusted: float = roll_value + drm
	var success: bool = adjusted <= threshold

	var ev = MovementTypes.ResolutionEvent.new(
		ship_state.ship_id, impulse, MovementTypes.ResolutionEventType.TACKING_ROLL
	)
	ev.from_hex = ship_state.hex_position
	ev.to_hex = ship_state.hex_position
	ev.facing = ship_state.facing
	ev.roll = roll_value
	ev.threshold = threshold
	ev.success = success
	ev.detail = "drm=%.2f adjusted=%.2f threshold=%.2f" % [drm, adjusted, threshold]
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


func _calculate_tacking_drm(ship_state: ShipState) -> float:
	var drm: float = 0.0

	if ship_state.ship:
		var rigging_max = ship_state.ship.rigging_hp
		for i in range(4):
			var max_hp: int = rigging_max[i] if i < rigging_max.size() else 0
			var cur_hp: int = ship_state.rigging_current_hp[i] if i < ship_state.rigging_current_hp.size() else 0
			if max_hp > 0 and cur_hp <= 0:
				drm += 0.2

	var wind_facing: String = _get_ship_wind_facing(ship_state)
	if wind_facing == "L":
		drm += 0.1

	if ship_state.towing:
		drm += 0.1

	return drm


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


func _get_luffing_facing(_ship_state: ShipState, environment: EnvironmentState) -> int:
	return environment.wind_direction


func _get_plotted_steps(ship_state: ShipState) -> Array:
	return ship_state.plotted_actions.get("movement", [])


func _find_tacking_impulse(ship_state: ShipState, steps: Array) -> int:
	if not ship_state.tacking:
		return -1

	var current_facing: int = ship_state.facing
	for i in range(steps.size()):
		var step_facing: int = int(steps[i].get("facing", current_facing))
		if step_facing != current_facing:
			var wind_facing: String = hex_grid.get_wind_facing(step_facing, _wind_direction())
			if wind_facing == "L":
				return i
		current_facing = step_facing
	return -1


func _wind_direction() -> int:
	if game_state and game_state.environment:
		return game_state.environment.wind_direction
	return 0


## ============================================================================
## Apply results to state
## ============================================================================

@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func apply_results(log: MovementTypes.ResolutionLog, ships: Array[ShipState]) -> void:
	var sc = game_state.ship_controller if game_state else null
	for ship_state in ships:
		var result = log.get_result(ship_state.ship_id)
		if result == null:
			continue
		var sid = ship_state.ship_id
		if sc:
			sc.set_ship_position(sid, result.final_hex)
			sc.set_ship_facing(sid, result.final_facing)
			if result.immobilized:
				sc.set_immobilized(sid, true)
			sc.set_ship_speed(sid, _count_hexes_moved(result))
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
