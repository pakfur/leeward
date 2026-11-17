extends GutTest
## Limited information (14.C): PlayerView, the per-player projection of ships and the turn log.

const TYPES := PhaseEvents.Type
var _scenario: Dictionary


func before_each() -> void:
	_scenario = DataManager.load_scenario("test_squadron").duplicate(true)
	_start(_scenario)


func after_each() -> void:
	var pc: TurnPhaseController = GameState.phase_controller
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	pc.players_ready = {0: false, 1: false}
	GameState.dice = Dice.new(GameState.rng)
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()
	GameState.talks.clear()


func _start(scenario: Dictionary) -> void:
	assert_true(GameState.start_scenario(scenario, [0, 1] as Array[int]))
	GameState.talks.clear()


func _view() -> PlayerView:
	return GameState.player_view


func _turn() -> int:
	return GameState.turn_log.turn


func _events(player_id: int, type: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _view().events_for(player_id, _turn()):
		if int(e["type"]) == type:
			out.append(e)
	return out


func test_own_ship_full() -> void:
	var d: Dictionary = _view().ship_for(0, "brit_a1")
	assert_eq(d, GameState.get_ship("brit_a1").serialize())
	assert_true(d.has("rigging_current_hp"))
	assert_true(d.has("crew_count"))


func test_enemy_ship_sections_only() -> void:
	var s: ShipState = GameState.get_ship("fr_a1")
	s.rigging_current_hp = [0, 3, 6, 6] as Array[int]
	s.hull_current_hp = [0, 0, 5, 5] as Array[int]
	s.crew_count = [0, 2, 3, 3] as Array[int]
	s.marine_count = 0
	var d: Dictionary = _view().ship_for(0, "fr_a1")
	assert_eq(d["rigging_sections_lost"], 1)
	assert_eq(d["hull_sections_lost"], 2)
	assert_eq(d["crew_sections_lost"], 1)
	assert_true(d["marine_section_lost"])
	for key in ["rigging_current_hp", "hull_current_hp", "crew_count", "marine_count"]:
		assert_false(d.has(key), "%s hidden" % key)


func test_teammate_ship_also_limited() -> void:
	# 14.C.1: "to any other player, enemy or friendly": brit_b1 is player 1's, on player 0's side.
	var d: Dictionary = _view().ship_for(0, "brit_b1")
	assert_false(d.has("rigging_current_hp"))
	assert_eq(d["rigging_sections_lost"], 0)
	assert_true(_view().ship_for(1, "brit_b1").has("rigging_current_hp"))


func test_guns_and_crits_visible() -> void:
	var s: ShipState = GameState.get_ship("fr_a1")
	s.guns_dismounted = [2, 1] as Array[int]
	s.critical_effects = [{"id": "rudder_jammed", "side": -1, "seq": 1}]
	s.fire_list = [{"seq": 1, "created_turn": 1, "started_turn": 1, "cause": "test"}]
	var d: Dictionary = _view().ship_for(0, "fr_a1")
	assert_eq(d["guns_dismounted"], [2, 1])
	assert_eq(d["critical_effects"].size(), 1)
	assert_eq(d["fire_list"].size(), 1)
	for key in ["status", "position", "facing", "sail_state", "speed", "fouled_with", "grappled_with", "prize", "ship"]:
		assert_true(d.has(key), "%s shown" % key)


func test_tournament_shows_all() -> void:
	assert_true(_view().limited())
	GameState.clear_ships()
	_scenario["tournament"] = true
	_start(_scenario)
	assert_false(_view().limited())
	assert_eq(_view().ship_for(0, "fr_a1"), GameState.get_ship("fr_a1").serialize())


func test_ships_for_covers_all_sorted() -> void:
	var list: Array[Dictionary] = _view().ships_for(2)
	var ids: Array = []
	for d in list:
		ids.append(d["ship"]["ship_id"])
	var expected: Array = GameState.ships.keys()
	expected.sort()
	assert_eq(ids, expected)
	assert_false(list[0].has("crew_count"), "brit_a1 is not player 2's")


func test_enemy_damage_event_has_no_boxes() -> void:
	var s: ShipState = GameState.get_ship("fr_a1")
	s.rigging_current_hp = [2, 6, 6, 6] as Array[int]
	GameState.damage_controller.apply_hits("fr_a1", 3, 0, 0, "gunfire_at_hull", 0, "brit_a1")
	# The emptied section's Rigging Check may log more DAMAGE after it; the hits' own line is first.
	var own := _events(2, TYPES.DAMAGE)
	assert_eq(own[0]["data"]["rigging"], 3)
	assert_eq(own[0]["data"]["sections_emptied"], {"rigging": [0], "hull": [], "crew": []})
	var theirs := _events(0, TYPES.DAMAGE)
	assert_eq(theirs.size(), own.size())
	var data: Dictionary = theirs[0]["data"]
	for key in ["rigging", "hull", "crew", "sailors_lost", "marines_lost", "crew_rolls", "sections_emptied"]:
		assert_false(data.has(key), "%s hidden" % key)
	assert_eq(data["sections_lost"], 1)
	assert_false(data["marine_section_lost"])


func test_damage_event_marine_section_flag() -> void:
	var s: ShipState = GameState.get_ship("fr_a1")
	s.crew_count = [0, 0, 0, 0] as Array[int]
	s.marine_count = 1
	GameState.damage_controller.apply_crew_boxes("fr_a1", 1, true, 0, "brit_a1")
	var theirs := _events(0, TYPES.DAMAGE)
	assert_eq(theirs.size(), 1)
	assert_eq(theirs[0]["data"]["sections_lost"], 1)
	assert_true(theirs[0]["data"]["marine_section_lost"])


func test_own_damage_from_enemy_source_stays_full() -> void:
	GameState.damage_controller.apply_hits("brit_a1", 1, 1, 0, "gunfire_at_hull", 0, "fr_a1")
	var own := _events(0, TYPES.DAMAGE)
	assert_eq(own.size(), 1)
	assert_eq(own[0]["data"]["rigging"], 1)
	assert_eq(own[0]["data"]["hull"], 1)


func test_marine_fire_hides_firer_boxes_from_the_target() -> void:
	GameState.turn_log.add(TYPES.MARINE_FIRE, 0, "fr_a1", {"boxes": 7, "column": "7-8", "modifiers": [],
		"modifier": 0, "d6": 4, "total": 4, "crew": 1}, "brit_a1")
	var target_view := _events(0, TYPES.MARINE_FIRE)
	assert_false(target_view[0]["data"].has("boxes"))
	assert_eq(target_view[0]["data"]["crew"], 1)
	assert_eq(target_view[0]["data"]["column"], "7-8")
	var firer_view := _events(2, TYPES.MARINE_FIRE)
	assert_eq(firer_view[0]["data"]["boxes"], 7)
	assert_false(firer_view[0]["data"].has("crew"))


func test_boarding_round_hides_the_other_side_only() -> void:
	var side := {"sailors": 6, "marines": 2, "tbcf": 30, "lost_sailors": 1, "lost_marines": 0, "below": 0,
		"roll": 7, "drm": 1, "total": 8}
	GameState.turn_log.add(TYPES.BOARDING_ROUND, 0, "brit_a1", {"action": 1, "round": 1,
		"attacker": side.duplicate(), "defender": side.duplicate()}, "fr_a1")
	var data: Dictionary = _events(0, TYPES.BOARDING_ROUND)[0]["data"]
	assert_eq(data["attacker"]["sailors"], 6)
	assert_eq(data["attacker"]["tbcf"], 30)
	for key in ["sailors", "marines", "tbcf", "lost_sailors", "lost_marines", "below"]:
		assert_false(data["defender"].has(key), "defender %s hidden" % key)
	assert_eq(data["defender"]["total"], 8)


func test_tournament_events_full() -> void:
	GameState.clear_ships()
	_scenario["tournament"] = true
	_start(_scenario)
	GameState.damage_controller.apply_hits("fr_a1", 1, 0, 0, "gunfire_at_hull", 0, "brit_a1")
	assert_eq(_events(0, TYPES.DAMAGE)[0]["data"]["rigging"], 1)


func test_signal_event_hidden_from_enemy() -> void:
	GameState.turn_log.add(TYPES.SIGNAL, 0, "brit_a1", {"from_player": 0,
		"address": {"kind": "all", "name": ""}, "words": ["engage"]})
	assert_eq(_events(0, TYPES.SIGNAL).size(), 1)
	assert_eq(_events(1, TYPES.SIGNAL).size(), 1, "the sender's teammate reads it")
	assert_eq(_events(2, TYPES.SIGNAL).size(), 0)
	assert_eq(_events(3, TYPES.SIGNAL).size(), 0)


func test_signal_follows_sender_side_not_stamp() -> void:
	# The sending ship is captured before delivery: its stamp says side 1, the signal is side 0's.
	var ev: PhaseEvents.PhaseEvent = GameState.turn_log.add(TYPES.SIGNAL, 0, "brit_a1", {"from_player": 0,
		"address": {"kind": "all", "name": ""}, "words": ["engage"]})
	ev.sides["brit_a1"] = 1
	assert_eq(_events(0, TYPES.SIGNAL).size(), 1)
	assert_eq(_events(2, TYPES.SIGNAL).size(), 0)


func test_talk_event_only_to_talkers() -> void:
	GameState.talks.append({"id": "talk_1_brit_a2_brit_b1", "turn": _turn(), "ship_a": "brit_a2",
		"ship_b": "brit_b1", "first_player": 1, "second_player": 0, "messages": []})
	GameState.turn_log.add(TYPES.TALK, 0, "brit_b1", {"talk_id": "talk_1_brit_a2_brit_b1",
		"from_player": 1, "words": ["follow"]})
	assert_eq(_events(0, TYPES.TALK).size(), 1)
	assert_eq(_events(1, TYPES.TALK).size(), 1)
	assert_eq(_events(2, TYPES.TALK).size(), 0)
	assert_eq(_events(3, TYPES.TALK).size(), 0)


func test_events_for_past_turn_and_no_mutation() -> void:
	GameState.damage_controller.apply_hits("fr_a1", 1, 0, 0, "gunfire_at_hull", 0, "brit_a1")
	var turn := _turn()
	GameState.turn_logs[turn] = GameState.turn_log
	_view().events_for(0, turn)
	var ev: PhaseEvents.PhaseEvent = GameState.turn_log.of_type(TYPES.DAMAGE)[0]
	assert_eq(ev.data["rigging"], 1, "the log itself is untouched")
	assert_eq(_view().events_for(0, turn + 50), [] as Array[Dictionary])
	GameState.turn_logs.erase(turn)
