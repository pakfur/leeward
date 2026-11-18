extends GutTest
## The anchoring step after drift (Close Action 13.C-F, SoP V.A-B; anchoring spec §4):
## AnchorController.resolve_anchoring. V.A rides each anchored ship to her anchor (swing, settle,
## wind shift, veer out; a blocked forced move holds), V.B drops and cuts. Anchored groups never
## drift (8.A.6). Wind from the east (direction 0), speed 3: downwind is west (-1, 0), a bow anchor's
## proper facing is 0, a stern anchor's 3.
## Dice order: drift first (its own resolver); then per anchored ship, leeward first: the swing d6
## (opposite, no direction yet), then the fouling d10 (a ship in the way) or the depth d6 (shallows).

const PHASE := TurnPhaseController.GamePhase.DRIFT_CALCULATION

var anchors: AnchorController
var sc: ShipStateController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _old_turn: int


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	_old_turn = GameState.current_turn
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}, "anchoring": true}
	GameState.current_turn = 2
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	anchors = GameState.anchor_controller
	sc = GameState.ship_controller


func after_each() -> void:
	assert_eq(_dice.remaining(), 0, "every scripted die was used")
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, facing: int, side: int = 0) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F", "draft": 16,
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	state.side = side
	state.hex_position = hex
	state.facing = facing
	state.sail_state = "FS"
	state.moved_this_turn = true
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


## An anchored ship: bow at `bow` facing `facing`, anchor at `anchor_hex` (anchored on turn 1).
func _anchored(id: String, bow: Vector2i, facing: int, anchor_hex: Vector2i, cable: int,
		end: String = "bow", springs: bool = false) -> ShipState:
	var ship := _make_ship(id, bow, facing)
	sc.drop_anchor(id, {"hex": anchor_hex, "end": end, "springs": springs, "cable": cable,
		"veered": 0, "swing_dir": 0, "wind_dir": 0, "turn": 1})
	return ship


func _task(ship: ShipState, code: String) -> void:
	sc.add_task(ship.ship_id, {"code": code, "sections": [ShipState.MARINES],
		"started_turn": GameState.current_turn})


func _moves() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.ANCHOR_MOVE)


func _anchor_events() -> Array:
	var out: Array = []
	for t in [PhaseEvents.Type.ANCHOR_MOVE, PhaseEvents.Type.ANCHORED, PhaseEvents.Type.CABLE_CUT]:
		out.append_array(GameState.turn_log.of_type(t))
	return out


func _next_turn() -> void:
	GameState.current_turn += 1
	GameState.turn_log = PhaseEvents.PhaseLog.new()


func _hex(h: Vector2i) -> Dictionary:
	return {"q": h.x, "r": h.y}


# --- no anchors --------------------------------------------------------------------

func test_no_anchor_no_change() -> void:
	var a := _make_ship("a", Vector2i(0, 0), 0)
	var b := _make_ship("b", Vector2i(0, 5), 0)
	a.moved_this_turn = false
	b.moved_this_turn = false
	a.sail_state = "MS"
	b.sail_state = "MS"
	_dice.queue([0, 0])  # neither drifts (MS at WS 3 needs 4, class +1)
	GameState.drift_resolver.resolve(PHASE)
	anchors.resolve_anchoring(PHASE)
	assert_eq(_anchor_events().size(), 0)
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.DRIFT).size(), 2)


func test_leeward_first_orders_downwind() -> void:
	var a := _make_ship("a", Vector2i(3, 0), 0)
	var b := _make_ship("b", Vector2i(-3, 0), 0)
	var c := _make_ship("c", Vector2i(0, 0), 0)
	var order: Array[ShipState] = GameState.drift_resolver.leeward_first([a, b, c] as Array[ShipState], 3)
	assert_eq(order.map(func(s): return s.ship_id), ["b", "c", "a"])


# --- V.A: swing and settle ------------------------------------------------------

