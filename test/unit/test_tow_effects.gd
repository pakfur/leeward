extends GutTest
## The tow's effects outside movement (towing spec §6-8): a tower and her tow drift as one group
## (8.A.6), a dismasted ship raked in tow takes no MC while her tower is rigged (9.B.1b), hull
## critical #6 rolls a d6 and parts the tow on a 1 (12.A.6), and a tower escaping takes her tow
## with her: an own ship escapes in tow, a prize is carried off and stays a capture.

const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
const COMBAT := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const DRIFT := TurnPhaseController.GamePhase.DRIFT_CALCULATION
const END := TurnPhaseController.GamePhase.END_TURN
const STARBOARD := 1
const WIND_FROM_E := 0  # downwind is west, (-1, 0)
const WIND_SPEED := 3

var sc: ShipStateController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_scenario: Dictionary
var _old_env: EnvironmentState
var _old_turn: int
var _old_log: PhaseEvents.PhaseLog
var _old_crits: CriticalHitController


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	sc = GameState.ship_controller
	_old_dice = GameState.dice
	_old_scenario = GameState.active_scenario
	_old_env = GameState.environment
	_old_turn = GameState.current_turn
	_old_log = GameState.turn_log
	_old_crits = GameState.critical_hit_controller
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.active_scenario = {"map_bounds": {"width": 100, "height": 100}, "escape": {"0": {}, "1": {}}}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = WIND_FROM_E
	env.wind_speed = WIND_SPEED
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 5
	GameState.turn_log = GameState.new_turn_log(5)


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
	GameState.current_turn = _old_turn
	GameState.turn_log = _old_log
	GameState.critical_hit_controller = _old_crits
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, side: int, facing: int = 3) -> ShipState:
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
	state.initialize_from_scenario({"position": {"q": hex.x, "r": hex.y}, "facing": facing}, ship_def)
	state.sail_state = "PS"
	state.crew_quality = "C"
	state.starting_crew_quality = "C"
	state.morale_rating = 4
	state.crew_auto = false
	state.mp_used_this_turn = 0
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


## t (bow (5, 5), facing W) towing w (bow (7, 5), the hex astern of t's stern), both side 0.
func _tow_pair() -> Array[ShipState]:
	var t := _make_ship("t", Vector2i(5, 5), 0)
	var w := _make_ship("w", Vector2i(7, 5), 0)
	w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	w.sail_state = "NS"
	assert_true(sc.begin_tow("t", "w"))
	return [t, w]


func _events(type: PhaseEvents.Type) -> Array[PhaseEvents.PhaseEvent]:
	return GameState.turn_log.of_type(type)


func _names() -> Dictionary:
	return {"t": "Ajax", "w": "Brunswick"}


# ---------- drift (8.A.6) ----------

func test_tow_drifts_as_group() -> void:
	var pair := _tow_pair()
	var t: ShipState = pair[0]
	var w: ShipState = pair[1]
	t.speed = 0
	t.moved_this_turn = false
	_dice.queue([9])
	GameState.drift_resolver.resolve(DRIFT)
	assert_eq(_dice.remaining(), 0, "one d10 for the group")
	assert_eq(t.hex_position, Vector2i(4, 5), "the tower drifts one hex west")
	assert_eq(w.hex_position, Vector2i(6, 5), "her tow with her")
	assert_eq(t.facing, 3)
	assert_eq(w.facing, 3)
	assert_eq(w.hex_position, t.stern_hex() + Vector2i(1, 0), "the tow still astern of her tower")
	assert_eq(_events(PhaseEvents.Type.DRIFT).size(), 2, "one DRIFT line per member")


func test_moving_tow_does_not_drift() -> void:
	var pair := _tow_pair()
	for s: ShipState in pair:
		s.moved_this_turn = true
		s.speed = 2
	GameState.drift_resolver.resolve(DRIFT)
	assert_eq(_dice.remaining(), 0)
	assert_eq(pair[0].hex_position, Vector2i(5, 5))
	assert_eq(pair[1].hex_position, Vector2i(7, 5))
	assert_eq(_events(PhaseEvents.Type.DRIFT).size(), 0)


func test_tow_drift_keyed_on_the_tower() -> void:
	# The tower moved; her tow was held (moved_this_turn false): the pair does not drift.
	var pair := _tow_pair()
	pair[0].moved_this_turn = true
	pair[0].speed = 1
	pair[1].moved_this_turn = false
	GameState.drift_resolver.resolve(DRIFT)
	assert_eq(_dice.remaining(), 0, "no die: the tower moved")
	assert_eq(_events(PhaseEvents.Type.DRIFT).size(), 0)


