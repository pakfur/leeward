class_name ResolutionPanel
extends VBoxContainer
## The left-panel card of the resolution replay: one step at a time (a roll and what came of it).
## Top to bottom: "Combat · 3 of 11", the step's title, its picture, the dice, the modifiers, the
## final number, the outcome lines, then Resolve all | Next ▸ pinned at the bottom. Next is enabled
## once the dice have settled. While a prompt is shown its answer controls take the buttons' place
## (`set_answer_section`). View only: it shows a `ResolutionStep` and reports the buttons; the
## replay decides what comes next. Space, Enter and the right arrow press Next.

signal next_pressed()
signal resolve_all_pressed()

@onready var _header: Label = %HeaderLabel
@onready var _title: Label = %TitleLabel
@onready var _picture: ResolutionPicture = %Picture
@onready var _dice: ResolutionDice = %Dice
@onready var _modifiers: VBoxContainer = %Modifiers
@onready var _final: Label = %FinalLabel
@onready var _outcome: VBoxContainer = %Outcome
@onready var _button_row: HBoxContainer = %ButtonRow
@onready var _answer_holder: VBoxContainer = %AnswerHolder
@onready var _next: Button = %NextButton
@onready var _resolve_all: Button = %ResolveAllButton

var _header_text := ""


func _ready() -> void:
	# Keys act through _unhandled_key_input only: a focused button would also take ui_accept.
	_next.focus_mode = Control.FOCUS_NONE
	_resolve_all.focus_mode = Control.FOCUS_NONE
	_next.pressed.connect(func() -> void: next_pressed.emit())
	_resolve_all.pressed.connect(func() -> void: resolve_all_pressed.emit())
	_dice.settled.connect(_on_dice_settled)
	_answer_holder.visible = false


## Shows `step` as step `index` (0-based) of `total` in the phase named `phase_label`; `instant`
## lands the dice at once (Resolve all, tests).
func show_step(step: ResolutionStep, index: int, total: int, phase_label: String, instant: bool) -> void:
	_header_text = "%s · %d of %d" % [phase_label, index + 1, total]
	_header.text = _header_text
	_title.text = step.title
	_picture.kind = step.kind
	_fill_modifiers(step.modifiers)
	_final.text = step.final_text
	_final.visible = step.final_text != ""
	for child in _outcome.get_children():
		child.free()
	for line in step.outcome_lines:
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_outcome.add_child(l)
	_outcome.visible = not step.outcome_lines.is_empty()
	_dice.visible = not step.dice.is_empty()
	_next.disabled = true
	_dice.roll(step.dice, instant)


## Puts `control` in place of Resolve all | Next while a prompt is shown; `null` brings the buttons
## back. The panel owns the section it holds and frees it when it is replaced or removed.
func set_answer_section(control: Control) -> void:
	# Freed at the end of the frame, not at once: the call may come from one of its own buttons.
	for child in _answer_holder.get_children():
		if not child.is_queued_for_deletion():
			child.hide()
			child.queue_free()
	if control != null:
		_answer_holder.add_child(control)
	_answer_holder.visible = control != null
	_button_row.visible = control == null


func header_text() -> String:
	return _header_text


## The modifier rows as shown: "Crew  +2", "Two targets  −12".
func modifier_rows() -> PackedStringArray:
	var out := PackedStringArray()
	for row in _modifiers.get_children():
		out.append("%s  %s" % [(row.get_child(0) as Label).text, (row.get_child(1) as Label).text])
	return out


func dice_widget() -> ResolutionDice:
	return _dice


func picture() -> ResolutionPicture:
	return _picture


func next_button() -> Button:
	return _next


func resolve_all_button() -> Button:
	return _resolve_all


static func signed(value: int) -> String:
	return "%s%d" % ["−" if value < 0 else "+", absi(value)]


func _fill_modifiers(modifiers: Array) -> void:
	for child in _modifiers.get_children():
		child.free()
	for m in modifiers:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.theme_type_variation = &"TabularLabel"
		name_label.text = str(m.get("label", ""))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var value_label := Label.new()
		value_label.theme_type_variation = &"TabularLabel"
		value_label.text = str(int(m.get("value", 0))) if m.get("base", false) \
			else signed(int(m.get("value", 0)))
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_label)
		row.add_child(value_label)
		_modifiers.add_child(row)
	_modifiers.visible = not modifiers.is_empty()


func _on_dice_settled() -> void:
	_next.disabled = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT]:
		if _button_row.visible and not _next.disabled and is_visible_in_tree():
			get_viewport().set_input_as_handled()
			next_pressed.emit()
