extends GutTest
## Tests for PhaseEvents (per-turn phase event log).

const NAMES := {"s1": "Surprise", "s2": "Renard"}


func _fire_data() -> Dictionary:
	return {
		"side": 1, "range": 3, "aim": "low", "ammo": "round", "bgn": 22,
		"modifiers": [
			{"name": "crew_quality", "value": 2},
			{"name": "initial_broadside", "value": 3},
		],
		"mgn": 27, "d6": 4, "fgn": 31,
		"rigging": 2, "hull": 1, "crew": 1, "rake": "",
	}


func test_add_appends_in_order_and_sets_fields() -> void:
	var log := PhaseEvents.PhaseLog.new()
	log.turn = 3
	var a := log.add(PhaseEvents.Type.FIRE, 4, "s1", {"d6": 4}, "s2")
	var b := log.add(PhaseEvents.Type.DAMAGE, 4, "s2")
	assert_eq(log.events.size(), 2)
	assert_eq(log.events[0], a)
	assert_eq(log.events[1], b)
	assert_eq(a.type, PhaseEvents.Type.FIRE)
	assert_eq(a.phase, 4)
	assert_eq(a.ship_id, "s1")
	assert_eq(a.target_id, "s2")
	assert_eq(a.data["d6"], 4)
	assert_eq(b.target_id, "")
	assert_eq(b.data, {})


func test_of_type_filters() -> void:
	var log := PhaseEvents.PhaseLog.new()
	log.add(PhaseEvents.Type.FIRE, 4, "s1")
	log.add(PhaseEvents.Type.DAMAGE, 4, "s2")
	log.add(PhaseEvents.Type.FIRE, 4, "s2")
	assert_eq(log.of_type(PhaseEvents.Type.FIRE).size(), 2)
	assert_eq(log.of_type(PhaseEvents.Type.DAMAGE).size(), 1)
	assert_eq(log.of_type(PhaseEvents.Type.VICTORY).size(), 0)


func test_fire_to_text_reads_as_a_sentence_with_all_numbers() -> void:
	var ev := PhaseEvents.PhaseLog.new().add(PhaseEvents.Type.FIRE, 4, "s1", _fire_data(), "s2")
	assert_eq(ev.to_text(NAMES), "Surprise fires starboard at Renard, range 3, low, roundshot — "
		+ "base 22, crew +2, initial broadside +3 = 27, d6 4 → 31: 2 rigging, 1 hull, 1 crew")


func test_fire_to_text_matches_the_spec_example() -> void:
	var data := {"side": 1, "range": 2, "aim": "low", "ammo": "round", "bgn": 18,
		"modifiers": [{"name": "initial_broadside", "value": 4}], "mgn": 22, "d6": 4, "fgn": 26,
		"rigging": 0, "hull": 1, "crew": 1, "rake": ""}
	var ev := PhaseEvents.PhaseLog.new().add(PhaseEvents.Type.FIRE, 4, "s1", data, "s2")
	assert_eq(ev.to_text(NAMES), "Surprise fires starboard at Renard, range 2, low, roundshot — "
		+ "base 18, initial broadside +4 = 22, d6 4 → 26: 1 hull, 1 crew")


func test_fire_to_text_negative_modifier_rake_and_dismantling() -> void:
	var data := _fire_data()
	data["modifiers"] = [{"name": "two_targets", "value": -12}]
	data["rake"] = "stern"
	data["ammo"] = "dismantling"
	data["side"] = 0
	var text := PhaseEvents.PhaseLog.new().add(PhaseEvents.Type.FIRE, 4, "s1", data, "s2").to_text(NAMES)
	assert_string_contains(text, "fires port at Renard")
	assert_string_contains(text, "two targets -12")
	assert_string_contains(text, "dismantling shot, stern rake —")
	assert_false(text.contains("BGN"), text)


func test_fire_without_modifiers_or_damage_says_no_damage() -> void:
	var data := {"side": 0, "range": 9, "aim": "low", "ammo": "round", "bgn": 2,
		"modifiers": [], "mgn": 2, "d6": 1, "fgn": 3, "rigging": 0, "hull": 0, "crew": 0, "rake": ""}
	var text := PhaseEvents.PhaseLog.new().add(PhaseEvents.Type.FIRE, 4, "s1", data, "s2").to_text(NAMES)
	assert_eq(text, "Surprise fires port at Renard, range 9, low, roundshot — base 2, d6 1 → 3: no damage")


func test_hold_fire_text() -> void:
	var ev := PhaseEvents.PhaseLog.new().add(PhaseEvents.Type.HOLD_FIRE, 4, "s1")
	assert_eq(ev.to_text(NAMES), "Surprise holds fire.")


func test_to_text_tolerates_missing_data_for_every_type() -> void:
	var log := PhaseEvents.PhaseLog.new()
	for t in PhaseEvents.Type.values():
		var ev := log.add(t, 0, "s1", {}, "s2")
		assert_ne(ev.to_text(NAMES), "", "type %d renders" % t)
		assert_ne(ev.to_text({}), "", "type %d renders without names" % t)


