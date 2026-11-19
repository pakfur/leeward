class_name PhaseFooters
extends RefCounted
## The fleet panel's footers that need no binding, view only: End Turn (POST_COMBAT) and the
## read-only status lines of a phase that plays out on the map (movement, the combat lines).

const END_TURN_HINT := "Review the combat log, then end the turn."
const END_TURN_KEYS := "Space or Enter also ends the turn."


## "Review the combat log, then end the turn.", the key hint and **End Turn** (named
## "EndTurnButton"; it takes no focus: Space and Enter are handled once, by GameController).
static func end_turn() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "EndTurnPanel"
	box.add_theme_constant_override("separation", 12)
	box.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = END_TURN_HINT
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var key_hint := Label.new()
	key_hint.text = END_TURN_KEYS
	key_hint.theme_type_variation = &"SecondaryLabel"
	key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(key_hint)
	var button := Button.new()
	button.name = "EndTurnButton"
	button.text = "End Turn"
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_NONE
	box.add_child(button)
	return box


## The End Turn footer's button.
static func end_turn_button(footer: Control) -> Button:
	return footer.get_node_or_null("EndTurnButton") as Button


## Read-only lines (plus an optional secondary hint), named `node_name`; no buttons.
static func status(node_name: String, lines: Array[String], hint_text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = node_name
	box.add_theme_constant_override("separation", 8)
	box.add_child(HSeparator.new())
	for line in lines:
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	if hint_text != "":
		var hint := Label.new()
		hint.text = hint_text
		hint.theme_type_variation = &"SecondaryLabel"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)
	return box
