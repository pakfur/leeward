class_name GunneryCalculator
extends RefCounted
## GunneryCalculator - pure queries over the 1997 gunnery rules (sections 9.1-9.4).
## Which broadsides can fire at which targets, and each shot's modified gunfire number.
## Never mutates state and never rolls dice.

const SIDES: Array[int] = [ShipState.PORT, ShipState.STARBOARD]
const GUN_TYPES: Array[String] = ["lg", "mg", "cr"]

var game_state: Node


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## What `order` would do right now. `two_targets` is true when the firing ship's orders this turn
## name two different targets (7.C.12g: then every shot takes -12 and no half-broadside -8).
## The battery decides which of the firer's hexes fire: "full" needs both to bear (7.B.1),
## "bow"/"stern" is a half broadside (-8, 7.C.12f). Range, rake and gun factors stay the ship's.
## `initial_broadside_allowed` false withholds the 7.C.10 bonus; preview_orders() uses it when a
## split side's bonus goes to the other battery.
## A chase order (side GunneryTypes.CHASE_BOW/CHASE_STERN, battery "chase"; house rule, register §5)
## fires one long-gun factor (FireRules.CHASE_GUN_FACTORS) from the bow or stern hex, round shot only.
## It takes the ship-wide modifiers only: no half broadside, rake, initial broadside, guns dismounted,
## broadside obscured or lower deck closed.
func preview(order: GunneryTypes.FireOrder, two_targets: bool = false,
		initial_broadside_allowed: bool = true) -> GunneryTypes.ShotPreview:
	var p := GunneryTypes.ShotPreview.new()
	p.order = order
	var firer: ShipState = game_state.get_ship(order.ship_id)
	var target: ShipState = game_state.get_ship(order.target_id)
	if firer == null or target == null:
		return _refuse(p, "unknown ship")
	if firer.is_destroyed() or target.is_destroyed():
		return _refuse(p, "a destroyed ship cannot fire or be fired on")
	if firer.is_captured():
		return _refuse(p, "a prize does not fight (10.H.2)")
	if firer.is_aground():
		return _refuse(p, "an aground ship cannot fire its guns (13.G.3)")
	if firer.is_out_of_play() or not target.is_targetable():
		return _refuse(p, "a struck ship cannot fire or be fired on")
	if firer.side == target.side:
		return _refuse(p, "cannot fire on a ship of the same side")
	var chase := GunneryTypes.is_chase_side(order.side)
	if order.side != ShipState.PORT and order.side != ShipState.STARBOARD and not chase:
		return _refuse(p, "invalid broadside")
	if not GunneryTypes.is_known_battery(order.battery):
		return _refuse(p, "unknown battery '%s'" % order.battery)
	if FireRules.chase_mismatch(order.side, order.battery):
		return _refuse(p, "a chaser fires only from its own end")
	if chase and order.ammo == GunneryTypes.AMMO_DISMANTLING:
		return _refuse(p, "chasers fire round shot only")

	var geometry: FireGeometry = game_state.fire_geometry
	var tables: CombatTables = DataManager.combat_tables
	var firer_hexes := firer.occupied_hexes()
	var battery_hexes: Array[Vector2i] = [FireGeometry.chase_battery_hex(firer, order.side)]
	if not chase:
		battery_hexes = _battery_hexes(firer_hexes, order.battery)
	var target_hexes := target.occupied_hexes()
	p.range_hexes = geometry.range_between(firer_hexes, target_hexes)
	p.high_only = FireRules.high_only(p.range_hexes)

	if not _any_in_arc(geometry, battery_hexes, firer.facing, order.side, target_hexes):
		if chase:
			return _refuse(p, "target is not in the %s's arc" % PhaseEvents.CHASE_NAMES[order.side])
		return _refuse(p, "target is not in that broadside's arc")
	var max_range := FireRules.max_range(order.ammo)
	if p.range_hexes > max_range:
		return _refuse(p, "target is out of range (%d hexes, maximum %d)" % [p.range_hexes, max_range])
	# 7.B.7: neither the firer's nor the target's own hexes block its lines of sight.
	var occupied := _occupied_hexes([firer.ship_id, target.ship_id])
	var friends := friendly_ships(firer)
	var bearing: Array[String] = []
	var blocked_by: ShipState = null
	var blocked_name := ""
	for i in battery_hexes.size():
		var blocking := battery_blocking_hexes(battery_hexes[i], firer, order.side, friends)
		if geometry.battery_bears(battery_hexes[i], firer.facing, order.side, target_hexes, occupied, blocking):
			bearing.append(_battery_name(order.battery, i))
		elif blocked_by == null and geometry.battery_bears(battery_hexes[i], firer.facing, order.side,
				target_hexes, occupied):
			blocked_by = _blocking_friend(battery_hexes[i], firer, order.side, target_hexes, occupied, friends)
			if blocked_by != null:
				blocked_name = _battery_name(order.battery, i)
	if bearing.is_empty():
		if blocked_by != null:
			return _refuse(p, "Blocked by friendly ship %s" % blocked_by.ship_name)
		return _refuse(p, "no line of sight to target")
	if bearing.size() < battery_hexes.size():
		var why := "only the %s battery bears: a full broadside needs both" % bearing[0]
		if blocked_by != null:
			why += " (%s blocked by friendly ship %s)" % [blocked_name, blocked_by.ship_name]
		return _refuse(p, why)
	p.batteries = bearing.size()
	var sections := firer.sections_able_to_fire()
	if sections == 0:
		return _refuse(p, "no sailor sections able to fire")

	var gun_factors: Dictionary = FireRules.CHASE_GUN_FACTORS if chase else firer.ship.gun_factors
	var total := 0.0
	for gun_type in GUN_TYPES:
		total += float(gun_factors.get(gun_type, 0)) * tables.gunnery_multiplier(gun_type, p.range_hexes)
	p.tgf = ceili(total)
	if p.tgf <= 0:
		return _refuse(p, "no gunnery factor at this range")
	p.bgn = tables.basic_gunfire_number(p.tgf, p.range_hexes, firer.is_french_gunned())
	if p.bgn < 0:
		return _refuse(p, "cannot fire at this range with this gunnery factor")

	_add_modifier(p, "crew_quality", tables.crew_quality_modifier(firer.crew_quality))
	_add_modifier(p, "sections_firing", tables.sections_firing_modifier(sections))
	if not chase:
		_add_modifier(p, "guns_dismounted", -int(firer.guns_dismounted[order.side]))
		# 7.C.11: -2 per broadside obscured entry on this side (Rigging #6; #10 obscures both).
		_add_modifier(p, "broadside_obscured", firer.obscured_penalty(order.side))
		# 7.C.12g: when firing at two targets only the two-target modifier applies, full or half.
		if order.battery != GunneryTypes.BATTERY_FULL and not two_targets:
			_add_modifier(p, "half_broadside", tables.flat_modifier("half_broadside"))
	# A chaser never rakes and never earns or spends an initial broadside: p.rake stays "".
	if not chase and p.range_hexes <= FireGeometry.RAKE_RANGE:
		p.rake = geometry.rake_type_ships(target.hex_position, target.facing, firer_hexes)
		if p.rake != "":
			_add_modifier(p, "rake", tables.range_bonus("rake", p.range_hexes))
		if initial_broadside_allowed and not firer.initial_broadside_fired[order.side]:
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
	# 7.C.12c: an anchored ship (still anchored on the turn she cuts) fires steadier.
	if firer.is_anchored():
		_add_modifier(p, "anchored", tables.flat_modifier("anchored"))
	if not chase:
		_add_modifier(p, "lower_deck_closed", _lower_deck_modifier(firer, order.side))
	if firer.is_dismasted():
		_add_modifier(p, "dismasted", -int(game_state.environment.sea_state))
	# 7.C.14: a player may reduce the MGN by any amount (an FGN below 1 does no damage).
	if order.mgn_reduction > 0:
		_add_modifier(p, "voluntary_reduction", -order.mgn_reduction)

	p.mgn = p.bgn
	for m in p.modifiers:
		p.mgn += int(m["value"])
	p.can_fire = true
	return p


