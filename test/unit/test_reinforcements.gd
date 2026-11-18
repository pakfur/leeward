extends GutTest
## Reinforcements (2.B.1, 3.A): a waiting ship enters at the start of its turn at plain-sail speed.

const PHASES := TurnPhaseController.GamePhase
const ENTRY := Vector2i(20, 5)

var pc: TurnPhaseController


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller


func after_each() -> void:
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = PHASES.SETUP
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()
	GameState.turn_logs = {}


func _ship(id: String, player: int, q: int, r: int, facing: int, extra: Dictionary = {}) -> Dictionary:
	var d := {
		"id": id, "ship_name": id, "player_id": player, "ship_type": "frigate_32",
		"position": {"q": q, "r": r}, "facing": facing, "speed": 0, "sail_state": "MS",
		"crew_quality": "Trained", "crew_morale": 4,
	}
	d.merge(extra, true)
	return d


## Player 0 (human) has p0, player 1 (AI) has enemy, player 2 (human) has only the reinforcement,
## which arrives on turn 3 at ENTRY facing west.
func _scenario(with_blocker: bool = false) -> Dictionary:
	var ships := [
		_ship("p0", 0, -8, 0, 0),
		_ship("enemy", 1, 8, 0, 3),
		_ship("reinf", 0, ENTRY.x, ENTRY.y, 3, {"arrives": 3, "sail_state": null}),
	]
	ships[2].erase("sail_state")
	if with_blocker:
		ships.append(_ship("blocker", 1, -20, 20, 0))
	var roster := [
		{"id": 0, "side": 0, "name": "A", "ships": ["p0"]},
		{"id": 2, "side": 0, "name": "B", "ships": ["reinf"]},
		{"id": 1, "side": 1, "name": "C"},
	]
	return {
		"name": "reinforcements", "seed": 5, "wind_direction": 2, "wind_speed": 2,
		"sea_state": 1, "turn_limit": 30, "map_bounds": {"width": 100, "height": 100},
		"ships": ships, "players": roster,
	}


func _start(with_blocker: bool = false) -> void:
	var humans: Array[int] = [0, 2]
	assert_true(GameState.start_scenario(_scenario(with_blocker), humans))


## Plays the current turn from PLANNING to the next PLANNING (no shots: all ships far apart).
func _play_turn(end_turn: bool = true) -> void:
	pc.player_submit_plan(0)
	if pc.current_phase == PHASES.PLANNING:
		pc.player_submit_plan(2)
	assert_eq(pc.current_phase, PHASES.MOVEMENT_RESOLUTION)
	pc.on_playback_completed()
	assert_eq(pc.current_phase, PHASES.POST_COMBAT)
	if end_turn:
		_end_turn()


func _end_turn() -> void:
	pc.player_end_turn(0)
	pc.player_end_turn(2)
	assert_eq(pc.current_phase, PHASES.PLANNING)


func _arrival_speed(wind_speed: int, wind_direction: int) -> int:
	var wf := HexGrid.new().get_wind_facing(3, wind_direction)
	return DataManager.get_movement_allowance("F/S", wind_speed, wf, "ps", 4)


func test_waiting_ship_is_placed_at_its_turn_with_plain_sail_speed() -> void:
	_start()
	var ship: ShipState = GameState.ships["reinf"]
	assert_true(ship.is_awaiting_arrival())
	_play_turn()
	assert_eq(pc.current_turn, 2)
	assert_true(ship.is_awaiting_arrival())
	assert_false(ship.is_on_map())
	var env: EnvironmentState = GameState.environment
	var ws_before := env.wind_speed
	var wd_before := env.wind_direction
	# turn 3's ENVIRONMENT applies a change rolled last turn: pin it so the wind stays put
	env.pending_wind_speed = -1
	env.pending_wind_direction = -1
	_play_turn()
	assert_eq(pc.current_turn, 3)
	assert_true(ship.is_on_map())
	assert_eq(ship.sail_state, "PS")
	assert_eq(ship.speed, _arrival_speed(ws_before, wd_before))
	assert_gt(ship.speed, 0)
	var arrived := GameState.turn_log.of_type(PhaseEvents.Type.ARRIVED)
	assert_eq(arrived.size(), 1)
	assert_eq(arrived[0].ship_id, "reinf")
	assert_eq(int(arrived[0].data["speed"]), ship.speed)


func test_entry_speed_uses_the_wind_before_this_turns_change() -> void:
	_start()
	_play_turn()
	var env: EnvironmentState = GameState.environment
	var old_speed := env.wind_speed
	var old_dir := env.wind_direction
	env.pending_wind_speed = 4 if old_speed != 4 else 1
	env.pending_wind_direction = -1
	_play_turn()
	var ship: ShipState = GameState.ships["reinf"]
	assert_true(ship.is_on_map())
	assert_eq(ship.speed, _arrival_speed(old_speed, old_dir))
	assert_eq(env.wind_speed, 4 if old_speed != 4 else 1, "the change applied after the entry")


