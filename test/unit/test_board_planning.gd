extends GutTest
## BoardPlanning (board planning piece 1): the ring items an own ship gets, Plan / Done, Move mode
## and the PLANNING keys, against a test GameState in PLANNING. Headless: no camera, so the ring,
## badges and chip box are checked by state, not by screen position.

const PLANNING := TurnPhaseController.GamePhase.PLANNING

var bp: BoardPlanning
var a: ShipState
var b: ShipState
var _old_phase: TurnPhaseController.GamePhase
var _old_gs_phase
var _old_ready: Dictionary
var _old_env: EnvironmentState
var _old_humans: Array[int]
var _old_ai: Array[int]
var _old_stub_ai: Variant
var _selected := ""
var _old_scenario: Dictionary
var _old_players: Dictionary
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_pc_turn: int
var _old_turn: int


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	_old_phase = _pc().current_phase
	_old_gs_phase = GameState.current_phase
	_old_ready = _pc().players_ready.duplicate()
	_old_humans = _pc().human_player_ids.duplicate()
	_old_ai = _pc().ai_player_ids.duplicate()
	_old_stub_ai = GameState.stub_ai
	_old_env = GameState.environment
	GameState.stub_ai = null
	_old_scenario = GameState.active_scenario
	_old_players = GameState.players
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_pc_turn = _pc().current_turn
	_old_turn = GameState.current_turn
	GameState.active_scenario = {}
	GameState.players = {0: PlayerState.from_dict({"id": 0, "side": 0}),
		1: PlayerState.from_dict({"id": 1, "side": 1})}
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	_pc().current_turn = 1
	GameState.current_turn = 1
	GameState.environment = EnvironmentState.new()
	GameState.environment.wind_direction = 3
	GameState.environment.wind_speed = 3
	_pc().human_player_ids = [0] as Array[int]
	_pc().ai_player_ids = [] as Array[int]
	_pc().current_phase = PLANNING
	GameState.current_phase = GameState.GamePhase.PLANNING
	_pc().players_ready = {0: false, 1: false}
	a = _make_ship("a", 0, Vector2i(0, 0))
	b = _make_ship("b", 0, Vector2i(0, 4))
	_selected = ""
	bp = BoardPlanning.new()
	add_child_autofree(bp)
	bp.setup(null, null, func(id: String) -> Variant: return Vector3(0, 0, 0) if id != "" else null,
		Callable(), func() -> String: return _selected)


func after_each() -> void:
	_pc().current_phase = _old_phase
	GameState.current_phase = _old_gs_phase
	_pc().players_ready = _old_ready
	_pc().human_player_ids = _old_humans
	_pc().ai_player_ids = _old_ai
	_pc().planning_snapshot = {}
	GameState.stub_ai = _old_stub_ai
	GameState.active_scenario = _old_scenario
	GameState.players = _old_players
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	_pc().current_turn = _old_pc_turn
	GameState.current_turn = _old_turn
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _pc() -> TurnPhaseController:
	return GameState.phase_controller


func _make_ship(id: String, player: int, hex: Vector2i) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex
	state.speed = 2
	state.sail_state = "MS"
	state.crew_quality = "B"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	GameState.add_ship(state)
	return state


func _ships(list: Array) -> Array[ShipState]:
	var out: Array[ShipState] = []
	out.assign(list)
	return out


func _ids(items: Array[RadialItem]) -> Array[String]:
	var out: Array[String] = []
	for item in items:
		out.append(item.id)
	return out


func _item(items: Array[RadialItem], id: String) -> RadialItem:
	for item in items:
		if item.id == id:
			return item
	return null


func _anchor(ship: ShipState) -> void:
	ship.anchor = {"hex": ship.hex_position, "end": "bow", "springs": false, "cable": 0}


func _choose(id: String) -> void:
	var menu := bp.radial_menu()
	for i in menu.item_count():
		if bp._current_items(GameState.get_ship(bp.ring_ship_id()))[i].id == id:
			menu.choose(i)
			return
	fail_test("no ring item " + id)


