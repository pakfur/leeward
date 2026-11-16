class_name CourseClicks
extends RefCounted
## Routes a map click to the course it edits (pure, no state).
##
## `courses` maps ship_id to {path_hexes: Array[Vector2i], next_hexes: Array[Vector2i],
## end_hex: Vector2i}. A click on a hex offered next extends that course, a click on a hex of
## the course cuts it back to that step.

static func route(hex: Vector2i, courses: Dictionary, selected_id: String) -> Dictionary:
	var claims := {}  # ship_id -> claim
	for ship_id in courses:
		var claim := _claim(hex, courses[ship_id], ship_id)
		if not claim.is_empty():
			claims[ship_id] = claim
	if claims.is_empty():
		return {}
	if claims.has(selected_id):
		return claims[selected_id]
	var grid := HexGrid.new()
	var best_id := ""
	var best_dist := 0
	var ids: Array = claims.keys()
	ids.sort()
	for ship_id in ids:
		var end: Vector2i = courses[ship_id].get("end_hex", Vector2i.ZERO)
		var d := grid.hex_distance(hex.x, hex.y, end.x, end.y)
		if best_id == "" or d < best_dist:
			best_id = ship_id
			best_dist = d
	return claims[best_id]


static func _claim(hex: Vector2i, course: Dictionary, ship_id: String) -> Dictionary:
	var path: Array = course.get("path_hexes", [])
	var next: Array = course.get("next_hexes", [])
	var end: Vector2i = course.get("end_hex", Vector2i(-9999, -9999))
	if hex == end and next.has(hex):
		return {"ship_id": ship_id, "kind": "extend", "step_index": -1}
	for i in range(path.size() - 1, -1, -1):
		if path[i] == hex:
			return {"ship_id": ship_id, "kind": "cut", "step_index": i}
	if next.has(hex):
		return {"ship_id": ship_id, "kind": "extend", "step_index": -1}
	return {}
