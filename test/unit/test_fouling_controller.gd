extends GutTest
## Tests for FoulingController (Close Action 1997 Unfouling table).
## Roll d10 + skill modifier <= success number (attempt 1: 2, attempt 2: 3, attempt 3+: 4).

const PHASE := 6

var controller: FoulingController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_turning_table()


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	controller = FoulingController.new(GameState)


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, quality: String = "D", player: int = 0) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
	})
	state.player_id = player
	state.hex_position = hex
	state.facing = 1
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.marine_count = 2
	state.crew_quality = quality
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


func _foul_pair(quality_a: String = "D", quality_b: String = "D") -> Array[ShipState]:
	var a := _make_ship("a", Vector2i(5, 5), quality_a, 0)
	var b := _make_ship("b", Vector2i(4, 5), quality_b, 1)
	GameState.ship_controller.set_fouled_with("a", "b")
	GameState.ship_controller.set_fouled_with("b", "a")
	return [a, b]


func _events() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.UNFOUL)


func test_first_attempt_roll_2_frees_pair() -> void:
	var ships := _foul_pair()
	_dice.queue([2])
	controller.resolve_unfouling(PHASE)
	assert_eq(ships[0].fouled_with, "")
	assert_eq(ships[1].fouled_with, "")
	var events := _events()
	assert_eq(events.size(), 1, "Second ship does not roll once the first succeeds")
	assert_eq(events[0].ship_id, "a")
	assert_eq(events[0].target_id, "b")
	assert_eq(events[0].data["roll"], 2)
	assert_eq(events[0].data["modifier"], 0)
	assert_eq(events[0].data["needed"], 2)
	assert_true(events[0].data["success"])


func test_first_attempt_roll_3_stays_fouled() -> void:
	var ships := _foul_pair()
	_dice.queue([3, 3])
	controller.resolve_unfouling(PHASE)
	assert_eq(ships[0].fouled_with, "b")
	assert_eq(ships[1].fouled_with, "a")
	assert_eq(ships[0].unfoul_attempts, 1)
	assert_eq(ships[1].unfoul_attempts, 1)
	assert_eq(_events().size(), 2)
	assert_false(_events()[0].data["success"])


func test_second_turn_roll_3_frees_pair() -> void:
	var ships := _foul_pair()
	_dice.queue([3, 3])
	controller.resolve_unfouling(PHASE)
	_dice.queue([3])
	controller.resolve_unfouling(PHASE)
	assert_eq(ships[0].fouled_with, "")
	assert_eq(ships[1].fouled_with, "")
	var last: PhaseEvents.PhaseEvent = _events()[2]
	assert_eq(last.data["needed"], 3)
	assert_true(last.data["success"])


func test_third_attempt_needs_4() -> void:
	var ships := _foul_pair()
	_dice.queue([9, 9, 9, 9, 4])
	controller.resolve_unfouling(PHASE)
	controller.resolve_unfouling(PHASE)
	controller.resolve_unfouling(PHASE)
	assert_eq(ships[0].fouled_with, "")
	assert_eq(_events()[4].data["needed"], 4)


func test_crew_quality_a_modifier_helps() -> void:
	var ships := _foul_pair("A", "D")
	_dice.queue([5])  # 5 - 3 = 2
	controller.resolve_unfouling(PHASE)
	assert_eq(ships[0].fouled_with, "")
	assert_eq(_events()[0].data["modifier"], -3)


func test_crew_quality_g_modifier_hurts() -> void:
	var ships := _foul_pair("G", "G")
	_dice.queue([0, 9])  # 0 + 3 = 3 > 2: fails
	controller.resolve_unfouling(PHASE)
	assert_eq(ships[0].fouled_with, "b")
	assert_eq(_events()[0].data["modifier"], 3)
	assert_false(_events()[0].data["success"])


func test_first_ship_fails_second_succeeds() -> void:
	var ships := _foul_pair()
	_dice.queue([7, 1])
	controller.resolve_unfouling(PHASE)
	assert_eq(ships[0].fouled_with, "")
	assert_eq(ships[1].fouled_with, "")
	var events := _events()
	assert_eq(events.size(), 2)
	assert_eq(events[0].ship_id, "a")
	assert_false(events[0].data["success"])
	assert_eq(events[1].ship_id, "b")
	assert_eq(events[1].target_id, "a")
	assert_true(events[1].data["success"])


func test_struck_ship_does_not_roll() -> void:
	var ships := _foul_pair()
	ships[0].status = ShipState.Status.STRUCK
	_dice.queue([9])
	controller.resolve_unfouling(PHASE)
	var events := _events()
	assert_eq(events.size(), 1)
	assert_eq(events[0].ship_id, "b")
	assert_eq(ships[0].unfoul_attempts, 0)
	assert_eq(ships[1].unfoul_attempts, 1)


func test_each_pair_resolved_once_in_ship_id_order() -> void:
	var ships := _foul_pair()
	var c := _make_ship("c", Vector2i(1, 1), "D", 0)
	var d := _make_ship("d", Vector2i(0, 1), "D", 1)
	GameState.ship_controller.set_fouled_with("c", "d")
	GameState.ship_controller.set_fouled_with("d", "c")
	_dice.queue([9, 9, 9, 9])
	controller.resolve_unfouling(PHASE)
	var ids: Array = []
	for ev in _events():
		ids.append(ev.ship_id)
	assert_eq(ids, ["a", "b", "c", "d"])
	assert_eq(ships[0].fouled_with, "b")
	assert_eq(c.fouled_with, "d")
	assert_eq(d.unfoul_attempts, 1)


func test_dangling_partner_missing_cleared_silently() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	a.fouled_with = "ghost"
	controller.resolve_unfouling(PHASE)
	assert_eq(a.fouled_with, "")
	assert_eq(_events().size(), 0)


func test_dangling_partner_not_pointing_back_cleared_silently() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	var b := _make_ship("b", Vector2i(4, 5))
	a.fouled_with = "b"
	controller.resolve_unfouling(PHASE)
	assert_eq(a.fouled_with, "")
	assert_eq(b.fouled_with, "")
	assert_eq(_events().size(), 0)


func test_unfouled_ships_untouched() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	controller.resolve_unfouling(PHASE)
	assert_eq(a.unfoul_attempts, 0)
	assert_eq(_events().size(), 0)


func test_freed_ships_can_start_plotting_again() -> void:
	var ships := _foul_pair()
	_dice.queue([1])
	controller.resolve_unfouling(PHASE)
	GameState.movement_plotting_controller.sessions.clear()
	GameState.movement_plotting_controller.ship_sessions.clear()
	var response := GameState.movement_plotting_controller.handle_start_plotting(
			ships[0].player_id, "a", "req")
	assert_false(response is MovementTypes.PlottingErrorResponse)


func test_status_adjustment_phase_runs_unfouling() -> void:
	var ships := _foul_pair()
	_dice.queue([1])
	GameState.phase_controller._enter_status_adjustment_phase()
	assert_eq(ships[0].fouled_with, "")
	assert_eq(_events().size(), 1)
