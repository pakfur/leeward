extends GutTest
## Tests for CrewTaskController, the crew-task engine (Close Action 1997, 4.A.3, 4.B; crew-tasks
## spec §3.2). Expected values come from the rules and the ship log's Crew Task Order Codes:
## MS<->PS 2 CS 2/3 g-t's, FS<->MS 1 CS 1/2 g-t's, RR 6 ± SK g-t's (SK: A -3 ... G +3).
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const PLANNING := TurnPhaseController.GamePhase.PLANNING
const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT

var ctrl: CrewTaskController
var ship: ShipState
var _old_log: PhaseEvents.PhaseLog
var _old_phase: TurnPhaseController.GamePhase


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_old_log = GameState.turn_log
	_old_phase = GameState.phase_controller.current_phase
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.phase_controller.current_phase = PLANNING
	ctrl = GameState.crew_task_controller
	ship = _make_ship("crew_ship", 0)


func after_each() -> void:
	GameState.turn_log = _old_log
	GameState.phase_controller.current_phase = _old_phase
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, player: int, quality: String = "B") -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = Vector2i(10 * GameState.ships.size(), 0)
	state.sail_state = "MS"
	state.crew_quality = quality
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	GameState.add_ship(state)
	return state


## One g-t of the task engine: tasks start, then are counted; the turn's flags are cleared after.
func _turn() -> void:
	ctrl.begin_turn_tasks(MOVE)
	ctrl.advance_tasks(STATUS)


func _next_turn() -> void:
	GameState.ship_controller.clear_turn_flags(ship.ship_id)


func _crew_events() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.CREW_TASK)


# --- Sail changes as tasks (5.F.6-8) ---

func test_major_change_by_marines_and_s4_cq_b() -> void:
	# Spec §8 #4: MS->PS by M and S4 at CQ B takes 2 g-t's; PS from the next g-t, and until then
	# the ship moves and takes damage at MS (5.F.8).
	assert_eq(GameState.sail_controller.plot_sail_change(0, "crew_ship", "PS"), "")
	_turn()
	assert_eq(ship.sail_change_info()["sections"], [3, ShipState.MARINES])
	assert_eq(ship.sail_state, "MS", "1 of 2 g-t's")
	assert_eq(ship.movement_sail_state(), "MS")
	_next_turn()
	_turn()
	assert_eq(ship.sail_state, "PS")
	assert_eq(ship.tasks_with("SAIL"), [] as Array[Dictionary])


func test_minor_change_cq_e_takes_two_turns() -> void:
	# Spec §8 #5: FS->MS at CQ E: 2 g-t's (ship log 1/2).
	ship.crew_quality = "E"
	ship.sail_state = "FS"
	GameState.sail_controller.plot_sail_change(0, "crew_ship", "MS")
	_turn()
	assert_eq(ship.sail_state, "FS")
	_next_turn()
	_turn()
	assert_eq(ship.sail_state, "MS")


func test_sections_on_tasks_do_not_fire_minus_three_each() -> void:
	# Spec §8 #6 (ship log, Majestic g-t 7/17): S2 on a task -3; two sailor sections -6; all four
	# cannot fire.
	var tables: CombatTables = DataManager.combat_tables
	ship.plotted_sections = [1] as Array[int]
	assert_eq(tables.sections_firing_modifier(ship.sections_able_to_fire()), -3)
	ship.plotted_sections = [1, 2] as Array[int]
	assert_eq(tables.sections_firing_modifier(ship.sections_able_to_fire()), -6)
	ship.plotted_sections = [0, 1, 2, 3] as Array[int]
	assert_eq(ship.sections_able_to_fire(), 0)


func test_two_section_change_with_one_section_does_not_start() -> void:
	# Spec §8 #56 (5.F.6b): a 2-CS change with one section placed does not start.
	ship.crew_auto = false
	CrewFixtures.order_sail(ship, "PS")
	ship.plotted_actions["crew_assignments"] = {3: {"code": "SAIL", "params": {"target": "PS"}}}
	ctrl.begin_turn_tasks(MOVE)
	assert_false(ship.has_sail_change())
	assert_eq(ship.plotted_sections, [] as Array[int], "the section serves the guns")
	var sail := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(sail[0].data["cancelled"], "no crew")


