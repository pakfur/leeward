class_name FireMarks
extends Control
## The fire step's marks on the map (board planning piece 3, view only): one arrow per fire order,
## from the firing battery to the target in the side's colour (BroadsideColors; muskets in their
## own), labelled with the aim and the modified number, and in target mode a "range n" label under
## each target. Data from FireBoard.arrows / range_labels (world points); drawn in screen space
## every frame so it follows the camera. Takes no mouse input. Look: prototypes/planning_radial
## (`.order`, the `arr` marker, `range n`).

const WIDTH := 3.0
const HEAD := 11.0
const LABEL_SIZE := 13
const LABEL_BG := Color(0.055, 0.082, 0.114, 0.8)
const RANGE_COLOR := Color("#e3b344")
## How far below a target's centre (world units on screen) its range label sits.
const RANGE_DROP := 1.1

var _camera: Camera3D = null
var _arrows: Array[Dictionary] = []
var _labels: Array[Dictionary] = []


func setup(camera: Camera3D) -> void:
	_camera = camera
	set_process(false)  # on only while marks are shown
	name = "FireMarks"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Replaces the marks: `arrows` from FireBoard.arrows, `labels` from FireBoard.range_labels.
func show_marks(arrows: Array[Dictionary], labels: Array[Dictionary]) -> void:
	_arrows = arrows.duplicate()
	_labels = labels.duplicate()
	set_process(not (_arrows.is_empty() and _labels.is_empty()))
	queue_redraw()


func clear() -> void:
	show_marks([] as Array[Dictionary], [] as Array[Dictionary])


func arrow_data() -> Array[Dictionary]:
	return _arrows.duplicate()


func label_data() -> Array[Dictionary]:
	return _labels.duplicate()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _camera == null or not _camera.is_inside_tree():
		return
	var font := get_theme_font("font", &"CounterBoldLabel")
	for a in _arrows:
		var from: Vector3 = a["from"]
		var to: Vector3 = a["to"]
		if _camera.is_position_behind(from) or _camera.is_position_behind(to):
			continue
		var p0 := _camera.unproject_position(from)
		var p1 := _camera.unproject_position(to)
		var color: Color = a["color"]
		if a.get("dim", false):
			color.a = FireBoard.DIM_ALPHA
		var dir := (p1 - p0)
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		var tip := p1 - dir * HEAD * 0.5
		draw_line(p0, tip - dir * HEAD * 0.6, color, WIDTH, true)
		var normal := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * HEAD + normal * HEAD * 0.5,
			tip - dir * HEAD - normal * HEAD * 0.5]), color)
		_label(font, (p0 + p1) * 0.5 - Vector2(0, 8), str(a.get("text", "")), Color(1, 1, 1, color.a))
	for l in _labels:
		var world: Vector3 = l["world"]
		if _camera.is_position_behind(world):
			continue
		var at := _camera.unproject_position(world)
		var unit_px := (_camera.unproject_position(world + _camera.global_basis.x) - at).length()
		_label(font, at + Vector2(0, unit_px * RANGE_DROP), str(l["text"]), RANGE_COLOR)


func _label(font: Font, centre: Vector2, text: String, color: Color) -> void:
	if text == "" or font == null:
		return
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var box := Rect2(centre - Vector2(extent.x / 2.0 + 4.0, extent.y / 2.0 + 1.0), extent + Vector2(8.0, 2.0))
	draw_rect(box, Color(LABEL_BG.r, LABEL_BG.g, LABEL_BG.b, LABEL_BG.a * color.a))
	draw_string(font, Vector2(box.position.x + 4.0, centre.y + extent.y * 0.3), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
