extends GutTest
## Tests for DataManager speed change table loading and lookups.
##
## Validates the 2-level nested lookup: change_type → maneuverability → cost
## Uses the actual speed_change_table.json data file for regression testing.

var dm: Node

func before_all() -> void:
	dm = DataManager
	dm.load_speed_change_table()

# --- Table Loading ---

func test_speed_change_table_loads_successfully() -> void:
	assert_gt(dm.speed_change_table.size(), 0, "Speed change table should not be empty after loading")

func test_speed_change_table_has_both_change_types() -> void:
	assert_true(dm.speed_change_table.has("acceleration"), "Table should contain 'acceleration'")
	assert_true(dm.speed_change_table.has("deceleration"), "Table should contain 'deceleration'")

func test_speed_change_table_change_type_count() -> void:
	assert_eq(dm.speed_change_table.size(), 2, "Should have exactly 2 change types")

func test_speed_change_table_has_all_maneuverability_grades() -> void:
	var expected_grades = ["a", "b", "c", "d"]
	for change_type in ["acceleration", "deceleration"]:
		var grades_dict = dm.speed_change_table[change_type]
		for grade in expected_grades:
			assert_true(grades_dict.has(grade), "Change type '%s' should have maneuverability '%s'" % [change_type, grade])

# --- Known Value Lookups (regression anchors from speed_change_table.json) ---

func test_lookup_acceleration_a() -> void:
	assert_eq(dm.get_speed_change("acceleration", "a"), 2)

func test_lookup_acceleration_b() -> void:
	assert_eq(dm.get_speed_change("acceleration", "b"), 2)

func test_lookup_acceleration_c() -> void:
	assert_eq(dm.get_speed_change("acceleration", "c"), 3)

func test_lookup_acceleration_d() -> void:
	assert_eq(dm.get_speed_change("acceleration", "d"), 3)

func test_lookup_deceleration_a() -> void:
	assert_eq(dm.get_speed_change("deceleration", "a"), 2)

func test_lookup_deceleration_b() -> void:
	assert_eq(dm.get_speed_change("deceleration", "b"), 3)

func test_lookup_deceleration_c() -> void:
	assert_eq(dm.get_speed_change("deceleration", "c"), 3)

func test_lookup_deceleration_d() -> void:
	assert_eq(dm.get_speed_change("deceleration", "d"), 4)

# --- Case Insensitivity for Maneuverability ---

func test_maneuverability_uppercase_converted_to_lowercase() -> void:
	var lower = dm.get_speed_change("acceleration", "a")
	var upper = dm.get_speed_change("acceleration", "A")
	assert_eq(lower, upper, "Maneuverability lookup should be case-insensitive")

func test_maneuverability_mixed_case_deceleration() -> void:
	assert_eq(dm.get_speed_change("deceleration", "B"), 3, "Uppercase 'B' should work for deceleration")

func test_maneuverability_all_uppercase() -> void:
	assert_eq(dm.get_speed_change("acceleration", "C"), 3, "Uppercase 'C' should work for acceleration")

func test_maneuverability_uppercase_d() -> void:
	assert_eq(dm.get_speed_change("deceleration", "D"), 4, "Uppercase 'D' should work for deceleration")

# --- Game Balance Sanity Checks ---

func test_deceleration_cost_gte_acceleration_cost() -> void:
	for grade in ["a", "b", "c", "d"]:
		var accel = dm.get_speed_change("acceleration", grade)
		var decel = dm.get_speed_change("deceleration", grade)
		assert_true(decel >= accel, "Deceleration cost should be >= acceleration cost for grade '%s'" % grade)

func test_worse_maneuverability_costs_at_least_as_much() -> void:
	var accel_a = dm.get_speed_change("acceleration", "a")
	var accel_d = dm.get_speed_change("acceleration", "d")
	assert_true(accel_d >= accel_a, "Worse maneuverability (d) should cost >= better (a) for acceleration")

	var decel_a = dm.get_speed_change("deceleration", "a")
	var decel_d = dm.get_speed_change("deceleration", "d")
	assert_true(decel_d >= decel_a, "Worse maneuverability (d) should cost >= better (a) for deceleration")
