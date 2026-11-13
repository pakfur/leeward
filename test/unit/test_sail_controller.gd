extends GutTest
## Tests for SailController: plotted sail changes (Close Action 1997, 8).

var ctrl: SailController
var ship: ShipState
var _old_log: PhaseEvents.PhaseLog
var _old_phase: TurnPhaseController.GamePhase


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_old_log = GameState.turn_log
	_old_phase = GameState.phase_controller.current_phase
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.phase_controller.current_phase = TurnPhaseController.GamePhase.PLANNING
	ctrl = SailController.new(GameState)
	ship = _make_ship("sail_ship")


func after_each() -> void:
	GameState.turn_log = _old_log
	GameState.phase_controller.current_phase = _old_phase
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, sail: String = "MS", quality: String = "D") -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id,
		"player_id": 0,
		"ship_name": id,
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "C",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.sail_state = sail
	state.crew_quality = quality
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	GameState.ships[id] = state
	GameState.ships_by_player[0].append(id)
	return state


func test_available_targets_full_rigging_at_ms() -> void:
	assert_eq(ctrl.available_targets("sail_ship"), ["FS", "PS"] as Array[String])


func test_available_targets_capped_by_rigging_level_3() -> void:
	ship.rigging_current_hp = [0, 5, 6, 6] as Array[int]
	assert_eq(ship.rigging_level(), 3)
	assert_eq(ctrl.available_targets("sail_ship"), ["FS"] as Array[String])


func test_available_targets_at_ps_with_level_3() -> void:
	ship.rigging_current_hp = [0, 5, 6, 6] as Array[int]
	ship.sail_state = "PS"
	assert_eq(ctrl.available_targets("sail_ship"), ["MS"] as Array[String])


func test_available_targets_at_ps_with_level_2_offers_downward_step() -> void:
	ship.rigging_current_hp = [0, 0, 6, 6] as Array[int]
	ship.sail_state = "PS"
	assert_eq(ship.rigging_level(), 2)
	assert_eq(ctrl.available_targets("sail_ship"), ["MS"] as Array[String])


func test_available_targets_empty_when_struck() -> void:
	ship.status = ShipState.Status.STRUCK
	assert_eq(ctrl.available_targets("sail_ship"), [] as Array[String])


func test_available_targets_empty_when_dismasted() -> void:
	ship.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(ctrl.available_targets("sail_ship"), [] as Array[String])


func test_available_targets_empty_when_change_in_progress() -> void:
	ship.sail_change = {"target": "FS", "turns_left": 1, "sections": [3]}
	assert_eq(ctrl.available_targets("sail_ship"), [] as Array[String])


func test_change_cost_ms_to_fs() -> void:
	assert_eq(ctrl.change_cost("sail_ship", "FS"), {"turns": 1, "sections": 1})


func test_change_cost_ms_to_ps() -> void:
	assert_eq(ctrl.change_cost("sail_ship", "PS"), {"turns": 2, "sections": 2})


func test_change_cost_ms_to_ps_green_crew_adds_a_turn() -> void:
	ship.crew_quality = "E"
	assert_eq(ctrl.change_cost("sail_ship", "PS").turns, 3)


func test_change_cost_fs_to_ns() -> void:
	ship.sail_state = "FS"
	assert_eq(ctrl.change_cost("sail_ship", "NS"), {"turns": 1, "sections": 1})


func test_one_turn_change_uses_section_3_and_completes() -> void:
	assert_eq(ctrl.plot_sail_change(0, "sail_ship", "FS"), "")
	assert_eq(ship.plotted_actions["sail_change"], "FS")
	ctrl.begin_plotted_changes()
	assert_eq(ship.sail_change.get("sections"), [3])
	assert_eq(ship.sail_change.get("turns_left"), 1)
	assert_eq(ship.sections_able_to_fire(), 3)
	assert_eq(ship.sail_state, "MS")
	ctrl.advance_changes(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(ship.sail_state, "FS")
	assert_eq(ship.sail_change, {})


func test_two_turn_change_completes_on_second_advance() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "PS")
	ctrl.begin_plotted_changes()
	assert_eq(ship.sail_change.get("sections"), [3, 2])
	assert_eq(ship.sections_able_to_fire(), 2)
	ctrl.advance_changes(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(ship.sail_state, "MS")
	ctrl.advance_changes(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(ship.sail_state, "PS")
	assert_eq(ship.sail_change, {})


func test_begin_logs_event_with_turns_left() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "PS")
	ctrl.begin_plotted_changes()
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("from"), "MS")
	assert_eq(events[0].data.get("to"), "PS")
	assert_eq(events[0].data.get("turns_left"), 2)


func test_plot_consumed_even_when_cleared_after_movement() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	ctrl.begin_plotted_changes()
	GameState.ship_controller.clear_plotted_actions("sail_ship")
	assert_eq(ship.sail_change.get("target"), "FS")


func test_empty_target_clears_plot() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	assert_eq(ctrl.plot_sail_change(0, "sail_ship", ""), "")
	assert_eq(ship.plotted_actions["sail_change"], "")
	ctrl.begin_plotted_changes()
	assert_eq(ship.sail_change, {})


func test_plot_non_adjacent_state_is_error() -> void:
	assert_ne(ctrl.plot_sail_change(0, "sail_ship", "NS"), "")


func test_plot_state_above_max_is_error() -> void:
	ship.rigging_current_hp = [0, 5, 6, 6] as Array[int]
	assert_ne(ctrl.plot_sail_change(0, "sail_ship", "PS"), "")


func test_plot_other_players_ship_is_error() -> void:
	assert_ne(ctrl.plot_sail_change(1, "sail_ship", "FS"), "")


func test_plot_outside_planning_is_error() -> void:
	GameState.phase_controller.current_phase = TurnPhaseController.GamePhase.COMBAT_RESOLUTION
	assert_ne(ctrl.plot_sail_change(0, "sail_ship", "FS"), "")


func test_plot_while_change_in_progress_is_error() -> void:
	ship.sail_change = {"target": "FS", "turns_left": 1, "sections": [3]}
	assert_ne(ctrl.plot_sail_change(0, "sail_ship", "FS"), "")


func test_plot_when_struck_is_error() -> void:
	ship.status = ShipState.Status.STRUCK
	assert_ne(ctrl.plot_sail_change(0, "sail_ship", "FS"), "")


func test_no_crew_drops_order() -> void:
	ship.crew_count = [0, 0, 0, 0] as Array[int]
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	ctrl.begin_plotted_changes()
	assert_eq(ship.sail_change, {})
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("cancelled"), "no crew")


func test_section_emptied_mid_change_cancels() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	ctrl.begin_plotted_changes()
	ship.crew_count = [3, 3, 3, 0] as Array[int]
	ctrl.advance_changes(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(ship.sail_state, "MS")
	assert_eq(ship.sail_change, {})
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events[events.size() - 1].data.has("cancelled"), true)


func test_dismasted_mid_change_cancels() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	ctrl.begin_plotted_changes()
	ship.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	ctrl.advance_changes(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(ship.sail_state, "MS")
	assert_eq(ship.sail_change, {})


func test_struck_mid_change_cancels() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	ctrl.begin_plotted_changes()
	ship.status = ShipState.Status.STRUCK
	ctrl.advance_changes(TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
	assert_eq(ship.sail_state, "MS")
	assert_eq(ship.sail_change, {})
