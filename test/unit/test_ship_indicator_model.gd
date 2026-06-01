extends GutTest

const Model = preload("res://scripts/view/ship_indicator_model.gd")

var hex_grid: HexGrid

func before_each() -> void:
	hex_grid = HexGrid.new(1.0)

func test_point_of_sail_mapping() -> void:
	assert_eq(Model.point_of_sail_label("L"), "In Irons")
	assert_eq(Model.point_of_sail_label("C"), "Close Hauled")
	assert_eq(Model.point_of_sail_label("B"), "Broad Reach")
	assert_eq(Model.point_of_sail_label("R"), "Running")
	assert_eq(Model.point_of_sail_label("?"), "")

func test_clamp_scale_bounds() -> void:
	assert_eq(Model.clamp_scale(1.0, 0.1, 0.5, 2.0), 0.5)    # below min -> min
	assert_eq(Model.clamp_scale(100.0, 0.1, 0.5, 2.0), 2.0)  # above max -> max
	assert_almost_eq(Model.clamp_scale(10.0, 0.1, 0.5, 2.0), 1.0, 0.0001)

func test_windward_hidden_when_calm() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 2, 0, hex_grid)
	assert_false(m.windward_visible)

func test_windward_face_is_wind_direction() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 4, 2, hex_grid)  # wind from NW(4)
	assert_eq(m.windward_anchor, hex_grid.axial_to_edge_world(0, 0, 4))
	assert_true(m.windward_visible)

func test_direction_face_is_facing_when_selected() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 1, 3, 4, 2, hex_grid)  # facing SE(1)
	assert_eq(m.direction_anchor, hex_grid.axial_to_edge_world(0, 0, 1))

func test_hover_uses_resulting_facing_and_constant_speed() -> void:
	var m = Model.build_hover(Vector2i(2, -1), 5, 4, 0, 2, hex_grid)  # resulting facing NE(5)
	assert_eq(m.direction_anchor, hex_grid.axial_to_edge_world(2, -1, 5))
	assert_eq(m.speed, 4)
	assert_almost_eq(m.opacity, 0.6, 0.001)

func test_point_of_sail_in_irons_when_facing_into_wind() -> void:
	# facing == wind_direction -> relative 0 -> "L" -> In Irons
	var m = Model.build_selected(Vector2i(0, 0), 2, 3, 2, 2, hex_grid)
	assert_eq(m.point_of_sail, "In Irons")

func test_center_anchor_is_hex_center() -> void:
	var m = Model.build_selected(Vector2i(3, -2), 0, 1, 0, 2, hex_grid)
	assert_eq(m.center_anchor, hex_grid.axial_to_world(3, -2))
