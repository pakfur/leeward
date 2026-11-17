class_name CrewTaskController
extends RefCounted
## CrewTaskController - the crew-task engine (Close Action 1997, 4.A.3, 4.B; crew-tasks spec §3).
## Stores the crew plots, turns them into tasks at the start of MOVEMENT_RESOLUTION, counts their
## g-t's in STATUS_ADJUSTMENT, and completes or cancels them. One CrewTaskHandler per code
## (register_handler); SAIL is SailController. All mutations go through ShipStateController.
##
## - 4.A.3: a multi-g-t task is done by the same sections every g-t; a section that stops plotting
##   it loses its progress (the task ends "abandoned"; a later plot starts again from 0).
## - 4.B.3: a section with no boxes left loses its task.
## - 4.B.4: sections plotted to a task this g-t do not serve the guns (plotted_sections), even if
##   the task ends early.
## - 9.A.2: g-t's needed are recomputed from the current crew quality every g-t.

const ABANDONED := "abandoned"
const COMPLETED := "completed"

var is_server: bool = true
var game_state: Node = null
var _handlers: Dictionary = {}  # code -> CrewTaskHandler
var _default_handler: CrewTaskHandler = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state
	_default_handler = CrewTaskHandler.new(p_game_state)


func register_handler(code: String, task_handler: CrewTaskHandler) -> void:
	_handlers[code] = task_handler


func handler(code: String) -> CrewTaskHandler:
	return _handlers.get(code, _default_handler)


# --- Planning ---

## Stores the player's crew plan for the ship (normalized; never refused for its content).
## Returns "" or the reason it was refused.
func plot_crew(player_id: int, ship_id: String, plan: Dictionary) -> String:
	if not is_server:
		push_error("CrewTaskController: Cannot plot crew on client")
		return "Not the server"
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "Unknown ship"
	if ship.side != player_id:
		return "Not your ship"
	if game_state.phase_controller.current_phase != TurnPhaseController.GamePhase.PLANNING:
		return "Crew can only be plotted during planning"
	if ship.is_destroyed():
		return "Ship is destroyed"
	if not plan.get("assignments", {}) is Dictionary or not plan.get("orders", {}) is Dictionary:
		return "Malformed crew plan"
	for section in plan.get("assignments", {}):
		var key := str(section)
		if not key.is_valid_int() or int(key) < 0 or int(key) > ShipState.MARINES \
				or not plan["assignments"][section] is Dictionary:
			return "Malformed crew plan"
	# The sail target is an order: a new one must be a change the ship can make now (5.F.6).
	var target := str(plan.get("orders", {}).get("sail_target", ""))
	if target != "" and target != ship.ordered_sail_target() and not target in SailController.targets_for(ship):
		return "Cannot change to %s from %s" % [target, ship.sail_state]
	# The boarding order (boarding spec §2.4 #6): "", "ready", "stand_down" or "board:<enemy>".
	var boarding := str(plan.get("orders", {}).get("boarding", ""))
	if boarding != "" and boarding != "ready" and boarding != "stand_down":
		if not boarding.begins_with("board:"):
			return "Unknown boarding order %s" % boarding
		var board_target := boarding.trim_prefix("board:")
		if board_target != ship.boarding_order().trim_prefix("board:"):
			var why := BoardingRules.target_error(ship, CrewRules.context(game_state, ship), board_target)
			if why != "":
				return why
	_store(ship, CrewRules.normalize(ship, plan, CrewRules.context(game_state, ship)))
	return ""


## The Automatic crew setting for one ship (spec §3.3). Turning it off keeps the current
## allocation as the manual plan; turning it on re-allocates at once.
func set_auto(player_id: int, ship_id: String, on: bool) -> String:
	if not is_server:
		push_error("CrewTaskController: Cannot set automatic crew on client")
		return "Not the server"
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "Unknown ship"
	if ship.side != player_id:
		return "Not your ship"
	var plan := current_plan(ship_id)
	game_state.ship_controller.set_crew_auto(ship_id, on)
	if game_state.phase_controller.current_phase == TurnPhaseController.GamePhase.PLANNING:
		_store(ship, CrewRules.normalize(ship, plan, CrewRules.context(game_state, ship)))
	return ""


