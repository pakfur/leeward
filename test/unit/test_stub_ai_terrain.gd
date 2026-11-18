extends GutTest
## StubAI on a map with terrain (map and scenario spec §12): every strategy keeps off land and
## doubtful shoals (_move_safe), casts the lead on a short course into shallow water, and a ship
## whose side may escape (scenario `ai` posture "escape", or a disengage order) declares escape and
## runs for a permitted escape edge.

var stub_ai: StubAI
var env: EnvironmentState
var _saved_scenario: Dictionary


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	_reset_ships()
	env = EnvironmentState.new()
	env.wind_direction = 0  # from the east: a ship heading west runs before it
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 1
	# The AI plots on entry to PLANNING, before its player is marked ready.
	GameState.phase_controller.current_phase = TurnPhaseController.GamePhase.PLANNING
	GameState.phase_controller.game_result = {}
	GameState.phase_controller.players_ready = {0: false, 1: false}
	_saved_scenario = GameState.active_scenario
	GameState.active_scenario = {}
	stub_ai = StubAI.new(GameState)


func after_each() -> void:
	GameState.active_scenario = _saved_scenario
	GameState.phase_controller.current_phase = TurnPhaseController.GamePhase.SETUP
	_reset_ships()


func _reset_ships() -> void:
	GameState.ships.clear()
	GameState.ships_by_side.clear()
	if GameState.movement_plotting_controller:
		GameState.movement_plotting_controller.sessions.clear()
		GameState.movement_plotting_controller.ship_sessions.clear()


func _make_ship(ship_id: String, player_id: int, hex_pos: Vector2i, facing: int, speed: int,
		draft: int = 16) -> ShipState:
	var state = ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": ship_id,
		"player_id": player_id,
		"ship_name": "Ship " + ship_id,
		"ship_type": "frigate_32",
		"name": "32-gun Frigate",
		"nationality": "British",
		"rating": 32,
		"class": 3,
		"maneuverability": "C",
		"speed_type": "F/F",
		"draft": draft,
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex_pos
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = "B"
	GameState.add_ship(state)
	return state


func _plotted(ship: ShipState) -> Array:
	var out: Array = []
	for step in ship.plotted_actions.get("movement", []):
		out.append([Vector2i(int(step["hex"]["q"]), int(step["hex"]["r"])), int(step["facing"])])
	return out


func _end_bow(ship: ShipState) -> Vector2i:
	var path := _plotted(ship)
	return ship.hex_position if path.is_empty() else path[path.size() - 1][0]


func _hexes(list: Array) -> Array:
	var out: Array = []
	for h: Vector2i in list:
		out.append([h.x, h.y])
	return out


## A 20 x 20 map whose west edge is an escape edge; side 1 may escape from turn 1.
func _escape_scenario(posture: bool) -> Dictionary:
	var scenario := {
		"map_bounds": {"width": 20, "height": 20},
		"terrain": {"edges": {"W": "escape"}},
		"escape": {"1": {}},
	}
	if posture:
		scenario["ai"] = {"1": "escape"}
	return scenario


# ===========================================================================
# Safe water
# ===========================================================================

func test_ai_never_plots_into_land() -> void:
	# A line of land at q = -2 (running NW-SE) across the westward course.
	var land: Array[Vector2i] = []
	for r in range(-6, 7):
		land.append(Vector2i(-2, r))
	var cases := [
		{"order": {}, "enemy": Vector2i(-8, 0)},
		{"order": {"order": "close", "range": 2}, "enemy": Vector2i(-8, 0)},
		{"order": {"order": "disengage"}, "enemy": Vector2i(6, 0)},
	]
	for c in cases:
		_reset_ships()
		GameState.active_scenario = {"terrain": {"land": _hexes(land)}}
		_make_ship("p1", 0, c["enemy"], 3, 0)
		var ai := _make_ship("ai1", 1, Vector2i(0, 0), 3, 3)
		if not (c["order"] as Dictionary).is_empty():
			GameState.ship_controller.set_standing_order("ai1", c["order"])
		stub_ai.plot_all_ai_ships()
		var steps := _plotted(ai)
		assert_gt(steps.size(), 0, "%s: the ship still moves" % [c["order"]])
		for step in steps:
			assert_false(land.has(step[0]), "%s: bow on land at %s" % [c["order"], step])
			assert_false(land.has(HexGrid.stern_of(step[0], step[1])),
				"%s: stern on land at %s" % [c["order"], step])


