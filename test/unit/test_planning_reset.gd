extends GutTest
## Planning start: default courses for human ships, the planning snapshot, Cancel (reset planning)
## and Reset course.

const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const PLANNING := TurnPhaseController.GamePhase.PLANNING

var ship: ShipState
var _old_phase: TurnPhaseController.GamePhase
var _old_ready: Array[bool]
var _old_env: EnvironmentState
var _old_humans: Array[int]
var _old_ai: Array[int]
var _old_stub_ai: Variant


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	_old_phase = GameState.phase_controller.current_phase
	_old_ready = GameState.phase_controller.players_ready.duplicate()
	_old_humans = _pc().human_player_ids.duplicate()
	_old_ai = _pc().ai_player_ids.duplicate()
	_old_stub_ai = GameState.stub_ai
	_old_env = GameState.environment
	GameState.stub_ai = null
	GameState.environment = EnvironmentState.new()
	GameState.environment.wind_direction = 3
	GameState.environment.wind_speed = 3
	_pc().human_player_ids = [0] as Array[int]
	_pc().ai_player_ids = [] as Array[int]
	_pc().current_phase = PLANNING
	_pc().players_ready = [false, false] as Array[bool]
	ship = _make_ship("own", 0, Vector2i(5, 5))


func after_each() -> void:
	_pc().current_phase = _old_phase
	_pc().players_ready = _old_ready
	_pc().human_player_ids = _old_humans
	_pc().ai_player_ids = _old_ai
	_pc().planning_snapshot = {}
	GameState.stub_ai = _old_stub_ai
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


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


func test_planning_start_stores_the_default_course_for_human_ships() -> void:
	_pc()._enter_planning_phase()
	assert_eq(ship.plotted_actions["movement"].size(), 2)
	assert_true(ship.plotted_actions["movement_plotted"])
	assert_eq(_pc().planning_snapshot["own"]["course"], ship.plotted_actions["movement"])
	assert_eq(_pc().start_of_turn_course("own"), ship.plotted_actions["movement"])


func test_planning_start_skips_ships_that_cannot_plot() -> void:
	ship.fouled_with = "x"
	_pc()._enter_planning_phase()
	assert_eq(ship.plotted_actions.get("movement", []), [])
	assert_false(ship.plotted_actions.get("movement_plotted", false))
	assert_eq(_pc().planning_snapshot["own"]["course"], [])


func test_planning_start_leaves_ai_ships_alone() -> void:
	var enemy := _make_ship("foe", 1, Vector2i(9, 9))
	_pc()._enter_planning_phase()
	assert_false(enemy.plotted_actions.get("movement_plotted", false))
	assert_false(_pc().planning_snapshot.has("foe"))


func test_reset_restores_course_crew_and_sail() -> void:
	_pc()._enter_planning_phase()
	var start: Array = ship.plotted_actions["movement"].duplicate(true)
	assert_eq(_pc().player_extend_course(0, "own", _ahead(_pc().stored_course(ship)[-1].hex, 0)), "")
	GameState.ship_controller.set_crew_assignments("own", {0: {"code": "RO", "params": {}}})
	CrewFixtures.order_sail(ship, "FS")
	assert_eq(_pc().player_reset_planning(0), "")
	assert_eq(ship.plotted_actions["movement"], start)
	assert_false(ship.plotted_actions["crew_plotted"])
	assert_eq(ship.plotted_actions["crew_orders"]["sail_target"], "")


func test_reset_to_an_empty_snapshot_course_leaves_no_movement_plotted() -> void:
	_pc()._enter_planning_phase()
	_pc().planning_snapshot["own"]["course"] = []
	assert_eq(_pc().player_reset_course(0, "own"), "")
	assert_eq(ship.plotted_actions["movement"], [])
	assert_false(ship.plotted_actions["movement_plotted"])


func test_reset_restores_auto_and_boarding_and_keeps_tasks_in_progress() -> void:
	ship.crew_auto = true
	_pc()._enter_planning_phase()
	ship.crew_auto = false
	GameState.ship_controller.set_crew_orders("own", {"boarding": "ready"})
	CrewFixtures.give_sail_change(ship, "FS", [0, 1])
	assert_eq(_pc().player_reset_planning(0), "")
	assert_true(ship.crew_auto)
	assert_eq(ship.plotted_actions["crew_orders"]["boarding"], "")
	var live := 0
	for t in ship.crew_tasks:
		if str(t.get("ended", "")) == "":
			live += 1
	assert_eq(live, 1)


func test_reset_refused_after_ready_and_outside_planning() -> void:
	_pc()._enter_planning_phase()
	_pc().players_ready[0] = true
	assert_ne(_pc().player_reset_planning(0), "")
	_pc().players_ready[0] = false
	_pc().current_phase = TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
	assert_ne(_pc().player_reset_planning(0), "")


func test_reset_course_restores_one_ship_only() -> void:
	var other := _make_ship("own2", 0, Vector2i(5, 9))
	_pc()._enter_planning_phase()
	var start: Array = ship.plotted_actions["movement"].duplicate(true)
	var other_start: Array = other.plotted_actions["movement"].duplicate(true)
	_pc().player_cut_course(0, "own", 0)
	_pc().player_cut_course(0, "own2", 0)
	assert_eq(_pc().player_reset_course(0, "own"), "")
	assert_eq(ship.plotted_actions["movement"], start)
	assert_eq(other.plotted_actions["movement"], [])
	assert_ne(other_start, [])


func test_snapshot_cleared_at_end_turn() -> void:
	_pc()._enter_planning_phase()
	assert_false(_pc().planning_snapshot.is_empty())
	_pc()._enter_end_turn_phase()
	assert_true(_pc().planning_snapshot.is_empty())
