class_name SailController
extends CrewTaskHandler
## SailController - sail changes (Close Action 1997, 5.F.6-9), the SAIL crew-task handler.
## The player orders a target sail state in PLANNING (`plot_sail_change`, stored as
## plotted_actions crew_orders.sail_target); CrewRules / CrewAuto place the sections; the change
## starts at the beginning of MOVEMENT_RESOLUTION (CrewTaskController.begin_turn_tasks) and is
## counted and completed in STATUS_ADJUSTMENT (advance_tasks). Its sections do not serve the guns.
## Ship log costs (crew_tasks.json): MS<->PS 2 CS, 2/3 g-t's; FS<->MS and FS<->Furl 1 CS, 1/2 g-t's
## (CQ A-D / E-G). Once begun it must be completed (5.F.9): it is not abandonable.
## All mutations go through ShipStateController.

const CODE := "SAIL"
## Cancellation reason (5.F.9c): a Lines Jammed critical hit (Rigging #5) abandons a change in
## progress and forbids new ones until fixed (8.D.5) or the ship is dismasted.
const CANCEL_LINES_JAMMED := "lines jammed"
const ROW_MAJOR := "SAIL_MAJOR"
const ROW_MINOR := "SAIL_MINOR"


func _init(p_game_state: Node) -> void:
	super(p_game_state)
	abandonable = false


## States one step from the carried sail, not above what the rigging can carry; none while a change
## is in progress, the lines are jammed, or the ship is dismasted or out of play.
static func targets_for(ship: ShipState) -> Array[String]:
	var result: Array[String] = []
	if ship == null or ship.is_out_of_play() or ship.is_dismasted() or ship.has_sail_change() \
			or ship.has_critical("lines_jammed"):
		return result
	var current := ShipState.SAIL_ORDER.find(ship.sail_state.to_upper())
	var limit := ShipState.SAIL_ORDER.find(ship.max_sail_state())
	if current < 0:
		return result
	for idx in [current - 1, current + 1]:
		if idx >= 0 and idx < ShipState.SAIL_ORDER.size() and (idx < current or idx <= limit):
			result.append(ShipState.SAIL_ORDER[idx])
	return result


## The crew_tasks.json row for a change from the carried state to `target`.
static func cost_row(ship: ShipState, target: String) -> String:
	return ROW_MAJOR if ship.sail_state.to_upper() == "PS" or target == "PS" else ROW_MINOR


## Sections the change to `target` needs (ship log: 2 for MS<->PS, else 1).
static func sections_needed(ship: ShipState, target: String) -> int:
	var sections: Array = DataManager.combat_tables.task_sections(cost_row(ship, target))
	return int(sections[0]) if not sections.is_empty() else 1


func available_targets(ship_id: String) -> Array[String]:
	return targets_for(game_state.get_ship(ship_id))


func change_cost(ship_id: String, target: String) -> Dictionary:
	## {"turns", "sections"} from the ship log at the ship's crew quality.
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return {"turns": 0, "sections": 0}
	var row := cost_row(ship, target)
	return {"turns": DataManager.combat_tables.task_turns(row, ship.crew_quality),
		"sections": sections_needed(ship, target)}


func plot_sail_change(player_id: int, ship_id: String, target: String) -> String:
	## Orders a sail change (crew_orders.sail_target). Returns "" on success, otherwise the reason it
	## was refused. An empty target clears the order.
	if not is_server:
		push_error("SailController: Cannot plot sail change on client")
		return "Not the server"
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "Unknown ship"
	if not game_state.commands(player_id, ship_id):
		return "Not your ship"
	if game_state.phase_controller.current_phase != TurnPhaseController.GamePhase.PLANNING:
		return "Sail changes can only be ordered during planning"
	if target == "":
		game_state.ship_controller.set_crew_orders(ship_id, {"sail_target": ""})
		_place_manual_crew(ship, "")
		return ""
	if ship.is_destroyed():
		return "Ship is destroyed"
	if ship.is_struck():
		return "Ship has struck"
	if ship.is_dismasted():
		return "Ship is dismasted"
	if ship.has_critical("lines_jammed"):
		return "Lines jammed"
	if ship.has_sail_change():
		return "A sail change is already in progress"
	if not target in available_targets(ship_id):
		return "Cannot change to %s from %s" % [target, ship.sail_state]
	game_state.ship_controller.set_crew_orders(ship_id, {"sail_target": target})
	_place_manual_crew(ship, target)
	return ""


