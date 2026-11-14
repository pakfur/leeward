extends Control
## PauseMenu - In-game menu opened with Escape (or the corner Menu button): Resume, or Leave game
## after a confirm step. While it is open its backdrop takes every mouse event, so nothing reaches
## the map; the game controller also ignores its keys. Presentation only: leaving is the
## controller's job, on leave_confirmed. (View layer.)

signal leave_confirmed()
signal closed()

const OPEN := "open"
const CLOSE := "close"
const NONE := "none"

const CONFIRM_TEXT := "Leave this game? Progress is not saved."

var resume_button: Button
var leave_button: Button
var confirm_box: VBoxContainer
var confirm_label: Label
var confirm_leave_button: Button
var stay_button: Button
var _main_box: VBoxContainer


## What Escape does: open the menu, close it, or nothing (the game-over card is showing and has
## its own button). Pure; unit tested.
static func escape_action(menu_open: bool, game_over: bool) -> String:
	if menu_open:
		return CLOSE
	if game_over:
		return NONE
	return OPEN


func _init() -> void:
	name = "PauseMenu"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # the backdrop swallows clicks, drags and the wheel
	z_index = 100  # above the side panel (50) and the log bar (20), for drawing and for clicks
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Paused"
	title.theme_type_variation = &"HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 8)
	outer.add_child(_main_box)
	resume_button = _button(_main_box, "Resume")
	leave_button = _button(_main_box, "Leave game")
	var hint := Label.new()
	hint.text = "Esc resumes."
	hint.theme_type_variation = &"SecondaryLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_box.add_child(hint)

	confirm_box = VBoxContainer.new()
	confirm_box.add_theme_constant_override("separation", 8)
	confirm_box.visible = false
	outer.add_child(confirm_box)
	confirm_label = Label.new()
	confirm_label.text = CONFIRM_TEXT
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_box.add_child(confirm_label)
	confirm_leave_button = _button(confirm_box, "Leave")
	stay_button = _button(confirm_box, "Stay")

	resume_button.pressed.connect(close)
	leave_button.pressed.connect(_show_confirm.bind(true))
	stay_button.pressed.connect(_show_confirm.bind(false))
	confirm_leave_button.pressed.connect(func(): leave_confirmed.emit())


func _button(parent: Container, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	parent.add_child(b)
	return b


func is_open() -> bool:
	return visible


## Show the menu on its first page (Resume / Leave game).
func open() -> void:
	_show_confirm(false)
	visible = true
	resume_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	_show_confirm(false)
	closed.emit()


func _show_confirm(on: bool) -> void:
	_main_box.visible = not on
	confirm_box.visible = on
	if visible:
		(stay_button if on else resume_button).grab_focus.call_deferred()
