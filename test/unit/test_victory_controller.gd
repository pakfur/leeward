extends GutTest
## Tests for VictoryController (Close Action 1997 victory points, section 12.1) and the
## POST_COMBAT wait / END_TURN / game over flow in TurnPhaseController.

const PHASES := TurnPhaseController.GamePhase

var controller: VictoryController
var pc: TurnPhaseController
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_logs: Dictionary
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _over_results: Array = []


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_logs = GameState.turn_logs
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	GameState.dice = Dice.new(GameState.rng)
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.turn_logs = {}
	GameState.active_scenario = {}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	controller = VictoryController.new(GameState)
	pc.game_result = {}
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	_over_results = []
	pc.game_over.connect(_on_game_over)


func after_each() -> void:
	pc.game_over.disconnect(_on_game_over)
	pc.game_result = {}
	pc.current_phase = PHASES.SETUP
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.turn_logs = _old_logs
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _on_game_over(result: Dictionary) -> void:
	_over_results.append(result)


func _make_ship(id: String, player: int, quality: String = "D", rating: int = 4) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	state.hex_position = Vector2i(5 + player * 10, 5)
	state.facing = 3
	state.speed = 1
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
	state.morale_rating = rating
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


func _strike(ship: ShipState) -> void:
	ship.status = ShipState.Status.STRUCK


# --- points_lost ---------------------------------------------------------------

func test_undamaged_ship_loses_no_points() -> void:
	var ship := _make_ship("a", 0)
	assert_eq(controller.points_lost(ship), 0.0)


func test_struck_ship_loses_full_value() -> void:
	var ship := _make_ship("a", 0)
	_strike(ship)
	assert_eq(controller.points_lost(ship), 38.0)


func test_rigging_one_and_hull_one_lost_is_fifteen_percent() -> void:
	var ship := _make_ship("a", 0)
	ship.rigging_current_hp[0] = 0
	ship.hull_current_hp[0] = 0
	assert_true(is_equal_approx(controller.points_lost(ship), 5.7), "5% + 10% of 38")


func test_all_rigging_sections_lost_is_twenty_five_percent() -> void:
	var ship := _make_ship("a", 0)
	for i in range(4):
		ship.rigging_current_hp[i] = 0
	assert_true(is_equal_approx(controller.points_lost(ship), 9.5), "5+5+5+10 percent of 38")


func test_crew_loss_is_capped_at_forty_percent() -> void:
	var ship := _make_ship("a", 0)
	for i in range(4):
		ship.crew_count[i] = 0
	ship.marine_count = 0
	assert_true(is_equal_approx(controller.points_lost(ship), 15.2), "five sections lost, capped at 40%")


func test_points_use_starting_crew_quality() -> void:
	var ship := _make_ship("a", 0, "D")
	ship.crew_quality = "G"
	_strike(ship)
	assert_eq(controller.points_lost(ship), 38.0, "value is taken at the starting quality (D4)")


# --- check ---------------------------------------------------------------------

func test_game_continues_when_nobody_struck() -> void:
	_make_ship("a", 0)
	_make_ship("b", 1)
	assert_eq(controller.check(3), {})


func test_all_enemy_ships_struck_player_wins() -> void:
	_make_ship("a", 0)
	_strike(_make_ship("b", 1))
	var result: Dictionary = controller.check(3)
	assert_eq(result["winner"], 0)
	assert_eq(result["reason"], "all struck")
	assert_eq(result["turn"], 3)
	assert_eq(result["points"][0], 38.0)
	assert_eq(result["points"][1], 0.0)


func test_both_sides_struck_equal_is_a_draw() -> void:
	_strike(_make_ship("a", 0))
	_strike(_make_ship("b", 1))
	var result: Dictionary = controller.check(2)
	assert_eq(result["winner"], -1)
	assert_eq(result["reason"], "all struck")


func test_turn_limit_decides_on_points_scored() -> void:
	GameState.active_scenario = {"turn_limit": 5}
	_make_ship("a", 0)
	var enemy := _make_ship("b", 1)
	enemy.hull_current_hp[0] = 0
	var result: Dictionary = controller.check(5)
	assert_eq(result["winner"], 0)
	assert_eq(result["reason"], "turn limit")


func test_before_turn_limit_game_continues() -> void:
	GameState.active_scenario = {"turn_limit": 5}
	_make_ship("a", 0)
	_make_ship("b", 1).hull_current_hp[0] = 0
	assert_eq(controller.check(4), {})