func test_damage_names_sailors_and_marines_and_skips_zeros() -> void:
	var log := PhaseEvents.PhaseLog.new()
	var text := log.add(PhaseEvents.Type.DAMAGE, 4, "s2", {"rigging": 0, "hull": 1, "crew": 1,
		"sailors_lost": 0, "marines_lost": 1, "crew_rolls": [6]}).to_text(NAMES)
	assert_eq(text, "Renard loses 1 hull box, 1 marine")
	text = log.add(PhaseEvents.Type.DAMAGE, 4, "s2", {"rigging": 2, "hull": 3, "crew": 3,
		"sailors_lost": 2, "marines_lost": 1, "crew_rolls": [1, 2, 6]}).to_text(NAMES)
	assert_eq(text, "Renard loses 2 rigging boxes, 3 hull boxes, 2 sailors, 1 marine")
	assert_false(text.contains("["), "no raw roll arrays")


func test_damage_all_zero_and_legacy_crew_total() -> void:
	var log := PhaseEvents.PhaseLog.new()
	assert_eq(log.add(PhaseEvents.Type.DAMAGE, 4, "s2", {"rigging": 0, "hull": 0, "crew": 0,
		"sailors_lost": 0, "marines_lost": 0}).to_text(NAMES), "Renard takes no damage")
	assert_eq(log.add(PhaseEvents.Type.DAMAGE, 4, "s2", {"rigging": 0, "hull": 0, "crew": 2})
		.to_text(NAMES), "Renard loses 2 crew")


func test_guns_dismounted_text() -> void:
	var log := PhaseEvents.PhaseLog.new()
	assert_eq(log.add(PhaseEvents.Type.GUNS_DISMOUNTED, 4, "s2", {"amount": 1}).to_text(NAMES),
		"Renard has 1 gun dismounted on each broadside")
	assert_eq(log.add(PhaseEvents.Type.GUNS_DISMOUNTED, 4, "s2", {"amount": 3}).to_text(NAMES),
		"Renard has 3 guns dismounted on each broadside")


func test_morale_noted_maps_trigger_ids_to_phrases() -> void:
	var cases := {
		"hull_1": "first hull section lost", "hull_2": "second hull section lost",
		"hull_3": "third hull section lost", "crew_0": "first crew section lost",
		"crew_3": "fourth crew section lost", "crew_4": "all marines lost",
		"dismasted": "dismasted", "raked_dismasted_t3": "raked while dismasted",
	}
	var log := PhaseEvents.PhaseLog.new()
	for trigger in cases:
		var text := log.add(PhaseEvents.Type.MORALE_NOTED, 4, "s1",
			{"trigger": trigger, "count": 1}).to_text(NAMES)
		assert_eq(text, "Surprise must check morale (%s)" % cases[trigger])
		assert_false(text.contains(trigger) and trigger.contains("_"), "raw id hidden: %s" % text)
	assert_eq(log.add(PhaseEvents.Type.MORALE_NOTED, 4, "s1", {"trigger": "hull_3", "count": 2})
		.to_text(NAMES), "Surprise must check morale twice (third hull section lost)")


func test_morale_check_passes_and_fails() -> void:
	var log := PhaseEvents.PhaseLog.new()
	assert_eq(log.add(PhaseEvents.Type.MORALE_CHECK, 7, "s1",
		{"roll": 3, "rating": 4, "passed": false, "quality": "E"}).to_text(NAMES),
		"Surprise morale check: rolled 3, needed 4 — fails; crew quality drops to E")
	assert_eq(log.add(PhaseEvents.Type.MORALE_CHECK, 7, "s1",
		{"roll": 8, "rating": 4, "passed": true, "quality": "D"}).to_text(NAMES),
		"Surprise morale check: rolled 8, needed 4 — passes")


func test_sail_change_begin_complete_and_cancel() -> void:
	var log := PhaseEvents.PhaseLog.new()
	assert_eq(log.add(PhaseEvents.Type.SAIL_CHANGE, 3, "s1",
		{"from": "MS", "to": "FS", "turns_left": 1}).to_text(NAMES),
		"Surprise begins changing sail MS → FS (1 turn)")
	assert_eq(log.add(PhaseEvents.Type.SAIL_CHANGE, 3, "s1",
		{"from": "FS", "to": "PS", "turns_left": 2}).to_text(NAMES),
		"Surprise begins changing sail FS → PS (2 turns)")
	assert_eq(log.add(PhaseEvents.Type.SAIL_CHANGE, 6, "s1",
		{"from": "MS", "to": "FS", "turns_left": 0}).to_text(NAMES),
		"Surprise is now at fighting sail (FS)")
	assert_eq(log.add(PhaseEvents.Type.SAIL_CHANGE, 6, "s1",
		{"from": "MS", "to": "FS", "turns_left": 1, "cancelled": "no crew"}).to_text(NAMES),
		"Surprise: sail change to fighting sail (FS) cancelled: not enough crew to work the sails")


