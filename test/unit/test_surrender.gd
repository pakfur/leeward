extends GutTest
## 14.B voluntary surrender (sub-project 7, spec §2.1-2.3): eligibility (CQ F/G or five sections
## lost), the planning request, a surrendering ship's g-t (she does not fire or board), the strike at
## MORALE_CHECK before the noted checks, the permanent second surrender, and what the enemy may see.

const PHASES := TurnPhaseController.GamePhase
const PHASE := TurnPhaseController.GamePhase.MORALE_CHECK
const STARBOARD := 1

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


func _order(ship_id: String, target_id: String) -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = STARBOARD
	order.target_id = target_id
	order.ammo = "round"
	order.aim = "low"
	order.battery = "full"
	return order


func _set_rigging(ship: ShipState, values: Array) -> void:
	var arr: Array[int] = []
	arr.assign(values)
	ship.rigging_current_hp = arr


func _set_hull(ship: ShipState, values: Array) -> void:
	var arr: Array[int] = []
	arr.assign(values)
	ship.hull_current_hp = arr


func _set_crew(ship: ShipState, values: Array) -> void:
	var arr: Array[int] = []
	arr.assign(values)
	ship.crew_count = arr


## A ship whose CQ lets her surrender, ordered to through the request.
func _order_surrender(ship: ShipState) -> void:
	ship.crew_quality = "F"
	assert_eq(pc.player_surrender(ship.side, ship.ship_id), "", "the order is accepted")


func _events(type: PhaseEvents.Type) -> Array[PhaseEvents.PhaseEvent]:
	return GameState.turn_log.of_type(type)


# --- eligibility (14.B.2) ---

func test_sections_lost_counts_every_kind() -> void:
	_set_rigging(a, [0, 0, 6, 6])
	_set_hull(a, [0, 5, 5, 6])
	_set_crew(a, [0, 3, 3, 3])
	a.marine_count = 0
	assert_eq(SurrenderRules.sections_lost(a), 5, "2 rigging + 1 hull + 1 sailor + the marines")
	var detached: Array[int] = [3, 0, 0, 0, 2]
	a.detached_boxes = detached
	assert_eq(SurrenderRules.sections_lost(a), 3, "crew sections sent off as a prize crew do not count")


func test_eligibility() -> void:
	_set_rigging(a, [0, 0, 6, 6])
	_set_hull(a, [0, 0, 5, 6])
	assert_false(SurrenderRules.eligible(a), "CQ D with 4 sections lost")
	_set_crew(a, [0, 3, 3, 3])
	assert_true(SurrenderRules.eligible(a), "CQ D with 5 sections lost")
	var fresh := _make_ship("c_id", 0, Vector2i(5, 5), 0)
	fresh.crew_quality = "F"
	assert_true(SurrenderRules.eligible(fresh), "CQ F, none lost")
	fresh.crew_quality = "G"
	assert_true(SurrenderRules.eligible(fresh), "CQ G, none lost")
	fresh.crew_quality = "E"
	assert_false(SurrenderRules.eligible(fresh), "CQ E, none lost")


func test_rally_error_order() -> void:
	a.status = ShipState.Status.CAPTURED
	assert_eq(SurrenderRules.rally_error(a, 1), "a captured ship cannot rally (14.B.2)")
	a.status = ShipState.Status.STRUCK
	a.surrenders = 2
	assert_eq(SurrenderRules.rally_error(a, 1), "a_id has surrendered twice: she has struck for good (14.B.4)")
	a.surrenders = 1
	a.surrendered = false
	assert_eq(SurrenderRules.rally_error(a, 1), "a_id has struck for good")
	a.status = ShipState.Status.ACTIVE
	assert_eq(SurrenderRules.rally_error(a, 1), "a_id has not surrendered")
	a.status = ShipState.Status.STRUCK
	a.surrendered = true
	a.rally_turn = 1
	assert_eq(SurrenderRules.rally_error(a, 1), "a_id has tried to rally this turn")
	assert_eq(SurrenderRules.rally_error(a, 2), "", "a surrendered ship may try once a g-t")


# --- the request (spec §2.3) ---

