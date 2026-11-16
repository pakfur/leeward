extends GutTest
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
## Tests for the pure presentation helpers of the combat turn_log panel and ship status panel.

const LogPanel = preload("res://scripts/ui/combat_log_panel.gd")

const COMBAT := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const DRIFT := TurnPhaseController.GamePhase.DRIFT_CALCULATION


func _make_ship(id: String = "s1") -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": 0, "ship_name": "HMS Test", "ship_type": "frigate_38",
		"name": "38-gun Frigate", "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 4,
	})
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 4
	return state


func _log_with(entries: Array) -> PhaseEvents.PhaseLog:
	var turn_log := PhaseEvents.PhaseLog.new()
	turn_log.turn = 2
	for e in entries:
		turn_log.add(e[0], e[1], e[2], e[3] if e.size() > 3 else {})
	return turn_log


# --- Combat turn_log helpers -----------------------------------------------------

func test_phase_heading_names_turn_and_phase() -> void:
	assert_eq(LogPanel.phase_heading(3, COMBAT), "Turn 3 — Combat Resolution")
	assert_eq(LogPanel.phase_heading(1, DRIFT), "Turn 1 — Drift Calculation")


func test_entries_add_a_heading_when_the_phase_changes() -> void:
	var log := _log_with([
		[PhaseEvents.Type.FIRE, COMBAT, "a", {"bgn": 5}],
		[PhaseEvents.Type.DAMAGE, COMBAT, "b", {"hull": 1}],
		[PhaseEvents.Type.DRIFT, DRIFT, "a", {}],
	])
	var list: Array = LogPanel.entries(log, 0, 3, -1, {"a": "Alpha", "b": "Bravo"})
	assert_eq(list.size(), 5)  # heading, 2 lines, heading, 1 line
	assert_true(list[0]["heading"])
	assert_eq(list[0]["text"], "Turn 2 — Combat Resolution")
	assert_false(list[1]["heading"])
	assert_string_contains(list[2]["text"], "Bravo loses 1 hull box")
	assert_true(list[3]["heading"])
	assert_eq(list[3]["text"], "Turn 2 — Drift Calculation")


func test_entries_continue_a_phase_without_repeating_the_heading() -> void:
	var log := _log_with([
		[PhaseEvents.Type.FIRE, COMBAT, "a"],
		[PhaseEvents.Type.DAMAGE, COMBAT, "b"],
	])
	var list: Array = LogPanel.entries(log, 1, 2, COMBAT, {})
	assert_eq(list.size(), 1)
	assert_false(list[0]["heading"])


func test_entries_clamp_range_and_tolerate_null() -> void:
	var log := _log_with([[PhaseEvents.Type.FIRE, COMBAT, "a"]])
	assert_eq(LogPanel.entries(log, 0, 99, -1, {}).size(), 2)
	assert_eq(LogPanel.entries(log, 1, 1, -1, {}).size(), 0)
	assert_eq(LogPanel.entries(null, 0, 3, -1, {}).size(), 0)


func test_plan_window_keeps_the_most_recent_ten_turns() -> void:
	var available := {}
	for turn in range(1, 15):
		available[turn] = 3
	var plan: Dictionary = LogPanel.plan_update({}, available)
	assert_eq(plan["window"], range(5, 15))
	assert_true(plan["truncated"])
	assert_eq(plan["append"].size(), 10)
	assert_eq(plan["append"][5], 3)


func test_plan_not_truncated_with_few_turns() -> void:
	var plan: Dictionary = LogPanel.plan_update({}, {1: 2, 2: 0})
	assert_false(plan["truncated"])
	assert_eq(plan["window"], [1, 2])


func test_plan_appends_only_the_new_lines_of_the_current_turn() -> void:
	var plan: Dictionary = LogPanel.plan_update({1: 4, 2: 3}, {1: 4, 2: 5})
	assert_eq(plan["append"], {2: 2})
	assert_eq(plan["drop"], [])


