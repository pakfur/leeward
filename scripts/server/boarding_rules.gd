class_name BoardingRules
extends RefCounted
## BoardingRules - which boarding tasks a crew section may be plotted to, as pure static functions
## (Close Action 1997, 10.A-10.C, 10.E.4, 4.B.1; boarding spec §2.4), like FireRules. The server
## (CrewRules.normalize, CrewAuto rule A2b, BoardingController) and the crew overlay all use these,
## so displayed and enforced rules are the same code. No mutation, no dice.
##
## Codes (ShipState.BOARDING_CODES), one section per task, params {"section": s} plus "target" for BA:
##   FB form boarders (one g-t; the section can defend at once and board from the next g-t, 10.B.2);
##   BR boarders ready (every later g-t until BA or BD, 10.B.3);
##   BA boarders away (10.C.1: readied sections only, at most two new ones a g-t, sailors in
##      numerical order, never S4; all of them after a repulse, 10.E.4);
##   BD disband (one g-t, 10.B.5).
## While a section is engaged in a boarding action its task is forced and carries params "action"
## and "enemy" (10.E.1).
##
## ctx keys read (CrewRules.context): "board_targets" [{id, name}] (enemies fouled or grappled to the
## ship when PLANNING began that may be boarded, 10.A.2), "linked_at_plot" [ids], "counter_board"
## {enemy_id: [sections]} (10.E.4), "ship_names" {id: name}.

const FB := "FB"
const BR := "BR"
const BA := "BA"
const BD := "BD"
const CODES: Array[String] = ["FB", "BR", "BA", "BD"]
## Crews that may not board (10.A.2; spec 0.4 #3: they may still form boarders to defend).
const NO_BOARD_QUALITIES: Array[String] = ["F", "G"]
## Most sections that may go away for the first time in one g-t (10.C.1).
const MAX_NEW_BA := 2
## S4: may FB and BR but never BA (10.C.1).
const MINIMUM_CREW_SECTION := 3

const FIRE_REFUSAL := "A ship on fire can neither board nor be boarded (10.A.2)."


static func is_code(code: String) -> bool:
	return CODES.has(code)


## The plan entry for a boarding task.
static func entry(code: String, section: int, target: String = "") -> Dictionary:
	var params := {"section": section}
	if code == BA:
		params["target"] = target
	return {"code": code, "params": params}


static func _name(section: int) -> String:
	return ShipState.SECTION_NAMES[section] if section >= 0 and section <= ShipState.MARINES else "?"


static func _ship_name(ctx: Dictionary, ship_id: String) -> String:
	return str((ctx.get("ship_names", {}) as Dictionary).get(ship_id, ship_id))


## Section `k`'s task is forced (RO, an engaged boarding action) or a boarding task in `assignments`
## or on the ship: it does not hold up a higher sailor section forming boarders (4.B.1).
static func _clears_order(ship: ShipState, assignments: Dictionary, k: int) -> bool:
	var e: Dictionary = assignments.get(k, {})
	if is_code(str(e.get("code", ""))) and str(e.get("code", "")) != BD:
		return true
	var task := ship.task_of(k)
	if bool(task.get("forced", false)):
		return true
	return ship.is_readied(k) or ship.boarding_action_of(k) >= 0


## "" when `section` may be plotted to boarding task `code` (target `target` for BA) in a plan with
## `assignments`, else the reason, quoting the rule.
static func task_error(ship: ShipState, assignments: Dictionary, ctx: Dictionary, section: int,
		code: String, target: String = "") -> String:
	var name := _name(section)
	if section < 0 or section > ShipState.MARINES:
		return "Unknown crew section"
	if not ship.crew_can_act():
		if ship.is_captured():
			return "%s: the prize crew is not yet aboard (10.G.7)." % ship.ship_name
		return "%s cannot form boarders: the ship is out of the fight." % ship.ship_name
	if not ship.section_alive(section):
		return "%s is lost (4.B.3)" % name
	match code:
		FB:
			if ship.is_burning():
				return FIRE_REFUSAL
			if ship.is_readied(section):
				return ""
			if section < ShipState.SAILOR_SECTIONS:
				for k in range(section):
					if ship.section_alive(k) and not _clears_order(ship, assignments, k):
						return "Boarders come from the lowest-numbered sailor sections first: send %s before %s (4.B.1)." % [
							_name(k), name]
			return ""
		BR:
			if ship.is_burning():
				return FIRE_REFUSAL
			if not ship.is_readied(section):
				return "%s has not formed boarders (10.B.3)." % name
			return ""
		BD:
			if not ship.is_readied(section):
				return "%s is not a readied boarder (10.B.5)." % name
			return ""
		BA:
			return _ba_error(ship, assignments, ctx, section, target)
	return "Unknown boarding task %s" % code


