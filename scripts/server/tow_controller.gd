class_name TowController
extends CrewTaskHandler
## TowController - towing (Close Action 1997, 12.A; towing spec §3, §4, §6) and the crew-task
## handler of PT (prepare to tow, 12.A.3) and TX (cut the tow, 12.A.9). One instance
## (game_state.tow_controller) is registered for every TowRules.CODES code.
##
## - §3, the tasks: whether one may start is TowRules.refusal (prepare). A completed PT makes the
##   tow ready (ShipState.tow_prepared); a completed TX does nothing here (the cut is made in the
##   tow step, §6). A PT ends once the ship is towing, a TX once the tow is gone.
## - §4, the tow attempt, and §6, cutting and breaking a tow: filled in with the tow step.
##
## Dice order (game_state.dice): none yet; the tow step's rolls are listed here when it is added.


func _init(p_game_state: Node) -> void:
	super(p_game_state)


func prepare(ship: ShipState, candidate: Dictionary) -> String:
	return TowRules.refusal(ship, str(candidate.get("code", "")), [])


func on_complete(ship: ShipState, task: Dictionary, phase: int) -> void:
	if not is_server:
		push_error("TowController: Cannot complete a towing task on client")
		return
	super(ship, task, phase)
	if str(task.get("code", "")) == "PT":
		game_state.ship_controller.set_tow_prepared(ship.ship_id, true)


func cancel_reason(ship: ShipState, task: Dictionary) -> String:
	var reason := super(ship, task)
	if reason != "":
		return reason
	match str(task.get("code", "")):
		"PT":
			if ship.is_towing():
				return "towing"
		"TX":
			if ship.tow_partner() == "":
				return "no tow"
	return ""