func test_ring_items_for_movable_ship() -> void:
	_pc()._enter_planning_phase()  # stores the default course and the planning snapshot
	bp.begin_planning(_ships([a, b]))
	var items := bp.ring_items(a)
	assert_eq(_ids(items), ["move", "crew", "orders", "signal", "reset", "done"] as Array[String])
	assert_true(_item(items, "orders").is_enabled(), "Orders is always there")
	assert_true(_item(items, "signal").is_enabled(), "the composer opens it: greyed only by the server")
	assert_true(_item(items, "move").is_enabled(), "a movable ship may Move")
	assert_true(_item(items, "crew").is_enabled())
	assert_eq(_item(items, "reset").off_reason, "No course plotted: she sails her default course.",
		"her course is the default one")
	var path: Array = _pc().course_options("a")["path"]
	var hex: Vector2i = HexGrid.new().get_neighbor(path[-1].hex.x, path[-1].hex.y, path[-1].facing)
	assert_eq(_pc().player_extend_course(0, "a", hex), "")
	assert_true(_item(bp.ring_items(a), "reset").is_enabled(), "a plotted course may be reset")


func test_move_greyed_with_server_reason_for_anchored_ship() -> void:
	_anchor(b)
	bp.begin_planning(_ships([a, b]))
	assert_eq(bp.checklist().state("b"), PlanChecklist.LOCKED, "she cannot plot: never stuck in Plan")
	var items := bp.ring_items(b)
	var move := _item(items, "move")
	assert_ne(move.off_reason, "")
	assert_eq(move.off_reason, PlanningSailUi.movement_block_reason(b), "the server's own reason")
	assert_eq(_ids(items)[-1], "undo", "a locked ship shows Plan again")
	assert_eq(items[-1].off_reason, PlanningSailUi.movement_block_reason(b), "greyed with the same reason")
	bp.open_ring("b")
	assert_true(bp.radial_menu().is_open(), "her ring still opens")
	bp.enter_move("b")
	assert_eq(bp.move_ship_id(), "", "and Move does nothing")


func test_done_and_plan_again_toggle() -> void:
	bp.begin_planning(_ships([a, b]))
	bp.open_ring("a")
	_choose("done")
	assert_eq(bp.checklist().state("a"), PlanChecklist.DONE)
	assert_false(bp.radial_menu().is_open(), "Done closes the ring")
	assert_eq(_ids(bp.ring_items(a))[-1], "undo", "Plan again in her ring now")
	bp.open_ring("a")
	_choose("undo")
	assert_eq(bp.checklist().state("a"), PlanChecklist.PLAN)
	assert_eq(_ids(bp.ring_items(a))[-1], "done")


func test_tab_opens_next_ship_in_plan() -> void:
	var c := _make_ship("c", 0, Vector2i(0, 8))
	bp.begin_planning(_ships([a, b, c]))
	bp.checklist().set_done("b", true)
	watch_signals(bp)
	_selected = "a"
	assert_true(bp.handle_key(KEY_TAB))
	assert_eq(bp.ring_ship_id(), "a", "the first Tab opens the selected ship's ring (she is in Plan)")
	assert_true(bp.handle_key(KEY_TAB))
	assert_eq(bp.ring_ship_id(), "c", "b is Done: the next in Plan after a is c")
	assert_signal_emitted_with_parameters(bp, "ring_opened", ["c"])
	assert_true(bp.handle_key(KEY_TAB))
	assert_eq(bp.ring_ship_id(), "a", "wraps round, from the ring's ship")
	bp.checklist().set_done("a", true)
	bp.checklist().set_done("c", true)
	bp.close_ring()
	assert_true(bp.handle_key(KEY_TAB), "taken even when nothing is left in Plan")
	assert_false(bp.radial_menu().is_open())


func test_first_tab_skips_a_done_selected_ship() -> void:
	var c := _make_ship("c", 0, Vector2i(0, 8))
	bp.begin_planning(_ships([a, b, c]))
	bp.checklist().set_done("a", true)
	_selected = "a"
	assert_true(bp.handle_key(KEY_TAB))
	assert_eq(bp.ring_ship_id(), "b", "a is Done: Tab opens the next ship in Plan after her")


