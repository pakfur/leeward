extends GutTest
## Signalling (4.A.4, 11.A.3-5, 11.B.2, 8.G.1e): sending in PLANNING, delivery at MESSAGE_DELIVERY.

const PHASES := TurnPhaseController.GamePhase

func before_each() -> void:
	_reset()
	var s := DataManager.load_scenario("test_squadron").duplicate(true)
	assert_true(GameState.start_scenario(s, [0, 1] as Array[int]))
	if _pc().current_phase != PHASES.PLANNING:
		_pc().advance_phase()
	assert_eq(_pc().current_phase, PHASES.PLANNING)


func after_each() -> void:
	_reset()


func _pc() -> TurnPhaseController:
	return GameState.phase_controller


func _reset() -> void:
	var pc := _pc()
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = PHASES.SETUP
	pc.players_ready = {0: false, 1: false}
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()
	GameState.signals.clear()


func _fleet() -> Dictionary:
	return {"kind": "fleet", "name": ""}


func test_flagship_sends_seven_words_in_1805() -> void:
	assert_eq(_pc().player_send_signal(0, "brit_a1", _fleet(), "one two three four five six seven"), "")
	assert_ne(_pc().player_send_signal(0, "brit_a1", _fleet(), "one two three four five six seven eight"), "")


func test_captain_limited_to_three() -> void:
	var r := _pc().player_send_signal(0, "brit_a2", _fleet(), "one two three four")
	assert_ne(r, "")
	assert_true(r.contains("3"))
	var r1 := _pc().player_send_signal(1, "brit_b1", _fleet(), "one two three four")
	assert_true(r1.contains("3"))
	assert_eq(_pc().player_send_signal(1, "brit_b1", _fleet(), "one two three"), "")


func test_halyards_cut_blocks_every_ship_of_the_player() -> void:
	GameState.ship_controller.add_critical_effect("brit_a2", {"id": "signal_halyards_cut"})
	assert_ne(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")


func test_struck_ship_with_halyards_cut_does_not_block_the_player() -> void:
	GameState.ship_controller.add_critical_effect("brit_a2", {"id": "signal_halyards_cut"})
	GameState.ships["brit_a2"].status = ShipState.Status.STRUCK
	assert_eq(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")


func test_captured_prize_with_halyards_cut_does_not_block_the_captor() -> void:
	var prize: ShipState = GameState.ships["fr_a1"]
	prize.commander_id = 0
	prize.status = ShipState.Status.CAPTURED
	GameState.ship_controller.add_critical_effect("fr_a1", {"id": "signal_halyards_cut"})
	assert_true(GameState.ships_of_player(0).has(prize))
	assert_eq(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")


func test_queries_return_copies() -> void:
	assert_eq(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")
	_pc().pending_signal(0).words.append("EXTRA")
	_pc().pending_signal(0).delivered = true
	assert_eq(GameState.signals[0].words, ["ATTACK"] as Array[String])
	assert_false(GameState.signals[0].delivered)
	GameState.signals[0].delivered = true
	_pc().signals_for(0)[0].words.append("EXTRA")
	assert_eq(GameState.signals[0].words.size(), 1)


func test_struck_ship_cannot_signal() -> void:
	GameState.ships["brit_a1"].status = ShipState.Status.STRUCK
	assert_ne(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")


func test_dismasted_ship_cannot_signal() -> void:
	var s: ShipState = GameState.ships["brit_a1"]
	for i in s.rigging_current_hp.size():
		s.rigging_current_hp[i] = 0
	assert_true(s.is_dismasted())
	assert_ne(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")


func test_unknown_group_refused() -> void:
	assert_ne(_pc().player_send_signal(0, "brit_a1", {"kind": "group", "name": "Nowhere"}, "attack"), "")
	assert_eq(_pc().player_send_signal(0, "brit_a1", {"kind": "group", "name": "Van"}, "attack"), "")


func test_enemy_ship_address_refused() -> void:
	assert_ne(_pc().player_send_signal(0, "brit_a1", {"kind": "ship", "name": "fr_a1"}, "attack"), "")
	assert_eq(_pc().player_send_signal(0, "brit_a1", {"kind": "ship", "name": "brit_b1"}, "attack"), "")


func test_not_own_ship_refused() -> void:
	assert_ne(_pc().player_send_signal(0, "brit_b1", _fleet(), "attack"), "")


func test_second_signal_replaces_first() -> void:
	assert_eq(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")
	assert_eq(_pc().player_send_signal(0, "brit_a1", _fleet(), "retire"), "")
	assert_eq(GameState.signals.size(), 1)
	assert_eq(_pc().pending_signal(0).words, ["RETIRE"] as Array[String])
	assert_eq(_pc().player_cancel_signal(0), "")
	assert_null(_pc().pending_signal(0))


func test_refused_after_plan_submitted() -> void:
	_pc().players_ready[0] = true
	assert_ne(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")
	assert_ne(_pc().player_cancel_signal(0), "")


func test_refused_outside_planning() -> void:
	_pc().current_phase = PHASES.COMBAT_RESOLUTION
	assert_ne(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")


func test_ships_addressed() -> void:
	_pc().player_send_signal(0, "brit_a1", {"kind": "group", "name": "Van"}, "attack")
	assert_eq(_pc().ships_addressed(_pc().pending_signal(0)), ["brit_a1", "brit_a2"] as Array[String])
	_pc().player_send_signal(0, "brit_a1", _fleet(), "attack")
	assert_eq(_pc().ships_addressed(_pc().pending_signal(0)).size(), 3)


func _to_post_combat() -> void:
	_pc().player_submit_plan(0)
	_pc().player_submit_plan(1)
	if _pc().current_phase == PHASES.MOVEMENT_RESOLUTION:
		_pc().on_playback_completed()
	if _pc().current_phase == PHASES.COMBAT_RESOLUTION:
		for id in [0, 1]:
			_pc().player_submit_fire_orders(id, [])
		_pc().on_combat_playback_completed()


func test_delivered_at_message_delivery() -> void:
	assert_eq(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")
	assert_true(_pc().signals_for(1).is_empty())
	_to_post_combat()
	assert_eq(_pc().current_phase, PHASES.POST_COMBAT)
	assert_eq(_pc().signals_for(1).size(), 1)
	assert_eq(_pc().signals_for(1)[0].from_player, 0)
	assert_true(_pc().signals_for(1)[0].delivered)
	assert_true(_pc().signals_for(2).is_empty())


func test_struck_after_sending_still_delivered() -> void:
	assert_eq(_pc().player_send_signal(0, "brit_a1", _fleet(), "attack"), "")
	GameState.ships["brit_a1"].status = ShipState.Status.STRUCK
	_to_post_combat()
	assert_eq(_pc().signals_for(0).size(), 1)


func test_signal_event_logged() -> void:
	_pc().player_send_signal(1, "brit_b1", _fleet(), "attack")
	_pc().player_send_signal(0, "brit_a1", {"kind": "group", "name": "Van"}, "form line")
	_to_post_combat()
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SIGNAL)
	assert_eq(events.size(), 2)
	assert_eq(events[0].ship_id, "brit_a1")
	assert_eq(int(events[0].data["from_player"]), 0)
	assert_eq(events[0].data["address"]["kind"], "group")
	assert_eq(events[0].data["words"], ["FORM", "LINE"])
	assert_eq(events[1].ship_id, "brit_b1")
	assert_ne(events[0].to_text({}), "")
