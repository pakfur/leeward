extends Node3D
## HexMap - Renders the hex grid and manages hex tiles

@export var hex_size: float = 1.0
@export var grid_width: int = 100
@export var grid_height: int = 100
@export var water_texture: Texture2D
@export var show_grid_lines: bool = true
@export var grid_line_color: Color = Color(0.2, 0.3, 0.4, 0.3)

var hex_grid: HexGrid
var hex_meshes: Dictionary = {}  # Map of Vector2i(q,r) -> MeshInstance3D (not rendered, just for tracking)
var ocean_material: ShaderMaterial  # Shared material for all hexes
var grid_overlay: MeshInstance3D  # Static grid overlay above water
var water_plane: MeshInstance3D  # Single plane for seamless water

func _ready() -> void:
	hex_grid = HexGrid.new(hex_size)
	_create_ocean_material()
	_create_water_plane()
	_initialize_hex_tracking()
	# Grid overlay disabled for now - may add back later for planning/combat phases
	#if show_grid_lines:
	#	_create_grid_overlay()

func _create_ocean_material() -> void:
	"""Load and configure the ocean shader material"""
	# Load the material resource (already has shader assigned in editor)
	ocean_material = load("res://assets/materials/ocean_water.tres")

	# If material doesn't exist yet, create it
	if ocean_material == null:
		ocean_material = ShaderMaterial.new()
		var shader = load("res://assets/shaders/ocean_water.gdshader")
		ocean_material.shader = shader

	# Load textures
	var normal_a = load("res://assets/textures/water/normal_A.png")
	var normal_b = load("res://assets/textures/water/normal_B.png")
	var foam_tex = load("res://assets/textures/water/foam_albedo.png")
	var uv_tex = load("res://assets/textures/water/uv_example.png")
	var caustic_tex = load("res://assets/textures/water/caustic.png")

	# Configure normal maps and textures
	ocean_material.set_shader_parameter("normalmap_a", normal_a)
	ocean_material.set_shader_parameter("normalmap_b", normal_b)
	ocean_material.set_shader_parameter("edge_foam_texture", foam_tex)
	ocean_material.set_shader_parameter("foam_texture", foam_tex)
	ocean_material.set_shader_parameter("uv_sampler", uv_tex)

	# Create Texture2DArray for caustics from the single caustic texture
	var caustic_image = caustic_tex.get_image()
	var tex_array = Texture2DArray.new()

	# Create array with 16 layers (all using the same caustic texture)
	var images: Array[Image] = []
	for i in range(16):
		images.append(caustic_image)

	tex_array.create_from_images(images)
	ocean_material.set_shader_parameter("caustic_sampler", tex_array)

	# Disable hex grid in shader (we'll use a separate overlay instead)
	ocean_material.set_shader_parameter("show_hex_grid", false)

	print("Ocean material loaded and configured")

func _create_water_plane() -> void:
	"""Create a single large plane for seamless water rendering"""
	# Check if water_plane already exists as a child node (added in editor)
	water_plane = get_node_or_null("WaterPlane")

	if water_plane == null:
		# Create it at runtime if not found
		water_plane = MeshInstance3D.new()
		water_plane.name = "WaterPlane"
		add_child(water_plane)

	# Calculate the size of the water plane to cover all hexes on XZ plane
	var map_width_x = grid_width * hex_size * 1.732  # SQRT(3) approximation for X axis
	var map_depth_z = grid_height * hex_size * 1.5  # For Z axis

	# Create a subdivided plane mesh for better wave detail
	# PlaneMesh size.x maps to X axis, size.y maps to Z axis when oriented horizontally
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(map_width_x, map_depth_z)
	plane_mesh.subdivide_width = 128
	plane_mesh.subdivide_depth = 128
	plane_mesh.orientation = PlaneMesh.FACE_Y  # Face up on XZ plane (Y = up)

	water_plane.mesh = plane_mesh
	water_plane.material_override = ocean_material
	water_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	print("Water plane created on XZ plane: X=%.1f Z=%.1f with %d subdivisions" % [map_width_x, map_depth_z, 128])

func _initialize_hex_tracking() -> void:
	"""Initialize hex coordinate tracking (no visible meshes)"""
	print("Initializing hex tracking: %dx%d" % [grid_width, grid_height])

	# Calculate offset to center the grid
	var offset_q = -grid_width / 2
	var offset_r = -grid_height / 2

	var sample_printed = false
	for q in range(grid_width):
		for r in range(grid_height):
			var hex_coord = Vector2i(q + offset_q, r + offset_r)
			# Store hex coordinate for tracking (no mesh creation)
			hex_meshes[hex_coord] = null

			# Print first hex for debugging
			if not sample_printed and q == 0 and r == 0:
				var world_pos = hex_grid.axial_to_world(hex_coord.x, hex_coord.y)
				print("First hex at coord %s -> world pos %s" % [hex_coord, world_pos])
				sample_printed = true

	print("Initialized tracking for %d hex coordinates" % hex_meshes.size())

