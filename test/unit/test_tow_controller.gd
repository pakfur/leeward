extends GutTest
## TowController's tow step (towing spec §4, §6; Close Action 12.A.4, 12.A.9): the tow attempt in
## the Grappling sub-phase (a grapple roll, d10 + DRMs <= 2 with the towing -1), the TX cut in SoP
## V.B, and the automatic cuts when a ship strikes, blows up, is taken or runs aground.

const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
const COMBAT := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const DRIFT := TurnPhaseController.GamePhase.DRIFT_CALCULATION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT
const MORALE := TurnPhaseController.GamePhase.MORALE_CHECK

var pc: TurnPhaseController
var tows: TowController
var sc: ShipStateController
var _dice: ScriptedDice
var _old_dice: Dice
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
	pc = GameState.phase_controller
	tows = GameState.tow_controller
	sc = GameState.ship_controller
	_old_dice = GameState.dice
	_old_scenario = GameState.active_scenario
	_old_env = GameState.environment
	_old_phase = pc.current_phase
	_old_turn = GameState.current_turn
	_old_log = GameState.turn_log
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 5
	GameState.turn_log = GameState.new_turn_log(5)
	# Facing 3 (W): t's stern is (6, 5), the hex ahead of w's bow (7, 5) (12.A.4a).
	var t := _make_ship("t", Vector2i(5, 5), 0)
	t.tow_prepared = true
	var w := _make_ship("w", Vector2i(7, 5), 0)
	w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	w.sail_state = "NS"
	assert_true(TowRules.in_position(t, w))
	t.plotted_actions["crew_orders"] = {"tow": "take:w"}


func after_each() -> void:
	pc._reset_maintenance()
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = _old_phase
	GameState.dice = _old_dice
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
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
		"point_costs": {"C4": 100},
	})
	var state := ShipState.new()
	state.initialize_from_scenario({"position": {"q": hex.x, "r": hex.y}, "facing": 3}, ship_def)
	state.side = side
	state.crew_quality = "C"
	state.starting_crew_quality = "C"
	state.morale_rating = 4
	state.crew_auto = false
	state.mp_used_this_turn = 0
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


func _ship(id: String) -> ShipState:
	return GameState.get_ship(id)


func _events(type: PhaseEvents.Type) -> Array:
	return GameState.turn_log.of_type(type)


func _modifier_names(ev) -> Array:
	return (ev.data["modifiers"] as Array).map(func(m): return str(m["name"]))


func _tx(ship_id: String, started: int) -> int:
	return sc.add_task(ship_id, {"code": "TX", "sections": [3], "params": {}, "started_turn": started})


func test_attempt_succeeds_with_towing_drm() -> void:
	_dice.queue([5])
	tows.resolve_tow_attempts(STATUS)
	var t := _ship("t")
	assert_eq(t.towing_id, "w")
	assert_eq(_ship("w").towed_by, "t")
	var begun := _events(PhaseEvents.Type.TOW_BEGUN)
	assert_eq(begun.size(), 1)
	var ev = begun[0]
	assert_eq(ev.ship_id, "t")
	assert_eq(ev.target_id, "w")
	assert_eq(int(ev.data["roll"]), 5)
	assert_eq(int(ev.data["modifier"]), -3)
	assert_eq(int(ev.data["needed"]), 2)
	assert_eq(int(ev.data["total"]), 2)
	assert_true(ev.data["success"])
	var names := _modifier_names(ev)
	for name in ["towing", "skill", "target_did_not_move"]:
		assert_has(names, name)
	assert_eq(t.tow_order(), "")
	assert_false(t.tow_prepared)
	assert_eq(_dice.remaining(), 0)


func test_attempt_fails_order_stands() -> void:
	_dice.queue([6])
	tows.resolve_tow_attempts(STATUS)
	var t := _ship("t")
	assert_false(t.is_towing())
	var begun := _events(PhaseEvents.Type.TOW_BEGUN)
	assert_eq(begun.size(), 1)
	assert_false(begun[0].data["success"])
	assert_eq(int(begun[0].data["total"]), 3)
	assert_eq(t.tow_order(), "take:w")
	assert_true(t.tow_prepared)


