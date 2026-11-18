class_name AnchorMarkers
extends Node3D
## AnchorMarkers - the anchors of anchored ships and their cables on the map (13.B-C; presentation
## only). A dark anchor mesh sits at each anchor hex and a hemp cable runs from it to the end of
## the ship the cable holds. GameController calls refresh() with the ships' state; this node never
## changes game state.

const CABLE_COLOR := Color(1.0, 0.82, 0.38)
const ANCHOR_COLOR := Color(0.12, 0.1, 0.08)
const CABLE_RADIUS := 0.06
const CABLE_HEIGHT := 0.42  ## above the waterline, like the grapple lines
const ANCHOR_RADIUS := 0.2

var _cable_material: StandardMaterial3D = null
var _anchor_material: StandardMaterial3D = null


func _ready() -> void:
	name = "AnchorMarkers"


## Redraws every anchor and cable among `ships` (Array[ShipState]) on `grid`.
func refresh(ships: Array, grid: HexGrid) -> void:
	for child in get_children():
		child.queue_free()
	for m in markers(ships, grid):
		_add_marker(m["anchor"], m["end"])


## One marker per anchored ship on the map, by ship id: {"ship_id", "anchor", "end"} with both
## points in world space, raised to CABLE_HEIGHT. Pure.
static func markers(ships: Array, grid: HexGrid) -> Array:
	var anchored: Array = []
	for s in ships:
		if s.is_anchored() and s.is_on_map():
			anchored.append(s)
	anchored.sort_custom(func(x, y): return x.ship_id < y.ship_id)
	var lift := Vector3(0, CABLE_HEIGHT, 0)
	var out: Array = []
	for s in anchored:
		var ah: Vector2i = s.anchor.get("hex", s.hex_position)
		var eh: Vector2i = s.anchored_end_hex()
		out.append({
			"ship_id": s.ship_id,
			"anchor": grid.axial_to_world(ah.x, ah.y) + lift,
			"end": grid.axial_to_world(eh.x, eh.y) + lift,
		})
	return out


func _add_marker(anchor_pos: Vector3, end_pos: Vector3) -> void:
	var body := MeshInstance3D.new()
	body.name = "Anchor"
	var sphere := SphereMesh.new()
	sphere.radius = ANCHOR_RADIUS
	sphere.height = ANCHOR_RADIUS * 2.0
	body.mesh = sphere
	body.material_override = _anchor()
	body.position = anchor_pos
	add_child(body)
	var length := anchor_pos.distance_to(end_pos)
	if length <= 0.001:
		return
	var cable := MeshInstance3D.new()
	cable.name = "Cable"
	var mesh := CylinderMesh.new()
	mesh.top_radius = CABLE_RADIUS
	mesh.bottom_radius = CABLE_RADIUS
	mesh.height = length
	mesh.radial_segments = 6
	cable.mesh = mesh
	cable.material_override = _cable()
	add_child(cable)
	# A CylinderMesh runs along local Y: point Y from the anchor to the ship.
	var dir := (end_pos - anchor_pos) / length
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var forward := side.cross(dir).normalized()
	cable.transform = Transform3D(Basis(side, dir, forward), (anchor_pos + end_pos) / 2.0)


func _cable() -> StandardMaterial3D:
	if _cable_material == null:
		_cable_material = GrappleLines._overlay_material(CABLE_COLOR)
	return _cable_material


func _anchor() -> StandardMaterial3D:
	if _anchor_material == null:
		_anchor_material = GrappleLines._overlay_material(ANCHOR_COLOR)
	return _anchor_material
