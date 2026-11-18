extends GutTest
## Towing in the crew plan (towing spec §3; Close Action 12.A.3, 12.A.9): TowController as the PT/TX
## crew-task handler, the tow crew order checked by plot_crew, the Automatic tow order (rule A2d) and
## manual plans made legal by CrewRules.normalize through TowRules.refusal.

const PLANNING := TurnPhaseController.GamePhase.PLANNING
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT

var _old_scenario: Dictionary
var _old_env: EnvironmentState
var _old_phase: TurnPhaseController.GamePhase
var _old_turn: int
var _old_log: PhaseEvents.PhaseLog
var ctrl: CrewTaskController
var sc: ShipStateController


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
	GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.phase_controller.current_phase = PLANNING
	GameState.current_turn = 5
	GameState.turn_log = GameState.new_turn_log(5)
	ctrl = GameState.crew_task_controller
	sc = GameState.ship_controller
	_make_ship("t", Vector2i(5, 5), 0)
	_make_ship("w", Vector2i(7, 5), 0)
	_make_ship("e", Vector2i(20, 20), 1)


func after_each() -> void:
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
	GameState.phase_controller.current_phase = _old_phase
	GameState.current_turn = _old_turn
	GameState.turn_log = _old_log
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, side: int) -> ShipState:
	var ship_def := Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	var state := ShipState.new()
	state.initialize_from_scenario({"position": {"q": hex.x, "r": hex.y}, "facing": 3}, ship_def)
	state.side = side
	state.crew_quality = "C"
	state.crew_auto = false
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


func _ship(id: String) -> ShipState:
	return GameState.get_ship(id)


func _tow_codes(plan: Dictionary) -> Dictionary:
	var out := {}
	var assignments: Dictionary = plan.get("assignments", {})
	for s in assignments:
		if TowRules.is_code(str(assignments[s].get("code", ""))):
			out[int(s)] = str(assignments[s]["code"])
	return out


func _plot_order(id: String, tow: String) -> String:
	return ctrl.plot_crew(0, id, {"assignments": {}, "orders": {"tow": tow}})


func _live_pt(section: int, done: int = 0, started: int = 4) -> int:
	var seq := sc.add_task("t", {"code": "PT", "sections": [section], "params": {},
		"done": done, "started_turn": started})
	sc.set_plotted_sections("t", [section])
	return seq


func test_pt_handler_registered() -> void:
	assert_not_null(GameState.tow_controller)
	assert_eq(ctrl.handler("PT"), GameState.tow_controller)
	assert_eq(ctrl.handler("TX"), GameState.tow_controller)


func test_plot_take_order_places_pt_automatic() -> void:
	_ship("t").crew_auto = true
	assert_eq(_plot_order("t", "take:w"), "")
	assert_eq(_tow_codes(ctrl.current_plan("t")), {ShipState.MARINES: "PT"})


func test_take_order_refused_for_enemy_and_unknown() -> void:
	assert_string_contains(_plot_order("t", "take:e"), "12.A.2")
	assert_string_contains(_plot_order("t", "take:nobody"), "Unknown ship")
	assert_eq(_plot_order("t", "tow"), "Unknown tow order tow")


func test_standing_take_order_kept_when_target_strikes() -> void:
	_ship("t").crew_auto = true
	assert_eq(_plot_order("t", "take:w"), "")
	assert_eq(_ship("t").tow_order(), "take:w")
	_ship("w").status = ShipState.Status.STRUCK
	# The unchanged standing order is not re-checked: the plot is accepted, and no PT is placed.
	assert_eq(_plot_order("t", "take:w"), "")
	assert_true(_tow_codes(ctrl.current_plan("t")).is_empty())
	# A new order naming the struck ship is refused.
	assert_eq(_plot_order("t", ""), "")
	assert_string_contains(_plot_order("t", "take:w"), "has struck")


func test_no_pt_when_prepared() -> void:
	var t := _ship("t")
	t.crew_auto = true
	t.tow_prepared = true
	assert_eq(_plot_order("t", "take:w"), "")
	assert_true(_tow_codes(ctrl.current_plan("t")).is_empty())


func test_pt_in_progress_continues() -> void:
	_ship("t").crew_auto = true
	_live_pt(3, 1, 4)
	assert_eq(_plot_order("t", "take:w"), "")
	assert_eq(_tow_codes(ctrl.current_plan("t")), {3: "PT"})


