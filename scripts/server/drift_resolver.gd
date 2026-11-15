class_name DriftResolver
extends RefCounted
## DriftResolver - Drift of stopped ships (Close Action 1997, 10).
## A ship that did not move forward this turn, was in a collision, or is fouled rolls a d10 on the
## Drifting table. On a success it drifts one hex downwind, keeping its facing. A drift into an
## occupied hex or off the map is blocked; drifting onto a ship may foul the two, and the drift
## line itself names the ship in the way and says whether they fouled.
## All mutations go through ShipStateController.

var is_server: bool = true
var game_state: Node = null
var _hex_grid := HexGrid.new()


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## Resolve drift for `phase`.
##
## Dice order is part of the contract (tests script dice by position). Ships are processed
## leeward-most first (8.A.2: largest projection of the footprint's middle, between bow and stern,
## on the downwind world vector; ties by ship_id), each seeing the positions left by those before
## it. Judging by the middle, a ship whose hex would drift into another's is always the later one. For each ship (or fouled pair, processed once at
## its more leeward member):
##   1. the drift d10
##   2. only if that drift is blocked by another ship that may foul it: the fouling d10
## At wind speed 0 nothing is rolled and nothing is logged.
func resolve(phase: int) -> void:
	if not is_server:
		push_error("DriftResolver: Cannot resolve drift on client")
		return
	var wind_speed: int = game_state.environment.wind_speed
	if wind_speed <= 0:
		return

	var downwind_dir: int = (game_state.environment.wind_direction + 3) % 6
	var delta: Vector2i = HexGrid.DIRECTIONS[downwind_dir]
	var downwind_vector: Vector3 = _hex_grid.axial_to_world(delta.x, delta.y)

	var ships: Array[ShipState] = game_state.get_all_ships()
	ships.sort_custom(func(x: ShipState, y: ShipState) -> bool:
		var px := _projection(x, downwind_vector)
		var py := _projection(y, downwind_vector)
		if not is_equal_approx(px, py):
			return px > py
		return x.ship.ship_id < y.ship.ship_id)

	var done := {}
	for ship in ships:
		var sid: String = ship.ship.ship_id
		if done.has(sid):
			continue
		done[sid] = true
		var group: Array[ShipState] = [ship]
		var partner: ShipState = game_state.get_ship(ship.fouled_with) if ship.fouled_with != "" else null
		if partner != null and not done.has(partner.ship.ship_id):
			done[partner.ship.ship_id] = true
			group.append(partner)
		if not _is_eligible(group):
			continue
		_resolve_group(group, downwind_dir, wind_speed, phase)


func _projection(ship: ShipState, downwind_vector: Vector3) -> float:
	return _hex_grid.ship_center_world(ship.hex_position, ship.facing).dot(downwind_vector)


func _is_eligible(group: Array[ShipState]) -> bool:
	for ship in group:
		if not ship.moved_this_turn or ship.collision_this_turn or ship.fouled_with != "":
			return true
	return false


func _sail_key(ship: ShipState) -> String:
	return "dismasted" if ship.is_dismasted() else ship.sail_state.to_lower()


