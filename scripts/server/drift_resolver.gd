class_name DriftResolver
extends RefCounted
## DriftResolver - Drift of stopped ships (Close Action 1997, 10).
## A ship that did not move forward this turn, was in a collision, or is fouled rolls a d10 on the
## Drifting table. On a success it drifts one hex downwind, keeping its facing. A drift into an
## occupied hex or off the map is blocked; ramming into a ship may foul the two.
## All mutations go through ShipStateController.

var is_server: bool = true
var game_state: Node = null
var _hex_grid := HexGrid.new()


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## Resolve drift for `phase`.
##
## Dice order is part of the contract (tests script dice by position). Ships are processed
## leeward-most first (largest projection on the downwind world vector, ties by ship_id), each
## seeing the positions left by those before it. For each ship (or fouled pair, processed once at
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
	return _hex_grid.axial_to_world(ship.hex_position.x, ship.hex_position.y).dot(downwind_vector)


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

	var targets := {}
	var blocked := ""
	var blocker: ShipState = null
	if drifts:
		for ship in group:
			var target: Vector2i = _hex_grid.get_neighbor(ship.hex_position.x, ship.hex_position.y, downwind_dir)
			targets[ship.ship.ship_id] = target
			if not _in_bounds(target):
				blocked = "map edge"
				continue
			var occupant: ShipState = _occupant(target, group)
			if occupant != null and blocked != "map edge":
				blocked = "ship"
				blocker = occupant

	var moved: bool = drifts and blocked == ""
	for ship in group:
		var from: Vector2i = ship.hex_position
		var data := {
			"roll": roll,
			"needed": needed,
			"modifier": modifier,
			"drifted": moved,
			"from": {"q": from.x, "r": from.y},
		}
		if moved:
			var to: Vector2i = targets[ship.ship.ship_id]
			data["to"] = {"q": to.x, "r": to.y}
		elif blocked != "":
			data["blocked"] = blocked
		game_state.turn_log.add(PhaseEvents.Type.DRIFT, phase, ship.ship.ship_id, data)
	if moved:
		for ship in group:
			game_state.ship_controller.set_ship_position(ship.ship.ship_id, targets[ship.ship.ship_id])
	elif blocked == "ship" and group.size() == 1:
		_try_foul(group[0], blocker, phase)


func _try_foul(drifter: ShipState, other: ShipState, phase: int) -> void:
	## Only a free, unfouled pair can foul; a ship fouled with a third ship keeps its partner.
	if drifter.fouled_with != "" or other.fouled_with != "":
		return
	if not game_state.movement_resolver.roll_fouling(drifter, other, true):
		return
	var a: String = drifter.ship.ship_id
	var b: String = other.ship.ship_id
	game_state.ship_controller.set_fouled_with(a, b)
	game_state.ship_controller.set_fouled_with(b, a)
	game_state.turn_log.add(PhaseEvents.Type.FOULED, phase, a, {}, b)


func _occupant(hex: Vector2i, ignore: Array[ShipState]) -> ShipState:
	for ship in game_state.get_all_ships():
		if ship in ignore:
			continue
		if ship.hex_position == hex:
			return ship
	return null


## Same grid the hex map draws: width x height hexes centred on the origin (offset = -size / 2,
## integer division). No map_bounds in the scenario means nothing is out of bounds.
func _in_bounds(hex: Vector2i) -> bool:
	var bounds: Dictionary = game_state.active_scenario.get("map_bounds", {})
	if not bounds.has("width") or not bounds.has("height"):
		return true
	var width: int = int(bounds["width"])
	var height: int = int(bounds["height"])
	@warning_ignore("integer_division")
	var min_q: int = -width / 2
	@warning_ignore("integer_division")
	var min_r: int = -height / 2
	return hex.x >= min_q and hex.x < min_q + width and hex.y >= min_r and hex.y < min_r + height
