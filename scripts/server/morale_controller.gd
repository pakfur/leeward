class_name MoraleController
extends RefCounted
## MoraleController - The MORALE_CHECK phase (Close Action 1997): first the voluntary surrenders
## ordered this g-t (14.B.2, `resolve_surrenders`), then the pending morale checks
## (`resolve_checks`); `resolve_phase` runs both in that order. Surrenders come first because a ship
## may surrender "before it is forced to strike": a ship that surrenders is out of play and her noted
## checks are never rolled. A check rolls d10 and passes at or above the ship's morale rating. A
## failure lowers crew quality one letter; failing while already at G strikes the ship. All
## mutations go through ShipStateController / DamageController.

const QUALITY_ORDER: Array[String] = ["A", "B", "C", "D", "E", "F", "G"]

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## The MORALE_CHECK phase: the 14.B surrenders, then the noted morale checks.
func resolve_phase(phase: int) -> void:
	resolve_surrenders(phase)
	resolve_checks(phase)


func resolve_surrenders(phase: int) -> void:
	## 14.B.2: every ship ordered to surrender this g-t, in ascending ship_id order: the order is
	## cleared; a ship already out of play (struck, destroyed or captured during the g-t) does not
	## surrender; any other logs SURRENDER and strikes (reason "surrender"); a second surrender is
	## for good (14.B.4). No dice.
	if not is_server:
		push_error("MoraleController: Cannot resolve surrenders on client")
		return
	var ids: Array = game_state.ships.keys()
	ids.sort()
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or not ship.surrender_ordered:
			continue
		game_state.ship_controller.set_surrender_ordered(ship_id, false)
		if ship.is_out_of_play():
			continue
		var n: int = game_state.ship_controller.record_surrender(ship_id)
		var permanent: bool = n >= SurrenderRules.MAX_SURRENDERS
		game_state.turn_log.add(PhaseEvents.Type.SURRENDER, phase, ship_id,
			{"surrenders": n, "permanent": permanent})
		game_state.damage_controller.strike(ship_id, "surrender", phase)
		if permanent:
			game_state.ship_controller.end_surrender(ship_id)


func resolve_checks(phase: int) -> void:
	## Ships resolve in ascending ship_id order; one ship's checks all roll before the next
	## ship's. A ship that strikes stops rolling. Pending checks are cleared for every ship.
	if not is_server:
		push_error("MoraleController: Cannot resolve morale checks on client")
		return
	var ids: Array = game_state.ships.keys()
	ids.sort()
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null:
			continue
		var remaining: int = ship.pending_morale_checks
		while remaining > 0 and not ship.is_out_of_play():
			remaining -= 1
			_check(ship, phase)
		game_state.ship_controller.clear_pending_morale_checks(ship_id)


func _check(ship: ShipState, phase: int) -> void:
	var ship_id: String = ship.ship.ship_id
	var roll: int = game_state.dice.d10()
	var rating: int = ship.morale_rating
	var passed: bool = roll >= rating
	var failed_at_g: bool = not passed and ship.crew_quality == "G"
	if not passed and not failed_at_g:
		var index: int = QUALITY_ORDER.find(ship.crew_quality)
		if index < 0:
			push_warning("MoraleController: ship %s has unrecognised crew quality '%s'; treated as D" % [
				ship_id, ship.crew_quality])
			index = QUALITY_ORDER.find("D")
		game_state.ship_controller.set_crew_quality(ship_id, QUALITY_ORDER[mini(index + 1, QUALITY_ORDER.size() - 1)])
	var data := {"roll": roll, "rating": rating, "passed": passed}
	if failed_at_g:
		data["breaks"] = true  # already at G: no quality left to lose, the ship strikes
	else:
		data["quality"] = ship.crew_quality
	game_state.turn_log.add(PhaseEvents.Type.MORALE_CHECK, phase, ship_id, data)
	if failed_at_g:
		game_state.damage_controller.strike(ship_id, "morale", phase)
