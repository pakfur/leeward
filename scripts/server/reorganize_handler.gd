class_name ReorganizeHandler
extends CrewTaskHandler
## ReorganizeHandler - the RO crew task (crew-tasks spec §3.6): a disorganized section reorganizes
## for 5 g-t's ± SK (Hull Critical Hits #4; ship log Crew Task Order Codes), recomputed from the
## current crew quality every g-t (9.A.2). Forced on the section (CrewTaskController.force_task):
## it cannot be moved, abandoned or called to a fire (8.E.2), and does not serve the guns (spec
## §0.3 #3; Majestic g-t 17). Its time is counted from the g-t after the one it began in ("S4 must
## now plot RO for the next 5 g-ts ± SK", Majestic g-t 16).

const CODE := "RO"
## params.reason for a section disorganized by hull critical #4 (ShipState.is_disorganized).
const REASON_DISORGANIZED := "crew_disorganized"


func _init(p_game_state: Node) -> void:
	super(p_game_state)
	forced = true
	abandonable = false
	fire_exempt = true


## The g-t the task began in does not count towards it.
func counts_turn(_ship: ShipState, task: Dictionary) -> bool:
	return int(task.get("started_turn", 0)) < _current_turn()


func _current_turn() -> int:
	var turn = game_state.get("current_turn") if game_state != null else null
	return int(turn) if turn != null else 0