func test_manual_plan_any_section_may_alter_sail() -> void:
	# 4.B.1: S1 may alter sail (manual plan).
	ship.crew_auto = false
	assert_eq(GameState.sail_controller.plot_sail_change(0, "crew_ship", "FS"), "")
	var plan := CrewRules.assign(ship, CrewRules.plan_of(ship), {}, 0, CrewRules.STATION_SAILS)
	assert_eq(ctrl.plot_crew(0, "crew_ship", plan), "")
	ctrl.begin_turn_tasks(MOVE)
	assert_eq(ship.sail_change_info()["sections"], [0])
	assert_eq(ship.sections_able_to_fire(), 3)


func test_begin_clears_the_crew_plot() -> void:
	GameState.sail_controller.plot_sail_change(0, "crew_ship", "FS")
	ctrl.begin_turn_tasks(MOVE)
	assert_eq(ship.ordered_sail_target(), "")
	assert_eq(ship.plotted_actions["crew_assignments"], {})


func test_shared_change_cancelled_for_both_sections() -> void:
	# 5.F.9a: a section of a 2-CS sail change is lost to its task; the change ends for both.
	CrewFixtures.give_sail_change(ship, "PS", [2, 3])
	assert_true(ctrl.cancel_section("crew_ship", 3, "crew disorganized", STATUS))
	assert_false(ship.has_sail_change())
	assert_eq(ship.task_of(2), {})


# --- Continuation, abandonment, progress (4.A.3, 4.B.3, 9.A.2) ---

func _start_rr(section: int) -> int:
	return GameState.ship_controller.add_task("crew_ship", {"code": "RR", "sections": [section], "params": {}})


func test_task_continued_by_the_same_section_counts_turns() -> void:
	# 4.A.3: plotted again by the same section, the task goes on (Automatic rule A2).
	var seq := _start_rr(2)
	ship.plotted_sections = [2] as Array[int]
	ctrl.advance_tasks(STATUS)
	_next_turn()
	_turn()
	assert_eq(ship.task_by_seq(seq)["done"], 2)
	assert_eq(ship.task_by_seq(seq)["ended"], "")


func test_task_not_plotted_again_is_abandoned() -> void:
	# Spec §8 #2 (4.A.3): a section that stops plotting a task loses all progress.
	ship.crew_auto = false
	var seq := _start_rr(2)
	GameState.ship_controller.update_task("crew_ship", seq, {"done": 1})
	ship.plotted_actions["crew_assignments"] = {}
	ctrl.begin_turn_tasks(MOVE)
	assert_eq(ship.task_by_seq(seq)["ended"], CrewTaskController.ABANDONED)
	var events := _crew_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0].data["state"], "abandoned")
	assert_eq(ship.sections_able_to_fire(), 4, "S3 is back at the guns")


func test_crew_quality_change_extends_the_task() -> void:
	# Spec §8 #17 (9.A.2; Majestic g-t 16-20): RR at CQ B needs 6 - 2 = 4 g-t's; CQ falls to C
	# after the third, so 5 are needed and it completes a g-t later.
	var seq := _start_rr(2)
	for i in range(3):
		ship.plotted_sections = [2] as Array[int]
		ctrl.advance_tasks(STATUS)
	assert_eq(ship.task_by_seq(seq)["done"], 3)
	ship.crew_quality = "C"
	ctrl.advance_tasks(STATUS)
	assert_eq(ship.task_by_seq(seq)["ended"], "", "4 of 5")
	ctrl.advance_tasks(STATUS)
	assert_eq(ship.task_by_seq(seq)["ended"], CrewTaskController.COMPLETED)
	assert_eq(_crew_events()[-1].data["state"], "completed")


func test_crew_loss_ends_the_task() -> void:
	# Spec §8 #8 (4.B.3): crew loss empties S1 doing RR 2 of 4: the task ends, progress gone.
	var seq := _start_rr(0)
	GameState.ship_controller.update_task("crew_ship", seq, {"done": 2})
	ship.plotted_sections = [0] as Array[int]
	ship.crew_count = [0, 3, 3, 3] as Array[int]
	ctrl.advance_tasks(STATUS)
	assert_eq(ship.task_by_seq(seq)["ended"], "crew lost")
	assert_eq(ship.task_of(0), {})


