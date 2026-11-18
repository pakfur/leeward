class_name AnchorRules
extends RefCounted
## AnchorRules - pure statics for anchoring (Close Action 13.A-F; anchoring spec §1, §3, §7):
## which anchoring task may be ordered (`refusal`, `order_task`), where the scenario allows a
## ship to anchor (`permitted`, `scenario_errors`), and the geometry of a ship riding to her
## anchor (`footprint`, `proper_facing`, `swing_step`, `spring_turn`, `forced_check`).
##
## Geometry (spec §1): the anchored end lies `cable` hexes directly downwind of the anchor. Anchored
## by the bow (AB) the ship's proper facing is into the wind (13.A.3), by the stern (AS) downwind.
## Port is facing - 1, starboard facing + 1.

const CODES: Array[String] = ["PBA", "PSA", "PBS", "PSS", "A", "AX", "VO", "VI", "HS"]
const PREP_CODES: Array[String] = ["PBA", "PSA", "PBS", "PSS"]
const ORDERS: Array[String] = ["", "prepare_bow", "prepare_stern", "prepare_springs", "anchor", "cut",
	"veer_out", "veer_in", "turn_port", "turn_starboard"]
## 13.E.1c: at most three veer-outs.
const MAX_VEERED := 3
## 13.A.5: a ship may anchor at most twice a scenario.
const MAX_ANCHORINGS := 2
## The crew-overlay station of every anchoring task.
const STATION := "anchor"

const _ORDER_CODES := {
	"prepare_bow": "PBA", "prepare_stern": "PSA", "anchor": "A", "cut": "AX",
	"veer_out": "VO", "veer_in": "VI",
}

const R_CREW := "The crew cannot handle the anchors (struck, or a prize)."
const R_HS_PARAMS := "Handle springs needs a turn to port or starboard (13.D.2)."
const R_ANCHORED := "Already anchored: cut the cable first (13.F)."
const R_TWICE := "Anchored twice already (13.A.5)."
const R_READY := "An anchor is already ready (13.B.3)."
const R_ONE_ANCHOR := "Only one anchor at a time (13.B.3)."
const R_SPRINGS_READY := "The springs are already ready (13.B.4)."
const R_PREPARE_FIRST := "Prepare an anchor first (13.B.1)."
const R_NOT_HERE := "The scenario does not allow anchoring here (Scenario Book V.B)."
const R_MPS := "MPs plotted: the anchoring is erased (13.C.1)."
const R_NOT_ANCHORED := "Not anchored."
const R_CUT := "No turn or veering on the g-t the cable is cut (13.F.2)."
const R_VO_CALM := "No wind: a ship cannot veer out (13.E.3)."
const R_VO_MAX := "Three VOs already (13.E.1c)."
const R_VO_LINKED := "Fouled or grappled: cannot veer out."
const R_VO_TURN := "Not on a g-t it turns (13.E.1d)."
const R_VEER_BOTH := "Veer out or veer in, not both."
const R_VI_NONE := "Nothing to veer in (13.E.2)."
const R_VI_TURN := "Not on a g-t it turns (13.E.2)."
const R_HS_NO_SPRINGS := "Springs are not rigged (13.D)."
const R_HS_CALM := "No wind: springs cannot be used (13.E.3)."
const R_HS_LINKED := "Fouled or grappled ships cannot turn (13.D.2)."


static func is_code(code: String) -> bool:
	return CODES.has(code)


## Whether the scenario allows anchoring at `hex` (Scenario Book V.B; spec §7): `anchoring` absent
## or false = nowhere, true = anywhere, a zone {"rows": [first, last], "areas": [names]} = a hex in
## the offset rows (inclusive) or in a named shallow area.
static func permitted(scenario: Dictionary, hex: Vector2i) -> bool:
	var rule = scenario.get("anchoring", false)
	if rule is bool:
		return rule
	if not (rule is Dictionary):
		return false
	var rows = rule.get("rows", null)
	if _valid_rows(rows):
		var row := TerrainMap.axial_to_offset(hex).y
		if row >= int(rows[0]) and row <= int(rows[1]):
			return true
	var names = rule.get("areas", [])
	if names is Array:
		var area := TerrainMap.of(scenario).area_at(hex)
		if area != null and names.has(area.name):
			return true
	return false


