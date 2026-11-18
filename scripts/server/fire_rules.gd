class_name FireRules
extends RefCounted
## FireRules - the declaration rules for fire orders, as pure static functions (no state, no dice).
## The single place these rules live: GunneryCalculator (preview / validate_orders), the stub AI
## and the fire declaration panel (read-only queries) all use them.
## - 7.A.4: a ship names at most MAX_TARGETS targets.
## - 7.B.1: each battery fires at most once; bow and stern of one side at one target is a full
##   broadside and must be declared as one; a full broadside is preferred over a half.
## - Chasers (house rule, register §5): an order on side GunneryTypes.CHASE_BOW/CHASE_STERN uses
##   battery "chase" and no other; each chaser fires once, counts towards MAX_TARGETS, round shot only.
## - 7.C.5 / 9.x: roundshot reaches MAX_RANGE, dismantling MAX_DISMANTLING_RANGE; from
##   HIGH_ONLY_RANGE on only high fire is allowed.

const MAX_RANGE := 15
const MAX_DISMANTLING_RANGE := 7
const HIGH_ONLY_RANGE := 10
const MAX_TARGETS := 2
## 7.G.1: marines fire only at adjacent ships (the optional range-2 rule is not offered).
const MARINE_RANGE := 1
## House rule, register §5: each chaser (bow and stern) is one long-gun factor.
const CHASE_GUN_FACTORS := {"lg": 1, "mg": 0, "cr": 0}
## 14.D.2-3 (optional fatigue): no penalty for the first 5 firing turns, then -1, and a further -1
## for each 10 more. The register reads "g-t 15" as -2 from the 16th firing turn; no recovery.
const FATIGUE_FREE_TURNS := 5
const FATIGUE_STEP_TURNS := 10


## The fatigue penalty (a positive number to subtract) of a ship that has fired in `prior` earlier
## turns: the shot of its 6th firing turn takes -1 (prior 5), its 16th -2 (prior 15), and so on.
static func fatigue_penalty(prior: int) -> int:
	if prior < FATIGUE_FREE_TURNS:
		return 0
	@warning_ignore("integer_division")
	return 1 + (prior - FATIGUE_FREE_TURNS) / FATIGUE_STEP_TURNS


## Ranges from HIGH_ONLY_RANGE on allow only high fire.
static func high_only(range_hexes: int) -> bool:
	return range_hexes >= HIGH_ONLY_RANGE


static func max_range(ammo: String) -> int:
	return MAX_DISMANTLING_RANGE if ammo == GunneryTypes.AMMO_DISMANTLING else MAX_RANGE


static func dismantling_allowed(range_hexes: int) -> bool:
	return range_hexes <= MAX_DISMANTLING_RANGE


## The aim an order carries: high when the range forces it, else the wanted aim.
static func effective_aim(wanted_aim: String, is_high_only: bool) -> String:
	return GunneryTypes.AIM_HIGH if is_high_only else wanted_aim


## Dismantling only when wanted and within its range; roundshot otherwise.
static func effective_ammo(want_dismantling: bool, range_hexes: int) -> String:
	return GunneryTypes.AMMO_DISMANTLING if want_dismantling and dismantling_allowed(range_hexes) \
		else GunneryTypes.AMMO_ROUND


## The single batteries an order uses.
static func single_batteries(battery: String) -> Array[String]:
	if battery == GunneryTypes.BATTERY_FULL:
		return [GunneryTypes.BATTERY_BOW, GunneryTypes.BATTERY_STERN] as Array[String]
	return [battery] as Array[String]


## Lower is preferred: a full broadside before a half broadside (7.B.1, 7.C.12f), a chaser last.
static func battery_rank(battery: String) -> int:
	if battery == GunneryTypes.BATTERY_FULL:
		return 0
	if battery == GunneryTypes.BATTERY_CHASE:
		return 2
	return 1


