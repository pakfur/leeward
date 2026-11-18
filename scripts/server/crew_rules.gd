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
const STATION_BRACES := "braces"
## The Boarders station (boarding spec §4.1-4.2): FB, BR, BA and, in its "Standing down" strip, BD.
const STATION_BOARDERS := "boarders"
## Sections in RO (crew disorganized) sit here; not a drop target (spec §4.3).
const STATION_REORGANIZING := "reorganizing"
## Fire stations are "fire_<seq>", one per fire burning (8.E.2).
const STATION_FIRE_PREFIX := "fire_"
## Fire watch (8.E.2 HINT): FF with no fire, any number of sections; drawn in the fire zone while no
## fire burns, offered in the assign menu only (menu_only) while fires burn.
const STATION_FIRE_WATCH := "fire_-1"
const CODE_FF := "FF"
const CODE_RO := "RO"
## Repair stations (8.F): station id = the code in lower case (station_of).
const STATION_RR := "rr"
const STATION_RH := "rh"
const STATION_RS := "rs"
const REPAIR_STATIONS := {"rr": "RR", "rh": "RH", "rs": "RS"}
## Codes a fire never calls a section away from (8.E.2: RO, engaged boarding). Forced tasks too.
const FIRE_EXEMPT_CODES: Array[String] = ["RO"]
## One-g-t tasks the fire draft takes before multi-g-t ones (spec §3.4 step 4).
const ONE_TURN_CODES: Array[String] = ["T", "BD"]
## Tie order among multi-g-t tasks for the fire draft (spec §3.4 step 5).
const DRAFT_TIE_ORDER: Array[String] = ["RS", "RR", "RH", "SAIL"]
## Short words for a section's task (the Crew line on a ship card, CrewOverlayText.section_job).
const SUMMARY_WORDS := {"guns": "guns", "marine_fire": "fire", "sails": "sails", "braces": "braces",
	"reorganizing": "RO", "boarders": "boarders", "anchor": "anchor"}
## Station labels and short codes (small deck cards), spec §4.3.
const STATION_LABELS := {"guns": "Serve the guns", "marine_fire": "Marine fire", "sails": "Sails aloft",
	"braces": "Braces (tacking)", "reorganizing": "Reorganizing", "boarders": "Boarders", "rr": "Rigging repair",
	"rh": "Hull repair", "rs": "Shroud repair", "anchor": "Anchor & cable"}
const STATION_SHORT := {"guns": "Guns", "marine_fire": "Marines", "sails": "Sails", "braces": "T",
	"reorganizing": "RO", "boarders": "FB", "rr": "RR", "rh": "RH", "rs": "RS", "anchor": "Anc"}
## Codes whose sections are locked once begun (5.F.9: a sail change must be completed).
const LOCKED_CODES: Array[String] = ["SAIL"]
## Critical effects whose 8.D.5 fix roll the marines would spoil if busy (+1, "marines not avail.").
const MARINE_HOLD_EFFECTS: Array[String] = [
	"broadside_obscured", "braces_cut", "lines_jammed", "rudder_jammed", "signal_halyards_cut",
]
## 10.H.2-3: what a prize's crew may not do.
const PRIZE_REFUSAL := "A prize may only board or repair; her original crew below fights the fires (10.H.2-3)."
const PRIZE_IDLE_NOTE := "A prize does not fight (10.H.2): sections here stand by."
const PRIZE_FIRE_NOTE := "Fought by the original crew locked below (10.H.3)."
## Marines-held-back reasons (spec §3.3), shown on the Marine fire station.
const HOLD_FIRE := "fire aboard"
const HOLD_EFFECT := "damage to fix"
const HOLD_FOULED := "fouled"
const HOLD_GRAPPLED := "grappled"
const HOLD_ENEMY := "enemy alongside"
## The anchor station (anchoring spec §3) is read-only: its tasks come from the anchor crew order.
const ANCHOR_REFUSAL := "Anchoring is ordered with the crew orders (anchor), not by placing sections here."


## The MPs the ship will sail this g-t, as far as planning knows: the stored course, or, when none
## is stored, her default course (6.G.2; AnchorController.actual_steps reads it the same way at End
## Planning), so the 13.C.1 and 8.F.3b warnings fire for a ship nobody plotted.
static func _plotted_mps(game_state: Node, ship: ShipState, steps: Array) -> int:
	if not steps.is_empty() or bool(ship.plotted_actions.get("movement_plotted", false)):
		return steps.size()
	if game_state == null or game_state.get("ship_controller") == null:
		return 0
	return DefaultCourse.for_ship(game_state, ship).size()