func test_plan_drops_sections_that_left_the_window() -> void:
	var built := {}
	var available := {}
	for turn in range(1, 12):
		built[turn] = 1
		available[turn] = 1
	var plan: Dictionary = LogPanel.plan_update(built, available)
	assert_eq(plan["drop"], [1])
	assert_eq(plan["append"], {})


func test_plan_with_nothing_new_requests_no_work() -> void:
	var plan: Dictionary = LogPanel.plan_update({1: 2}, {1: 2})
	assert_eq(plan["append"], {})
	assert_eq(plan["drop"], [])


func test_list_is_only_built_while_expanded_and_dirty() -> void:
	assert_false(LogPanel.needs_build(false, true))
	assert_false(LogPanel.needs_build(true, false))
	assert_true(LogPanel.needs_build(true, true))


func test_playback_events_are_only_combat_resolution_events() -> void:
	var turn_log := _log_with([
		[PhaseEvents.Type.SAIL_CHANGE, DRIFT, "a"],
		[PhaseEvents.Type.FIRE, COMBAT, "a"],
		[PhaseEvents.Type.DAMAGE, COMBAT, "b"],
		[PhaseEvents.Type.STRIKE, COMBAT, "b"],
	])
	var events: Array = LogPanel.playback_events(turn_log)
	assert_eq(events.size(), 3)
	assert_eq(events[0].type, PhaseEvents.Type.FIRE)
	assert_eq(events[2].type, PhaseEvents.Type.STRIKE)


func test_view_sync_only_after_damage_or_strike() -> void:
	var fire := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.FIRE)
	var dmg := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.DAMAGE)
	var strike := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.STRIKE)
	assert_false(LogPanel.syncs_views(fire))
	assert_true(LogPanel.syncs_views(dmg))
	assert_true(LogPanel.syncs_views(strike))


func test_latest_line_is_last_event_text_or_placeholder() -> void:
	assert_eq(LogPanel.latest_line(null, {}), "No events yet")
	var turn_log := _log_with([[PhaseEvents.Type.DAMAGE, COMBAT, "b", {"hull": 2}]])
	assert_string_contains(LogPanel.latest_line(turn_log, {"b": "Bravo"}), "Bravo loses 2 hull boxes")


# --- Status helpers ---------------------------------------------------------

func test_explosion_resyncs_ship_views() -> void:
	var ev := PhaseEvents.PhaseLog.new().add(PhaseEvents.Type.DESTROYED, 4, "s1", {"reason": "explosion"})
	assert_true(CombatLogPanel.syncs_views(ev))


# --- Ship names in log lines -------------------------------------------------------

func test_log_names_tell_the_sides_apart() -> void:
	var mine := _make_ship("s1")
	var theirs := _make_ship("s2")
	theirs.ship.player_id = 1
	var names: Dictionary = LogPanel.log_names([mine, theirs])
	assert_eq(names["s1"], "HMS Test (yours)")
	assert_eq(names["s2"], "HMS Test (enemy)")


func test_log_names_feed_event_text() -> void:
	var mine := _make_ship("s1")
	var theirs := _make_ship("s2")
	theirs.ship.player_id = 1
	var turn_log := PhaseEvents.PhaseLog.new()
	turn_log.add(PhaseEvents.Type.STRIKE, COMBAT, "s2", {"reason": "morale"})
	assert_eq(LogPanel.latest_line(turn_log, LogPanel.log_names([mine, theirs])),
		"HMS Test (enemy) strikes her colours (the crew's morale broke)")


