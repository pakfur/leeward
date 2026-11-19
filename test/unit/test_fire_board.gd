extends GutTest
## FireBoard (board planning piece 3): the fire step's state over a FireOrdersModel. Ring items,
## Plan / Done, target mode, the option box's draft (applied to the model, put back on Cancel) and
## the arrows, against ships placed on GameState (the real GunneryCalculator and MarineFireResolver).

const FirePanel = preload("res://scripts/ui/fire_declaration_panel.gd")

var _old_env: EnvironmentState
var board: FireBoard
var model: FireOrdersModel


func before_each() -> void:
	_old_env = GameState.environment
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	board = FireBoard.new()
	model = FireOrdersModel.new()


func after_each() -> void:
	board.end()
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _armed(id: String, player: int, hex: Vector2i, facing: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British", "rating": 38,
		"class": 3, "maneuverability": "C", "speed_type": "F/F", "rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6], "crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4}})
	state.hex_position = hex
	state.facing = facing
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_side[player].append(id)
	return state


## Places enemy `id` where `side` of "firer" (at the origin, facing E) bears on it with a full,
## low-capable broadside (searched, not hand-placed); false when none was found.
func _place_target(id: String, side: int, rows: Array) -> bool:
	var taken: Array[Vector2i] = []
	for s: ShipState in GameState.get_all_ships():
		taken.append_array(s.occupied_hexes())
	for r in rows:
		for q in range(-8, 4):
			var bow := Vector2i(q, r)
			var stern := HexGrid.stern_of(bow, 0)
			if taken.has(bow) or taken.has(stern):
				continue
			_armed(id, 1, bow, 0)
			var p := GameState.gunnery_calculator.preview(FireRules.make_order("firer", side, id, "full", false, false, 0))
			if p.can_fire and not p.high_only and p.range_hexes >= 2:
				return true
			GameState.ships.erase(id)
			GameState.ships_by_side[1].erase(id)
	return false


## "firer" with a starboard target (t_s) and a port target (t_p).
func _two_sides() -> void:
	_armed("firer", 0, Vector2i.ZERO, 0)
	assert_true(_place_target("t_s", ShipState.STARBOARD, range(3, 9)), "fixture: a starboard target")
	assert_true(_place_target("t_p", ShipState.PORT, range(-3, -9, -1)), "fixture: a port target")


func _begin(ids: Array) -> void:
	model.setup(ids)
	board.begin(model, ids)


func _item(items: Array[RadialItem], id: String) -> RadialItem:
	for item in items:
		if item.id == id:
			return item
	return null


func test_fire_ring_greys_sides_without_targets() -> void:
	_armed("firer", 0, Vector2i.ZERO, 0)
	assert_true(_place_target("t_s", ShipState.STARBOARD, range(3, 9)), "fixture")
	_begin(["firer"])
	var items := board.ring_items("firer")
	var ids: Array = items.map(func(i: RadialItem) -> String: return i.id)
	assert_eq(ids, ["port", "starboard", "bowchase", "sternchase", "marines", "hold", "done"])
	assert_true(_item(items, "starboard").is_enabled())
	assert_false(_item(items, "starboard").on, "no order yet: the board starts with none")
	var port := _item(items, "port")
	assert_false(port.is_enabled(), "no target in the port arc")
	assert_eq(port.off_reason, model.side_reason("firer", ShipState.PORT))
	assert_eq(port.off_reason, FireOrdersModel.NO_SHOT_SIDE_ARC)
	assert_false(_item(items, "marines").is_enabled(), "no enemy alongside")
	assert_eq(_item(items, "marines").off_reason, model.marine_reason("firer"))
	assert_eq(_item(items, "hold").label, "Hold fire")