## Manual crew (Automatic off): the order also puts worker-order sections on Sails if the station
## is short of them, and an order withdrawn sends them back (crew-tasks spec §4.8).
func _place_manual_crew(ship: ShipState, target: String) -> void:
	if ship.crew_auto or game_state.get("crew_task_controller") == null:
		return
	var ctx := CrewRules.context(game_state, ship)
	var plan := CrewRules.with_sail_order(ship, CrewRules.plan_of(ship), ctx, target)
	var normalized := CrewRules.normalize(ship, plan, ctx)
	game_state.ship_controller.set_crew_assignments(ship.ship_id, normalized.get("assignments", {}))
	game_state.ship_controller.set_crew_orders(ship.ship_id, normalized.get("orders", {"sail_target": target}))


## Abandons the change in progress at once (e.g. Lines Jammed, 5.F.9c) and logs SAIL_CHANGE
## with `reason`. Returns false when there was none.
func cancel_change(ship_id: String, reason: String, phase: int) -> bool:
	if not is_server:
		push_error("SailController: Cannot cancel sail change on client")
		return false
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or not ship.has_sail_change():
		return false
	return game_state.crew_task_controller.cancel_task(ship_id, int(ship.tasks_with(CODE)[0]["seq"]),
		reason, phase)


# --- CrewTaskHandler ---

func can_plot(ship: ShipState, sections: Array, params: Dictionary, plan: Dictionary) -> String:
	var target := str(params.get("target", ""))
	var orders: Dictionary = plan.get("orders", {})
	if ship.has_critical("lines_jammed"):
		return "Lines jammed: no sail changes (5.F.9c)"
	if target == "" or target != str(orders.get("sail_target", "")):
		return "No sail change is ordered"
	if sections.size() > sections_needed(ship, target):
		return "Sails aloft is full (%d %s)" % [sections_needed(ship, target),
			"section" if sections_needed(ship, target) == 1 else "sections"]
	return ""


func turns_required(ship: ShipState, task: Dictionary) -> int:
	return ship.task_turns_required(task)


func same_task(task: Dictionary, params: Dictionary) -> bool:
	return str((task.get("params", {}) as Dictionary).get("target", "")) == str(params.get("target", ""))


func prepare(ship: ShipState, candidate: Dictionary) -> String:
	var target := str(candidate["params"].get("target", ""))
	if ship.has_critical("lines_jammed"):
		return CANCEL_LINES_JAMMED
	if not target in targets_for(ship):
		return "not available"
	if (candidate.get("sections", []) as Array).size() < sections_needed(ship, target):
		return "no crew"
	candidate["params"]["from"] = ship.sail_state
	candidate["params"]["row"] = cost_row(ship, target)
	return ""


func on_started(ship: ShipState, task: Dictionary, phase: int) -> void:
	_log_sail(ship, str(task["params"].get("target", "")), turns_required(ship, task), phase)


func on_refused(ship: ShipState, candidate: Dictionary, reason: String, phase: int) -> void:
	var target := str(candidate["params"].get("target", ""))
	var turns := 0
	if reason == "no crew":
		turns = DataManager.combat_tables.task_turns(cost_row(ship, target), ship.crew_quality)
	_log_sail(ship, target, turns, phase, reason)


func on_complete(ship: ShipState, task: Dictionary, phase: int) -> void:
	var target := str(task["params"].get("target", ""))
	var from_state: String = ship.sail_state
	game_state.ship_controller.set_sail_state(ship.ship_id, target)
	game_state.turn_log.add(PhaseEvents.Type.SAIL_CHANGE, phase, ship.ship_id,
		{"from": from_state, "to": target, "turns_left": 0})


func on_cancel(ship: ShipState, task: Dictionary, reason: String, phase: int) -> void:
	var turns_left := maxi(0, turns_required(ship, task) - int(task.get("done", 0)))
	_log_sail(ship, str(task["params"].get("target", "")), turns_left, phase, reason)


func cancel_reason(ship: ShipState, task: Dictionary) -> String:
	if ship.is_destroyed():
		return "destroyed"
	if ship.is_struck():
		return "struck"
	if ship.is_dismasted():
		return "dismasted"
	if ship.has_critical("lines_jammed"):
		return CANCEL_LINES_JAMMED
	for section in task.get("sections", []):
		if not ship.section_alive(int(section)):
			return "crew lost"
	return ""


func _log_sail(ship: ShipState, target: String, turns_left: int, phase: int, cancelled: String = "") -> void:
	var data := {"from": ship.sail_state, "to": target, "turns_left": turns_left}
	if cancelled != "":
		data["cancelled"] = cancelled
	game_state.turn_log.add(PhaseEvents.Type.SAIL_CHANGE, phase, ship.ship_id, data)
