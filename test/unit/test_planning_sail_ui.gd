extends GutTest
## Tests for PlanningSailUi: pure presentation logic for the planning sail row and status badges.


func _ship(sail: String = "MS") -> ShipState:
	var state := ShipState.new()
	state.sail_state = sail
	state.rigging_current_hp = [4, 4, 4, 4]
	return state


func test_sail_name_includes_code() -> void:
	assert_eq(PlanningSailUi.sail_name("FS"), "Fighting sail (FS)")
	assert_eq(PlanningSailUi.sail_name("ms"), "Manoeuvring sail (MS)")
	assert_eq(PlanningSailUi.sail_name("PS"), "Plain sail (PS)")
	assert_eq(PlanningSailUi.sail_name("NS"), "Furled (NS)")


func test_button_text_singular_and_plural() -> void:
	assert_eq(PlanningSailUi.target_button_text("FS", {"turns": 1, "sections": 1}), "→ FS (1 turn, 1 section)")
	assert_eq(PlanningSailUi.target_button_text("PS", {"turns": 2, "sections": 2}), "→ PS (2 turns, 2 sections)")
	assert_eq(PlanningSailUi.target_button_text("MS", {"turns": 3, "sections": 2}), "→ MS (3 turns, 2 sections)")


func test_status_badge_priority() -> void:
	var state := _ship()
	assert_eq(PlanningSailUi.status_badge(state), "")
	state.fouled_with = "other"
	assert_eq(PlanningSailUi.status_badge(state), "FOULED")
	state.rigging_current_hp = [0, 0, 0, 0]
	assert_eq(PlanningSailUi.status_badge(state), "DISMASTED")
	state.status = ShipState.Status.STRUCK
	assert_eq(PlanningSailUi.status_badge(state), "STRUCK")


func test_movement_blocked_with_reason_when_badged() -> void:
	var state := _ship()
	assert_true(PlanningSailUi.can_plot_movement(state))
	assert_eq(PlanningSailUi.movement_block_reason(state), "")
	state.fouled_with = "other"
	assert_false(PlanningSailUi.can_plot_movement(state))
	assert_string_contains(PlanningSailUi.movement_block_reason(state), "fouled")
	state.fouled_with = ""
	state.status = ShipState.Status.STRUCK
	assert_false(PlanningSailUi.can_plot_movement(state))
	assert_string_contains(PlanningSailUi.movement_block_reason(state), "struck")


func test_choose_mode_lists_a_button_per_target() -> void:
	var row := PlanningSailUi.sail_row(_ship("MS"), ["FS", "PS"],
		{"FS": {"turns": 1, "sections": 1}, "PS": {"turns": 2, "sections": 2}})
	assert_eq(row["mode"], PlanningSailUi.Mode.CHOOSE)
	assert_eq(row["current"], "Manoeuvring sail (MS)")
	assert_eq(row["buttons"].size(), 2)
	assert_eq(row["buttons"][0]["target"], "FS")
	assert_eq(row["buttons"][0]["text"], "→ FS (1 turn, 1 section)")
	assert_eq(row["buttons"][1]["text"], "→ PS (2 turns, 2 sections)")
	assert_false(row["can_cancel"])
	assert_eq(row["hint"], "Sections changing sail cannot serve the guns.")


func test_ordered_mode_shows_order_and_cancel() -> void:
	var state := _ship("MS")
	state.plotted_actions["sail_change"] = "FS"
	var row := PlanningSailUi.sail_row(state, ["FS", "PS"], {})
	assert_eq(row["mode"], PlanningSailUi.Mode.ORDERED)
	assert_eq(row["text"], "Ordered: → FS")
	assert_true(row["can_cancel"])
	assert_eq(row["buttons"].size(), 0)


func test_progress_mode_has_no_buttons() -> void:
	var state := _ship("MS")
	state.sail_change = {"target": "PS", "turns_left": 1, "sections": [3, 2]}
	var row := PlanningSailUi.sail_row(state, [], {})
	assert_eq(row["mode"], PlanningSailUi.Mode.PROGRESS)
	assert_eq(row["text"], "Changing to PS — 1 turn left")
	assert_eq(row["buttons"].size(), 0)
	assert_false(row["can_cancel"])


func test_progress_text_plural_turns() -> void:
	var state := _ship("MS")
	state.sail_change = {"target": "PS", "turns_left": 2, "sections": [3, 2]}
	assert_eq(PlanningSailUi.sail_row(state, [], {})["text"], "Changing to PS — 2 turns left")


func test_struck_ship_has_no_sail_control() -> void:
	var state := _ship("MS")
	state.status = ShipState.Status.STRUCK
	var row := PlanningSailUi.sail_row(state, ["FS"], {"FS": {"turns": 1, "sections": 1}})
	assert_eq(row["mode"], PlanningSailUi.Mode.NONE)
	assert_eq(row["buttons"].size(), 0)


func test_no_targets_means_no_control() -> void:
	var row := PlanningSailUi.sail_row(_ship("NS"), [], {})
	assert_eq(row["mode"], PlanningSailUi.Mode.NONE)


func test_fouled_ship_with_targets_still_offers_sail_change() -> void:
	var state := _ship("MS")
	state.fouled_with = "other"
	var row := PlanningSailUi.sail_row(state, ["FS"], {"FS": {"turns": 1, "sections": 1}})
	assert_eq(row["mode"], PlanningSailUi.Mode.CHOOSE)