## One preview per (side, target, battery) that can fire roundshot, battery in BATTERIES order:
## "full" when both batteries bear, and each battery that bears on its own; after all of them, one
## per (target, chase side) that can fire. Previews assume one target. Aim is "high" when only high
## fire is allowed.
func eligible_shots(ship_id: String) -> Array[GunneryTypes.ShotPreview]:
	var shots: Array[GunneryTypes.ShotPreview] = []
	var firer: ShipState = game_state.get_ship(ship_id)
	if firer == null or firer.is_out_of_play():
		return shots
	for target in game_state.get_all_ships():
		if target.ship_id == ship_id:
			continue
		for side in SIDES:
			for battery in GunneryTypes.BATTERIES:
				var order := GunneryTypes.FireOrder.new()
				order.ship_id = ship_id
				order.side = side
				order.target_id = target.ship_id
				order.battery = battery
				_append_if_eligible(shots, order)
	# Then the chasers (house rule, register §5): one preview per target per chase side.
	for target in game_state.get_all_ships():
		if target.ship_id == ship_id:
			continue
		for side in GunneryTypes.CHASE_SIDES:
			var order := GunneryTypes.FireOrder.new()
			order.ship_id = ship_id
			order.side = side
			order.target_id = target.ship_id
			order.battery = GunneryTypes.BATTERY_CHASE
			_append_if_eligible(shots, order)
	return shots


