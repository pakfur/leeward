extends GutTest
## Tests for FireController: fires and explosions (Close Action 1997, 8.E, 9.B.1c-d, Sequence of
## Play V.F; crew-tasks spec §3.5, §8 #20 and #27-44). Expected values come from the rules and
## charts: Unfouling table (d10 <= 2 / 3 / 4 for the 1st / 2nd / 3rd+ g-t, ± SK, +1 marines not
## available); 8.E.4 spread d10 <= 4 + SK (§9 Q1 reading); 8.E.5 growth every 5 g-t's; 8.E.8
## explosion 2d6 <= 2, -1 DRM each later g-t; 8.E.10 blast table (rb-p26-1.png); 8.E.11 debris
## d6 >= range, a 1 never; SK A -3 ... D 0 ... G +3. ScriptedDice: d10 = 0-9.
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const COMBAT := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT
const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
const TURN := 10

var fc: FireController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_turn := 0
var _old_phase: TurnPhaseController.GamePhase


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_turn = GameState.current_turn
	_old_phase = GameState.phase_controller.current_phase
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.current_turn = TURN
	GameState.phase_controller.current_phase = STATUS
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	fc = GameState.fire_controller


func after_each() -> void:
	assert_eq(_dice.remaining(), 0, "every scripted roll was used")
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.current_turn = _old_turn
	GameState.phase_controller.current_phase = _old_phase
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


