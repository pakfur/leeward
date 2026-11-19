extends GutTest
## SignalComposer (board planning piece 2): the signal box's word count, send, pending line and
## refusal, headless (by state, not screen position).

var box: SignalComposer


func _options(extra := {}) -> Dictionary:
	var o := {
		"error": "", "pending": {}, "limit": 3,
		"addresses": [
			{"kind": "fleet", "name": "", "label": "Fleet"},
			{"kind": "group", "name": "van", "label": "van"},
			{"kind": "ship", "name": "b_id", "label": "Bellona"},
		],
	}
	o.merge(extra, true)
	return o


func before_each() -> void:
	box = SignalComposer.new()
	box.ui_scale = CrewStyle.K
	add_child_autofree(box)
	box.setup(null)
	box.ship_names = ["Bellona"] as Array[String]


func test_word_count_and_limit() -> void:
	box.open("Agamemnon", _options())
	assert_eq(box.title_text(), "Signal from Agamemnon")
	assert_eq(box.count_text(), "0 of 3 words")
	box.set_text("engage the enemy")
	assert_eq(box.count_text(), "3 of 3 words")
	assert_false(box.count_is_over())
	box.set_text("engage the enemy closely")
	assert_eq(box.count_text(), "4 of 3 words")
	assert_true(box.count_is_over(), "amber over the limit")
	box.set_text("don't")
	assert_string_contains(box.count_text(), "contractions", "the words error shows")
	assert_true(box.count_is_over())
	box.set_text("follow Bellona")
	assert_eq(box.count_text(), "2 of 3 words", "a ship's name is one word")


func test_send_emits_address_and_text() -> void:
	box.open("Agamemnon", _options())
	watch_signals(box)
	box.select_address(2)
	box.set_text("  follow me ")
	box.send_button().pressed.emit()
	assert_signal_emitted_with_parameters(box, "send_requested",
		[{"kind": "ship", "name": "b_id"}, "follow me"])
	box.select_address(0)
	box.field().text_submitted.emit("follow me")  # Enter in the field sends too
	assert_signal_emit_count(box, "send_requested", 2)
	assert_eq(get_signal_parameters(box, "send_requested", 1)[0], {"kind": "fleet", "name": ""})


func test_empty_text_goes_to_the_server() -> void:
	box.open("Agamemnon", _options())
	watch_signals(box)
	box.send_button().pressed.emit()
	assert_signal_emit_count(box, "send_requested", 1)  # the server answers "Empty signal"
	assert_eq(get_signal_parameters(box, "send_requested", 0)[1], "")


func test_pending_signal_shown_with_cancel() -> void:
	box.open("Agamemnon", _options())
	assert_eq(box.pending_text(), "")
	assert_false(box.cancel_button().is_visible_in_tree())
	box.open("Agamemnon", _options({"pending": {
		"address": {"kind": "ship", "name": "b_id"}, "words": ["FOLLOW", "ME"]}}))
	assert_eq(box.pending_text(), "From \nTo Bellona: FOLLOW ME")
	box.open("Agamemnon", _options({"pending": {
		"address": {"kind": "ship", "name": "gone_id"}, "words": ["GO"], "from_ship": "x", "from_name": "Ajax"}}),
		null, "y")
	assert_eq(box.pending_text(),
		"From Ajax\nTo gone_id: GO\nSending replaces it (one signal a turn).",
		"an address not listed shows its name; another sender gets the note")
	assert_true(box.cancel_button().is_visible_in_tree())
	watch_signals(box)
	box.cancel_button().pressed.emit()
	assert_signal_emitted(box, "cancel_pending_requested")


func test_error_shown() -> void:
	box.open("Agamemnon", _options())
	box.show_error("Agamemnon may signal at most 3 words (11.A.6)")
	assert_eq(box.error_text(), "Agamemnon may signal at most 3 words (11.A.6)")
	box.set_text("x")  # an edit answers the refusal
	assert_eq(box.error_text(), "")
	box.show_error("again")
	box.show_error("")
	assert_eq(box.error_text(), "")


func test_reopen_keeps_typed_text_and_address() -> void:
	box.open("Agamemnon", _options())
	box.select_address(1)
	box.set_text("engage")
	box.open("Agamemnon", _options())
	assert_eq(box.text(), "engage")
	assert_eq(box.selected_address(), {"kind": "group", "name": "van"})


func test_close_emits_and_hides() -> void:
	box.open("Agamemnon", _options())
	watch_signals(box)
	box.close()
	assert_false(box.is_open())
	assert_signal_emitted(box, "closed")


func test_tab_keeps_focus_in_the_field() -> void:
	var ui := Control.new()  # the box shares the UI tree with the side panel's buttons
	add_child_autofree(ui)
	box.reparent(ui)
	var other := Button.new()
	other.focus_mode = Control.FOCUS_ALL
	ui.add_child(other)
	box.open("Agamemnon", _options())
	var f := box.field()
	assert_eq(f.find_next_valid_focus(), f, "Tab stays in the field (not the side panel's buttons)")
	assert_eq(f.find_prev_valid_focus(), f, "and Shift+Tab")


func test_field_keeps_editing_after_enter_sends() -> void:
	box.open("Agamemnon", _options())
	box.field().grab_focus()
	box.field().edit()
	box.set_text("engage")
	var sent := []
	box.send_requested.connect(func(_a: Dictionary, t: String): sent.append(t))
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	get_viewport().push_input(enter)
	assert_eq(sent, ["engage"], "Enter sends")
	assert_true(box.field().is_editing(),
		"still editing: the next letters go in the field, not to the board's keys (C = crew)")
