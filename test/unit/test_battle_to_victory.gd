extends GutTest
## Full-loop integration tests: whole battles driven headlessly through the real GameState,
## TurnPhaseController, StubAI, gunnery, drift, morale and victory controllers.

const PHASES := TurnPhaseController.GamePhase
const PORT := 0
const STARBOARD := 1
const MAX_TURNS := 60

var pc: TurnPhaseController
var _saved: Dictionary = {}
var _stalls: Array[String] = []


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller
	_saved = {
		"dice": GameState.dice,
		"rng": GameState.rng,
		"log": GameState.turn_log,
		"logs": GameState.turn_logs,
		"env": GameState.environment,
		"scenario": GameState.active_scenario,
		"resolver": GameState.movement_resolver,
	}
	_stalls = []
	_reset_game()


func after_each() -> void:
	_reset_game()
	GameState.dice = _saved["dice"]
	GameState.rng = _saved["rng"]
	GameState.turn_log = _saved["log"]
	GameState.turn_logs = _saved["logs"]
	GameState.environment = _saved["env"]
	GameState.active_scenario = _saved["scenario"]
	GameState.movement_resolver = _saved["resolver"]
	pc.current_phase = PHASES.SETUP


func _reset_game() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	GameState.clear_state_history()
	GameState.current_turn = 0
	GameState.current_phase = GameState.GamePhase.SETUP
	GameState.turn_logs = {}
	pc.game_result = {}
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.current_phase = PHASES.SETUP
	if GameState.movement_plotting_controller:
		GameState.movement_plotting_controller.sessions.clear()
		GameState.movement_plotting_controller.ship_sessions.clear()


# --- helpers -------------------------------------------------------------------------

func _make_ship(id: String, player: int, hex: Vector2i, facing: int, quality: String) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	state.hex_position = hex
	state.facing = facing
	state.speed = 0
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.marine_count = 2
	state.crew_quality = quality
	state.starting_crew_quality = quality
	state.morale_rating = 4
	GameState.add_ship(state)
	return state


## Two frigates adjacent: "p0" faces east, "p1" sits on its starboard side facing west.
func _add_duel_ships() -> void:
	_make_ship("p0", 0, Vector2i.ZERO, 0, "B")
	_make_ship("p1", 1, HexGrid.DIRECTIONS[1], 3, "E")


func _start(scenario_overrides: Dictionary = {}) -> void:
	var scenario := {
		"name": "battle_test", "wind_direction": 0, "wind_speed": 2, "sea_state": 1,
		"seed": 11, "turn_limit": MAX_TURNS,
	}
	scenario.merge(scenario_overrides, true)
	# The resolver has its own RNG, as in test_game_loop.gd
	var resolver_rng := RandomNumberGenerator.new()
	resolver_rng.seed = 200
	GameState.movement_resolver = MovementResolver.new(GameState, resolver_rng)
	GameState.start_new_game(scenario)


## Orders for player 0: its single best shot (highest mgn, then nearest), low aim.
func _best_shot_orders() -> Array:
	var best: GunneryTypes.ShotPreview = null
	for ship: ShipState in GameState.get_player_ships(0):
		for shot in GameState.gunnery_calculator.eligible_shots(ship.ship_id):
			if best == null or shot.mgn > best.mgn \
					or (shot.mgn == best.mgn and shot.range_hexes < best.range_hexes):
				best = shot
	if best == null:
		return []
	var order := best.order.to_dict()
	order["aim"] = GunneryTypes.AIM_HIGH if best.high_only else GunneryTypes.AIM_LOW
	return [order]


func _hold_fire() -> Array:
	return []


