class_name CrewAuto
extends RefCounted
## CrewAuto - the Automatic crew setting (crew-tasks spec §3.3), as pure static functions: the
## ship's officers place the crew sections by fixed rules, the same every turn, with no dice and
## no hidden inputs. Applied in order; a section taken by an earlier rule is not available to a
## later one:
##   A0 locked tasks stay (a sail change in progress, forced tasks);
##   A1 fires, lowest seq first: the section already fighting it, else the fire draft
##      (CrewRules.fire_draft; ctx.fires, the fires burning);
##   A2 other tasks in progress continue with the same sections;
##   A3 the ordered sail change, 1 or 2 sections in worker order;
##   A4 tacking crew: when the movement plot holds a turn at MA 0, as many of 3 sections as are
##      free, in worker order (5.D.2a); A5 repairs (phase 5);
##   A6 everyone else: sailors serve the guns, the marines are at marine fire.
## Worker order: M (unless held back, CrewRules.marines_held_back), then S4, S3, S2, S1. Marines
## first because they cost no gunfire; then the highest sailors, which crew losses reach last.


## {"assignments": {section -> {"code", "params"}}, "auto": [sections placed off the defaults]}.
static func allocate(ship: ShipState, orders: Dictionary, ctx: Dictionary) -> Dictionary:
	var taken := {}
	# A0: locked tasks.
	var locked := CrewRules.locked_sections(ship)
	for section in locked:
		taken[section] = locked[section]
	# A1: every fire gets a section (8.E.2): the one already fighting it, else the fire draft.
	taken = fire_assignments(ship, ctx, taken)
	# A2: tasks in progress, while every section still has boxes.
	for task in ship.crew_tasks:
		if task.get("ended", "") != "":
			continue
		var sections: Array = task.get("sections", [])
		if sections.is_empty():
			continue
		var all_alive := true
		var any_taken := false
		for section in sections:
			all_alive = all_alive and ship.section_alive(int(section))
			any_taken = any_taken or taken.has(int(section))
		if not all_alive or any_taken:
			continue
		for section in sections:
			taken[int(section)] = {"code": str(task["code"]),
				"params": (task.get("params", {}) as Dictionary).duplicate(true)}
	# A3: the ordered sail change. Placed only when every section it needs is free; otherwise it
	# does not start ("no crew") and nobody leaves the guns for it.
	var needed := CrewRules.sail_sections_needed(ship, orders)
	if needed > 0 and not ship.has_critical("lines_jammed"):
		var workers := CrewRules.worker_order(ship, ctx, taken)
		if workers.size() >= needed:
			for k in range(needed):
				taken[workers[k]] = {"code": SailController.CODE,
					"params": {"target": str(orders.get("sail_target", ""))}}
	# A4: the braces, for a turn at MA 0 (5.D.2a: the Tacking table assumes 3 sections).
	if bool(ctx.get("ma0_turn_plotted", false)):
		var hands := CrewRules.worker_order(ship, ctx, taken)
		for k in range(mini(TackCrewHandler.max_sections(), hands.size())):
			taken[hands[k]] = {"code": TackCrewHandler.CODE, "params": {}}
	# A6: the rest stay unplotted.
	var auto: Array[int] = []
	for section in range(ShipState.MARINES + 1):
		if taken.has(section):
			auto.append(section)
	return {"assignments": taken, "auto": auto}


## Rule A1 alone: `taken` with every fire in ctx.fires given a section, lowest seq first: the
## section already fighting it (if it has boxes), else the fire draft (CrewRules.fire_draft), which
## sees tasks in progress as plotted. A struck ship's crew is allocated by this rule only.
static func fire_assignments(ship: ShipState, ctx: Dictionary, taken_in: Dictionary) -> Dictionary:
	var taken := taken_in.duplicate(true)
	var fires: Array = (ctx.get("fires", []) as Array).duplicate()
	fires.sort()
	for seq in fires:
		var keeper := -1
		for task in ship.crew_tasks:
			if task.get("ended", "") == "" and str(task.get("code", "")) == CrewRules.CODE_FF \
					and int(task.get("params", {}).get("fire", -1)) == int(seq):
				for section in task.get("sections", []):
					if ship.section_alive(int(section)) and not taken.has(int(section)):
						keeper = int(section)
		if keeper < 0:
			# The draft sees tasks in progress as plotted (A2 would keep them), so it takes a free
			# section before calling one away from a task (spec §8 #20).
			var preview := taken.duplicate(true)
			for task in ship.crew_tasks:
				if task.get("ended", "") != "":
					continue
				for section in task.get("sections", []):
					if not preview.has(int(section)):
						preview[int(section)] = {"code": str(task["code"]),
							"params": (task.get("params", {}) as Dictionary).duplicate(true)}
			var drafted := CrewRules.fire_draft(ship, preview, int(seq))
			if drafted >= 0:
				taken[drafted] = {"code": CrewRules.CODE_FF, "params": {"fire": int(seq)}}
		else:
			taken[keeper] = {"code": CrewRules.CODE_FF, "params": {"fire": int(seq)}}
	return taken
