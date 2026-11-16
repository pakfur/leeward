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
	if ship.is_struck():
		return "STRUCK"
	if ship.is_captured():
		return "PRIZE"
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


## The card badge text: the status badge and the fire badge, joined.
static func card_badge(ship: ShipState) -> String:
	var parts: PackedStringArray = []
	for b in [status_badge(ship), fire_badge(ship), "BOARDERS" if ship.has_boarders() else ""]:
		if b != "":
			parts.append(b)
	return " · ".join(parts)


static func can_plot_movement(ship: ShipState) -> bool:
	return status_badge(ship) == ""


static func movement_block_reason(ship: ShipState) -> String:
	match status_badge(ship):
		"DESTROYED": return "Ship has been destroyed."
		"STRUCK": return "Ship has struck its colours and cannot move."
		"PRIZE": return "Prize: cannot sail (10.H.2)."
		"DISMASTED": return "Ship is dismasted and cannot move."
		"FOULED": return "Ship is fouled with %s and cannot move until it breaks free." % ship.fouled_with
		"GRAPPLED": return "Ship is grappled to %s and cannot move until the grapples are cut (8.C.7)." % ", ".join(ship.grappled_with)
	return ""
