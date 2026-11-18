class_name TowRules
extends RefCounted
## TowRules - pure statics for towing (Close Action 12.A; towing spec §1, §3, §4, §6): the tow
## station and the follow pose (`station_hex`, `in_position`, `follow_pose`), the 12.A.7 MA loss
## (`ma_loss`), the tow crew order and its tasks (`parse_order`, `take_target_error`, `refusal`,
## `order_task`), whether a tow may begin (`pair_error`) and why a standing tow breaks
## (`broken_reason`).
##
## Geometry (spec §1): the tow station is the hex ahead of the towed ship's bow; the tower's stern
## must lie there (12.A.4a). On each tower step the towed ship's bow takes the hex the tower's stern
## has just left and points at the tower's new stern.
##
## The 8.C limits of the tow grapple (12.A.4b) are GrapplingController's own statics, not copies.

const CODES: Array[String] = ["PT", "TX"]
## The crew-overlay station of both towing tasks.
const STATION := "tow"
## Most MPs either ship may have used this g-t (8.C.1).
const MAX_MPS := GrapplingController.MAX_MPS


static func is_code(code: String) -> bool:
	return CODES.has(code)


## The hex directly ahead of the towed ship's bow, where the tower's stern must lie (12.A.4a).
static func station_hex(towed: ShipState) -> Vector2i:
	return towed.hex_position + HexGrid.DIRECTIONS[towed.facing]


static func in_position(tower: ShipState, towed: ShipState) -> bool:
	return tower.stern_hex() == station_hex(towed)


## The towed ship's pose after the tower steps from (`bow`, `facing`) to (`new_bow`, `new_facing`)
## (spec §1): {"bow": S, "facing": d, "stern": S - DIRECTIONS[d]}, S the tower's old stern and d the
## direction from S to the tower's new stern. {} (and an error) when the two sterns are not neighbours.
static func follow_pose(bow: Vector2i, facing: int, new_bow: Vector2i, new_facing: int) -> Dictionary:
	var old_stern := HexGrid.stern_of(bow, facing)
	var new_stern := HexGrid.stern_of(new_bow, new_facing)
	var d: int = HexGrid.DIRECTIONS.find(new_stern - old_stern)
	if d < 0:
		push_error("TowRules.follow_pose: sterns %s and %s are not neighbours" % [old_stern, new_stern])
		return {}
	return {"bow": old_stern, "facing": d, "stern": old_stern - HexGrid.DIRECTIONS[d]}


## The tower's MA loss (12.A.7): 1, plus 1 per class the tower is larger by (a higher class number),
## plus 1 when the tow is dismasted or carries no sail.
static func ma_loss(tower: ShipState, towed: ShipState) -> int:
	var loss := 1 + maxi(0, tower.ship.ship_class - towed.ship.ship_class)
	if towed.is_dismasted() or towed.sail_state.to_upper() == "NS":
		loss += 1
	return loss


## The tow crew order (spec §3): {"kind": "" | "cut" | "take" | "bad", "target": ship id or ""}.
static func parse_order(order: String) -> Dictionary:
	if order == "" or order == "cut":
		return {"kind": order, "target": ""}
	if order.begins_with("take:") and order.length() > 5:
		return {"kind": "take", "target": order.substr(5)}
	return {"kind": "bad", "target": ""}


## Why `ship` may not be ordered to take `target` in tow (spec §3, §4), or "".
static func take_target_error(ship: ShipState, target: ShipState) -> String:
	if target == null:
		return "Unknown ship"
	if target.ship_id == ship.ship_id:
		return "a ship cannot tow itself"
	if target.side != ship.side:
		return "only friendly ships may be towed (12.A.2)"
	if target.is_struck():
		return "%s has struck: a ship that has surrendered is not towed (ruling)" % target.ship_name
	return GrapplingController.destroyed_target_error(target)


## Why `ship` may not plot `code` (PT or TX) now, `accepted` the codes already in the plan (spec §3),
## or "".
static func refusal(ship: ShipState, code: String, accepted: Array) -> String:
	if not ship.crew_can_act():
		return "the crew cannot act"
	if ship.is_captured():
		return "a prize plots only boarding and repairs (10.H.2)"
	match code:
		"PT":
			if ship.is_towing():
				return "already towing (12.A.2)"
			if ship.is_towed():
				return "a towed ship cannot tow (12.A.2)"
			if ship.tow_prepared:
				return "already prepared to tow (12.A.3)"
			if accepted.has("PT"):
				return "one section prepares the tow (12.A.3)"
			return ""
		"TX":
			if ship.tow_partner() == "":
				return "no tow to cut (12.A.9)"
			if accepted.has("TX"):
				return "one section cuts the tow (12.A.9)"
			return ""
	return "not a towing task"


## The task the tow order calls for (Automatic rule A2d): {"code", "params": {}}, or {} when none.
static func order_task(ship: ShipState, order: String) -> Dictionary:
	match str(parse_order(order)["kind"]):
		"take":
			if not ship.is_towing() and not ship.is_towed() and not ship.tow_prepared \
					and ship.tasks_with("PT").is_empty():
				return {"code": "PT", "params": {}}
		"cut":
			if ship.tow_partner() != "":
				return {"code": "TX", "params": {}}
	return {}


