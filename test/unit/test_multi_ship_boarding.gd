extends GutTest
## Multi-ship boarding (Close Action 1997, 10.F; boarding spec B6, §3.4, §6 test 53): several ships
## boarding one, one ship boarding while it defends, the defence shared out, the sixth-ship rule,
## simultaneous results (10.F.3) and the 10.F.3 example (Mars, Themis, Hermione).
## Numbers from the Boarding Combat chart (p.109): BCF at CQ D sailor 5, marine 7; rows 2d6 <=4 2 %,
## 8 10 %, 11 25 %; attacker 11+ "defending ship captured", defender 8-10 "attacker repulsed and
## takes 1 MC". Odds DRMs (F:E rounded down): 1:4 -4, 2:3 -1, 1:1 0, 2:1 +2, 3:1 +3. Other DRMs: a
## class 3 defender -1, same class 0. Crew Loss "All Other Causes": d6 1-3 sailor, 4-6 marine.
## Losses are the row's % of the roller's TBCF, to the nearest BCF (10.D.4).

const PHASE := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT
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
	GameState.ships_by_side = {0: [], 1: []}
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
	GameState.ships_by_side = {0: [], 1: []}
	GameState.boarding_actions = []
	GameState.linked_at_plot = {}


# --- fixtures (as test_boarding.gd) ---

## A class 3 frigate at CQ D, MR 3, with the given live crew; its type's crew is 6-6-7-7:7.
func _ship(id: String, player: int, hex: Vector2i, crew: Array, marines: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": id, "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [6, 6, 7, 7], "marine_count": 7, "point_costs": {"D3": 100},
	})
	state.hex_position = hex
	state.facing = 1
	state.sail_state = "FS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = ShipState._int_array(crew)
	state.marine_count = marines
	state.crew_quality = "D"
	state.starting_crew_quality = "D"
	state.morale_rating = 3
	state.crew_auto = false
	GameState.ships[id] = state
	GameState.ships_by_side[player].append(id)
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


## Grapples the two ships and takes the PLANNING link snapshot (10.A.2).
func _link(a: ShipState, b: ShipState) -> void:
	a.grappled_with.append(b.ship_id)
	b.grappled_with.append(a.ship_id)
	boarding.take_link_snapshot()


func _events(type: PhaseEvents.Type) -> Array[PhaseEvents.PhaseEvent]:
	return GameState.turn_log.of_type(type)


func _action(attacker_id: String, defender_id: String) -> BoardingAction:
	for a in GameState.boarding_actions:
		if a.attacker_id == attacker_id and a.defender_id == defender_id:
			return a
	return null


func _names() -> Dictionary:
	var out := {}
	for s in GameState.get_all_ships():
		out[s.ship_id] = s.ship_name
	return out


## d (CQ D, 3-3-3-3:2, M, S1 and S2 readied) boarded by a (marines 4 and S1 3: TBCF 4x7 + 3x5 = 43)
## and c (S1 3: TBCF 15).
func _two_board_one() -> Array:
	var d := _ship("d", 1, Vector2i(6, 5), [3, 3, 3, 3], 2)
	var a := _ship("a", 0, Vector2i(5, 5), [3, 3, 3, 3], 4)
	var c := _ship("c", 0, Vector2i(7, 6), [3, 3, 3, 3], 2)
	_readied(d, [M, 0, 1])
	_link(a, d)
	_link(c, d)
	_task(a, "BA", M, "d")
	_task(a, "BA", 0, "d")
	_task(c, "BA", 0, "d")
	boarding.declare(PHASE)
	return [a, c, d]


# --- 10.F.2: the defence is shared out (spec §3.4, §6 test 53) ---