func test_held_entry_waits_a_turn() -> void:
	_start(true)
	_play_turn()
	_play_turn(false)
	var blocker: ShipState = GameState.ships["blocker"]
	blocker.hex_position = ENTRY
	blocker.facing = 3
	_end_turn()
	var ship: ShipState = GameState.ships["reinf"]
	assert_eq(pc.current_turn, 3)
	assert_true(ship.is_awaiting_arrival())
	assert_eq(ship.arrives_turn, 4)
	var delayed := GameState.turn_log.of_type(PhaseEvents.Type.ARRIVAL_DELAYED)
	assert_eq(delayed.size(), 1)
	assert_eq(delayed[0].ship_id, "reinf")
	assert_eq(delayed[0].target_id, "blocker")
	_play_turn()
	assert_eq(pc.current_turn, 4)
	assert_true(ship.is_on_map())
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.ARRIVED).size(), 1)


func test_waiting_ship_takes_no_part() -> void:
	_start()
	assert_true(pc.is_player_ready(2), "a player commanding only a waiting ship is ready")
	assert_true(GameState.in_play_ships_of_player(2).is_empty())
	_play_turn()
	_play_turn()
	for turn in [1, 2]:
		for ev: PhaseEvents.PhaseEvent in GameState.turn_logs[turn].events:
			assert_ne(ev.ship_id, "reinf", "turn %d: %s names the waiting ship" % [turn, ev.type])
			assert_ne(ev.target_id, "reinf")
	for r in GameState.stub_ai.refusals:
		assert_ne(str(r.get("ship_id", "")), "reinf")


func test_default_course_and_deceleration_after_arrival() -> void:
	_start()
	_play_turn()
	GameState.environment.pending_wind_speed = -1
	GameState.environment.pending_wind_direction = -1
	GameState.environment.wind_speed = 4
	_play_turn()
	var ship: ShipState = GameState.ships["reinf"]
	assert_true(ship.is_on_map())
	var ma := GameState.ship_controller.get_movement_allowance(ship.ship_id)
	var course := pc.stored_course(ship)
	assert_eq(course.size(), mini(ship.speed, ma))
	var decel: int = GameState.ship_controller.speed_change_limits(ship).decel
	assert_gt(ship.speed - decel, 0, "the test wind must leave a deceleration minimum")
	assert_eq(pc.player_cut_course(2, "reinf", 0), "")
	assert_true(pc.plan_errors(2).has("reinf"), "a course below speed - deceleration is refused")


func test_entry_sail_is_capped_by_the_rigging() -> void:
	_start()
	var ship: ShipState = GameState.ships["reinf"]
	var wf := HexGrid.new().get_wind_facing(ship.facing, 3)
	assert_eq(MapRules.max_ma(ship, wf, 3, "PS"), DataManager.get_movement_allowance("F/S", 3, wf, "ps", 4))
	assert_eq(MapRules.max_ma(ship, wf, 3, "FS"), DataManager.get_movement_allowance("F/S", 3, wf, "fs", 4))
	var rigging: Array[int] = [5, 5, 5, 0]
	ship.rigging_current_hp = rigging
	assert_eq(MapRules.max_ma(ship, wf, 3, "PS"), DataManager.get_movement_allowance("F/S", 3, wf, "ms", 3))
	assert_eq(MapRules.max_ma(ship, wf, 3), DataManager.get_movement_allowance("F/S", 3, wf, "ms", 3))


func test_a_scenario_with_terrain_errors_is_not_started() -> void:
	var scenario := _scenario()
	scenario["terrain"] = {"land": [[900, 900]]}
	var humans: Array[int] = [0, 2]
	assert_false(GameState.start_scenario(scenario, humans))
	assert_push_error("off the map")
	assert_push_error("bad terrain")


## An enemy alongside the entry hex while the reinforcement waits (its footprint is not a berth).
func _enemy_alongside_entry() -> ShipState:
	var blocker: ShipState = GameState.ships["blocker"]
	blocker.hex_position = ENTRY + HexGrid.DIRECTIONS[1]
	blocker.facing = 0
	return blocker


func test_waiting_ship_cannot_be_grappled_and_prompts_no_maintenance() -> void:
	_start(true)
	var blocker := _enemy_alongside_entry()
	var gc: GrapplingController = GameState.grappling_controller
	assert_true(gc.adjacent(blocker, GameState.ships["reinf"]), "the entry footprint is alongside")
	assert_ne(gc.grapple_error("blocker", "reinf"), "")
	assert_ne(gc.grapple_error("reinf", "blocker"), "")
	assert_true(gc.grapple_options("blocker").is_empty())
	assert_true(pc.maintenance_options(2, TurnPhaseController.MaintenanceStep.GRAPPLE).is_empty())
	assert_true(pc.maintenance_options(1, TurnPhaseController.MaintenanceStep.GRAPPLE).is_empty())


func test_explosion_near_the_entry_hex_spares_the_waiting_ship() -> void:
	_start(true)
	var blocker := _enemy_alongside_entry()
	var ship: ShipState = GameState.ships["reinf"]
	var hull_before := ship.hull_current_hp.duplicate()
	GameState.fire_controller.explode("blocker", PHASES.STATUS_ADJUSTMENT)
	assert_true(blocker.is_destroyed())
	assert_eq(ship.hull_current_hp, hull_before)
	assert_eq(ship.fire_count(), 0)
	for ev: PhaseEvents.PhaseEvent in GameState.turn_log.events:
		assert_ne(ev.target_id, "reinf")
