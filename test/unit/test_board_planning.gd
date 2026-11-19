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
		if bp.ring_items(GameState.get_ship(bp.ring_ship_id()))[i].id == id:
			menu.choose(i)
			return
	fail_test("no ring item " + id)


func test_ring_items_for_movable_ship() -> void:
	_pc()._enter_planning_phase()  # stores the default course and the planning snapshot
	bp.begin_planning(_ships([a, b]))
	var items := bp.ring_items(a)
	assert_eq(_ids(items), ["move", "crew", "reset", "done"] as Array[String])
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
	assert_eq(menu.item_count(), 4)
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
