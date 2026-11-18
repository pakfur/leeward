extends GutTest
## Anchoring in the crew plan (anchoring spec §3; Close Action 13.B-F): manual plans made legal by
## CrewRules.normalize through AnchorRules.refusal, the Automatic anchor order (rule A2c), the anchor
## order checked by plot_crew, and the read-only anchor station of the crew overlay.

const PLANNING := TurnPhaseController.GamePhase.PLANNING

var _old_scenario: Dictionary
var _old_env: EnvironmentState
var _old_phase: TurnPhaseController.GamePhase
var _old_turn: int


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	_old_scenario = GameState.active_scenario
	_old_env = GameState.environment
	_old_phase = GameState.phase_controller.current_phase
	_old_turn = GameState.current_turn
	GameState.active_scenario = {"anchoring": true}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.phase_controller.current_phase = PLANNING
	GameState.current_turn = 3


func after_each() -> void:
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
	GameState.phase_controller.current_phase = _old_phase
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, auto: bool) -> ShipState:
	var ship_def := Ship.from_dict({
		"ship_id": id, "player_id": 0, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	var state := ShipState.new()
	state.initialize_from_scenario({"position": {"q": 0, "r": 0}, "facing": 3}, ship_def)
	state.side = 0
	state.crew_quality = "C"
	state.crew_auto = auto
	GameState.ships[id] = state
	GameState.ships_by_side[0].append(id)
	return state


func _anchor_data(end: String = "bow", springs: bool = false) -> Dictionary:
	return {"hex": Vector2i(0, 0), "end": end, "springs": springs, "cable": 0, "veered": 0,
		"swing_dir": 0, "wind_dir": 0, "turn": 2}


func _ctx(ship: ShipState) -> Dictionary:
	return CrewRules.context(GameState, ship)


func _anchoring_codes(assignments: Dictionary) -> Dictionary:
	var out := {}
	for s in assignments:
		if AnchorRules.is_code(str(assignments[s].get("code", ""))):
			out[int(s)] = assignments[s]
	return out


func test_context_has_wind_and_anchoring_here() -> void:
	var a := _make_ship("a", true)
	var ctx := _ctx(a)
	assert_eq(ctx["wind_speed"], 3)
	assert_true(ctx["anchoring_here"])
	GameState.active_scenario = {}
	assert_false(_ctx(a)["anchoring_here"])
	assert_eq(CrewRules.context(null, a)["wind_speed"], 0)
	assert_false(CrewRules.context(null, a)["anchoring_here"])


func test_auto_prepare_bow_takes_marines() -> void:
	var a := _make_ship("a", true)
	var out := CrewAuto.allocate(a, {"anchor": "prepare_bow"}, _ctx(a))
	var anchoring := _anchoring_codes(out["assignments"])
	assert_eq(anchoring, {ShipState.MARINES: {"code": "PBA", "params": {}}})


func test_auto_anchor_refused_without_ready_anchor() -> void:
	var a := _make_ship("a", true)
	var out := CrewAuto.allocate(a, {"anchor": "anchor"}, _ctx(a))
	assert_true(_anchoring_codes(out["assignments"]).is_empty())


func test_auto_anchor_not_where_forbidden() -> void:
	GameState.active_scenario = {"anchoring": false}
	var a := _make_ship("a", true)
	a.anchor_ready = "bow"
	var out := CrewAuto.allocate(a, {"anchor": "anchor"}, _ctx(a))
	assert_true(_anchoring_codes(out["assignments"]).is_empty())


func test_auto_anchor_where_allowed() -> void:
	var a := _make_ship("a", true)
	a.anchor_ready = "bow"
	var out := CrewAuto.allocate(a, {"anchor": "anchor"}, _ctx(a))
	assert_eq(_anchoring_codes(out["assignments"]), {ShipState.MARINES: {"code": "A", "params": {}}})


func test_auto_turn_with_springs() -> void:
	var a := _make_ship("a", true)
	assert_true(GameState.ship_controller.drop_anchor("a", _anchor_data("bow", true)))
	var out := CrewAuto.allocate(a, {"anchor": "turn_starboard"}, _ctx(a))
	assert_eq(_anchoring_codes(out["assignments"]),
		{ShipState.MARINES: {"code": "HS", "params": {"turn": "starboard"}}})


func test_prep_continues_as_task_in_progress() -> void:
	var a := _make_ship("a", true)
	GameState.ship_controller.add_task("a", {"code": "PBA", "sections": [3], "params": {},
		"started_turn": GameState.current_turn - 1})
	var out := CrewAuto.allocate(a, {}, _ctx(a))
	assert_eq(_anchoring_codes(out["assignments"]), {3: {"code": "PBA", "params": {}}})


func test_manual_conflicts_dropped() -> void:
	var a := _make_ship("a", false)
	GameState.ship_controller.drop_anchor("a", _anchor_data("bow", true))
	GameState.ship_controller.update_anchor("a", {"veered": 1})
	var plan := {"assignments": {
		0: {"code": "HS", "params": {"turn": "port", "extra": 1}},
		1: {"code": "VI", "params": {}},
		2: {"code": "VO", "params": {}},
	}, "orders": {}}
	var out := CrewRules.normalize(a, plan, _ctx(a))
	assert_eq(out["assignments"], {0: {"code": "HS", "params": {"turn": "port"}}})
	assert_true(out["dropped"].has(1))
	assert_true(out["dropped"].has(2))
	var text := "\n".join(PackedStringArray(out["warnings"]))
	assert_string_contains(text, "13.E.2")
	assert_string_contains(text, "13.E.1d")


func test_manual_anchor_with_course_kept_then_erased() -> void:
	var a := _make_ship("a", false)
	a.anchor_ready = "bow"
	a.plotted_actions["movement"] = [
		{"hex": Vector2i(-1, 0), "facing": 3, "move_type": "ahead"},
		{"hex": Vector2i(-2, 0), "facing": 3, "move_type": "ahead"},
	]
	var plan := {"assignments": {ShipState.MARINES: {"code": "A", "params": {}}}, "orders": {}}
	var ctx := _ctx(a)
	assert_eq(ctx["plotted_mps"], 2)
	var out := CrewRules.normalize(a, plan, ctx)
	assert_eq(out["assignments"], {ShipState.MARINES: {"code": "A", "params": {}}})
	assert_string_contains("\n".join(PackedStringArray(out["warnings"])), "13.C.1")
	ctx["final"] = true
	out = CrewRules.normalize(a, plan, ctx)
	assert_true(out["assignments"].is_empty())
	assert_true(out["dropped"].has(ShipState.MARINES))


func test_plot_crew_rejects_unknown_order() -> void:
	_make_ship("a", false)
	assert_eq(GameState.crew_task_controller.plot_crew(0, "a",
		{"assignments": {}, "orders": {"anchor": "drop"}}), "Unknown anchor order drop")
	assert_eq(GameState.crew_task_controller.plot_crew(0, "a",
		{"assignments": {}, "orders": {"anchor": "prepare_bow"}}), "")


func test_anchor_order_lapses() -> void:
	var a := _make_ship("a", true)
	assert_eq(GameState.crew_task_controller.plot_crew(0, "a",
		{"assignments": {}, "orders": {"anchor": "prepare_bow"}}), "")
	assert_eq(str(a.plotted_actions.crew_orders.get("anchor", "")), "prepare_bow")
	GameState.ship_controller.clear_crew_plot("a")
	assert_eq(str(a.plotted_actions.crew_orders.get("anchor", "")), "")


func test_anchor_station_read_only() -> void:
	var a := _make_ship("a", false)
	var ctx := _ctx(a)
	var empty := {"assignments": {}, "orders": {}}
	var ids: Array = []
	for st in CrewRules.stations(a, empty, ctx):
		ids.append(st["id"])
	assert_false(ids.has("anchor"), "no anchor state, no task: no station")
	GameState.ship_controller.drop_anchor("a", _anchor_data("bow", true))
	var plan := {"assignments": {2: {"code": "HS", "params": {"turn": "port"}}}, "orders": {}}
	var found := {}
	for st in CrewRules.stations(a, plan, ctx):
		if st["id"] == "anchor":
			found = st
	assert_false(found.is_empty())
	assert_eq(found["accepts"], "none")
	assert_eq(found["label"], "Anchor & cable")
	assert_eq(found["short"], "Anc")
	assert_true((found["occupants"] as Array).has(2))
	assert_eq(found["note"], AnchorRules.status_text(a))
	assert_string_contains(str(found["disabled_reason"]), "crew orders")
	assert_string_contains(CrewRules.refusal(a, plan, ctx, 3, "anchor"), "crew orders")
	assert_eq(CrewRules.station_of(1, {"code": "PBA"}), "anchor")
	assert_eq(CrewRules.task_name("PBA"), "preparing the bow anchor")
	assert_eq(CrewRules.task_name("HS"), "handling the springs")


func test_a2c_after_fire() -> void:
	# A1 first: with only the marines left, the fire takes them and the anchor order gets no one.
	var a := _make_ship("a", true)
	a.crew_count = [0, 0, 0, 0] as Array[int]
	var ctx := _ctx(a)
	ctx["fires"] = [1]
	var out := CrewAuto.allocate(a, {"anchor": "prepare_bow"}, ctx)
	assert_eq(out["assignments"].get(ShipState.MARINES, {}).get("code", ""), "FF")
	assert_true(_anchoring_codes(out["assignments"]).is_empty())


func test_a2c_after_boarding_order() -> void:
	# A2b first: "ready" forms the marines and S1 as boarders; the anchor order takes S4.
	var a := _make_ship("a", true)
	var out := CrewAuto.allocate(a, {"anchor": "prepare_bow", "boarding": "ready"}, _ctx(a))
	assert_eq(out["assignments"].get(ShipState.MARINES, {}).get("code", ""), "FB")
	assert_eq(_anchoring_codes(out["assignments"]), {3: {"code": "PBA", "params": {}}})


func test_a2c_before_sail_change() -> void:
	# A3 after: the anchor order takes the marines, the sail change the next sections in worker order.
	var a := _make_ship("a", true)
	var target: String = SailController.targets_for(a)[0]
	var needed := SailController.sections_needed(a, target)
	var out := CrewAuto.allocate(a, {"anchor": "prepare_bow", "sail_target": target}, _ctx(a))
	assert_eq(_anchoring_codes(out["assignments"]), {ShipState.MARINES: {"code": "PBA", "params": {}}})
	var on_sails: Array = []
	for s in out["assignments"]:
		if str(out["assignments"][s].get("code", "")) == SailController.CODE:
			on_sails.append(int(s))
	on_sails.sort()
	var expected: Array = [2, 3] if needed == 2 else [3]
	assert_eq(on_sails, expected)


func test_client_anchor_station_refusal() -> void:
	_make_ship("a", false)
	GameState.ship_controller.drop_anchor("a", _anchor_data("bow", true))
	var old_ready: Dictionary = GameState.phase_controller.players_ready.duplicate()
	GameState.phase_controller.players_ready = {0: false, 1: false}
	var client := CrewOverlayClient.new(GameState, 0)
	client.open_for("a")
	assert_eq(client.refusal(3, "anchor"), CrewRules.ANCHOR_REFUSAL)
	assert_eq(client.mark_for("anchor", 3), "invalid")
	GameState.phase_controller.players_ready = old_ready


## A ship with no course stored sails her default course (6.G.2): the planning context counts it, so
## the 13.C.1 warning fires before End Planning erases the anchoring.
func test_anchor_warning_counts_the_default_course() -> void:
	var a := _make_ship("a", false)
	a.anchor_ready = "bow"
	a.speed = 2
	a.sail_state = "FS"
	a.plotted_actions["movement"] = []
	a.plotted_actions["movement_plotted"] = false
	var ctx := _ctx(a)
	assert_gt(DefaultCourse.for_ship(GameState, a).size(), 0, "control: she has a default course")
	assert_eq(ctx["plotted_mps"], DefaultCourse.for_ship(GameState, a).size())
	assert_eq(ctx["plotted_mps"], GameState.anchor_controller.actual_steps(a), "as End Planning reads it")
	var plan := {"assignments": {ShipState.MARINES: {"code": "A", "params": {}}}, "orders": {}}
	assert_string_contains("\n".join(PackedStringArray(CrewRules.normalize(a, plan, ctx)["warnings"])),
		"13.C.1")
	GameState.ship_controller.set_plotted_movement("a", [])
	assert_eq(_ctx(a)["plotted_mps"], 0, "an empty stored course is no MPs")


## I2: a prize, even with her prize crew aboard, handles no anchors (10.H.2), manual or Automatic.
func test_prize_orders_no_anchoring() -> void:
	var a := _make_ship("a", true)
	a.status = ShipState.Status.CAPTURED
	a.prize = {"captor_id": "x", "prize_crew_aboard": true, "original_crew": {}}
	assert_true(a.crew_can_act(), "her prize crew can act")
	assert_eq(AnchorRules.refusal(a, "PBA", {}, _ctx(a), []), AnchorRules.R_CREW)
	var out := CrewAuto.allocate(a, {"anchor": "prepare_bow"}, _ctx(a))
	assert_true(_anchoring_codes(out["assignments"]).is_empty())


func test_section_job_word_for_anchor_tasks() -> void:
	var a := _make_ship("a", false)
	assert_eq(CrewOverlayText.section_job(a, 2, {"code": "HS", "params": {"turn": "port"}})["text"], "anchor")
