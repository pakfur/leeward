class_name ResolutionSteps
extends RefCounted
## Groups the events of a turn into replay steps, one per action (a shot, a morale check, a drift
## roll, a boarding round...). Pure statics, view side: it only reads the events a player may see
## (`PlayerView.events_for`), so a step about an enemy ship never shows a box count the filter hid.
##
## Every `PhaseEvents.Type` is in exactly one of three places (a test checks it):
##   LEADS    opens a step and names its kind;
##   FOLLOWS  folds into the open step when it is in the same phase and names the lead's ship or
##            target (a result of the lead: damage, a crit, a strike...); otherwise it is dropped
##            from the steps (it stays in the combat log);
##   SKIPPED  no die and no change worth a card, or a movement-phase event: not a step.
## Skipped events and followers that do not belong never close a step; the next lead does.

const LEADS := {
	PhaseEvents.Type.FIRE: "gunfire",
	PhaseEvents.Type.MARINE_FIRE: "marine_fire",
	PhaseEvents.Type.MORALE_CHECK: "morale",
	PhaseEvents.Type.DRIFT: "drift",
	PhaseEvents.Type.GRAPPLE: "grapple",
	PhaseEvents.Type.UNGRAPPLE: "ungrapple",
	PhaseEvents.Type.UNFOUL: "unfoul",
	PhaseEvents.Type.BOARDING_ROUND: "boarding",
	PhaseEvents.Type.FIRE_FOUGHT: "fire",
	PhaseEvents.Type.FIRE_SPREAD: "fire",
	PhaseEvents.Type.EXPLOSION_CHECK: "explosion",
	PhaseEvents.Type.BLAST: "explosion",
	PhaseEvents.Type.DEBRIS: "explosion",
	PhaseEvents.Type.TOW_BEGUN: "tow",
	PhaseEvents.Type.RALLY: "rally",
	PhaseEvents.Type.AIM_FORCED: "aim",
	PhaseEvents.Type.CRITICAL_FIXED: "crit_fix",
	PhaseEvents.Type.ANCHOR_MOVE: "anchor",
}

const FOLLOWS := [
	PhaseEvents.Type.DAMAGE,
	PhaseEvents.Type.GUNS_DISMOUNTED,
	PhaseEvents.Type.MORALE_NOTED,
	PhaseEvents.Type.STRIKE,
	PhaseEvents.Type.CRITICAL_ROLL,
	PhaseEvents.Type.CRITICAL_HIT,
	PhaseEvents.Type.CRITICAL_ENDED,
	PhaseEvents.Type.FIRE_STARTED,
	PhaseEvents.Type.DESTROYED,
	PhaseEvents.Type.FOULED,
	PhaseEvents.Type.AGROUND,
	PhaseEvents.Type.BOARDING_RESULT,
	PhaseEvents.Type.DEFENCE_SPLIT,
	PhaseEvents.Type.SHIP_CAPTURED,
	PhaseEvents.Type.PRIZE_CREW,
	PhaseEvents.Type.RECAPTURED,
	PhaseEvents.Type.REORGANIZING_ABORTED,
	PhaseEvents.Type.TOW_CUT,
]

const SKIPPED := [
	PhaseEvents.Type.SAIL_CHANGE,
	PhaseEvents.Type.VICTORY,
	PhaseEvents.Type.HOLD_FIRE,
	PhaseEvents.Type.COLLISION,
	PhaseEvents.Type.STOPPED_SHORT,
	PhaseEvents.Type.IN_IRONS,
	PhaseEvents.Type.WIND,
	PhaseEvents.Type.TURN_UNDONE,
	PhaseEvents.Type.BEAR_OFF,
	PhaseEvents.Type.POOR_MANEUVERING,
	PhaseEvents.Type.CREW_TASK,
	PhaseEvents.Type.FIRE_UNFOUGHT,
	PhaseEvents.Type.REPAIR,
	PhaseEvents.Type.BOARDERS,
	PhaseEvents.Type.BOARDERS_AWAY,
	PhaseEvents.Type.MARINES_DEFEND,
	PhaseEvents.Type.BEAR_OFF_ORDER,
	PhaseEvents.Type.SIGNAL,
	PhaseEvents.Type.TALK,
	PhaseEvents.Type.END_OFFER,
	PhaseEvents.Type.LEAD_CAST,
	PhaseEvents.Type.ESCAPE_DECLARED,
	PhaseEvents.Type.ESCAPED,
	PhaseEvents.Type.ARRIVED,
	PhaseEvents.Type.ARRIVAL_DELAYED,
	PhaseEvents.Type.ANCHORED,
	PhaseEvents.Type.CABLE_CUT,
	PhaseEvents.Type.SPRING_TURN,
	PhaseEvents.Type.VEER_IN,
	PhaseEvents.Type.SURRENDER,
]

