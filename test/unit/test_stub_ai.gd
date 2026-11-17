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
	# Plotting is refused once a turn loop is past PLANNING; start from SETUP like a fresh game.
	GameState.phase_controller.current_phase = TurnPhaseController.GamePhase.SETUP
	GameState.phase_controller.game_result = {}
	GameState.phase_controller.players_ready = [false, false] as Array[bool]

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
	# Both ships face east, side by side: both of the AI's batteries bear at range 1.
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 2)
	var enemy = _make_ship("p1", 0, Vector2i(0, 1), 0, 0)
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


# ===========================================================================
# Turns pivot on the bow (5.C.2)
# ===========================================================================

func test_plot_step_stores_bow_hex() -> void:
	env.wind_direction = 3
	var ship = _make_ship("p1", 0, Vector2i(5, 5), 0, 3)
	_add_ship(ship)
	var controller: MovementPlottingController = GameState.movement_plotting_controller
	var started = controller.handle_start_plotting(0, "p1", "req_start")
	var target: Vector2i = started.valid_next_hexes.starboard.hex
	assert_eq(target, Vector2i(5, 6), "Click target is the hex the bow will point at")

	var response = controller.handle_select_hex(started.session_id, started.session_version, target, "req_turn")

	assert_false(response is MovementTypes.PlottingErrorResponse)
	var step: MovementTypes.PlotStep = response.plotted_path.back()
	assert_eq(step.hex, Vector2i(5, 5), "The stored step is the unchanged bow hex")
	assert_eq(step.facing, 1)


# ===========================================================================
# Two-hex footprints
# ===========================================================================

func test_ai_scores_broadside_against_two_hex_enemy() -> void:
	# Enemy bow (5,0) facing 0, stern (4,0). The firer faces east with its keel on row 2.
	var enemy = _make_ship("p1", 0, Vector2i(5, 0), 0, 0)
	var ai = _make_ship("ai1", 1, Vector2i(5, 2), 0, 0)
	_add_ship(enemy)
	_add_ship(ai)
	var occupied := {}
	var geometry: FireGeometry = GameState.fire_geometry

	var both_bow := Vector2i(5, 2)
	var one_bow := Vector2i(2, 2)
	var both_hexes: Array[Vector2i] = [both_bow, HexGrid.stern_of(both_bow, 0)]
	var one_hexes: Array[Vector2i] = [one_bow, HexGrid.stern_of(one_bow, 0)]
	var count_both := 0
	var count_one := 0
	for h in both_hexes:
		if geometry.battery_bears(h, 0, ShipState.PORT, enemy.occupied_hexes(), occupied):
			count_both += 1
	for h in one_hexes:
		if geometry.battery_bears(h, 0, ShipState.PORT, enemy.occupied_hexes(), occupied):
			count_one += 1
	assert_eq(count_both, 2, "fixture: both batteries bear from the abeam position")
	assert_eq(count_one, 1, "fixture: only one battery bears from the offset position")

	var both_score := stub_ai._score_position(both_bow, 0, enemy, occupied)
	var one_score := stub_ai._score_position(one_bow, 0, enemy, occupied)
	assert_gt(one_score, 0, "a single bearing battery is still a firing position")
	assert_gt(both_score, one_score, "two batteries bearing outscore one")


func test_second_battery_does_not_outweigh_two_hexes_of_range() -> void:
	# Enemy bow (5,0) facing E, stern (4,0); the firer faces E south of it, its port side bearing.
	# Fixture positions (bow): two batteries at range 4 from (2,4); one battery at range 4 from
	# (6,4), at 3 from (6,3), at 2 from (6,2).
	var enemy = _make_ship("p1", 0, Vector2i(5, 0), 0, 0)
	_add_ship(enemy)
	var occupied := {}
	var two_at_4 := stub_ai._score_position(Vector2i(2, 4), 0, enemy, occupied)
	var one_at_4 := stub_ai._score_position(Vector2i(6, 4), 0, enemy, occupied)
	var one_at_3 := stub_ai._score_position(Vector2i(6, 3), 0, enemy, occupied)
	var one_at_2 := stub_ai._score_position(Vector2i(6, 2), 0, enemy, occupied)
	assert_gt(two_at_4, one_at_4, "two batteries beat one at the same range")
	assert_gt(two_at_4, one_at_3, "two batteries beat one a hex closer")
	assert_gt(one_at_2, two_at_4, "one battery two hexes closer beats two batteries")


func test_nearest_enemy_measures_footprint_to_footprint() -> void:
	# AI bow (0,0) facing E, stern (-1,0). "b" has the nearer bow (3 hexes) but its closest hex is 3
	# away; "a" points away (bow (-4,0) facing W, stern (-3,0)): bow 4 hexes off, closest hex 2.
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 2)
	var a = _make_ship("a", 0, Vector2i(-4, 0), 3, 0)
	var b = _make_ship("b", 0, Vector2i(3, 0), 3, 0)
	_add_ship(ai)
	_add_ship(b)
	_add_ship(a)
	assert_eq(stub_ai._nearest_enemy(ai), a)


