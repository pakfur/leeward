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
	var mp_spent: int = 0  ## movement points the path so far spends (turns included, free pivot not)
	var pivots_used: int = 0
	var forward_hexes_since_last_pivot: int = 0
	var last_pivot_direction: MovementTypes.MoveType = MovementTypes.MoveType.NONE
	var free_pivot_used: bool = false
	var luffing_ended: bool = false
	## True after a turn plotted at MA=0 (tacking or turning out of irons, 5.D): the ship moves no further this g-t.
	var ma_zero_turn_ended: bool = false
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
	## MPs lost to critical hits (sheets cut, shrouds severed), off every table MA.
	var mp_loss: int = 0
	## Steps in the plot so far.
	var steps_plotted: int = 0


func calculate_valid_moves(
	ship_state: ShipState,
	current_hex: Vector2i,
	current_facing: int,
	path_so_far: Array[MovementTypes.PlotStep]
) -> MovementTypes.ValidMovesResult:
	var ps = _build_plotting_state(ship_state, current_hex, current_facing, path_so_far)
	var result = MovementTypes.ValidMovesResult.new()
	result.remaining_ma = ps.remaining_ma
	result.max_ma = ps.max_ma
	result.mp_spent = ps.mp_spent
	result.can_submit = rudder_jam_error(ship_state, path_so_far) == ""
	result.is_tacking_attempt = ps.is_tacking_attempt

	if ps.luffing_ended or ps.ma_zero_turn_ended:
		return result

	# A ship in irons gets the ordinary MA=0 options: one plotted turn, resolved by a Tacking roll (5.D.6).
	var valid_options = _calculate_real_valid_hexes(ps, ship_state, path_so_far)
	result.valid_hexes = valid_options
	result.can_submit = result.can_submit and _shortfall(ps, valid_options) == 0

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
	var jam_error := rudder_jam_error(ship_state, path)
	if jam_error != "":
		return MovementTypes.SubmissionValidationResult.failure("RUDDER_JAMMED", jam_error)
	var slow_error := deceleration_error(ship_state, path)
	if slow_error != "":
		return MovementTypes.SubmissionValidationResult.failure("TOO_SLOW", slow_error)
	return MovementTypes.SubmissionValidationResult.success()


## 5.E.4: the MPs the plot is short of the deceleration limit (last turn's speed less the ship's
## deceleration). 0 when the plot meets it, or when the ship cannot use any more MPs at the end of
## the plot: its movement allowance at that heading is used up, it turned head to wind or turned at
## MA 0 (5.E.9). A stopped ship (speed 0) has no minimum.
func deceleration_shortfall(ship_state: ShipState, path: Array) -> int:
	if ship_state == null:
		return 0
	var steps := _typed(path)
	var end_hex: Vector2i = steps[-1].hex if not steps.is_empty() else ship_state.hex_position
	var end_facing: int = steps[-1].facing if not steps.is_empty() else ship_state.facing
	var ps := _build_plotting_state(ship_state, end_hex, end_facing, steps)
	if ps.luffing_ended or ps.ma_zero_turn_ended:
		return 0
	return _shortfall(ps, _calculate_real_valid_hexes(ps, ship_state, steps))


## The MPs short of the deceleration limit at the end of a plot whose next moves are `valid`; 0 when
## no more MPs can be used there (5.E.9).
static func _shortfall(ps: PlottingState, valid: MovementTypes.ValidNextHexes) -> int:
	if ps.remaining_ma <= 0 or valid == null or not valid.has_any_moves():
		return 0
	return maxi(mini(ps.min_ma, ps.max_ma) - ps.mp_spent, 0)


## The deceleration refusal for a plot ("" when it is acceptable), naming the MPs it must use.
func deceleration_error(ship_state: ShipState, path: Array) -> String:
	var short := deceleration_shortfall(ship_state, path)
	if short <= 0:
		return ""
	var steps := _typed(path)
	var end_hex: Vector2i = steps[-1].hex if not steps.is_empty() else ship_state.hex_position
	var end_facing: int = steps[-1].facing if not steps.is_empty() else ship_state.facing
	var used: int = _build_plotting_state(ship_state, end_hex, end_facing, steps).mp_spent
	var decel: int = game_state.ship_controller.speed_change_limits(ship_state).decel
	return "Too slow: must use at least %d MP this turn (speed %d last turn, deceleration %d)" % [
		used + short, ship_state.speed, decel]


static func _typed(path: Array) -> Array[MovementTypes.PlotStep]:
	var typed: Array[MovementTypes.PlotStep] = []
	typed.assign(path)
	return typed


