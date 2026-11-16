extends GutTest
## Boarders and boarding combat, to capture (Close Action 1997, 10.A-10.E, 10.G, 10.H.1-2, 4.B.1,
## 8.C.5, 8.D.4, 8.E.2, VI.B; boarding spec B4, §6 tests 8-9, 12-45, 47, 52 and the combat skip).
## Numbers from the Boarding Combat chart (p.109): BCF S/M by CQ: C 6/8, D 5/7, B 7/9, E 4/6;
## rows 2d6 <=4 2 %, 5 4 %, 6 6 %, 7 8 %, 8 10 %, 9 15 %, 10 20 %, 11 25 %, >=12 30 %; attacker
## specials 9-10 "d10 < defender's MR: captured", 11+ "captured"; defender specials 5-7 "d10 <
## attacker's MR: repulsed", 8-10 "repulsed, 1 MC", 11+ "repulsed, 2 MC". Odds DRMs (F:E, rounded
## down): 1:4 -4, 1:3 -3, 1:2 -2, 2:3 -1, 1:1 0, 3:2 +1, 2:1 +2, 3:1 +3, 4:1 +4. Other DRMs
## (attacker only): defender class 1 -3, 2 -2, 3 -1; -1 per class larger, +1 per class smaller.

const PHASE := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const M := ShipState.MARINES

var boarding: BoardingController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState
var _old_turn: int


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_env = GameState.environment
	_old_turn = GameState.phase_controller.current_turn
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	GameState.boarding_actions = []
	GameState.linked_at_plot = {}
	GameState.phase_controller.current_turn = 5
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 2
	GameState.environment = env
	boarding = GameState.boarding_controller


func after_each() -> void:
	var pc: TurnPhaseController = GameState.phase_controller
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	pc.current_turn = _old_turn
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	GameState.boarding_actions = []
	GameState.linked_at_plot = {}


# --- fixtures ---

## A ship of class `ship_class` with the given live crew. Facing 1 (SE) at `hex`: ships on (5,5)
## and (6,5) are alongside. The ship type's crew (the prize's original section sizes) is `start`.
func _ship(id: String, player: int, hex: Vector2i, quality: String, ship_class: int, crew: Array,
		marines: int, morale: int = 3, start: Array = [6, 6, 7, 7], start_marines: int = 7) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "ship_of_line_74" if ship_class == 2 else "frigate_38", "name": id, "nationality": "British",
		"rating": 74 if ship_class == 2 else 38, "class": ship_class, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": start, "marine_count": start_marines, "point_costs": {"B3": 100, "C3": 100, "D3": 100},
	})
	state.hex_position = hex
	state.facing = 1
	state.sail_state = "FS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = ShipState._int_array(crew)
	state.marine_count = marines
	state.crew_quality = quality
	state.starting_crew_quality = quality
	state.morale_rating = morale
	state.crew_auto = false
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


## A live boarding task on one section (fixtures write ShipState fields directly).
func _task(ship: ShipState, code: String, section: int, target: String = "", started: int = 5) -> Dictionary:
	ship.task_seq += 1
	var params := {"section": section}
	if code == "BA":
		params["target"] = target
	var task := ShipState.crew_task_from({"seq": ship.task_seq, "code": code, "sections": [section],
		"done": 0, "started_turn": started, "params": params, "forced": false,
		"marines_available": code != "BA", "ended": ""})
	ship.crew_tasks.append(task)
	if not ship.plotted_sections.has(section):
		ship.plotted_sections.append(section)
	return task


func _readied(ship: ShipState, sections: Array) -> void:
	for s in sections:
		_task(ship, "BR", int(s), "", 4)


## Grapples the two ships and takes the PLANNING link snapshot (10.A.2).
func _link(a: ShipState, b: ShipState) -> void:
	a.grappled_with.append(b.ship_id)
	b.grappled_with.append(a.ship_id)
	boarding.take_link_snapshot()


func _ctx(ship: ShipState) -> Dictionary:
	return CrewRules.context(GameState, ship)


func _events(type: PhaseEvents.Type) -> Array[PhaseEvents.PhaseEvent]:
	return GameState.turn_log.of_type(type)


## Heureux (French 74, CQ D) and Majestic (British 74, CQ C), as in the 10.D examples.
func _heureux_majestic() -> Array:
	var heureux := _ship("heureux", 1, Vector2i(5, 5), "D", 2, [4, 5, 6, 6], 6)
	var majestic := _ship("majestic", 0, Vector2i(6, 5), "C", 2, [2, 6, 6, 6], 4)
	_link(heureux, majestic)
	return [heureux, majestic]


# --- 10.B, 10.C.1, 4.B.1: what may be plotted (tests 12-19) ---

func test_12_sailors_form_lowest_first() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	# 10.B.2, 4.B.1: S2 may not form while S1 has boxes and is free.
	assert_string_contains(BoardingRules.task_error(a, {}, _ctx(a), 1, "FB"), "send S1 before S2")
	assert_eq(BoardingRules.task_error(a, {0: BoardingRules.entry("FB", 0)}, _ctx(a), 1, "FB"), "", "S1 forms too")
	# With S1 in RO (forced) it is out of the order.
	a.task_seq += 1
	a.crew_tasks.append(ShipState.crew_task_from({"seq": a.task_seq, "code": "RO", "sections": [0], "done": 0,
		"started_turn": 4, "params": {"reason": "crew_disorganized"}, "forced": true, "ended": ""}))
	assert_eq(BoardingRules.task_error(a, {}, _ctx(a), 1, "FB"), "")


