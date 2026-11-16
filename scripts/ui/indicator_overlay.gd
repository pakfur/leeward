extends Control
## IndicatorOverlay - 2D label(s) for the selected ship and plotting hover.
## Consumes ShipIndicatorModel DTOs. No game-state access. (View layer.)

var _camera: Camera3D = null
var _sel_label: Label = null
var _hov_label: Label = null
var _sel_ship_id: String = ""
var _sel_model: ShipIndicatorModel = null
var _hov_model: ShipIndicatorModel = null
var _sel_label_enabled: bool = true  # false while the status plate on the water shows the same facts
## Returns the screen rect of the map area (clear of the side panel and the log bar); labels are
## kept inside it. Unset: the whole overlay.
var map_rect_provider: Callable = Callable()
const MAP_EDGE_GAP_PX := 6.0

## The label keeps at least this far (screen px) from the ship's centre, so it never covers the
## ship model even when the camera is zoomed far out.
const MIN_CLEARANCE_PX := 64.0
## Label clearance from the bow centre, in screen hex widths: ahead (hover preview) just past the
## hovered hex; astern (selected ship) past the far edge of the stern hex (1.5 hex widths out).
const AHEAD_CLEARANCE_HEXES := 0.55
const ASTERN_CLEARANCE_HEXES := 1.55


func setup(camera: Camera3D) -> void:
	_camera = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_sel_label = _make_label()
	_hov_label = _make_label()
	add_child(_sel_label)
	add_child(_hov_label)

func _make_label() -> Label:
	var l := Label.new()
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = &"MapLabel"  # subtle dark backing so it reads over water
	l.add_theme_color_override("font_color", Color(0.91, 0.93, 0.96))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

func show_selected(model: ShipIndicatorModel, ship_id: String) -> void:
	_sel_model = model
	_sel_ship_id = ship_id
	_update()

func clear_selected() -> void:
	_sel_model = null
	_sel_ship_id = ""
	_sel_label.visible = false


## Show (true) or hide (false) the selected ship's speed / point-of-sail label. Off while the
## status plate on the water is up: it carries the same two facts.
func set_selected_label_enabled(enabled: bool) -> void:
	_sel_label_enabled = enabled
	if not enabled:
		_sel_label.visible = false


func is_selected_label_visible() -> bool:
	return _sel_label != null and _sel_label.visible


func show_hover(model: ShipIndicatorModel) -> void:
	_hov_model = model
	_update()

func clear_hover() -> void:
	_hov_model = null
	_hov_label.visible = false

func _process(_delta: float) -> void:
	if _sel_model != null or _hov_model != null:
		_update()

func _update() -> void:
	_update_label(_sel_model if _sel_label_enabled else null, _sel_label, -1.0)
	_update_label(_hov_model, _hov_label, 1.0)


## Top-left corner for a label of `label_size` placed beside `center_px` along the unit screen
## direction `away`, its nearest edge `clearance` px from the centre. Pure; unit tested.
static func label_position(center_px: Vector2, away: Vector2, clearance: float, label_size: Vector2) -> Vector2:
	var dir := away.normalized() if away.length() > 0.0001 else Vector2.DOWN
	var half_extent := absf(dir.x) * label_size.x * 0.5 + absf(dir.y) * label_size.y * 0.5
	var label_center := center_px + dir * (clearance + half_extent)
	return (label_center - label_size * 0.5).round()


## The label's lines: the ship's name when the model carries one (the hover preview), then speed
## and point of sail.
static func label_text(model: ShipIndicatorModel) -> String:
	var text := "Speed: %d\n%s" % [model.speed, model.point_of_sail]
	return text if model.ship_name == "" else model.ship_name + "\n" + text


## `side` -1 puts the label astern (the selected ship: the offered hexes are all ahead of it),
## +1 ahead (the hover preview: past the hovered hex, away from the ship and its other options).
## `min_clearance` pushes the label further out.
func _update_label(model: ShipIndicatorModel, label: Label, side: float, min_clearance: float = 0.0) -> void:
	if model == null or _camera == null:
		label.visible = false
		return
	if _camera.is_position_behind(model.center_anchor):
		label.visible = false
		return
	label.text = label_text(model)
	label.modulate = Color(1, 1, 1, model.opacity)
	label.reset_size()
	var center_px := _camera.unproject_position(model.center_anchor)
	# One hex-width away from the centre along the heading, in screen space.
	var along := model.center_anchor + model.direction_dir * side * 2.0 * model.center_anchor.distance_to(model.direction_anchor)
	var along_px := _camera.unproject_position(along)
	var clearance := label_clearance(center_px.distance_to(along_px), side, min_clearance)
	label.position = keep_inside(label_position(center_px, along_px - center_px, clearance, label.size),
		label.size, _map_rect(), MAP_EDGE_GAP_PX)
	label.visible = true


## How far (screen px) a label keeps from the bow centre: `hex_px` is one hex width on screen, `side`
## as in _update_label (-1 astern: past the stern hex; +1 ahead), never under MIN_CLEARANCE_PX or
## `min_clearance`. Pure; unit tested.
static func label_clearance(hex_px: float, side: float, min_clearance: float) -> float:
	var hexes := ASTERN_CLEARANCE_HEXES if side < 0.0 else AHEAD_CLEARANCE_HEXES
	return maxf(maxf(hex_px * hexes, MIN_CLEARANCE_PX), min_clearance)


func _map_rect() -> Rect2:
	if map_rect_provider.is_valid():
		return map_rect_provider.call()
	return get_rect()


## Top-left corner that keeps a label of `label_size` at `pos` inside `rect` (inset by `gap`), so
## it is never clipped by or hidden under a panel beside the map.
static func keep_inside(pos: Vector2, label_size: Vector2, rect: Rect2, gap: float) -> Vector2:
	var lo := rect.position + Vector2(gap, gap)
	var hi := rect.end - label_size - Vector2(gap, gap)
	return Vector2(clampf(pos.x, lo.x, maxf(lo.x, hi.x)), clampf(pos.y, lo.y, maxf(lo.y, hi.y)))
