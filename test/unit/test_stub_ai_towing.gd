extends GutTest
## StubAI and towing (towing spec §11; register §4): with no enemy within 8 hexes an AI ship claims
## its nearest friendly cripple (dismasted, or a prize) when it is the nearest free AI ship to her,
## prepares the tow, steers for the tow station and takes her in tow; a tower runs for the escape
## edge (else disengages) and cuts the tow when an enemy closes within 3. AI ships are player 1's,
## the enemy player 0's. Wind from the east (direction 0), speed 3; a 40 x 30 board (cols -20..19,
## rows -15..14).

const PLANNING := TurnPhaseController.GamePhase.PLANNING
const DRIFT := TurnPhaseController.GamePhase.DRIFT_CALCULATION

var stub_ai: StubAI
var sc: ShipStateController
var pc: TurnPhaseController
var _dice: ScriptedDice
var _saved_scenario: Dictionary
var _saved_env: EnvironmentState
var _saved_turn: int
var _saved_dice: Dice
var _saved_rng: RandomNumberGenerator
var _saved_log: PhaseEvents.PhaseLog


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	_reset_ships()
	pc = GameState.phase_controller
	_saved_scenario = GameState.active_scenario
	_saved_env = GameState.environment
	_saved_turn = GameState.current_turn
	_saved_dice = GameState.dice
	_saved_rng = GameState.rng
	_saved_log = GameState.turn_log
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 3
	GameState.turn_log = GameState.new_turn_log(3)
	pc.current_phase = PLANNING
	pc.game_result = {}
	pc.players_ready = {0: false, 1: false}
	GameState.active_scenario = _scenario()
	sc = GameState.ship_controller
	stub_ai = StubAI.new(GameState)
	_make_ship("a", 1, Vector2i(-10, -5), 3)
	var b := _make_ship("b", 1, Vector2i(-6, -5), 3)
	b.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	b.sail_state = "NS"
	_make_ship("e", 0, Vector2i(15, 10), 3)


func after_each() -> void:
	pc._reset_maintenance()
	GameState.active_scenario = _saved_scenario
	GameState.environment = _saved_env
	GameState.current_turn = _saved_turn
	GameState.rng = _saved_rng
	GameState.dice = _saved_dice
	GameState.turn_log = _saved_log
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	pc._pending_resolution_log = null
	_reset_ships()


func _reset_ships() -> void:
	GameState.ships.clear()
	GameState.ships_by_side.clear()
	if GameState.movement_plotting_controller:
		GameState.movement_plotting_controller.sessions.clear()
		GameState.movement_plotting_controller.ship_sessions.clear()


func _scenario(escape: bool = false) -> Dictionary:
	var s := {"map_bounds": {"width": 40, "height": 30}}
	if escape:
		s["terrain"] = {"edges": {"W": "escape"}}
		s["escape"] = {"1": {"from_turn": 1, "edges": ["W"], "share": 0.5}}
	return s


func _make_ship(ship_id: String, player_id: int, hex_pos: Vector2i, facing: int, speed: int = 0) -> ShipState:
	var state = ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": ship_id,
		"player_id": player_id,
		"ship_name": "Ship " + ship_id,
		"ship_type": "frigate_32",
		"name": "32-gun Frigate",
		"nationality": "British",
		"rating": 32,
		"class": 3,
		"maneuverability": "C",
		"speed_type": "F/F",
		"draft": 16,
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex_pos
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = "B"
	state.starting_crew_quality = "B"
	state.morale_rating = 4
	state.mp_used_this_turn = 0
	assert_true(GameState.add_ship(state))
	return state


func _ship(id: String) -> ShipState:
	return GameState.get_ship(id)


## `a` tows `b` (the fields only; geometry does not matter to the AI's choices).
func _a_tows_b() -> void:
	_ship("a").towing_id = "b"
	_ship("b").towed_by = "a"


## `a` on the tow station of `b`: bow (-8, -5) f3, stern (-7, -5), the hex ahead of b's bow.
func _a_on_station() -> ShipState:
	var a := _ship("a")
	a.hex_position = Vector2i(-8, -5)
	assert_true(TowRules.in_position(a, _ship("b")))
	return a


func _tow_codes(plan: Dictionary) -> Dictionary:
	var out := {}
	var assignments: Dictionary = plan.get("assignments", {})
	for s in assignments:
		if TowRules.is_code(str(assignments[s].get("code", ""))):
			out[int(s)] = str(assignments[s]["code"])
	return out


# --- the tow target --------------------------------------------------------------------

