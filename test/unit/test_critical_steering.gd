extends GutTest
## Movement effects of critical hits (spec phases 6 and 8): MP loss from sheets cut and shrouds
## severed (rigging #7, #9), speed-change limits (5.E.4-6, braces cut, sheets cut), steering damage
## (hull #2 rudder destroyed/jammed, hull #3 wheel shot away), the Poor Maneuvering roll (6.F.3-5)
## and the Tacking/Bearing Off chart DRMs. Expected values from the rules and the p.109/p.112-113
## charts; spec test rows are named where they apply.

const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const PORT := 0
const STARBOARD := 1

var resolver: MovementResolver
var validator: MovementValidator
var rng: RandomNumberGenerator
var env: EnvironmentState
var _saved_turn_log: PhaseEvents.PhaseLog
var _saved_env: EnvironmentState
var _saved_turn := 0
var _saved_scenario: Dictionary


func before_all() -> void:
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_turning_table()
	DataManager.load_movement_allowance_table()
	DataManager.load_speed_change_table()


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 12345
	resolver = MovementResolver.new(GameState, rng)
	validator = MovementValidator.new(GameState)
	_saved_env = GameState.environment
	_saved_turn = GameState.current_turn
	_saved_scenario = GameState.active_scenario
	GameState.active_scenario = {}
	GameState.current_turn = 5
	env = EnvironmentState.new()
	env.wind_direction = 0  # from E: facing W (3) runs, facing E (0) is head to wind
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.ships.clear()
	_saved_turn_log = GameState.turn_log
	GameState.turn_log = PhaseEvents.PhaseLog.new()


func after_each() -> void:
	GameState.turn_log = _saved_turn_log
	GameState.environment = _saved_env
	GameState.current_turn = _saved_turn
	GameState.active_scenario = _saved_scenario
	GameState.ships.clear()


func _ship(maneuverability: String = "B", crew_quality: String = "E", facing: int = 3,
		speed: int = 4, ship_id: String = "pm_ship", hex: Vector2i = Vector2i(5, 5)) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": ship_id, "player_id": 0, "ship_name": ship_id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": maneuverability, "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
	})
	state.hex_position = hex
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = crew_quality
	CrewFixtures.give_tack_crew(state, 3)  # three at the braces: no 5.D.2a DRM
	GameState.ships[ship_id] = state
	return state


func _effect(state: ShipState, id: String, turn: int = 5, side: int = -1) -> void:
	state.critical_effects.append({"seq": state.critical_seq, "id": id, "turn": turn, "side": side,
		"attempts": 0, "expires_after_turn": turn + 1 if id == "sheets_cut" else -1})
	state.critical_seq += 1


## A plot from a string: "F" ahead, "P"/"S" a turn (pivoting on the bow, 5.C.2).
func _plot(state: ShipState, code: String) -> void:
	var steps: Array = []
	var bow := state.hex_position
	var facing := state.facing
	for c in code:
		if c == "F":
			bow += HexGrid.DIRECTIONS[facing]
		else:
			facing = (facing + 5) % 6 if c == "P" else (facing + 1) % 6
		steps.append({"hex": {"q": bow.x, "r": bow.y}, "facing": facing})
	GameState.ship_controller.set_plotted_movement(state.ship_id, steps)


## The executed steps as a code ("F", "P", "S").
func _moves(result: MovementTypes.ShipResolutionResult) -> String:
	var code := ""
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.MOVE:
			if ev.facing == ev.from_facing:
				code += "F"
			else:
				code += "P" if ev.facing == (ev.from_facing + 5) % 6 else "S"
	return code


func _steering_rolls(result: MovementTypes.ShipResolutionResult) -> Array:
	return result.events.filter(func(ev): return ev.event_type == MovementTypes.ResolutionEventType.POOR_MANEUVERING_ROLL)


## A seed whose first d10s (randi_range(0, 9)) are exactly `rolls`.
func _seed_for(rolls: Array) -> int:
	for s in range(1, 200000):
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		var ok := true
		for want in rolls:
			if probe.randi_range(0, 9) != want:
				ok = false
				break
		if ok:
			return s
	fail_test("no seed found for %s" % str(rolls))
	return 1