func test_53_two_ships_board_one_defence_shared_out() -> void:
	_two_board_one()
	# 10.F.2: one combat per enemy ship. Spec §3.4: the marines to the higher TBCF (a, 43), then the
	# readied sailor sections in order round robin: S1 to c, S2 to a.
	assert_eq(GameState.boarding_actions.size(), 2, "two separate combats")
	assert_eq(Array(_action("a", "d").defender_sections), [1, M])
	assert_eq(Array(_action("c", "d").defender_sections), [0])
	var split := _events(PhaseEvents.Type.DEFENCE_SPLIT)
	assert_eq(split.size(), 1)
	assert_eq(split[0].to_text(_names()), "d, boarded by 2 ships, splits her defence: S2, marines against a; S1 against c (10.F.2)")
	var d: ShipState = GameState.get_ship("d")
	assert_eq(d.boarding_action_of(0), _action("c", "d").id, "each section is engaged with one named enemy")
	assert_eq(d.boarding_action_of(M), _action("a", "d").id)


func test_actions_are_fought_separately() -> void:
	var ships := _two_board_one()
	# a v d: 43 v 29 (S2 15 + marines 14). a 1:1 0, class 3 -1 = -1; d 29:43 = 2:3 -1.
	#   2d6 2 and 2: both 1, 2 % of 43 = 1 BCF and 2 % of 29 = 1 BCF; d6 1 and 1: a sailor each.
	# c v d: 15 v 15. c -1, d 0. 2d6 2 and 2: 2 % of 15 = 0 BCF each, no Crew Loss d6.
	_dice.queue([1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	boarding.resolve(PHASE)
	assert_eq(_dice.remaining(), 0, "10.F.2: two rounds, each with its own rolls")
	var rounds := _events(PhaseEvents.Type.BOARDING_ROUND)
	assert_eq(rounds.size(), 2)
	assert_eq(int(rounds[0].data["attacker"]["tbcf"]), 43)
	assert_eq(int(rounds[0].data["defender"]["tbcf"]), 29)
	assert_eq(int(rounds[1].data["defender"]["tbcf"]), 15)
	var d: ShipState = ships[2]
	assert_eq(Array(d.crew_count), [3, 2, 3, 3], "only S2, engaged with a, lost a box; S1 fought c and lost none")
	assert_eq((ships[0] as ShipState).crew_count[0], 2)
	assert_eq(_action("a", "d").state, BoardingAction.ENGAGED)
	assert_eq(_action("c", "d").state, BoardingAction.ENGAGED)


func test_capture_in_one_action_takes_her_in_all() -> void:
	var ships := _two_board_one()
	var a: ShipState = ships[0]
	var c: ShipState = ships[1]
	var d: ShipState = ships[2]
	# a v d fights on (as above); c v d: 2d6 12 - 1 = 11: "defending ship captured" (no d10).
	_dice.queue([1, 1, 1, 1, 1, 1, 6, 6, 1, 1])
	boarding.resolve(PHASE)
	assert_eq(_dice.remaining(), 0)
	assert_true(d.is_captured(), "10.E.2d")
	assert_eq(str(d.prize["captor_id"]), "c")
	var shared := _action("a", "d")
	# The 10.F.3 example: "All French CSs boarding the Mars must now reorganize".
	assert_eq(shared.state, BoardingAction.ATTACKER_WON)
	assert_eq(shared.outcome, "shared_capture")
	assert_eq(shared.shared_with, _action("c", "d").id)
	assert_eq(a.tasks_with("RO").size(), 2, "a's marines and S1 reorganize aboard her (10.G.2)")
	assert_eq(c.tasks_with("RO").size(), 1)
	var texts := PackedStringArray()
	for ev in _events(PhaseEvents.Type.BOARDING_RESULT):
		texts.append(ev.to_text(_names()))
	assert_has(texts, "a's boarders are aboard d as c takes her: they reorganize too (10.F)")
	# RO over: the prize crew comes from the action that took her only (class 3: 2 boxes, 10.G.6).
	for ship in [a, c]:
		for task in ship.tasks_with("RO"):
			ship.crew_tasks.erase(task)
	boarding.advance_reorganizing(STATUS)
	assert_eq(d.total_crew_boxes(), 2)
	assert_eq(c.crew_count[0], 1, "the prize crew leaves c's S1")
	assert_eq(a.crew_count[0], 2, "a's boarders come home")
	assert_eq(a.marine_count, 4)
	assert_true(shared.prize_aboard, "the shared action is finished")


func test_attacker_left_with_no_defender_takes_her() -> void:
	var d := _ship("d", 1, Vector2i(6, 5), [3, 3, 3, 3], 2)
	var a := _ship("a", 0, Vector2i(5, 5), [3, 3, 3, 3], 4)
	var c := _ship("c", 0, Vector2i(7, 6), [3, 3, 3, 3], 2)
	_link(a, d)
	_link(c, d)
	_task(a, "BA", M, "d")
	_task(a, "BA", 0, "d")
	_task(c, "BA", 0, "d")
	boarding.declare(PHASE)
	# 10.C.3: her marines are replotted to FB and go to the higher TBCF (a); c has no one against it:
	# 10.E.2b, she is taken with no roll (spec §3.4), and a shares the capture.
	assert_eq(_events(PhaseEvents.Type.MARINES_DEFEND).size(), 1)
	assert_true(d.is_captured())
	assert_eq(str(d.prize["captor_id"]), "c")
	assert_eq(_action("c", "d").outcome, "undefended")
	assert_eq(_action("a", "d").outcome, "shared_capture")
	var cap: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.SHIP_CAPTURED)[0]
	assert_eq(cap.to_text(_names()), "d is taken by c: no one is left to defend her (10.E.2b)")
	assert_eq(_dice.remaining(), 0, "no dice")


func test_later_defenders_are_shared_out_too() -> void:
	_two_board_one()
	var d: ShipState = GameState.get_ship("d")
	_readied(d, [2, 3])
	boarding._join_defenders([_action("a", "d"), _action("c", "d")])
	# 10.E.1 with 10.F.2: S3 to the higher TBCF (a), S4 to c.
	assert_eq(Array(_action("a", "d").defender_sections), [1, 2, M])
	assert_eq(Array(_action("c", "d").defender_sections), [0, 3])


# --- 10.F.2: the sixth ship ---

func _many_board_one(count: int) -> ShipState:
	var d := _ship("d", 1, Vector2i(6, 5), [3, 3, 3, 3], 2)
	_readied(d, [M, 0, 1, 2, 3])
	for i in range(count):
		var b := _ship("b%d" % (i + 1), 0, Vector2i(i, 9), [3, 3, 3, 3], 0)
		b.grappled_with.append("d")
		d.grappled_with.append(b.ship_id)
		_task(b, "BA", 0, "d")
	boarding.take_link_snapshot()
	boarding.declare(PHASE)
	return d


func test_five_boarding_ships_are_fought_one_section_each() -> void:
	var d := _many_board_one(5)
	# 10.F.2: "a single ship could engage up to five enemy ships in boarding by allocating one CS to
	# fight each enemy ship". Equal TBCFs: by ship_id, the marines to b1, S1 to b2 ... S4 to b5.
	assert_false(d.is_captured())
	assert_eq(GameState.boarding_actions.size(), 5)
	assert_eq(Array(_action("b1", "d").defender_sections), [M])
	assert_eq(Array(_action("b2", "d").defender_sections), [0])
	assert_eq(Array(_action("b5", "d").defender_sections), [3])


func test_sixth_boarding_ship_captures_outright() -> void:
	var d := _many_board_one(6)
	# 10.F.2: "if a sixth enemy ship managed to board the friendly ship, the friendly ship would be
	# overwhelmed and would automatically be captured."
	assert_true(d.is_captured())
	assert_eq(str(d.prize["captor_id"]), "b6")
	assert_eq(_action("b6", "d").outcome, "overwhelmed")
	for i in range(1, 6):
		assert_eq(_action("b%d" % i, "d").outcome, "shared_capture")
	var cap: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.SHIP_CAPTURED)[0]
	assert_eq(cap.to_text(_names()), "d is overwhelmed by a sixth boarding ship and taken by b6 (10.F.2)")
	assert_eq(_dice.remaining(), 0, "no dice")