## Problems with the scenario's `anchoring` entry and the ships' starting `anchor`s (spec §7).
## Every message starts "Anchoring: ".
static func scenario_errors(scenario: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var terrain := TerrainMap.of(scenario)
	if scenario.has("anchoring"):
		var rule = scenario["anchoring"]
		if rule is Dictionary:
			if not rule.has("rows") and not rule.has("areas"):
				errors.append("Anchoring: a zone needs rows or areas")
			if rule.has("rows") and not _valid_rows(rule["rows"]):
				errors.append("Anchoring: rows must be [first, last]")
			if rule.has("areas"):
				var names = rule["areas"]
				if not (names is Array):
					errors.append("Anchoring: areas must be a list of area names")
				else:
					var known: Array[String] = []
					for a in terrain.areas:
						known.append(a.name)
					for n in names:
						if not known.has(str(n)):
							errors.append("Anchoring: unknown area %s" % str(n))
		elif not (rule is bool):
			errors.append("Anchoring: anchoring must be true, false or a zone")
	for entry in scenario.get("ships", []):
		if not (entry is Dictionary) or not entry.has("anchor"):
			continue
		var id := str(entry.get("id", ""))
		var a = entry["anchor"]
		if not (a is Dictionary):
			errors.append("Anchoring: ship '%s' anchor end must be bow or stern" % id)
			continue
		if not ["bow", "stern"].has(str(a.get("end", ""))):
			errors.append("Anchoring: ship '%s' anchor end must be bow or stern" % id)
		if a.has("cable"):
			var cable = a["cable"]
			if not _integral(cable) or int(cable) < 1 or int(cable) > 4:
				errors.append("Anchoring: ship '%s' cable must be 1-4" % id)
		if a.has("hex"):
			var h = a["hex"]
			if not (h is Array) or h.size() != 2 or not _integral(h[0]) or not _integral(h[1]) \
					or not terrain.in_bounds(Vector2i(int(h[0]), int(h[1]))):
				errors.append("Anchoring: ship '%s' anchor is off the map" % id)
	return errors


## The hex the ready anchor would drop in (13.C.2): the stern for a stern anchor, else the bow.
static func drop_hex(ship: ShipState) -> Vector2i:
	if ship.anchor_ready == "stern":
		return ship.stern_hex()
	return ship.hex_position


## The facing a normally anchored ship swings to (13.A.3, 13.C.4): AB into the wind, AS downwind.
static func proper_facing(end: String, wind_dir: int) -> int:
	return downwind(wind_dir) if end == "stern" else posmod(wind_dir, 6)


## The direction the wind blows toward.
static func downwind(wind_dir: int) -> int:
	return (wind_dir + 3) % 6


## The ship's hexes [bow, stern] riding to an anchor at `anchor_hex` (spec §1; Diagram 25, 13.C.6):
## the anchored end `cable` hexes downwind of the anchor, the rest of the hull by `facing`.
static func footprint(anchor_hex: Vector2i, end: String, cable: int, facing: int, wind_dir: int) -> Array[Vector2i]:
	var end_hex: Vector2i = anchor_hex + cable * HexGrid.DIRECTIONS[downwind(wind_dir)]
	if end == "stern":
		return [end_hex + HexGrid.DIRECTIONS[posmod(facing, 6)], end_hex]
	return [end_hex, HexGrid.stern_of(end_hex, facing)]


## A spring turn of 60 degrees (13.D.2-3), `direction` -1 port or +1 starboard: {"facing", "hexes":
## [bow, stern]}. Anchored by the bow the ship pivots on her bow; by the stern on her stern.
static func spring_turn(ship: ShipState, direction: int) -> Dictionary:
	var facing := posmod(ship.facing + direction, 6)
	var hexes: Array[Vector2i] = []
	if str(ship.anchor.get("end", "bow")) == "stern":
		var stern := ship.stern_hex()
		hexes = [stern + HexGrid.DIRECTIONS[facing], stern]
	else:
		hexes = [ship.hex_position, HexGrid.stern_of(ship.hex_position, facing)]
	return {"facing": facing, "hexes": hexes}


## 13.C.4: a ship facing exactly away from her proper facing, not yet swinging, rolls a d6 for the way.
static func needs_swing_roll(facing: int, proper: int, swing_dir: int) -> bool:
	return swing_dir == 0 and posmod(proper - facing, 6) == 3


## One 60-degree swing toward the proper facing (13.C.4): {"facing", "swing_dir"}. A ship already
## swinging keeps her direction; otherwise the fewest steps, and when exactly opposite the d6 `roll`
## (1-3 port, 4-6 starboard). `swing_dir` is 0 once the proper facing is reached.
static func swing_step(facing: int, proper: int, swing_dir: int, roll: int) -> Dictionary:
	if facing == proper:
		return {"facing": facing, "swing_dir": 0}
	var dir := swing_dir
	if dir == 0:
		var diff := posmod(proper - facing, 6)
		if diff <= 2:
			dir = 1
		elif diff >= 4:
			dir = -1
		else:
			dir = -1 if roll <= 3 else 1
	var new_facing := posmod(facing + dir, 6)
	return {"facing": new_facing, "swing_dir": 0 if new_facing == proper else dir}


## What moving an anchored ship from `old_hexes` to `new_hexes` (bow first) meets (spec §4):
## {"result": "clear"|"edge"|"land"|"ship", "blocker": ship id or "", "shallow_bow": bool}.
## `others` maps hex -> ship id. An anchored ship never leaves the map: any new hex off the board,
## and any boundary crossing MapRules.forced_move finds (blocked, lost or escape), is "edge".
## `shallow_bow` (clear only): the bow enters a new hex, and that hex is shallow (13.G.2a, 13.G.4b,
## as in drift), even when it was her own stern hex. A bow that stays where it was, as in a swing
## about the anchored bow, rolls nothing.
static func forced_check(scenario: Dictionary, old_hexes: Array[Vector2i], new_hexes: Array[Vector2i],
		others: Dictionary) -> Dictionary:
	var terrain := TerrainMap.of(scenario)
	for hex in new_hexes:
		if not terrain.in_bounds(hex):
			return _forced("edge")
	# MapRules.forced_move checks each old -> new pair for a boundary side; pairs that are not
	# adjacent (a swing and a drift together) cross none, and the in_bounds test above covers the edge.
	# The ship only matters there for escape, which is collapsed to "edge" anyway.
	var r := MapRules.forced_move(scenario, ShipState.new(), old_hexes, new_hexes, others, 0)
	match str(r["result"]):
		"edge", "lost", "escape":
			return _forced("edge")
		"land":
			return _forced("land")
		"ship":
			return _forced("ship", str(r["blocker"]))
	var shallow := bool(r["shallow_bow"]) and not new_hexes.is_empty() \
		and (old_hexes.is_empty() or new_hexes[0] != old_hexes[0])
	return {"result": "clear", "blocker": "", "shallow_bow": shallow}


## The crew task an Automatic anchor order asks for (spec §3): {} or {"code", "params"}.
## prepare_springs prepares the springs of the end ready or anchored (the bow when neither).
static func order_task(ship: ShipState, order: String) -> Dictionary:
	if _ORDER_CODES.has(order):
		return {"code": _ORDER_CODES[order], "params": {}}
	match order:
		"prepare_springs":
			var stern := ship.anchor_ready == "stern" \
				or (ship.is_anchored() and str(ship.anchor.get("end", "bow")) == "stern")
			return {"code": "PSS" if stern else "PBS", "params": {}}
		"turn_port":
			return {"code": "HS", "params": {"turn": "port"}}
		"turn_starboard":
			return {"code": "HS", "params": {"turn": "starboard"}}
	return {}


## "" when `code` may be plotted for `ship`, else the reason (spec §3). `ctx`: wind_speed (int),
## anchoring_here (bool: permitted at the drop hex), plotted_mps (int), final (bool: End Planning or
## resolution, when an A with MPs plotted is erased). `plan_codes`: the other anchoring codes
## already accepted in the plan.
static func refusal(ship: ShipState, code: String, params: Dictionary, ctx: Dictionary, plan_codes: Array) -> String:
	if not ship.crew_can_act():
		return R_CREW
	if code == "HS" and not ["port", "starboard"].has(str(params.get("turn", ""))):
		return R_HS_PARAMS
	if plan_codes.has(code):
		return "One section is enough for %s." % code
	var wind := int(ctx.get("wind_speed", 0))
	match code:
		"PBA", "PSA":
			if ship.is_anchored():
				return R_ANCHORED
			if ship.anchorings_used >= MAX_ANCHORINGS:
				return R_TWICE
			if ship.anchor_ready != "":
				return R_READY
			var other := "PSA" if code == "PBA" else "PBA"
			if not ship.tasks_with(other).is_empty() or plan_codes.has(other):
				return R_ONE_ANCHOR
		"PBS", "PSS":
			var end := "bow" if code == "PBS" else "stern"
			if ship.springs_ready or ship.has_springs():
				return R_SPRINGS_READY
			var anchored_here := ship.is_anchored() and str(ship.anchor.get("end", "bow")) == end
			if ship.anchor_ready != end and not anchored_here:
				return "Prepare the %s anchor first (13.B.3)." % end
			if not ship.tasks_with("PSS" if code == "PBS" else "PBS").is_empty():
				return R_ONE_ANCHOR
		"A":
			if ship.is_anchored():
				return R_ANCHORED
			if ship.anchor_ready == "":
				return R_PREPARE_FIRST
			if ship.anchorings_used >= MAX_ANCHORINGS:
				return R_TWICE
			if not bool(ctx.get("anchoring_here", false)):
				return R_NOT_HERE
			if bool(ctx.get("final", false)) and int(ctx.get("plotted_mps", 0)) > 0:
				return R_MPS
		"AX", "VO", "VI", "HS":
			if not ship.is_anchored():
				return R_NOT_ANCHORED
			return _anchored_refusal(ship, code, wind, plan_codes)
		_:
			return "Unknown anchoring task %s" % code
	return ""


## The overlay note on a ship's anchor (spec §13), e.g. "Anchored by the bow, 2 hexes of cable,
## springs rigged." or "Bow anchor ready."; "" when there is nothing to say.
static func status_text(ship: ShipState) -> String:
	if ship.is_anchored():
		var cable := int(ship.anchor.get("cable", 0))
		var text := "Anchored by the %s, %d %s of cable" % [str(ship.anchor.get("end", "bow")), cable,
			"hex" if cable == 1 else "hexes"]
		if ship.has_springs():
			text += ", springs rigged"
		return text + "."
	var parts: Array[String] = []
	if ship.anchor_ready != "":
		parts.append("%s anchor ready." % ship.anchor_ready.capitalize())
	if ship.springs_ready:
		parts.append("Springs ready.")
	return " ".join(parts)


static func _anchored_refusal(ship: ShipState, code: String, wind: int, plan_codes: Array) -> String:
	var veered := int(ship.anchor.get("veered", 0))
	match code:
		"AX":
			if plan_codes.has("HS") or plan_codes.has("VO") or plan_codes.has("VI"):
				return R_CUT
		"VO":
			if wind == 0:
				return R_VO_CALM
			if veered >= MAX_VEERED:
				return R_VO_MAX
			if ship.is_linked():
				return R_VO_LINKED
			if plan_codes.has("HS"):
				return R_VO_TURN
			if plan_codes.has("AX"):
				return R_CUT
			if plan_codes.has("VI"):
				return R_VEER_BOTH
		"VI":
			if veered <= 0:
				return R_VI_NONE
			if plan_codes.has("HS"):
				return R_VI_TURN
			if plan_codes.has("AX"):
				return R_CUT
			if plan_codes.has("VO"):
				return R_VEER_BOTH
		"HS":
			if not ship.has_springs():
				return R_HS_NO_SPRINGS
			if wind == 0:
				return R_HS_CALM
			if ship.is_linked():
				return R_HS_LINKED
			if plan_codes.has("VO"):
				return R_VO_TURN
			if plan_codes.has("VI"):
				return R_VI_TURN
			if plan_codes.has("AX"):
				return R_CUT
	return ""


static func _forced(result: String, blocker: String = "") -> Dictionary:
	return {"result": result, "blocker": blocker, "shallow_bow": false}


static func _integral(v) -> bool:
	return v is int or (v is float and v == floorf(v))


static func _valid_rows(rows) -> bool:
	return rows is Array and rows.size() == 2 and _integral(rows[0]) and _integral(rows[1]) \
		and int(rows[0]) <= int(rows[1])
