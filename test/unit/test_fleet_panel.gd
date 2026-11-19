extends GutTest
## FleetPanel: the side panel for the whole turn (Players, Your ships, a footer slot).

var panel: FleetPanel


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
	panel = FleetPanel.new()
	add_child_autofree(panel)
	panel.setup(0)


func after_each() -> void:
	GameState.clear_ships()


func _ships(list: Array) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for s in list:
		out.append(s)
	return out


func _card_order() -> Array:
	var ids := []
	for child in panel.ship_list.get_children():
		if not child.is_queued_for_deletion():
			ids.append(child.ship_state.ship_id)
	return ids


func test_cards_added_updated_removed() -> void:
	var a := _make_ship("a", "HMS Lively", Vector2i(0, 0))
	var b := _make_ship("b", "HMS Phoebe", Vector2i(3, 0))
	panel.refresh_ships(_ships([a, b]))
	assert_eq(_card_order(), ["a", "b"])
	assert_eq(panel.selected_ship_id, "a", "the first card is selected")
	assert_true(panel.card("a").is_selected, "and expanded")
	var card_b: Control = panel.card("b")
	# A prize taken joins; a renamed (redrawn) ship keeps her card; order follows the list.
	var c := _make_ship("c", "Le Prize", Vector2i(6, 0))
	b.ship.ship_name = "HMS Phoebe II"
	panel.refresh_ships(_ships([c, b, a]))
	assert_eq(_card_order(), ["c", "b", "a"])
	assert_eq(panel.card("b"), card_b, "a known ship keeps her card")
	assert_eq(card_b.ship_name_label.text, "HMS Phoebe II", "and it is redrawn")
	assert_eq(panel.selected_ship_id, "a", "the selection is kept")
	# The selected ship is lost: her card leaves and the first card is selected.
	var card_a: Control = panel.card("a")
	panel.refresh_ships(_ships([c, b]))
	assert_eq(_card_order(), ["c", "b"])
	assert_null(panel.card("a"))
	assert_true(card_a.is_queued_for_deletion(), "the card is freed")
	assert_eq(panel.selected_ship_id, "c")
	# A new game: no cards.
	panel.setup(0)
	assert_eq(_card_order(), [])
	assert_eq(panel.selected_ship_id, "")


func test_footer_swaps() -> void:
	assert_null(panel.footer())
	var one := Button.new()
	panel.set_footer(one)
	assert_eq(one.get_parent(), panel.footer_slot, "the footer is in the slot")
	assert_eq(panel.get_child(panel.get_child_count() - 1), panel.footer_slot, "pinned at the bottom")
	var two := Label.new()
	panel.set_footer(two)
	assert_eq(panel.footer(), two)
	assert_eq(panel.footer_slot.get_children(), [two], "one footer at a time")
	assert_true(one.is_queued_for_deletion(), "the old footer is freed")
	panel.set_footer(two)
	assert_false(two.is_queued_for_deletion(), "setting the same footer again keeps it")
	panel.set_footer(null)
	assert_null(panel.footer())
	assert_eq(panel.footer_slot.get_child_count(), 0, "null clears the slot")
	assert_true(two.is_queued_for_deletion())


func test_card_press_signal() -> void:
	var a := _make_ship("a", "HMS Lively", Vector2i(0, 0))
	var b := _make_ship("b", "HMS Phoebe", Vector2i(3, 0))
	panel.refresh_ships(_ships([a, b]))
	watch_signals(panel)
	panel.select_ship("b")
	assert_signal_not_emitted(panel, "ship_card_pressed", "a selection made by code emits nothing")
	assert_true(panel.card("b").is_selected)
	assert_false(panel.card("a").is_selected, "the other card collapses")
	panel.card("a").selected.emit()
	assert_signal_emitted_with_parameters(panel, "ship_card_pressed", ["a"])
	assert_eq(panel.selected_ship_id, "a", "a click selects the card")
	panel.card("b").crew_pressed.emit()
	assert_signal_emitted_with_parameters(panel, "crew_overlay_requested", ["b"])
	panel.card("b").set_plan_state(PlanChecklist.PLAN)
	panel.card("b").pill.pressed.emit()
	assert_signal_emitted_with_parameters(panel, "pill_pressed", ["b"])
	panel.select_ship("nobody")
	assert_eq(panel.selected_ship_id, "", "an unknown ship selects nothing")


func test_roster_shown() -> void:
	assert_false(panel.roster.visible, "no rows: no Players section")
	assert_false(panel.players_header.visible)
	var rows := [
		{"id": 0, "name": "You", "side": 0, "is_ai": false, "is_local": true, "state": RosterRows.PLANNING, "ships": 2},
		{"id": 1, "name": "Player 1", "side": 1, "is_ai": true, "is_local": false, "state": RosterRows.READY, "ships": 2},
	]
	panel.refresh_roster(rows)
	assert_true(panel.roster.visible)
	assert_true(panel.players_header.visible)
	assert_eq(panel.players_header.text, "Players")
	assert_eq(panel.roster.get_child_count(), 2, "a row per player")
	var texts := []
	for label in panel.roster.find_children("*", "Label", true, false):
		texts.append(label.text)
	for t in ["You", "Player 1", "AI", "planning", "ready"]:
		assert_has(texts, t)
	assert_lt(panel.roster.get_index(), panel.ship_list.get_parent().get_index(), "Players above Your ships")
	panel.refresh_roster([])
	assert_false(panel.roster.visible)


## The pills belong to the footer's step: a new footer (or none) hides the last step's pills, so the
## fire step's FIRE / NO TARGET do not stay on the cards into POST_COMBAT.
func test_footer_change_hides_the_pills() -> void:
	var a := _make_ship("a", "HMS Lively", Vector2i(0, 0))
	panel.refresh_ships(_ships([a]))
	panel.set_footer(Button.new())
	panel.card("a").set_plan_state(PlanChecklist.PLAN, "FIRE")
	assert_true(panel.card("a").pill.visible)
	panel.set_footer(panel.footer())
	assert_true(panel.card("a").pill.visible, "the same footer again keeps them")
	panel.set_footer(Label.new())
	assert_false(panel.card("a").pill.visible, "another footer: hidden until it sets its own")
	panel.card("a").set_plan_state(PlanChecklist.DONE)
	panel.set_footer(null)
	assert_false(panel.card("a").pill.visible, "no footer: no pills")
