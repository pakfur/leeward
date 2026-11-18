extends GutTest
## The nine anchoring crew task codes (13.B) and the 2 x (n +/- SK) length form.

var ct: CombatTables

func before_all() -> void:
	ct = DataManager.combat_tables

func test_pba_two_or_three() -> void:
	assert_eq(ct.task_turns("PBA", "A"), 2)
	assert_eq(ct.task_turns("PBA", "D"), 2)
	assert_eq(ct.task_turns("PBA", "E"), 3)
	assert_eq(ct.task_turns("PBA", "G"), 3)

func test_psa_six_plus_sk() -> void:
	assert_eq(ct.task_turns("PSA", "C"), 5)
	assert_eq(ct.task_turns("PSA", "A"), 3)
	assert_eq(ct.task_turns("PSA", "G"), 9)

func test_pbs_twice_five_plus_sk() -> void:
	assert_eq(ct.task_turns("PBS", "C"), 8)
	assert_eq(ct.task_turns("PBS", "A"), 4)
	assert_eq(ct.task_turns("PBS", "G"), 16)

func test_pss_twice_six_plus_sk() -> void:
	assert_eq(ct.task_turns("PSS", "C"), 10)
	assert_eq(ct.task_turns("PSS", "A"), 6)
	assert_eq(ct.task_turns("PSS", "G"), 18)

func test_one_turn_codes() -> void:
	for code in ["A", "AX", "VO", "VI", "HS"]:
		for cq in ["A", "B", "C", "D", "E", "F", "G"]:
			assert_eq(ct.task_turns(code, cq), 1, "%s at CQ %s" % [code, cq])

func test_every_code_takes_one_section() -> void:
	for code in ["PBA", "PSA", "PBS", "PSS", "A", "AX", "VO", "VI", "HS"]:
		assert_eq(ct.task_sections(code), [1, 1], code)

func test_times_defaults_to_one() -> void:
	assert_eq(ct.task_turns("RR", "C"), 5)