func _run(ships: Array[ShipState], rolls: Array) -> MovementTypes.ResolutionLog:
	rng.seed = _seed_for(rolls)
	return resolver.run(ships, env)


func _path(state: ShipState, code: String) -> Array[MovementTypes.PlotStep]:
	var path: Array[MovementTypes.PlotStep] = []
	var bow := state.hex_position
	var facing := state.facing
	for c in code:
		var move_type := MovementTypes.MoveType.FORWARD
		if c == "F":
			bow += HexGrid.DIRECTIONS[facing]
		elif c == "P":
			facing = (facing + 5) % 6
			move_type = MovementTypes.MoveType.PORT
		else:
			facing = (facing + 1) % 6
			move_type = MovementTypes.MoveType.STARBOARD
		path.append(MovementTypes.PlotStep.new(bow, facing, move_type))
	return path


func _moves_at(state: ShipState, code: String) -> MovementTypes.ValidMovesResult:
	var path := _path(state, code)
	var bow: Vector2i = path.back().hex if not path.is_empty() else state.hex_position
	var facing: int = path.back().facing if not path.is_empty() else state.facing
	return validator.calculate_valid_moves(state, bow, facing, path)


# --- MP loss: sheets cut and shrouds severed (rigging #7, #9) ---

func test_shrouds_severed_costs_one_mp() -> void:
	var state := _ship()
	var before := GameState.ship_controller.get_movement_allowance(state.ship_id)
	_effect(state, "shrouds_severed")
	assert_eq(GameState.ship_controller.get_movement_allowance(state.ship_id), before - 1)


func test_row10_sheets_cut_acts_on_the_next_turn_only() -> void:
	# Rigging #7: -1 MP and -1 acceleration on the g-t after it was inflicted (type B: 2 -> 1).
	var state := _ship("B")
	var ma := GameState.ship_controller.get_movement_allowance(state.ship_id)
	_effect(state, "sheets_cut", 5)
	assert_eq(GameState.ship_controller.get_movement_allowance(state.ship_id), ma, "no effect on g-t 5")
	assert_eq(GameState.ship_controller.get_speed_change_limits(state.ship_id).accel, 2)
	GameState.current_turn = 6
	assert_eq(GameState.ship_controller.get_movement_allowance(state.ship_id), ma - 1, "g-t 6: -1 MP")
	assert_eq(GameState.ship_controller.get_speed_change_limits(state.ship_id).accel, 1, "g-t 6: accel 2 -> 1")


func test_row13_shrouds_and_sheets_with_three_sections_left() -> void:
	# Majestic G-T 17: three rigging sections left, shrouds severed and sheets cut: MA -2.
	var state := _ship()
	state.rigging_current_hp = [0, 5, 6, 6] as Array[int]
	var ma := GameState.ship_controller.get_movement_allowance(state.ship_id)
	_effect(state, "shrouds_severed", 4)
	_effect(state, "sheets_cut", 4)
	assert_eq(GameState.ship_controller.get_movement_allowance(state.ship_id), ma - 2)


func test_two_sheets_cut_cost_one_mp() -> void:
	# Rigging #7: at most one sheets cut counts.
	var state := _ship()
	var ma := GameState.ship_controller.get_movement_allowance(state.ship_id)
	_effect(state, "sheets_cut", 4)
	_effect(state, "sheets_cut", 4)
	assert_eq(GameState.ship_controller.get_movement_allowance(state.ship_id), ma - 1)


