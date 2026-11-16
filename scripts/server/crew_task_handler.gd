class_name CrewTaskHandler
extends RefCounted
## CrewTaskHandler - one crew task code (4.A.3, 4.B; crew-tasks spec §3.1). CrewTaskController
## keeps the tasks and counts their g-t's; a handler says whether a task may start, how long it
## takes, what completing it does and when it is cancelled. Subclasses override what they need.
## The default handler logs CREW_TASK events and takes its length from crew_tasks.json.

## Flags (spec §3.1).
## forced: the section cannot be moved by the player (RO, engaged boarders).
var forced: bool = false
## abandonable: false when the task, once begun, must be completed (a sail change, 5.F.9).
var abandonable: bool = true
## fire_exempt: never called away to fight a fire (RO, engaged boarding, 8.E.2).
var fire_exempt: bool = false
## marines_available: marines on this task still count as available (FB, BR, BD; 10.B.4-5).
var marines_available: bool = false
## section_order: "" or "lowest_sailor_first" (boarders, 4.B.1).
var section_order: String = ""
## one_turn: the task ends at the end of every g-t (T).
var one_turn: bool = false

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node = null) -> void:
	game_state = p_game_state


## "" when `sections` may be plotted to this task with `params` in `plan`, else the reason.
func can_plot(_ship: ShipState, _sections: Array, _params: Dictionary, _plan: Dictionary) -> String:
	return ""


## G-t's needed at the ship's current crew quality (9.A.2); -1 = open-ended.
func turns_required(ship: ShipState, task: Dictionary) -> int:
	return ship.task_turns_required(task)


## Whether this g-t counts towards the task (advance_tasks), when its sections were plotted.
## RO does not count the g-t it began in.
func counts_turn(_ship: ShipState, _task: Dictionary) -> bool:
	return true


## Whether plotted `params` continue `task` (same identifying parameter, e.g. the sail target).
func same_task(_task: Dictionary, _params: Dictionary) -> bool:
	return true


## Start of MOVEMENT_RESOLUTION, before a new task is added: "" to start it, else the reason it
## does not start. May fill in `candidate.params`.
func prepare(_ship: ShipState, _candidate: Dictionary) -> String:
	return ""


func on_started(ship: ShipState, task: Dictionary, phase: int) -> void:
	_log(ship, task, "started", "", phase)


func on_refused(ship: ShipState, candidate: Dictionary, reason: String, phase: int) -> void:
	_log(ship, candidate, "refused", reason, phase)


func on_complete(ship: ShipState, task: Dictionary, phase: int) -> void:
	_log(ship, task, "completed", "", phase)


func on_cancel(ship: ShipState, task: Dictionary, reason: String, phase: int) -> void:
	_log(ship, task, "cancelled" if reason != CrewTaskController.ABANDONED else "abandoned", reason, phase)


## 8.E.2, 10.B.5: a fire broke out aboard the ship (the boarding handler disbands unengaged boarders).
func on_fire_breaks_out(_ship_id: String) -> void:
	pass


## After movement (CrewTaskController.after_movement): a reason the task ends because of the
## movement just made (8.F.3b: hull repair and more than 4 MPs), or "".
func after_movement_reason(_ship: ShipState, _task: Dictionary) -> String:
	return ""


## The task's progress went back to 0 (8.F.6). Logs CREW_TASK with state "reset".
func on_reset(ship: ShipState, task: Dictionary, reason: String, phase: int) -> void:
	_log(ship, task, "reset", reason, phase)


## A reason the task ends now (checked in advance_tasks), or "".
func cancel_reason(ship: ShipState, task: Dictionary) -> String:
	if ship.is_destroyed():
		return "destroyed"
	if ship.is_struck() and str(task.get("code", "")) != "FF":
		return "struck"  # a struck ship only fights fires (9.C.3)
	for section in task.get("sections", []):
		if not ship.section_alive(int(section)):
			return "crew lost"
	return ""


func _log(ship: ShipState, task: Dictionary, state: String, reason: String, phase: int) -> void:
	if game_state == null or game_state.get("turn_log") == null:
		return
	var data := {
		"code": str(task.get("code", "")),
		"sections": (task.get("sections", []) as Array).duplicate(),
		"params": (task.get("params", {}) as Dictionary).duplicate(true),
		"state": state,
		"done": int(task.get("done", 0)),
		"needed": turns_required(ship, task),
	}
	if reason != "":
		data["reason"] = reason
	game_state.turn_log.add(PhaseEvents.Type.CREW_TASK, phase, ship.ship_id, data)
