extends GutTest
## Tests for DataManager bearing-off table loading and lookups.
##
## bearing_off_table.json is the BEARING OFF (d10) chart (docs/combat_tables_1.jpeg):
## crew quality (A..G) -> maneuverability (a..d) -> highest d10 roll (0-9) that succeeds, null = NA.

var dm: Node

func before_all() -> void:
	dm = DataManager
	dm.load_bearing_off_table()

# --- Table Loading ---

func test_bearing_off_table_has_all_crew_quality_grades() -> void:
	for grade in ["A", "B", "C", "D", "E", "F", "G"]:
		assert_true(dm.bearing_off_table.has(grade), "Table should contain crew_quality '%s'" % grade)

# --- Chart values (every cell of the printed table; -1 = NA) ---

func test_chart_numbers() -> void:
	var chart := {
		"A": [4, 5, 6, 7],
		"B": [3, 4, 5, 6],
		"C": [2, 3, 4, 5],
		"D": [1, 2, 3, 4],
		"E": [0, 1, 2, 3],
		"F": [-1, 0, 1, 2],
		"G": [-1, -1, 0, 1],
	}
	var types := ["a", "b", "c", "d"]
	for cq in chart:
		for i in range(4):
			assert_eq(dm.get_bearing_off_number(cq, types[i]), chart[cq][i],
				"Bearing off CQ %s / type %s" % [cq, types[i]])

func test_lookup_case_insensitive() -> void:
	assert_eq(dm.get_bearing_off_number("c", "B"), dm.get_bearing_off_number("C", "b"))

func test_better_crew_never_worse() -> void:
	for m in ["a", "b", "c", "d"]:
		var prev := -2
		for cq in ["G", "F", "E", "D", "C", "B", "A"]:
			var n: int = dm.get_bearing_off_number(cq, m)
			assert_true(n >= prev, "CQ %s / %s should be at least as good as the worse crew" % [cq, m])
			prev = n