## Drives one full turn from PLANNING to the next PLANNING (or game over).
## `fire` is a Callable returning player 0's orders. Returns false (and records why) on a stall.
func _play_turn(fire: Callable) -> bool:
	var turn := pc.current_turn
	if pc.current_phase != PHASES.PLANNING:
		return _stall(turn, "not in PLANNING at start of turn (%s)" % pc.get_phase_name())
	pc.player_submit_plan(0)
	pc.player_submit_plan(1)
	if pc.current_phase != PHASES.MOVEMENT_RESOLUTION:
		return _stall(turn, "plans did not reach MOVEMENT_RESOLUTION (%s)" % pc.get_phase_name())
	pc.on_playback_completed()
	if pc.current_phase == PHASES.COMBAT_RESOLUTION:
		if pc.combat_step != TurnPhaseController.CombatStep.DECLARE:
			return _stall(turn, "combat not waiting in DECLARE")
		var reason := pc.player_submit_fire_orders(0, fire.call())
		if reason != "":
			return _stall(turn, "fire orders rejected: %s" % reason)
		if pc.combat_step != TurnPhaseController.CombatStep.RESOLVE:
			return _stall(turn, "combat did not reach RESOLVE")
		pc.on_combat_playback_completed()
	if pc.current_phase != PHASES.POST_COMBAT:
		return _stall(turn, "did not reach POST_COMBAT (%s)" % pc.get_phase_name())
	if not pc.player_end_turn(0):
		return _stall(turn, "player_end_turn refused")
	if pc.game_result.is_empty() and pc.current_phase != PHASES.PLANNING:
		return _stall(turn, "did not return to PLANNING (%s)" % pc.get_phase_name())
	return true


func _stall(turn: int, message: String) -> bool:
	_stalls.append("turn %d: %s" % [turn, message])
	return false


## Plays until a result exists, a stall occurs, or `max_turns` turns have been played.
func _play_battle(fire: Callable, max_turns: int = MAX_TURNS) -> void:
	for i in range(max_turns):
		if not _play_turn(fire):
			return
		if not pc.game_result.is_empty():
			return


func _log_dicts() -> Dictionary:
	var result := {}
	for turn in GameState.turn_logs:
		result[turn] = GameState.turn_logs[turn].to_dict()
	return result


func _count_events(type: PhaseEvents.Type) -> int:
	var total := 0
	for turn in GameState.turn_logs:
		total += GameState.turn_logs[turn].of_type(type).size()
	return total


func _boxes_ok(ship: ShipState) -> bool:
	for list in [ship.hull_current_hp, ship.rigging_current_hp, ship.crew_count]:
		for value in list:
			if value < 0:
				return false
	return ship.marine_count >= 0


func _run_duel() -> void:
	_reset_game()
	_add_duel_ships()
	_start()
	_play_battle(_best_shot_orders)


# --- tests ---------------------------------------------------------------------------

func test_scripted_duel_runs_to_a_winner() -> void:
	_run_duel()
	assert_eq(_stalls, [] as Array[String], "no stalls")
	var result := pc.game_result
	assert_false(result.is_empty(), "the duel produced a result")
	assert_lte(int(result["turn"]), MAX_TURNS, "ended within the turn limit")
	assert_true(int(result["winner"]) in [0, 1, -1], "winner is a side or a draw")
	assert_ne(String(result["reason"]), "", "reason is set")
	assert_true(result["points"].has(0) and result["points"].has(1), "both sides scored")
	assert_gt(_count_events(PhaseEvents.Type.FIRE), 0, "at least one FIRE event")
	assert_gt(_count_events(PhaseEvents.Type.DAMAGE), 0, "at least one DAMAGE event")
	assert_gt(_count_events(PhaseEvents.Type.VICTORY), 0, "the result is logged")
	for ship: ShipState in GameState.get_all_ships():
		assert_true(_boxes_ok(ship), "%s has no negative box count" % ship.ship_id)


func test_battle_is_deterministic() -> void:
	_run_duel()
	var first_result := pc.game_result.duplicate(true)
	var first_logs := _log_dicts()
	assert_false(first_result.is_empty(), "first run finished")

	_run_duel()
	assert_eq(pc.game_result, first_result, "same game_result")
	assert_eq(_log_dicts(), first_logs, "same turn logs, event for event")