func test_mp_loss_comes_before_blocked_wind() -> void:
	# 5.G.3: blocked wind is applied after every other change. Table MA 2, shrouds -1 = 1, and
	# blocked wind then leaves it at 1 (it never lowers MA 1); the other order would give 0.
	var state := _ship("B", "E", 3, 0)
	var found := false
	for ws in [1, 2, 3, 4]:
		for level in [4, 3, 2, 1]:
			if not found and DataManager.get_movement_allowance("F/F", ws, "R", "fs", level) == 2:
				env.wind_speed = ws
				state.sail_state = "FS"
				var rigging: Array[int] = [5, 5, 6, 6]
				for i in range(4 - level):
					rigging[i] = 0
				state.rigging_current_hp = rigging
				found = true
	assert_true(found, "fixture: a table MA of 2 running")
	# Running W with the wind from E: the stern (6,5) has its windward hex (7,5) held by a ship at FS.
	var blocker := _ship("B", "E", 3, 0, "blocker", Vector2i(7, 5))
	blocker.sail_state = "FS"
	assert_true(BlockedWind.is_blocked(state.hex_position, state.facing, env.wind_direction,
		GameState.ships.values(), state.ship_id), "fixture: wind blocked")
	assert_eq(GameState.ship_controller.get_movement_allowance(state.ship_id), 1, "blocked: 2 -> 1")
	_effect(state, "shrouds_severed")
	assert_eq(GameState.ship_controller.get_movement_allowance(state.ship_id), 1,
		"shrouds first (2 -> 1), then blocked wind leaves 1")


func test_validator_plots_with_the_mp_loss() -> void:
	var state := _ship("A", "E", 3, 6)  # running at WS 3, MS: MA 7 is reachable from speed 6
	var free := _moves_at(state, "")
	_effect(state, "shrouds_severed")
	var lost := _moves_at(state, "")
	assert_eq(lost.remaining_ma, free.remaining_ma - 1)


# --- Speed change limits (5.E.4-6) ---

func test_speed_change_limits_are_the_table_value() -> void:
	var state := _ship("B")
	assert_eq(GameState.ship_controller.get_speed_change_limits(state.ship_id), {"accel": 2, "decel": 3},
		"5.E.4 example 1: type B accelerates 2, decelerates 3")


func test_two_rigging_sections_lost_reduce_acceleration() -> void:
	# 5.E.5 example: type B with two rigging sections left accelerates by 1.
	var state := _ship("B")
	state.rigging_current_hp = [0, 0, 6, 6] as Array[int]
	assert_eq(GameState.ship_controller.get_speed_change_limits(state.ship_id).accel, 1)


func test_acceleration_reductions_never_below_one() -> void:
	# 5.E.5 example: type B, two sections left and towing: still 1.
	var state := _ship("B")
	state.rigging_current_hp = [0, 0, 6, 6] as Array[int]
	state.towing_id = "tow"
	assert_eq(GameState.ship_controller.get_speed_change_limits(state.ship_id).accel, 1)


func test_wind_speed_one_reduces_acceleration() -> void:
	var state := _ship("C")
	env.wind_speed = 1
	assert_eq(GameState.ship_controller.get_speed_change_limits(state.ship_id),
		{"accel": DataManager.get_speed_change("acceleration", "c") - 1,
		"decel": DataManager.get_speed_change("deceleration", "c")}, "5.E.5: acceleration only")


func test_row12_braces_cut_limits_accel_and_decel_to_one() -> void:
	# Rigging #4 and 5.E.5: type C (accel 3) with braces cut: accel 1, decel 1.
	var state := _ship("C")
	_effect(state, "braces_cut")
	assert_eq(GameState.ship_controller.get_speed_change_limits(state.ship_id), {"accel": 1, "decel": 1})


func test_sheets_cut_can_reach_zero() -> void:
	# 5.E.6 example 2: type C, one rigging section left (-1), braces cut (1), sheets cut: 0.
	var state := _ship("C")
	state.rigging_current_hp = [0, 0, 0, 6] as Array[int]
	_effect(state, "braces_cut")
	_effect(state, "sheets_cut", 4)
	assert_eq(GameState.ship_controller.get_speed_change_limits(state.ship_id).accel, 0)


func test_validator_uses_the_limits() -> void:
	# Type B at speed 2 with braces cut: may use 1 to 3 MPs (decel 1, accel 1).
	var state := _ship("B", "E", 3, 2)
	_effect(state, "braces_cut")
	var ps := validator._build_plotting_state(state, state.hex_position, state.facing, [])
	assert_eq(ps.min_ma, 1)
	assert_eq(ps.max_ma, 3)


