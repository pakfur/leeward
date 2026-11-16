extends GutTest
## Prizes (Close Action 1997, 10.G.5-10, 10.H.1-4, 1.G.8; boarding spec B5, §6 test 46, §8 Q2, Q3,
## Q5). Numbers from the Boarding Combat chart (p.109): BCF S/M by CQ: B 7/9, C 6/8, G 2/4; SK mod
## G +3; minimum prize crew class 1 4, 2 3, 3 2 (10.G.6); Unfouling table success <= 2 / 3 / 4 on the
## 1st / 2nd / 3rd+ g-t (8.E.3 firefighting); Crew Loss "All Other Causes" d6 1-3 sailor, 4-6 marine.

const COMBAT := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT
const M := ShipState.MARINES

var boarding: BoardingController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState
var _old_turn: int
var _old_prompt: Array[int]


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
	_old_prompt = GameState.phase_controller.maintenance_prompt_player_ids.duplicate()
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	GameState.boarding_actions = []
	GameState.linked_at_plot = {}
	GameState.phase_controller.current_turn = 5
	GameState.current_turn = 5
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 2
	GameState.environment = env
	boarding = GameState.boarding_controller


func after_each() -> void:
	var pc: TurnPhaseController = GameState.phase_controller
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	pc.maintenance_step = TurnPhaseController.MaintenanceStep.NONE
	pc.maintenance_prompt_player_ids = _old_prompt
	pc.current_turn = _old_turn
	pc.game_result = {}
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	GameState.boarding_actions = []
	GameState.linked_at_plot = {}


# --- fixtures ---

func _ship(id: String, player: int, hex: Vector2i, quality: String, ship_class: int, crew: Array,
		marines: int, morale: int = 3, start: Array = [6, 6, 7, 7], start_marines: int = 7) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "ship_of_line_74" if ship_class == 2 else "frigate_38", "name": id, "nationality": "British",
		"rating": 74 if ship_class == 2 else 38, "class": ship_class, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": start, "marine_count": start_marines,
		"point_costs": {"B3": 100, "C3": 100, "C4": 80, "D3": 100, "G6": 10},
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


func _link(a: ShipState, b: ShipState) -> void:
	a.grappled_with.append(b.ship_id)
	b.grappled_with.append(a.ship_id)
	boarding.take_link_snapshot()


## `captor` (player 1) takes `prize` (player 0) with its marines and S1 against no defence
## (10.E.2b): the boarders then reorganize (RO) aboard her.
func _take(captor: ShipState, prize: ShipState) -> BoardingAction:
	_link(captor, prize)
	_task(captor, "BA", M, prize.ship_id)
	_task(captor, "BA", 0, prize.ship_id)
	boarding.declare(COMBAT)
	assert_true(prize.is_captured(), "fixture: captured")
	return GameState.boarding_actions[0]


## Ends every RO task of the ship (its reorganization is over).
func _finish_ro(ship: ShipState) -> void:
	for task in ship.tasks_with("RO"):
		ship.crew_tasks.erase(task)


## A prize with her prize crew aboard (fixture: fields written directly). The prize crew is
## `crew`/`marines` at the captor's CQ B MR 3; the original crew below is `below` sailors.
func _prize(id: String, captor_id: String, crew: Array, marines: int, below: Array, below_marines: int = 0) -> ShipState:
	var s := _ship(id, 0, Vector2i(6, 5), "B", 2, crew, marines, 3)
	s.status = ShipState.Status.CAPTURED
	s.controller_id = 1
	GameState.ships_by_player[0].erase(id)
	GameState.ships_by_player[1].append(id)
	s.prize = {"captor_id": captor_id, "prize_crew_aboard": true, "original_navy": "",
		"original_crew": {"crew_count": below, "marine_count": below_marines, "crew_quality": "C", "morale_rating": 4}}
	return s


func _events(type: PhaseEvents.Type) -> Array[PhaseEvents.PhaseEvent]:
	return GameState.turn_log.of_type(type)