func test_13_marines_form_with_no_sailor_forming() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	assert_eq(BoardingRules.task_error(a, {}, _ctx(a), M, "FB"), "", "10.B.2: the marines may FB regardless")


func test_14_no_boarding_in_the_turn_of_forming() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	_link(a, b)
	var plan := {0: BoardingRules.entry("FB", 0)}
	assert_string_contains(BoardingRules.task_error(a, plan, _ctx(a), 0, "BA", "b"), "formed this turn")


func test_15_at_most_two_new_sections_board() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	_link(a, b)
	_readied(a, [M, 0, 1])
	var plan := {M: BoardingRules.entry("BA", M, "b"), 0: BoardingRules.entry("BA", 0, "b")}
	assert_eq(BoardingRules.task_error(a, {M: plan[M]}, _ctx(a), 0, "BA", "b"), "")
	assert_string_contains(BoardingRules.task_error(a, plan, _ctx(a), 1, "BA", "b"), "Only two sections")


func test_16_s4_never_boards() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [0, 0, 0, 3], 0)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	_link(a, b)
	_readied(a, [3])
	assert_eq(BoardingRules.task_error(a, {}, _ctx(a), 3, "FB"), "", "S4 may form (10.C.1)")
	assert_string_contains(BoardingRules.task_error(a, {}, _ctx(a), 3, "BA", "b"), "S4 never boards")


func test_17_cq_f_may_form_but_not_board() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "F", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	_link(a, b)
	_readied(a, [M])
	assert_string_contains(BoardingRules.task_error(a, {}, _ctx(a), M, "BA", "b"), "CQ F may not board")
	assert_eq(BoardingRules.task_error(a, {}, _ctx(a), 0, "FB"), "", "spec 0.4 #3: F may form to defend")


func test_18_board_only_an_enemy_linked_at_the_start_of_the_turn() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	var friend := _ship("f", 0, Vector2i(4, 5), "C", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	_readied(a, [M])
	_link(a, friend)
	assert_string_contains(BoardingRules.task_error(a, {}, _ctx(a), M, "BA", "f"), "Friendly ships may not board")
	assert_string_contains(BoardingRules.task_error(a, {}, _ctx(a), M, "BA", "b"), "start of the turn",
		"an unlinked enemy")
	# Grappled after PLANNING began (this g-t's maintenance or movement): not yet.
	a.grappled_with.append("b")
	b.grappled_with.append("a")
	assert_string_contains(BoardingRules.task_error(a, {}, _ctx(a), M, "BA", "b"), "start of the turn",
		"10.A.2: linked only since the snapshot")
	boarding.take_link_snapshot()
	assert_eq(BoardingRules.task_error(a, {}, _ctx(a), M, "BA", "b"), "")


func test_19_fire_stops_boarding_both_ways() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	_link(a, b)
	_readied(a, [M])
	b.fire_list.append({"seq": 1, "created_turn": 4, "started_turn": 4, "cause": "crit"})
	boarding.take_link_snapshot()
	assert_string_contains(BoardingRules.task_error(a, {}, _ctx(a), M, "BA", "b"), "on fire")
	a.fire_list.append({"seq": 1, "created_turn": 4, "started_turn": 4, "cause": "crit"})
	assert_string_contains(BoardingRules.task_error(a, {}, _ctx(a), 0, "FB"), "on fire", "10.A.2: no FB while burning")


# --- 8.E.2: fire breaking out (tests 20-21) ---

func test_20_fire_disbands_unengaged_boarders() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	_readied(a, [M, 0])
	GameState.crew_task_controller.notify_fire_breaks_out("a")
	assert_false(a.has_boarders(), "S1 and M at BR are disbanded")
	assert_false(a.is_readied(0))
	assert_false(a.is_readied(M), "free next g-t (10.B.5 note)")


func test_21_engaged_boarders_fight_on_through_a_fire() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	var task := _task(a, "BA", 0, "b")
	task["forced"] = true
	task["params"]["action"] = 1
	task["params"]["enemy"] = "b"
	GameState.crew_task_controller.notify_fire_breaks_out("a")
	assert_eq(a.boarding_action_of(0), 1, "8.E.2 exception: engaged sections fight on")
	var drafted := CrewRules.fire_draft(a, {0: {"code": "BA", "params": task["params"]}}, 1)
	assert_ne(drafted, 0, "the fire draft takes another section")
	assert_eq(drafted, 1, "the lowest free sailor section")


# --- declare: 10.C.3, 10.E.2a-b, 10.C.5b (tests 22-26) ---

func test_22_marines_drop_their_repair_to_defend() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "D", 2, [4, 5, 6, 6], 6)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 2, [2, 6, 6, 6], 4)
	_link(a, b)
	_task(a, "BA", M, "b")
	_task(b, "FB", 0)
	b.task_seq += 1
	b.crew_tasks.append(ShipState.crew_task_from({"seq": b.task_seq, "code": "RR", "sections": [M], "done": 3,
		"started_turn": 2, "params": {}, "forced": false, "ended": ""}))
	assert_true(boarding.declare(PHASE))
	assert_true(b.tasks_with("RR").is_empty(), "10.C.3: the repair is erased")
	assert_eq(str(b.boarding_task(M).get("code", "")), "FB", "the marines are replotted to FB")
	assert_eq(int(b.boarding_task(M).get("done", -1)), 0, "RR progress is lost (Majestic g-t 20)")
	assert_eq(_events(PhaseEvents.Type.MARINES_DEFEND).size(), 1)
	assert_eq(GameState.boarding_actions[0].defender_sections, [0, M] as Array[int])


