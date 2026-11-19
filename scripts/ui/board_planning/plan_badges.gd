class_name PlanBadges
extends Control
## One small pill above each own ship on the map (PLAN, DONE, locked, SURRENDERED), with her
## standing orders as small marks beside it (the lead, ESCAPE, SURRENDER), following the camera like
## IndicatorOverlay. View only; takes no mouse input. Look: prototypes/planning_radial
## (`badgeSvg`, `statusOf`, the `I` icons).

## The pill of a ship struck by a voluntary surrender (14.B), in place of LOCKED.
const SURRENDERED := "surrendered"
const PILL_BG := {
	"plan": Color("#e3b344"),
	"done": Color("#62b47d"),
	"locked": Color("#3a4655"),
	SURRENDERED: Color("#3a4655"),
}
const PILL_FG := {
	"plan": Color("#1b1300"),
	"done": Color("#07160c"),
	"locked": Color("#c3ccd6"),
	SURRENDERED: Color("#f0f0f0"),
}
const PILL_TEXT := {
	"plan": "PLAN",
	"done": "✓ DONE",
	"locked": "LOCKED",
	SURRENDERED: "SURRENDERED",
}
## Standing-order marks, drawn in this order right of the pill.
const MARK_LEAD := "lead"
const MARK_ESCAPE := "escape"
const MARK_SURRENDER := "surrender"
const MARK_ORDER := [MARK_LEAD, MARK_ESCAPE, MARK_SURRENDER]
const MARK_TEXT := {MARK_ESCAPE: "ESCAPE", MARK_SURRENDER: "SURRENDER"}
const MARK_BG := {
	MARK_LEAD: Color("#1f2b39"),
	MARK_ESCAPE: Color("#79b7dc"),
	MARK_SURRENDER: Color("#e3b344"),  # amber
}
const MARK_FG := {MARK_ESCAPE: Color("#08131c"), MARK_SURRENDER: Color("#1b1300")}
const LEAD_ICON := preload("res://assets/ui/radial/lead.svg")
const MARK_GAP := 3.0
const PILL_HEIGHT := 17.0
const EDGE_GAP_PX := 4.0

## Screen rect of the map area (clear of the side panel); pills stay inside it. Unset: this Control.
var map_rect_provider: Callable = Callable()
## How far above its point a pill sits, in world units measured on screen (screen-up, so it clears
## the hull under a top-down camera too, and keeps its distance at every zoom). 0 = on the point.
var lift := 0.0

var _camera: Camera3D = null
var _hidden := ""  # the ship whose ring is open: her pill and marks are not drawn
var _entries: Dictionary = {}  # ship_id -> {"world": Vector3, "state": String, "marks": Array}
var _pills: Dictionary = {}  # ship_id -> Label
var _marks: Dictionary = {}  # ship_id -> HBoxContainer of her standing-order marks
var _mark_ids: Dictionary = {}  # ship_id -> Array[String] the marks drawn


func setup(camera: Camera3D) -> void:
	_camera = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## `entries`: ship_id -> {"world": Vector3, "state": "plan"|"done"|"locked"|SURRENDERED,
## "marks": Array of MARK_* (optional)}; replaces the set.
func show_for(entries: Dictionary) -> void:
	_entries = entries.duplicate()
	for id in _pills.keys():
		if not _entries.has(id) or not PILL_TEXT.has(_entries[id].get("state", "")):
			_drop(id)
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
		_show_marks(id, _entries[id].get("marks", []))
	_update()


## Hides this ship's pill and marks (her ring is open over them); "" shows every ship again.
func hide_ship(ship_id: String) -> void:
	_hidden = ship_id
	_update()


## The ship whose pill and marks are hidden, or "" (tests).
func hidden_ship() -> String:
	return _hidden


func clear() -> void:
	_hidden = ""
	_entries.clear()
	for id in _pills.keys():
		_drop(id)


## The pill for a ship, or null (tests).
func pill_for(ship_id: String) -> Label:
	return _pills.get(ship_id)