const TITLES := {
	"gunfire": "Broadside",
	"marine_fire": "Musketry",
	"morale": "Morale check",
	"drift": "Drift",
	"grapple": "Grappling",
	"ungrapple": "Cutting the grapples",
	"unfoul": "Cutting free",
	"boarding": "Boarding",
	"fire": "Fire",
	"explosion": "Explosion",
	"tow": "Taking in tow",
	"rally": "Rally",
	"aim": "Gun crews' aim",
	"crit_fix": "Fixing damage",
	"anchor": "Riding to anchor",
}


## The step kind a type opens, "" when it does not lead.
static func lead_kind(type: PhaseEvents.Type) -> String:
	return str(LEADS.get(type, ""))


## True when `ev` belongs to the step `lead` opened: same phase, and `ev` names the lead's ship
## or target.
static func folds_into(lead: PhaseEvents.PhaseEvent, ev: PhaseEvents.PhaseEvent) -> bool:
	if ev.phase != lead.phase:
		return false
	for id in [ev.ship_id, ev.target_id]:
		if id != "" and (id == lead.ship_id or id == lead.target_id):
			return true
	return false


## The steps of `event_dicts` (`PlayerView.events_for` output) from index `from_index` on.
## `first_index` / `last_index` are indices into `event_dicts`. `ship_info` is
## `CombatLogPanel.log_ships(...)`.
static func build(event_dicts: Array, from_index: int, ship_info: Dictionary) -> Array[ResolutionStep]:
	var steps: Array[ResolutionStep] = []
	var open: ResolutionStep = null
	var open_events: Array[PhaseEvents.PhaseEvent] = []
	for i in range(maxi(from_index, 0), event_dicts.size()):
		var ev := PhaseEvents.PhaseEvent.from_dict(event_dicts[i])
		var kind := lead_kind(ev.type)
		if kind == "drift" and open != null and _same_drift_group(open_events, ev, i, open.last_index):
			open_events.append(ev)
			open.last_index = i
		elif kind != "":
			if open != null:
				open.events = open_events
			open = ResolutionStep.new()
			open_events = [ev]
			open.kind = kind
			open.phase = ev.phase
			open.ship_id = ev.ship_id
			open.target_id = ev.target_id
			open.first_index = i
			open.last_index = i
			steps.append(open)
		elif open != null and FOLLOWS.has(ev.type) and folds_into(open_events[0], ev):
			open_events.append(ev)
			open.last_index = i
	if open != null:
		open.events = open_events
	for step in steps:
		_fill(step, ship_info)
	return steps


## A drift group (8.A.6) logs one DRIFT per member in a row, all with the group's one roll: `ev`
## belongs to the open drift step when it follows at once, in the phase, with the same roll, needed,
## modifier and result, from a hex within three of the step's first ship.
static func _same_drift_group(open_events: Array[PhaseEvents.PhaseEvent], ev: PhaseEvents.PhaseEvent,
		index: int, last_index: int) -> bool:
	var lead := open_events[0]
	if lead.type != PhaseEvents.Type.DRIFT or ev.phase != lead.phase or index != last_index + 1:
		return false
	for key in ["roll", "needed", "modifier", "drifted"]:
		if not lead.data.has(key) or lead.data.get(key) != ev.data.get(key):
			return false
	if lead.data.has("partial") or ev.data.has("partial"):
		return false
	var a: Dictionary = lead.data.get("from", {})
	var b: Dictionary = ev.data.get("from", {})
	if a.is_empty() or b.is_empty():
		return false
	var dq := int(a["q"]) - int(b["q"])
	var dr := int(a["r"]) - int(b["r"])
	@warning_ignore("integer_division")
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2 <= 3


# --- Filling a step -----------------------------------------------------------

static func _fill(step: ResolutionStep, ship_info: Dictionary) -> void:
	var lead := step.events[0]
	step.dice = _dice(lead)
	for ev in step.events:
		if ev.type == PhaseEvents.Type.BOARDING_RESULT and int(ev.data.get("d10", -1)) >= 0:
			step.dice.append(_die(10, int(ev.data["d10"])))
	step.modifiers = _modifiers(lead)
	step.final_text = _final_text(lead)
	step.title = _title(step.kind, lead, ship_info)
	for ev in step.events:
		step.outcome_lines.append(_outcome_text(ev, ship_info))