func test_shift_tab_goes_to_the_previous_ship_in_plan() -> void:
	var c := _make_ship("c", 0, Vector2i(0, 8))
	bp.begin_planning(_ships([a, b, c]))
	bp.checklist().set_done("b", true)
	bp.open_ring("c")
	assert_true(bp.handle_key(KEY_TAB, true))
	assert_eq(bp.ring_ship_id(), "a", "b is Done: before c in Plan is a")
	assert_true(bp.handle_key(KEY_TAB, true))
	assert_eq(bp.ring_ship_id(), "c", "wraps backward")


func test_space_in_move_mode_leaves_move_mode() -> void:
	bp.begin_planning(_ships([a, b]))
	_selected = "a"
	bp.enter_move("a")
	assert_true(bp.handle_key(KEY_SPACE))
	assert_eq(bp.move_ship_id(), "", "the ring and Move mode are never open together")
	assert_eq(bp.ring_ship_id(), "a")
	_choose("done")
	assert_eq(bp.checklist().state("a"), PlanChecklist.DONE)
	assert_eq(bp.move_ship_id(), "")


func test_checklist_change_refreshes_the_open_ring_in_place() -> void:
	bp.begin_planning(_ships([a, b]))
	bp.open_ring("a")
	watch_signals(bp)
	bp.checklist().set_done("b", true)  # another ship: the ring stays as it was
	bp.checklist().set_done("a", true)  # her own pill: Done becomes Plan again, ring still open
	assert_eq(bp.ring_ship_id(), "a")
	assert_signal_not_emitted(bp, "ring_opened", "no re-open, no reselect")
	var menu := bp.radial_menu()
	assert_true(menu.is_open())
	assert_eq(menu.item_count(), 6)
	assert_eq(_ids(bp.ring_items(a))[-1], "undo")
	assert_not_null(menu.find_child("Item_undo", true, false), "the last button is Plan again")


func test_space_opens_selected_ship_and_enter_marks_done() -> void:
	bp.begin_planning(_ships([a, b]))
	_selected = "b"
	assert_true(bp.handle_key(KEY_SPACE))
	assert_eq(bp.ring_ship_id(), "b")
	assert_true(bp.handle_key(KEY_ENTER))
	assert_eq(bp.checklist().state("b"), PlanChecklist.DONE, "Enter = Done for the ring's ship")
	assert_false(bp.radial_menu().is_open())
	bp.enter_move("a")
	assert_true(bp.handle_key(KEY_KP_ENTER))
	assert_eq(bp.checklist().state("a"), PlanChecklist.DONE, "and for the Move-mode ship")
	assert_eq(bp.move_ship_id(), "", "leaving Move mode")
	assert_false(bp.handle_key(KEY_ENTER), "nothing open: not taken")


func test_esc_steps_back() -> void:
	bp.begin_planning(_ships([a, b]))
	watch_signals(bp)
	bp.open_ring("a")
	_choose("move")
	assert_eq(bp.move_ship_id(), "a")
	assert_false(bp.radial_menu().is_open(), "Move closes the ring")
	assert_signal_emitted_with_parameters(bp, "move_mode_changed", ["a"])
	assert_true(bp.handle_key(KEY_ESCAPE))
	assert_eq(bp.move_ship_id(), "", "Esc leaves Move mode")
	assert_signal_emitted_with_parameters(bp, "move_mode_changed", [""])
	assert_eq(bp.ring_ship_id(), "a", "back to her ring")
	assert_true(bp.handle_key(KEY_ESCAPE))
	assert_false(bp.radial_menu().is_open(), "then the ring closes")
	assert_false(bp.handle_key(KEY_ESCAPE), "then Esc is not ours (the pause menu)")


func test_chip_box_done_and_keep() -> void:
	bp.begin_planning(_ships([a, b]))
	bp.enter_move("a")
	bp.show_course({"used": 2, "allowance": 4, "note": "", "collision": "Refused: no"}, null)
	var chips := bp.course_chips()
	assert_true(chips.visible)
	assert_eq(chips.title_text(), "Course: 2 of 4 MP")
	assert_eq(chips.warning_text(), "Refused: no")
	chips.keep_button().pressed.emit()
	assert_eq(bp.move_ship_id(), "", "Keep planning leaves Move mode")
	assert_eq(bp.checklist().state("a"), PlanChecklist.PLAN, "still in Plan")
	assert_false(chips.visible)
	bp.enter_move("a")
	chips.done_button().pressed.emit()
	assert_eq(bp.checklist().state("a"), PlanChecklist.DONE)
	assert_eq(bp.move_ship_id(), "")


