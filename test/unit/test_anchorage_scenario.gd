extends GutTest
## test_anchorage: two French frigates ride at anchor against a British squadron; every player AI
## (anchoring spec §7, §9).

const PHASES := TurnPhaseController.GamePhase
const FRENCH: Array[String] = ["fr_frigate_38", "fr_frigate_32"]

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
	return GameState.start_scenario(DataManager.load_scenario("test_anchorage"), humans)


## One turn with every player AI (as test_map_scenarios.gd).
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


func test_anchorage_places_cleanly() -> void:
	assert_true(_start())
	assert_eq(GameState.placement_errors(), [] as Array[String])
	for id in FRENCH:
		var ship: ShipState = GameState.get_ship(id)
		assert_true(ship.is_anchored(), "%s starts anchored" % id)
		assert_eq(ship.anchorings_used, 1)
	assert_true(GameState.get_ship("fr_frigate_38").has_springs())
	assert_false(GameState.get_ship("br_ship_of_line").is_anchored())


func test_anchorage_plays_twelve_turns_cleanly() -> void:
	assert_true(_start())
	var fired_by_french := false
	for i in range(12):
		if not pc.game_result.is_empty():
			break
		_play_turn()
		for id in FRENCH:
			var ship: ShipState = GameState.get_ship(id)
			assert_true(ship.is_anchored() or ship.is_out_of_play(),
					"%s still at anchor (or out of play) after turn %d" % [id, pc.current_turn])
	for turn in GameState.turn_logs:
		var log: PhaseEvents.PhaseLog = GameState.turn_logs[turn]
		for ev in log.of_type(PhaseEvents.Type.FIRE):
			if FRENCH.has(ev.ship_id):
				fired_by_french = true
	assert_true(pc.current_turn >= 12 or not pc.game_result.is_empty(), "the loop ran its turns")
	assert_true(fired_by_french, "a French ship fired at some point")