## Appends the preview of `order` when it can fire, aiming high when only high fire is allowed.
func _append_if_eligible(shots: Array[GunneryTypes.ShotPreview], order: GunneryTypes.FireOrder) -> void:
	var probe := preview(order)
	if probe.can_fire:
		order.aim = GunneryTypes.AIM_HIGH if probe.high_only else GunneryTypes.AIM_LOW
		shots.append(probe)


## Previews of a whole set of orders, as they will resolve, in `orders` order:
## - two_targets per ship from target_count (7.C.12g);
## - 7.C.10 "once for each broadside": when a side fires more than one battery shot that would
##   earn the initial-broadside bonus, only the one with the larger bonus (closer range) keeps it,
##   the bow battery on a tie; the others are re-previewed without it.
## Single-order previews (preview()) cannot know the rest of the set; the resolver uses this.
func preview_orders(orders: Array[GunneryTypes.FireOrder]) -> Array[GunneryTypes.ShotPreview]:
	var previews: Array[GunneryTypes.ShotPreview] = []
	var holder_by_side := {}   # "ship:side" -> index into previews
	for i in orders.size():
		var order := orders[i]
		var p := preview(order, target_count(order.ship_id, orders) > 1)
		previews.append(p)
		if not (p.can_fire and p.initial_broadside):
			continue
		var key := "%s:%d" % [order.ship_id, order.side]
		if not holder_by_side.has(key) or _ib_beats(p, previews[holder_by_side[key]]):
			holder_by_side[key] = i
	for i in orders.size():
		var p := previews[i]
		if not (p.can_fire and p.initial_broadside):
			continue
		if holder_by_side["%s:%d" % [p.order.ship_id, p.order.side]] != i:
			previews[i] = preview(p.order, target_count(p.order.ship_id, orders) > 1, false)
	return previews


## Number of different targets the orders of `ship_id` name (FireRules.target_count).
static func target_count(ship_id: String, orders: Array) -> int:
	return FireRules.target_count(ship_id, orders)


func any_eligible_shot() -> bool:
	for ship in game_state.get_all_ships():
		if not eligible_shots(ship.ship_id).is_empty():
			return true
	return false


## "" when the orders are legal for `player_id`, otherwise a message naming the first problem.
## Declaration rules (FireRules.declaration_error): each battery fires at most once ("battery fired
## twice"), at most two targets per ship ("more than two targets", 7.A.4), and bow and stern of one
## side may not name the same target (that is a full broadside and must be declared so). Then each
## order must be able to fire, and range 10+ must aim high.
func validate_orders(player_id: int, orders: Array[GunneryTypes.FireOrder]) -> String:
	for order in orders:
		var firer: ShipState = game_state.get_ship(order.ship_id)
		if firer == null or not game_state.commands(player_id, firer.ship_id):
			return "ship %s is not yours to command" % order.ship_id
	var declaration := FireRules.declaration_error(orders)
	if declaration != "":
		return declaration
	for order in orders:
		if order.mgn_reduction < 0:
			return "Reduction cannot be negative"
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


## 7.F.2 (Freeboard Calculation): the LDGM when the sea has shut this broadside's lower-deck guns
## (FireRules.lower_deck_modifier; the ship card's Guns rows use the same rule).
func _lower_deck_modifier(firer: ShipState, side: int) -> int:
	var env: EnvironmentState = game_state.environment
	return FireRules.lower_deck_modifier(firer, side, env.sea_state, env.wind_direction)