## The ship's crew plan as it stands, normalized ({"assignments", "orders", "auto", "warnings",
## "dropped"}). Pure query. `end_planning`: as End Planning makes it (braces with no MA-0 turn dropped).
func current_plan(ship_id: String, end_planning: bool = false) -> Dictionary:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return {}
	var ctx := CrewRules.context(game_state, ship)
	ctx["final"] = end_planning
	return CrewRules.normalize(ship, CrewRules.plan_of(ship), ctx)


## Sections the ship's crew plan puts at the braces (T) if its movement plot holds a turn at MA 0
## (for the planning tacking note, shown while that turn is being plotted). Pure query.
func planned_tack_sections(ship_id: String) -> int:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return 0
	var ctx := CrewRules.context(game_state, ship)
	ctx["ma0_turn_plotted"] = true
	return CrewRules.tack_sections_in(CrewRules.normalize(ship, CrewRules.plan_of(ship), ctx))


## End of PLANNING: normalize every ship's plan against its final movement plot.
func finalize_plots() -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot finalize crew plots on client")
		return
	for ship_id in _sorted_ids():
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship != null and not ship.is_destroyed():
			_store(ship, current_plan(ship_id, true))


# --- Turn phases ---

## Start of MOVEMENT_RESOLUTION: the plots become tasks. Ships in id order; tasks not continued
## end ("abandoned"), new ones start (the handler may refuse: a sail change with no crew, lines
## jammed, not available). Sets plotted_sections and clears the crew plot.
func begin_turn_tasks(phase: int) -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot begin crew tasks on client")
		return
	var sc: ShipStateController = game_state.ship_controller
	for ship_id in _sorted_ids():
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null:
			continue
		var plan := current_plan(ship_id, true)
		var assignments: Dictionary = plan.get("assignments", {})
		var orders: Dictionary = plan.get("orders", {})
		var plotted: Array[int] = []
		var consumed := {}
		# Continuations (4.A.3): the same sections, code and identifying parameter.
		for task in _live_tasks(ship):
			var sections: Array = task.get("sections", [])
			var h := handler(str(task["code"]))
			var ended_by := h.cancel_reason(ship, task)
			if ended_by != "":
				cancel_task(ship_id, int(task["seq"]), ended_by, phase)
				continue
			var continued := not sections.is_empty()
			for section in sections:
				var entry: Dictionary = assignments.get(int(section), {})
				if entry.get("code", "") != task["code"] or not h.same_task(task, entry.get("params", {})):
					continued = false
			if continued:
				for section in sections:
					plotted.append(int(section))
					consumed[int(section)] = true
			else:
				cancel_task(ship_id, int(task["seq"]), ABANDONED, phase)
		# New tasks, grouped by code and parameters, in section order.
		var groups: Array = []
		var keys: Array = assignments.keys()
		keys.sort()
		for section in keys:
			if consumed.has(section):
				continue
			var entry: Dictionary = assignments[section]
			var group = null
			for g in groups:
				if g["code"] == entry.get("code", "") and g["params"] == entry.get("params", {}):
					group = g
			if group == null:
				group = {"code": str(entry.get("code", "")),
					"params": (entry.get("params", {}) as Dictionary).duplicate(true), "sections": []}
				groups.append(group)
			group["sections"].append(int(section))
		# An ordered sail change no section was found for still reports "no crew".
		var target := str(orders.get("sail_target", ""))
		if target != "" and not ship.is_out_of_play() and not ship.has_sail_change():
			var has_sail := false
			for g in groups:
				has_sail = has_sail or (g["code"] == SailController.CODE and g["params"].get("target", "") == target)
			if not has_sail:
				groups.append({"code": SailController.CODE, "params": {"target": target}, "sections": []})
		for group in groups:
			var h := handler(group["code"])
			var reason := h.prepare(ship, group)
			if reason != "":
				h.on_refused(ship, group, reason, phase)
				continue
			var seq := sc.add_task(ship_id, {
				"code": group["code"], "sections": group["sections"], "params": group["params"],
				"forced": h.forced, "marines_available": h.marines_available,
			})
			h.on_started(ship, ship.task_by_seq(seq), phase)
			for section in group["sections"]:
				plotted.append(int(section))
		plotted.sort()
		sc.set_plotted_sections(ship_id, plotted)
		sc.clear_crew_plot(ship_id)


