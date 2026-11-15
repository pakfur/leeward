extends GutTest
## Tests for the two-hex ship footprint helpers and shared occupancy.

func before_all() -> void:
	DataManager.load_ship_definitions()


func _make(id: String, bow: Vector2i, facing: int) -> ShipState:
	var data := {
		"id": id, "player_id": 1, "ship_type": "frigate_38", "ship_name": id,
		"position": {"q": bow.x, "r": bow.y}, "facing": facing,
		"sail_state": "MS", "crew_quality": "B", "crew_morale": 4,
	}
	var ship_ref := Ship.initialize_from_scenario(data, DataManager.get_ship_definition("frigate_38").to_dict())
	var s := ShipState.new()
	s.initialize_from_scenario(data, ship_ref)
	return s


func test_stern_is_behind_bow() -> void:
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 0), Vector2i(4, 5))
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 1), Vector2i(5, 4))
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 4), Vector2i(5, 6))


func test_occupied_hexes_bow_first() -> void:
	var ss := _make("a", Vector2i(5, 5), 0)
	assert_eq(ss.stern_hex(), Vector2i(4, 5))
	assert_eq(ss.occupied_hexes(), [Vector2i(5, 5), Vector2i(4, 5)])


func test_center_is_midpoint() -> void:
	var grid := HexGrid.new()
	var expected := (grid.axial_to_world(0, 0) + grid.axial_to_world(-1, 0)) / 2.0
	assert_eq(grid.ship_center_world(Vector2i(0, 0), 0), expected)


func test_occupancy_maps_both_hexes() -> void:
	var ships: Array[ShipState] = [_make("a", Vector2i(5, 5), 0), _make("b", Vector2i(2, 2), 1)]
	var occ := Occupancy.build(ships)
	assert_eq(occ.size(), 4)
	assert_eq(occ[Vector2i(5, 5)], "a")
	assert_eq(occ[Vector2i(4, 5)], "a")
	assert_eq(occ[Vector2i(2, 2)], "b")
	assert_eq(occ[Vector2i(2, 1)], "b")


func test_occupancy_excludes() -> void:
	var ships: Array[ShipState] = [_make("a", Vector2i(5, 5), 0), _make("b", Vector2i(2, 2), 1)]
	var occ := Occupancy.build(ships, ["a"])
	assert_eq(occ.size(), 2)
	assert_false(occ.has(Vector2i(5, 5)))
	assert_eq(occ[Vector2i(2, 2)], "b")


func test_from_positions() -> void:
	var occ := Occupancy.from_positions({"a": Vector2i(5, 5), "b": Vector2i(2, 2)}, {"a": 0, "b": 1}, ["b"])
	assert_eq(occ.size(), 2)
	assert_eq(occ[Vector2i(4, 5)], "a")


func test_overlap_detected() -> void:
	var ships: Array[ShipState] = [_make("a", Vector2i(5, 5), 0), _make("b", Vector2i(4, 5), 1)]
	var ids := Occupancy.overlapping_ids(ships)
	ids.sort()
	assert_eq(ids, ["a", "b"] as Array[String])


func test_no_overlap() -> void:
	var ships: Array[ShipState] = [_make("a", Vector2i(5, 5), 0), _make("b", Vector2i(2, 2), 1)]
	assert_eq(Occupancy.overlapping_ids(ships).size(), 0)


func test_scenario_without_map_bounds_is_unbounded() -> void:
	# Test mocks rely on this: an empty active_scenario leaves every hex on the map.
	for hex in [Vector2i(0, 0), Vector2i(-500, 0), Vector2i(0, 900), Vector2i(10000, -10000)]:
		assert_true(Occupancy.in_bounds(hex, {}), "No scenario: %s is in bounds" % hex)
		assert_true(Occupancy.in_bounds(hex, {"name": "no bounds"}), "No map_bounds: %s is in bounds" % hex)
	assert_false(Occupancy.in_bounds(Vector2i(5, 0), {"map_bounds": {"width": 10, "height": 10}}),
		"With map_bounds the edge applies (q -5..4)")
