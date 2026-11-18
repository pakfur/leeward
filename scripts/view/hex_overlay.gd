extends Node3D
## HexOverlay - Renders hex overlays on the 3D board
##
## Layers:
## - Courses: one per own ship (show_course): its plotted hexes in blue, the hexes it may extend to
##   in green (orange where another ship is in the way); the selected ship at full strength
## - Blocked hexes: red, the moves the selected ship cannot make from its course end
## - Fire arcs and target outlines (fire declaration)
## - Terrain (show_terrain): land and shallow tints, a depth label per shallow area, and strips along
##   the escape (green) and none (red) boundaries

const OVERLAY_Y = 0.1  # Slightly above water surface
const HEX_INSET = 0.9  # Fraction of hex_size for slight inset from edges

# Overlay colors
const COLOR_VALID = Color(0.2, 0.8, 0.2, 0.35)     # Green, semi-transparent
const COLOR_PLOTTED = Color(0.2, 0.4, 0.9, 0.45)    # Blue, semi-transparent
const COLOR_BLOCKED = Color(0.8, 0.2, 0.2, 0.35)    # Red, semi-transparent
const COLOR_TARGET = Color(1.0, 0.95, 0.25, 1.0)    # Bright yellow outline, chosen fire targets
## Target outline band (fractions of hex_size, measured to the corners): on the hex's own edge,
## outside the arc rim and clear of the middle, where the ship, its owner ring and pennant stay seen.
const TARGET_RING_OUTER = 1.04
const TARGET_RING_INNER = 0.92
const ARC_RENDER_PRIORITY = 1  # above the transparent ocean (priority 0)
const TARGET_RENDER_PRIORITY = 2
const COLOR_COLLISION = Color(1.0, 0.5, 0.0, 0.6)   # Orange, an offered hex that holds another ship
const COLOR_LAND = Color(0.76, 0.66, 0.45, 0.85)    # Sand
const COLOR_SHALLOW = Color(0.55, 0.80, 0.70, 0.55)  # Pale green
const COLOR_EDGE_ESCAPE = Color(0.2, 0.85, 0.35, 0.9)  # Green: ships may leave here and escape
const COLOR_EDGE_NONE = Color(0.9, 0.2, 0.2, 0.9)      # Red: no sea room, a ship leaving is lost
const TERRAIN_Y = 0.06  # under the course and arc layers
const EDGE_STRIP_WIDTH = 0.14  # fraction of hex_size
const DEPTH_LABEL_COLOR = Color(0.92, 0.97, 0.95, 1.0)

# Child nodes for each layer
var blocked_hexes_node: Node3D = null
var courses_node: Node3D = null
var arcs_node: Node3D = null
var targets_node: Node3D = null
var terrain_node: Node3D = null

## Grid used to place arc hexes; set by the owner (show_arc takes only hexes and a colour).
var arc_grid: HexGrid = null

# Materials (shared across meshes in each layer)
var _valid_material: StandardMaterial3D = null
var _plotted_material: StandardMaterial3D = null
var _blocked_material: StandardMaterial3D = null
var _arc_materials: Dictionary = {}  # Color -> StandardMaterial3D
var _terrain_materials: Dictionary = {}  # Color -> StandardMaterial3D
var _target_material: StandardMaterial3D = null
var _collision_material: StandardMaterial3D = null
# Course layers of ships other than the selected one: the same colours at about half alpha.
var _valid_material_dim: StandardMaterial3D = null
var _plotted_material_dim: StandardMaterial3D = null
var _collision_material_dim: StandardMaterial3D = null


func _ready() -> void:
	_ensure_terrain_node()

	courses_node = Node3D.new()
	courses_node.name = "Courses"
	add_child(courses_node)

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
	_blocked_material = _create_material(COLOR_BLOCKED)
	_target_material = _create_material(COLOR_TARGET)
	# Draw order: ocean (0) < arcs and plotting hexes (1) < target outline (2) < owner rings (3, ShipView).
	_target_material.render_priority = TARGET_RENDER_PRIORITY
	_collision_material = _create_material(COLOR_COLLISION)
	_valid_material_dim = _create_material(_half_alpha(COLOR_VALID))
	_plotted_material_dim = _create_material(_half_alpha(COLOR_PLOTTED))
	_collision_material_dim = _create_material(_half_alpha(COLOR_COLLISION))


func _ensure_terrain_node() -> void:
	if terrain_node == null:
		terrain_node = Node3D.new()
		terrain_node.name = "Terrain"
		add_child(terrain_node)


