extends GutTest
## Tests for repairs (Close Action 1997, 8.F, 9.B.2, Scenario Book VI.B.4; crew-tasks spec §3.7,
## §8 #2, #3, #22, #45-55): RepairController (RR, RH, RS handlers), rule A5, repair_box,
## checked_sections, the 4-MP limit and 8.F.6. Expected values come from the rules and the ship
## log's Crew Task Order Codes: RR 6 ± SK, RH 10 ± SK, RS 5 ± SK g-t's (SK: A -3, B -2, C -1, D 0).
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const PLANNING := TurnPhaseController.GamePhase.PLANNING
const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
const COMBAT := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT

var ctrl: CrewTaskController
var ship: ShipState
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_phase: TurnPhaseController.GamePhase
var _old_crits: CriticalHitController
var _old_turn: int


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_old_log = GameState.turn_log
	_old_phase = GameState.phase_controller.current_phase
	_old_dice = GameState.dice
	_old_crits = GameState.critical_hit_controller
	_old_turn = GameState.current_turn
	# A fresh, held critical-hit controller keeps Rigging/Hull Checks queued (pending_checks).
	GameState.critical_hit_controller = CriticalHitController.new(GameState)
	GameState.critical_hit_controller.hold()
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.phase_controller.current_phase = PLANNING
	GameState.current_turn = 1
	ctrl = GameState.crew_task_controller
	ship = _make_ship("rep", 0, Vector2i(0, 0))


func after_each() -> void:
	GameState.turn_log = _old_log
	GameState.phase_controller.current_phase = _old_phase
	GameState.dice = _old_dice
	GameState.critical_hit_controller = _old_crits
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, player: int, hex: Vector2i, quality: String = "B") -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
		"point_costs": {"B4": 100},
	})
	state.hex_position = hex
	state.facing = 0
	state.sail_state = "FS"
	state.crew_quality = quality
	state.starting_crew_quality = quality
	state.morale_rating = 4
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	GameState.add_ship(state)
	return state


## A manual crew plan stored for this turn (as plot_crew would store it).
func _plot(assignments: Dictionary) -> void:
	ship.crew_auto = false
	ship.plotted_actions["crew_assignments"] = assignments
	ship.plotted_actions["crew_plotted"] = true


## One g-t of the task engine; the turn's flags are cleared at the end.
func _turn() -> void:
	ctrl.begin_turn_tasks(MOVE)
	ctrl.advance_tasks(STATUS)
	GameState.ship_controller.clear_turn_flags(ship.ship_id)
	GameState.current_turn += 1


func _ctx() -> Dictionary:
	return CrewRules.context(GameState, ship)


func _station(id: String, plan: Dictionary = {}) -> Dictionary:
	if plan.is_empty():
		plan = ctrl.current_plan(ship.ship_id)
	for st in CrewRules.stations(ship, plan, _ctx()):
		if st["id"] == id:
			return st
	return {}


func _events(type: int) -> Array:
	return GameState.turn_log.of_type(type)


# --- Task lengths (ship log; 8.F.4, 8.F.6 examples; Majestic g-t 14) ---

func test_row48_repair_lengths_by_crew_quality() -> void:
	# Spec §8 #48: CQ A RR 3, RH 7 (8.F.4 example); CQ D RR 6 (8.F.6 example); CQ B RS 3 (Majestic).
	ship.crew_quality = "A"
	assert_eq(ship.task_turns_required({"code": "RR"}), 3)
	assert_eq(ship.task_turns_required({"code": "RH"}), 7)
	ship.crew_quality = "D"
	assert_eq(ship.task_turns_required({"code": "RR"}), 6)
	ship.crew_quality = "B"
	assert_eq(ship.task_turns_required({"code": "RS"}), 3)