## True when an order's side and battery disagree: a chase side with a broadside battery, or a
## broadside with the "chase" battery.
static func chase_mismatch(side: int, battery: String) -> bool:
	return GunneryTypes.is_chase_side(side) != (battery == GunneryTypes.BATTERY_CHASE)


## One side's shots from the target of each battery ("" = that battery holds): bow and stern at
## one target is one full broadside, else one half broadside per battery that fires.
## Returns [{"target_id", "battery"}].
static func side_shots(bow_target: String, stern_target: String) -> Array:
	if bow_target != "" and bow_target == stern_target:
		return [{"target_id": bow_target, "battery": GunneryTypes.BATTERY_FULL}]
	var shots: Array = []
	if bow_target != "":
		shots.append({"target_id": bow_target, "battery": GunneryTypes.BATTERY_BOW})
	if stern_target != "":
		shots.append({"target_id": stern_target, "battery": GunneryTypes.BATTERY_STERN})
	return shots


## An order with the aim and ammunition it must carry at `range_hexes`.
static func make_order(ship_id: String, side: int, target_id: String, battery: String,
		want_high: bool, want_dismantling: bool, range_hexes: int, mgn_reduction: int = 0) -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = side
	order.target_id = target_id
	order.battery = battery
	order.aim = effective_aim(GunneryTypes.AIM_HIGH if want_high else GunneryTypes.AIM_LOW, high_only(range_hexes))
	# A chaser fires round shot only (house rule, register §5).
	order.ammo = effective_ammo(want_dismantling and battery != GunneryTypes.BATTERY_CHASE, range_hexes)
	order.mgn_reduction = mgn_reduction
	return order


## Number of different targets the orders of `ship_id` name (7.A.4, 7.C.12g).
static func target_count(ship_id: String, orders: Array) -> int:
	var targets: Dictionary = {}
	for order: GunneryTypes.FireOrder in orders:
		if order.ship_id == ship_id:
			targets[order.target_id] = true
	return targets.size()


## "" when the set obeys the declaration rules (independent of geometry), else the problem:
## "unknown battery", "a chaser fires only from its own end", "battery fired twice",
## "declare a full broadside", "more than two targets".
static func declaration_error(orders: Array) -> String:
	var used: Dictionary = {}       # "ship:side:bow|stern|chase" -> target_id
	for order: GunneryTypes.FireOrder in orders:
		if not GunneryTypes.is_known_battery(order.battery):
			return "unknown battery '%s'" % order.battery
		if chase_mismatch(order.side, order.battery):
			return "a chaser fires only from its own end (side %d, battery %s)" % [order.side, order.battery]
		for battery in single_batteries(order.battery):
			var key := "%s:%d:%s" % [order.ship_id, order.side, battery]
			if used.has(key):
				return "battery fired twice"
			used[key] = order.target_id
		if order.battery == GunneryTypes.BATTERY_BOW or order.battery == GunneryTypes.BATTERY_STERN:
			var other := GunneryTypes.BATTERY_STERN if order.battery == GunneryTypes.BATTERY_BOW \
					else GunneryTypes.BATTERY_BOW
			if used.get("%s:%d:%s" % [order.ship_id, order.side, other], "") == order.target_id:
				return "ship %s fires both batteries of one side at %s: declare a full broadside" \
						% [order.ship_id, order.target_id]
		if target_count(order.ship_id, orders) > MAX_TARGETS:
			return "more than two targets"
	return ""


## Keep one ship's battery targets within MAX_TARGETS. `sides` is side -> {"bow", "stern", ...}
## (target per battery, "" holds). The side just changed keeps its targets; other sides drop
## batteries aimed elsewhere, stern first. Returns a deep copy.
static func limit_targets(sides: Dictionary, changed_side: int) -> Dictionary:
	var out: Dictionary = sides.duplicate(true)
	var keep := {}
	if out.has(changed_side):
		for key in ["bow", "stern"]:
			if str(out[changed_side][key]) != "":
				keep[str(out[changed_side][key])] = true
	var others := out.keys()
	others.sort()
	while battery_targets(out).size() > MAX_TARGETS:
		var dropped := false
		for side in others:
			if side == changed_side:
				continue
			for key in ["stern", "bow"]:
				var t := str(out[side][key])
				if t != "" and not keep.has(t):
					out[side][key] = ""
					dropped = true
					break
			if dropped:
				break
		if not dropped:
			break
	return out


