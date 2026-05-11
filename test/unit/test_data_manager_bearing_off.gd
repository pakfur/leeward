extends GutTest
## Tests for DataManager bearing-off probability table loading and lookups.
##
## Validates the 2-level nested lookup: crew_quality (A..G) → maneuverability (a..d) → float.
## Uses the actual bearing_off_table.json data file for regression testing.
## Derivation reference: Close Action rules VI.D.2 (see _doc field in the JSON).

var dm: Node

func before_all() -> void:
	dm = DataManager
	dm.load_bearing_off_table()

# --- Table Loading ---

func test_bearing_off_table_loads_successfully() -> void:
	assert_gt(dm.bearing_off_table.size(), 0, "Bearing off table should not be empty after loading")

func test_bearing_off_table_has_all_crew_quality_grades() -> void:
	var expected_grades = ["A", "B", "C", "D", "E", "F", "G"]
	for grade in expected_grades:
		assert_true(dm.bearing_off_table.has(grade), "Table should contain crew_quality '%s'" % grade)

func test_bearing_off_table_has_all_maneuverability_grades() -> void:
	var expected_maneuverabilities = ["a", "b", "c", "d"]
	for cq in ["A", "B", "C", "D", "E", "F", "G"]:
		var maneuverability_dict = dm.bearing_off_table[cq]
		for m in expected_maneuverabilities:
			assert_true(maneuverability_dict.has(m), "Crew quality '%s' should have maneuverability '%s'" % [cq, m])

# --- Known Value Lookups (regression anchors from bearing_off_table.json) ---

func test_lookup_A_a_is_5_of_6() -> void:
	# SK=1, class1 DRM=-1 → target=2 → need 2..6 → 5/6
	assert_almost_eq(dm.get_bearing_off_probability("A", "a"), 5.0 / 6.0, 0.0001)

func test_lookup_C_b_is_4_of_6() -> void:
	# SK=3, class2 DRM=0 → target=3 → need 3..6 → 4/6
	assert_almost_eq(dm.get_bearing_off_probability("C", "b"), 4.0 / 6.0, 0.0001)

func test_lookup_E_a_is_1_of_6() -> void:
	# SK=5, class1 DRM=-1 → target=6 → need 6 → 1/6
	assert_almost_eq(dm.get_bearing_off_probability("E", "a"), 1.0 / 6.0, 0.0001)

func test_lookup_G_a_is_zero() -> void:
	# SK=7, class1 DRM=-1 → target=8 → impossible → 0.0
	assert_eq(dm.get_bearing_off_probability("G", "a"), 0.0)

func test_lookup_A_d_is_one() -> void:
	# SK=1, class4 DRM=+2 → target=-1 → auto-success → 1.0
	assert_eq(dm.get_bearing_off_probability("A", "d"), 1.0)

# --- Case Insensitivity ---

func test_crew_quality_lowercase_converted_to_uppercase() -> void:
	var upper = dm.get_bearing_off_probability("C", "b")
	var lower = dm.get_bearing_off_probability("c", "b")
	assert_almost_eq(lower, upper, 0.0001, "crew_quality lookup should be case-insensitive")

func test_maneuverability_uppercase_converted_to_lowercase() -> void:
	var lower = dm.get_bearing_off_probability("D", "b")
	var upper = dm.get_bearing_off_probability("D", "B")
	assert_almost_eq(lower, upper, 0.0001, "maneuverability lookup should be case-insensitive")

# --- Game Balance Sanity Checks ---

func test_better_crew_quality_geq_worse_at_same_maneuverability() -> void:
	# Better crew quality = lower letter (A is best, G is worst).
	# At any fixed maneuverability, going from worse (higher letter) to better (lower letter)
	# should monotonically non-decrease the success probability.
	for m in ["a", "b", "c", "d"]:
		var prev: float = -1.0
		# Iterate worst → best (G → A); each step must be >= previous.
		for cq in ["G", "F", "E", "D", "C", "B", "A"]:
			var p = dm.get_bearing_off_probability(cq, m)
			assert_true(p >= prev, "Probability for CQ '%s' / man '%s' (%f) should be >= worse CQ (%f)" % [cq, m, p, prev])
			prev = p
