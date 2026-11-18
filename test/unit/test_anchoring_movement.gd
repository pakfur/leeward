extends GutTest
## The springs step at the start of MOVEMENT_RESOLUTION (Close Action 13.D.2-3, 13.E.2; anchoring
## spec §5): AnchorController.resolve_spring_step turns a ship anchored with springs (HS) or veers
## her in (VI) before any ship moves, and is refused, with no collision and no die, when the hex is
## held, land or off the map. And the in-irons exceptions (5.D.4a-b, 13.F.3; spec §6): an anchored
## ship is never in irons, nor is a ship in the g-t after she cuts her cable.
## Wind from the east (direction 0), speed 3: downwind is west (-1, 0); a bow anchor's proper facing
## is 0, a stern anchor's 3.

const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const PLANNING := TurnPhaseController.GamePhase.PLANNING
const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION

var anchors: AnchorController
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
	GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}, "anchoring": true}
	GameState.current_turn = 5
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	anchors = GameState.anchor_controller
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


func _on_log(log: MovementTypes.ResolutionLog) -> void:
	_logs.append(log)


func _make_ship(id: String, hex: Vector2i, facing: int, side: int = 0, speed: int = 0) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": "HMS " + id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "D", "speed_type": "F/F", "draft": 16,
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	state.side = side
	state.hex_position = hex
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = "A"
	state.crew_auto = false
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


## An anchored ship: bow at `bow` facing `facing`, anchor at `anchor_hex` (anchored on turn 1).
func _anchored(id: String, bow: Vector2i, facing: int, anchor_hex: Vector2i, cable: int,
		end: String = "bow", springs: bool = true, veered: int = 0) -> ShipState:
	var ship := _make_ship(id, bow, facing)
	sc.drop_anchor(id, {"hex": anchor_hex, "end": end, "springs": springs, "cable": cable,
		"veered": veered, "swing_dir": 0, "wind_dir": 0, "turn": 1})
	return ship


## A live task begun this g-t on the marines.
func _task(ship: ShipState, code: String, params: Dictionary = {}) -> void:
	sc.add_task(ship.ship_id, {"code": code, "sections": [ShipState.MARINES], "params": params,
		"started_turn": GameState.current_turn})


func _springs() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.SPRING_TURN)


func _veers() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.VEER_IN)


func _no_collision_or_fouling() -> void:
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.FOULED).size(), 0, "no fouling")
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.COLLISION).size(), 0, "no collision")


# --- spring turns (13.D.2-3) --------------------------------------------------------

func test_spring_turn_bow() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_task(a, "HS", {"turn": "starboard"})
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 1)
	assert_eq(a.hex_position, Vector2i(-1, 0), "AB pivots on her bow")
	assert_eq(a.stern_hex(), Vector2i(-1, -1))
	var ev: Array = _springs()
	assert_eq(ev.size(), 1)
	assert_eq(str(ev[0].data["refused"]), "")
	assert_eq(str(ev[0].data["pivot"]), "bow")
	assert_eq(str(ev[0].data["direction"]), "starboard")
	assert_eq(int(ev[0].data["from_facing"]), 0)
	assert_eq(int(ev[0].data["to_facing"]), 1)
	assert_ne(ev[0].to_text({}), "")


func test_spring_turn_stern_pivot() -> void:
	# 13.D.2: AS turns on her stern hex, the bow swings.
	var a := _anchored("a", Vector2i(-1, 0), 3, Vector2i(1, 0), 1, "stern")
	assert_eq(a.stern_hex(), Vector2i(0, 0))
	_task(a, "HS", {"turn": "port"})
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 2)
	assert_eq(a.hex_position, Vector2i(-1, 1))
	assert_eq(a.stern_hex(), Vector2i(0, 0))
	assert_eq(str(_springs()[0].data["pivot"]), "stern")


func test_spring_turn_refused_when_held() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_make_ship("b", Vector2i(-1, -1), 3, 1)  # bow (-1, -1), stern (0, -1)
	_task(a, "HS", {"turn": "starboard"})
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0, "the turn is refused")
	assert_eq(a.hex_position, Vector2i(-1, 0))
	var ev: Array = _springs()
	assert_eq(ev.size(), 1)
	assert_string_contains(str(ev[0].data["refused"]), "HMS b")
	assert_eq(ev[0].target_id, "b")
	_no_collision_or_fouling()


func test_spring_turn_refused_without_wind() -> void:
	GameState.environment.wind_speed = 0
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_task(a, "HS", {"turn": "starboard"})
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0)
	assert_eq(str(_springs()[0].data["refused"]), "no wind (13.E.3)")