func test_surrender_request_checks() -> void:
	a.crew_quality = "F"
	GameState.active_scenario = {}
	assert_string_contains(pc.player_surrender(0, "a_id"), "not used in this scenario")
	GameState.active_scenario = {"optional_rules": {"voluntary_surrender": true}}
	pc.current_phase = PHASES.COMBAT_RESOLUTION
	assert_string_contains(pc.player_surrender(0, "a_id"), "planning phase")
	pc.current_phase = PHASES.PLANNING
	assert_string_contains(pc.player_surrender(1, "a_id"), "not this player's")
	pc.players_ready[0] = true
	assert_string_contains(pc.player_surrender(0, "a_id"), "already submitted")
	pc.players_ready[0] = false
	a.crew_quality = "D"
	assert_string_contains(pc.player_surrender(0, "a_id"), "14.B.2")
	a.crew_quality = "F"
	a.status = ShipState.Status.STRUCK
	assert_string_contains(pc.player_surrender(0, "a_id"), "not in play")
	a.status = ShipState.Status.ACTIVE
	assert_false(a.surrender_ordered, "no refused request set the order")
	assert_eq(pc.player_surrender(0, "a_id"), "")
	assert_true(a.surrender_ordered)
	assert_eq(pc.player_surrender(0, "a_id", false), "")
	assert_false(a.surrender_ordered, "the order is withdrawn")


# --- the g-t of the order ---

func test_surrendering_ship_does_not_fire() -> void:
	assert_true(GameState.gunnery_calculator.preview(_order("a_id", "b_id")).can_fire, "A's broadside bears on B")
	_order_surrender(a)
	var p := GameState.gunnery_calculator.preview(_order("a_id", "b_id"))
	assert_false(p.can_fire)
	assert_string_contains(p.reason, "surrendering")
	assert_eq(GameState.gunnery_calculator.eligible_shots("a_id").size(), 0)
	assert_true(GameState.gunnery_calculator.preview(_order("b_id", "a_id")).can_fire, "she can still be fired on")


func test_surrendering_ship_fires_no_muskets() -> void:
	_order_surrender(a)
	assert_string_contains(FireRules.marine_error(a, b, 1), "surrendering")


func test_surrendering_ship_sends_no_new_boarders() -> void:
	a.task_seq += 1
	a.crew_tasks.append(ShipState.crew_task_from({"seq": a.task_seq, "code": "BR", "sections": [0],
		"done": 0, "started_turn": 0, "params": {"section": 0}, "forced": false,
		"marines_available": true, "ended": ""}))
	assert_true(a.is_readied(0), "S1 is readied")
	# Eligible by sections lost, at CQ D (a crew at CQ F may not board anyway, 10.A.2).
	_set_rigging(a, [0, 0, 6, 6])
	_set_hull(a, [0, 0, 5, 6])
	a.marine_count = 0
	assert_eq(pc.player_surrender(0, "a_id"), "", "the order is accepted")
	assert_string_contains(BoardingRules._ba_error(a, {}, {}, 0, "b_id"), "does not board")


# --- the strike at MORALE_CHECK ---

func test_strikes_at_morale_check() -> void:
	_order_surrender(a)
	GameState.morale_controller.resolve_phase(PHASE)
	assert_true(a.is_struck())
	assert_true(a.surrendered)
	assert_eq(a.surrenders, 1)
	assert_false(a.surrender_ordered, "the order is spent")
	assert_true(a.can_rally())
	var types: Array = []
	for ev in GameState.turn_log.events:
		types.append(ev.type)
	assert_eq(types, [PhaseEvents.Type.SURRENDER, PhaseEvents.Type.STRIKE])
	var surrender := _events(PhaseEvents.Type.SURRENDER)[0]
	assert_eq(surrender.ship_id, "a_id")
	assert_eq(int(surrender.data["surrenders"]), 1)
	assert_eq(surrender.data["permanent"], false)
	assert_eq(str(_events(PhaseEvents.Type.STRIKE)[0].data["reason"]), "surrender")


func test_surrender_comes_before_noted_checks() -> void:
	_order_surrender(a)
	a.pending_morale_checks = 1
	GameState.morale_controller.resolve_phase(PHASE)
	assert_eq(_dice.remaining(), 0, "no die rolled")
	assert_eq(_events(PhaseEvents.Type.MORALE_CHECK).size(), 0, "her noted check is never rolled")
	assert_true(a.surrendered)
	assert_eq(a.pending_morale_checks, 0)