## The standing-order marks drawn beside a ship's pill, in order (tests).
func marks_for(ship_id: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(_mark_ids.get(ship_id, []))
	return out


func _process(_delta: float) -> void:
	if not _entries.is_empty():
		_update()


func _drop(ship_id: String) -> void:
	_pills[ship_id].queue_free()
	_pills.erase(ship_id)
	if _marks.has(ship_id):
		_marks[ship_id].queue_free()
		_marks.erase(ship_id)
	_mark_ids.erase(ship_id)


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
	pill.add_theme_stylebox_override("normal", _pill_box(PILL_BG[st]))
	pill.reset_size()
	pill.custom_minimum_size.y = PILL_HEIGHT


func _pill_box(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(PILL_HEIGHT / 2.0))
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


## Rebuilds a ship's marks when they changed: the lead as a small icon pill, ESCAPE and SURRENDER
## as text pills, in MARK_ORDER.
func _show_marks(ship_id: String, wanted: Array) -> void:
	var ids: Array = []  # untyped, as stored: compared with the last set
	for m in MARK_ORDER:
		if wanted.has(m):
			ids.append(m)
	if _mark_ids.get(ship_id, []) == ids:
		return
	_mark_ids[ship_id] = ids
	var box: HBoxContainer = _marks.get(ship_id)
	if box == null:
		box = HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", int(MARK_GAP))
		_marks[ship_id] = box
		add_child(box)
	for child in box.get_children():
		child.hide()  # left in the box (hidden: not laid out) until freed, so never an orphan
		child.queue_free()
	for m in ids:
		box.add_child(_make_mark(m))
	box.reset_size()


func _make_mark(mark: String) -> Control:
	if mark == MARK_LEAD:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := _pill_box(MARK_BG[mark])
		sb.content_margin_left = 3.0
		sb.content_margin_right = 3.0
		panel.add_theme_stylebox_override("panel", sb)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = LEAD_ICON
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(PILL_HEIGHT - 3.0, PILL_HEIGHT)
		panel.add_child(icon)
		return panel
	var l := _make_pill()
	l.text = MARK_TEXT[mark]
	l.add_theme_color_override("font_color", MARK_FG[mark])
	l.add_theme_stylebox_override("normal", _pill_box(MARK_BG[mark]))
	l.custom_minimum_size.y = PILL_HEIGHT
	return l


func _update() -> void:
	for id in _pills:
		var pill: Label = _pills[id]
		var box: HBoxContainer = _marks.get(id)
		var has_marks: bool = box != null and not _mark_ids.get(id, []).is_empty()
		if id == _hidden or _camera == null or _camera.is_position_behind(_entries[id]["world"]):
			pill.visible = false
			if box != null:
				box.visible = false
			continue
		var world: Vector3 = _entries[id]["world"]
		var p := _camera.unproject_position(world)
		if lift != 0.0:
			var unit_px := (_camera.unproject_position(world + _camera.global_basis.x) - p).length()
			p.y -= unit_px * lift
		pill.reset_size()
		# The pill stays centred over her; the marks sit to its right, and the pair stays on the map.
		var whole := pill.size
		if has_marks:
			box.reset_size()
			whole.x += MARK_GAP + box.size.x
		pill.position = keep_inside(p - Vector2(pill.size.x * 0.5, PILL_HEIGHT * 0.5), whole, _map_rect(), EDGE_GAP_PX)
		pill.visible = true
		if box != null:
			box.visible = has_marks
			box.position = pill.position + Vector2(pill.size.x + MARK_GAP, 0.0)


func _map_rect() -> Rect2:
	if map_rect_provider.is_valid():
		return map_rect_provider.call()
	return get_rect()


## Top-left that keeps a pill of `pill_size` at `pos` inside `rect` (inset by `gap`). Pure.
static func keep_inside(pos: Vector2, pill_size: Vector2, rect: Rect2, gap: float) -> Vector2:
	var lo := rect.position + Vector2(gap, gap)
	var hi := rect.end - pill_size - Vector2(gap, gap)
	return Vector2(clampf(pos.x, lo.x, maxf(lo.x, hi.x)), clampf(pos.y, lo.y, maxf(lo.y, hi.y)))
