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

## V.D.1b: a ship this far from every pursuer escapes.
const ESCAPE_DISTANCE := 31
## V.D.1c: the band in which a ship escapes by being at least as fast as every pursuer in it.
const SPEED_RANGE_MIN := 20
const SPEED_RANGE_MAX := 30


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


## Range between two footprints: the axial distance between their closest hexes (7.C.4).
static func footprint_range(a: Array[Vector2i], b: Array[Vector2i]) -> int:
	var best := -1
	for x in a:
		for y in b:
			var dq := x.x - y.x
			var dr := x.y - y.y
			var d := (absi(dq) + absi(dr) + absi(dq + dr)) / 2
			if best < 0 or d < best:
				best = d
	return best


## The table movement allowance, 0 where the table has no entry: luffing, dismasted (level 0) or
## calm (wind speed 0). `sail_state` in either case.
static func table_ma(speed_type: String, wind_speed: int, wind_facing: String, sail_state: String,
		rigging_level: int) -> int:
	if wind_facing == "L" or rigging_level <= 0 or wind_speed <= 0:
		return 0
	return DataManager.get_movement_allowance(speed_type, wind_speed, wind_facing,
			sail_state.to_lower(), rigging_level)


## The ship's best movement allowance at `wind_facing` and `wind_speed`: the heaviest sail her
## rigging can carry (max_sail_state) at her rigging level, whatever sail she carries now. Used by
## the escape speed test (V.D.1c) and for arrival speed.
static func max_ma(ship: ShipState, wind_facing: String, wind_speed: int) -> int:
	return table_ma(ship.ship.speed_type, wind_speed, wind_facing, ship.max_sail_state(),
			ship.rigging_level())


## max_ma for a ship heading `facing` with the wind from `wind_direction`.
static func max_ma_heading(ship: ShipState, facing: int, wind_direction: int, wind_speed: int) -> int:
	return max_ma(ship, HexGrid.new().get_wind_facing(facing, wind_direction), wind_speed)


## Whether `ship` escapes now (V.D.1b-c), against `pursuers` (enemy ships that could chase her):
## {} or {"how": "distance", "range": r} (r >= ESCAPE_DISTANCE, or -1 with no pursuer) or
## {"how": "speed", "range": r} (the nearest pursuer SPEED_RANGE_MIN..MAX off, her max_ma above 0
## and at least that of every pursuer in that band of her class or larger (class number no
## higher)). Every max_ma is taken at the escaping ship's wind facing.
static func condition(ship: ShipState, pursuers: Array[ShipState], wind_direction: int,
		wind_speed: int) -> Dictionary:
	var own_hexes := ship.occupied_hexes()
	var nearest := -1
	for p in pursuers:
		var r := footprint_range(own_hexes, p.occupied_hexes())
		if nearest < 0 or r < nearest:
			nearest = r
	if nearest < 0 or nearest >= ESCAPE_DISTANCE:
		return {"how": "distance", "range": nearest}
	if nearest < SPEED_RANGE_MIN or nearest > SPEED_RANGE_MAX:
		return {}
	var wind_facing := HexGrid.new().get_wind_facing(ship.facing, wind_direction)
	var own := max_ma(ship, wind_facing, wind_speed)
	if own <= 0:
		return {}
	for p in pursuers:
		var r := footprint_range(own_hexes, p.occupied_hexes())
		if r < SPEED_RANGE_MIN or r > SPEED_RANGE_MAX or p.ship.ship_class > ship.ship.ship_class:
			continue
		if max_ma(p, wind_facing, wind_speed) > own:
			return {}
	return {"how": "speed", "range": nearest}