# --- 10.G.6, spec §8 Q3, §4.3: the prize-crew size ---

func test_prize_size_choice_ranges_from_the_minimum_to_the_boarders() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 2, 3)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0, 4, [6, 6, 7, 7], 7)
	var action := _take(a, b)
	_finish_ro(a)
	var options := boarding.prize_size_options(1)
	assert_eq(options.size(), 1)
	var o: Dictionary = options[0]
	assert_eq(int(o["minimum"]), 2, "10.G.6: class 3 minimum 2")
	assert_eq(int(o["maximum"]), 6, "spec §8 Q3: the boarders only, S1 4 + M 2")
	assert_eq((o["previews"] as Array).size(), 5, "2..6")
	# 10.G.7: sailors from the lowest sections, formed from S4 down into her sizes 6-6-7-7:7.
	var five: Dictionary = (o["previews"] as Array)[3]
	assert_eq(int(five["size"]), 5)
	assert_eq(str(five["prize"]), "0-0-0-4:1")
	assert_eq(str(five["parent"]), "0-5-6-6:1")
	assert_eq(boarding.prize_size_options(0).size(), 0, "only the captor chooses")
	assert_ne(boarding.set_prize_size(action.id, 1), "", "below the minimum is refused (10.G.6)")
	assert_ne(boarding.set_prize_size(action.id, 7), "", "more than the boarders is refused (§8 Q3)")
	assert_eq(boarding.set_prize_size(action.id, 5), "")
	boarding.advance_reorganizing(STATUS)
	assert_eq(b.total_crew_boxes(), 5, "the chosen prize crew is aboard")
	assert_eq(b.crew_count, [0, 0, 0, 4] as Array[int])
	assert_eq(b.marine_count, 1)
	assert_eq(a.crew_count, [0, 5, 6, 6] as Array[int])
	assert_eq(a.marine_count, 1)
	assert_eq(a.pending_morale_checks, 0, "10.G.7: no MCs for boxes detached as prize crew")


func test_no_choice_with_no_more_boarders_than_the_minimum() -> void:
	# Spec §8 Q3: with the minimum or fewer, there is nothing to choose (all of them go).
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [1, 5, 6, 6], 1, 3)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0, 4)
	_take(a, b)
	_finish_ro(a)
	assert_eq(boarding.prize_size_options(1).size(), 0)
	boarding.advance_reorganizing(STATUS)
	assert_eq(b.total_crew_boxes(), 2, "S1 1 + M 1: the minimum")


func test_no_choice_while_reorganizing_or_once_parted() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 2, 3)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0, 4)
	_take(a, b)
	assert_eq(boarding.prize_size_options(1).size(), 0, "10.G.7: chosen when the reorganization ends")
	_finish_ro(a)
	a.grappled_with.clear()
	b.grappled_with.clear()
	assert_eq(boarding.prize_size_options(1).size(), 0, "parted: every boarder is the prize crew (spec 0.4 #6)")


func test_maintenance_prompt_asks_for_the_prize_crew() -> void:
	# Spec §3.1, §4.3: STATUS_ADJUSTMENT waits for the size in the g-t the reorganization ends.
	var a := _ship("a", 0, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 2, 3)
	var b := _ship("b", 1, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0, 4)
	_link(a, b)
	_task(a, "BA", M, "b")
	_task(a, "BA", 0, "b")
	boarding.declare(COMBAT)
	_finish_ro(a)
	var pc: TurnPhaseController = GameState.phase_controller
	pc.maintenance_prompt_player_ids = [0] as Array[int]
	pc.current_phase = STATUS
	watch_signals(pc)
	pc._finish_status_adjustment()
	assert_eq(pc.maintenance_step, TurnPhaseController.MaintenanceStep.PRIZE)
	assert_signal_emitted(pc, "maintenance_orders_requested")
	var params: Array = get_signal_parameters(pc, "maintenance_orders_requested")
	assert_eq(str(params[1]), "prize_size")
	var id := int((params[2] as Array)[0]["action_id"])
	assert_ne(pc.player_submit_maintenance_orders(0, {"grapple": []}), "", "only prize_size orders now")
	assert_ne(pc.player_submit_maintenance_orders(0, {"prize_size": {id: 9}}), "", "out of range")
	assert_eq(b.total_crew_boxes(), 0, "nothing aboard on a refusal")
	assert_eq(pc.player_submit_maintenance_orders(0, {"prize_size": {id: 4}}), "")
	assert_eq(b.total_crew_boxes(), 4, "the chosen prize crew went aboard")
	assert_eq(pc.maintenance_step, TurnPhaseController.MaintenanceStep.NONE)
	assert_ne(pc.current_phase, STATUS, "the phase went on")


