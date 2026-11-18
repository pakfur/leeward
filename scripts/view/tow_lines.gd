class_name TowLines
extends Node3D
## TowLines - the hawsers of the tows on the map (12.A; presentation only). Each tow is drawn as one
## line from the tower's stern to her tow's bow. GameController calls refresh() with the ships'
## state after every sync, and follow_views() every frame, so that the hawser stays on the ships
## while movement playback glides them between hexes; this node never changes game state.

const HAWSER_COLOR := Color(0.93, 0.86, 0.62)
const HAWSER_RADIUS := 0.09

var _material: StandardMaterial3D = null
## Tower ship id -> her hawser (MeshInstance3D), reused from frame to frame.
var _hawsers: Dictionary = {}


func _ready() -> void:
	name = "TowLines"


## Redraws every tow among `ships` (Array[ShipState]) on `grid`, from the ships' hexes.
func refresh(ships: Array, grid: HexGrid) -> void:
	var by_tower := {}
	for pair in _pairs(ships):
		by_tower[pair[0].ship_id] = _hex_segment(pair[0], pair[1], grid)
	_draw(by_tower)


## Redraws every tow among `ships` from the drawn poses of their views (`views`: ship id -> ShipView),
## so the hawser follows the ships through movement playback; a pair without both views is drawn
## from its hexes.
func follow_views(ships: Array, views: Dictionary, grid: HexGrid) -> void:
	var by_tower := {}
	for pair in _pairs(ships):
		var tower_view = views.get(pair[0].ship_id)
		var towed_view = views.get(pair[1].ship_id)
		if _posed(tower_view) and _posed(towed_view):
			by_tower[pair[0].ship_id] = segment_from_poses(tower_view.base_position,
				tower_view.model_node.rotation_degrees.y, towed_view.base_position,
				towed_view.model_node.rotation_degrees.y, grid)
		else:
			by_tower[pair[0].ship_id] = _hex_segment(pair[0], pair[1], grid)
	_draw(by_tower)


## Whether there is any tow among `ships` to draw.
static func any_tow(ships: Array) -> bool:
	return not _pairs(ships).is_empty()


## World-space [from, to] segments, one per tower on the map whose tow is on the map too (by tower
## ship_id): from the tower's stern hex to the tow's bow hex, raised to GrappleLines.ROPE_HEIGHT. Pure.
static func segments(ships: Array, grid: HexGrid) -> Array:
	var out: Array = []
	for pair in _pairs(ships):
		out.append(_hex_segment(pair[0], pair[1], grid))
	return out


## The hawser between two drawn ships (view poses: the centre of the two-hex hull, `*_angle` the
## model's Y rotation in degrees, as ShipView and the playback set them): from half a hex astern of
## the tower's centre (her stern hex) to half a hex ahead of the tow's centre (her bow hex), raised
## to GrappleLines.ROPE_HEIGHT. At whole hexes it is `segments`'. Pure.
static func segment_from_poses(tower_center: Vector3, tower_angle: float, towed_center: Vector3,
		towed_angle: float, grid: HexGrid) -> Array:
	var half_length := grid.hex_size * HexGrid.SQRT3 / 2.0
	var lift := Vector3(0, GrappleLines.ROPE_HEIGHT, 0)
	var stern := Vector3(tower_center.x, 0.0, tower_center.z) + _astern(tower_angle) * half_length
	var bow := Vector3(towed_center.x, 0.0, towed_center.z) - _astern(towed_angle) * half_length
	return [stern + lift, bow + lift]


## The model's +Z (its bow is -Z) in world space for a model Y rotation of `angle_deg`.
static func _astern(angle_deg: float) -> Vector3:
	var rad := deg_to_rad(angle_deg)
	return Vector3(sin(rad), 0.0, cos(rad))


## [tower, towed] for every tower on the map whose tow is on the map too, by tower ship_id.
static func _pairs(ships: Array) -> Array:
	var by_id := {}
	for s in ships:
		by_id[s.ship_id] = s
	var ids: Array = by_id.keys()
	ids.sort()
	var out: Array = []
	for sid in ids:
		var tower: ShipState = by_id[sid]
		if not tower.is_towing() or not tower.is_on_map() or not by_id.has(tower.towing_id):
			continue
		var towed: ShipState = by_id[tower.towing_id]
		if towed.is_on_map():
			out.append([tower, towed])
	return out


static func _hex_segment(tower: ShipState, towed: ShipState, grid: HexGrid) -> Array:
	var lift := Vector3(0, GrappleLines.ROPE_HEIGHT, 0)
	var stern := tower.stern_hex()
	var bow := towed.hex_position
	return [grid.axial_to_world(stern.x, stern.y) + lift, grid.axial_to_world(bow.x, bow.y) + lift]


static func _posed(view) -> bool:
	return view != null and is_instance_valid(view) and view.model_node != null


## Shows one hawser per entry of `by_tower` (tower id -> [from, to]) and drops the others.
func _draw(by_tower: Dictionary) -> void:
	for tower_id in _hawsers.keys():
		if not by_tower.has(tower_id):
			_hawsers[tower_id].queue_free()
			_hawsers.erase(tower_id)
	for tower_id in by_tower:
		var seg: Array = by_tower[tower_id]
		if not _hawsers.has(tower_id):
			_hawsers[tower_id] = _new_hawser()
		_place_hawser(_hawsers[tower_id], seg[0], seg[1])


func _new_hawser() -> MeshInstance3D:
	var hawser := MeshInstance3D.new()
	hawser.name = "Hawser"
	var mesh := CylinderMesh.new()
	mesh.top_radius = HAWSER_RADIUS
	mesh.bottom_radius = HAWSER_RADIUS
	mesh.height = 1.0
	mesh.radial_segments = 6
	hawser.mesh = mesh
	if _material == null:
		_material = GrappleLines._overlay_material(HAWSER_COLOR)
	hawser.material_override = _material
	add_child(hawser)
	return hawser


func _place_hawser(hawser: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	hawser.visible = length > 0.001
	if not hawser.visible:
		return
	(hawser.mesh as CylinderMesh).height = length
	# A CylinderMesh runs along local Y: point Y from `from` to `to`.
	var dir := (to - from) / length
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var forward := side.cross(dir).normalized()
	hawser.transform = Transform3D(Basis(side, dir, forward), (from + to) / 2.0)
