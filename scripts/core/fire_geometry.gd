class_name FireGeometry
extends RefCounted
## FireGeometry - Pure hex geometry for gunnery: broadside arcs, rake wedges, line of sight.
##
## Angles are measured in world space (HexGrid.axial_to_world) between a ship's heading
## vector (towards its neighbour in `facing`) and the vector to another hex.
## Holds no game state; callers pass hexes, facings and an `occupied` dictionary.

const MAX_RANGE := 15
## Angular tolerance (degrees) so hexes lying exactly on an arc boundary are inside it.
const EPSILON_DEG := 0.5
const LOS_NUDGE := 1e-6

var hex_grid: HexGrid


func _init(p_hex_grid: HexGrid) -> void:
	hex_grid = p_hex_grid


## Which broadside covers `to_hex` from a ship at `from_hex` facing `facing`.
## Returns ShipState.PORT, ShipState.STARBOARD, or -1 if in neither broadside arc.
func bearing_side(from_hex: Vector2i, facing: int, to_hex: Vector2i) -> int:
	if from_hex == to_hex:
		return -1
	var heading := _heading_vector(from_hex, facing)
	var target := _world_xz(to_hex) - _world_xz(from_hex)
	var theta := _angle_deg(heading, target)
	if theta < 60.0 - EPSILON_DEG or theta > 120.0 + EPSILON_DEG:
		return -1
	# World x/z: +z is down the map, so a positive cross product is clockwise (starboard).
	var cross := heading.x * target.y - heading.y * target.x
	return ShipState.STARBOARD if cross > 0.0 else ShipState.PORT


## Whether a firer at `firer_hex` rakes a target at `target_hex` facing `target_facing`.
## Returns "bow" (firer within the target's bow wedge), "stern", or "". Range is the caller's job.
func rake_type(target_hex: Vector2i, target_facing: int, firer_hex: Vector2i) -> String:
	if target_hex == firer_hex:
		return ""
	var heading := _heading_vector(target_hex, target_facing)
	var to_firer := _world_xz(firer_hex) - _world_xz(target_hex)
	var theta := _angle_deg(heading, to_firer)
	if theta < 30.0 - EPSILON_DEG:
		return "bow"
	if theta > 150.0 + EPSILON_DEG:
		return "stern"
	return ""


## Line of sight between two hexes. `occupied` maps Vector2i -> anything.
## For each intermediate point on the centre line, the point is nudged ±1e-6 perpendicular to
## the line and both nudged points are rounded to hexes; sight is blocked only if both are occupied.
## Endpoints never block.
func has_line_of_sight(from_hex: Vector2i, to_hex: Vector2i, occupied: Dictionary) -> bool:
	var n := hex_grid.hex_distance(from_hex.x, from_hex.y, to_hex.x, to_hex.y)
	if n <= 1:
		return true
	var a := _world_xz(from_hex)
	var b := _world_xz(to_hex)
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x) * LOS_NUDGE
	for i in range(1, n):
		var p := a.lerp(b, float(i) / float(n))
		var h1 := hex_grid.world_to_axial(Vector3(p.x + perp.x, 0.0, p.y + perp.y))
		var h2 := hex_grid.world_to_axial(Vector3(p.x - perp.x, 0.0, p.y - perp.y))
		if occupied.has(h1) and occupied.has(h2):
			return false
	return true


## All hexes within `max_range` (excluding the ship's own) that lie in the given broadside arc.
func broadside_hexes(hex: Vector2i, facing: int, side: int, max_range: int = MAX_RANGE) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for h in hex_grid.hex_range(hex.x, hex.y, max_range):
		if h != hex and bearing_side(hex, facing, h) == side:
			result.append(h)
	return result


func _world_xz(hex: Vector2i) -> Vector2:
	var w := hex_grid.axial_to_world(hex.x, hex.y)
	return Vector2(w.x, w.z)


func _heading_vector(hex: Vector2i, facing: int) -> Vector2:
	var nb := hex_grid.get_neighbor(hex.x, hex.y, posmod(facing, 6))
	return _world_xz(nb) - _world_xz(hex)


## Unsigned angle in degrees [0, 180] between two 2D vectors.
func _angle_deg(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(atan2(absf(a.cross(b)), a.dot(b)))