## Facts about the ship's situation the rules read (spec §3.2). Pure read of game_state.
## ma0_turn_plotted: the stored movement plot begins with a turn at MA 0 (5.D.1), so the Braces (T)
## station is open (MovementResolver.plots_ma0_turn, the test the Tacking roll uses).
static func context(game_state: Node, ship: ShipState) -> Dictionary:
	var nearest := -1
	var adjacent: Array = []  # [ship_id, ship_name] of enemies in play alongside (7.G.1)
	if game_state != null and game_state.get("fire_geometry") != null:
		for other: ShipState in game_state.get_all_ships():
			if other.side == ship.side or other.is_out_of_play():
				continue
			var r: int = game_state.fire_geometry.range_between(ship.occupied_hexes(), other.occupied_hexes())
			if r >= 0 and (nearest < 0 or r < nearest):
				nearest = r
			if r == FireRules.MARINE_RANGE:
				adjacent.append([other.ship_id, other.ship_name])
	adjacent.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	var adjacent_names: Array[String] = []
	for pair in adjacent:
		adjacent_names.append(str(pair[1]))
	var turn = game_state.get("current_turn") if game_state != null else null
	var boarding := boarding_context(game_state, ship)
	var env = game_state.get("environment") if game_state != null else null
	var scenario = game_state.get("active_scenario") if game_state != null else null
	var ma0_turn := false
	var steps: Array = ship.plotted_actions.get("movement", [])
	if not steps.is_empty() and game_state != null and game_state.get("ship_controller") != null \
			and not ship.is_out_of_play():
		ma0_turn = MovementResolver.plots_ma0_turn(ship, steps,
			game_state.ship_controller.get_movement_allowance(ship.ship_id))
	return {
		"ma0_turn_plotted": ma0_turn,
		# Fires burning, as fire seqs in seq order (8.E.2: each needs one section).
		"fires": Array(ship.fire_seqs()),
		# final: End Planning (finalize_plots, begin_turn_tasks). While planning, braces placed
		# before the MA-0 turn is plotted are kept (with a warning) rather than dropped.
		"final": false,
		"plotted_mps": _plotted_mps(game_state, ship, steps),
		"nearest_enemy": nearest,
		"enemy_in_gun_range": nearest >= 0 and nearest <= FireRules.MAX_RANGE,
		"enemy_adjacent": nearest == 1,
		# Names of the enemy ships the marines could fire on (7.G.1), by ship_id.
		"adjacent_enemies": adjacent_names,
		"turn": int(turn) if turn != null else 0,
		# Anchoring (AnchorRules.refusal): the wind speed (13.E.3) and whether the scenario allows
		# anchoring where the ready anchor would drop (Scenario Book V.B).
		"wind_speed": int(env.wind_speed) if env != null else 0,
		"anchoring_here": scenario is Dictionary and AnchorRules.permitted(scenario, AnchorRules.drop_hex(ship)),
		# Boarding (boarding spec §2.4; BoardingRules): the enemies the ship may board this g-t
		# [{id, name, odds}], why others may not {id: reason}, counter-boarding {enemy: [sections]},
		# and every ship's name.
		"board_targets": boarding["board_targets"],
		"board_refusals": boarding["board_refusals"],
		"counter_board": boarding["counter_board"],
		"ship_names": boarding["ship_names"],
	}


## The boarding part of context(): ships linked to `ship` when PLANNING began (10.A.2) that it may
## board, with the odds as they stand (BoardingController.preview; the enemy counts only its
## announced boarders and its marines), and counter-boarding rights (10.E.4). Pure read.
static func boarding_context(game_state: Node, ship: ShipState) -> Dictionary:
	var out := {"board_targets": [], "board_refusals": {}, "counter_board": {}, "ship_names": {}}
	if game_state == null:
		return out
	for other: ShipState in game_state.get_all_ships():
		out["ship_names"][other.ship_id] = other.ship_name
	var links = game_state.get("linked_at_plot")
	var linked: Array = (links as Dictionary).get(ship.ship_id, []) if links is Dictionary else []
	var boarding = game_state.get("boarding_controller")
	if boarding != null:
		out["counter_board"] = boarding.counter_board(ship.ship_id)
	var ids := linked.duplicate()
	ids.sort()
	for other_id in ids:
		var other: ShipState = game_state.get_ship(str(other_id))
		if other == null:
			continue
		var why := BoardingRules.boardable_error(ship, other, linked)
		if why != "":
			out["board_refusals"][other.ship_id] = why
			continue
		var entry := {"id": other.ship_id, "name": other.ship_name, "odds": ""}
		if boarding != null:
			var goers := board_goers(ship, (out["counter_board"] as Dictionary).get(other.ship_id, []))
			var p: Dictionary = boarding.preview(ship.ship_id, other.ship_id, goers)
			entry["tbcf"] = int(p["tbcf"])
			entry["enemy_tbcf"] = int(p["enemy_tbcf"])
			entry["drm"] = int(p["drm"])
			entry["odds"] = "%d v about %d · you %s%d" % [int(p["tbcf"]), int(p["enemy_tbcf"]),
				"−" if int(p["drm"]) < 0 else "+", absi(int(p["drm"]))]
		out["board_targets"].append(entry)
	return out


## The sections that would go on a "Board" order (10.C.1): the readied marines and lowest readied
## sailor section (S4 never), or with none readied the marines and the lowest sailor section; after a
## repulse every section in `counter` (10.E.4).
static func board_goers(ship: ShipState, counter: Array) -> Array:
	var out: Array = []
	if not counter.is_empty():
		for s in counter:
			if ship.section_alive(int(s)) and int(s) != BoardingRules.MINIMUM_CREW_SECTION:
				out.append(int(s))
		return out
	var any_ready := false
	for s in range(ShipState.MARINES + 1):
		any_ready = any_ready or ship.is_readied(s)
	if ship.section_alive(ShipState.MARINES) and (ship.is_readied(ShipState.MARINES) or not any_ready):
		out.append(ShipState.MARINES)
	for k in range(BoardingRules.MINIMUM_CREW_SECTION):
		if ship.section_alive(k) and (ship.is_readied(k) or not any_ready):
			out.append(k)
			break
	return out


