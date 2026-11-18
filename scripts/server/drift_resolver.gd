class_name DriftResolver
extends RefCounted
## DriftResolver - Drift of stopped ships (Close Action 1997, 10).
## A ship that did not move forward this turn, was in a collision, or is fouled rolls a d10 on the
## Drifting table. A destroyed ship (wreck) never drifts or fouls, but it blocks drift. On a success it drifts one hex downwind, keeping its facing. A drift into an
## occupied hex or off the map is blocked; drifting onto a ship may foul the two, and the drift
## line itself names the ship in the way and says whether they fouled.
## Ships fouled or grappled together drift as one group (8.A.6): the connected ships over
## ShipState.linked_ids(), one d10 by the member least likely to drift, never a partial drift, and
## the whole group stays when any of its hexes is blocked. An aground ship never drifts and holds its
## group (8.A.1); a drift onto land or into shoals too shallow for the draft runs the ship aground
## where it stands (13.G.2); a drift across a `none` edge loses the ship, across a crossable escape
## edge escapes it (map and scenario spec).
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
## it. Judging by the middle, a single ship whose hex would drift into another's is always the
## later one. A group of fouled or grappled ships (8.A.6) is processed once, at its most leeward
## member, so its other members may come before a ship they would drift into. For each ship or group:
##   1. the drift d10
##   2. only if that drift is blocked by another ship that may foul it: the fouling d10
##   3. only if nothing blocks: one depth d6 per member whose bow enters shallows, in group order
##      (for a partial drift, one d6 for the moving end, after the fouling d10)
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

	var ships: Array[ShipState] = game_state.ships_on_map()
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
		var group: Array[ShipState] = _linked_group(ship)
		for member in group:
			done[member.ship.ship_id] = true
		if not _is_eligible(group):
			continue
		_resolve_group(group, downwind_dir, wind_speed, phase)


## `ship` and every ship fouled or grappled to it, directly or through others (8.A.6), `ship`
## first, the rest by ship_id.
func _linked_group(ship: ShipState) -> Array[ShipState]:
	var seen := {ship.ship.ship_id: true}
	var queue: Array[ShipState] = [ship]
	var others: Array[ShipState] = []
	while not queue.is_empty():
		var current: ShipState = queue.pop_front()
		for other_id in current.linked_ids():
			if seen.has(other_id):
				continue
			var other: ShipState = game_state.get_ship(other_id)
			if other == null:
				continue
			seen[other_id] = true
			queue.append(other)
			others.append(other)
	others.sort_custom(func(a: ShipState, b: ShipState) -> bool: return a.ship.ship_id < b.ship.ship_id)
	var group: Array[ShipState] = [ship]
	group.append_array(others)
	return group


func _projection(ship: ShipState, downwind_vector: Vector3) -> float:
	return _hex_grid.ship_center_world(ship.hex_position, ship.facing).dot(downwind_vector)


## Whether `ship` is held in place and holds every ship tied to it (8.A.1: an aground ship never
## drifts). Anchoring will extend this one test; so will towing for the group.
func _holds_group(ship: ShipState) -> bool:
	return ship.is_aground()


func _is_eligible(group: Array[ShipState]) -> bool:
	for ship in group:
		if ship.is_destroyed():
			return false  # a wreck never drifts (its fouling was cleared when it blew up)
		if _holds_group(ship):
			return false
	for ship in group:
		if not ship.moved_this_turn or ship.collision_this_turn or ship.is_linked():
			return true
	return false


func _sail_key(ship: ShipState) -> String:
	return "dismasted" if ship.is_dismasted() else ship.sail_state.to_lower()