## STATUS_ADJUSTMENT (SoP V.G): ships in id order, tasks in seq order. A task with a cancel reason
## ends; otherwise, if it was plotted this g-t, it counts the g-t and completes when it has done
## the g-t's its handler requires at the current crew quality. No dice.
func advance_tasks(phase: int) -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot advance crew tasks on client")
		return
	var sc: ShipStateController = game_state.ship_controller
	for ship_id in _sorted_ids():
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null:
			continue
		for task in _live_tasks(ship):
			var seq := int(task["seq"])
			var h := handler(str(task["code"]))
			var reason := h.cancel_reason(ship, task)
			if reason != "":
				cancel_task(ship_id, seq, reason, phase)
				continue
			var plotted := true
			for section in task.get("sections", []):
				plotted = plotted and ship.plotted_sections.has(int(section))
			if not plotted or not h.counts_turn(ship, task):
				continue
			sc.update_task(ship_id, seq, {"done": int(task.get("done", 0)) + 1})
			var current := ship.task_by_seq(seq)
			var needed := h.turns_required(ship, current)
			if needed >= 0 and int(current["done"]) >= needed:
				h.on_complete(ship, current, phase)
				sc.end_task(ship_id, seq, COMPLETED)
			elif h.one_turn:
				sc.end_task(ship_id, seq, COMPLETED)


## MOVEMENT_RESOLUTION, after the results are applied (mp_used_this_turn set): tasks the movement
## ends (8.F.3b: a hull repair on a ship that moved more than 4 MPs). Ships in id order.
func after_movement(phase: int) -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot check crew tasks after movement on client")
		return
	for ship_id in _sorted_ids():
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null:
			continue
		for task in _live_tasks(ship):
			var reason := handler(str(task["code"])).after_movement_reason(ship, task)
			if reason != "":
				cancel_task(ship_id, int(task["seq"]), reason, phase)


# --- Cancelling and forcing ---

## Ends the task with this seq at once, logging through its handler unless `log_it` is false.
func cancel_task(ship_id: String, seq: int, reason: String, phase: int, log_it: bool = true) -> bool:
	if not is_server:
		push_error("CrewTaskController: Cannot cancel crew task on client")
		return false
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return false
	var task := ship.task_by_seq(seq)
	if task.is_empty() or task.get("ended", "") != "":
		return false
	game_state.ship_controller.end_task(ship_id, seq, reason)
	if log_it:
		handler(str(task["code"])).on_cancel(ship, task, reason, phase)
	return true


## Ends the task the section is on (4.B.3 crew lost, crew disorganized): a task shared with other
## sections ends for all of them (5.F.9a).
func cancel_section(ship_id: String, section: int, reason: String, phase: int) -> bool:
	if not is_server:
		push_error("CrewTaskController: Cannot change tasks on client")
		return false
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return false
	var task := ship.task_of(section)
	if task.is_empty():
		return false
	return cancel_task(ship_id, int(task["seq"]), reason, phase)