func test_ai_steers_clear_of_doubtful_shoals() -> void:
	# Base 15: depth 16-21, a draft-16 frigate may ground. Deep water lies north and south of it.
	var shoal: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(-2, 0), Vector2i(-3, 0), Vector2i(-4, 0)]
	GameState.active_scenario = {"terrain": {"shallow": [{"name": "bar", "base": 15,
		"hexes": _hexes(shoal)}]}}
	_make_ship("p1", 0, Vector2i(-9, 0), 3, 0)
	var ai := _make_ship("ai1", 1, Vector2i(0, 0), 3, 3)
	assert_eq(TerrainMap.of(GameState.active_scenario).grounds(Vector2i(-1, 0), 16), "maybe", "fixture")
	stub_ai.plot_all_ai_ships()
	var steps := _plotted(ai)
	assert_gt(steps.size(), 0, "the ship still moves")
	for step in steps:
		assert_false(shoal.has(step[0]), "bow in the shoal at %s" % [step])


## The bow at (0,0) facing W: both turns, here and one hex ahead, swing the stern onto land, so
## the only move is ahead into the base-15 shoal.
func _boxed_into_shoal() -> Dictionary:
	var land := [Vector2i(1, -1), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 1)]
	var shoal := [Vector2i(-1, 0), Vector2i(-2, 0), Vector2i(-3, 0)]
	return {"terrain": {"land": _hexes(land), "shallow": [{"name": "bar", "base": 15,
		"hexes": _hexes(shoal)}]}}


func test_ai_casts_lead_on_short_course_through_shoal() -> void:
	# Speed 4, deceleration 3 (C): the course must use 1 MP, and the only one is into the shoal.
	GameState.active_scenario = _boxed_into_shoal()
	_make_ship("p1", 0, Vector2i(-9, 0), 3, 0)
	var ai := _make_ship("ai1", 1, Vector2i(0, 0), 3, 4)
	stub_ai.plot_all_ai_ships()
	var steps := _plotted(ai)
	assert_between(steps.size(), 1, 2, "a short course into the shoal: %s" % [steps])
	assert_true(ai.plotted_actions.get("cast_lead", false), "the AI casts the lead")


func test_ai_does_not_cast_lead_on_a_longer_course() -> void:
	GameState.active_scenario = _boxed_into_shoal()
	_make_ship("p1", 0, Vector2i(-9, 0), 3, 0)
	var ai := _make_ship("ai1", 1, Vector2i(0, 0), 3, 4)
	stub_ai.strategy_override = "forward"
	stub_ai.plot_all_ai_ships()
	var steps := _plotted(ai)
	assert_gte(steps.size(), 3, "fixture: a 3-step course through the shoal: %s" % [steps])
	assert_false(ai.plotted_actions.get("cast_lead", false), "no lead on a course over 2 MPs (13.G.4)")


# ===========================================================================
# Escape
# ===========================================================================

func test_ai_escape_posture_declares_and_runs_for_the_edge() -> void:
	GameState.active_scenario = _escape_scenario(true)
	# The enemy lies west, between the ship and the escape edge: engage would close, disengage open
	# the range eastward; escape runs west regardless.
	_make_ship("p1", 0, Vector2i(-4, 4), 0, 0)
	var ai := _make_ship("ai1", 1, Vector2i(0, 0), 3, 3)
	var terrain := TerrainMap.of(GameState.active_scenario)
	var start := terrain.distance_to_boundary(ai.hex_position, "W")
	assert_eq(stub_ai._get_strategy(ai), "escape")
	stub_ai.plot_all_ai_ships()
	assert_true(ai.escape_declared, "the AI declares escape")
	var end := terrain.distance_to_boundary(_end_bow(ai), "W")
	assert_lt(end, start, "closer to the west edge (%d -> %d)" % [start, end])


