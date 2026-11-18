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
	if game_state.get("tow_controller") != null:
		game_state.tow_controller.on_ship_changed(ship_id, phase)  # her tow parts (towing spec §6)


## Whether `ship_id` is held by a live boarding action, as attacker or defender, and so may not
## escape (ruling 2026-11-17): its escape crossings are blocked in plotting, movement and drift.
## False when `gs` has no boarding controller (bare test fixtures).
static func escape_locked(gs: Node, ship_id: String) -> bool:
	if gs == null or gs.get("boarding_controller") == null:
		return false
	return gs.boarding_controller.live_action_of(ship_id) != null


## The ship escapes: `data` is {how, edge}, {how, range} or {how: "in_tow", tower}. No-op for a ship
## already out of play. A tower takes her tow with her (towing spec §8): an own ship escapes in tow;
## a prize is carried off the map and stays CAPTURED (her captor took her away, so her value stays
## lost to her owner). The tow is then cleared, with no TOW_CUT.
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
	var towed_id: String = ship.towing_id
	var sc: ShipStateController = game_state.ship_controller
	sc.set_status(ship_id, ShipState.Status.ESCAPED)
	if game_state.get("crew_task_controller") != null:
		game_state.crew_task_controller.drop_all(ship_id, "escaped")
	sc.clear_fires(ship_id)  # she burns no more where we can see her (as a wreck, spec Q10)
	sc.clear_pending_morale_checks(ship_id)
	sc.remove_from_map(ship_id)
	game_state.turn_log.add(PhaseEvents.Type.ESCAPED, phase, ship_id, data)
	Trace.trace_log("Map", "Ship %s escaped (%s)" % [ship_id, str(data.get("how", ""))])
	if towed_id != "":
		_carry_tow(ship_id, towed_id, phase)
		if ship.is_towing():
			sc.cut_tow(ship_id)


## The escaped tower `tower_id` takes `towed_id` with her (towing spec §8).
func _carry_tow(tower_id: String, towed_id: String, phase: int) -> void:
	var towed: ShipState = game_state.get_ship(towed_id)
	if towed == null or not towed.is_on_map():
		return
	if towed.is_captured():
		var sc: ShipStateController = game_state.ship_controller
		if game_state.get("crew_task_controller") != null:
			game_state.crew_task_controller.drop_all(towed_id, "carried off")
		sc.clear_fires(towed_id)
		sc.remove_from_map(towed_id)
		game_state.turn_log.add(PhaseEvents.Type.ESCAPED, phase, towed_id,
				{"how": "in_tow", "tower": tower_id, "prize": true})
		Trace.trace_log("Map", "Prize %s carried off by %s" % [towed_id, tower_id])
	elif towed.status == ShipState.Status.ACTIVE:
		escape(towed_id, {"how": "in_tow", "tower": tower_id}, phase)


## The enemy ships that could chase `ship` (V.D.1): of another side, in play, on the map, not
## aground and not anchored (ruling 2026-11-18).
func pursuers(ship: ShipState) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for other: ShipState in game_state.get_all_ships():
		if other.side == ship.side or other.is_out_of_play() or not other.is_on_map() \
				or other.is_aground() or other.is_anchored():
			continue
		out.append(other)
	return out


## End of the turn (V.D.1-4): first every declared ship in play is reported (ESCAPE_DECLARED, in
## ship id order); then every declared ship in play, on the map, not fouled, grappled or anchored
## (ruling 2026-11-18), not in tow (she escapes only with her tower, towing spec §8), in no
## live boarding action and not towing a ship that is fouled, grappled or in one, of a side that
## may escape this turn, escapes by distance or speed (MapRules.condition; a tower's 12.A.7 loss
## comes off her own speed). Every condition is read from the positions before any ship leaves.
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
		if not ship.is_on_map() or ship.is_linked() or ship.is_anchored() or ship.is_towed() \
				or escape_locked(game_state, ship.ship_id) or _tow_held(ship) \
				or not MapRules.may_declare(game_state.active_scenario, ship.side, turn):
			continue
		var how := MapRules.condition(ship, pursuers(ship), env.wind_direction, env.wind_speed,
				game_state.ship_controller.tow_mp_loss(ship))
		if not how.is_empty():
			escapes.append([ship.ship_id, how])
	for e in escapes:
		escape(e[0], e[1], phase)


## Whether `ship`'s tow is fouled, grappled or in a live boarding action, so that she may not
## escape with her (final-wave ruling: she would carry off a ship another holds).
func _tow_held(ship: ShipState) -> bool:
	if not ship.is_towing():
		return false
	var towed: ShipState = game_state.get_ship(ship.towing_id)
	return towed != null and (towed.is_linked() or escape_locked(game_state, towed.ship_id))


## The ship leaves the map where there is no sea room and is lost.
func lose_off_map(ship_id: String, edge: String, phase: int) -> void:
	if not is_server:
		push_error("MapController: Cannot lose a ship on client")
		return
	game_state.damage_controller.destroy(ship_id, "no_sea_room", phase, {"edge": edge})
	game_state.ship_controller.remove_from_map(ship_id)


## The speed a reinforcement enters at (2.B.1, 3.A.1): its movement allowance at its entry sail
## (PS unless the scenario says otherwise, capped by the rigging) and heading in the present wind,
## as if it had moved straight at that speed last turn. 0 in a calm, luffing or dismasted.
func arrival_speed(ship: ShipState) -> int:
	var env: EnvironmentState = game_state.environment
	return MapRules.max_ma_heading(ship, ship.facing, env.wind_direction, env.wind_speed,
			ship.sail_state)


## Start of `turn` (ENVIRONMENT, before the wind changes): every waiting reinforcement due by
## `turn`, by ship id, enters if neither of its hexes is held by a ship on the map, else its
## arrival is put back a turn (ARRIVAL_DELAYED, naming the holder).
func place_arrivals(turn: int, phase: int) -> void:
	if not is_server:
		push_error("MapController: Cannot place arrivals on client")
		return
	var ids: Array = game_state.ships.keys()
	ids.sort()
	for id in ids:
		var ship: ShipState = game_state.get_ship(str(id))
		if not ship.is_awaiting_arrival() or ship.arrives_turn > turn:
			continue
		var holder := _holder_of_entry(ship)
		if holder != "":
			game_state.ship_controller.delay_arrival(ship.ship_id, turn + 1)
			game_state.turn_log.add(PhaseEvents.Type.ARRIVAL_DELAYED, phase, ship.ship_id, {}, holder)
			continue
		var speed := arrival_speed(ship)
		game_state.ship_controller.place_arrival(ship.ship_id, speed)
		game_state.turn_log.add(PhaseEvents.Type.ARRIVED, phase, ship.ship_id, {
			"hex": {"q": ship.hex_position.x, "r": ship.hex_position.y},
			"facing": ship.facing, "sail_state": ship.sail_state, "speed": speed})
		Trace.trace_log("Map", "Ship %s arrives at %s, speed %d" % [ship.ship_id, str(ship.hex_position), speed])


## The id of a ship on the map holding the bow or stern hex of `ship`'s entry footprint, or "".
func _holder_of_entry(ship: ShipState) -> String:
	var mine := ship.occupied_hexes()
	for other: ShipState in game_state.ships_on_map():
		if other == ship:
			continue
		for h in other.occupied_hexes():
			if mine.has(h):
				return other.ship_id
	return ""