func test_settle_and_swing_after_anchoring() -> void:
	var ship := _anchored("a", Vector2i(0, 0), 1, Vector2i(0, 0), 0)
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.facing, 0)
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	assert_eq(ship.stern_hex(), Vector2i(-2, 0))
	assert_eq(int(ship.anchor["cable"]), 1)
	var moves := _moves()
	assert_eq(moves.size(), 1)
	assert_eq(moves[0].data["causes"], ["swing", "settle"])
	assert_eq(moves[0].data["roll"], -1)
	assert_eq(moves[0].data["from"], _hex(Vector2i(0, 0)))
	assert_eq(moves[0].data["to"], _hex(Vector2i(-1, 0)))
	assert_eq(moves[0].data["from_facing"], 1)
	assert_eq(moves[0].data["to_facing"], 0)
	assert_eq(moves[0].data["blocked"], "")
	assert_eq(moves[0].data["fouled"], null)
	assert_eq(moves[0].to_text({"a": "Ajax"}),
		"Ajax swings to her anchor and drops back on her cable to (-1, 0)")


func test_settled_ship_does_not_drift_again() -> void:
	var ship := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	anchors.resolve_anchoring(PHASE)
	assert_eq(_moves().size(), 0)
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	assert_eq(ship.facing, 0)


func test_opposite_swing_rolls_d6() -> void:
	var ship := _anchored("a", Vector2i(-1, 0), 3, Vector2i(0, 0), 1)
	_dice.queue([2])
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.facing, 2)
	assert_eq(int(ship.anchor["swing_dir"]), -1)
	assert_eq(_moves()[0].data["roll"], 2)
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	_next_turn()
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.facing, 1)
	assert_eq(_moves()[0].data["roll"], -1)
	_next_turn()
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.facing, 0)
	assert_eq(int(ship.anchor["swing_dir"]), 0)


func test_opposite_swing_high_roll_turns_starboard() -> void:
	var ship := _anchored("a", Vector2i(-1, 0), 3, Vector2i(0, 0), 1)
	_dice.queue([5])
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.facing, 4)
	assert_eq(int(ship.anchor["swing_dir"]), 1)


func test_stern_anchor_settles() -> void:
	var ship := _anchored("a", Vector2i(0, 0), 3, Vector2i(1, 0), 0, "stern")
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	assert_eq(ship.stern_hex(), Vector2i(0, 0))
	assert_eq(ship.facing, 3)
	assert_eq(_moves()[0].data["causes"], ["settle"])


func test_anchored_this_turn_waits() -> void:
	var ship := _anchored("a", Vector2i(0, 0), 1, Vector2i(0, 0), 0)
	sc.update_anchor("a", {"turn": 2})
	anchors.resolve_anchoring(PHASE)
	assert_eq(_moves().size(), 0)
	assert_eq(ship.hex_position, Vector2i(0, 0))


# --- V.A: wind shifts -----------------------------------------------------------

func test_wind_shift_oblique() -> void:
	var ship := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	GameState.environment.wind_direction = 1
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.facing, 1)
	assert_eq(ship.hex_position, Vector2i(0, -1))
	assert_true(_moves()[0].data["causes"].has("wind"))
	assert_eq(int(ship.anchor["wind_dir"]), 1)


func test_springs_keep_wind_facing() -> void:
	var ship := _anchored("a", Vector2i(-1, 0), 5, Vector2i(0, 0), 1, "bow", true)
	GameState.environment.wind_direction = 1
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.facing, 0)
	assert_eq(ship.hex_position, Vector2i(0, -1))
	assert_eq(_moves()[0].data["causes"], ["wind"])
	assert_eq(int(ship.anchor["wind_dir"]), 1)


# --- V.A: veering out -----------------------------------------------------------

