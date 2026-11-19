class_name FireOrdersModel
extends RefCounted
## FireOrdersModel - the fire declaration's order logic and per-ship selection state, used by the
## board's fire step (FireBoard). View state only: it reads the eligible shots
## (GunneryCalculator.eligible_shots, MarineFireResolver.eligible_marine_shots) and the numbers
## (GunneryCalculator.preview_orders) through pure queries and never touches game state; the caller
## sends orders() / marine_orders() with player_submit_fire_orders.
##
## Per ship and side the state is {"bow", "stern", "want_high", "want_dismantling", "reductions"}:
## the target of each battery ("" holds), the player's wishes (a forced high aim or a roundshot
## fallback never sticks: FireRules.make_order applies them), and the voluntary MGN reduction per row
## (7.C.14, keyed by row_key). A chase side keeps its target under "bow" ("stern" stays ""), so
## FireRules.limit_targets / battery_targets keep the ship within two targets. The firing rules
## themselves (full vs half, target cap, forced aim, ammunition range) live in FireRules.
##
## setup() chooses each ship's single best shot (the best broadside row, else the best chaser row;
## the other sides hold fire, since firing both costs the two-target modifier on each shot) and the
## best marine shot (7.G.2: one target at most). A ship with a marine shot but no gun shot is listed
## (ships_with_shots), with the guns' no-shot reason kept.

signal changed()

## Every side a ship may fire from, in display order: the two broadsides, then the bow and stern chasers.
const ALL_SIDES: Array[int] = [ShipState.PORT, ShipState.STARBOARD, GunneryTypes.CHASE_BOW,
	GunneryTypes.CHASE_STERN]

## Calculator refusal reasons (GunneryCalculator.preview) -> plain words.
const NO_SHOT_ARC := "out of both broadside arcs"
const NO_SHOT_RANGE := "out of range"
const NO_SHOT_LOS := "line of sight blocked"
const NO_SHOT_CREW := "no crew to serve the guns"
const NO_SHOT_STRUCK := "struck"
const NO_SHOT_SURRENDERING := "surrendering"
const NO_SHOT_SURRENDERED := "surrendered"
const NO_SHOT_DESTROYED := "destroyed"
const NO_SHOT_NO_ENEMY := "no enemy afloat"
## One side (side_reason) with every enemy outside its arc.
const NO_SHOT_SIDE_ARC := "no enemy in this arc"
## GunneryCalculator.preview's "Blocked by friendly ship <name>" (7.B.10), shown as it is.
const NO_SHOT_FRIENDLY_PREFIX := "Blocked by friendly ship"

## ship_id -> {"options": {side: {target_id: {battery: ShotPreview}}} (one-target eligible shots),
##             "sides": {side: side state}, "defaults": {side: {"bow", "stern"}},
##             "rows": {side: Array of {"target_id", "mgn", "battery", "range", "name"}} (display order)}
var _ships: Dictionary = {}
var _ship_order: Array[String] = []
## ship_id -> {"options": Array[Dictionary] (MarineFireResolver previews), "target": String ("" holds),
##             "default": String}
var _marines: Dictionary = {}
var _marine_order: Array[String] = []
## ship_id -> the guns' no-shot reason, for the ships setup() found no gun shot for.
var _no_shot: Dictionary = {}
var _no_shot_order: Array[String] = []
## Order-set key -> preview_orders() result, for this setup(). Game state does not change while fire
## is declared, so a set's previews never go stale; setup() empties it.
var _preview_cache: Dictionary = {}


# ============================================================================
# Pure order logic (unit tested)
# ============================================================================

## ship_id -> "Topaze — 32-gun Frigate": target rows name each ship with its type.
static func target_names(ships: Array) -> Dictionary:
	var names := {}
	for ship in ships:
		names[ship.ship_id] = PlanningText.name_and_type(ship)
	return names


## The default marine target among previews: the best chance of a hit, then the lower DRM total,
## then the target id; "" when no shot can hit.
static func default_marine_target(previews: Array) -> String:
	var best: Dictionary = {}
	for p: Dictionary in previews:
		if int(p.get("hit_max", 0)) <= 0:
			continue
		if best.is_empty() or int(p["hit_max"]) > int(best["hit_max"]) \
				or (int(p["hit_max"]) == int(best["hit_max"]) and int(p["modifier"]) < int(best["modifier"])) \
				or (int(p["hit_max"]) == int(best["hit_max"]) and int(p["modifier"]) == int(best["modifier"])
					and str(p["target_id"]) < str(best["target_id"])):
			best = p
	return "" if best.is_empty() else str(best["target_id"])