## The plan stored on the ship (plotted_actions), as a plan dictionary (copies). Before anything
## is stored this turn (crew_plotted false) the assignments are the carry-over defaults: tasks in
## progress stay with their sections (spec §0.1 Q-UX2; 4.A.3).
static func plan_of(ship: ShipState) -> Dictionary:
	var assignments := {}
	var stored = ship.plotted_actions.get("crew_assignments", {})
	if not bool(ship.plotted_actions.get("crew_plotted", false)):
		stored = default_plan(ship, {}).get("assignments", {})
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


## The Marine fire station's note (boarding spec §4.1): the muskets' possible targets, chosen with
## the guns in the fire panel (marine fire is not plotted, 4.A.1). "Adjacent enemy: Hermione",
## "Adjacent enemies: A, B" or "No enemy alongside".
static func marine_fire_note(adjacent_names: Array) -> String:
	if adjacent_names.is_empty():
		return "No enemy alongside."
	var names := PackedStringArray()
	for n in adjacent_names:
		names.append(str(n))
	return "Adjacent %s: %s. Targets are chosen with the guns." % [
		"enemy" if names.size() == 1 else "enemies", ", ".join(names)]


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
	if ship.is_grappled():  # ungrappling wants the marines too (8.C.4)
		return HOLD_GRAPPLED
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


## Sections the plan puts at the braces (T).
static func tack_sections_in(plan: Dictionary) -> int:
	var count := 0
	var assignments: Dictionary = plan.get("assignments", {})
	for section in assignments:
		if str(assignments[section].get("code", "")) == TackCrewHandler.CODE:
			count += 1
	return count


