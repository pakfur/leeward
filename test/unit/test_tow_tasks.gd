extends GutTest
## Towing vocabulary (12.A): the PT and TX crew tasks, the event types and the log words.

var ct: CombatTables

func before_all() -> void:
	ct = DataManager.combat_tables

func test_pt_five_plus_sk() -> void:
	assert_eq(ct.task_turns("PT", "C"), 4)
	assert_eq(ct.task_turns("PT", "A"), 2)
	assert_eq(ct.task_turns("PT", "D"), 5)
	assert_eq(ct.task_turns("PT", "G"), 8)
	assert_eq(ct.task_sections("PT"), [1, 1])

func test_tx_one_turn() -> void:
	for q in ["A", "B", "C", "D", "E", "F", "G"]:
		assert_eq(ct.task_turns("TX", q), 1, "TX at CQ %s" % q)
	assert_eq(ct.task_sections("TX"), [1, 1])

func test_event_types_appended() -> void:
	assert_eq(PhaseEvents.Type.TOW_BEGUN, PhaseEvents.Type.VEER_IN + 1)
	assert_eq(PhaseEvents.Type.TOW_CUT, PhaseEvents.Type.VEER_IN + 2)
	assert_eq(MovementTypes.ResolutionEventType.TOW_FOLLOW, MovementTypes.ResolutionEventType.LEAD_SOUNDING + 1)
	assert_eq(MovementTypes.ResolutionEventType.TOW_HELD, MovementTypes.ResolutionEventType.LEAD_SOUNDING + 2)

func test_crew_task_words() -> void:
	assert_eq(PhaseEvents.CREW_TASK_NAMES["PT"], "prepare to tow")
	assert_eq(PhaseEvents.CREW_TASK_NAMES["TX"], "cut the tow")
	assert_eq(PhaseEvents.CREW_TASK_GERUNDS["PT"], "preparing to tow")
	assert_eq(PhaseEvents.CREW_TASK_GERUNDS["TX"], "cutting the tow")