func test_sixth_ship_counts_those_already_in_action() -> void:
	var d := _many_board_one(5)
	var b6 := _ship("b6", 0, Vector2i(6, 9), [3, 3, 3, 3], 0)
	_link(b6, d)
	_task(b6, "BA", 0, "d")
	boarding.declare(PHASE)
	assert_true(d.is_captured(), "10.F.2: the five already fighting her count")
	assert_eq(str(d.prize["captor_id"]), "b6")


# --- one ship boarding while defending, and 10.F.3 ---

func test_ship_boards_one_enemy_while_defending_against_another() -> void:
	var x := _ship("x", 0, Vector2i(5, 5), [3, 3, 3, 3], 2)
	var y := _ship("y", 1, Vector2i(6, 5), [3, 3, 3, 3], 2)
	var z := _ship("z", 1, Vector2i(4, 5), [3, 3, 3, 3], 2)
	_link(x, y)
	_link(z, x)
	_task(x, "BA", 0, "y")
	_task(z, "BA", 0, "x")
	boarding.declare(PHASE)
	# 10.F.2: each CS is engaged with one enemy: x's S1 boards y, x's marines (10.C.3) defend
	# against z; y's marines defend against x.
	assert_eq(GameState.boarding_actions.size(), 2)
	assert_eq(Array(_action("x", "y").attacker_sections), [0])
	assert_eq(Array(_action("z", "x").defender_sections), [M])
	assert_eq(Array(_action("x", "y").defender_sections), [M])
	assert_eq(x.boarding_action_of(0), _action("x", "y").id)
	assert_eq(x.boarding_action_of(M), _action("z", "x").id)