func test_row48_shroud_repair_removes_the_mp_loss() -> void:
	# Spec §8 #48 (8.F.1, rigging #9): RS at CQ B takes 3 g-t's and removes the -1 MP.
	GameState.ship_controller.add_critical_effect("rep", {"id": "shrouds_severed", "turn": 0})
	assert_eq(ship.critical_mp_loss(), 1)
	_plot({ShipState.MARINES: {"code": "RS", "params": {}}})
	for i in range(2):
		_turn()
		assert_true(ship.has_critical("shrouds_severed"), "g-t %d of 3" % (i + 1))
	_turn()
	assert_false(ship.has_critical("shrouds_severed"))
	assert_eq(ship.critical_mp_loss(), 0)
	var repairs := _events(PhaseEvents.Type.REPAIR)
	assert_eq(repairs.size(), 1)
	assert_eq(repairs[0].data["kind"], "shrouds")
	assert_string_contains(repairs[0].to_text({}), "splices the severed shrouds")


# --- Plotting limits (8.F.3, 8.F.4) ---

func test_row45_rigging_repair_only_at_fs_furled_or_dismasted() -> void:
	# Spec §8 #45 (8.F.3a): RR at MS refused; furled (NS) accepted; dismasted accepted.
	ship.crew_auto = false
	ship.rigging_current_hp[0] = 3
	ship.sail_state = "MS"
	var plan := {"assignments": {}, "orders": {"sail_target": ""}}
	assert_string_contains(CrewRules.refusal(ship, plan, _ctx(), 2, CrewRules.STATION_RR), "8.F.3a")
	assert_ne(_station(CrewRules.STATION_RR, plan).get("disabled_reason", ""), "", "station shown, disabled")
	ship.sail_state = "NS"
	assert_eq(CrewRules.refusal(ship, plan, _ctx(), 2, CrewRules.STATION_RR), "")
	ship.sail_state = "MS"
	ship.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_true(ship.is_dismasted())
	assert_eq(CrewRules.refusal(ship, plan, _ctx(), 2, CrewRules.STATION_RR), "")


func test_row3_one_section_per_repair_type() -> void:
	# Spec §8 #3 (8.F.4): a second section on RR is refused; RR and RH together are fine.
	ship.crew_auto = false
	CrewFixtures.allow_rigging_repair(ship)
	CrewFixtures.allow_hull_repair(ship)
	var plan := {"assignments": {2: {"code": "RR", "params": {}}}, "orders": {"sail_target": ""}}
	assert_string_contains(CrewRules.refusal(ship, plan, _ctx(), 3, CrewRules.STATION_RR), "8.F.4")
	assert_eq(CrewRules.refusal(ship, plan, _ctx(), 3, CrewRules.STATION_RH), "")
	var both := CrewRules.assign(ship, plan, _ctx(), 3, CrewRules.STATION_RH)
	var normalized := CrewRules.normalize(ship, both, _ctx())
	assert_eq(normalized["assignments"], {2: {"code": "RR", "params": {}}, 3: {"code": "RH", "params": {}}})
	var two := {"assignments": {2: {"code": "RR", "params": {}}, 3: {"code": "RR", "params": {}}}, "orders": {}}
	assert_eq(CrewRules.normalize(ship, two, _ctx())["assignments"].keys(), [2], "the second RR is dropped")


func test_no_repair_without_damage() -> void:
	# 8.F.3: nothing marked out, nothing to repair: no stations, refused.
	ship.crew_auto = false
	var plan := {"assignments": {}, "orders": {"sail_target": ""}}
	for id in [CrewRules.STATION_RR, CrewRules.STATION_RH, CrewRules.STATION_RS]:
		assert_eq(_station(id, plan), {}, "%s not shown" % id)
		assert_string_contains(CrewRules.refusal(ship, plan, _ctx(), 2, id), "8.F.3")


func test_row47_station_appears_the_turn_after_damage() -> void:
	# Spec §8 #47 (8.F.3): rigging first damaged in g-t 3: no RR station in g-t 3's planning
	# (plotting comes first), present in g-t 4's.
	assert_eq(_station(CrewRules.STATION_RR), {})
	GameState.damage_controller.apply_hits("rep", 1, 0, 0, "other", COMBAT)
	var st := _station(CrewRules.STATION_RR)
	assert_false(st.is_empty())
	assert_eq(st["capacity"], 1)
	assert_eq(st["turns"], 4, "CQ B: 6 - 2")
	assert_eq(st["disabled_reason"], "")


