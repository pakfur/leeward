extends GutTest
## Tests for the pure presentation helpers of the combat turn_log panel and ship status panel.

const LogPanel = preload("res://scripts/ui/combat_log_panel.gd")
const StatusPanel = preload("res://scripts/ui/ship_status_panel.gd")

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

func test_box_line_formats_current_over_max_per_section() -> void:
	assert_eq(StatusPanel.box_line("Hull", [5, 4, 5, 6] as Array[int], [5, 5, 5, 6] as Array[int]),
		"Hull 5/5 4/5 5/5 6/6")


func test_box_line_tolerates_short_max_array() -> void:
	assert_eq(StatusPanel.box_line("Hull", [2, 3] as Array[int], [4] as Array[int]), "Hull 2/4 3/0")


func test_status_lines_show_boxes_marines_quality_and_morale() -> void:
	var s := _make_ship()
	s.hull_current_hp = [5, 4, 5, 6] as Array[int]
	var lines: Array = StatusPanel.status_lines(s)
	assert_has(lines, "Hull 5/5 4/5 5/5 6/6")
	assert_has(lines, "Rigging 5/5 5/5 6/6 6/6")
	assert_has(lines, "Crew 3/3 3/3 3/3 3/3")
	assert_has(lines, "Marines 4/4")
	assert_has(lines, "Crew quality B (of A–G)")
	assert_has(lines, "Morale rating %d (2 best – 6 worst)" % s.morale_rating)


func test_guns_dismounted_only_shown_when_non_zero() -> void:
	var s := _make_ship()
	assert_false(StatusPanel.status_lines(s).any(func(l): return l.begins_with("Guns")))
	s.guns_dismounted = [2, 0] as Array[int]
	assert_has(StatusPanel.status_lines(s), "Guns dismounted: port 2, starboard 0")


func test_sail_line_notes_when_it_moves_as_a_lighter_sail() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.sail_line(s), "Sail: Manoeuvring sail")
	s.sail_state = "PS"
	s.rigging_current_hp = [0, 5, 6, 6] as Array[int]  # 3 sections -> max MS
	assert_eq(StatusPanel.sail_line(s), "Sail: Plain sail (moves as manoeuvring sail)")


func test_pending_sail_change_line_covers_underway_and_ordered() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.sail_change_line(s), "")
	s.plotted_actions["sail_change"] = "FS"
	assert_eq(StatusPanel.sail_change_line(s), "Sail change ordered: Fighting sail")
	s.sail_change = {"target": "PS", "turns_left": 2, "sections": [0]}
	assert_eq(StatusPanel.sail_change_line(s), "Sail change: Plain sail, 2 turns left")


func test_badges_for_fouled_struck_and_dismasted() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.badges(s), [])
	s.fouled_with = "other"
	s.status = ShipState.Status.STRUCK
	s.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(StatusPanel.badges(s), ["FOULED", "STRUCK", "DISMASTED"])


func test_identity_line_shows_owner_and_type_only_when_it_differs() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.identity_line(s), "Yours · 38-gun Frigate")
	s.ship.player_id = 1
	s.ship.ship_name = "38-gun frigate"  # unnamed: the scenario fell back to the type name
	assert_eq(StatusPanel.identity_line(s), "Enemy")


func test_heading_and_speed_lines_in_words() -> void:
	assert_eq(StatusPanel.heading_line(0), "Heading: east")
	assert_eq(StatusPanel.heading_line(4), "Heading: north-west")
	assert_eq(StatusPanel.speed_line(0), "Speed last turn: 0 hexes")
	assert_eq(StatusPanel.speed_line(1), "Speed last turn: 1 hex")


func test_crew_quality_and_morale_lines_carry_their_scales_without_adjectives() -> void:
	assert_eq(StatusPanel.crew_quality_line("G"), "Crew quality G (of A–G)")
	assert_eq(StatusPanel.morale_line(4), "Morale rating 4 (2 best – 6 worst)")


func test_movement_line_says_why_a_ship_cannot_move() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.movement_line(s, 5), "Movement allowance this turn: 5")
	s.fouled_with = "s2"
	assert_eq(StatusPanel.movement_line(s, 5, "Foe"), "Cannot move (fouled with Foe)")
	s.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(StatusPanel.movement_line(s, 0), "Cannot move (dismasted)")
	s.status = ShipState.Status.STRUCK
	assert_eq(StatusPanel.movement_line(s, 5), "Cannot move (struck)")


func test_movement_line_after_movement_says_how_far_the_ship_moved() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.movement_line(s, 0, "", 4), "Moved 4 hexes this turn")
	assert_eq(StatusPanel.movement_line(s, 0, "", 1), "Moved 1 hex this turn")
	assert_eq(StatusPanel.movement_line(s, 0, "", 0), "Moved 0 hexes this turn")


func test_movement_has_resolved_from_combat_until_the_turn_ends() -> void:
	var P := TurnPhaseController.GamePhase
	assert_false(StatusPanel.movement_resolved(P.PLANNING))
	assert_false(StatusPanel.movement_resolved(P.MOVEMENT_RESOLUTION))
	assert_false(StatusPanel.movement_resolved(P.ENVIRONMENT))
	assert_true(StatusPanel.movement_resolved(P.COMBAT_RESOLUTION))
	assert_true(StatusPanel.movement_resolved(P.POST_COMBAT))
	assert_true(StatusPanel.movement_resolved(P.END_TURN))


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
