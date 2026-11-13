class_name MoraleController
extends RefCounted
## MoraleController - Resolves pending morale checks in MORALE_CHECK (Close Action 1997).
## A check rolls d10 and passes at or above the ship's morale rating. A failure lowers crew
## quality one letter; failing while already at G strikes the ship. All mutations go through
## ShipStateController / DamageController.

const QUALITY_ORDER: Array[String] = ["A", "B", "C", "D", "E", "F", "G"]

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


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
		while remaining > 0 and not ship.is_struck():
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
	game_state.turn_log.add(PhaseEvents.Type.MORALE_CHECK, phase, ship_id, {
		"roll": roll, "rating": rating, "passed": passed, "quality": ship.crew_quality,
	})
	if failed_at_g:
		game_state.damage_controller.strike(ship_id, "morale", phase)