func test_23_unplotted_marines_defend() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "D", 3, [4, 5, 6, 6], 6)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 4)
	_link(a, b)
	_task(a, "BA", M, "b")
	boarding.declare(PHASE)
	var action: BoardingAction = GameState.boarding_actions[0]
	assert_eq(action.defender_sections, [M] as Array[int], "SoP IV.A: the marines defend")
	assert_eq(action.state, BoardingAction.DECLARED)


func test_24_no_defender_captured_without_a_roll() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "D", 3, [4, 5, 6, 6], 6)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0)
	_link(a, b)
	_task(a, "BA", M, "b")
	boarding.declare(PHASE)
	assert_true(b.is_captured(), "10.E.2b")
	assert_eq(b.player_id, 1, "friendly to the captor (10.H.1)")
	assert_eq(_dice.remaining(), 0)
	assert_eq(str(a.task_of(M).get("code", "")), "RO", "10.G.2: the boarders reorganize")


func test_25_struck_defender_no_reorganizing_prize_crew_this_turn() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 6, 3)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 4, 4, [6, 6, 7, 7], 7)
	b.status = ShipState.Status.STRUCK
	_link(a, b)
	_task(a, "BA", M, "b")
	_task(a, "BA", 0, "b")
	boarding.declare(PHASE)
	assert_true(b.is_captured(), "10.A.3: the boarders win automatically")
	assert_true(a.tasks_with("RO").is_empty(), "10.A.3: no reorganizing")
	boarding.advance_reorganizing(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	# Class 3 minimum 2 boxes (10.G.6), sailors first from the boarders: S1 loses 2.
	assert_eq(b.total_crew_boxes(), 2, "the minimum prize crew")
	assert_eq(b.crew_count, [0, 0, 0, 2] as Array[int], "formed from S4 down (10.G.7)")
	assert_eq(a.crew_count[0], 2)
	assert_eq(_events(PhaseEvents.Type.PRIZE_CREW).size(), 1)
	# Test 44 (10.G.8): the prize crew takes the captor's current CQ and MR.
	assert_eq(b.crew_quality, "B")
	assert_eq(b.morale_rating, 3)
	assert_eq(int(b.prize["original_crew"]["crew_count"][1]), 6, "the original crew is below")


func test_26_both_board_the_higher_tbcf_attacks() -> void:
	# a: M 5 x 7 + S1 3 x 5 = 50 at CQ D; b: M 5 x 8 = 40 at CQ C.
	var a := _ship("a", 0, Vector2i(5, 5), "D", 3, [3, 3, 3, 3], 5)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 5)
	_link(a, b)
	_task(a, "BA", M, "b")
	_task(a, "BA", 0, "b")
	_task(b, "BA", M, "a")
	assert_eq(boarding.tbcf("a", [M, 0]), 50)
	assert_eq(boarding.tbcf("b", [M]), 40)
	boarding.declare(PHASE)
	assert_eq(GameState.boarding_actions.size(), 1, "spec 0.4 #2: one action")
	var action: BoardingAction = GameState.boarding_actions[0]
	assert_eq(action.attacker_id, "a", "10.C.5b: the higher TBCF attacks")
	assert_eq(action.defender_sections, [M] as Array[int], "the other's BA section defends")


# --- 10.D (tests 27-37) ---

func test_27_odds_drms() -> void:
	var t: CombatTables = DataManager.combat_tables
	assert_eq(t.odds_drm(62, 44), 0, "1.41:1 -> 1:1")
	assert_eq(t.odds_drm(44, 62), -1, "0.71:1 -> 2:3")
	assert_eq(t.odds_drm(40, 10), 4, "4:1")
	assert_eq(t.odds_drm(10, 45), -4, "below 1:4")


func test_28_class_drms() -> void:
	var t: CombatTables = DataManager.combat_tables
	assert_eq(t.boarding_class_drm(2, 3), -3, "frigate (3) boards a 74 (2): -2 -1")
	assert_eq(t.boarding_class_drm(3, 2), 0, "74 boards a frigate: -1 +1")


func test_29_and_33_losses_round_to_the_nearest_bcf() -> void:
	assert_eq(CombatTables.boarding_loss_bcf(8, 62), 5, "10.D.4: 8 % of 62 = 4.96 -> 5")
	assert_eq(CombatTables.boarding_loss_bcf(10, 45), 5, "spec 0.4 #1: 4.5 rounds up")