func test_marine_only_ship_has_marines_item() -> void:
	var firer := _armed("firer", 0, Vector2i.ZERO, 0)
	firer.marine_count = 7
	_armed("foe", 1, Vector2i(2, 0), 0)  # stern (1,0) alongside the firer's bow
	firer.plotted_sections = [0, 1, 2, 3] as Array[int]  # no sailor serves the guns
	_begin(["firer"])
	assert_true(board.has_shot("firer"), "listed for her marines")
	assert_eq(board.state("firer"), PlanChecklist.PLAN)
	var items := board.ring_items("firer")
	assert_true(_item(items, "marines").is_enabled())
	for side_id in ["port", "starboard", "bowchase", "sternchase"]:
		assert_false(_item(items, side_id).is_enabled(), "%s greyed" % side_id)
		assert_eq(_item(items, side_id).off_reason, model.no_shot_reason("firer"), "the guns' reason")
	assert_true(board.enter_target("firer", FireBoard.MARINES))
	assert_eq(board.targets().map(func(t): return t["target_id"]), ["foe"])
	assert_true(board.pick("foe"))
	var box := board.box_content()
	assert_eq(box["kind"], "marines")
	assert_eq(box["title"], "firer → foe · range 1")
	assert_eq(box["text"], FirePanel.marine_option_text(PlanningText.name_and_type(GameState.get_ship("foe")),
		model.marine_targets("firer")[0]["preview"]), "the fire panel's wording, the target named with her type")
	board.confirm_box()
	assert_eq(model.marine_orders(), [{"ship_id": "firer", "target_id": "foe"}])
	assert_true(_item(board.ring_items("firer"), "marines").on)


func test_target_mode_lists_bearing_targets() -> void:
	_armed("firer", 0, Vector2i.ZERO, 0)
	assert_true(_place_target("t0", ShipState.STARBOARD, range(3, 9)), "fixture")
	assert_true(_place_target("t1", ShipState.STARBOARD, range(3, 9)), "fixture")
	assert_true(_place_target("t_p", ShipState.PORT, range(-3, -9, -1)), "fixture")
	_begin(["firer"])
	assert_false(board.enter_target("firer", GunneryTypes.CHASE_BOW), "no chase target: refused")
	assert_true(board.enter_target("firer", ShipState.STARBOARD))
	assert_eq(board.target_ship(), "firer")
	assert_eq(board.target_side(), ShipState.STARBOARD)
	var listed: Array = board.targets().map(func(t): return t["target_id"])
	assert_eq(listed, model.sides_bearing("firer")[ShipState.STARBOARD])
	assert_false(listed.has("t_p"), "the port target is not in the starboard arc")
	for t in board.targets():
		assert_eq(int(t["range"]), int(model.targets("firer", ShipState.STARBOARD)[listed.find(t["target_id"])]["range"]))
	var labels := board.range_labels(GameState.fire_geometry.hex_grid)
	assert_eq(labels.size(), 2)
	assert_eq(labels[0]["text"], "range %d" % int(board.targets()[0]["range"]))
	assert_false(board.pick("t_p"), "not a target of this side")
	board.leave_target()
	assert_eq(board.target_ship(), "")


func test_option_box_confirm_adds_order() -> void:
	_two_sides()
	_begin(["firer"])
	assert_eq(model.orders().size(), 0, "no orders to begin with")
	board.enter_target("firer", ShipState.STARBOARD)
	assert_true(board.pick("t_s"))
	var box := board.box_content()
	assert_eq(box["kind"], "guns")
	assert_string_starts_with(box["title"], "firer → t_s · range ")
	var key := FireOrdersModel.order_key("firer", ShipState.STARBOARD, "t_s", board.box_battery())
	var p: GunneryTypes.ShotPreview = model.order_previews()[key]
	assert_eq(int(box["number"]), p.mgn)
	assert_eq(box["breakdown"], FirePanel.breakdown_text(p))
	var chips: Array = box["batteries"].map(func(c): return c["id"])
	assert_eq(chips, model.battery_options_for("firer", ShipState.STARBOARD, "t_s"))
	board.set_box_high(true)
	board.step_box_reduction(2)
	assert_eq(int(board.box_content()["reduction"]), 2)
	assert_true(board.box_content()["high"])
	assert_eq(board.confirm_box(), "firer")
	assert_false(board.box_open())
	assert_eq(board.target_ship(), "", "target mode closes with the box")
	var orders := model.orders()
	assert_eq(orders.size(), 1)
	assert_eq(orders[0].target_id, "t_s")
	assert_eq(orders[0].aim, "high")
	assert_eq(orders[0].mgn_reduction, 2)
	assert_eq(board.pill("firer"), {"state": PlanBadges.FIRE, "text": ""}, "still in Plan")
	board.set_done("firer", true)
	assert_eq(board.pill("firer"), {"state": PlanBadges.ORDERS, "text": "✓ 1 ORDER"})
	var arrows := board.arrows(GameState.fire_geometry.hex_grid, "")
	assert_eq(arrows.size(), 1)
	assert_eq(arrows[0]["color"], BroadsideColors.color(ShipState.STARBOARD))
	assert_eq(arrows[0]["text"], "high · %d" % model.order_previews().values()[0].mgn)


