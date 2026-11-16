extends GutTest
## Planning panel: one ship's orders are shown at a time, and every control acts on that ship.

const PlanningScene = preload("res://scenes/ui/planning_phase_ui.tscn")

var ui: Control


func _make_ship(id: String, ship_name: String, hex: Vector2i) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": 0, "ship_name": ship_name, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 4,
	})
	state.hex_position = hex
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 4
	return state


func before_each() -> void:
	GameState.clear_ships()
	var a := _make_ship("p1", "HMS Lively", Vector2i(0, 0))
	var b := _make_ship("p2", "HMS Phoebe", Vector2i(3, 0))
	GameState.add_ship(a)
	GameState.add_ship(b)
	ui = PlanningScene.instantiate()
	add_child_autofree(ui)
	var ships: Array[ShipState] = [a, b]
	ui.setup_for_player(ships)


func after_each() -> void:
	GameState.clear_ships()


func test_cards_have_no_movement_button() -> void:
	for id in ["p1", "p2"]:
		assert_null(ui.ship_list_items[id].find_child("MovementButton", true, false), "no Movement button on %s" % id)
	assert_null(ui.find_child("PlottingControls", true, false), "no shared plotting box")


func test_end_planning_is_enabled_with_no_orders_given() -> void:
	assert_false(ui.end_planning_button.disabled)
	assert_eq(ui.end_planning_button.text, "End Planning")
	watch_signals(ui)
	ui.end_planning_button.pressed.emit()
	assert_signal_emitted(ui, "end_planning_pressed")


func test_cancel_asks_before_resetting() -> void:
	watch_signals(ui)
	ui.cancel_button.pressed.emit()
	assert_true(ui.reset_dialog.visible, "the dialog is shown")
	assert_signal_not_emitted(ui, "reset_planning_confirmed")
	assert_eq(ui.reset_dialog.ok_button_text, "Reset")
	assert_eq(ui.reset_dialog.cancel_button_text, "Keep orders")
	ui.reset_dialog.confirmed.emit()
	assert_signal_emit_count(ui, "reset_planning_confirmed", 1)


func test_keeping_orders_emits_nothing() -> void:
	watch_signals(ui)
	ui.cancel_button.pressed.emit()
	ui.reset_dialog.canceled.emit()
	assert_signal_not_emitted(ui, "reset_planning_confirmed")


func test_course_info_on_the_selected_card() -> void:
	ui.select_ship("p2")
	ui.set_course_info("p2", {"used": 3, "allowance": 5, "tacking": "", "steering": "Steering note", "collision": ""})
	var card = ui.ship_list_items["p2"]
	assert_eq(card.course_line.text, "Course: 3 of 5 MP")
	assert_true(card.steering_label.visible)
	assert_eq(card.steering_label.text, "Steering note")
	assert_false(card.tacking_label.visible, "an empty note hides its line")
	assert_false(card.collision_label.visible)


func test_reset_course_button_asks_for_that_ship() -> void:
	ui.select_ship("p2")
	watch_signals(ui)
	ui.ship_list_items["p2"].reset_course_button.pressed.emit()
	assert_signal_emitted_with_parameters(ui, "reset_course_requested", ["p2"])


func test_only_the_selected_card_is_expanded() -> void:
	var open = ui.ship_list_items["p1"]
	var shut = ui.ship_list_items["p2"]
	assert_true(open.status_box.visible, "the selected card shows hull, rigging, crew and guns")
	assert_true(open.action_row.visible, "and its buttons")
	assert_false(shut.status_box.visible, "a collapsed card hides the status box")
	assert_false(shut.action_row.visible, "and its buttons")
	assert_true(shut.health_icon.visible, "but keeps the health icon")
	assert_eq(shut.ship_name_label.text, "HMS Phoebe", "a collapsed card shows the name alone")
	ui.select_ship("p2")
	assert_true(shut.status_box.visible, "selecting a card expands it")
	assert_false(open.status_box.visible, "and collapses the other")


func test_card_titles_carry_no_orders_marks() -> void:
	assert_eq(ui.ship_list_items["p2"].ship_name_label.text, "HMS Phoebe")
	ui.select_ship("p2")
	assert_eq(ui.ship_list_items["p2"].ship_name_label.text, "HMS Phoebe — 38-gun Frigate")


func test_card_speed_shows_the_movement_allowance() -> void:
	const Item = preload("res://scripts/ui/ship_list_item.gd")
	assert_eq(Item.speed_text(3, 5), "Speed 3/5")
	assert_eq(Item.speed_text(0, 0), "Speed 0/0")
	assert_eq(Item.speed_text(2, -1), "Speed 2", "no allowance known: speed alone")


func test_status_box_draws_every_line() -> void:
	var box: ShipCardStatus = ui.ship_list_items["p1"].status_box
	for line in ["HullLine", "RiggingLine", "CrewLine", "MarinesLine", "GunsLine"]:
		assert_not_null(box.find_child(line, true, false), "%s is drawn" % line)
