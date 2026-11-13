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


func test_group_events_groups_consecutive_same_phase_under_one_heading() -> void:
	var turn_log := _log_with([
		[PhaseEvents.Type.FIRE, COMBAT, "a", {"bgn": 5}],
		[PhaseEvents.Type.DAMAGE, COMBAT, "b", {"hull": 1}],
		[PhaseEvents.Type.DRIFT, DRIFT, "a", {}],
	])
	var groups: Array = LogPanel.group_events(turn_log, {"a": "Alpha", "b": "Bravo"})
	assert_eq(groups.size(), 2)
	assert_eq(groups[0]["heading"], "Turn 2 — Combat Resolution")
	assert_eq(groups[0]["lines"].size(), 2)
	assert_string_contains(groups[0]["lines"][1], "Bravo takes")
	assert_eq(groups[1]["heading"], "Turn 2 — Drift Calculation")
	assert_eq(groups[1]["lines"].size(), 1)


func test_group_events_respects_reveal_limit() -> void:
	var turn_log := _log_with([
		[PhaseEvents.Type.FIRE, COMBAT, "a"],
		[PhaseEvents.Type.DAMAGE, COMBAT, "b"],
		[PhaseEvents.Type.DRIFT, DRIFT, "a"],
	])
	var groups: Array = LogPanel.group_events(turn_log, {}, 1)
	assert_eq(groups.size(), 1)
	assert_eq(groups[0]["lines"].size(), 1)


func test_group_events_empty_log_gives_no_groups() -> void:
	assert_eq(LogPanel.group_events(PhaseEvents.PhaseLog.new(), {}).size(), 0)
	assert_eq(LogPanel.group_events(null, {}).size(), 0)


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
	assert_string_contains(LogPanel.latest_line(turn_log, {"b": "Bravo"}), "Bravo takes")


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
	assert_true(lines.any(func(l): return l.contains("Quality B") and l.contains("Morale")))


func test_guns_dismounted_only_shown_when_non_zero() -> void:
	var s := _make_ship()
	assert_false(StatusPanel.status_lines(s).any(func(l): return l.begins_with("Guns")))
	s.guns_dismounted = [2, 0] as Array[int]
	assert_has(StatusPanel.status_lines(s), "Guns dismounted: port 2, starboard 0")


func test_sail_line_notes_when_it_moves_as_a_lighter_sail() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.sail_line(s), "Sail: Maneuvering Sail")
	s.sail_state = "PS"
	s.rigging_current_hp = [0, 5, 6, 6] as Array[int]  # 3 sections -> max MS
	assert_eq(StatusPanel.sail_line(s), "Sail: Plain Sail (moves as MS)")


func test_pending_sail_change_line_covers_underway_and_ordered() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.sail_change_line(s), "")
	s.plotted_actions["sail_change"] = "FS"
	assert_eq(StatusPanel.sail_change_line(s), "Sail change ordered: FS")
	s.sail_change = {"target": "PS", "turns_left": 2, "sections": [0]}
	assert_eq(StatusPanel.sail_change_line(s), "Sail change: PS, 2 turns left")


func test_badges_for_fouled_struck_and_dismasted() -> void:
	var s := _make_ship()
	assert_eq(StatusPanel.badges(s), [])
	s.fouled_with = "other"
	s.status = ShipState.Status.STRUCK
	s.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(StatusPanel.badges(s), ["FOULED", "STRUCK", "DISMASTED"])
