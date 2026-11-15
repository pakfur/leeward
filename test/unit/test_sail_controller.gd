extends GutTest
## Tests for SailController: plotted sail changes (Close Action 1997, 5.F.6-9), worked as SAIL crew
## tasks by CrewTaskController (4.A.3, 4.B). Every ship is on Automatic: the sections come from
## CrewAuto's worker order M, S4, S3, S2, S1 (crew-tasks spec §3.3 A3).
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT

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
	state.marine_count = 2
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


func test_available_targets_empty_when_destroyed() -> void:
	ship.status = ShipState.Status.DESTROYED
	assert_eq(ctrl.available_targets("sail_ship"), [] as Array[String])


func test_plot_when_destroyed_is_error() -> void:
	ship.status = ShipState.Status.DESTROYED
	assert_eq(ctrl.plot_sail_change(0, "sail_ship", "FS"), "Ship is destroyed")


func test_available_targets_empty_when_dismasted() -> void:
	ship.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(ctrl.available_targets("sail_ship"), [] as Array[String])


func test_available_targets_empty_when_change_in_progress() -> void:
	CrewFixtures.give_sail_change(ship, "FS", [3])
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


func test_one_turn_change_uses_marines_and_completes() -> void:
	# Spec §3.3 A3: the worker order starts with the marines, so the guns keep all four sections
	# (4.B.4). Ship log FS: 1 CS, 1 g-t at CQ D.
	assert_eq(ctrl.plot_sail_change(0, "sail_ship", "FS"), "")
	assert_eq(ship.ordered_sail_target(), "FS")
	_begin()
	assert_eq(ship.sail_change_info().get("sections"), [ShipState.MARINES])
	assert_eq(ship.sail_change_info().get("turns_left"), 1)
	assert_eq(ship.sections_able_to_fire(), 4)
	assert_eq(ship.sail_state, "MS")
	_advance()
	assert_eq(ship.sail_state, "FS")
	assert_eq(ship.sail_change_info(), {})


func test_two_turn_change_completes_on_second_advance() -> void:
	# Ship log PS: 2 CS, 2 g-t's at CQ D. Spec §3.3 worker order: M, then S4 (4.B.4: one sailor
	# section off the guns).
	ctrl.plot_sail_change(0, "sail_ship", "PS")
	_begin()
	assert_eq(ship.sail_change_info().get("sections"), [3, ShipState.MARINES])
	assert_eq(ship.sections_able_to_fire(), 3)
	_advance()
	assert_eq(ship.sail_state, "MS")
	_advance()
	assert_eq(ship.sail_state, "PS")
	assert_eq(ship.sail_change_info(), {})


func test_begin_logs_event_with_turns_left() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "PS")
	_begin()
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("from"), "MS")
	assert_eq(events[0].data.get("to"), "PS")
	assert_eq(events[0].data.get("turns_left"), 2)


func test_plot_consumed_even_when_cleared_after_movement() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	GameState.ship_controller.clear_plotted_actions("sail_ship")
	assert_eq(ship.sail_change_info().get("target"), "FS")


func test_replotting_movement_keeps_sail_order() -> void:
	# GameController clears only the movement plot when the player re-plots a ship
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	GameState.ship_controller.set_plotted_movement("sail_ship", [{"hex": {"q": 1, "r": 0}, "facing": 0}])
	GameState.ship_controller.set_plotted_movement("sail_ship", [])
	assert_eq(ship.plotted_actions["movement"], [], "the old movement plot is gone")
	assert_eq(ship.ordered_sail_target(), "FS", "the sail order survives the re-plot")
	_begin()
	assert_eq(ship.sail_change_info().get("target"), "FS", "and the change still starts")


func test_empty_target_clears_plot() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	assert_eq(ctrl.plot_sail_change(0, "sail_ship", ""), "")
	assert_eq(ship.ordered_sail_target(), "")
	_begin()
	assert_eq(ship.sail_change_info(), {})


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
	CrewFixtures.give_sail_change(ship, "FS", [3])
	assert_ne(ctrl.plot_sail_change(0, "sail_ship", "FS"), "")


func test_plot_when_struck_is_error() -> void:
	ship.status = ShipState.Status.STRUCK
	assert_ne(ctrl.plot_sail_change(0, "sail_ship", "FS"), "")


func test_no_crew_drops_order() -> void:
	ship.crew_count = [0, 0, 0, 0] as Array[int]
	ship.marine_count = 0
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	assert_eq(ship.sail_change_info(), {})
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("cancelled"), "no crew")


func test_section_emptied_mid_change_cancels() -> void:
	# 4.B.3: the section working the sails is wiped out; the change is lost.
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	assert_eq(ship.sail_change_info().get("sections"), [ShipState.MARINES])
	ship.marine_count = 0
	_advance()
	assert_eq(ship.sail_state, "MS")
	assert_eq(ship.sail_change_info(), {})
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events[events.size() - 1].data.has("cancelled"), true)


func test_dismasted_mid_change_cancels() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	ship.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	_advance()
	assert_eq(ship.sail_state, "MS")
	assert_eq(ship.sail_change_info(), {})


