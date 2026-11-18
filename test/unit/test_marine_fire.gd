extends GutTest
## Marine fire (Close Action 7.G; boarding spec B2, §1.6, §3.3, tests 48-51): MarineFireResolver,
## FireRules.marine_error, the fire submission's marine orders and the AI's choice.
## Expected values from the Marine Fire table and DRMs (gunfire results chart, p.110).

const PHASE := TurnPhaseController.GamePhase.COMBAT_RESOLUTION

var mf: MarineFireResolver
var a: ShipState
var b: ShipState
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_env = GameState.environment
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	mf = MarineFireResolver.new(GameState)
	# a (player 0) bow (0,0) facing E; b (player 1) bow (-1,1) facing W: abeam, adjacent (range 1).
	a = _make_ship("a_ship", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_ship", 1, Vector2i(-1, 1), 3)


func after_each() -> void:
	var pc: TurnPhaseController = GameState.phase_controller
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, player: int, hex: Vector2i, facing: int, ship_class: int = 3,
		marines: int = 2, quality: String = "D") -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": ship_class,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": marines,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex
	state.facing = facing
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.marine_count = marines
	state.crew_quality = quality
	GameState.ships[id] = state
	GameState.ships_by_side[player].append(id)
	return state


## Puts the marines on a live task this g-t (FB/BR/BD leave them available, 10.B.4-5).
func _marines_on(ship: ShipState, code: String, marines_available: bool) -> void:
	ship.task_seq += 1
	ship.crew_tasks.append(ShipState.crew_task_from({
		"seq": ship.task_seq, "code": code, "sections": [ShipState.MARINES], "done": 0, "started_turn": 1,
		"params": {}, "forced": false, "marines_available": marines_available, "ended": "",
	}))
	ship.plotted_sections.append(ShipState.MARINES)


func _order(ship_id: String = "a_ship", target_id: String = "b_ship") -> Dictionary:
	return {"ship_id": ship_id, "target_id": target_id}


func _marine_events() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.MARINE_FIRE)


# --- The table and DRMs (spec tests 48, 49) ---

func test_seven_boxes_fouled_to_target_d6_5_loses_one_box() -> void:
	# Spec test 48: 7 boxes, fouled to the target (-1), CQ D, d6 5: 5 - 1 = 4, column 7-8: 1 box.
	a.marine_count = 7
	a.fouled_with = "b_ship"
	b.fouled_with = "a_ship"
	var p := mf.preview("a_ship", "b_ship")
	assert_true(p["can_fire"])
	assert_eq(p["column"], "7-8")
	assert_eq(p["modifier"], -1)
	_dice.queue([5, 2])  # marine fire d6 5; Crew Loss "All Other Causes" d6 2 = sailor (S 1-3)
	mf.resolve(mf.prepare([_order()]), PHASE)
	var ev: PhaseEvents.PhaseEvent = _marine_events()[0]
	assert_eq(ev.data["total"], 4)
	assert_eq(ev.data["crew"], 1)
	assert_eq(b.total_crew_boxes(), 13, "one box lost")
	assert_eq(b.crew_count[0], 2, "the sailor comes from S1 (7.D.9)")
	assert_eq(_dice.remaining(), 0)


func test_two_boxes_d6_2_has_no_effect() -> void:
	# Spec test 49: 2 boxes, d6 2: column 1-2 hits only on <= 1.
	_dice.queue([2])
	mf.resolve(mf.prepare([_order()]), PHASE)
	assert_eq(_marine_events()[0].data["crew"], 0)
	assert_eq(b.total_crew_boxes(), 14)
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.DAMAGE).size(), 0, "no damage line for a miss")


func test_cq_g_eleven_boxes_d6_1_is_three_one_box() -> void:
	# Spec test 49: CQ G (+2), 11 boxes, d6 1: 1 + 2 = 3, column 11+: 1 box.
	a.marine_count = 11
	a.crew_quality = "G"
	_dice.queue([1, 5])  # crew loss 5 = marine (M 4-6)
	mf.resolve(mf.prepare([_order()]), PHASE)
	var ev: PhaseEvents.PhaseEvent = _marine_events()[0]
	assert_eq(ev.data["modifier"], 2)
	assert_eq(ev.data["total"], 3)
	assert_eq(ev.data["crew"], 1)
	assert_eq(b.marine_count, 1, "the d6 5 takes a marine")


func test_crew_quality_e_and_f_are_plus_one() -> void:
	# Marine Fire DRMs: firing marines CQ = E or F +1.
	for q in ["E", "F"]:
		a.crew_quality = q
		assert_eq(mf.preview("a_ship", "b_ship")["modifier"], 1, "CQ %s" % q)


func test_larger_firing_class_is_minus_one_never_plus() -> void:
	# 7.G.4: firing class # < target class # gives -1; smaller firing ship gets no modifier.
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	a = _make_ship("a_ship", 0, Vector2i.ZERO, 0, 2)
	b = _make_ship("b_ship", 1, Vector2i(-1, 1), 3, 3)
	assert_eq(mf.preview("a_ship", "b_ship")["modifier"], -1, "class 2 firing at class 3")
	assert_eq(mf.preview("b_ship", "a_ship")["modifier"], 0, "class 3 firing at class 2")