## The batteries a target can be fired at with from one side, from its eligible previews, in
## GunneryTypes.BATTERIES order: "full" only when both batteries bear, and each single battery
## that bears (each gets its own row, so a side can split or fire a half broadside); then "chase"
## (a chase side's only battery).
static func battery_options(previews: Array) -> Array[String]:
	var can := {}
	for p: GunneryTypes.ShotPreview in previews:
		if p.can_fire and p.order != null:
			can[p.order.battery] = true
	var options: Array[String] = []
	for battery in GunneryTypes.BATTERIES:
		if can.has(battery):
			options.append(battery)
	if can.has(GunneryTypes.BATTERY_CHASE):
		options.append(GunneryTypes.BATTERY_CHASE)
	return options


## eligible_shots() output grouped as side -> target_id -> battery -> ShotPreview.
static func options_by_target(shots: Array[GunneryTypes.ShotPreview]) -> Dictionary:
	var by_side := {}
	for shot in shots:
		var side := shot.order.side
		if not by_side.has(side):
			by_side[side] = {}
		if not by_side[side].has(shot.order.target_id):
			by_side[side][shot.order.target_id] = {}
		by_side[side][shot.order.target_id][shot.order.battery] = shot
	return by_side


## Key of a target row within one side ("" is the hold-fire row).
static func row_key(target_id: String, battery: String) -> String:
	return "" if target_id == "" else "%s|%s" % [target_id, battery]


## Key of one order in order_previews(): "<ship_id>|<side>|<row_key>", e.g. "firer|1|t0|bow".
static func order_key(ship_id: String, side: int, target_id: String, battery: String) -> String:
	return "%s|%d|%s" % [ship_id, side, row_key(target_id, battery)]


## Whether the row (target_id, battery) is what the side currently fires. A chaser's target is
## kept under "bow".
static func row_chosen(bow: String, stern: String, target_id: String, battery: String) -> bool:
	match battery:
		GunneryTypes.BATTERY_CHASE:
			return bow == target_id
		GunneryTypes.BATTERY_FULL:
			return bow == target_id and stern == target_id
		GunneryTypes.BATTERY_BOW:
			return bow == target_id and stern != target_id
		GunneryTypes.BATTERY_STERN:
			return stern == target_id and bow != target_id
	return false


## Row-pick state transition for one side (FireRules.side_shots turns it into shots). `state` has
## "bow" and "stern" (target per battery). target_id "" holds fire; picking the chosen row again
## holds what it fires; "full" aims both batteries at the target; a single battery aims only that
## battery, and a full broadside at that target becomes the half; "chase" toggles "bow" between the
## target and "" ("stern" stays "").
static func choose_battery(state: Dictionary, target_id: String, battery: String) -> Dictionary:
	var bow: String = str(state.get("bow", ""))
	var stern: String = str(state.get("stern", ""))
	if target_id == "":
		return {"bow": "", "stern": ""}
	var chosen := row_chosen(bow, stern, target_id, battery)
	match battery:
		GunneryTypes.BATTERY_CHASE:
			bow = "" if chosen else target_id
			stern = ""
		GunneryTypes.BATTERY_FULL:
			bow = "" if chosen else target_id
			stern = bow
		GunneryTypes.BATTERY_BOW:
			bow = "" if chosen else target_id
			if stern == target_id:
				stern = ""
		GunneryTypes.BATTERY_STERN:
			stern = "" if chosen else target_id
			if bow == target_id:
				bow = ""
	return {"bow": bow, "stern": stern}


## The side state with row (target_id, battery)'s voluntary MGN reduction (7.C.14) set to n,
## clamped at 0. A copy; "reductions" maps row_key to the reduction of that order, so a side split
## between two targets can reduce one shot only.
static func with_reduction(state: Dictionary, target_id: String, battery: String, n: int) -> Dictionary:
	var out := state.duplicate(true)
	var reductions: Dictionary = out.get("reductions", {})
	reductions[row_key(target_id, battery)] = maxi(n, 0)
	out["reductions"] = reductions
	return out


## The reduction set for row (target_id, battery) in a side state (0 when none).
static func reduction_of(state: Dictionary, target_id: String, battery: String) -> int:
	return int((state.get("reductions", {}) as Dictionary).get(row_key(target_id, battery), 0))


