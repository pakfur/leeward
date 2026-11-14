extends GutTest
## Tests for DamageController: box allocation, guns dismounted, morale triggers, striking.

var ctrl: DamageController
var ship: ShipState
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _dice: ScriptedDice


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	ctrl = DamageController.new(GameState)
	ship = _make_ship("hit_ship")


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String) -> ShipState:
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
	state.sail_state = "MS"
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


func _hit(rigging: int, hull: int, crew: int, cause: String = "other") -> void:
	ctrl.apply_hits("hit_ship", rigging, hull, crew, cause, 4, "enemy")


func test_rigging_taken_from_lowest_section() -> void:
	_hit(3, 0, 0)
	assert_eq(ship.rigging_current_hp, [2, 5, 6, 6] as Array[int])


func test_rigging_overflows_into_next_section() -> void:
	_hit(7, 0, 0)
	assert_eq(ship.rigging_current_hp, [0, 3, 6, 6] as Array[int])


func test_first_hull_section_dismounts_and_notes_morale() -> void:
	_hit(0, 5, 0)
	assert_eq(ship.hull_current_hp, [0, 5, 5, 6] as Array[int])
	assert_eq(ship.guns_dismounted, [1, 1] as Array[int])
	assert_eq(ship.pending_morale_checks, 1)


func test_three_hull_sections_cumulative() -> void:
	_hit(0, 15, 0)
	assert_eq(ship.guns_dismounted, [6, 6] as Array[int])
	assert_eq(ship.pending_morale_checks, 4)
	assert_false(ship.is_struck())


func test_hull_destroyed_strikes_once() -> void:
	_hit(0, 21, 0)
	assert_true(ship.is_struck())
	var strikes := GameState.turn_log.of_type(PhaseEvents.Type.STRIKE)
	assert_eq(strikes.size(), 1)
	assert_eq(strikes[0].data["reason"], "hull destroyed")


func test_excess_hull_is_discarded() -> void:
	_hit(0, 30, 0)
	assert_eq(ship.hull_current_hp, [0, 0, 0, 0] as Array[int])
	assert_true(ship.is_struck())


func test_dismasting() -> void:
	_hit(22, 0, 0)
	assert_true(ship.is_dismasted())
	assert_eq(ship.sail_state, "NS")
	assert_eq(ship.pending_morale_checks, 1)
	_hit(1, 0, 0)
	assert_eq(ship.pending_morale_checks, 1)


func test_dismasting_clears_sail_change() -> void:
	ship.sail_change = {"target": "FS", "turns_left": 1, "sections": [0]}
	_hit(22, 0, 0)
	assert_eq(ship.sail_change, {})


func test_crew_gunfire_at_hull_rolls() -> void:
	_dice.queue([1, 6])
	_hit(0, 0, 2, "gunfire_at_hull")
	assert_eq(ship.crew_count, [2, 3, 3, 3] as Array[int])
	assert_eq(ship.marine_count, 1)


func test_crew_other_cause_roll_four_is_marine() -> void:
	_dice.queue([4])
	_hit(0, 0, 1, "other")
	assert_eq(ship.marine_count, 1)
	assert_eq(ship.crew_count, [3, 3, 3, 3] as Array[int])


func test_emptying_sailor_section_notes_one_check() -> void:
	ship.crew_count = [1, 3, 3, 3] as Array[int]
	_dice.queue([1])
	_hit(0, 0, 1, "gunfire_at_hull")
	assert_eq(ship.pending_morale_checks, 1)
	assert_true(ship.morale_triggers_used.has("crew_0"))


func test_emptying_marines_notes_one_check() -> void:
	ship.marine_count = 1
	_dice.queue([6])
	_hit(0, 0, 1, "gunfire_at_hull")
	assert_eq(ship.pending_morale_checks, 1)
	assert_true(ship.morale_triggers_used.has("crew_4"))


func test_all_crew_removed_strikes_no_crew() -> void:
	var total := ship.total_crew_boxes()
	for i in range(total):
		_dice.queue([1])
	_hit(0, 0, total + 3, "other")
	assert_true(ship.is_struck())
	var strikes := GameState.turn_log.of_type(PhaseEvents.Type.STRIKE)
	assert_eq(strikes.size(), 1)
	assert_eq(strikes[0].data["reason"], "no crew")


func test_damage_event_records_applied_amounts() -> void:
	_dice.queue([1])
	_hit(3, 2, 1, "gunfire_at_hull")
	var events := GameState.turn_log.of_type(PhaseEvents.Type.DAMAGE)
	assert_eq(events.size(), 1)
	assert_eq(events[0].ship_id, "hit_ship")
	assert_eq(events[0].target_id, "enemy")
	assert_eq(events[0].data["rigging"], 3)
	assert_eq(events[0].data["hull"], 2)
	assert_eq(events[0].data["crew"], 1)
	assert_eq(events[0].data["crew_rolls"], [1])
	assert_eq(events[0].data["sailors_lost"] + events[0].data["marines_lost"], 1)


func test_damage_event_splits_crew_loss_into_sailors_and_marines() -> void:
	var sailors_before := 0
	for c in ship.crew_count:
		sailors_before += c
	var marines_before := ship.marine_count
	_dice.queue([1, 6, 1, 6])
	_hit(0, 0, 4, "gunfire_at_hull")
	var ev: PhaseEvents.PhaseEvent = GameState.turn_log.of_type(PhaseEvents.Type.DAMAGE)[0]
	var sailors_after := 0
	for c in ship.crew_count:
		sailors_after += c
	assert_eq(ev.data["sailors_lost"], sailors_before - sailors_after)
	assert_eq(ev.data["marines_lost"], marines_before - ship.marine_count)
	assert_eq(ev.data["sailors_lost"] + ev.data["marines_lost"], 4)
	assert_gt(ev.data["sailors_lost"], 0, "some sailors lost")
	assert_gt(ev.data["marines_lost"], 0, "some marines lost")


func test_damage_event_without_crew_hits_loses_nobody() -> void:
	_hit(2, 0, 0)
	var ev: PhaseEvents.PhaseEvent = GameState.turn_log.of_type(PhaseEvents.Type.DAMAGE)[0]
	assert_eq(ev.data["sailors_lost"], 0)
	assert_eq(ev.data["marines_lost"], 0)


func test_guns_and_morale_events() -> void:
	_hit(0, 5, 0)
	var guns := GameState.turn_log.of_type(PhaseEvents.Type.GUNS_DISMOUNTED)
	assert_eq(guns.size(), 1)
	assert_eq(guns[0].data["amount"], 1)
	var morale := GameState.turn_log.of_type(PhaseEvents.Type.MORALE_NOTED)
	assert_eq(morale.size(), 1)
	assert_eq(morale[0].data["trigger"], "hull_1")
	assert_eq(morale[0].data["count"], 1)


func test_already_struck_ship_notes_nothing() -> void:
	ctrl.strike("hit_ship", "test", 4)
	_hit(0, 5, 0)
	assert_eq(ship.pending_morale_checks, 0)
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.STRIKE).size(), 1)


func test_non_server_changes_nothing() -> void:
	ctrl.is_server = false
	_hit(5, 5, 0)
	assert_push_error("Cannot apply hits on client")
	assert_eq(ship.rigging_current_hp, [5, 5, 6, 6] as Array[int])
	assert_eq(ship.hull_current_hp, [5, 5, 5, 6] as Array[int])
	assert_eq(GameState.turn_log.events.size(), 0)
