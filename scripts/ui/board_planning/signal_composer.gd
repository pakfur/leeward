class_name SignalComposer
extends PanelContainer
## The signal box by the ship (board planning piece 2, view only): "Signal from <ship>", an
## address picker (Fleet, each group, each ship by name), a one-line text field with a live word
## count, Send / Close, and the signal already sent this g-t with Cancel signal. It follows the
## camera like CourseChips. The field is the one control that takes keyboard focus; while it has
## it the board's keys are off (`is_typing`). The server re-checks everything on send
## (`player_send_signal`); the count here reads `SignalText.words` and is only a guide.

signal send_requested(address: Dictionary, text: String)
signal cancel_pending_requested()
signal closed()

const BOX_WIDTH := 300.0
const SIDE_GAP := 1.6  # world units from the ship's centre to the box's left edge
const EDGE_GAP_PX := 4.0
const BG := Color(0.078, 0.114, 0.157, 0.94)

## Prototype pixels to screen pixels (CrewStyle.K); read when the box is built.
var ui_scale := 1.0
## Screen rect of the map area; the box stays inside it. Unset: no clamp.
var map_rect_provider: Callable = Callable()
## Every ship's name (a ship's name is one word in a signal, 11.A.7); set by BoardPlanning.
var ship_names: Array[String] = []

var _camera: Camera3D = null
var _world: Variant = null
var _limit := 0
var _addresses: Array = []
var _title: Label
var _picker: OptionButton
var _field: LineEdit
var _count: Label
var _error: Label
var _pending_box: VBoxContainer
var _pending_label: Label
var _send: Button
var _close: Button
var _cancel: Button


func _init() -> void:
	name = "SignalComposer"
	visible = false
	set_process(false)


func setup(camera: Camera3D) -> void:
	_camera = camera
	if _title == null:
		_build()


## Opens the box for `ship_name` with `options`, the `signal` entry of `order_options`
## ({error, pending, limit, addresses}). Reopening while open keeps what was typed and the
## address picked (a sent or cancelled signal re-reads the pending line).
func open(ship_name: String, options: Dictionary, world: Variant = null) -> void:
	if _title == null:
		_build()
	var keep_text := visible
	var keep_address := selected_address() if visible else {}
	_title.text = "Signal from %s" % ship_name
	_limit = int(options.get("limit", 0))
	_addresses = options.get("addresses", []).duplicate()
	_picker.clear()
	for i in _addresses.size():
		_picker.add_item(str(_addresses[i].get("label", "")))
		if _addresses[i].get("kind", "") == keep_address.get("kind", "?") \
				and _addresses[i].get("name", "") == keep_address.get("name", "?"):
			_picker.select(i)
	if _picker.item_count > 0 and _picker.selected < 0:
		_picker.select(0)
	if not keep_text:
		_field.text = ""
		_error.text = ""
		_error.visible = false
	_show_pending(options.get("pending", {}))
	_update_count()
	if world != null:
		_world = world
	visible = true
	set_process(true)
	reset_size()
	_place()
	if not keep_text and is_inside_tree():
		_field.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	_world = null
	if _field and _field.has_focus():
		_field.release_focus()
	closed.emit()


## Shows the server's refusal under the field (amber); "" clears it.
func show_error(reason: String) -> void:
	_error.text = reason
	_error.visible = reason != ""
	reset_size()


## Empties the field (after a successful send).
func clear_text() -> void:
	_field.text = ""
	_update_count()


func is_open() -> bool:
	return visible


## True while the text field has keyboard focus: the board's keys are off.
func is_typing() -> bool:
	return visible and _field != null and _field.has_focus()


## The address picked: {"kind", "name"} (the server's form), {} when there is none.
func selected_address() -> Dictionary:
	var i := _picker.selected if _picker else -1
	if i < 0 or i >= _addresses.size():
		return {}
	return {"kind": str(_addresses[i].get("kind", "")), "name": str(_addresses[i].get("name", ""))}


func select_address(index: int) -> void:
	_picker.select(index)


func set_text(value: String) -> void:
	_field.text = value
	_field.text_changed.emit(value)  # as typing does


func text() -> String:
	return _field.text


func title_text() -> String:
	return _title.text if _title else ""


## "n of limit words" (or the words error), as shown under the field.
func count_text() -> String:
	return _count.text


func count_is_over() -> bool:
	return _count.get_theme_color("font_color") == CrewStyle.WARN


func error_text() -> String:
	return _error.text if _error.visible else ""


## The pending signal's line ("To Fleet: ENGAGE THE ENEMY"), "" when none.
func pending_text() -> String:
	return _pending_label.text if _pending_box.visible else ""


func field() -> LineEdit:
	return _field


func send_button() -> Button:
	return _send


func close_button() -> Button:
	return _close


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
	var p := _camera.unproject_position(_world)
	var unit_px := (_camera.unproject_position(_world + _camera.global_basis.x) - p).length()
	var at := p + Vector2(unit_px * SIDE_GAP, -size.y * 0.5)
	if map_rect_provider.is_valid():
		var rect: Rect2 = map_rect_provider.call()
		at = PlanBadges.keep_inside(at, size, rect, EDGE_GAP_PX)
	position = at