## A ship's FireOrders for its sides (side -> side state) through FireRules (bow+stern at one target
## = full broadside, forced aim, ammunition range). A chase side's shot (its target under "bow") is a
## GunneryTypes.BATTERY_CHASE order (round shot, FireRules.make_order). `ranges` is target_id -> range
## in hexes. Sides in ascending order.
static func orders_for_sides(ship_id: String, sides: Dictionary, ranges: Dictionary) -> Array[GunneryTypes.FireOrder]:
	var orders: Array[GunneryTypes.FireOrder] = []
	var keys := sides.keys()
	keys.sort()
	for side in keys:
		var state: Dictionary = sides[side]
		var chase := GunneryTypes.is_chase_side(int(side))
		for shot: Dictionary in FireRules.side_shots(state["bow"], "" if chase else state["stern"]):
			var battery: String = GunneryTypes.BATTERY_CHASE if chase else str(shot["battery"])
			orders.append(FireRules.make_order(ship_id, int(side), shot["target_id"], battery,
				bool(state.get("want_high", false)), bool(state.get("want_dismantling", false)),
				int(ranges.get(shot["target_id"], 0)),
				reduction_of(state, shot["target_id"], battery)))
	return orders


## Target rows ranked for the default choice: highest modified gunfire number first, then nearest,
## then name. Each entry is {"target_id", "mgn", "range", "name"}; returns a sorted copy.
static func rank_targets(entries: Array) -> Array:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return _better_row(x, y))
	return sorted


## Target rows in list order: nearest first, then name, then target id (the default choice is
## still the best shot, rank_targets). Each entry has "target_id", "range" and "name"; returns a
## sorted copy. Within a target the rows go Full, Bow, Stern (battery_options).
static func display_order(entries: Array) -> Array:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["range"]) != int(y["range"]):
			return int(x["range"]) < int(y["range"])
		if str(x["name"]) != str(y["name"]):
			return str(x["name"]) < str(y["name"])
		return str(x["target_id"]) < str(y["target_id"]))
	return sorted


## Which side starts with a target: the broadside whose best row is the best one-target shot
## (highest modified number, then nearest, then name; port before starboard on a full tie).
## `ranked_by_side` is side -> rank_targets() output. The other sides start on hold fire. A chase
## side only when no broadside has a row (then the best chaser row, by the same order). -1 when no
## side has a row.
static func default_side(ranked_by_side: Dictionary) -> int:
	var broadsides := {}
	var chasers := {}
	for side in ranked_by_side:
		if GunneryTypes.is_chase_side(int(side)):
			chasers[side] = ranked_by_side[side]
		else:
			broadsides[side] = ranked_by_side[side]
	var best_side := _best_side(broadsides)
	return best_side if best_side >= 0 else _best_side(chasers)


static func _best_side(ranked_by_side: Dictionary) -> int:
	var best_side := -1
	var best: Dictionary = {}
	var sides := ranked_by_side.keys()
	sides.sort()
	for side in sides:
		var rows: Array = ranked_by_side[side]
		if rows.is_empty():
			continue
		var top: Dictionary = rows[0]
		if best_side < 0 or _better_row(top, best):
			best_side = int(side)
			best = top
	return best_side


static func _better_row(x: Dictionary, y: Dictionary) -> bool:
	if int(x["mgn"]) != int(y["mgn"]):
		return int(x["mgn"]) > int(y["mgn"])
	if int(x["range"]) != int(y["range"]):
		return int(x["range"]) < int(y["range"])
	return str(x["name"]) < str(y["name"])


## The main reason a ship cannot fire at its nearest enemy, in plain words, from the calculator's
## refusal reasons for each broadside. A reason other than "not in the arc" wins (it means the
## target IS in that broadside's arc). Empty `reasons` means there is no enemy to shoot at.
static func no_shot_words(reasons: Array) -> String:
	if reasons.is_empty():
		return NO_SHOT_NO_ENEMY
	var chosen := ""
	for r in reasons:
		var text := str(r)
		# 7.B.10: shown as given; the friend's name must not trip the keyword checks below.
		if text.begins_with(NO_SHOT_FRIENDLY_PREFIX):
			return text
		if not text.contains("arc"):
			chosen = text
			break
	if chosen == "":
		return NO_SHOT_ARC
	if chosen.contains("destroyed"):
		return NO_SHOT_DESTROYED
	if chosen.contains("surrendering"):
		return NO_SHOT_SURRENDERING
	if chosen.contains("struck"):
		return NO_SHOT_STRUCK
	if chosen.contains("line of sight"):
		return NO_SHOT_LOS
	if chosen.contains("sailor") or chosen.contains("crew"):
		return NO_SHOT_CREW
	if chosen.contains("range"):
		return NO_SHOT_RANGE
	return chosen


