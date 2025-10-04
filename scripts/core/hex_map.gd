extends Node3D
## HexMap - Renders the hex grid and manages hex tiles

@export var hex_size: float = 1.0
@export var grid_width: int = 100
@export var grid_height: int = 100
@export var water_texture: Texture2D
@export var show_grid_lines: bool = true
@export var grid_line_color: Color = Color(0.2, 0.3, 0.4, 0.3)

var hex_grid: HexGrid
var hex_meshes: Dictionary = {}  # Map of Vector2i(q,r) -> MeshInstance3D

func _ready() -> void:
	hex_grid = HexGrid.new(hex_size)
	_generate_hex_map()

func _generate_hex_map() -> void:
	"""Generate the visible hex grid"""
	print("Generating hex map: %dx%d" % [grid_width, grid_height])

	# Calculate offset to center the grid
	var offset_q = -grid_width / 2
	var offset_r = -grid_height / 2

	var sample_printed = false
	for q in range(grid_width):
		for r in range(grid_height):
			var hex_coord = Vector2i(q + offset_q, r + offset_r)
			_create_hex_tile(hex_coord)

			# Print first hex for debugging
			if not sample_printed and q == 0 and r == 0:
				var world_pos = hex_grid.axial_to_world(hex_coord.x, hex_coord.y)
				print("First hex at coord %s -> world pos %s" % [hex_coord, world_pos])
				sample_printed = true

	print("Generated %d hex tiles" % hex_meshes.size())

func _create_hex_tile(coord: Vector2i) -> void:
	"""Create a single hex tile at the given axial coordinates"""
	var world_pos = hex_grid.axial_to_world(coord.x, coord.y)

	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.position = world_pos

	# Create hex mesh
	var mesh = _create_hex_mesh()
	mesh_instance.mesh = mesh

	# Create shader material for ocean water
	var shader = load("res://assets/shaders/ocean_water.gdshader")
	var material = ShaderMaterial.new()
	material.shader = shader

	# Load and assign textures
	var normal_a = load("res://assets/textures/water/normal_A.png")
	var normal_b = load("res://assets/textures/water/normal_B.png")
	var foam_tex = load("res://assets/textures/water/foam_albedo.png")
	var uv_tex = load("res://assets/textures/water/uv_example.png")
	var caustic_tex = load("res://assets/textures/water/caustic.png")

	material.set_shader_parameter("normalmap_a", normal_a)
	material.set_shader_parameter("normalmap_b", normal_b)
	material.set_shader_parameter("edge_foam_texture", foam_tex)
	material.set_shader_parameter("foam_texture", foam_tex)
	material.set_shader_parameter("uv_sampler", uv_tex)

	# Create Texture2DArray for caustics (using single texture for all layers)
	var caustic_array = Texture2DArray.new()
	# For now, just use the single caustic texture - ideally would have 16 frames
	material.set_shader_parameter("caustic_sampler", caustic_tex)

	# Configure hex grid lines
	material.set_shader_parameter("show_hex_grid", show_grid_lines)
	material.set_shader_parameter("hex_size", hex_size)
	material.set_shader_parameter("hex_grid_color", Vector3(1.0, 1.0, 1.0))
	material.set_shader_parameter("hex_grid_width", 0.03)

	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

	hex_meshes[coord] = mesh_instance

func _create_hex_mesh() -> ArrayMesh:
	"""Create a hexagon mesh (flat with pointy-top orientation)"""
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()

	# Center vertex
	vertices.append(Vector3.ZERO)
	uvs.append(Vector2(0.5, 0.5))
	normals.append(Vector3.UP)

	# Create 6 vertices around the hex
	for i in range(7):  # 7 to close the loop
		var angle_deg = 60.0 * i - 30.0  # Offset by 30 for pointy-top
		var angle_rad = deg_to_rad(angle_deg)
		var x = hex_size * cos(angle_rad)
		var z = hex_size * sin(angle_rad)

		vertices.append(Vector3(x, 0, z))
		normals.append(Vector3.UP)

		# UV mapping
		var u = 0.5 + 0.5 * cos(angle_rad)
		var v = 0.5 + 0.5 * sin(angle_rad)
		uvs.append(Vector2(u, v))

	# Create triangles
	for i in range(6):
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)

	# Build the mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh

func world_to_hex(world_pos: Vector3) -> Vector2i:
	"""Convert world position to hex coordinates"""
	return hex_grid.world_to_axial(world_pos)

func hex_to_world(coord: Vector2i) -> Vector3:
	"""Convert hex coordinates to world position"""
	return hex_grid.axial_to_world(coord.x, coord.y)

func highlight_hex(coord: Vector2i, color: Color = Color.YELLOW) -> void:
	"""Highlight a specific hex tile"""
	if hex_meshes.has(coord):
		var mesh_instance = hex_meshes[coord]
		var material = mesh_instance.material_override as StandardMaterial3D
		if material:
			material.albedo_color = color

func clear_highlight(coord: Vector2i) -> void:
	"""Remove highlight from a hex tile"""
	if hex_meshes.has(coord):
		var mesh_instance = hex_meshes[coord]
		var material = mesh_instance.material_override as StandardMaterial3D
		if material:
			material.albedo_color = Color(0.1, 0.3, 0.5)

func set_water_texture(texture: Texture2D) -> void:
	"""Update the water texture for all hex tiles"""
	water_texture = texture
	for mesh_instance in hex_meshes.values():
		var material = mesh_instance.material_override as StandardMaterial3D
		if material:
			material.albedo_texture = texture

func get_hex_grid() -> HexGrid:
	return hex_grid