func _add_modifier(p: GunneryTypes.ShotPreview, modifier_name: String, value: int) -> void:
	if value != 0:
		p.modifiers.append({"name": modifier_name, "value": value})


## The ships friendly to `firer` (7.B.10): its side (`player_id`, so a prize counts for her
## captor), struck ones included, the firer and ships removed from the map (8.G.1f) left out.
func friendly_ships(firer: ShipState) -> Array[ShipState]:
	var friends: Array[ShipState] = []
	for ship: ShipState in game_state.ships_on_map():
		if ship.ship_id != firer.ship_id and ship.side == firer.side:
			friends.append(ship)
	return friends


## The friendly blocking hexes (7.B.10-12) of `firer`'s `side` battery at `battery_hex`.
func battery_blocking_hexes(battery_hex: Vector2i, firer: ShipState, side: int,
		friends: Array[ShipState]) -> Dictionary:
	return game_state.fire_geometry.blocking_hexes(battery_hex, firer.facing, side,
		firer.occupied_hexes(), friends.map(func(f: ShipState) -> Array[Vector2i]: return f.occupied_hexes()))


## The friend whose blocking hexes stop a battery that bears without them: the first whose own
## blocking hexes do it, else the first that makes any for this battery (several together).
func _blocking_friend(battery_hex: Vector2i, firer: ShipState, side: int, target_hexes: Array[Vector2i],
		occupied: Dictionary, friends: Array[ShipState]) -> ShipState:
	var geometry: FireGeometry = game_state.fire_geometry
	var first_with_hexes: ShipState = null
	for friend in friends:
		var own: Array[ShipState] = [friend]
		var blocking := battery_blocking_hexes(battery_hex, firer, side, own)
		if blocking.is_empty():
			continue
		if first_with_hexes == null:
			first_with_hexes = friend
		if not geometry.battery_bears(battery_hex, firer.facing, side, target_hexes, occupied, blocking):
			return friend
	return first_with_hexes


## Bow and stern hex of every ship (struck ones included), minus `exclude_ids`, and every land
## hex ("land"): land blocks line of sight like a ship (7.B.7-9; shallows do not).
func _occupied_hexes(exclude_ids: Array = []) -> Dictionary:
	var occupied := Occupancy.build(game_state.get_all_ships(), exclude_ids)
	for hex in TerrainMap.of(game_state.active_scenario).land:
		occupied[hex] = "land"
	return occupied


## The firer hexes a battery fires from: `ship_hexes` is [bow, stern].
static func _battery_hexes(ship_hexes: Array[Vector2i], battery: String) -> Array[Vector2i]:
	match battery:
		GunneryTypes.BATTERY_BOW:
			return [ship_hexes[0]]
		GunneryTypes.BATTERY_STERN:
			return [ship_hexes[1]]
	return ship_hexes


## The single battery behind index `i` of `_battery_hexes(..., battery)`.
static func _battery_name(battery: String, i: int) -> String:
	if battery == GunneryTypes.BATTERY_FULL:
		return GunneryTypes.BATTERY_BOW if i == 0 else GunneryTypes.BATTERY_STERN
	return battery


## True when shot `a` has the better claim on its side's initial-broadside bonus than `b`.
static func _ib_beats(a: GunneryTypes.ShotPreview, b: GunneryTypes.ShotPreview) -> bool:
	var bonus_a := _modifier_value(a, "initial_broadside")
	var bonus_b := _modifier_value(b, "initial_broadside")
	if bonus_a != bonus_b:
		return bonus_a > bonus_b
	return GunneryTypes.BATTERIES.find(a.order.battery) < GunneryTypes.BATTERIES.find(b.order.battery)


static func _modifier_value(p: GunneryTypes.ShotPreview, modifier_name: String) -> int:
	for m in p.modifiers:
		if m["name"] == modifier_name:
			return int(m["value"])
	return 0


## Whether any of `target_hexes` lies in the `side` arc of any of `battery_hexes`.
func _any_in_arc(geometry: FireGeometry, battery_hexes: Array[Vector2i], facing: int, side: int,
		target_hexes: Array[Vector2i]) -> bool:
	for battery in battery_hexes:
		for h in target_hexes:
			if geometry.in_battery_arc(battery, facing, side, h):
				return true
	return false