func test_30_heureux_v_majestic() -> void:
	var ships := _heureux_majestic()
	var heureux: ShipState = ships[0]
	var majestic: ShipState = ships[1]
	_task(heureux, "BA", M, "majestic")
	_task(heureux, "BA", 0, "majestic")
	_readied(heureux, [1])  # another readied section: disbanded by the repulse too (10.D.5a)
	_task(majestic, "FB", 0)
	majestic.task_seq += 1
	majestic.crew_tasks.append(ShipState.crew_task_from({"seq": majestic.task_seq, "code": "RR",
		"sections": [M], "done": 1, "started_turn": 4, "params": {}, "forced": false, "ended": ""}))
	boarding.declare(PHASE)
	# 2d6 9 and 9; Majestic's loss d6 2 (sailor); Heureux's loss d6 1 (sailor). No d10: 8 is a
	# plain "repulsed, 1 MC".
	_dice.queue([4, 5, 4, 5, 2, 1])
	boarding.resolve(PHASE)
	assert_eq(_dice.remaining(), 0, "dice order (spec §3.3)")
	var round_ev: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.BOARDING_ROUND)[0]
	var att: Dictionary = round_ev.data["attacker"]
	var def: Dictionary = round_ev.data["defender"]
	assert_eq(att["tbcf"], 62, "10.D.1: 6 x 7 + 4 x 5")
	assert_eq(def["tbcf"], 44, "2 x 6 + 4 x 8")
	assert_eq(att["drm"], -2, "10.D.2: 1:1 0, class 2 defender -2")
	assert_eq(def["drm"], -1, "2:3 -1")
	assert_eq(att["total"], 7)
	assert_eq(def["total"], 8)
	assert_eq(att["inflicts"], 5, "8 % of 62")
	assert_eq(def["inflicts"], 4, "10 % of Majestic's 44 (spec 0.2)")
	assert_eq(majestic.crew_count[0], 1, "Majestic loses one sailor box")
	assert_eq(heureux.crew_count[0], 3, "Heureux loses one sailor box")
	var result: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.BOARDING_RESULT)[0]
	assert_eq(result.data["result"], "repulsed")
	assert_eq(result.data["mcs"], 1)
	assert_eq(heureux.pending_morale_checks, 1, "Heureux takes 1 MC")
	assert_false(heureux.has_boarders(), "all her FB/BR/BA are disbanded")
	var action: BoardingAction = GameState.boarding_actions[0]
	assert_eq(action.state, BoardingAction.DEFENDER_WON)
	assert_eq(action.outcome, "repulsed")
	assert_false(majestic.is_captured())


func test_31_mixed_losses_roll_each_box() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "D", 3, [3, 3, 3, 3], 2)
	_dice.queue([2, 5])
	var lost: Dictionary = GameState.damage_controller.apply_boarding_losses("a", 6, [M, 0], "D", PHASE)
	assert_eq(lost["sailors"], 1, "10.D.4 example: d6 2, a sailor (5 BCF)")
	assert_eq(lost["marines"], 1, "then d6 5, a marine (7): 12 BCF lost for 6")
	assert_eq(a.crew_count[0], 2)
	assert_eq(a.marine_count, 1)


func test_32_one_crew_type_rolls_no_d6() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "D", 3, [3, 3, 3, 3], 2)
	var lost: Dictionary = GameState.damage_controller.apply_boarding_losses("a", 9, [0, 1], "D", PHASE)
	assert_eq(_dice.remaining(), 0)
	assert_eq(lost["sailors"], 2, "10.D.4a: two sailor boxes for 9 BCF")
	assert_eq(a.crew_count, [1, 3, 3, 3] as Array[int], "from the lowest section in the action")


## Sailors-only fight between equal frigates (class 3 v 3: attacker -1): no loss d6.
func _sailors_fight(att_boxes: int, def_boxes: int, att_mr: int = 3, def_mr: int = 3) -> Array:
	var a := _ship("a", 0, Vector2i(5, 5), "D", 3, [att_boxes, 3, 3, 3], 0, att_mr)
	var b := _ship("b", 1, Vector2i(6, 5), "D", 3, [def_boxes, 3, 3, 3], 0, def_mr)
	_link(a, b)
	_task(a, "BA", 0, "b")
	_task(b, "FB", 0)
	boarding.declare(PHASE)
	return [a, b]


func test_34_only_the_higher_special_result() -> void:
	_sailors_fight(8, 8)
	# Attacker 10 - 1 = 9 (d10 special pending); defender 11: "repulsed and 2 MC" wins (10.D.5).
	_dice.queue([5, 5, 5, 6])
	boarding.resolve(PHASE)
	assert_eq(_dice.remaining(), 0, "no d10 for the attacker's special")
	var r: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.BOARDING_RESULT)[0]
	assert_eq(r.data["result"], "repulsed")
	assert_eq(r.data["mcs"], 2)


func test_35_equal_rolls_go_to_the_higher_tbcf() -> void:
	# 50 v 40 at CQ D: attacker 1:1 0, class -1; defender 2:3 -1. Both modified 9.
	_sailors_fight(10, 8)
	_dice.queue([5, 5, 5, 5, 9])
	boarding.resolve(PHASE)
	var r: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.BOARDING_RESULT)[0]
	assert_eq(r.data["side"], "attacker", "the 50 side's special")
	assert_eq(r.data["d10"], 9)
	assert_eq(r.data["result"], "fight_on", "d10 9 is not < MR 3")


func test_35b_equal_rolls_equal_tbcf_neither() -> void:
	_sailors_fight(8, 8)
	_dice.queue([5, 5, 4, 5])  # 10 - 1 = 9 v 9 + 0 = 9
	boarding.resolve(PHASE)
	assert_eq(_dice.remaining(), 0)
	var r: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.BOARDING_RESULT)[0]
	assert_eq(r.data["side"], "", "10.D.5: neither")
	assert_eq(r.data["result"], "fight_on")
	assert_eq(GameState.boarding_actions[0].state, BoardingAction.ENGAGED)


func test_36_capture_needs_d10_below_defender_mr() -> void:
	var ships := _sailors_fight(8, 8, 3, 3)
	_dice.queue([5, 6, 1, 1, 2])  # attacker 11 - 1 = 10, defender 2: d10 2 < MR 3
	boarding.resolve(PHASE)
	assert_true((ships[1] as ShipState).is_captured(), "d10 2 < 3: captured")


func test_36b_d10_equal_to_mr_does_not_capture() -> void:
	var ships := _sailors_fight(8, 8, 3, 3)
	_dice.queue([5, 6, 1, 1, 3])
	boarding.resolve(PHASE)
	assert_false((ships[1] as ShipState).is_captured(), "d10 3 is not < MR 3")


