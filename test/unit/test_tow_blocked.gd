extends GutTest
## Blocked tows (Close Action 12.A.10-11; towing spec §5, register §4): a follow into a third ship's
## hex, off the map or onto land undoes the tower's step (a tow rollback, TOW_HELD, no padding); the
## tower's old stern is held for her tow (12.A.10); a towed ship hit by a third ship holds her tower;
## the tow rams a tower stopped by a collision (12.A.11) and the tow is kept; a towed ship that grounds
## in the tower's wake parts the tow.
## Wind from the east (direction 0), speed 3. Tower t: bow (5, 5), facing 3, stern (6, 5), MS, class 3.
## Towed w: bow (7, 5), facing 3, stern (8, 5), class 2, dismasted.

const MOVE_PHASE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION

var sc: ShipStateController
var pc: TurnPhaseController
var _dice: ScriptedDice
var _logs: Array = []
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _old_turn: int
var _old_phase: TurnPhaseController.GamePhase
var _old_prompt: Array[int]


func before_all() -> void:
	DataManager.load_ship_definitions()
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_turning_table()
	DataManager.load_speed_change_table()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	_old_turn = GameState.current_turn
	_old_phase = pc.current_phase
	_old_prompt = pc.bear_off_prompt_player_ids
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}}
	GameState.current_turn = 5
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	sc = GameState.ship_controller
	_logs = []
	pc.resolution_log_ready.connect(_on_log)
	pc.bear_off_prompt_player_ids = [] as Array[int]


func after_each() -> void:
	assert_eq(_dice.remaining(), 0, "every scripted die was used")
	pc.resolution_log_ready.disconnect(_on_log)
	pc.bear_off_prompt_player_ids = _old_prompt
	pc.current_phase = _old_phase
	pc._pending_resolution_log = null
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


@warning_ignore("shadowed_global_identifier")
func _on_log(log: MovementTypes.ResolutionLog) -> void:
	_logs.append(log)


func _ship(id: String, hex: Vector2i, facing: int = 3, ship_class: int = 3, side: int = 0,
		speed: int = 0) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({
		"ship_id": id, "side": side, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": ship_class,
		"maneuverability": "C", "speed_type": "F/F", "draft": 16,
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	s.side = side
	s.hex_position = hex
	s.facing = facing
	s.speed = speed
	s.sail_state = "MS"
	s.crew_quality = "C"
	s.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	s.hull_current_hp = [5, 5, 5, 6] as Array[int]
	s.crew_count = [3, 3, 3, 3] as Array[int]
	s.marine_count = 2
	s.crew_auto = false
	GameState.ships[id] = s
	GameState.ships_by_side[side].append(id)
	return s


## The tower t (speed `speed`) and her dismasted tow w, in tow.
func _pair(speed: int = 2) -> Array[ShipState]:
	var t := _ship("t", Vector2i(5, 5), 3, 3, 0, speed)
	var w := _ship("w", Vector2i(7, 5), 3, 2)
	w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	w.sail_state = "NS"
	assert_true(sc.begin_tow("t", "w"))
	return [t, w] as Array[ShipState]


func _plot(id: String, steps: Array) -> void:
	var cmds: Array = []
	for s in steps:
		cmds.append({"hex": {"q": s[0].x, "r": s[0].y}, "facing": s[1]})
	assert_true(sc.set_plotted_movement(id, cmds))


func _resolver(seed_value: int = 12345) -> MovementResolver:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return MovementResolver.new(GameState, rng)


func _events(result: MovementTypes.ShipResolutionResult, event_type: int) -> Array:
	return result.events.filter(func(ev) -> bool: return ev.event_type == event_type)


func _follows(result: MovementTypes.ShipResolutionResult) -> Array:
	return _events(result, MovementTypes.ResolutionEventType.TOW_FOLLOW)


func _moves(result: MovementTypes.ShipResolutionResult) -> Array:
	return _events(result, MovementTypes.ResolutionEventType.MOVE)


func _tow_held(result: MovementTypes.ShipResolutionResult) -> Array:
	return _events(result, MovementTypes.ResolutionEventType.TOW_HELD)


func _scenario_with(terrain: Dictionary) -> void:
	# A new dictionary, so TerrainMap.of builds the board again.
	GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}, "terrain": terrain}


## t turns to starboard: the follow pose would be bow (6, 5) facing 2, stern (7, 4).
func _starboard_turn() -> void:
	_plot("t", [[Vector2i(5, 5), 4]])


