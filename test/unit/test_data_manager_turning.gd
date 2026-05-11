extends GutTest
## Tests for DataManager turning table loading and lookups.
##
## Validates the 3-level nested lookup: direction → speed → maneuverability → min hexes
## Uses the actual turning_table.json data file for regression testing.

var dm: Node

func before_all() -> void:
	dm = DataManager
	dm.load_turning_table()

# --- Table Loading ---

func test_turning_table_loads_successfully() -> void:
	assert_gt(dm.turning_table.size(), 0, "Turning table should not be empty after loading")

func test_turning_table_has_both_directions() -> void:
	assert_true(dm.turning_table.has("same_direction"), "Table should contain 'same_direction'")
	assert_true(dm.turning_table.has("opposite_direction"), "Table should contain 'opposite_direction'")

func test_turning_table_has_speeds_1_through_10() -> void:
	for direction in ["same_direction", "opposite_direction"]:
		var speed_dict = dm.turning_table[direction]
		for s in range(1, 11):
			assert_true(speed_dict.has(str(s)), "Direction '%s' should have speed '%d'" % [direction, s])

func test_turning_table_has_all_maneuverability_grades() -> void:
	var grades = ["a", "b", "c", "d"]
	for direction in ["same_direction", "opposite_direction"]:
		for s in range(1, 11):
			var m_dict = dm.turning_table[direction][str(s)]
			for grade in grades:
				assert_true(m_dict.has(grade), "Direction '%s' speed %d should have maneuverability '%s'" % [direction, s, grade])

# --- Known Value Lookups: same_direction (regression anchors) ---

func test_same_dir_speed1_a() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 1, "a"), 1)

func test_same_dir_speed1_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 1, "d"), 1)

func test_same_dir_speed3_a() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 3, "a"), 2)

func test_same_dir_speed3_b() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 3, "b"), 1)

func test_same_dir_speed4_b() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 4, "b"), 2)

func test_same_dir_speed6_a() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 6, "a"), 3)

func test_same_dir_speed6_c() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 6, "c"), 2)

func test_same_dir_speed6_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 6, "d"), 1)

func test_same_dir_speed8_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 8, "d"), 2)

func test_same_dir_speed10_a() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 10, "a"), 3)

func test_same_dir_speed10_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 10, "d"), 2)

# --- Known Value Lookups: opposite_direction (regression anchors) ---

func test_opp_dir_speed1_a() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 1, "a"), 1)

func test_opp_dir_speed5_a() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 5, "a"), 1)

func test_opp_dir_speed5_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 5, "d"), 1)

func test_opp_dir_speed6_a() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 6, "a"), 2)

func test_opp_dir_speed6_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 6, "d"), 1)

func test_opp_dir_speed8_a() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 8, "a"), 3)

func test_opp_dir_speed8_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 8, "d"), 2)

func test_opp_dir_speed10_b() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 10, "b"), 3)

func test_opp_dir_speed10_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 10, "d"), 2)

# --- Ship Speed <= 0 Returns -1 ---

func test_speed_zero_returns_negative_one() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 0, "a"), -1)

func test_speed_negative_returns_negative_one() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", -1, "b"), -1)

func test_speed_negative_large_returns_negative_one() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", -100, "c"), -1)

# --- Case Insensitivity for Maneuverability ---

func test_maneuverability_uppercase() -> void:
	var lower = dm.get_min_heading_change_movement_required("same_direction", 6, "a")
	var upper = dm.get_min_heading_change_movement_required("same_direction", 6, "A")
	assert_eq(lower, upper, "Maneuverability lookup should be case-insensitive")

func test_maneuverability_uppercase_b() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("opposite_direction", 8, "B"), 3)

func test_maneuverability_uppercase_c() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 6, "C"), 2)

func test_maneuverability_uppercase_d() -> void:
	assert_eq(dm.get_min_heading_change_movement_required("same_direction", 10, "D"), 2)

# --- Game Balance Sanity Checks ---

func test_same_direction_gte_opposite_direction() -> void:
	for s in range(1, 11):
		for grade in ["a", "b", "c", "d"]:
			var same = dm.get_min_heading_change_movement_required("same_direction", s, grade)
			var opp = dm.get_min_heading_change_movement_required("opposite_direction", s, grade)
			assert_true(same >= opp,
				"same_direction should require >= hexes than opposite_direction at speed %d grade '%s'" % [s, grade])

func test_higher_speed_requires_at_least_as_many_hexes() -> void:
	for direction in ["same_direction", "opposite_direction"]:
		for grade in ["a", "b", "c", "d"]:
			var prev = dm.get_min_heading_change_movement_required(direction, 1, grade)
			for s in range(2, 11):
				var curr = dm.get_min_heading_change_movement_required(direction, s, grade)
				assert_true(curr >= prev,
					"Speed %d should require >= hexes than speed %d for %s grade '%s'" % [s, s - 1, direction, grade])
				prev = curr

func test_better_maneuverability_requires_at_most_as_many_hexes() -> void:
	# d is best maneuverability, a is worst — d should require <= a
	for direction in ["same_direction", "opposite_direction"]:
		for s in range(1, 11):
			var val_a = dm.get_min_heading_change_movement_required(direction, s, "a")
			var val_d = dm.get_min_heading_change_movement_required(direction, s, "d")
			assert_true(val_d <= val_a,
				"Better maneuverability (d) should require <= hexes than (a) at speed %d %s" % [s, direction])

func test_all_values_at_least_one() -> void:
	for direction in ["same_direction", "opposite_direction"]:
		for s in range(1, 11):
			for grade in ["a", "b", "c", "d"]:
				var val = dm.get_min_heading_change_movement_required(direction, s, grade)
				assert_true(val >= 1, "Min hexes should be >= 1 for %s speed %d grade '%s', got %d" % [direction, s, grade, val])
