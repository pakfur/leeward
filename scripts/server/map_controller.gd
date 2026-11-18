class_name MapController
extends RefCounted
## MapController - server-side map events: running aground, escaping and being lost off the map
## (map and scenario spec §9). All state changes go through the ship and damage controllers.

var game_state: Node
var is_server := true


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## The ship runs aground now; `data` is {cause, terrain, hex: {q, r}, depth, draft}.
func ground(ship_id: String, data: Dictionary, phase: int) -> void:
	if not is_server:
		push_error("MapController: Cannot ground a ship on client")
		return
	if game_state.get_ship(ship_id) == null:
		push_error("[Server] Ship not found: %s" % ship_id)
		return
	game_state.ship_controller.set_aground(ship_id, game_state.current_turn)
	game_state.turn_log.add(PhaseEvents.Type.AGROUND, phase, ship_id, data)
	Trace.trace_log("Map", "Ship %s aground (%s)" % [ship_id, str(data.get("terrain", ""))])


## The ship escapes: `data` is {how, edge} or {how, range}. No-op for a ship already out of play.
func escape(ship_id: String, data: Dictionary, phase: int) -> void:
	if not is_server:
		push_error("MapController: Cannot escape a ship on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		push_error("[Server] Ship not found: %s" % ship_id)
		return
	if ship.is_out_of_play():
		return
	var sc: ShipStateController = game_state.ship_controller
	sc.set_status(ship_id, ShipState.Status.ESCAPED)
	if game_state.get("crew_task_controller") != null:
		game_state.crew_task_controller.drop_all(ship_id, "escaped")
	sc.clear_pending_morale_checks(ship_id)
	sc.remove_from_map(ship_id)
	game_state.turn_log.add(PhaseEvents.Type.ESCAPED, phase, ship_id, data)
	Trace.trace_log("Map", "Ship %s escaped (%s)" % [ship_id, str(data.get("how", ""))])


## The ship leaves the map where there is no sea room and is lost.
func lose_off_map(ship_id: String, edge: String, phase: int) -> void:
	if not is_server:
		push_error("MapController: Cannot lose a ship on client")
		return
	game_state.damage_controller.destroy(ship_id, "no_sea_room", phase, {"edge": edge})
	game_state.ship_controller.remove_from_map(ship_id)