## "" when `section` may go to `station_id` in `plan`, else the reason (quoting the rule).
static func refusal(ship: ShipState, plan: Dictionary, ctx: Dictionary, section: int, station_id: String) -> String:
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
		if BoardingRules.is_code(code):
			return "%s is fighting a boarding action and cannot leave it (10.E.1)." % name
		if code == CODE_RO and str(locked[section]["params"].get("reason", "")) == "boarding":
			return "%s is reorganizing aboard the prize (10.G.2)." % name
		return "%s cannot be moved." % name
	if ship.is_captured() and not (station_id in [STATION_BOARDERS, STATION_GUNS, STATION_MARINE_FIRE]
			or REPAIR_STATIONS.has(station_id)):
		return PRIZE_REFUSAL
	match station_id:
		STATION_BOARDERS:
			if ship.is_readied(section):
				return ""
			return BoardingRules.task_error(ship, plan.get("assignments", {}), ctx, section, BoardingRules.FB)
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
		STATION_BRACES:
			if not bool(ctx.get("ma0_turn_plotted", false)):
				return "Plot a turn at MA 0 first: the braces are manned only to tack (5.D.1)."
			var at_braces := tack_sections_in(plan)
			var current: Dictionary = plan.get("assignments", {}).get(section, {})
			if str(current.get("code", "")) == TackCrewHandler.CODE:
				at_braces -= 1
			if at_braces >= TackCrewHandler.max_sections():
				return "Braces (tacking) is full (%d sections)." % TackCrewHandler.max_sections()
			return ""
		AnchorRules.STATION:
			return ANCHOR_REFUSAL
		STATION_REORGANIZING:
			return "Sections reorganize only after Crew Disorganized (hull critical #4); it cannot be plotted."
		STATION_RR, STATION_RH, STATION_RS:
			var code: String = REPAIR_STATIONS[station_id]
			var why := RepairController.refusal(ship, code)
			if why != "":
				return why
			for other in plan.get("assignments", {}):
				if int(other) != section and str(plan["assignments"][other].get("code", "")) == code:
					return "%s already has %s on it. One section per repair type (8.F.4)." % [
						STATION_LABELS[station_id], ShipState.SECTION_NAMES[int(other)]]
			return ""
	if station_id == STATION_FIRE_WATCH:
		return ""
	if station_id.begins_with(STATION_FIRE_PREFIX):
		var seq := int(station_id.trim_prefix(STATION_FIRE_PREFIX))
		if not (ctx.get("fires", []) as Array).has(seq):
			return "There is no such fire."
		for other in plan.get("assignments", {}):
			var entry: Dictionary = plan["assignments"][other]
			if int(other) != section and str(entry.get("code", "")) == CODE_FF \
					and int(entry.get("params", {}).get("fire", -1)) == seq:
				return "Fire %d already has %s fighting it. One section per fire (8.E.2)." % [
					fire_number(ctx, seq), ShipState.SECTION_NAMES[int(other)]]
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
	var readied := ship.is_readied(section)
	if readied and station_id != STATION_BOARDERS:
		# 10.B.5: a readied section leaving the boarders must disband (BD) this g-t.
		result["assignments"][section] = BoardingRules.entry(BoardingRules.BD, section)
		return result
	match station_id:
		STATION_BOARDERS:
			result["assignments"][section] = BoardingRules.entry(BoardingRules.BR if readied else BoardingRules.FB, section)
		STATION_GUNS, STATION_MARINE_FIRE:
			result["assignments"].erase(section)
		STATION_SAILS:
			result["assignments"][section] = {"code": SailController.CODE,
				"params": {"target": str(result["orders"].get("sail_target", ""))}}
		STATION_BRACES:
			result["assignments"][section] = {"code": TackCrewHandler.CODE, "params": {}}
		STATION_RR, STATION_RH, STATION_RS:
			result["assignments"][section] = {"code": REPAIR_STATIONS[station_id], "params": {}}
		_:
			if station_id.begins_with(STATION_FIRE_PREFIX):
				result["assignments"][section] = {"code": CODE_FF,
					"params": ff_params(int(station_id.trim_prefix(STATION_FIRE_PREFIX)), section)}
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
	if ship.is_captured():
		# A prize (10.H.2-3): her prize crew may plot only boarding and repairs; the original crew
		# below fights the fires (FireController), so no fire draft and no fire stations. With no
		# prize crew aboard yet there is no crew to plot.
		orders["sail_target"] = ""
		if not ship.has_prize_crew():
			result["orders"] = {"sail_target": ""}
			result["dropped"] = assignments.keys()
			return result
		ctx = ctx.duplicate()
		ctx["fires"] = []
		ctx["ma0_turn_plotted"] = false
		for section in assignments.keys():
			var code := str(assignments[section].get("code", ""))
			if not (BoardingRules.is_code(code) or RepairController.is_repair(code)):
				assignments.erase(section)
				result["dropped"].append(section)
				result["warnings"].append("%s: %s" % [ShipState.SECTION_NAMES[section], PRIZE_REFUSAL])
	elif ship.is_out_of_play():
		# (6) A destroyed ship has no crew tasks. A struck ship only fights its fires (8.E.3, 9.C.3),
		# always by the automatic allocation (rule A1; spec 0.3 #8).
		result["orders"] = {"sail_target": ""}
		if ship.is_struck():
			result["assignments"] = CrewAuto.fire_assignments(ship, ctx, {})
			result["auto"] = result["assignments"].keys()
		for section in assignments.keys():
			if not result["assignments"].has(section):
				result["dropped"].append(section)
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
	# (4) manual: drop what the rules refuse. Boarding first (BoardingRules.normalize_manual): readied
	# sections not plotted to BR/BA/BD stand down, illegal FB/BA are refused.
	var boarding := BoardingRules.normalize_manual(ship, assignments, ctx, locked)
	assignments = boarding["assignments"]
	result["warnings"].append_array(boarding["warnings"])
	result["dropped"].append_array(boarding["dropped"])
	result["notes"] = boarding["notes"]
	_normalize_anchoring(ship, assignments, ctx, locked, result)
	var sail_target := str(orders.get("sail_target", ""))
	var on_sails := 0
	var at_braces := 0
	var repairs := {}
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
		elif code == TackCrewHandler.CODE:
			if at_braces >= TackCrewHandler.max_sections():
				why = "Braces (tacking) is full"
			elif not bool(ctx.get("ma0_turn_plotted", false)) and bool(ctx.get("final", false)):
				why = "No turn at MA 0 is plotted (5.D.1)"
			else:
				# While planning, braces manned before the MA-0 turn is (re)plotted are kept; End
				# Planning (ctx.final) drops them if no such turn is plotted by then.
				at_braces += 1
				entry["params"] = {}
				if not bool(ctx.get("ma0_turn_plotted", false)):
					result["warnings"].append("%s: at the braces, but no turn at MA 0 is plotted. Back to %s at End Planning unless one is (5.D.1)." % [
						ShipState.SECTION_NAMES[section], "marine fire" if section == ShipState.MARINES else "the guns"])
		elif code == CODE_FF:
			var fire := int(entry.get("params", {}).get("fire", -1))
			if fire >= 0 and not (ctx.get("fires", []) as Array).has(fire):
				why = "That fire is out"
			else:
				entry["params"] = ff_params(fire, section)
		elif BoardingRules.is_code(code):
			pass  # made legal by BoardingRules.normalize_manual above
		elif AnchorRules.is_code(code):
			pass  # made legal by _normalize_anchoring above
		elif RepairController.is_repair(code):
			# 8.F.3, 8.F.4: only when there is something to repair, one section per type.
			why = RepairController.refusal(ship, code)
			if why == "" and repairs.has(code):
				why = "one section per repair type (8.F.4)"
			if why == "":
				repairs[code] = section
				entry["params"] = {}
				var mp := RepairController.mp_warning(code, ctx)
				if mp != "":
					result["warnings"].append("%s: %s" % [ShipState.SECTION_NAMES[section], mp])
		else:
			var live := ship.task_of(section)
			if live.is_empty() or str(live.get("code", "")) != code:
				why = "Unknown task %s" % code
		if why != "":
			assignments.erase(section)
			result["dropped"].append(section)
			result["warnings"].append("%s: %s" % [ShipState.SECTION_NAMES[section], why])
	# (5) every fire gets a section (8.E.2): the draft fills empty fire slots, marked auto.
	var filled := fill_fires(ship, assignments, ctx.get("fires", []))
	assignments = filled["assignments"]
	result["auto"] = filled["auto"]
	var needed := sail_sections_needed(ship, orders)
	on_sails = 0
	for section in assignments:
		if str(assignments[section].get("code", "")) == SailController.CODE:
			on_sails += 1
	if needed > 0 and on_sails < needed:
		result["warnings"].append("Needs %d %s: %d placed. The change will not start." % [needed,
			"section" if needed == 1 else "sections", on_sails])
	result["assignments"] = assignments
	return result


