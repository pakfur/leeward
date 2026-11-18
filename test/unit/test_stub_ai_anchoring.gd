extends GutTest
## StubAI and anchoring (anchoring spec §11; register §3): a ship that starts anchored stays, rigs
## springs and hauls to bear; it cuts on CUT CABLES, or when a signalled move order finds no enemy
## within 15 hexes; a ship told ANCHOR, or drifting toward land or a `none` edge, prepares an anchor
## and lets it go. Wind from the east (direction 0), speed 3: downwind is west (-1, 0). AI ships are
## player 1's; a 40 x 30 board, anchoring allowed unless stated.

const PLANNING := TurnPhaseController.GamePhase.PLANNING

var stub_ai: StubAI
var sc: ShipStateController
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
	_saved_scenario = GameState.active_scenario
	_saved_env = GameState.environment
	_saved_turn = GameState.current_turn
	_saved_dice = GameState.dice
	_saved_rng = GameState.rng
	_saved_log = GameState.turn_log
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 3
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.phase_controller.current_phase = PLANNING
	GameState.phase_controller.game_result = {}
	GameState.phase_controller.players_ready = {0: false, 1: false}
	GameState.active_scenario = _scenario()
	sc = GameState.ship_controller
	stub_ai = StubAI.new(GameState)


func after_each() -> void:
	GameState.active_scenario = _saved_scenario
	GameState.environment = _saved_env
	GameState.current_turn = _saved_turn
	GameState.rng = _saved_rng
	GameState.dice = _saved_dice
	GameState.turn_log = _saved_log
	GameState.phase_controller.current_phase = TurnPhaseController.GamePhase.SETUP
	GameState.phase_controller._pending_resolution_log = null
	_reset_ships()


func _reset_ships() -> void:
	GameState.ships.clear()
	GameState.ships_by_side.clear()
	if GameState.movement_plotting_controller:
		GameState.movement_plotting_controller.sessions.clear()
		GameState.movement_plotting_controller.ship_sessions.clear()


func _scenario(anchoring: bool = true, terrain: Dictionary = {}) -> Dictionary:
	var s := {"map_bounds": {"width": 40, "height": 30}, "terrain": terrain}
	if anchoring:
		s["anchoring"] = true
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
	assert_true(GameState.add_ship(state))
	return state


## An AI ship anchored by the bow at (0, 0) facing 0 (into the wind), anchor one hex upwind.
func _anchored(springs: bool) -> ShipState:
	var ship := _make_ship("ai", 1, Vector2i(0, 0), 0)
	assert_true(sc.drop_anchor("ai", {"hex": Vector2i(1, 0), "end": "bow", "springs": springs,
		"cable": 1, "veered": 0, "swing_dir": 0, "wind_dir": 0, "turn": 1}))
	return ship


func _task(ship: ShipState, code: String) -> void:
	sc.add_task(ship.ship_id, {"code": code, "sections": [ShipState.MARINES],
		"started_turn": GameState.current_turn})


func _dismasted(bow: Vector2i) -> ShipState:
	var ship := _make_ship("ai", 1, bow, 0)
	ship.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	return ship


func _batteries(ship: ShipState, target: ShipState, hexes: Array[Vector2i], facing: int) -> int:
	return stub_ai._bearing_batteries(hexes, facing, target.occupied_hexes(),
		stub_ai._occupied_except(ship, target), stub_ai._friendly_footprints(ship))


# --- at anchor ----------------------------------------------------------------------

func test_start_anchored_stays_without_signal() -> void:
	var ai := _anchored(true)
	_make_ship("enemy", 0, Vector2i(18, 0), 0)  # range 17
	assert_ne(stub_ai.anchor_order(ai), "cut")


func test_cut_when_signalled_move_and_no_enemy() -> void:
	var ai := _anchored(true)
	var enemy := _make_ship("enemy", 0, Vector2i(18, 0), 0)
	sc.set_standing_order("ai", {"order": "engage"})
	assert_eq(stub_ai.anchor_order(ai), "cut")
	enemy.hex_position = Vector2i(11, 0)  # stern (10, 0): range 10
	assert_ne(stub_ai.anchor_order(ai), "cut")


func test_cut_cables_signal_cuts_at_once() -> void:
	var ai := _anchored(true)
	_make_ship("enemy", 0, Vector2i(4, 0), 0)  # stern (3, 0): range 3
	sc.set_standing_order("ai", {"order": "cut"})
	assert_eq(stub_ai.anchor_order(ai), "cut")