func test_veer_out_moves_one_hex() -> void:
	var ship := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_task(ship, "VO")
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.hex_position, Vector2i(-2, 0))
	assert_eq(int(ship.anchor["cable"]), 2)
	assert_eq(int(ship.anchor["veered"]), 1)
	assert_eq(_moves()[0].data["causes"], ["veer_out"])
	assert_eq(_moves()[0].data["cable"], 2)


func test_wind_zero_nothing_moves() -> void:
	GameState.environment.wind_speed = 0
	var ship := _anchored("a", Vector2i(0, 0), 1, Vector2i(0, 0), 0)
	var b := _make_ship("b", Vector2i(0, 5), 0)
	b.anchor_ready = "bow"
	b.moved_this_turn = false
	_task(b, "A")
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.hex_position, Vector2i(0, 0))
	assert_eq(int(ship.anchor["cable"]), 0)
	assert_eq(_moves().size(), 0)
	assert_true(b.is_anchored())


# --- V.A: blocked forced moves --------------------------------------------------

func test_blocked_by_ship_rolls_fouling_and_holds() -> void:
	var ship := _anchored("a", Vector2i(0, 0), 0, Vector2i(0, 0), 0)
	var blocker := _make_ship("b", Vector2i(-2, 0), 1, 1)
	_dice.queue([9])
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.hex_position, Vector2i(0, 0))
	assert_eq(ship.facing, 0)
	assert_eq(ship.fouled_with, "b")
	assert_eq(blocker.fouled_with, "a")
	var move = _moves()[0]
	assert_eq(move.data["blocked"], "ship")
	assert_eq(move.data["fouled"], true)
	assert_eq(move.target_id, "b")
	assert_eq(int(ship.anchor["cable"]), 1)
	assert_eq(move.to_text({"a": "Ajax", "b": "Brunswick"}),
		"Ajax cannot ride to her anchor: Brunswick is in the way (fouled)")


func test_blocked_by_ship_not_fouled_then_settles() -> void:
	var ship := _anchored("a", Vector2i(0, 0), 0, Vector2i(0, 0), 0)
	var blocker := _make_ship("b", Vector2i(-2, 0), 1, 1)
	_dice.queue([0])
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.fouled_with, "")
	assert_eq(_moves()[0].data["fouled"], false)
	assert_eq(ship.hex_position, Vector2i(0, 0))
	assert_eq(int(ship.anchor["cable"]), 1)
	_next_turn()
	sc.set_ship_position("b", Vector2i(-2, 10))
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	assert_eq(_moves()[0].data["causes"], ["settle"])
	assert_eq(blocker.hex_position, Vector2i(-2, 10))


func test_veer_out_lost_when_blocked() -> void:
	var ship := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_make_ship("b", Vector2i(-3, 0), 1, 1)
	_task(ship, "VO")
	_dice.queue([0])  # the fouling roll fails
	anchors.resolve_anchoring(PHASE)
	assert_eq(int(ship.anchor["cable"]), 1)
	assert_eq(int(ship.anchor["veered"]), 0)
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	assert_eq(_moves()[0].data["blocked"], "ship")


func test_forced_move_onto_land_grounds() -> void:
	GameState.active_scenario["terrain"] = {"land": [[-2, 0]]}
	var ship := _anchored("a", Vector2i(0, 0), 0, Vector2i(0, 0), 0)
	anchors.resolve_anchoring(PHASE)
	assert_true(ship.is_aground())
	assert_eq(ship.hex_position, Vector2i(0, 0))
	assert_eq(ship.rigging_current_hp, [5, 5, 6, 6] as Array[int])
	assert_eq(_moves()[0].data["blocked"], "land")
	var aground := GameState.turn_log.of_type(PhaseEvents.Type.AGROUND)
	assert_eq(aground.size(), 1)
	assert_eq(aground[0].data["cause"], "anchor")
	assert_eq(aground[0].data["terrain"], "land")
	assert_eq(aground[0].data["hex"], _hex(Vector2i(-2, 0)))
	# An aground ship never rides to her anchor again.
	_next_turn()
	anchors.resolve_anchoring(PHASE)
	assert_eq(_moves().size(), 0)


