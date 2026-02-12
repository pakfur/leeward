extends GutTest
## Tests for DataManager movement allowance table loading and lookups.
##
## Validates the 5-level nested lookup: speed_type → wind_facing → wind_speed → rigging_quality → sail_state → MA
## Uses the actual movement_allowance.json data file for regression testing.

var dm: Node

func before_all() -> void:
	dm = DataManager
	dm.load_movement_allowance_table()

# --- Table Loading ---

func test_movement_table_loads_successfully() -> void:
	assert_gt(dm.movement_allowance_table.size(), 0, "Movement table should not be empty after loading")

func test_movement_table_has_all_speed_types() -> void:
	var expected_speed_types = ["L/F", "L/S", "L/VS", "F/F", "F/S", "F/VS", "C/F", "C/S", "C/VS"]
	for st in expected_speed_types:
		assert_true(dm.movement_allowance_table.has(st), "Table should contain speed_type '%s'" % st)

func test_movement_table_speed_type_count() -> void:
	assert_eq(dm.movement_allowance_table.size(), 9, "Should have exactly 9 speed types")

func test_movement_table_has_wind_facings_per_speed_type() -> void:
	var expected_facings = ["C", "B", "R"]
	for speed_type in dm.movement_allowance_table.keys():
		var facings_dict = dm.movement_allowance_table[speed_type]
		for facing in expected_facings:
			assert_true(facings_dict.has(facing), "Speed type '%s' should have wind facing '%s'" % [speed_type, facing])

func test_movement_table_has_wind_speeds_1_through_4() -> void:
	# Spot-check one speed_type/facing combo for all wind speeds
	var close_hauled = dm.movement_allowance_table["F/F"]["C"]
	for ws in ["1", "2", "3", "4"]:
		assert_true(close_hauled.has(ws), "F/F Close-hauled should have wind speed '%s'" % ws)

func test_movement_table_has_rigging_qualities_1_through_4() -> void:
	# Spot-check one full path for all rigging qualities
	var wind_speed_dict = dm.movement_allowance_table["F/F"]["B"]["2"]
	for rq in ["1", "2", "3", "4"]:
		assert_true(wind_speed_dict.has(rq), "F/F B ws2 should have rigging quality '%s'" % rq)

# --- Luffing Special Case ---

func test_luffing_returns_zero_for_all_speed_types() -> void:
	var speed_types = ["L/F", "L/S", "L/VS", "F/F", "F/S", "F/VS", "C/F", "C/S", "C/VS"]
	for st in speed_types:
		var ma = dm.get_movement_allowance(st, 2, "L", "fs", 4)
		assert_eq(ma, 0, "Luffing should return 0 for speed_type '%s'" % st)

func test_luffing_returns_zero_all_wind_speeds() -> void:
	for ws in [1, 2, 3, 4]:
		var ma = dm.get_movement_allowance("F/F", ws, "L", "ms", 4)
		assert_eq(ma, 0, "Luffing should return 0 at wind speed %d" % ws)

func test_luffing_returns_zero_all_sail_states() -> void:
	for ss in ["fs", "ms", "ps", "ns"]:
		var ma = dm.get_movement_allowance("L/F", 2, "L", ss, 4)
		assert_eq(ma, 0, "Luffing should return 0 for sail state '%s'" % ss)

# --- Known Value Lookups (regression anchors from movement_allowance.json) ---

func test_lookup_lf_close_hauled_ws1_rq4_fs() -> void:
	var ma = dm.get_movement_allowance("L/F", 1, "C", "fs", 4)
	assert_eq(ma, 1, "L/F, C, ws1, rq4, fs should be 1")

func test_lookup_lf_close_hauled_ws2_rq4_ps() -> void:
	var ma = dm.get_movement_allowance("L/F", 2, "C", "ps", 4)
	assert_eq(ma, 5, "L/F, C, ws2, rq4, ps should be 5")

func test_lookup_lf_broad_reach_ws3_rq4_ms() -> void:
	var ma = dm.get_movement_allowance("L/F", 3, "B", "ms", 4)
	assert_eq(ma, 7, "L/F, B, ws3, rq4, ms should be 7")

func test_lookup_ff_broad_reach_ws2_rq4_ps() -> void:
	var ma = dm.get_movement_allowance("F/F", 2, "B", "ps", 4)
	assert_eq(ma, 9, "F/F, B, ws2, rq4, ps should be 9")

func test_lookup_ff_reach_ws1_rq4_fs() -> void:
	var ma = dm.get_movement_allowance("F/F", 1, "R", "fs", 4)
	assert_eq(ma, 3, "F/F, R, ws1, rq4, fs should be 3")

func test_lookup_ff_close_hauled_ws3_rq3_ms() -> void:
	var ma = dm.get_movement_allowance("F/F", 3, "C", "ms", 3)
	assert_eq(ma, 4, "F/F, C, ws3, rq3, ms should be 4")

func test_lookup_cf_broad_reach_ws2_rq4_fs() -> void:
	var ma = dm.get_movement_allowance("C/F", 2, "B", "fs", 4)
	assert_eq(ma, 6, "C/F, B, ws2, rq4, fs should be 6")

func test_lookup_cf_reach_ws1_rq3_ms() -> void:
	var ma = dm.get_movement_allowance("C/F", 1, "R", "ms", 3)
	assert_eq(ma, 5, "C/F, R, ws1, rq3, ms should be 5")

