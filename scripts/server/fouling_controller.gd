class_name FoulingController
extends RefCounted
## FoulingController - Automatic unfouling attempts (Close Action 1997 Unfouling table).
## Each turn, in STATUS_ADJUSTMENT, every fouled pair gets unfouling rolls. A ship's roll is
## d10 + crew-quality skill modifier and frees the pair when it is <= the success number for
## that ship's attempt count (lower is better). All mutations go through ShipStateController.

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


func resolve_unfouling(phase: int) -> void:
	## Dice order: pairs are taken by their lower ship_id; within a pair the lower ship_id rolls
	## first, and the second ship does not roll once the first succeeds. Struck ships never roll.
	if not is_server:
		push_error("FoulingController: Cannot resolve unfouling on client")
		return
	var ids: Array = game_state.ships.keys()
	ids.sort()
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.fouled_with == "":
			continue
		var partner: ShipState = game_state.get_ship(ship.fouled_with)
		if partner == null or partner.fouled_with != ship_id:
			game_state.ship_controller.set_fouled_with(ship_id, "")
			continue
		if ship_id > ship.fouled_with:
			continue  # the pair was (or will be) handled from its lower ship_id
		if _attempt(ship, partner, phase) or _attempt(partner, ship, phase):
			game_state.ship_controller.set_fouled_with(ship_id, "")
			game_state.ship_controller.set_fouled_with(partner.ship.ship_id, "")


func _attempt(ship: ShipState, partner: ShipState, phase: int) -> bool:
	if ship.is_struck():
		return false
	var ship_id: String = ship.ship.ship_id
	var attempts: int = ship.unfoul_attempts + 1
	game_state.ship_controller.set_unfoul_attempts(ship_id, attempts)
	var tables: CombatTables = DataManager.combat_tables
	var roll: int = game_state.dice.d10()
	var modifier: int = tables.skill_modifier(ship.crew_quality)
	var needed: int = tables.unfouling_success_max(attempts)
	var success: bool = roll + modifier <= needed
	game_state.turn_log.add(PhaseEvents.Type.UNFOUL, phase, ship_id, {
		"roll": roll, "modifier": modifier, "needed": needed, "success": success,
	}, partner.ship.ship_id)
	return success