func test_follow_blocked_by_third_ship_undoes_tower_step() -> void:
	var ships := _pair(1)
	_starboard_turn()
	ships.append(_ship("c", Vector2i(7, 4), 1))  # stopped; holds (7, 4) and (7, 3)
	var log := _resolver().run(ships, GameState.environment)
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	var w: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(t.final_hex, Vector2i(5, 5))
	assert_eq(t.final_facing, 3, "the turn is undone")
	assert_eq(_moves(t).size(), 0)
	var held := _tow_held(t)
	assert_eq(held.size(), 1)
	if held.size() == 1:
		assert_true(held[0].detail.begins_with("blocked by c"), held[0].detail)
		assert_eq(held[0].impulse, 0)
		assert_false(held[0].success)
	assert_eq(t.blocked_by, "c")
	assert_eq(_follows(w).size(), 0)
	assert_eq(w.final_hex, Vector2i(7, 5))
	assert_eq(w.final_facing, 3)
	assert_eq(MovementResolver.stop_cause(t), {"cause": "tow", "other": "c"})


func test_follow_blocked_by_land() -> void:
	_scenario_with({"land": [[7, 4]]})
	var ships := _pair(1)
	_starboard_turn()
	var log := _resolver().run(ships, GameState.environment)
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	var held := _tow_held(t)
	assert_eq(held.size(), 1)
	if held.size() == 1:
		assert_eq(held[0].detail, "blocked")
	assert_eq(t.blocked_by, "")
	assert_eq(t.final_facing, 3)
	assert_eq(_follows(log.get_result("w")).size(), 0)
	assert_eq(MovementResolver.stop_cause(t), {"cause": "tow", "other": ""})


func test_follow_blocked_off_map() -> void:
	# The board's rows are -15..14: the follow stern (7, -16) is off it.
	var t := _ship("t", Vector2i(5, -15), 3, 3, 0, 1)
	var w := _ship("w", Vector2i(7, -15), 3, 2)
	w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	w.sail_state = "NS"
	assert_true(sc.begin_tow("t", "w"))
	_plot("t", [[Vector2i(5, -15), 4]])
	var log := _resolver().run([t, w] as Array[ShipState], GameState.environment)
	var tr: MovementTypes.ShipResolutionResult = log.get_result("t")
	var held := _tow_held(tr)
	assert_eq(held.size(), 1)
	if held.size() == 1:
		assert_eq(held[0].detail, "blocked")
	assert_eq(tr.final_hex, Vector2i(5, -15))
	assert_eq(tr.final_facing, 3, "the tower keeps her facing")
	assert_eq(log.get_result("w").final_hex, Vector2i(7, -15))


func test_follow_ignores_own_pair() -> void:
	var ships := _pair()
	_plot("t", [[Vector2i(4, 5), 3], [Vector2i(3, 5), 3]])
	var log := _resolver().run(ships, GameState.environment)
	assert_eq(_tow_held(log.get_result("t")).size(), 0)
	assert_eq(_follows(log.get_result("w")).size(), 2)


func test_old_stern_reserved_for_tow() -> void:
	# 12.A.10: c sails into (6, 5), the hex t's stern leaves; the towed bow takes it first.
	var ships := _pair(1)
	_plot("t", [[Vector2i(4, 5), 3]])
	var c := _ship("c", Vector2i(6, 4), 1, 3, 1, 1)
	_plot("c", [[Vector2i(6, 5), 1]])
	ships.append(c)
	var log := _resolver().run(ships, GameState.environment, {"c": {"choice": "collide", "segment": 0}})
	var cr: MovementTypes.ShipResolutionResult = log.get_result("c")
	assert_eq(cr.final_hex, Vector2i(6, 4))
	assert_false(_moves(cr).any(func(ev) -> bool: return ev.to_hex == Vector2i(6, 5)), "c never enters (6, 5)")
	assert_eq(cr.collided_with, "t")
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	assert_eq(t.final_hex, Vector2i(5, 5))
	var held := _tow_held(t)
	assert_eq(held.size(), 1)
	if held.size() == 1:
		assert_true(held[0].detail.begins_with("tow_collision"), held[0].detail)
	assert_eq(log.get_result("w").final_hex, Vector2i(7, 5))


func test_towed_rammed_holds_tower() -> void:
	var ships := _pair(1)
	_plot("t", [[Vector2i(4, 5), 3]])
	var c := _ship("c", Vector2i(9, 5), 3, 3, 1, 1)
	_plot("c", [[Vector2i(8, 5), 3]])  # into w's stern
	ships.append(c)
	var log := _resolver().run(ships, GameState.environment, {"c": {"choice": "collide", "segment": 0}})
	assert_eq(log.get_result("c").collided_with, "w")
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	var held := _tow_held(t)
	assert_eq(held.size(), 1)
	if held.size() == 1:
		assert_true(held[0].detail.begins_with("tow_collision"), held[0].detail)
	assert_eq(t.final_hex, Vector2i(5, 5))
	assert_eq(MovementResolver.stop_cause(t).get("cause", ""), "tow")