## A ship facing east with its bow at (q, 0) (stern at (q - 1, 0)): ships at q = 0 and q = r + 1
## are r hexes apart. Plenty of boxes so a turn of fire empties no section.
func _ship(id: String, q: int, quality: String = "D", ship_class: int = 3, player: int = 0) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": ship_class,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [6, 6, 6, 6], "hull_hp": [6, 6, 6, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = Vector2i(q, 0)
	state.facing = 0
	state.sail_state = "FS"
	state.crew_quality = quality
	state.rigging_current_hp = [6, 6, 6, 6] as Array[int]
	state.hull_current_hp = [6, 6, 6, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


## A fire that broke out on g-t `created` in the Combat Phase (burning since then).
func _fire(ship: ShipState, created: int = TURN - 1) -> int:
	ship.fire_seq += 1
	ship.fire_list.append({"seq": ship.fire_seq, "created_turn": created, "started_turn": created, "cause": "crit"})
	return ship.fire_seq


## `section` fights fire `seq` this g-t, having fought it `done` g-t's already.
func _fight(ship: ShipState, seq: int, section: int, done: int = 0) -> void:
	_task(ship, "FF", [section], {"fire": seq}, done)


func _task(ship: ShipState, code: String, sections: Array, params: Dictionary = {}, done: int = 0) -> void:
	ship.task_seq += 1
	ship.crew_tasks.append(ShipState.crew_task_from({
		"seq": ship.task_seq, "code": code, "sections": sections, "done": done, "started_turn": TURN - done,
		"params": params, "forced": code == "RO", "marines_available": false, "ended": "",
	}))
	for s in sections:
		if not ship.plotted_sections.has(int(s)):
			ship.plotted_sections.append(int(s))


func _events(type: PhaseEvents.Type) -> Array[PhaseEvents.PhaseEvent]:
	return GameState.turn_log.of_type(type)


func _fire_damage(ship_id: String) -> Array:
	return _events(PhaseEvents.Type.DAMAGE).filter(
		func(e): return e.ship_id == ship_id and e.data.get("cause", "") == "fire")


func _boxes(arr: Array) -> int:
	var n := 0
	for v in arr:
		n += int(v)
	return n


# --- Catching fire, damage, the fear MC (8.E.7, 8.E.8) ---

func test_row29_combat_fire_unfought_burns_that_turn_one_mc_only() -> void:
	# Spec §8 #29: a fire breaks out in the Combat Phase with no FF plotted: no firefighting roll;
	# 1R and 1H that g-t (8.E.8 "including the g-t it catches fire"); one MC only (8.E.7), no
	# unfought MC since it did not exist at plotting (spec 0.2 Q11).
	var b := _ship("b", 0)
	GameState.phase_controller.current_phase = COMBAT
	var seq := fc.start_fire("b", FireController.CAUSE_CRIT, COMBAT)
	assert_eq(seq, 1)
	assert_eq(b.pending_morale_checks, 1)
	fc.resolve(STATUS)
	assert_eq(_events(PhaseEvents.Type.FIRE_FOUGHT).size(), 0, "no roll: nobody plotted FF")
	assert_eq(_boxes(b.rigging_current_hp), 23)
	assert_eq(_boxes(b.hull_current_hp), 23)
	assert_eq(_fire_damage("b").size(), 1)
	assert_eq(b.pending_morale_checks, 1, "the fear MC only")
	assert_eq(_events(PhaseEvents.Type.FIRE_UNFOUGHT).size(), 0)


func test_struck_ship_catching_fire_takes_no_mc() -> void:
	# Spec 0.3 #8: struck ships take no morale checks.
	var b := _ship("b", 0)
	b.status = ShipState.Status.STRUCK
	fc.start_fire("b", FireController.CAUSE_CRIT, COMBAT)
	assert_eq(b.fire_count(), 1)
	assert_eq(b.pending_morale_checks, 0)


func test_destroyed_ship_does_not_catch_fire() -> void:
	# Spec Q10: a wreck does not burn.
	var b := _ship("b", 0)
	b.status = ShipState.Status.DESTROYED
	assert_eq(fc.start_fire("b", FireController.CAUSE_DEBRIS, COMBAT), -1)
	assert_false(b.is_burning())


# --- Firefighting (8.E.3, Unfouling table) ---

func test_row30_ff_cq_b_first_turn_four_puts_it_out_no_damage() -> void:
	# Spec §8 #30: CQ B (SK -2), 1st g-t, d10 4: 4 - 2 = 2 <= 2: out, no damage that g-t.
	var b := _ship("b", 0, "B")
	var seq := _fire(b)
	_fight(b, seq, 1)
	_dice.queue([4])
	fc.resolve(STATUS)
	assert_false(b.is_burning())
	assert_eq(_fire_damage("b").size(), 0)
	var ev: Dictionary = _events(PhaseEvents.Type.FIRE_FOUGHT)[0].data
	assert_eq([ev["roll"], ev["modifier"], ev["needed"], ev["attempt"], ev["success"]], [4, -2, 2, 1, true])
	assert_true(b.tasks_with("FF").is_empty(), "the FF task ends with the fire")


func test_row30_ff_cq_b_first_turn_five_burns() -> void:
	# Spec §8 #30: d10 5: 3 > 2: still burning, 1R and 1H.
	var b := _ship("b", 0, "B")
	var seq := _fire(b)
	_fight(b, seq, 1)
	_dice.queue([5])
	fc.resolve(STATUS)
	assert_true(b.is_burning())
	assert_eq(_boxes(b.rigging_current_hp), 23)
	assert_eq(_boxes(b.hull_current_hp), 23)
	assert_eq(b.pending_morale_checks, 0, "a fought fire gives no unfought MC")


func test_row31_third_turn_same_section_marines_busy() -> void:
	# Spec §8 #31: FF 3rd g-t by the same section, CQ D, M on RR (marines not available +1),
	# d10 3: 3 + 1 = 4 <= 4: out.
	var b := _ship("b", 0, "D")
	var seq := _fire(b)
	_fight(b, seq, 0, 2)
	_task(b, "RR", [ShipState.MARINES])
	_dice.queue([3])
	fc.resolve(STATUS)
	assert_false(b.is_burning())
	var ev: Dictionary = _events(PhaseEvents.Type.FIRE_FOUGHT)[0].data
	assert_eq([ev["modifier"], ev["needed"], ev["attempt"]], [1, 4, 3])


func test_marines_fighting_the_fire_themselves_are_not_available() -> void:
	# Spec 0.2 Q5: the +1 applies when the marine section is itself the one fighting the fire.
	# CQ D, M on FF 1st g-t, d10 2: 2 + 1 = 3 > 2: still burning.
	var b := _ship("b", 0, "D")
	var seq := _fire(b)
	_fight(b, seq, ShipState.MARINES)
	_dice.queue([2])
	fc.resolve(STATUS)
	assert_true(b.is_burning())
	assert_eq(_events(PhaseEvents.Type.FIRE_FOUGHT)[0].data["modifier"], 1)


func test_wiped_out_marines_are_not_unavailable() -> void:
	# §9 Q5: a ship whose marines are all lost takes no +1. CQ D, d10 2: 2 <= 2: out.
	var b := _ship("b", 0, "D")
	b.marine_count = 0
	var seq := _fire(b)
	_fight(b, seq, 0)
	_dice.queue([2])
	fc.resolve(STATUS)
	assert_false(b.is_burning())


func test_column_counts_only_turns_the_section_fought() -> void:
	# Spec 0.2 Q5: after a roll the task's g-t count rises (advance_tasks); fire watch time does not.
	var b := _ship("b", 0, "D")
	var seq := _fire(b)
	_fight(b, seq, 0)
	_dice.queue([9])
	fc.resolve(STATUS)
	GameState.crew_task_controller.advance_tasks(STATUS)
	assert_eq(int(b.fire_task(seq)["done"]), 1, "fought once: the 2nd column next g-t")


func test_row32_a_new_section_starts_in_column_one() -> void:
	# Spec §8 #32: S1 fought fire 1 for one g-t; the plot now puts S3 on it. S1's task ends
	# (4.A.3) and S3 rolls in the "1" column: CQ D, d10 3 > 2: still burning (S1's column 2 would
	# have put it out).
	var b := _ship("b", 0, "D")
	b.crew_auto = false
	var seq := _fire(b)
	_fight(b, seq, 0, 1)
	b.plotted_sections.clear()
	b.plotted_actions["crew_assignments"] = {2: {"code": "FF", "params": {"fire": seq}}}
	GameState.crew_task_controller.begin_turn_tasks(MOVE)
	assert_eq(b.fire_task(seq)["sections"], [2])
	_dice.queue([3])
	fc.resolve(STATUS)
	assert_true(b.is_burning())
	var ev: Dictionary = _events(PhaseEvents.Type.FIRE_FOUGHT)[0].data
	assert_eq([ev["attempt"], ev["needed"]], [1, 2])


func test_row33_fire_watch_rolls_the_same_turn() -> void:
	# Spec §8 #33, 8.E.2 HINT: S1 on fire watch; a fire breaks out in combat; CQ D, d10 2: rolled
	# this g-t in the "1" column: out, no damage.
	var b := _ship("b", 0, "D")
	_task(b, "FF", [0], {"fire": -1, "section": 0})
	var seq := fc.start_fire("b", FireController.CAUSE_CRIT, COMBAT)
	assert_eq(int(b.fire_task(seq)["sections"][0]), 0, "the watch is attached at once")
	_dice.queue([2])
	fc.resolve(STATUS)
	assert_false(b.is_burning())
	assert_eq(_fire_damage("b").size(), 0)
	assert_eq(_events(PhaseEvents.Type.FIRE_FOUGHT)[0].data["attempt"], 1)


# --- Growth (8.E.5), unfought fires (8.E.6) ---

func test_row34_growth_every_five_turns() -> void:
	# Spec §8 #34, 8.E.5 example: a fire from g-t 7, never put out. In step 3 of g-t 11 a second
	# fire breaks out (with an MC); it does no damage in g-t 11 and burns from g-t 12.
	var b := _ship("b", 0, "D")
	var first := _fire(b, 7)
	GameState.current_turn = 11
	fc.resolve(STATUS)
	assert_eq(b.fire_count(), 2)
	var second := b.fire_seqs()[1]
	assert_eq(b.fire_by_seq(second)["created_turn"], 11)
	assert_eq(b.fire_by_seq(second)["started_turn"], 12)
	assert_eq(_fire_damage("b")[0].data["hull"], 1, "only the first fire did damage in g-t 11")
	assert_true(b.morale_triggers_used.has("fire_%d" % second), "the new fire's MC")
	# g-t 12: both fires burn (FF2 is needed from this g-t's plot on).
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.current_turn = 12
	fc.resolve(STATUS)
	assert_eq(_fire_damage("b")[0].data["hull"], 2, "two fires: 2H and 2R")
	assert_eq(b.fire_count(), 2, "no growth at g-t 12")
	assert_eq(first, 1)


func test_row34_third_fire_from_the_first_at_turn_sixteen() -> void:
	# 8.E.5: "each existing fire generates another fire every five g-t's": at g-t 16 the first
	# (from g-t 7, age 10) and the second (burning from g-t 12, age 5) both grow.
	var b := _ship("b", 0, "D")
	_fire(b, 7)
	b.fire_seq += 1
	b.fire_list.append({"seq": b.fire_seq, "created_turn": 11, "started_turn": 12, "cause": "growth"})
	GameState.current_turn = 16
	fc.resolve(STATUS)
	assert_eq(b.fire_count(), 4)
	var froms: Array = _events(PhaseEvents.Type.FIRE_STARTED).map(func(e): return e.data["from_fire"])
	assert_eq(froms, [1, 2])


func test_row35_two_fires_one_section_one_unfought_mc() -> void:
	# Spec §8 #35, 8.E.6, 9.B.1d: two fires, only one fought: one MC this g-t for the other.
	var b := _ship("b", 0, "D")
	var one := _fire(b)
	var two := _fire(b)
	_fight(b, one, 0)
	_dice.queue([9])
	fc.resolve(STATUS)
	var unfought := _events(PhaseEvents.Type.FIRE_UNFOUGHT)
	assert_eq(unfought.size(), 1)
	assert_eq(unfought[0].data["fire"], two)
	assert_eq(b.pending_morale_checks, 1)
	assert_true(b.morale_triggers_used.has("unfought_%d_%d" % [two, TURN]))


func test_row44_section_in_ro_is_not_called_to_the_fire() -> void:
	# Spec §8 #44, 8.E.2 exception: S3 in RO and nobody else: S3 keeps RO, the fire is unfought, MC.
	var b := _ship("b", 0, "D")
	b.crew_count = [0, 0, 3, 0] as Array[int]
	b.marine_count = 0
	_task(b, "RO", [2], {"reason": "crew_disorganized"})
	var seq := _fire(b)
	var plan := GameState.crew_task_controller.current_plan("b", true)
	assert_eq(plan["assignments"].get(2, {}).get("code", ""), "RO")
	assert_true(b.fire_task(seq).is_empty())
	fc.resolve(STATUS)
	assert_eq(_events(PhaseEvents.Type.FIRE_UNFOUGHT).size(), 1)
	assert_eq(b.pending_morale_checks, 1)


# --- Spread (8.E.4) ---

func test_row36_spread_to_fouled_ship_cq_d() -> void:
	# Spec §8 #36: fouled to a burning ship, CQ D (SK 0): d10 4 <= 4: catches fire, with an MC.
	var b := _ship("b", 0)
	var a := _ship("a", 3)
	a.fouled_with = "b"
	b.fouled_with = "a"
	_fire(b)
	_dice.queue([4])
	fc.resolve(STATUS)
	assert_eq(a.fire_count(), 1)
	assert_eq(a.fire_list[0]["cause"], "spread")
	assert_eq(a.fire_list[0]["started_turn"], TURN + 1, "made in the Fire sub-phase: burns from next g-t")
	assert_true(a.morale_triggers_used.has("fire_1"))
	assert_eq(_fire_damage("a").size(), 0)


func test_row36_no_spread_on_five() -> void:
	var b := _ship("b", 0)
	var a := _ship("a", 3)
	a.fouled_with = "b"
	b.fouled_with = "a"
	_fire(b)
	_dice.queue([5])
	fc.resolve(STATUS)
	assert_false(a.is_burning())
	assert_false(_events(PhaseEvents.Type.FIRE_SPREAD)[0].data["spreads"])


func test_spread_better_crew_resists() -> void:
	# §9 Q1 reading: d10 <= 4 + SK; CQ A (SK -3): 1 or less. d10 2: no spread.
	var b := _ship("b", 0)
	var a := _ship("a", 3, "A")
	a.fouled_with = "b"
	b.fouled_with = "a"
	_fire(b)
	_dice.queue([2])
	fc.resolve(STATUS)
	assert_false(a.is_burning())
	assert_eq(_events(PhaseEvents.Type.FIRE_SPREAD)[0].data["needed"], 1)


# --- Explosions (8.E.8) ---

func test_row37_last_hull_box_strikes_then_explodes_next_turn() -> void:
	# Spec §8 #37, 8.E.8 example: the fire takes the last hull box: the ship strikes and rolls
	# 2d6 = 3 > 2: no explosion. Next g-t 2d6 = 3 <= 3: explodes.
	var b := _ship("b", 0)
	b.hull_current_hp = [0, 0, 0, 1] as Array[int]
	_fire(b)
	_dice.queue([1, 2])
	fc.resolve(STATUS)
	assert_true(b.is_struck())
	assert_false(b.is_destroyed())
	assert_eq(b.explosion_checks, 1)
	var check: Dictionary = _events(PhaseEvents.Type.EXPLOSION_CHECK)[0].data
	assert_eq([check["roll"], check["needed"], check["explodes"]], [3, 2, false])
	GameState.current_turn = TURN + 1
	_dice.queue([1, 2])
	fc.resolve(STATUS)
	assert_true(b.is_destroyed())
	assert_false(b.is_burning(), "a wreck does not burn")
	assert_eq(_events(PhaseEvents.Type.DESTROYED)[0].data["reason"], "explosion")


func test_row42_struck_ship_fights_as_cq_g() -> void:
	# Spec §8 #42, 8.E.3, 9.C.4: struck, CQ had been B, FF 1st g-t, d10 0: 0 + 3 = 3 > 2: burning.
	var b := _ship("b", 0, "B")
	b.status = ShipState.Status.STRUCK
	var seq := _fire(b)
	_fight(b, seq, 0)
	_dice.queue([0])
	fc.resolve(STATUS)
	assert_true(b.is_burning())
	assert_eq(_events(PhaseEvents.Type.FIRE_FOUGHT)[0].data["modifier"], 3)


func test_row43_struck_ship_with_no_crew_burns_and_rolls_to_explode() -> void:
	# Spec §8 #43, 9.C.3: no crew: no roll, no MC; it burns; explosion checks once hull is 0.
	var b := _ship("b", 0)
	b.status = ShipState.Status.STRUCK
	b.crew_count = [0, 0, 0, 0] as Array[int]
	b.marine_count = 0
	b.hull_current_hp = [0, 0, 0, 1] as Array[int]
	_fire(b)
	assert_true(GameState.crew_task_controller.current_plan("b")["assignments"].is_empty())
	_dice.queue([6, 6])
	fc.resolve(STATUS)
	assert_eq(_events(PhaseEvents.Type.FIRE_FOUGHT).size(), 0)
	assert_eq(b.pending_morale_checks, 0)
	assert_eq(_boxes(b.hull_current_hp), 0)
	assert_eq(_events(PhaseEvents.Type.EXPLOSION_CHECK).size(), 1)


func test_struck_ship_plan_keeps_only_firefighting() -> void:
	# Spec 0.3 #8: a struck ship fights fires with automatic allocation (rule A1) and nothing else.
	var b := _ship("b", 0, "B")
	b.crew_auto = false
	var seq := _fire(b)
	b.status = ShipState.Status.STRUCK
	b.plotted_actions["crew_assignments"] = {3: {"code": "SAIL", "params": {"target": "MS"}}}
	var plan := GameState.crew_task_controller.current_plan("b")
	assert_eq(plan["assignments"], {0: {"code": "FF", "params": {"fire": seq}}})


func test_strike_ends_every_task_but_firefighting() -> void:
	# §3.8: a ship that strikes ends every task but FF.
	var b := _ship("b", 0)
	var seq := _fire(b)
	_fight(b, seq, 0)
	CrewFixtures.give_sail_change(b, "MS", [3])
	GameState.damage_controller.strike("b", "morale", COMBAT)
	assert_false(b.has_sail_change())
	assert_false(b.fire_task(seq).is_empty())


# --- Blast and debris (8.E.9-11) ---

func test_row38_blast_class_two_range_one() -> void:
	# Spec §8 #38, 8.E.10: class 2 explodes; target at range 1 at FS, d6 4: FGN 35 + 4 = 39,
	# firing high, FS: 5r-h-c. No critical-hit roll; the crew box on "All Other Causes" (d6 4-6:
	# marine). Then debris: d6 1 never sets a fire.
	var b := _ship("b", 0, "D", 2)
	var a := _ship("a", 2)
	_dice.queue([4, 5, 1])  # blast d6, crew-loss d6, debris d6
	fc.explode("b", STATUS)
	assert_true(b.is_destroyed())
	var blast: Dictionary = _events(PhaseEvents.Type.BLAST)[0].data
	assert_eq([blast["range"], blast["mgn"], blast["d6"], blast["fgn"]], [1, 35, 4, 39])
	assert_eq(_boxes(a.rigging_current_hp), 19)
	assert_eq(_boxes(a.hull_current_hp), 23)
	assert_eq(a.marine_count, 1, "crew d6 5 on All Other Causes: a marine")
	assert_eq(_events(PhaseEvents.Type.CRITICAL_ROLL).size(), 0, "no crit roll for a blast (0.2 Q8)")
	assert_false(a.is_burning())
	assert_eq(_events(PhaseEvents.Type.DAMAGE)[0].data["cause"], "blast")


func test_row39_blast_class_three_range_two_and_three() -> void:
	# Spec §8 #39: class 3, target at range 2, d6 1: FGN 15 + 1 = 16 high FS "r/h" (d6 1-3: r).
	# A ship at range 3 takes no blast. Debris: range 2 d6 1 (never), range 3 d6 2 (< 3).
	var b := _ship("b", 0, "D", 3)
	var a := _ship("a", 3)
	var c := _ship("c", 4)
	_dice.queue([1, 2, 1, 2])  # a: blast d6, slash d6; debris a, c
	fc.explode("b", STATUS)
	var blasts := _events(PhaseEvents.Type.BLAST)
	assert_eq(blasts.size(), 1)
	assert_eq(blasts[0].target_id, "a")
	assert_eq(blasts[0].data["fgn"], 16)
	assert_eq(_boxes(a.rigging_current_hp), 23)
	assert_eq(_boxes(c.rigging_current_hp), 24)
	assert_false(a.is_burning())
	assert_false(c.is_burning())


func test_row40_debris_range_five() -> void:
	# Spec §8 #40, 8.E.11 example: "A ship 5 hexes away is on fire if it rolls a 5 or 6": a at
	# range 5 rolls 5: afire; c at range 5 (west) rolls 4: no fire. Ships in id order: a, c.
	var b := _ship("b", 0, "D", 3)
	var a := _ship("a", 6)
	var c := _ship("c", -6)
	assert_eq(GameState.fire_geometry.range_between(b.occupied_hexes(), a.occupied_hexes()), 5)
	assert_eq(GameState.fire_geometry.range_between(b.occupied_hexes(), c.occupied_hexes()), 5)
	_dice.queue([5, 4])
	fc.explode("b", STATUS)
	assert_eq(a.fire_count(), 1)
	assert_eq(a.fire_list[0]["cause"], "debris")
	assert_false(c.is_burning(), "a roll below the range sets no fire")
	assert_eq(a.fire_list[0]["started_turn"], TURN + 1, "debris in the Fire sub-phase burns from next g-t")


func test_row40_debris_range_one_roll_of_one_never() -> void:
	# 8.E.11: a DR of 1 never causes a fire, even adjacent. Class 4 blast at range 1: 25 + 1 = 26
	# high FS: 2r.
	var b := _ship("b", 0, "D", 4)
	var a := _ship("a", 2)
	_dice.queue([1, 1])  # blast d6, debris d6
	fc.explode("b", STATUS)
	assert_false(a.is_burning())
	assert_eq(_boxes(a.rigging_current_hp), 22)


func test_row40_debris_fouled_ship_always_catches_fire() -> void:
	# 8.E.11: a ship fouled to the exploding ship catches fire with no roll (here at range 3).
	var b := _ship("b", 0, "D", 3)
	var a := _ship("a", 4)
	a.fouled_with = "b"
	b.fouled_with = "a"
	fc.explode("b", STATUS)
	assert_eq(a.fire_count(), 1)
	assert_eq(a.fouled_with, "", "freed from the wreck")
	assert_true(_events(PhaseEvents.Type.DEBRIS)[0].data["attached"])


func test_row41_hull_twelve_explosion_blast_and_debris_wreck_stays() -> void:
	# Spec §8 #41, hull #12: "explodes ... after doing all appropriate blast damage, etc.". Class 2
	# CQ D, 2d10 = 0 < 2. a at range 1, FS: blast d6 4 -> 39 high FS 5r-h-c, crew d6 2 (sailor);
	# debris d6 6 >= 1: a catches fire in the Combat Phase (burns this g-t).
	var b := _ship("b", 0, "D", 2, 1)
	var a := _ship("a", 2)
	GameState.current_turn = TURN
	_dice.queue([1, 6, 6, 0, 0, 4, 2, 6])  # CH d6, 2d6 12, 2d10 0, blast d6, crew d6, debris d6
	var crits: CriticalHitController = GameState.critical_hit_controller
	crits.hold()
	crits.check_gunfire_crit({"source_id": "a", "target_id": "b", "aim": "low", "ammo": "round",
		"rake": "", "engaged_side": ShipState.STARBOARD, "dismasted_at_start": false, "fgn": 40, "d6": 6}, COMBAT)
	crits.release(COMBAT)
	assert_true(b.is_destroyed())
	assert_eq(GameState.get_ship("b"), b, "the wreck stays on the map")
	assert_eq(_boxes(a.rigging_current_hp), 19)
	assert_eq(a.crew_count[0], 2, "crew d6 2: a sailor")
	assert_eq(a.fire_count(), 1)
	assert_eq(a.fire_list[0]["started_turn"], TURN, "a Combat Phase fire burns this g-t")


# --- Automatic crew with a real fire (spec §8 #20) ---

func test_row20_automatic_with_a_real_fire() -> void:
	# Spec §8 #20: fire aboard, S1 on RR in progress, MA-0 turn plotted: fire -> S2 (lowest free
	# sailor); S1 keeps RR; T: S4, S3 only (M held back: fire aboard); nothing left for a third.
	var b := _ship("b", 0, "B")
	var seq := _fire(b)
	_task(b, "RR", [0], {}, 2)
	b.plotted_sections.clear()
	var ctx := CrewRules.context(GameState, b)
	assert_eq(ctx["fires"], [seq], "context lists the fires burning")
	ctx["ma0_turn_plotted"] = true
	var a: Dictionary = CrewAuto.allocate(b, {"sail_target": ""}, ctx)["assignments"]
	assert_eq(a[1], {"code": "FF", "params": {"fire": seq}})
	assert_eq(a[0]["code"], "RR")
	assert_eq(a[3]["code"], "T")
	assert_eq(a[2]["code"], "T")
	assert_false(a.has(ShipState.MARINES), "marines held back: fire aboard")
	var stations := CrewRules.stations(b, {"assignments": a, "orders": {}}, ctx)
	assert_eq(stations[0]["id"], "fire_%d" % seq, "fire stations come first")
	assert_eq(stations[0]["occupants"], [1])
	assert_eq(stations[0]["fire"]["age"], 2, "burning since g-t 9: its 2nd g-t")
	var watch: Array = stations.filter(func(s): return s["id"] == CrewRules.STATION_FIRE_WATCH)
	assert_true(watch[0]["menu_only"], "fire watch only in the menu while fires burn")


func test_dev_command_starts_a_fire() -> void:
	var b := _ship("b", 0)
	assert_eq(GameState.dev_commands.start_fire("b"), "")
	assert_eq(b.fire_count(), 1)
	assert_ne(GameState.dev_commands.start_fire("nope"), "")