func test_ai_prize_crew_minimum_plus_one_with_an_enemy_near() -> void:
	# Spec §3.6: the minimum, plus one if another enemy ship is within 3 hexes.
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 2, 3)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0, 4)
	var action := _take(a, b)
	_finish_ro(a)
	var players: Array[int] = [1]
	assert_eq(GameState.stub_ai.prize_sizes(players), {action.id: 2})
	_ship("c", 0, Vector2i(8, 5), "C", 3, [3, 3, 3, 3], 2)
	assert_eq(GameState.stub_ai.prize_sizes(players), {action.id: 3})


# --- 10.H.2, spec §4.5: the prize's crew overlay ---

func test_prize_crew_may_only_board_and_repair() -> void:
	var b := _prize("b", "a", [0, 0, 1, 2], 0, [2, 6, 6, 6])
	b.hull_current_hp = [3, 5, 5, 6] as Array[int]  # something to repair
	var ctx := CrewRules.context(GameState, b)
	var plan := {"assignments": {2: {"code": "SAIL", "params": {"target": "MS"}}, 3: {"code": "RH", "params": {}}},
		"orders": {"sail_target": "MS"}}
	var n := CrewRules.normalize(b, plan, ctx)
	assert_false((n["assignments"] as Dictionary).has(2), "10.H.2: no sail change")
	assert_eq(str(n["assignments"][3]["code"]), "RH", "10.H.2: repairs allowed")
	assert_eq(str(n["orders"]["sail_target"]), "")
	assert_string_contains(" ".join(n["warnings"]), "10.H.2")
	assert_eq(BoardingRules.task_error(b, {}, ctx, 2, "FB"), "", "10.H.2: boarding allowed")
	assert_eq(CrewRules.refusal(b, plan, ctx, 2, CrewRules.STATION_SAILS), CrewRules.PRIZE_REFUSAL)
	assert_eq(CrewRules.refusal(b, plan, ctx, 3, CrewRules.STATION_GUNS), "", "back to idle")
	var ids: Array = []
	var guns := {}
	for st in CrewRules.stations(b, plan, ctx):
		ids.append(st["id"])
		if st["id"] == CrewRules.STATION_GUNS:
			guns = st
	assert_true(ids.has(CrewRules.STATION_BOARDERS), "the Boarders station")
	assert_true(ids.has(CrewRules.STATION_RH), "the repair station")
	assert_false(ids.has(CrewRules.STATION_FIRE_WATCH), "no fire watch: the crew below fights fires")
	assert_string_contains(str(guns["note"]), "does not fight", "spec §8 Q2")


func test_prize_without_her_prize_crew_plots_nothing() -> void:
	var b := _prize("b", "a", [0, 0, 0, 0], 0, [2, 6, 6, 6])
	b.prize["prize_crew_aboard"] = false
	var n := CrewRules.normalize(b, {"assignments": {}, "orders": {"boarding": "ready"}}, CrewRules.context(GameState, b))
	assert_eq((n["assignments"] as Dictionary).size(), 0)
	assert_false(b.crew_can_act())