## The manual plan's anchoring tasks made legal (anchoring spec §3): sections in ascending order,
## each checked by AnchorRules.refusal against the anchoring codes kept before it; a refused one is
## dropped with a warning. An A kept while MPs are plotted is warned of: End Planning erases it
## (13.C.1). Edits `assignments` and `result` in place.
static func _normalize_anchoring(ship: ShipState, assignments: Dictionary, ctx: Dictionary,
		locked: Dictionary, result: Dictionary) -> void:
	var accepted: Array = []
	var sections: Array = assignments.keys()
	sections.sort()
	for section in sections:
		if locked.has(section):
			continue
		var entry: Dictionary = assignments[section]
		var code := str(entry.get("code", ""))
		if not AnchorRules.is_code(code):
			continue
		var raw = entry.get("params", {})
		var params: Dictionary = raw if raw is Dictionary else {}
		var why := AnchorRules.refusal(ship, code, params, ctx, accepted)
		if why != "":
			assignments.erase(section)
			result["dropped"].append(section)
			result["warnings"].append("%s: %s" % [ShipState.SECTION_NAMES[section], why])
			continue
		accepted.append(code)
		entry["params"] = {"turn": str(params["turn"])} if code == "HS" else {}
		if code == "A" and int(ctx.get("plotted_mps", 0)) > 0 and not bool(ctx.get("final", false)):
			result["warnings"].append(
				"%s: anchoring needs a plot of no MPs; erased at End Planning unless the course is cut (13.C.1)."
				% ShipState.SECTION_NAMES[section])


## FF params: {"fire": seq}, or for fire watch (seq < 0) {"fire": -1, "section": s} so that each
## section on watch is its own task (one section per fire once a fire breaks out, 8.E.2).
static func ff_params(fire: int, section: int) -> Dictionary:
	if fire < 0:
		return {"fire": -1, "section": section}
	return {"fire": fire}


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


# --- Stations (spec §4.3), progress warnings ---

## The station a plan entry sits on: "" (unplotted) is the guns for a sailor, marine fire for M.
static func station_of(section: int, entry: Dictionary) -> String:
	var code := str(entry.get("code", ""))
	match code:
		"":
			return STATION_MARINE_FIRE if section == ShipState.MARINES else STATION_GUNS
		SailController.CODE:
			return STATION_SAILS
		TackCrewHandler.CODE:
			return STATION_BRACES
		CODE_RO:
			return STATION_REORGANIZING
		CODE_FF:
			return STATION_FIRE_PREFIX + str(int(entry.get("params", {}).get("fire", -1)))
	if BoardingRules.is_code(code):
		return STATION_BOARDERS
	if AnchorRules.is_code(code):
		return AnchorRules.STATION
	return code.to_lower()


## Fire N as the player counts them (1-based, in seq order) for a fire seq; 0 if unknown.
static func fire_number(ctx: Dictionary, seq: int) -> int:
	var fires: Array = (ctx.get("fires", []) as Array).duplicate()
	fires.sort()
	return fires.find(seq) + 1


