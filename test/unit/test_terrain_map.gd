extends GutTest
## TerrainMap: the rectangular board, typed boundaries, land and shallows.

const TEN := {"map_bounds": {"width": 10, "height": 10}}


func _ten(extra: Dictionary = {}) -> TerrainMap:
	var s := TEN.duplicate(true)
	if not extra.is_empty():
		s["terrain"] = extra
	return TerrainMap.from_scenario(s)


func test_offset_round_trip() -> void:
	assert_eq(TerrainMap.axial_to_offset(Vector2i(3, 0)), Vector2i(3, 0))
	assert_eq(TerrainMap.axial_to_offset(Vector2i(0, 2)), Vector2i(1, 2))
	assert_eq(TerrainMap.axial_to_offset(Vector2i(0, -1)), Vector2i(-1, -1))
	assert_eq(TerrainMap.offset_to_axial(-1, -1), Vector2i(0, -1))
	for h in TerrainMap.rect_hexes(6, 4):
		var o := TerrainMap.axial_to_offset(h)
		assert_eq(TerrainMap.offset_to_axial(o.x, o.y), h)
	assert_eq(TerrainMap.rect_hexes(10, 10).size(), 100)


func test_rectangle_bounds() -> void:
	var t := _ten()
	for h in [Vector2i(4, 0), Vector2i(2, 4), Vector2i(-7, 4), Vector2i(7, -5), Vector2i(-2, -5)]:
		assert_true(t.in_bounds(h), str(h))
	for h in [Vector2i(5, 0), Vector2i(3, 4), Vector2i(-8, 4), Vector2i(8, -5), Vector2i(0, 5), Vector2i(0, -6)]:
		assert_false(t.in_bounds(h), str(h))


func test_no_map_bounds_is_unbounded() -> void:
	var t := TerrainMap.from_scenario({})
	assert_false(t.bounded)
	assert_true(t.in_bounds(Vector2i(10000, -10000)))
	assert_true(t.boundaries.is_empty())
	assert_null(t.crossing(Vector2i(0, 0), Vector2i(1, 0)))


func test_edges_default_open() -> void:
	var t := _ten()
	for n in ["N", "E", "S", "W"]:
		assert_eq(t.boundary(n).kind, "open", n)
	assert_eq(t.crossing(Vector2i(0, -5), Vector2i(0, -6)).name, "N")
	assert_eq(t.crossing(Vector2i(4, 0), Vector2i(5, 0)).name, "E")
	assert_eq(t.crossing(Vector2i(-5, 0), Vector2i(-6, 0)).name, "W")
	assert_eq(t.crossing(Vector2i(2, 4), Vector2i(2, 5)).name, "S")
	assert_eq(t.crossing(Vector2i(5, 0), Vector2i(4, 0)).name, "E")
	assert_null(t.crossing(Vector2i(0, 0), Vector2i(1, 0)))


func test_corner_side_belongs_to_row_edge() -> void:
	var t := _ten()
	assert_eq(t.crossing(Vector2i(7, -5), Vector2i(8, -6)).name, "N")
	assert_eq(t.crossing(Vector2i(7, -5), Vector2i(8, -5)).name, "E")


func test_edge_kinds_from_scenario() -> void:
	var t := _ten({"edges": {"W": "escape", "E": "none"}})
	assert_eq(t.boundary("W").kind, "escape")
	assert_eq(t.boundary("E").kind, "none")
	assert_eq(t.boundary("N").kind, "open")
	assert_eq(t.boundary("S").kind, "open")
	assert_eq(t.errors.size(), 0)


func test_land_and_shallow_queries() -> void:
	var t := TerrainMap.from_scenario({"terrain": {
		"land": [[1, 0]],
		"shallow": [{"name": "A", "base": 15, "hexes": [[2, 0], [3, 0]]}],
	}})
	assert_true(t.is_land(Vector2i(1, 0)))
	assert_eq(t.area_at(Vector2i(2, 0)).name, "A")
	assert_null(t.area_at(Vector2i(0, 0)))
	assert_eq(t.depth_range(Vector2i(2, 0)), Vector2i(16, 21))
	assert_eq(t.depth_range(Vector2i(1, 0)), Vector2i(0, 0))
	assert_eq(t.depth_range(Vector2i(0, 0)), Vector2i(-1, -1))
	assert_eq(t.grounds(Vector2i(2, 0), 16), "maybe")
	assert_eq(t.grounds(Vector2i(2, 0), 15), "never")
	assert_eq(t.grounds(Vector2i(2, 0), 21), "always")
	assert_eq(t.grounds(Vector2i(1, 0), 1), "always")
	assert_eq(t.grounds(Vector2i(0, 0), 30), "never")