static func _ba_error(ship: ShipState, assignments: Dictionary, ctx: Dictionary, section: int, target: String) -> String:
	var name := _name(section)
	if section == MINIMUM_CREW_SECTION:
		return "S4 never boards: the minimum crew (10.C.1)."
	if not ship.is_readied(section):
		if str(assignments.get(section, {}).get("code", "")) == FB or str(ship.boarding_task(section).get("code", "")) == FB:
			return "%s formed this turn: it can board next turn (10.B.2)." % name
		return "%s must form boarders first (10.B.2)." % name
	if NO_BOARD_QUALITIES.has(ship.crew_quality):
		return "A crew at CQ %s may not board (10.A.2)." % ship.crew_quality
	if ship.is_burning():
		return FIRE_REFUSAL
	var why := target_error(ship, ctx, target)
	if why != "":
		return why
	var counter: Array = (ctx.get("counter_board", {}) as Dictionary).get(target, [])
	if not counter.has(section):
		var new_ba := 0
		for other in assignments:
			if int(other) == section:
				continue
			var e: Dictionary = assignments[other]
			if str(e.get("code", "")) == BA and not counter.has(int(other)) \
					and ship.boarding_action_of(int(other)) < 0:
				new_ba += 1
		if new_ba >= MAX_NEW_BA:
			return "Only two sections may go in one turn (10.C.1)."
	if section < ShipState.SAILOR_SECTIONS:
		for k in range(section):
			if not ship.section_alive(k) or (bool(ship.task_of(k).get("forced", false)) and ship.boarding_action_of(k) < 0):
				continue  # lost, or held by RO: not in the order
			var e: Dictionary = assignments.get(k, {})
			var away := str(e.get("code", "")) == BA and str(e.get("params", {}).get("target", "")) == target
			if not away and ship.boarding_action_of(k) < 0:
				return "Boarders go in numerical order: %s before %s (10.C.1)." % [_name(k), name]
	return ""


## "" when `ship` may board `target_id` now (10.A.2-3), else the reason. Reads ctx.board_targets
## (enemies linked when PLANNING began, CrewRules.context).
static func target_error(ship: ShipState, ctx: Dictionary, target_id: String) -> String:
	if target_id == "":
		return "Choose the ship to board."
	for t in ctx.get("board_targets", []):
		if str(t.get("id", "")) == target_id:
			return ""
	var why := str((ctx.get("board_refusals", {}) as Dictionary).get(target_id, ""))
	if why != "":
		return why
	return "Boarding needs an enemy fouled or grappled to %s at the start of the turn (10.A.2)." % ship.ship_name


## Why `ship` may not board `target` (10.A.2-3) given the ships linked to it when PLANNING began, or "".
static func boardable_error(ship: ShipState, target: ShipState, linked_at_plot: Array) -> String:
	if target == null:
		return "There is no such ship."
	if target.side == ship.side:
		return "Friendly ships may not board each other (10.A.2)."
	if target.is_destroyed():
		return "%s has been destroyed." % target.ship_name
	if target.is_burning():
		return FIRE_REFUSAL
	if not linked_at_plot.has(target.ship_id):
		return "Boarding needs an enemy fouled or grappled to %s at the start of the turn (10.A.2)." % ship.ship_name
	if not target.can_be_boarded():
		return "%s cannot be boarded." % target.ship_name
	return ""


## 10.D.7: the Crew Loss row for gunfire and marine fire against `ship`. With boarding tasks plotted
## (FB, BR, BA or engaged): "gunfire_at_hull" when only sailor sections are on them, else "other";
## with none, `default_cause`.
static func crew_loss_cause(ship: ShipState, default_cause: String) -> String:
	if ship == null or not ship.has_boarders():
		return default_cause
	var marines := str(ship.boarding_task(ShipState.MARINES).get("code", ""))
	return "other" if ShipState.BOARDER_CODES.has(marines) else "gunfire_at_hull"