func test_turn_with_all_player_ships_struck_still_ends() -> void:
	var p0 := _make_ship("p0", 0, Vector2i.ZERO, 0, "B")
	_make_ship("p1", 1, Vector2i(10, 0), 3, "E")
	p0.status = ShipState.Status.STRUCK
	_start()
	_play_turn(_hold_fire)
	assert_eq(_stalls, [] as Array[String], "the turn completes")
	assert_false(pc.game_result.is_empty(), "game over at the first END_TURN")
	assert_eq(pc.game_result["winner"], 1)
	assert_eq(pc.game_result["reason"], "all struck")
	assert_eq(pc.current_phase, PHASES.END_TURN)


func test_sail_change_reduces_fire_then_takes_effect() -> void:
	_add_duel_ships()
	_start()
	assert_eq(GameState.sail_controller.plot_sail_change(0, "p0", "FS"), "")
	var turn := pc.current_turn
	assert_true(_play_turn(_best_shot_orders), "turn plays")
	var fire_events: Array = GameState.turn_logs[turn].of_type(PhaseEvents.Type.FIRE)
	var p0_fire: PhaseEvents.PhaseEvent = null
	for ev in fire_events:
		if ev.ship_id == "p0":
			p0_fire = ev
	assert_not_null(p0_fire, "p0 fired during the change")
	var section_modifier := 0
	for m in p0_fire.data["modifiers"]:
		if m["name"] == "sections_firing":
			section_modifier = int(m["value"])
	assert_eq(section_modifier, -3, "one sailor section busy: sections_firing -3")
	var changes: Array = GameState.turn_logs[turn].of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_gt(changes.size(), 0, "sail change logged")
	assert_eq(GameState.get_ship("p0").sail_state, "FS", "the change completed by the next turn")


func test_sail_change_and_drift_appear_in_turn_log() -> void:
	_make_ship("p0", 0, Vector2i.ZERO, 0, "B")
	_make_ship("p1", 1, Vector2i(30, 20), 3, "E")
	_start()
	assert_eq(GameState.sail_controller.plot_sail_change(0, "p0", "FS"), "")
	var turn := pc.current_turn
	assert_true(_play_turn(_hold_fire), "turn plays")
	var turn_log: PhaseEvents.PhaseLog = GameState.turn_logs[turn]
	assert_gt(turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE).size(), 0, "SAIL_CHANGE event")
	var drifts: Array = turn_log.of_type(PhaseEvents.Type.DRIFT)
	var p0_drifted := false
	for ev in drifts:
		if ev.ship_id == "p0":
			p0_drifted = true
	assert_true(p0_drifted, "the stationary ship drifts in wind speed 2")


func test_ai_engages_in_every_wind_direction() -> void:
	var rows: Array[String] = []
	var engaged_count := 0
	for wind in range(6):
		_reset_game()
		_make_ship("p0", 0, Vector2i(5, 5), 0, "C")
		_make_ship("ai", 1, Vector2i(15, 5), 3, "C")
		_start({"wind_direction": wind, "turn_limit": 0})
		var min_dist := 99
		var fired := false
		var turns := 0
		for i in range(25):
			turns += 1
			if not _play_turn(_hold_fire):
				break
			var d := HexGrid.new().hex_distance(
				GameState.get_ship("p0").hex_position.x, GameState.get_ship("p0").hex_position.y,
				GameState.get_ship("ai").hex_position.x, GameState.get_ship("ai").hex_position.y)
			min_dist = mini(min_dist, d)
			if not pc.game_result.is_empty():
				break
		for turn in GameState.turn_logs:
			for ev in GameState.turn_logs[turn].of_type(PhaseEvents.Type.FIRE):
				if ev.ship_id == "ai":
					fired = true
		var engaged := min_dist <= 5 or fired
		if engaged:
			engaged_count += 1
		rows.append("wind %d: min distance %d, fired %s, turns %d, result %s" % [
			wind, min_dist, str(fired), turns,
			"none" if pc.game_result.is_empty() else str(pc.game_result["reason"])])
	gut.p("\n".join(rows))
	assert_eq(_stalls, [] as Array[String], "no turn stalled in any wind direction")
	assert_gte(engaged_count, 4, "AI got within range 5 or fired in at least 4 of 6 wind directions")