func _resolve_group(group: Array[ShipState], downwind_dir: int, wind_speed: int, phase: int) -> void:
	## The ship that is harder to drift (higher number) decides for a fouled pair, with its own
	## class modifier. A ship that never drifts (-1) holds the pair in place.
	var decider: ShipState = null
	var needed := 0
	for ship in group:
		var number: int = DataManager.combat_tables.drift_number(_sail_key(ship), wind_speed)
		if number < 0:
			return
		if decider == null or number > needed:
			decider = ship
			needed = number
	var modifier: int = DataManager.combat_tables.drift_class_drm(decider.ship.ship_class)
	var roll: int = game_state.dice.d10()
	var drifts: bool = roll + modifier >= needed

	## Per ship: what stops it ("map edge" / "ship"), and the ship in the way.
	var targets := {}
	var own_block := {}
	var own_blocker := {}
	var blocked := ""
	var blocker: ShipState = null
	var partial := ""
	var pivot := {}
	var others := {}
	if drifts:
		## The whole footprint shifts one hex downwind. The group's own hexes never block.
		var group_ids: Array = []
		for ship in group:
			group_ids.append(ship.ship.ship_id)
		others = Occupancy.build(game_state.get_all_ships(), group_ids)
		for ship in group:
			var sid: String = ship.ship.ship_id
			targets[sid] = _hex_grid.get_neighbor(ship.hex_position.x, ship.hex_position.y, downwind_dir)
			var block: Dictionary = _first_block(ship, downwind_dir, others)
			if block.is_empty():
				continue
			own_block[sid] = block["blocked"]
			if block["blocked"] == "map edge":
				blocked = "map edge"
				continue
			own_blocker[sid] = block["blocker"]
			if blocked == "":
				blocked = "ship"
				blocker = game_state.get_ship(block["blocker"])

	# The fouled_with check is not redundant: a ship the partner drifted onto and fouled earlier
	# this phase comes up later in a group of one, and a fouled ship never partially drifts (8.A.6).
	if drifts and blocked == "ship" and group.size() == 1 and group[0].fouled_with == "":
		# Partial drift (8.A.5): only the bow or only the stern is blocked by a ship; the free end
		# drifts and the ship pivots on the other, if that leaves a legal two-hex footprint.
		var lone: ShipState = group[0]
		var stern_from: Vector2i = lone.stern_hex()
		var stern_to: Vector2i = _hex_grid.get_neighbor(stern_from.x, stern_from.y, downwind_dir)
		var bow_blocked: bool = others.has(targets[lone.ship.ship_id])
		var stern_blocked: bool = others.has(stern_to)
		if bow_blocked != stern_blocked:
			var free_end := "stern" if bow_blocked else "bow"
			var result: Dictionary = _partial_drift(lone, free_end, downwind_dir)
			if not result.is_empty():
				partial = free_end
				pivot = result

	var moved: bool = drifts and blocked == ""
	# The fouling roll comes after the drift roll (dice order unchanged); its outcome is logged on
	# the drift line, so a single line tells what happened. null: no fouling roll was made.
	var fouled: Variant = null
	if blocked == "ship" and group.size() == 1:
		fouled = _try_foul(group[0], blocker)

	if partial != "":
		var lone: ShipState = group[0]
		var from_hex: Vector2i = lone.hex_position
		var new_bow: Vector2i = pivot["bow"]
		var partial_data := {
			"roll": roll, "needed": needed, "modifier": modifier, "drifted": true,
			"from": {"q": from_hex.x, "r": from_hex.y}, "to": {"q": new_bow.x, "r": new_bow.y},
			"partial": partial, "facing": pivot["facing"],
		}
		if fouled != null:
			partial_data["fouled"] = fouled
		game_state.turn_log.add(PhaseEvents.Type.DRIFT, phase, lone.ship.ship_id, partial_data, blocker.ship.ship_id)
		game_state.ship_controller.set_ship_position(lone.ship.ship_id, new_bow)
		game_state.ship_controller.set_ship_facing(lone.ship.ship_id, pivot["facing"])
		return

	for ship in group:
		var sid: String = ship.ship.ship_id
		var from: Vector2i = ship.hex_position
		var data := {
			"roll": roll,
			"needed": needed,
			"modifier": modifier,
			"drifted": moved,
			"from": {"q": from.x, "r": from.y},
		}
		var other_id := ""
		if moved:
			var to: Vector2i = targets[sid]
			data["to"] = {"q": to.x, "r": to.y}
		elif blocked != "":
			if own_block.has(sid):
				data["blocked"] = own_block[sid]
				other_id = own_blocker.get(sid, "")
			else:
				# Free to drift itself, but held by the fouled partner that is blocked.
				data["blocked"] = "partner"
				other_id = ship.fouled_with
			if fouled != null:
				data["fouled"] = fouled
		game_state.turn_log.add(PhaseEvents.Type.DRIFT, phase, sid, data, other_id)
	if moved:
		for ship in group:
			game_state.ship_controller.set_ship_position(ship.ship.ship_id, targets[ship.ship.ship_id])


## What first stops `ship`'s whole footprint shifting one hex downwind: {} when nothing does,
## {"blocked": "map edge"} when a hex would leave the map (that outranks a ship), otherwise
## {"blocked": "ship", "blocker": id} for the first of its hexes (bow, then stern) that would enter
## a hex in `others` (hex -> ship id).
func _first_block(ship: ShipState, downwind_dir: int, others: Dictionary) -> Dictionary:
	var result := {}
	for hex in ship.occupied_hexes():
		var shifted: Vector2i = _hex_grid.get_neighbor(hex.x, hex.y, downwind_dir)
		if not _in_bounds(shifted):
			return {"blocked": "map edge"}
		if result.is_empty() and others.has(shifted):
			result = {"blocked": "ship", "blocker": others[shifted]}
	return result


## The footprint after only one end of `ship` drifts one hex downwind: the free end ("bow" or
## "stern") moves, the other stays. Returns {bow, facing}, or {} when the two hexes would not be
## neighbours (5.A.2c: a ship always points at its other hex), so the ship does not drift.
func _partial_drift(ship: ShipState, free_end: String, downwind_dir: int) -> Dictionary:
	var step: Vector2i = HexGrid.DIRECTIONS[downwind_dir]
	var new_bow: Vector2i = ship.hex_position
	var new_stern: Vector2i = ship.stern_hex()
	if free_end == "stern":
		new_stern += step
	else:
		new_bow += step
	var facing: int = HexGrid.DIRECTIONS.find(new_bow - new_stern)
	if facing < 0:
		return {}
	return {"bow": new_bow, "facing": facing}


## Rolls to foul a drifter against the ship blocking it. Returns whether they fouled, or null when
## no roll is made: only a free, unfouled pair can foul (a ship fouled with a third ship keeps its
## partner), and a dismasted ship never fouls.
func _try_foul(drifter: ShipState, other: ShipState) -> Variant:
	if drifter.fouled_with != "" or other.fouled_with != "":
		return null
	if drifter.is_dismasted() or other.is_dismasted():
		return null
	if not game_state.movement_resolver.roll_fouling(drifter, other, true):
		return false
	var a: String = drifter.ship.ship_id
	var b: String = other.ship.ship_id
	game_state.ship_controller.set_fouled_with(a, b)
	game_state.ship_controller.set_fouled_with(b, a)
	return true


func _in_bounds(hex: Vector2i) -> bool:
	return Occupancy.in_bounds(hex, game_state.active_scenario)