## The prize crew formed into sections of the captured ship's original sizes (10.G.7): sailors fill
## from S4 down, marines go to M up to its original size and any more fill sailor sections.
## Returns {"crew_count": [4 ints], "marine_count": int}.
static func form_prize_sections(sizes: Array, marine_size: int, sailors: int, marines: int) -> Dictionary:
	var crew: Array[int] = [0, 0, 0, 0]
	var m := mini(marines, maxi(0, marine_size))
	var left := sailors + (marines - m)
	for i in range(ShipState.SAILOR_SECTIONS - 1, -1, -1):
		var cap := int(sizes[i]) if i < sizes.size() else 0
		var take := mini(cap, left)
		crew[i] = take
		left -= take
	if left > 0:
		crew[ShipState.SAILOR_SECTIONS - 1] += left  # more than the hull held: the overflow joins S4
	return {"crew_count": crew, "marine_count": m}


# --- Plan normalisation (manual crew) and rule A2b (Automatic) ---

## Manual crew: makes the boarding entries of `assignments` legal (CrewRules.normalize step 4).
## A readied section plotted to anything but BR/BA/BD stands down (BD, 10.B.5); FB on a readied
## section is BR; BR on an unready section is FB; an illegal BA stays ready (BR); an illegal FB is
## dropped. Sections in `locked` are left alone. Returns {"assignments", "warnings", "dropped", "notes"}.
static func normalize_manual(ship: ShipState, assignments_in: Dictionary, ctx: Dictionary, locked: Dictionary) -> Dictionary:
	var assignments := assignments_in.duplicate(true)
	var warnings: Array = []
	var dropped: Array = []
	var notes: Array = []
	var done := {}
	for section in [ShipState.MARINES, 0, 1, 2, 3]:
		if locked.has(section) or not ship.section_alive(section):
			continue
		var e: Dictionary = assignments.get(section, {})
		var code := str(e.get("code", ""))
		var readied := ship.is_readied(section)
		var name := _name(section)
		if readied:
			if code == FB or code == BR:
				assignments[section] = entry(BR, section)
			elif code == BA:
				var target := str(e.get("params", {}).get("target", ""))
				var visible := {}
				for k in done:
					visible[k] = assignments.get(k, {})
				visible[section] = e
				var why := _ba_error(ship, visible, ctx, section, target)
				if why != "":
					assignments[section] = entry(BR, section)
					warnings.append("%s: %s" % [name, why])
				else:
					assignments[section] = entry(BA, section, target)
			elif code == BD:
				assignments[section] = entry(BD, section)
			elif code == CrewRules.CODE_FF and ship.is_burning():
				pass  # a fire disbands readied boarders (8.E.2); the fire party stands
			else:
				assignments[section] = entry(BD, section)
				notes.append("%s stands down this turn and is free next turn (10.B.5)." % name)
		elif is_code(code):
			if code == BD:
				assignments.erase(section)
			else:
				var why := task_error(ship, assignments, ctx, section, FB)
				if why != "":
					assignments.erase(section)
					dropped.append(section)
					warnings.append("%s: %s" % [name, why])
				else:
					if code == BA:
						warnings.append("%s: %s" % [name, _ba_error(ship, assignments, ctx, section,
							str(e.get("params", {}).get("target", "")))])
					assignments[section] = entry(FB, section)
		done[section] = true
	return {"assignments": assignments, "warnings": warnings, "dropped": dropped, "notes": notes}


