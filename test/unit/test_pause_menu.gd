extends GutTest
## The in-game pause menu: Escape opens and closes it, "Leave game" asks before leaving.

const PauseMenu = preload("res://scripts/ui/pause_menu.gd")

var menu: Control


func before_each() -> void:
	menu = PauseMenu.new()
	add_child_autofree(menu)


func test_escape_opens_closes_and_is_ignored_after_game_over() -> void:
	assert_eq(PauseMenu.escape_action(false, false), PauseMenu.OPEN)
	assert_eq(PauseMenu.escape_action(true, false), PauseMenu.CLOSE)
	assert_eq(PauseMenu.escape_action(false, true), PauseMenu.NONE, "the result card has its own button")
	assert_eq(PauseMenu.escape_action(true, true), PauseMenu.CLOSE)


func test_starts_closed_and_opens_on_the_first_page() -> void:
	assert_false(menu.is_open())
	menu.open()
	assert_true(menu.is_open())
	assert_true(menu.resume_button.is_visible_in_tree())
	assert_true(menu.leave_button.is_visible_in_tree())
	assert_false(menu.confirm_box.visible)


func test_resume_closes() -> void:
	menu.open()
	watch_signals(menu)
	menu.resume_button.pressed.emit()
	assert_false(menu.is_open())
	assert_signal_not_emitted(menu, "leave_confirmed")


func test_leave_asks_first_and_only_the_confirm_leaves() -> void:
	menu.open()
	watch_signals(menu)
	menu.leave_button.pressed.emit()
	assert_true(menu.confirm_box.visible)
	assert_eq(menu.confirm_label.text, "Leave this game? Progress is not saved.")
	assert_signal_not_emitted(menu, "leave_confirmed")
	menu.stay_button.pressed.emit()
	assert_false(menu.confirm_box.visible, "back to the first page")
	assert_true(menu.is_open())
	menu.leave_button.pressed.emit()
	menu.confirm_leave_button.pressed.emit()
	assert_signal_emitted(menu, "leave_confirmed")


func test_reopening_after_a_cancelled_leave_starts_on_the_first_page() -> void:
	menu.open()
	menu.leave_button.pressed.emit()
	menu.close()
	menu.open()
	assert_false(menu.confirm_box.visible)