func test_boarding_marines_are_not_replotted_to_defend() -> void:
	# w sorts before x, so x's boarding of w is announced before z's boarding of x.
	var x := _ship("x", 0, Vector2i(5, 5), [3, 3, 3, 3], 2)
	var w := _ship("w", 1, Vector2i(6, 5), [3, 3, 3, 3], 2)
	var z := _ship("z", 1, Vector2i(4, 5), [3, 3, 3, 3], 2)
	_link(x, w)
	_link(z, x)
	_task(x, "BA", M, "w")
	_task(z, "BA", 0, "x")
	boarding.declare(PHASE)
	# 10.C.3 replots marines on a non-boarding task only; x's marines are away at w, so x has no one
	# to defend against z: 10.E.2b, taken. Her boarders aboard w are cut off and surrender (10.D.6).
	assert_true(x.is_captured())
	assert_eq(str(x.prize["captor_id"]), "z")
	assert_eq(_action("x", "w").state, BoardingAction.DEFENDER_WON)
	assert_eq(_action("x", "w").outcome, "surrendered")
	assert_false(w.is_captured())


func test_repulse_in_one_action_leaves_the_other() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), [3, 3, 3, 3], 4)
	var b := _ship("b", 1, Vector2i(6, 5), [3, 3, 3, 3], 2)
	var c := _ship("c", 1, Vector2i(4, 5), [3, 3, 3, 3], 2)
	_link(a, b)
	_link(a, c)
	_task(a, "BA", M, "b")
	_task(a, "BA", 0, "c")
	boarding.declare(PHASE)
	# b v a (marines 28 v marines 14): a 2:1 +2, class -1 = +1, 2d6 2 -> 3: 2 % of 28 = 1 BCF;
	#   b 1:2 -2, 2d6 10 -> 8: 10 % of 14 = 1 BCF and "attacker repulsed, 1 MC". One crew type each.
	# c v a (S1 15 v marines 14): a -1, c 2:3 -1; 2d6 2 and 2: 0 BCF each; fight on.
	_dice.queue([1, 1, 5, 5, 1, 1, 1, 1])
	boarding.resolve(PHASE)
	assert_eq(_dice.remaining(), 0)
	assert_eq(_action("a", "b").outcome, "repulsed")
	# 10.D.5a disbands the attacker's other FB/BR, but 10.F.3: not a section locked against c.
	assert_true(a.boarding_task(M).is_empty(), "the repulsed marines are disbanded")
	assert_eq(a.boarding_action_of(0), _action("a", "c").id, "S1 fights on aboard c")
	assert_eq(_action("a", "c").state, BoardingAction.ENGAGED)