func test_strike_fouled_and_unfoul_sentences() -> void:
	var log := PhaseEvents.PhaseLog.new()
	assert_eq(log.add(PhaseEvents.Type.STRIKE, 7, "s1", {"reason": "morale"}).to_text(NAMES),
		"Surprise strikes her colours (the crew's morale broke)")
	assert_eq(log.add(PhaseEvents.Type.STRIKE, 4, "s1", {"reason": "no crew"}).to_text(NAMES),
		"Surprise strikes her colours (no crew left)")
	assert_eq(log.add(PhaseEvents.Type.FOULED, 5, "s1", {}, "s2").to_text(NAMES),
		"Surprise drifts into Renard; the two ships are fouled")
	assert_eq(log.add(PhaseEvents.Type.UNFOUL, 6, "s1",
		{"roll": 3, "modifier": 1, "needed": 8, "success": true}, "s2").to_text(NAMES),
		"Surprise tries to cut free of Renard: rolled 3 +1, needed 8 or less — frees herself")
	assert_eq(log.add(PhaseEvents.Type.UNFOUL, 6, "s1",
		{"roll": 9, "modifier": 0, "needed": 2, "success": false}, "s2").to_text(NAMES),
		"Surprise tries to cut free of Renard: rolled 9, needed 2 or less — stays fouled")


func test_victory_names_the_side_never_a_number() -> void:
	var log := PhaseEvents.PhaseLog.new()
	var win := log.add(PhaseEvents.Type.VICTORY, 10, "", {"winner": 0, "reason": "all struck"}).to_text(NAMES)
	assert_eq(win, "Victory: you (every ship of one side has struck)")
	assert_eq(log.add(PhaseEvents.Type.VICTORY, 10, "", {"winner": 1, "reason": "turn limit"})
		.to_text(NAMES), "Victory: the enemy (turn limit reached)")
	assert_eq(log.add(PhaseEvents.Type.VICTORY, 10, "", {"winner": -1, "reason": "turn limit"})
		.to_text(NAMES), "Draw (turn limit reached)")
	assert_false(win.contains("side 0"), win)


func test_to_dict_round_trips_through_json() -> void:
	var log := PhaseEvents.PhaseLog.new()
	log.turn = 2
	log.add(PhaseEvents.Type.FIRE, 4, "s1", _fire_data(), "s2")
	log.add(PhaseEvents.Type.DAMAGE, 4, "s2", {"crew_rolls": [1, 2]})
	var json := JSON.stringify(log.to_dict())
	assert_ne(json, "")
	var parsed: Variant = JSON.parse_string(json)
	assert_true(parsed is Dictionary)
	assert_eq(int(parsed["turn"]), 2)
	assert_eq(parsed["events"].size(), 2)
	assert_eq(parsed["events"][0]["ship_id"], "s1")
	assert_eq(JSON.stringify(log.events[0].to_dict()), JSON.stringify(log.events[0].to_dict()))


func test_game_state_has_turn_log_and_start_new_game_replaces_it() -> void:
	assert_not_null(GameState.turn_log)
	var old: PhaseEvents.PhaseLog = GameState.turn_log
	GameState.turn_logs[9] = old
	GameState.start_new_game({"seed": 1})
	assert_not_null(GameState.turn_log)
	assert_ne(GameState.turn_log, old)
	assert_true(GameState.turn_logs.is_empty())


func test_drift_renders_hexes_as_coordinates() -> void:
	var log := PhaseEvents.PhaseLog.new()
	var text := log.add(PhaseEvents.Type.DRIFT, 5, "s1", {
		"roll": 6, "needed": 5, "modifier": 0, "drifted": true,
		"from": {"q": 3, "r": -2}, "to": {"q": 2, "r": -2}}).to_text(NAMES)
	assert_eq(text, "Surprise drifts downwind from (3, -2) to (2, -2) (drift roll 6, needed 5)")
	assert_string_contains(text, "roll 6")
	assert_string_contains(text, "needed 5")
	assert_false(text.contains("{"), "no raw dictionary in: %s" % text)


func test_blocked_drift_keeps_numbers_and_shows_position() -> void:
	var log := PhaseEvents.PhaseLog.new()
	var text := log.add(PhaseEvents.Type.DRIFT, 5, "s1", {
		"roll": 7, "needed": 5, "modifier": 0, "drifted": false, "blocked": "map edge",
		"from": {"q": 3, "r": -2}}).to_text(NAMES)
	assert_string_contains(text, "roll 7")
	assert_string_contains(text, "needed 5")
	assert_string_contains(text, "blocked by the map edge")
	assert_string_contains(text, "(3, -2)")
	assert_false(text.contains("{"), "no raw dictionary in: %s" % text)


func test_failed_drift_roll_holds_position() -> void:
	var log := PhaseEvents.PhaseLog.new()
	var text := log.add(PhaseEvents.Type.DRIFT, 5, "s1", {
		"roll": 2, "needed": 5, "modifier": 0, "drifted": false,
		"from": {"q": 3, "r": -2}}).to_text(NAMES)
	assert_string_contains(text, "holds position")
	assert_string_contains(text, "roll 2")
	assert_string_contains(text, "needed 5")
	assert_false(text.contains("{"), "no raw dictionary in: %s" % text)
