class_name MovementValidator
extends RefCounted
## MovementValidator - Calculates valid movement options for ships
##
## Consults DataManager rule tables for MA, turning, and speed change limits.
## Single-ship rules only (no collision/contest detection).

var game_state: Node = null
var hex_grid: HexGrid = null


func _init(p_game_state: Node = null) -> void:
	game_state = p_game_state if p_game_state else GameState
	hex_grid = HexGrid.new()


## Internal snapshot of computed state during path validation.
class PlottingState extends RefCounted:
	var base_ma: int = 0
	var remaining_ma: int = 0
	var min_ma: int = 0
	var max_ma: int = 0
	var pivots_used: int = 0
	var forward_hexes_since_last_pivot: int = 0
	var last_pivot_direction: MovementTypes.MoveType = MovementTypes.MoveType.NONE
	var free_pivot_used: bool = false
	var luffing_ended: bool = false
	var is_tacking_attempt: bool = false
	var current_facing: int = 0
	var current_hex: Vector2i = Vector2i.ZERO
	var wind_direction: int = 0
	var wind_speed: int = 0
	var speed_last_turn: int = 0
	var maneuverability: String = "a"
	var speed_type: String = "F/F"
	var sail_state: String = "MS"
	var rigging_quality: int = 4


func calculate_valid_moves(
	ship_state: ShipState,
	current_hex: Vector2i,
	current_facing: int,
	path_so_far: Array[MovementTypes.PlotStep]
) -> MovementTypes.ValidMovesResult:
	var ps = _build_plotting_state(ship_state, current_hex, current_facing, path_so_far)
	var result = MovementTypes.ValidMovesResult.new()
	result.remaining_ma = ps.remaining_ma
	result.can_submit = true
	result.is_tacking_attempt = ps.is_tacking_attempt

	if ps.luffing_ended:
		return result

	if _is_in_irons(ship_state, path_so_far):
		Trace.trace_log("MovementValidator", "Ship %s in irons — no movement available" % ship_state.ship_id)
		return result

	var valid_options = _calculate_real_valid_hexes(ps, ship_state, path_so_far)
	result.valid_hexes = valid_options

	return result


func validate_hex_selection(
	ship_state: ShipState,
	current_hex: Vector2i,
	current_facing: int,
	selected_hex: Vector2i,
	path_so_far: Array[MovementTypes.PlotStep]
) -> MovementTypes.HexValidationResult:
	var valid_moves = calculate_valid_moves(
		ship_state, current_hex, current_facing, path_so_far
	)

	for valid_hex_option in valid_moves.valid_hexes.get_all_valid_moves():
		if valid_hex_option.hex == selected_hex:
			return MovementTypes.HexValidationResult.success(
				valid_hex_option.metadata.resulting_facing,
				valid_hex_option.metadata
			)

	return MovementTypes.HexValidationResult.failure(
		"ILLEGAL_HEX",
		"Selected hex is not a valid move option"
	)


func validate_submission(
	ship_state: ShipState,
	path: Array[MovementTypes.PlotStep]
) -> MovementTypes.SubmissionValidationResult:
	return MovementTypes.SubmissionValidationResult.success()


