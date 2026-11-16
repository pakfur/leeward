class_name GrapplingController
extends RefCounted
## GrapplingController - Grappling and ungrappling (Close Action 1997, 8.C; SoP V.C-D).
##
## Both run in STATUS_ADJUSTMENT, after drift and before unfouling: first every grapple attempt
## (resolve_grapples), then every ungrapple attempt (resolve_ungrapples). Neither is plotted (4.A.1):
## orders are [ship_id, other_id] pairs, given by the player in the maintenance prompt
## (TurnPhaseController.player_submit_maintenance_orders) or by StubAI.
##
## Grappling (8.C.1-3, Grappling table p.109): a ship may try once per g-t to grapple each adjacent
## ship it is not grappled to, when both used <= 2 MPs this g-t (turns count, 8.C.1 example 2). A
## burning or struck ship, or one at CQ F or G, cannot grapple (it can be grappled). d10 + DRMs <= 2
## succeeds. DRMs: ± SK, fouled to the target -1 (the chart's DRM, which the rule text denies; the
## chart wins), towing -1 (no towing in Leeward), marines not available +1, wind speed 4 +1, the
## target did not move (0 MPs this g-t; drift is not movement) -1.
##
## Ungrappling (8.C.4-6, Unfouling table): either ship of a grappled pair may roll d10 on the
## Unfouling table, success <= 2 / 3 / 4 by that ship's attempt against that partner. DRMs (All
## Uses): ± SK, marines not available +1 (8.C.5: also when they fight in a boarding action);
## (Ungrappling Only): -1 per CQ level the roller is better than an enemy partner (a struck partner
## counts as CQ G, 8.C.6, 9.C.4), friendly ships -2, wind speed 4 -1. Ships locked in a boarding
## action may not ungrapple from each other (8.C.5, BoardingController.locked_in_boarding).
##
## A grapple made while either ship is at WF=L puts that ship in irons (5.D.5): its speed is set to
## 0, which is how Leeward knows a ship is in irons.
##
## Dice order (the contract for ScriptedDice):
##   Grappling: rollers by ship_id; for each, its ordered targets by ship_id; one d10 per attempt.
##   A pair already grappled (earlier in the sub-phase, or before) is skipped without a roll.
##   Ungrappling: pairs by the lower ship_id, then the higher; the lower id rolls first if it
##   ordered an attempt, the partner only if that failed (or the lower id did not try).
## All mutations go through ShipStateController.

## Crew quality of a struck ship for these rolls (8.C.6, 9.C.4).
const STRUCK_QUALITY := "G"
## Crews that may not grapple (8.C.3).
const NO_GRAPPLE_QUALITIES := ["F", "G"]
## Most MPs either ship may have used this g-t (8.C.1).
const MAX_MPS := 2
const QUALITY_ORDER := "ABCDEFG"

var is_server: bool = true
var game_state: Node = null
var _hex_grid := HexGrid.new()


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


# --- queries (pure) ---

## Why `ship_id` may not try to grapple `target_id` now (8.C.1-3), or "".
func grapple_error(ship_id: String, target_id: String) -> String:
	var ship: ShipState = game_state.get_ship(ship_id)
	var target: ShipState = game_state.get_ship(target_id)
	if ship == null or target == null:
		return "no such ship"
	if ship_id == target_id:
		return "a ship cannot grapple itself"
	if ship.is_out_of_play():
		return "%s has struck and cannot grapple (8.C.3)" % ship.ship_name
	if ship.is_burning():
		return "%s is on fire and cannot grapple (8.C.3)" % ship.ship_name
	if NO_GRAPPLE_QUALITIES.has(ship.crew_quality):
		return "a crew at CQ %s cannot grapple (8.C.3)" % ship.crew_quality
	if target.is_destroyed():
		return "%s has blown up" % target.ship_name
	if ship.is_grappled_to(target_id):
		return "already grappled to %s" % target.ship_name
	if not adjacent(ship, target):
		return "%s is not alongside" % target.ship_name
	if ship.mp_used_this_turn > MAX_MPS:
		return "%s used %d MPs this turn (at most %d, 8.C.1)" % [ship.ship_name, ship.mp_used_this_turn, MAX_MPS]
	if target.mp_used_this_turn > MAX_MPS:
		return "%s used %d MPs this turn (at most %d, 8.C.1)" % [target.ship_name, target.mp_used_this_turn, MAX_MPS]
	return ""


