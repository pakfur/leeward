class_name MarineFireResolver
extends RefCounted
## MarineFireResolver - Marine fire (Close Action 1997, 7.G).
## The marine section of a ship fires muskets at one adjacent enemy per g-t, simultaneously with the
## gunfire (7.G.5). One d6 on the Marine Fire table (p.110) by the marine boxes at the start of the
## step, with the DRMs; the result is crew boxes the target loses, each rolled on the Crew Loss table's
## "All Other Causes" row (7.G.3), or none when the target has only one type of crew left.
## Eligibility is FireRules.marine_error. Queries (preview, eligible_marine_shots, validate_orders)
## are pure; prepare() captures the shots before any gunfire damage and resolve() rolls and applies
## them.
##
## Marine orders are {"ship_id", "target_id"} dictionaries, a second list in the fire submission
## (TurnPhaseController.player_submit_fire_orders).
##
## Boarding (boarding spec B4): the "target has boarders preparing or prepared" -1 reads
## ShipState.has_boarders(); while boarders are formed the Crew Loss row follows 10.D.7
## (BoardingRules.crew_loss_cause).

## Live tasks that put boarders on the target ("preparing or prepared", 10.B.6).
const BOARDER_CODES: Array[String] = ["FB", "BR", "BA"]
## Crew Loss row for marine fire (7.G.3, 7.D.9).
const CREW_LOSS_CAUSE := "other"
## DAMAGE "cause" for boxes lost to marine fire.
const DAMAGE_CAUSE := "marine_fire"

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## What the marines of `ship_id` firing at `target_id` would do now, without rolling:
## {ship_id, target_id, can_fire, reason, range, boxes, column ("7-8"), modifiers: [{name, value}]
##  (zero values omitted), modifier (their sum), hit_max (highest d6 that marks out a box, 0 = none),
##  chance (percent of a hit), most (boxes lost on the best roll)}.
func preview(ship_id: String, target_id: String) -> Dictionary:
	var out := {"ship_id": ship_id, "target_id": target_id, "can_fire": false, "reason": "",
		"range": -1, "boxes": 0, "column": "", "modifiers": [], "modifier": 0,
		"hit_max": 0, "chance": 0, "most": 0}
	var firer: ShipState = game_state.get_ship(ship_id)
	var target: ShipState = game_state.get_ship(target_id)
	if firer != null and target != null and game_state.fire_geometry != null:
		out["range"] = game_state.fire_geometry.range_between(firer.occupied_hexes(), target.occupied_hexes())
	var reason := FireRules.marine_error(firer, target, int(out["range"]))
	if reason != "":
		out["reason"] = reason
		return out
	var tables: CombatTables = DataManager.combat_tables
	var boxes := firer.marine_count
	var modifiers: Array = []
	var add := func(name: String, applies: bool) -> void:
		if applies and tables.marine_fire_drm(name) != 0:
			modifiers.append({"name": name, "value": tables.marine_fire_drm(name)})
	add.call("grappled_or_fouled", linked(firer, target_id))
	add.call("cq_e_f", firer.crew_quality in ["E", "F"])
	add.call("cq_g", firer.crew_quality == "G")
	add.call("target_boarders", has_boarders(target))
	add.call("larger_class", _ship_class(firer) > 0 and _ship_class(firer) < _ship_class(target))
	var total := 0
	for m in modifiers:
		total += int(m["value"])
	var hit_max := 0
	for d6 in range(1, 7):
		if tables.marine_fire_result(d6 + total, boxes) > 0:
			hit_max = d6
	out["can_fire"] = true
	out["boxes"] = boxes
	out["column"] = tables.marine_fire_column_label(boxes)
	out["modifiers"] = modifiers
	out["modifier"] = total
	out["hit_max"] = hit_max
	@warning_ignore("integer_division")
	out["chance"] = (hit_max * 100 + 3) / 6
	out["most"] = tables.marine_fire_result(1 + total, boxes)
	return out