func test_target_with_boarders_preparing_is_minus_one() -> void:
	# Marine Fire DRMs: target has boarders preparing or prepared -1 (a live FB/BR/BA task).
	_marines_on(b, "FB", true)
	assert_eq(mf.preview("a_ship", "b_ship")["modifier"], -1)


func test_preview_chance_and_hit_max() -> void:
	# 2 boxes (column 1-2) at DRM 0: hits only on a 1 (17 %); 11 boxes at -1: a 6 -> 5 still hits.
	var p := mf.preview("a_ship", "b_ship")
	assert_eq(p["hit_max"], 1)
	assert_eq(p["chance"], 17)
	a.marine_count = 11
	a.fouled_with = "b_ship"
	p = mf.preview("a_ship", "b_ship")
	assert_eq(p["hit_max"], 6, "6 - 1 = 5: column 11+ hits")
	assert_eq(p["most"], 2, "a 1 (0 after the DRM) is the <= 1 row: 2 boxes")


func test_target_with_one_crew_type_rolls_no_crew_loss_die() -> void:
	# 7.G.3: only one type of crew left, so no Crew Loss roll.
	b.marine_count = 0
	_dice.queue([1])
	mf.resolve(mf.prepare([_order()]), PHASE)
	assert_eq(b.crew_count[0], 2, "a sailor from S1")
	assert_eq(_dice.remaining(), 0, "no Crew Loss d6 consumed")


# --- Who may fire (7.G.1, 7.G.2; spec test 50) ---

func test_marines_on_a_non_boarding_task_cannot_fire() -> void:
	# 7.G.1: marines plotted to any non-boarding task (here RR) cannot use marine fire.
	_marines_on(a, "RR", false)
	var p := mf.preview("a_ship", "b_ship")
	assert_false(p["can_fire"])
	assert_string_contains(p["reason"], "7.G.1")


func test_marines_boarding_away_cannot_fire() -> void:
	# 7.G.1: marines BA (or engaged) may not fire; the BA handler leaves them unavailable.
	_marines_on(a, "BA", false)
	assert_false(mf.preview("a_ship", "b_ship")["can_fire"])


func test_marines_at_br_fb_or_bd_can_fire() -> void:
	# 7.G.1, 10.B.4-5: marines plotted FB, BR or BD may use marine fire.
	for code in ["FB", "BR", "BD"]:
		a.crew_tasks.clear()
		a.plotted_sections.clear()
		_marines_on(a, code, true)
		assert_true(mf.preview("a_ship", "b_ship")["can_fire"], code)


func test_only_adjacent_targets() -> void:
	# 7.G.1: adjacent ships only (the optional range-2 rule is not offered).
	b.hex_position = Vector2i(-1, 2)
	b.facing = 3
	var p := mf.preview("a_ship", "b_ship")
	assert_false(p["can_fire"])
	assert_eq(p["range"], 2)


func test_orientation_does_not_matter() -> void:
	# 7.G.1: a ship dead ahead (no broadside bears) is still a marine target.
	b.hex_position = Vector2i(2, 0)
	b.facing = 0  # stern (1,0), adjacent to a's bow (0,0)
	assert_true(mf.preview("a_ship", "b_ship")["can_fire"])
	var shots := GameState.gunnery_calculator.eligible_shots("a_ship")
	assert_eq(shots.map(func(s): return s.order.side), [GunneryTypes.CHASE_BOW],
		"no broadside bears: only the bow chaser")


func test_struck_own_side_and_no_marines_refused() -> void:
	assert_ne(FireRules.marine_error(a, a, 1), "", "own ship")
	a.marine_count = 0
	assert_string_contains(FireRules.marine_error(a, b, 1), "no marines")
	a.marine_count = 2
	b.status = ShipState.Status.STRUCK
	assert_string_contains(FireRules.marine_error(a, b, 1), "struck")
	b.status = ShipState.Status.ACTIVE
	assert_eq(FireRules.marine_error(a, b, 1), "")
	assert_string_contains(FireRules.marine_error(a, b, 2), "adjacent")


func test_one_target_per_ship() -> void:
	# 7.G.2: the marine section fires at one enemy ship per g-t.
	var c := _make_ship("c_ship", 1, Vector2i(1, -1), 3)
	assert_eq(mf.validate_orders(0, [_order()]), "")
	assert_string_contains(mf.validate_orders(0, [_order(), _order("a_ship", c.ship_id)]), "7.G.2")
	assert_string_contains(mf.validate_orders(1, [_order()]), "not yours")


# --- Simultaneous with gunfire (7.G.5; spec test 51) ---

func test_marine_shot_uses_boxes_at_the_start_of_the_step() -> void:
	# 7.G.5: marine losses to gunfire do not reduce the boxes that fire this g-t.
	a.marine_count = 7
	var shots := mf.prepare([_order()])
	GameState.ship_controller.remove_crew_box("a_ship", true)  # a marine lost to gunfire
	GameState.ship_controller.remove_crew_box("a_ship", true)
	assert_eq(a.marine_count, 5)
	_dice.queue([4, 1])  # column 7-8 at 4: 1 box; crew loss 1 = sailor
	mf.resolve(shots, PHASE)
	assert_eq(_marine_events()[0].data["boxes"], 7)
	assert_eq(_marine_events()[0].data["crew"], 1, "7 boxes hit on 4; 5 boxes would not")