func test_row2_another_section_starting_the_repair_abandons_the_first() -> void:
	# Spec §8 #2 (4.A.3, 8.F.4): S3 on RR in g-t 1; in g-t 2 S4 plots RR instead: S3's task ends
	# "abandoned" and S4's starts from 0.
	CrewFixtures.allow_rigging_repair(ship, 2)
	_plot({2: {"code": "RR", "params": {}}})
	_turn()
	var first := ship.task_of(2)
	assert_eq(first["done"], 1)
	_plot({3: {"code": "RR", "params": {}}})
	ctrl.begin_turn_tasks(MOVE)
	assert_eq(ship.task_by_seq(int(first["seq"]))["ended"], CrewTaskController.ABANDONED)
	assert_eq(ship.task_of(3)["code"], "RR")
	assert_eq(ship.task_of(3)["done"], 0)


func test_manual_repair_carries_over_without_a_new_plot() -> void:
	# Spec §0.1 Q-UX2 (4.A.3): a task in progress stays with its section until the player moves it.
	CrewFixtures.allow_rigging_repair(ship, 2)
	_plot({2: {"code": "RR", "params": {}}})
	_turn()
	assert_false(bool(ship.plotted_actions.get("crew_plotted", true)), "plot cleared for the next turn")
	assert_eq(ctrl.current_plan("rep")["assignments"], {2: {"code": "RR", "params": {}}})
	_turn()
	assert_eq(ship.task_of(2)["done"], 2)


func test_progress_warning_before_moving_a_repair() -> void:
	# Spec §4.4 (4.A.3): S3 has 2 of 4 turns on rigging repair; moving it asks first.
	CrewFixtures.allow_rigging_repair(ship, 2)
	_plot({2: {"code": "RR", "params": {}}})
	_turn()
	_turn()
	var plan := ctrl.current_plan("rep")
	assert_eq(CrewRules.progress_warning(ship, plan, 2, CrewRules.STATION_GUNS),
		"S3 has 2 of 4 turns on rigging repair. Moving it loses them (4.A.3).")
	assert_eq(CrewRules.progress_warning(ship, plan, 2, CrewRules.STATION_RR), "", "staying put")


# --- The 4-MP limit (8.F.3b) ---

func test_row46_hull_repair_lost_above_four_mps() -> void:
	# Spec §8 #46 (8.F.3b, "move <= 4 MPs" checked against the PDF): RH in progress; the ship uses
	# 5 MPs (turns counted): lost. With 4 MPs it is kept and the g-t counts.
	CrewFixtures.allow_hull_repair(ship, 2)
	_plot({2: {"code": "RH", "params": {}}})
	ctrl.begin_turn_tasks(MOVE)
	GameState.ship_controller.set_mp_used("rep", 4)
	ctrl.after_movement(MOVE)
	assert_eq(ship.task_of(2)["code"], "RH")
	ctrl.advance_tasks(STATUS)
	assert_eq(ship.task_of(2)["done"], 1)
	GameState.ship_controller.clear_turn_flags("rep")
	GameState.current_turn += 1
	ctrl.begin_turn_tasks(MOVE)
	var seq := int(ship.task_of(2)["seq"])
	GameState.ship_controller.set_mp_used("rep", 5)
	ctrl.after_movement(MOVE)
	assert_eq(ship.task_by_seq(seq)["ended"], RepairController.ENDED_MOVED)
	assert_eq(ship.sections_able_to_fire(), 3, "S3 was plotted to a task this g-t (spec 0.3 #2)")
	var crew := _events(PhaseEvents.Type.CREW_TASK)
	assert_eq(crew[-1].data["state"], "cancelled")
	assert_eq(crew[-1].data["reason"], RepairController.ENDED_MOVED)


func test_hull_repair_with_five_mps_plotted_warns_and_automatic_skips_it() -> void:
	# 8.F.3b: with more than 4 MPs in the movement plot the RH station warns; Automatic does not
	# start (A5) or continue (A2) a hull repair.
	CrewFixtures.allow_hull_repair(ship)
	var ctx := _ctx()
	ctx["plotted_mps"] = 5
	var st: Dictionary = {}
	for s in CrewRules.stations(ship, {"assignments": {}, "orders": {}}, ctx):
		if s["id"] == CrewRules.STATION_RH:
			st = s
	assert_string_contains(st["warning"], "8.F.3b")
	var a: Dictionary = CrewAuto.allocate(ship, {"sail_target": ""}, ctx)["assignments"]
	assert_false(a.has(ShipState.MARINES), "no hull repair at 5 MPs")
	ctx["plotted_mps"] = 4
	a = CrewAuto.allocate(ship, {"sail_target": ""}, ctx)["assignments"]
	assert_eq(a[ShipState.MARINES], {"code": "RH", "params": {}})


