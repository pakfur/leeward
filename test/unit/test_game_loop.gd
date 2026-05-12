extends GutTest
## Integration tests: multi-turn game loop and determinism verification
## Drives the server-side pipeline (TurnPhaseController + StubAI + MovementResolver)
## without a scene tree or GameController (view layer).

var hex_grid: HexGrid


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ships_table()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	hex_grid = HexGrid.new()

	GameState.ships.clear()
	GameState.ships_by_player.clear()
	GameState.clear_state_history()
	GameState.current_turn = 0
	GameState.current_phase = GameState.GamePhase.SETUP

	if GameState.movement_plotting_controller:
		GameState.movement_plotting_controller.sessions.clear()
		GameState.movement_plotting_controller.ship_sessions.clear()

	# Seed all RNGs for determinism in tests
	if GameState.environment_controller:
		GameState.environment_controller.rng.seed = 100

	var test_rng = RandomNumberGenerator.new()
	test_rng.seed = 200
	GameState.movement_resolver = MovementResolver.new(GameState, test_rng)


func _make_ship(
	ship_id: String,
	player_id: int,
	hex_pos: Vector2i = Vector2i(5, 5),
	facing: int = 3,
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


func _setup_two_ship_scenario() -> void:
	# Ships face west (direction 3), wind from east (direction 0)
	# Wind facing = broad reach, gives good MA
	var player_ship = _make_ship("player_1", 0, Vector2i(5, 5), 3, 2)
	var ai_ship = _make_ship("ai_1", 1, Vector2i(20, 5), 3, 2)
	GameState.add_ship(player_ship)
	GameState.add_ship(ai_ship)


func _start_game() -> void:
	GameState.start_new_game({
		"name": "integration_test",
		"wind_direction": 0,
		"wind_speed": 2,
		"sea_state": 1,
	})


func _plot_player_ship_forward(ship_id: String) -> void:
	var ship_state = GameState.get_ship(ship_id)
	if not ship_state:
		return
	var ma = ship_state.get_movement_allowance()
	if ma == 0:
		return
	var movement: Array = []
	var current_hex = ship_state.hex_position
	var current_facing = ship_state.facing
	for i in range(ma):
		var next_hex = hex_grid.get_neighbor(current_hex.x, current_hex.y, current_facing)
		movement.append({"hex": {"q": next_hex.x, "r": next_hex.y}, "facing": current_facing})
		current_hex = next_hex
	ship_state.plotted_actions.movement = movement


func _run_one_turn(phase_controller: TurnPhaseController) -> void:
	assert_eq(phase_controller.current_phase, TurnPhaseController.GamePhase.PLANNING,
		"Should be in PLANNING after ENVIRONMENT auto-advances")

	# StubAI plots for non-player ships (called automatically on PLANNING entry,
	# but we call it here for headless tests that bypass signal-based wiring)
	if GameState.stub_ai:
		GameState.stub_ai.plot_all_ai_ships()
	_plot_player_ship_forward("player_1")

	phase_controller.player_submit_plan(0)
	phase_controller.player_submit_plan(1)

	assert_eq(phase_controller.current_phase, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION,
		"Should be in MOVEMENT_RESOLUTION after both plans submitted")

	# Simulate what the view layer does after playback finishes
	phase_controller.on_playback_completed()

	# Stubbed phases (COMBAT→DRIFT→STATUS→MORALE→MESSAGE) auto-advance to POST_COMBAT
	assert_eq(phase_controller.current_phase, TurnPhaseController.GamePhase.POST_COMBAT,
		"Should be in POST_COMBAT after stubbed phases")

	# POST_COMBAT → END_TURN (manual advance required)
	phase_controller.advance_phase()
	assert_eq(phase_controller.current_phase, TurnPhaseController.GamePhase.END_TURN,
		"Should be in END_TURN")

	# END_TURN → new turn → ENVIRONMENT (auto-advances) → PLANNING
	phase_controller.advance_phase()
	assert_eq(phase_controller.current_phase, TurnPhaseController.GamePhase.PLANNING,
		"Should be back in PLANNING for next turn")


# ===========================================================================
# Multi-turn integration
# ===========================================================================

func test_five_turn_game_loop() -> void:
	_setup_two_ship_scenario()

	var pc = GameState.phase_controller
	assert_not_null(pc, "Phase controller should exist")

	var initial_player_pos = GameState.get_ship("player_1").hex_position
	var initial_ai_pos = GameState.get_ship("ai_1").hex_position

	_start_game()

	assert_eq(pc.current_turn, 1, "Turn should be 1 after start")
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.PLANNING,
		"Should start in PLANNING phase")

	for turn_idx in range(5):
		var expected_turn = turn_idx + 1
		assert_eq(pc.current_turn, expected_turn,
			"Turn should be %d" % expected_turn)
		_run_one_turn(pc)

	assert_eq(pc.current_turn, 6, "Should be on turn 6 after 5 complete turns")

	var final_player_pos = GameState.get_ship("player_1").hex_position
	var final_ai_pos = GameState.get_ship("ai_1").hex_position

	assert_ne(final_player_pos, initial_player_pos, "Player ship should have moved")
	assert_ne(final_ai_pos, initial_ai_pos, "AI ship should have moved")


