class_name HexGrid
extends RefCounted
## HexGrid - Handles hex coordinate math using axial coordinates (q, r)

const SQRT3 = 1.732050807568877

# Hex directions (pointy-top orientation)
const DIRECTIONS = [
	Vector2i(1, 0),   # 0: East
	Vector2i(0, 1),   # 1: Southeast
	Vector2i(-1, 1),  # 2: Southwest
	Vector2i(-1, 0),  # 3: West
	Vector2i(0, -1),  # 4: Northwest
	Vector2i(1, -1),  # 5: Northeast
]

var hex_size: float = 1.0

func _init(size: float = 1.0) -> void:
	hex_size = size

## Convert axial coordinates (q, r) to world position (isometric)
func axial_to_world(q: int, r: int) -> Vector3:
	var x = hex_size * (SQRT3 * q + SQRT3/2.0 * r)
	var z = hex_size * (3.0/2.0 * r)
	return Vector3(x, 0, z)

## Convert world position to axial coordinates (returns Vector2i with q, r)
func world_to_axial(world_pos: Vector3) -> Vector2i:
	var q = (SQRT3/3.0 * world_pos.x - 1.0/3.0 * world_pos.z) / hex_size
	var r = (2.0/3.0 * world_pos.z) / hex_size
	return axial_round(q, r)

## Round fractional axial coordinates to nearest hex
func axial_round(q: float, r: float) -> Vector2i:
	var s = -q - r
	var rq = round(q)
	var rr = round(r)
	var rs = round(s)

	var q_diff = abs(rq - q)
	var r_diff = abs(rr - r)
	var s_diff = abs(rs - s)

	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs

	return Vector2i(int(rq), int(rr))

## Get neighbor hex in a given direction (0-5)
func get_neighbor(q: int, r: int, direction: int) -> Vector2i:
	var dir = DIRECTIONS[direction % 6]
	return Vector2i(q + dir.x, r + dir.y)

## Calculate distance between two hexes (in hex units)
func hex_distance(q1: int, r1: int, q2: int, r2: int) -> int:
	var s1 = -q1 - r1
	var s2 = -q2 - r2
	return (abs(q1 - q2) + abs(r1 - r2) + abs(s1 - s2)) / 2

## Get all hexes in a line from start to end
func hex_line(q1: int, r1: int, q2: int, r2: int) -> Array[Vector2i]:
	var distance = hex_distance(q1, r1, q2, r2)
	var results: Array[Vector2i] = []

	if distance == 0:
		results.append(Vector2i(q1, r1))
		return results

	for i in range(distance + 1):
		var t = float(i) / float(distance)
		var q = lerp(float(q1), float(q2), t)
		var r = lerp(float(r1), float(r2), t)
		results.append(axial_round(q, r))

	return results

## Get all hexes within a certain range
func hex_range(q: int, r: int, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []

	for dq in range(-radius, radius + 1):
		var r1 = max(-radius, -dq - radius)
		var r2 = min(radius, -dq + radius)
		for dr in range(r1, r2 + 1):
			results.append(Vector2i(q + dq, r + dr))

	return results

## Get ring of hexes at exact distance
func hex_ring(q: int, r: int, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []

	if radius == 0:
		results.append(Vector2i(q, r))
		return results

	# Start at a hex 'radius' steps away in direction 4 (Northwest)
	var current = Vector2i(q, r)
	for _i in range(radius):
		current = get_neighbor(current.x, current.y, 4)

	# Walk around the ring
	for direction in range(6):
		for _step in range(radius):
			results.append(current)
			current = get_neighbor(current.x, current.y, direction)

	return results

## Get facing direction (0-5) from one hex to another
func get_facing_direction(from_q: int, from_r: int, to_q: int, to_r: int) -> int:
	var dq = to_q - from_q
	var dr = to_r - from_r

	# Find the direction that best matches the delta
	var best_dir = 0
	var best_score = -999.0

	for i in range(6):
		var dir = DIRECTIONS[i]
		var score = float(dq * dir.x + dr * dir.y)
		if score > best_score:
			best_score = score
			best_dir = i

	return best_dir

## Calculate wind facing category based on ship facing and wind direction
## Returns: "L" (luffing), "C" (close hauled), "B" (broad reach), "R" (running)
func get_wind_facing(ship_facing: int, wind_direction: int) -> String:
	var relative_angle = (ship_facing - wind_direction + 6) % 6

	match relative_angle:
		0:  # Directly into wind
			return "L"
		1, 5:  # 60 degrees off wind
			return "C"
		2, 4:  # 120 degrees off wind
			return "B"
		3:  # Running before wind
			return "R"
		_:
			return "L"

## Get world position for edge between two hexes (for 2-hex ships)
## facing: direction the ship is pointing (0-5)
## q, r: the hex coordinates (for 2-hex ships, this is the "rear" hex)
func axial_to_edge_world(q: int, r: int, facing: int) -> Vector3:
	# Get the neighboring hex in the facing direction
	var neighbor = get_neighbor(q, r, facing)

	# Calculate center positions of both hexes
	var pos1 = axial_to_world(q, r)
	var pos2 = axial_to_world(neighbor.x, neighbor.y)

	# Edge position is midpoint between the two hex centers
	return (pos1 + pos2) / 2.0
