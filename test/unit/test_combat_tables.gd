extends GutTest
## Tests for CombatTables: the 1997 Close Action combat charts loaded from
## data/rules/*.json and exposed through DataManager.combat_tables.
##
## Expected values are regression anchors read from the 1997 charts
## (Gunnery Factor / BGN Determination, Gunfire Results, Drifting,
## Unfouling, Crew Quality / Skill).

var ct: CombatTables

func before_all() -> void:
	ct = DataManager.combat_tables

func _counts(tokens: Array) -> Dictionary:
	## Sum the counts of single-alternative tokens by damage type.
	var totals := {"r": 0, "h": 0, "c": 0}
	for token in tokens:
		assert_eq(token.size(), 1, "expected an unslashed token, got %s" % [token])
		var alt: Dictionary = token[0]
		totals[alt["type"]] += alt["count"]
	return totals

# --- Loading ---

func test_data_manager_owns_loaded_combat_tables() -> void:
	assert_not_null(ct, "DataManager.combat_tables should exist after _ready")

func test_load_all_returns_true_on_fresh_instance() -> void:
	var fresh := CombatTables.new()
	assert_true(fresh.load_all(), "load_all should succeed on the shipped tables")

# --- Gunnery Factor multipliers ---

func test_gunnery_multipliers() -> void:
	assert_eq(ct.gunnery_multiplier("lg", 15), 1.0)
	assert_eq(ct.gunnery_multiplier("cr", 4), 1.5)
	assert_eq(ct.gunnery_multiplier("cr", 7), 0.0)
	assert_eq(ct.gunnery_multiplier("mg", 11), 0.5)

func test_gunnery_multiplier_medium_guns_three_quarters_and_out_of_range() -> void:
	assert_eq(ct.gunnery_multiplier("mg", 6), 0.75)
	assert_eq(ct.gunnery_multiplier("mg", 13), 0.0)
	assert_eq(ct.gunnery_multiplier("lg", 16), 0.0, "beyond the table is 0")

# --- Basic Gunfire Number ---

func test_basic_gunfire_number() -> void:
	assert_eq(ct.basic_gunfire_number(14, 1, false), 24)
	assert_eq(ct.basic_gunfire_number(12, 4, false), 20)
	assert_eq(ct.basic_gunfire_number(8, 6, false), 13)
	assert_eq(ct.basic_gunfire_number(6, 7, false), 9)
	assert_eq(ct.basic_gunfire_number(6, 10, false), 4)
	assert_eq(ct.basic_gunfire_number(6, 15, false), -1)
	assert_eq(ct.basic_gunfire_number(19, 1, false), 27)
	assert_eq(ct.basic_gunfire_number(8, 11, false), 5)
	assert_eq(ct.basic_gunfire_number(8, 11, true), 6)
	assert_eq(ct.basic_gunfire_number(31, 1, false), 32)
	assert_eq(ct.basic_gunfire_number(500, 9, false), 20)
	assert_eq(ct.basic_gunfire_number(1, 8, false), -1)

func test_basic_gunfire_number_extra_anchors() -> void:
	assert_eq(ct.basic_gunfire_number(1, 7, false), 0, "TGF 1 range 7 prints 0, not grey")
	assert_eq(ct.basic_gunfire_number(31, 15, true), 12)
	assert_eq(ct.basic_gunfire_number(31, 15, false), 11)
	assert_eq(ct.basic_gunfire_number(3, 10, true), 0, "single number at range 10 is used for French too")
	assert_eq(ct.basic_gunfire_number(26, 12, false), 14, "TGF 25-27 band")

# --- Gunfire Results ---

func test_gunfire_result_row_1_is_empty() -> void:
	for aim in ["low", "high"]:
		for column in ["fs", "ms", "ps"]:
			assert_eq(ct.gunfire_result(1, aim, column), [], "row 1 %s %s" % [aim, column])
	assert_eq(ct.critical_hit_number(1), 0)