func test_crew_item_asks_for_the_overlay_and_closes_the_ring() -> void:
	bp.begin_planning(_ships([a, b]))
	watch_signals(bp)
	bp.open_ring("b")
	_choose("crew")
	assert_signal_emitted_with_parameters(bp, "crew_overlay_requested", ["b"])
	assert_false(bp.radial_menu().is_open())


func test_end_planning_closes_everything() -> void:
	bp.begin_planning(_ships([a, b]))
	assert_not_null(bp.badges().pill_for("a"), "a badge per own ship")
	bp.open_ring("b")
	bp.enter_move("a")
	bp.show_course({"used": 1, "allowance": 3}, null)
	bp.open_ring("b")
	bp.end_planning()
	assert_false(bp.radial_menu().is_open())
	assert_eq(bp.move_ship_id(), "")
	assert_false(bp.course_chips().visible)
	assert_null(bp.badges().pill_for("a"))
	assert_eq(bp.checklist().state("a"), "", "no stale checklist entries")
	assert_false(bp.handle_key(KEY_TAB), "keys are not taken outside planning")


# --- piece 2: the Orders ring ----------------------------------------------------------------

const GameControllerScript = preload("res://scripts/core/game_controller.gd")
const SURRENDER_ON := {"optional_rules": {"voluntary_surrender": true}}


func _surrendered(ship: ShipState) -> void:
	ship.status = ShipState.Status.STRUCK
	ship.surrendered = true
	ship.surrenders = 1
	ship.crew_quality = "D"
	ship.morale_rating = 4


## A GameController (not in the tree: no map, no panel), wired as in the game.
func _controller() -> Node:
	var gc: Node = GameControllerScript.new()
	autofree(gc)
	gc.ships_container = Node3D.new()  # the ship views a redraw syncs
	autofree(gc.ships_container)
	return gc


func _escape_scenario(extra := {}) -> Dictionary:
	var s := {
		"optional_rules": {"voluntary_surrender": true},
		"escape": {"0": {"from_turn": 1, "edges": ["W"], "share": 0.5}},
	}
	s.merge(extra, true)
	return s


func test_orders_ring_items_follow_options() -> void:
	GameState.active_scenario = _escape_scenario()
	bp.begin_planning(_ships([a, b]))
	var items := bp.orders_items(a)
	assert_eq(_ids(items), ["lead", "escape", "surrender", "back"] as Array[String],
		"no Rally: she has not surrendered")
	var o: Dictionary = _pc().order_options(0, "a")
	assert_true(_item(items, "lead").is_enabled())
	assert_false(_item(items, "lead").on)
	assert_true(_item(items, "escape").is_enabled())
	var surrender := _item(items, "surrender")
	assert_ne(surrender.off_reason, "", "crew B, no section lost: not eligible")
	assert_eq(surrender.off_reason, o["surrender"]["error"], "the server's reason, verbatim")
	assert_eq(surrender.off_reason, _pc().player_surrender(0, "a", true), "the request agrees")
	assert_eq(_pc().player_set_cast_lead(0, "a", true), "")
	var lead := _item(bp.orders_items(a), "lead")
	assert_true(lead.on, "ordered: drawn on")
	assert_eq(lead.label, "Cast the lead: on")
	assert_eq(_pc().player_declare_escape(0, "a", true), "")
	assert_true(_item(bp.orders_items(a), "escape").on)
	_pc().players_ready[0] = true  # her plan is in: each toggle greyed with the request's reason
	var refused := _item(bp.orders_items(a), "lead")
	assert_ne(refused.off_reason, "")
	assert_eq(refused.off_reason, _pc().player_set_cast_lead(0, "a", false))
	_pc().players_ready[0] = false
	GameState.active_scenario = {}
	assert_eq(_ids(bp.orders_items(a)), ["lead", "back"] as Array[String],
		"no escape edge, no 14.B: hidden, not greyed")