func test_no_roll_when_illegal() -> void:
	_make_ship("x", Vector2i(7, 6), 0)
	assert_true(sc.add_grapple("w", "x"))
	tows.resolve_tow_attempts(STATUS)
	assert_false(_ship("t").is_towing())
	assert_eq(_events(PhaseEvents.Type.TOW_BEGUN).size(), 0)
	assert_eq(_ship("t").tow_order(), "take:w")
	assert_true(_ship("t").tow_prepared)


func test_unprepared_tower_does_not_roll() -> void:
	_ship("t").tow_prepared = false
	tows.resolve_tow_attempts(STATUS)
	assert_eq(_events(PhaseEvents.Type.TOW_BEGUN).size(), 0)
	assert_eq(_ship("t").tow_order(), "take:w")


func test_order_lapses_when_target_struck() -> void:
	# A standing order whose target may no longer be taken in tow lapses at the attempt, with one
	# event and no die (controller ruling).
	_ship("w").status = ShipState.Status.STRUCK
	tows.resolve_tow_attempts(STATUS)
	assert_false(_ship("t").is_towing())
	assert_eq(_ship("t").tow_order(), "")
	var begun := _events(PhaseEvents.Type.TOW_BEGUN)
	assert_eq(begun.size(), 1)
	assert_false(begun[0].data["success"])
	assert_string_contains(str(begun[0].data["lapsed"]), "has struck")
	assert_false(begun[0].data.has("roll"))
	assert_eq(begun[0].to_text({"t": "HMS t", "w": "HMS w"}),
		"HMS t's order to take HMS w in tow lapses: w has struck: a ship that has surrendered is not towed (ruling)")


func test_order_lapses_for_unknown_target() -> void:
	_ship("t").plotted_actions["crew_orders"] = {"tow": "take:nobody"}
	tows.resolve_tow_attempts(STATUS)
	assert_eq(_ship("t").tow_order(), "")
	var begun := _events(PhaseEvents.Type.TOW_BEGUN)
	assert_eq(begun.size(), 1)
	assert_eq(str(begun[0].data["lapsed"]), "Unknown ship")


func test_attempt_runs_before_grapple_step() -> void:
	_dice.queue([5])
	pc.current_phase = DRIFT
	pc._enter_status_adjustment_phase()
	assert_true(_ship("t").is_towing())
	assert_eq(_dice.remaining(), 0)


func test_no_grapple_within_a_tow() -> void:
	# The two ends of one tow are not offered a grapple (12.A): no option, no GRAPPLE pause.
	assert_true(tows.begin("t", "w", STATUS))
	_ship("t").plotted_actions["crew_orders"] = {}
	var gc: GrapplingController = GameState.grappling_controller
	assert_eq(gc.grapple_error("t", "w"), "w is at the other end of t's tow (12.A)")
	assert_eq(gc.grapple_error("w", "t"), "t is at the other end of w's tow (12.A)")
	assert_eq(pc.maintenance_options(0, TurnPhaseController.MaintenanceStep.GRAPPLE), [])
	pc.maintenance_prompt_player_ids = [0] as Array[int]
	watch_signals(pc)
	pc.current_phase = DRIFT
	pc._enter_status_adjustment_phase()
	assert_signal_not_emitted(pc, "maintenance_orders_requested")
	assert_eq(_events(PhaseEvents.Type.GRAPPLE).size(), 0)
	assert_eq(_dice.remaining(), 0)


func test_failed_tow_attempt_is_the_grapple_at_that_ship() -> void:
	# A tow attempt rolled this g-t was that ship's grapple at her target (8.C.1, 12.A.4b).
	_dice.queue([6])
	tows.resolve_tow_attempts(STATUS)
	var gc: GrapplingController = GameState.grappling_controller
	assert_string_contains(gc.grapple_error("t", "w"), "tried to take w in tow this turn")
	assert_false(gc.grapple_options("t").has("w"))
	assert_eq(gc.grapple_error("w", "t"), "")  # w rolled nothing


