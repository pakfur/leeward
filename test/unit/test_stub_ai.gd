extends GutTest
## Tests for StubAI - drives plotting protocol for non-player ships

var stub_ai: StubAI
var env: EnvironmentState
var hex_grid: HexGrid


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
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
	var a3 = _make_ship("ai3", 2, Vector2i(0, -10), 1)
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
	stub_ai.strategy_override = "forward"
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
	stub_ai.strategy_override = "forward"
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 4)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()

	var steps: Array = ai.plotted_actions.movement
	var ma = GameState.ship_controller.get_movement_allowance(ai.ship_id)
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
		stub_ai.strategy_override = "forward"

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
	stub_ai.strategy_override = "forward"
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 2)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()

	var steps: Array = ai.plotted_actions.movement
	for step in steps:
		assert_has(step, "hex", "Each step should have a hex field")
		assert_has(step, "facing", "Each step should have a facing field")


func test_ai_ship_can_be_resolved_after_plotting() -> void:
	stub_ai.strategy_override = "forward"
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
	GameState.ship_controller.set_plotted_movement(player.ship_id, movement)

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
	stub_ai.strategy_override = "forward"
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 2)
	_add_ship(ai)

	stub_ai.plot_all_ai_ships()
	var first_plot = ai.plotted_actions.movement.duplicate()
	assert_gt(first_plot.size(), 0)

	# Second call should still work (plot overwrites)
	stub_ai.plot_all_ai_ships()
	var second_plot = ai.plotted_actions.movement
	assert_eq(second_plot.size(), first_plot.size(), "Second plot should produce same result")


# ===========================================================================
# Engage strategy: closing
# ===========================================================================

func test_ai_closes_distance() -> void:
	# Enemy 12 hexes off the AI's starboard beam: the AI must turn toward it, not just sail on.
	var enemy_hex := HexGrid.DIRECTIONS[4] * 12
	var player = _make_ship("p1", 0, enemy_hex, 3, 0)
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 3, 2)
	_add_ship(player)
	_add_ship(ai)
	var start := hex_grid.hex_distance(ai.hex_position.x, ai.hex_position.y, enemy_hex.x, enemy_hex.y)

	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var resolver = MovementResolver.new(GameState, rng)
	for turn in range(3):
		stub_ai.plot_all_ai_ships()
		var ships: Array[ShipState] = [player, ai]
		var log = resolver.run(ships, env)
		resolver.apply_results(log, ships)

	var end := hex_grid.hex_distance(ai.hex_position.x, ai.hex_position.y, enemy_hex.x, enemy_hex.y)
	assert_lt(end, start, "AI should be closer after three turns (start %d, end %d)" % [start, end])


func test_ai_turns_back_toward_enemy_astern() -> void:
	# Wind from the east (0), speed 2. AI faces SE (1); the enemy lies due west.
	var player = _make_ship("p1", 0, Vector2i(0, 0), 3, 0)
	var ai = _make_ship("ai1", 1, Vector2i(12, 0), 1, 2)
	_add_ship(player)
	_add_ship(ai)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var resolver = MovementResolver.new(GameState, rng)
	var best := 12
	for turn in range(8):
		stub_ai.plot_all_ai_ships()
		var ships: Array[ShipState] = [player, ai]
		var log = resolver.run(ships, env)
		resolver.apply_results(log, ships)
		best = mini(best, hex_grid.hex_distance(ai.hex_position.x, ai.hex_position.y, 0, 0))
	assert_lt(best, 12, "AI facing away must come round and close within 8 turns")


func test_engaged_ship_with_no_better_option_does_not_move() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 2)
	var enemy = _make_ship("p1", 0, HexGrid.DIRECTIONS[1], 3, 0)
	_add_ship(ai)
	_add_ship(enemy)
	stub_ai.plot_all_ai_ships()
	assert_eq(ai.plotted_actions.movement.size(), 0, "Already broadside at range 1: hold")


func test_engage_with_no_enemy_plots_nothing() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 2)
	_add_ship(ai)
	stub_ai.plot_all_ai_ships()
	assert_eq(ai.plotted_actions.movement.size(), 0, "No enemy, no movement")
	assert_eq(GameState.movement_plotting_controller.sessions.size(), 0, "Session submitted and cleaned up")


func test_engage_ignores_struck_enemy() -> void:
	var struck = _make_ship("p1", 0, Vector2i(0, 0), 3, 0)
	struck.status = ShipState.Status.STRUCK
	_add_ship(struck)
	var ai = _make_ship("ai1", 1, Vector2i(10, 0), 3, 2)
	_add_ship(ai)
	stub_ai.plot_all_ai_ships()
	assert_eq(ai.plotted_actions.movement.size(), 0, "Struck enemies are not pursued")


# ===========================================================================
# Fire orders
# ===========================================================================

func _starboard_hex(origin: Vector2i, facing: int, steps: int) -> Vector2i:
	# Facing 0 (E): directions 1 (SE) and 2 (SW) lie on the starboard beam arc edges.
	return origin + HexGrid.DIRECTIONS[(facing + 1) % 6] * steps


