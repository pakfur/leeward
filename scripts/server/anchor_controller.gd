class_name AnchorController
extends CrewTaskHandler
## AnchorController - the crew-task handler of the nine anchoring codes (Close Action 1997,
## 13.B-F, SoP V.A-B; anchoring spec §3-§5). One instance (game_state.anchor_controller) is
## registered for every AnchorRules.CODES code.
##
## - 13.B: preparing an anchor (PBA, PSA) makes it ready at the bow or stern; preparing springs
##   (PBS, PSS) makes them ready for the next anchoring, or rigs them at once on a ship already
##   anchored by that end (13.B.2). A preparation ends when its reason is gone: an anchor task once
##   the ship is anchored, a springs task once its end has no anchor (the cable cut, 13.F).
## - 13.C.1: an anchoring (A) on a g-t the ship moves is erased. The MPs are the ship's actual plot:
##   the stored course, or the default course (6.G.2) when none was stored (actual_steps).
## - Whether a task may start is AnchorRules.refusal, at End Planning (ctx "final").

const ENDED_ANCHORED := "anchored"
const ENDED_NO_BOW := "no bow anchor"
const ENDED_NO_STERN := "no stern anchor"


func _init(p_game_state: Node) -> void:
	super(p_game_state)


## The MPs the ship sails this g-t: its stored course when one was plotted, else its default course
## (6.G.2).
func actual_steps(ship: ShipState) -> int:
	if bool(ship.plotted_actions.get("movement_plotted", false)):
		return (ship.plotted_actions.get("movement", []) as Array).size()
	return DefaultCourse.for_ship(game_state, ship).size()


## The live task with `code` begun this g-t, or {}.
func live_this_turn(ship: ShipState, code: String) -> Dictionary:
	var turn := int(game_state.current_turn)
	for task in ship.tasks_with(code):
		if int(task.get("started_turn", -1)) == turn:
			return task
	return {}


func prepare(ship: ShipState, candidate: Dictionary) -> String:
	var ctx := CrewRules.context(game_state, ship)
	ctx["final"] = true
	ctx["plotted_mps"] = actual_steps(ship)
	var raw = candidate.get("params", {})
	var params: Dictionary = raw if raw is Dictionary else {}
	return AnchorRules.refusal(ship, str(candidate.get("code", "")), params, ctx, [])


func on_complete(ship: ShipState, task: Dictionary, phase: int) -> void:
	super(ship, task, phase)
	var sc: ShipStateController = game_state.ship_controller
	var id := ship.ship_id
	match str(task.get("code", "")):
		"PBA":
			sc.set_anchor_ready(id, "bow")
		"PSA":
			sc.set_anchor_ready(id, "stern")
		"PBS":
			_springs_done(ship, "bow")
		"PSS":
			_springs_done(ship, "stern")


func cancel_reason(ship: ShipState, task: Dictionary) -> String:
	var reason := super(ship, task)
	if reason != "":
		return reason
	match str(task.get("code", "")):
		"PBA", "PSA":
			if ship.is_anchored():
				return ENDED_ANCHORED
		"PBS":
			if not _has_anchor_at(ship, "bow"):
				return ENDED_NO_BOW
		"PSS":
			if not _has_anchor_at(ship, "stern"):
				return ENDED_NO_STERN
	return ""


## 13.B.2: springs rigged at once on a ship anchored by `end`, else ready for the next anchoring.
func _springs_done(ship: ShipState, end: String) -> void:
	var sc: ShipStateController = game_state.ship_controller
	if _anchored_by(ship, end):
		sc.update_anchor(ship.ship_id, {"springs": true})
	else:
		sc.set_springs_ready(ship.ship_id, true)


static func _anchored_by(ship: ShipState, end: String) -> bool:
	return ship.is_anchored() and str(ship.anchor.get("end", "bow")) == end


## An anchor ready or let go at `end`.
static func _has_anchor_at(ship: ShipState, end: String) -> bool:
	return ship.anchor_ready == end or _anchored_by(ship, end)