func test_order_lapses_if_already_out_of_play() -> void:
	_order_surrender(a)
	GameState.damage_controller.strike("a_id", "morale", PHASE)
	GameState.morale_controller.resolve_surrenders(PHASE)
	assert_eq(_events(PhaseEvents.Type.SURRENDER).size(), 0)
	assert_eq(a.surrenders, 0)
	assert_false(a.surrender_ordered)
	assert_false(a.surrendered)


func test_second_surrender_is_permanent() -> void:
	a.surrenders = 1
	_order_surrender(a)
	GameState.morale_controller.resolve_phase(PHASE)
	var surrender := _events(PhaseEvents.Type.SURRENDER)[0]
	assert_eq(int(surrender.data["surrenders"]), 2)
	assert_eq(surrender.data["permanent"], true)
	assert_true(a.is_struck())
	assert_false(a.surrendered, "14.B.4: struck for good")
	assert_false(a.can_rally())


func test_client_does_not_resolve_surrenders() -> void:
	_order_surrender(a)
	GameState.morale_controller.is_server = false
	GameState.morale_controller.resolve_surrenders(PHASE)
	GameState.morale_controller.is_server = true
	assert_push_error(1, "client refusal")
	assert_true(a.surrender_ordered, "the order stands")
	assert_false(a.is_struck())
	assert_eq(_events(PhaseEvents.Type.SURRENDER).size(), 0)


func test_set_status_clears_surrendered() -> void:
	for status in [ShipState.Status.CAPTURED, ShipState.Status.DESTROYED, ShipState.Status.ACTIVE]:
		a.status = ShipState.Status.STRUCK
		a.surrendered = true
		GameState.ship_controller.set_status("a_id", status)
		assert_false(a.surrendered, "status %d clears surrendered" % status)
	a.surrendered = true
	GameState.ship_controller.set_status("a_id", ShipState.Status.STRUCK)
	assert_true(a.surrendered, "STRUCK keeps it")


func test_last_ship_surrender_concedes() -> void:
	_order_surrender(a)
	GameState.morale_controller.resolve_phase(PHASE)
	var result: Dictionary = GameState.victory_controller.check(1)
	assert_eq(str(result.get("reason", "")), "all struck")
	assert_eq(int(result.get("winner", -2)), 1)


# --- information and serialization ---

func test_surrender_order_hidden_from_the_enemy() -> void:
	a.surrender_ordered = true
	var enemy_view: Dictionary = GameState.player_view.ship_for(1, "a_id")
	assert_false(enemy_view.has("surrender_ordered"), "the order is the side's secret")
	assert_true(enemy_view.has("surrenders"))
	assert_true(enemy_view.has("surrendered"))
	assert_eq(GameState.player_view.ship_for(0, "a_id")["surrender_ordered"], true)


func test_surrender_fields_serialized() -> void:
	a.surrender_ordered = true
	a.surrenders = 1
	a.surrendered = true
	a.rally_turn = 7
	var copy := ShipState.deserialize(a.serialize())
	assert_true(copy.surrender_ordered)
	assert_eq(copy.surrenders, 1)
	assert_true(copy.surrendered)
	assert_eq(copy.rally_turn, 7)
	var data := a.serialize()
	for key in ["surrender_ordered", "surrenders", "surrendered", "rally_turn"]:
		data.erase(key)
	var old := ShipState.deserialize(data)
	assert_false(old.surrender_ordered)
	assert_eq(old.surrenders, 0)
	assert_false(old.surrendered)
	assert_eq(old.rally_turn, -1)


func test_surrender_text() -> void:
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.SURRENDER, PHASE, "a_id",
		{"surrenders": 1, "permanent": false})
	var text := ev.to_text({"a_id": "HMS Alert"})
	assert_string_contains(text, "hauls down her colours")
	assert_false(text.contains("cannot rally again"))
	ev.data = {"surrenders": 2, "permanent": true}
	assert_string_contains(ev.to_text({"a_id": "HMS Alert"}), "cannot rally again")
	var strike := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.STRIKE, PHASE, "a_id", {"reason": "surrender"})
	assert_string_contains(strike.to_text({"a_id": "HMS Alert"}), "surrendered")


# --- fix wave: cancel, rally turn, gutted ships, boarders, muskets ---