func test_cut_order_places_tx() -> void:
	_ship("t").crew_auto = true
	_ship("w").crew_auto = true
	assert_eq(_plot_order("w", "cut"), "")
	assert_true(_tow_codes(ctrl.current_plan("w")).is_empty(), "no TX on an untowed ship")
	assert_true(sc.begin_tow("t", "w"))
	assert_eq(_plot_order("t", "cut"), "")
	var codes := _tow_codes(ctrl.current_plan("t"))
	assert_eq(codes.size(), 1)
	assert_eq(codes.values(), ["TX"])


func test_manual_pt_tx_normalized() -> void:
	var t := _ship("t")
	var two_pt := {"assignments": {3: {"code": "PT"}, 2: {"code": "PT"}}, "orders": {}}
	# The warnings are made when the plan is normalized (the stored plan no longer holds the drop).
	var normalized := CrewRules.normalize(t, two_pt, CrewRules.context(GameState, t))
	assert_eq(_tow_codes(normalized), {2: "PT"})
	assert_eq(normalized["assignments"][2]["params"], {})
	assert_true(normalized["dropped"].has(3))
	var warned := false
	for w in normalized["warnings"]:
		warned = warned or ("12.A.3" in str(w) and str(w).begins_with(ShipState.SECTION_NAMES[3]))
	assert_true(warned, "the second PT is dropped with a 12.A.3 warning: %s" % [normalized["warnings"]])
	assert_eq(ctrl.plot_crew(0, "t", two_pt), "")
	assert_eq(_tow_codes(ctrl.current_plan("t")), {2: "PT"})
	var tx := {"assignments": {1: {"code": "TX"}}, "orders": {}}
	normalized = CrewRules.normalize(t, tx, CrewRules.context(GameState, t))
	assert_true(_tow_codes(normalized).is_empty())
	warned = false
	for w in normalized["warnings"]:
		warned = warned or "12.A.9" in str(w)
	assert_true(warned, "TX with no tow is dropped with a 12.A.9 warning: %s" % [normalized["warnings"]])
	assert_eq(ctrl.plot_crew(0, "t", tx), "")
	assert_true(_tow_codes(ctrl.current_plan("t")).is_empty())


func test_pt_completes_into_prepared() -> void:
	var t := _ship("t")
	var seq := _live_pt(ShipState.MARINES, 3, GameState.current_turn - 4)
	ctrl.advance_tasks(STATUS)
	assert_true(t.tow_prepared)
	assert_ne(str(t.task_by_seq(seq).get("ended", "")), "")


func test_pt_cancelled_once_towing() -> void:
	var t := _ship("t")
	var seq := _live_pt(ShipState.MARINES, 1)
	assert_eq(GameState.tow_controller.cancel_reason(t, t.task_by_seq(seq)), "")
	assert_true(sc.begin_tow("t", "w"))
	assert_eq(GameState.tow_controller.cancel_reason(t, t.task_by_seq(seq)), "towing")


func test_tx_cancelled_once_tow_gone() -> void:
	var t := _ship("t")
	assert_true(sc.begin_tow("t", "w"))
	# Begun last g-t: a TX begun this g-t made its own cut in V.B and is not cancelled (test_tow_controller).
	var seq := sc.add_task("t", {"code": "TX", "sections": [3], "params": {},
		"started_turn": GameState.current_turn - 1})
	assert_eq(GameState.tow_controller.cancel_reason(t, t.task_by_seq(seq)), "")
	assert_true(sc.cut_tow("t"))
	assert_eq(GameState.tow_controller.cancel_reason(t, t.task_by_seq(seq)), "no tow")


func test_prepare_uses_refusal() -> void:
	var t := _ship("t")
	assert_eq(GameState.tow_controller.prepare(t, {"code": "PT", "params": {}}), "")
	assert_string_contains(GameState.tow_controller.prepare(t, {"code": "TX", "params": {}}), "12.A.9")


func test_station_of_tow() -> void:
	assert_eq(CrewRules.station_of(4, {"code": "PT"}), "tow")
	assert_eq(CrewRules.station_of(1, {"code": "TX"}), TowRules.STATION)
