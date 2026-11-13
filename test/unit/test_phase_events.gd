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


func test_fire_to_text_shows_all_numbers() -> void:
	var log := PhaseEvents.PhaseLog.new()
	var ev := log.add(PhaseEvents.Type.FIRE, 4, "s1", _fire_data(), "s2")
	var text := ev.to_text(NAMES)
	assert_string_contains(text, "Surprise")
	assert_string_contains(text, "Renard")
	assert_string_contains(text, "starboard")
	assert_string_contains(text, "range 3")
	assert_string_contains(text, "BGN 22")
	assert_string_contains(text, "+2 crew")
	assert_string_contains(text, "+3 initial broadside")
	assert_string_contains(text, "= 27")
	assert_string_contains(text, "d6 4")
	assert_string_contains(text, "31")
	assert_string_contains(text, "2 rigging, 1 hull, 1 crew")


func test_fire_to_text_negative_modifier_and_rake() -> void:
	var data := _fire_data()
	data["modifiers"] = [{"name": "two_targets", "value": -12}]
	data["rake"] = "stern"
	var ev := PhaseEvents.PhaseLog.new().add(PhaseEvents.Type.FIRE, 4, "s1", data, "s2")
	var text := ev.to_text(NAMES)
	assert_string_contains(text, "-12 two targets")
	assert_string_contains(text, "stern rake")


func test_to_text_tolerates_missing_data_for_every_type() -> void:
	var log := PhaseEvents.PhaseLog.new()
	for t in PhaseEvents.Type.values():
		var ev := log.add(t, 0, "s1", {}, "s2")
		assert_ne(ev.to_text(NAMES), "", "type %d renders" % t)
		assert_ne(ev.to_text({}), "", "type %d renders without names" % t)


func test_other_types_render_their_data() -> void:
	var log := PhaseEvents.PhaseLog.new()
	assert_string_contains(log.add(PhaseEvents.Type.DAMAGE, 4, "s2",
		{"rigging": 2, "hull": 1, "crew": 3, "crew_rolls": [4, 7]}).to_text(NAMES), "3 crew")
	assert_string_contains(log.add(PhaseEvents.Type.GUNS_DISMOUNTED, 4, "s2",
		{"amount": 5}).to_text(NAMES), "5")
	var drift := log.add(PhaseEvents.Type.DRIFT, 5, "s1",
		{"roll": 6, "needed": 5, "drifted": true}).to_text(NAMES)
	assert_string_contains(drift, "6")
	assert_string_contains(drift, "drift")
	assert_string_contains(log.add(PhaseEvents.Type.MORALE_CHECK, 7, "s1",
		{"roll": 8, "rating": 7, "passed": false, "quality": "C"}).to_text(NAMES), "8")
	assert_string_contains(log.add(PhaseEvents.Type.STRIKE, 7, "s1",
		{"reason": "morale"}).to_text(NAMES), "morale")
	assert_string_contains(log.add(PhaseEvents.Type.VICTORY, 10, "s1",
		{"winner": 1, "reason": "fleet struck"}).to_text(NAMES), "fleet struck")
	assert_string_contains(log.add(PhaseEvents.Type.SAIL_CHANGE, 6, "s1",
		{"from": "FS", "to": "PS", "turns_left": 2}).to_text(NAMES), "PS")
	assert_string_contains(log.add(PhaseEvents.Type.UNFOUL, 6, "s1",
		{"roll": 3, "modifier": 1, "needed": 8, "success": false}, "s2").to_text(NAMES), "Renard")


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
	assert_string_contains(text, "drifts from (3, -2) to (2, -2)")
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
	assert_string_contains(text, "blocked by map edge")
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