func test_deceleration_minimum_uses_braces_cut() -> void:
	var state := _ship("B", "E", 3, 4)
	assert_eq(resolver._deceleration_minimum(state), 1, "4 - 3")
	_effect(state, "braces_cut")
	assert_eq(resolver._deceleration_minimum(state), 3, "4 - 1")


# --- Steering in the validator (hull #2, #3) ---

func test_row29_wheel_shot_away_allows_one_turn() -> void:
	# Hull #3: one 60-degree turn per g-t. After P1 no second turn is offered.
	var state := _ship("A", "B", 3, 4)
	state.wheel_shot_away = true
	var first := _moves_at(state, "")
	assert_not_null(first.valid_hexes.port, "the first turn is allowed")
	var after := _moves_at(state, "PF")
	assert_null(after.valid_hexes.port, "no second turn")
	assert_null(after.valid_hexes.starboard, "no second turn")
	assert_false(after.valid_hexes.forward.is_empty(), "ahead still allowed")


func test_rudder_jammed_straight_allows_no_turn() -> void:
	var state := _ship("A", "B", 3, 4)
	_effect(state, "rudder_jammed", 4, -1)
	var moves := _moves_at(state, "F")
	assert_null(moves.valid_hexes.port)
	assert_null(moves.valid_hexes.starboard)


func test_rudder_jammed_to_port_turns_only_to_port() -> void:
	var state := _ship("A", "B", 3, 4)
	_effect(state, "rudder_jammed", 4, PORT)
	var moves := _moves_at(state, "")
	assert_not_null(moves.valid_hexes.port)
	assert_null(moves.valid_hexes.starboard)


func test_rudder_jammed_to_port_must_turn_when_moving() -> void:
	# Hull #2: a moving ship must turn at least once the jammed way; a ship that stops need not.
	var state := _ship("A", "B", 3, 4)
	_effect(state, "rudder_jammed", 4, PORT)
	assert_false(validator.validate_submission(state, _path(state, "FF")).can_submit)
	assert_eq(validator.validate_submission(state, _path(state, "FF")).error_code, "RUDDER_JAMMED")
	assert_false(_moves_at(state, "FF").can_submit, "the panel cannot submit either")
	assert_true(validator.validate_submission(state, _path(state, "FPF")).can_submit)
	# Stopping is still bound by the deceleration limit (5.E.4): speed 4, type A decelerates 2.
	assert_eq(validator.validate_submission(state, _path(state, "")).error_code, "TOO_SLOW")
	state.speed = 2
	assert_true(validator.validate_submission(state, _path(state, "")).can_submit, "2 - 2: may stop")


func test_rudder_destroyed_cancels_the_jam() -> void:
	var state := _ship("A", "B", 3, 4)
	_effect(state, "rudder_jammed", 4, -1)
	state.rudder_destroyed = true
	assert_not_null(_moves_at(state, "").valid_hexes.starboard)


func test_pending_turn_must_be_the_first_move() -> void:
	# 6.F.4: the turn left over from last g-t is the first MP.
	var state := _ship("A", "B", 3, 4)
	state.wheel_shot_away = true
	state.pending_turn = STARBOARD
	var moves := _moves_at(state, "")
	assert_not_null(moves.valid_hexes.starboard)
	assert_null(moves.valid_hexes.port)
	assert_true(moves.valid_hexes.forward.is_empty(), "no step ahead before the left-over turn")


# --- Poor maneuvering in the resolver (6.F.3-5) ---

