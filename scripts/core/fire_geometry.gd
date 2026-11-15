class_name FireGeometry
extends RefCounted
## FireGeometry - Pure hex geometry for gunnery: battery arcs, range, rakes, line of sight.
##
## Angles are measured in world space (HexGrid.axial_to_world) between a ship's heading
## vector (towards its neighbour in `facing`) and the vector to another hex.
## Holds no game state; callers pass hexes, facings and an `occupied` dictionary.

const MAX_RANGE := 15
## Rakes need the target within this range (7.E.2).
const RAKE_RANGE := 5
## Angular tolerance (degrees) so hexes lying exactly on an arc boundary are inside it.
const EPSILON_DEG := 0.5
const LOS_NUDGE := 1e-6

var hex_grid: HexGrid


func _init(p_hex_grid: HexGrid) -> void:
	hex_grid = p_hex_grid


## Which broadside of a single battery hex `from_hex` (bow or stern) facing `facing` covers `to_hex`.
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


## Shortest hex distance between any hex of `a` and any hex of `b` (7.C.4: firer to the closest
## hex of the target). Returns -1 when either list is empty.
func range_between(a: Array[Vector2i], b: Array[Vector2i]) -> int:
	var best := -1
	for x in a:
		for y in b:
			var d := hex_grid.hex_distance(x.x, x.y, y.x, y.y)
			if best < 0 or d < best:
				best = d
	return best


## Whether one battery (the bow or stern hex of a ship facing `facing`) bears on a target on
## broadside `side` (7.B.2-7.B.6): at least one target hex lies in the battery's arc within
## MAX_RANGE, and every target hex in that arc has a clear line of sight. Target hexes outside the
## arc are ignored (7.B.6). `occupied` must already exclude the firer's and the target's hexes.
func battery_bears(battery_hex: Vector2i, facing: int, side: int, target_hexes: Array[Vector2i],
		occupied: Dictionary) -> bool:
	var any_in_arc := false
	for h in target_hexes:
		if not in_battery_arc(battery_hex, facing, side, h):
			continue
		any_in_arc = true
		if not has_line_of_sight(battery_hex, h, occupied):
			return false
	return any_in_arc


## Whether `hex` lies in the `side` arc of the battery at `battery_hex`, within MAX_RANGE.
func in_battery_arc(battery_hex: Vector2i, facing: int, side: int, hex: Vector2i) -> bool:
	return bearing_side(battery_hex, facing, hex) == side \
		and hex_grid.hex_distance(battery_hex.x, battery_hex.y, hex.x, hex.y) <= MAX_RANGE


## Rake by two-hex ships (7.E.2). The target's bow is `target_bow`, its stern is behind it.
## A rake needs range (closest hexes) <= RAKE_RANGE and either
##   a. no firer hex lies in any of the target's four battery arcs, or
##   b. a firer hex is adjacent to the target, directly ahead of its bow or astern of its stern.
## Returns "stern" when the firer's centre is aft of the target's beam line (through the target's
## centre, perpendicular to its keel), "bow" otherwise, "" for no rake. Whether the firer can fire
## at all is the caller's job.
func rake_type_ships(target_bow: Vector2i, target_facing: int, firer_hexes: Array[Vector2i]) -> String:
	if firer_hexes.is_empty():
		return ""
	var target_stern := HexGrid.stern_of(target_bow, target_facing)
	var target_hexes: Array[Vector2i] = [target_bow, target_stern]
	var r := range_between(firer_hexes, target_hexes)
	if r < 1 or r > RAKE_RANGE:
		return ""
	if not _outside_all_arcs(target_hexes, target_facing, firer_hexes) \
			and not _dead_ahead_or_astern(target_bow, target_stern, target_facing, firer_hexes):
		return ""
	var target_centre := (_world_xz(target_bow) + _world_xz(target_stern)) / 2.0
	var keel := _world_xz(target_bow) - _world_xz(target_stern)
	var firer_centre := Vector2.ZERO
	for h in firer_hexes:
		firer_centre += _world_xz(h)
	firer_centre /= float(firer_hexes.size())
	return "stern" if keel.dot(firer_centre - target_centre) < 0.0 else "bow"


## Which side of the target (bow `target_bow`, facing `target_facing`) the firer's centre lies on,
## by relative bearing from the target's centre: ShipState.PORT, ShipState.STARBOARD, or -1 when
## the firer's centre is on the target's centre line (dead ahead or astern).
func relative_side(target_bow: Vector2i, target_facing: int, firer_hexes: Array[Vector2i]) -> int:
	if firer_hexes.is_empty():
		return -1
	var target_stern := HexGrid.stern_of(target_bow, target_facing)
	var target_centre := (_world_xz(target_bow) + _world_xz(target_stern)) / 2.0
	var keel := _world_xz(target_bow) - _world_xz(target_stern)
	var firer_centre := Vector2.ZERO
	for h in firer_hexes:
		firer_centre += _world_xz(h)
	firer_centre /= float(firer_hexes.size())
	var to_firer := firer_centre - target_centre
	var cross := keel.x * to_firer.y - keel.y * to_firer.x
	if absf(cross) <= 1e-4 * maxf(keel.length() * to_firer.length(), 1.0):
		return -1
	# Same convention as bearing_side: a positive cross product is clockwise (starboard).
	return ShipState.STARBOARD if cross > 0.0 else ShipState.PORT


func _outside_all_arcs(target_hexes: Array[Vector2i], target_facing: int,
		firer_hexes: Array[Vector2i]) -> bool:
	for battery in target_hexes:
		for h in firer_hexes:
			if bearing_side(battery, target_facing, h) != -1:
				return false
	return true


func _dead_ahead_or_astern(target_bow: Vector2i, target_stern: Vector2i, target_facing: int,
		firer_hexes: Array[Vector2i]) -> bool:
	var ahead := hex_grid.get_neighbor(target_bow.x, target_bow.y, posmod(target_facing, 6))
	var astern := hex_grid.get_neighbor(target_stern.x, target_stern.y, posmod(target_facing + 3, 6))
	return firer_hexes.has(ahead) or firer_hexes.has(astern)


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


## All hexes within `max_range` of `battery_hex` (a ship's bow or stern hex) that lie in that
## battery's `side` arc. A ship's whole broadside arc is the union for its bow and stern.
func broadside_hexes(battery_hex: Vector2i, facing: int, side: int, max_range: int = MAX_RANGE) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for h in hex_grid.hex_range(battery_hex.x, battery_hex.y, max_range):
		if h != battery_hex and bearing_side(battery_hex, facing, h) == side:
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