func test_gunfire_result_row_30() -> void:
	assert_eq(_counts(ct.gunfire_result(30, "low", "fs")), {"r": 2, "h": 1, "c": 1})
	assert_eq(ct.critical_hit_number(30), 3)

func test_gunfire_result_row_52() -> void:
	assert_eq(_counts(ct.gunfire_result(52, "low", "fs")), {"r": 9, "h": 12, "c": 6})
	assert_eq(_counts(ct.gunfire_result(52, "high", "fs")), {"r": 14, "h": 3, "c": 3})

func test_gunfire_result_clamps_above_52() -> void:
	assert_eq(ct.gunfire_result(60, "low", "fs"), ct.gunfire_result(52, "low", "fs"))

func test_gunfire_result_below_1_is_empty() -> void:
	assert_eq(ct.gunfire_result(0, "low", "fs"), [])

func test_slashed_cell_parses_to_two_alternatives() -> void:
	# Row 3 low FS prints "h/." : one hull box or nothing.
	var tokens := ct.gunfire_result(3, "low", "fs")
	assert_eq(tokens.size(), 1)
	assert_eq(tokens[0], [{"type": "h", "count": 1}, {}])

func test_mixed_slashed_cell_parses_each_token() -> void:
	# Row 20 low FS prints "r/h-c/." : rigging-or-hull, then crew-or-nothing.
	var tokens := ct.gunfire_result(20, "low", "fs")
	assert_eq(tokens, [
		[{"type": "r", "count": 1}, {"type": "h", "count": 1}],
		[{"type": "c", "count": 1}, {}],
	])

func test_increment_column_cell() -> void:
	# Row 52 high +PS column prints "5r".
	assert_eq(ct.gunfire_result(52, "high", "ps"), [[{"type": "r", "count": 5}]])

# --- Modifiers ---

func test_gunfire_modifiers() -> void:
	assert_eq(ct.crew_quality_modifier("A"), 6)
	assert_eq(ct.crew_quality_modifier("G"), -6)
	assert_eq(ct.sections_firing_modifier(1), -9)
	assert_eq(ct.range_bonus("rake", 3), 3)
	assert_eq(ct.range_bonus("rake", 6), 0)
	assert_eq(ct.flat_modifier("two_targets"), -12)

func test_flat_modifiers_from_other_modifiers_block() -> void:
	assert_eq(ct.flat_modifier("wind_speed_4"), -1)
	assert_eq(ct.flat_modifier("plain_sail"), -1)
	assert_eq(ct.flat_modifier("dismantling_shot"), 1)
	assert_eq(ct.flat_modifier("anchored"), 1)

# --- Crew loss ---

func test_crew_loss() -> void:
	assert_true(ct.crew_loss_is_sailor("gunfire_at_hull", 5))
	assert_false(ct.crew_loss_is_sailor("gunfire_at_hull", 6))
	assert_true(ct.crew_loss_is_sailor("other", 3))
	assert_false(ct.crew_loss_is_sailor("other", 4))

# --- Drifting ---

func test_drift() -> void:
	assert_eq(ct.drift_number("ps", 4), 0)
	assert_eq(ct.drift_number("dismasted", 1), 10)
	assert_eq(ct.drift_number("ms", 0), -1)
	assert_eq(ct.drift_class_drm(3), 1)
	assert_eq(ct.drift_class_drm(2), 0)

# --- Unfouling and skill ---

func test_unfouling() -> void:
	assert_eq(ct.unfouling_success_max(1), 2)
	assert_eq(ct.unfouling_success_max(2), 3)
	assert_eq(ct.unfouling_success_max(7), 4)

func test_skill_modifier() -> void:
	assert_eq(ct.skill_modifier("A"), -3)
	assert_eq(ct.skill_modifier("D"), 0)
	assert_eq(ct.skill_modifier("G"), 3)
