extends GutTest
## The springs step at the start of MOVEMENT_RESOLUTION (Close Action 13.D.2-3, 13.E.2; anchoring
## spec §5): AnchorController.resolve_spring_step turns a ship anchored with springs (HS) or veers
## her in (VI) before any ship moves, and is refused, with no collision and no die, when the hex is
## held, land or off the map. And the in-irons exceptions (5.D.4a-b, 13.F.3; spec §6): an anchored
## ship is never in irons, nor is a ship in the g-t after she cuts her cable.
## Wind from the east (direction 0), speed 3: downwind is west (-1, 0); a bow anchor's proper facing
## is 0, a stern anchor's 3.

const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const GameControllerScript = preload("res://scripts/core/game_controller.gd")
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


func test_veer_in_refused_when_linked() -> void:
	# A fouled or grappled anchored ship holds, as in V.A.
	var a := _anchored("a", Vector2i(-2, 0), 0, Vector2i(0, 0), 2, "bow", false, 1)
	_make_ship("b", Vector2i(-2, 1), 0, 1)
	sc.add_grapple("a", "b")
	_task(a, "VI")
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.hex_position, Vector2i(-2, 0))
	assert_eq(int(a.anchor["cable"]), 2)
	assert_eq(int(a.anchor["veered"]), 1)
	assert_eq(str(_veers()[0].data["refused"]), AnchorController.REFUSED_LINKED)


func test_spring_step_skips_aground_ships() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	sc.set_aground(a.ship_id, GameState.current_turn - 1)
	_task(a, "HS", {"turn": "starboard"})
	var b := _anchored("b", Vector2i(-2, 5), 0, Vector2i(0, 5), 2, "bow", false, 1)
	sc.set_aground(b.ship_id, GameState.current_turn - 1)
	_task(b, "VI")
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0)
	assert_eq(b.hex_position, Vector2i(-2, 5))
	assert_eq(_springs().size() + _veers().size(), 0, "nothing logged")


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


# --- review fixes -------------------------------------------------------------------

func test_veer_in_rechecks_nothing_veered() -> void:
	var a := _anchored("a", Vector2i(-2, 0), 0, Vector2i(0, 0), 2, "bow", false, 0)
	_task(a, "VI")
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.hex_position, Vector2i(-2, 0))
	assert_eq(int(a.anchor["cable"]), 2)
	assert_eq(str(_veers()[0].data["refused"]), AnchorController.REFUSED_NOTHING_TO_VEER_IN)


func test_veer_in_refused_up_front_when_linked() -> void:
	var a := _anchored("a", Vector2i(-2, 0), 0, Vector2i(0, 0), 2, "bow", false, 1)
	_make_ship("b", Vector2i(-2, 1), 0, 1)
	assert_eq(AnchorRules.refusal(a, "VI", {}, {"wind_speed": 3}, []), "")
	sc.add_grapple("a", "b")
	assert_eq(AnchorRules.refusal(a, "VI", {}, {"wind_speed": 3}, []), AnchorRules.R_VI_LINKED)


## Spec §1, 13.D.1: a springs ship keeps her WF, so V.A after the springs step leaves her on her
## new bearing (no swing back, no move, no die).
func test_riding_keeps_the_spring_turned_bearing() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_task(a, "HS", {"turn": "starboard"})
	var s := _anchored("s", Vector2i(-1, 6), 3, Vector2i(1, 6), 1, "stern")
	_task(s, "HS", {"turn": "port"})
	anchors.resolve_spring_step(MOVE)
	anchors.resolve_anchoring(TurnPhaseController.GamePhase.DRIFT_CALCULATION)
	assert_eq(a.facing, 1)
	assert_eq(a.occupied_hexes(), [Vector2i(-1, 0), Vector2i(-1, -1)] as Array[Vector2i])
	assert_eq(s.facing, 2)
	assert_eq(s.occupied_hexes(), [Vector2i(-1, 7), Vector2i(0, 6)] as Array[Vector2i])
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.ANCHOR_MOVE).size(), 0)


