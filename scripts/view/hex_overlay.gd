extends Node3D
## HexOverlay - Renders hex overlays on the 3D board for movement plotting
##
## Manages three visual layers:
## - Valid moves: semi-transparent green hexes the player can click
## - Plotted path: semi-transparent blue hexes showing the planned route
## - Submitted paths: dimmed gray hexes for finalized movement plans

const OVERLAY_Y = 0.1  # Slightly above water surface
const HEX_INSET = 0.9  # Fraction of hex_size for slight inset from edges

# Overlay colors
const COLOR_VALID = Color(0.2, 0.8, 0.2, 0.35)     # Green, semi-transparent
const COLOR_PLOTTED = Color(0.2, 0.4, 0.9, 0.45)    # Blue, semi-transparent
const COLOR_SUBMITTED = Color(0.5, 0.5, 0.5, 0.25)  # Gray, dimmed

# Child nodes for each layer
var valid_hexes_node: Node3D = null
var plotted_path_node: Node3D = null
var submitted_paths_node: Node3D = null

# Track current valid hex positions for click detection
var _valid_hex_positions: Array[Vector2i] = []

# Materials (shared across meshes in each layer)
var _valid_material: StandardMaterial3D = null
var _plotted_material: StandardMaterial3D = null
var _submitted_material: StandardMaterial3D = null


func _ready() -> void:
	valid_hexes_node = Node3D.new()
	valid_hexes_node.name = "ValidHexes"
	add_child(valid_hexes_node)

	plotted_path_node = Node3D.new()
	plotted_path_node.name = "PlottedPath"
	add_child(plotted_path_node)

	submitted_paths_node = Node3D.new()
	submitted_paths_node.name = "SubmittedPaths"
	add_child(submitted_paths_node)

	_valid_material = _create_material(COLOR_VALID)
	_plotted_material = _create_material(COLOR_PLOTTED)
	_submitted_material = _create_material(COLOR_SUBMITTED)


func show_valid_hexes(hexes: Array, hex_grid: HexGrid) -> void:
	clear_valid_hexes()
	_valid_hex_positions.clear()

	for valid_move in hexes:
		var hex_pos: Vector2i = valid_move.hex
		_valid_hex_positions.append(hex_pos)
		var world_pos = hex_grid.axial_to_world(hex_pos.x, hex_pos.y)
		_add_hex_mesh(valid_hexes_node, world_pos, hex_grid.hex_size, _valid_material)


func show_plotted_path(steps: Array, hex_grid: HexGrid) -> void:
	clear_plotted_path()

	for step in steps:
		var world_pos = hex_grid.axial_to_world(step.hex.x, step.hex.y)
		_add_hex_mesh(plotted_path_node, world_pos, hex_grid.hex_size, _plotted_material)


func show_submitted_path(ship_id: String, steps: Array, hex_grid: HexGrid) -> void:
	clear_submitted_path(ship_id)

	var container = Node3D.new()
	container.name = "Submitted_" + ship_id
	submitted_paths_node.add_child(container)

	for step in steps:
		var world_pos = hex_grid.axial_to_world(step.hex.x, step.hex.y)
		_add_hex_mesh(container, world_pos, hex_grid.hex_size, _submitted_material)


func clear_valid_hexes() -> void:
	_clear_children(valid_hexes_node)
	_valid_hex_positions.clear()


func clear_plotted_path() -> void:
	_clear_children(plotted_path_node)


func clear_submitted_path(ship_id: String) -> void:
	if not submitted_paths_node:
		return
	var node = submitted_paths_node.get_node_or_null("Submitted_" + ship_id)
	if node:
		node.queue_free()


func clear_all() -> void:
	clear_valid_hexes()
	clear_plotted_path()
	# Don't clear submitted paths - they persist


func clear_everything() -> void:
	clear_valid_hexes()
	clear_plotted_path()
	_clear_children(submitted_paths_node)


func get_valid_hex_at_world_pos(world_pos: Vector3, hex_grid: HexGrid) -> Vector2i:
	var hex = hex_grid.world_to_axial(world_pos)
	if hex in _valid_hex_positions:
		return hex
	return Vector2i(-99, -99)


func _add_hex_mesh(parent: Node3D, world_pos: Vector3, hex_size: float, material: StandardMaterial3D) -> void:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = _create_hex_mesh(hex_size * HEX_INSET)
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(world_pos.x, OVERLAY_Y, world_pos.z)
	parent.add_child(mesh_instance)


func _create_hex_mesh(radius: float) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()

	# Center vertex
	vertices.append(Vector3.ZERO)

	# 6 outer vertices (pointy-top hex)
	for i in range(6):
		var angle = deg_to_rad(60.0 * i - 30.0)  # Pointy-top: start at -30 degrees
		vertices.append(Vector3(cos(angle) * radius, 0, sin(angle) * radius))

	# 6 triangles from center to each edge
	for i in range(6):
		indices.append(0)           # Center
		indices.append(i + 1)       # Current vertex
		indices.append((i % 6) + 1 if i == 5 else i + 2)  # Next vertex (wrap around)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _create_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 1
	return mat


func _clear_children(node: Node3D) -> void:
	if not node:
		return
	for child in node.get_children():
		child.queue_free()