func test_back_returns_to_main_ring() -> void:
	bp.begin_planning(_ships([a, b]))
	watch_signals(bp)
	bp.open_ring("a")
	_choose("orders")
	assert_eq(bp.ring_kind(), BoardPlanning.ORDERS, "Orders opens the second ring")
	assert_eq(bp.ring_ship_id(), "a", "for the same ship, in place")
	assert_eq(_ids(bp._current_items(a))[-1], "back")
	_choose("back")
	assert_eq(bp.ring_kind(), BoardPlanning.MAIN)
	assert_eq(bp.radial_menu().item_count(), 6)
	_choose("orders")
	assert_true(bp.handle_key(KEY_ESCAPE))
	assert_eq(bp.ring_kind(), BoardPlanning.MAIN, "Esc steps back to the main ring")
	assert_true(bp.handle_key(KEY_ESCAPE))
	assert_false(bp.radial_menu().is_open(), "then closes it")
	assert_signal_emit_count(bp, "ring_opened", 1, "switching rings opens no new ring")


func test_order_items_ask_for_the_requests() -> void:
	GameState.active_scenario = SURRENDER_ON
	bp.begin_planning(_ships([a, b]))
	watch_signals(bp)
	bp.open_ring("a")
	_choose("orders")
	_choose("lead")
	assert_signal_emitted_with_parameters(bp, "order_toggled", ["a", "lead", true])
	assert_eq(_pc().player_set_cast_lead(0, "a", true), "")
	_choose("lead")
	assert_signal_emitted_with_parameters(bp, "order_toggled", ["a", "lead", false], 1)
	assert_true(bp.radial_menu().is_open(), "an order keeps the ring open")


func test_order_refusal_shows_in_the_caption() -> void:
	GameState.active_scenario = SURRENDER_ON
	var gc := _controller()
	var board: BoardPlanning = gc._board()
	board.begin_planning(_ships([a, b]))
	board.open_ring("a")
	board.open_orders()
	gc._on_order_toggled("a", "surrender", true)
	var why: String = _pc().order_options(0, "a")["surrender"]["error"]
	assert_ne(why, "")
	assert_eq(board.radial_menu().caption_text(), why, "the server's refusal, in the ring's caption")
	assert_true(board.radial_menu().caption_is_reason())
	assert_eq(board.ring_kind(), BoardPlanning.ORDERS, "the ring stays open")
	assert_false(a.surrender_ordered)
	board.radial_menu().hover_item(0)
	assert_eq(board.radial_menu().caption_text().get_slice("\n", 0), "Cast the lead",
		"hovering another item clears the note")


func test_escape_toggle_refreshes_courses() -> void:
	GameState.active_scenario = _escape_scenario({
		"map_bounds": {"width": 10, "height": 10}, "terrain": {"edges": {"W": "escape"}},
	})
	GameState.environment.wind_direction = 0  # from the east: heading west she runs
	a.hex_position = Vector2i(-5, 0)
	a.facing = 3
	a.speed = 0
	var gc := _controller()
	var board: BoardPlanning = gc._board()
	board.begin_planning(_ships([a, b]))
	board.enter_move("a")
	assert_false(gc._courses["a"]["next_hexes"].has(Vector2i(-6, 0)), "undeclared: the edge is closed")
	board.open_ring("a")
	board.open_orders()
	gc._on_order_toggled("a", "escape", true)
	assert_true(a.escape_declared)
	assert_true(gc._courses["a"]["next_hexes"].has(Vector2i(-6, 0)), "declared: redrawn at once")
	assert_true(_item(board.orders_items(a), "escape").on, "the ring re-reads the order")
	assert_eq(board.radial_menu().caption_text(), "", "no refusal, no note")


