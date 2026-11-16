class_name CrewOverlayText
extends RefCounted
## CrewOverlayText - the crew overlay's strings (crew-tasks spec §4), as pure static functions of
## read-only state: header, Guns readout, DAMAGE (N), roster rows, tactical caption, deck notes,
## the Automatic rules. No scene nodes, no state changes.

const POUNDER_WORDS := {6: "six", 9: "nine", 12: "twelve", 18: "eighteen", 24: "twenty-four",
	32: "thirty-two", 36: "thirty-six", 42: "forty-two"}

## Rules A0-A6 of the Automatic crew setting, in the words of spec §3.3 (the "?" beside the switch).
const AUTO_RULES := [
	"A0  Locked tasks stay: reorganizing, a sail change in progress.",
	"A1  Fires first, lowest fire first: the section already fighting it, else the lowest free sailor section.",
	"A2  Tasks in progress continue with the same sections while still legal.",
	"A3  The ordered sail change: 1 or 2 sections in worker order.",
	"A4  Tacking: with a turn at MA 0 plotted, up to 3 free sections at the braces.",
	"A5  Repairs, one section each, shrouds, then rigging, then hull: the marines if free; sailors only with no enemy within 15 hexes.",
	"A6  Everyone else: sailors serve the guns, marines at marine fire.",
	"Worker order: M, then S4, S3, S2, S1. The marines are held back while there is a fire aboard, damage to fix, the ship is fouled or grappled or an enemy is alongside.",
]

const LOCKED_AUTO := "Automatic crew is on: the ship's officers place the sections. Turn it off to place them yourself."


static func section_name(section: int) -> String:
	return ShipState.SECTION_NAMES[section] if section >= 0 and section <= ShipState.MARINES else "?"


## "38-gun Frigate · crew quality B · carrying fighting sail".
static func header_subtitle(ship: ShipState) -> String:
	var type_name: String = ship.ship.name if ship.ship else ship.ship_type
	return "%s · crew quality %s · carrying %s" % [type_name, ship.crew_quality,
		PlanningSailUi.sail_name(ship.sail_state).to_lower()]


## Why the overlay is read-only, or "" when it is editable.
static func read_only_note(phase: int, ship: ShipState, own: bool, submitted: bool) -> String:
	if not own:
		return "Enemy crew orders are secret."
	if ship.is_destroyed():
		return "The ship is destroyed."
	if ship.is_struck():
		return "The ship has struck: firefighting is automatic."
	if phase != TurnPhaseController.GamePhase.PLANNING:
		return "Orders are given in the planning phase."
	if submitted:
		return "This turn's orders are submitted."
	return ""


## "Serving the guns", "Altering sail to MS", "At the braces", ...: a section's task in the plan.
static func task_title(section: int, entry: Dictionary) -> String:
	var code := str(entry.get("code", ""))
	var params: Dictionary = entry.get("params", {})
	match code:
		"":
			return "Marine fire" if section == ShipState.MARINES else "Serving the guns"
		SailController.CODE:
			var target := str(params.get("target", ""))
			return "Altering sail to %s" % target if target != "" else "Altering sail"
		TackCrewHandler.CODE:
			return "At the braces (tacking)"
		CrewRules.CODE_RO:
			return "Reorganizing"
		CrewRules.CODE_FF:
			return "Fire watch" if int(params.get("fire", -1)) < 0 else "Fighting a fire"
	return CrewRules.task_name(code, params).capitalize()


## {"now": g-t being worked (1-based), "total": g-t's needed} for a multi-g-t task the section is
## plotted to, or {} (one-g-t tasks, defaults). A task in progress counts from its done g-t's; a new
## one from 1. Needed g-t's follow the current crew quality (9.A.2).
static func progress_of(ship: ShipState, section: int, entry: Dictionary) -> Dictionary:
	var code := str(entry.get("code", ""))
	if code == "" or code == TackCrewHandler.CODE or code == CrewRules.CODE_FF:
		return {}
	var live := ship.task_of(section)
	var task := {"code": code, "params": entry.get("params", {}), "done": 0}
	if not live.is_empty() and str(live.get("code", "")) == code:
		task = live
	elif code == SailController.CODE:
		var target := str(task["params"].get("target", ""))
		task["params"] = {"target": target, "row": SailController.cost_row(ship, target)}
	var total := ship.task_turns_required(task)
	if total <= 1:
		return {}
	return {"now": mini(int(task.get("done", 0)) + 1, total), "total": total, "done": int(task.get("done", 0))}