func test_custom_boundary() -> void:
	var t := TerrainMap.from_scenario({"terrain": {"boundaries": [
		{"name": "boom", "kind": "open", "sides": [[[0, 0], [1, 0]]]}]}})
	var b := t.crossing(Vector2i(1, 0), Vector2i(0, 0))
	assert_eq(b.name, "boom")
	assert_eq(b.kind, "open")
	assert_eq(t.distance_to_boundary(Vector2i(3, 0), "boom"), 2)


func test_validation_errors() -> void:
	var t := _ten({
		"land": [[9, 0], [1, 0]],
		"shallow": [{"name": "A", "base": 5, "hexes": [[1, 0]]},
			{"name": "B", "base": -1, "hexes": [[2, 0]]}],
		"edges": {"X": "open", "N": "wall"},
		"boundaries": [{"name": "bad", "kind": "open", "sides": [[[0, 0], [2, 0]]]}],
	})
	assert_eq(t.errors.size(), 6, str(t.errors))
	var joined := "\n".join(t.errors)
	for part in ["off the map", "both land and shallow", "unknown edge X", "unknown kind wall",
			"base", "not neighbours"]:
		assert_string_contains(joined, part)
	for e in t.errors:
		assert_true(e.begins_with("Terrain: "), e)


func test_inner_none_or_escape_boundary_is_not_supported_yet() -> void:
	for kind in ["none", "escape"]:
		var t := _ten({"boundaries": [{"name": "line", "kind": kind, "sides": [[[0, 0], [1, 0]]]}]})
		assert_eq(t.errors.size(), 1, str(t.errors))
		assert_string_contains("\n".join(t.errors), "not supported yet")
		assert_eq(t.crossing(Vector2i(0, 0), Vector2i(1, 0)).kind, TerrainMap.OPEN, "read as a wall")
	var ok := _ten({"boundaries": [{"name": "line", "kind": "open", "sides": [[[0, 0], [1, 0]]]}]})
	assert_eq(ok.errors.size(), 0, str(ok.errors))


func test_non_integer_base_is_an_error() -> void:
	for base in [5.5, "5"]:
		var t := _ten({"shallow": [{"name": "A", "base": base, "hexes": [[1, 0]]}]})
		assert_eq(t.errors.size(), 1, str(t.errors))
		assert_string_contains("\n".join(t.errors), "non-integer base")
	var ok := _ten({"shallow": [{"name": "A", "base": 5.0, "hexes": [[1, 0]]}]})
	assert_eq(ok.errors.size(), 0, "JSON numbers are floats: 5.0 is an integer")


func test_hex_in_two_shallow_areas_is_an_error() -> void:
	var t := _ten({"shallow": [
		{"name": "A", "base": 5, "hexes": [[1, 0]]},
		{"name": "B", "base": 8, "hexes": [[1, 0]]}]})
	assert_eq(t.errors.size(), 1, str(t.errors))
	assert_string_contains(t.errors[0], "two shallow areas")


func test_of_caches_by_reference() -> void:
	var s := {"map_bounds": {"width": 10, "height": 10}}
	assert_same(TerrainMap.of(s), TerrainMap.of(s))
	assert_not_same(TerrainMap.of(s), TerrainMap.of(s.duplicate(true)))


func test_distance_to_boundary() -> void:
	var t := _ten()
	assert_eq(t.distance_to_boundary(Vector2i(0, 0), "W"), 6)
	assert_eq(t.distance_to_boundary(Vector2i(-5, 0), "W"), 1)
	assert_eq(t.distance_to_boundary(Vector2i(0, 0), "Q"), -1)


func test_existing_scenarios_fit_the_rectangle() -> void:
	var dir := DirAccess.open("res://data/scenarios")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/" + f))
		var t := TerrainMap.of(scenario)
		for ship in scenario.get("ships", []):
			var bow := Vector2i(int(ship["position"]["q"]), int(ship["position"]["r"]))
			var stern := HexGrid.stern_of(bow, int(ship["facing"]))
			assert_true(t.in_bounds(bow), "%s %s bow" % [f, ship["id"]])
			assert_true(t.in_bounds(stern), "%s %s stern" % [f, ship["id"]])