func test_lapsed_order_does_not_block_grapple() -> void:
	_ship("t").plotted_actions["crew_orders"] = {"tow": "take:nobody"}
	tows.resolve_tow_attempts(STATUS)
	assert_eq(GameState.grappling_controller.grapple_error("t", "w"), "")


func test_tow_attempt_rolls_before_grapples() -> void:
	# Dice order in one Grappling sub-phase: the tow attempts' d10s, then the grapples' d10s.
	var g := _make_ship("g", Vector2i(5, 8), 0)
	var x := _make_ship("x", Vector2i(5, 9), 0)
	pc.maintenance_prompt_player_ids = [0] as Array[int]
	_dice.queue([5, 4])
	pc.current_phase = DRIFT
	pc._enter_status_adjustment_phase()
	assert_true(_ship("t").is_towing())  # the d10 5: 5 - 3 = 2
	assert_eq(pc.player_submit_maintenance_orders(0, {"grapple": [["g", "x"]]}), "")
	assert_true(g.is_grappled_to("x"))  # the d10 4: 4 - 2 = 2
	assert_eq(int(_events(PhaseEvents.Type.GRAPPLE)[0].data["roll"]), 4)
	assert_eq(_dice.remaining(), 0)
	assert_eq(pc.player_submit_maintenance_orders(0, {"ungrapple": []}), "")
	assert_true(x.is_grappled_to("g"))


func test_tx_cuts_in_v_b() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	_tx("w", GameState.current_turn)
	tows.resolve_cuts(DRIFT)
	assert_false(_ship("t").is_towing())
	assert_false(_ship("w").is_towed())
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(cuts[0].ship_id, "t")
	assert_eq(cuts[0].target_id, "w")
	assert_eq(str(cuts[0].data["cause"]), "tx")
	assert_eq(str(cuts[0].data["by"]), "w")


func test_tx_begun_last_turn_does_not_cut() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	_tx("w", GameState.current_turn - 1)
	tows.resolve_cuts(DRIFT)
	assert_true(_ship("t").is_towing())
	assert_eq(_events(PhaseEvents.Type.TOW_CUT).size(), 0)


func test_tx_on_both_ships_cuts_once() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	_tx("t", GameState.current_turn)
	_tx("w", GameState.current_turn)
	tows.resolve_cuts(DRIFT)
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(str(cuts[0].data["by"]), "t")


func test_tx_begun_this_turn_not_cancelled_after_cut() -> void:
	# V.B cuts the tow; the TX then completes in the crew tasks instead of being cancelled "no tow".
	assert_true(tows.begin("t", "w", STATUS))
	var seq := _tx("t", GameState.current_turn)
	tows.resolve_cuts(DRIFT)
	var t := _ship("t")
	assert_eq(tows.cancel_reason(t, t.task_by_seq(seq)), "")
	t.task_by_seq(seq)["started_turn"] = GameState.current_turn - 1
	assert_eq(tows.cancel_reason(t, t.task_by_seq(seq)), "no tow")


func test_cut_in_drift_phase() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	_tx("t", GameState.current_turn)
	for id in ["t", "w"]:
		_ship(id).speed = 2
		_ship(id).moved_this_turn = true
	pc.current_phase = COMBAT
	pc._enter_drift_calculation_phase()
	assert_false(_ship("t").is_towing())
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(str(cuts[0].data["cause"]), "tx")


func test_cut_false_without_tow() -> void:
	assert_false(tows.cut("t", "tx", DRIFT, "t"))
	assert_eq(_events(PhaseEvents.Type.TOW_CUT).size(), 0)


func test_strike_cuts() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	GameState.damage_controller.strike("w", "morale", MORALE)
	assert_false(_ship("t").is_towing())
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(str(cuts[0].data["cause"]), "struck")


func test_destroy_cuts() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	GameState.damage_controller.destroy("t", "explosion", STATUS)
	assert_false(_ship("w").is_towed())
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(str(cuts[0].data["cause"]), "destroyed")


func test_taken_cuts() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	GameState.transfer_control("w", 1)
	tows.on_ship_changed("w", COMBAT)
	assert_false(_ship("t").is_towing())
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(str(cuts[0].data["cause"]), "taken")


