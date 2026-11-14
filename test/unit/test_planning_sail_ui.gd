extends GutTest
## Tests for PlanningSailUi: pure presentation logic for the planning sail row and status badges.


func _ship(sail: String = "MS") -> ShipState:
	var state := ShipState.new()
	state.sail_state = sail
	state.rigging_current_hp = [4, 4, 4, 4]
	return state


func test_sail_label_is_the_name_without_code() -> void:
	assert_eq(PlanningSailUi.sail_label("FS"), "Fighting sail")
	assert_eq(PlanningSailUi.sail_label("ms"), "Manoeuvring sail")
	assert_eq(PlanningSailUi.sail_label("PS"), "Plain sail")
	assert_eq(PlanningSailUi.sail_label("NS"), "Furled")


func test_button_text_singular_and_plural() -> void:
	assert_eq(PlanningSailUi.target_button_text("FS", {"turns": 1, "sections": 1}), "Fighting sail — 1 turn, 1 section")
	assert_eq(PlanningSailUi.target_button_text("PS", {"turns": 2, "sections": 2}), "Plain sail — 2 turns, 2 sections")
	assert_eq(PlanningSailUi.target_button_text("MS", {"turns": 3, "sections": 2}), "Manoeuvring sail — 3 turns, 2 sections")


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
	assert_eq(row["current"], "Manoeuvring sail")
	assert_eq(row["buttons"].size(), 2)
	assert_eq(row["buttons"][0]["target"], "FS")
	assert_eq(row["buttons"][0]["text"], "Fighting sail — 1 turn, 1 section")
	assert_eq(row["buttons"][1]["text"], "Plain sail — 2 turns, 2 sections")
	assert_false(row["buttons"][0]["pressed"])
	assert_eq(row["text"], PlanningSailUi.CHOOSE_TEXT)
	assert_eq(row["hint"], "Sections changing sail cannot serve the guns.")


func test_ordered_mode_keeps_the_choices_in_place_with_the_order_pressed() -> void:
	var state := _ship("MS")
	var costs := {"FS": {"turns": 1, "sections": 1}, "PS": {"turns": 2, "sections": 2}}
	var before := PlanningSailUi.sail_row(state, ["FS", "PS"], costs)
	state.plotted_actions["sail_change"] = "FS"
	var row := PlanningSailUi.sail_row(state, ["FS", "PS"], costs)
	assert_eq(row["mode"], PlanningSailUi.Mode.ORDERED)
	assert_eq(row["text"], "Ordered: Fighting sail. Press it again to cancel.")
	assert_eq(row["buttons"].size(), before["buttons"].size(), "same buttons, same places")
	for i in range(row["buttons"].size()):
		assert_eq(row["buttons"][i]["target"], before["buttons"][i]["target"])
		assert_eq(row["buttons"][i]["text"], before["buttons"][i]["text"])
	assert_true(row["buttons"][0]["pressed"])
	assert_false(row["buttons"][1]["pressed"])


func test_progress_mode_has_no_buttons() -> void:
	var state := _ship("MS")
	state.sail_change = {"target": "PS", "turns_left": 1, "sections": [3, 2]}
	var row := PlanningSailUi.sail_row(state, [], {})
	assert_eq(row["mode"], PlanningSailUi.Mode.PROGRESS)
	assert_eq(row["text"], "Changing to Plain sail — 1 turn left")
	assert_eq(row["buttons"].size(), 0)


func test_progress_text_plural_turns() -> void:
	var state := _ship("MS")
	state.sail_change = {"target": "PS", "turns_left": 2, "sections": [3, 2]}
	assert_eq(PlanningSailUi.sail_row(state, [], {})["text"], "Changing to Plain sail — 2 turns left")


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
