class_name GunneryCalculator
extends RefCounted
## GunneryCalculator - pure queries over the 1997 gunnery rules (sections 9.1-9.4).
## Which broadsides can fire at which targets, and each shot's modified gunfire number.
## Never mutates state and never rolls dice.

const MAX_RANGE := 15
const MAX_DISMANTLING_RANGE := 7
const HIGH_ONLY_RANGE := 10
const SIDES: Array[int] = [ShipState.PORT, ShipState.STARBOARD]
const GUN_TYPES: Array[String] = ["lg", "mg", "cr"]

var game_state: Node


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## What `order` would do right now. `two_targets` is true when the same broadside is split.
func preview(order: GunneryTypes.FireOrder, two_targets: bool = false) -> GunneryTypes.ShotPreview:
	var p := GunneryTypes.ShotPreview.new()
	p.order = order
	var firer: ShipState = game_state.get_ship(order.ship_id)
	var target: ShipState = game_state.get_ship(order.target_id)
	if firer == null or target == null:
		return _refuse(p, "unknown ship")
	if firer.is_struck() or target.is_struck():
		return _refuse(p, "a struck ship cannot fire or be fired on")
	if firer.player_id == target.player_id:
		return _refuse(p, "cannot fire on a ship of the same side")
	if order.side != ShipState.PORT and order.side != ShipState.STARBOARD:
		return _refuse(p, "invalid broadside")

	var geometry: FireGeometry = game_state.fire_geometry
	var tables: CombatTables = DataManager.combat_tables
	p.range_hexes = geometry.hex_grid.hex_distance(
		firer.hex_position.x, firer.hex_position.y, target.hex_position.x, target.hex_position.y)
	p.high_only = p.range_hexes >= HIGH_ONLY_RANGE

	if geometry.bearing_side(firer.hex_position, firer.facing, target.hex_position) != order.side:
		return _refuse(p, "target is not in that broadside's arc")
	var max_range := MAX_DISMANTLING_RANGE if order.ammo == GunneryTypes.AMMO_DISMANTLING else MAX_RANGE
	if p.range_hexes > max_range:
		return _refuse(p, "target is out of range (%d hexes, maximum %d)" % [p.range_hexes, max_range])
	if not geometry.has_line_of_sight(firer.hex_position, target.hex_position, _occupied_hexes()):
		return _refuse(p, "no line of sight to target")
	var sections := firer.sections_able_to_fire()
	if sections == 0:
		return _refuse(p, "no sailor sections able to fire")

	var total := 0.0
	for gun_type in GUN_TYPES:
		total += float(firer.ship.gun_factors.get(gun_type, 0)) * tables.gunnery_multiplier(gun_type, p.range_hexes)
	p.tgf = ceili(total)
	if p.tgf <= 0:
		return _refuse(p, "no gunnery factor at this range")
	p.bgn = tables.basic_gunfire_number(p.tgf, p.range_hexes, firer.ship.is_french_gunned())
	if p.bgn < 0:
		return _refuse(p, "cannot fire at this range with this gunnery factor")

	_add_modifier(p, "crew_quality", tables.crew_quality_modifier(firer.crew_quality))
	_add_modifier(p, "sections_firing", tables.sections_firing_modifier(sections))
	_add_modifier(p, "guns_dismounted", -int(firer.guns_dismounted[order.side]))
	if p.range_hexes <= 5:
		p.rake = geometry.rake_type(target.hex_position, target.facing, firer.hex_position)
		if p.rake != "":
			_add_modifier(p, "rake", tables.range_bonus("rake", p.range_hexes))
		if not firer.initial_broadside_fired[order.side]:
			var bonus := tables.range_bonus("initial_broadside", p.range_hexes)
			p.initial_broadside = bonus != 0
			_add_modifier(p, "initial_broadside", bonus)
	if two_targets:
		_add_modifier(p, "two_targets", tables.flat_modifier("two_targets"))
	var wind_speed: int = game_state.environment.wind_speed
	if firer.sail_state.to_upper() == "PS" and wind_speed >= 2:
		_add_modifier(p, "plain_sail", tables.flat_modifier("plain_sail"))
	if order.ammo == GunneryTypes.AMMO_DISMANTLING:
		_add_modifier(p, "dismantling_shot", tables.flat_modifier("dismantling_shot"))
	if wind_speed >= 4:
		_add_modifier(p, "wind_speed_4", tables.flat_modifier("wind_speed_4"))
	if firer.is_dismasted():
		_add_modifier(p, "dismasted", -int(game_state.environment.sea_state))

	p.mgn = p.bgn
	for m in p.modifiers:
		p.mgn += int(m["value"])
	p.can_fire = true
	return p


## One preview per (side, target) that can fire roundshot. Aim is "high" when only high fire is allowed.
func eligible_shots(ship_id: String) -> Array[GunneryTypes.ShotPreview]:
	var shots: Array[GunneryTypes.ShotPreview] = []
	var firer: ShipState = game_state.get_ship(ship_id)
	if firer == null or firer.is_struck():
		return shots
	for target in game_state.get_all_ships():
		if target.ship_id == ship_id:
			continue
		for side in SIDES:
			var order := GunneryTypes.FireOrder.new()
			order.ship_id = ship_id
			order.side = side
			order.target_id = target.ship_id
			var probe := preview(order)
			if probe.can_fire:
				order.aim = GunneryTypes.AIM_HIGH if probe.high_only else GunneryTypes.AIM_LOW
				shots.append(probe)
	return shots


func any_eligible_shot() -> bool:
	for ship in game_state.get_all_ships():
		if not eligible_shots(ship.ship_id).is_empty():
			return true
	return false


## "" when the orders are legal for `player_id`, otherwise a message naming the first problem.
func validate_orders(player_id: int, orders: Array[GunneryTypes.FireOrder]) -> String:
	var seen: Dictionary = {}
	for order in orders:
		var firer: ShipState = game_state.get_ship(order.ship_id)
		if firer == null or firer.player_id != player_id:
			return "ship %s is not yours to command" % order.ship_id
		var key := "%s:%d" % [order.ship_id, order.side]
		if seen.has(key):
			return "ship %s has two orders for one broadside" % order.ship_id
		seen[key] = true
		if order.aim != GunneryTypes.AIM_LOW and order.aim != GunneryTypes.AIM_HIGH:
			return "unknown aim '%s'" % order.aim
		if order.ammo != GunneryTypes.AMMO_ROUND and order.ammo != GunneryTypes.AMMO_DISMANTLING:
			return "unknown ammunition '%s'" % order.ammo
		var shot := preview(order)
		if not shot.can_fire:
			return shot.reason
		if shot.high_only and order.aim == GunneryTypes.AIM_LOW:
			return "range %d allows only high fire" % shot.range_hexes
	return ""


func _refuse(p: GunneryTypes.ShotPreview, reason: String) -> GunneryTypes.ShotPreview:
	p.can_fire = false
	p.reason = reason
	return p


func _add_modifier(p: GunneryTypes.ShotPreview, modifier_name: String, value: int) -> void:
	if value != 0:
		p.modifiers.append({"name": modifier_name, "value": value})


func _occupied_hexes() -> Dictionary:
	var occupied: Dictionary = {}
	for ship in game_state.get_all_ships():
		occupied[ship.hex_position] = true
	return occupied