func test_automatic_prize_crew_fights_no_fire_and_forms_boarders() -> void:
	var b := _prize("b", "a", [0, 0, 1, 2], 1, [2, 6, 6, 6])
	b.crew_auto = true
	b.fire_list.append({"seq": 1, "created_turn": 4, "started_turn": 4, "cause": "crit"})
	b.fire_seq = 1
	var ctx := CrewRules.context(GameState, b)
	var n := CrewRules.normalize(b, {"assignments": {}, "orders": {"boarding": ""}}, ctx)
	for s in n["assignments"]:
		assert_ne(str(n["assignments"][s]["code"]), "FF", "10.H.3: fires are the original crew's")
	var fire := {}
	for st in CrewRules.stations(b, {"assignments": {}}, ctx):
		if st["id"] == "fire_1":
			fire = st
	assert_eq(str(fire["accepts"]), "none")
	assert_string_contains(str(fire["note"]), "10.H.3")


func test_prize_crew_boards_an_enemy() -> void:
	# 10.H.2: boarding is allowed to a prize.
	var b := _prize("b", "a", [0, 0, 1, 4], 2, [2, 6, 6, 6])
	var c := _ship("c", 0, Vector2i(5, 5), "C", 3, [0, 0, 0, 1], 0)
	_link(b, c)
	_readied(b, [M])
	_task(b, "BA", M, "c")
	_dice.queue([])
	assert_true(boarding.declare(COMBAT))
	assert_true(c.is_captured(), "c had no defender: captured by the prize's boarders (10.E.2b)")
	assert_eq(str(c.prize["captor_id"]), "b")


# --- 10.G.5: a prize boarded while her captors reorganize ---

## a (player 1, CQ B MR 3) takes b (player 0) and reorganizes; c (player 0, CQ C) boards b back
## with `goers`.
func _recapture_setup(a_crew: Array, a_marines: int, below: Array, goers: Array = [M, 0]) -> Array:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, a_crew, a_marines, 3)
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, below, 0, 4)
	var taking := _take(a, b)
	var c := _ship("c", 0, Vector2i(7, 5), "C", 3, [3, 3, 3, 3], 4, 4)
	c.facing = 1
	_link(c, b)
	for s in goers:
		_task(c, "BA", int(s), "b")
	return [a, b, c, taking]


func test_10_g_5_original_crew_joins_the_attack_and_captors_reorganize_again() -> void:
	var r := _recapture_setup([4, 5, 6, 6], 6, [2, 6, 6, 6], [M])
	var a: ShipState = r[0]
	var b: ShipState = r[1]
	var c: ShipState = r[2]
	var taking: BoardingAction = r[3]
	boarding.declare(COMBAT)
	var action: BoardingAction = GameState.boarding_actions[1]
	assert_eq(action.defender_id, "b")
	assert_eq(action.helper_id, "a", "10.G.5: the reorganizing boarders defend")
	assert_eq(action.helper_sections, [0, M] as Array[int])
	assert_true(action.original_crew_joins, "10.G.5: the original crew joins at CQ G")
	assert_true(BoardingController.below_attacks(action), "with its own side's attackers (user decision 2026-11-15)")
	assert_true(a.tasks_with("RO").is_empty(), "10.G.5: the reorganization is aborted")
	assert_eq(a.tasks_with("FB").size(), 2)
	assert_eq(_events(PhaseEvents.Type.REORGANIZING_ABORTED).size(), 1)
	# TBCF (10.D.1, chart BCF: B 7/9, C 6/8, G 2/4): defence a's S1 4 x 7 + M 6 x 9 = 82; attack c's
	# M 4 x 8 = 32 plus the 20 sailors below x 2 = 40: 72.
	assert_eq(boarding.defence_tbcf(action), 82)
	assert_eq(boarding.attack_tbcf(action), 72)
	# c 72:82 -> 2:3 -1, class 3 defender -1: -2; b 82:72 -> 1:1 0.
	# Dice: c 3+3 = 6 - 2 = 4 (2 % of 72 = 1 BCF); b 4+5 = 9 (15 % of 82 = 12 BCF; "attacker
	# repulsed, 1 MC"). b's loss: both types in the defence, d6 1 = sailor: a's S1 (7). The attack's
	# loss: both types on that side (c's marines, the sailors below): d6 4 = marine (c's, 8), d6 1 and
	# 1 = two sailors from below (2 + 2): 12.
	_dice.queue([3, 3, 4, 5, 1, 4, 1, 1])
	boarding.resolve(COMBAT)
	assert_eq(_dice.remaining(), 0, "dice order as documented")
	assert_eq(a.crew_count[0], 3, "the defence's loss fell on the captor's S1")
	assert_eq(c.marine_count, 3, "the attack's marine loss fell on c")
	assert_eq(Array(b.prize["original_crew"]["crew_count"]), [0, 6, 6, 6], "two sailors lost below")
	assert_eq(action.state, BoardingAction.DEFENDER_WON)
	assert_true(b.is_captured(), "held")
	var ro := a.tasks_with("RO")
	assert_eq(ro.size(), 2, "10.G.5: reorganizing begins again")
	for task in ro:
		assert_eq(int(task["done"]), 0, "from the beginning")
		assert_eq(int(task["params"]["action"]), taking.id)
	assert_eq(c.pending_morale_checks, 1, "repulsed: 1 MC (10.D.5)")