func test_lookup_cs_close_hauled_ws4_rq4_ps() -> void:
	var ma = dm.get_movement_allowance("C/S", 4, "C", "ps", 4)
	assert_eq(ma, 5, "C/S, C, ws4, rq4, ps should be 5")

func test_lookup_cvs_broad_reach_ws3_rq4_ms() -> void:
	var ma = dm.get_movement_allowance("C/VS", 3, "B", "ms", 4)
	assert_eq(ma, 6, "C/VS, B, ws3, rq4, ms should be 6")

# --- Low Rigging Quality (degraded ships) ---

func test_low_rigging_quality_reduces_options() -> void:
	# At rq1, only "fs" key may exist (or none), values should be low
	var ma = dm.get_movement_allowance("L/F", 1, "C", "fs", 1)
	assert_eq(ma, 0, "L/F, C, ws1, rq1, fs should be 0")

func test_rigging_quality_2_close_hauled() -> void:
	var ma = dm.get_movement_allowance("F/F", 2, "C", "ps", 2)
	assert_eq(ma, 1, "F/F, C, ws2, rq2, ps should be 1")

func test_rigging_quality_3_broad_reach() -> void:
	var ma = dm.get_movement_allowance("F/F", 2, "B", "ms", 3)
	assert_eq(ma, 6, "F/F, B, ws2, rq3, ms should be 6")

# --- Missing Sail States Return Zero ---

func test_missing_sail_state_returns_zero() -> void:
	# rq1 for L/F at ws1 C only has "fs" key — "ms" is missing and should return 0
	var ma = dm.get_movement_allowance("L/F", 1, "C", "ms", 1)
	assert_eq(ma, 0, "Missing sail state in table should return 0")

func test_no_sail_returns_zero() -> void:
	# "ns" (no sail) is not present in the JSON data — should return 0
	var ma = dm.get_movement_allowance("F/F", 2, "B", "ns", 4)
	assert_eq(ma, 0, "No sail (ns) should return 0 when missing from table")

# --- Case Insensitivity for Sail State ---

func test_sail_state_uppercase_converted_to_lowercase() -> void:
	var ma_lower = dm.get_movement_allowance("F/F", 2, "B", "fs", 4)
	var ma_upper = dm.get_movement_allowance("F/F", 2, "B", "FS", 4)
	assert_eq(ma_lower, ma_upper, "Sail state lookup should be case-insensitive")

func test_sail_state_mixed_case() -> void:
	var ma = dm.get_movement_allowance("F/F", 2, "B", "Fs", 4)
	assert_eq(ma, 5, "Mixed case sail state 'Fs' should work (F/F, B, ws2, rq4)")

# --- Boundary Values ---

func test_wind_speed_min_boundary() -> void:
	var ma = dm.get_movement_allowance("F/F", 1, "B", "fs", 4)
	assert_eq(ma, 4, "Wind speed 1 (minimum) should return valid MA")

func test_wind_speed_max_boundary() -> void:
	var ma = dm.get_movement_allowance("F/F", 4, "B", "fs", 4)
	assert_eq(ma, 6, "Wind speed 4 (maximum) should return valid MA")

func test_rigging_quality_min_boundary() -> void:
	var ma = dm.get_movement_allowance("F/F", 2, "B", "fs", 1)
	# rq1 for F/F B ws2 only has "ps" key, fs is missing → 0
	assert_eq(ma, 0, "Rigging quality 1 with fs should return 0 (not in table)")

func test_rigging_quality_max_boundary() -> void:
	var ma = dm.get_movement_allowance("F/F", 2, "B", "fs", 4)
	assert_eq(ma, 5, "Rigging quality 4 (maximum) should return expected MA")

# --- Cross-speed-type Comparisons (game balance sanity checks) ---

func test_broad_reach_faster_than_close_hauled() -> void:
	var ma_close = dm.get_movement_allowance("F/F", 2, "C", "ms", 4)
	var ma_broad = dm.get_movement_allowance("F/F", 2, "B", "ms", 4)
	assert_gt(ma_broad, ma_close, "Broad reach should yield more MA than close-hauled")

func test_plain_sail_faster_than_fighting_sail() -> void:
	var ma_fs = dm.get_movement_allowance("F/F", 2, "B", "fs", 4)
	var ma_ps = dm.get_movement_allowance("F/F", 2, "B", "ps", 4)
	assert_gt(ma_ps, ma_fs, "Plain sail should yield more MA than fighting sail")

func test_higher_wind_speed_generally_faster() -> void:
	var ma_ws1 = dm.get_movement_allowance("F/F", 1, "B", "ms", 4)
	var ma_ws3 = dm.get_movement_allowance("F/F", 3, "B", "ms", 4)
	assert_gt(ma_ws3, ma_ws1, "Higher wind speed should generally yield more MA")

func test_higher_rigging_quality_at_least_as_fast() -> void:
	var ma_rq3 = dm.get_movement_allowance("F/F", 2, "B", "fs", 3)
	var ma_rq4 = dm.get_movement_allowance("F/F", 2, "B", "fs", 4)
	assert_true(ma_rq4 >= ma_rq3, "Higher rigging quality should yield >= MA")
