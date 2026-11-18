extends GutTest
## The stub AI's 14.B policy (sub-project 7, spec §5): rally first when no enemy is within 5, plot,
## then surrender at 2:1 gun factors within range 3 or to a linked enemy with boarders.

const PHASES := TurnPhaseController.GamePhase

var stub_ai: StubAI
var pc: TurnPhaseController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_logs: Dictionary
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _old_turn: int
var _old_pc_turn: int
var _old_humans: Array[int]
var _old_ai: Array[int]


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_logs = GameState.turn_logs
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	_old_turn = GameState.current_turn
	_old_pc_turn = pc.current_turn
	_old_humans = pc.human_player_ids.duplicate()
	_old_ai = pc.ai_player_ids.duplicate()
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.turn_logs = {}
	GameState.active_scenario = {"optional_rules": {"voluntary_surrender": true}}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 1
	pc.current_turn = 1
	pc.human_player_ids = []
	pc.ai_player_ids = []
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	pc.current_phase = PHASES.PLANNING
	pc.players_ready = {0: false, 1: false}
	pc.game_result = {}
	if GameState.movement_plotting_controller:
		GameState.movement_plotting_controller.sessions.clear()
		GameState.movement_plotting_controller.ship_sessions.clear()
	stub_ai = StubAI.new(GameState)


func after_each() -> void:
	pc.game_result = {}
	pc.current_phase = PHASES.SETUP
	pc.players_ready = {}
	pc.planning_snapshot = {}
	pc.current_turn = _old_pc_turn
	pc.human_player_ids = _old_humans
	pc.ai_player_ids = _old_ai
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.turn_logs = _old_logs
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, side: int, bow: Vector2i, facing: int, lg: int, cq: String = "D") -> ShipState:
	var def := DataManager.get_ship_definition("frigate_38")
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": "frigate_38", "name": def.name, "nationality": "British",
		"rating": def.rating, "class": def.ship_class,
		"maneuverability": def.maneuverability, "speed_type": def.speed_type,
		"rigging_hp": def.rigging_hp, "hull_hp": def.hull_hp,
		"crew_count": def.crew_count, "marine_count": def.marine_count,
		"gun_factors": {"lg": lg, "mg": 0, "cr": 0},
		"point_costs": def.point_costs,
	})
	state.hex_position = bow
	state.facing = facing
	state.speed = 1
	state.sail_state = "MS"
	var rigging: Array[int] = []
	rigging.assign(def.rigging_hp)
	state.rigging_current_hp = rigging
	var hull: Array[int] = []
	hull.assign(def.hull_hp)
	state.hull_current_hp = hull
	var crew: Array[int] = []
	crew.assign(def.crew_count)
	state.crew_count = crew
	state.marine_count = def.marine_count
	state.crew_quality = cq
	state.starting_crew_quality = cq
	state.morale_rating = 4
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


## Own ship s1 (side 1, facing west, stern at x+1) and the enemy e0 `distance` hexes east of her stern.
func _duel(own_lg: int, enemy_lg: int, distance: int, cq: String = "F") -> Array[ShipState]:
	var s1 := _make_ship("s1", 1, Vector2i(10, 10), 3, own_lg, cq)
	var e0 := _make_ship("e0", 0, Vector2i(10 + 2 + distance, 10), 3, enemy_lg)
	return [s1, e0]


func test_gun_strength() -> void:
	var s := _make_ship("s", 1, Vector2i(10, 10), 3, 0)
	s.ship.gun_factors = {"lg": 6, "mg": 0, "cr": 4}
	s.guns_dismounted = [3, 1] as Array[int]
	assert_eq(StubAI.gun_strength(s), 9)
	s.status = ShipState.Status.STRUCK
	assert_eq(StubAI.gun_strength(s), 0)


func test_surrenders_against_two_to_one() -> void:
	var ships := _duel(4, 10, 2)
	assert_true(stub_ai.wants_to_surrender(ships[0]), "10 against 4 within range 3")
	stub_ai.plot_all_ai_ships()
	assert_true(ships[0].surrender_ordered)
	assert_eq(stub_ai.refusals.size(), 0)


func test_no_surrender_below_two_to_one() -> void:
	var ships := _duel(4, 7, 2)
	assert_false(stub_ai.wants_to_surrender(ships[0]), "7 is under 2 x 4")
	stub_ai.plot_all_ai_ships()
	assert_false(ships[0].surrender_ordered)


func test_no_surrender_beyond_range_three() -> void:
	var ships := _duel(4, 10, 4)
	assert_false(stub_ai.wants_to_surrender(ships[0]))


func test_surrenders_to_a_linked_boarder() -> void:
	var ships := _duel(10, 4, 0, "G")
	var s1 := ships[0]
	var e0 := ships[1]
	GameState.ship_controller.add_grapple(s1.ship_id, e0.ship_id)
	e0.crew_tasks.append(ShipState.crew_task_from({"seq": 1, "code": "BR", "sections": [0],
		"done": 0, "started_turn": 0, "params": {"section": 0}, "forced": false,
		"marines_available": true, "ended": ""}))
	assert_true(e0.has_boarders())
	assert_true(stub_ai.wants_to_surrender(s1), "linked to an enemy with readied boarders")
	e0.crew_tasks.clear()
	assert_false(stub_ai.wants_to_surrender(s1), "no boarders, and her guns are the stronger")


func test_not_eligible_never_surrenders() -> void:
	var ships := _duel(4, 20, 0, "D")
	assert_false(stub_ai.wants_to_surrender(ships[0]))
	stub_ai.plot_all_ai_ships()
	assert_false(ships[0].surrender_ordered)


func test_off_switch() -> void:
	GameState.active_scenario = {}
	var ships := _duel(4, 10, 2)
	stub_ai.plot_all_ai_ships()
	assert_false(ships[0].surrender_ordered)
	assert_eq(stub_ai.refusals.size(), 0, "no request, so no refusal")


func _surrendered_ship(enemy_distance: int) -> Array[ShipState]:
	var ships := _duel(4, 4, enemy_distance, "F")
	assert_eq(pc.player_surrender(1, "s1"), "")
	GameState.morale_controller.resolve_phase(PHASES.MORALE_CHECK)
	assert_true(ships[0].can_rally())
	ships[0].crew_quality = "D"
	pc.current_phase = PHASES.PLANNING
	pc.players_ready = {0: false, 1: false}
	GameState.current_turn = 2
	pc.current_turn = 2
	return ships


func test_rallies_when_clear() -> void:
	var ships := _surrendered_ship(8)
	_dice.queue([6])
	stub_ai.plot_all_ai_ships()
	assert_eq(ships[0].status, ShipState.Status.ACTIVE, "she rallied")
	assert_gt(ships[0].plotted_actions.movement.size(), 0, "and plots this turn")
	assert_false(ships[0].surrender_ordered, "a ship that has just rallied does not surrender again")


func test_no_rally_with_enemy_near() -> void:
	var ships := _surrendered_ship(4)
	_dice.queue([6])
	stub_ai.plot_all_ai_ships()
	assert_true(ships[0].is_struck())
	assert_eq(_dice.remaining(), 1, "no die rolled")