## Rule A2b (boarding spec §2.4 #6), between CrewAuto's A2 and A3: the boarding order.
##   "ready": the marines and the lowest-numbered sailor section with boxes form (FB) or stay ready
##     (BR); other readied sections stay ready;
##   "board:<id>": as "ready", and the readied ones among those two go away (BA) at <id>; after a
##     repulse every section that defended (not S4) goes (10.E.4);
##   "stand_down" or "": readied sections disband (BD).
## Sections already in `taken` (locked, fires, tasks in progress) are not moved. Returns the new taken.
static func auto_assign(ship: ShipState, orders: Dictionary, ctx: Dictionary, taken_in: Dictionary) -> Dictionary:
	var taken := taken_in.duplicate(true)
	if not ship.crew_can_act():
		return taken
	var order := str(orders.get("boarding", ""))
	var readied: Array[int] = []
	for s in range(ShipState.MARINES + 1):
		if ship.is_readied(s) and not taken.has(s):
			readied.append(s)
	if order != "ready" and not order.begins_with("board:"):
		for s in readied:
			taken[s] = entry(BD, s)
		return taken
	if ship.is_burning():
		return taken  # a fire disbands boarders (8.E.2) and none may form (10.A.2)
	var picks: Array[int] = []
	if ship.section_alive(ShipState.MARINES) and not taken.has(ShipState.MARINES):
		picks.append(ShipState.MARINES)
	for k in range(ShipState.SAILOR_SECTIONS):
		if not ship.section_alive(k):
			continue
		if taken.has(k):
			var code := str(taken[k].get("code", ""))
			if is_code(code):
				break  # this section is already boarding: no new sailors
			if bool(ship.task_of(k).get("forced", false)):
				continue  # RO: out of the order
			break  # busy on a task in progress or a fire: no sailor forms behind it (4.B.1)
		picks.append(k)
		break
	for s in picks:
		if ship.is_readied(s):
			taken[s] = entry(BR, s)
		elif task_error(ship, taken, ctx, s, FB) == "":
			taken[s] = entry(FB, s)
	for s in readied:
		if not taken.has(s):
			taken[s] = entry(BR, s)
	if order.begins_with("board:"):
		var target := order.trim_prefix("board:")
		var counter: Array = (ctx.get("counter_board", {}) as Dictionary).get(target, [])
		var goers: Array[int] = []
		if not counter.is_empty():
			for s in [ShipState.MARINES, 0, 1, 2]:
				if counter.has(s) and ship.is_readied(s):
					goers.append(s)
		else:
			for s in [ShipState.MARINES, 0, 1, 2]:
				if picks.has(s) and ship.is_readied(s):
					goers.append(s)
		for s in goers:
			if _ba_error(ship, taken, ctx, s, target) == "":
				taken[s] = entry(BA, s, target)
	return taken


## Manual crew: the plan with the boarding order set (the Boarders station's picker, spec §4.2).
## "board:<id>": the readied marines and the lowest readied sailor section go (two at most; every
## section that defended after a repulse, 10.E.4); "ready": BA entries go back to BR; "stand_down":
## readied sections disband. Automatic: only the order changes (rule A2b places the sections).
static func with_order(ship: ShipState, plan: Dictionary, ctx: Dictionary, order: String) -> Dictionary:
	var result := plan.duplicate(true)
	if not result.has("assignments"):
		result["assignments"] = {}
	if not result.has("orders"):
		result["orders"] = {"sail_target": ""}
	result["orders"]["boarding"] = order
	if ship.crew_auto:
		return result
	var assignments: Dictionary = result["assignments"]
	for s in range(ShipState.MARINES + 1):
		if ship.boarding_action_of(s) >= 0:
			continue
		var e: Dictionary = assignments.get(s, {})
		if str(e.get("code", "")) == BA:
			assignments[s] = entry(BR, s)
		if order == "stand_down" and ship.is_readied(s):
			assignments[s] = entry(BD, s)
	if order.begins_with("board:"):
		var target := order.trim_prefix("board:")
		var counter: Array = (ctx.get("counter_board", {}) as Dictionary).get(target, [])
		for s in [ShipState.MARINES, 0, 1, 2]:
			if not ship.is_readied(s):
				continue
			if not counter.is_empty() and not counter.has(s):
				continue
			if _ba_error(ship, assignments, ctx, s, target) == "":
				assignments[s] = entry(BA, s, target)
	return result


## Manual crew: a readied section on the Boarders station toggled between BA (at the ordered
## target) and BR. Returns {"plan", "error"}; the plan is unchanged when refused.
static func toggle_away(ship: ShipState, plan: Dictionary, ctx: Dictionary, section: int) -> Dictionary:
	var result := plan.duplicate(true)
	var assignments: Dictionary = result.get("assignments", {})
	var order := str(result.get("orders", {}).get("boarding", ""))
	var e: Dictionary = assignments.get(section, {})
	if str(e.get("code", "")) == BA:
		assignments[section] = entry(BR, section)
		result["assignments"] = assignments
		return {"plan": result, "error": ""}
	if not order.begins_with("board:"):
		return {"plan": plan, "error": "Choose \"Board …!\" first: the ship to board (10.C.1)."}
	var target := order.trim_prefix("board:")
	var why := _ba_error(ship, assignments, ctx, section, target)
	if why != "":
		return {"plan": plan, "error": why}
	assignments[section] = entry(BA, section, target)
	result["assignments"] = assignments
	return {"plan": result, "error": ""}