func test_spring_step_ship_ids_names_the_ships_moved() -> void:
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1)
	_task(a, "HS", {"turn": "starboard"})
	var c := _anchored("c", Vector2i(-2, 6), 0, Vector2i(0, 6), 2, "bow", false, 1)
	_task(c, "VI")
	var b := _anchored("b", Vector2i(-1, 12), 0, Vector2i(0, 12), 1, "bow", false)
	_task(b, "HS", {"turn": "port"})  # refused: no springs
	anchors.resolve_spring_step(MOVE)
	assert_eq(GameControllerScript.spring_step_ship_ids(GameState.turn_log), ["a", "c"] as Array[String])
	assert_eq(GameControllerScript.spring_step_ship_ids(null), [] as Array[String])


func test_irons_excused() -> void:
	var env: EnvironmentState = GameState.environment
	var turn := GameState.current_turn
	var plain := _make_ship("plain", Vector2i(5, 5), 0)
	assert_false(IronsRules.excused(plain, env, turn))
	plain.cable_cut_turn = turn - 1
	assert_true(IronsRules.excused(plain, env, turn), "5.D.4b: the g-t after the cut")
	plain.cable_cut_turn = turn - 2
	assert_false(IronsRules.excused(plain, env, turn))
	var a := _anchored("a", Vector2i(-1, 0), 0, Vector2i(0, 0), 1, "bow", false)
	assert_true(IronsRules.excused(a, env, turn), "5.D.4a: anchored")
	env.calm_ended_turn = turn
	assert_true(IronsRules.excused(_make_ship("calm", Vector2i(5, 9), 0), env, turn), "3.D.4")
	# The planning note follows it: head to wind the g-t after a cut cable is not in irons.
	plain.cable_cut_turn = turn - 1
	assert_eq(CourseView.course_note({}, "C", "L", IronsRules.excused(plain, null, turn)),
		PlanningText.HEAD_TO_WIND_NOTE)
	plain.cable_cut_turn = -1
	assert_eq(CourseView.course_note({}, "C", "L", IronsRules.excused(plain, null, turn)),
		PlanningText.IRONS_NOTE)


# --- fix wave ------------------------------------------------------------------------

## I1: a stored course is never executed by an anchored ship: the Developer UI drop clears it, and
## the resolver ignores any plot of an anchored ship.
func test_anchored_ship_does_not_sail_a_stored_course() -> void:
	var a := _make_ship("a", Vector2i(5, 5), 0, 0, 2)
	sc.set_plotted_movement(a.ship_id, [{"hex": {"q": 6, "r": 5}, "facing": 0},
		{"hex": {"q": 7, "r": 5}, "facing": 0}])
	assert_eq(anchors.drop_now("a", "bow", false, PLANNING), "")
	assert_eq(a.plotted_actions.get("movement", []), [], "the drop clears her course")
	var before: Array[Vector2i] = a.occupied_hexes()
	var resolver := _resolver()
	var ships: Array[ShipState] = [a]
	resolver.apply_results(resolver.run(ships, GameState.environment), ships)
	assert_eq(a.occupied_hexes(), before, "she rides to her anchor")


func test_resolver_ignores_the_plot_of_an_anchored_ship() -> void:
	var a := _anchored("a", Vector2i(5, 5), 0, Vector2i(6, 5), 1, "bow", false)
	sc.set_plotted_movement(a.ship_id, [{"hex": {"q": 6, "r": 5}, "facing": 0}])
	var before: Array[Vector2i] = a.occupied_hexes()
	var resolver := _resolver()
	var ships: Array[ShipState] = [a]
	resolver.apply_results(resolver.run(ships, GameState.environment), ships)
	assert_eq(a.occupied_hexes(), before)