func test_side_without_ships_counts_as_defeated() -> void:
	_make_ship("a", 0)
	var result: Dictionary = controller.check(1)
	assert_eq(result["reason"], "all struck")
	assert_eq(result["winner"], -1, "no points scored by either side")


func test_check_does_not_change_state() -> void:
	_make_ship("a", 0)
	_strike(_make_ship("b", 1))
	controller.check(1)
	assert_eq(GameState.turn_log.events.size(), 0)
	assert_eq(pc.game_result, {})


# --- phase flow ----------------------------------------------------------------

func _enter_post_combat(turn: int) -> void:
	pc.current_turn = turn
	GameState.current_turn = turn
	pc.current_phase = PHASES.POST_COMBAT


func test_end_turn_outside_post_combat_is_refused() -> void:
	pc.current_phase = PHASES.PLANNING
	assert_false(pc.player_end_turn(0))
	assert_eq(pc.current_phase, PHASES.PLANNING)


func test_post_combat_does_not_advance_on_its_own() -> void:
	_enter_post_combat(1)
	pc.advance_phase()
	assert_engine_error("POST_COMBAT waits for player_end_turn")
	assert_eq(pc.current_phase, PHASES.POST_COMBAT, "only player_end_turn leaves POST_COMBAT")


func test_end_turn_without_victory_starts_next_turn() -> void:
	_make_ship("a", 0)
	_make_ship("b", 1)
	GameState.turn_log.turn = 4
	_enter_post_combat(4)
	assert_true(pc.player_end_turn(0))
	assert_eq(pc.current_phase, PHASES.PLANNING)
	assert_eq(pc.current_turn, 5)
	assert_true(GameState.turn_logs.has(4), "finished turn's log is archived")
	assert_eq(GameState.turn_log.turn, 5, "fresh log for the new turn")
	assert_eq(pc.game_result, {})
	assert_eq(_over_results.size(), 0)


func test_end_turn_with_victory_stops_the_game() -> void:
	_make_ship("a", 0)
	_strike(_make_ship("b", 1))
	GameState.turn_log.turn = 2
	_enter_post_combat(2)
	assert_true(pc.player_end_turn(0))
	assert_eq(pc.current_phase, PHASES.END_TURN)
	assert_eq(pc.game_result["winner"], 0)
	assert_eq(_over_results.size(), 1, "game_over emitted once")
	var victories = GameState.turn_logs[2].of_type(PhaseEvents.Type.VICTORY)
	assert_eq(victories.size(), 1)
	assert_eq(victories[0].data["winner"], 0)
	assert_eq(victories[0].data["reason"], "all struck")
	pc.advance_phase()
	assert_eq(pc.current_phase, PHASES.END_TURN, "advance_phase is ignored after game over")
	assert_false(pc.player_end_turn(0))
	assert_eq(pc.current_turn, 2)
	assert_eq(_over_results.size(), 1)


func test_submissions_ignored_after_game_over() -> void:
	_make_ship("a", 0)
	_strike(_make_ship("b", 1))
	_enter_post_combat(1)
	pc.player_end_turn(0)
	assert_false(pc.player_submit_plan(0))
	assert_ne(pc.player_submit_fire_orders(0, []), "")
	assert_eq(pc.current_phase, PHASES.END_TURN)


func test_start_new_game_clears_game_result() -> void:
	pc.game_result = {"winner": 0}
	GameState.start_new_game({"name": "t", "wind_direction": 0, "wind_speed": 2, "sea_state": 1})
	assert_eq(pc.game_result, {})
	assert_eq(GameState.turn_log.turn, 1)


# --- starting_crew_quality -------------------------------------------------------

func test_starting_crew_quality_round_trips() -> void:
	var ship := _make_ship("a", 0, "C")
	ship.crew_quality = "F"
	var copy := ShipState.deserialize(ship.serialize())
	assert_eq(copy.starting_crew_quality, "C")
	assert_eq(copy.crew_quality, "F")


func test_deserialize_defaults_starting_quality_to_current() -> void:
	var data := _make_ship("a", 0, "C").serialize()
	data.erase("starting_crew_quality")
	data["crew_quality"] = "E"
	assert_eq(ShipState.deserialize(data).starting_crew_quality, "E")
