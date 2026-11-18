class_name TerrainMap
extends RefCounted
## TerrainMap - the board of one scenario: a rectangle of hexes (offset columns and rows),
## typed boundaries (the four map edges plus any scenario-defined lines), land and shallow areas.
##
## Pure and read-only: it is built once from the scenario dictionary and only answers queries.
## `of()` caches the last map by dictionary identity, so mutating a scenario dictionary in place
## after a query is unsupported (build a new dictionary or call `from_scenario`).
## Problems found while reading the scenario are collected in `errors` (all start "Terrain: ").

const OPEN := "open"
const NONE := "none"
const ESCAPE := "escape"
const KINDS: Array[String] = ["open", "none", "escape"]
const EDGE_NAMES: Array[String] = ["N", "E", "S", "W"]
const DEPTH_DIE := 6

## A set of hex sides (a line) with a kind. A map edge's `outside` lists the off-map hexes it
## borders; a custom boundary lists both hexes of every side.
class Boundary extends RefCounted:
	var name: String = ""
	var kind: String = "open"
	var sides: Dictionary = {}            # side_key(a, b) -> true
	var outside: Array[Vector2i] = []


## Shallow water: every hex of the area has depth base + 1d6 (so base+1 .. base+6).
class ShallowArea extends RefCounted:
	var name: String = ""
	var base: int = 0
	var hexes: Array[Vector2i] = []


static var _cache_source: Dictionary = {}
static var _cache_map: TerrainMap = null

var bounded: bool = false
var width: int = 0
var height: int = 0
var col_min: int = 0
var row_min: int = 0
var land: Dictionary = {}                 # Vector2i -> true
var areas: Array[ShallowArea] = []
var boundaries: Array[Boundary] = []      # N, E, S, W first (bounded maps), then terrain.boundaries in order
var errors: Array[String] = []

var _area_of: Dictionary = {}             # Vector2i -> ShallowArea
var _by_side: Dictionary = {}             # side_key -> Boundary (first boundary listed wins)


## The map of `scenario`, cached while the same dictionary is asked about again.
static func of(scenario: Dictionary) -> TerrainMap:
	if _cache_map == null or not is_same(scenario, _cache_source):
		_cache_map = from_scenario(scenario)
		_cache_source = scenario
	return _cache_map


static func from_scenario(scenario: Dictionary) -> TerrainMap:
	var m := TerrainMap.new()
	var bounds: Dictionary = scenario.get("map_bounds", {})
	var terrain: Dictionary = scenario.get("terrain", {})
	m.bounded = bounds.has("width") and bounds.has("height")
	if m.bounded:
		m.width = int(bounds["width"])
		m.height = int(bounds["height"])
		@warning_ignore("integer_division")
		m.col_min = -m.width / 2
		@warning_ignore("integer_division")
		m.row_min = -m.height / 2
	m._read_edges(terrain.get("edges", {}))
	m._read_land(terrain.get("land", []))
	m._read_shallow(terrain.get("shallow", []))
	m._read_boundaries(terrain.get("boundaries", []))
	return m


## Both hexes of a side as a key, the smaller hex (x, then y) first, so a side has one key.
static func side_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		return Vector4i(b.x, b.y, a.x, a.y)
	return Vector4i(a.x, a.y, b.x, b.y)