func test_tow_held_by_blocked_tower() -> void:
	# A ship in the hex west of the tower's bow blocks her; her tow is held at the other end.
	var pair := _tow_pair()
	pair[0].moved_this_turn = false
	var x := _make_ship("x", Vector2i(3, 5), 1)
	x.moved_this_turn = true
	_dice.queue([9, 9])  # the drift, then the fouling d10 (no foul)
	GameState.drift_resolver.resolve(DRIFT)
	assert_eq(pair[0].hex_position, Vector2i(5, 5))
	assert_eq(pair[1].hex_position, Vector2i(7, 5))
	var held: Array = _events(PhaseEvents.Type.DRIFT).filter(func(e): return e.ship_id == "w")
	assert_eq(held.size(), 1)
	assert_eq(held[0].data["blocked"], "partner")
	assert_eq(held[0].target_id, "t")
	assert_eq(held[0].data["link"], "tow")
	assert_string_contains(held[0].to_text(_names()), "held back by Ajax, at the other end of her tow")


# ---------- 9.B.1b ----------

## a (side 1) at (0, 0) facing E stern-rakes b (bow (0, 2) facing SE) with its bow battery, as in
## test_gunnery_resolver. b is dismasted; with `towed` she is in tow of t (far off, side 0).
func _rake_dismasted(towed: bool, tower_dismasted: bool = false) -> int:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	GameState.turn_log = GameState.new_turn_log(5)
	_make_ship("a", Vector2i.ZERO, 1, 0)
	var b := _make_ship("b", Vector2i(0, 2), 0, 1)
	b.sail_state = "NS"
	b.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	b.crew_quality = "D"
	if towed:
		var t := _make_ship("t", Vector2i(30, 30), 0)
		if tower_dismasted:
			t.rigging_current_hp = [0, 0, 0, 0] as Array[int]
			t.sail_state = "NS"
		assert_true(sc.begin_tow("t", "b"))
	var values: Array = []
	values.resize(200)
	values.fill(6)
	_dice = ScriptedDice.new()
	_dice.queue(values)
	GameState.dice = _dice
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "a"
	order.side = STARBOARD
	order.target_id = "b"
	order.ammo = "round"
	order.aim = "low"
	order.battery = "bow"
	var orders: Array[GunneryTypes.FireOrder] = [order]
	GunneryResolver.new(GameState).resolve(orders, COMBAT)
	var fire: Array = _events(PhaseEvents.Type.FIRE)
	assert_eq(fire.size(), 1)
	assert_eq(fire[0].data["rake"], "stern", "the setup rakes")
	var trigger := "raked_dismasted_t%d" % GameState.phase_controller.current_turn
	return _events(PhaseEvents.Type.MORALE_NOTED).filter(
			func(e): return e.ship_id == "b" and e.data.get("trigger") == trigger).size()


func test_raked_dismasted_tow_no_mc() -> void:
	assert_eq(_rake_dismasted(true), 0, "in tow of a rigged ship: no MC (9.B.1b)")
	assert_eq(_rake_dismasted(true, true), 1, "her tower dismasted too: the MC")
	assert_eq(_rake_dismasted(false), 1, "not in tow: the MC")


# ---------- hull critical #6 (12.A.6) ----------

## Hull #6 on `target_id` from a gunfire crit: CH d6 1, 2d6 3+3 (aim low: the hull column), then
## `extra` (the tow d6).
func _hull_six(target_id: String, extra: Array) -> void:
	var crits := CriticalHitController.new(GameState)
	GameState.critical_hit_controller = crits
	_dice.queue([1, 3, 3])
	_dice.queue(extra)
	var ctx := {"source_id": "x", "target_id": target_id, "aim": "low", "ammo": "round", "rake": "",
		"engaged_side": STARBOARD, "dismasted_at_start": false, "fgn": 40, "d6": 6}
	crits.hold()
	assert_true(crits.check_gunfire_crit(ctx, COMBAT))
	crits.release(COMBAT)
	var hits := _events(PhaseEvents.Type.CRITICAL_HIT)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].data["result_id"], "hull_structural_damage")