## The distinct targets named in side -> {"bow", "stern"}, as target_id -> true.
static func battery_targets(sides: Dictionary) -> Dictionary:
	var targets := {}
	for side in sides:
		for key in ["bow", "stern"]:
			if str(sides[side][key]) != "":
				targets[str(sides[side][key])] = true
	return targets


## "" when `firer`'s marines may fire at `target` at `range_hexes` (7.G.1), else the reason. Pure:
## - the firer is in play and has marine boxes;
## - its marines are not plotted to a task that takes them away (any task but FB, BR, BD;
##   ShipState.marines_busy, which also covers BA and an engaged boarding action);
## - the target is another side's ship still in play (struck ships are not fired on, as for gunfire);
## - the target is adjacent (MARINE_RANGE), whatever the ships' orientation.
static func marine_error(firer: ShipState, target: ShipState, range_hexes: int) -> String:
	if firer == null or target == null:
		return "unknown ship"
	if firer.is_destroyed() or target.is_destroyed():
		return "a destroyed ship cannot fire or be fired on"
	if firer.is_captured():
		return "a prize does not fight (10.H.2)"
	if firer.is_out_of_play() or not target.is_targetable():
		return "a struck ship cannot fire or be fired on"
	if firer.side == target.side:
		return "cannot fire on a ship of the same side"
	if firer.marine_count <= 0:
		return "no marines left"
	if firer.marines_in_boarding():
		return "the marines are fighting a boarding action (7.G.1)"
	if firer.marines_busy():
		return "the marines are plotted to another task (7.G.1)"
	if range_hexes < 1 or range_hexes > MARINE_RANGE:
		return "marines fire only at an adjacent ship (7.G.1)"
	return ""


## "" when a set of marine orders ({ship_id, target_id} dictionaries) obeys 7.G.2 (one target per
## ship per g-t), else the problem. Geometry and eligibility are checked by marine_error.
static func marine_orders_error(orders: Array) -> String:
	var seen := {}
	for order in orders:
		if not order is Dictionary or str(order.get("ship_id", "")) == "" or str(order.get("target_id", "")) == "":
			return "malformed marine fire order"
		var ship_id := str(order["ship_id"])
		if seen.has(ship_id):
			return "the marines of %s fire at one ship per turn (7.G.2)" % ship_id
		seen[ship_id] = true
	return ""


## 7.F.2 (Freeboard Calculation): true when the sea has shut `side`'s lower-deck gunports. Pure.
## Sea below freeboard (or calm): open. Equal: the leeward broadside only; `leeward` is
## FireGeometry.leeward_side, -1 at WF=L or WF=R, where nothing closes. Above: both broadsides.
static func lower_deck_closed(freeboard: int, sea: int, side: int, leeward: int) -> bool:
	if sea <= 0 or sea < freeboard:
		return false
	if sea > freeboard:
		return true
	return leeward >= 0 and leeward == side


## The lower-deck gunfire modifier (the ship's LDGM, negative) on `side` in this sea and wind, or 0.
## The gunnery calculator and the ship card both read it, so they cannot disagree.
static func lower_deck_modifier(ship: ShipState, side: int, sea: int, wind_direction: int) -> int:
	if ship == null or ship.ship == null:
		return 0
	var leeward := FireGeometry.leeward_side(ship.facing, wind_direction)
	if not lower_deck_closed(ship.ship.freeboard, sea, side, leeward):
		return 0
	return ship.ship.lower_deck_modifier
