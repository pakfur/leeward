extends GutTest
## Tests for FireGeometry: broadside arcs, rake wedges, line of sight.

var grid: HexGrid
var geo: FireGeometry


func before_each() -> void:
	grid = HexGrid.new()
	geo = FireGeometry.new(grid)


func _n(d: int) -> Vector2i:
	return HexGrid.DIRECTIONS[d]


func _steps(d: int, count: int) -> Vector2i:
	return HexGrid.DIRECTIONS[d] * count


# --- bearing_side ---

func test_bearing_side_starboard_neighbours() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(1)), ShipState.STARBOARD)
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(2)), ShipState.STARBOARD)


func test_bearing_side_port_neighbours() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(5)), ShipState.PORT)
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(4)), ShipState.PORT)


func test_bearing_side_bow_and_stern_are_neither() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(0)), -1)
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(3)), -1)


func test_bearing_side_three_steps_along_direction_1() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _steps(1, 3)), ShipState.STARBOARD)


func test_bearing_side_due_beam_range_two() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(1) + _n(2)), ShipState.STARBOARD)


func test_bearing_side_thirty_degrees_off_bow_is_neither() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(0) + _n(1)), -1)


func test_bearing_side_facing_three() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 3, _n(4)), ShipState.STARBOARD)


# --- rake_type ---

func test_rake_stern() -> void:
	assert_eq(geo.rake_type(Vector2i.ZERO, 0, _n(3)), "stern")


func test_rake_bow() -> void:
	assert_eq(geo.rake_type(Vector2i.ZERO, 0, _steps(0, 2)), "bow")


func test_rake_beam_is_none() -> void:
	assert_eq(geo.rake_type(Vector2i.ZERO, 0, _n(2)), "")


func test_rake_exactly_150_degrees_is_none() -> void:
	assert_eq(geo.rake_type(Vector2i.ZERO, 0, _n(3) + _n(2)), "")


func test_rake_inside_stern_wedge() -> void:
	assert_eq(geo.rake_type(Vector2i.ZERO, 0, _steps(3, 3) + _n(2)), "stern")


# --- line of sight ---

func test_los_clear() -> void:
	assert_true(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), {}))


func test_los_blocked_by_intermediate() -> void:
	assert_false(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), {Vector2i(2, 0): true}))


func test_los_endpoints_do_not_block() -> void:
	var occ := {Vector2i(0, 0): true, Vector2i(4, 0): true}
	assert_true(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), occ))


func test_los_edge_case_one_side_occupied_is_clear() -> void:
	assert_true(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 1), {Vector2i(1, 0): true}))


func test_los_edge_case_both_sides_occupied_is_blocked() -> void:
	var occ := {Vector2i(1, 0): true, Vector2i(0, 1): true}
	assert_false(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 1), occ))


# --- broadside_hexes ---

func test_broadside_hexes_starboard_range_two() -> void:
	var hexes := geo.broadside_hexes(Vector2i.ZERO, 0, ShipState.STARBOARD, 2)
	assert_true(hexes.has(_n(1)))
	assert_true(hexes.has(_n(2)))
	assert_true(hexes.has(_n(1) + _n(2)))
	for h in hexes:
		assert_eq(geo.bearing_side(Vector2i.ZERO, 0, h), ShipState.STARBOARD, "hex %s" % h)
		assert_true(grid.hex_distance(0, 0, h.x, h.y) <= 2)