## Previews of every target the marines of `ship_id` may fire at, by target_id.
func eligible_marine_shots(ship_id: String) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var firer: ShipState = game_state.get_ship(ship_id)
	if firer == null or firer.is_out_of_play() or firer.marine_count <= 0:
		return shots
	var ids: Array = []
	for other: ShipState in game_state.get_all_ships():
		if other.ship_id != ship_id:
			ids.append(other.ship_id)
	ids.sort()
	for target_id: String in ids:
		var p := preview(ship_id, target_id)
		if p["can_fire"]:
			shots.append(p)
	return shots


func any_eligible_marine_shot() -> bool:
	for ship: ShipState in game_state.get_all_ships():
		if not eligible_marine_shots(ship.ship_id).is_empty():
			return true
	return false


## "" when `orders` ({ship_id, target_id} dictionaries) are legal for `player_id`, else the reason.
func validate_orders(player_id: int, orders: Array) -> String:
	var shape := FireRules.marine_orders_error(orders)
	if shape != "":
		return shape
	for order: Dictionary in orders:
		var firer: ShipState = game_state.get_ship(str(order["ship_id"]))
		if firer == null or not game_state.commands(player_id, firer.ship_id):
			return "ship %s is not yours to command" % str(order["ship_id"])
		var p := preview(str(order["ship_id"]), str(order["target_id"]))
		if not p["can_fire"]:
			return p["reason"]
	return ""


## The shots of `orders`, previewed now (marine boxes and DRMs at the start of the step, 7.G.3,
## 7.G.5), sorted by firer ship_id; orders that cannot fire are dropped. Call before gunfire.
func prepare(orders: Array) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	for order in orders:
		if not order is Dictionary:
			continue
		var p := preview(str(order.get("ship_id", "")), str(order.get("target_id", "")))
		if p["can_fire"]:
			shots.append(p)
	shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["ship_id"]) < str(b["ship_id"]))
	return shots


## Rolls and applies prepared shots (prepare()). Dice order (spec §3.3), after all gunfire dice:
## firers in ascending ship_id, each one d6 on the Marine Fire table, then one Crew Loss d6 per box
## lost (none while the target has one crew type). Logs MARINE_FIRE, then the DAMAGE it causes.
func resolve(shots: Array[Dictionary], phase: int) -> void:
	if not is_server:
		push_error("MarineFireResolver: Cannot resolve marine fire on client")
		return
	for shot in shots:
		var d6: int = game_state.dice.d6()
		var total := d6 + int(shot["modifier"])
		var hits: int = DataManager.combat_tables.marine_fire_result(total, int(shot["boxes"]))
		game_state.turn_log.add(PhaseEvents.Type.MARINE_FIRE, phase, str(shot["ship_id"]), {
			"boxes": int(shot["boxes"]),
			"column": str(shot["column"]),
			"modifiers": (shot["modifiers"] as Array).duplicate(true),
			"modifier": int(shot["modifier"]),
			"d6": d6,
			"total": total,
			"crew": hits,
		}, str(shot["target_id"]))
		if hits > 0:
			var cause := BoardingRules.crew_loss_cause(game_state.get_ship(str(shot["target_id"])), CREW_LOSS_CAUSE)  # 10.D.7
			game_state.damage_controller.apply_crew_losses(str(shot["target_id"]), hits, cause,
				phase, str(shot["ship_id"]), DAMAGE_CAUSE)
		Trace.trace_log("MarineFire", "%s -> %s: d6 %d %+d = %d, %d box(es)" % [
			shot["ship_id"], shot["target_id"], d6, int(shot["modifier"]), total, hits])


## The firing ship is grappled or fouled to the target (Marine Fire DRM).
static func linked(firer: ShipState, target_id: String) -> bool:
	return firer.linked_ids().has(target_id)


## The ship has boarders preparing or prepared (a live FB, BR or BA task, 10.B.6).
static func has_boarders(ship: ShipState) -> bool:
	return ship != null and ship.has_boarders()


static func _ship_class(ship: ShipState) -> int:
	return ship.ship.ship_class if ship.ship != null else 0
