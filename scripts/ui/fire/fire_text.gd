class_name FireText
extends RefCounted
## The fire step's words (board planning piece 3), pure statics: the option box's battery labels,
## notes and breakdown, the marines' option line, the Fire button's text and the no-shot line.
## Moved unchanged from the retired fire declaration panel. The rules are FireRules', every number
## the caller's (GunneryCalculator.preview_orders, MarineFireResolver.preview).

const CHASE_AMMO_NOTE := "Chasers fire round shot only"
const SEPARATOR := " — "
const HIGH_ONLY_NOTE := "Range %d+: must fire high"
const DISMANTLING_NOTE := "Dismantling shot reaches %d hexes"
const D6_NOTE := "A d6 is added when you fire; higher is better."
const BATTERY_LABELS := {
	GunneryTypes.BATTERY_FULL: "Full broadside",
	GunneryTypes.BATTERY_BOW: "Bow battery",
	GunneryTypes.BATTERY_STERN: "Stern battery",
	GunneryTypes.BATTERY_CHASE: "Chaser",
}


## "Hermione — 7 marines, column 7-8, alongside −1 — hits on 4 or less (67%)" for a marine-fire
## preview (MarineFireResolver.preview). A shot that cannot hit says so.
static func marine_option_text(target_name: String, preview: Dictionary) -> String:
	var parts: Array[String] = [target_name]
	var head := "%s, column %s" % [PhaseEvents.plural(int(preview.get("boxes", 0)), "marine"),
		str(preview.get("column", ""))]
	for m in preview.get("modifiers", []):
		var v := int(m.get("value", 0))
		head += ", %s %s%d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))), "−" if v < 0 else "+", absi(v)]
	parts.append(head)
	var hit_max := int(preview.get("hit_max", 0))
	if hit_max <= 0:
		parts.append("cannot hit")
	else:
		var odds := "hits on %s (%d%%)" % ["any roll" if hit_max >= 6 else "%d or less" % hit_max,
			int(preview.get("chance", 0))]
		if int(preview.get("most", 0)) > 1:
			odds += ", up to %d boxes" % int(preview["most"])
		parts.append(odds)
	return SEPARATOR.join(parts)


## The Fire button's text with marine fire: "Fire 1 broadside and muskets", "Fire muskets",
## or fire_button_text_for() alone when no marines fire.
static func fire_button_text_with_marines(orders: Array, marine_count: int) -> String:
	var guns := fire_button_text_for(orders)
	if marine_count <= 0:
		return guns
	if orders.is_empty():
		return "Fire muskets"
	return guns + " and muskets"


## One "name value" line per modifier, e.g. "rake +2".
static func modifier_lines(preview: GunneryTypes.ShotPreview) -> Array[String]:
	var lines: Array[String] = []
	for m in preview.modifiers:
		lines.append("%s %+d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))), int(m.get("value", 0))])
	return lines


## "Base 18, initial broadside +4 = 22. A d6 is added when you fire; higher is better."
## A half broadside leads: "Half broadside −8 on base 18, crew +1 = 11. ..." (only when the
## calculator applied it: with two targets it does not, 7.C.12g).
static func breakdown_text(preview: GunneryTypes.ShotPreview) -> String:
	var half := 0
	var lines: Array[String] = []
	for m in preview.modifiers:
		if str(m.get("name", "")) == "half_broadside":
			half = int(m.get("value", 0))
		else:
			lines.append("%s %+d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))), int(m.get("value", 0))])
	var sum := "Base %d" % preview.bgn
	if half != 0:
		sum = "%s on base %d" % [half_broadside_text(half), preview.bgn]
	if not lines.is_empty():
		sum += ", " + ", ".join(lines)
	if half != 0 or not lines.is_empty():
		sum += " = %d" % preview.mgn
	return "%s. %s" % [sum, D6_NOTE]


## "Half broadside −8" (true minus sign).
static func half_broadside_text(value: int) -> String:
	return "Half broadside %s%d" % ["−" if value < 0 else "+", absi(value)]


## "Full broadside", "Bow battery", "Stern battery" or "Chaser".
static func battery_label(battery: String) -> String:
	return str(BATTERY_LABELS.get(battery, battery))


## What the Fire button does: "Fire 1 broadside", "Fire 2 half broadsides", "Fire 1 broadside and
## 1 half broadside", "Fire 1 broadside and 1 chaser" or "Hold all fire". A full-broadside order
## counts as a broadside, a bow or stern battery order as a half broadside (a side split between
## two targets is two half broadsides), a "chase" order as a chaser.
static func fire_button_text(full_count: int, half_count: int = 0, chase_count: int = 0) -> String:
	var parts := PackedStringArray()
	if full_count > 0:
		parts.append("%d broadside%s" % [full_count, "" if full_count == 1 else "s"])
	if half_count > 0:
		parts.append("%d half broadside%s" % [half_count, "" if half_count == 1 else "s"])
	if chase_count > 0:
		parts.append("%d chaser%s" % [chase_count, "" if chase_count == 1 else "s"])
	if parts.is_empty():
		return "Hold all fire"
	return "Fire " + " and ".join(parts)


## fire_button_text() for a set of orders (FireOrders or their dictionaries).
static func fire_button_text_for(orders: Array) -> String:
	var full := 0
	var chase := 0
	for order in orders:
		if order.battery == GunneryTypes.BATTERY_FULL:
			full += 1
		elif order.battery == GunneryTypes.BATTERY_CHASE:
			chase += 1
	return fire_button_text(full, orders.size() - full - chase, chase)


## Why High is locked on; else the 14.E chance that a low aim holds (`limits` from the previews'
## aim_limits); "" when the player may choose freely.
static func aim_note(high_only: bool, limits: Array = [], crew_quality: String = "") -> String:
	if high_only:
		return HIGH_ONLY_NOTE % FireRules.HIGH_ONLY_RANGE
	if limits.is_empty():
		return ""
	var parts := PackedStringArray()
	for rule in limits:
		parts.append("crew CQ %s" % crew_quality if str(rule) == "crew" else "firing to windward")
	return "Low aim holds only on a d6 of 1–3 (14.E: %s)" % ", ".join(parts)


## Why Dismantling is unavailable, "" when it may be chosen. Says so when the player's choice is
## being replaced by roundshot for this target.
static func dismantling_note(range_hexes: int, want_dismantling: bool) -> String:
	if FireRules.dismantling_allowed(range_hexes):
		return ""
	var note := DISMANTLING_NOTE % FireRules.MAX_DISMANTLING_RANGE
	return note + " — roundshot this time" if want_dismantling else note


## The two-target note, e.g. "Two targets: −12 on each broadside". `modifier` is the (negative)
## two-target modifier. `with_chaser` (a chaser is one of the two targets) says "shot" instead of
## "broadside".
static func two_target_note(modifier: int, with_chaser: bool = false) -> String:
	return "Two targets: %s%d on each %s" % ["−" if modifier < 0 else "+", absi(modifier),
		"shot" if with_chaser else "broadside"]


## "HMS Phoebe — no broadside bears: out of range": one ship's no-shot line in the "Combat" panel.
static func no_shot_line(ship_name: String, reason: String) -> String:
	return "%s%sno broadside bears: %s" % [ship_name, SEPARATOR, reason]