## The nearest enemy afloat (ties by ship id), null when none. Distance on `grid` from the closest
## hex of one footprint to the closest hex of the other.
static func nearest_enemy(ship: ShipState, all_ships: Array, grid: HexGrid) -> ShipState:
	var nearest: ShipState = null
	var best := 1 << 30
	if grid == null:
		return null
	var geometry := FireGeometry.new(grid)
	for other: ShipState in all_ships:
		if other.side == ship.side or other.is_out_of_play():
			continue
		var d := geometry.range_between(ship.occupied_hexes(), other.occupied_hexes())
		if d < best or (d == best and other.ship_id < nearest.ship_id):
			best = d
			nearest = other
	return nearest


## Why `ship` has no shot, in plain words: its calculator previews (a pure query) of both
## broadsides and chasers against its nearest enemy, mapped by no_shot_words(). `calculator` is a
## GunneryCalculator (anything with preview(order)).
static func ship_no_shot_reason(ship: ShipState, all_ships: Array, calculator, grid: HexGrid) -> String:
	if ship.is_destroyed():
		return NO_SHOT_DESTROYED
	if ship.is_struck() and ship.surrendered:
		return NO_SHOT_SURRENDERED
	if ship.is_struck():
		return NO_SHOT_STRUCK
	if ship.surrender_ordered:
		return NO_SHOT_SURRENDERING
	var reasons: Array = []
	var target := nearest_enemy(ship, all_ships, grid)
	if target and calculator:
		for side in [ShipState.PORT, ShipState.STARBOARD]:
			reasons.append(_broadside_reason(calculator, ship.ship_id, side, target.ship_id))
		# A chaser may be the only thing that bears (or the only refusal worth naming): an empty
		# reason means it could fire, so it says nothing.
		for side in GunneryTypes.CHASE_SIDES:
			var chase_reason := _no_shot_preview(calculator, ship.ship_id, side, target.ship_id,
				GunneryTypes.BATTERY_CHASE)
			if chase_reason != "":
				reasons.append(chase_reason)
	return no_shot_words(reasons)


## A broadside's refusal reason against one target: the full broadside's preview, or, when only
## one battery bears ("needs both"), that battery's own reason (crew, range...).
static func _broadside_reason(calculator, ship_id: String, side: int, target_id: String) -> String:
	var reason := _no_shot_preview(calculator, ship_id, side, target_id, GunneryTypes.BATTERY_FULL)
	if reason.contains("needs both"):
		for battery in [GunneryTypes.BATTERY_BOW, GunneryTypes.BATTERY_STERN]:
			var single := _no_shot_preview(calculator, ship_id, side, target_id, battery)
			if not single.contains("arc") and not single.contains("line of sight"):
				return single
	return reason


static func _no_shot_preview(calculator, ship_id: String, side: int, target_id: String, battery: String) -> String:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = side
	order.target_id = target_id
	order.battery = battery
	return str(calculator.preview(order).reason)


## The preview of order (side, target_id, battery) among `previews`, null when absent.
static func find_preview(previews: Array[GunneryTypes.ShotPreview], side: int, target_id: String,
		battery: String) -> GunneryTypes.ShotPreview:
	for p in previews:
		if p.order.side == side and p.order.target_id == target_id and p.order.battery == battery:
			return p
	return null


# ============================================================================
# Setup and queries
# ============================================================================

## Loads the eligible gun and marine shots of the given ships (pure queries) and chooses each ship's
## best shot. Ships without a gun shot keep their no-shot reason.
func setup(ship_ids: Array) -> void:
	_ships.clear()
	_ship_order.clear()
	_marines.clear()
	_marine_order.clear()
	_no_shot.clear()
	_no_shot_order.clear()
	_preview_cache.clear()
	var calculator: GunneryCalculator = GameState.gunnery_calculator
	var marines = GameState.get("marine_fire_resolver")
	var no_shot: Array[ShipState] = []
	var marine_only: Dictionary = {}  # ship_id -> marine shots
	for ship_id in ship_ids:
		var ship_state: ShipState = GameState.get_ship(ship_id)
		if ship_state == null:
			continue
		var options := options_by_target(calculator.eligible_shots(ship_id))
		var marine_shots: Array = marines.eligible_marine_shots(ship_id) if marines != null else []
		if options.is_empty():
			no_shot.append(ship_state)
			if not marine_shots.is_empty():
				marine_only[ship_state.ship_id] = marine_shots
			continue
		_add_ship(ship_state, options)
		if not marine_shots.is_empty():
			_add_marines(ship_state.ship_id, marine_shots)
	var grid: HexGrid = GameState.fire_geometry.hex_grid if GameState.fire_geometry else null
	for ship_state in no_shot:
		_no_shot[ship_state.ship_id] = ship_no_shot_reason(ship_state, GameState.get_all_ships(),
			calculator, grid)
		_no_shot_order.append(ship_state.ship_id)
	for ship_id: String in marine_only:
		_add_marines(ship_id, marine_only[ship_id])
	changed.emit()


