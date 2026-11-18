class_name BearOffPanel
extends VBoxContainer
## BearOffPanel - the player's decision at a potential collision (Close Action 6.D.3): bear off to
## port or starboard (only the legal turns are offered, with the Bearing Off chart odds), or hold
## course and collide. Widget state and text only; GameController submits the choice.

signal choice_made(ship_id: String, choice: String)

var _ship_id: String = ""
var _buttons: Array[Button] = []
var _error_label: Label = null


## `ship_name` / `blocker_name` are display names. `compact`: the answer section of a resolution
## step, which shows the situation and the odds itself: only the choices, the note and the error line.
func setup(situation: MovementTypes.BearOffSituation, ship_name: String, blocker_name: String,
		compact: bool = false) -> void:
	_ship_id = situation.ship_id
	name = "BearOffPanel"
	add_theme_constant_override("separation", 8)
	if not compact:
		_add_label("%s is about to run into %s." % [ship_name, blocker_name])
		_add_label(odds_text(situation), &"SecondaryLabel")
	for choice in situation.eligible:
		_add_button(choice_label(choice, situation.chance), choice)
	if situation.eligible.is_empty():
		_add_label("No turn is possible here.", &"SecondaryLabel")
	_add_button(choice_label(MovementTypes.BEAR_OFF_COLLIDE, 0.0), MovementTypes.BEAR_OFF_COLLIDE)
	_add_label("The other ships' plotted moves are shown on the map.", &"SecondaryLabel")
	_error_label = _add_label("", &"SecondaryLabel")
	_error_label.name = "ErrorLabel"
	_error_label.visible = false


static func choice_label(choice: String, chance: float) -> String:
	if choice == MovementTypes.BEAR_OFF_COLLIDE:
		return "Hold course and collide"
	return "Bear off to %s (%d%%)" % [choice, roundi(chance * 100.0)]


## "Bearing off succeeds on a d10 of 5 or less (+1 for MPs plotted)." or "… cannot bear off …".
static func odds_text(situation: MovementTypes.BearOffSituation) -> String:
	if situation.number < 0:
		return "This crew cannot bear off (NA on the Bearing Off chart)."
	var text := "Bearing off succeeds on a d10 of %d or less" % situation.number
	if situation.drm != 0:
		text += " (%+d for MPs plotted)" % situation.drm
	return text + "."


func show_error(reason: String) -> void:
	for button in _buttons:
		button.disabled = false
	_error_label.text = reason
	_error_label.visible = true


## The refusal shown, "" when none.
func error_text() -> String:
	return _error_label.text if _error_label != null and _error_label.visible else ""


func _add_label(text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	add_child(label)
	return label


func _add_button(text: String, choice: String) -> void:
	var button := Button.new()
	button.text = text
	button.name = "Choice_" + choice
	button.pressed.connect(_on_pressed.bind(choice))
	add_child(button)
	_buttons.append(button)


func _on_pressed(choice: String) -> void:
	for button in _buttons:
		button.disabled = true  # no double submit while the server decides
	choice_made.emit(_ship_id, choice)