func test_prize_boarded_back_is_retaken() -> void:
	# a's boarders: S1 1 box at CQ B: defence 7. c sends M 2 + S1 1 (2 x 8 + 1 x 6 = 22) with the 10
	# sailors below at CQ G (20): attack 42. c 42:7 -> 4:1 +4, class -1: +3; b 7:42 -> 1:4 -4.
	var r := _recapture_setup([1, 5, 6, 6], 0, [0, 4, 6, 0])
	var a: ShipState = r[0]
	var b: ShipState = r[1]
	var c: ShipState = r[2]
	var taking: BoardingAction = r[3]
	c.marine_count = 2
	c.crew_count[0] = 1
	b.prize["original_crew"]["morale_rating"] = 4
	boarding.declare(COMBAT)
	var action: BoardingAction = GameState.boarding_actions[1]
	assert_eq(boarding.defence_tbcf(action), 7)
	assert_eq(boarding.attack_tbcf(action), 42)
	# c 6+6 = 12 + 3 = 15 (row 12+): 30 % of 42 = 13 BCF, "defending ship captured"; b 1+1 = 2 - 4:
	# 2 % of 7 = 0 BCF. b's loss: sailors only, no d6: a's S1 (7), then nothing left.
	_dice.queue([6, 6, 1, 1])
	boarding.resolve(COMBAT)
	assert_eq(_dice.remaining(), 0)
	assert_eq(a.crew_count[0], 0, "a's boarder lost")
	assert_false(b.is_captured(), "retaken")
	assert_true(b.prize.is_empty())
	assert_eq(b.status, ShipState.Status.ACTIVE)
	assert_eq(b.player_id, 0, "back with her own side")
	assert_true(GameState.get_player_ships(0).has(b))
	assert_eq(b.crew_count, [0, 4, 6, 0] as Array[int], "her original crew is freed")
	assert_eq(b.crew_quality, "G", "as 10.H.4: G6")
	assert_eq(b.morale_rating, 6)
	assert_eq(_events(PhaseEvents.Type.RECAPTURED).size(), 1)
	assert_true(action.retaken)
	assert_true(taking.prize_aboard, "the old capture is finished: no prize crew follows")
	# 10.G.2: the winners reorganize, then come home with no prize crew.
	assert_eq(c.tasks_with("RO").size(), 2)
	_finish_ro(c)
	boarding.advance_reorganizing(STATUS)
	assert_true(action.prize_aboard)
	assert_eq(c.marine_count, 2, "nobody detached")
	assert_eq(b.crew_count, [0, 4, 6, 0] as Array[int])
	# Spec §8 Q5: she scores by her state at the end, at her original value (MR 4, not 6).
	var vc := VictoryController.new(GameState)
	assert_eq(b.original_morale_rating(), 4)
	assert_almost_eq(vc.points_lost(b), 80.0 * 0.30, 0.001, "C4 = 80; S1, S4 and M empty: 30 %")