func test_combat_not_skipped_for_a_marine_shot_alone() -> void:
	# Spec §3.1: combat is skipped only when there is neither gunfire nor marine fire to declare.
	b.hex_position = Vector2i(2, 0)
	b.facing = 0  # b's stern alongside a's bow: no broadside bears either way
	# The chasers bear on each other, so every sailor section is put on a task: no gun bears.
	a.plotted_sections = [0, 1, 2, 3] as Array[int]
	b.plotted_sections = [0, 1, 2, 3] as Array[int]
	assert_false(GameState.gunnery_calculator.any_eligible_shot(), "no gun bears (every section busy)")
	var pc: TurnPhaseController = GameState.phase_controller
	pc.current_phase = TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
	pc.on_playback_completed()
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE, "marine fire keeps the declare step")
	_dice.queue([1, 2, 6])  # AI already submitted; a: marine d6 1, crew loss d6 2; b: marine d6 6
	assert_eq(pc.player_submit_fire_orders(0, [], [_order()]), "")
	var events := _marine_events()
	assert_eq(events.size(), 2, "both ships' marines fire")
	assert_eq(events[0].ship_id, "a_ship", "firers in ascending ship_id (spec §3.3)")


func test_submission_refuses_bad_marine_orders() -> void:
	var pc: TurnPhaseController = GameState.phase_controller
	pc.current_phase = TurnPhaseController.GamePhase.COMBAT_RESOLUTION
	pc.combat_step = TurnPhaseController.CombatStep.DECLARE
	b.hex_position = Vector2i(-1, 3)
	assert_string_contains(pc.player_submit_fire_orders(0, [], [_order()]), "adjacent")
	assert_ne(pc.player_submit_fire_orders(0, [], ["nope"]), "")


func test_marine_fire_rolls_after_all_gunfire() -> void:
	# Spec §3.3: marine fire dice come after all the gunfire dice; MARINE_FIRE follows FIRE in the log.
	var pc: TurnPhaseController = GameState.phase_controller
	var sixes: Array = []
	sixes.resize(300)
	sixes.fill(6)
	_dice.queue(sixes)
	pc.current_phase = TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
	pc.on_playback_completed()
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE)
	var gun := {"ship_id": "a_ship", "side": 1, "target_id": "b_ship", "aim": "low", "ammo": "round"}
	assert_eq(pc.player_submit_fire_orders(0, [gun], [_order()]), "")
	var last_fire := -1
	var first_marine := -1
	for i in GameState.turn_log.events.size():
		var ev: PhaseEvents.PhaseEvent = GameState.turn_log.events[i]
		if ev.type == PhaseEvents.Type.FIRE:
			last_fire = i
		elif ev.type == PhaseEvents.Type.MARINE_FIRE and first_marine < 0:
			first_marine = i
	assert_gt(first_marine, last_fire, "marine fire is logged after every broadside")
	assert_eq(_marine_events().filter(func(e): return e.ship_id == "a_ship")[0].data["boxes"], 2,
		"a's marines fire with the boxes they had before the broadsides (7.G.5)")


# --- AI (spec §3.6) ---

func test_ai_fires_marines_at_the_best_modified_die() -> void:
	# b (AI) has two adjacent enemies; fouled to c gives -1, so c is the better target.
	var c := _make_ship("c_ship", 0, Vector2i(-2, 1), 0)  # c alongside b's bow
	b.fouled_with = "c_ship"
	c.fouled_with = "b_ship"
	b.marine_count = 11
	var orders := GameState.stub_ai.choose_marine_orders()
	assert_eq(orders.size(), 1)
	assert_eq(orders[0]["ship_id"], "b_ship")
	assert_eq(orders[0]["target_id"], "c_ship")


func test_ai_ties_go_to_the_lower_ship_id() -> void:
	var c := _make_ship("c_ship", 0, Vector2i(-2, 1), 0)
	assert_eq(mf.preview("b_ship", "c_ship")["can_fire"], true, "fixture: c is adjacent to b")
	var orders := GameState.stub_ai.choose_marine_orders()
	assert_eq(orders[0]["target_id"], "a_ship")


func test_log_text() -> void:
	a.marine_count = 7
	a.fouled_with = "b_ship"
	_dice.queue([5, 2])
	mf.resolve(mf.prepare([_order()]), PHASE)
	var names := {"a_ship": "Vengeance", "b_ship": "Hermione"}
	assert_eq(_marine_events()[0].to_text(names),
		"Vengeance's marines fire on Hermione (7 boxes, column 7-8) — d6 5, alongside −1 → 4: 1 crew box")
	var damage: PhaseEvents.PhaseEvent = GameState.turn_log.of_type(PhaseEvents.Type.DAMAGE)[0]
	assert_eq(damage.to_text(names), "Hermione loses 1 sailor to musketry")