func test_row27_failed_turn_moves_one_hex_ahead_first() -> void:
	# 6.F.3 example: type B, CQ E (needs <= 4), plot S2S, d10 5: the plot becomes 1S2.
	var state := _ship("B", "E", 3, 4)
	state.wheel_shot_away = true
	_plot(state, "SFFS")
	var result := _run([state] as Array[ShipState], [5]).get_result(state.ship_id)
	assert_eq(_moves(result), "FSFF")
	var rolls := _steering_rolls(result)
	assert_eq(rolls.size(), 1, "the second turn is never rolled for")
	assert_eq(int(rolls[0].roll), 5)
	assert_eq(int(rolls[0].threshold), 4)
	assert_false(rolls[0].success)
	assert_eq(result.pending_turn, -1, "6.F.4 example 2: no turn carried over")


func test_successful_roll_turns_as_plotted() -> void:
	var state := _ship("B", "E", 3, 4)
	state.wheel_shot_away = true
	_plot(state, "FSFF")
	var result := _run([state] as Array[ShipState], [4]).get_result(state.ship_id)
	assert_eq(_moves(result), "FSFF")
	assert_true(_steering_rolls(result)[0].success)


func test_row28_failed_last_mp_turn_carries_over() -> void:
	# 6.F.4 example 1: plot 4S, the turn fails: the ship moves 5 and S is next g-t's first MP.
	var state := _ship("B", "E", 3, 5)
	state.wheel_shot_away = true
	_plot(state, "FFFFS")
	var ships: Array[ShipState] = [state]
	var log := _run(ships, [9])
	var result := log.get_result(state.ship_id)
	assert_eq(_moves(result), "FFFFF")
	assert_eq(result.pending_turn, STARBOARD)
	resolver.apply_results(log, ships)
	assert_eq(state.pending_turn, STARBOARD)
	assert_eq(state.speed, 5)
	# Next g-t: the left-over turn needs no roll.
	_plot(state, "SFFF")
	var next := _run(ships, [9]).get_result(state.ship_id)
	assert_eq(_moves(next), "SFFF")
	assert_true(_steering_rolls(next).is_empty(), "the left-over turn succeeds automatically")
	assert_eq(next.pending_turn, -1)


func test_rudder_destroyed_keeps_rolling_each_hex() -> void:
	# Hull #2: rudder destroyed rolls again at each further hex until it succeeds.
	var state := _ship("B", "E", 3, 4)
	state.rudder_destroyed = true
	_plot(state, "SFFF")
	var result := _run([state] as Array[ShipState], [7, 8, 2]).get_result(state.ship_id)
	assert_eq(_moves(result), "FFSF")
	var rolls := _steering_rolls(result)
	assert_eq(rolls.map(func(ev): return int(ev.roll)), [7, 8, 2])
	assert_eq(rolls.map(func(ev): return ev.impulse), [0, 1, 2])


func test_poor_maneuvering_rolls_land_on_the_slower_ships_segments() -> void:
	# Unequal paces: the steering ship plots 3 (steps at 1/3, 2/3, 1), the other 6 (1/6 ... 1), so the
	# segments are 1/6, 1/3, 1/2, 2/3, 5/6, 1. Its rolls at steps 0 and 1 fall on segments 1 and 3.
	var state := _ship("B", "E", 3, 4)
	state.rudder_destroyed = true
	_plot(state, "SFF")
	var other := _ship("B", "E", 3, 6, "other", Vector2i(14, 12))
	_plot(other, "FFFFFF")
	var log := _run([state, other] as Array[ShipState], [7, 2])
	var result := log.get_result(state.ship_id)
	assert_eq(_moves(result), "FSF")
	var rolls := _steering_rolls(result)
	assert_eq(rolls.map(func(ev): return ev.impulse), [1, 3], "each roll on the segment of its step")
	assert_eq(rolls.map(func(ev): return ev.time), [Vector2i(1, 3), Vector2i(2, 3)])
	var moves: Array = result.events.filter(func(ev): return ev.event_type == MovementTypes.ResolutionEventType.MOVE)
	assert_eq(moves.map(func(ev): return ev.impulse), [1, 3, 5], "the moves on the same segments")
	assert_true(_steering_rolls(log.get_result("other")).is_empty())


