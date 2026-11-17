extends GutTest
## Ending the game by agreement (2.A.1).

const PHASES := TurnPhaseController.GamePhase


func _start(humans: Array[int]) -> void:
	var s := DataManager.load_scenario("test_squadron").duplicate(true)
	assert_true(GameState.start_scenario(s, humans))


func after_each() -> void:
	var pc := _pc()
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = PHASES.SETUP
	pc.game_result = {}
	pc.players_ready = {0: false, 1: false}
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()
	GameState.end_offers = {}


func _pc() -> TurnPhaseController:
	return GameState.phase_controller


func _strike(player_id: int, flag: String) -> void:
	for s in GameState.ships_of_player(player_id):
		if s.ship.flag == flag:
			s.status = ShipState.Status.STRUCK


func test_only_senior_human_may_offer() -> void:
	_start([0, 1, 2, 3] as Array[int])
	_pc().current_phase = PHASES.PLANNING
	assert_ne(_pc().player_offer_end(1, true), "")
	assert_false(GameState.end_offers.get(0, false))
	assert_eq(_pc().player_offer_end(0, true), "")
	assert_true(GameState.end_offers[0])


func test_senior_passes_when_flagship_struck() -> void:
	_start([0, 1, 2, 3] as Array[int])
	assert_eq(GameState.senior_human_player(1), 2)
	_strike(2, "fleet")
	assert_eq(GameState.senior_human_player(1), 3)
	_strike(0, "fleet")
	assert_eq(GameState.senior_human_player(0), 0)


func test_game_ends_when_all_sides_agree() -> void:
	_start([0, 1, 2, 3] as Array[int])
	_pc().current_phase = PHASES.POST_COMBAT
	assert_eq(_pc().player_offer_end(0, true), "")
	assert_eq(_pc().player_offer_end(2, true), "")
	_pc()._enter_end_turn_phase()
	assert_eq(_pc().game_result.get("reason"), "agreement")
	assert_ne(_pc().player_offer_end(0, false), "")  # over: refused


func test_offer_withdrawn() -> void:
	_start([0, 1, 2, 3] as Array[int])
	_pc().current_phase = PHASES.POST_COMBAT
	_pc().player_offer_end(0, true)
	_pc().player_offer_end(2, true)
	_pc().player_offer_end(2, false)
	_pc()._enter_end_turn_phase()
	assert_true(_pc().game_result.is_empty())


func test_ai_side_never_agrees() -> void:
	_start([0, 1] as Array[int])
	_pc().current_phase = PHASES.POST_COMBAT
	assert_eq(_pc().player_offer_end(0, true), "")
	_pc()._enter_end_turn_phase()
	assert_true(_pc().game_result.is_empty())


func test_equal_points_draw() -> void:
	_start([0, 1, 2, 3] as Array[int])
	_pc().current_phase = PHASES.POST_COMBAT
	_pc().player_offer_end(0, true)
	_pc().player_offer_end(2, true)
	var r: Dictionary = GameState.victory_controller.check(1)
	assert_eq(r["reason"], "agreement")
	assert_eq(r["winner"], -1)


func test_more_points_wins() -> void:
	_start([0, 1, 2, 3] as Array[int])
	_pc().current_phase = PHASES.POST_COMBAT
	_pc().player_offer_end(0, true)
	_pc().player_offer_end(2, true)
	for s in GameState.ships_of_player(2):
		s.status = ShipState.Status.STRUCK
	var r: Dictionary = GameState.victory_controller.check(1)
	assert_eq(r["winner"], 0)


func test_panel_text() -> void:
	assert_eq(GameOverPanel.reason_text("agreement", {"struck": 0, "total": 2}, {"struck": 0, "total": 2}), "Ended by agreement")
	assert_eq(GameOverPanel.headline(-1), "Draw")