func test_prepare_springs_when_anchored() -> void:
	var ai := _anchored(false)
	assert_eq(stub_ai.anchor_order(ai), "prepare_springs")
	_task(ai, "PBS")
	assert_ne(stub_ai.anchor_order(ai), "prepare_springs", "it continues by rule A2")


func test_haul_to_bear() -> void:
	var ai := _anchored(true)
	var enemy := _make_ship("enemy", 0, Vector2i(4, 0), 1)  # dead ahead
	var choice := stub_ai.haul_choice(ai)
	assert_true(choice in ["turn_starboard", "turn_port"], "hauls round: %s" % choice)
	var turn := AnchorRules.spring_turn(ai, 1 if choice == "turn_starboard" else -1)
	var hexes: Array[Vector2i] = []
	hexes.assign(turn["hexes"])
	assert_gt(_batteries(ai, enemy, hexes, int(turn["facing"])), 0)
	assert_eq(stub_ai.anchor_order(ai), choice)
	enemy.hex_position = Vector2i(0, 4)  # on the beam
	enemy.facing = 0
	assert_gt(_batteries(ai, enemy, ai.occupied_hexes(), ai.facing), 0, "the broadside bears")
	assert_eq(stub_ai.haul_choice(ai), "")


func test_haul_skips_blocked_turn() -> void:
	var ai := _anchored(true)
	_make_ship("enemy", 0, Vector2i(4, 0), 1)
	assert_eq(stub_ai.haul_choice(ai), "turn_starboard", "control: the starboard haul bears best")
	# The starboard turn swings the stern into (0, -1).
	_make_ship("friend", 1, Vector2i(0, -1), 0)
	assert_ne(stub_ai.haul_choice(ai), "turn_starboard")


func test_haul_refused_without_wind() -> void:
	var ai := _anchored(true)
	_make_ship("enemy", 0, Vector2i(4, 0), 1)
	GameState.environment.wind_speed = 0
	assert_eq(stub_ai.haul_choice(ai), "", "springs cannot be used in a calm (13.E.3)")


# --- never cut back into danger -----------------------------------------------------

func test_emergency_anchored_dismasted_ship_never_cuts() -> void:
	var ai := _anchored(true)
	ai.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	sc.set_standing_order("ai", {"order": "engage"})  # no enemy near
	assert_ne(stub_ai.anchor_order(ai), "cut")
	sc.set_standing_order("ai", {"order": "cut"})
	assert_ne(stub_ai.anchor_order(ai), "cut")


func test_cut_cables_not_with_land_to_leeward() -> void:
	GameState.active_scenario = _scenario(true, {"land": [[-4, 0]]})
	var ai := _anchored(true)
	sc.set_standing_order("ai", {"order": "cut"})
	assert_ne(stub_ai.anchor_order(ai), "cut")


func test_cut_cables_in_open_water() -> void:
	var ai := _anchored(true)
	sc.set_standing_order("ai", {"order": "cut"})
	assert_eq(stub_ai.anchor_order(ai), "cut")


# --- emergency anchoring ------------------------------------------------------------

func test_emergency_anchoring() -> void:
	GameState.active_scenario = _scenario(true, {"land": [[-3, 0]]})
	var ai := _dismasted(Vector2i(0, 0))
	assert_true(stub_ai.drift_danger(ai))
	assert_eq(stub_ai.anchor_order(ai), "prepare_bow")
	sc.set_anchor_ready("ai", "bow")
	assert_eq(stub_ai.anchor_order(ai), "anchor")

	GameState.active_scenario = _scenario(true, {"land": [[-8, 0]]})
	assert_false(stub_ai.drift_danger(ai), "land too far to leeward")

	_reset_ships()
	GameState.active_scenario = _scenario(true, {"edges": {"W": "none"}})
	ai = _dismasted(Vector2i(-17, 0))  # stern (-18, 0); the W edge lies west of column -20
	assert_true(stub_ai.drift_danger(ai), "a none edge to leeward")
	GameState.active_scenario = _scenario(true, {})
	assert_false(stub_ai.drift_danger(ai), "an open edge holds her")

	_reset_ships()
	GameState.active_scenario = _scenario(true, {"land": [[-3, 0]], "boundaries": [
		{"name": "reef", "kind": "open", "sides": [[[-1, 0], [-2, 0]]]}]})
	ai = _dismasted(Vector2i(0, 0))
	assert_false(stub_ai.drift_danger(ai), "an open edge between her and the land")


func test_no_anchoring_without_permission() -> void:
	GameState.active_scenario = _scenario(false, {"land": [[-3, 0]]})
	var ai := _dismasted(Vector2i(0, 0))
	assert_true(stub_ai.drift_danger(ai))
	assert_false(stub_ai.wants_to_anchor(ai))
	assert_eq(stub_ai.anchor_order(ai), "")