func test_10_f_3_example_mars_takes_themis_as_hermione_takes_mars() -> void:
	# The 10.F.3 example, cut down: Mars boards Themis (marines 4, S1 3) while Hermione boards Mars
	# (S1 3), Mars defending with S4. Both captures happen on the same g-t.
	var mars := _ship("mars", 0, Vector2i(5, 5), [3, 3, 3, 3], 4)
	var themis := _ship("themis", 1, Vector2i(6, 5), [3, 3, 3, 3], 2)
	var hermione := _ship("hermione", 1, Vector2i(4, 5), [3, 3, 3, 3], 2)
	_link(mars, themis)
	_link(hermione, mars)
	_readied(mars, [3])
	_task(mars, "BA", M, "themis")
	_task(mars, "BA", 0, "themis")
	_task(hermione, "BA", 0, "mars")
	boarding.declare(PHASE)
	# hermione v mars (15 v 15): hermione -1, 2d6 12 -> 11 "captured", 25 % of 15 = 4 BCF (one S4
	#   box); mars 0, 2d6 2: 0 BCF.
	# mars v themis (43 v marines 14): mars 3:1 +3, class -1 = +2, 2d6 9 -> 11 "captured", 25 % of 43
	#   = 11 BCF (both marines); themis 1:4 -4, 2d6 2 -> -2: 0 BCF.
	_dice.queue([6, 6, 1, 1, 5, 4, 1, 1])
	boarding.resolve(PHASE)
	assert_eq(_dice.remaining(), 0)
	# "Themis is now British-controlled, while Mars has been captured by the French."
	assert_true(themis.is_captured())
	assert_eq(themis.side, 0)
	assert_true(mars.is_captured())
	assert_eq(mars.side, 1)
	# Mars' boarders aboard Themis are cut off from Mars: they hold Themis as her prize crew at once
	# (spec 0.4 #6 by analogy): 3 sailors from S4 down and 4 marines, at Mars' CQ D.
	assert_true(themis.has_prize_crew())
	assert_eq(Array(themis.crew_count), [0, 0, 0, 3])
	assert_eq(themis.marine_count, 4)
	# "S2 and S3 are accordingly taken prisoner": Mars' crew goes below.
	assert_eq(Array(mars.prize["original_crew"]["crew_count"]), [0, 3, 3, 2])
	assert_eq(hermione.tasks_with("RO").size(), 1, "Hermione's boarders reorganize aboard Mars")


# --- log, card and overlay ---

func test_round_text_names_later_rounds() -> void:
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BOARDING_ROUND, PHASE, "a", {"round": 2,
		"attacker": {"tbcf": 62, "roll": 9, "drm": -2, "total": 7},
		"defender": {"tbcf": 44, "roll": 9, "drm": -1, "total": 8}}, "b")
	assert_eq(ev.to_text({"a": "Vengeance", "b": "Hermione"}),
		"Boarding, Vengeance onto Hermione (round 2): 62 v 44; attacker 9 −2 = 7, defender 9 −1 = 8")


func test_results_without_a_round_are_logged() -> void:
	var names := {"a": "Vengeance", "b": "Hermione"}
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BOARDING_RESULT, PHASE, "a", {"result": "surrendered"}, "b")
	assert_eq(ev.to_text(names), "Vengeance's boarders aboard Hermione surrender with their ship (10.D.6)")
	ev = PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BOARDING_RESULT, PHASE, "a", {"result": "captured", "reason": "struck_in_action"}, "b")
	assert_eq(ev.to_text(names), "Hermione has struck with boarders aboard (10.E.2c)")
	ev = PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BOARDING_RESULT, PHASE, "a", {"result": "target_gone"}, "b")
	assert_eq(ev.to_text(names), "The fight aboard Hermione ends: she is gone")