func test_prize_with_her_crew_aboard_defends_with_it() -> void:
	# A prize with her prize crew may be boarded (10.G.5 no longer refused); her marines defend.
	var b := _prize("b", "a", [0, 0, 0, 2], 1, [2, 6, 6, 6])
	var c := _ship("c", 0, Vector2i(5, 5), "C", 3, [3, 3, 3, 3], 4)
	assert_true(b.can_be_boarded())
	_link(c, b)
	assert_eq(BoardingRules.boardable_error(c, b, GameState.linked_at_plot["c"]), "")
	_readied(c, [M])
	_task(c, "BA", M, "b")
	boarding.declare(COMBAT)
	var action: BoardingAction = GameState.boarding_actions[0]
	assert_eq(action.defender_sections, [M] as Array[int], "10.C.3: the prize crew's marines")
	assert_eq(action.helper_id, "", "no reorganizing captors")
	assert_false(action.original_crew_joins, "the original crew stays below (10.H.3)")


# --- 10.H.4, §6 test 46 ---

func test_46_original_crew_retakes_below_the_minimum() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 2, [4, 5, 6, 6], 2)
	# Class 2 prize (minimum 3), prize crew down to 1, original crew 1 box: 1 < 2 x 1.
	var b := _prize("b", "a", [0, 0, 0, 1], 0, [1, 0, 0, 0])
	boarding.start_of_turn(TurnPhaseController.GamePhase.ENVIRONMENT)
	assert_true(b.is_captured(), "original 1 box: not twice the prize crew")
	# Original crew 2 boxes: 2 >= 2 x 1: retaken at the start of the g-t, G6.
	b.prize["original_crew"]["crew_count"] = [2, 0, 0, 0]
	assert_true(BoardingController.recapture_due(b))
	boarding.start_of_turn(TurnPhaseController.GamePhase.ENVIRONMENT)
	assert_false(b.is_captured(), "retaken")
	assert_eq(b.player_id, 0)
	assert_eq(b.crew_count, [2, 0, 0, 0] as Array[int])
	assert_eq(b.crew_quality, "G")
	assert_eq(b.morale_rating, 6)
	var ev := _events(PhaseEvents.Type.RECAPTURED)
	assert_eq(ev.size(), 1)
	assert_eq(int(ev[0].data["prize_boxes"]), 1)
	assert_string_contains(ev[0].to_text({}), "retakes the ship")
	assert_true(GameState.get_player_ships(0).has(b))
	assert_false(GameState.get_player_ships(1).has(b))
	assert_true(a.tasks_with("RO").is_empty())
	# Prize crew 3 (the minimum), original 20: not below the minimum, no recapture.
	var d := _prize("d", "a", [0, 0, 1, 2], 0, [2, 6, 6, 6])
	d.hex_position = Vector2i(9, 9)
	boarding.start_of_turn(TurnPhaseController.GamePhase.ENVIRONMENT)
	assert_true(d.is_captured(), "prize crew at the minimum")


# --- 10.H.3: the original crew fights the fires below ---

func test_original_crew_fights_the_prize_fires() -> void:
	var b := _prize("b", "a", [0, 0, 1, 2], 0, [2, 6, 6, 6])
	b.fire_list.append({"seq": 1, "created_turn": 5, "started_turn": 5, "cause": "crit"})
	b.fire_seq = 1
	var fc: FireController = GameState.fire_controller
	# 1st g-t: d10 0 + SK G +3 = 3 > 2: still burning (damage: 1R 1H, no dice on a sound ship).
	_dice.queue([0])
	fc.resolve(STATUS)
	assert_eq(_dice.remaining(), 0)
	assert_true(b.is_burning())
	var ev := _events(PhaseEvents.Type.FIRE_FOUGHT)
	assert_eq(ev.size(), 1)
	assert_true(bool(ev[0].data["below"]))
	assert_eq(int(ev[0].data["modifier"]), 3, "CQ G")
	assert_string_contains(ev[0].to_text({}), "original crew below")
	assert_eq(b.pending_morale_checks, 0, "a prize takes no unfought-fire MC")
	# 2nd g-t: the same crew's 2nd g-t, d10 0 + 3 = 3 <= 3: out.
	GameState.phase_controller.current_turn = 6
	GameState.current_turn = 6
	_dice.queue([0])
	fc.resolve(STATUS)
	assert_false(b.is_burning(), "put out by the crew below")
	assert_false((b.prize.get("fires_below", {}) as Dictionary).has("1"))