func test_tow_target_nearest_cripple() -> void:
	assert_eq(stub_ai.tow_target(_ship("a")), "b")
	var c := _make_ship("c", 1, Vector2i(5, -5), 3)
	c.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(stub_ai.tow_target(_ship("a")), "b", "the nearer cripple")


func test_no_tow_near_enemy() -> void:
	_ship("e").hex_position = Vector2i(-10, 1)  # range 6
	assert_eq(stub_ai.tow_target(_ship("a")), "")
	_ship("e").hex_position = Vector2i(-10, 4)  # range 9
	assert_eq(stub_ai.tow_target(_ship("a")), "b")


func test_struck_friend_not_towed_prize_is() -> void:
	var b := _ship("b")
	b.status = ShipState.Status.STRUCK
	assert_eq(stub_ai.tow_target(_ship("a")), "")
	# A prize held by side 1, rigged (not dismasted).
	b.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	b.status = ShipState.Status.CAPTURED
	b.controller_side = 1
	assert_true(b.is_captured())
	assert_eq(b.side, 1)
	assert_eq(stub_ai.tow_target(_ship("a")), "b")


func test_claim_goes_to_nearest() -> void:
	_make_ship("a2", 1, Vector2i(-3, -5), 3)
	assert_eq(stub_ai.tow_target(_ship("a2")), "b")
	assert_eq(stub_ai.tow_target(_ship("a")), "", "a2 is nearer to b and claims her")


func test_anchored_or_becalmed_ship_never_starts_a_tow() -> void:
	GameState.environment.wind_speed = 0
	assert_eq(stub_ai.tow_target(_ship("a")), "", "no way at any heading")
	GameState.environment.wind_speed = 3
	_ship("a").anchor = {"hex": Vector2i(-11, -5), "end": "bow"}
	assert_true(_ship("a").is_anchored())
	assert_eq(stub_ai.tow_target(_ship("a")), "")


# --- the tow order ---------------------------------------------------------------------

func test_tow_order() -> void:
	assert_eq(stub_ai.tow_order(_ship("a")), "take:b")
	_a_tows_b()
	_ship("e").hex_position = Vector2i(-10, -2)  # range 3
	assert_eq(stub_ai.tow_order(_ship("a")), "cut")
	_ship("e").hex_position = Vector2i(-10, -1)  # range 4
	assert_eq(stub_ai.tow_order(_ship("a")), "")
	assert_eq(stub_ai.tow_order(_ship("b")), "", "the towed ship never cuts")


func test_tow_being_prepared_is_not_cut() -> void:
	var a := _ship("a")
	a.tow_prepared = true
	_ship("e").hex_position = Vector2i(-10, -2)  # range 3
	assert_eq(stub_ai.tow_order(a), "")


# --- strategy --------------------------------------------------------------------------

func test_strategy_choice() -> void:
	_a_tows_b()
	GameState.active_scenario = _scenario(true)
	assert_eq(stub_ai._get_strategy(_ship("a")), "escape")
	GameState.active_scenario = _scenario()
	assert_eq(stub_ai._get_strategy(_ship("a")), "disengage")
	_ship("a").towing_id = ""
	_ship("b").towed_by = ""
	assert_eq(stub_ai._get_strategy(_ship("a")), "tow")


func test_tow_strategy_slows() -> void:
	_ship("a").speed = 4
	stub_ai.plot_all_ai_ships()
	var course: Array = _ship("a").plotted_actions.get("movement", [])
	assert_eq(course.size(), 1, "one move, the full deceleration: %s" % [course])


func test_tow_strategy_holds_on_station() -> void:
	var a := _a_on_station()
	stub_ai.plot_all_ai_ships()
	assert_eq((a.plotted_actions.get("movement", []) as Array).size(), 0)
	assert_eq(a.tow_order(), "take:b")
	assert_true(a.crew_auto)
	var plan: Dictionary = GameState.crew_task_controller.current_plan("a")
	assert_eq(_tow_codes(plan).values(), ["PT"])


func test_ai_takes_tow_end_to_end() -> void:
	var a := _a_on_station()
	a.tow_prepared = true
	a.crew_quality = "C"
	a.starting_crew_quality = "C"
	stub_ai.assign_crew()
	_dice.queue([0])
	pc.current_phase = DRIFT
	pc._enter_status_adjustment_phase()
	assert_eq(a.towing_id, "b")
	assert_eq(_dice.remaining(), 0)


func test_towed_ai_ship_skipped() -> void:
	_a_on_station()
	_a_tows_b()
	stub_ai.plot_all_ai_ships()
	for r in stub_ai.refusals:
		assert_ne(str(r["ship_id"]), "b", "no refusal for the towed ship: %s" % [r])