static func _die(sides: int, value: int) -> Dictionary:
	return {"sides": sides, "values": [value]}


static func _dice(ev: PhaseEvents.PhaseEvent) -> Array:
	var d := ev.data
	match ev.type:
		PhaseEvents.Type.FIRE, PhaseEvents.Type.MARINE_FIRE:
			return [_die(6, int(d["d6"]))] if d.has("d6") else []
		PhaseEvents.Type.BLAST:
			return [_die(6, int(d["d6"]))] if d.has("d6") else []
		PhaseEvents.Type.AIM_FORCED, PhaseEvents.Type.DEBRIS:
			return [_die(6, int(d["roll"]))] if d.has("roll") else []
		PhaseEvents.Type.EXPLOSION_CHECK:
			if not d.has("roll"):
				return []
			var two := _die(6, int(d["roll"]))
			two["count"] = 2
			return [two]
		PhaseEvents.Type.BOARDING_ROUND:
			var out: Array = []
			for side in ["attacker", "defender"]:
				var s: Dictionary = d.get(side, {})
				if s.has("roll"):
					var two := _die(6, int(s["roll"]))
					two["count"] = 2
					out.append(two)
			return out
		PhaseEvents.Type.ANCHOR_MOVE:
			return [_die(6, int(d["roll"]))] if int(d.get("roll", -1)) >= 0 else []
		PhaseEvents.Type.MORALE_CHECK, PhaseEvents.Type.DRIFT, PhaseEvents.Type.GRAPPLE, \
		PhaseEvents.Type.UNGRAPPLE, PhaseEvents.Type.UNFOUL, PhaseEvents.Type.FIRE_FOUGHT, \
		PhaseEvents.Type.FIRE_SPREAD, PhaseEvents.Type.TOW_BEGUN, PhaseEvents.Type.RALLY, \
		PhaseEvents.Type.CRITICAL_FIXED:
			return [_die(10, int(d["roll"]))] if d.has("roll") else []
	return []


static func _modifiers(ev: PhaseEvents.PhaseEvent) -> Array:
	var out: Array = []
	var list: Array = ev.data.get("modifiers", []) if ev.data.get("modifiers") is Array else []
	for m in list:
		if m is Dictionary:
			out.append({"label": PhaseEvents.modifier_label(str(m.get("name", "?"))),
				"value": int(m.get("value", 0))})
	if list.is_empty() and ev.data.get("modifier") is int and int(ev.data["modifier"]) != 0:
		out.append({"label": "modifier", "value": int(ev.data["modifier"])})
	return out


static func _final_text(ev: PhaseEvents.PhaseEvent) -> String:
	var d := ev.data
	match ev.type:
		PhaseEvents.Type.FIRE, PhaseEvents.Type.BLAST:
			return "Gunfire number %s" % d["fgn"] if d.has("fgn") else ""
		PhaseEvents.Type.MARINE_FIRE:
			return "Total %s" % d["total"] if d.has("total") else ""
		PhaseEvents.Type.MORALE_CHECK, PhaseEvents.Type.RALLY:
			return "Needs %s or more" % d["rating"] if d.has("rating") else ""
		PhaseEvents.Type.GRAPPLE, PhaseEvents.Type.UNGRAPPLE, PhaseEvents.Type.TOW_BEGUN:
			if d.has("total") and d.has("needed"):
				return "Total %s, needs %s or less" % [d["total"], d["needed"]]
			return ""
		PhaseEvents.Type.AIM_FORCED:
			return "4 or more fires high"
		PhaseEvents.Type.BOARDING_ROUND:
			var a: Dictionary = d.get("attacker", {})
			var df: Dictionary = d.get("defender", {})
			if a.has("total") and df.has("total"):
				return "Attacker %s, defender %s" % [a["total"], df["total"]]
			return ""
		PhaseEvents.Type.DRIFT, PhaseEvents.Type.UNFOUL, PhaseEvents.Type.FIRE_FOUGHT, \
		PhaseEvents.Type.FIRE_SPREAD, PhaseEvents.Type.EXPLOSION_CHECK, \
		PhaseEvents.Type.CRITICAL_FIXED:
			return "Needs %s or less" % d["needed"] if d.has("needed") else ""
	return ""


