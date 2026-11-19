class_name CourseChips
extends PanelContainer
## The small box beside the course end of the Move-mode ship (board planning, view only): the
## course readout ("Course: n of m MP"), the notes the card's Course block shows (tacking,
## steering, heading), the warning line (a refused click, a collision, a jammed rudder, a course
## too short), then ✓ Done and Keep planning. Follows the camera every frame like IndicatorOverlay.
## Look: prototypes/planning_radial (`.chipbox`, `.chip`).

signal done_pressed()
signal keep_pressed()

## How far below the course end (world units on screen, hex size 1) the box's top edge sits:
## past every hex next to the end (centres 0.87 away, plus a hex's half height), so it never
## covers a hex the course may extend to. Centred under the end.
const DROP := 1.8
## The gap below the end when there is no camera scale to read (screen px).
const MIN_DROP_PX := 40.0
const NOTE_WIDTH := 260.0
const EDGE_GAP_PX := 4.0
const BG := Color(0.078, 0.114, 0.157, 0.94)  # rgba(20,29,40,.94)
const DONE_BG := Color("#2f6a45")
const DONE_EDGE := Color("#4f9a6a")

## Prototype pixels to screen pixels (the crew overlay's CrewStyle.K); read when the box is built.
var ui_scale := 1.0
## Screen rect of the map area (clear of the side panel); the box stays inside it. Unset: no clamp.
var map_rect_provider: Callable = Callable()

var _camera: Camera3D = null
var _world: Variant = null  # Vector3 of the course end, or null (no camera placement)
var _title: Label
var _notes: Array[Label] = []  # tacking, steering, note
var _warning: Label
var _done: Button
var _keep: Button


func _init() -> void:
	name = "CourseChips"
	visible = false
	set_process(false)


func setup(camera: Camera3D) -> void:
	_camera = camera
	if _title == null:
		_build()


## Shows the box for `info` (GameController._course_info: used, allowance, tacking, steering,
## note, collision) at the course end `world_end` (null: keep the box where it is).
func show_course(info: Dictionary, world_end: Variant) -> void:
	if _title == null:
		_build()
	_title.text = "Course: %d of %d MP" % [int(info.get("used", 0)), int(info.get("allowance", 0))]
	var keys := ["tacking", "steering", "note"]
	for i in keys.size():
		var text := str(info.get(keys[i], ""))
		_notes[i].text = text
		_notes[i].visible = text != ""
	var warning := str(info.get("collision", ""))
	_warning.text = warning
	_warning.visible = warning != ""
	_world = world_end
	visible = true
	set_process(true)
	reset_size()
	_place()


func hide_chips() -> void:
	visible = false
	set_process(false)
	_world = null


func title_text() -> String:
	return _title.text if _title else ""


## The visible note and warning lines, in order (tests).
func lines() -> Array[String]:
	var out: Array[String] = []
	for l in _notes + [_warning]:
		if l.visible:
			out.append(l.text)
	return out


func warning_text() -> String:
	return _warning.text if _warning and _warning.visible else ""


func done_button() -> Button:
	return _done


func keep_button() -> Button:
	return _keep


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	if _camera == null or not (_world is Vector3) or not _camera.is_inside_tree():
		return
	if _camera.is_position_behind(_world):
		modulate.a = 0.0
		return
	modulate.a = 1.0
	var end_px := _camera.unproject_position(_world)
	var unit_px := (_camera.unproject_position(_world + _camera.global_basis.x) - end_px).length()
	var p := end_px + Vector2(-size.x / 2.0, maxf(unit_px * DROP, MIN_DROP_PX))
	if map_rect_provider.is_valid():
		var rect: Rect2 = map_rect_provider.call()
		p = PlanBadges.keep_inside(p, size, rect, EDGE_GAP_PX)
	position = p


func _build() -> void:
	var s := ui_scale
	mouse_filter = Control.MOUSE_FILTER_STOP  # a click on the box is not a click on the sea
	var bg := CrewStyle.box(BG, CrewStyle.LINE, 1, roundi(8.0 * s), 7.0 * s)
	bg.shadow_color = Color(0, 0, 0, 0.5)
	bg.shadow_size = roundi(7.0 * s)
	bg.shadow_offset = Vector2(0, 4.0 * s)
	add_theme_stylebox_override("panel", bg)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", roundi(4.0 * s))
	add_child(col)
	_title = _line(&"StrongLabel", CrewStyle.FG, false)
	col.add_child(_title)
	for i in 3:
		var note := _line(&"", CrewStyle.MUTED, true)
		col.add_child(note)
		_notes.append(note)
	_warning = _line(&"", CrewStyle.WARN, true)
	col.add_child(_warning)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(6.0 * s))
	col.add_child(row)
	_done = _chip("✓ Done", DONE_BG, DONE_EDGE)
	_done.name = "Done"
	_done.pressed.connect(func(): done_pressed.emit())
	row.add_child(_done)
	_keep = _chip("Keep planning", CrewStyle.BTN, CrewStyle.BTN_EDGE)
	_keep.name = "KeepPlanning"
	_keep.pressed.connect(func(): keep_pressed.emit())
	row.add_child(_keep)


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


func _chip(text: String, bg: Color, edge: Color) -> Button:
	var s := ui_scale
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # Space / Enter stay the board's keys
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