## The scenario's terrain (map and scenario spec §15): each land hex tinted sand (`Land_<q>_<r>`),
## each shallow hex pale green (`Shallow_<q>_<r>`), one depth label per shallow area on its hex
## nearest the area's centre (`DepthLabel_<area>`, "A 16–21 ft"), and a strip along every side of
## an escape (green) or none (red) boundary (`Edge_<boundary>_<i>`). Replaces any earlier terrain.
func show_terrain(terrain: TerrainMap, hex_grid: HexGrid) -> void:
	clear_terrain()
	if terrain == null or hex_grid == null:
		return
	_ensure_terrain_node()
	var land_mat := _terrain_material(COLOR_LAND)
	var shallow_mat := _terrain_material(COLOR_SHALLOW)
	for hex: Vector2i in terrain.land:
		_add_terrain_hex("Land_%d_%d" % [hex.x, hex.y], hex, hex_grid, land_mat)
	for area in terrain.areas:
		for hex in area.hexes:
			_add_terrain_hex("Shallow_%d_%d" % [hex.x, hex.y], hex, hex_grid, shallow_mat)
		if not area.hexes.is_empty():
			_add_depth_label(area, hex_grid)
	for b in terrain.boundaries:
		if b.kind == TerrainMap.ESCAPE:
			_add_edge_strips(b, hex_grid, _terrain_material(COLOR_EDGE_ESCAPE))
		elif b.kind == TerrainMap.NONE:
			_add_edge_strips(b, hex_grid, _terrain_material(COLOR_EDGE_NONE))


func clear_terrain() -> void:
	if terrain_node == null:
		return
	for child in terrain_node.get_children():
		terrain_node.remove_child(child)
		child.queue_free()


## The depth label text of a shallow area: "<name> <base+1>–<base+6> ft".
static func depth_label_text(area: TerrainMap.ShallowArea) -> String:
	return "%s %d–%d ft" % [area.name, area.base + 1, area.base + TerrainMap.DEPTH_DIE]


## The hex of `hexes` nearest their centroid (in world space); the first listed wins a tie.
static func central_hex(hexes: Array[Vector2i], hex_grid: HexGrid) -> Vector2i:
	var sum := Vector3.ZERO
	for h in hexes:
		sum += hex_grid.axial_to_world(h.x, h.y)
	var centre := sum / float(hexes.size())
	var best: Vector2i = hexes[0]
	var best_d := INF
	for h in hexes:
		var d := hex_grid.axial_to_world(h.x, h.y).distance_squared_to(centre)
		if d < best_d - 0.0001:
			best_d = d
			best = h
	return best


func _terrain_material(color: Color) -> StandardMaterial3D:
	if not _terrain_materials.has(color):
		var mat := _create_material(color)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # strips are drawn whichever way they wind
		_terrain_materials[color] = mat
	return _terrain_materials[color]


func _add_terrain_hex(node_name: String, hex: Vector2i, hex_grid: HexGrid, material: StandardMaterial3D) -> void:
	var w := hex_grid.axial_to_world(hex.x, hex.y)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = _create_hex_mesh(hex_grid.hex_size)  # full hex: neighbouring tints join up
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(w.x, TERRAIN_Y, w.z)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_node.add_child(mesh_instance)


func _add_depth_label(area: TerrainMap.ShallowArea, hex_grid: HexGrid) -> void:
	var hex := central_hex(area.hexes, hex_grid)
	var w := hex_grid.axial_to_world(hex.x, hex.y)
	var label := Label3D.new()
	label.name = "DepthLabel_" + area.name
	label.text = depth_label_text(area)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 20
	label.outline_size = 8
	label.modulate = DEPTH_LABEL_COLOR
	label.outline_modulate = Color(0.05, 0.15, 0.2, 0.9)
	label.render_priority = ARC_RENDER_PRIORITY
	label.position = Vector3(w.x, TERRAIN_Y + 0.1, w.z)
	terrain_node.add_child(label)


## One flat strip along each hex side of the boundary, centred on the side.
func _add_edge_strips(b: TerrainMap.Boundary, hex_grid: HexGrid, material: StandardMaterial3D) -> void:
	var i := 0
	for key: Vector4i in b.sides:
		var c1 := hex_grid.axial_to_world(key.x, key.y)
		var c2 := hex_grid.axial_to_world(key.z, key.w)
		var strip := MeshInstance3D.new()
		strip.name = "Edge_%s_%d" % [b.name, i]
		strip.mesh = _create_edge_strip_mesh(c2 - c1, hex_grid.hex_size)
		strip.material_override = material
		var mid := (c1 + c2) * 0.5
		strip.position = Vector3(mid.x, TERRAIN_Y + 0.01, mid.z)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain_node.add_child(strip)
		i += 1


## A quad along the side shared by two hexes whose centres differ by `across`: as long as the side
## (a hex side is as long as the hex's circumradius) and EDGE_STRIP_WIDTH wide, centred on the origin.
func _create_edge_strip_mesh(across: Vector3, hex_size: float) -> ArrayMesh:
	var d := Vector3(across.x, 0, across.z).normalized()
	var along := Vector3(-d.z, 0, d.x) * hex_size * 0.5
	var half_w := d * hex_size * EDGE_STRIP_WIDTH * 0.5
	var vertices := PackedVector3Array([-along - half_w, -along + half_w, along + half_w, along - half_w])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _half_alpha(c: Color) -> Color:
	return Color(c.r, c.g, c.b, c.a * 0.5)


