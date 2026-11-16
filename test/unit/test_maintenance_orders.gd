extends GutTest
## The maintenance-orders step in STATUS_ADJUSTMENT (boarding spec §3.1, §4.3, §8 Q1): grappling
## (SoP V.C), then ungrappling (V.D). A prompted player is asked only when it has a choice; its
## answer goes through player_submit_maintenance_orders, which checks the phase, the waiting step,
## the player, the ship and the legality of each pair. Unprompted players' ships use StubAI.

var pc: TurnPhaseController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState
var _old_prompt: Array[int]
var _requests: Array = []


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_ship_definitions()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_env = GameState.environment
	_old_prompt = pc.maintenance_prompt_player_ids
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	GameState.environment = env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_requests = []
	pc.maintenance_orders_requested.connect(_on_request)
	pc.maintenance_prompt_player_ids = [0] as Array[int]


func after_each() -> void:
	pc.maintenance_orders_requested.disconnect(_on_request)
	pc.maintenance_prompt_player_ids = _old_prompt
	pc._reset_maintenance()
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _on_request(player_id: int, step: String, options: Array) -> void:
	_requests.append({"player": player_id, "step": step, "options": options})


func _make_ship(id: String, player: int, hex: Vector2i, quality: String = "D") -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
	})
	state.hex_position = hex
	state.facing = 1
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = quality
	state.mp_used_this_turn = 1
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


func _enter() -> void:
	pc.current_phase = TurnPhaseController.GamePhase.DRIFT_CALCULATION
	pc._enter_status_adjustment_phase()


func test_no_choice_no_pause() -> void:
	# Nothing alongside: STATUS_ADJUSTMENT runs straight through to POST_COMBAT.
	_make_ship("mine", 0, Vector2i(2, 2))
	_make_ship("theirs", 1, Vector2i(9, 9))
	_enter()
	assert_eq(_requests.size(), 0)
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT)
	assert_eq(pc.maintenance_step, TurnPhaseController.MaintenanceStep.NONE)


func test_headless_players_are_never_asked() -> void:
	# As for bear-off: only players in maintenance_prompt_player_ids are asked. StubAI orders the
	# rest; equal crews leave each other alone, so nothing is rolled.
	pc.maintenance_prompt_player_ids = [] as Array[int]
	_make_ship("mine", 0, Vector2i(5, 5))
	_make_ship("theirs", 1, Vector2i(6, 5))
	_enter()
	assert_eq(_requests.size(), 0)
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT)


func test_grapple_prompt_waits_and_validates_the_answer() -> void:
	_make_ship("mine", 0, Vector2i(5, 5), "B")
	_make_ship("theirs", 1, Vector2i(6, 5))
	_make_ship("far", 1, Vector2i(12, 12))
	_enter()
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.STATUS_ADJUSTMENT, "waiting")
	assert_eq(pc.maintenance_step, TurnPhaseController.MaintenanceStep.GRAPPLE)
	assert_eq(_requests.size(), 1)
	assert_eq(_requests[0]["step"], "grapple")
	var options: Array = _requests[0]["options"]
	assert_eq(options.size(), 1)
	assert_eq(options[0]["target_id"], "theirs")
	assert_eq(int(options[0]["needed"]), 4, "CQ B: d10 <= 4")
	assert_eq(int(options[0]["percent"]), 50)
	pc.advance_phase()
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.STATUS_ADJUSTMENT, "advance_phase ignored")
	assert_engine_error("waits for maintenance orders")
	# Refusals change nothing.
	assert_ne(pc.player_submit_maintenance_orders(1, {"grapple": []}), "", "player 1 is not asked")
	assert_ne(pc.player_submit_maintenance_orders(0, {"ungrapple": []}), "", "wrong step")
	assert_ne(pc.player_submit_maintenance_orders(0, {"grapple": "x"}), "", "malformed")
	assert_string_contains(pc.player_submit_maintenance_orders(0, {"grapple": [["theirs", "mine"]]}),
		"not this player's ship")
	assert_string_contains(pc.player_submit_maintenance_orders(0, {"grapple": [["mine", "far"]]}),
		"not alongside")
	assert_eq(pc.maintenance_step, TurnPhaseController.MaintenanceStep.GRAPPLE)
	# A legal answer: d10 3 - 2 = 1 <= 2, grappled; then the ungrapple step asks again (8.C.4: the
	# player may cut a grapple at once), and an empty answer ends the phase.
	_dice.queue([3])
	assert_eq(pc.player_submit_maintenance_orders(0, {"grapple": [["mine", "theirs"]]}), "")
	assert_true(GameState.get_ship("mine").is_grappled_to("theirs"))
	assert_eq(pc.maintenance_step, TurnPhaseController.MaintenanceStep.UNGRAPPLE)
	assert_eq(_requests.size(), 2)
	assert_eq(_requests[1]["step"], "ungrapple")
	# StubAI does not want the grapple (CQ D against B) and tries to cut it: d10 9, fails.
	_dice.queue([9])
	assert_eq(pc.player_submit_maintenance_orders(0, {"ungrapple": []}), "")
	assert_eq(_dice.remaining(), 0, "the AI rolled once")
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT)
	assert_true(GameState.get_ship("mine").is_grappled_to("theirs"), "kept")
	assert_ne(pc.player_submit_maintenance_orders(0, {"grapple": []}), "", "nothing is asked now")