func test_spring_turn_refused_without_springs() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1, "bow", false)
	_task(a, "HS", {"turn": "starboard"})
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0)
	assert_eq(str(_springs()[0].data["refused"]), "springs not rigged (13.D)")


func test_spring_turn_refused_when_linked() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_make_ship("b", Vector2i(-1, 1), 0, 1)
	sc.add_grapple("a", "b")
	_task(a, "HS", {"turn": "starboard"})
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0)
	assert_eq(str(_springs()[0].data["refused"]), "fouled or grappled (13.D.2)")


func test_spring_turn_refused_at_the_edge() -> void:
	# Bow (8, -15) on the top row facing 0: a starboard turn swings the stern to (8, -16), off the
	# map (rows -15 to 14).
	var a := _anchored("a", Vector2i(8, -15), 0, Vector2i(9, -15), 1)
	_task(a, "HS", {"turn": "starboard"})
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0)
	assert_eq(str(_springs()[0].data["refused"]), "the edge of the map")


func test_spring_turn_refused_into_land() -> void:
	GameState.active_scenario["terrain"] = {"land": [[2, 4]]}
	var a := _anchored("a", Vector2i(2, 5), 0, Vector2i(3, 5), 1)
	_task(a, "HS", {"turn": "starboard"})  # stern swings to (2, 4)
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0)
	assert_eq(str(_springs()[0].data["refused"]), "land")
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.AGROUND).size(), 0, "no grounding")


func test_spring_step_ignores_tasks_of_earlier_turns() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	sc.add_task(a.ship_id, {"code": "HS", "sections": [ShipState.MARINES],
		"params": {"turn": "starboard"}, "started_turn": GameState.current_turn - 1})
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0)
	assert_eq(_springs().size(), 0)


# --- veering in (13.E.2) ------------------------------------------------------------

func test_veer_in() -> void:
	var a := _anchored("a", Vector2i(-2, 0), 0, Vector2i(0, 0), 2, "bow", false, 1)
	_task(a, "VI")
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.hex_position, Vector2i(-1, 0))
	assert_eq(a.stern_hex(), Vector2i(-2, 0))
	assert_eq(int(a.anchor["cable"]), 1)
	assert_eq(int(a.anchor["veered"]), 0)
	var ev: Array = _veers()
	assert_eq(ev.size(), 1)
	assert_eq(str(ev[0].data["refused"]), "")
	assert_eq(int(ev[0].data["cable"]), 1)
	assert_ne(ev[0].to_text({}), "")


func test_veer_in_blocked() -> void:
	var a := _anchored("a", Vector2i(-2, 0), 0, Vector2i(0, 0), 2, "bow", false, 1)
	_make_ship("b", Vector2i(-1, 0), 1, 1)  # bow (-1, 0), stern (-1, -1)
	_task(a, "VI")
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.hex_position, Vector2i(-2, 0), "she stays where she is")
	assert_eq(int(a.anchor["cable"]), 2)
	assert_eq(int(a.anchor["veered"]), 1)
	var ev: Array = _veers()
	assert_eq(ev.size(), 1)
	assert_string_contains(str(ev[0].data["refused"]), "HMS b")
	_no_collision_or_fouling()


func test_veer_in_at_wind_zero() -> void:
	# 13.E.3: ships can veer in at WS 0.
	GameState.environment.wind_speed = 0
	var a := _anchored("a", Vector2i(-2, 0), 0, Vector2i(0, 0), 2, "bow", false, 1)
	_task(a, "VI")
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.hex_position, Vector2i(-1, 0))
	assert_eq(str(_veers()[0].data["refused"]), "")


# --- in the turn loop ---------------------------------------------------------------

## A manual plan of `code` on the marines, stored through the engine's request in PLANNING.
func _plot(ship: ShipState, code: String, params: Dictionary = {}) -> void:
	pc.current_phase = PLANNING
	assert_eq(GameState.crew_task_controller.plot_crew(ship.side, ship.ship_id,
		{"assignments": {ShipState.MARINES: {"code": code, "params": params}}, "orders": {}}), "")


