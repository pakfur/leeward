extends GutTest
## 5.E.4 deceleration limit: a plot must use at least last turn's speed less the ship's
## deceleration, unless the ship can use no more MPs where its plot ends (5.E.9). Enforced at End
## Planning (TurnPhaseController.player_submit_plan / plan_errors) and on AI submissions.
## The ship is maneuver type C (deceleration 3), F/F at MS; wind 3 from the west, so facing 0 (E)
## is R (MA 7), 5 (NE) is B (MA 8), 4 (NW) is C (MA 5) and 3 (W) is head to wind.

const PLANNING := TurnPhaseController.GamePhase.PLANNING

var ship: ShipState
var validator: MovementValidator
var _old_phase: TurnPhaseController.GamePhase
var _old_ready: Dictionary
var _old_env: EnvironmentState
var _old_scenario: Dictionary


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	_old_phase = GameState.phase_controller.current_phase
	_old_ready = GameState.phase_controller.players_ready.duplicate()
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	GameState.active_scenario = {}  # no map bounds left over from another test
	GameState.environment = EnvironmentState.new()
	GameState.environment.wind_direction = 3
	GameState.environment.wind_speed = 3
	GameState.phase_controller.current_phase = PLANNING
	GameState.phase_controller.players_ready = {0: false, 1: false}
	ship = _make_ship("own", 0, Vector2i(5, 5), 0, 6)
	validator = MovementValidator.new(GameState)


func after_each() -> void:
	GameState.phase_controller.current_phase = _old_phase
	GameState.phase_controller.players_ready = _old_ready
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, player: int, hex: Vector2i, facing: int, speed: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	state.crew_quality = "B"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	GameState.add_ship(state)
	return state


func _pc() -> TurnPhaseController:
	return GameState.phase_controller


## Extends the stored course `n` times ahead from its end.
func _ahead(n: int) -> void:
	for _i in range(n):
		var path := _pc().stored_course(ship)
		var end: Vector2i = path[-1].hex if not path.is_empty() else ship.hex_position
		var facing: int = path[-1].facing if not path.is_empty() else ship.facing
		assert_eq(_pc().player_extend_course(0, ship.ship_id,
			HexGrid.new().get_neighbor(end.x, end.y, facing)), "", "ahead step")


## Extends the stored course ahead until the server offers a turn to `new_facing`, then takes it.
func _turn_to(new_facing: int) -> void:
	for _i in range(8):
		var vnh: MovementTypes.ValidNextHexes = _pc().course_options(ship.ship_id)["valid_next"]
		for turn in [vnh.port, vnh.starboard]:
			if turn != null and turn.metadata.resulting_facing == new_facing:
				assert_eq(_pc().player_extend_course(0, ship.ship_id, turn.hex), "", "turn")
				return
		_ahead(1)
	fail_test("no turn to %d offered" % new_facing)


## Extends the stored course ahead while a move ahead is offered.
func _ahead_to_the_end() -> void:
	for _i in range(20):
		var options := _pc().course_options(ship.ship_id)
		if (options["valid_next"] as MovementTypes.ValidNextHexes).forward.is_empty():
			return
		_ahead(1)


func _shortfall() -> int:
	return validator.deceleration_shortfall(ship, _pc().stored_course(ship))


func test_5e4_a_course_must_use_speed_less_deceleration() -> void:
	# Speed 6, deceleration 3: at least 3 MPs.
	assert_eq(_shortfall(), 3, "no course: 3 short")
	_ahead(1)
	assert_eq(_shortfall(), 2)
	_ahead(2)
	assert_eq(_shortfall(), 0, "3 MPs meets the limit")


func test_5e4_refusal_names_the_minimum() -> void:
	_ahead(1)
	var why := validator.deceleration_error(ship, _pc().stored_course(ship))
	assert_string_contains(why, "at least 3 MP")
	assert_string_contains(why, "speed 6")
	assert_string_contains(why, "deceleration 3")
	_ahead(2)
	assert_eq(validator.deceleration_error(ship, _pc().stored_course(ship)), "")


