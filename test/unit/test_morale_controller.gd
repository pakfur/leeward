extends GutTest
## Tests for MoraleController (Close Action 1997 morale: d10 >= morale rating passes;
## a failure lowers crew quality one letter; failing at G strikes the ship).

const PHASE := 7

var controller: MoraleController
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
	controller = MoraleController.new(GameState)


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, quality: String, rating: int, pending: int, player: int = 0) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
	})
	state.player_id = player
	state.hex_position = Vector2i(5, 5)
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
	state.morale_rating = rating
	state.pending_morale_checks = pending
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


func _events() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.MORALE_CHECK)


func test_roll_equal_to_rating_passes() -> void:
	var ship := _make_ship("a", "D", 4, 1)
	_dice.queue([4])
	controller.resolve_checks(PHASE)
	assert_eq(ship.crew_quality, "D")
	assert_false(ship.is_struck())


func test_roll_below_rating_lowers_quality() -> void:
	var ship := _make_ship("a", "D", 4, 1)
	_dice.queue([3])
	controller.resolve_checks(PHASE)
	assert_eq(ship.crew_quality, "E")


func test_two_failures_lower_two_letters() -> void:
	var ship := _make_ship("a", "D", 4, 2)
	_dice.queue([0, 0])
	controller.resolve_checks(PHASE)
	assert_eq(ship.crew_quality, "F")
	assert_false(ship.is_struck())


func test_failure_at_g_strikes_with_morale_reason() -> void:
	var ship := _make_ship("a", "G", 4, 1)
	_dice.queue([0])
	controller.resolve_checks(PHASE)
	assert_true(ship.is_struck())
	var strikes: Array = GameState.turn_log.of_type(PhaseEvents.Type.STRIKE)
	assert_eq(strikes.size(), 1)
	assert_eq(strikes[0].data["reason"], "morale")


func test_f_fails_to_g_then_strikes() -> void:
	var ship := _make_ship("a", "F", 4, 2)
	_dice.queue([0, 0])
	controller.resolve_checks(PHASE)
	assert_eq(ship.crew_quality, "G")
	assert_true(ship.is_struck())


func test_striking_discards_remaining_checks() -> void:
	var ship := _make_ship("a", "G", 4, 3)
	_dice.queue([0, 0, 0])
	controller.resolve_checks(PHASE)
	assert_true(ship.is_struck())
	assert_eq(_dice.remaining(), 2, "only one die consumed before striking")
	assert_eq(ship.pending_morale_checks, 0)


func test_rating_2_roll_2_passes() -> void:
	var ship := _make_ship("a", "D", 2, 1)
	_dice.queue([2])
	controller.resolve_checks(PHASE)
	assert_eq(ship.crew_quality, "D")


func test_pending_cleared_afterwards() -> void:
	var ship := _make_ship("a", "D", 4, 2)
	_dice.queue([9, 9])
	controller.resolve_checks(PHASE)
	assert_eq(ship.pending_morale_checks, 0)


func test_struck_ship_clears_pending_without_rolling() -> void:
	var ship := _make_ship("a", "D", 4, 2)
	ship.status = ShipState.Status.STRUCK
	_dice.queue([0, 0])
	controller.resolve_checks(PHASE)
	assert_eq(_dice.remaining(), 2)
	assert_eq(ship.pending_morale_checks, 0)
	assert_eq(ship.crew_quality, "D")


func test_ships_roll_in_ship_id_order() -> void:
	var b := _make_ship("b", "D", 4, 1, 1)
	var a := _make_ship("a", "D", 4, 1, 0)
	_dice.queue([0, 9])
	controller.resolve_checks(PHASE)
	assert_eq(a.crew_quality, "E", "a rolls first and fails")
	assert_eq(b.crew_quality, "D", "b rolls second and passes")


func test_check_events_logged() -> void:
	_make_ship("a", "D", 4, 1)
	_dice.queue([3])
	controller.resolve_checks(PHASE)
	var events := _events()
	assert_eq(events.size(), 1)
	var d: Dictionary = events[0].data
	assert_eq(d["roll"], 3)
	assert_eq(d["rating"], 4)
	assert_false(d["passed"])
	assert_eq(d["quality"], "E")


func test_unrecognised_quality_fails_as_d() -> void:
	var ship := _make_ship("odd", "Veteran", 4, 1)
	_dice.queue([0])
	controller.resolve_checks(PHASE)
	assert_eq(ship.crew_quality, "E", "an unknown quality drops as if it were D")
	assert_engine_error("ship odd has unrecognised crew quality 'Veteran'")
	assert_false(ship.is_struck())