# --- Completing repairs (8.F.5) ---

func test_row49_box_goes_to_the_section_taking_damage() -> void:
	# Spec §8 #49 (8.F.5): rigging section 1 at 3 of 5; the repair goes there: 4.
	ship.rigging_current_hp[0] = 3
	assert_eq(GameState.ship_controller.repair_box("rep", "rigging"), 0)
	assert_eq(ship.rigging_current_hp[0], 4)


func test_row50_full_section_sends_the_box_to_the_one_before() -> void:
	# Spec §8 #50 (8.F.5 example): rigging section 1 at 0, section 2 full: the box goes to
	# section 1, giving rigging level 4 again.
	ship.rigging_current_hp[0] = 0
	assert_eq(ship.rigging_level(), 3)
	assert_eq(GameState.ship_controller.repair_box("rep", "rigging"), 0)
	assert_eq(ship.rigging_current_hp[0], 1)
	assert_eq(ship.rigging_level(), 4)


func test_row51_restored_rigging_section_lost_again_is_not_checked() -> void:
	# Spec §8 #51 (8.F.5 example, 9.B.2): section 1 emptied (Rigging Check), repaired, emptied
	# again: no second Rigging Check, no morale check.
	var crits: CriticalHitController = GameState.critical_hit_controller
	GameState.damage_controller.apply_hits("rep", 5, 0, 0, "other", COMBAT)
	assert_eq(crits.pending_checks(), 1, "the first loss is checked (7.D.7)")
	assert_true(ship.checked_sections["rigging"][0])
	GameState.critical_hit_controller = CriticalHitController.new(GameState)
	GameState.critical_hit_controller.hold()
	GameState.ship_controller.repair_box("rep", "rigging")
	var noted := _events(PhaseEvents.Type.MORALE_NOTED).size()
	GameState.damage_controller.apply_hits("rep", 1, 0, 0, "other", COMBAT)
	assert_eq(ship.rigging_current_hp[0], 0)
	assert_eq(GameState.critical_hit_controller.pending_checks(), 0, "no second Rigging Check")
	assert_eq(_events(PhaseEvents.Type.MORALE_NOTED).size(), noted, "no morale check")


func test_row52_restored_hull_section_lost_again_dismounts_no_guns() -> void:
	# Spec §8 #52 (8.F.5, 9.B.2, spec 0.3 #7): hull section 1 emptied (1 gun, Hull Check, 1 MC),
	# repaired, emptied again: no Hull Check, no MC, no guns dismounted again.
	GameState.damage_controller.apply_hits("rep", 0, 5, 0, "other", COMBAT)
	assert_eq(ship.guns_dismounted, [1, 1] as Array[int])
	assert_eq(GameState.critical_hit_controller.pending_checks(), 1)
	var mcs := ship.pending_morale_checks
	GameState.critical_hit_controller = CriticalHitController.new(GameState)
	GameState.critical_hit_controller.hold()
	GameState.ship_controller.repair_box("rep", "hull")
	assert_eq(ship.hull_current_hp[0], 1)
	GameState.damage_controller.apply_hits("rep", 0, 1, 0, "other", COMBAT)
	assert_eq(ship.hull_current_hp[0], 0)
	assert_eq(ship.guns_dismounted, [1, 1] as Array[int], "guns are marked once")
	assert_eq(GameState.critical_hit_controller.pending_checks(), 0, "no second Hull Check")
	assert_eq(ship.pending_morale_checks, mcs, "no second MC")
	assert_eq(_events(PhaseEvents.Type.GUNS_DISMOUNTED).size(), 1)