func test_5e7_stopped_ship_has_no_minimum() -> void:
	ship.speed = 0
	assert_eq(_shortfall(), 0)


func test_5e9_allowance_wins_over_the_limit() -> void:
	# Speed 9 last turn, now at fighting sail running (MA 5): the limit says 6, the allowance 5.
	ship.speed = 9
	ship.sail_state = "FS"
	var options := _pc().course_options(ship.ship_id)
	assert_eq(int(options["max_ma"]), 5, "the allowance is not raised to the deceleration limit")
	assert_eq(_shortfall(), 5, "short of what it can use")
	_ahead_to_the_end()
	options = _pc().course_options(ship.ship_id)
	assert_eq(int(options["mp_used"]), 5)
	assert_eq(_shortfall(), 0, "5.E.9: out of MPs")
	assert_eq(str(options["speed_error"]), "")


func test_5e9_turning_head_to_wind_ends_the_move() -> void:
	# Close-hauled at speed 6 (limit 3): the turn to port puts it head to wind, and it moves no further.
	ship.facing = 4
	_turn_to(3)
	assert_eq(_pc().stored_course(ship)[-1].facing, 3, "head to wind")
	assert_eq(_shortfall(), 0)


func test_end_planning_refuses_a_short_course() -> void:
	_ahead(1)
	assert_false(_pc().player_submit_plan(0), "1 MP of 3")
	assert_false(_pc().players_ready[0])
	assert_true(_pc().plan_errors(0).has("own"))
	_ahead(2)
	assert_eq(_pc().plan_errors(0), {})
	assert_true(_pc().player_submit_plan(0))
	assert_true(_pc().players_ready[0])


func test_end_planning_refuses_a_cleared_course() -> void:
	_ahead(3)
	assert_eq(_pc().player_cut_course(0, "own", 0), "", "cutting below the limit is allowed")
	assert_false(_pc().player_submit_plan(0), "an empty course stops dead from speed 6")


func test_unplotted_ship_sails_its_default_course() -> void:
	# No course stored: the resolver sails the default course (6.G.2), which keeps last speed.
	assert_true(_pc().player_submit_plan(0))


func test_enemy_short_course_does_not_block_this_player() -> void:
	var enemy := _make_ship("enemy", 1, Vector2i(20, 20), 0, 6)
	GameState.ship_controller.set_plotted_movement(enemy.ship_id, [])
	assert_true(_pc().player_submit_plan(0))


func test_course_options_carry_the_speed_error() -> void:
	_ahead(1)
	assert_string_contains(str(_pc().course_options("own")["speed_error"]), "Too slow")
	_ahead(2)
	assert_eq(str(_pc().course_options("own")["speed_error"]), "")


func test_submission_validation_refuses_too_slow() -> void:
	var path: Array[MovementTypes.PlotStep] = []
	var result := validator.validate_submission(ship, path)
	assert_false(result.can_submit)
	assert_eq(result.error_code, "TOO_SLOW")
	var moves := validator.calculate_valid_moves(ship, ship.hex_position, ship.facing, path)
	assert_false(moves.can_submit, "the plotting session may not submit it either")


func test_resolver_minimum_never_exceeds_the_allowance() -> void:
	ship.speed = 20
	var resolver := MovementResolver.new(GameState)
	assert_eq(resolver._deceleration_minimum(ship), GameState.ship_controller.get_movement_allowance("own"),
		"5.E.9: 20 - 3 capped at the allowance")


func test_card_warning_lists_the_speed_error_last() -> void:
	assert_eq(CourseView.warning_text("", "Collision risk", "Rudder jammed", "Too slow"),
		"Collision risk\nRudder jammed\nToo slow")
	assert_eq(CourseView.warning_text("", "", "", "Too slow"), "Too slow")