func test_rally_result_caption() -> void:
	GameState.active_scenario = SURRENDER_ON
	var dice := ScriptedDice.new()
	GameState.dice = dice
	_surrendered(a)
	var gc := _controller()
	var board: BoardPlanning = gc._board()
	board.begin_planning(_ships([a, b]))
	assert_eq(board.checklist().state("a"), PlanChecklist.LOCKED)
	board.open_ring("a")
	dice.queue([2])
	board.radial_menu().choose(1)  # Rally (Crew & damage is the first)
	assert_eq(board.radial_menu().caption_text(), "Rally: d10 2 against 4 — failed: crew quality now E")
	assert_true(board.radial_menu().caption_is_reason())
	assert_true(a.surrendered, "she stays surrendered")
	var rally := _item(board.ring_items(a), "rally")
	assert_ne(rally.off_reason, "")
	assert_eq(rally.off_reason, _pc().player_rally(0, "a"), "one attempt a g-t: greyed with the reason")
	_pc().current_turn = 2  # the next g-t
	board.refresh_ring()
	dice.queue([7])
	board.radial_menu().choose(1)
	assert_eq(board.radial_menu().caption_text(), "Rally: d10 7 against 4 — she is back in play")
	assert_false(board.radial_menu().caption_is_reason())
	assert_false(a.surrendered)
	assert_eq(board.checklist().state("a"), PlanChecklist.PLAN, "she joins planning")
	assert_true(board.radial_menu().is_open(), "the ring stays open on her")
	assert_eq(board.ring_kind(), BoardPlanning.MAIN)
	assert_true(_item(board.ring_items(a), "move").is_enabled(), "her main ring, Move on")
	assert_true(gc._courses.has("a"), "her default course is drawn")
	assert_eq(BoardPlanning.rally_caption({"roll": 1, "rating": 4, "passed": false, "breaks": true}),
		"Rally: d10 1 against 4 — failed: she has struck for good")


func test_surrendered_ship_ring_has_rally_only() -> void:
	GameState.active_scenario = _escape_scenario()
	_surrendered(a)
	bp.begin_planning(_ships([a, b]))
	assert_eq(bp.checklist().state("a"), PlanChecklist.LOCKED)
	assert_eq(_ids(bp.ring_items(a)), ["crew", "rally"] as Array[String],
		"Crew & damage (read-only) and Rally: nothing else needs her in play")
	assert_eq(_ids(bp.orders_items(a)), ["rally"] as Array[String])
	assert_true(_item(bp.ring_items(a), "rally").is_enabled())
	bp.open_ring("a")
	assert_true(bp.radial_menu().is_open(), "her ring opens")
	assert_eq(bp.radial_menu().subtitle_text(), "Surrendered")
	assert_true(bp.handle_key(KEY_ESCAPE))
	assert_false(bp.radial_menu().is_open(), "Esc closes it: there is no main ring to go back to")
	assert_eq(bp.badges().pill_for("a").text, "SURRENDERED")


func test_badges_show_standing_orders() -> void:
	GameState.active_scenario = _escape_scenario()
	bp.begin_planning(_ships([a, b]))
	assert_eq(bp.badges().marks_for("a"), [] as Array[String])
	assert_eq(_pc().player_set_cast_lead(0, "a", true), "")
	assert_eq(_pc().player_declare_escape(0, "a", true), "")
	a.surrender_ordered = true  # as player_surrender on an eligible ship
	bp.refresh()
	assert_eq(bp.badges().marks_for("a"), ["lead", "escape", "surrender"] as Array[String])
	assert_eq(bp.badges().marks_for("b"), [] as Array[String])
	assert_eq(bp.badges().pill_for("a").text, "PLAN", "the pill keeps her checklist state")
	assert_eq(_pc().player_set_cast_lead(0, "a", false), "")
	bp.refresh()
	assert_eq(bp.badges().marks_for("a"), ["escape", "surrender"] as Array[String])


# --- piece 2: the signal composer and the controller's rulings ---------------------------------

func test_signal_item_opens_composer() -> void:
	bp.begin_planning(_ships([a, b]))
	var item := _item(bp.ring_items(a), "signal")
	assert_true(item.is_enabled(), "no client-made 'coming next': greyed only by the server's error")
	bp.open_ring("a")
	_choose("signal")
	assert_false(bp.radial_menu().is_open(), "opening the composer closes the ring")
	assert_eq(bp.composer_ship_id(), "a")
	assert_eq(bp.signal_composer().title_text(), "Signal from a")
	assert_true(bp.handle_key(KEY_ESCAPE), "Esc closes the composer")
	assert_eq(bp.composer_ship_id(), "")
	_pc().players_ready[0] = true
	var off := _item(bp.ring_items(a), "signal")
	assert_eq(off.off_reason, _pc().order_options(0, "a")["signal"]["error"])
	assert_ne(off.off_reason, "")
	bp.open_composer("a")
	assert_eq(bp.composer_ship_id(), "", "a greyed Signal does not open it")