func test_rigging_repair_completes_through_the_engine() -> void:
	# 8.F.5: RR at CQ B, 4 g-t's by the same section; one box back, REPAIR logged, the section
	# is free again (spec §0.1 Q7: one box per task).
	ship.rigging_current_hp[0] = 2
	_plot({2: {"code": "RR", "params": {}}})
	for i in range(3):
		_turn()
	assert_eq(ship.rigging_current_hp[0], 2)
	_turn()
	assert_eq(ship.rigging_current_hp[0], 3)
	var repairs := _events(PhaseEvents.Type.REPAIR)
	assert_eq(repairs.size(), 1)
	assert_eq([repairs[0].data["kind"], repairs[0].data["section"]], ["rigging", 0])
	assert_eq(repairs[0].to_text({}), "rep repairs a rigging box in section 1 (S3)")
	assert_eq(ship.task_of(2), {})
	assert_eq(ctrl.current_plan("rep")["assignments"], {}, "back at the guns")


# --- Dismasted ships (8.F.6, spec 0.2 Q6) ---

func _dismasted_rr(done: int) -> int:
	ship.crew_quality = "D"
	ship.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	ship.sail_state = "NS"
	var seq := GameState.ship_controller.add_task("rep", {"code": "RR", "sections": [2], "params": {}})
	GameState.ship_controller.update_task("rep", seq, {"done": done})
	ship.plotted_sections = [2] as Array[int]
	return seq


func test_row53_rigging_hit_on_a_dismasted_ship_cancels_rr_progress() -> void:
	# Spec §8 #53 (8.F.6 example): dismasted, CQ D, RR 5 of 6; a fire's 1R: progress back to 0,
	# the task goes on, and the g-t of the hit does not count.
	var seq := _dismasted_rr(5)
	GameState.damage_controller.apply_hits("rep", 1, 0, 0, "other", STATUS, "", {}, FireController.DAMAGE_FIRE)
	assert_eq(ship.task_by_seq(seq)["done"], 0)
	assert_eq(ship.task_by_seq(seq)["ended"], "")
	ctrl.advance_tasks(STATUS)
	assert_eq(ship.task_by_seq(seq)["done"], 0, "the g-t of the hit is cancelled too")
	var crew := _events(PhaseEvents.Type.CREW_TASK)
	assert_eq(crew[-1].data["state"], "reset")
	assert_eq(crew[-1].data["done"], 5)
	assert_string_contains(crew[-1].to_text({}), RepairController.RESET_DISMASTED)


func test_row53_gunfire_r_on_a_dismasted_ship_cancels_rr_progress() -> void:
	# Spec §8 #53, 0.3 #6: a gunfire result with an r marks nothing on a dismasted ship
	# (GunneryResolver zeroes it) but still counts as a rigging hit.
	var seq := _dismasted_rr(3)
	GameState.damage_controller.rigging_hit_while_dismasted("rep", COMBAT)
	assert_eq(ship.task_by_seq(seq)["done"], 0)


func test_rigging_hit_on_a_masted_ship_keeps_progress() -> void:
	# 8.F.6: "This only applies to dismasted ships."
	ship.rigging_current_hp[0] = 3
	var seq := GameState.ship_controller.add_task("rep", {"code": "RR", "sections": [2], "params": {}})
	GameState.ship_controller.update_task("rep", seq, {"done": 2})
	GameState.damage_controller.apply_hits("rep", 1, 0, 0, "other", COMBAT)
	assert_eq(ship.task_by_seq(seq)["done"], 2)


func test_row54_dismasted_repair_goes_to_section_four() -> void:
	# Spec §8 #54 (0.2 Q6, 8.F.5): dismasted, RR completes: rigging section 4 has 1 box, rigging
	# level 1, and the ship is still furled (NS) until it alters sail.
	var seq := _dismasted_rr(5)
	ctrl.advance_tasks(STATUS)
	assert_eq(ship.task_by_seq(seq)["ended"], CrewTaskController.COMPLETED)
	assert_eq(ship.rigging_current_hp, [0, 0, 0, 1] as Array[int])
	assert_eq(ship.rigging_level(), 1)
	assert_eq(ship.sail_state, "NS")


# --- Victory points (Scenario Book VI.B.4) ---