func test_cancel_puts_the_ship_back() -> void:
	_two_sides()
	_begin(["firer"])
	board.enter_target("firer", ShipState.STARBOARD)
	board.pick("t_s")
	assert_eq(model.orders().size(), 1, "the draft is in the model while the box is open")
	board.cancel_box()
	assert_eq(model.orders().size(), 0, "Cancel puts it back")
	assert_eq(board.target_ship(), "firer", "target mode stays")
	board.pick("t_s")
	board.leave_target()
	assert_eq(model.orders().size(), 0, "leaving target mode cancels the box too")


func test_second_target_changes_number() -> void:
	_two_sides()
	_begin(["firer"])
	board.enter_target("firer", ShipState.STARBOARD)
	board.pick("t_s")
	board.confirm_box()
	var s_key := FireOrdersModel.order_key("firer", ShipState.STARBOARD, "t_s", "full")
	var alone: int = model.order_previews()[s_key].mgn
	board.enter_target("firer", ShipState.PORT)
	board.pick("t_p")
	var box := board.box_content()
	var whole := GameState.gunnery_calculator.preview_orders(model.orders())
	var p_key := FireOrdersModel.order_key("firer", ShipState.PORT, "t_p", "full")
	var by_key := {}
	for p in whole:
		by_key[FireOrdersModel.order_key(p.order.ship_id, p.order.side, p.order.target_id, p.order.battery)] = p
	assert_eq(int(box["number"]), by_key[p_key].mgn, "the box shows preview_orders over the whole set")
	var two := DataManager.combat_tables.flat_modifier("two_targets")
	assert_eq(by_key[s_key].mgn, alone + two, "the first shot loses the two-target modifier too")
	assert_eq(box["two_target"], FirePanel.two_target_note(two, false))
	board.cancel_box()
	assert_eq(model.order_previews()[s_key].mgn, alone, "cancelled: one target again")


func test_hold_fire_clears_and_marks_done() -> void:
	_two_sides()
	_begin(["firer"])
	board.enter_target("firer", ShipState.STARBOARD)
	board.pick("t_s")
	board.confirm_box()
	assert_eq(_item(board.ring_items("firer"), "hold").label, "Clear orders")
	model.hold_fire("firer")
	board.set_done("firer", true)
	assert_eq(model.orders().size(), 0)
	assert_eq(board.state("firer"), PlanChecklist.DONE)
	assert_eq(board.pill("firer")["state"], PlanBadges.NO_FIRE)
	assert_eq(_item(board.ring_items("firer"), "undo").label, "Change orders")
	assert_eq(board.ships_without_orders(), 1)


func test_no_shot_ship_starts_done_with_reason() -> void:
	var firer := _armed("firer", 0, Vector2i.ZERO, 0)
	assert_true(_place_target("t_s", ShipState.STARBOARD, range(3, 9)), "fixture")
	firer.plotted_sections = [0, 1, 2, 3] as Array[int]  # no crew to serve the guns
	firer.marine_count = 0
	_begin(["firer"])
	assert_false(board.has_shot("firer"))
	assert_eq(board.state("firer"), PlanChecklist.DONE)
	assert_eq(board.pill("firer")["state"], PlanBadges.NO_TARGET, "never a FIRE pill")
	assert_eq(board.no_shot_reason("firer"), FireOrdersModel.NO_SHOT_CREW)
	assert_eq(board.subtitle("firer"), "No shot: %s" % FireOrdersModel.NO_SHOT_CREW)
	for item in board.ring_items("firer"):
		assert_false(item.is_enabled(), "%s greyed" % item.id)
	board.set_done("firer", false)
	assert_eq(board.state("firer"), PlanChecklist.DONE, "she cannot go back to Plan")


func test_struck_and_surrendering_ships_start_done() -> void:
	var a := _armed("firer", 0, Vector2i.ZERO, 0)
	assert_true(_place_target("t_s", ShipState.STARBOARD, range(3, 9)), "fixture")
	a.surrender_ordered = true
	_begin(["firer"])
	assert_eq(board.pill("firer")["state"], PlanBadges.NO_TARGET)
	assert_eq(board.no_shot_reason("firer"), FireOrdersModel.NO_SHOT_SURRENDERING)