## Build a PlottingState snapshot by replaying the path so far.
func _build_plotting_state(
	ship_state: ShipState,
	current_hex: Vector2i,
	current_facing: int,
	path_so_far: Array[MovementTypes.PlotStep]
) -> PlottingState:
	var ps = PlottingState.new()
	ps.current_hex = current_hex
	ps.current_facing = current_facing
	ps.wind_direction = game_state.environment.wind_direction if game_state.environment else 0
	ps.wind_speed = game_state.environment.wind_speed if game_state.environment else 2
	ps.speed_last_turn = ship_state.speed
	ps.maneuverability = ship_state.ship.maneuverability.to_lower() if ship_state.ship else "a"
	ps.speed_type = ship_state.ship.speed_type if ship_state.ship else "F/F"
	ps.sail_state = ship_state.sail_state
	ps.rigging_quality = ship_state.get_rigging_quality()

	var accel = DataManager.get_speed_change("acceleration", ps.maneuverability)
	var decel = DataManager.get_speed_change("deceleration", ps.maneuverability)

	# Replay path to compute state at current position
	var replay_facing = ship_state.facing
	for step in path_so_far:
		if step.move_type == MovementTypes.MoveType.FORWARD:
			ps.forward_hexes_since_last_pivot += 1
		elif step.move_type == MovementTypes.MoveType.PORT or step.move_type == MovementTypes.MoveType.STARBOARD:
			ps.pivots_used += 1
			ps.forward_hexes_since_last_pivot = 0
			ps.last_pivot_direction = step.move_type

			# Check for luffing: pivot into wind_facing L ends movement
			var wf_after = hex_grid.get_wind_facing(step.facing, ps.wind_direction)
			if wf_after == "L":
				ps.luffing_ended = true

			# Check for tacking: pivot to L then same direction again
			if ps.pivots_used >= 2 and ps.luffing_ended:
				ps.is_tacking_attempt = true

		replay_facing = step.facing

	# Calculate MA at current facing
	var wind_facing = hex_grid.get_wind_facing(current_facing, ps.wind_direction)
	ps.base_ma = _lookup_ma(ps.speed_type, ps.wind_speed, wind_facing, ps.sail_state, ps.rigging_quality)

	# Speed range
	ps.min_ma = max(ps.speed_last_turn - decel, 0)
	ps.max_ma = min(ps.speed_last_turn + accel, ps.base_ma)
	if ps.max_ma < ps.min_ma:
		ps.max_ma = ps.min_ma

	# If MA is 0 from table, speed range is 0
	if ps.base_ma == 0:
		ps.min_ma = 0
		ps.max_ma = 0

	# Count MA spent so far
	var ma_spent = 0
	var replay_facing2 = ship_state.facing
	var first_move = true
	for step in path_so_far:
		if step.move_type == MovementTypes.MoveType.FORWARD:
			ma_spent += 1
			first_move = false
		elif step.move_type == MovementTypes.MoveType.PORT or step.move_type == MovementTypes.MoveType.STARBOARD:
			# Check for fast-tack bonus: C→B on first move
			if first_move:
				var wf_before = hex_grid.get_wind_facing(replay_facing2, ps.wind_direction)
				var wf_after = hex_grid.get_wind_facing(step.facing, ps.wind_direction)
				if wf_before == "C" and wf_after == "B":
					ps.max_ma += 1
					Trace.trace_log("MovementValidator", "Fast-tack bonus: C→B first pivot, +1 MA for ship %s" % ship_state.ship_id)

			# Pivots cost 1 MA, unless it's a free pivot at MA=0
			var pivot_wind_facing = hex_grid.get_wind_facing(replay_facing2, ps.wind_direction)
			var pivot_base_ma = _lookup_ma(ps.speed_type, ps.wind_speed, pivot_wind_facing, ps.sail_state, ps.rigging_quality)
			if pivot_base_ma == 0 or (ps.max_ma - ma_spent) <= 0:
				if not ps.free_pivot_used:
					ps.free_pivot_used = true
				else:
					ma_spent += 1
			else:
				ma_spent += 1
			first_move = false
		replay_facing2 = step.facing

	ps.remaining_ma = max(0, ps.max_ma - ma_spent)

	return ps


func _is_in_irons(ship_state: ShipState, path_so_far: Array[MovementTypes.PlotStep]) -> bool:
	"""Ship at wind_facing=L with speed 0 and no path yet = in irons."""
	if not path_so_far.is_empty():
		return false
	if ship_state.speed != 0:
		return false
	var wind_dir = game_state.environment.wind_direction if game_state.environment else 0
	var wf = hex_grid.get_wind_facing(ship_state.facing, wind_dir)
	if wf == "L":
		Trace.trace_log("MovementValidator", "Ship %s is in irons (facing L, speed 0)" % ship_state.ship_id)
		return true
	return false


