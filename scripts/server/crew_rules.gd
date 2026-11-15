class_name CrewRules
extends RefCounted
## CrewRules - which tasks a ship's crew sections may be plotted to, as pure static functions
## (no mutation, no dice). The server (CrewTaskController), the AI (through CrewAuto) and the
## planning UI all use these, so displayed and enforced rules are the same code (crew-tasks spec
## §3.2).
##
## A plan is {"assignments": {section:int -> {"code": String, "params": Dictionary}},
## "orders": {"sail_target": String}}. A section absent from assignments is unplotted: a sailor
## section serves the guns, the marines are at marine fire (4.B.4).
## - 4.B.2: one task per section per g-t (assignments are keyed by section).
## - 4.A.3 / 5.F.9: a sail change in progress keeps its sections (locked); forced tasks too.
## - 4.B.4: each sailor section not serving the guns is -3 on gunfire (sections_firing_modifier).

const STATION_GUNS := "guns"
const STATION_MARINE_FIRE := "marine_fire"
const STATION_SAILS := "sails"
## Codes whose sections are locked once begun (5.F.9: a sail change must be completed).
const LOCKED_CODES: Array[String] = ["SAIL"]
## Critical effects whose 8.D.5 fix roll the marines would spoil if busy (+1, "marines not avail.").
const MARINE_HOLD_EFFECTS: Array[String] = [
	"broadside_obscured", "braces_cut", "lines_jammed", "rudder_jammed", "signal_halyards_cut",
]
## Marines-held-back reasons (spec §3.3), shown on the Marine fire station.
const HOLD_FIRE := "fire aboard"
const HOLD_EFFECT := "damage to fix"
const HOLD_FOULED := "fouled"
const HOLD_ENEMY := "enemy alongside"


## Facts about the ship's situation the rules read (spec §3.2). Pure read of game_state.
## ma0_turn_plotted is for the T task (phase 2) and is always false for now.
static func context(game_state: Node, ship: ShipState) -> Dictionary:
	var nearest := -1
	if game_state != null and game_state.get("fire_geometry") != null:
		for other: ShipState in game_state.get_all_ships():
			if other.player_id == ship.player_id or other.is_out_of_play():
				continue
			var r: int = game_state.fire_geometry.range_between(ship.occupied_hexes(), other.occupied_hexes())
			if r >= 0 and (nearest < 0 or r < nearest):
				nearest = r
	var turn = game_state.get("current_turn") if game_state != null else null
	return {
		"ma0_turn_plotted": false,
		"plotted_mps": (ship.plotted_actions.get("movement", []) as Array).size(),
		"nearest_enemy": nearest,
		"enemy_in_gun_range": nearest >= 0 and nearest <= FireRules.MAX_RANGE,
		"enemy_adjacent": nearest == 1,
		"turn": int(turn) if turn != null else 0,
	}


## The plan stored on the ship (plotted_actions), as a plan dictionary (copies).
static func plan_of(ship: ShipState) -> Dictionary:
	var assignments := {}
	var stored = ship.plotted_actions.get("crew_assignments", {})
	if stored is Dictionary:
		for section in stored:
			assignments[int(section)] = (stored[section] as Dictionary).duplicate(true)
	var orders := {"sail_target": ""}
	var stored_orders = ship.plotted_actions.get("crew_orders", {})
	if stored_orders is Dictionary:
		orders.merge(stored_orders.duplicate(true), true)
	return {"assignments": assignments, "orders": orders}


## Sections held by a task in progress that cannot be moved: section -> {"code", "params"}.
static func locked_sections(ship: ShipState) -> Dictionary:
	var result := {}
	for task in ship.crew_tasks:
		if task.get("ended", "") != "":
			continue
		if not (bool(task.get("forced", false)) or LOCKED_CODES.has(str(task.get("code", "")))):
			continue
		for section in task.get("sections", []):
			if ship.section_alive(int(section)):
				result[int(section)] = {"code": str(task["code"]),
					"params": (task.get("params", {}) as Dictionary).duplicate(true)}
	return result