func test_no_fire_fought_below_without_an_original_crew() -> void:
	var b := _prize("b", "a", [0, 0, 1, 2], 0, [0, 0, 0, 0])
	b.fire_list.append({"seq": 1, "created_turn": 5, "started_turn": 5, "cause": "crit"})
	b.fire_seq = 1
	GameState.fire_controller.resolve(STATUS)
	assert_eq(_events(PhaseEvents.Type.FIRE_FOUGHT).size(), 0)


# --- 1.G.8 and the views ---

func test_a_prize_sails_under_her_captors_navy_and_back() -> void:
	var a := _ship("a", 1, Vector2i(5, 5), "B", 3, [4, 5, 6, 6], 2, 3)
	a.navy = "French"
	var b := _ship("b", 0, Vector2i(6, 5), "C", 3, [2, 6, 6, 6], 0, 4)
	_take(a, b)
	assert_true(b.is_french_gunned(), "1.G.8c: the navy using her (EXAMPLE 2)")
	b.prize["prize_crew_aboard"] = true
	b.crew_count = [0, 0, 0, 0] as Array[int]
	boarding.start_of_turn(TurnPhaseController.GamePhase.ENVIRONMENT)
	assert_false(b.is_captured())
	assert_false(b.is_french_gunned(), "back under her own navy")


func test_maintenance_panel_prize_stepper() -> void:
	var option := {"action_id": 3, "prize_id": "b", "captor_id": "a", "minimum": 2, "maximum": 4, "size": 2,
		"previews": [{"size": 2, "prize": "0-0-0-2:0", "parent": "2-5-6-6:2"},
			{"size": 3, "prize": "0-0-0-3:0", "parent": "1-5-6-6:2"},
			{"size": 4, "prize": "0-0-0-4:0", "parent": "0-5-6-6:2"}]}
	var panel := MaintenanceOrdersPanel.new()
	add_child_autofree(panel)
	panel.setup("prize_size", [option], {"a": "Lively", "b": "Topaze"})
	assert_eq(MaintenanceOrdersPanel.title("prize_size"), "Prize crew")
	assert_eq(panel.selected_sizes(), {3: 2})
	panel.step_prize(3, 1)
	panel.step_prize(3, 5)
	assert_eq(panel.selected_sizes(), {3: 4}, "capped at the boarders")
	assert_eq(MaintenanceOrdersPanel.prize_text(option, 3, {"a": "Lively", "b": "Topaze"}),
		"Topaze: prize crew 3 (minimum 2) · Topaze 0-0-0-3:0 · Lively keeps 1-5-6-6:2")
	watch_signals(panel)
	panel._on_done()
	assert_signal_emitted_with_parameters(panel, "orders_submitted", ["prize_size", {3: 4}])


func test_is_server_false_refuses_prize_mutations() -> void:
	var b := _prize("b", "a", [0, 0, 0, 1], 0, [4, 0, 0, 0])
	boarding.is_server = false
	boarding.start_of_turn(TurnPhaseController.GamePhase.ENVIRONMENT)
	assert_push_error("Cannot check recaptures on client")
	boarding.retake("b", "rose", 0)
	assert_push_error("Cannot retake a ship on client")
	assert_ne(boarding.set_prize_size(1, 2), "")
	assert_push_error("Cannot set a prize-crew size on client")
	boarding.is_server = true
	assert_true(b.is_captured(), "a client never retakes a ship")
