extends GutTest
## 14.B.3-4 rallying (sub-project 7, spec §2.4): a surrendered ship's one morale check a g-t in
## PLANNING (pass: she is back in play and plots this turn; fail: her CQ falls; fail at G: struck for
## good), the second surrender after a rally, readiness of a player who can only rally, and the
## Developer requests.

const PHASES := TurnPhaseController.GamePhase
const PHASE := TurnPhaseController.GamePhase.MORALE_CHECK

var pc: TurnPhaseController
var a: ShipState
var b: ShipState
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
	DataManager.load_ship_definitions()


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
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 1
	pc.current_turn = 1
	pc.human_player_ids = []
	pc.ai_player_ids = []
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	a = _make_ship("a_id", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_id", 1, Vector2i(-1, 1), 3)
	pc.current_phase = PHASES.PLANNING
	pc.players_ready = {0: false, 1: false}
	pc.game_result = {}
	_surrender(a)


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


## A frigate_38 at CQ D, MR 4.
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


## Orders the ship's surrender (CQ F makes her eligible), strikes her at MORALE_CHECK, then opens
## the PLANNING of g-t 2 with her crew back at CQ D.
func _surrender(ship: ShipState) -> void:
	ship.crew_quality = "F"
	assert_eq(pc.player_surrender(ship.side, ship.ship_id), "", "the order is accepted")
	GameState.morale_controller.resolve_phase(PHASE)
	assert_true(ship.can_rally(), "she has surrendered")
	ship.crew_quality = "D"
	_planning(2)


func _planning(turn: int) -> void:
	pc.current_phase = PHASES.PLANNING
	pc.players_ready = {0: false, 1: false}
	GameState.current_turn = turn
	pc.current_turn = turn


func _rallies() -> Array[PhaseEvents.PhaseEvent]:
	return GameState.turn_log.of_type(PhaseEvents.Type.RALLY)


func test_rally_passes() -> void:
	_dice.queue([4])
	assert_eq(pc.player_rally(0, "a_id"), "")
	assert_eq(a.status, ShipState.Status.ACTIVE)
	assert_false(a.surrendered)
	assert_eq(a.surrenders, 1)
	assert_eq(a.rally_turn, 2)
	var ev := _rallies()[0]
	assert_eq(ev.ship_id, "a_id")
	assert_eq(ev.data["passed"], true)
	assert_eq(int(ev.data["roll"]), 4)
	assert_eq(int(ev.data["rating"]), 4)


func test_rally_fails_and_lowers_quality() -> void:
	_dice.queue([3])
	assert_eq(pc.player_rally(0, "a_id"), "")
	assert_true(a.is_struck())
	assert_true(a.surrendered)
	assert_eq(a.crew_quality, "E")
	var ev := _rallies()[0]
	assert_eq(ev.data["passed"], false)
	assert_eq(str(ev.data["quality"]), "E")


func test_rally_fails_at_g_for_good() -> void:
	a.crew_quality = "G"
	_dice.queue([3])
	assert_eq(pc.player_rally(0, "a_id"), "")
	assert_false(a.surrendered)
	assert_true(a.is_struck())
	assert_eq(_rallies()[0].data.get("breaks", false), true)
	assert_false(_rallies()[0].data.has("quality"))
	_planning(3)
	var why := pc.player_rally(0, "a_id")
	assert_true(why.contains("has not surrendered") or why.contains("for good"), why)
	assert_eq(_rallies().size(), 1, "no second roll")


func test_one_attempt_per_turn() -> void:
	_dice.queue([3])
	assert_eq(pc.player_rally(0, "a_id"), "")
	assert_string_contains(pc.player_rally(0, "a_id"), "this turn")
	assert_eq(_dice.remaining(), 0)
	assert_eq(_rallies().size(), 1, "the refused attempt rolls nothing")
	_planning(3)
	_dice.queue([3])
	assert_eq(pc.player_rally(0, "a_id"), "", "a new g-t, a new attempt")
	assert_eq(_rallies().size(), 2)


func test_rally_request_checks() -> void:
	GameState.active_scenario = {}
	assert_string_contains(pc.player_rally(0, "a_id"), "not used")
	GameState.active_scenario = {"optional_rules": {"voluntary_surrender": true}}
	pc.current_phase = PHASES.COMBAT_RESOLUTION
	assert_string_contains(pc.player_rally(0, "a_id"), "planning phase")
	pc.current_phase = PHASES.PLANNING
	assert_string_contains(pc.player_rally(1, "a_id"), "not this player's")
	pc.players_ready[0] = true
	assert_string_contains(pc.player_rally(0, "a_id"), "already submitted")
	pc.players_ready[0] = false
	assert_string_contains(pc.player_rally(1, "b_id"), "has not surrendered")
	assert_eq(_rallies().size(), 0)
	assert_eq(a.rally_turn, -1, "a refused request records no attempt")


func test_captured_ship_cannot_rally() -> void:
	GameState.ship_controller.set_status("a_id", ShipState.Status.CAPTURED)
	assert_string_contains(pc.player_rally(0, "a_id"), "captured")
	assert_false(a.surrendered)
	assert_eq(_rallies().size(), 0)


func test_rallied_ship_plots_this_turn() -> void:
	pc.human_player_ids = [0]
	a.speed = 2
	_dice.queue([6])
	assert_eq(pc.player_rally(0, "a_id"), "")
	assert_true(pc.planning_snapshot.has("a_id"), "her planning start state is recorded")
	assert_true(DefaultCourse.can_move(GameState, a))
	assert_eq(pc.plan_errors(0), {})


func test_ai_rallied_ship_gets_no_snapshot() -> void:
	pc.human_player_ids = []
	_dice.queue([6])
	assert_eq(pc.player_rally(0, "a_id"), "")
	assert_false(pc.planning_snapshot.has("a_id"))


func test_rally_then_second_surrender_is_permanent() -> void:
	_dice.queue([6])
	assert_eq(pc.player_rally(0, "a_id"), "")
	a.crew_quality = "F"
	assert_eq(pc.player_surrender(0, "a_id"), "")
	GameState.morale_controller.resolve_phase(PHASE)
	var surrenders := GameState.turn_log.of_type(PhaseEvents.Type.SURRENDER)
	assert_eq(surrenders[surrenders.size() - 1].data["permanent"], true)
	assert_false(a.can_rally())


func test_rallied_ship_scores_by_sections() -> void:
	_dice.queue([6])
	assert_eq(pc.player_rally(0, "a_id"), "")
	var full: float = a.ship.point_value(a.starting_crew_quality, a.original_morale_rating())
	assert_lt(GameState.victory_controller.points_lost(a), full, "no longer lost as a whole")


func test_rallyable_human_is_not_auto_ready() -> void:
	pc.ai_player_ids = [1]
	pc._auto_ready_players()
	assert_eq(pc.players_ready[0], false, "player 0 can still rally her")
	assert_eq(pc.players_ready[1], true, "the AI player")
	pc.players_ready = {0: false, 1: false}
	GameState.active_scenario = {}
	pc._auto_ready_players()
	assert_eq(pc.players_ready[0], true, "the option off: nothing to do")
	GameState.active_scenario = {"optional_rules": {"voluntary_surrender": true}}
	pc.players_ready = {0: false, 1: false}
	GameState.ship_controller.end_surrender("a_id")
	pc._auto_ready_players()
	assert_eq(pc.players_ready[0], true, "struck for good")


func test_rallyable_exception_is_planning_only() -> void:
	pc.current_phase = PHASES.POST_COMBAT
	pc.ended_turn = {0: false, 1: false}
	pc._auto_ready_players()
	assert_eq(pc.ended_turn[0], true, "End Turn never waits on a ship that can only rally")
	pc.ended_turn = {}


func test_dev_commands_reach_the_requests() -> void:
	var c := _make_ship("c_id", 0, Vector2i(5, 5), 0)
	c.crew_quality = "F"
	assert_eq(GameState.dev_commands.surrender_ship("c_id"), "")
	assert_true(c.surrender_ordered)
	assert_eq(GameState.dev_commands.surrender_ship("c_id", false), "")
	assert_false(c.surrender_ordered)
	_dice.queue([6])
	assert_eq(GameState.dev_commands.rally_ship("a_id"), "")
	assert_eq(a.status, ShipState.Status.ACTIVE)
	assert_string_contains(GameState.dev_commands.surrender_ship("nope"), "no ship")
	assert_string_contains(GameState.dev_commands.rally_ship("nope"), "no ship")


func test_rally_text() -> void:
	var names := {"a_id": "HMS Alert"}
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.RALLY, PHASES.PLANNING, "a_id",
		{"roll": 6, "rating": 4, "passed": true})
	assert_eq(ev.to_text(names), "HMS Alert tries to rally: rolled 6, needed 4 — she rallies and fights on")
	ev.data = {"roll": 3, "rating": 4, "passed": false, "quality": "E"}
	assert_eq(ev.to_text(names), "HMS Alert tries to rally: rolled 3, needed 4 — fails; crew quality drops to E")
	ev.data = {"roll": 3, "rating": 4, "passed": false, "breaks": true}
	assert_eq(ev.to_text(names), "HMS Alert tries to rally: rolled 3, needed 4 — fails; she has struck for good")