func test_37_repulse_needs_d10_below_attacker_mr() -> void:
	var ships := _sailors_fight(8, 8, 3, 3)
	_dice.queue([1, 1, 3, 3, 3])  # attacker 2 - 1 = 1; defender 6: d10 3, attacker MR 3
	boarding.resolve(PHASE)
	var r: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.BOARDING_RESULT)[0]
	assert_eq(r.data["result"], "fight_on", "not repulsed")
	assert_true((ships[0] as ShipState).has_boarders())


# --- 10.E (tests 38-40), 8.C.5 / 8.D.4 (tests 8-9) ---

func test_38_engaged_action_goes_on_locked() -> void:
	var ships := _sailors_fight(8, 8)
	var a: ShipState = ships[0]
	var b: ShipState = ships[1]
	a.fouled_with = "b"
	b.fouled_with = "a"
	_dice.queue([5, 5, 4, 5])
	boarding.resolve(PHASE)
	var action: BoardingAction = GameState.boarding_actions[0]
	assert_eq(action.state, BoardingAction.ENGAGED, "10.E.1")
	assert_true(bool(a.task_of(0).get("forced", false)), "the boarders are locked")
	assert_string_contains(CrewRules.refusal(a, CrewRules.plan_of(a), _ctx(a), 0, CrewRules.STATION_GUNS), "10.E.1")
	# Test 8: no ungrapple or unfoul between them.
	assert_true(boarding.locked_in_boarding("a", "b"))
	assert_ne(GameState.grappling_controller.ungrapple_error("a", "b"), "")
	GameState.fouling_controller.resolve_unfouling(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(_events(PhaseEvents.Type.UNFOUL).size(), 0, "8.D.4: no unfouling roll")
	assert_eq(a.fouled_with, "b")
	# Next g-t: no new BA is declared; the action is fought again.
	assert_false(boarding.declare(PHASE))
	_dice.queue([5, 5, 4, 5])
	boarding.resolve(PHASE)
	assert_eq(action.rounds, 2)


func test_9_marines_engaged_count_as_unavailable() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "D", 3, [3, 3, 3, 3], 2)
	var c := _ship("c", 1, Vector2i(5, 6), "D", 3, [3, 3, 3, 3], 2)
	var task := _task(a, "FB", M)
	task["forced"] = true
	task["params"]["action"] = 3
	a.grappled_with.append("c")
	c.grappled_with.append("a")
	var chance: Dictionary = GameState.grappling_controller.ungrapple_chance("a", "c")
	var names: Array = []
	for m in chance["modifiers"]:
		names.append(m["name"])
	assert_has(names, "marines_unavailable", "8.C.5: +1 ungrappling from a third ship")


func test_39_counter_boarding_all_who_defended() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	_link(a, b)
	var won := BoardingAction.new()
	won.id = 7
	won.attacker_id = "b"
	won.defender_id = "a"
	won.defender_sections = [0, 1, 2, 3, M] as Array[int]
	won.state = BoardingAction.DEFENDER_WON
	won.outcome = "repulsed"
	won.finished_turn = 4
	GameState.boarding_actions.append(won)
	_readied(a, [M, 0, 1, 2, 3])
	var plan := {}
	for s in [M, 0, 1, 2]:
		assert_eq(BoardingRules.task_error(a, plan, _ctx(a), s, "BA", "b"), "", "10.E.4: %s may go" % s)
		plan[s] = BoardingRules.entry("BA", s, "b")
	assert_string_contains(BoardingRules.task_error(a, plan, _ctx(a), 3, "BA", "b"), "S4 never boards")
	assert_eq(CrewRules.boarding_choices(a, _ctx(a))[2]["text"], "Counter-board b!")


func test_40_parent_strikes_boarders_surrender() -> void:
	var ships := _sailors_fight(8, 8)
	(ships[0] as ShipState).status = ShipState.Status.STRUCK
	boarding.resolve(PHASE)
	var action: BoardingAction = GameState.boarding_actions[0]
	assert_eq(action.state, BoardingAction.DEFENDER_WON, "10.D.6")
	assert_eq(action.outcome, "surrendered")
	assert_eq(_dice.remaining(), 0)


# --- 10.D.7 (test 41) ---

func test_41_gunfire_crew_loss_row_with_boarders() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	assert_eq(BoardingRules.crew_loss_cause(a, "other"), "other", "no boarders: unchanged")
	_task(a, "FB", 0)
	var cause := BoardingRules.crew_loss_cause(a, "other")
	assert_eq(cause, "gunfire_at_hull", "only sailors at FB")
	assert_true(DataManager.combat_tables.crew_loss_is_sailor(cause, 5), "d6 5: a sailor (S 1-5)")
	_task(a, "FB", M)
	cause = BoardingRules.crew_loss_cause(a, "gunfire_at_hull")
	assert_eq(cause, "other", "the marines at FB too")
	assert_false(DataManager.combat_tables.crew_loss_is_sailor(cause, 5), "d6 5: a marine (M 4-6)")


# --- 10.G (tests 42-44) ---

func test_42_reorganizing_takes_five_plus_sk() -> void:
	var t: CombatTables = DataManager.combat_tables
	assert_eq(t.task_turns("RO", "B"), 3, "CQ B: 5 - 2")
	assert_eq(t.task_turns("RO", "E"), 6, "CQ E: 5 + 1")
	# Through a capture: the boarders' RO tasks.
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 6)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0)
	_link(a, b)
	_task(a, "BA", M, "b")
	boarding.declare(PHASE)
	var ro: Dictionary = a.tasks_with("RO")[0]
	assert_eq(a.task_turns_required(ro), 3)