## Rudder Jammed to port or starboard (hull #2): a ship that moves must turn at least once that
## way this g-t; one that plots nothing (stops) need not. "" when the plot is acceptable.
func rudder_jam_error(ship_state: ShipState, path: Array) -> String:
	var jam: int = ship_state.rudder_jam_direction() if ship_state else ShipState.RUDDER_NOT_JAMMED
	if jam < 0 or path.is_empty():
		return ""
	var wanted := MovementTypes.MoveType.PORT if jam == ShipState.PORT else MovementTypes.MoveType.STARBOARD
	for step in path:
		if step.move_type == wanted:
			return ""
	return "Rudder jammed: the ship must turn to %s at least once" % PhaseEvents.SIDE_NAMES[jam]


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
	ps.sail_state = ship_state.movement_sail_state()
	ps.rigging_quality = game_state.ship_controller.get_rigging_quality(ship_state.ship_id)
	ps.mp_loss = ship_state.critical_mp_loss(game_state.ship_controller.current_turn())
	ps.steps_plotted = path_so_far.size()

	var limits: Dictionary = game_state.ship_controller.speed_change_limits(ship_state)
	var accel: int = limits.accel
	var decel: int = limits.decel

	# Replay path to compute state at current position
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


	# Calculate MA at current facing
	var wind_facing = hex_grid.get_wind_facing(current_facing, ps.wind_direction)
	ps.base_ma = _ship_ma(ps, wind_facing)
	# 5.G: blocked wind at the plotted position, against the other ships where they are now.
	ps.base_ma = BlockedWind.apply(ps.base_ma, BlockedWind.is_blocked(current_hex, current_facing,
			ps.wind_direction, game_state.ships.values(), ship_state.ship_id))

	# Speed range
	ps.min_ma = max(ps.speed_last_turn - decel, 0)
	# 5.E.9: the movement allowance at this heading wins over the deceleration limit.
	ps.max_ma = min(ps.speed_last_turn + accel, ps.base_ma)

	# If MA is 0 from table, speed range is 0
	if ps.base_ma == 0:
		ps.min_ma = 0
		ps.max_ma = 0

	# Count MA spent so far
	var ma_spent = 0
	var replay_facing2 = ship_state.facing
	for step in path_so_far:
		if step.move_type == MovementTypes.MoveType.FORWARD:
			ma_spent += 1
		elif step.move_type == MovementTypes.MoveType.PORT or step.move_type == MovementTypes.MoveType.STARBOARD:
			# Pivots cost 1 MA, unless it's a free pivot at MA=0
			var pivot_wind_facing = hex_grid.get_wind_facing(replay_facing2, ps.wind_direction)
			var pivot_base_ma = _ship_ma(ps, pivot_wind_facing)
			if pivot_base_ma == 0 or (ps.max_ma - ma_spent) <= 0:
				if not ps.free_pivot_used:
					ps.free_pivot_used = true
				else:
					ma_spent += 1
			else:
				ma_spent += 1
		replay_facing2 = step.facing

	ps.mp_spent = ma_spent
	ps.remaining_ma = max(0, ps.max_ma - ma_spent)

	# A ship starting at MA=0 can only turn, and that turn needs a Tacking roll (5.D.1): the planning
	# screen shows the chance. Ships may not turn in calm (5.D.1a).
	var start_wf = hex_grid.get_wind_facing(ship_state.facing, ps.wind_direction)
	var starts_at_ma_zero: bool = _ship_ma(ps, start_wf) == 0
	ps.is_tacking_attempt = starts_at_ma_zero and ps.wind_speed > 0

	# A turn made at MA=0 is the ship's whole move for the g-t (5.D.3 example: "it cannot move any further").
	if starts_at_ma_zero and not path_so_far.is_empty():
		var first_type = path_so_far[0].move_type
		if first_type == MovementTypes.MoveType.PORT or first_type == MovementTypes.MoveType.STARBOARD:
			ps.ma_zero_turn_ended = true
			ps.remaining_ma = 0

	# 5.E.8: a stopped ship which uses its first MP to turn can move no further that g-t.
	if ps.speed_last_turn == 0 and not path_so_far.is_empty():
		var first_move = path_so_far[0].move_type
		if first_move == MovementTypes.MoveType.PORT or first_move == MovementTypes.MoveType.STARBOARD:
			ps.ma_zero_turn_ended = true
			ps.remaining_ma = 0

	return ps