func test_wheel_shot_away_turns_after_one_hex() -> void:
	# Hull #3: the wheel turns after the one extra hex, without another roll.
	var state := _ship("B", "E", 3, 4)
	state.wheel_shot_away = true
	_plot(state, "SFFF")
	var result := _run([state] as Array[ShipState], [7, 8]).get_result(state.ship_id)
	assert_eq(_moves(result), "FSFF")
	assert_eq(_steering_rolls(result).size(), 1)


func test_poor_maneuvering_roll_is_logged() -> void:
	var state := _ship("B", "E", 3, 4)
	state.wheel_shot_away = true
	_plot(state, "SFFS")
	var ships: Array[ShipState] = [state]
	var log := _run(ships, [5])
	resolver.apply_results(log, ships)
	var events := GameState.turn_log.of_type(PhaseEvents.Type.POOR_MANEUVERING)
	assert_eq(events.size(), 1)
	assert_eq(events[0].data, {"roll": 5, "needed": 4, "success": false, "outcome": "one hex ahead"})
	assert_eq(events[0].to_text({"pm_ship": "Vengeance"}),
		"Vengeance's damaged steering fails the turn (5 > 4) — one hex ahead")


func test_steering_rolls_are_reproduced_by_replays() -> void:
	# The rolls come from the resolver's rng before the passes: the same seed gives the same plot.
	var state := _ship("B", "E", 3, 4)
	state.rudder_destroyed = true
	_plot(state, "SFFF")
	var seed_value := _seed_for([7, 8, 2])
	rng.seed = seed_value
	var first := _moves(resolver.run([state] as Array[ShipState], env).get_result(state.ship_id))
	rng.seed = seed_value
	var second := _moves(resolver.run([state] as Array[ShipState], env).get_result(state.ship_id))
	assert_eq(first, second)


func test_ma_zero_turn_needs_both_rolls() -> void:
	# 6.F.5: at MA 0 the ship rolls Poor Maneuvering and Tacking; both must succeed. A failure does
	# not move it ahead, and next g-t it rolls only on the Tacking table.
	var state := _ship("D", "E", 0, 2)  # head to wind (WF=L), luffed last g-t: not in irons
	state.wheel_shot_away = true
	_plot(state, "S")
	var ships: Array[ShipState] = [state]
	# PM needs <= 5 (CQ E, type D): 9 fails. Tacking (D at WS 3: <= 9, SK +1): 3 passes.
	var log := _run(ships, [9, 3])
	var result := log.get_result(state.ship_id)
	assert_eq(_moves(result), "", "no turn")
	assert_true(result.tacking_failed)
	assert_eq(_steering_rolls(result).size(), 1)
	assert_eq(result.pending_turn, STARBOARD)
	resolver.apply_results(log, ships)
	# Next g-t: only the Tacking roll.
	_plot(state, "S")
	var next := _run(ships, [3]).get_result(state.ship_id)
	assert_eq(_moves(next), "S")
	assert_true(_steering_rolls(next).is_empty())


func test_ma_zero_poor_maneuvering_roll_is_at_start() -> void:
	var state := _ship("D", "E", 0, 2)
	state.wheel_shot_away = true
	_plot(state, "S")
	var log := _run([state] as Array[ShipState], [9, 3])
	var rolls := _steering_rolls(log.get_result(state.ship_id))
	assert_eq(rolls.size(), 1)
	if rolls.size() == 1:
		assert_eq(rolls[0].time, MoveSchedule.START)


func test_ma_zero_left_over_turn_failing_its_tack_resets() -> void:
	# 6.F.5: a failed Tacking roll on the second g-t resets the condition.
	var state := _ship("A", "E", 0, 0)
	state.wheel_shot_away = true
	state.rigging_current_hp = [0, 0, 0, 6] as Array[int]  # +6: only a natural 0 tacks
	env.wind_speed = 1
	state.pending_turn = STARBOARD
	_plot(state, "S")
	var result := _run([state] as Array[ShipState], [5]).get_result(state.ship_id)
	assert_true(result.tacking_failed)
	assert_true(_steering_rolls(result).is_empty())
	assert_eq(result.pending_turn, -1)