## A stern anchor settling: the bow (0, 0) facing 3 moves on to (-1, 0), a hex she did not hold.
## (A bow anchor settling moves her bow on to her own old stern hex, which rolls no depth.)
func test_forced_move_into_too_shallow_water_grounds() -> void:
	GameState.active_scenario["terrain"] = {"shallow": [
		{"name": "bar", "base": 10, "hexes": [[-1, 0]]}]}
	var ship := _anchored("a", Vector2i(0, 0), 3, Vector2i(1, 0), 0, "stern")
	_dice.queue([3])  # 10 + 3 = 13 <= draft 16
	anchors.resolve_anchoring(PHASE)
	assert_true(ship.is_aground())
	assert_eq(ship.hex_position, Vector2i(0, 0))
	assert_eq(_moves()[0].data["blocked"], "land")
	var aground := GameState.turn_log.of_type(PhaseEvents.Type.AGROUND)
	assert_eq(aground.size(), 1)
	assert_eq(aground[0].data["terrain"], "shallow")
	assert_eq(aground[0].data["depth"], 13)
	assert_eq(aground[0].data["hex"], _hex(Vector2i(-1, 0)))


func test_forced_move_into_deep_enough_shallows_moves() -> void:
	GameState.active_scenario["terrain"] = {"shallow": [
		{"name": "bar", "base": 14, "hexes": [[-1, 0]]}]}
	var ship := _anchored("a", Vector2i(0, 0), 3, Vector2i(1, 0), 0, "stern")
	_dice.queue([3])  # 17 > 16
	anchors.resolve_anchoring(PHASE)
	assert_false(ship.is_aground())
	assert_eq(ship.hex_position, Vector2i(-1, 0))


func test_bow_settling_onto_own_shoal_hex_rolls_no_depth() -> void:
	GameState.active_scenario["terrain"] = {"shallow": [
		{"name": "bar", "base": 10, "hexes": [[-1, 0]]}]}
	var ship := _anchored("a", Vector2i(0, 0), 0, Vector2i(0, 0), 0)
	anchors.resolve_anchoring(PHASE)
	assert_false(ship.is_aground())
	assert_eq(ship.hex_position, Vector2i(-1, 0))


func test_forced_move_off_map_holds() -> void:
	for west in ["", "none"]:
		GameState.ships.clear()
		GameState.ships_by_side = {0: [], 1: []}
		GameState.turn_log = PhaseEvents.PhaseLog.new()
		GameState.active_scenario = {"map_bounds": {"width": 10, "height": 10}}
		if west != "":
			GameState.active_scenario["terrain"] = {"edges": {"W": west}}
		var ship := _anchored("a", Vector2i(-5, 0), 0, Vector2i(-5, 0), 0)
		anchors.resolve_anchoring(PHASE)
		assert_eq(_moves()[0].data["blocked"], "edge", west)
		assert_true(ship.is_on_map(), west)
		assert_eq(ship.status, ShipState.Status.ACTIVE, west)
		assert_eq(ship.hex_position, Vector2i(-5, 0), west)


func test_linked_anchored_ship_holds() -> void:
	var ship := _anchored("a", Vector2i(0, 0), 0, Vector2i(0, 0), 0)
	_make_ship("b", Vector2i(0, -1), 0, 1)
	sc.add_grapple("a", "b")
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.hex_position, Vector2i(0, 0))
	assert_eq(_moves()[0].data["blocked"], "linked")
	assert_eq(_moves()[0].data["fouled"], null)
	assert_eq(int(ship.anchor["cable"]), 1)


# --- V.B: drop and cut ----------------------------------------------------------

