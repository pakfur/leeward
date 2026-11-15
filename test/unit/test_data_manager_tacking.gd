extends GutTest
## Tests for DataManager tacking table loading and lookups.
##
## tacking_table.json is the TACKING (d10) chart (docs/combat_tables_1.jpeg):
## maneuverability -> highest d10 roll (0-9) that succeeds at wind speed 1-4.

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

# --- Chart values (every cell of the printed table) ---

func test_chart_numbers() -> void:
	var chart := {
		"a": [2, 4, 6, 5],
		"b": [3, 5, 7, 6],
		"c": [5, 7, 8, 7],
		"d": [7, 8, 9, 8],
	}
	for grade in chart:
		for ws in [1, 2, 3, 4]:
			assert_eq(dm.get_tacking_number(grade, ws), chart[grade][ws - 1],
				"Tacking %s at WS %d" % [grade, ws])

func test_no_turning_in_calm() -> void:
	for grade in ["a", "b", "c", "d"]:
		assert_eq(dm.get_tacking_number(grade, 0), -1, "WS 0: no turn possible (5.D.1a)")
		assert_almost_eq(dm.get_tacking_percent(grade, 0), 0.0, 0.001)

func test_maneuverability_case_insensitive() -> void:
	assert_eq(dm.get_tacking_number("B", 3), dm.get_tacking_number("b", 3))

# --- Base chance for display ---

func test_percent_is_number_plus_one_tenths() -> void:
	# The rulebook example (5.D.3): type A at WS 3 is "<6 on a d10, or 70%"
	assert_almost_eq(dm.get_tacking_percent("a", 3), 0.7, 0.001)
	assert_almost_eq(dm.get_tacking_percent("d", 3), 1.0, 0.001, "<=9 always succeeds before DRMs")

func test_better_maneuverability_tacks_more_easily() -> void:
	for ws in [1, 2, 3, 4]:
		assert_true(dm.get_tacking_number("d", ws) >= dm.get_tacking_number("a", ws),
			"Type d should be at least as good as type a at WS %d" % ws)
