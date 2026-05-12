extends GutTest
## Tests for StubAI - drives plotting protocol for non-player ships

var stub_ai: StubAI
var env: EnvironmentState
var hex_grid: HexGrid


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ships_table()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player.clear()
	env = EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 1

	if GameState.movement_plotting_controller:
		GameState.movement_plotting_controller.sessions.clear()
		GameState.movement_plotting_controller.ship_sessions.clear()

	stub_ai = StubAI.new(GameState)
	hex_grid = HexGrid.new()


func _make_ship(
	ship_id: String,
	player_id: int,
	hex_pos: Vector2i = Vector2i(5, 5),
	facing: int = 0,
	speed: int = 2
) -> ShipState:
	var state = ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": ship_id,
		"player_id": player_id,
		"ship_name": "Ship " + ship_id,
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "C",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
	})
	state.hex_position = hex_pos
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = "B"
	return state


func _add_ship(ship_state: ShipState) -> void:
	GameState.add_ship(ship_state)


# ===========================================================================
# AI ship detection
# ===========================================================================

func test_no_ai_ships_no_error() -> void:
	var player_ship = _make_ship("p1", 0)
	_add_ship(player_ship)
	stub_ai.plot_all_ai_ships()
	assert_eq(player_ship.plotted_actions.movement.size(), 0, "Player ship should not be plotted by AI")


func test_only_plots_non_player_zero_ships() -> void:
	var player_ship = _make_ship("p1", 0, Vector2i(0, 0), 3)
	var ai_ship = _make_ship("ai1", 1, Vector2i(10, 0), 3)
	_add_ship(player_ship)
	_add_ship(ai_ship)

	stub_ai.plot_all_ai_ships()

	assert_eq(player_ship.plotted_actions.movement.size(), 0, "Player ship untouched")
	assert_gt(ai_ship.plotted_actions.movement.size(), 0, "AI ship should have plotted movement")


func test_multiple_ai_ships_all_plotted() -> void:
	var p = _make_ship("p1", 0, Vector2i(0, 0), 3)
	var a1 = _make_ship("ai1", 1, Vector2i(10, 0), 3)
	var a2 = _make_ship("ai2", 1, Vector2i(10, 5), 3)
	var a3 = _make_ship("ai3", 2, Vector2i(15, 0), 3)
	_add_ship(p)
	_add_ship(a1)
	_add_ship(a2)
	_add_ship(a3)

	stub_ai.plot_all_ai_ships()

	assert_gt(a1.plotted_actions.movement.size(), 0, "AI ship 1 plotted")
	assert_gt(a2.plotted_actions.movement.size(), 0, "AI ship 2 plotted")
	assert_gt(a3.plotted_actions.movement.size(), 0, "AI ship 3 (player 2) plotted")
	assert_eq(p.plotted_actions.movement.size(), 0, "Player ship untouched")


# ===========================================================================
# Forward strategy
# ===========================================================================

func test_forward_strategy_produces_straight_line() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 2)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()

	var steps: Array = ai.plotted_actions.movement
	assert_gt(steps.size(), 0, "Should have at least one step")

	var current_hex = Vector2i(5, 5)
	for step in steps:
		var step_hex = Vector2i(int(step.hex.q), int(step.hex.r))
		var expected = hex_grid.get_neighbor(current_hex.x, current_hex.y, 3)
		assert_eq(step_hex, expected, "Each step should be forward in facing direction 3")
		current_hex = step_hex


func test_forward_strategy_respects_ma() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 4)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()

	var steps: Array = ai.plotted_actions.movement
	var ma = ai.get_movement_allowance()
	assert_eq(steps.size(), ma, "Should consume exactly the full MA (%d)" % ma)