## Why the marines are kept free (spec §3.3), or "": a fire aboard, a fixable critical effect,
## fouled, or an enemy ship adjacent. Each is a roll or a use the busy marines would spoil.
static func marines_held_back(ship: ShipState, ctx: Dictionary) -> String:
	if ship.is_burning():
		return HOLD_FIRE
	for effect in ship.critical_effects:
		if MARINE_HOLD_EFFECTS.has(str(effect.get("id", ""))):
			return HOLD_EFFECT
	if ship.fouled_with != "":
		return HOLD_FOULED
	if bool(ctx.get("enemy_adjacent", false)):
		return HOLD_ENEMY
	return ""


## Worker order (spec §3.3): M (unless held back), then S4, S3, S2, S1; only sections with boxes
## that are not in `taken`.
static func worker_order(ship: ShipState, ctx: Dictionary, taken: Dictionary) -> Array[int]:
	var order: Array[int] = []
	var candidates: Array[int] = [ShipState.MARINES, 3, 2, 1, 0]
	for section in candidates:
		if section == ShipState.MARINES and marines_held_back(ship, ctx) != "":
			continue
		if ship.section_alive(section) and not taken.has(section):
			order.append(section)
	return order


## Sections the ordered sail change needs (0 when none is ordered or one is in progress).
static func sail_sections_needed(ship: ShipState, orders: Dictionary) -> int:
	var target := str(orders.get("sail_target", ""))
	if target == "" or ship.has_sail_change():
		return 0
	return SailController.sections_needed(ship, target)


## The carry-over defaults (spec §0.1 Q-UX2): tasks in progress stay, everyone else at the
## default stations; no orders.
static func default_plan(ship: ShipState, _ctx: Dictionary) -> Dictionary:
	var assignments := {}
	for task in ship.crew_tasks:
		if task.get("ended", "") != "":
			continue
		for section in task.get("sections", []):
			if ship.section_alive(int(section)):
				assignments[int(section)] = {"code": str(task["code"]),
					"params": (task.get("params", {}) as Dictionary).duplicate(true)}
	return {"assignments": assignments, "orders": {"sail_target": ""}}


## "" when `section` may go to `station_id` in `plan`, else the reason (quoting the rule).
static func refusal(ship: ShipState, plan: Dictionary, _ctx: Dictionary, section: int, station_id: String) -> String:
	var name: String = ShipState.SECTION_NAMES[section] if section >= 0 and section <= ShipState.MARINES else "?"
	if section < 0 or section > ShipState.MARINES:
		return "Unknown crew section"
	if not ship.section_alive(section):
		return "%s is lost (4.B.3)" % name
	if ship.crew_auto:
		return "Automatic crew is on: the ship's officers place the sections. Turn it off to place them yourself."
	var locked := locked_sections(ship)
	if locked.has(section):
		var code: String = locked[section]["code"]
		if code == SailController.CODE:
			return "%s is altering sail. Must be completed (5.F.9)." % name
		return "%s cannot be moved." % name
	match station_id:
		STATION_GUNS:
			if section == ShipState.MARINES:
				return "Only sailor sections serve the guns. Marines fire muskets instead."
			return ""
		STATION_MARINE_FIRE:
			if section != ShipState.MARINES:
				return "Only the marine section gives marine fire."
			return ""
		STATION_SAILS:
			var orders: Dictionary = plan.get("orders", {})
			var target := str(orders.get("sail_target", ""))
			if ship.has_critical("lines_jammed"):
				return "Lines jammed: no sail changes (5.F.9c)"
			if target == "":
				return "Order a sail change first"
			var needed := SailController.sections_needed(ship, target)
			var on_sails := 0
			for s in plan.get("assignments", {}):
				if int(s) != section and plan["assignments"][s].get("code", "") == SailController.CODE:
					on_sails += 1
			if on_sails >= needed:
				return "Sails aloft is full (%d %s)." % [needed, "section" if needed == 1 else "sections"]
			return ""
	return "Unknown station"


