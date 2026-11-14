extends Control
## IndicatorOverlay - 2D label(s) + info-icon button for the selected ship and plotting hover.
## Consumes ShipIndicatorModel DTOs; emits info_toggled. No game-state access. (View layer.)

signal info_toggled(ship_id: String)

var _camera: Camera3D = null
var _sel_label: Label = null
var _hov_label: Label = null
var _info_btn: Button = null
var _sel_ship_id: String = ""
var _sel_model: ShipIndicatorModel = null
var _hov_model: ShipIndicatorModel = null
var _info_enabled: bool = true  # false while a ship is being plotted: nothing clickable over the hexes

## The label keeps at least this far (screen px) from the ship's centre, so it never covers the
## ship model or its info button even when the camera is zoomed far out.
const MIN_CLEARANCE_PX := 64.0

## The info button keeps this share of the ship-to-astern-hex distance (and at least
## INFO_MIN_MARGIN_PX) clear of every hex centre; when it cannot, it is hidden.
const INFO_MARGIN_FRACTION := 0.15
const INFO_MIN_MARGIN_PX := 4.0
const INFO_FONT_SIZE := 12

func setup(camera: Camera3D) -> void:
	_camera = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_sel_label = _make_label()
	_hov_label = _make_label()
	add_child(_sel_label)
	add_child(_hov_label)

	_info_btn = Button.new()
	_info_btn.text = "i"
	_info_btn.tooltip_text = "Ship status"
	_info_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_btn.focus_mode = Control.FOCUS_NONE
	# Small enough to sit on the ship's own hex edge, astern, without reaching a hex centre.
	_info_btn.add_theme_font_size_override("font_size", INFO_FONT_SIZE)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.12, 0.16, 0.22, 0.9) if state != "hover" else Color(0.2, 0.27, 0.36, 0.95)
		box.border_color = Color(0.75, 0.82, 0.9, 0.9)
		box.set_border_width_all(1)
		box.set_corner_radius_all(9)
		box.content_margin_left = 6
		box.content_margin_right = 6
		box.content_margin_top = 1
		box.content_margin_bottom = 1
		_info_btn.add_theme_stylebox_override(state, box)
	_info_btn.visible = false
	_info_btn.pressed.connect(func(): info_toggled.emit(_sel_ship_id))
	add_child(_info_btn)

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
	_info_btn.visible = false

## Hide (false) or allow (true) the info button. Off while plotting: the offered hexes must be
## clickable everywhere, so nothing clickable may sit over the map.
func set_info_enabled(enabled: bool) -> void:
	_info_enabled = enabled
	_update_info_button()


func is_info_button_visible() -> bool:
	return _info_btn != null and _info_btn.visible


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
	_update_info_button()  # first: the selected label is pushed clear of it
	var sel_min := 0.0
	if _info_btn.visible:
		sel_min = clearance_past(_camera.unproject_position(_sel_model.center_anchor),
			Rect2(_info_btn.position, _info_btn.size), 4.0)
	_update_label(_sel_model, _sel_label, -1.0, sel_min)
	_update_label(_hov_model, _hov_label, 1.0)


## Top-left corner for a label of `label_size` placed beside `center_px` along the unit screen
## direction `away`, its nearest edge `clearance` px from the centre. Pure; unit tested.
static func label_position(center_px: Vector2, away: Vector2, clearance: float, label_size: Vector2) -> Vector2:
	var dir := away.normalized() if away.length() > 0.0001 else Vector2.DOWN
	var half_extent := absf(dir.x) * label_size.x * 0.5 + absf(dir.y) * label_size.y * 0.5
	var label_center := center_px + dir * (clearance + half_extent)
	return (label_center - label_size * 0.5).round()


## The smallest label clearance (from `center_px`) that keeps a label placed with label_position
## clear of `rect`: the distance to the rect's farthest corner plus `gap`. Pure; unit tested.
static func clearance_past(center_px: Vector2, rect: Rect2, gap: float) -> float:
	var far := 0.0
	for corner in [rect.position, rect.position + Vector2(rect.size.x, 0),
			rect.position + Vector2(0, rect.size.y), rect.end]:
		far = maxf(far, center_px.distance_to(corner))
	return far + gap


## Where the info button goes, from the projected centres of the ship's hex (`centers[0]`) and its
## six neighbours (`centers[1 + d]` for direction d): centred on the edge between the ship's hex
## and the hex astern (opposite `facing`), at `button_size`. Returns an empty Rect2 (hide it) when
## the button would come within the margin of any of the seven centres, so it can never take a
## click meant for the ship's hex or a hex it can move to, at any heading, zoom or camera turn.
## Pure; unit tested.
static func info_button_rect(centers: Array, facing: int, button_size: Vector2) -> Rect2:
	if centers.size() < 7:
		return Rect2()
	var ship: Vector2 = centers[0]
	var astern: Vector2 = centers[1 + posmod(facing + 3, 6)]
	var margin := maxf(INFO_MIN_MARGIN_PX, ship.distance_to(astern) * INFO_MARGIN_FRACTION)
	var rect := Rect2(((ship + astern) * 0.5 - button_size * 0.5).round(), button_size)
	var guard := rect.grow(margin)
	for c in centers:
		if guard.has_point(c):
			return Rect2()
	return rect


## `side` -1 puts the label astern (the selected ship: the offered hexes are all ahead of it),
## +1 ahead (the hover preview: past the hovered hex, away from the ship and its other options).
## `min_clearance` pushes the label further out (past the info button).
func _update_label(model: ShipIndicatorModel, label: Label, side: float, min_clearance: float = 0.0) -> void:
	if model == null or _camera == null:
		label.visible = false
		return
	if _camera.is_position_behind(model.center_anchor):
		label.visible = false
		return
	label.text = "Speed: %d\n%s" % [model.speed, model.point_of_sail]
	label.modulate = Color(1, 1, 1, model.opacity)
	label.reset_size()
	var center_px := _camera.unproject_position(model.center_anchor)
	# One hex-width away from the centre along the heading, in screen space.
	var along := model.center_anchor + model.direction_dir * side * 2.0 * model.center_anchor.distance_to(model.direction_anchor)
	var along_px := _camera.unproject_position(along)
	var clearance := maxf(maxf(center_px.distance_to(along_px) * 0.55, MIN_CLEARANCE_PX), min_clearance)
	label.position = label_position(center_px, along_px - center_px, clearance, label.size)
	label.visible = true

func _update_info_button() -> void:
	if not _info_enabled or _sel_model == null or _camera == null \
			or _sel_model.neighbor_anchors.size() != 6:
		_info_btn.visible = false
		return
	var world: Array[Vector3] = [_sel_model.center_anchor]
	world.append_array(_sel_model.neighbor_anchors)
	var centers: Array = []
	for p in world:
		if _camera.is_position_behind(p):
			_info_btn.visible = false
			return
		centers.append(_camera.unproject_position(p))
	var rect := info_button_rect(centers, _sel_model.facing, _info_btn.get_combined_minimum_size())
	if rect.size == Vector2.ZERO:
		_info_btn.visible = false
		return
	_info_btn.position = rect.position
	_info_btn.size = rect.size
	_info_btn.visible = true