## The counter's band tag: "T2/4" for multi-g-t tasks ("" otherwise).
static func progress_tag(ship: ShipState, section: int, entry: Dictionary) -> String:
	if str(entry.get("code", "")) == CrewRules.CODE_FF:
		# Fire parties show the Unfouling column they roll in: g-t's this section has fought it (0.2 Q5).
		var fire := int(entry.get("params", {}).get("fire", -1))
		if fire < 0:
			return ""
		var live := ship.fire_task(fire)
		var done := int(live.get("done", 0)) if (live.get("sections", []) as Array).has(section) else 0
		return ["1st", "2nd", "3rd+"][mini(done, 2)]
	var p := progress_of(ship, section, entry)
	return "" if p.is_empty() else "T%d/%d" % [p["now"], p["total"]]


## The Guns readout (spec §4.6): {"big", "bad", "why", "marines"}.
static func guns_readout(ship: ShipState, plan: Dictionary) -> Dictionary:
	var preview := CrewRules.guns_preview(ship, plan)
	var n: int = preview["sections"]
	var big := "Guns silent"
	var bad := true
	if preview["modifier"] != null:
		var mod: int = preview["modifier"]
		big = "%d of 4 sections · %s" % [n, "±0" if mod == 0 else ("%d" % mod).replace("-", "−")]
		bad = mod <= -6
	var why: PackedStringArray = []
	for m in preview["missing"]:
		var name := section_name(int(m["section"]))
		var code := str(m["why"])
		why.append("%s lost" % name if code == "lost" else "%s %s" % [name, _doing(code)])
	var why_text := " · ".join(why) if not why.is_empty() else "Gunfire modifier for sections firing, on both broadsides."
	if preview["modifier"] == null:
		why_text = "No sailor section is left at the guns: neither broadside can fire."
	var assignments: Dictionary = plan.get("assignments", {})
	var marines := "Marines: lost."
	if ship.section_alive(ShipState.MARINES):
		var entry: Dictionary = assignments.get(ShipState.MARINES, {})
		marines = "Marines: muskets at the rail." if entry.is_empty() else "Marines: %s." % task_title(ShipState.MARINES, entry).to_lower()
	return {"big": big, "bad": bad, "why": why_text, "marines": marines}


static func _doing(code: String) -> String:
	match code:
		SailController.CODE:
			return "altering sail"
		TackCrewHandler.CODE:
			return "at the braces"
		CrewRules.CODE_RO:
			return "reorganizing"
		CrewRules.CODE_FF:
			return "fighting fire"
	return CrewRules.task_name(code)


