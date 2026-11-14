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


func test_movement_on_another_card_selects_that_ship() -> void:
	assert_eq(ui.selected_ship_id, "p1")
	watch_signals(ui)
	ui._on_action_button_pressed("p2", "movement")
	assert_eq(ui.selected_ship_id, "p2", "the ship whose Movement was pressed is selected")
	assert_true(ui.ship_list_items["p2"].is_selected, "its card is highlighted")
	assert_false(ui.ship_list_items["p1"].is_selected, "the other card is not")
	assert_signal_emitted_with_parameters(ui, "ship_selected", ["p2"])
	assert_signal_emitted_with_parameters(ui, "action_toggled", ["p2", "movement", true])


func test_sail_choice_after_movement_orders_the_selected_ship() -> void:
	ui._on_action_button_pressed("p2", "movement")
	watch_signals(ui)
	ui._request_sail_change("FS")
	assert_signal_emitted_with_parameters(ui, "sail_change_requested", ["p2", "FS"])


func test_movement_on_a_new_ship_releases_the_other_ships_movement_button() -> void:
	ui._on_action_button_pressed("p1", "movement")
	ui._on_action_button_pressed("p2", "movement")
	assert_false(ui.get_action_state("p1", "movement"), "only one ship plots at a time")
	assert_true(ui.get_action_state("p2", "movement"))


func test_plotting_controls_select_their_ship() -> void:
	ui.show_plotting_controls("p2", 4, 4, 2, 1, true)
	assert_eq(ui.selected_ship_id, "p2")


func test_submit_follows_the_server_on_an_empty_path() -> void:
	ui.show_plotting_controls("p1", 4, 4, 2, 1, true)
	assert_false(ui.submit_button.disabled, "staying put is allowed: Submit is enabled")
	assert_eq(ui.submit_button.text, "Submit (hold position)")
	assert_true(ui.undo_button.disabled, "nothing to undo")
	assert_true(ui.undo_all_button.disabled, "nothing to undo")


func test_submit_disabled_when_server_refuses() -> void:
	ui.show_plotting_controls("p1", 4, 4, 2, 1, false)
	assert_true(ui.submit_button.disabled)


func test_submit_and_undo_after_a_step() -> void:
	ui.show_plotting_controls("p1", 4, 4, 2, 1, true)
	var step := MovementTypes.PlotStep.new()
	step.hex = Vector2i(1, 0)
	ui.update_plotting_state([step], 3, true)
	assert_eq(ui.submit_button.text, "Submit")
	assert_false(ui.submit_button.disabled)
	assert_false(ui.undo_button.disabled)
	assert_false(ui.undo_all_button.disabled)
	ui.update_plotting_state([], 4, true)
	assert_eq(ui.submit_button.text, "Submit (hold position)")
	assert_true(ui.undo_button.disabled)