func test_row55_repaired_section_yields_no_points() -> void:
	# Spec §8 #55 (VI.B.4): rigging section 1 at 0 scores 5 %; after a repair there, nothing.
	ship.rigging_current_hp[0] = 0
	var before: float = GameState.victory_controller.points_lost(ship)
	assert_almost_eq(before, 5.0, 0.001)
	GameState.ship_controller.repair_box("rep", "rigging")
	assert_almost_eq(GameState.victory_controller.points_lost(ship), 0.0, 0.001)


# --- Automatic rule A5 (spec §3.3, §9 Q3) ---

func test_row22_automatic_repairs_marines_in_action_sailors_out_of_range() -> void:
	# Spec §8 #22: rigging and hull boxes missing, FS, enemy at 10 hexes, M free: M on RR, no RH
	# (sailors stay at the guns). Enemy at 16: S4 on RH as well.
	CrewFixtures.allow_rigging_repair(ship)
	CrewFixtures.allow_hull_repair(ship)
	var enemy := _make_ship("enemy", 1, Vector2i(11, 0))
	assert_eq(GameState.fire_geometry.range_between(ship.occupied_hexes(), enemy.occupied_hexes()), 10)
	var a: Dictionary = CrewAuto.allocate(ship, {"sail_target": ""}, _ctx())["assignments"]
	assert_eq(a, {ShipState.MARINES: {"code": "RR", "params": {}}})
	enemy.hex_position = Vector2i(17, 0)
	assert_eq(GameState.fire_geometry.range_between(ship.occupied_hexes(), enemy.occupied_hexes()), 16)
	a = CrewAuto.allocate(ship, {"sail_target": ""}, _ctx())["assignments"]
	assert_eq(a, {ShipState.MARINES: {"code": "RR", "params": {}}, 3: {"code": "RH", "params": {}}})


func test_a5_order_shrouds_then_rigging_then_hull() -> void:
	# Spec §3.3 A5: RS, RR, RH in that order, in worker order (M, S4, S3) with no enemy near.
	GameState.ship_controller.add_critical_effect("rep", {"id": "shrouds_severed", "turn": 0})
	CrewFixtures.allow_rigging_repair(ship)
	CrewFixtures.allow_hull_repair(ship)
	var a: Dictionary = CrewAuto.allocate(ship, {"sail_target": ""}, _ctx())["assignments"]
	assert_eq(a, {ShipState.MARINES: {"code": "RS", "params": {}}, 3: {"code": "RR", "params": {}},
		2: {"code": "RH", "params": {}}})


func test_a5_no_rigging_repair_above_fs() -> void:
	# A5 with 8.F.3a: at MS the rigging is not repaired.
	CrewFixtures.allow_rigging_repair(ship)
	ship.sail_state = "MS"
	assert_eq(CrewAuto.allocate(ship, {"sail_target": ""}, _ctx())["assignments"], {})


func test_a2_rigging_repair_dropped_when_sail_goes_above_fs() -> void:
	# A2 with 8.F.3a, 8.F.4: RR in progress, the ship now carries MS: dropped (progress lost).
	CrewFixtures.allow_rigging_repair(ship)
	GameState.ship_controller.add_task("rep", {"code": "RR", "sections": [ShipState.MARINES], "params": {}})
	ship.sail_state = "MS"
	assert_eq(CrewAuto.allocate(ship, {"sail_target": ""}, _ctx())["assignments"], {})


func test_automatic_repair_runs_to_completion() -> void:
	# A2 + A5 through the engine: the marines repair rigging at CQ B in 4 g-t's, then (with more
	# to do) start again from 0 (spec §0.1 Q7).
	ship.rigging_current_hp[0] = 3
	for i in range(4):
		_turn()
	assert_eq(ship.rigging_current_hp[0], 4)
	_turn()
	assert_eq(ship.task_of(ShipState.MARINES)["done"], 1, "a new task for the next box")


func test_struck_ship_makes_no_repairs() -> void:
	# Spec §3.7: struck and destroyed ships plot no repairs.
	CrewFixtures.allow_rigging_repair(ship)
	ship.status = ShipState.Status.STRUCK
	assert_eq(_station(CrewRules.STATION_RR), {})
	assert_ne(RepairController.refusal(ship, "RR"), "")
