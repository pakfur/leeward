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
const COLOR_BLOCKED = Color(0.8, 0.2, 0.2, 0.35)    # Red, semi-transparent
const COLOR_TARGET = Color(1.0, 0.9, 0.2, 0.5)      # Yellow, chosen fire targets
const COLOR_COLLISION = Color(1.0, 0.5, 0.0, 0.6)   # Orange, an offered hex that holds another ship

# Child nodes for each layer
var valid_hexes_node: Node3D = null
var plotted_path_node: Node3D = null
var submitted_paths_node: Node3D = null
var blocked_hexes_node: Node3D = null
var arcs_node: Node3D = null
var targets_node: Node3D = null

## Grid used to place arc hexes; set by the owner (show_arc takes only hexes and a colour).
var arc_grid: HexGrid = null

# Track current valid hex positions for click detection
var _valid_hex_positions: Array[Vector2i] = []

# Materials (shared across meshes in each layer)
var _valid_material: StandardMaterial3D = null
var _plotted_material: StandardMaterial3D = null
var _submitted_material: StandardMaterial3D = null
var _blocked_material: StandardMaterial3D = null
var _arc_materials: Dictionary = {}  # Color -> StandardMaterial3D
var _target_material: StandardMaterial3D = null
var _collision_material: StandardMaterial3D = null


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

	blocked_hexes_node = Node3D.new()
	blocked_hexes_node.name = "BlockedHexes"
	add_child(blocked_hexes_node)

	arcs_node = Node3D.new()
	arcs_node.name = "Arcs"
	add_child(arcs_node)

	targets_node = Node3D.new()
	targets_node.name = "TargetHighlights"
	add_child(targets_node)

	_valid_material = _create_material(COLOR_VALID)
	_plotted_material = _create_material(COLOR_PLOTTED)
	_submitted_material = _create_material(COLOR_SUBMITTED)
	_blocked_material = _create_material(COLOR_BLOCKED)
	_target_material = _create_material(COLOR_TARGET)
	_target_material.render_priority = 2
	_collision_material = _create_material(COLOR_COLLISION)


## Offered moves in green; any listed in `collision_hexes` (they hold another ship) in orange.
func show_valid_hexes(hexes: Array, hex_grid: HexGrid, collision_hexes: Array = []) -> void:
	clear_valid_hexes()
	_valid_hex_positions.clear()

	for valid_move in hexes:
		var hex_pos: Vector2i = valid_move.hex
		_valid_hex_positions.append(hex_pos)
		var world_pos = hex_grid.axial_to_world(hex_pos.x, hex_pos.y)
		var material := _collision_material if collision_hexes.has(hex_pos) else _valid_material
		_add_hex_mesh(valid_hexes_node, world_pos, hex_grid.hex_size, material)


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


func show_blocked_hexes(hex_positions: Array[Vector2i], hex_grid: HexGrid) -> void:
	clear_blocked_hexes()
	for hex_pos in hex_positions:
		var world_pos = hex_grid.axial_to_world(hex_pos.x, hex_pos.y)
		_add_hex_mesh(blocked_hexes_node, world_pos, hex_grid.hex_size, _blocked_material)


## Draw one broadside's fire arc in that side's colour (BroadsideColors): a faint fill and an
## opaque rim, so the arc reads as the same colour as the fire panel's swatch on any water.
## Arcs accumulate until clear_arcs().
func show_arc(hexes: Array[Vector2i], side: int) -> void:
	if arc_grid == null or arcs_node == null:
		return
	var fill_mat := _arc_material(BroadsideColors.fill(side))
	var rim_mat := _arc_material(BroadsideColors.color(side))
	for hex_pos in hexes:
		var world_pos = arc_grid.axial_to_world(hex_pos.x, hex_pos.y)
		_add_hex_mesh(arcs_node, world_pos, arc_grid.hex_size, fill_mat)
		var rim := MeshInstance3D.new()
		rim.name = "ArcRim"
		rim.mesh = _create_hex_ring_mesh(arc_grid.hex_size * HEX_INSET, arc_grid.hex_size * HEX_INSET * 0.86)
		rim.material_override = rim_mat
		rim.position = Vector3(world_pos.x, OVERLAY_Y, world_pos.z)
		arcs_node.add_child(rim)


func _arc_material(color: Color) -> StandardMaterial3D:
	if not _arc_materials.has(color):
		_arc_materials[color] = _create_material(color)
	return _arc_materials[color]


## A flat hexagonal band between two radii (pointy-top), for arc rims.
func _create_hex_ring_mesh(outer: float, inner: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)
		vertices.append(Vector3(cos(angle) * outer, 0, sin(angle) * outer))
		vertices.append(Vector3(cos(angle) * inner, 0, sin(angle) * inner))
	for i in range(6):
		var o0 := i * 2
		var i0 := o0 + 1
		var o1 := ((i + 1) % 6) * 2
		var i1 := o1 + 1
		indices.append_array([o0, o1, i0, i0, o1, i1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Highlight the hexes of the currently chosen fire targets.
func show_target_highlights(hexes: Array[Vector2i]) -> void:
	_clear_children(targets_node)
	if arc_grid == null or targets_node == null:
		return
	for hex_pos in hexes:
		var world_pos = arc_grid.axial_to_world(hex_pos.x, hex_pos.y)
		_add_hex_mesh(targets_node, world_pos, arc_grid.hex_size, _target_material)


func clear_arcs() -> void:
	_clear_children(arcs_node)
	_clear_children(targets_node)


func clear_valid_hexes() -> void:
	_clear_children(valid_hexes_node)
	_valid_hex_positions.clear()


func clear_plotted_path() -> void:
	_clear_children(plotted_path_node)


func clear_blocked_hexes() -> void:
	_clear_children(blocked_hexes_node)


func clear_submitted_path(ship_id: String) -> void:
	if not submitted_paths_node:
		return
	var node = submitted_paths_node.get_node_or_null("Submitted_" + ship_id)
	if node:
		node.queue_free()


func clear_all() -> void:
	clear_valid_hexes()
	clear_plotted_path()
	clear_blocked_hexes()
	# Don't clear submitted paths - they persist


func clear_everything() -> void:
	clear_valid_hexes()
	clear_plotted_path()
	clear_blocked_hexes()
	clear_arcs()
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
		indices.append(1 if i == 5 else i + 2)  # Next vertex (wrap around)

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