## Why one side of a ship has no target, in plain words ("" when it bears on one). A ship with no gun
## shot at all gives her no_shot_reason (no crew, struck, surrendering...). Otherwise the side is
## previewed (GunneryCalculator.preview, a pure query) against every enemy afloat, nearest first,
## and the refusals are worded by no_shot_words; "not in the arc" for all of them reads NO_SHOT_SIDE_ARC.
func side_reason(ship_id: String, side: int) -> String:
	if sides(ship_id).has(side):
		return ""
	if not _ships.has(ship_id):
		var whole := no_shot_reason(ship_id)
		if whole != "":
			return whole
	var ship: ShipState = GameState.get_ship(ship_id)
	var calculator: GunneryCalculator = GameState.gunnery_calculator
	if ship == null or calculator == null:
		return NO_SHOT_NO_ENEMY
	var reasons: Array = []
	for enemy in _enemies_by_range(ship):
		if GunneryTypes.is_chase_side(side):
			reasons.append(_no_shot_preview(calculator, ship_id, side, enemy.ship_id, GunneryTypes.BATTERY_CHASE))
			continue
		reasons.append(_broadside_reason(calculator, ship_id, side, enemy.ship_id))
	var words := no_shot_words(reasons)
	return NO_SHOT_SIDE_ARC if words == NO_SHOT_ARC else words


## Why a ship's marines have no shot: MarineFireResolver.preview's reason against her nearest enemy
## (the server's words), "" when they have one; NO_SHOT_NO_ENEMY with no enemy afloat.
func marine_reason(ship_id: String) -> String:
	if _marines.has(ship_id):
		return ""
	var ship: ShipState = GameState.get_ship(ship_id)
	var marines = GameState.get("marine_fire_resolver")
	var grid: HexGrid = GameState.fire_geometry.hex_grid if GameState.fire_geometry else null
	var target := nearest_enemy(ship, GameState.get_all_ships(), grid) if ship != null else null
	if target == null or marines == null:
		return NO_SHOT_NO_ENEMY
	var reason := str(marines.preview(ship_id, target.ship_id).get("reason", ""))
	return reason if reason != "" else NO_SHOT_NO_ENEMY


## A copy of a ship's choices (every side and the marines' target), for restore_ship.
func ship_snapshot(ship_id: String) -> Dictionary:
	var out := {}
	if _ships.has(ship_id):
		out["sides"] = (_ships[ship_id]["sides"] as Dictionary).duplicate(true)
	if _marines.has(ship_id):
		out["marines"] = str(_marines[ship_id]["target"])
	return out


## Puts back a ship's choices from ship_snapshot (an option box cancelled); emits changed.
func restore_ship(ship_id: String, snapshot: Dictionary) -> void:
	if _ships.has(ship_id) and snapshot.has("sides"):
		_ships[ship_id]["sides"] = (snapshot["sides"] as Dictionary).duplicate(true)
	if _marines.has(ship_id) and snapshot.has("marines"):
		_marines[ship_id]["target"] = str(snapshot["marines"])
	changed.emit()


## The listed ships: those with a gun shot (setup order), then those with only a marine shot.
func ships_with_shots() -> Array[String]:
	var ids := _ship_order.duplicate()
	for ship_id in _marine_order:
		if not _ships.has(ship_id):
			ids.append(ship_id)
	return ids


## The ships with a gun shot, in setup order.
func gun_ships() -> Array[String]:
	return _ship_order.duplicate()


## The ships whose marines may fire: gun ships first (setup order), then marine-only ships.
func marine_ships() -> Array[String]:
	return _marine_order.duplicate()


## The ships with no gun shot (marine-only ships among them), in setup order.
func no_shot_ships() -> Array[String]:
	return _no_shot_order.duplicate()


func has_gun_shots(ship_id: String) -> bool:
	return _ships.has(ship_id)


func has_marines(ship_id: String) -> bool:
	return _marines.has(ship_id)


## Why a ship's guns have no shot, in plain words ("" for a ship with a gun shot or not set up).
func no_shot_reason(ship_id: String) -> String:
	return str(_no_shot.get(ship_id, ""))


## The sides of a ship that have a target, in ALL_SIDES order.
func sides(ship_id: String) -> Array[int]:
	var out: Array[int] = []
	if _ships.has(ship_id):
		for side in ALL_SIDES:
			if _ships[ship_id]["sides"].has(side):
				out.append(side)
	return out


