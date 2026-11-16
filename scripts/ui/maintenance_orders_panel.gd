class_name MaintenanceOrdersPanel
extends VBoxContainer
## MaintenanceOrdersPanel - the player's grapple (SoP V.C) or ungrapple (V.D) orders in the
## Maintenance Phase (Close Action 8.C; boarding spec §4.3). One toggle per choice with its chance,
## then Done. Widget state and text only; GameController submits the orders to the server.

signal orders_submitted(step: String, pairs: Array)

var _step: String = ""
var _toggles: Array[Button] = []
var _pairs: Array = []  # parallel to _toggles: [ship_id, target_id]
var _done: Button = null
var _error_label: Label = null


## `step`: "grapple" or "ungrapple". `options`: TurnPhaseController.maintenance_options entries.
## `names`: ship_id -> display name.
func setup(step: String, options: Array, names: Dictionary) -> void:
	_step = step
	name = "MaintenanceOrdersPanel"
	add_theme_constant_override("separation", 8)
	_add_label(intro_text(step))
	for option in options:
		# A toggle row in the fire panel's style: "☐ …" / "☑ …".
		var toggle := Button.new()
		var label := option_label(step, option, names)
		toggle.toggle_mode = true
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		toggle.theme_type_variation = &"SecondaryButton"
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.text = toggle_text(label, false)
		toggle.name = "Toggle_%s_%s" % [option["ship_id"], option["target_id"]]
		toggle.toggled.connect(func(on: bool): toggle.text = toggle_text(label, on))
		add_child(toggle)
		_toggles.append(toggle)
		_pairs.append([str(option["ship_id"]), str(option["target_id"])])
	_add_label(rule_text(step), &"SecondaryLabel")
	_done = Button.new()
	_done.text = "Done"
	_done.name = "DoneButton"
	_done.pressed.connect(_on_done)
	add_child(_done)
	_error_label = _add_label("", &"SecondaryLabel")
	_error_label.visible = false


static func toggle_text(label: String, on: bool) -> String:
	return ("☑ " if on else "☐ ") + label


static func title(step: String) -> String:
	return "Grappling" if step == "grapple" else "Ungrappling"


static func intro_text(step: String) -> String:
	if step == "grapple":
		return "Ships alongside may throw grapples. Tick the ships to grapple:"
	return "Your ships may try to cut their grapples. Tick the grapples to cut:"


static func rule_text(step: String) -> String:
	if step == "grapple":
		return "Grappled ships cannot move or turn; they drift together (8.C.7, 8.A.6)."
	return "Each try is easier than the last (Unfouling table, 8.C.4)."


## "Hermione: grapple Vengeance — needs 2 or less, 40 %" / "Hermione: cut the grapples to
## Vengeance — needs 1 or less, 20 % (try 1)".
static func option_label(step: String, option: Dictionary, names: Dictionary) -> String:
	var ship := str(names.get(option["ship_id"], option["ship_id"]))
	var target := str(names.get(option["target_id"], option["target_id"]))
	var needed := int(option.get("needed", 0))
	var odds := "needs %d or less, %d %%" % [needed, int(option.get("percent", 0))] if needed >= 0 \
			else "cannot succeed"
	if step == "grapple":
		return "%s: grapple %s — %s" % [ship, target, odds]
	return "%s: cut the grapples to %s — %s (try %d)" % [ship, target, odds, int(option.get("attempt", 1))]


## The ticked [ship_id, target_id] pairs.
func selected_pairs() -> Array:
	var out: Array = []
	for i in _toggles.size():
		if _toggles[i].button_pressed:
			out.append(_pairs[i])
	return out


func show_error(reason: String) -> void:
	_done.disabled = false
	_error_label.text = reason
	_error_label.visible = true


func _add_label(text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	add_child(label)
	return label


func _on_done() -> void:
	_done.disabled = true  # no double submit while the server decides
	orders_submitted.emit(_step, selected_pairs())