func test_log_labels_each_event_by_the_side_when_it_was_logged() -> void:
	# A prize changes side (10.H.1); earlier lines must not read as if she had always been on it.
	var mine := _make_ship("s1")
	var theirs := _make_ship("s2")
	theirs.ship.player_id = 1
	var sides := {"s1": 0, "s2": 1}
	var turn_log := PhaseEvents.PhaseLog.new()
	turn_log.controller_of = func(id: String) -> int: return int(sides.get(id, -1))
	turn_log.add(PhaseEvents.Type.HOLD_FIRE, COMBAT, "s2")
	sides["s2"] = 0
	theirs.controller_id = 0  # captured by side 0
	turn_log.add(PhaseEvents.Type.HOLD_FIRE, COMBAT, "s2")
	var info := LogPanel.log_ships([mine, theirs])
	var list: Array = LogPanel.entries(turn_log, 0, 2, -1, info)
	assert_eq(list[1]["text"], "HMS Test (enemy) holds fire.", "logged before the capture")
	assert_eq(list[2]["text"], "HMS Test (yours) holds fire.", "logged after it")
	assert_eq(LogPanel.latest_line(turn_log, info, 1), "HMS Test (enemy) holds fire.")


func test_unstamped_events_fall_back_to_the_side_now() -> void:
	var theirs := _make_ship("s2")
	theirs.ship.player_id = 1
	var turn_log := PhaseEvents.PhaseLog.new()  # no controller_of: nothing recorded
	turn_log.add(PhaseEvents.Type.HOLD_FIRE, COMBAT, "s2")
	assert_eq(LogPanel.latest_line(turn_log, LogPanel.log_ships([theirs])), "HMS Test (enemy) holds fire.")


func test_game_state_logs_record_sides() -> void:
	var fresh := GameState.new_turn_log(3)
	assert_eq(fresh.turn, 3)
	assert_true(fresh.controller_of.is_valid())
	assert_eq(fresh.controller_of.call("no_such_ship"), -1)


# --- Auto collapse / expand ----------------------------------------------------------

func test_phase_key_separates_turns_phases_and_combat_steps() -> void:
	assert_eq(LogPanel.phase_key(3, 4, 1), "3:4:1")
	assert_ne(LogPanel.phase_key(3, 4, 1), LogPanel.phase_key(3, 4, 2))
	assert_ne(LogPanel.phase_key(3, 2, 0), LogPanel.phase_key(4, 2, 0))


func test_manual_choice_only_holds_in_its_own_phase_step() -> void:
	assert_true(LogPanel.choose_expanded(true, "", "3:4:2", false), "no manual choice: auto wins")
	assert_false(LogPanel.choose_expanded(true, "3:4:2", "3:4:2", false), "same step: manual wins")
	assert_true(LogPanel.choose_expanded(false, "3:4:2", "3:4:2", true), "same step: manual expand kept")
	assert_false(LogPanel.choose_expanded(false, "3:9:0", "4:2:0", true), "next planning: auto collapse")
	assert_true(LogPanel.choose_expanded(true, "3:4:1", "3:4:2", false), "declare -> playback re-expands")


# --- Only the current game's turns ---------------------------------------------------

func _turn_log(turn: int) -> PhaseEvents.PhaseLog:
	var l := PhaseEvents.PhaseLog.new()
	l.turn = turn
	return l


func test_current_game_logs_drop_turns_left_from_an_earlier_game() -> void:
	var old_logs := {}
	for turn in range(1, 15):
		old_logs[turn] = _turn_log(turn)
	var fresh := _turn_log(1)
	var by_turn: Dictionary = LogPanel.current_game_logs(old_logs, fresh)
	assert_eq(by_turn.keys(), [1])
	assert_eq(by_turn[1], fresh, "turn 1 of the new game, not the old game's turn 1")
	var plan: Dictionary = LogPanel.plan_update({}, {1: 0})
	assert_false(plan["truncated"], "no 'Earlier turns not shown' on turn 1")


func test_current_game_logs_keep_finished_turns_of_this_game() -> void:
	var logs := {1: _turn_log(1), 2: _turn_log(2)}
	var current := _turn_log(3)
	assert_eq(LogPanel.current_game_logs(logs, current).keys(), [1, 2, 3])