## side -> Array of the target ids that side bears on (list order: nearest first).
func sides_bearing(ship_id: String) -> Dictionary:
	var out := {}
	for side in sides(ship_id):
		var ids: Array = []
		for row: Dictionary in _ships[ship_id]["rows"][side]:
			ids.append(str(row["target_id"]))
		out[side] = ids
	return out


## The targets one side bears on, nearest first: {target_id, name, range, batteries, preview}, where
## `batteries` is battery_options() and `preview` the one-target preview of the first of them (the
## full broadside when both batteries bear).
func targets(ship_id: String, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _ships.has(ship_id) or not _ships[ship_id]["rows"].has(side):
		return out
	for row: Dictionary in _ships[ship_id]["rows"][side]:
		var target_id := str(row["target_id"])
		var batteries := battery_options_for(ship_id, side, target_id)
		out.append({"target_id": target_id, "name": row["name"], "range": int(row["range"]),
			"batteries": batteries,
			"preview": _ships[ship_id]["options"][side][target_id][batteries[0]]})
	return out


## battery_options() for one side and target of a ship ([] when it does not bear).
func battery_options_for(ship_id: String, side: int, target_id: String) -> Array[String]:
	if not _ships.has(ship_id):
		return [] as Array[String]
	var by_target: Dictionary = _ships[ship_id]["options"].get(side, {})
	return battery_options((by_target.get(target_id, {}) as Dictionary).values())


## A copy of one side's state ({"bow", "stern", "want_high", "want_dismantling", "reductions"});
## {} when the side has no target.
func side_state(ship_id: String, side: int) -> Dictionary:
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return {}
	return (_ships[ship_id]["sides"][side] as Dictionary).duplicate(true)


## The voluntary reduction of row (target_id, battery) on a side (0 when none).
func reduction(ship_id: String, side: int, target_id: String, battery: String) -> int:
	return reduction_of(side_state(ship_id, side), target_id, battery)


## Target ship ids currently chosen for a ship, each once (holding batteries omitted).
func target_ids(ship_id: String) -> Array[String]:
	var ids: Array[String] = []
	if not _ships.has(ship_id):
		return ids
	for target_id in FireRules.battery_targets(_ships[ship_id]["sides"]):
		ids.append(str(target_id))
	return ids


## The single batteries ("bow", "stern") that fire from `side` of a ship; [] while it holds fire.
## A chaser that fires reports "bow" (its target is kept there).
func batteries(ship_id: String, side: int) -> Array[String]:
	var out: Array[String] = []
	var state := side_state(ship_id, side)
	if state.is_empty():
		return out
	if state["bow"] != "":
		out.append(GunneryTypes.BATTERY_BOW)
	if state["stern"] != "":
		out.append(GunneryTypes.BATTERY_STERN)
	return out


## The marine shots of a ship: {target_id, preview} per adjacent enemy (preview is the
## MarineFireResolver.preview dictionary).
func marine_targets(ship_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _marines.has(ship_id):
		for p: Dictionary in _marines[ship_id]["options"]:
			out.append({"target_id": str(p["target_id"]), "preview": p})
	return out


## The marine target chosen for a ship ("" while its marines hold fire or it has no marine shot).
func marine_target(ship_id: String) -> String:
	return str(_marines[ship_id]["target"]) if _marines.has(ship_id) else ""


## Previews of a ship's current order set as it will resolve (GunneryCalculator.preview_orders).
func previews(ship_id: String) -> Array[GunneryTypes.ShotPreview]:
	if not _ships.has(ship_id):
		return [] as Array[GunneryTypes.ShotPreview]
	return _preview_sides(ship_id, _ships[ship_id]["sides"])


## Previews of the order set a ship would have after choosing row (target_id, battery) on `side`.
func previews_if_chosen(ship_id: String, side: int, target_id: String, battery: String) -> Array[GunneryTypes.ShotPreview]:
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return [] as Array[GunneryTypes.ShotPreview]
	return _preview_sides(ship_id, _apply_choice(ship_id, side, target_id, battery))


## Every gun order, ships in setup order (what the retired fire panel's get_all_orders gave, as FireOrders).
func orders() -> Array[GunneryTypes.FireOrder]:
	var out: Array[GunneryTypes.FireOrder] = []
	for ship_id in _ship_order:
		out.append_array(ship_orders(ship_id))
	return out


## orders() as the dictionaries player_submit_fire_orders takes.
func order_dicts() -> Array:
	return orders().map(func(o: GunneryTypes.FireOrder) -> Dictionary: return o.to_dict())


## One ship's gun orders.
func ship_orders(ship_id: String) -> Array[GunneryTypes.FireOrder]:
	if not _ships.has(ship_id):
		return [] as Array[GunneryTypes.FireOrder]
	return _orders(ship_id, _ships[ship_id]["sides"])


## Marine fire orders as {ship_id, target_id} dictionaries, one per ship whose marines fire.
func marine_orders() -> Array:
	var out: Array = []
	for ship_id in _marine_order:
		var target := str(_marines[ship_id]["target"])
		if target != "":
			out.append({"ship_id": ship_id, "target_id": target})
	return out


## order_key(ship_id, side, target_id, battery) -> ShotPreview for every order in orders(), as
## GunneryCalculator.preview_orders gives them (two targets, half broadside, initial broadside once
## per broadside): the numbers the resolver rolls.
func order_previews() -> Dictionary:
	var out := {}
	for ship_id in _ship_order:
		for p in previews(ship_id):
			out[order_key(p.order.ship_id, p.order.side, p.order.target_id, p.order.battery)] = p
	return out


## True once the player picked a target (or hold fire) other than the one chosen for them.
func targets_changed() -> bool:
	for ship_id in _ship_order:
		var entry: Dictionary = _ships[ship_id]
		for side in entry["sides"]:
			var default: Dictionary = entry["defaults"].get(side, {"bow": "", "stern": ""})
			for key in ["bow", "stern"]:
				if entry["sides"][side][key] != default[key]:
					return true
	for ship_id in _marine_order:
		if str(_marines[ship_id]["target"]) != str(_marines[ship_id]["default"]):
			return true
	return false


## True while some ship names two different targets (the two-target modifier applies).
func any_ship_fires_both() -> bool:
	for ship_id in _ship_order:
		if target_ids(ship_id).size() > 1:
			return true
	return false


## True while a ship naming two targets fires a chaser at one of them.
func any_two_target_chaser() -> bool:
	for ship_id in _ship_order:
		if target_ids(ship_id).size() < 2:
			continue
		for order in ship_orders(ship_id):
			if order.battery == GunneryTypes.BATTERY_CHASE:
				return true
	return false


# ============================================================================
# Choices (each returns true and emits changed when it applied)
# ============================================================================

## Pick a side's target row (target_id, battery); target_id "" holds fire, battery "" means the
## target's preferred battery (a full broadside when both bear). Picking the chosen row again holds
## what it fires. Then the target cap (FireRules.limit_targets). False for an unknown ship or side,
## or a battery that does not bear.
func choose(ship_id: String, side: int, target_id: String, battery: String = "") -> bool:
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return false
	if target_id != "":
		var options := battery_options_for(ship_id, side, target_id)
		if battery == "" and not options.is_empty():
			battery = options[0]
		if not options.has(battery):
			return false
	_ships[ship_id]["sides"] = _apply_choice(ship_id, side, target_id, battery)
	changed.emit()
	return true


## Hold fire on one side.
func clear_side(ship_id: String, side: int) -> bool:
	return choose(ship_id, side, "", "")


## Ask for high fire on a side (FireRules may force it anyway).
func set_high(ship_id: String, side: int, on: bool) -> bool:
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return false
	_ships[ship_id]["sides"][side]["want_high"] = on
	changed.emit()
	return true


## Ask for dismantling shot on a side (round shot beyond its range, and always for a chaser).
func set_dismantling(ship_id: String, side: int, on: bool) -> bool:
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return false
	_ships[ship_id]["sides"][side]["want_dismantling"] = on
	changed.emit()
	return true


## Set row (target_id, battery)'s voluntary MGN reduction (7.C.14) to n, clamped at 0.
func set_reduction(ship_id: String, side: int, target_id: String, battery: String, n: int) -> bool:
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return false
	_ships[ship_id]["sides"][side] = with_reduction(_ships[ship_id]["sides"][side], target_id, battery, n)
	changed.emit()
	return true


## Pick the marines' target (7.G.2: one ship); "" holds musket fire. False for a ship with no marine
## shot or a target its marines cannot fire on.
func select_marine_target(ship_id: String, target_id: String) -> bool:
	if not _marines.has(ship_id):
		return false
	if target_id != "" and not _marine_target_ids(ship_id).has(target_id):
		return false
	_marines[ship_id]["target"] = target_id
	changed.emit()
	return true


## Every side and the marines of a ship hold fire (reductions and wishes are kept).
func hold_fire(ship_id: String) -> bool:
	if not _ships.has(ship_id) and not _marines.has(ship_id):
		return false
	if _ships.has(ship_id):
		for side in _ships[ship_id]["sides"]:
			_ships[ship_id]["sides"][side]["bow"] = ""
			_ships[ship_id]["sides"][side]["stern"] = ""
	if _marines.has(ship_id):
		_marines[ship_id]["target"] = ""
	changed.emit()
	return true


# ============================================================================
# Internals
# ============================================================================

func _add_ship(ship_state: ShipState, options: Dictionary) -> void:
	var ship_id := ship_state.ship_id
	var entry := {"options": options, "sides": {}, "defaults": {}, "rows": {}}
	_ships[ship_id] = entry
	_ship_order.append(ship_id)
	var names := target_names(GameState.get_all_ships())
	var ranked_by_side := {}
	for side in ALL_SIDES:
		if not options.has(side):
			continue
		# Rank by each target's preferred battery (full broadside when both bear), one target.
		var ranked_entries: Array = []
		for target_id: String in options[side]:
			var battery: String = battery_options_for(ship_id, side, target_id)[0]  # full first
			var shot: GunneryTypes.ShotPreview = options[side][target_id][battery]
			ranked_entries.append({"target_id": target_id, "mgn": shot.mgn, "battery": battery,
				"range": shot.range_hexes, "name": str(names.get(target_id, target_id))})
		ranked_by_side[side] = rank_targets(ranked_entries)
	var firing_side := default_side(ranked_by_side)
	for side in ALL_SIDES:
		if not ranked_by_side.has(side):
			continue
		var ranked: Array = ranked_by_side[side]
		var start := {"bow": "", "stern": ""}
		if side == firing_side:
			start = choose_battery(start, str(ranked[0]["target_id"]), str(ranked[0]["battery"]))
		entry["defaults"][side] = start.duplicate()
		entry["sides"][side] = {"bow": start["bow"], "stern": start["stern"],
			"want_high": false, "want_dismantling": false, "reductions": {}}
		entry["rows"][side] = display_order(ranked)


func _add_marines(ship_id: String, marine_shots: Array) -> void:
	var default := default_marine_target(marine_shots)
	_marines[ship_id] = {"options": marine_shots, "target": default, "default": default}
	_marine_order.append(ship_id)


## The enemies afloat, nearest first (footprint to footprint), ties by ship id.
func _enemies_by_range(ship: ShipState) -> Array[ShipState]:
	var out: Array[ShipState] = []
	if GameState.fire_geometry == null:
		return out
	var ranges := {}
	for other: ShipState in GameState.get_all_ships():
		if other.side == ship.side or other.is_out_of_play():
			continue
		ranges[other.ship_id] = GameState.fire_geometry.range_between(ship.occupied_hexes(), other.occupied_hexes())
		out.append(other)
	out.sort_custom(func(x: ShipState, y: ShipState) -> bool:
		if int(ranges[x.ship_id]) != int(ranges[y.ship_id]):
			return int(ranges[x.ship_id]) < int(ranges[y.ship_id])
		return x.ship_id < y.ship_id)
	return out


func _marine_target_ids(ship_id: String) -> Array[String]:
	var ids: Array[String] = []
	for p: Dictionary in _marines[ship_id]["options"]:
		ids.append(str(p["target_id"]))
	return ids


## The ship's sides after picking row (target_id, battery) on `side`: choose_battery, then the
## target cap (FireRules.limit_targets). A copy.
func _apply_choice(ship_id: String, side: int, target_id: String, battery: String) -> Dictionary:
	var sides_now: Dictionary = _ships[ship_id]["sides"].duplicate(true)
	var chosen := choose_battery(sides_now[side], target_id, battery)
	sides_now[side]["bow"] = chosen["bow"]
	sides_now[side]["stern"] = chosen["stern"]
	return FireRules.limit_targets(sides_now, side)


## The ship's FireOrders for `sides_now` (orders_for_sides with each target's range).
func _orders(ship_id: String, sides_now: Dictionary) -> Array[GunneryTypes.FireOrder]:
	var ranges := {}
	for side in _ships[ship_id]["options"]:
		for target_id in _ships[ship_id]["options"][side]:
			for p: GunneryTypes.ShotPreview in _ships[ship_id]["options"][side][target_id].values():
				ranges[target_id] = p.range_hexes
	return orders_for_sides(ship_id, sides_now, ranges)


## Previews of a ship's whole order set as they will resolve (GunneryCalculator.preview_orders),
## computed once per order set (_preview_cache).
func _preview_sides(ship_id: String, sides_now: Dictionary) -> Array[GunneryTypes.ShotPreview]:
	var set_orders := _orders(ship_id, sides_now)
	var key := JSON.stringify(set_orders.map(func(o: GunneryTypes.FireOrder) -> Dictionary: return o.to_dict()))
	if not _preview_cache.has(key):
		_preview_cache[key] = GameState.gunnery_calculator.preview_orders(set_orders)
	return _preview_cache[key]