func test_43_prize_crew_assignment_example() -> void:
	# 10.G.10: Majestic 1-6-6-6:2 leaves 8 sailors + 1 marine on Heureux (6-6-7-7:7).
	var parent := _ship("majestic", 0, Vector2i(5, 5), "C", 2, [1, 6, 6, 6], 2)
	var taken: Dictionary = GameState.damage_controller.detach_prize_crew("majestic", 8, 1, TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(taken, {"sailors": 8, "marines": 1})
	assert_eq(parent.crew_count, [0, 0, 5, 6] as Array[int], "0-0-5-6:1")
	assert_eq(parent.marine_count, 1)
	assert_eq(parent.pending_morale_checks, 0, "10.G.7: no MCs")
	assert_eq(DataManager.combat_tables.sections_firing_modifier(parent.sections_able_to_fire()), -6,
		"S1 and S2 gone: -6 on the guns")
	var formed := BoardingRules.form_prize_sections([6, 6, 7, 7], 7, 8, 1)
	assert_eq(formed["crew_count"], [0, 0, 1, 7] as Array[int], "0-0-1-7")
	assert_eq(formed["marine_count"], 1)
	# Spec §8 Q4: sections emptied for a prize crew are not destroyed for victory points.
	var vc := VictoryController.new(GameState)
	assert_almost_eq(vc.points_lost(parent), 0.0, 0.001)


# --- 10.H (test 45), VI.B (test 47) ---

func test_45_a_prize_cannot_sail_or_fight_but_is_a_target() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 6)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0)
	var c := _ship("c", 0, Vector2i(6, 6), "C", 3, [3, 3, 3, 3], 2)
	_link(a, b)
	_task(a, "BA", M, "b")
	boarding.declare(PHASE)
	assert_true(b.is_captured())
	var r: MovementTypes.PlottingResponse = GameState.movement_plotting_controller.handle_start_plotting(1, "b", "t45")
	assert_eq(r.get("error_code"), "SHIP_CAPTURED", "10.H.2")
	assert_eq(FireRules.marine_error(c, b, 1), "", "10.H.1: the old side may fire on her")
	assert_string_contains(FireRules.marine_error(b, c, 1), "prize does not fight", "spec §8 Q2")
	assert_true(b.is_targetable())
	assert_false(b.is_struck())


func test_47_captured_ship_scores_full_value_for_the_captor() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 6)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0, 3)
	_link(a, b)
	_task(a, "BA", M, "b")
	boarding.declare(PHASE)
	var vc := VictoryController.new(GameState)
	assert_almost_eq(vc.points_lost(b), 100.0, 0.001, "VI.B.2-3: 100 %")
	assert_almost_eq(vc._points_scored(1), 100.0, 0.001, "to the captor's side")
	assert_true(vc._is_defeated(0), "player 0 has no ship in play left")
	assert_false(vc._is_defeated(1))
	assert_eq(GameState.get_player_ships(1).size(), 2, "the prize is indexed under her captor")


# --- rule A2b (test 52) ---

func test_52_automatic_ready_then_board() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	a.crew_auto = true
	_link(a, b)
	var first := CrewAuto.allocate(a, {"sail_target": "", "boarding": "ready"}, _ctx(a))["assignments"] as Dictionary
	assert_eq(str(first[M]["code"]), "FB", "the marines form")
	assert_eq(str(first[0]["code"]), "FB", "S1 forms")
	assert_false(first.has(1))
	_readied(a, [M, 0])
	var second := CrewAuto.allocate(a, {"sail_target": "", "boarding": "board:b"}, _ctx(a))["assignments"] as Dictionary
	assert_eq(str(second[M]["code"]), "BA")
	assert_eq(str(second[0]["code"]), "BA")
	assert_eq(str(second[0]["params"]["target"]), "b")
	var none := CrewAuto.allocate(a, {"sail_target": "", "boarding": ""}, _ctx(a))["assignments"] as Dictionary
	assert_eq(str(none[M]["code"]), "BD", "no order: readied sections stand down (10.B.5)")


func test_manual_readied_section_moved_off_stands_down() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	_readied(a, [0])
	var plan := CrewRules.assign(a, {"assignments": {0: BoardingRules.entry("BR", 0)}, "orders": {}}, _ctx(a), 0, CrewRules.STATION_GUNS)
	assert_eq(str(plan["assignments"][0]["code"]), "BD", "10.B.5: it must disband this g-t")
	var normalized := CrewRules.normalize(a, {"assignments": {}, "orders": {}}, _ctx(a))
	assert_eq(str(normalized["assignments"][0]["code"]), "BD", "a readied section left unplotted stands down")


# --- the combat phase (spec §3.1) ---

func test_combat_runs_boarding_alone_with_no_shot() -> void:
	# a bow (0,0) facing E, b bow (2,0) facing E: b's stern alongside a's bow, no broadside bears.
	var a := _ship("a", 0, Vector2i(0, 0), "D", 3, [8, 3, 3, 3], 0)
	var b := _ship("b", 1, Vector2i(2, 0), "D", 3, [8, 3, 3, 3], 0)
	a.facing = 0
	b.facing = 0
	a.sail_state = "FS"
	_link(a, b)
	_task(a, "BA", 0, "b")
	_task(b, "FB", 0)
	assert_false(GameState.gunnery_calculator.any_eligible_shot(), "no gun shot")
	var pc: TurnPhaseController = GameState.phase_controller
	pc.current_phase = TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
	_dice.queue([5, 5, 4, 5])
	pc.on_playback_completed()
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION, "not skipped")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.RESOLVE, "no declare step: boarding alone")
	assert_eq(_events(PhaseEvents.Type.BOARDERS_AWAY).size(), 1)
	assert_eq(_events(PhaseEvents.Type.BOARDING_ROUND).size(), 1)


