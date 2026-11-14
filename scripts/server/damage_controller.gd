class_name DamageController
extends RefCounted
## DamageController - Applies rigging, hull and crew hits to a ship (Close Action 1997, 9.5).
## Boxes come off the lowest-numbered section first. All mutations go through ShipStateController.

## Morale checks noted when hull section 1, 2 or 3 is emptied
const HULL_MORALE_CHECKS: Array[int] = [1, 1, 2]

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


func apply_hits(ship_id: String, rigging: int, hull: int, crew: int, crew_cause: String,
		phase: int, source_id: String = "") -> void:
	if not is_server:
		push_error("DamageController: Cannot apply hits on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return
	var struck_before := ship.is_struck()

	var rigging_applied := _apply_rigging(ship, ship_id, rigging, phase, struck_before)
	var hull_applied := _apply_hull(ship, ship_id, hull, phase, struck_before)
	var crew_rolls: Array = []
	var marines_before := ship.marine_count
	var crew_applied := _apply_crew(ship, ship_id, crew, crew_cause, phase, struck_before, crew_rolls)
	var marines_lost := marines_before - ship.marine_count

	game_state.turn_log.add(PhaseEvents.Type.DAMAGE, phase, ship_id, {
		"rigging": rigging_applied,
		"hull": hull_applied,
		"crew": crew_applied,
		"sailors_lost": crew_applied - marines_lost,
		"marines_lost": marines_lost,
		"crew_rolls": crew_rolls,
	}, source_id)


func strike(ship_id: String, reason: String, phase: int) -> void:
	if not is_server:
		push_error("DamageController: Cannot strike a ship on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return
	if ship.is_struck():
		return
	game_state.ship_controller.set_status(ship_id, ShipState.Status.STRUCK)
	game_state.turn_log.add(PhaseEvents.Type.STRIKE, phase, ship_id, {"reason": reason})
	Trace.trace_log("Damage", "Ship %s strikes: %s" % [ship_id, reason])


func _apply_rigging(ship: ShipState, ship_id: String, amount: int, phase: int,
		struck_before: bool) -> int:
	var applied := 0
	for section in range(ship.rigging_current_hp.size()):
		while applied < amount and ship.rigging_current_hp[section] > 0:
			game_state.ship_controller.apply_rigging_damage(ship_id, section, 1)
			applied += 1
	if applied > 0 and ship.is_dismasted():
		game_state.ship_controller.set_sail_state(ship_id, "NS")
		game_state.ship_controller.set_sail_change(ship_id, {})
		if not struck_before:
			_note_morale(ship_id, "dismasted", 1, phase)
	return applied


func _apply_hull(ship: ShipState, ship_id: String, amount: int, phase: int,
		struck_before: bool) -> int:
	var applied := 0
	for section in range(ship.hull_current_hp.size()):
		var emptied := false
		while applied < amount and ship.hull_current_hp[section] > 0:
			game_state.ship_controller.apply_hull_damage(ship_id, section, 1)
			applied += 1
			emptied = ship.hull_current_hp[section] == 0
		if not emptied:
			continue
		if section < HULL_MORALE_CHECKS.size():
			var guns := section + 1
			game_state.ship_controller.add_guns_dismounted(ship_id, guns)
			game_state.turn_log.add(PhaseEvents.Type.GUNS_DISMOUNTED, phase, ship_id, {"amount": guns})
			if not struck_before:
				_note_morale(ship_id, "hull_%d" % (section + 1), HULL_MORALE_CHECKS[section], phase)
		elif not struck_before:
			strike(ship_id, "hull destroyed", phase)
	return applied


func _apply_crew(ship: ShipState, ship_id: String, amount: int, cause: String, phase: int,
		struck_before: bool, rolls: Array) -> int:
	var applied := 0
	for i in range(amount):
		if ship.total_crew_boxes() == 0:
			break
		var roll: int = game_state.dice.d6()
		rolls.append(roll)
		var sailor: bool = DataManager.combat_tables.crew_loss_is_sailor(cause, roll)
		var emptied: int = game_state.ship_controller.remove_crew_box(ship_id, not sailor)
		applied += 1
		if emptied >= 0 and not struck_before:
			_note_morale(ship_id, "crew_%d" % emptied, 1, phase)
	if applied > 0 and ship.total_crew_boxes() == 0 and not struck_before:
		strike(ship_id, "no crew", phase)
	return applied


func _note_morale(ship_id: String, trigger: String, count: int, phase: int) -> void:
	if game_state.ship_controller.note_morale_check(ship_id, trigger, count):
		game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, ship_id,
				{"trigger": trigger, "count": count})
