class_name FireOptionBox
extends PanelContainer
## The option box beside a fire target (board planning piece 3, view only): what FireBoard.box_content
## gives, shown as chips. Guns: the title "<ship> → <target> · range n", the battery chips (only those
## that bear), Low / High, Round / Dismantling, the voluntary reduction − n +, the modified gunfire
## number and its breakdown, the notes (forced high, dismantling range, two targets), ✓ Order /
## Cancel. Marines: the title, the column and chance, ✓ Order / Cancel. Every press is a signal;
## FireBoard changes the model and the box is shown again. Follows the camera like CourseChips; its
## buttons take no focus (Enter and Esc stay the board's keys). Look: prototypes/planning_radial
## (`.chipbox`, `ui.pending`).

signal battery_picked(battery: String)
signal aim_picked(high: bool)
signal ammo_picked(dismantling: bool)
signal reduction_stepped(delta: int)
signal order_pressed()
signal cancel_pressed()

## How far right of the target's centre (world units on screen, hex size 1) the box's left edge sits.
const SIDE_GAP := 1.6
const MIN_GAP_PX := 40.0
const NOTE_WIDTH := 280.0
const EDGE_GAP_PX := 4.0
const ON_BG := Color("#3b5a2f")
const ON_EDGE := Color("#7fbf5f")

## Prototype pixels to screen pixels (CrewStyle.K); read when the box is built.
var ui_scale := 1.0
## Screen rect of the map area; the box stays inside it. Unset: no clamp.
var map_rect_provider: Callable = Callable()

var _camera: Camera3D = null
var _world: Variant = null
var _content: Dictionary = {}
var _title: Label
var _battery_row: HBoxContainer
var _aim_row: HBoxContainer
var _low: Button
var _high: Button
var _ammo_row: HBoxContainer
var _round: Button
var _dismantling: Button
var _reduce_row: HBoxContainer
var _minus: Button
var _reduce_value: Label
var _plus: Button
var _number: Label
var _text: Label
var _notes: Array[Label] = []  # aim, ammunition, two targets
var _order: Button
var _cancel: Button


func _init() -> void:
	name = "FireOptionBox"
	visible = false
	set_process(false)


func setup(camera: Camera3D) -> void:
	_camera = camera
	if _title == null:
		_build()


## Shows `content` (FireBoard.box_content) beside the target at `world` (null: stays where it is).
func show_box(content: Dictionary, world: Variant = null) -> void:
	if _title == null:
		_build()
	_content = content
	var guns: bool = content.get("kind", "") == "guns"
	_title.text = str(content.get("title", ""))
	for child in _battery_row.get_children():
		child.hide()
		child.queue_free()
	var chips: Array = content.get("batteries", [])
	for chip: Dictionary in chips:
		var b := _chip(str(chip["label"]), bool(chip.get("on", false)))
		var battery := str(chip["id"])
		b.set_meta("battery", battery)
		b.pressed.connect(func(): battery_picked.emit(battery))
		_battery_row.add_child(b)
	_battery_row.visible = guns and not chips.is_empty()
	_aim_row.visible = guns
	_ammo_row.visible = guns
	_reduce_row.visible = guns and bool(content.get("can_fire", false))
	if guns:
		var high: bool = content.get("high", false)
		_restyle(_low, not high)
		_restyle(_high, high)
		_low.disabled = bool(content.get("low_off", false))
		var dis: bool = content.get("dismantling", false)
		_restyle(_round, not dis)
		_restyle(_dismantling, dis)
		_dismantling.disabled = bool(content.get("dismantling_off", false))
		var n := int(content.get("reduction", 0))
		_reduce_value.text = str(n)
		_minus.disabled = n <= 0
		_number.text = "Gunfire %d" % int(content.get("number", 0)) if content.get("can_fire", false) else "Cannot fire"
		_text.text = str(content.get("breakdown", ""))
	else:
		_number.text = ""
		_text.text = str(content.get("text", ""))
	_number.visible = guns
	var note_keys := ["aim_note", "dismantling_note", "two_target"]
	for i in note_keys.size():
		var note := str(content.get(note_keys[i], "")) if guns else ""
		_notes[i].text = note
		_notes[i].visible = note != ""
	if world != null:
		_world = world
	visible = true
	set_process(true)
	reset_size()
	_place()


func hide_box() -> void:
	visible = false
	set_process(false)
	_world = null
	_content = {}


func is_open() -> bool:
	return visible


func content() -> Dictionary:
	return _content


func title_text() -> String:
	return _title.text if _title else ""


func number_text() -> String:
	return _number.text if _number and _number.visible else ""


## The main text (the gunfire breakdown, or the marines' column and chance).
func body_text() -> String:
	return _text.text if _text else ""


## The visible notes, in order (tests).
func notes() -> Array[String]:
	var out: Array[String] = []
	for l in _notes:
		if l.visible:
			out.append(l.text)
	return out


## The battery chips, in order (tests); freed chips of an earlier show are left out.
func battery_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _battery_row:
		for c in _battery_row.get_children():
			if c is Button and not c.is_queued_for_deletion():
				out.append(c)
	return out


func low_button() -> Button:
	return _low


func high_button() -> Button:
	return _high


func round_button() -> Button:
	return _round


func dismantling_button() -> Button:
	return _dismantling


func minus_button() -> Button:
	return _minus


func plus_button() -> Button:
	return _plus


func order_button() -> Button:
	return _order