func test_hull_6_cuts_on_one() -> void:
	var pair := _tow_pair()
	_make_ship("x", Vector2i(5, 8), 1)
	_hull_six("t", [1])
	assert_eq(_dice.remaining(), 0)
	var hit: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.CRITICAL_HIT)[0]
	assert_eq(hit.data["tow_roll"], 1)
	assert_eq(pair[0].hull_current_hp, [4, 5, 5, 6] as Array[int], "the 1H first")
	var cuts := _events(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	assert_eq(cuts[0].data["cause"], "structural")
	assert_eq(cuts[0].data["by"], "t")
	assert_false(pair[0].is_towing())
	assert_false(pair[1].is_towed())


func test_hull_6_stands_on_two() -> void:
	var pair := _tow_pair()
	_make_ship("x", Vector2i(5, 8), 1)
	_hull_six("w", [2])  # the towed ship rolls too
	assert_eq(_dice.remaining(), 0)
	assert_eq(_events(PhaseEvents.Type.CRITICAL_HIT)[0].data["tow_roll"], 2)
	assert_eq(_events(PhaseEvents.Type.TOW_CUT).size(), 0)
	assert_true(pair[0].is_towing(), "the tow stands")


func test_hull_6_untowed_no_die() -> void:
	_make_ship("u", Vector2i(5, 5), 0)
	_make_ship("x", Vector2i(5, 8), 1)
	_hull_six("u", [])
	assert_eq(_dice.remaining(), 0, "no tow: no extra die")
	assert_false(_events(PhaseEvents.Type.CRITICAL_HIT)[0].data.has("tow_roll"))


# ---------- escape ----------

func test_tower_escape_takes_tow() -> void:
	var pair := _tow_pair()
	GameState.map_controller.escape("t", {"how": "edge", "edge": "W"}, MOVE)
	for s: ShipState in pair:
		assert_true(s.is_escaped(), "%s escaped" % s.ship_id)
		assert_false(s.is_on_map(), "%s off the map" % s.ship_id)
		assert_eq(s.tow_partner(), "", "no tow left")
	var escaped := _events(PhaseEvents.Type.ESCAPED)
	assert_eq(escaped.size(), 2)
	assert_eq(escaped[0].ship_id, "t")
	assert_eq(escaped[1].ship_id, "w")
	assert_eq(escaped[1].data["how"], "in_tow")
	assert_eq(escaped[1].data["tower"], "t")
	assert_eq(escaped[1].to_text(_names()), "Brunswick escapes in tow of Ajax")
	assert_eq(_events(PhaseEvents.Type.TOW_CUT).size(), 0, "no TOW_CUT")


func test_tower_carries_off_prize() -> void:
	# w is side 1's, taken by side 0 (t's side): a prize with a weak prize crew over a full crew below.
	var t := _make_ship("t", Vector2i(5, 5), 0)
	var w := _make_ship("w", Vector2i(7, 5), 1)
	w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	w.sail_state = "NS"
	w.status = ShipState.Status.CAPTURED
	assert_true(GameState.transfer_control("w", 0))
	assert_true(sc.begin_tow("t", "w"))
	var pair: Array[ShipState] = [t, w]
	w.crew_count = [1, 0, 0, 0] as Array[int]
	w.marine_count = 0
	w.prize = {"captor_id": "t", "prize_crew_aboard": true, "original_navy": "",
		"original_crew": {"crew_count": [3, 3, 3, 3], "marine_count": 2, "crew_quality": "C", "morale_rating": 4}}
	assert_eq(w.side, 0)
	assert_true(BoardingController.recapture_due(w), "on the map she would be retaken")
	GameState.map_controller.escape("t", {"how": "edge", "edge": "W"}, MOVE)
	assert_true(pair[0].is_escaped())
	assert_true(w.is_captured(), "she stays a capture")
	assert_false(w.is_on_map(), "carried off the map")
	assert_eq(w.tow_partner(), "")
	assert_true(GameState.victory_controller.is_lost(w), "lost to her owner")
	assert_false(BoardingController.recapture_due(w), "never retaken off the map")
	var escaped := _events(PhaseEvents.Type.ESCAPED)
	assert_eq(escaped.size(), 2)
	assert_eq(escaped[1].ship_id, "w")
	assert_eq(escaped[1].data, {"how": "in_tow", "tower": "t", "prize": true})
	assert_eq(escaped[1].to_text(_names()), "Ajax carries off the prize Brunswick")


func test_towed_not_escaping_alone() -> void:
	var pair := _tow_pair()
	var w: ShipState = pair[1]
	w.escape_declared = true
	_make_ship("e", Vector2i(60, 50), 1)  # far beyond 30 hexes
	GameState.map_controller.resolve_escapes(5, END)
	assert_false(w.is_escaped(), "a towed ship escapes only with her tower")
	assert_true(w.is_on_map())
	assert_eq(_events(PhaseEvents.Type.ESCAPED).size(), 0)


# ---------- the D.1c speed test ----------

func test_condition_speed_with_loss() -> void:
	# As test_escape: a side-1 frigate_38 running west at (-20, 0), a side-0 pursuer 25 hexes off
	# with two rigging sections (fighting sail only), slower than her at plain sail.
	var esc := _make_ship("esc", Vector2i(-20, 0), 1)
	var p := _make_ship("p", Vector2i(-19 + 25, 0), 0)
	p.rigging_current_hp = [0, 0, 6, 6] as Array[int]
	var own := MapRules.max_ma(esc, "R", WIND_SPEED)
	var theirs := MapRules.max_ma(p, "R", WIND_SPEED)
	assert_gt(own, theirs, "unladen she is faster")
	var pursuers: Array[ShipState] = [p]
	var how := MapRules.condition(esc, pursuers, WIND_FROM_E, WIND_SPEED)
	assert_eq(how.get("how", ""), "speed")
	assert_eq(MapRules.condition(esc, pursuers, WIND_FROM_E, WIND_SPEED, 0), how)
	assert_eq(MapRules.condition(esc, pursuers, WIND_FROM_E, WIND_SPEED, own - theirs + 1), {},
			"her tow's loss puts her below the pursuer")
	assert_eq(MapRules.condition(esc, pursuers, WIND_FROM_E, WIND_SPEED, 99), {}, "floored at 0")
