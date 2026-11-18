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


## The enemy ships that could chase `ship` (V.D.1): of another side, in play, on the map and not
## aground.
func pursuers(ship: ShipState) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for other: ShipState in game_state.get_all_ships():
		if other.side == ship.side or other.is_out_of_play() or not other.is_on_map() \
				or other.is_aground():
			continue
		out.append(other)
	return out


## End of the turn (V.D.1-4): first every declared ship in play is reported (ESCAPE_DECLARED, in
## ship id order); then every declared ship in play, on the map and not fouled or grappled, of a
## side that may escape this turn, escapes by distance or speed (MapRules.condition). Every
## condition is read from the positions before any ship leaves.
func resolve_escapes(turn: int, phase: int) -> void:
	if not is_server:
		push_error("MapController: Cannot resolve escapes on client")
		return
	var ids: Array = game_state.ships.keys()
	ids.sort()
	var declared: Array[ShipState] = []
	for id in ids:
		var ship: ShipState = game_state.get_ship(str(id))
		if ship.escape_declared and not ship.is_out_of_play():
			declared.append(ship)
			game_state.turn_log.add(PhaseEvents.Type.ESCAPE_DECLARED, phase, ship.ship_id)
	var env: EnvironmentState = game_state.environment
	var escapes: Array = []
	for ship in declared:
		if not ship.is_on_map() or ship.is_linked() \
				or not MapRules.may_declare(game_state.active_scenario, ship.side, turn):
			continue
		var how := MapRules.condition(ship, pursuers(ship), env.wind_direction, env.wind_speed)
		if not how.is_empty():
			escapes.append([ship.ship_id, how])
	for e in escapes:
		escape(e[0], e[1], phase)


## The ship leaves the map where there is no sea room and is lost.
func lose_off_map(ship_id: String, edge: String, phase: int) -> void:
	if not is_server:
		push_error("MapController: Cannot lose a ship on client")
		return
	game_state.damage_controller.destroy(ship_id, "no_sea_room", phase, {"edge": edge})
	game_state.ship_controller.remove_from_map(ship_id)
