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


## ---------------------------------------------------------------------------- final wave

## t bears off e to starboard, but land at (7, 4) stops her tow following the turn: the tow rollback
## undoes the turn, and the bear-off roll stays in the final log (as a contest's rolls do).
func test_tow_rollback_keeps_bear_off_roll() -> void:
	var found := false
	for seed_value in range(1, 60):
		GameState.ships.clear()
		GameState.ships_by_side = {0: [], 1: []}
		GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}}
		var ships := _pair(1)
		_plot("t", [[Vector2i(4, 5), 3]])
		ships.append(_ship("e", Vector2i(4, 5), 1, 3, 1))  # stopped; holds (4, 5) and (4, 4)
		var decide := {"t": {"choice": "starboard", "segment": 0}}
		var free := _resolver(seed_value).run(ships, GameState.environment, decide)
		var free_rolls := _events(free.get_result("t"), MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
		if free_rolls.is_empty() or not free_rolls[0].success:
			continue
		found = true
		_scenario_with({"land": [[7, 4]]})
		var log := _resolver(seed_value).run(ships, GameState.environment, decide)
		var t: MovementTypes.ShipResolutionResult = log.get_result("t")
		assert_eq(_tow_held(t).size(), 1, "the tow holds the bear-off turn back")
		assert_eq(t.final_facing, 3, "the turn is undone")
		var rolls := _events(t, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
		assert_eq(rolls.size(), 1, "the bear-off roll is kept")
		if rolls.size() == 1:
			assert_true(rolls[0].success)
			assert_eq(rolls[0].roll, free_rolls[0].roll, "the same die")
			assert_eq(rolls[0].impulse, 0)
		assert_eq(MovementResolver.stop_cause(t).get("cause", ""), "tow")
		break
	assert_true(found, "some seed bears off")


## A tower held back by her tow and then run into by c stops for the collision (STOPPED_SHORT
## "collision"), not "tow".
func test_collision_beats_tow_cause() -> void:
	_scenario_with({"land": [[7, 4]]})
	var ships := _pair(1)
	_starboard_turn()
	var c := _ship("c", Vector2i(4, 5), 0, 3, 1, 1)  # stern (3, 5)
	_plot("c", [[Vector2i(5, 5), 0]])  # into t's bow
	ships.append(c)
	var resolver := _resolver()
	var log := resolver.run(ships, GameState.environment, {"c": {"choice": "collide", "segment": 0}})
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	assert_eq(_tow_held(t).size(), 1)
	assert_eq(t.collided_with, "c")
	assert_eq(MovementResolver.stop_cause(t), {"cause": "collision", "other": "c"})
	resolver.log_outcomes(log, ships, GameState.turn_log)
	var stops: Array = GameState.turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT).filter(
		func(ev) -> bool: return ev.ship_id == "t")
	assert_eq(stops.size(), 1)
	if stops.size() == 1:
		assert_eq(stops[0].data.get("cause"), "collision")
		assert_eq(stops[0].target_id, "c")


## log_outcomes reads the tow flag of a COLLISION from the event (12.A.11's ram detail), not from
## whom the ship collided with: a ram names the tower; a plain collision with the partner is no ram.
func test_collision_tow_flag_keyed_on_event() -> void:
	var pair := _pair(1)
	var resolver := _resolver()
	var log := MovementTypes.ResolutionLog.new(5)
	var wr := MovementTypes.ShipResolutionResult.new()
	wr.ship_id = "w"
	wr.collided_with = "c"  # what she was first marked with
	var ram := MovementTypes.ResolutionEvent.new("w", 0, MovementTypes.ResolutionEventType.COLLISION)
	ram.from_hex = Vector2i(7, 5)
	ram.facing = 3
	ram.detail = "collided with t, rigging_loss=0, tow"
	wr.events.append(ram)
	log.add_result(wr)
	var tr := MovementTypes.ShipResolutionResult.new()
	tr.ship_id = "t"
	tr.collided_with = "w"
	var plain := MovementTypes.ResolutionEvent.new("t", 0, MovementTypes.ResolutionEventType.COLLISION)
	plain.from_hex = Vector2i(5, 5)
	plain.facing = 3
	plain.detail = "collided with w"
	tr.events.append(plain)
	log.add_result(tr)
	resolver.log_outcomes(log, pair, GameState.turn_log)
	var by_ship := {}
	for ev in GameState.turn_log.of_type(PhaseEvents.Type.COLLISION):
		by_ship[ev.ship_id] = ev
	assert_eq(by_ship["w"].data.get("tow"), true)
	assert_eq(by_ship["w"].target_id, "t", "the ram names her tower")
	assert_false(by_ship["t"].data.has("tow"), "no ram detail, no tow flag")


## The tower's stern swings onto her own tow's bow (t at bow (5, 5) facing NW, stern (5, 6); w at bow
## (6, 5) facing SW, the follow pose of a starboard turn): t turns to port (W), new stern (6, 5). The
## tow follows the same segment (bow (5, 6), facing NE), so the pair never shares a hex at its end:
## no overlap rollback, no collision (pinned behaviour).
func test_tower_stern_swings_onto_own_tow_bow() -> void:
	var t := _ship("t", Vector2i(5, 5), 4, 3, 0, 1)
	var w := _ship("w", Vector2i(6, 5), 2, 2)
	w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	w.sail_state = "NS"
	assert_true(TowRules.in_position(t, w))
	assert_true(sc.begin_tow("t", "w"))
	_plot("t", [[Vector2i(5, 5), 3]])
	var log := _resolver().run([t, w] as Array[ShipState], GameState.environment)
	var tr: MovementTypes.ShipResolutionResult = log.get_result("t")
	var wr: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(tr.final_facing, 3, "the turn is made")
	assert_eq(_tow_held(tr).size(), 0)
	assert_eq(_events(tr, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK).size(), 0)
	assert_eq(tr.collided_with, "")
	assert_eq(wr.collided_with, "")
	var follows := _follows(wr)
	assert_eq(follows.size(), 1)
	if follows.size() == 1:
		assert_eq(follows[0].to_hex, Vector2i(5, 6))
		assert_eq(follows[0].facing, 5)
	assert_eq(HexGrid.stern_of(tr.final_hex, tr.final_facing), Vector2i(6, 5))


## Two tows abreast (rows 5 and 6), both towers two hexes ahead: each tow follows its own tower and
## neither pair blocks the other (pinned behaviour).
func test_two_tows_side_by_side() -> void:
	var ships := _pair(2)
	var t2 := _ship("t2", Vector2i(5, 6), 3, 3, 0, 2)
	var w2 := _ship("w2", Vector2i(7, 6), 3, 2)
	w2.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	w2.sail_state = "NS"
	assert_true(sc.begin_tow("t2", "w2"))
	ships.append_array([t2, w2])
	_plot("t", [[Vector2i(4, 5), 3], [Vector2i(3, 5), 3]])
	_plot("t2", [[Vector2i(4, 6), 3], [Vector2i(3, 6), 3]])
	var log := _resolver().run(ships, GameState.environment)
	for pair in [["t", "w", 5], ["t2", "w2", 6]]:
		var tr: MovementTypes.ShipResolutionResult = log.get_result(pair[0])
		var wr: MovementTypes.ShipResolutionResult = log.get_result(pair[1])
		assert_eq(tr.final_hex, Vector2i(3, pair[2]), "%s sails on" % pair[0])
		assert_eq(_tow_held(tr).size(), 0)
		assert_eq(_follows(wr).size(), 2, "%s follows each step" % pair[1])
		assert_eq(wr.final_hex, Vector2i(5, pair[2]))
		assert_eq(wr.collided_with, "")


## 12.A.11 with a rigged tow: t runs into the dismasted x (no fouling die: a dismasted ship never
## fouls); then w, at MS, rams t: her rigging-loss d6 (MS: d6 + 1) and the fouling d10, from the
## resolver's rng in that order.
func test_ram_dice_with_rigged_tow() -> void:
	var ships := _pair(1)
	var w: ShipState = ships[1]
	w.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	w.sail_state = "MS"
	var x := _ship("x", Vector2i(4, 5), 1)
	x.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	x.sail_state = "NS"
	ships.append(x)
	_plot("t", [[Vector2i(4, 5), 3]])
	var resolver := _resolver()
	var log := resolver.run(ships, GameState.environment, {"t": {"choice": "collide", "segment": 0}})
	var ref := RandomNumberGenerator.new()
	ref.seed = 12345
	var t_d6 := ref.randi_range(1, 6)  # t's own rigging loss (MS)
	var w_d6 := ref.randi_range(1, 6)  # the ram: w's rigging loss
	var foul_d10 := ref.randi_range(0, 9)  # the ram's fouling roll, MS + MS = +2
	assert_eq(resolver.rng.state, ref.state, "exactly these three dice")
	var tr: MovementTypes.ShipResolutionResult = log.get_result("t")
	var wr: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(tr.rigging_damage, MovementResolver.collision_rigging_loss("MS", t_d6, 0))
	assert_eq(wr.rigging_damage, MovementResolver.collision_rigging_loss("MS", w_d6, 0))
	assert_eq(_events(wr, MovementTypes.ResolutionEventType.COLLISION_RIGGING_LOSS).size(), 1)
	var fouled := foul_d10 + 2 >= 6
	assert_eq(wr.fouled_with, "t" if fouled else "")
	assert_eq(tr.fouled_with, "w" if fouled else "")
	assert_eq(_events(wr, MovementTypes.ResolutionEventType.FOULING).size(), 1 if fouled else 0)


## The "fouled" hold: a towed ship fouled before movement holds her tower before the pass (8.C.7,
## DefaultCourse.tow_held: her plot is ignored, so no step is made and none undone, no TOW_HELD).
## The TOW_HELD reason "tow_fouled" is a defence only: a tow fouled during the pass was always in
## a collision too, which _follow_tows reads first ("tow_collision"). Pinned behaviour.
func test_fouled_tow_holds_tower() -> void:
	var ships := _pair(1)
	var y := _ship("y", Vector2i(7, 6), 3, 3, 1)
	ships.append(y)
	ships[1].fouled_with = "y"
	y.fouled_with = "w"
	_plot("t", [[Vector2i(4, 5), 3]])
	var log := _resolver().run(ships, GameState.environment)
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	assert_eq(_tow_held(t).size(), 0, "held before the pass, not rolled back")
	assert_eq(_moves(t).size(), 0)
	assert_eq(t.final_hex, Vector2i(5, 5))
	assert_eq(_follows(log.get_result("w")).size(), 0)
	var held := GameState.movement_plotting_controller.handle_start_plotting(0, "t", "r1")
	assert_true(held is MovementTypes.PlottingErrorResponse)
	if held is MovementTypes.PlottingErrorResponse:
		assert_eq(held.error_code, "TOW_HELD")


## SHIP_TOWED at the resolver: a towed ship's stored plot is ignored; she only follows her tower.
func test_towed_plot_ignored_by_resolver() -> void:
	var ships := _pair(1)
	var w: ShipState = ships[1]
	w.plotted_actions["movement"] = [{"hex": {"q": 6, "r": 5}, "facing": 3}]
	w.plotted_actions["movement_plotted"] = true
	_plot("t", [[Vector2i(4, 5), 3]])
	var log := _resolver().run(ships, GameState.environment)
	var wr: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(_moves(wr).size(), 0, "no step of her own")
	assert_eq(_follows(wr).size(), 1)
	assert_eq(wr.final_hex, Vector2i(6, 5))