func test_dismasted_tower_casts_off() -> void:
	# Ruling: a dismasted ship cannot tow, so a tower that loses her last rigging casts off her tow.
	assert_true(tows.begin("t", "w", STATUS))
	_ship("t").checked_sections["rigging"] = [true, true, true, true]  # no Rigging Checks to roll
	GameState.damage_controller.apply_hits("t", 22, 0, 0, "other", COMBAT)
	assert_true(_ship("t").is_dismasted())
	assert_false(_ship("t").is_towing())
	assert_false(_ship("w").is_towed())
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(str(cuts[0].data["cause"]), "dismasted")
	assert_eq(cuts[0].to_text({"t": "HMS t", "w": "HMS w"}),
		"The tow between HMS t and HMS w parts: the tower is dismasted")


func test_dismasted_tow_holds() -> void:
	# w is already dismasted (the usual tow); more rigging hits on her do not part the tow.
	assert_true(tows.begin("t", "w", STATUS))
	_ship("w").rigging_current_hp = [1, 0, 0, 0] as Array[int]
	_ship("w").checked_sections["rigging"] = [true, true, true, true]
	GameState.damage_controller.apply_hits("w", 1, 0, 0, "other", COMBAT)
	assert_true(_ship("w").is_dismasted())
	assert_true(_ship("t").is_towing())
	assert_eq(TowRules.broken_reason(_ship("t"), _ship("w")), "")


func test_unbroken_tow_not_cut() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	tows.on_ship_changed("w", COMBAT)
	assert_true(_ship("t").is_towing())
	assert_eq(_events(PhaseEvents.Type.TOW_CUT).size(), 0)


func test_ground_cuts() -> void:
	assert_true(tows.begin("t", "w", STATUS))
	GameState.map_controller.ground("w", {"cause": "drift", "terrain": "shoal",
		"hex": {"q": 7, "r": 5}, "depth": 1, "draft": 2}, MOVE)
	assert_false(_ship("t").is_towing())
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(str(cuts[0].data["cause"]), "aground")


func test_grapple_chance_default_unchanged() -> void:
	var chance := GameState.grappling_controller.grapple_chance("t", "w")
	var names: Array = (chance["modifiers"] as Array).map(func(m): return str(m["name"]))
	assert_does_not_have(names, "towing")
	var towing := GameState.grappling_controller.grapple_chance("t", "w", true)
	assert_eq(int(towing["modifier"]), int(chance["modifier"]) - 1)


func test_tow_lines_in_log() -> void:
	var names := {"t": "HMS t", "w": "HMS w"}
	_dice.queue([5])
	tows.resolve_tow_attempts(STATUS)
	var begun: String = _events(PhaseEvents.Type.TOW_BEGUN)[0].to_text(names)
	assert_string_contains(begun, "HMS t takes HMS w in tow")
	assert_string_contains(begun, "d10 5")
	assert_string_contains(begun, "≤ 2")
	GameState.damage_controller.strike("w", "morale", MORALE)
	var cut: String = _events(PhaseEvents.Type.TOW_CUT)[0].to_text(names)
	assert_eq(cut, "The tow between HMS t and HMS w parts: a ship has struck")


func test_failed_and_tx_lines_in_log() -> void:
	var names := {"t": "HMS t", "w": "HMS w"}
	_dice.queue([6])
	tows.resolve_tow_attempts(STATUS)
	var failed: String = _events(PhaseEvents.Type.TOW_BEGUN)[0].to_text(names)
	assert_string_contains(failed, "HMS t fails to pass a tow to HMS w")
	assert_string_contains(failed, "> 2")
	assert_true(tows.begin("t", "w", STATUS))
	_tx("w", GameState.current_turn)
	tows.resolve_cuts(DRIFT)
	assert_eq(_events(PhaseEvents.Type.TOW_CUT)[0].to_text(names),
		"The tow between HMS t and HMS w is cut by HMS w")


func test_client_refuses() -> void:
	tows.is_server = false
	tows.resolve_tow_attempts(STATUS)
	tows.is_server = true
	assert_push_error("Cannot")
	assert_false(_ship("t").is_towing())
