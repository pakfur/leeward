extends GutTest
## AnchorController, the crew-task handler of the anchoring codes (Close Action 13.B-F, SoP V.A-B;
## anchoring spec §3-§5), driven through the real crew-task engine: plot_crew, begin_turn_tasks,
## advance_tasks. Lengths from the ship log's Crew Task Order Codes: PBA 2 g-t's at CQ A-D (3 at
## E-G), PBS (5 ± SK) × 2 (CQ A, SK -3: 4 g-t's).

const PLANNING := TurnPhaseController.GamePhase.PLANNING
const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT

var ctrl: CrewTaskController
var sc: ShipStateController
var _old_scenario: Dictionary
var _old_env: EnvironmentState
var _old_phase: TurnPhaseController.GamePhase
var _old_turn: int
var _old_log: PhaseEvents.PhaseLog


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	_old_scenario = GameState.active_scenario
	_old_env = GameState.environment
	_old_phase = GameState.phase_controller.current_phase
	_old_turn = GameState.current_turn
	_old_log = GameState.turn_log
	GameState.active_scenario = {"anchoring": true}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.phase_controller.current_phase = PLANNING
	GameState.current_turn = 3
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	ctrl = GameState.crew_task_controller
	sc = GameState.ship_controller


func after_each() -> void:
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
	GameState.phase_controller.current_phase = _old_phase
	GameState.current_turn = _old_turn
	GameState.turn_log = _old_log
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, quality: String, facing: int = 3) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": 0, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
		"point_costs": {"B4": 100},
	})
	state.hex_position = Vector2i(0, 0)
	state.facing = facing
	state.sail_state = "FS"
	state.crew_quality = quality
	state.starting_crew_quality = quality
	state.morale_rating = 4
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_auto = false
	GameState.add_ship(state)
	return state


func _anchor_data(end: String = "bow", springs: bool = false) -> Dictionary:
	return {"hex": Vector2i(0, 0), "end": end, "springs": springs, "cable": 0, "veered": 0,
		"swing_dir": 0, "wind_dir": 0, "turn": 2}


## A manual plan of `code` on the marines (section 4), stored through the engine's request.
func _plot(ship: ShipState, code: String) -> void:
	GameState.phase_controller.current_phase = PLANNING
	assert_eq(ctrl.plot_crew(0, ship.ship_id, {"assignments": {4: {"code": code}}, "orders": {}}), "")


## One g-t of the task engine; the turn's flags are cleared at the end.
func _turn(ship: ShipState) -> void:
	ctrl.begin_turn_tasks(MOVE)
	ctrl.advance_tasks(STATUS)
	sc.clear_turn_flags(ship.ship_id)
	GameState.current_turn += 1


func _crew_events(code: String, state: String) -> Array:
	var out: Array = []
	for ev in GameState.turn_log.of_type(PhaseEvents.Type.CREW_TASK):
		if ev.data.get("code", "") == code and ev.data.get("state", "") == state:
			out.append(ev)
	return out


func test_handlers_registered() -> void:
	assert_not_null(GameState.anchor_controller)
	for code in AnchorRules.CODES:
		assert_eq(ctrl.handler(code), GameState.anchor_controller, code)


func test_pba_two_turns_then_ready() -> void:
	var ship := _make_ship("a", "C")
	_plot(ship, "PBA")
	_turn(ship)
	assert_eq(ship.anchor_ready, "")
	_plot(ship, "PBA")
	_turn(ship)
	assert_eq(ship.anchor_ready, "bow")
	assert_eq(_crew_events("PBA", "completed").size(), 1)


func test_pbs_after_anchoring_rigs_springs() -> void:
	# 13.B.2: springs prepared on a ship already anchored by the bow are rigged at once.
	var ship := _make_ship("a", "A")
	sc.drop_anchor(ship.ship_id, _anchor_data("bow", false))
	for i in 4:
		_plot(ship, "PBS")
		_turn(ship)
	assert_true(bool(ship.anchor.get("springs", false)))
	assert_false(ship.springs_ready)
	assert_eq(_crew_events("PBS", "completed").size(), 1)


func test_pbs_before_anchoring_sets_springs_ready() -> void:
	var ship := _make_ship("a", "A")
	sc.set_anchor_ready(ship.ship_id, "bow")
	for i in 3:
		_plot(ship, "PBS")
		_turn(ship)
	assert_false(ship.springs_ready)
	_plot(ship, "PBS")
	_turn(ship)
	assert_true(ship.springs_ready)
	assert_false(ship.is_anchored())