func test_unengaged_score_measures_bow_to_enemy_footprint() -> void:
	# Firer bow (0,0) facing E toward an enemy bow (10,0) facing E, stern (9,0): out of firing range.
	# The firer's bow is 9 hexes from the enemy's stern (10 from its bow); no misalignment.
	var enemy = _make_ship("p1", 0, Vector2i(10, 0), 0, 0)
	_add_ship(enemy)
	assert_eq(stub_ai._score_position(Vector2i(0, 0), 0, enemy, {}), -18)
	# Pointing away brings the firer's own stern a hex nearer, but the bow leads: no reward for it.
	assert_eq(stub_ai._score_position(Vector2i(0, 0), 3, enemy, {}), -21)


func test_ai_never_plots_stern_into_occupied_hex() -> void:
	env.wind_direction = 3
	# AI bow (5,5) facing east, stern (4,5); a friend lies alongside on row 6 (stern (4,6)).
	# Turning to port (facing 5) would swing the stern onto (4,6). The enemy is far to the north-east.
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 0, 2)
	var friend = _make_ship("ai2", 1, Vector2i(5, 6), 0, 0)
	var enemy = _make_ship("p1", 0, Vector2i(14, -6), 3, 0)
	_add_ship(ai)
	_add_ship(friend)
	_add_ship(enemy)
	var blocked: Array[Vector2i] = friend.occupied_hexes()

	stub_ai.plot_all_ai_ships()

	var steps: Array = ai.plotted_actions.get("movement", [])
	assert_gt(steps.size(), 0, "the AI still plots something")
	for step in steps:
		var bow := Vector2i(int(step["hex"]["q"]), int(step["hex"]["r"]))
		var stern := HexGrid.stern_of(bow, int(step["facing"]))
		assert_false(stern in blocked, "step %s facing %d swings the stern into the friend" % [bow, step["facing"]])


func _plotted(ship: ShipState) -> Array:
	var out: Array = []
	for step in ship.plotted_actions.get("movement", []):
		out.append([Vector2i(int(step["hex"]["q"]), int(step["hex"]["r"])), int(step["facing"])])
	return out


func test_ai_stern_guard_applies_to_a_turn_later_in_the_plan() -> void:
	env.wind_direction = 3
	# AI bow (5,5) facing E at speed 2; the enemy lies to the east-south-east. Unhindered, the AI
	# steps ahead to (6,5) and then turns to starboard there, swinging its stern onto (6,4).
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 0, 2)
	var enemy = _make_ship("p1", 0, Vector2i(12, 2), 0, 0)
	_add_ship(ai)
	_add_ship(enemy)
	stub_ai.plot_all_ai_ships()
	var free_path := _plotted(ai)
	assert_eq(free_path.slice(0, 2), [[Vector2i(6, 5), 0], [Vector2i(6, 5), 1]], "fixture: ahead, then turn")
	assert_eq(HexGrid.stern_of(Vector2i(6, 5), 1), Vector2i(6, 4))

	# A friend on (6,4) and (7,4): the second step's turn would put the stern into it.
	GameState.movement_plotting_controller.sessions.clear()
	GameState.movement_plotting_controller.ship_sessions.clear()
	var friend = _make_ship("ai2", 1, Vector2i(6, 4), 3, 0)
	_add_ship(friend)
	stub_ai.plot_all_ai_ships()
	var path := _plotted(ai)
	assert_gt(path.size(), 0)
	assert_eq(path[0], [Vector2i(6, 5), 0], "still steps ahead first")
	for step in path:
		var stern := HexGrid.stern_of(step[0], step[1])
		assert_false(stern in friend.occupied_hexes(), "step %s swings the stern into the friend" % [step])


func test_ai_stern_guard_applies_to_an_ma_zero_turn() -> void:
	# In irons (facing W into a westerly): MA 0, the only move is a turn (5.D.1). The enemy lies to
	# the south-west, so the AI wants the port turn to SW, which would swing the stern onto (6,4).
	env.wind_direction = 3
	var ai = _make_ship("ai1", 1, Vector2i(5, 5), 3, 0)
	var enemy = _make_ship("p1", 0, Vector2i(-3, 13), 0, 0)
	_add_ship(ai)
	_add_ship(enemy)
	stub_ai.plot_all_ai_ships()
	assert_eq(_plotted(ai), [[Vector2i(5, 5), 2]], "fixture: unhindered, the AI turns to port")
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 2), Vector2i(6, 4))

	GameState.movement_plotting_controller.sessions.clear()
	GameState.movement_plotting_controller.ship_sessions.clear()
	var friend = _make_ship("ai2", 1, Vector2i(6, 4), 0, 0)  # holds (6,4) and (5,4)
	_add_ship(friend)
	stub_ai.plot_all_ai_ships()
	assert_eq(_plotted(ai), [[Vector2i(5, 5), 4]], "the AI takes the starboard turn to NW instead")
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 4), Vector2i(5, 6), "a stern hex clear of the friend")
	assert_false(Vector2i(5, 6) in friend.occupied_hexes())