func test_combat_skipped_with_no_shot_and_no_boarding() -> void:
	var a := _ship("a", 0, Vector2i(0, 0), "D", 3, [8, 3, 3, 3], 0)
	var b := _ship("b", 1, Vector2i(2, 0), "D", 3, [8, 3, 3, 3], 0)
	a.facing = 0
	b.facing = 0
	var pc: TurnPhaseController = GameState.phase_controller
	pc.current_phase = TurnPhaseController.GamePhase.COMBAT_RESOLUTION
	assert_false(boarding.has_actions_to_resolve())
	assert_false(boarding.declare(PHASE), "nothing to announce: the phase may be skipped")


# --- end of turn ---

func test_end_of_turn_keeps_a_repulse_one_turn_for_counter_boarding() -> void:
	var won := BoardingAction.new()
	won.id = 1
	won.state = BoardingAction.DEFENDER_WON
	won.finished_turn = 5
	GameState.boarding_actions.append(won)
	boarding.end_of_turn(5)
	assert_eq(GameState.boarding_actions.size(), 1, "kept for the next g-t (10.E.4)")
	assert_true(GameState.boarding_history.has(5))
	boarding.end_of_turn(6)
	assert_eq(GameState.boarding_actions.size(), 0)


# --- more: RO to prize crew, 10.E.2e, log text, the station, orders ---

func test_reorganizing_ends_then_prize_crew_goes_aboard() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 6, 3)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0, 4)
	_link(a, b)
	_task(a, "BA", M, "b")
	_task(a, "BA", 0, "b")
	boarding.declare(PHASE)  # undefended: captured, M and S1 reorganize for 3 g-t's (CQ B)
	var status := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT
	var pc: TurnPhaseController = GameState.phase_controller
	for turn in [5, 6, 7]:
		pc.current_turn = turn
		GameState.current_turn = turn
		a.plotted_sections = [0, M] as Array[int]
		GameState.crew_task_controller.advance_tasks(status)
		boarding.advance_reorganizing(status)
		if turn < 7:
			assert_eq(b.total_crew_boxes(), 0, "turn %d: still reorganizing (10.G.4)" % turn)
			assert_string_contains(ShipView.prize_caption(b), "reorganizing")
	assert_eq(b.total_crew_boxes(), 2, "RO done after 3 counted g-t's: class 3 minimum of 2 aboard")
	assert_eq(ShipView.prize_caption(b), "PRIZE")
	assert_true(bool(b.prize["prize_crew_aboard"]))
	boarding.end_of_turn(7)
	assert_eq(GameState.boarding_actions.size(), 0, "the won action is dropped once the prize crew is aboard")


func test_link_broken_while_reorganizing_every_boarder_stays_aboard() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 6)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0)
	_link(a, b)
	_task(a, "BA", M, "b")
	_task(a, "BA", 0, "b")
	boarding.declare(PHASE)
	for task in a.tasks_with("RO"):
		a.crew_tasks.erase(task)  # RO finished
	a.grappled_with.clear()
	b.grappled_with.clear()
	boarding.advance_reorganizing(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(b.total_crew_boxes(), 10, "spec 0.4 #6: all 4 + 6 boarders are crossed off the parent")
	assert_eq(a.crew_count[0], 0)
	assert_eq(a.marine_count, 0)


func test_all_defending_boxes_lost_is_a_capture() -> void:
	var ships := _sailors_fight(8, 1)
	# 40 v 5: attacker 4:1 +4, class -1: 2 + 3 = 5, 4 % of 40 = 2 BCF, the defender's one box goes;
	# defender 1:4 -4: 2 - 4, no special either side.
	_dice.queue([1, 1, 1, 1])
	boarding.resolve(PHASE)
	assert_true((ships[1] as ShipState).is_captured(), "10.E.2e")


func test_engaged_marines_cannot_fire() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "D", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "D", 3, [3, 3, 3, 3], 2)
	_readied(a, [M])
	assert_eq(FireRules.marine_error(a, b, 1), "", "7.G.1: marines at BR may fire")
	var task := a.boarding_task(M)
	task["params"]["action"] = 2
	assert_string_contains(FireRules.marine_error(a, b, 1), "boarding action", "engaged marines may not")