func test_struck_mid_change_cancels() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	ship.status = ShipState.Status.STRUCK
	_advance()
	assert_eq(ship.sail_state, "MS")
	assert_eq(ship.sail_change_info(), {})


func test_destroyed_mid_change_cancels() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	ship.status = ShipState.Status.DESTROYED
	_advance()
	assert_eq(ship.sail_state, "MS")
	assert_eq(ship.sail_change_info(), {})
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events[events.size() - 1].data.get("cancelled"), "destroyed")


# --- Lines Jammed (Rigging #5, 5.F.9c) ---

func _begin() -> void:
	GameState.crew_task_controller.begin_turn_tasks(MOVE)


func _advance() -> void:
	GameState.crew_task_controller.advance_tasks(STATUS)


func _jam_lines() -> void:
	GameState.ship_controller.add_critical_effect("sail_ship", {"id": "lines_jammed"})


func test_lines_jammed_refuses_plotting() -> void:
	_jam_lines()
	assert_eq(ctrl.available_targets("sail_ship"), [] as Array[String])
	assert_eq(ctrl.plot_sail_change(0, "sail_ship", "FS"), "Lines jammed")
	assert_eq(ship.ordered_sail_target(), "")


func test_lines_jammed_still_allows_clearing_the_plot() -> void:
	_jam_lines()
	assert_eq(ctrl.plot_sail_change(0, "sail_ship", ""), "")


func test_lines_jammed_drops_a_plotted_order_at_begin() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_jam_lines()
	_begin()
	assert_eq(ship.sail_change_info(), {})
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events.size(), 1)
	assert_eq(events[0].data.get("cancelled"), "lines jammed")


func test_cancel_change_logs_the_reason() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "PS")
	_begin()
	assert_true(ship.has_sail_change())
	assert_true(ctrl.cancel_change("sail_ship", "lines jammed", TurnPhaseController.GamePhase.COMBAT_RESOLUTION))
	assert_eq(ship.sail_change_info(), {})
	assert_eq(ship.sail_state, "MS")
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events[events.size() - 1].data, {"from": "MS", "to": "PS", "turns_left": 2,
		"cancelled": "lines jammed"})
	assert_eq(events[events.size() - 1].to_text({"sail_ship": "Vengeance"}),
		"Vengeance: sail change to plain sail (PS) cancelled: the lines are jammed")
	assert_false(ctrl.cancel_change("sail_ship", "lines jammed", TurnPhaseController.GamePhase.COMBAT_RESOLUTION),
		"nothing left to cancel")


func test_lines_jammed_cancels_in_advance_changes() -> void:
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	_jam_lines()
	_advance()
	assert_eq(ship.sail_state, "MS")
	var events := GameState.turn_log.of_type(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(events[events.size() - 1].data.get("cancelled"), "lines jammed")


# --- Crew sections (4.B, spec §3.3) ---

func test_marines_held_back_when_fouled_s4_alters_sail() -> void:
	# Spec §3.3: a fouled ship keeps its marines free for the unfouling roll (+1 if busy), so the
	# worker order starts at S4.
	ship.fouled_with = "someone"
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	assert_eq(ship.sail_change_info().get("sections"), [3])
	assert_eq(ship.sections_able_to_fire(), 3, "4.B.4: one sailor section off the guns")


func test_marines_lost_s4_alters_sail() -> void:
	# Spec §3.3 worker order M, S4, ...: an eliminated section is passed over.
	ship.marine_count = 0
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	assert_eq(ship.sail_change_info().get("sections"), [3])


func test_green_crew_needs_two_turns_for_minor_change() -> void:
	# Ship log: FS<->MS takes 1 g-t at CQ A-D, 2 at CQ E-G.
	ship.crew_quality = "E"
	ctrl.plot_sail_change(0, "sail_ship", "FS")
	_begin()
	_advance()
	assert_eq(ship.sail_state, "MS", "1 of 2 g-t's done")
	assert_eq(ship.sail_change_info().get("turns_left"), 1)
	_advance()
	assert_eq(ship.sail_state, "FS")


func test_change_in_progress_keeps_its_sections_next_turn() -> void:
	# 5.F.9 / 4.A.3: a sail change must be continued by the same sections until complete; the
	# plan cannot move them (A0 locked), and the second g-t completes it.
	ctrl.plot_sail_change(0, "sail_ship", "PS")
	_begin()
	_advance()
	var seq: int = ship.tasks_with("SAIL")[0]["seq"]
	GameState.ship_controller.clear_turn_flags("sail_ship")
	assert_eq(ship.plotted_sections, [] as Array[int])
	ship.plotted_actions["crew_assignments"] = {}
	_begin()
	assert_eq(ship.tasks_with("SAIL")[0]["seq"], seq, "the same task continues")
	assert_eq(ship.plotted_sections, [3, ShipState.MARINES] as Array[int])
	_advance()
	assert_eq(ship.sail_state, "PS", "5.F.8: complete after 2 g-t's")
