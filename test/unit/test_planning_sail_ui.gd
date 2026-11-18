extends GutTest
## Tests for PlanningSailUi: sail names, the sail-change wording and the ship status badges.


func _ship(sail: String = "MS") -> ShipState:
	var state := ShipState.new()
	state.sail_state = sail
	state.rigging_current_hp = [4, 4, 4, 4]
	return state


func test_sail_label_is_the_name_without_code() -> void:
	assert_eq(PlanningSailUi.sail_label("FS"), "Fighting sail")
	assert_eq(PlanningSailUi.sail_label("ms"), "Manoeuvring sail")
	assert_eq(PlanningSailUi.sail_label("PS"), "Plain sail")
	assert_eq(PlanningSailUi.sail_label("NS"), "Furled")


func test_button_text_singular_and_plural() -> void:
	assert_eq(PlanningSailUi.target_button_text("FS", {"turns": 1, "sections": 1}), "Fighting sail — 1 turn, 1 section")
	assert_eq(PlanningSailUi.target_button_text("PS", {"turns": 2, "sections": 2}), "Plain sail — 2 turns, 2 sections")
	assert_eq(PlanningSailUi.target_button_text("MS", {"turns": 3, "sections": 2}), "Manoeuvring sail — 3 turns, 2 sections")


func test_status_badge_priority() -> void:
	var state := _ship()
	assert_eq(PlanningSailUi.status_badge(state), "")
	state.fouled_with = "other"
	assert_eq(PlanningSailUi.status_badge(state), "FOULED")
	state.rigging_current_hp = [0, 0, 0, 0]
	assert_eq(PlanningSailUi.status_badge(state), "DISMASTED")
	state.status = ShipState.Status.STRUCK
	assert_eq(PlanningSailUi.status_badge(state), "STRUCK")


func test_movement_blocked_with_reason_when_badged() -> void:
	var state := _ship()
	assert_true(PlanningSailUi.can_plot_movement(state))
	assert_eq(PlanningSailUi.movement_block_reason(state), "")
	state.fouled_with = "other"
	assert_false(PlanningSailUi.can_plot_movement(state))
	assert_string_contains(PlanningSailUi.movement_block_reason(state), "fouled")
	state.fouled_with = ""
	state.status = ShipState.Status.STRUCK
	assert_false(PlanningSailUi.can_plot_movement(state))
	assert_string_contains(PlanningSailUi.movement_block_reason(state), "struck")


func test_destroyed_ship_cannot_plot() -> void:
	var state := _ship("MS")
	state.status = ShipState.Status.DESTROYED
	assert_eq(PlanningSailUi.status_badge(state), "DESTROYED")
	assert_false(PlanningSailUi.can_plot_movement(state))
	assert_eq(PlanningSailUi.movement_block_reason(state), "Ship has been destroyed.")


func test_surrendered_badge() -> void:
	var s := _ship()
	s.status = ShipState.Status.STRUCK
	assert_eq(PlanningSailUi.status_badge(s), "STRUCK")
	s.surrendered = true
	assert_eq(PlanningSailUi.status_badge(s), "SURRENDERED")
	assert_eq(ShipStatusBars.last_line(s, ""), ["Status", "Surrendered"] as Array[String])
	var o := _ship()
	o.surrender_ordered = true
	assert_true(PlanningSailUi.card_badge(o).contains("SURRENDERING"))