func test_log_text() -> void:
	var names := {"a": "Vengeance", "b": "Hermione"}
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BOARDING_ROUND, PHASE, "a", {
		"attacker": {"tbcf": 62, "roll": 9, "drm": -2, "total": 7},
		"defender": {"tbcf": 44, "roll": 9, "drm": -1, "total": 8}}, "b")
	assert_eq(ev.to_text(names), "Boarding, Vengeance onto Hermione: 62 v 44; attacker 9 −2 = 7, defender 9 −1 = 8")
	ev = PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BOARDING_RESULT, PHASE, "a", {"result": "repulsed", "mcs": 1}, "b")
	assert_eq(ev.to_text(names), "Vengeance's boarders are repulsed and take 1 MC")
	ev = PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BOARDERS_AWAY, PHASE, "a", {"sections": [0, 4]}, "b")
	assert_eq(ev.to_text(names), "Vengeance: boarders away! (S1, marines) onto Hermione")
	ev = PhaseEvents.PhaseEvent.new(PhaseEvents.Type.SHIP_CAPTURED, PHASE, "b", {"captor_id": "a"}, "a")
	assert_eq(ev.to_text(names), "Hermione is taken by Vengeance")
	ev = PhaseEvents.PhaseEvent.new(PhaseEvents.Type.PRIZE_CREW, PHASE, "b", {"sailors": 3, "marines": 0, "cq": "B", "mr": 3}, "a")
	assert_eq(ev.to_text(names), "A prize crew of 3 (B3) from Vengeance goes aboard Hermione")
	ev = PhaseEvents.PhaseEvent.new(PhaseEvents.Type.DAMAGE, PHASE, "b", {"sailors_lost": 1, "cause": "boarding", "bcf_needed": 5})
	assert_eq(ev.to_text(names), "Hermione loses 1 sailor in the boarding (5 BCF needed)")


func test_boarding_card_columns() -> void:
	var side := {"sections": [0, 4], "sailors": 4, "marines": 6, "cq": "D", "tbcf": 62, "odds": 0, "other": -2,
		"drm": -2, "roll": 9, "total": 7, "pct": 8, "inflicts": 5, "lost_sailors": 1, "lost_marines": 0}
	var lines := BoardingCard.column_lines(side, true)
	assert_eq(lines[0], "S1, marines · 4 sailors, 6 marines")
	assert_eq(lines[1], "TBCF 62 (CQ D)")
	assert_eq(lines[2], "odds ±0, other −2 → −2")
	assert_eq(lines[3], "2d6 9 → 7")
	assert_eq(lines[4], "Enemy loses 8% = 5 BCF")
	assert_eq(lines[5], "Lost: 1 sailor")
	assert_eq(BoardingCard.result_text({"result": "repulsed", "mcs": 1}), "REPULSED · 1 MC")
	assert_eq(BoardingCard.result_text({"result": "captured"}), "CAPTURED")


func test_boarders_station_and_summary() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [3, 3, 3, 3], 2)
	_link(a, b)
	_readied(a, [M, 0])
	var plan := BoardingRules.with_order(a, {"assignments": {M: BoardingRules.entry("BR", M), 0: BoardingRules.entry("BR", 0)},
		"orders": {"sail_target": ""}}, _ctx(a), "board:b")
	assert_eq(str(plan["assignments"][M]["code"]), "BA", "spec §4.2: the readied marines go")
	assert_eq(str(plan["assignments"][0]["code"]), "BA", "and the lowest readied sailor section")
	var normalized := CrewRules.normalize(a, plan, _ctx(a))
	var st := {}
	for s in CrewRules.stations(a, normalized, _ctx(a)):
		if s["id"] == CrewRules.STATION_BOARDERS:
			st = s
	assert_eq(st["occupants"], [0, M])
	assert_eq(st["order"], "board:b")
	assert_eq(st["choices"][2]["order"], "board:b")
	assert_string_contains(str(st["choices"][2]["odds"]), " v about ")
	assert_eq(CrewRules.summary_text(CrewRules.summary(a, normalized, _ctx(a))), "S1 M board b")
	var toggled := BoardingRules.toggle_away(a, normalized, _ctx(a), 0)
	assert_eq(str(toggled["plan"]["assignments"][0]["code"]), "BR", "clicking a BA token keeps it ready")


func test_boarding_order_is_a_standing_order() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	a.plotted_actions["crew_orders"] = {"sail_target": "", "boarding": "ready"}
	GameState.ship_controller.clear_plotted_actions("a")
	assert_eq(a.boarding_order(), "ready", "kept across the movement plot clear")
	a.plotted_actions["crew_orders"] = {"sail_target": "", "boarding": "stand_down"}
	GameState.ship_controller.clear_plotted_actions("a")
	assert_eq(a.boarding_order(), "", "stand_down lapses after its g-t")


func test_plot_crew_refuses_a_bad_boarding_order() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 2)
	_ship("b", 1, Vector2i(9, 9), "C", 3, [3, 3, 3, 3], 2)
	boarding.take_link_snapshot()
	var pc: TurnPhaseController = GameState.phase_controller
	pc.current_phase = TurnPhaseController.GamePhase.PLANNING
	pc.players_ready = [false, false] as Array[bool]
	assert_string_contains(pc.player_plot_crew(0, "a", {"assignments": {}, "orders": {"boarding": "board:b"}}),
		"start of the turn", "10.A.2: not linked")
	assert_ne(pc.player_plot_crew(0, "a", {"assignments": {}, "orders": {"boarding": "charge"}}), "")
	assert_eq(pc.player_plot_crew(0, "a", {"assignments": {}, "orders": {"boarding": "ready"}}), "")
	assert_eq(a.boarding_order(), "ready")


func test_defenders_formed_later_join_the_action() -> void:
	var ships := _sailors_fight(8, 8)
	var b: ShipState = ships[1]
	_dice.queue([5, 5, 4, 5])
	boarding.resolve(PHASE)
	_task(b, "FB", 1, "", 6)  # 10.E.1: S2 forms to defend on the next g-t
	# 30 v 45: attacker 2:3 -1, class -1: 4 - 2 = 2; defender 3:2 +1: 3 + 1 = 4; no special.
	_dice.queue([2, 2, 1, 2])
	boarding.resolve(PHASE)
	assert_eq(GameState.boarding_actions[0].defender_sections, [0, 1] as Array[int])
	assert_eq(b.boarding_action_of(1), GameState.boarding_actions[0].id)
