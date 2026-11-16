class_name GrappleLines
extends Node3D
## GrappleLines - the grapples between ships on the map (8.C; presentation only). Each grappled pair
## is drawn as hemp lines between every pair of their hexes that touch, with a grapnel at each end.
## GameController calls refresh() with the ships' state; this node never changes game state.

const ROPE_COLOR := Color(1.0, 0.82, 0.38)
const GRAPNEL_COLOR := Color(0.25, 0.2, 0.12)
const ROPE_RADIUS := 0.07
const ROPE_HEIGHT := 0.42  ## above the waterline, over the bulwarks
const GRAPNEL_RADIUS := 0.13

var _rope_material: StandardMaterial3D = null
var _grapnel_material: StandardMaterial3D = null


func _ready() -> void:
	name = "GrappleLines"


## Redraws every grapple among `ships` (Array[ShipState]) on `grid`.
func refresh(ships: Array, grid: HexGrid) -> void:
	for child in get_children():
		child.queue_free()
	for seg in segments(ships, grid):
		_add_rope(seg[0], seg[1])


## World-space [from, to] segments for every grappled pair (each pair once, by ship_id): one per
## pair of their hexes one hex apart, raised to ROPE_HEIGHT. Pure.
static func segments(ships: Array, grid: HexGrid) -> Array:
	var by_id := {}
	for s in ships:
		by_id[s.ship_id] = s
	var out: Array = []
	var ids: Array = by_id.keys()
	ids.sort()
	for sid in ids:
		var a: ShipState = by_id[sid]
		for other_id in a.grappled_with:
			if other_id <= sid or not by_id.has(other_id):
				continue
			var b: ShipState = by_id[other_id]
			for ha in a.occupied_hexes():
				for hb in b.occupied_hexes():
					if grid.hex_distance(ha.x, ha.y, hb.x, hb.y) != 1:
						continue
					var lift := Vector3(0, ROPE_HEIGHT, 0)
					out.append([grid.axial_to_world(ha.x, ha.y) + lift, grid.axial_to_world(hb.x, hb.y) + lift])
	return out


func _add_rope(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length <= 0.001:
		return
	var rope := MeshInstance3D.new()
	rope.name = "Rope"
	var mesh := CylinderMesh.new()
	mesh.top_radius = ROPE_RADIUS
	mesh.bottom_radius = ROPE_RADIUS
	mesh.height = length
	mesh.radial_segments = 6
	rope.mesh = mesh
	rope.material_override = _rope()
	add_child(rope)
	# A CylinderMesh runs along local Y: point Y from `from` to `to`.
	var dir := (to - from) / length
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var forward := side.cross(dir).normalized()
	rope.transform = Transform3D(Basis(side, dir, forward), (from + to) / 2.0)
	for end in [from, to]:
		var grapnel := MeshInstance3D.new()
		grapnel.name = "Grapnel"
		var sphere := SphereMesh.new()
		sphere.radius = GRAPNEL_RADIUS
		sphere.height = GRAPNEL_RADIUS * 2.0
		grapnel.mesh = sphere
		grapnel.material_override = _grapnel()
		grapnel.position = end
		add_child(grapnel)


func _rope() -> StandardMaterial3D:
	if _rope_material == null:
		_rope_material = _overlay_material(ROPE_COLOR)
	return _rope_material


func _grapnel() -> StandardMaterial3D:
	if _grapnel_material == null:
		_grapnel_material = _overlay_material(GRAPNEL_COLOR)
	return _grapnel_material


## Unshaded and drawn over the hulls and sails, like the other map markers: from the overhead camera
## the lines between two hulls alongside would otherwise be hidden.
static func _overlay_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.render_priority = 10
	return m