func _create_hex_tile(coord: Vector2i) -> void:
	"""Create a single hex tile at the given axial coordinates"""
	var world_pos = hex_grid.axial_to_world(coord.x, coord.y)

	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.position = world_pos

	# Create hex mesh
	var mesh = _create_hex_mesh()
	mesh_instance.mesh = mesh

	# Use the shared ocean material
	mesh_instance.material_override = ocean_material
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

func _create_grid_overlay() -> void:
	"""Create a static grid overlay that sits above the water"""
	grid_overlay = MeshInstance3D.new()

	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var colors = PackedColorArray()

	var overlay_y = 0.05  # Slightly above water surface
	var line_width = 0.04  # Width of grid lines
	var offset_q = -grid_width / 2
	var offset_r = -grid_height / 2

	var vertex_index = 0

	# Create line segments for each hex edge
	for q in range(grid_width):
		for r in range(grid_height):
			var hex_coord = Vector2i(q + offset_q, r + offset_r)
			var center = hex_grid.axial_to_world(hex_coord.x, hex_coord.y)
			center.y = overlay_y

			# Create 6 edges of the hex
			for i in range(6):
				var angle1 = deg_to_rad(60.0 * i - 30.0)
				var angle2 = deg_to_rad(60.0 * (i + 1) - 30.0)

				var p1 = center + Vector3(hex_size * cos(angle1), 0, hex_size * sin(angle1))
				var p2 = center + Vector3(hex_size * cos(angle2), 0, hex_size * sin(angle2))

				# Create a quad for the line segment
				var dir = (p2 - p1).normalized()
				var perp = Vector3(-dir.z, 0, dir.x) * line_width * 0.5

				# Four corners of the line quad
				vertices.append(p1 - perp)
				vertices.append(p1 + perp)
				vertices.append(p2 + perp)
				vertices.append(p2 - perp)

				# White color for grid lines
				for j in range(4):
					colors.append(Color.WHITE)

				# Two triangles for the quad
				indices.append(vertex_index + 0)
				indices.append(vertex_index + 1)
				indices.append(vertex_index + 2)

				indices.append(vertex_index + 0)
				indices.append(vertex_index + 2)
				indices.append(vertex_index + 3)

				vertex_index += 4

	# Build the mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	grid_overlay.mesh = mesh

	# Create an unshaded material for the grid
	var grid_material = StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.vertex_color_use_as_albedo = true
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.albedo_color = Color(1, 1, 1, 0.6)  # Semi-transparent white
	grid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	grid_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	grid_material.no_depth_test = true

	grid_overlay.material_override = grid_material
	grid_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid_overlay)

	print("Grid overlay created with %d vertices" % vertices.size())

func world_to_hex(world_pos: Vector3) -> Vector2i:
	"""Convert world position to hex coordinates"""
	return hex_grid.world_to_axial(world_pos)

func hex_to_world(coord: Vector2i) -> Vector3:
	"""Convert hex coordinates to world position"""
	return hex_grid.axial_to_world(coord.x, coord.y)

func highlight_hex(coord: Vector2i, color: Color = Color.YELLOW) -> void:
	"""Highlight a specific hex tile (no-op for now - could add overlay marker later)"""
	# TODO: Could create a temporary marker mesh at this hex position
	pass

func clear_highlight(coord: Vector2i) -> void:
	"""Remove highlight from a hex tile (no-op for now)"""
	# TODO: Could remove marker mesh
	pass

func set_water_texture(texture: Texture2D) -> void:
	"""Update the water texture (no-op now that we use a single plane)"""
	water_texture = texture
	# Water texture is now handled by the shader material

func get_hex_grid() -> HexGrid:
	return hex_grid

func show_grid_overlay() -> void:
	"""Show the hex grid overlay (for planning/combat phases)"""
	if grid_overlay == null:
		_create_grid_overlay()
	else:
		grid_overlay.visible = true

func hide_grid_overlay() -> void:
	"""Hide the hex grid overlay"""
	if grid_overlay:
		grid_overlay.visible = false

func set_hex_grid_visible(visible: bool) -> void:
	"""Set hex grid visibility (shader-based grid that responds to waves)"""
	# Only use shader hex grid, not the mesh overlay
	# The shader grid is part of the water and responds to waves
	if ocean_material:
		ocean_material.set_shader_parameter("show_hex_grid", visible)
		print("Hex grid (shader) visibility set to: %s" % visible)
