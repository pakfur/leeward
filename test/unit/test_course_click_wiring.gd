extends GutTest
## GameController's course wiring, headless: planning draws (routes) every own ship's course, and a
## map click that a course claims goes to the server's extend / cut request instead of selecting.

const GameControllerScript = preload("res://scripts/core/game_controller.gd")
const PLANNING := TurnPhaseController.GamePhase.PLANNING

var gc: Node
var _old_phase: TurnPhaseController.GamePhase
var _old_gs_phase
var _old_ready: Array[bool]
var _old_env: EnvironmentState


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	_old_phase = GameState.phase_controller.current_phase
	_old_gs_phase = GameState.current_phase
	_old_ready = GameState.phase_controller.players_ready.duplicate()
	_old_env = GameState.environment
	GameState.environment = EnvironmentState.new()
	GameState.environment.wind_direction = 3
	GameState.environment.wind_speed = 3
	GameState.phase_controller.current_phase = PLANNING
	GameState.current_phase = GameState.GamePhase.PLANNING
	GameState.phase_controller.players_ready = [false, false] as Array[bool]
	_make_ship("a", 0, Vector2i(0, 0))
	_make_ship("b", 0, Vector2i(0, 4))
	_make_ship("enemy", 1, Vector2i(8, 8))
	gc = GameControllerScript.new()  # not in the tree: no map, overlay or panel, only the routing
	autofree(gc)


func after_each() -> void:
	GameState.phase_controller.current_phase = _old_phase
	GameState.current_phase = _old_gs_phase
	GameState.phase_controller.players_ready = _old_ready
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, player: int, hex: Vector2i) -> ShipState:
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
	state.speed = 2
	state.sail_state = "MS"
	state.crew_quality = "B"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	GameState.add_ship(state)
	return state


func test_planning_routes_every_own_course() -> void:
	gc._refresh_courses()
	assert_eq(gc._courses.keys().size(), 2, "both own ships, no enemy")
	assert_true(gc._courses.has("a") and gc._courses.has("b"))
	assert_false(gc._courses["a"]["next_hexes"].is_empty())


func test_a_routed_click_extends_then_cuts_through_the_server() -> void:
	gc._refresh_courses()
	var ahead: Vector2i = gc._courses["b"]["next_hexes"][0]
	assert_true(gc._handle_course_click(ahead), "the click is taken: no ship selection after it")
	var course := GameState.phase_controller.stored_course(GameState.get_ship("b"))
	assert_eq(course.size(), 1, "extended through player_extend_course")
	assert_eq(gc._courses["b"]["path_hexes"], [course[0].hex] as Array[Vector2i], "and redrawn")
	assert_eq(gc.selected_ship_id, "", "nothing selected on the map")
	assert_true(gc._handle_course_click(course[0].hex), "a course hex cuts")
	assert_eq(GameState.phase_controller.stored_course(GameState.get_ship("b")).size(), 0)


func test_a_click_no_course_claims_falls_through() -> void:
	gc._refresh_courses()
	assert_false(gc._handle_course_click(Vector2i(20, 20)), "open water: ship selection decides")
	GameState.current_phase = GameState.GamePhase.COMBAT_RESOLUTION
	var ahead: Vector2i = gc._courses["a"]["next_hexes"][0]
	assert_false(gc._handle_course_click(ahead), "outside planning no course takes clicks")
