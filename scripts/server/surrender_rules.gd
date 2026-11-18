class_name SurrenderRules
extends RefCounted
## 14.B voluntary surrender and rallying (sub-project 7 spec §2.2): who may surrender and who may
## try to rally. Pure statics; the request is TurnPhaseController.player_surrender, the strike
## MoraleController.resolve_surrenders.

## 14.B.2: a ship with this many sections lost may surrender whatever her crew quality.
const SECTIONS_TO_SURRENDER := 5
## 14.B.2: crews of these qualities may surrender with no sections lost.
const SURRENDER_QUALITIES: Array[String] = ["F", "G"]
## 14.B.4: the second surrender is for good.
const MAX_SURRENDERS := 2


## Rigging, hull, sailor and marine sections at 0 boxes, each counted only where the type has boxes;
## a crew section counts only when none of its boxes were sent off as a prize crew (as
## VictoryController.points_lost).
static func sections_lost(ship: ShipState) -> int:
	var type: Ship = ship.ship
	if type == null:
		return 0
	var lost := _lost(ship.rigging_current_hp, type.rigging_hp) + _lost(ship.hull_current_hp, type.hull_hp)
	for i in mini(ship.crew_count.size(), type.crew_count.size()):
		if type.crew_count[i] > 0 and ship.crew_count[i] <= 0 and _detached(ship, i) == 0:
			lost += 1
	if type.marine_count > 0 and ship.marine_count <= 0 and _detached(ship, ShipState.MARINES) == 0:
		lost += 1
	return lost


## 14.B.2: CQ F or G, or SECTIONS_TO_SURRENDER sections lost.
static func eligible(ship: ShipState) -> bool:
	return SURRENDER_QUALITIES.has(ship.crew_quality) or sections_lost(ship) >= SECTIONS_TO_SURRENDER


## "" when the ship may be ordered to surrender, else why not. Any ship in play and on the map may
## (aground, anchored, fouled, grappled or towed included) when eligible.
static func surrender_error(ship: ShipState, turn: int = -1) -> String:
	if ship.is_out_of_play() or not ship.is_on_map():
		return "%s is not in play" % ship.ship_name
	if turn >= 0 and ship.rally_turn == turn:
		return "%s rallied this turn: she may not surrender again until the next (14.B.3)" % ship.ship_name
	if not eligible(ship):
		return "%s may surrender only at CQ F or G or with five sections lost (14.B.2): %d lost" % [
			ship.ship_name, sections_lost(ship)]
	return ""


## "" when the ship may try to rally on g-t `turn` (14.B.3: one attempt a g-t), else why not.
static func rally_error(ship: ShipState, turn: int) -> String:
	if ship.is_captured():
		return "a captured ship cannot rally (14.B.2)"
	if ship.surrenders >= MAX_SURRENDERS:
		return "%s has surrendered twice: she has struck for good (14.B.4)" % ship.ship_name
	if ship.is_struck() and not ship.surrendered:
		return "%s has struck for good" % ship.ship_name
	if ship.is_struck() and ship.surrendered and ship.is_gutted():
		return "%s has no hull or no crew left: her surrender is permanent (9.C)" % ship.ship_name
	if not ship.can_rally():
		return "%s has not surrendered" % ship.ship_name
	if ship.rally_turn == turn:
		return "%s has tried to rally this turn" % ship.ship_name
	return ""


static func _lost(current: Array, full: Array) -> int:
	var n := 0
	for i in mini(current.size(), full.size()):
		if int(full[i]) > 0 and int(current[i]) <= 0:
			n += 1
	return n


static func _detached(ship: ShipState, section: int) -> int:
	return ship.detached_boxes[section] if section < ship.detached_boxes.size() else 0