## The plan with `section` moved to `station_id` (one task per section, 4.B.2: the new station
## replaces the old). Unchanged when refused.
static func assign(ship: ShipState, plan: Dictionary, ctx: Dictionary, section: int, station_id: String) -> Dictionary:
	var result := plan.duplicate(true)
	if not result.has("assignments"):
		result["assignments"] = {}
	if not result.has("orders"):
		result["orders"] = {"sail_target": ""}
	if refusal(ship, plan, ctx, section, station_id) != "":
		return result
	match station_id:
		STATION_GUNS, STATION_MARINE_FIRE:
			result["assignments"].erase(section)
		STATION_SAILS:
			result["assignments"][section] = {"code": SailController.CODE,
				"params": {"target": str(result["orders"].get("sail_target", ""))}}
	return result


## The one place a plan is made legal (spec §3.2). Never refuses. Returns
## {"assignments", "orders", "auto": [sections placed by the rules], "warnings": [String],
## "dropped": [sections whose assignment was removed]}.
static func normalize(ship: ShipState, plan: Dictionary, ctx: Dictionary) -> Dictionary:
	var orders := {"sail_target": ""}
	orders.merge((plan.get("orders", {}) as Dictionary).duplicate(true), true)
	var assignments := {}
	for section in plan.get("assignments", {}):
		assignments[int(section)] = (plan["assignments"][section] as Dictionary).duplicate(true)
	var result := {"assignments": {}, "orders": orders, "auto": [], "warnings": [], "dropped": []}
	if ship.is_out_of_play():
		# A struck ship keeps only firefighting (phase 4); a destroyed ship has no crew tasks.
		result["orders"] = {"sail_target": ""}
		result["dropped"] = assignments.keys()
		return result
	# (1) eliminated sections
	for section in assignments.keys():
		if not ship.section_alive(section):
			assignments.erase(section)
			result["dropped"].append(section)
	# (2) locked sections
	var locked := locked_sections(ship)
	for section in locked:
		assignments[section] = locked[section]
	if ship.crew_auto:
		# (3) Automatic
		var auto := CrewAuto.allocate(ship, orders, ctx)
		result["assignments"] = auto["assignments"]
		result["auto"] = auto["auto"]
		return result
	# (4) manual: drop what the rules refuse
	var sail_target := str(orders.get("sail_target", ""))
	var on_sails := 0
	var sections: Array = assignments.keys()
	sections.sort()
	for section in sections:
		if locked.has(section):
			continue
		var entry: Dictionary = assignments[section]
		var code := str(entry.get("code", ""))
		var why := ""
		if code == SailController.CODE:
			if ship.has_critical("lines_jammed"):
				why = "Lines jammed: no sail changes (5.F.9c)"
			elif sail_target == "" or ship.has_sail_change():
				why = "No sail change is ordered"
			elif on_sails >= SailController.sections_needed(ship, sail_target):
				why = "Sails aloft is full"
			else:
				on_sails += 1
				entry["params"] = {"target": sail_target}
		else:
			var live := ship.task_of(section)
			if live.is_empty() or str(live.get("code", "")) != code:
				why = "Unknown task %s" % code
		if why != "":
			assignments.erase(section)
			result["dropped"].append(section)
			result["warnings"].append("%s: %s" % [ShipState.SECTION_NAMES[section], why])
	var needed := sail_sections_needed(ship, orders)
	if needed > 0 and on_sails < needed:
		result["warnings"].append("Needs %d sections: %d placed. The change will not start." % [needed, on_sails])
	result["assignments"] = assignments
	return result


## The Guns readout (spec §4.6): sailor sections the plan leaves at the guns and their modifier.
## {"sections": n, "modifier": int or null (cannot fire), "missing": [{"section", "why"}]}.
static func guns_preview(ship: ShipState, plan: Dictionary) -> Dictionary:
	var assignments: Dictionary = plan.get("assignments", {})
	var able := 0
	var missing: Array = []
	for section in range(ShipState.SAILOR_SECTIONS):
		if not ship.section_alive(section):
			missing.append({"section": section, "why": "lost"})
		elif assignments.has(section):
			missing.append({"section": section, "why": str(assignments[section].get("code", ""))})
		else:
			able += 1
	var modifier = null
	if able > 0:
		modifier = DataManager.combat_tables.sections_firing_modifier(able)
	return {"sections": able, "modifier": modifier, "missing": missing}
