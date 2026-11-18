extends GutTest
## The towed ship follows in her tower's wake (Close Action 12.A.5; towing spec §5, register §4): on
## each step the tower makes, the towed bow takes the hex the tower's stern just left, pointing at the
## tower's new stern. The follow is on the tower's segment, draws no die, and repeats through re-runs
## (bear-off pauses, overlap rollbacks). apply_results gives the towed ship the unit's speed.
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


func _impulses(events: Array) -> Array:
	return events.map(func(ev) -> int: return ev.impulse)


@warning_ignore("shadowed_global_identifier")
func _assert_tow_geometry(log: MovementTypes.ResolutionLog) -> void:
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	var w: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(w.final_hex + HexGrid.DIRECTIONS[w.final_facing], HexGrid.stern_of(t.final_hex, t.final_facing),
		"the towed bow points at the tower's stern")


func _straight_plot() -> void:
	_plot("t", [[Vector2i(4, 5), 3], [Vector2i(3, 5), 3]])


func test_straight_tow_follows_each_step() -> void:
	var ships := _pair()
	_straight_plot()
	var log := _resolver().run(ships, GameState.environment)
	var w: MovementTypes.ShipResolutionResult = log.get_result("w")
	var follows := _follows(w)
	assert_eq(follows.size(), 2)
	assert_eq(follows[0].from_hex, Vector2i(7, 5))
	assert_eq(follows[0].from_facing, 3)
	assert_eq(follows[0].to_hex, Vector2i(6, 5))
	assert_eq(follows[0].facing, 3)
	assert_eq(follows[1].to_hex, Vector2i(5, 5))
	assert_eq(follows[1].facing, 3)
	assert_true(follows.all(func(ev) -> bool: return ev.success))
	assert_eq(_impulses(follows), _impulses(_moves(log.get_result("t"))), "on the tower's segments")
	assert_eq(w.final_hex, Vector2i(5, 5))
	assert_eq(w.final_facing, 3)
	_assert_tow_geometry(log)
	assert_eq(log.towed_by, {"w": "t"})
	assert_eq(log.to_dict().get("towed_by"), {"w": "t"})


func test_follow_after_starboard_turn() -> void:
	var ships := _pair()
	_plot("t", [[Vector2i(5, 5), 4]])
	var log := _resolver().run(ships, GameState.environment)
	var w: MovementTypes.ShipResolutionResult = log.get_result("w")
	assert_eq(_follows(w).size(), 1)
	assert_eq(w.final_hex, Vector2i(6, 5))
	assert_eq(w.final_facing, 2)
	_assert_tow_geometry(log)


func test_turn_then_ahead() -> void:
	var ships := _pair()
	_plot("t", [[Vector2i(5, 5), 4], [Vector2i(5, 4), 4]])
	var log := _resolver().run(ships, GameState.environment)
	var w: MovementTypes.ShipResolutionResult = log.get_result("w")
	var follows := _follows(w)
	assert_eq(follows.size(), 2)
	assert_eq(follows[1].to_hex, Vector2i(5, 6))
	assert_eq(follows[1].facing, 4)
	assert_eq(w.final_hex, Vector2i(5, 6))
	assert_eq(w.final_facing, 4)
	_assert_tow_geometry(log)


func test_proportional_pace() -> void:
	var ships := _pair()
	_straight_plot()
	var o := _ship("o", Vector2i(20, 20), 3, 3, 0, 3)
	_plot("o", [[Vector2i(19, 20), 3], [Vector2i(18, 20), 3], [Vector2i(17, 20), 3]])
	ships.append(o)
	var log := _resolver().run(ships, GameState.environment)
	var follows := _follows(log.get_result("w"))
	assert_eq(follows.size(), 2)
	assert_eq(_impulses(follows), _impulses(_moves(log.get_result("t"))))
	for k in range(follows.size()):
		assert_eq(log.segment_times[follows[k].impulse], MoveSchedule.step_time(k, 2),
			"follow %d at the tower's pace" % k)
		assert_eq(follows[k].time, MoveSchedule.step_time(k, 2))