## One ship's course layer (`Course_<ship_id>`): its plotted hexes in blue, the hexes it may
## extend to in green (orange where another ship holds one), as `collision_hexes`. Unselected
## ships draw at about half alpha. Replaces that ship's earlier layer.
func show_course(ship_id: String, path_hexes: Array[Vector2i], next_hexes: Array[Vector2i],
		collision_hexes: Array[Vector2i], hex_grid: HexGrid, selected: bool) -> void:
	clear_course(ship_id)
	if courses_node == null:
		return
	var container := Node3D.new()
	container.name = "Course_" + ship_id
	courses_node.add_child(container)
	var path_mat := _plotted_material if selected else _plotted_material_dim
	var next_mat := _valid_material if selected else _valid_material_dim
	var hit_mat := _collision_material if selected else _collision_material_dim
	for hex_pos in path_hexes:
		var w := hex_grid.axial_to_world(hex_pos.x, hex_pos.y)
		_add_hex_mesh(container, w, hex_grid.hex_size, path_mat)
	for hex_pos in next_hexes:
		var w := hex_grid.axial_to_world(hex_pos.x, hex_pos.y)
		_add_hex_mesh(container, w, hex_grid.hex_size, hit_mat if collision_hexes.has(hex_pos) else next_mat)
	for hex_pos in collision_hexes:
		if not next_hexes.has(hex_pos):
			var w := hex_grid.axial_to_world(hex_pos.x, hex_pos.y)
			_add_hex_mesh(container, w, hex_grid.hex_size, hit_mat)


func clear_course(ship_id: String) -> void:
	if courses_node == null:
		return
	var node := courses_node.get_node_or_null("Course_" + ship_id)
	if node:
		courses_node.remove_child(node)
		node.queue_free()


func clear_courses() -> void:
	if courses_node == null:
		return
	for child in courses_node.get_children():
		courses_node.remove_child(child)
		child.queue_free()


## The hex under a world position, valid or not, so click routing can decide.
func hex_at_world_pos(world_pos: Vector3, hex_grid: HexGrid) -> Vector2i:
	return hex_grid.world_to_axial(world_pos)


func show_blocked_hexes(hex_positions: Array[Vector2i], hex_grid: HexGrid) -> void:
	clear_blocked_hexes()
	for hex_pos in hex_positions:
		var world_pos = hex_grid.axial_to_world(hex_pos.x, hex_pos.y)
		_add_hex_mesh(blocked_hexes_node, world_pos, hex_grid.hex_size, _blocked_material)


## Draw one broadside's fire arc (for a two-hex ship the caller passes the union of the bow and
## stern battery hexes, GameController.broadside_arc) in that side's colour (BroadsideColors): a faint fill and an
## opaque rim, so the arc reads as the same colour as the fire panel's swatch on any water.
## `highlight` false draws the fill only: the part of a broadside's arc that the chosen battery
## does not cover (GameController.battery_arc gives the chosen battery's hexes).
## Arcs accumulate until clear_arcs().
func show_arc(hexes: Array[Vector2i], side: int, highlight: bool = true) -> void:
	if arc_grid == null or arcs_node == null:
		return
	var fill_mat := _arc_material(BroadsideColors.fill(side))
	var rim_mat := _arc_material(BroadsideColors.color(side))
	for hex_pos in hexes:
		var world_pos = arc_grid.axial_to_world(hex_pos.x, hex_pos.y)
		_add_hex_mesh(arcs_node, world_pos, arc_grid.hex_size, fill_mat)
		if not highlight:
			continue
		var rim := MeshInstance3D.new()
		rim.name = "ArcRim"
		rim.mesh = _create_hex_ring_mesh(arc_grid.hex_size * HEX_INSET, arc_grid.hex_size * HEX_INSET * 0.86)
		rim.material_override = rim_mat
		rim.position = Vector3(world_pos.x, OVERLAY_Y, world_pos.z)
		arcs_node.add_child(rim)


func _arc_material(color: Color) -> StandardMaterial3D:
	if not _arc_materials.has(color):
		var mat := _create_material(color)
		mat.render_priority = ARC_RENDER_PRIORITY  # beneath the target outline
		_arc_materials[color] = mat
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


## Outline the hexes of the currently chosen fire targets: an opaque ring on the hex edge, never a
## fill, so the target ship and its owner marker remain visible inside it.
func show_target_highlights(hexes: Array[Vector2i]) -> void:
	_clear_children(targets_node)
	if arc_grid == null or targets_node == null:
		return
	for hex_pos in hexes:
		var world_pos = arc_grid.axial_to_world(hex_pos.x, hex_pos.y)
		var ring := MeshInstance3D.new()
		ring.name = "TargetRing"
		ring.mesh = _create_hex_ring_mesh(arc_grid.hex_size * TARGET_RING_OUTER,
				arc_grid.hex_size * TARGET_RING_INNER)
		ring.material_override = _target_material
		ring.position = Vector3(world_pos.x, OVERLAY_Y, world_pos.z)
		targets_node.add_child(ring)


func clear_arcs() -> void:
	_clear_children(arcs_node)
	_clear_children(targets_node)


func clear_blocked_hexes() -> void:
	_clear_children(blocked_hexes_node)


func clear_everything() -> void:
	clear_courses()
	clear_blocked_hexes()
	clear_arcs()


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