func _port_hex(origin: Vector2i, facing: int, steps: int) -> Vector2i:
	return origin + HexGrid.DIRECTIONS[(facing + 5) % 6] * steps


func test_ai_fires_at_best_target() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	var near = _make_ship("near", 0, _starboard_hex(Vector2i.ZERO, 0, 2), 0, 0)
	var far = _make_ship("far", 0, _starboard_hex(Vector2i.ZERO, 0, 6), 0, 0)
	_add_ship(ai)
	_add_ship(near)
	_add_ship(far)

	var orders: Array[Dictionary] = stub_ai.choose_fire_orders()

	assert_eq(orders.size(), 1, "One order")
	assert_eq(orders[0]["ship_id"], "ai1")
	assert_eq(orders[0]["side"], ShipState.STARBOARD)
	assert_eq(orders[0]["target_id"], "near")
	assert_eq(orders[0]["aim"], "low")
	assert_eq(orders[0]["ammo"], "round")


func test_ai_aims_high_beyond_range_9() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	ai.ship.gun_factors = {"lg": 20, "mg": 0, "cr": 0}
	var far = _make_ship("far", 0, _starboard_hex(Vector2i.ZERO, 0, 10), 0, 0)
	_add_ship(ai)
	_add_ship(far)

	var orders: Array[Dictionary] = stub_ai.choose_fire_orders()

	assert_eq(orders.size(), 1, "Target at range 10 is fireable with strong guns")
	assert_eq(orders[0]["aim"], "high")


func test_ai_fires_both_broadsides_when_both_strong() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	var s = _make_ship("s", 0, _starboard_hex(Vector2i.ZERO, 0, 2), 0, 0)
	var p = _make_ship("p", 0, _port_hex(Vector2i.ZERO, 0, 2), 0, 0)
	_add_ship(ai)
	_add_ship(s)
	_add_ship(p)

	var orders: Array[Dictionary] = stub_ai.choose_fire_orders()

	assert_eq(orders.size(), 2, "Both broadsides fire")


func test_ai_holds_second_broadside_when_penalty_wastes_it() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	var strong = _make_ship("strong", 0, _starboard_hex(Vector2i.ZERO, 0, 2), 0, 0)
	var weak = _make_ship("weak", 0, _port_hex(Vector2i.ZERO, 0, 13), 0, 0)
	_add_ship(ai)
	_add_ship(strong)
	_add_ship(weak)

	var calc: GunneryCalculator = GameState.gunnery_calculator
	var weak_order := GunneryTypes.FireOrder.new()
	weak_order.ship_id = "ai1"
	weak_order.side = ShipState.PORT
	weak_order.target_id = "weak"
	weak_order.aim = "high"
	var weak_preview := calc.preview(weak_order, true)
	assert_true(weak_preview.can_fire, "Precondition: weak shot is legal")
	assert_lt(weak_preview.mgn, 1, "Precondition: weak shot is wasted by the two-target penalty")

	var orders: Array[Dictionary] = stub_ai.choose_fire_orders()

	assert_eq(orders.size(), 1, "Only the better broadside fires")
	assert_eq(orders[0]["target_id"], "strong")


func test_ai_orders_pass_validation() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	var s = _make_ship("s", 0, _starboard_hex(Vector2i.ZERO, 0, 3), 0, 0)
	var p = _make_ship("p", 0, _port_hex(Vector2i.ZERO, 0, 4), 0, 0)
	_add_ship(ai)
	_add_ship(s)
	_add_ship(p)

	var typed: Array[GunneryTypes.FireOrder] = []
	for d in stub_ai.choose_fire_orders():
		typed.append(GunneryTypes.FireOrder.from_dict(d))

	assert_gt(typed.size(), 0, "Precondition: AI has orders")
	assert_eq(GameState.gunnery_calculator.validate_orders(1, typed), "")


func test_ai_with_no_targets_fires_nothing() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	_add_ship(ai)
	assert_eq(stub_ai.choose_fire_orders().size(), 0)


func test_ai_with_no_movable_ships_does_not_error() -> void:
	GameState.rng = RandomNumberGenerator.new()
	GameState.rng.seed = 11
	GameState.dice = Dice.new(GameState.rng)
	var player = _make_ship("player_1", 0, Vector2i(5, 5), 3, 0)
	var ai = _make_ship("ai_1", 1, _starboard_hex(Vector2i(5, 5), 0, 3), 0, 0)
	ai.fouled_with = "ghost"
	_add_ship(player)
	_add_ship(ai)
	GameState.start_new_game({"name": "t", "wind_direction": 0, "wind_speed": 2, "sea_state": 1})
	# start_new_game may reposition nothing; make sure fouling stays for the test
	ai.fouled_with = "ghost"
	var pc = GameState.phase_controller

	stub_ai.plot_all_ai_ships()
	pc.player_submit_plan(0)
	pc.player_submit_plan(1)
	pc.on_playback_completed()
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION, "Combat declared")

	# The controller invoked the AI's declaration on entering combat; the player now declares.
	assert_eq(pc.player_submit_fire_orders(0, []), "")
	if pc.combat_step == TurnPhaseController.CombatStep.RESOLVE:
		pc.on_combat_playback_completed()

	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT, "Phase advanced")