func test_declining_to_grapple_skips_the_ungrapple_prompt() -> void:
	_make_ship("mine", 0, Vector2i(5, 5))
	_make_ship("theirs", 1, Vector2i(6, 5))
	_enter()
	assert_eq(pc.player_submit_maintenance_orders(0, {"grapple": []}), "")
	assert_eq(_requests.size(), 1, "no grapple to cut: no second prompt")
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT)


func test_ai_grapple_then_player_cuts_it_the_same_turn() -> void:
	# The AI (B, 102 BCF) grapples the player's weak ship (E, 60 BCF) in V.C; the player is then
	# asked in V.D and cuts it: d10 1 + 1 (SK E) - 0 = 2 <= 2.
	_make_ship("mine", 0, Vector2i(5, 5), "E")
	_make_ship("theirs", 1, Vector2i(6, 5), "B")
	_enter()
	# The player (CQ E) may grapple too: asked first.
	assert_eq(_requests[0]["step"], "grapple")
	_dice.queue([0])  # the AI's grapple: 0 - 2 = -2 <= 2
	assert_eq(pc.player_submit_maintenance_orders(0, {"grapple": []}), "")
	assert_true(GameState.get_ship("theirs").is_grappled_to("mine"))
	assert_eq(_requests[1]["step"], "ungrapple")
	_dice.queue([1])
	assert_eq(pc.player_submit_maintenance_orders(0, {"ungrapple": [["mine", "theirs"]]}), "")
	assert_false(GameState.get_ship("mine").is_grappled())
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.UNGRAPPLE).size(), 1)
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT)


func test_grapple_and_ungrapple_lines_read_well() -> void:
	var log := PhaseEvents.PhaseLog.new()
	var ev := log.add(PhaseEvents.Type.GRAPPLE, 6, "a", {"roll": 4, "modifiers": [{"name": "skill", "value": -2}],
		"modifier": -2, "total": 2, "needed": 2, "success": true}, "b")
	assert_eq(ev.to_text({"a": "Vengeance", "b": "Hermione"}),
		"Vengeance throws grapples at Hermione — d10 4, crew −2 → 2 ≤ 2: grappled")
	var cut := log.add(PhaseEvents.Type.UNGRAPPLE, 6, "b", {"roll": 7, "modifiers": [], "modifier": 0,
		"total": 7, "needed": 2, "attempt": 1, "success": false}, "a")
	assert_eq(cut.to_text({"a": "Vengeance", "b": "Hermione"}),
		"Hermione fails to cut the grapples to Vengeance — d10 7 → 7 > 2 (try 1)")


# --- the prompt panel and the map lines (view; read state only) ---

func test_panel_lists_choices_and_returns_the_ticked_pairs() -> void:
	var panel: MaintenanceOrdersPanel = autofree(MaintenanceOrdersPanel.new())
	var options := [
		{"ship_id": "mine", "target_id": "theirs", "needed": 3, "percent": 40},
		{"ship_id": "mine", "target_id": "other", "needed": -1, "percent": 0},
	]
	panel.setup("grapple", options, {"mine": "Lively", "theirs": "Topaze"})
	var toggles: Array = panel.find_children("Toggle_*", "Button", false, false)
	assert_eq(toggles.size(), 2)
	assert_eq(toggles[0].text, "☐ Lively: grapple Topaze — needs 3 or less, 40 %")
	assert_eq(toggles[1].text, "☐ Lively: grapple other — cannot succeed")
	toggles[0].button_pressed = true
	assert_eq(toggles[0].text.left(2), "☑ ")
	assert_eq(panel.selected_pairs(), [["mine", "theirs"]])
	watch_signals(panel)
	panel.get_node("DoneButton").emit_signal("pressed")
	assert_signal_emitted_with_parameters(panel, "orders_submitted", ["grapple", [["mine", "theirs"]]])
	assert_eq(MaintenanceOrdersPanel.option_label("ungrapple",
		{"ship_id": "mine", "target_id": "theirs", "needed": 1, "percent": 20, "attempt": 2}, {}),
		"mine: cut the grapples to theirs — needs 1 or less, 20 % (try 2)")


func test_grapple_lines_join_every_touching_hex_pair_once() -> void:
	var a := _make_ship("a", 0, Vector2i(5, 5))
	var b := _make_ship("b", 1, Vector2i(6, 5))
	var grid := HexGrid.new()
	assert_eq(GrappleLines.segments(GameState.get_all_ships(), grid), [], "not grappled")
	GameState.ship_controller.add_grapple("a", "b")
	# a: (5,5)+(5,4); b: (6,5)+(6,4): bow-bow, stern-stern and a's bow to b's stern touch.
	var segs: Array = GrappleLines.segments(GameState.get_all_ships(), grid)
	assert_eq(segs.size(), 3)
	assert_almost_eq(segs[0][0].y, GrappleLines.ROPE_HEIGHT, 0.001)
	assert_true(a.is_grappled_to("b") and b.is_grappled_to("a"))
