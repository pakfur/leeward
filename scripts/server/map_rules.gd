class_name MapRules
extends RefCounted
## MapRules - pure statics for escape permission and boundary crossings (map and scenario spec).
##
## The scenario's `escape` entry, keyed by side (string), gives {from_turn, edges, share}:
## from_turn defaults to 1, edges to [] (every escape boundary), share to 0.0.

const CLEAR := "clear"
const BLOCKED := "blocked"
const LOST := "lost"
const ESCAPE := "escape"


## {} when the side may not escape, else {from_turn: int, edges: Array[String], share: float}.
static func permission(scenario: Dictionary, side: int) -> Dictionary:
	var all = scenario.get("escape", {})
	if not (all is Dictionary) or not all.has(str(side)):
		return {}
	var entry = all[str(side)]
	if not (entry is Dictionary):
		return {}
	var edges: Array[String] = []
	for e in entry.get("edges", []):
		edges.append(str(e))
	return {
		"from_turn": int(entry.get("from_turn", 1)),
		"edges": edges,
		"share": float(entry.get("share", 0.0)),
	}


## "" when the side may declare escape on `turn`, else the reason.
static func declare_error(scenario: Dictionary, side: int, turn: int) -> String:
	var p := permission(scenario, side)
	if p.is_empty():
		return "side %d may not escape" % side
	if turn < int(p["from_turn"]):
		return "escape is allowed from turn %d" % int(p["from_turn"])
	return ""


static func may_declare(scenario: Dictionary, side: int, turn: int) -> bool:
	return declare_error(scenario, side, turn) == ""


static func may_cross(scenario: Dictionary, ship: ShipState, boundary: TerrainMap.Boundary, turn: int) -> bool:
	if boundary == null or boundary.kind != TerrainMap.ESCAPE:
		return false
	var p := permission(scenario, ship.side)
	if p.is_empty() or turn < int(p["from_turn"]):
		return false
	var edges: Array = p["edges"]
	if not edges.is_empty() and not edges.has(boundary.name):
		return false
	return ship.escape_declared


static func share(scenario: Dictionary, side: int) -> float:
	return float(permission(scenario, side).get("share", 0.0))


## What stepping from `from` to `to` does: {"outcome": CLEAR|BLOCKED|LOST|ESCAPE, "edge": name or ""}.
static func crossing_outcome(scenario: Dictionary, ship: ShipState, from: Vector2i, to: Vector2i,
		turn: int) -> Dictionary:
	var b := TerrainMap.of(scenario).crossing(from, to)
	if b == null:
		return {"outcome": CLEAR, "edge": ""}
	match b.kind:
		TerrainMap.NONE:
			return {"outcome": LOST, "edge": b.name}
		TerrainMap.ESCAPE:
			if may_cross(scenario, ship, b, turn):
				return {"outcome": ESCAPE, "edge": b.name}
	return {"outcome": BLOCKED, "edge": b.name}


## What shifting a ship's footprint from `old_hexes` to `new_hexes` (paired, bow first) meets when
## it is forced (drift): {"result": "edge"|"lost"|"escape"|"land"|"ship"|"clear", "edge": name,
## "blocker": ship id, "shallow_bow": bool}. `others` maps hex -> ship id of the ships the footprint
## may not enter. Priority: a blocking crossing (edge), then a crossing off the map where there is
## no sea room (lost), then an escape crossing, then a new hex of land, then a ship in a new hex
## (bow first), else clear. `shallow_bow` (clear only) says the new bow hex is in a shallow area,
## so the caller rolls the depth.
static func forced_move(scenario: Dictionary, ship: ShipState, old_hexes: Array[Vector2i],
		new_hexes: Array[Vector2i], others: Dictionary, turn: int) -> Dictionary:
	var lost := ""
	var escape := ""
	for i in new_hexes.size():
		var crossing := crossing_outcome(scenario, ship, old_hexes[i], new_hexes[i], turn)
		match crossing["outcome"]:
			BLOCKED:
				return {"result": "edge", "edge": crossing["edge"], "blocker": "", "shallow_bow": false}
			LOST:
				if lost == "":
					lost = crossing["edge"]
			ESCAPE:
				if escape == "":
					escape = crossing["edge"]
	if lost != "":
		return {"result": "lost", "edge": lost, "blocker": "", "shallow_bow": false}
	if escape != "":
		return {"result": "escape", "edge": escape, "blocker": "", "shallow_bow": false}
	var terrain := TerrainMap.of(scenario)
	for hex in new_hexes:
		if terrain.is_land(hex):
			return {"result": "land", "edge": "", "blocker": "", "shallow_bow": false}
	for hex in new_hexes:
		if others.has(hex):
			return {"result": "ship", "edge": "", "blocker": others[hex], "shallow_bow": false}
	return {"result": "clear", "edge": "", "blocker": "",
		"shallow_bow": not new_hexes.is_empty() and terrain.area_at(new_hexes[0]) != null}
