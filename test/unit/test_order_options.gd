extends GutTest
## TurnPhaseController.order_options (board planning piece 2): the read-only query behind the orders
## ring. Each order's "error" is the one its request returns; the request's checks are shared.

const PHASES := TurnPhaseController.GamePhase

var pc: TurnPhaseController
var a: ShipState
var b: ShipState
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_logs: Dictionary
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _old_turn: int
var _old_groups: Dictionary
var _old_signals: Array
var _old_players: Dictionary
var _old_pc_turn: int


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_logs = GameState.turn_logs
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	_old_turn = GameState.current_turn
	_old_groups = GameState.groups
	_old_signals = GameState.signals
	GameState.dice = Dice.new(GameState.rng)
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.turn_logs = {}
	GameState.active_scenario = {
		"optional_rules": {"voluntary_surrender": true},
		"escape": {"0": {"from_turn": 1, "edges": ["W"], "share": 0.5}},
		"year": 1805,
	}
	GameState.groups = {0: {"van": ["a_id"]}}
	_old_players = GameState.players
	GameState.players = {0: PlayerState.from_dict({"id": 0, "side": 0}), 1: PlayerState.from_dict({"id": 1, "side": 1})}
	_old_pc_turn = pc.current_turn
	pc.current_turn = 1
	GameState.signals = []
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 1
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	a = _make_ship("a_id", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_id", 1, Vector2i(-1, 1), 3)
	pc.current_phase = PHASES.PLANNING
	pc.players_ready = {0: false, 1: false}
	pc.game_result = {}


func after_each() -> void:
	pc.game_result = {}
	pc.current_phase = PHASES.SETUP
	pc.players_ready = {}
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.turn_logs = _old_logs
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.current_turn = _old_turn
	GameState.groups = _old_groups
	GameState.signals = _old_signals
	GameState.players = _old_players
	pc.current_turn = _old_pc_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


## A frigate_38 (rigging [5, 5, 6, 6], hull [5, 5, 5, 6], crew [3, 3, 3, 3], marines 2) at CQ D.
func _make_ship(id: String, side: int, bow: Vector2i, facing: int) -> ShipState:
	var def := DataManager.get_ship_definition("frigate_38")
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": "frigate_38", "name": def.name, "nationality": "British",
		"rating": def.rating, "class": def.ship_class,
		"maneuverability": def.maneuverability, "speed_type": def.speed_type,
		"rigging_hp": def.rigging_hp, "hull_hp": def.hull_hp,
		"crew_count": def.crew_count, "marine_count": def.marine_count,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
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
	state.crew_quality = "D"
	state.starting_crew_quality = "D"
	state.morale_rating = 4
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


func _opts() -> Dictionary:
	return pc.order_options(0, "a_id")


func _fwd(q: int, r: int, facing: int) -> MovementTypes.PlotStep:
	return MovementTypes.PlotStep.new(Vector2i(q, r), facing, MovementTypes.MoveType.FORWARD)


func _store(ship: ShipState, steps: Array[MovementTypes.PlotStep]) -> void:
	GameState.ship_controller.set_plotted_movement(ship.ship_id, DefaultCourse.as_dicts(steps))


func test_unknown_or_foreign_ship_gives_nothing() -> void:
	assert_eq(pc.order_options(0, "nope"), {})
	assert_eq(pc.order_options(0, "b_id"), {})
	assert_eq(pc.order_options(1, "a_id"), {})


# --- lead ---

func test_lead_allowed_then_request_agrees() -> void:
	var lead: Dictionary = _opts()["lead"]
	assert_eq(lead["error"], "")
	assert_false(lead["on"])
	assert_eq(pc.player_set_cast_lead(0, "a_id", true), "")
	assert_true(_opts()["lead"]["on"])


func test_lead_refused_matches_request() -> void:
	pc.players_ready[0] = true
	var err: String = _opts()["lead"]["error"]
	assert_ne(err, "")
	assert_eq(pc.player_set_cast_lead(0, "a_id", true), err)
	assert_false(a.casts_lead())


func test_lead_refused_for_a_ship_that_cannot_plot() -> void:
	a.fouled_with = "b_id"
	var err: String = _opts()["lead"]["error"]
	assert_ne(err, "")
	assert_eq(pc.player_set_cast_lead(0, "a_id", true), err)


func test_lead_over_two_mp_course_gives_the_plan_error() -> void:
	_store(a, [_fwd(1, 0, 0), _fwd(2, 0, 0), _fwd(3, 0, 0)] as Array[MovementTypes.PlotStep])
	var err: String = _opts()["lead"]["error"]
	assert_string_contains(err, "13.G.4a")
	# It is the string plan_errors gives once the lead is ordered.
	assert_eq(pc.player_set_cast_lead(0, "a_id", true), "")
	assert_eq(pc.plan_errors(0)["a_id"], err)
	# Turning it off is always possible.
	assert_eq(_opts()["lead"]["error"], "")


func test_lead_short_course_allowed() -> void:
	_store(a, [_fwd(1, 0, 0), _fwd(2, 0, 0)] as Array[MovementTypes.PlotStep])
	assert_eq(_opts()["lead"]["error"], "")


# --- escape ---

func test_escape_allowed_then_request_agrees() -> void:
	var esc: Dictionary = _opts()["escape"]
	assert_true(esc["shown"])
	assert_false(esc["on"])
	assert_eq(esc["error"], "")
	assert_eq(pc.player_declare_escape(0, "a_id", true), "")
	assert_true(_opts()["escape"]["on"])
	assert_eq(_opts()["escape"]["error"], "")  # withdrawing is allowed


func test_escape_refused_before_its_turn_matches_request() -> void:
	GameState.active_scenario["escape"] = {"0": {"from_turn": 5, "edges": ["W"]}}
	var esc: Dictionary = _opts()["escape"]
	assert_true(esc["shown"])
	assert_ne(esc["error"], "")
	assert_eq(pc.player_declare_escape(0, "a_id", true), esc["error"])
	assert_false(a.escape_declared)


func test_escape_refused_when_plan_submitted() -> void:
	pc.players_ready[0] = true
	var err: String = _opts()["escape"]["error"]
	assert_ne(err, "")
	assert_eq(pc.player_declare_escape(0, "a_id", true), err)
	assert_false(a.escape_declared)


# --- surrender and rally ---

func test_surrender_refused_when_not_eligible_matches_request() -> void:
	var s: Dictionary = _opts()["surrender"]
	assert_true(s["shown"])
	assert_ne(s["error"], "")
	assert_eq(pc.player_surrender(0, "a_id", true), s["error"])
	assert_false(a.surrender_ordered)
	assert_false(_opts()["rally"]["shown"])


func test_surrender_allowed_when_eligible() -> void:
	a.crew_quality = "F"
	var s: Dictionary = _opts()["surrender"]
	assert_eq(s["error"], "")
	assert_false(s["on"])
	assert_eq(pc.player_surrender(0, "a_id", true), "")
	var after: Dictionary = _opts()["surrender"]
	assert_true(after["on"])
	assert_eq(after["error"], "")  # withdrawing is allowed


func test_rally_shown_for_a_surrendered_ship() -> void:
	a.crew_quality = "F"
	a.surrendered = true
	a.surrenders = 1
	a.status = ShipState.Status.STRUCK
	var o := _opts()
	assert_false(o["surrender"]["shown"])
	assert_true(o["rally"]["shown"])
	assert_eq(o["rally"]["error"], "")


func test_rally_refused_matches_request() -> void:
	a.surrendered = true
	a.surrenders = 1
	a.status = ShipState.Status.STRUCK
	a.rally_turn = 1
	var err: String = _opts()["rally"]["error"]
	assert_ne(err, "")
	assert_eq(pc.player_rally(0, "a_id"), err)
	assert_eq(a.rally_turn, 1)


func test_hidden_when_scenario_has_none() -> void:
	GameState.active_scenario = {}
	var o := _opts()
	assert_false(o["escape"]["shown"])
	assert_false(o["surrender"]["shown"])
	assert_false(o["rally"]["shown"])
	assert_ne(o["surrender"]["error"], "")
	assert_eq(pc.player_surrender(0, "a_id", true), o["surrender"]["error"])
	assert_ne(o["escape"]["error"], "")
	assert_eq(pc.player_declare_escape(0, "a_id", true), o["escape"]["error"])


# --- signal ---

func test_signal_allowed_then_request_agrees() -> void:
	var sig: Dictionary = _opts()["signal"]
	assert_eq(sig["error"], "")
	assert_eq(sig["pending"], {})
	assert_eq(pc.player_send_signal(0, "a_id", {"kind": "fleet", "name": ""}, "engage"), "")
	assert_ne(_opts()["signal"]["pending"], {})


func test_signal_refused_matches_request() -> void:
	a.rigging_current_hp = [0, 0, 0, 0] as Array[int]  # dismasted
	var err: String = _opts()["signal"]["error"]
	assert_string_contains(err, "11.B.2b")
	assert_eq(pc.player_send_signal(0, "a_id", {"kind": "fleet", "name": ""}, "engage"), err)
	assert_eq(GameState.signals.size(), 0)


func test_signal_refused_when_halyards_cut() -> void:
	a.critical_effects.append({"id": "signal_halyards_cut", "turn": 1})
	var err: String = _opts()["signal"]["error"]
	assert_string_contains(err, "11.B.2c")
	assert_eq(pc.player_send_signal(0, "a_id", {"kind": "fleet", "name": ""}, "engage"), err)


func test_signal_refused_in_the_wrong_phase() -> void:
	pc.current_phase = PHASES.MOVEMENT_RESOLUTION
	var err: String = _opts()["signal"]["error"]
	assert_ne(err, "")
	assert_eq(pc.player_send_signal(0, "a_id", {"kind": "fleet", "name": ""}, "engage"), err)


func test_signal_addresses_and_limit() -> void:
	var c := _make_ship("c_id", 0, Vector2i(3, 0), 0)
	c.ship.ship_name = "Cee"
	var sig: Dictionary = _opts()["signal"]
	assert_eq(sig["limit"], SignalText.limit(a, 1805))
	var addresses: Array = sig["addresses"]
	assert_eq(addresses[0], {"kind": "fleet", "name": "", "label": "Fleet"})
	assert_eq(addresses[1], {"kind": "group", "name": "van", "label": "van"})
	var ships := addresses.filter(func(x): return x["kind"] == "ship")
	assert_eq(ships.size(), 1)  # own side only, and not the sender herself: c_id
	assert_eq(ships.map(func(x): return x["name"]), ["c_id"])
	assert_eq(ships[0]["label"], "Cee")
	c.status = ShipState.Status.STRUCK
	var after: Array = _opts()["signal"]["addresses"].filter(func(x): return x["kind"] == "ship")
	assert_eq(after.size(), 0)


# --- read only ---

func test_read_only() -> void:
	a.crew_quality = "F"
	pc.player_send_signal(0, "a_id", {"kind": "fleet", "name": ""}, "engage")
	var before_a := a.serialize()
	var before_b := b.serialize()
	var events := GameState.turn_log.events.size()
	var signals := GameState.signals.size()
	var ready := pc.players_ready.duplicate()
	_opts()
	_opts()
	assert_eq(a.serialize(), before_a)
	assert_eq(b.serialize(), before_b)
	assert_eq(GameState.turn_log.events.size(), events)
	assert_eq(GameState.signals.size(), signals)
	assert_eq(pc.players_ready, ready)