func test_follow_draws_no_dice() -> void:
	var ships := _pair()
	_straight_plot()
	var resolver_a := _resolver(99)
	resolver_a.run(ships, GameState.environment)
	# B: the same plot, with w absent and no tow.
	sc.cut_tow("t")
	GameState.ships.erase("w")
	GameState.ships_by_side[0].erase("w")
	_straight_plot()
	var alone: Array[ShipState] = [ships[0]]
	var resolver_b := _resolver(99)
	resolver_b.run(alone, GameState.environment)
	assert_eq(resolver_a.rng.state, resolver_b.rng.state, "the follow drew no die")


func test_deterministic_rerun() -> void:
	var ships := _pair()
	_plot("t", [[Vector2i(5, 5), 4], [Vector2i(5, 4), 4]])
	var log_a := _resolver(7).run(ships, GameState.environment)
	var log_b := _resolver(7).run(ships, GameState.environment)
	assert_eq(JSON.stringify(log_a.to_dict()), JSON.stringify(log_b.to_dict()))


func test_follow_survives_bear_off_rerun() -> void:
	pc.bear_off_prompt_player_ids = [0] as Array[int]
	var requests: Array = []
	var on_request := func(_player: int, situation: MovementTypes.BearOffSituation) -> void:
		requests.append(situation)
	pc.bear_off_decision_requested.connect(on_request)
	_pair(3)
	_plot("t", [[Vector2i(4, 5), 3], [Vector2i(3, 5), 3], [Vector2i(2, 5), 3]])
	_ship("e", Vector2i(2, 5), 1, 3, 1, 0)
	pc._enter_movement_resolution_phase()
	assert_eq(_logs.size(), 1)
	assert_false(_logs[0].is_complete(), "paused for the bear-off decision")
	var first := _follows(_logs[0].get_result("w"))
	assert_eq(first.size(), 2, "the follows of the segments before the pause")
	assert_true(first.all(func(ev) -> bool: return ev.impulse < _logs[0].pending_bear_off.segment))
	assert_eq(pc.player_submit_bear_off(0, "t", MovementTypes.BEAR_OFF_COLLIDE), "")
	assert_eq(_logs.size(), 2, "re-run")
	var second := _follows(_logs[1].get_result("w"))
	assert_true(second.size() >= first.size())
	for i in range(first.size()):
		assert_eq(second[i].impulse, first[i].impulse)
		assert_eq(second[i].to_hex, first[i].to_hex)
		assert_eq(second[i].facing, first[i].facing)
	pc.bear_off_decision_requested.disconnect(on_request)


func test_follow_after_overlap_rollback() -> void:
	var ships := _pair(4)
	_plot("t", [[Vector2i(5, 5), 4]])  # a starboard turn: the new stern is (5, 6)
	ships.append(_ship("y", Vector2i(5, 6), 3, 3, 1, 0))  # holds (5, 6) and (6, 6)
	var log := _resolver().run(ships, GameState.environment)
	var t: MovementTypes.ShipResolutionResult = log.get_result("t")
	var rollbacks := _events(t, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1)
	assert_true(rollbacks[0].detail.contains("already occupied"), rollbacks[0].detail)
	var moves := _moves(t)
	assert_eq(moves.size(), 1, "amended to one step ahead")
	assert_eq(moves[0].to_hex, Vector2i(4, 5))
	assert_eq(moves[0].facing, 3)
	var follows := _follows(log.get_result("w"))
	assert_eq(follows.size(), 1)
	assert_eq(follows[0].to_hex, Vector2i(6, 5))
	assert_eq(follows[0].facing, 3)
	_assert_tow_geometry(log)


func test_apply_results_towed() -> void:
	var ships := _pair()
	_straight_plot()
	var resolver := _resolver()
	var log := resolver.run(ships, GameState.environment)
	resolver.apply_results(log, ships)
	var t: ShipState = ships[0]
	var w: ShipState = ships[1]
	assert_eq(w.hex_position, Vector2i(5, 5))
	assert_eq(w.facing, 3)
	assert_eq(t.speed, 2)
	assert_eq(w.speed, t.speed, "the towed ship takes the unit's speed")
	assert_true(w.moved_this_turn)
	assert_eq(w.mp_used_this_turn, 2)
	assert_true(t.is_towing())
	assert_eq(w.towed_by, "t", "still in tow")