func test_ai_leaves_across_the_escape_edge() -> void:
	GameState.active_scenario = _escape_scenario(true)
	var edge := TerrainMap.offset_to_axial(-10, 0)
	_make_ship("p1", 0, Vector2i(5, 0), 3, 0)
	var ai := _make_ship("ai1", 1, edge, 3, 3)
	var terrain := TerrainMap.of(GameState.active_scenario)
	assert_true(terrain.in_bounds(edge) and not terrain.in_bounds(edge + HexGrid.DIRECTIONS[3]),
		"fixture: the bow is on the west edge")
	stub_ai.plot_all_ai_ships()
	var steps := _plotted(ai)
	assert_gt(steps.size(), 0, "the ship moves")
	if steps.size() > 0:
		assert_false(terrain.in_bounds(steps[0][0]), "the first step leaves the map: %s" % [steps])


func test_disengage_order_escapes_only_when_permitted() -> void:
	var scenario := _escape_scenario(false)
	scenario.erase("escape")
	GameState.active_scenario = scenario
	_make_ship("p1", 0, Vector2i(5, 0), 3, 0)
	var ai := _make_ship("ai1", 1, Vector2i(0, 0), 3, 3)
	GameState.ship_controller.set_standing_order("ai1", {"order": "disengage"})
	assert_eq(stub_ai._get_strategy(ai), "disengage", "no escape permitted: plain disengage")
	stub_ai.plot_all_ai_ships()
	assert_false(ai.escape_declared, "no declaration without permission")


func test_disengage_order_escapes_when_permitted() -> void:
	GameState.active_scenario = _escape_scenario(false)
	_make_ship("p1", 0, Vector2i(5, 0), 3, 0)
	var ai := _make_ship("ai1", 1, Vector2i(0, 0), 3, 3)
	GameState.ship_controller.set_standing_order("ai1", {"order": "disengage"})
	assert_eq(stub_ai._get_strategy(ai), "escape", "a disengage order escapes when permitted")
	stub_ai.plot_all_ai_ships()
	assert_true(ai.escape_declared)


func test_escape_posture_waits_for_from_turn() -> void:
	var scenario := _escape_scenario(true)
	scenario["escape"] = {"1": {"from_turn": 3}}
	GameState.active_scenario = scenario
	_make_ship("p1", 0, Vector2i(5, 0), 3, 0)
	var ai := _make_ship("ai1", 1, Vector2i(0, 0), 3, 3)
	assert_eq(stub_ai._get_strategy(ai), "engage", "escape not yet allowed: the default order")
	stub_ai.plot_all_ai_ships()
	assert_false(ai.escape_declared)


func test_aground_and_waiting_ships_are_skipped() -> void:
	GameState.active_scenario = _escape_scenario(true)
	_make_ship("p1", 0, Vector2i(5, 0), 3, 0)
	var aground := _make_ship("ai1", 1, Vector2i(0, 0), 3, 3)
	aground.aground = true
	var waiting := _make_ship("ai2", 1, Vector2i(0, 4), 3, 3)
	waiting.awaiting_arrival = true
	stub_ai.plot_all_ai_ships()
	for ship: ShipState in [aground, waiting]:
		for refusal in stub_ai.refusals:
			assert_ne(refusal["ship_id"], ship.ship_id, "%s refused: %s" % [ship.ship_id, refusal])
		assert_eq(_plotted(ship).size(), 0, "%s gets no plot" % ship.ship_id)
		assert_false(ship.escape_declared, "%s does not declare escape" % ship.ship_id)