## DAMAGE (N) lines (spec §4.6): [{"text", "repairable"}]: fires, lasting critical effects, then
## the boxes lost that repairs could restore.
static func damage_lines(ship: ShipState, turn: int = -1, plan: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seqs := ship.fire_seqs()
	for k in seqs.size():
		out.append({"text": fire_line(ship, seqs[k], k + 1, turn, plan), "repairable": false, "fire": true})
	for line in ShipStatusPanel.critical_lines(ship):
		if line.begins_with("Afire"):
			continue  # each fire has its own line above
		out.append({"text": line, "repairable": false})
	if ship.missing_boxes("rigging") > 0:
		out.append({"text": "Rigging boxes lost: %d, repairable (RR)" % ship.missing_boxes("rigging"), "repairable": true})
	if ship.missing_boxes("hull") > 0:
		out.append({"text": "Hull boxes lost: %d, repairable (RH)" % ship.missing_boxes("hull"), "repairable": true})
	return out


## "Fire 1: burning 3 turns · 1 hull and 1 rigging a turn · fought by S2 (2nd turn)", or
## "… · unfought: morale check each turn" (spec §4.6). `turn` < 0: the age is left out.
## While planning, `plan` (the normalized crew plan) names the section that will fight it.
static func fire_line(ship: ShipState, seq: int, number: int, turn: int = -1, plan: Dictionary = {}) -> String:
	var text := "Fire %d: " % number
	if turn >= 0:
		var age := ship.fire_age(seq, turn)
		text += "burning %d turn%s · " % [age, "" if age == 1 else "s"] if age > 0 else "breaks out · "
	text += "1 hull and 1 rigging a turn · "
	var task := ship.fire_task(seq)
	var sections: Array = task.get("sections", [])
	var done := int(task.get("done", 0))
	var assignments: Dictionary = plan.get("assignments", {})
	if not assignments.is_empty():
		sections = []
		for s in assignments:
			var entry: Dictionary = assignments[s]
			if str(entry.get("code", "")) == CrewRules.CODE_FF and int(entry.get("params", {}).get("fire", -1)) == seq:
				sections.append(int(s))
		if not (task.get("sections", []) as Array) == sections:
			done = 0  # a new section starts in the first column (0.2 Q5)
	if sections.is_empty():
		return text + "unfought: morale check each turn"
	var names: Array = []
	for s in sections:
		names.append(section_name(int(s)))
	var attempt := mini(done + 1, 3)
	return text + "fought by %s (%s turn)" % [" ".join(names), ["1st", "2nd", "3rd+"][attempt - 1]]


## "Rigging 19/22 · carries up to plain sail" / "Hull 21/21".
static func boxes_caption(ship: ShipState, kind: String) -> String:
	var now: Array = ship.rigging_current_hp if kind == "rigging" else ship.hull_current_hp
	var start: Array = []
	if ship.ship:
		start = ship.ship.rigging_hp if kind == "rigging" else ship.ship.hull_hp
	var left := 0
	var all := 0
	for v in now:
		left += int(v)
	for v in start:
		all += int(v)
	if kind != "rigging":
		return "%d/%d" % [left, all]
	var cap := "dismasted" if ship.is_dismasted() else "carries up to " + PlanningSailUi.sail_name(ship.max_sail_state()).to_lower()
	return "%d/%d · %s" % [left, all, cap]


## Which side and how far forward `target` lies from `ship` (spec §4.7): "ahead", "off the
## starboard bow", "on the port beam", "on the starboard quarter", "astern".
static func bearing_words(ship: ShipState, target: ShipState) -> String:
	var grid := HexGrid.new()
	var bow := grid.axial_to_world(ship.hex_position.x, ship.hex_position.y)
	var stern_hex := ship.stern_hex()
	var stern := grid.axial_to_world(stern_hex.x, stern_hex.y)
	var me := grid.ship_center_world(ship.hex_position, ship.facing)
	var them := grid.ship_center_world(target.hex_position, target.facing)
	var heading := Vector2(bow.x - stern.x, bow.z - stern.z)
	var to := Vector2(them.x - me.x, them.z - me.z)
	if to.length() < 0.001:
		return "alongside"
	# x east, z south: a positive angle from the heading turns clockwise seen from above = starboard
	var a := rad_to_deg(heading.angle_to(to))
	var side := "starboard" if a > 0.0 else "port"
	var off := absf(a)
	if off <= 22.5:
		return "ahead"
	if off <= 67.5:
		return "off the %s bow" % side
	if off <= 112.5:
		return "on the %s beam" % side
	if off <= 157.5:
		return "on the %s quarter" % side
	return "astern"


## "Topaze 4 hexes off the starboard bow · wind SW 2" (nearest enemy in play), or "No enemy within
## gun range" when none is within 15 hexes.
static func tactical_caption(ship: ShipState, ships: Array, geometry: FireGeometry, env: EnvironmentState) -> String:
	var nearest: ShipState = null
	var best := -1
	for other: ShipState in ships:
		if other.player_id == ship.player_id or other.is_out_of_play():
			continue
		var r := geometry.range_between(ship.occupied_hexes(), other.occupied_hexes()) if geometry else -1
		if r >= 0 and (best < 0 or r < best):
			best = r
			nearest = other
	var wind := ""
	if env:
		wind = "wind %s %d" % [PhaseEvents.wind_direction_word(env.wind_direction), env.wind_speed]
		if env.has_pending_wind_change():
			var to_dir: int = env.pending_wind_direction if env.pending_wind_direction >= 0 else env.wind_direction
			var to_speed: int = env.pending_wind_speed if env.pending_wind_speed >= 0 else env.wind_speed
			wind += " (next turn %s %d)" % [PhaseEvents.wind_direction_word(to_dir), to_speed]
	var lead := "No enemy within gun range"
	if nearest != null and best <= FireRules.MAX_RANGE:
		lead = "%s %d hex%s %s" % [nearest.ship_name, best, "" if best == 1 else "es", bearing_words(ship, nearest)]
	return lead if wind == "" else "%s · %s" % [lead, wind]


## A gun deck's card note from the ship type's display-only armament ("19 eighteen-pounders a
## side"), or "" when the armament does not name that deck (spec §2.3).
static func deck_note(deck: Dictionary, armament: Dictionary) -> String:
	var key := str(deck.get("armament", ""))
	if key == "":
		return str(deck.get("note", ""))
	var long_guns: Dictionary = armament.get("long_guns", {})
	var entry: Dictionary = long_guns.get(key + "_port", long_guns.get(key + "_starboard", {}))
	if entry.is_empty():
		return str(deck.get("note", ""))
	var count := int(entry.get("count", 0))
	var pounds := int(entry.get("size", 0))
	var word: String = POUNDER_WORDS.get(pounds, "%d" % pounds)
	return "%d %s-pounder%s a side" % [count, word, "" if count == 1 else "s"]