func test_parent_strikes_logs_surrender() -> void:
	var a := _ship("a", 0, Vector2i(5, 5), [3, 3, 3, 3], 0)
	var b := _ship("b", 1, Vector2i(6, 5), [3, 3, 3, 3], 0)
	_link(a, b)
	_task(a, "BA", 0, "b")
	_task(b, "FB", 0)
	boarding.declare(PHASE)
	a.status = ShipState.Status.STRUCK
	boarding.resolve(PHASE)
	var r: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.BOARDING_RESULT)[0]
	assert_eq(r.data["result"], "surrendered", "10.D.6, now logged")


func test_card_stacks_the_rounds_of_one_combat() -> void:
	var card: BoardingCard = autofree(BoardingCard.new())
	card.setup("a", "d", {"round": 1, "attacker": {}, "defender": {}}, {"result": "fight_on"}, {})
	card.add_round("c", "d", {"round": 1, "attacker": {}, "defender": {}}, {"result": "captured"}, {})
	assert_eq(card.round_count(), 2)
	assert_eq(BoardingCard.title_text(2), "BOARDING · 2 ACTIONS (10.F)")
	assert_eq(BoardingCard.title_text(1), "BOARDING")
	assert_eq(BoardingCard.result_text({"result": "shared_capture"}), "CAPTURED · BY ANOTHER SHIP")


func test_card_reads_each_actions_own_result() -> void:
	var combat := PhaseEvents.PhaseLog.new()
	var r1 := combat.add(PhaseEvents.Type.BOARDING_ROUND, PHASE, "a", {"action": 1}, "d")
	var r2 := combat.add(PhaseEvents.Type.BOARDING_ROUND, PHASE, "c", {"action": 2}, "d")
	combat.add(PhaseEvents.Type.BOARDING_RESULT, PHASE, "a", {"action": 1, "result": "fight_on"}, "d")
	combat.add(PhaseEvents.Type.BOARDING_RESULT, PHASE, "c", {"action": 2, "result": "captured"}, "d")
	combat.add(PhaseEvents.Type.BOARDING_RESULT, PHASE, "a", {"action": 1, "result": "shared_capture"}, "d")
	assert_eq(BoardingCard.result_for(combat, r1)["result"], "shared_capture", "the last word on action 1")
	assert_eq(BoardingCard.result_for(combat, r2)["result"], "captured")


func test_guns_readout_of_a_prize() -> void:
	var p := _ship("p", 0, Vector2i(5, 5), [0, 0, 0, 3], 0)
	p.status = ShipState.Status.CAPTURED
	p.prize = {"captor_id": "x", "prize_crew_aboard": true, "original_crew": {}}
	var g := CrewOverlayText.guns_readout(p, {"assignments": {}})
	# 10.H.2, boarding spec §8 Q2: a prize does not fight, so no gunfire modifier is shown.
	assert_eq(g["big"], "Guns silent · a prize")
	assert_string_contains(g["why"], "A prize does not fight (10.H.2)")


func test_prize_label_sits_clear_of_the_hull() -> void:
	# Top-down camera (pitched straight down, north up): screen-up on the water is -Z.
	var down := Basis(Vector3.RIGHT, -PI / 2.0)
	var along := ShipView.prize_label_offset(down, 0.0)  # bow to the north: along the screen's up
	assert_almost_eq(along.z, -(ShipView.LABEL_HALF_LENGTH + ShipView.LABEL_GAP), 0.001, "beyond the bow")
	assert_almost_eq(along.x, 0.0, 0.001)
	var abeam := ShipView.prize_label_offset(down, PI / 2.0)  # bow to the west: beam towards the top
	assert_almost_eq(abeam.z, -(ShipView.LABEL_HALF_BEAM + ShipView.LABEL_GAP), 0.001, "beyond the side")
	assert_gt(along.y, 0.0, "above the water")


func test_card_shows_the_crew_below_with_the_attackers() -> void:
	var lines := BoardingCard.column_lines({"sections": [4], "marines": 4, "sailors": 20, "below": 20}, true)
	assert_has(lines, "incl. 20 of the prize's crew from below (CQ G, 10.G.5)")