func test_drop_after_drift() -> void:
	var ship := _make_ship("a", Vector2i(0, 0), 0)
	ship.sail_state = "MS"
	ship.speed = 0
	ship.moved_this_turn = false
	ship.anchor_ready = "bow"
	_task(ship, "A")
	_dice.queue([9])  # 9 + 1 >= 4: drifts
	GameState.drift_resolver.resolve(PHASE)
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	assert_true(ship.is_anchored())
	assert_eq(ship.anchor["hex"], ship.hex_position)
	assert_eq(int(ship.anchor["cable"]), 0)
	assert_eq(ship.anchor["end"], "bow")
	assert_eq(int(ship.anchor["turn"]), 2)
	assert_eq(ship.anchorings_used, 1)
	assert_eq(ship.anchor_ready, "")
	var types: Array = GameState.turn_log.events.map(func(e): return e.type)
	assert_eq(types, [PhaseEvents.Type.DRIFT, PhaseEvents.Type.ANCHORED])
	var ev = GameState.turn_log.of_type(PhaseEvents.Type.ANCHORED)[0]
	assert_eq(ev.data, {"end": "bow", "springs": false, "hex": _hex(Vector2i(-1, 0))})
	assert_eq(ev.to_text({"a": "Ajax"}), "Ajax anchors by the bow at (-1, 0)")


func test_drop_stern_anchor_with_springs() -> void:
	var ship := _make_ship("a", Vector2i(0, 0), 0)
	ship.anchor_ready = "stern"
	ship.springs_ready = true
	_task(ship, "A")
	anchors.resolve_anchoring(PHASE)
	assert_eq(ship.anchor["hex"], Vector2i(-1, 0))
	assert_true(ship.has_springs())
	var ev = GameState.turn_log.of_type(PhaseEvents.Type.ANCHORED)[0]
	assert_eq(ev.to_text({"a": "Ajax"}), "Ajax anchors by the stern with springs at (-1, 0)")


func test_anchored_group_does_not_drift() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	var b := _make_ship("b", Vector2i(-1, 1), 0, 1)
	b.moved_this_turn = false
	sc.set_fouled_with("a", "b")
	sc.set_fouled_with("b", "a")
	GameState.drift_resolver.resolve(PHASE)
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.DRIFT).size(), 0)
	assert_eq(a.hex_position, Vector2i(-1, 0))
	assert_eq(b.hex_position, Vector2i(-1, 1))


func test_cut_removes_anchor() -> void:
	var ship := _anchored("a", Vector2i(0, 0), 0, Vector2i(0, 0), 0)
	_task(ship, "AX")
	anchors.resolve_anchoring(PHASE)
	assert_false(ship.is_anchored())
	assert_eq(ship.cable_cut_turn, 2)
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	var types: Array = GameState.turn_log.events.map(func(e): return e.type)
	assert_eq(types, [PhaseEvents.Type.ANCHOR_MOVE, PhaseEvents.Type.CABLE_CUT])
	var ev = GameState.turn_log.of_type(PhaseEvents.Type.CABLE_CUT)[0]
	assert_eq(ev.data, {"hex": _hex(Vector2i(0, 0))})
	assert_eq(ev.to_text({"a": "Ajax"}), "Ajax cuts her cable")


func test_drift_phase_runs_anchoring() -> void:
	var pc: TurnPhaseController = GameState.phase_controller
	var old_phase := pc.current_phase
	var ship := _anchored("a", Vector2i(0, 0), 1, Vector2i(0, 0), 0)
	pc._enter_drift_calculation_phase()
	assert_eq(ship.hex_position, Vector2i(-1, 0))
	assert_eq(ship.facing, 0)
	assert_eq(int(ship.anchor["cable"]), 1)
	pc.current_phase = old_phase


func test_client_refuses() -> void:
	var ship := _anchored("a", Vector2i(0, 0), 1, Vector2i(0, 0), 0)
	anchors.is_server = false
	anchors.resolve_anchoring(PHASE)
	anchors.is_server = true
	assert_push_error("Cannot resolve anchoring on client")
	assert_eq(ship.hex_position, Vector2i(0, 0))
