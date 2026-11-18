class_name PlanningSailUi
extends RefCounted
## PlanningSailUi - Pure presentation logic for sail names, sail-change wording and ship status badges.
## No scene nodes and no state changes: given a ShipState it says what text and controls to show.

const SAIL_NAMES := {
	"NS": "Furled",
	"FS": "Fighting sail",
	"MS": "Manoeuvring sail",
	"PS": "Plain sail",
}


## The sail's name alone ("Fighting sail"); unknown codes pass through.
static func sail_label(code: String) -> String:
	var upper := code.to_upper()
	return SAIL_NAMES.get(upper, upper)


static func sail_name(code: String) -> String:
	return sail_label(code)


static func plural(count: int, noun: String) -> String:
	return "%d %s%s" % [count, noun, "" if count == 1 else "s"]


## "Fighting sail — 1 turn, 1 section"
static func target_button_text(target: String, cost: Dictionary) -> String:
	return "%s — %s, %s" % [sail_label(target), plural(cost.get("turns", 0), "turn"), plural(cost.get("sections", 0), "section")]


static func status_badge(ship: ShipState) -> String:
	if ship.is_destroyed():
		return "DESTROYED"
	if ship.is_escaped():
		return "ESCAPED"
	if ship.is_struck() and ship.surrendered:
		return "SURRENDERED"
	if ship.is_struck():
		return "STRUCK"
	if ship.is_captured():
		return "PRIZE"
	if ship.is_aground():
		return "AGROUND"
	if ship.is_anchored():
		return "ANCHORED"
	if ship.is_towing():
		return "TOWING"
	if ship.is_towed():
		return "IN TOW"
	if ship.is_dismasted():
		return "DISMASTED"
	if ship.fouled_with != "":
		return "FOULED"
	if ship.is_grappled():
		return "GRAPPLED"
	return ""


## "AFIRE" / "AFIRE ×2" for a burning ship (8.E), else "". Not a movement lock: shown beside
## status_badge.
static func fire_badge(ship: ShipState) -> String:
	if ship.is_destroyed() or not ship.is_burning():
		return ""
	return "AFIRE" if ship.fire_count() == 1 else "AFIRE ×%d" % ship.fire_count()


## "ESCAPING" for a ship in play that has declared it is trying to escape (V.D), else "".
static func escape_badge(ship: ShipState) -> String:
	return "ESCAPING" if ship.escape_declared and not ship.is_out_of_play() else ""


## "SURRENDERING" for a ship in play that has ordered a voluntary surrender (14.B), else "".
static func surrender_badge(ship: ShipState) -> String:
	return "SURRENDERING" if ship.surrender_ordered and not ship.is_out_of_play() else ""


## The card badge text: the status badge, the fire badge and the escape badge, joined.
static func card_badge(ship: ShipState) -> String:
	var parts: PackedStringArray = []
	for b in [status_badge(ship), fire_badge(ship), escape_badge(ship), surrender_badge(ship),
			"BOARDERS" if ship.has_boarders() else ""]:
		if b != "":
			parts.append(b)
	return " · ".join(parts)


## A towing ship plots her own course (TOWING does not block), unless her tow is fouled or grappled
## and holds her (8.C.7, DefaultCourse.tow_held), or she is herself dismasted, fouled or grappled
## (the locks the TOWING badge hides): DefaultCourse.can_move.
static func can_plot_movement(ship: ShipState) -> bool:
	match status_badge(ship):
		"":
			return true
		"TOWING":
			return DefaultCourse.can_move(GameState, ship)
	return false


static func movement_block_reason(ship: ShipState) -> String:
	match status_badge(ship):
		"DESTROYED": return "Ship has been destroyed."
		"ESCAPED": return "Ship has escaped."
		"SURRENDERED": return "Ship has surrendered (14.B) and cannot move unless she rallies."
		"STRUCK": return "Ship has struck its colours and cannot move."
		"PRIZE": return "Prize: cannot sail (10.H.2)."
		"AGROUND": return "Ship is aground and cannot move (13.G.3)."
		"ANCHORED": return "Ship is anchored: cut the cable (AX) to get under way (13.C.3)."
		"TOWING":
			var own := _lock_reason(ship)
			if own != "":
				return own
			if DefaultCourse.tow_held(GameState, ship):
				return "Ship's tow %s is fouled or grappled: neither can move (8.C.7)." % ship.towing_id
			return ""
		"IN TOW": return "Ship is in tow and follows her tower (12.A.6)."
	return _lock_reason(ship)


## Why the ship's own masts or lines hold her (dismasted, fouled, grappled), or "".
static func _lock_reason(ship: ShipState) -> String:
	if ship.is_dismasted():
		return "Ship is dismasted and cannot move."
	if ship.fouled_with != "":
		return "Ship is fouled with %s and cannot move until it breaks free." % ship.fouled_with
	if ship.is_grappled():
		return "Ship is grappled to %s and cannot move until the grapples are cut (8.C.7)." % ", ".join(ship.grappled_with)
	return ""