func test_tower_collision_rams_tow() -> void:
	var ships := _pair(1)
	ships.append(_ship("x", Vector2i(4, 5), 1))  # stopped; holds (4, 5) and (4, 4)
	_plot("t", [[Vector2i(4, 5), 3]])
	var resolver := _resolver()
	var log := resolver.run(ships, GameState.environment, {"t": {"choice": "collide", "segment": 0}})
	assert_eq(log.get_result("t").collided_with, "x")
	var w: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(w.collided_with, "t")
	var collisions := _events(w, MovementTypes.ResolutionEventType.COLLISION)
	assert_eq(collisions.size(), 1)
	if collisions.size() == 1:
		assert_true(collisions[0].detail.contains("tow"), collisions[0].detail)
	var tower_hits := _events(log.get_result("t"), MovementTypes.ResolutionEventType.COLLISION).filter(
		func(ev) -> bool: return ev.detail == "hit by w, tow")
	assert_eq(tower_hits.size(), 1, "the tower is told she was hit by her tow")
	assert_eq(_tow_held(log.get_result("t")).size(), 0, "a ram is no rollback")
	resolver.apply_results(log, ships)
	var ws: ShipState = ships[1]
	assert_eq(ws.towed_by, "t", "the tow is kept (12.A.11)")
	assert_eq(ws.speed, 0)
	assert_true(ws.collision_this_turn)
	var logged: Array = GameState.turn_log.of_type(PhaseEvents.Type.COLLISION).filter(
		func(ev) -> bool: return ev.ship_id == "w")
	assert_eq(logged.size(), 1)
	if logged.size() == 1:
		assert_eq(logged[0].data.get("tow"), true)
		assert_eq(logged[0].target_id, "t")
		assert_eq(logged[0].to_text({"w": "w", "t": "t"}), "w runs into her tower t")


## One collision per ship per segment: c runs into w while t runs into x; w, already held, does not
## also ram t (no second COLLISION, no rigging-loss roll for her).
func test_held_tow_does_not_ram_tower() -> void:
	var ships := _pair(1)
	var w: ShipState = ships[1]
	w.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	w.sail_state = "MS"  # a ram would cost her d6 + 1 rigging
	ships.append(_ship("x", Vector2i(4, 5), 1))
	_plot("t", [[Vector2i(4, 5), 3]])
	var c := _ship("c", Vector2i(9, 5), 3, 3, 1, 1)
	_plot("c", [[Vector2i(8, 5), 3]])  # into w's stern
	ships.append(c)
	var log := _resolver().run(ships, GameState.environment, {
		"c": {"choice": "collide", "segment": 0}, "t": {"choice": "collide", "segment": 0}})
	assert_eq(log.get_result("t").collided_with, "x")
	var wr: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(wr.collided_with, "c")
	var collisions := _events(wr, MovementTypes.ResolutionEventType.COLLISION)
	assert_eq(collisions.size(), 1, "one collision for the tow")
	if collisions.size() == 1:
		assert_eq(collisions[0].detail, "hit by c")
	assert_eq(_events(wr, MovementTypes.ResolutionEventType.COLLISION_RIGGING_LOSS).size(), 0)
	assert_eq(wr.rigging_damage, 0, "no rigging-loss roll for the tow")
	assert_false(_events(log.get_result("t"), MovementTypes.ResolutionEventType.COLLISION).any(
		func(ev) -> bool: return ev.detail.contains("tow")), "the tower is not hit by her tow")


## t wins a stern contest with y for (5, 6), but her tow cannot follow (land at (7, 4)): the tow
## rollback undoes the winning turn, and the contest dice stay in the final log.
func test_tow_rollback_keeps_contest_dice() -> void:
	_scenario_with({"land": [[7, 4]]})
	var ships := _pair(1)
	ships[0].crew_quality = "A"  # +6 against y's G: t always wins
	_starboard_turn()  # new stern (5, 6)
	var y := _ship("y", Vector2i(4, 6), 4, 3, 1, 1)  # stern (4, 7)
	y.crew_quality = "G"
	_plot("y", [[Vector2i(4, 6), 3]])  # port turn: the stern swings into (5, 6)
	ships.append(y)
	var log := _resolver().run(ships, GameState.environment)
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	var yr: MovementTypes.ShipResolutionResult = log.get_result("y")
	assert_eq(_tow_held(t).size(), 1)
	assert_eq(t.final_facing, 3, "the won turn is undone")
	assert_eq(yr.final_facing, 3, "y turns into the hex in the replay")
	var t_rolls := _events(t, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL)
	var y_rolls := _events(yr, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL)
	assert_eq(t_rolls.size(), 1, "t's contest die is kept")
	assert_eq(y_rolls.size(), 1, "y's contest die is kept")
	if t_rolls.size() == 1:
		assert_true(t_rolls[0].success)
		assert_eq(t_rolls[0].impulse, 0)


