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

func _edge_offset(direction: int) -> Vector3:
	return hex_grid.axial_to_edge_world(0, 0, direction) - hex_grid.axial_to_world(0, 0)

func test_windward_quarter_wind_sits_on_the_stern_face() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 4, 2, hex_grid)  # wind from NW(4), on the port quarter
	var stern := HexGrid.stern_of(Vector2i(0, 0), 0)
	var expected: Vector3 = hex_grid.axial_to_edge_world(stern.x, stern.y, 4)
	assert_almost_eq(m.windward_anchor.x, expected.x, 0.001, "the stern hex's NW face")
	assert_almost_eq(m.windward_anchor.z, expected.z, 0.001)
	assert_true(m.windward_visible)


func test_windward_bow_quarter_wind_sits_on_the_bow_face() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 1, 2, hex_grid)  # wind from SE(1), forward of the beam
	var expected: Vector3 = hex_grid.axial_to_edge_world(0, 0, 1)
	assert_almost_eq(m.windward_anchor.x, expected.x, 0.001, "the bow hex's SE face")
	assert_almost_eq(m.windward_anchor.z, expected.z, 0.001)


func test_windward_anchor_is_on_a_face_normal_to_the_wind() -> void:
	# For every facing and wind: the anchor is the midpoint of an outer face of the footprint whose
	# normal is windward_dir (the wind direction), on the more windward of the two hexes.
	for facing in 6:
		var bow := Vector2i(2, 1)
		var stern := HexGrid.stern_of(bow, facing)
		for wind in 6:
			var m = Model.build_selected(bow, facing, 3, wind, 2, hex_grid)
			var label := "facing %d, wind %d" % [facing, wind]
			var wind_dir: Vector3 = (hex_grid.axial_to_edge_world(0, 0, wind) - hex_grid.axial_to_world(0, 0)).normalized()
			assert_almost_eq(m.windward_dir.x, wind_dir.x, 0.001, label)
			assert_almost_eq(m.windward_dir.z, wind_dir.z, 0.001, label)
			var bow_face: Vector3 = hex_grid.axial_to_edge_world(bow.x, bow.y, wind)
			var stern_face: Vector3 = hex_grid.axial_to_edge_world(stern.x, stern.y, wind)
			var windward_face: Vector3 = bow_face if bow_face.dot(wind_dir) > stern_face.dot(wind_dir) else stern_face
			assert_almost_eq(m.windward_anchor.x, windward_face.x, 0.001, label)
			assert_almost_eq(m.windward_anchor.z, windward_face.z, 0.001, label)
			var owner: Vector2i = bow if windward_face == bow_face else stern
			var outside: Vector2i = hex_grid.get_neighbor(owner.x, owner.y, wind)
			assert_false(outside in [bow, stern], label + ": an outer face")


func test_windward_from_astern_sits_on_the_stern_face() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 3, 2, hex_grid)  # wind from W(3), dead astern
	var stern := HexGrid.stern_of(Vector2i(0, 0), 0)
	var expected: Vector3 = hex_grid.axial_to_edge_world(stern.x, stern.y, 3)
	assert_almost_eq(m.windward_anchor.x, expected.x, 0.001, "the stern hex's outer face")
	assert_almost_eq(m.windward_anchor.z, expected.z, 0.001)

func test_windward_from_ahead_sits_on_the_bow_face() -> void:
	var m = Model.build_selected(Vector2i(2, 1), 0, 3, 0, 2, hex_grid)  # wind from E(0), dead ahead
	var expected: Vector3 = hex_grid.axial_to_edge_world(2, 1, 0)
	assert_almost_eq(m.windward_anchor.x, expected.x, 0.001)
	assert_almost_eq(m.windward_anchor.z, expected.z, 0.001)

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

func test_direction_dir_is_outward_unit_vector() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 4, 2, hex_grid)  # facing E(0)
	assert_almost_eq(m.direction_dir.length(), 1.0, 0.001)
	var expected = (hex_grid.axial_to_edge_world(0, 0, 0) - hex_grid.axial_to_world(0, 0)).normalized()
	assert_almost_eq(m.direction_dir.x, expected.x, 0.001)
	assert_almost_eq(m.direction_dir.z, expected.z, 0.001)

func test_windward_dir_is_outward_unit_vector() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 4, 2, hex_grid)  # wind from NW(4)
	assert_almost_eq(m.windward_dir.length(), 1.0, 0.001)
	var expected = (hex_grid.axial_to_edge_world(0, 0, 4) - hex_grid.axial_to_world(0, 0)).normalized()
	assert_almost_eq(m.windward_dir.x, expected.x, 0.001)
	assert_almost_eq(m.windward_dir.z, expected.z, 0.001)

func test_model_carries_facing_and_the_six_neighbour_centres() -> void:
	var m = Model.build_selected(Vector2i(2, 1), 4, 3, 0, 2, hex_grid)
	assert_eq(m.heading, 4)
	assert_eq(m.neighbor_anchors.size(), 6)
	for d in range(6):
		var n := hex_grid.get_neighbor(2, 1, d)
		assert_eq(m.neighbor_anchors[d], hex_grid.axial_to_world(n.x, n.y))
