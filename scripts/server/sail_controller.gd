class_name SailController
extends RefCounted
## SailController - Plotted sail changes (Close Action 1997, 8).
## A change is plotted in PLANNING, starts at the beginning of MOVEMENT_RESOLUTION (occupying
## sailor sections, which cannot then serve the guns), and completes in STATUS_ADJUSTMENT.
## All mutations go through ShipStateController.

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


func available_targets(ship_id: String) -> Array[String]:
	## States one step from the carried sail, not above what the rigging can carry.
	var result: Array[String] = []
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.is_struck() or ship.is_dismasted() or not ship.sail_change.is_empty():
		return result
	var current := ShipState.SAIL_ORDER.find(ship.sail_state.to_upper())
	var limit := ShipState.SAIL_ORDER.find(ship.max_sail_state())
	if current < 0:
		return result
	for idx in [current - 1, current + 1]:
		if idx >= 0 and idx < ShipState.SAIL_ORDER.size() and idx <= limit:
			result.append(ShipState.SAIL_ORDER[idx])
	return result


func change_cost(ship_id: String, target: String) -> Dictionary:
	## FS<->MS and FS<->NS: 1 section, 1 turn. MS<->PS: 2 sections, 2 turns. +1 turn for CQ E-G.
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return {"turns": 0, "sections": 0}
	var involves_ps: bool = ship.sail_state.to_upper() == "PS" or target == "PS"
	var sections := 2 if involves_ps else 1
	var turns := sections
	if ship.crew_quality in ["E", "F", "G"]:
		turns += 1
	return {"turns": turns, "sections": sections}


func plot_sail_change(player_id: int, ship_id: String, target: String) -> String:
	## Returns "" on success, otherwise the reason it was refused. An empty target clears the plot.
	if not is_server:
		push_error("SailController: Cannot plot sail change on client")
		return "Not the server"
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "Unknown ship"
	if ship.player_id != player_id:
		return "Not your ship"
	if game_state.phase_controller.current_phase != TurnPhaseController.GamePhase.PLANNING:
		return "Sail changes can only be ordered during planning"
	if target == "":
		game_state.ship_controller.set_plotted_sail_change(ship_id, "")
		return ""
	if ship.is_struck():
		return "Ship has struck"
	if ship.is_dismasted():
		return "Ship is dismasted"
	if not ship.sail_change.is_empty():
		return "A sail change is already in progress"
	if not target in available_targets(ship_id):
		return "Cannot change to %s from %s" % [target, ship.sail_state]
	game_state.ship_controller.set_plotted_sail_change(ship_id, target)
	return ""


func begin_plotted_changes() -> void:
	## Start of MOVEMENT_RESOLUTION: turn each plotted order into an in-progress change.
	if not is_server:
		push_error("SailController: Cannot begin sail changes on client")
		return
	var phase: int = game_state.phase_controller.current_phase
	for ship in game_state.get_all_ships():
		var target: String = ship.plotted_actions.get("sail_change", "")
		if target == "":
			continue
		var ship_id: String = ship.ship_id
		game_state.ship_controller.set_plotted_sail_change(ship_id, "")
		if not target in available_targets(ship_id):
			_log(ship, target, 0, phase, "not available")
			continue
		var cost: Dictionary = change_cost(ship_id, target)
		var sections: Array[int] = _free_sections(ship, cost["sections"])
		if sections.size() < cost["sections"]:
			_log(ship, target, cost["turns"], phase, "no crew")
			continue
		game_state.ship_controller.set_sail_change(ship_id, {
			"target": target, "turns_left": cost["turns"], "sections": sections})
		_log(ship, target, cost["turns"], phase)


func advance_changes(phase: int) -> void:
	## STATUS_ADJUSTMENT: count down each change; complete or cancel it.
	if not is_server:
		push_error("SailController: Cannot advance sail changes on client")
		return
	for ship in game_state.get_all_ships():
		if ship.sail_change.is_empty():
			continue
		var change: Dictionary = ship.sail_change
		var target: String = change.get("target", "")
		var turns_left: int = change.get("turns_left", 0)
		var reason: String = _cancel_reason(ship, change)
		if reason != "":
			game_state.ship_controller.set_sail_change(ship.ship_id, {})
			_log(ship, target, turns_left, phase, reason)
			continue
		turns_left -= 1
		if turns_left > 0:
			var updated: Dictionary = change.duplicate(true)
			updated["turns_left"] = turns_left
			game_state.ship_controller.set_sail_change(ship.ship_id, updated)
			continue
		var from_state: String = ship.sail_state
		game_state.ship_controller.set_sail_state(ship.ship_id, target)
		game_state.ship_controller.set_sail_change(ship.ship_id, {})
		game_state.turn_log.add(PhaseEvents.Type.SAIL_CHANGE, phase, ship.ship_id,
			{"from": from_state, "to": target, "turns_left": 0})


func _cancel_reason(ship: ShipState, change: Dictionary) -> String:
	if ship.is_struck():
		return "struck"
	if ship.is_dismasted():
		return "dismasted"
	for section in change.get("sections", []):
		if ship.crew_count[section] <= 0:
			return "crew lost"
	return ""


func _free_sections(ship: ShipState, needed: int) -> Array[int]:
	## Highest-numbered sailor sections that still have boxes (0-based indices, highest first).
	var result: Array[int] = []
	for i in range(ship.crew_count.size() - 1, -1, -1):
		if result.size() >= needed:
			break
		if ship.crew_count[i] > 0:
			result.append(i)
	return result


func _log(ship: ShipState, target: String, turns_left: int, phase: int, cancelled: String = "") -> void:
	var data := {"from": ship.sail_state, "to": target, "turns_left": turns_left}
	if cancelled != "":
		data["cancelled"] = cancelled
	game_state.turn_log.add(PhaseEvents.Type.SAIL_CHANGE, phase, ship.ship_id, data)