func test_towed_grounds_and_parts() -> void:
	_scenario_with({"shallow": [{"name": "A", "base": 0, "hexes": [[6, 5]]}]})
	var ships := _pair()
	_plot("t", [[Vector2i(4, 5), 3], [Vector2i(3, 5), 3]])
	var resolver := _resolver()
	var log := resolver.run(ships, GameState.environment)
	var w: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(_events(w, MovementTypes.ResolutionEventType.AGROUND).size(), 1)
	assert_eq(_follows(w).size(), 0)
	assert_eq(w.final_hex, Vector2i(7, 5))
	assert_true(w.aground)
	assert_eq(w.aground_data.get("terrain"), "shallow")
	assert_eq(w.aground_data.get("hex"), {"q": 6, "r": 5})
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	assert_eq(t.final_hex, Vector2i(3, 5), "the tower sails on free")
	assert_eq(_tow_held(t).size(), 0)
	resolver.apply_results(log, ships)
	assert_true(ships[1].is_aground())
	assert_false(ships[0].is_towing())
	var cuts: Array = GameState.turn_log.of_type(PhaseEvents.Type.TOW_CUT)
	assert_eq(cuts.size(), 1)
	if cuts.size() == 1:
		assert_eq(cuts[0].data.get("cause"), "aground")


## Three tows, each held back by land on a different segment (a starboard turn first, then k steps
## ahead: the turns fall at 1/3, 1/2 and 1 of the g-t), so each pass finds one more rollback.
func test_rollback_terminates() -> void:
	var land: Array = []
	var ships: Array[ShipState] = []
	var turn_segments: Array = []
	for k in range(3):
		var r: int = -6 + 6 * k
		var tid := "t%d" % k
		var wid := "w%d" % k
		var t := _ship(tid, Vector2i(5, r), 3, 3, 0, k + 1)
		var w := _ship(wid, Vector2i(7, r), 3, 2)
		w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
		w.sail_state = "NS"
		assert_true(sc.begin_tow(tid, wid))
		var steps: Array = [[Vector2i(5, r), 4]]  # the follow stern would be (7, r - 1)
		for n in range(k):
			steps.append([Vector2i(5, r - 1 - n), 4])
		_plot(tid, steps)
		land.append([7, r - 1])
		ships.append(t)
		ships.append(w)
	_scenario_with({"land": land})
	var log := _resolver().run(ships, GameState.environment)
	assert_push_error(0, "no 'did not settle' error")
	for k in range(3):
		var t: MovementTypes.ShipResolutionResult = log.get_result("t%d" % k)
		var held := _tow_held(t)
		assert_eq(held.size(), 1, "t%d held" % k)
		if held.size() == 1:
			turn_segments.append(held[0].impulse)
		assert_eq(_moves(t).size(), 0, "t%d makes no step" % k)
		assert_eq(t.final_hex, Vector2i(5, -6 + 6 * k))
		assert_eq(t.final_facing, 3)
		assert_eq(log.get_result("w%d" % k).final_hex, Vector2i(7, -6 + 6 * k))
	assert_eq(turn_segments, [3, 1, 0], "one rollback per segment, found pass by pass")


func test_stopped_short_tow_line() -> void:
	var ships := _pair(1)
	_starboard_turn()
	ships.append(_ship("c", Vector2i(7, 4), 1))
	var resolver := _resolver()
	var log := resolver.run(ships, GameState.environment)
	resolver.log_outcomes(log, ships, GameState.turn_log)
	var stops: Array = GameState.turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT).filter(
		func(ev) -> bool: return ev.ship_id == "t")
	assert_eq(stops.size(), 1)
	if stops.size() == 1:
		assert_eq(stops[0].data.get("cause"), "tow")
		var text: String = stops[0].to_text({"t": "t", "c": "c", "w": "w"})
		assert_true(text.contains("held back by her tow"), text)
		assert_eq(text, "t stops short: held back by her tow (c in the way)")


