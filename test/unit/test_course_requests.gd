extends GutTest
## Course editing requests on TurnPhaseController: player_extend_course, player_cut_course,
## course_options (stateless: no plotting session).

const PLANNING := TurnPhaseController.GamePhase.PLANNING
const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION

var ship: ShipState
var _old_phase: TurnPhaseController.GamePhase
var _old_ready: Array[bool]
var _old_env: EnvironmentState


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_old_phase = GameState.phase_controller.current_phase
	_old_ready = GameState.phase_controller.players_ready.duplicate()
	_old_env = GameState.environment
	GameState.environment = EnvironmentState.new()
	GameState.environment.wind_direction = 3  # from the west: a ship facing east runs before it
	GameState.environment.wind_speed = 3
	GameState.phase_controller.current_phase = PLANNING
	GameState.phase_controller.players_ready = [false, false] as Array[bool]
	ship = _make_ship("own", 0, Vector2i(5, 5))


func after_each() -> void:
	GameState.phase_controller.current_phase = _old_phase
	GameState.phase_controller.players_ready = _old_ready
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, player: int, hex: Vector2i, facing: int = 0) -> ShipState:
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
	state.speed = 2
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


func _ahead(hex: Vector2i, facing: int) -> Vector2i:
	return HexGrid.new().get_neighbor(hex.x, hex.y, facing)


func test_extend_appends_a_valid_move_and_stores_it() -> void:
	var target := _ahead(ship.hex_position, 0)
	assert_eq(_pc().player_extend_course(0, "own", target), "")
	var course := _pc().stored_course(ship)
	assert_eq(course.size(), 1)
	assert_eq(course[0].hex, target)
	assert_true(ship.plotted_actions["movement_plotted"])


func test_extend_refuses_an_invalid_hex_and_keeps_the_course() -> void:
	_pc().player_extend_course(0, "own", _ahead(ship.hex_position, 0))
	var before: Array = ship.plotted_actions["movement"].duplicate(true)
	assert_ne(_pc().player_extend_course(0, "own", Vector2i(40, 40)), "")
	assert_eq(ship.plotted_actions["movement"], before)


func test_extend_refused_outside_planning_after_ready_or_for_another_players_ship() -> void:
	var target := _ahead(ship.hex_position, 0)
	GameState.phase_controller.current_phase = MOVE
	assert_ne(_pc().player_extend_course(0, "own", target), "")
	GameState.phase_controller.current_phase = PLANNING
	GameState.phase_controller.players_ready = [true, false] as Array[bool]
	assert_ne(_pc().player_extend_course(0, "own", target), "")
	GameState.phase_controller.players_ready = [false, false] as Array[bool]
	assert_ne(_pc().player_extend_course(1, "own", target), "")
	assert_true(_pc().stored_course(ship).is_empty())


func test_extend_refused_for_a_fouled_ship() -> void:
	var other := _make_ship("other", 1, Vector2i(5, 8))
	ship.fouled_with = other.ship_id
	assert_ne(_pc().player_extend_course(0, "own", _ahead(ship.hex_position, 0)), "")
	assert_true(_pc().stored_course(ship).is_empty())
	assert_true(_pc().course_options("own").is_empty())


func test_cut_at_last_step_removes_one_step() -> void:
	_pc().player_extend_course(0, "own", _ahead(ship.hex_position, 0))
	var first: Vector2i = _pc().stored_course(ship)[0].hex
	_pc().player_extend_course(0, "own", _ahead(first, 0))
	assert_eq(_pc().stored_course(ship).size(), 2)
	assert_eq(_pc().player_cut_course(0, "own", 1), "")
	var course := _pc().stored_course(ship)
	assert_eq(course.size(), 1)
	assert_eq(course[0].hex, first)


func test_cut_at_zero_clears_the_course() -> void:
	_pc().player_extend_course(0, "own", _ahead(ship.hex_position, 0))
	assert_eq(_pc().player_cut_course(0, "own", 0), "")
	assert_eq(ship.plotted_actions["movement"], [])
	assert_true(ship.plotted_actions["movement_plotted"])


func test_cut_out_of_range_is_refused() -> void:
	_pc().player_extend_course(0, "own", _ahead(ship.hex_position, 0))
	assert_ne(_pc().player_cut_course(0, "own", 2), "")
	assert_ne(_pc().player_cut_course(0, "own", -1), "")
	assert_eq(_pc().stored_course(ship).size(), 1)


func test_extend_after_a_turn_continues_from_the_new_facing() -> void:
	# Plot a turn: the course options name the valid turn hexes.
	var opts := _pc().course_options("own")
	var turn_move: MovementTypes.ValidMove = opts["valid_next"].starboard
	if turn_move == null:
		turn_move = opts["valid_next"].port
	assert_not_null(turn_move, "a turn must be available")
	assert_eq(_pc().player_extend_course(0, "own", turn_move.hex), "")
	var turned := _pc().stored_course(ship)[0]
	assert_ne(turned.facing, ship.facing)
	assert_eq(_pc().player_extend_course(0, "own", _ahead(turned.hex, turned.facing)), "")
	var course := _pc().stored_course(ship)
	assert_eq(course.size(), 2)
	assert_eq(course[1].facing, turned.facing)


func test_course_options_lists_next_hexes_from_the_course_end() -> void:
	var opts := _pc().course_options("own")
	assert_eq(opts["path"].size(), 0)
	assert_eq(opts["valid_next"].forward[0].hex, _ahead(ship.hex_position, 0))
	_pc().player_extend_course(0, "own", _ahead(ship.hex_position, 0))
	var end: Vector2i = _pc().stored_course(ship)[0].hex
	opts = _pc().course_options("own")
	assert_eq(opts["path"].size(), 1)
	assert_eq(opts["valid_next"].forward[0].hex, _ahead(end, 0))
	assert_true(opts.has("remaining_ma"))
	assert_true(opts.has("is_tacking_attempt"))
	assert_eq(opts["rudder_error"], "")


func test_course_options_count_the_mp_a_turn_spends() -> void:
	# Ahead, a turn, ahead: three movement points, the turn included; used and left add up to the
	# allowance at the course-end heading.
	var opts := _pc().course_options("own")
	assert_eq(opts["mp_used"], 0)
	assert_eq(opts["start_max_ma"], opts["max_ma"], "no course: start and end headings are the same")
	assert_eq(_pc().player_extend_course(0, "own", _ahead(ship.hex_position, 0)), "")
	opts = _pc().course_options("own")
	var turn: MovementTypes.ValidMove = opts["valid_next"].starboard
	assert_not_null(turn, "a starboard turn must be offered")
	assert_eq(_pc().player_extend_course(0, "own", turn.hex), "")
	var turned := _pc().stored_course(ship)[1]
	assert_eq(_pc().player_extend_course(0, "own", _ahead(turned.hex, turned.facing)), "")
	opts = _pc().course_options("own")
	assert_eq(opts["path"].size(), 3)
	assert_eq(opts["mp_used"], 3, "two aheads and the turn")
	assert_eq(opts["mp_used"] + opts["remaining_ma"], opts["max_ma"], "used and left add up")
