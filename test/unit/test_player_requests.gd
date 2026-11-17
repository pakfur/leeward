extends GutTest
## Requests checked against the commanding player (players/side split, step 3), on test_squadron:
## side 0 is players 0 (brit_a1, brit_a2) and 1 (brit_b1), side 1 players 2 (fr_a1, fr_a2) and
## 3 (fr_b1).

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
	pc.is_server = true
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.game_result = {}
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.current_phase = PHASES.SETUP
	pc.players_ready = {0: false, 1: false}
	GameState.boarding_actions = []
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()


func _start(humans: Array[int]) -> void:
	assert_true(GameState.start_scenario(DataManager.load_scenario("test_squadron").duplicate(true), humans))
	assert_eq(pc.current_phase, PHASES.PLANNING)


## From PLANNING (every human's plan already in) to POST_COMBAT, firing nothing.
func _to_post_combat(humans: Array) -> void:
	if pc.current_phase == PHASES.MOVEMENT_RESOLUTION:
		pc.on_playback_completed()
	if pc.current_phase == PHASES.COMBAT_RESOLUTION and pc.combat_step == TurnPhaseController.CombatStep.DECLARE:
		for p in humans:
			if not GameState.in_play_ships_of_player(p).is_empty():
				assert_eq(pc.player_submit_fire_orders(p, []), "")
	if pc.current_phase == PHASES.COMBAT_RESOLUTION and pc.combat_step == TurnPhaseController.CombatStep.RESOLVE:
		pc.on_combat_playback_completed()
	assert_eq(pc.current_phase, PHASES.POST_COMBAT)


func _ids(ships: Array) -> Array:
	var out: Array = []
	for s in ships:
		out.append(s.ship_id)
	out.sort()
	return out


func test_teammate_cannot_plot_anothers_ship() -> void:
	_start([0, 1] as Array[int])
	var options: Dictionary = pc.course_options("brit_a1")
	var hex: Vector2i = (options["valid_next"] as MovementTypes.ValidNextHexes).get_all_valid_moves()[0].hex
	assert_string_contains(pc.player_extend_course(1, "brit_a1", hex), "not this player's ship")
	assert_ne(pc.player_plot_sail_change(1, "brit_a1", ""), "")
	assert_ne(pc.player_set_crew_auto(1, "brit_a1", false), "")
	assert_eq(pc.player_extend_course(0, "brit_a1", hex), "", "the commander may")
	assert_eq(pc.player_set_crew_auto(1, "brit_b1", false), "", "player 1 commands brit_b1")


func test_planning_waits_for_every_player() -> void:
	_start([0, 1] as Array[int])
	assert_true(pc.is_player_ready(2), "AI players are ready at once")
	assert_true(pc.is_player_ready(3))
	assert_false(pc.is_player_ready(1))
	assert_true(pc.player_submit_plan(0))
	assert_eq(pc.current_phase, PHASES.PLANNING, "player 1 has not submitted")
	assert_true(pc.player_submit_plan(1))
	assert_ne(pc.current_phase, PHASES.PLANNING)


func test_plan_errors_cover_only_that_players_ships() -> void:
	_start([0, 1] as Array[int])
	GameState.ship_controller.set_ship_speed("brit_b1", 6)
	GameState.ship_controller.set_plotted_movement("brit_b1", [])  # 0 MPs from speed 6: too short
	assert_true(pc.plan_errors(1).has("brit_b1"))
	assert_false(pc.plan_errors(0).has("brit_b1"))
	assert_false(pc.player_submit_plan(1))
	assert_true(pc.player_submit_plan(0))


func test_end_turn_waits_for_every_human() -> void:
	_start([0, 1] as Array[int])
	pc.player_submit_plan(0)
	pc.player_submit_plan(1)
	_to_post_combat([0, 1])
	assert_false(pc.player_end_turn(2), "an AI player does not end the turn")
	assert_true(pc.player_end_turn(0))
	assert_eq(pc.current_phase, PHASES.POST_COMBAT, "player 1 has not ended the turn")
	assert_true(pc.ended_turn[0])
	assert_true(pc.player_end_turn(1))
	assert_eq(pc.current_turn, 2)
	assert_eq(pc.current_phase, PHASES.PLANNING)


func test_player_left_with_nothing_is_not_waited_on() -> void:
	_start([0, 1] as Array[int])
	GameState.damage_controller.strike("brit_b1", "test", PHASES.PLANNING)
	assert_true(pc.player_submit_plan(0))
	assert_ne(pc.current_phase, PHASES.PLANNING, "player 1 commands nothing in play")
	_to_post_combat([0, 1])
	assert_false(pc.player_end_turn(1), "nothing to command")
	assert_true(pc.player_end_turn(0))
	assert_eq(pc.current_turn, 2)
	assert_true(pc.is_player_ready(1), "ready at once at the next PLANNING")


func test_planning_with_every_player_ready_moves_on() -> void:
	_start([0] as Array[int])
	GameState.boarding_controller.capture(_action("fr_a1", "brit_a1"), false, PHASES.COMBAT_RESOLUTION)
	GameState.boarding_controller.capture(_action("fr_a2", "brit_a2"), false, PHASES.COMBAT_RESOLUTION)
	assert_true(GameState.in_play_ships_of_player(0).is_empty(), "player 0's ships are prizes")
	assert_true(pc.player_submit_plan(0))
	_to_post_combat([0])
	assert_true(pc.player_end_turn(0), "no human commands a ship in play: any human ends the turn")
	assert_true(pc.game_result.is_empty(), "side 0 still has brit_b1")
	assert_eq(pc.current_turn, 2)
	assert_ne(pc.current_phase, PHASES.PLANNING, "nobody to wait for: planning ends at once")