## Why `tower` may not try to take `towed` in tow now (spec §4, 12.A.2-4), or "". With `setup`
## (Developer UI, a scenario's starting tow) the preparation, fire, crew-quality and MP checks are
## skipped.
## `placed` is a tow already made (a scenario's starting tow, checked once placed): the tow-state
## checks (already towing / in tow) are skipped, the rest still hold.
static func pair_error(tower: ShipState, towed: ShipState, setup: bool = false, placed: bool = false) -> String:
	if tower.ship_id == towed.ship_id:
		return "a ship cannot tow itself"
	for s: ShipState in [tower, towed]:
		if not s.is_on_map():
			return "%s is not on the map" % s.ship_name
	if tower.is_out_of_play():
		return "%s cannot tow (12.A.2, 10.H.2)" % tower.ship_name
	if towed.is_struck():
		return "%s has struck: a ship that has surrendered is not towed (ruling)" % towed.ship_name
	if towed.is_destroyed():
		return GrapplingController.destroyed_target_error(towed)
	if towed.side != tower.side:
		return "only friendly ships may be towed (12.A.2)"
	if not placed:
		if tower.is_towing():
			return "%s already tows %s" % [tower.ship_name, tower.towing_id]
		if tower.is_towed():
			return "a towed ship cannot tow (12.A.2)"
		if towed.is_towed():
			return "%s is already in tow" % towed.ship_name
		if towed.is_towing():
			return "%s already tows %s" % [towed.ship_name, towed.towing_id]
	for s: ShipState in [tower, towed]:
		if s.is_anchored():
			return "%s is anchored" % s.ship_name
	for s: ShipState in [tower, towed]:
		if s.is_aground():
			return "%s is aground (13.G.3)" % s.ship_name
	if tower.is_dismasted():
		return "a dismasted ship cannot tow"
	if not in_position(tower, towed):
		return "%s's stern must lie in the hex ahead of %s's bow (12.A.4a)" % [tower.ship_name, towed.ship_name]
	if tower.is_linked() or towed.is_linked():
		return "neither ship may be fouled or grappled (12.A.4b)"
	if setup:
		return ""
	if not tower.tow_prepared:
		return "%s has not prepared to tow (PT, 12.A.3)" % tower.ship_name
	var crew_error := GrapplingController.roller_error(tower)
	if crew_error != "":
		return crew_error
	return GrapplingController.mps_error(tower, towed)


## Why a standing tow breaks now (spec §6), or "": "destroyed", "struck", "aground" (either ship),
## "taken" (the tower captured, or the tow no longer of the tower's side) or "dismasted" (the
## tower: a dismasted ship cannot tow, so she casts off her tow; ruling).
static func broken_reason(tower: ShipState, towed: ShipState) -> String:
	if tower.is_destroyed() or towed.is_destroyed():
		return "destroyed"
	if tower.is_struck() or towed.is_struck():
		return "struck"
	if tower.is_aground() or towed.is_aground():
		return "aground"
	if tower.is_captured() or towed.side != tower.side:
		return "taken"
	if tower.is_dismasted():
		return "dismasted"  # a dismasted ship cannot tow: she casts off her tow (ruling)
	return ""


## The scenario's starting tows (spec §7): a ship entry's optional "tow": "<towed ship id>". The
## problem with `entry`'s tow (an entry with none gives ""), judged against every entry of the
## scenario and the placed `ships` (ShipStates). Messages start "Towing: ".
static func entry_error(entry: Dictionary, entries: Array, ships: Array) -> String:
	if not entry.has("tow"):
		return ""
	var id := str(entry.get("id", ""))
	var towed_id := str(entry["tow"])
	var by_id := {}
	for s: ShipState in ships:
		by_id[s.ship_id] = s
	if not by_id.has(id):
		return "Towing: unknown tower '%s'" % id
	if not by_id.has(towed_id):
		return "Towing: '%s' tows unknown ship '%s'" % [id, towed_id]
	if towed_id == id:
		return "Towing: '%s' cannot tow itself" % id
	for other in entries:
		if not (other is Dictionary) or other == entry or not other.has("tow"):
			continue
		if str(other["tow"]) == towed_id:
			return "Towing: '%s' is towed by two ships" % towed_id
		if str(other.get("id", "")) == towed_id:
			return "Towing: '%s' is towed and also tows" % towed_id
	var why := pair_error(by_id[id], by_id[towed_id], true, by_id[id].towing_id == towed_id)
	if why != "":
		return "Towing: '%s' cannot tow '%s': %s" % [id, towed_id, why]
	return ""


## Problems with the scenario's starting tows, one message each; empty when all are legal.
static func scenario_errors(scenario: Dictionary, ships: Array) -> Array[String]:
	var errors: Array[String] = []
	var entries: Array = scenario.get("ships", [])
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var why := entry_error(entry, entries, ships)
		if why != "":
			errors.append(why)
	return errors