func test_cancel_planning_withdraws_the_surrender_order() -> void:
	pc.planning_snapshot = {}
	_order_surrender(a)
	assert_true(a.surrender_ordered)
	assert_eq(pc.player_reset_planning(0), "")
	assert_false(a.surrender_ordered, "Cancel withdraws the order, snapshot or not")


func test_no_surrender_on_the_turn_of_a_rally() -> void:
	a.crew_quality = "F"
	a.rally_turn = pc.current_turn
	assert_string_contains(pc.player_surrender(0, "a_id"), "rallied this turn")
	assert_false(a.surrender_ordered)
	a.rally_turn = pc.current_turn - 1
	assert_eq(pc.player_surrender(0, "a_id"), "")


func test_gutted_ship_surrender_is_permanent() -> void:
	_set_hull(a, [0, 0, 0, 0])
	_order_surrender(a)
	GameState.morale_controller.resolve_phase(PHASE)
	assert_true(a.is_struck())
	assert_false(a.surrendered, "no hull left: struck for good")
	assert_false(a.can_rally())
	assert_eq(_events(PhaseEvents.Type.SURRENDER)[0].data["permanent"], true)


func test_no_crew_ship_cannot_rally() -> void:
	_order_surrender(a)
	GameState.morale_controller.resolve_phase(PHASE)
	assert_true(a.can_rally())
	_set_crew(a, [0, 0, 0, 0])
	a.marine_count = 0
	assert_false(a.can_rally(), "can_rally reflects it")
	assert_string_contains(SurrenderRules.rally_error(a, 5), "permanent")
	_dice.queue([9])
	var result: Dictionary = GameState.morale_controller.rally("a_id", PHASE)
	assert_false(result["passed"])
	assert_true(a.is_struck(), "never back to ACTIVE")
	assert_eq(_dice.remaining(), 1, "no die rolled")
	assert_false(a.surrendered)


func test_fire_gutted_hull_cannot_rally() -> void:
	_order_surrender(a)
	GameState.morale_controller.resolve_phase(PHASE)
	_set_hull(a, [0, 0, 0, 0])
	assert_false(a.can_rally())
	assert_string_contains(SurrenderRules.rally_error(a, 5), "permanent")


func test_plotted_ba_is_dropped_for_a_surrendering_ship() -> void:
	a.task_seq += 1
	a.crew_tasks.append(ShipState.crew_task_from({"seq": a.task_seq, "code": "BR", "sections": [0],
		"done": 0, "started_turn": 0, "params": {"section": 0}, "forced": false,
		"marines_available": true, "ended": ""}))
	_set_rigging(a, [0, 0, 6, 6])
	_set_hull(a, [0, 0, 5, 6])
	a.marine_count = 0
	a.crew_auto = false
	a.grappled_with.append("b_id")
	b.grappled_with.append("a_id")
	GameState.boarding_controller.take_link_snapshot()
	var ctx := CrewRules.context(GameState, a)
	var plan := {"assignments": {0: BoardingRules.entry("BA", 0, "b_id")}, "orders": {}}
	var before := CrewRules.normalize(a, plan, ctx)
	assert_eq(str(before["assignments"][0]["code"]), "BA", "before the order the boarding plot stands")
	assert_eq(pc.player_surrender(0, "a_id"), "")
	ctx = CrewRules.context(GameState, a)
	var after := CrewRules.normalize(a, plan, ctx)
	assert_eq(str(after["assignments"][0]["code"]), "BR", "the boarding plot stays ready, no BA")
	GameState.crew_task_controller.plot_crew(0, "a_id", plan)
	GameState.crew_task_controller.finalize_plots()
	var stored: Dictionary = GameState.crew_task_controller.current_plan("a_id", true)
	assert_eq(str(stored["assignments"][0]["code"]), "BR", "and through finalize_plots")


func test_surrendering_ship_has_no_marine_shots() -> void:
	a.marine_count = 2
	b.marine_count = 2
	b.hex_position = Vector2i(1, 0)
	b.facing = 3
	var before := GameState.marine_fire_resolver.eligible_marine_shots("a_id").size()
	assert_gt(before, 0, "adjacent enemy: a shot exists before the order")
	_order_surrender(a)
	assert_eq(GameState.marine_fire_resolver.eligible_marine_shots("a_id").size(), 0)
	b.marine_count = 0
	assert_false(GameState.marine_fire_resolver.any_eligible_marine_shot(), "nobody else can shoot either")

