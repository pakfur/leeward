extends GutTest
## AnchorMarkers (the anchors and cables on the map) and the ANCHORED card badge: presentation only.

var grid: HexGrid


func before_each() -> void:
	grid = HexGrid.new()


func _ship(id: String, bow: Vector2i, facing: int = 0) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.new()
	s.ship.ship_id = id
	s.hex_position = bow
	s.facing = facing
	return s


func _anchored(id: String, bow: Vector2i, anchor_hex: Vector2i, end: String = "bow") -> ShipState:
	var s := _ship(id, bow)
	s.anchor = {"hex": anchor_hex, "end": end, "cable": 1}
	return s


func test_markers_for_anchored_ships_only() -> void:
	var a := _anchored("a", Vector2i(5, 5), Vector2i(6, 5))
	var b := _ship("b", Vector2i(2, 2))
	var c := _anchored("c", Vector2i(8, 8), Vector2i(9, 8))
	c.removed_from_map = true
	var markers := AnchorMarkers.markers([c, b, a], grid)
	assert_eq(markers.size(), 1)
	assert_eq(markers[0]["ship_id"], "a")
	var want := grid.axial_to_world(6, 5)
	assert_almost_eq(markers[0]["anchor"].x, want.x, 0.001)
	assert_almost_eq(markers[0]["anchor"].z, want.z, 0.001)
	var bow := grid.axial_to_world(5, 5)
	assert_almost_eq(markers[0]["end"].x, bow.x, 0.001)
	assert_almost_eq(markers[0]["end"].z, bow.z, 0.001)


func test_marker_end_is_stern_when_anchored_by_the_stern() -> void:
	var a := _anchored("a", Vector2i(5, 5), Vector2i(3, 5), "stern")
	var markers := AnchorMarkers.markers([a], grid)
	var stern := grid.axial_to_world(a.stern_hex().x, a.stern_hex().y)
	assert_almost_eq(markers[0]["end"].x, stern.x, 0.001)


func test_refresh_builds_children() -> void:
	var node := AnchorMarkers.new()
	add_child_autofree(node)
	node.refresh([_anchored("a", Vector2i(5, 5), Vector2i(6, 5))], grid)
	assert_gte(node.get_child_count(), 2)
	node.refresh([_ship("b", Vector2i(2, 2))], grid)
	await get_tree().process_frame
	assert_eq(node.get_child_count(), 0)


func test_anchored_badge() -> void:
	var s := _anchored("a", Vector2i(5, 5), Vector2i(6, 5))
	assert_eq(PlanningSailUi.status_badge(s), "ANCHORED")
	assert_false(PlanningSailUi.can_plot_movement(s))
	assert_true(PlanningSailUi.movement_block_reason(s).contains("13.C.3"))
	s.aground = true
	assert_eq(PlanningSailUi.status_badge(s), "AGROUND")