## A veer in after a wind shift (the anchor laid in a wind from 0, the wind now from 1): the springs
## step lays the footprint in the new wind on her old facing (oblique), and V.A then swings her and
## lays it again.
func test_veer_in_after_a_wind_shift() -> void:
	var a := _anchored("a", Vector2i(-2, 0), 0, Vector2i(0, 0), 2, "bow", false, 1)
	GameState.environment.wind_direction = 1  # downwind is now 4 (NW, (0, -1))
	_task(a, "VI")
	anchors.resolve_spring_step(MOVE)
	assert_eq(a.facing, 0, "no swing in the springs step")
	assert_eq(a.occupied_hexes(), [Vector2i(0, -1), Vector2i(-1, -1)] as Array[Vector2i],
		"the bow 1 hex downwind of the anchor in the new wind, the hull on her old facing")
	assert_eq(int(a.anchor["cable"]), 1)
	anchors.resolve_anchoring(TurnPhaseController.GamePhase.DRIFT_CALCULATION)
	assert_eq(a.facing, 1, "V.A swings her to the new wind")
	assert_eq(a.occupied_hexes(), [Vector2i(0, -1), Vector2i(0, -2)] as Array[Vector2i])


## Spec §8, 7.C.12c, through the real turn order: on the g-t she lets go (V.B, after combat) her guns
## get no "anchored" +1; on the g-t she cuts (V.B again) they still do.
func test_anchored_bonus_timing_through_the_turn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	GameState.dice = Dice.new(rng)  # drift rolls: real dice (_dice stays empty)
	var f := _make_ship("f", Vector2i(5, 5), 0, 0)
	var t := _make_ship("t", Vector2i(5, 5) + HexGrid.DIRECTIONS[1] * 3, 0, 1)
	for s in [f, t]:
		s.ship.gun_factors = {"lg": 6, "mg": 0, "cr": 4}
	f.anchor_ready = "bow"

	assert_eq(_turn_bonus(f, "A"), 0, "the drop g-t: not yet anchored at the combat step")
	assert_true(f.is_anchored(), "anchored in V.B")

	GameState.current_turn += 1
	assert_eq(_turn_bonus(f, "AX"), 1, "the cut g-t: still anchored at the combat step")
	assert_false(f.is_anchored(), "the cable cut in V.B")
	assert_eq(f.cable_cut_turn, GameState.current_turn)


## Plots `code` on f's marines, runs the g-t from movement to the combat declaration, returns f's
## "anchored" modifier on her starboard broadside at t, then fires nothing and plays the g-t on to
## POST_COMBAT (drift and the anchoring step included).
func _turn_bonus(f: ShipState, code: String) -> int:
	# Fixture: put the target back on f's starboard beam, 3 hexes off (drift moved them last g-t).
	var t: ShipState = GameState.get_ship("t")
	t.hex_position = f.hex_position + HexGrid.DIRECTIONS[1] * 3
	t.facing = 0
	_plot(f, code)
	sc.set_plotted_movement("f", [])
	sc.set_plotted_movement("t", [])
	pc.players_ready = {0: true, 1: true}
	GameState.crew_task_controller.finalize_plots()
	pc._enter_movement_resolution_phase()
	pc.on_playback_completed()
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION)
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE)
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "f"
	order.side = ShipState.STARBOARD
	order.target_id = "t"
	order.ammo = "round"
	order.aim = "low"
	order.battery = "full"
	var p: GunneryTypes.ShotPreview = GameState.gunnery_calculator.preview(order)
	assert_true(p.can_fire, p.reason)
	var bonus := 0
	for m in p.modifiers:
		if m["name"] == "anchored":
			bonus = int(m["value"])
	assert_eq(pc.player_submit_fire_orders(0, []), "")
	if pc.combat_step == TurnPhaseController.CombatStep.DECLARE:  # unless the stub AI played side 1
		assert_eq(pc.player_submit_fire_orders(1, []), "")
	pc.on_combat_playback_completed()
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT)
	return bonus


func test_aground_ship_does_not_sail_a_stored_course() -> void:
	var a := _make_ship("a", Vector2i(5, 5), 0, 0, 2)
	a.aground = true
	a.aground_turn = GameState.current_turn - 1
	sc.set_plotted_movement(a.ship_id, [{"hex": {"q": 6, "r": 5}, "facing": 0},
		{"hex": {"q": 7, "r": 5}, "facing": 0}])
	var before: Array[Vector2i] = a.occupied_hexes()
	var resolver := _resolver()
	var ships: Array[ShipState] = [a]
	resolver.apply_results(resolver.run(ships, GameState.environment), ships)
	assert_eq(a.occupied_hexes(), before, "an aground ship stays put")