func test_ships_move_each_turn() -> void:
	_setup_two_ship_scenario()
	_start_game()

	var pc = GameState.phase_controller
	var positions: Array = []
	positions.append(GameState.get_ship("player_1").hex_position)

	for turn_idx in range(3):
		_run_one_turn(pc)
		positions.append(GameState.get_ship("player_1").hex_position)

	for i in range(positions.size() - 1):
		assert_ne(positions[i], positions[i + 1],
			"Ship should move between turn %d and %d" % [i + 1, i + 2])


func test_plotted_actions_cleared_after_resolution() -> void:
	_setup_two_ship_scenario()
	_start_game()

	var pc = GameState.phase_controller

	if GameState.stub_ai:
		GameState.stub_ai.plot_all_ai_ships()
	_plot_player_ship_forward("player_1")

	var player = GameState.get_ship("player_1")
	var ai = GameState.get_ship("ai_1")
	assert_gt(player.plotted_actions.movement.size(), 0, "Player should have plotted before resolution")
	assert_gt(ai.plotted_actions.movement.size(), 0, "AI should have plotted before resolution")

	pc.player_submit_plan(0)
	pc.player_submit_plan(1)
	pc.on_playback_completed()

	assert_eq(player.plotted_actions.movement.size(), 0, "Player plot cleared after resolution")
	assert_eq(ai.plotted_actions.movement.size(), 0, "AI plot cleared after resolution")


func test_turn_counter_increments() -> void:
	_setup_two_ship_scenario()
	_start_game()

	var pc = GameState.phase_controller
	assert_eq(pc.current_turn, 1)

	_run_one_turn(pc)
	assert_eq(pc.current_turn, 2)

	_run_one_turn(pc)
	assert_eq(pc.current_turn, 3)


# ===========================================================================
# Determinism
# ===========================================================================

func test_deterministic_resolution_with_same_seed() -> void:
	var logs: Array = []

	for run_idx in range(2):
		# Full reset
		GameState.ships.clear()
		GameState.ships_by_player.clear()
		GameState.clear_state_history()
		GameState.current_turn = 0
		GameState.current_phase = GameState.GamePhase.SETUP

		if GameState.movement_plotting_controller:
			GameState.movement_plotting_controller.sessions.clear()
			GameState.movement_plotting_controller.ship_sessions.clear()

		# Deterministic seeds — same for both runs
		if GameState.environment_controller:
			GameState.environment_controller.rng.seed = 500

		var test_rng = RandomNumberGenerator.new()
		test_rng.seed = 600
		GameState.movement_resolver = MovementResolver.new(GameState, test_rng)

		_setup_two_ship_scenario()
		_start_game()

		var pc = GameState.phase_controller
		var run_log: Array = []

		for turn_idx in range(3):
			if GameState.stub_ai:
				GameState.stub_ai.plot_all_ai_ships()
			_plot_player_ship_forward("player_1")

			pc.player_submit_plan(0)
			pc.player_submit_plan(1)

			var res_log = pc._pending_resolution_log
			if res_log:
				var turn_data = {}
				for result in res_log.ship_results.values():
					turn_data[result.ship_id] = {
						"final_hex": result.final_hex,
						"final_facing": result.final_facing,
					}
				run_log.append(turn_data)

			pc.on_playback_completed()
			pc.advance_phase()  # POST_COMBAT → END_TURN
			pc.advance_phase()  # END_TURN → new turn → ENVIRONMENT → PLANNING

		logs.append(run_log)

	assert_eq(logs[0].size(), logs[1].size(), "Both runs should produce same number of turns")
	for i in range(logs[0].size()):
		assert_eq(logs[0][i], logs[1][i],
			"Turn %d resolution should be identical across runs" % (i + 1))
