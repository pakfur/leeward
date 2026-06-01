extends Node3D
## ShipIndicators - Flat-on-water 3D arrow renderer for the selected ship and the
## plotting-hover preview. Consumes a ShipIndicatorModel DTO only; no game state. (View layer.)

const Model = preload("res://scripts/view/ship_indicator_model.gd")

const ARROW_Y := 0.12                              # just above the hex overlay (0.1)
const WIND_COLOR := Color(0.27, 0.78, 1.0)         # cyan
const DIR_COLOR := Color(1.0, 0.80, 0.27)          # amber

# Zoom-scaling (tunable in-engine)
@export var scale_factor: float = 0.045
@export var min_world: float = 0.6
@export var max_world: float = 2.2

var _camera: Camera3D = null
var _arrows: Dictionary = {}            # role:String -> MeshInstance3D
var _selected_model: ShipIndicatorModel = null
var _hover_model: ShipIndicatorModel = null

func setup(camera: Camera3D) -> void:
	_camera = camera
	for role in ["sel_wind", "sel_dir", "hov_wind", "hov_dir"]:
		var mi := MeshInstance3D.new()
		mi.name = role
		mi.mesh = _build_unit_arrow_mesh()
		mi.material_override = _make_material()
		mi.visible = false
		add_child(mi)
		_arrows[role] = mi

func show_selected(model: ShipIndicatorModel) -> void:
	_selected_model = model
	_refresh()

func clear_selected() -> void:
	_selected_model = null
	_refresh()

func show_hover(model: ShipIndicatorModel) -> void:
	_hover_model = model
	_refresh()

func clear_hover() -> void:
	_hover_model = null
	_refresh()

func _process(_delta: float) -> void:
	if _selected_model != null or _hover_model != null:
		_refresh()

func _refresh() -> void:
	_apply(_selected_model, "sel_wind", "sel_dir")
	_apply(_hover_model, "hov_wind", "hov_dir")

func _apply(model: ShipIndicatorModel, wind_role: String, dir_role: String) -> void:
	var wind_mi: MeshInstance3D = _arrows[wind_role]
	var dir_mi: MeshInstance3D = _arrows[dir_role]
	if model == null:
		wind_mi.visible = false
		dir_mi.visible = false
		return
	var s := _scale_for(model.center_anchor)
	# Direction arrow: tail at face, head outward (+dir)
	dir_mi.visible = _place_arrow(dir_mi, model.direction_anchor, model.direction_anchor + model.direction_dir * s, s, DIR_COLOR, model.opacity)
	# Windward arrow: head at face (inward), tail outward
	if model.windward_visible:
		wind_mi.visible = _place_arrow(wind_mi, model.windward_anchor + model.windward_dir * s, model.windward_anchor, s, WIND_COLOR, model.opacity)
	else:
		wind_mi.visible = false

func _scale_for(anchor: Vector3) -> float:
	var dist := 20.0
	if _camera:
		dist = _camera.global_position.distance_to(anchor)
	return Model.clamp_scale(dist, scale_factor, min_world, max_world)

func _place_arrow(mi: MeshInstance3D, tail: Vector3, head: Vector3, width_scale: float, color: Color, opacity: float) -> bool:
	var d := head - tail
	d.y = 0.0
	var length := d.length()
	if length < 0.0001:
		return false
	var dir := d / length
	mi.position = Vector3(tail.x, ARROW_Y, tail.z)
	mi.rotation = Vector3(0, atan2(-dir.z, dir.x), 0)
	mi.scale = Vector3(length, 1.0, width_scale)
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(color.r, color.g, color.b, opacity)
	return true

func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	return mat

func _build_unit_arrow_mesh() -> ArrayMesh:
	# Arrow pointing +X, length 1: shaft x in [0,0.7] half-width 0.09, head x in [0.7,1.0] half-width 0.20
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var hw := 0.09
	var hh := 0.20
	v.append(Vector3(0, 0, -hw)); v.append(Vector3(0.7, 0, -hw))
	v.append(Vector3(0.7, 0, hw)); v.append(Vector3(0, 0, hw))
	idx.append_array([0, 1, 2, 0, 2, 3])
	var base := v.size()
	v.append(Vector3(0.7, 0, -hh)); v.append(Vector3(1.0, 0, 0)); v.append(Vector3(0.7, 0, hh))
	idx.append_array([base, base + 1, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
