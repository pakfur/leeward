extends GutTest
## Plotting at the typed edges (MovementValidator) and the escape / cast-the-lead requests
## (TurnPhaseController), map and scenario spec §5.

const PHASE_PLANNING := TurnPhaseController.GamePhase.PLANNING


class MockGameState extends Node:
	var environment: EnvironmentState = null
	var ship_controller: ShipStateController = null
	var ships: Dictionary = {}
	var active_scenario: Dictionary = {}
	func _init() -> void:
		environment = EnvironmentState.new()
		ship_controller = ShipStateController.new(self)
	func get_ship(ship_id: String) -> ShipState:
		return ships.get(ship_id, null)


var mock_gs: MockGameState
var validator: MovementValidator

var _old_scenario: Dictionary
var _old_ships: Dictionary
var _old_by_side: Dictionary
var _old_turn: int
var _old_wind_speed: int
var _old_wind_dir: int
var _old_phase: int
var _old_ready: Dictionary


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	mock_gs = MockGameState.new()
	mock_gs.environment.wind_direction = 3
	mock_gs.environment.wind_speed = 3
	validator = MovementValidator.new(mock_gs)
	_old_scenario = GameState.active_scenario
	_old_ships = GameState.ships.duplicate()
	_old_by_side = GameState.ships_by_side.duplicate(true)
	_old_turn = GameState.current_turn
	_old_wind_speed = GameState.environment.wind_speed
	_old_wind_dir = GameState.environment.wind_direction
	_old_phase = GameState.phase_controller.current_phase
	_old_ready = GameState.phase_controller.players_ready.duplicate()
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	GameState.current_turn = 1
	GameState.environment.wind_speed = 3
	GameState.environment.wind_direction = 0  # from the east: a ship heading west runs


func after_each() -> void:
	mock_gs.free()
	GameState.active_scenario = _old_scenario
	GameState.ships = _old_ships
	GameState.ships_by_side = _old_by_side
	GameState.current_turn = _old_turn
	GameState.environment.wind_speed = _old_wind_speed
	GameState.environment.wind_direction = _old_wind_dir
	GameState.phase_controller.current_phase = _old_phase
	GameState.phase_controller.players_ready = _old_ready
	GameState.phase_controller.planning_snapshot.clear()


func _make_ship(id: String, player: int, hex: Vector2i, facing: int, registry: Variant) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
	})
	state.hex_position = hex
	state.facing = facing
	state.speed = 0
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	if registry == mock_gs:
		mock_gs.ships[id] = state
	else:
		GameState.ships[id] = state
		GameState.ships_by_side[player].append(id)
	return state