func test_rudder_destroyed_entering_wind_facing_l_is_in_irons() -> void:
	# Hull #2: a ship with its rudder destroyed that enters WF=L is in irons at once.
	var state := _ship("B", "E", 1, 2)  # facing SE, wind from E: a port turn heads into the wind
	state.rudder_destroyed = true
	_plot(state, "FP")
	var ships: Array[ShipState] = [state]
	var log := _run(ships, [0])
	assert_eq(_moves(log.get_result(state.ship_id)), "FP")
	resolver.apply_results(log, ships)
	assert_eq(state.facing, 0)
	assert_eq(state.speed, 0, "stopped: in irons")
	assert_true(resolver._is_in_irons(state, env))
	var irons := GameState.turn_log.of_type(PhaseEvents.Type.IN_IRONS)
	assert_eq(irons.size(), 1)
	assert_eq(irons[0].data["cause"], "rudder")


func test_apply_results_records_the_last_step_direction() -> void:
	var state := _ship("B", "E", 3, 4)
	_plot(state, "FFPF")
	var ships: Array[ShipState] = [state]
	resolver.apply_results(_run(ships, []), ships)
	assert_eq(state.last_step_direction, -1, "last step ahead")
	_plot(state, "FFS")
	resolver.apply_results(_run(ships, []), ships)
	assert_eq(state.last_step_direction, STARBOARD)
	_plot(state, "")
	resolver.apply_results(_run(ships, []), ships)
	assert_eq(state.last_step_direction, STARBOARD, "kept through a g-t with no step (spec Q15)")


# --- Tacking and Bearing Off DRMs (p.109) ---

func test_row30_tacking_drm_rudder_destroyed() -> void:
	var state := _ship("B", "B", 3, 3)  # SK -2, not at WF=L -2
	var base := resolver._calculate_tacking_drm(state)
	state.rudder_destroyed = true
	assert_eq(resolver._calculate_tacking_drm(state), base + 3)


func test_row31_bearing_off_drm_rudder_destroyed_is_four() -> void:
	# Bearing Off chart: Rudder Destroyed/Jammed +3, Poor Maneuvering +1 (spec Q9).
	var state := _ship()
	state.rudder_destroyed = true
	assert_eq(resolver._bearing_off_drm(state, 2), 4)


func test_bearing_off_drm_rudder_jammed_and_wheel() -> void:
	var jammed := _ship()
	_effect(jammed, "rudder_jammed", 4, PORT)
	assert_eq(resolver._bearing_off_drm(jammed, 2), 3)
	var wheel := _ship("B", "E", 3, 4, "wheel_ship", Vector2i(10, 10))
	wheel.wheel_shot_away = true
	assert_eq(resolver._bearing_off_drm(wheel, 5), 2, "4-6 MPs +1, poor maneuvering +1")


func test_poor_maneuvering_chance() -> void:
	var state := _ship("B", "E")
	assert_eq(resolver.poor_maneuvering_chance(state), 1.0, "sound steering")
	state.wheel_shot_away = true
	assert_almost_eq(resolver.poor_maneuvering_chance(state), 0.5, 0.001, "d10 <= 4")


# --- Planning text ---

func test_steering_note() -> void:
	assert_eq(PlanningText.steering_note(false, 1.0, -1, ShipState.RUDDER_NOT_JAMMED, false), "")
	assert_eq(PlanningText.steering_note(true, 0.5, -1, ShipState.RUDDER_NOT_JAMMED, false),
		"Wheel shot away: one 60° turn per game turn, 50% to turn as plotted (else one hex ahead first).")
	assert_string_contains(PlanningText.steering_note(true, 0.5, STARBOARD, ShipState.RUDDER_NOT_JAMMED, true),
		"Left-over turn to starboard")
	assert_eq(PlanningText.steering_note(false, 1.0, -1, PORT, false),
		"Rudder jammed to port: turns only that way, at least once if moving.")
	assert_eq(PlanningText.steering_note(false, 1.0, -1, -1, false), "Rudder jammed amidships: no turns.")
