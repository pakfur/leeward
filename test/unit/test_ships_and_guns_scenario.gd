extends GutTest
## test_ships_and_guns: a 100, the two-decker Diomede (medium guns) and the frigate Arethusa against a
## French 80, the corvette Babet and the brig Coureur; every player AI (sub-project 6).

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
	return GameState.start_scenario(DataManager.load_scenario("test_ships_and_guns"), humans)


## One turn with every player AI (as test_towing_scenario.gd).
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


func _shot_at(ship_id: String, side: int, target_id: String) -> bool:
	for shot in GameState.gunnery_calculator.eligible_shots(ship_id):
		if shot.order.side == side and shot.order.target_id == target_id:
			return true
	return false


func test_scenario_places_cleanly() -> void:
	assert_true(_start())
	assert_eq(GameState.placement_errors(), [] as Array[String])
	var diomede: ShipState = GameState.get_ship("br_44_diomede")
	assert_eq(FireRules.lower_deck_modifier(diomede, ShipState.STARBOARD, 3, 4), -4,
			"sea 3 = freeboard 3: the leeward (starboard) lower deck is shut")
	assert_eq(FireRules.lower_deck_modifier(diomede, ShipState.PORT, 3, 4), 0, "the windward side is open")
	assert_true(_shot_at("br_38", GunneryTypes.CHASE_BOW, "fr_20_babet"), "Arethusa's bow chaser bears on Babet")
	assert_true(_shot_at("fr_20_babet", GunneryTypes.CHASE_STERN, "br_38"), "Babet's stern chaser bears on Arethusa")


func test_scenario_plays_to_the_end_cleanly() -> void:
	assert_true(_start())
	for i in range(15):
		if not pc.game_result.is_empty():
			break
		_play_turn()
	# GUT fails the test on any push_error raised during the run.
	assert_true(pc.current_turn >= 15 or not pc.game_result.is_empty(), "the loop ran to game over or turn 15")
	var fires := 0
	for turn in GameState.turn_logs:
		fires += GameState.turn_logs[turn].of_type(PhaseEvents.Type.FIRE).size()
	assert_true(fires >= 1, "at least one FIRE event in the run (%d)" % fires)