func _scenario(edges: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var s := {"map_bounds": {"width": 10, "height": 10}, "terrain": {"edges": edges}}
	s.merge(extra, true)
	return s


func _forward_hexes(ship: ShipState, hex: Vector2i, facing: int) -> Array:
	var typed: Array[MovementTypes.PlotStep] = []
	var moves := validator.calculate_valid_moves(ship, hex, facing, typed)
	var out: Array = []
	for m in moves.valid_hexes.forward:
		out.append(m.hex)
	return out


# ---------- validator ----------

func test_forward_off_open_edge_not_offered() -> void:
	mock_gs.active_scenario = _scenario({"E": "open"})
	var ship := _make_ship("a", 0, Vector2i(4, 0), 0, mock_gs)
	assert_eq(_forward_hexes(ship, Vector2i(4, 0), 0), [], "no step off the open edge")
	assert_eq(_forward_hexes(ship, Vector2i(3, 0), 0), [Vector2i(4, 0)], "one hex short is fine")


func test_none_edge_refused_too() -> void:
	mock_gs.active_scenario = _scenario({"E": "none"})
	var ship := _make_ship("a", 0, Vector2i(4, 0), 0, mock_gs)
	assert_eq(_forward_hexes(ship, Vector2i(4, 0), 0), [])


func test_escape_edge_offered_only_when_declared_and_permitted() -> void:
	mock_gs.active_scenario = _scenario({"W": "escape"}, {"escape": {"1": {}}})
	mock_gs.environment.wind_direction = 0
	var ship := _make_ship("a", 1, Vector2i(-5, 0), 3, mock_gs)
	assert_eq(_forward_hexes(ship, Vector2i(-5, 0), 3), [], "undeclared")
	ship.escape_declared = true
	assert_eq(_forward_hexes(ship, Vector2i(-5, 0), 3), [Vector2i(-6, 0)], "declared")
	var typed: Array[MovementTypes.PlotStep] = [
		MovementTypes.PlotStep.new(Vector2i(-6, 0), 3, MovementTypes.MoveType.FORWARD)]
	var moves := validator.calculate_valid_moves(ship, Vector2i(-6, 0), 3, typed)
	assert_false(moves.valid_hexes.has_any_moves(), "a ship off the map plots no more")
	assert_eq(validator.deceleration_shortfall(ship, typed), 0)


func test_land_and_shallow_not_refused() -> void:
	mock_gs.active_scenario = _scenario({}, {"terrain": {"land": [[1, 0]],
			"shallow": [{"name": "bank", "base": 10, "hexes": [[2, 0]]}]}})
	var ship := _make_ship("a", 0, Vector2i(0, 0), 0, mock_gs)
	assert_eq(_forward_hexes(ship, Vector2i(0, 0), 0), [Vector2i(1, 0)])


# ---------- requests ----------

func _planning(scenario: Dictionary) -> TurnPhaseController:
	GameState.active_scenario = scenario
	var pc: TurnPhaseController = GameState.phase_controller
	pc.current_phase = PHASE_PLANNING
	pc.players_ready = {0: false, 1: false}
	return pc


func test_declare_escape_checks() -> void:
	var pc := _planning(_scenario({"W": "escape"}, {"escape": {"1": {"from_turn": 3}}}))
	var mine := _make_ship("mine", 1, Vector2i(0, 0), 3, GameState)
	_make_ship("theirs", 0, Vector2i(2, 2), 3, GameState)
	assert_string_contains(pc.player_declare_escape(0, "theirs", true), "may not escape")
	assert_string_contains(pc.player_declare_escape(0, "mine", true), "not this player's")
	assert_string_contains(pc.player_declare_escape(1, "mine", true), "from turn")
	GameState.current_turn = 3
	assert_eq(pc.player_declare_escape(1, "mine", true), "")
	assert_true(mine.escape_declared)
	assert_eq(pc.player_declare_escape(1, "mine", false), "")
	assert_false(mine.escape_declared)
	pc.current_phase = TurnPhaseController.GamePhase.COMBAT_RESOLUTION
	assert_string_contains(pc.player_declare_escape(1, "mine", true), "planning")


func _store(ship: ShipState, steps: Array[MovementTypes.PlotStep]) -> void:
	GameState.ship_controller.set_plotted_movement(ship.ship_id, DefaultCourse.as_dicts(steps))


func _fwd(q: int, r: int, facing: int) -> MovementTypes.PlotStep:
	return MovementTypes.PlotStep.new(Vector2i(q, r), facing, MovementTypes.MoveType.FORWARD)


func test_cast_lead_plan_error() -> void:
	var pc := _planning(_scenario({}))
	var ship := _make_ship("a", 0, Vector2i(-2, 0), 0, GameState)
	assert_eq(pc.player_set_cast_lead(0, "a", true), "")
	assert_true(ship.casts_lead())
	_store(ship, [_fwd(-1, 0, 0), _fwd(0, 0, 0), _fwd(1, 0, 0)])
	assert_true(pc.plan_errors(0).has("a"))
	assert_string_contains(pc.plan_errors(0)["a"], "13.G.4a")
	assert_false(pc.player_submit_plan(0))
	_store(ship, [_fwd(-1, 0, 0), _fwd(0, 0, 0)])
	assert_false(pc.plan_errors(0).has("a"))


func test_course_over_escape_edge_needs_declaration() -> void:
	var pc := _planning(_scenario({"W": "escape"}, {"escape": {"1": {}}}))
	_make_ship("a", 1, Vector2i(-5, 0), 3, GameState)
	assert_eq(pc.player_declare_escape(1, "a", true), "")
	assert_eq(pc.player_extend_course(1, "a", Vector2i(-6, 0)), "")
	assert_false(pc.plan_errors(1).has("a"), "declared: the course is fine")
	assert_eq(pc.player_declare_escape(1, "a", false), "")
	assert_string_contains(pc.plan_errors(1)["a"], "declare escape first")


## Ruling 2026-11-17: a ship in a live boarding action may not plot over an escape edge.
func test_course_over_escape_edge_refused_in_a_boarding_action() -> void:
	var pc := _planning(_scenario({"W": "escape"}, {"escape": {"1": {}}}))
	_make_ship("a", 1, Vector2i(-5, 0), 3, GameState)
	pc.planning_snapshot["a"] = {"course": [], "crew_auto": true, "boarding": ""}
	assert_eq(pc.player_declare_escape(1, "a", true), "")
	assert_eq(pc.player_extend_course(1, "a", Vector2i(-6, 0)), "")
	var action := BoardingAction.new()
	action.attacker_id = "x"
	action.defender_id = "a"
	action.state = BoardingAction.ENGAGED
	var old_actions: Array = GameState.boarding_actions
	GameState.boarding_actions = [action]
	var errors: Dictionary = pc.plan_errors(1)
	assert_eq(pc.player_reset_course(1, "a"), "")
	var extend := pc.player_extend_course(1, "a", Vector2i(-6, 0))
	GameState.boarding_actions = old_actions
	assert_string_contains(str(errors.get("a", "")), "boarding action")
	assert_ne(extend, "", "the escape hex is not offered")


func test_reset_planning_clears_the_lead() -> void:
	var pc := _planning(_scenario({}))
	var ship := _make_ship("a", 0, Vector2i(0, 0), 0, GameState)
	pc.planning_snapshot["a"] = {"course": [], "crew_auto": true, "boarding": ""}
	assert_eq(pc.player_set_cast_lead(0, "a", true), "")
	assert_true(ship.casts_lead())
	assert_eq(pc.player_reset_planning(0), "")
	assert_false(ship.casts_lead())


func test_reset_course_clears_the_lead() -> void:
	var pc := _planning(_scenario({}))
	var ship := _make_ship("a", 0, Vector2i(0, 0), 0, GameState)
	pc.planning_snapshot["a"] = {"course": [], "crew_auto": true, "boarding": ""}
	assert_eq(pc.player_set_cast_lead(0, "a", true), "")
	assert_eq(pc.player_reset_course(0, "a"), "")
	assert_false(ship.casts_lead())