## Axial (q, r) to offset (col, row): odd rows are shifted half a hex right.
static func axial_to_offset(hex: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(hex.x + (hex.y - (hex.y & 1)) / 2, hex.y)


static func offset_to_axial(col: int, row: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(col - (row - (row & 1)) / 2, row)


## Every hex of a `cols` x `rows` rectangle centred on the origin, row by row.
static func rect_hexes(cols: int, rows: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	@warning_ignore("integer_division")
	var c0 := -cols / 2
	@warning_ignore("integer_division")
	var r0 := -rows / 2
	for row in range(r0, r0 + rows):
		for col in range(c0, c0 + cols):
			out.append(offset_to_axial(col, row))
	return out


func in_bounds(hex: Vector2i) -> bool:
	if not bounded:
		return true
	var o := axial_to_offset(hex)
	return o.x >= col_min and o.x < col_min + width and o.y >= row_min and o.y < row_min + height


## The boundary the side between `from` and `to` lies on (either order), or null.
func crossing(from: Vector2i, to: Vector2i) -> Boundary:
	return _by_side.get(side_key(from, to), null)


func boundary(boundary_name: String) -> Boundary:
	for b in boundaries:
		if b.name == boundary_name:
			return b
	return null


func is_land(hex: Vector2i) -> bool:
	return land.has(hex)


func area_at(hex: Vector2i) -> ShallowArea:
	return _area_of.get(hex, null)


## Depth in feet-or-fathoms as the rules count it: shallow (base+1, base+6); land (0, 0);
## deep water (-1, -1).
func depth_range(hex: Vector2i) -> Vector2i:
	if land.has(hex):
		return Vector2i(0, 0)
	var area := area_at(hex)
	if area == null:
		return Vector2i(-1, -1)
	return Vector2i(area.base + 1, area.base + DEPTH_DIE)


## Whether a ship of `draft` runs aground in `hex`: "never", "maybe" (depth is rolled) or "always".
func grounds(hex: Vector2i, draft: int) -> String:
	if land.has(hex):
		return "always"
	var range_ := depth_range(hex)
	if range_.x < 0 or draft < range_.x:
		return "never"
	if draft >= range_.y:
		return "always"
	return "maybe"


## Hex distance to the nearest `outside` hex of the named boundary; -1 for an unknown name.
func distance_to_boundary(hex: Vector2i, boundary_name: String) -> int:
	var b := boundary(boundary_name)
	if b == null:
		return -1
	var best := -1
	for h in b.outside:
		var d := _distance(hex, h)
		if best < 0 or d < best:
			best = d
	return best


static func _distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	@warning_ignore("integer_division")
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


static func _hex(pair: Variant) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


func _add_boundary(b: Boundary) -> void:
	boundaries.append(b)
	for key in b.sides:
		if not _by_side.has(key):
			_by_side[key] = b


func _read_edges(edges: Dictionary) -> void:
	var kinds := {}
	for key in edges:
		var kind := str(edges[key])
		if not EDGE_NAMES.has(str(key)):
			errors.append("Terrain: unknown edge %s" % key)
			continue
		if not KINDS.has(kind):
			errors.append("Terrain: unknown kind %s on edge %s" % [kind, key])
			continue
		kinds[str(key)] = kind
	if not bounded:
		return
	var made := {}
	for n in EDGE_NAMES:
		var b := Boundary.new()
		b.name = n
		b.kind = kinds.get(n, OPEN)
		made[n] = b
	for hex in rect_hexes(width, height):
		for d in HexGrid.DIRECTIONS:
			var nb: Vector2i = hex + d
			if in_bounds(nb):
				continue
			var o := axial_to_offset(nb)
			var edge: String
			if o.y < row_min:
				edge = "N"
			elif o.y >= row_min + height:
				edge = "S"
			elif o.x < col_min:
				edge = "W"
			else:
				edge = "E"
			var b: Boundary = made[edge]
			b.sides[side_key(hex, nb)] = true
			if not b.outside.has(nb):
				b.outside.append(nb)
	for n in EDGE_NAMES:
		_add_boundary(made[n])


func _read_land(list: Array) -> void:
	for pair in list:
		var h := _hex(pair)
		if not in_bounds(h):
			errors.append("Terrain: land hex %s is off the map" % h)
			continue
		land[h] = true


func _read_shallow(list: Array) -> void:
	for entry in list:
		var a := ShallowArea.new()
		a.name = str(entry.get("name", ""))
		var raw_base = entry.get("base", 0)
		var integral: bool = raw_base is int or (raw_base is float and raw_base == floorf(raw_base))
		if not integral:
			errors.append("Terrain: shallow area '%s' has a non-integer base %s" % [a.name, str(raw_base)])
		a.base = int(raw_base) if integral else 0
		if a.base < 0:
			errors.append("Terrain: shallow area '%s' has a negative base %d" % [a.name, a.base])
		for pair in entry.get("hexes", []):
			var h := _hex(pair)
			if not in_bounds(h):
				errors.append("Terrain: shallow hex %s of '%s' is off the map" % [h, a.name])
			elif land.has(h):
				errors.append("Terrain: hex %s is both land and shallow" % h)
			elif _area_of.has(h):
				errors.append("Terrain: hex %s is in two shallow areas ('%s' and '%s')" % [h, _area_of[h].name, a.name])
			else:
				_area_of[h] = a
				a.hexes.append(h)
		areas.append(a)


func _read_boundaries(list: Array) -> void:
	for entry in list:
		var b := Boundary.new()
		b.name = str(entry.get("name", ""))
		b.kind = str(entry.get("kind", OPEN))
		if not KINDS.has(b.kind):
			errors.append("Terrain: unknown kind %s on boundary '%s'" % [b.kind, b.name])
			b.kind = OPEN
		elif b.kind != OPEN:
			# Map and scenario spec: lines inside the map are walls only, for now.
			errors.append("Terrain: boundary '%s' of kind %s is not supported yet (inner boundaries are open only)"
				% [b.name, b.kind])
			b.kind = OPEN
		for side in entry.get("sides", []):
			var a := _hex(side[0])
			var c := _hex(side[1])
			if _distance(a, c) != 1:
				errors.append("Terrain: boundary '%s' side %s-%s: hexes are not neighbours" % [b.name, a, c])
				continue
			b.sides[side_key(a, c)] = true
			for h in [a, c]:
				if not b.outside.has(h):
					b.outside.append(h)
		_add_boundary(b)