func test_forward_strategy_different_facings() -> void:
	# Wind from direction 0 (East). Facings that give MA > 0: 1,2,3,4,5 (not 0, which is luffing)
	for facing in [1, 2, 3, 4, 5]:
		GameState.ships.clear()
		GameState.ships_by_player.clear()
		if GameState.movement_plotting_controller:
			GameState.movement_plotting_controller.sessions.clear()
			GameState.movement_plotting_controller.ship_sessions.clear()
		stub_ai._request_counter = 0

		var ai = _make_ship("ai_f%d" % facing, 1, Vector2i(20, 20), facing, 2)
		_add_ship(ai)
		stub_ai.plot_all_ai_ships()

		var steps: Array = ai.plotted_actions.movement
		assert_gt(steps.size(), 0, "Facing %d: should have steps (not luffing)" % facing)
		var first_step = steps[0]
		var expected_hex = hex_grid.get_neighbor(20, 20, facing)
		var step_hex = Vector2i(int(first_step.hex.q), int(first_step.hex.r))
		assert_eq(step_hex, expected_hex, "Facing %d: first step should be forward" % facing)


# ===========================================================================
# Session cleanup
# ===========================================================================

func test_sessions_cleaned_up_after_plotting() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()

	var controller = GameState.movement_plotting_controller
	assert_false(controller.has_active_session("ai1"), "Session should be cleaned up after submit")


func test_no_sessions_left_after_multiple_ships() -> void:
	var a1 = _make_ship("ai1", 1, Vector2i(5, 5), 3)
	var a2 = _make_ship("ai2", 1, Vector2i(10, 5), 3)
	_add_ship(a1)
	_add_ship(a2)

	stub_ai.plot_all_ai_ships()

	var controller = GameState.movement_plotting_controller
	assert_eq(controller.sessions.size(), 0, "All sessions should be cleaned up")


# ===========================================================================
# Integration with plotting protocol
# ===========================================================================

func test_plotted_path_matches_protocol_output() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 2)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()

	var steps: Array = ai.plotted_actions.movement
	for step in steps:
		assert_has(step, "hex", "Each step should have a hex field")
		assert_has(step, "facing", "Each step should have a facing field")


func test_ai_ship_can_be_resolved_after_plotting() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 2)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()

	assert_gt(ai.plotted_actions.movement.size(), 0, "Pre-condition: AI has plotted moves")

	var rng = RandomNumberGenerator.new()
	rng.seed = 99
	var resolver = MovementResolver.new(GameState, rng)
	var ships: Array[ShipState] = [ai]
	var log = resolver.run(ships, env)

	assert_not_null(log, "Resolver should produce a log")
	var result = log.get_result("ai1")
	assert_not_null(result, "Should have a result for ai1")
	assert_ne(result.final_hex, Vector2i(5, 5), "Ship should have moved from starting position")


func test_player_and_ai_ships_both_resolve() -> void:
	var player = _make_ship("p1", 0, Vector2i(0, 0), 3, 2)
	var ai = _make_ship("ai1", 1, Vector2i(20, 0), 3, 2)
	_add_ship(player)
	_add_ship(ai)

	# AI plots via stub
	stub_ai.plot_all_ai_ships()

	# Manually plot player ship forward
	var movement: Array = []
	var current_hex = Vector2i(0, 0)
	for i in range(2):
		var next_hex = hex_grid.get_neighbor(current_hex.x, current_hex.y, 3)
		movement.append({"hex": {"q": next_hex.x, "r": next_hex.y}, "facing": 3})
		current_hex = next_hex
	player.plotted_actions.movement = movement

	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	var resolver = MovementResolver.new(GameState, rng)
	var ships: Array[ShipState] = [player, ai]
	var log = resolver.run(ships, env)

	var p_result = log.get_result("p1")
	var a_result = log.get_result("ai1")
	assert_not_null(p_result, "Player result exists")
	assert_not_null(a_result, "AI result exists")


# ===========================================================================
# Edge cases
# ===========================================================================

func test_zero_ma_ship_submits_empty_plot() -> void:
	# Ship facing into wind (luffing) has 0 MA
	env.wind_direction = 3
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 0)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()

	var steps: Array = ai.plotted_actions.movement
	assert_eq(steps.size(), 0, "Luffing ship with 0 MA should have empty plot")


func test_idempotent_no_double_plot() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 2)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()
	var first_plot = ai.plotted_actions.movement.duplicate()
	assert_gt(first_plot.size(), 0)

	# Second call should still work (plot overwrites)
	stub_ai.plot_all_ai_ships()
	var second_plot = ai.plotted_actions.movement
	assert_eq(second_plot.size(), first_plot.size(), "Second plot should produce same result")