## Every live task with this code ends (log_it false: silently, as when the ship is dismasted).
func cancel_code(ship_id: String, code: String, reason: String, phase: int, log_it: bool = true) -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot change tasks on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return
	for task in ship.tasks_with(code):
		cancel_task(ship_id, int(task["seq"]), reason, phase, log_it)


## Every live task but those with code `keep` ends (a ship that strikes keeps fighting its fires
## and does nothing else, 8.E.3, 9.C.3).
func cancel_all_except(ship_id: String, keep: String, reason: String, phase: int) -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot change tasks on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return
	for task in _live_tasks(ship):
		if str(task["code"]) != keep:
			cancel_task(ship_id, int(task["seq"]), reason, phase)


## Tells every handler that a fire broke out aboard the ship (8.E.2; spec §3.9 hook).
func notify_fire_breaks_out(ship_id: String) -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot change tasks on client")
		return
	var seen := {}
	for code in _handlers:
		var h: CrewTaskHandler = _handlers[code]
		if not seen.has(h):
			seen[h] = true
			h.on_fire_breaks_out(ship_id)


## Every live task ends without a log line (the ship is destroyed); the crew plot is cleared.
func drop_all(ship_id: String, reason: String) -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot drop crew tasks on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return
	for task in _live_tasks(ship):
		game_state.ship_controller.end_task(ship_id, int(task["seq"]), reason)
	game_state.ship_controller.clear_crew_plot(ship_id)


## Puts `sections` on a forced task now (RO; the boarding spec's FB), ending what they were doing.
## The sections count as plotted this g-t. Returns the new task's seq, or -1.
func force_task(ship_id: String, sections: Array, code: String, params: Dictionary, phase: int) -> int:
	if not is_server:
		push_error("CrewTaskController: Cannot force crew task on client")
		return -1
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return -1
	var why := str(params.get("reason", code))
	for section in sections:
		cancel_section(ship_id, int(section), why, phase)
	var h := handler(code)
	var seq: int = game_state.ship_controller.add_task(ship_id, {
		"code": code, "sections": sections, "params": params, "forced": true,
		"marines_available": h.marines_available,
	})
	var plotted: Array = ship.plotted_sections.duplicate()
	for section in sections:
		if not plotted.has(int(section)):
			plotted.append(int(section))
	plotted.sort()
	game_state.ship_controller.set_plotted_sections(ship_id, plotted)
	h.on_started(ship, ship.task_by_seq(seq), phase)
	return seq


## Progress on every live task with this code goes back to 0 (8.F.6); the tasks go on. The task
## records `reset_turn` (this g-t), which its handler may use to leave this g-t uncounted. Logged
## (CREW_TASK "reset") when progress was lost.
func reset_progress(ship_id: String, code: String, reason: String, phase: int) -> void:
	if not is_server:
		push_error("CrewTaskController: Cannot reset crew task progress on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return
	var turn = game_state.get("current_turn")
	for task in ship.tasks_with(code):
		var done := int(task.get("done", 0))
		var seq := int(task["seq"])
		game_state.ship_controller.update_task(ship_id, seq, {"done": 0, "reset_turn": int(turn) if turn != null else 0})
		if done > 0:
			var before := task.duplicate(true)
			before["done"] = done
			handler(code).on_reset(ship, before, reason, phase)
		Trace.trace_log("CrewTasks", "%s %s progress reset: %s" % [ship_id, code, reason], {"phase": phase, "done": done})


# --- Internals ---

func _store(ship: ShipState, normalized: Dictionary) -> void:
	game_state.ship_controller.set_crew_assignments(ship.ship_id, normalized.get("assignments", {}))
	game_state.ship_controller.set_crew_orders(ship.ship_id, normalized.get("orders", {"sail_target": ""}))


func _live_tasks(ship: ShipState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task in ship.crew_tasks:
		if task.get("ended", "") == "":
			result.append(task.duplicate(true))
	result.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	return result


func _sorted_ids() -> Array:
	var ids: Array = game_state.ships.keys()
	ids.sort()
	return ids
