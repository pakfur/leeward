class_name CrewAuto
extends RefCounted
## CrewAuto - the Automatic crew setting (crew-tasks spec §3.3), as pure static functions: the
## ship's officers place the crew sections by fixed rules, the same every turn, with no dice and
## no hidden inputs. Applied in order; a section taken by an earlier rule is not available to a
## later one:
##   A0 locked tasks stay (a sail change in progress, forced tasks);
##   A1 fires, lowest seq first: the section already fighting it, else the fire draft
##      (CrewRules.fire_draft; ctx.fires, the fires burning);
##   A2 other tasks in progress continue with the same sections while still legal (RR is dropped
##      above FS, RH when the movement plot uses more than 4 MPs);
##   A2b the boarding order (BoardingRules.auto_assign, boarding spec §2.4 #6);
##   A2c the anchor order (crew_orders.anchor, AnchorRules.order_task): its task goes to the first
##      section in worker order, when AnchorRules.refusal allows it beside the anchoring tasks
##      already placed (a preparation in progress continues under A2);
##   A2d the tow order (crew_orders.tow, TowRules.order_task): PT for "take:<id>", TX for "cut";
##      its task goes to the first free section in worker order, when TowRules.refusal allows it
##      beside the towing tasks already placed and, for "take:", the target may still be taken in
##      tow (ctx.tow_target_errors; a standing order whose target struck places nothing); a PT in
##      progress continues under A2;
##   A3 the ordered sail change, 1 or 2 sections in worker order;
##   A4 tacking crew: when the movement plot holds a turn at MA 0, as many of 3 sections as are
##      free, in worker order (5.D.2a);
##   A5 repairs, one section each, in the order RS, RR, RH, each only where 8.F.3 allows it (RR at
##      FS, furled or dismasted; RH when the movement plot uses <= 4 MPs): the marines if they are
##      free under the worker order, a sailor section only when no enemy ship in play is within
##      15 hexes (spec §9 Q3);
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
		if not repair_allowed(ship, str(task["code"]), ctx):
			continue
		if BoardingRules.is_code(str(task["code"])):
			continue  # boarders follow the boarding order (A2b)
		for section in sections:
			taken[int(section)] = {"code": str(task["code"]),
				"params": (task.get("params", {}) as Dictionary).duplicate(true)}
	# A2b: the boarding order (boarding spec §2.4 #6): "ready" forms or keeps the marines and the
	# lowest sailor section as boarders, "board:<id>" also sends the readied ones away, no order or
	# "stand_down" disbands readied sections.
	taken = BoardingRules.auto_assign(ship, orders, ctx, taken)
	# A2c: the anchor order (anchoring spec §3): its task, if AnchorRules allows it beside the
	# anchoring tasks already placed, goes to the first free section in worker order.
	var wanted := AnchorRules.order_task(ship, str(orders.get("anchor", "")))
	if not wanted.is_empty():
		var accepted: Array = []
		for section in taken:
			var code := str(taken[section].get("code", ""))
			if AnchorRules.is_code(code):
				accepted.append(code)
		if AnchorRules.refusal(ship, str(wanted["code"]), wanted["params"], ctx, accepted) == "":
			var free := CrewRules.worker_order(ship, ctx, taken)
			if not free.is_empty():
				taken[free[0]] = wanted
	# A2d: the tow order (towing spec §3): its task, if TowRules allows it beside the towing tasks
	# already placed, goes to the first free section in worker order.
	var tow_order := str(orders.get("tow", ""))
	var tow_wanted := TowRules.order_task(ship, tow_order)
	var tow_parsed := TowRules.parse_order(tow_order)
	if str(tow_parsed["kind"]) == "take" and str((ctx.get("tow_target_errors", {}) as Dictionary).get(
			str(tow_parsed["target"]), "Unknown ship")) != "":
		tow_wanted = {}
	if not tow_wanted.is_empty():
		var tow_accepted: Array = []
		for section in taken:
			var code := str(taken[section].get("code", ""))
			if TowRules.is_code(code):
				tow_accepted.append(code)
		if TowRules.refusal(ship, str(tow_wanted["code"]), tow_accepted) == "":
			var free := CrewRules.worker_order(ship, ctx, taken)
			if not free.is_empty():
				taken[free[0]] = tow_wanted
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
	# A5: repairs (8.F), one section each: the marines if free, sailors only out of gun range.
	for code in RepairController.CODES:
		if not repair_allowed(ship, code, ctx):
			continue
		var busy := false
		for section in taken:
			busy = busy or str(taken[section].get("code", "")) == code
		if busy:
			continue
		var hands := CrewRules.worker_order(ship, ctx, taken)
		var pick := -1
		if hands.has(ShipState.MARINES):
			pick = ShipState.MARINES
		elif not hands.is_empty() and not enemy_within_gun_range(ctx):
			pick = hands[0]
		if pick >= 0:
			taken[pick] = {"code": code, "params": {}}
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


## Whether a repair (RR, RH, RS) may be plotted now under 8.F.3 (always true for other codes):
## something to repair, RR at FS/furled/dismasted, RH with the movement plot at <= 4 MPs.
static func repair_allowed(ship: ShipState, code: String, ctx: Dictionary) -> bool:
	if not RepairController.is_repair(code):
		return true
	return RepairController.refusal(ship, code) == "" and RepairController.mp_warning(code, ctx) == ""


## An enemy ship in play within 15 hexes (spec §9 Q3: sailors repair only when there is none).
static func enemy_within_gun_range(ctx: Dictionary) -> bool:
	var nearest := int(ctx.get("nearest_enemy", -1))
	return nearest >= 0 and nearest <= FireRules.MAX_RANGE
