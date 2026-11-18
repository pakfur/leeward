extends GutTest
## test_optional_rules: two lines of two, wind from the north-east, every optional rule of 14 on
## (voluntary surrender, fatigue, gunfire limits "both"); every player AI (sub-project 7).

const PHASES := TurnPhaseController.GamePhase

var pc: TurnPhaseController


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller


func after_each() -> void:
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = PHASES.SETUP
	pc.game_result = {}
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()
	GameState.turn_logs = {}


func _start() -> bool:
	var humans: Array[int] = []
	return GameState.start_scenario(DataManager.load_scenario("test_optional_rules"), humans)


## One turn with every player AI (as test_ships_and_guns_scenario.gd).
func _play_turn() -> void:
	var start_turn := pc.current_turn
	var guard := 0
	while pc.game_result.is_empty() and pc.current_turn == start_turn and guard < 40:
		guard += 1
		match pc.current_phase:
			PHASES.MOVEMENT_RESOLUTION:
				pc.on_playback_completed()
			PHASES.COMBAT_RESOLUTION:
				if pc.combat_step != TurnPhaseController.CombatStep.RESOLVE:
					break
				pc.on_combat_playback_completed()
			PHASES.POST_COMBAT:
				for id in GameState.player_ids():
					pc.player_end_turn(id)
			_:
				break


func test_scenario_places_cleanly() -> void:
	assert_true(_start())
	assert_eq(GameState.placement_errors(), [] as Array[String])
	assert_eq(OptionalRules.of(GameState.active_scenario),
			{"voluntary_surrender": true, "fatigue": true, "gunfire_limits": "both"})
	assert_true(FireRules.fires_to_windward(0, 5, ShipState.PORT), "side 0 (WF C): the port broadside is to windward")
	assert_false(FireRules.fires_to_windward(0, 5, ShipState.STARBOARD))
	assert_true(FireRules.fires_to_windward(3, 5, ShipState.STARBOARD), "side 1 (WF B): the starboard broadside is to windward")
	assert_false(FireRules.fires_to_windward(3, 5, ShipState.PORT))


func test_scenario_plays_to_the_end_cleanly() -> void:
	assert_true(_start())
	for i in range(30):
		if not pc.game_result.is_empty():
			break
		_play_turn()
	# GUT fails the test on any push_error raised during the run.
	assert_true(pc.current_turn >= 30 or not pc.game_result.is_empty(), "the loop ran to game over or turn 30")
	var aim_rolls := 0
	var fatigued := 0
	var surrenders := 0
	for turn in GameState.turn_logs:
		var turn_log: PhaseEvents.PhaseLog = GameState.turn_logs[turn]
		surrenders += turn_log.of_type(PhaseEvents.Type.SURRENDER).size()
		for event in turn_log.of_type(PhaseEvents.Type.FIRE):
			if event.data.has("aim_roll"):
				aim_rolls += 1
			for m in event.data.get("modifiers", []):
				if m.get("name", "") == "fatigue":
					fatigued += 1
	var most := 0
	for ship in GameState.ships.values():
		most = maxi(most, ship.gunfire_turns)
	Trace.trace_log("OptionalRules", "scenario run: %d aim rolls, %d fatigued shots, %d surrenders, most firing turns %d"
			% [aim_rolls, fatigued, surrenders, most])
	assert_true(aim_rolls >= 1, "a CQ E crew's low shot rolled the 14.E d6 (%d)" % aim_rolls)
	# The game may end before any ship's 6th firing turn; then only the count is known.
	if most >= 6:
		assert_true(fatigued >= 1, "a ship past her fifth firing turn fired with the fatigue modifier (most %d)" % most)
	else:
		assert_true(most >= 1, "the highest gunfire_turns seen was %d (game ended before a 6th firing turn)" % most)