func test_earlier_turns_label_hidden_on_turn_one_of_a_new_game() -> void:
	var saved_logs := GameState.turn_logs
	var saved_log := GameState.turn_log
	var old_logs := {}
	for turn in range(1, 15):
		var l := _turn_log(turn)
		l.add(PhaseEvents.Type.HOLD_FIRE, COMBAT, "a")
		old_logs[turn] = l
	var saved_turn := GameState.current_turn
	GameState.turn_logs = old_logs
	GameState.turn_log = old_logs[14]
	GameState.current_turn = 14
	var panel = load("res://scenes/ui/combat_log_panel.tscn").instantiate()
	add_child_autofree(panel)
	panel.set_expanded(true)
	assert_true(panel._earlier_label.visible, "14 turns of the old game: earlier turns are cut")
	# The next game starts with the panel already built
	GameState.turn_logs = {}
	GameState.turn_log = _turn_log(1)
	GameState.current_turn = 1
	panel.refresh()
	assert_false(panel._earlier_label.visible)
	GameState.turn_logs = saved_logs
	GameState.turn_log = saved_log
	GameState.current_turn = saved_turn


func test_earlier_turns_label_needs_more_turns_in_this_game_than_the_list_holds() -> void:
	assert_false(LogPanel.earlier_turns_omitted(1, true), "turn 1: there are no earlier turns")
	assert_false(LogPanel.earlier_turns_omitted(LogPanel.MAX_TURNS_SHOWN, true))
	assert_true(LogPanel.earlier_turns_omitted(LogPanel.MAX_TURNS_SHOWN + 1, true))
	assert_false(LogPanel.earlier_turns_omitted(LogPanel.MAX_TURNS_SHOWN + 1, false), "nothing cut")


func test_earlier_turns_label_hidden_on_turn_one_even_with_logs_left_from_another_game() -> void:
	# GameState says turn 1 (e.g. after a reset) while logs of a 14-turn game are still held.
	var saved_logs := GameState.turn_logs
	var saved_log := GameState.turn_log
	var saved_turn := GameState.current_turn
	var old_logs := {}
	for turn in range(1, 14):
		var l := _turn_log(turn)
		l.add(PhaseEvents.Type.HOLD_FIRE, COMBAT, "a")
		old_logs[turn] = l
	GameState.turn_logs = old_logs
	GameState.turn_log = _turn_log(14)
	GameState.current_turn = 1
	var panel = load("res://scenes/ui/combat_log_panel.tscn").instantiate()
	add_child_autofree(panel)
	panel.set_expanded(true)
	assert_false(panel._earlier_label.visible, "no 'Earlier turns not shown' on turn 1")
	GameState.turn_logs = saved_logs
	GameState.turn_log = saved_log
	GameState.current_turn = saved_turn



func test_critical_lines_one_per_lasting_effect() -> void:
	var s := _make_ship()
	assert_eq(CrewOverlayText.critical_lines(s), [] as Array[String], "No crits, no lines")
	s.critical_effects = [
		{"seq": 0, "id": "broadside_obscured", "side": ShipState.STARBOARD},
		{"seq": 1, "id": "rudder_jammed", "side": ShipState.PORT},
		{"seq": 2, "id": "signal_halyards_cut", "side": -1},
	] as Array[Dictionary]
	s.wheel_shot_away = true
	s.fire_list = [{"seq": 1, "created_turn": 1, "started_turn": 1, "cause": "crit"}] as Array[Dictionary]
	assert_eq(CrewOverlayText.critical_lines(s), [
		"Starboard broadside −2: obscured by fallen rigging (fix roll in maintenance)",
		"Rudder jammed to port (fix roll in maintenance)",
		"Signal halyards cut: no new signals (fix roll in maintenance)",
		"Wheel shot away: one turn per turn, poor maneuvering",
		"Afire ×1: 1 hull and 1 rigging box a turn per fire (8.E.8)",
	] as Array[String])


