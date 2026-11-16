class_name BoardingTaskHandler
extends CrewTaskHandler
## BoardingTaskHandler - the boarding crew tasks FB, BR, BA and BD (Close Action 1997, 10.B-10.C;
## boarding spec §2.4). One instance per code is registered with the CrewTaskController (each task
## dict copies its handler's marines_available flag). One section per task: params {"section": s}
## (+ "target" for BA); while engaged in a boarding action the task is forced and carries "action"
## and "enemy" (BoardingController).
##
## - FB lasts one g-t (10.B.2); when it completes the section is readied: a BR task is added (10.B.3).
## - BR is open-ended: it continues every g-t it is plotted again, until BA or BD (10.B.3).
## - BA lasts the g-t it boards; engaged, it goes on until the action ends (10.E.1).
## - BD lasts one g-t (10.B.5).
## - Engaged tasks are open-ended, forced and never called to a fire (8.E.2, 10.E.1).
## - A fire breaking out disbands every FB and BR task not engaged (8.E.2; on_fire_breaks_out).
## Rules for plotting live in BoardingRules; actions in BoardingController.

const CODES: Array[String] = ["FB", "BR", "BA", "BD"]
## Reasons a boarding task ends quietly (another log line says why).
const QUIET_REASONS: Array[String] = ["boarding", "captured", "repulsed", "boarders away", "action over"]

var code: String = ""


func _init(p_game_state: Node, p_code: String = "FB") -> void:
	super(p_game_state)
	code = p_code
	section_order = "lowest_sailor_first"
	marines_available = code != "BA"  # 10.B.4-5: FB, BR and BD marines may still fire and count as available
	abandonable = true


## Engaged in an action: open-ended. BR: open-ended (re-plotted each g-t). FB, BA, BD: one g-t.
func turns_required(_ship: ShipState, task: Dictionary) -> int:
	if engaged(task) or str(task.get("code", "")) == "BR":
		return -1
	return 1


static func engaged(task: Dictionary) -> bool:
	return int((task.get("params", {}) as Dictionary).get("action", -1)) >= 0


## The plotted section and target continue the task (other params are the server's).
func same_task(task: Dictionary, params: Dictionary) -> bool:
	var tp: Dictionary = task.get("params", {})
	if engaged(task):
		return true
	return int(tp.get("section", -1)) == int(params.get("section", -2)) \
		and str(tp.get("target", "")) == str(params.get("target", ""))


func on_started(ship: ShipState, task: Dictionary, phase: int) -> void:
	if game_state == null or game_state.get("turn_log") == null:
		return
	var c := str(task.get("code", ""))
	if c == "BA" or (c == "FB" and bool(task.get("forced", false))):
		return  # BOARDERS_AWAY / MARINES_DEFEND are logged by BoardingController
	if c == "FB" or c == "BD":
		# 10.B.6: forming boarders is announced to everyone.
		game_state.turn_log.add(PhaseEvents.Type.BOARDERS, phase, ship.ship_id, {
			"sections": (task.get("sections", []) as Array).duplicate(), "task": c})


## FB done: the section is readied and plots BR from the next g-t (10.B.3). BD done: free again.
func on_complete(ship: ShipState, task: Dictionary, phase: int) -> void:
	var c := str(task.get("code", ""))
	if c == "FB" and game_state != null and not ship.is_out_of_play():
		var section := int((task.get("params", {}) as Dictionary).get("section", -1))
		if section >= 0 and ship.section_alive(section):
			game_state.ship_controller.add_task(ship.ship_id, {
				"code": "BR", "sections": [section], "params": {"section": section},
				"forced": false, "marines_available": true,
			})
	elif c == "BD":
		_log(ship, task, "completed", "", phase)


func on_cancel(ship: ShipState, task: Dictionary, reason: String, phase: int) -> void:
	var c := str(task.get("code", ""))
	if reason == CrewTaskController.ABANDONED and c == "BR":
		return  # a readied section that goes away (BA) or disbands (BD): the new task says so
	if QUIET_REASONS.has(reason):
		return
	_log(ship, task, "cancelled" if reason != CrewTaskController.ABANDONED else "abandoned", reason, phase)


## 8.E.2: a fire breaks out: every boarding task not yet engaged (FB, BR) is disbanded; the
## sections are free the next g-t.
func on_fire_breaks_out(ship_id: String) -> void:
	if code != "FB" and code != "BR":
		return
	var ship: ShipState = game_state.get_ship(ship_id) if game_state != null else null
	if ship == null:
		return
	var phase: int = game_state.phase_controller.current_phase if game_state.get("phase_controller") != null else 0
	for task in ship.tasks_with(code):
		if not engaged(task):
			game_state.crew_task_controller.cancel_task(ship_id, int(task["seq"]), "disbanded: fire aboard", phase)
