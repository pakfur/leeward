class_name PlanBadges
extends Control
## One small pill above each own ship on the map (PLAN, DONE, locked), following the camera like
## IndicatorOverlay. View only; takes no mouse input. Look: prototypes/planning_radial
## (`badgeSvg`, `statusOf`).

const PILL_BG := {
	"plan": Color("#e3b344"),
	"done": Color("#62b47d"),
	"locked": Color("#3a4655"),
}
const PILL_FG := {
	"plan": Color("#1b1300"),
	"done": Color("#07160c"),
	"locked": Color("#c3ccd6"),
}
const PILL_TEXT := {
	"plan": "PLAN",
	"done": "✓ DONE",
	"locked": "LOCKED",
}
const PILL_HEIGHT := 17.0
const EDGE_GAP_PX := 4.0

## Screen rect of the map area (clear of the side panel); pills stay inside it. Unset: this Control.
var map_rect_provider: Callable = Callable()
## How far above its point a pill sits, in world units measured on screen (screen-up, so it clears
## the hull under a top-down camera too, and keeps its distance at every zoom). 0 = on the point.
var lift := 0.0

var _camera: Camera3D = null
var _entries: Dictionary = {}  # ship_id -> {"world": Vector3, "state": String}
var _pills: Dictionary = {}  # ship_id -> Label


func setup(camera: Camera3D) -> void:
	_camera = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## `entries`: ship_id -> {"world": Vector3, "state": "plan"|"done"|"locked"}; replaces the set.
func show_for(entries: Dictionary) -> void:
	_entries = entries.duplicate()
	for id in _pills.keys():
		if not _entries.has(id) or not PILL_TEXT.has(_entries[id].get("state", "")):
			_pills[id].queue_free()
			_pills.erase(id)
	for id in _entries:
		var st: String = _entries[id].get("state", "")
		if not PILL_TEXT.has(st):
			continue
		var pill: Label = _pills.get(id)
		if pill == null:
			pill = _make_pill()
			_pills[id] = pill
			add_child(pill)
		_style(pill, st)
	_update()


func clear() -> void:
	_entries.clear()
	for pill in _pills.values():
		pill.queue_free()
	_pills.clear()


## The pill for a ship, or null (tests).
func pill_for(ship_id: String) -> Label:
	return _pills.get(ship_id)


func _process(_delta: float) -> void:
	if not _entries.is_empty():
		_update()


func _make_pill() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = &"CounterBoldLabel"
	l.add_theme_font_size_override("font_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _style(pill: Label, st: String) -> void:
	pill.text = PILL_TEXT[st]
	pill.add_theme_color_override("font_color", PILL_FG[st])
	var sb := StyleBoxFlat.new()
	sb.bg_color = PILL_BG[st]
	sb.set_corner_radius_all(int(PILL_HEIGHT / 2.0))
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	pill.add_theme_stylebox_override("normal", sb)
	pill.reset_size()
	pill.custom_minimum_size.y = PILL_HEIGHT


func _update() -> void:
	for id in _pills:
		var pill: Label = _pills[id]
		if _camera == null or _camera.is_position_behind(_entries[id]["world"]):
			pill.visible = false
			continue
		var world: Vector3 = _entries[id]["world"]
		var p := _camera.unproject_position(world)
		if lift != 0.0:
			var unit_px := (_camera.unproject_position(world + _camera.global_basis.x) - p).length()
			p.y -= unit_px * lift
		pill.reset_size()
		pill.position = keep_inside(p - Vector2(pill.size.x * 0.5, PILL_HEIGHT * 0.5), pill.size, _map_rect(), EDGE_GAP_PX)
		pill.visible = true


func _map_rect() -> Rect2:
	if map_rect_provider.is_valid():
		return map_rect_provider.call()
	return get_rect()


## Top-left that keeps a pill of `pill_size` at `pos` inside `rect` (inset by `gap`). Pure.
static func keep_inside(pos: Vector2, pill_size: Vector2, rect: Rect2, gap: float) -> Vector2:
	var lo := rect.position + Vector2(gap, gap)
	var hi := rect.end - pill_size - Vector2(gap, gap)
	return Vector2(clampf(pos.x, lo.x, maxf(lo.x, hi.x)), clampf(pos.y, lo.y, maxf(lo.y, hi.y)))