func test_section_whose_task_ended_early_still_does_not_fire() -> void:
	# Spec §0.3 #2 (4.B.4): a section plotted to a task does not serve the guns that g-t, even if
	# the task ends early.
	CrewFixtures.give_sail_change(ship, "FS", [3])
	ctrl.cancel_section("crew_ship", 3, "lines jammed", STATUS)
	assert_eq(ship.sections_able_to_fire(), 3)
	_next_turn()
	assert_eq(ship.sections_able_to_fire(), 4, "free again next g-t")
	assert_eq(ship.crew_tasks, [] as Array[Dictionary], "ended tasks go at the end of the g-t")


func test_force_task_ends_the_old_task_and_locks_the_section() -> void:
	# Spec §3.9 contract: force_task ends the section's task and puts it on a forced one.
	var old := _start_rr(3)
	var seq := ctrl.force_task("crew_ship", [3], "RO", {"reason": "crew_disorganized"}, STATUS)
	assert_eq(ship.task_by_seq(old)["ended"], "crew_disorganized")
	assert_true(ship.task_by_seq(seq)["forced"])
	assert_true(ship.is_disorganized(3))
	assert_eq(CrewRules.locked_sections(ship).keys(), [3])
	assert_true(ship.plotted_sections.has(3))


func test_reset_progress_keeps_the_task() -> void:
	var seq := _start_rr(1)
	GameState.ship_controller.update_task("crew_ship", seq, {"done": 5})
	ctrl.reset_progress("crew_ship", "RR", "rigging hit while dismasted", STATUS)
	assert_eq(ship.task_by_seq(seq)["done"], 0)
	assert_eq(ship.task_by_seq(seq)["ended"], "")


# --- Plotting API ---

func test_plot_crew_refusals() -> void:
	var plan := {"assignments": {}, "orders": {"sail_target": ""}}
	assert_eq(ctrl.plot_crew(1, "crew_ship", plan), "Not your ship")
	assert_eq(ctrl.plot_crew(0, "crew_ship", {"assignments": {9: {}}, "orders": {}}), "Malformed crew plan")
	GameState.phase_controller.current_phase = MOVE
	assert_eq(ctrl.plot_crew(0, "crew_ship", plan), "Crew can only be plotted during planning")


func test_set_auto_off_keeps_the_allocation() -> void:
	# Spec §4.9: turning Automatic off keeps the current allocation as the manual plan.
	GameState.sail_controller.plot_sail_change(0, "crew_ship", "FS")
	assert_eq(ctrl.set_auto(0, "crew_ship", false), "")
	assert_false(ship.crew_auto)
	assert_eq(ship.plotted_actions["crew_assignments"].keys(), [ShipState.MARINES])
	assert_eq(ctrl.set_auto(0, "crew_ship", true), "")
	assert_true(ship.crew_auto)


func test_finalize_plots_stores_the_automatic_allocation() -> void:
	GameState.sail_controller.plot_sail_change(0, "crew_ship", "FS")
	ctrl.finalize_plots()
	assert_eq(ship.plotted_actions["crew_assignments"],
		{ShipState.MARINES: {"code": "SAIL", "params": {"target": "FS"}}})


func test_stub_ai_leaves_automatic_on() -> void:
	# Spec §3.3: AI ships are always on Automatic; the AI gives orders only.
	var ai := _make_ship("ai_ship", 1)
	ai.crew_auto = false
	GameState.stub_ai.assign_crew()
	assert_true(ai.crew_auto)
	assert_eq(ai.ordered_sail_target(), "")


func test_destroyed_ship_drops_its_tasks() -> void:
	CrewFixtures.give_sail_change(ship, "PS", [2, 3])
	ctrl.drop_all("crew_ship", "destroyed")
	assert_false(ship.has_sail_change())
	assert_eq(GameState.turn_log.events.size(), 0, "silently")


# --- Serialization (spec §8 #57) ---

func test_old_save_sail_change_becomes_a_task() -> void:
	ship.crew_quality = "B"
	var data := ship.serialize()
	data.erase("crew_tasks")
	data["sail_change"] = {"target": "PS", "turns_left": 1, "sections": [3, 2]}
	data["plotted_actions"] = {"movement": [], "sail_change": "FS"}
	var restored := ShipState.deserialize(data)
	var info := restored.sail_change_info()
	assert_eq(info["target"], "PS")
	assert_eq(info["turns_left"], 1, "MS->PS at CQ B: 2 g-t's, 1 done")
	assert_eq(info["sections"], [3, 2])
	assert_eq(restored.ordered_sail_target(), "FS")
	assert_false(restored.plotted_actions.has("sail_change"))