func test_anchor_with_mps_is_erased() -> void:
	# 13.C.1. End Planning (current_plan with end_planning, as begin_turn_tasks reads it) already
	# drops the A when the stored plot has MPs, so no task starts.
	var ship := _make_ship("a", "C")
	sc.set_anchor_ready(ship.ship_id, "bow")
	ship.speed = 2
	var steps := DefaultCourse.for_ship(GameState, ship)
	assert_eq(steps.size(), 2, "fixture: two forward steps available")
	sc.set_plotted_movement(ship.ship_id, DefaultCourse.as_dicts(steps))
	_plot(ship, "A")
	assert_eq(GameState.anchor_controller.actual_steps(ship), 2)
	var final := ctrl.current_plan(ship.ship_id, true)
	assert_true((final["dropped"] as Array).has(4))
	var warned := false
	for w in final["warnings"]:
		warned = warned or str(w).contains("13.C.1")
	assert_true(warned, "the erasure is explained (13.C.1)")
	ctrl.begin_turn_tasks(MOVE)
	assert_true(ship.tasks_with("A").is_empty())
	assert_true(GameState.anchor_controller.live_this_turn(ship, "A").is_empty())
	assert_eq(_crew_events("A", "started").size(), 0)


func test_anchor_with_default_course_is_erased() -> void:
	# 13.C.1: no course stored, so the ship sails its default course (6.G.2) of 2 MPs.
	var ship := _make_ship("a", "C")
	sc.set_anchor_ready(ship.ship_id, "bow")
	ship.speed = 2
	sc.clear_plotted_movement(ship.ship_id)
	_plot(ship, "A")
	assert_eq(GameState.anchor_controller.actual_steps(ship), 2)
	# The planning context counts the default course too (CrewRules.context plotted_mps), so End
	# Planning drops the anchoring with the 13.C.1 warning, as for a stored course; prepare() is the
	# backstop.
	var final_plan: Dictionary = ctrl.current_plan(ship.ship_id, true)
	assert_true(ShipState.MARINES in final_plan["dropped"])
	assert_string_contains("\n".join(PackedStringArray(final_plan["warnings"])), "13.C.1")
	ctrl.begin_turn_tasks(MOVE)
	assert_true(ship.tasks_with("A").is_empty())
	assert_eq(_crew_events("A", "started").size(), 0)


func test_anchor_with_no_mps_starts_this_turn() -> void:
	var ship := _make_ship("a", "C")
	sc.set_anchor_ready(ship.ship_id, "bow")
	ship.speed = 0
	sc.clear_plotted_movement(ship.ship_id)
	_plot(ship, "A")
	assert_eq(GameState.anchor_controller.actual_steps(ship), 0)
	ctrl.begin_turn_tasks(MOVE)
	var live: Dictionary = GameState.anchor_controller.live_this_turn(ship, "A")
	assert_eq(str(live.get("code", "")), "A")
	assert_eq(int(live.get("started_turn", -1)), 3)
	assert_true(GameState.anchor_controller.live_this_turn(ship, "PBA").is_empty())


func test_prep_cancelled_when_cable_cut() -> void:
	var ship := _make_ship("a", "A")
	sc.drop_anchor(ship.ship_id, _anchor_data("bow", false))
	_plot(ship, "PBS")
	ctrl.begin_turn_tasks(MOVE)
	assert_eq(ship.tasks_with("PBS").size(), 1)
	sc.cut_cable(ship.ship_id, GameState.current_turn)
	ctrl.advance_tasks(STATUS)
	assert_true(ship.tasks_with("PBS").is_empty())
	var cancelled := _crew_events("PBS", "cancelled")
	assert_eq(cancelled.size(), 1)
	if cancelled.size() == 1:
		assert_eq(str(cancelled[0].data.get("reason", "")), "no bow anchor")


func test_pba_cancelled_once_anchored() -> void:
	var ship := _make_ship("a", "C")
	_plot(ship, "PBA")
	ctrl.begin_turn_tasks(MOVE)
	sc.drop_anchor(ship.ship_id, _anchor_data("stern"))
	ctrl.advance_tasks(STATUS)
	var cancelled := _crew_events("PBA", "cancelled")
	assert_eq(cancelled.size(), 1)
	if cancelled.size() == 1:
		assert_eq(str(cancelled[0].data.get("reason", "")), "anchored")
