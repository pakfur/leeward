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
	_info_btn.custom_minimum_size = Vector2(28, 28)
	_info_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_btn.visible = false
	_info_btn.pressed.connect(func(): info_toggled.emit(_sel_ship_id))
	add_child(_info_btn)

func _make_label() -> Label:
	var l := Label.new()
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_update_label(_sel_model, _sel_label)
	_update_label(_hov_model, _hov_label)
	_update_info_button()

func _update_label(model: ShipIndicatorModel, label: Label) -> void:
	if model == null or _camera == null:
		label.visible = false
		return
	var anchor := model.label_anchor + model.direction_dir * 0.6
	if _camera.is_position_behind(anchor):
		label.visible = false
		return
	label.text = "Speed: %d\n%s" % [model.speed, model.point_of_sail]
	label.modulate = Color(1, 1, 1, model.opacity)
	label.reset_size()
	label.position = _camera.unproject_position(anchor) + Vector2(10, -10)
	label.visible = true

func _update_info_button() -> void:
	if _sel_model == null or _camera == null or _camera.is_position_behind(_sel_model.center_anchor):
		_info_btn.visible = false
		return
	_info_btn.position = _camera.unproject_position(_sel_model.center_anchor) + Vector2(14, 14)
	_info_btn.visible = true
