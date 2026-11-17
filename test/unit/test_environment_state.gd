extends GutTest
## Sea state 0-5 (names, clamping) and the heavy-weather scenario.

func after_each() -> void:
	var pc: TurnPhaseController = GameState.phase_controller
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	pc.players_ready = [false, false] as Array[bool]
	GameState.clear_ships()

func test_sea_state_names_cover_zero_to_five() -> void:
	assert_eq(EnvironmentState.sea_state_name(0), "calm")
	assert_eq(EnvironmentState.sea_state_name(1), "slight")
	assert_eq(EnvironmentState.sea_state_name(2), "moderate")
	assert_eq(EnvironmentState.sea_state_name(3), "rough")
	assert_eq(EnvironmentState.sea_state_name(4), "very rough")
	assert_eq(EnvironmentState.sea_state_name(5), "high")
	assert_eq(EnvironmentState.SEA_STATE_MAX, 5)

func test_get_sea_state_name_uses_the_scale() -> void:
	var env := EnvironmentState.new()
	env.sea_state = 5
	assert_eq(env.get_sea_state_name(), "high")

func test_sea_state_clamped_on_load() -> void:
	var env := EnvironmentState.new()
	env.initialize_from_scenario({"sea_state": 7})
	assert_eq(env.sea_state, 5)
	env.initialize_from_scenario({"sea_state": -1})
	assert_eq(env.sea_state, 0)
	env.initialize_from_scenario({"sea_state": 1})
	assert_eq(env.sea_state, 1)
	assert_eq(EnvironmentState.deserialize({"sea_state": 9}).sea_state, 5)

func test_heavy_weather_scenario_loads_with_valid_placements() -> void:
	GameState.start_scenario(DataManager.load_scenario("test_heavy_weather"), [] as Array[int])
	assert_eq(GameState.placement_errors(), [] as Array[String])
	assert_eq(GameState.get_all_ships().size(), 3)
	assert_eq(GameState.environment.sea_state, 4)
	assert_eq(GameState.environment.wind_speed, 4)