func test_board_keys_ignored_while_typing() -> void:
	bp.begin_planning(_ships([a, b]))
	_selected = "a"
	bp.open_composer("a")
	bp.signal_composer().field().grab_focus()
	assert_true(bp.signal_composer().is_typing())
	assert_false(bp.handle_key(KEY_TAB), "Tab is the field's")
	assert_false(bp.handle_key(KEY_SPACE))
	assert_false(bp.handle_key(KEY_ENTER))
	assert_eq(bp.ring_ship_id(), "", "no ring opened")
	assert_eq(bp.checklist().state("a"), PlanChecklist.PLAN, "Enter did not mark her Done")
	assert_true(bp.handle_key(KEY_ESCAPE), "Esc still closes the composer")
	assert_true(bp.handle_key(KEY_SPACE), "and the board's keys are back")


func test_signal_send_and_cancel_through_the_controller() -> void:
	var gc := _controller()
	var board: BoardPlanning = gc._board()
	board.begin_planning(_ships([a, b]))
	board.open_composer("a")
	var box := board.signal_composer()
	box.set_text("engage")
	box.send_button().pressed.emit()
	var pending := _pc().pending_signal(0)
	assert_not_null(pending, "the server holds the signal")
	assert_eq(pending.words, ["ENGAGE"] as Array[String])
	assert_true(box.pending_text().contains("To Fleet: ENGAGE"), "the box shows it as pending")
	assert_true(box.pending_text().begins_with("From "), "and which ship sent it")
	assert_false(box.pending_text().contains("replaces"), "no note when opened from the sender")
	assert_eq(box.text(), "", "the field is emptied")
	box.set_text("")
	box.send_button().pressed.emit()
	assert_eq(box.error_text(), "Empty signal", "an empty send is the server's refusal, verbatim")
	assert_eq(_pc().pending_signal(0).words, ["ENGAGE"] as Array[String])
	box.set_text("one two three four four four four four")
	box.send_button().pressed.emit()
	assert_ne(box.error_text(), "", "a refusal shows in the box")
	assert_eq(_pc().pending_signal(0).words, ["ENGAGE"] as Array[String], "and changes nothing")
	box.cancel_button().pressed.emit()
	assert_null(_pc().pending_signal(0))
	assert_eq(box.pending_text(), "")


func test_signal_box_from_another_ship_notes_replacement() -> void:
	var gc := _controller()
	var board: BoardPlanning = gc._board()
	board.begin_planning(_ships([a, b]))
	board.open_composer("a")
	board.signal_composer().set_text("engage")
	board.signal_composer().send_button().pressed.emit()
	board.close_composer()
	board.open_composer("b")
	var line := board.signal_composer().pending_text()
	assert_true(line.contains("From %s" % a.ship_name))
	assert_true(line.contains("Sending replaces it (one signal a turn)"))


func test_crew_overlay_open_closes_the_signal_box() -> void:
	var gc := _controller()
	var board: BoardPlanning = gc._board()
	board.begin_planning(_ships([a, b]))
	board.open_composer("a")
	gc._on_crew_open_changed(true)
	assert_eq(board.composer_ship_id(), "")


func test_ring_hides_the_ships_pill_and_marks() -> void:
	bp.begin_planning(_ships([a, b]))
	assert_eq(bp.badges().hidden_ship(), "")
	bp.open_ring("a")
	assert_eq(bp.badges().hidden_ship(), "a", "her pill and marks would draw over the ring")
	bp.open_ring("b")
	assert_eq(bp.badges().hidden_ship(), "b", "only the ship whose ring is open")
	bp.close_ring()
	assert_eq(bp.badges().hidden_ship(), "", "shown again when the ring closes")


func test_map_click_away_from_the_composer_closes_it() -> void:
	var gc := _controller()
	var board: BoardPlanning = gc._board()
	board.begin_planning(_ships([a, b]))
	board.open_composer("a")
	assert_eq(board.composer_ship_id(), "a")
	gc._handle_planning_click(Vector2(5, 5))  # open sea (no ship under it)
	assert_eq(board.composer_ship_id(), "", "a click on the map away from the box closes it")
	assert_false(board.signal_composer().is_typing(), "and the field gives up the keys")