func test_no_drift_danger_under_way() -> void:
	GameState.active_scenario = _scenario(true, {"land": [[-3, 0]]})
	var ai := _make_ship("ai", 1, Vector2i(0, 0), 3)  # running before the wind
	assert_false(stub_ai.drift_danger(ai))
	assert_eq(stub_ai.anchor_order(ai), "")


# --- the ANCHOR signal in the turn loop ---------------------------------------------

func test_anchor_signal_slows_and_anchors() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	GameState.rng = rng
	GameState.dice = Dice.new(rng)
	# Deceleration 3 for maneuverability C: from speed 2 she may plot nothing.
	var ai := _make_ship("ai", 1, Vector2i(0, 0), 3, 2)
	sc.set_standing_order("ai", {"order": "anchor"})
	sc.set_anchor_ready("ai", "bow")
	assert_eq(stub_ai._get_strategy(ai), "anchor")
	stub_ai.plot_all_ai_ships()
	assert_true(bool(ai.plotted_actions.get("movement_plotted", false)), "a course is stored")
	assert_eq((ai.plotted_actions.get("movement", []) as Array).size(), 0, "an empty course")
	var codes: Array = []
	var plan: Dictionary = GameState.crew_task_controller.current_plan("ai")
	for s in plan["assignments"]:
		codes.append(str(plan["assignments"][s].get("code", "")))
	assert_true(codes.has("A"), "the crew lets go the anchor: %s" % [codes])
	var pc: TurnPhaseController = GameState.phase_controller
	pc.players_ready = {0: true, 1: true}
	GameState.crew_task_controller.finalize_plots()
	pc._enter_movement_resolution_phase()
	pc.on_playback_completed()  # applies the moves, then combat (none) and DRIFT_CALCULATION
	assert_true(ai.is_anchored(), "anchored")


func test_strategy_anchor_order_without_permission_engages() -> void:
	GameState.active_scenario = _scenario(false)
	var ai := _make_ship("ai", 1, Vector2i(0, 0), 3, 2)
	sc.set_standing_order("ai", {"order": "anchor"})
	assert_eq(stub_ai._get_strategy(ai), "engage")
	sc.set_standing_order("ai", {"order": "cut"})
	assert_eq(stub_ai._get_strategy(ai), "engage")


func test_assign_crew_sets_anchor_order() -> void:
	var ai := _anchored(false)
	stub_ai.assign_crew()
	var orders: Dictionary = ai.plotted_actions.get("crew_orders", {})
	assert_eq(str(orders.get("anchor", "?")), stub_ai.anchor_order(ai))
	assert_eq(str(orders["anchor"]), "prepare_springs")


# --- fix wave -----------------------------------------------------------------------

## Ruling 2026-11-18: under an escape posture an anchored AI ship cuts her cable (an anchored ship
## cannot escape), unless her lee is dangerous or she cannot make way.
func test_escape_posture_cuts_the_cable() -> void:
	var escape := {"escape": {"1": {}}, "ai": {"1": "escape"}}
	GameState.active_scenario = _scenario().merged(escape)
	var ai := _anchored(true)
	_make_ship("enemy", 0, Vector2i(4, 0), 0)  # range 3: no move-order cut
	assert_eq(stub_ai.anchor_order(ai), "cut")
	GameState.active_scenario = _scenario(true, {"land": [[-4, 0]]}).merged(escape)
	assert_ne(stub_ai.anchor_order(ai), "cut", "not with land to leeward")
	GameState.active_scenario = _scenario().merged(escape)
	ai.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_ne(stub_ai.anchor_order(ai), "cut", "not when she cannot make way")


func test_escape_posture_cuts_on_a_disengage_order() -> void:
	GameState.active_scenario = _scenario().merged({"escape": {"1": {}}})
	var ai := _anchored(true)
	_make_ship("enemy", 0, Vector2i(4, 0), 0)
	assert_ne(stub_ai.anchor_order(ai), "cut", "control: no posture, enemy near")
	sc.set_standing_order("ai", {"order": "disengage"})
	assert_eq(stub_ai.anchor_order(ai), "cut")


## The haul's occupancy is the ships on the map: a wreck taken off the map does not block a turn.
func test_haul_ignores_ships_off_the_map() -> void:
	var ai := _anchored(true)
	_make_ship("enemy", 0, Vector2i(4, 0), 1)
	var wreck := _make_ship("friend", 1, Vector2i(0, -1), 0)
	wreck.status = ShipState.Status.DESTROYED
	wreck.removed_from_map = true
	assert_eq(stub_ai.haul_choice(ai), "turn_starboard")