## Ships `ship_id` may try to grapple now, by ship_id.
func grapple_options(ship_id: String) -> Array[String]:
	var out: Array[String] = []
	for other_id in _sorted_ids():
		if other_id != ship_id and grapple_error(ship_id, other_id) == "":
			out.append(other_id)
	return out


## The roll `ship_id` needs to grapple `target_id`: {"needed" (highest d10 that succeeds, may be
## below 0), "modifier" (DRM total), "modifiers" ([{name, value}], non-zero only), "percent"}.
func grapple_chance(ship_id: String, target_id: String) -> Dictionary:
	var ship: ShipState = game_state.get_ship(ship_id)
	var target: ShipState = game_state.get_ship(target_id)
	var tables: CombatTables = DataManager.combat_tables
	var mods: Array[Dictionary] = []
	_add(mods, "skill", tables.skill_modifier(ship.crew_quality))
	if ship.fouled_with == target_id:
		_add(mods, "fouled", tables.grapple_drm("fouled"))
	if marines_unavailable(ship):
		_add(mods, "marines_unavailable", tables.grapple_drm("marines_unavailable"))
	if _wind_speed() == 4:
		_add(mods, "ws4", tables.grapple_drm("ws4"))
	if target.mp_used_this_turn == 0:
		_add(mods, "target_did_not_move", tables.grapple_drm("target_did_not_move"))
	return _chance(mods, tables.grapple_success_max())


## Why `ship_id` may not try to ungrapple from `partner_id` now (8.C.4-5), or "".
func ungrapple_error(ship_id: String, partner_id: String) -> String:
	var ship: ShipState = game_state.get_ship(ship_id)
	var partner: ShipState = game_state.get_ship(partner_id)
	if ship == null or partner == null:
		return "no such ship"
	if not ship.is_grappled_to(partner_id):
		return "not grappled to %s" % partner.ship_name
	if ship.is_out_of_play():
		return "%s has struck and cannot cut the grapples" % ship.ship_name
	if locked_in_boarding(ship_id, partner_id):
		return "locked in a boarding action with %s (8.C.5)" % partner.ship_name
	return ""


## Partners `ship_id` may try to ungrapple from now, by ship_id.
func ungrapple_options(ship_id: String) -> Array[String]:
	var out: Array[String] = []
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return out
	for partner_id in ship.grappled_with:
		if ungrapple_error(ship_id, partner_id) == "":
			out.append(partner_id)
	out.sort()
	return out


## The roll `ship_id` needs to ungrapple from `partner_id` on its next attempt; as grapple_chance
## plus "attempt".
func ungrapple_chance(ship_id: String, partner_id: String) -> Dictionary:
	var ship: ShipState = game_state.get_ship(ship_id)
	var partner: ShipState = game_state.get_ship(partner_id)
	var tables: CombatTables = DataManager.combat_tables
	var mods: Array[Dictionary] = []
	_add(mods, "skill", tables.skill_modifier(quality_of(ship)))
	if marines_unavailable(ship):
		_add(mods, "marines_unavailable", tables.marines_unavailable_modifier())
	if ship.player_id == partner.player_id:
		_add(mods, "friendly", tables.ungrapple_drm("friendly"))
	else:
		var better: int = QUALITY_ORDER.find(quality_of(partner)) - QUALITY_ORDER.find(quality_of(ship))
		if better > 0:
			_add(mods, "better_crew", better * tables.ungrapple_drm("per_cq_better"))
	if _wind_speed() == 4:
		_add(mods, "ws4", tables.ungrapple_drm("ws4"))
	var attempt: int = int(ship.ungrapple_attempts.get(partner_id, 0)) + 1
	var result := _chance(mods, tables.unfouling_success_max(attempt))
	result["attempt"] = attempt
	return result


