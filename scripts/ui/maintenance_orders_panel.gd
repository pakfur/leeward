class_name MaintenanceOrdersPanel
extends VBoxContainer
## MaintenanceOrdersPanel - the player's grapple (SoP V.C) or ungrapple (V.D) orders in the
## Maintenance Phase (Close Action 8.C; boarding spec §4.3), or the prize-crew sizes (10.G.6). One
## toggle per grapple choice with its chance, or one stepper per prize from the minimum to the
## surviving boarders with both crews after it; then Done. Widget state and text only;
## GameController submits the orders to the server.

## `orders`: [[ship_id, target_id], ...] for grapple / ungrapple, {action_id: size} for prize_size.
signal orders_submitted(step: String, orders: Variant)

var _step: String = ""
var _toggles: Array[Button] = []
var _pairs: Array = []  # parallel to _toggles: [ship_id, target_id]
var _done: Button = null
var _error_label: Label = null
## prize_size: action_id -> {"option": Dictionary, "size": int, "label": Label}
var _prizes: Dictionary = {}


## `step`: "grapple" or "ungrapple". `options`: TurnPhaseController.maintenance_options entries.
## `names`: ship_id -> display name.
func setup(step: String, options: Array, names: Dictionary) -> void:
	_step = step
	name = "MaintenanceOrdersPanel"
	add_theme_constant_override("separation", 8)
	_add_label(intro_text(step))
	if step == "prize_size":
		for option in options:
			_add_prize_stepper(option, names)
		options = []
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
	match step:
		"grapple":
			return "Grappling"
		"prize_size":
			return "Prize crew"
	return "Ungrappling"


static func intro_text(step: String) -> String:
	match step:
		"grapple":
			return "Ships alongside may throw grapples. Tick the ships to grapple:"
		"prize_size":
			return "Your boarders have finished reorganizing. Choose how many stay aboard as the prize crew:"
	return "Your ships may try to cut their grapples. Tick the grapples to cut:"


static func rule_text(step: String) -> String:
	match step:
		"grapple":
			return "Grappled ships cannot move or turn; they drift together (8.C.7, 8.A.6)."
		"prize_size":
			return "At least the minimum for her class; a larger prize crew is harder to retake (10.G.6, 10.H.4). The rest of the boarders return next turn (10.G.9)."
	return "Each try is easier than the last (Unfouling table, 8.C.4)."


## "Topaze: prize crew 3 (minimum 2) · Topaze 0-0-1-2:0 · Lively keeps 0-3-5-6:2".
static func prize_text(option: Dictionary, crew_size: int, names: Dictionary) -> String:
	var prize := str(names.get(option["prize_id"], option["prize_id"]))
	var captor := str(names.get(option["captor_id"], option["captor_id"]))
	var preview: Dictionary = {}
	for p in option.get("previews", []):
		if int(p.get("size", -1)) == crew_size:
			preview = p
	return "%s: prize crew %d (minimum %d) · %s %s · %s keeps %s" % [prize, crew_size, int(option["minimum"]),
		prize, str(preview.get("prize", "?")), captor, str(preview.get("parent", "?"))]


func _add_prize_stepper(option: Dictionary, names: Dictionary) -> void:
	var id := int(option["action_id"])
	var row := HBoxContainer.new()
	row.name = "Prize_%d" % id
	var minus := Button.new()
	minus.text = "−"
	minus.name = "Less"
	minus.focus_mode = Control.FOCUS_NONE
	var plus := Button.new()
	plus.text = "+"
	plus.name = "More"
	plus.focus_mode = Control.FOCUS_NONE
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(minus)
	row.add_child(plus)
	row.add_child(label)
	add_child(row)
	_prizes[id] = {"option": option, "size": int(option.get("size", option["minimum"])), "label": label, "names": names}
	minus.pressed.connect(func(): step_prize(id, -1))
	plus.pressed.connect(func(): step_prize(id, 1))
	label.text = prize_text(option, int(_prizes[id]["size"]), names)


## The chosen size of a prize crew moves by `delta`, within the minimum and the boarders.
func step_prize(action_id: int, delta: int) -> void:
	if not _prizes.has(action_id):
		return
	var entry: Dictionary = _prizes[action_id]
	var option: Dictionary = entry["option"]
	entry["size"] = clampi(int(entry["size"]) + delta, int(option["minimum"]), int(option["maximum"]))
	(entry["label"] as Label).text = prize_text(option, int(entry["size"]), entry["names"])


## The chosen prize-crew sizes: {action_id: size}.
func selected_sizes() -> Dictionary:
	var out := {}
	for id in _prizes:
		out[id] = int(_prizes[id]["size"])
	return out


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
	if _step == "prize_size":
		orders_submitted.emit(_step, selected_sizes())
	else:
		orders_submitted.emit(_step, selected_pairs())