func _resolve_group(group: Array[ShipState], downwind_dir: int, wind_speed: int, phase: int) -> void:
	## The ship least likely to drift (higher number) decides for a fouled or grappled group (8.A.6),
	## with its own class modifier. A ship that never drifts (-1) holds the group in place.
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

	## Per ship: what stops it ("map edge" / "aground" / "ship"), and the ship in the way.
	var targets := {}
	var own_block := {}
	var own_blocker := {}
	var blocked := ""
	var blocker: ShipState = null
	var partial := ""
	var pivot := {}
	var others := {}
	var moves := {}      # ship_id -> MapRules.forced_move result (a drift that is not stopped)
	var grounded := {}   # ship_id -> AGROUND data of the ships this drift runs aground
	if drifts:
		## The whole footprint shifts one hex downwind. The group's own hexes never block.
		var group_ids: Array = []
		for ship in group:
			group_ids.append(ship.ship.ship_id)
		others = Occupancy.build(game_state.get_all_ships(), group_ids)
		for ship in group:
			var sid: String = ship.ship.ship_id
			targets[sid] = _hex_grid.get_neighbor(ship.hex_position.x, ship.hex_position.y, downwind_dir)
			var move: Dictionary = MapRules.forced_move(game_state.active_scenario, ship,
				ship.occupied_hexes(), _shifted(ship, downwind_dir), others, game_state.current_turn)
			moves[sid] = move
			match move["result"]:
				"edge":
					own_block[sid] = "map edge"
					blocked = "map edge"
				"land":
					own_block[sid] = "aground"
					grounded[sid] = _ground_data(ship, _land_hex(ship, downwind_dir), -1)
					if blocked != "map edge":
						blocked = "aground"
				"ship":
					own_block[sid] = "ship"
					own_blocker[sid] = move["blocker"]
					if blocked == "":
						blocked = "ship"
						blocker = game_state.get_ship(move["blocker"])

	# The fouled_with check is unreachable under the 8.A.2 order (a blocker is always resolved
	# first); kept so a fouled ship never partially drifts (8.A.6), e.g. one whose partner id is
	# dangling.
	if drifts and blocked == "ship" and group.size() == 1 and not group[0].is_linked():
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

	# The fouling roll comes after the drift roll (dice order unchanged); its outcome is logged on
	# the drift line, so a single line tells what happened. null: no fouling roll was made.
	var fouled: Variant = null
	if blocked == "ship" and group.size() == 1:
		fouled = _try_foul(group[0], blocker)

	if partial != "":
		# The moving end meets the terrain on its own (8.A.5): an edge or land stops the pivot, a
		# shoal under the bow end rolls its depth (after the fouling roll).
		var lone: ShipState = group[0]
		var lone_id: String = lone.ship.ship_id
		var from_end: Vector2i = lone.stern_hex() if partial == "stern" else lone.hex_position
		var to_end: Vector2i = _hex_grid.get_neighbor(from_end.x, from_end.y, downwind_dir)
		var end_move: Dictionary = MapRules.forced_move(game_state.active_scenario, lone,
			[from_end] as Array[Vector2i], [to_end] as Array[Vector2i], others, game_state.current_turn)
		if end_move["result"] != "clear":
			partial = ""
		elif end_move["shallow_bow"]:
			var depth := _roll_depth(to_end)
			if depth <= lone.ship.draft:
				partial = ""
				own_block[lone_id] = "aground"
				own_blocker.erase(lone_id)
				blocker = null
				blocked = "aground"
				grounded[lone_id] = _ground_data(lone, to_end, depth)
	elif drifts and blocked == "":
		# Depth dice, one per member whose bow enters shallows, in group order.
		for ship in group:
			var sid: String = ship.ship.ship_id
			if not moves[sid]["shallow_bow"]:
				continue
			var depth := _roll_depth(targets[sid])
			if depth <= ship.ship.draft:
				own_block[sid] = "aground"
				blocked = "aground"
				grounded[sid] = _ground_data(ship, targets[sid], depth)

	var moved: bool = drifts and blocked == ""

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
				# Free to drift itself, but held by a fouled or grappled member that is blocked.
				data["blocked"] = "partner"
				other_id = ship.fouled_with
				if other_id == "" or not own_block.has(other_id):
					other_id = _held_by(ship, own_block)
				# How it is tied to that ship: fouled (no key), grappled, or through other ships.
				if ship.fouled_with != other_id:
					data["link"] = "grappled" if ship.is_grappled_to(other_id) else "group"
			if fouled != null:
				data["fouled"] = fouled
		game_state.turn_log.add(PhaseEvents.Type.DRIFT, phase, sid, data, other_id)
	if moved:
		for ship in group:
			game_state.ship_controller.set_ship_position(ship.ship.ship_id, targets[ship.ship.ship_id])
		for ship in group:
			var sid: String = ship.ship.ship_id
			var move: Dictionary = moves[sid]
			if move["result"] == "lost":
				game_state.map_controller.lose_off_map(sid, move["edge"], phase)
			elif move["result"] == "escape":
				game_state.map_controller.escape(sid, {"how": "edge", "edge": move["edge"]}, phase)
	for sid in grounded:
		game_state.map_controller.ground(sid, grounded[sid], phase)


## The blocked group member that holds `ship` back: a directly linked one if any, else the first
## blocked member by ship_id.
func _held_by(ship: ShipState, own_block: Dictionary) -> String:
	for other_id in ship.linked_ids():
		if own_block.has(other_id):
			return other_id
	var ids: Array = own_block.keys()
	ids.sort()
	return str(ids[0]) if not ids.is_empty() else ""


## `ship`'s hexes (bow, stern) each one hex downwind.
func _shifted(ship: ShipState, downwind_dir: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for hex in ship.occupied_hexes():
		out.append(_hex_grid.get_neighbor(hex.x, hex.y, downwind_dir))
	return out


## The first of `ship`'s shifted hexes (bow first) that is land.
func _land_hex(ship: ShipState, downwind_dir: int) -> Vector2i:
	var terrain := TerrainMap.of(game_state.active_scenario)
	var shifted := _shifted(ship, downwind_dir)
	for hex in shifted:
		if terrain.is_land(hex):
			return hex
	return shifted[0]


## Depth of the shallow hex a drifting bow enters (13.G.1): base + d6, rolled through game_state.dice.
func _roll_depth(hex: Vector2i) -> int:
	var area := TerrainMap.of(game_state.active_scenario).area_at(hex)
	return (area.base if area != null else 0) + game_state.dice.d6()


## AGROUND data for a ship that drifts onto `hex` (`depth` -1 for land).
func _ground_data(ship: ShipState, hex: Vector2i, depth: int) -> Dictionary:
	return {"cause": "drift", "terrain": "land" if depth < 0 else "shallow",
		"hex": {"q": hex.x, "r": hex.y}, "depth": depth, "draft": ship.ship.draft}


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
	if drifter.is_destroyed() or other.is_destroyed():
		return null  # a wreck never fouls
	if not game_state.movement_resolver.roll_fouling(drifter, other, true):
		return false
	var a: String = drifter.ship.ship_id
	var b: String = other.ship.ship_id
	game_state.ship_controller.set_fouled_with(a, b)
	game_state.ship_controller.set_fouled_with(b, a)
	return true