func _calculate_real_valid_hexes(
	ps: PlottingState,
	ship_state: ShipState,
	path_so_far: Array[MovementTypes.PlotStep]
) -> MovementTypes.ValidNextHexes:
	var result = MovementTypes.ValidNextHexes.new()
	# A plot that has left the map (an escape step) has no further moves.
	var terrain := TerrainMap.of(game_state.active_scenario)
	if not terrain.in_bounds(ps.current_hex) \
			or not terrain.in_bounds(HexGrid.stern_of(ps.current_hex, ps.current_facing)):
		return result
	var last_step_was_pivot = false
	if not path_so_far.is_empty():
		var last_type = path_so_far.back().move_type
		last_step_was_pivot = (last_type == MovementTypes.MoveType.PORT or last_type == MovementTypes.MoveType.STARBOARD)

	# Forward move: available if remaining_ma > 0, except where a left-over turn must come first (6.F.4)
	if ps.remaining_ma > 0 and not _pending_turn_first(ps, ship_state):
		var forward_hex = hex_grid.get_neighbor(ps.current_hex.x, ps.current_hex.y, ps.current_facing)
		if _crossing_allowed(ship_state, ps.current_hex, forward_hex):
			var forward_meta = MovementTypes.MoveMetadata.new(MovementTypes.MoveType.FORWARD, ps.current_facing, 1, forward_hex)
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

	# No turning in calm (5.D.1a)
	if ps.wind_speed <= 0:
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
	var port_facing = (ps.current_facing + 5) % 6
	var starboard_facing = (ps.current_facing + 1) % 6
	allow_port = allow_port and _steering_allows(ps, ship_state, ShipState.PORT)
	allow_starboard = allow_starboard and _steering_allows(ps, ship_state, ShipState.STARBOARD)
	if allow_port and not _turn_crossing_allowed(ship_state, ps, port_facing):
		allow_port = false
	if allow_starboard and not _turn_crossing_allowed(ship_state, ps, starboard_facing):
		allow_starboard = false

	if allow_port:
		var port_hex = hex_grid.get_neighbor(ps.current_hex.x, ps.current_hex.y, port_facing)
		var port_wf = hex_grid.get_wind_facing(port_facing, ps.wind_direction)

		var port_meta = MovementTypes.MoveMetadata.new(MovementTypes.MoveType.PORT, port_facing, pivot_cost, ps.current_hex)
		result.port = MovementTypes.ValidMove.new(port_hex, MovementTypes.MoveType.PORT, port_meta)

		if port_wf == "L":
			Trace.trace_log("MovementValidator", "Ship %s: port pivot into luffing (L) — will end movement" % ship_state.ship_id)

	if allow_starboard:
		var starboard_hex = hex_grid.get_neighbor(ps.current_hex.x, ps.current_hex.y, starboard_facing)
		var starboard_wf = hex_grid.get_wind_facing(starboard_facing, ps.wind_direction)

		var starboard_meta = MovementTypes.MoveMetadata.new(MovementTypes.MoveType.STARBOARD, starboard_facing, pivot_cost, ps.current_hex)
		result.starboard = MovementTypes.ValidMove.new(starboard_hex, MovementTypes.MoveType.STARBOARD, starboard_meta)

		if starboard_wf == "L":
			Trace.trace_log("MovementValidator", "Ship %s: starboard pivot into luffing (L) — will end movement" % ship_state.ship_id)


## Steering damage (hull #2, #3; 6.F): one turn per g-t when poor maneuvering; Rudder Jammed
## straight allows no turn, jammed to a side only turns that way; a left-over turn (6.F.4) must be
## the first MP, in its direction.
func _steering_allows(ps: PlottingState, ship_state: ShipState, side: int) -> bool:
	var max_turns: int = ship_state.max_turns_per_gt()
	if max_turns != ShipState.UNLIMITED_TURNS and ps.pivots_used >= max_turns:
		return false
	var jam: int = ship_state.rudder_jam_direction()
	if jam != ShipState.RUDDER_NOT_JAMMED and jam != side:
		return false
	if _pending_turn_first(ps, ship_state) and ship_state.pending_turn != side:
		return false
	return true


## True at the start of the plot of a ship with a turn left over from last g-t (6.F.4).
func _pending_turn_first(ps: PlottingState, ship_state: ShipState) -> bool:
	return ps.steps_plotted == 0 and ship_state.pending_turn >= 0


## Table MA at a wind facing, less the MPs lost to critical hits.
func _ship_ma(ps: PlottingState, wind_facing: String) -> int:
	var ma := _lookup_ma(ps.speed_type, ps.wind_speed, wind_facing, ps.sail_state, ps.rigging_quality)
	return maxi(ma - ps.mp_loss, 0)


## A turn pivots on the bow (5.C.2): the stern swings from its hex to the new one, and that step
## must not be refused at a typed boundary.
func _turn_crossing_allowed(ship_state: ShipState, ps: PlottingState, new_facing: int) -> bool:
	return _crossing_allowed(ship_state, HexGrid.stern_of(ps.current_hex, ps.current_facing),
			HexGrid.stern_of(ps.current_hex, new_facing))


## True when stepping `from_hex` to `to_hex` crosses no boundary, or one the ship may cross
## (an escape edge it has declared for). Land and shallows are not refused here.
func _crossing_allowed(ship_state: ShipState, from_hex: Vector2i, to_hex: Vector2i) -> bool:
	var turn := 1
	var t = game_state.get("current_turn")
	if t != null:
		turn = int(t)
	var outcome: String = MapRules.crossing_outcome(game_state.active_scenario, ship_state,
			from_hex, to_hex, turn, MapController.escape_locked(game_state, ship_state.ship_id))["outcome"]
	return outcome == MapRules.CLEAR or outcome == MapRules.ESCAPE


func _get_min_forward_for_pivot(
	ps: PlottingState,
	pivot_direction: MovementTypes.MoveType,
	_ship_state: ShipState
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
	# Luffing, dismasted or calm (wind speed 0, outside the table): no movement allowance
	return MapRules.table_ma(speed_type, wind_speed, wind_facing, sail_state, rigging_quality)