func test_fire_orders_only_for_own_ships() -> void:
	_start([0, 1] as Array[int])
	pc.current_phase = PHASES.COMBAT_RESOLUTION
	pc.combat_step = TurnPhaseController.CombatStep.DECLARE
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "brit_a1"
	order.target_id = "fr_a1"
	order.side = ShipState.PORT
	assert_string_contains(pc.player_submit_fire_orders(1, [order.to_dict()]), "not yours")
	assert_string_contains(pc.player_submit_fire_orders(1, [], [{"ship_id": "brit_a1", "target_id": "fr_a1"}]),
			"not yours")
	assert_eq(pc.player_submit_fire_orders(1, [], [{"ship_id": "brit_b1", "target_id": "fr_b1"}]).find("not yours"),
			-1, "brit_b1 is player 1's to command")
	assert_eq(pc.player_submit_fire_orders(1, []), "", "its own (empty) orders")


func test_prompts_go_to_the_commanding_player() -> void:
	_start([0, 1] as Array[int])
	pc.bear_off_prompt_player_ids = [1] as Array[int]
	assert_eq(pc._bear_off_prompt_ship_ids(GameState.get_all_ships()), ["brit_b1"])
	# brit_b1 (player 1) alongside fr_b1: the grapple is player 1's option, not player 0's.
	GameState.ship_controller.set_ship_position("fr_b1", Vector2i(-7, 4))
	GameState.ship_controller.set_ship_facing("fr_b1", 1)
	var for_one: Array = pc.maintenance_options(1, TurnPhaseController.MaintenanceStep.GRAPPLE)
	assert_eq(for_one.map(func(o: Dictionary) -> String: return o["ship_id"]), ["brit_b1"])
	assert_eq(pc.maintenance_options(0, TurnPhaseController.MaintenanceStep.GRAPPLE), [])


func test_prize_commanded_by_captor_player() -> void:
	_start([0, 1] as Array[int])
	var action := _action("brit_b1", "fr_b1")
	GameState.boarding_controller.capture(action, false, PHASES.COMBAT_RESOLUTION)
	assert_true(GameState.ships["fr_b1"].is_captured())
	assert_eq(GameState.commander_of("fr_b1"), 1)
	assert_eq(int(GameState.ships["fr_b1"].prize["original_commander"]), 3)


func test_retaken_ship_returns_to_original_commander() -> void:
	_start([0, 1] as Array[int])
	GameState.boarding_controller.capture(_action("brit_b1", "fr_a2"), false, PHASES.COMBAT_RESOLUTION)
	assert_eq(GameState.commander_of("fr_a2"), 1)
	GameState.boarding_controller.retake("fr_a2", "rose", PHASES.ENVIRONMENT)
	assert_false(GameState.ships["fr_a2"].is_captured())
	assert_eq(GameState.commander_of("fr_a2"), 2, "player 2 still commands fr_a1")


func test_retaken_ship_of_a_player_with_nothing_goes_to_lowest_player() -> void:
	_start([0, 1] as Array[int])
	GameState.boarding_controller.capture(_action("fr_a1", "brit_b1"), false, PHASES.COMBAT_RESOLUTION)
	assert_eq(GameState.commander_of("brit_b1"), 2)
	GameState.boarding_controller.retake("brit_b1", "rose", PHASES.ENVIRONMENT)
	assert_eq(GameState.commander_of("brit_b1"), 0, "player 1 commands nothing in play")


func test_ai_ships_are_ai_players_ships() -> void:
	_start([0, 1] as Array[int])
	assert_eq(_ids(GameState.stub_ai._get_ai_ships()), ["fr_a1", "fr_a2", "fr_b1"])
	after_each()
	_start([0] as Array[int])
	assert_eq(_ids(GameState.stub_ai._get_ai_ships()), ["brit_b1", "fr_a1", "fr_a2", "fr_b1"])
	assert_eq(pc.ai_player_ids, [1, 2, 3] as Array[int])


func test_players_ready_serialises_as_a_dictionary() -> void:
	_start([0, 1] as Array[int])
	var data := pc.serialize_phase_state()
	assert_true(data["players_ready"] is Dictionary)
	assert_eq((data["players_ready"] as Dictionary).size(), 4)
	pc.is_server = false
	pc.apply_phase_state(data)
	assert_true(pc.is_player_ready(2))
	pc.apply_phase_state({"current_phase": PHASES.PLANNING, "players_ready": [true, false]})
	assert_eq(pc.players_ready, {0: true, 1: false}, "the old [bool, bool] array still reads")
	pc.is_server = true


func _action(attacker: String, defender: String) -> BoardingAction:
	var action := BoardingAction.new()
	GameState.boarding_seq += 1
	action.id = GameState.boarding_seq
	action.attacker_id = attacker
	action.defender_id = defender
	action.attacker_sections = [0] as Array[int]
	action.state = BoardingAction.ENGAGED
	GameState.boarding_actions.append(action)
	return action
