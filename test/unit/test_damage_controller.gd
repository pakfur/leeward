extends GutTest
## Tests for DamageController: box allocation, guns dismounted, morale triggers, striking.

var ctrl: DamageController
var ship: ShipState
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _dice: ScriptedDice
var _old_crits: CriticalHitController


func before_each() -> void:
	# Rigging/Hull Checks are CriticalHitController's (test_critical_hit_controller.gd): a fresh,
	# held controller keeps the checks queued here, so these tests roll only crew-loss dice.
	_old_crits = GameState.critical_hit_controller
	GameState.critical_hit_controller = CriticalHitController.new(GameState)
	GameState.critical_hit_controller.hold()
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
	GameState.critical_hit_controller = _old_crits
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


func test_damage_line_precedes_its_consequences() -> void:
	_hit(0, 21, 0)
	var types: Array = []
	for ev in GameState.turn_log.events:
		types.append(ev.type)
	assert_eq(types[0], PhaseEvents.Type.DAMAGE, "the loss is logged before what it causes")
	var damage_at := types.find(PhaseEvents.Type.DAMAGE)
	assert_lt(damage_at, types.find(PhaseEvents.Type.GUNS_DISMOUNTED))
	assert_lt(damage_at, types.find(PhaseEvents.Type.MORALE_NOTED))
	assert_lt(damage_at, types.find(PhaseEvents.Type.STRIKE))
	assert_eq(types.count(PhaseEvents.Type.DAMAGE), 1)
	# Consequences keep their own order: section 1 guns, its morale, ... then the strike last.
	assert_eq(types.back(), PhaseEvents.Type.STRIKE)
	assert_lt(types.find(PhaseEvents.Type.GUNS_DISMOUNTED), types.find(PhaseEvents.Type.MORALE_NOTED))


func test_damage_line_follows_earlier_events_in_the_log() -> void:
	GameState.turn_log.add(PhaseEvents.Type.FIRE, 4, "enemy", {}, "hit_ship")
	_hit(0, 5, 0)
	assert_eq(GameState.turn_log.events[0].type, PhaseEvents.Type.FIRE)
	assert_eq(GameState.turn_log.events[1].type, PhaseEvents.Type.DAMAGE)


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


# --- Rigging and Hull Checks are queued for emptied sections (7.D.7, 7.D.8a, 7.D.12) ---

func test_emptied_rigging_sections_queue_rigging_checks() -> void:
	_hit(11, 0, 0)  # empties sections 1 and 2 (5 + 5), one box into section 3
	assert_eq(GameState.critical_hit_controller.pending_checks(), 2)


func test_partly_hit_section_queues_no_check() -> void:
	_hit(4, 4, 0)
	assert_eq(GameState.critical_hit_controller.pending_checks(), 0)


func test_hull_sections_one_to_three_queue_hull_checks_not_four() -> void:
	# Spec Q5: no Hull Check for the last section, the ship strikes.
	_hit(0, 21, 0)
	assert_eq(GameState.critical_hit_controller.pending_checks(), 3)


func test_already_struck_ship_queues_no_checks() -> void:
	ctrl.strike("hit_ship", "test", 4)
	_hit(5, 5, 0)
	assert_eq(GameState.critical_hit_controller.pending_checks(), 0)


func test_crew_boxes_marines_first_without_rolls() -> void:
	ship.marine_count = 1
	var lost := ctrl.apply_crew_boxes("hit_ship", 2, true, 4, "enemy")
	assert_eq(lost, 2)
	assert_eq(ship.marine_count, 0)
	assert_eq(ship.crew_count, [2, 3, 3, 3] as Array[int])
	assert_true(ship.morale_triggers_used.has("crew_4"), "all marines lost: MC")
	var ev: PhaseEvents.PhaseEvent = GameState.turn_log.of_type(PhaseEvents.Type.DAMAGE)[0]
	assert_eq(ev.data["cause"], "critical")
	assert_eq(ev.data["marines_lost"], 1)
	assert_eq(ev.data["sailors_lost"], 1)
	assert_eq(_dice.remaining(), 0)


# --- destroyed ships (hull #12 explosion, spec Q2) ---

func _partner(id: String) -> ShipState:
	var other := _make_ship(id)
	return other


func test_destroy_sets_status_and_logs() -> void:
	ctrl.destroy("hit_ship", "explosion", 4)
	assert_true(ship.is_destroyed())
	var events := GameState.turn_log.of_type(PhaseEvents.Type.DESTROYED)
	assert_eq(events.size(), 1)
	assert_eq(events[0].data, {"reason": "explosion"})
	assert_eq(events[0].target_id, "")


func test_destroy_frees_fouled_partner() -> void:
	var other := _partner("other")
	GameState.ship_controller.set_fouled_with("hit_ship", "other")
	GameState.ship_controller.set_fouled_with("other", "hit_ship")
	ctrl.destroy("hit_ship", "explosion", 4)
	assert_eq(ship.fouled_with, "")
	assert_eq(other.fouled_with, "", "the partner is freed")
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.DESTROYED)[0].target_id, "other")


func test_destroy_drops_sail_change_and_morale_checks() -> void:
	GameState.ship_controller.set_sail_change("hit_ship", {"target": "FS", "turns_left": 1, "sections": [3]})
	GameState.ship_controller.note_morale_check("hit_ship", "hull_0")
	ctrl.destroy("hit_ship", "explosion", 4)
	assert_eq(ship.sail_change, {})
	assert_eq(ship.pending_morale_checks, 0)


func test_destroy_twice_logs_once() -> void:
	ctrl.destroy("hit_ship", "explosion", 4)
	ctrl.destroy("hit_ship", "explosion", 4)
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.DESTROYED).size(), 1)


func test_struck_ship_can_be_destroyed() -> void:
	ctrl.strike("hit_ship", "morale", 4)
	ctrl.destroy("hit_ship", "explosion", 4)
	assert_true(ship.is_destroyed())


func test_destroyed_ship_takes_no_damage_and_never_strikes() -> void:
	ship.status = ShipState.Status.DESTROYED
	_hit(3, 3, 0)
	assert_eq(ship.rigging_current_hp, [5, 5, 6, 6] as Array[int])
	assert_eq(ship.hull_current_hp, [5, 5, 5, 6] as Array[int])
	assert_eq(ctrl.apply_crew_boxes("hit_ship", 2, true, 4), 0)
	ctrl.strike("hit_ship", "morale", 4)
	assert_true(ship.is_destroyed())
	assert_eq(GameState.turn_log.events.size(), 0)


func test_destroy_on_client_is_refused() -> void:
	ctrl.is_server = false
	ctrl.destroy("hit_ship", "explosion", 4)
	assert_push_error("Cannot destroy a ship on client")
	assert_false(ship.is_destroyed())