func _submit() -> void:
	var t := _field.text.strip_edges()
	if t == "":
		show_error("Type the signal first.")
		return
	send_requested.emit(selected_address(), t)


func _show_pending(pending: Dictionary) -> void:
	if pending.is_empty():
		_pending_box.visible = false
		_pending_label.text = ""
		return
	var addr: Dictionary = pending.get("address", {})
	var to := "Fleet"
	for a in _addresses:
		if a.get("kind", "") == addr.get("kind", "") and a.get("name", "") == addr.get("name", ""):
			to = str(a.get("label", to))
	_pending_label.text = "To %s: %s" % [to, " ".join(PackedStringArray(pending.get("words", [])))]
	_pending_box.visible = true


func _update_count() -> void:
	var t := _field.text.strip_edges()
	var n := 0
	var over := false
	var note := ""
	if t != "":
		var parsed := SignalText.words(t, ship_names)
		n = (parsed["words"] as Array).size()
		note = str(parsed["error"])
		over = _limit > 0 and n > _limit
	_count.text = note if note != "" else "%d of %d words" % [n, _limit]
	_count.add_theme_color_override("font_color", CrewStyle.WARN if over or note != "" else CrewStyle.MUTED)
	reset_size()


func _on_field_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		field().accept_event()
		close()


func _build() -> void:
	var s := ui_scale
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = BOX_WIDTH * s
	var bg := CrewStyle.box(BG, CrewStyle.LINE, 1, roundi(8.0 * s), 8.0 * s)
	bg.shadow_color = Color(0, 0, 0, 0.5)
	bg.shadow_size = roundi(7.0 * s)
	bg.shadow_offset = Vector2(0, 4.0 * s)
	add_theme_stylebox_override("panel", bg)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", roundi(5.0 * s))
	add_child(col)
	_title = _line(&"StrongLabel", CrewStyle.FG)
	col.add_child(_title)
	_picker = OptionButton.new()
	_picker.name = "Address"
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.add_theme_font_size_override("font_size", roundi(13.0 * s))
	col.add_child(_picker)
	_field = LineEdit.new()
	_field.name = "Text"
	_field.placeholder_text = "Signal text"
	_field.add_theme_font_size_override("font_size", roundi(14.0 * s))
	_field.text_changed.connect(func(_t: String):
		show_error("")  # an edit answers the refusal
		_update_count())
	_field.text_submitted.connect(func(_t: String): _submit())
	_field.gui_input.connect(_on_field_gui_input)
	_field.focus_next = NodePath(".")  # Tab stays in the field, never on to the side panel
	_field.focus_previous = NodePath(".")
	# Enter sends and the field stays in edit mode: out of it, a focused field lets letters reach
	# the game's keys (C would open the crew overlay).
	_field.keep_editing_on_text_submit = true
	col.add_child(_field)
	_count = _line(&"", CrewStyle.MUTED)
	col.add_child(_count)
	_error = _line(&"", CrewStyle.WARN)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size.x = (BOX_WIDTH - 16.0) * s
	_error.visible = false
	col.add_child(_error)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(6.0 * s))
	col.add_child(row)
	_send = _chip("Send", CrewStyle.BTN_PRIMARY, CrewStyle.BTN_PRIMARY_EDGE)
	_send.name = "Send"
	_send.pressed.connect(_submit)
	row.add_child(_send)
	_close = _chip("Close", CrewStyle.BTN, CrewStyle.BTN_EDGE)
	_close.name = "Close"
	_close.pressed.connect(close)
	row.add_child(_close)
	_pending_box = VBoxContainer.new()
	_pending_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pending_box.visible = false
	col.add_child(_pending_box)
	_pending_label = _line(&"", CrewStyle.FG)
	_pending_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending_label.custom_minimum_size.x = (BOX_WIDTH - 16.0) * s
	_pending_box.add_child(_pending_label)
	_cancel = _chip("Cancel signal", CrewStyle.BTN, CrewStyle.BTN_EDGE)
	_cancel.name = "CancelSignal"
	_cancel.pressed.connect(func(): cancel_pending_requested.emit())
	_pending_box.add_child(_cancel)


func _line(variation: StringName, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if variation != &"":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", roundi(13.0 * ui_scale))
	l.add_theme_color_override("font_color", color)
	return l


func _chip(label: String, bg: Color, edge: Color) -> Button:
	var s := ui_scale
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE  # the field is the only control that takes the keyboard
	b.add_theme_font_override("font", CrewStyle.theme_font(CrewStyle.STRONG))
	b.add_theme_font_size_override("font_size", roundi(13.0 * s))
	var normal := CrewStyle.box(bg, edge, 1, roundi(14.0 * s))
	normal.content_margin_left = 10.0 * s
	normal.content_margin_right = 10.0 * s
	normal.content_margin_top = 3.0 * s
	normal.content_margin_bottom = 3.0 * s
	var hover: StyleBoxFlat = normal.duplicate()
	hover.border_color = RadialMenu.BRASS
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", CrewStyle.FG)
	b.add_theme_color_override("font_hover_color", CrewStyle.FG)
	return b