func test_prize_label_avoids_ships_alongside() -> void:
	var down := Basis(Vector3.RIGHT, -PI / 2.0)
	var above: Array[Vector3] = [Vector3(0.5, 0, -1.5), Vector3(-0.5, 0, -1.5)]
	var place := ShipView.prize_label_place(down, PI / 2.0, above, 3.0, 0.7)
	assert_true(place["below"], "a ship alongside above: the label goes below the hull")
	var both: Array[Vector3] = [Vector3(0.5, 0, -1.5), Vector3(0.5, 0, 1.5)]
	place = ShipView.prize_label_place(down, PI / 2.0, both, 3.0, 0.7)
	var z: float = (place["offset"] as Vector3).z
	assert_true(absf(z) > 1.5 + ShipView.LABEL_HULL_RADIUS, "sandwiched: pushed out past the neighbour")


# --- Log: one capture line, sides as they were (crew spec phase 6) ---

func _result_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for ev in _events(PhaseEvents.Type.BOARDING_RESULT):
		texts.append(ev.to_text(_names()))
	return texts


func test_two_actions_that_both_take_her_log_the_capture_once() -> void:
	var ships := _two_board_one()
	var d: ShipState = ships[2]
	d.status = ShipState.Status.STRUCK  # 10.E.2c in both actions: no round, no dice
	boarding.resolve(PHASE)
	assert_true(d.is_captured())
	var texts := _result_texts()
	assert_eq(texts.size(), 2, "one line per action: %s" % [texts])
	var struck_lines := 0
	for t in texts:
		if t.contains("has struck with boarders aboard"):
			struck_lines += 1
	assert_eq(struck_lines, 1, "the capture is logged once: %s" % [texts])
	assert_eq(_events(PhaseEvents.Type.SHIP_CAPTURED).size(), 1)
	var captor := str(d.prize["captor_id"])
	var other := "c" if captor == "a" else "a"
	assert_has(texts, "%s's boarders are aboard d as %s takes her: they reorganize too (10.F)" % [other, captor])


func test_shared_capture_keeps_the_superseded_capture_roll() -> void:
	_two_board_one()
	var a_act := _action("a", "d")
	var c_act := _action("c", "d")
	# Both actions rolled "captured if d10 < MR" and made it (as _fight logs them).
	for act in [a_act, c_act]:
		GameState.turn_log.add(PhaseEvents.Type.BOARDING_RESULT, PHASE, act.attacker_id,
			{"special": "capture_if_lt_mr", "side": "attacker", "d10": 1, "mr": 3, "mcs": 0,
			"result": "captured", "action": act.id, "round": 1}, "d")
	boarding._apply_outcomes([
		{"action": a_act, "kind": "capture", "outcome": "captured", "mcs": 0},
		{"action": c_act, "kind": "capture", "outcome": "captured", "mcs": 0}], PHASE)
	var texts := _result_texts()
	assert_eq(texts, PackedStringArray([
		"a's boarders carry d! (capture roll d10 1 < MR 3)",
		"c's boarders are aboard d as a takes her: they reorganize too (10.F) (capture roll d10 1 < MR 3)"]))


func test_capture_log_labels_ships_by_their_side_when_logged() -> void:
	GameState.turn_log = GameState.new_turn_log(5)
	var ships := _two_board_one()
	var d: ShipState = ships[2]
	d.status = ShipState.Status.STRUCK
	boarding.resolve(PHASE)
	assert_eq(d.side, 0, "d is now a prize of side 0")
	var info := CombatLogPanel.log_ships(GameState.get_all_ships())
	var split: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.DEFENCE_SPLIT)[0]
	assert_eq(split.sides.get("d"), 1, "recorded at log time")
	assert_string_contains(split.to_text(CombatLogPanel.event_names(split, info)), "d (enemy), boarded by 2 ships")
	var cap: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.SHIP_CAPTURED)[0]
	assert_string_starts_with(cap.to_text(CombatLogPanel.event_names(cap, info)), "d (enemy) is taken by ")
	# A line logged after the capture shows her new side.
	var later := GameState.turn_log.add(PhaseEvents.Type.HOLD_FIRE, PHASE, "d")
	assert_eq(later.to_text(CombatLogPanel.event_names(later, info)), "d (yours) holds fire.")