## The Grappling / Unfouling "Marines not avail." DRM: the marines are plotted to a task that takes
## them away (ShipState.marines_busy, as for unfouling), or fight in a boarding action (8.C.5).
func marines_unavailable(ship: ShipState) -> bool:
	return ship.marines_busy() or marines_in_boarding(ship)


## The ship's marines fight in a boarding action (8.C.5): away (BA) or engaged.
func marines_in_boarding(ship: ShipState) -> bool:
	return ship != null and ship.marines_in_boarding()


## The two ships fight a boarding action with each other, so neither may ungrapple or unfoul from
## the other (8.C.5, 8.D.4, 10.D.8; BoardingController.locked_in_boarding).
func locked_in_boarding(ship_a: String, ship_b: String) -> bool:
	var boarding = game_state.get("boarding_controller")
	return boarding != null and boarding.locked_in_boarding(ship_a, ship_b)


## Crew quality for these rolls: a struck ship is CQ G (8.C.6, 9.C.4).
static func quality_of(ship: ShipState) -> String:
	return STRUCK_QUALITY if ship.is_struck() else ship.crew_quality


## Any hex of one ship is next to any hex of the other (8.C.1: orientation does not matter).
func adjacent(a: ShipState, b: ShipState) -> bool:
	for ha in a.occupied_hexes():
		for hb in b.occupied_hexes():
			if _hex_grid.hex_distance(ha.x, ha.y, hb.x, hb.y) == 1:
				return true
	return false


## Normalized, de-duplicated [ship_id, other_id] pairs from untrusted input, or null when malformed.
static func parse_pairs(raw: Variant) -> Variant:
	if not raw is Array:
		return null
	var out: Array = []
	for entry in raw:
		if not entry is Array or (entry as Array).size() != 2:
			return null
		var pair := [str(entry[0]), str(entry[1])]
		if not out.has(pair):
			out.append(pair)
	return out


# --- resolution (server) ---

## The Grappling sub-phase (SoP V.C). `orders`: [ship_id, target_id] pairs; an order no longer legal
## is dropped with a trace line. Logs GRAPPLE per roll.
func resolve_grapples(orders: Array, phase: int) -> void:
	if not is_server:
		push_error("GrapplingController: Cannot resolve grappling on client")
		return
	var pairs: Array = _sorted_pairs(orders)
	for pair in pairs:
		var ship_id: String = pair[0]
		var target_id: String = pair[1]
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship != null and ship.is_grappled_to(target_id):
			continue  # one grapple per pair (8.C.2): the other ship's attempt already made it
		var why := grapple_error(ship_id, target_id)
		if why != "":
			Trace.trace_log("Grappling", "order dropped", {"ship": ship_id, "target": target_id, "reason": why})
			continue
		var chance := grapple_chance(ship_id, target_id)
		var roll: int = game_state.dice.d10()
		var total: int = roll + int(chance["modifier"])
		var success: bool = total <= DataManager.combat_tables.grapple_success_max()
		var data := {"roll": roll, "modifier": chance["modifier"], "modifiers": chance["modifiers"],
			"total": total, "needed": DataManager.combat_tables.grapple_success_max(), "success": success}
		if success:
			game_state.ship_controller.add_grapple(ship_id, target_id)
			var irons: Array[String] = _irons_on_grapple([ship_id, target_id])
			if not irons.is_empty():
				data["in_irons"] = irons
		game_state.turn_log.add(PhaseEvents.Type.GRAPPLE, phase, ship_id, data, target_id)
		Trace.trace_log("Grappling", "%s -> %s: d10 %d %+d = %d, %s" % [
			ship_id, target_id, roll, int(chance["modifier"]), total, "grappled" if success else "missed"])