## The sail changes the ship may order now: [{target, sections, turns, text}] (5.F.6, ship log).
static func sail_choices(ship: ShipState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for target in SailController.targets_for(ship):
		var sections := SailController.sections_needed(ship, target)
		var turns: int = DataManager.combat_tables.task_turns(SailController.cost_row(ship, target), ship.crew_quality)
		out.append({"target": target, "sections": sections, "turns": turns})
	return out


## Every station the overlay draws for the ship, in drawing order (spec §4.3). Each:
## {id, code, label, short, capacity, turns, accepts ("sailor"/"marine"/"any"/"none"), note,
##  warning, disabled_reason, occupants: [sections], locked: [sections], fire: {} or {seq, number}}.
## Sails also carries "choices" (sail_choices) and "target". Fire stations come from ctx.fires; the
## repair stations (rs, rr, rh) are listed while there is something to repair (8.F.3); the read-only
## anchor station while the ship is anchored, has an anchor or springs ready, or a section is on it.
static func stations(ship: ShipState, plan: Dictionary, ctx: Dictionary) -> Array[Dictionary]:
	var assignments: Dictionary = plan.get("assignments", {})
	var orders: Dictionary = plan.get("orders", {})
	var locked := locked_sections(ship)
	var by_station := {}
	for section in range(ShipState.MARINES + 1):
		if not ship.section_alive(section):
			continue
		var st := station_of(section, assignments.get(section, {}))
		if not by_station.has(st):
			by_station[st] = []
		by_station[st].append(section)
	var out: Array[Dictionary] = []
	var locked_on := func(sections: Array) -> Array:
		var result: Array = []
		for s in sections:
			if locked.has(int(s)) or ship.crew_auto:
				result.append(int(s))
		return result
	var make := func(id: String, code: String, capacity: int, turns: int, accepts: String, note: String) -> Dictionary:
		var occ: Array = by_station.get(id, [])
		return {"id": id, "code": code, "label": STATION_LABELS.get(id, id), "short": STATION_SHORT.get(id, code),
			"capacity": capacity, "turns": turns, "accepts": accepts, "note": note, "warning": "",
			"disabled_reason": "", "occupants": occ.duplicate(), "locked": locked_on.call(occ), "fire": {}}
	# Fires first (8.E.2): one station per fire, in seq order.
	var fires: Array = (ctx.get("fires", []) as Array).duplicate()
	fires.sort()
	for seq in fires:
		var n := fires.find(seq) + 1
		var st: Dictionary = make.call(STATION_FIRE_PREFIX + str(seq), CODE_FF, 1, 0, "any",
			"1 hull and 1 rigging box a turn until it is out (8.E.8). One section per fire (8.E.2).")
		st["label"] = "Fire %d" % n
		st["short"] = "FF%d" % n
		st["fire"] = {"seq": int(seq), "number": n, "age": ship.fire_age(int(seq), int(ctx.get("turn", 0)))}
		if ship.is_captured():
			st["accepts"] = "none"
			st["note"] = PRIZE_FIRE_NOTE
			st["disabled_reason"] = PRIZE_FIRE_NOTE
		elif (st["occupants"] as Array).is_empty():
			st["warning"] = "Unfought: morale check each turn (8.E.6)"
		out.append(st)
	# Fire watch (8.E.2 HINT): drawn while no fire burns; with fires, offered in the menu only.
	var watch: Dictionary = make.call(STATION_FIRE_WATCH, CODE_FF, 0, 0, "any",
		"A head start if fire breaks out (8.E.2).")
	watch["label"] = "Fire watch"
	watch["short"] = "FF"
	watch["menu_only"] = not fires.is_empty()
	if not ship.is_captured():
		out.append(watch)
	var guns: Dictionary = make.call(STATION_GUNS, "", ShipState.SAILOR_SECTIONS, 0, "sailor",
		"Both broadsides. Unassigned sailors work the guns (4.B.4).")
	var marine: Dictionary = make.call(STATION_MARINE_FIRE, "", 1, 0, "marine",
		marine_fire_note(ctx.get("adjacent_enemies", []) as Array))
	var held := marines_held_back(ship, ctx)
	if ship.crew_auto and held != "":
		marine["note"] = "Marines held back: %s. %s" % [held, marine["note"]]
	if ship.is_captured():
		guns["note"] = PRIZE_IDLE_NOTE  # spec §8 Q2: a prize does not fire
		guns["label"] = "Serve the guns (idle)"
		marine["note"] = PRIZE_IDLE_NOTE
	out.append(guns)
	out.append(marine)
	if ship.crew_can_act():
		out.append(boarders_station(ship, plan, ctx, by_station.get(STATION_BOARDERS, []), locked_on))
	var choices := sail_choices(ship)
	if not choices.is_empty() or ship.has_sail_change():
		var target := str(orders.get("sail_target", ""))
		var cap := 0
		var turns := 0
		if ship.has_sail_change():
			var task: Dictionary = ship.tasks_with(SailController.CODE)[0]
			cap = (task.get("sections", []) as Array).size()
			turns = ship.task_turns_required(task)
			target = str(task.get("params", {}).get("target", ""))
		elif target != "":
			cap = SailController.sections_needed(ship, target)
			turns = DataManager.combat_tables.task_turns(SailController.cost_row(ship, target), ship.crew_quality)
		var sails: Dictionary = make.call(STATION_SAILS, SailController.CODE, cap, turns, "any",
			"Choose the change, then place its sections.")
		sails["choices"] = choices
		sails["target"] = target
		if ship.has_sail_change():
			sails["note"] = "Sail change to %s in progress. Must be completed (5.F.9)." % target
		elif target == "":
			sails["note"] = "Order a sail change first."
		if ship.has_critical("lines_jammed"):
			sails["disabled_reason"] = "Lines jammed: no sail changes (5.F.9c)"
		var placed := (sails["occupants"] as Array).size()
		if not ship.has_sail_change() and cap > 0 and placed < cap:
			sails["warning"] = "Needs %d %s: %d placed. The change will not start." % [cap,
				"section" if cap == 1 else "sections", placed]
		out.append(sails)
	var at_braces: Array = by_station.get(STATION_BRACES, [])
	if bool(ctx.get("ma0_turn_plotted", false)) or not at_braces.is_empty():
		var braces: Dictionary = make.call(STATION_BRACES, TackCrewHandler.CODE, TackCrewHandler.max_sections(),
			0, "any", "The Tacking table assumes 3 sections: +2 on the roll for each one short (5.D.2a).")
		if not bool(ctx.get("ma0_turn_plotted", false)):
			braces["warning"] = "No turn at MA 0 is plotted: these sections go back at End Planning unless one is (5.D.1)."
		out.append(braces)
	# Repairs (8.F): shown when there is something to repair, or while a section is on one.
	for st_id in [STATION_RS, STATION_RR, STATION_RH]:
		var code: String = REPAIR_STATIONS[st_id]
		var occupied: Array = by_station.get(st_id, [])
		var why := RepairController.refusal(ship, code)
		var nothing := false
		match code:
			"RR": nothing = ship.missing_boxes("rigging") <= 0
			"RH": nothing = ship.missing_boxes("hull") <= 0
			"RS": nothing = not ship.has_critical(RepairController.SHROUDS)
		if (nothing or not ship.crew_can_act()) and occupied.is_empty():
			continue
		var note := ""
		match code:
			"RR": note = "One rigging box per repair, added to the section taking damage (8.F.5). Only at fighting sail, furled or dismasted (8.F.3a)."
			"RH": note = "Cancelled if the ship moves more than %d MPs (8.F.3b)." % RepairController.max_mp()
			"RS": note = "Splices the severed shrouds: the −1 MP ends (8.F.1)."
		var rep_st: Dictionary = make.call(st_id, code, 1,
			DataManager.combat_tables.task_turns(code, ship.crew_quality), "any", note)
		rep_st["disabled_reason"] = why
		var mp := RepairController.mp_warning(code, ctx)
		if mp != "" and why == "":
			rep_st["warning"] = mp
		out.append(rep_st)
	# The anchor (13.B-F): read-only; its tasks follow the anchor crew order.
	var at_anchor: Array = by_station.get(AnchorRules.STATION, [])
	if ship.is_anchored() or ship.anchor_ready != "" or ship.springs_ready or not at_anchor.is_empty():
		var anchor_st: Dictionary = make.call(AnchorRules.STATION, "", 0, 0, "none", AnchorRules.status_text(ship))
		anchor_st["disabled_reason"] = ANCHOR_REFUSAL
		out.append(anchor_st)
	if by_station.has(STATION_REORGANIZING):
		var ro: Dictionary = make.call(STATION_REORGANIZING, CODE_RO, 0, 0, "none",
			"Crew disorganized (hull critical #4): reorganizing, cannot be moved.")
		ro["locked"] = (by_station[STATION_REORGANIZING] as Array).duplicate()
		out.append(ro)
	return out


## The Boarders station (boarding spec §4.1-4.2). Beyond the common keys: "tags" {section: code}
## (FB forming, BR ready, BA away, BD standing down; "fighting" engaged ones carry "engaged": true),
## "standing_down" [sections at BD, drawn in a strip under the station, not in "occupants"],
## "order" (crew_orders.boarding) and "choices" [{order, text, odds}] for the order picker.
static func boarders_station(ship: ShipState, plan: Dictionary, ctx: Dictionary, sections: Array,
		locked_on: Callable) -> Dictionary:
	var assignments: Dictionary = plan.get("assignments", {})
	var orders: Dictionary = plan.get("orders", {})
	var occupants: Array = []
	var standing: Array = []
	var tags := {}
	var engaged: Array = []
	for s in sections:
		var code := str(assignments.get(int(s), {}).get("code", ""))
		tags[int(s)] = code
		if ship.boarding_action_of(int(s)) >= 0:
			engaged.append(int(s))
		if code == BoardingRules.BD:
			standing.append(int(s))
		else:
			occupants.append(int(s))
	var st := {"id": STATION_BOARDERS, "code": "FB", "label": STATION_LABELS[STATION_BOARDERS],
		"short": STATION_SHORT[STATION_BOARDERS], "capacity": ShipState.MARINES + 1, "turns": 1,
		"accepts": "any", "warning": "", "disabled_reason": "",
		"note": "Boarders come from the lowest-numbered sailor sections first (4.B.1). Each sailor section here is −3 on the guns; marines here still fire muskets (10.B.4).",
		"occupants": occupants, "locked": locked_on.call(occupants), "fire": {},
		"tags": tags, "engaged": engaged, "standing_down": standing,
		"order": str(orders.get("boarding", "")), "choices": boarding_choices(ship, ctx)}
	if ship.is_burning():
		st["disabled_reason"] = BoardingRules.FIRE_REFUSAL
	return st


## The Boarders station's order picker (spec §4.2): no order, "Stand ready", one "Board ‹enemy›!"
## (or "Counter-board ‹enemy›!", 10.E.4) per enemy that may be boarded, with the odds as they stand,
## and "Stand down" while any section is readied.
static func boarding_choices(ship: ShipState, ctx: Dictionary) -> Array:
	var out: Array = [{"order": "", "text": "No boarders", "odds": ""},
		{"order": "ready", "text": "Stand ready", "odds": ""}]
	var counter: Dictionary = ctx.get("counter_board", {})
	for t in ctx.get("board_targets", []):
		var id := str(t.get("id", ""))
		out.append({"order": "board:" + id, "odds": str(t.get("odds", "")),
			"text": "%s %s!" % ["Counter-board" if counter.has(id) else "Board", str(t.get("name", id))]})
	for s in range(ShipState.MARINES + 1):
		if ship.is_readied(s):
			out.append({"order": "stand_down", "text": "Stand down", "odds": ""})
			break
	return out


## How a task reads in a sentence ("rigging repair", "the sail change to MS").
static func task_name(code: String, params: Dictionary = {}) -> String:
	match code:
		"":
			return "the guns"
		SailController.CODE:
			var target := str(params.get("target", ""))
			return "the sail change to %s" % target if target != "" else "the sail change"
		TackCrewHandler.CODE:
			return "the braces"
		CODE_RO:
			return "reorganizing"
		"FB":
			return "forming boarders"
		"BR":
			return "boarders ready"
		"BA":
			return "boarding %s" % str(params.get("target", "")) if str(params.get("target", "")) != "" else "boarding"
		"BD":
			return "standing down"
		CODE_FF:
			var fire := int(params.get("fire", -1))
			return "fire watch" if fire < 0 else "fighting a fire"
		"RR":
			return "rigging repair"
		"RH":
			return "hull repair"
		"RS":
			return "shroud repair"
	if AnchorRules.is_code(code):
		return str(PhaseEvents.CREW_TASK_GERUNDS[code])
	return code


## The 4.A.3 warning before moving `section` to `station_id`, or "": a section that has done at
## least one g-t of an abandonable task loses that progress when it stops plotting it.
static func progress_warning(ship: ShipState, _plan: Dictionary, section: int, station_id: String) -> String:
	var task := ship.task_of(section)
	if task.is_empty() or int(task.get("done", 0)) <= 0:
		return ""
	var code := str(task.get("code", ""))
	if code == SailController.CODE or bool(task.get("forced", false)) or BoardingRules.is_code(code):
		return ""  # locked, or a boarding task (leaving it is BD, 10.B.5)
	if station_of(section, {"code": code, "params": task.get("params", {})}) == station_id:
		return ""
	var needed := ship.task_turns_required(task)
	return "%s has %d of %d turns on %s. Moving it loses them (4.A.3)." % [ShipState.SECTION_NAMES[section],
		int(task["done"]), needed, task_name(code, task.get("params", {}))]


## The plan with the sail change ordered (`target`, "" = none). In manual mode the sections
## already on Sails stay (up to what the change needs) and the rest come from the worker order if
## enough are free; with no target the Sails sections go back to their defaults (spec §4.8).
static func with_sail_order(ship: ShipState, plan: Dictionary, ctx: Dictionary, target: String) -> Dictionary:
	var result := plan.duplicate(true)
	if not result.has("assignments"):
		result["assignments"] = {}
	if not result.has("orders"):
		result["orders"] = {"sail_target": ""}
	result["orders"]["sail_target"] = target
	if ship.crew_auto or ship.has_sail_change():
		return result
	var assignments: Dictionary = result["assignments"]
	var on_sails: Array = []
	for section in assignments.keys():
		if str(assignments[section].get("code", "")) == SailController.CODE:
			on_sails.append(int(section))
	on_sails.sort()
	var needed := SailController.sections_needed(ship, target) if target != "" else 0
	for k in range(on_sails.size()):
		if k < needed:
			assignments[on_sails[k]] = {"code": SailController.CODE, "params": {"target": target}}
		else:
			assignments.erase(on_sails[k])
	var missing := needed - mini(needed, on_sails.size())
	if missing > 0:
		var workers := worker_order(ship, ctx, assignments)
		if workers.size() >= missing:
			for k in range(missing):
				assignments[workers[k]] = {"code": SailController.CODE, "params": {"target": target}}
	return result


# --- The fire draft (8.E.2; spec §3.4) ---

## The section to send to a fire nobody fights, or -1. First match wins:
## 1 a section standing by (FF with no fire), lowest first; 2 the lowest unplotted sailor section;
## 3 the marines, if unplotted; 4 a section on a one-g-t task (T, BD), highest first; 5 a section on
## a multi-g-t task that is not fire-exempt: fewest g-t's done, then RS, RR, RH, SAIL, then the
## highest section. Never RO, forced tasks (engaged boarders), another fire or a lost section.
static func fire_draft(ship: ShipState, assignments: Dictionary, _fire_seq: int) -> int:
	var alive := func(s: int) -> bool: return ship.section_alive(s)
	for s in range(ShipState.MARINES + 1):
		var entry: Dictionary = assignments.get(s, {})
		if alive.call(s) and str(entry.get("code", "")) == CODE_FF and int(entry.get("params", {}).get("fire", -1)) < 0:
			return s
	for s in range(ShipState.SAILOR_SECTIONS):
		if alive.call(s) and not assignments.has(s):
			return s
	if alive.call(ShipState.MARINES) and not assignments.has(ShipState.MARINES):
		return ShipState.MARINES
	for s in range(ShipState.MARINES, -1, -1):
		if alive.call(s) and assignments.has(s) and ONE_TURN_CODES.has(str(assignments[s].get("code", ""))):
			return s
	var best := -1
	var best_key: Array = []
	for s in range(ShipState.MARINES + 1):
		if not alive.call(s) or not assignments.has(s):
			continue
		var entry: Dictionary = assignments[s]
		var code := str(entry.get("code", ""))
		if code == CODE_FF or FIRE_EXEMPT_CODES.has(code) or ONE_TURN_CODES.has(code):
			continue
		var live := ship.task_of(s)
		if not live.is_empty() and str(live.get("code", "")) == code and bool(live.get("forced", false)):
			continue
		var done := int(live.get("done", 0)) if str(live.get("code", "")) == code else 0
		var tie := DRAFT_TIE_ORDER.find(code)
		var key: Array = [done, tie if tie >= 0 else DRAFT_TIE_ORDER.size(), -s]
		if best < 0 or _key_less(key, best_key):
			best = s
			best_key = key
	return best


## Fills every fire in `fires` (seqs) that no section fights, by the fire draft. A section drafted
## off a shared task ends it for its partners too (a two-section sail change, 5.F.9a): they go back
## to their defaults. Returns {"assignments", "auto": [drafted sections]}.
static func fill_fires(ship: ShipState, assignments: Dictionary, fires: Array) -> Dictionary:
	var result := assignments.duplicate(true)
	var auto: Array[int] = []
	var seqs := fires.duplicate()
	seqs.sort()
	for seq in seqs:
		var fought := false
		for s in result:
			var entry: Dictionary = result[s]
			fought = fought or (str(entry.get("code", "")) == CODE_FF and int(entry.get("params", {}).get("fire", -1)) == int(seq))
		if fought:
			continue
		var s := fire_draft(ship, result, int(seq))
		if s < 0:
			continue  # unfought (8.E.6)
		var old: Dictionary = result.get(s, {})
		if not old.is_empty() and str(old.get("code", "")) != CODE_FF:
			for other in result.keys():
				if int(other) != s and result[other] == old:
					result.erase(other)
		result[s] = {"code": CODE_FF, "params": {"fire": int(seq)}}
		auto.append(s)
	return {"assignments": result, "auto": auto}


static func _key_less(a: Array, b: Array) -> bool:
	for k in range(mini(a.size(), b.size())):
		if a[k] != b[k]:
			return a[k] < b[k]
	return a.size() < b.size()
