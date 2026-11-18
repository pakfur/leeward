extends GutTest
## ResolutionPanel, ResolutionDice and ResolutionPicture (view only). The dice are driven through the
## instant path, so nothing here waits on frame timing.

const PANEL_SCENE := "res://scenes/ui/resolution_panel.tscn"

var panel: ResolutionPanel


func before_each() -> void:
	panel = load(PANEL_SCENE).instantiate()
	add_child_autofree(panel)


func _step(dice: Array = [], modifiers: Array = []) -> ResolutionStep:
	var step := ResolutionStep.new()
	step.kind = "gunfire"
	step.title = "Broadside: Alpha at Bravo"
	step.dice = dice
	step.modifiers = modifiers
	step.final_text = "Final gunfire number 14"
	step.outcome_lines = PackedStringArray(["Bravo loses 2 hull boxes"])
	return step


func test_header_text() -> void:
	panel.show_step(_step(), 2, 11, "Combat", true)
	assert_eq(panel.header_text(), "Combat · 3 of 11")


func test_dice_hidden_without_dice() -> void:
	panel.show_step(_step(), 0, 1, "Combat", true)
	assert_false(panel.dice_widget().visible)
	panel.show_step(_step([{"sides": 6, "values": [4]}]), 0, 1, "Combat", true)
	assert_true(panel.dice_widget().visible)


func test_modifier_rows() -> void:
	panel.show_step(_step([], [{"label": "Crew", "value": 2}, {"label": "Two targets", "value": -12}]),
			0, 1, "Combat", true)
	var rows := panel.modifier_rows()
	assert_eq(rows.size(), 2)
	assert_eq(rows[0], "Crew  +2")
	assert_eq(rows[1], "Two targets  −12")
	panel.show_step(_step(), 0, 1, "Combat", true)
	assert_eq(panel.modifier_rows().size(), 0, "rows of the last step are cleared")


func test_next_waits_for_dice() -> void:
	panel.show_step(_step([{"sides": 10, "values": [7]}]), 0, 2, "Morale", false)
	assert_true(panel.dice_widget().is_rolling())
	assert_true(panel.next_button().disabled, "Next is disabled while the dice tumble")
	panel.show_step(_step([{"sides": 10, "values": [7]}]), 1, 2, "Morale", true)
	assert_false(panel.dice_widget().is_rolling())
	assert_false(panel.next_button().disabled, "Next is enabled once the dice settle")


func test_next_enabled_without_dice() -> void:
	panel.show_step(_step(), 0, 1, "Combat", false)
	assert_false(panel.next_button().disabled)


func test_next_and_resolve_all_signals() -> void:
	panel.show_step(_step(), 0, 1, "Combat", true)
	watch_signals(panel)
	panel.next_button().pressed.emit()
	panel.resolve_all_button().pressed.emit()
	assert_signal_emitted(panel, "next_pressed")
	assert_signal_emitted(panel, "resolve_all_pressed")


func test_answer_section_replaces_buttons() -> void:
	panel.show_step(_step(), 0, 1, "Combat", true)
	var answer := VBoxContainer.new()
	panel.set_answer_section(answer)
	assert_false(panel.next_button().is_visible_in_tree())
	assert_false(panel.resolve_all_button().is_visible_in_tree())
	assert_true(answer.is_inside_tree())
	panel.set_answer_section(null)
	assert_true(panel.next_button().is_visible_in_tree())
	assert_true(panel.resolve_all_button().is_visible_in_tree())
	assert_true(answer.is_queued_for_deletion(), "the panel frees the answer section it held")


func test_dice_land_on_the_values() -> void:
	var dice := ResolutionDice.new()
	add_child_autofree(dice)
	watch_signals(dice)
	dice.roll([{"sides": 6, "values": [3, 5]}, {"sides": 10, "values": [0]}], true)
	assert_signal_emitted(dice, "settled")
	assert_eq(Array(dice.shown_labels()), ["3", "5", "0"])


func test_two_dice_total_shows_only_the_total() -> void:
	var dice := ResolutionDice.new()
	add_child_autofree(dice)
	dice.roll([{"sides": 6, "values": [7], "count": 2}], true)
	assert_eq(Array(dice.shown_labels()), ["2d6 = 7"], "no invented split of the total")


func test_empty_roll_settles_at_once() -> void:
	var dice := ResolutionDice.new()
	add_child_autofree(dice)
	watch_signals(dice)
	dice.roll([], false)
	assert_false(dice.is_rolling())
	assert_signal_emitted(dice, "settled")


func test_picture_caption_per_kind() -> void:
	assert_eq(ResolutionPicture.caption_for("gunfire"), "Gunfire")
	assert_eq(ResolutionPicture.caption_for("prompt_bear_off"), "Bear off?")
	assert_ne(ResolutionPicture.caption_for("something_new"), "")
	panel.show_step(_step(), 0, 1, "Combat", true)
	assert_eq(panel.picture().kind, "gunfire")