## The Ungrappling sub-phase (SoP V.D). `orders`: [ship_id, partner_id] pairs. Logs UNGRAPPLE per
## roll.
func resolve_ungrapples(orders: Array, phase: int) -> void:
	if not is_server:
		push_error("GrapplingController: Cannot resolve ungrappling on client")
		return
	var wants := {}
	for pair in orders:
		wants["%s|%s" % [pair[0], pair[1]]] = true
	var done := {}
	for ship_id in _sorted_ids():
		var ship: ShipState = game_state.get_ship(ship_id)
		for partner_id in ship.grappled_with.duplicate():
			var key := "%s|%s" % [mini_id(ship_id, partner_id), maxi_id(ship_id, partner_id)]
			if done.has(key):
				continue
			done[key] = true
			var low := mini_id(ship_id, partner_id)
			var high := maxi_id(ship_id, partner_id)
			var freed := false
			for roller in [[low, high], [high, low]]:
				if freed or not wants.has("%s|%s" % [roller[0], roller[1]]):
					continue
				var why := ungrapple_error(roller[0], roller[1])
				if why != "":
					Trace.trace_log("Grappling", "ungrapple order dropped", {"ship": roller[0],
						"partner": roller[1], "reason": why})
					continue
				freed = _attempt_ungrapple(roller[0], roller[1], phase)
			if freed:
				game_state.ship_controller.remove_grapple(low, high)


func _attempt_ungrapple(ship_id: String, partner_id: String, phase: int) -> bool:
	var chance := ungrapple_chance(ship_id, partner_id)
	var attempt: int = int(chance["attempt"])
	game_state.ship_controller.set_ungrapple_attempts(ship_id, partner_id, attempt)
	var roll: int = game_state.dice.d10()
	var total: int = roll + int(chance["modifier"])
	var needed: int = DataManager.combat_tables.unfouling_success_max(attempt)
	var success: bool = total <= needed
	game_state.turn_log.add(PhaseEvents.Type.UNGRAPPLE, phase, ship_id, {
		"roll": roll, "modifier": chance["modifier"], "modifiers": chance["modifiers"], "total": total,
		"needed": needed, "attempt": attempt, "success": success}, partner_id)
	Trace.trace_log("Grappling", "%s cuts at %s: d10 %d %+d = %d (needs %d), %s" % [
		ship_id, partner_id, roll, int(chance["modifier"]), total, needed, "free" if success else "held"])
	return success


## 5.D.5: each ship of a new grapple that lies at WF=L is in irons: speed 0. Returns their ids.
func _irons_on_grapple(ids: Array) -> Array[String]:
	var out: Array[String] = []
	if game_state.environment == null:
		return out
	for sid in ids:
		var ship: ShipState = game_state.get_ship(sid)
		if _hex_grid.get_wind_facing(ship.facing, game_state.environment.wind_direction) != "L":
			continue
		out.append(sid)
		if ship.speed != 0:
			game_state.ship_controller.set_ship_speed(sid, 0)
	return out


# --- helpers ---

static func mini_id(a: String, b: String) -> String:
	return a if a < b else b


static func maxi_id(a: String, b: String) -> String:
	return b if a < b else a


func _sorted_pairs(orders: Array) -> Array:
	var pairs: Array = []
	for pair in orders:
		var p := [str(pair[0]), str(pair[1])]
		if not pairs.has(p):
			pairs.append(p)
	pairs.sort_custom(func(x: Array, y: Array) -> bool:
		if x[0] != y[0]:
			return x[0] < y[0]
		return x[1] < y[1])
	return pairs


func _sorted_ids() -> Array:
	var ids: Array = game_state.ships.keys()
	ids.sort()
	return ids


func _wind_speed() -> int:
	return game_state.environment.wind_speed if game_state.environment != null else 0


static func _add(mods: Array[Dictionary], name: String, value: int) -> void:
	if value != 0:
		mods.append({"name": name, "value": value})


static func _chance(mods: Array[Dictionary], success_max: int) -> Dictionary:
	var total := 0
	for m in mods:
		total += int(m["value"])
	var needed: int = success_max - total
	return {"needed": needed, "modifier": total, "modifiers": mods,
		"percent": clampi((needed + 1) * 10, 0, 100)}