func test_spring_turn_before_movement() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_plot(a, "HS", {"turn": "starboard"})
	# b sails south-east from (-1, -3) through (-1, -2) to (-1, -1), where a's stern swings.
	var b := _make_ship("b", Vector2i(-1, -3), 1, 1, 2)
	sc.set_plotted_movement(b.ship_id, [{"hex": {"q": -1, "r": -2}, "facing": 1},
		{"hex": {"q": -1, "r": -1}, "facing": 1}])
	pc._enter_movement_resolution_phase()
	assert_eq(a.facing, 1, "the spring turn is made before movement")
	assert_eq(_springs().size(), 1)
	assert_eq(str(_springs()[0].data["refused"]), "")
	assert_eq(_logs.size(), 1)
	var log: MovementTypes.ResolutionLog = _logs[0]
	assert_eq(log.get_result("a").final_facing, 1, "the resolver sees the new facing")
	assert_ne(log.get_result("b").final_hex, Vector2i(-1, -1), "a's stern holds the hex")


func test_spring_turn_survives_bear_off_rerun() -> void:
	pc.bear_off_prompt_player_ids = [0] as Array[int]
	var requests: Array = []
	var on_request := func(_player: int, situation: MovementTypes.BearOffSituation) -> void:
		requests.append(situation)
	pc.bear_off_decision_requested.connect(on_request)
	var a := _anchored("a", Vector2i(-1, 10), 0, Vector2i(0, 10), 1)
	_plot(a, "HS", {"turn": "starboard"})
	# The player's ship sails three hexes west into a stopped enemy on (7, 5).
	var mine := _make_ship("mine", Vector2i(10, 5), 3, 0, 7)
	sc.set_plotted_movement(mine.ship_id, [{"hex": {"q": 9, "r": 5}, "facing": 3},
		{"hex": {"q": 8, "r": 5}, "facing": 3}, {"hex": {"q": 7, "r": 5}, "facing": 3}])
	_make_ship("theirs", Vector2i(7, 5), 1, 1, 0)
	pc._enter_movement_resolution_phase()
	assert_eq(_logs.size(), 1)
	assert_false(_logs[0].is_complete(), "paused for the bear-off decision")
	assert_eq(pc.player_submit_bear_off(0, "mine", MovementTypes.BEAR_OFF_COLLIDE), "")
	assert_eq(_logs.size(), 2, "re-run")
	assert_eq(a.facing, 1, "the spring turn stands")
	assert_eq(_logs[1].get_result("a").final_facing, 1)
	assert_eq(_springs().size(), 1, "the spring step ran once")
	pc.bear_off_decision_requested.disconnect(on_request)


# --- in irons (5.D.4a-b, 13.F.3) ----------------------------------------------------

func _irons_events(result: MovementTypes.ShipResolutionResult) -> Array:
	return result.events.filter(func(ev) -> bool:
		return ev.event_type == MovementTypes.ResolutionEventType.IMMOBILIZED)


func _resolver() -> MovementResolver:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	return MovementResolver.new(GameState, rng)


func test_anchored_never_in_irons() -> void:
	# Bow anchor, facing 0 into a wind from 0: WF=L, speed 0.
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1, "bow", false)
	var resolver := _resolver()
	assert_false(resolver._is_in_irons(a, GameState.environment))
	var ships: Array[ShipState] = [a]
	var result: MovementTypes.ShipResolutionResult = resolver.run(ships, GameState.environment).get_result("a")
	assert_false(result.immobilized)
	assert_eq(_irons_events(result).size(), 0)


func test_free_turn_after_cut() -> void:
	var resolver := _resolver()
	var cut := _make_ship("cut", Vector2i(5, 5), 0)
	CrewFixtures.give_tack_crew(cut, 3)
	var plain := _make_ship("plain", Vector2i(5, 9), 0)
	CrewFixtures.give_tack_crew(plain, 3)
	cut.cable_cut_turn = GameState.current_turn - 1
	plain.cable_cut_turn = -1
	assert_false(resolver._is_in_irons(cut, GameState.environment), "5.D.4b: a free g-t")
	assert_true(resolver._is_in_irons(plain, GameState.environment))
	assert_eq(resolver._calculate_tacking_drm(cut, -1, ShipState.STARBOARD),
		resolver._calculate_tacking_drm(plain, -1, ShipState.STARBOARD) - 1, "no +1 for irons (5.D.6)")
	# No turn plotted: she does not remain in irons.
	sc.set_plotted_movement(cut.ship_id, [])
	var ships: Array[ShipState] = [cut]
	var result: MovementTypes.ShipResolutionResult = resolver.run(ships, GameState.environment).get_result("cut")
	assert_false(result.immobilized)
	assert_eq(_irons_events(result).size(), 0)


func test_in_irons_again_next_turn() -> void:
	var resolver := _resolver()
	var ship := _make_ship("cut", Vector2i(5, 5), 0)
	ship.cable_cut_turn = GameState.current_turn - 2
	assert_true(resolver._is_in_irons(ship, GameState.environment))