func cancel_button() -> Button:
	return _cancel


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	if _camera == null or not (_world is Vector3) or not _camera.is_inside_tree():
		return
	if _camera.is_position_behind(_world):
		modulate.a = 0.0
		return
	modulate.a = 1.0
	var at := _camera.unproject_position(_world)
	var unit_px := (_camera.unproject_position(_world + _camera.global_basis.x) - at).length()
	var p := at + Vector2(maxf(unit_px * SIDE_GAP, MIN_GAP_PX), -size.y / 2.0)
	if map_rect_provider.is_valid():
		p = PlanBadges.keep_inside(p, size, map_rect_provider.call(), EDGE_GAP_PX)
	position = p


func _build() -> void:
	var s := ui_scale
	mouse_filter = Control.MOUSE_FILTER_STOP  # a click on the box is not a click on the sea
	var bg := CrewStyle.box(CourseChips.BG, CrewStyle.LINE, 1, roundi(8.0 * s), 7.0 * s)
	bg.shadow_color = Color(0, 0, 0, 0.5)
	bg.shadow_size = roundi(7.0 * s)
	bg.shadow_offset = Vector2(0, 4.0 * s)
	add_theme_stylebox_override("panel", bg)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", roundi(5.0 * s))
	add_child(col)
	_title = _line(&"StrongLabel", CrewStyle.FG, false)
	col.add_child(_title)
	_battery_row = _row()
	col.add_child(_battery_row)
	_aim_row = _row()
	col.add_child(_aim_row)
	_low = _chip("Low", false)
	_low.name = "Low"
	_low.pressed.connect(func(): aim_picked.emit(false))
	_aim_row.add_child(_low)
	_high = _chip("High", false)
	_high.name = "High"
	_high.pressed.connect(func(): aim_picked.emit(true))
	_aim_row.add_child(_high)
	_ammo_row = _row()
	col.add_child(_ammo_row)
	_round = _chip("Round", false)
	_round.name = "Round"
	_round.pressed.connect(func(): ammo_picked.emit(false))
	_ammo_row.add_child(_round)
	_dismantling = _chip("Dismantling", false)
	_dismantling.name = "Dismantling"
	_dismantling.pressed.connect(func(): ammo_picked.emit(true))
	_ammo_row.add_child(_dismantling)
	_reduce_row = _row()
	col.add_child(_reduce_row)
	var reduce := _line(&"", CrewStyle.MUTED, false)
	reduce.text = "Reduce fire"
	_reduce_row.add_child(reduce)
	_minus = _chip("−", false)
	_minus.name = "Minus"
	_minus.pressed.connect(func(): reduction_stepped.emit(-1))
	_reduce_row.add_child(_minus)
	_reduce_value = _line(&"CounterBoldLabel", CrewStyle.FG, false)
	_reduce_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reduce_value.custom_minimum_size.x = 18.0 * s
	_reduce_row.add_child(_reduce_value)
	_plus = _chip("+", false)
	_plus.name = "Plus"
	_plus.pressed.connect(func(): reduction_stepped.emit(1))
	_reduce_row.add_child(_plus)
	_number = _line(&"StrongLabel", CrewStyle.WARN, false)
	col.add_child(_number)
	_text = _line(&"", CrewStyle.MUTED, true)
	_text.visible = true
	col.add_child(_text)
	for i in 3:
		var note := _line(&"", CrewStyle.WARN, true)
		col.add_child(note)
		_notes.append(note)
	var actions := _row()
	col.add_child(actions)
	_order = _chip("✓ Order", false, CourseChips.DONE_BG, CourseChips.DONE_EDGE)
	_order.name = "Order"
	_order.pressed.connect(func(): order_pressed.emit())
	actions.add_child(_order)
	_cancel = _chip("Cancel", false)
	_cancel.name = "Cancel"
	_cancel.pressed.connect(func(): cancel_pressed.emit())
	actions.add_child(_cancel)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(6.0 * ui_scale))
	return row


func _line(variation: StringName, color: Color, wrapped: bool) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if variation != &"":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", roundi(13.0 * ui_scale))
	l.add_theme_color_override("font_color", color)
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = NOTE_WIDTH * ui_scale
		l.visible = false
	return l


func _chip(text: String, on: bool, bg := CrewStyle.BTN, edge := CrewStyle.BTN_EDGE) -> Button:
	var s := ui_scale
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # Enter / Esc stay the board's keys
	b.add_theme_font_override("font", CrewStyle.theme_font(CrewStyle.STRONG))
	b.add_theme_font_size_override("font_size", roundi(13.0 * s))
	b.set_meta("bg", bg)
	b.set_meta("edge", edge)
	_restyle(b, on)
	b.add_theme_color_override("font_color", CrewStyle.FG)
	b.add_theme_color_override("font_hover_color", CrewStyle.FG)
	b.add_theme_color_override("font_disabled_color", CrewStyle.MUTED)
	return b


## A chip's look for on (chosen) or off.
func _restyle(b: Button, on: bool) -> void:
	var s := ui_scale
	var normal := CrewStyle.box(ON_BG if on else b.get_meta("bg"), ON_EDGE if on else b.get_meta("edge"),
		1, roundi(14.0 * s))
	normal.content_margin_left = 10.0 * s
	normal.content_margin_right = 10.0 * s
	normal.content_margin_top = 3.0 * s
	normal.content_margin_bottom = 3.0 * s
	var hover: StyleBoxFlat = normal.duplicate()
	hover.border_color = RadialMenu.BRASS
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = CrewStyle.PANEL
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.set_meta("on", on)


## Whether a chip is drawn as chosen (tests).
static func is_on(b: Button) -> bool:
	return bool(b.get_meta("on", false))