static func _plain_name(ship_info: Dictionary, id: String) -> String:
	if id == "":
		return ""
	var entry: Variant = ship_info.get(id)
	if entry is Dictionary:
		return str((entry as Dictionary).get("name", id))
	return str(entry) if entry != null else id


static func _title(kind: String, lead: PhaseEvents.PhaseEvent, ship_info: Dictionary) -> String:
	var base: String = TITLES.get(kind, kind.capitalize())
	if kind == "gunfire" and GunneryTypes.CHASE_NAMES.has(int(lead.data.get("side", -1))):
		base = "Chase gun"
	var who := _plain_name(ship_info, lead.ship_id)
	var other := _plain_name(ship_info, lead.target_id)
	if who == "":
		return base
	if other == "":
		return "%s: %s" % [base, who]
	return "%s: %s and %s" % [base, who, other] if kind in ["drift", "unfoul", "boarding"] \
		else "%s: %s at %s" % [base, who, other]


## The event's own wording, except where the player's view hid the boxes the wording counts: those
## lines say what the filtered event does give (sections lost), never "no damage".
static func _outcome_text(ev: PhaseEvents.PhaseEvent, ship_info: Dictionary) -> String:
	var names := CombatLogPanel.event_names(ev, ship_info)
	var text := ev.to_text(names)
	var d := ev.data
	match ev.type:
		PhaseEvents.Type.FIRE, PhaseEvents.Type.BLAST:
			if not d.has("hull"):
				return text.trim_suffix(": no damage")
		PhaseEvents.Type.MARINE_FIRE:
			if not d.has("crew") or not d.has("boxes"):
				return _hidden_marine_text(ev, names)
		PhaseEvents.Type.PRIZE_CREW:
			if not d.has("sailors") or not d.has("marines"):
				return "A prize crew from %s goes aboard %s" % [
					str(names.get(ev.target_id, ev.target_id)), str(names.get(ev.ship_id, ev.ship_id))]
		PhaseEvents.Type.RECAPTURED:
			if not d.has("original_boxes") or not d.has("prize_boxes"):
				var who := str(names.get(ev.ship_id, ev.ship_id))
				if str(d.get("cause", "")) == "boarded":
					return "%s is retaken by %s: her crew is freed from below" % [
						who, str(names.get(ev.target_id, ev.target_id))]
				return "%s's crew rises and retakes the ship" % who
		PhaseEvents.Type.DAMAGE:
			if d.has("sections_lost"):
				var who := str(names.get(ev.ship_id, ev.ship_id))
				var n := int(d["sections_lost"])
				var line := "%s loses %s" % [who, PhaseEvents.plural(n, "section")]
				if d.get("marine_section_lost", false):
					line += ", the marines among them"
				return line
		PhaseEvents.Type.BOARDING_ROUND:
			var a: Dictionary = d.get("attacker", {})
			var df: Dictionary = d.get("defender", {})
			if not a.has("tbcf") or not df.has("tbcf"):
				return "Boarding, %s onto %s: attacker %s, defender %s" % [
					str(names.get(ev.ship_id, ev.ship_id)), str(names.get(ev.target_id, ev.target_id)),
					str(a.get("total", "?")), str(df.get("total", "?"))]
	return text


## The marine fire line with only the numbers the player's view kept: no box count when `boxes` is
## hidden (the firer is not hers), no result when `crew` is hidden (the target is not hers).
static func _hidden_marine_text(ev: PhaseEvents.PhaseEvent, names: Dictionary) -> String:
	var d := ev.data
	var calc := PackedStringArray(["d6 %s" % str(d.get("d6", "?"))])
	for m in d.get("modifiers", []):
		var v := int(m.get("value", 0))
		calc.append("%s %s%d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))),
			"−" if v < 0 else "+", absi(v)])
	var setup := "column %s" % str(d.get("column", "?"))
	if d.has("boxes"):
		setup = "%s, %s" % [PhaseEvents.plural(int(d["boxes"]), "box", "boxes"), setup]
	var text := "%s's marines fire on %s (%s) — %s → %s" % [
		str(names.get(ev.ship_id, ev.ship_id)), str(names.get(ev.target_id, ev.target_id)),
		setup, ", ".join(calc), str(d.get("total", "?"))]
	if d.has("crew"):
		var crew := int(d["crew"])
		text += ": " + ("no effect" if crew <= 0 else PhaseEvents.plural(crew, "crew box", "crew boxes"))
	return text
