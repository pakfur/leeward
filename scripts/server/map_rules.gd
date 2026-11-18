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
