class_name TowLines
extends Node3D
## TowLines - the hawsers of the tows on the map (12.A; presentation only). Each tow is drawn as one
## line from the tower's stern hex to her tow's bow hex. GameController calls refresh() with the
## ships' state; this node never changes game state.

const HAWSER_COLOR := Color(0.93, 0.86, 0.62)
const HAWSER_RADIUS := 0.09

var _material: StandardMaterial3D = null


func _ready() -> void:
	name = "TowLines"


## Redraws every tow among `ships` (Array[ShipState]) on `grid`.
func refresh(ships: Array, grid: HexGrid) -> void:
	for child in get_children():
		child.queue_free()
	for seg in segments(ships, grid):
		_add_hawser(seg[0], seg[1])


## World-space [from, to] segments, one per tower on the map whose tow is on the map too (by tower
## ship_id): from the tower's stern hex to the tow's bow hex, raised to GrappleLines.ROPE_HEIGHT. Pure.
static func segments(ships: Array, grid: HexGrid) -> Array:
	var by_id := {}
	for s in ships:
		by_id[s.ship_id] = s
	var ids: Array = by_id.keys()
	ids.sort()
	var lift := Vector3(0, GrappleLines.ROPE_HEIGHT, 0)
	var out: Array = []
	for sid in ids:
		var tower: ShipState = by_id[sid]
		if not tower.is_towing() or not tower.is_on_map() or not by_id.has(tower.towing_id):
			continue
		var towed: ShipState = by_id[tower.towing_id]
		if not towed.is_on_map():
			continue
		var stern := tower.stern_hex()
		var bow := towed.hex_position
		out.append([grid.axial_to_world(stern.x, stern.y) + lift, grid.axial_to_world(bow.x, bow.y) + lift])
	return out


func _add_hawser(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length <= 0.001:
		return
	var hawser := MeshInstance3D.new()
	hawser.name = "Hawser"
	var mesh := CylinderMesh.new()
	mesh.top_radius = HAWSER_RADIUS
	mesh.bottom_radius = HAWSER_RADIUS
	mesh.height = length
	mesh.radial_segments = 6
	hawser.mesh = mesh
	if _material == null:
		_material = GrappleLines._overlay_material(HAWSER_COLOR)
	hawser.material_override = _material
	add_child(hawser)
	# A CylinderMesh runs along local Y: point Y from `from` to `to`.
	var dir := (to - from) / length
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var forward := side.cross(dir).normalized()
	hawser.transform = Transform3D(Basis(side, dir, forward), (from + to) / 2.0)