func _calculate_real_valid_hexes(
	ps: PlottingState,
	ship_state: ShipState,
	path_so_far: Array[MovementTypes.PlotStep]
) -> MovementTypes.ValidNextHexes:
	var result = MovementTypes.ValidNextHexes.new()
	var last_step_was_pivot = false
	if not path_so_far.is_empty():
		var last_type = path_so_far.back().move_type
		last_step_was_pivot = (last_type == MovementTypes.MoveType.PORT or last_type == MovementTypes.MoveType.STARBOARD)

	# Forward move: always available if remaining_ma > 0
	if ps.remaining_ma > 0:
		var forward_hex = hex_grid.get_neighbor(ps.current_hex.x, ps.current_hex.y, ps.current_facing)
		var forward_meta = MovementTypes.MoveMetadata.new(MovementTypes.MoveType.FORWARD, ps.current_facing, 1)
		result.forward.append(MovementTypes.ValidMove.new(forward_hex, MovementTypes.MoveType.FORWARD, forward_meta))

	# Pivot rules
	var can_pivot = true
	var pivot_cost = 1

	# No consecutive pivots
	if last_step_was_pivot:
		can_pivot = false
		Trace.trace_log("MovementValidator", "Ship %s: no consecutive pivots" % ship_state.ship_id)

	# Max 2 pivots per turn
	if ps.pivots_used >= 2:
		can_pivot = false
		Trace.trace_log("MovementValidator", "Ship %s: max 2 pivots reached" % ship_state.ship_id)

	# Luffing ended movement
	if ps.luffing_ended:
		can_pivot = false

	# Min forward-hex requirement from turning table
	if can_pivot and ps.pivots_used > 0:
		var required_forward_port = _get_min_forward_for_pivot(
			ps, MovementTypes.MoveType.PORT, ship_state
		)
		var required_forward_starboard = _get_min_forward_for_pivot(
			ps, MovementTypes.MoveType.STARBOARD, ship_state
		)
		var can_port = ps.forward_hexes_since_last_pivot >= required_forward_port
		var can_starboard = ps.forward_hexes_since_last_pivot >= required_forward_starboard

		if can_port or can_starboard:
			can_pivot = true
		else:
			can_pivot = false
			Trace.trace_log("MovementValidator", "Ship %s: need %d/%d forward hexes before port/starboard pivot (have %d)" % [
				ship_state.ship_id, required_forward_port, required_forward_starboard, ps.forward_hexes_since_last_pivot
			])

		if can_pivot:
			# Determine cost: free pivot if MA=0 or remaining=0 and not used yet
			if ps.remaining_ma <= 0:
				if ps.free_pivot_used:
					can_pivot = false
				else:
					pivot_cost = 0

			if can_pivot and ps.remaining_ma > 0:
				pivot_cost = 1

			_add_pivot_options(result, ps, ship_state, pivot_cost, can_port, can_starboard)
			return result

	if can_pivot:
		# First pivot or no pivot yet — check if MA allows it
		if ps.remaining_ma <= 0:
			if ps.free_pivot_used:
				can_pivot = false
			else:
				pivot_cost = 0
		if can_pivot:
			_add_pivot_options(result, ps, ship_state, pivot_cost, true, true)

	return result


func _add_pivot_options(
	result: MovementTypes.ValidNextHexes,
	ps: PlottingState,
	ship_state: ShipState,
	pivot_cost: int,
	allow_port: bool,
	allow_starboard: bool
) -> void:
	if allow_port:
		var port_facing = (ps.current_facing + 5) % 6
		var port_hex = hex_grid.get_neighbor(ps.current_hex.x, ps.current_hex.y, port_facing)
		var port_wf = hex_grid.get_wind_facing(port_facing, ps.wind_direction)

		var port_meta = MovementTypes.MoveMetadata.new(MovementTypes.MoveType.PORT, port_facing, pivot_cost)
		result.port = MovementTypes.ValidMove.new(port_hex, MovementTypes.MoveType.PORT, port_meta)

		if port_wf == "L":
			Trace.trace_log("MovementValidator", "Ship %s: port pivot into luffing (L) — will end movement" % ship_state.ship_id)

	if allow_starboard:
		var starboard_facing = (ps.current_facing + 1) % 6
		var starboard_hex = hex_grid.get_neighbor(ps.current_hex.x, ps.current_hex.y, starboard_facing)
		var starboard_wf = hex_grid.get_wind_facing(starboard_facing, ps.wind_direction)

		var starboard_meta = MovementTypes.MoveMetadata.new(MovementTypes.MoveType.STARBOARD, starboard_facing, pivot_cost)
		result.starboard = MovementTypes.ValidMove.new(starboard_hex, MovementTypes.MoveType.STARBOARD, starboard_meta)

		if starboard_wf == "L":
			Trace.trace_log("MovementValidator", "Ship %s: starboard pivot into luffing (L) — will end movement" % ship_state.ship_id)


func _get_min_forward_for_pivot(
	ps: PlottingState,
	pivot_direction: MovementTypes.MoveType,
	ship_state: ShipState
) -> int:
	var direction: String
	if ps.last_pivot_direction == MovementTypes.MoveType.NONE:
		direction = "same_direction"
	elif ps.last_pivot_direction == pivot_direction:
		direction = "same_direction"
	else:
		direction = "opposite_direction"

	var speed = ps.speed_last_turn
	if speed <= 0:
		speed = 1
	var min_fwd = DataManager.get_min_heading_change_movement_required(
		direction, speed, ps.maneuverability
	)
	return max(1, min_fwd)


func _lookup_ma(speed_type: String, wind_speed: int, wind_facing: String, sail_state: String, rigging_quality: int) -> int:
	if wind_facing == "L":
		return 0
	return DataManager.get_movement_allowance(
		speed_type, wind_speed, wind_facing, sail_state.to_lower(), rigging_quality
	)
