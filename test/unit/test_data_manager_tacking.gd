extends GutTest
## Tests for DataManager tacking table loading and lookups.
##
## Validates the 2-level lookup: maneuverability → wind_speed index → tacking percent
## Uses the actual tacking_table.json data file for regression testing.

var dm: Node

func before_all() -> void:
	dm = DataManager
	dm.load_tacking_table()

# --- Table Loading ---

func test_tacking_table_loads_successfully() -> void:
	assert_gt(dm.tacking_table.size(), 0, "Tacking table should not be empty after loading")

func test_tacking_table_has_all_maneuverability_grades() -> void:
	for grade in ["a", "b", "c", "d"]:
		assert_true(dm.tacking_table.has(grade), "Table should contain maneuverability '%s'" % grade)

func test_tacking_table_grade_count() -> void:
	assert_eq(dm.tacking_table.size(), 4, "Should have exactly 4 maneuverability grades")

func test_tacking_table_arrays_have_4_elements() -> void:
	for grade in ["a", "b", "c", "d"]:
		var arr = dm.tacking_table[grade]
		assert_eq(arr.size(), 4, "Maneuverability '%s' should have 4 wind speed entries" % grade)

# --- Known Value Lookups (regression anchors from tacking_table.json) ---

func test_lookup_a_ws1() -> void:
	assert_almost_eq(dm.get_tacking_percent("a", 1), 0.2, 0.001)

func test_lookup_a_ws2() -> void:
	assert_almost_eq(dm.get_tacking_percent("a", 2), 0.4, 0.001)

func test_lookup_a_ws3() -> void:
	assert_almost_eq(dm.get_tacking_percent("a", 3), 0.6, 0.001)

func test_lookup_a_ws4() -> void:
	assert_almost_eq(dm.get_tacking_percent("a", 4), 0.5, 0.001)

func test_lookup_b_ws1() -> void:
	assert_almost_eq(dm.get_tacking_percent("b", 1), 0.3, 0.001)

func test_lookup_b_ws2() -> void:
	assert_almost_eq(dm.get_tacking_percent("b", 2), 0.5, 0.001)

func test_lookup_b_ws3() -> void:
	assert_almost_eq(dm.get_tacking_percent("b", 3), 0.7, 0.001)

func test_lookup_b_ws4() -> void:
	assert_almost_eq(dm.get_tacking_percent("b", 4), 0.6, 0.001)

func test_lookup_c_ws1() -> void:
	assert_almost_eq(dm.get_tacking_percent("c", 1), 0.5, 0.001)

func test_lookup_c_ws2() -> void:
	assert_almost_eq(dm.get_tacking_percent("c", 2), 0.7, 0.001)

func test_lookup_c_ws3() -> void:
	assert_almost_eq(dm.get_tacking_percent("c", 3), 0.8, 0.001)

func test_lookup_c_ws4() -> void:
	assert_almost_eq(dm.get_tacking_percent("c", 4), 0.7, 0.001)

func test_lookup_d_ws1() -> void:
	assert_almost_eq(dm.get_tacking_percent("d", 1), 0.7, 0.001)

func test_lookup_d_ws2() -> void:
	assert_almost_eq(dm.get_tacking_percent("d", 2), 0.8, 0.001)

func test_lookup_d_ws3() -> void:
	assert_almost_eq(dm.get_tacking_percent("d", 3), 0.9, 0.001)

func test_lookup_d_ws4() -> void:
	assert_almost_eq(dm.get_tacking_percent("d", 4), 0.8, 0.001)

# --- Wind Speed 0 Returns 0.0 ---

func test_wind_speed_zero_returns_zero() -> void:
	for grade in ["a", "b", "c", "d"]:
		assert_almost_eq(dm.get_tacking_percent(grade, 0), 0.0, 0.001,
			"Wind speed 0 should return 0.0 for maneuverability '%s'" % grade)

# --- Case Insensitivity for Maneuverability ---

func test_maneuverability_uppercase() -> void:
	var lower = dm.get_tacking_percent("a", 2)
	var upper = dm.get_tacking_percent("A", 2)
	assert_almost_eq(lower, upper, 0.001, "Maneuverability lookup should be case-insensitive")

func test_maneuverability_uppercase_b() -> void:
	assert_almost_eq(dm.get_tacking_percent("B", 3), 0.7, 0.001, "Uppercase 'B' should work")

func test_maneuverability_uppercase_c() -> void:
	assert_almost_eq(dm.get_tacking_percent("C", 1), 0.5, 0.001, "Uppercase 'C' should work")

func test_maneuverability_uppercase_d() -> void:
	assert_almost_eq(dm.get_tacking_percent("D", 4), 0.8, 0.001, "Uppercase 'D' should work")

# --- Game Balance Sanity Checks ---

func test_worse_maneuverability_higher_tacking_percent() -> void:
	for ws in [1, 2, 3, 4]:
		var pct_a = dm.get_tacking_percent("a", ws)
		var pct_d = dm.get_tacking_percent("d", ws)
		assert_true(pct_d >= pct_a,
			"Worse maneuverability (d) should have >= tacking percent than (a) at wind speed %d" % ws)

func test_all_values_between_zero_and_one() -> void:
	for grade in ["a", "b", "c", "d"]:
		for ws in [1, 2, 3, 4]:
			var pct = dm.get_tacking_percent(grade, ws)
			assert_true(pct >= 0.0 and pct <= 1.0,
				"Tacking percent for '%s' ws%d should be between 0.0 and 1.0, got %f" % [grade, ws, pct])

# --- Return Type ---

func test_return_type_is_float() -> void:
	var result = dm.get_tacking_percent("a", 1)
	assert_typeof(result, TYPE_FLOAT, "get_tacking_percent should return a float")