func test_ai_prefers_full_broadside() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	var s = _make_ship("s", 0, Vector2i(-1, 2), 0, 0)  # abeam: both starboard batteries bear
	_add_ship(ai)
	_add_ship(s)
	var orders: Array[Dictionary] = stub_ai.choose_fire_orders()
	assert_eq(orders.size(), 1)
	assert_eq(orders[0]["battery"], "full")


func test_ai_falls_back_to_bearing_battery() -> void:
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	var s = _make_ship("s", 0, Vector2i(0, 3), 1, 0)  # bow (0,3) facing SE: only the bow battery bears
	_add_ship(ai)
	_add_ship(s)
	var orders: Array[Dictionary] = stub_ai.choose_fire_orders()
	assert_eq(orders.size(), 1)
	assert_eq(orders[0]["side"], ShipState.STARBOARD)
	assert_eq(orders[0]["battery"], "bow")
	var typed: Array[GunneryTypes.FireOrder] = [GunneryTypes.FireOrder.from_dict(orders[0])]
	assert_eq(GameState.gunnery_calculator.validate_orders(1, typed), "")


func _typed(orders: Array[Dictionary]) -> Array[GunneryTypes.FireOrder]:
	var typed: Array[GunneryTypes.FireOrder] = []
	for d in orders:
		typed.append(GunneryTypes.FireOrder.from_dict(d))
	return typed


func _split_fixture() -> void:
	# AI bow (0,0) facing E, stern (-1,0). "b" (bow (0,3) facing SE) lies only in the starboard bow
	# battery's arc, "c" (bow (-4,3) facing SW) only in the starboard stern battery's.
	_add_ship(_make_ship("ai1", 1, Vector2i(0, 0), 0, 0))
	_add_ship(_make_ship("b", 0, Vector2i(0, 3), 1, 0))
	_add_ship(_make_ship("c", 0, Vector2i(-4, 3), 2, 0))


func test_ai_splits_a_side_between_two_targets() -> void:
	_split_fixture()
	var orders := stub_ai.choose_fire_orders()
	assert_eq(orders.size(), 2, str(orders))
	var by_battery := {}
	for o in orders:
		assert_eq(o["side"], ShipState.STARBOARD)
		by_battery[o["battery"]] = o["target_id"]
	assert_eq(by_battery, {"bow": "b", "stern": "c"})
	var typed := _typed(orders)
	assert_eq(GameState.gunnery_calculator.validate_orders(1, typed), "")
	for p in GameState.gunnery_calculator.preview_orders(typed):
		assert_gte(p.mgn, 1, "each split shot is worth firing under the two-target penalty")


func test_ai_does_not_split_when_a_shot_would_be_wasted() -> void:
	_split_fixture()
	GameState.get_ship("ai1").ship.gun_factors = {"lg": 1, "mg": 0, "cr": 0}
	var orders := stub_ai.choose_fire_orders()
	assert_eq(orders.size(), 1, "a weak ship fires one battery rather than waste both: %s" % [orders])


func test_ai_split_never_names_more_than_two_targets() -> void:
	_split_fixture()
	# "d" lies off the port beam, where both port batteries bear: a third target.
	_add_ship(_make_ship("d", 0, Vector2i(1, -2), 0, 0))
	var at_d := GameState.gunnery_calculator.eligible_shots("ai1").filter(
		func(p): return p.order.target_id == "d" and p.order.side == ShipState.PORT)
	assert_gt(at_d.size(), 0, "fixture: the port broadside bears on d")
	var orders := stub_ai.choose_fire_orders()
	var targets := {}
	for o in orders:
		targets[o["target_id"]] = true
	assert_gt(orders.size(), 0)
	assert_lte(targets.size(), 2, str(orders))
	assert_eq(GameState.gunnery_calculator.validate_orders(1, _typed(orders)), "")


func test_ai_does_not_score_blocked_shot() -> void:
	# 7.B.10, Diagram 19 (ship 3 on E): firer bow (0,0) facing E, stern (-1,0). The enemy points
	# straight away from the bow battery, stern (0,5), bow (0,6), range 5; only the bow battery has
	# it in arc. A friend at (-1,5)/(-2,5), range 5, makes (0,5) a blocking hex, so the bow battery's
	# line to the enemy's bow, which passes through it, is blocked: no shot, no firing score.
	var enemy = _make_ship("p1", 0, Vector2i(0, 6), 1, 0)
	var ai = _make_ship("ai1", 1, Vector2i(0, 0), 0, 0)
	var friend = _make_ship("ai2", 1, Vector2i(-1, 5), 0, 0)
	_add_ship(enemy)
	_add_ship(ai)
	_add_ship(friend)
	var occupied := {friend.hex_position: true, friend.stern_hex(): true}
	var clear := stub_ai._score_position(Vector2i(0, 0), 0, enemy, occupied)
	assert_eq(clear, StubAI.FIRING_POSITION_BASE - StubAI.FIRING_RANGE_WEIGHT * 5,
		"setup: without blocking hexes the bow battery bears at range 5")
	var friendly: Array = [friend.occupied_hexes()]
	assert_lt(stub_ai._score_position(Vector2i(0, 0), 0, enemy, occupied, friendly), 0,
		"the blocked battery is not a firing position")
