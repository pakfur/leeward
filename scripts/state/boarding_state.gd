class_name BoardingAction
extends RefCounted
## BoardingAction - one boarding action between an attacking and a defending ship (Close Action
## 1997, 10.C-10.E; boarding spec §2.3). Pure data: BoardingController creates and changes these
## (GameState.boarding_actions); views only read them.
##
## Sections are crew section indices (0-3 sailors S1-S4, 4 = marines).
## state: "declared" (BA announced this g-t, not yet fought), "engaged" (fought at least one round
## and still going, 10.E.1), "attacker_won" (the defender was captured; kept until the prize crew is
## aboard), "defender_won" (repulsed or driven off; kept for one more g-t for counter-boarding, 10.E.4).

const DECLARED := "declared"
const ENGAGED := "engaged"
const ATTACKER_WON := "attacker_won"
const DEFENDER_WON := "defender_won"

var id: int = 0
var attacker_id: String = ""
var defender_id: String = ""
var attacker_sections: Array[int] = []
var defender_sections: Array[int] = []
var started_turn: int = 0
var rounds: int = 0
var state: String = DECLARED
## Chosen prize-crew size, 0 = the minimum (10.G.6; the choice arrives with boarding spec B5).
var prize_size: int = 0
## The g-t the action was won (attacker_won / defender_won), else -1.
var finished_turn: int = -1
## How it ended: "captured", "struck" (10.A.3), "undefended" (10.E.2b), "all_defenders_lost",
## "struck_in_action" (10.E.2c), "overwhelmed" (10.F.2: a sixth ship boards her), "shared_capture"
## (10.F: taken in another action), "repulsed", "attackers_lost", "surrendered" (10.D.6),
## "target_gone"; "" while live.
var outcome: String = ""
## The defender had struck before it was boarded (10.A.3: no reorganizing).
var struck_target: bool = false
## The prize crew has been put aboard (10.G.7), or none is needed (a recapture, or the prize is
## gone): the won action is finished once its boarders end their RO.
var prize_aboard: bool = false
## 10.G.5: the defender is a prize whose captors were reorganizing aboard it. helper_id is the
## captor (the parent ship), helper_sections its reorganizing sections, now defending; the prize's
## original crew joins the defence at CQ G when original_crew_joins (boarding spec §1.5, §3.4).
## prize_action is the id of the action that took the prize (its RO starts again if they hold).
var helper_id: String = ""
var helper_sections: Array[int] = []
var original_crew_joins: bool = false
var prize_action: int = -1
## The attacker took back a prize of its own side (no prize crew; the original crew is freed).
var retaken: bool = false
## 10.F: the defender was taken in another action (`shared_with`, its id) while this one was still
## being fought: these boarders are aboard her as she is taken and reorganize too (10.G.2, the 10.F.3
## example), then return; the prize crew comes from the action that took her only. -1 = not shared.
var shared_with: int = -1


func is_live() -> bool:
	return state == DECLARED or state == ENGAGED


func involves(ship_id: String) -> bool:
	return attacker_id == ship_id or defender_id == ship_id


## The enemy of `ship_id` in this action ("" when the ship is not in it).
func enemy_of(ship_id: String) -> String:
	if ship_id == attacker_id:
		return defender_id
	if ship_id == defender_id:
		return attacker_id
	return ""


## The ship's sections in the action.
func sections_of(ship_id: String) -> Array[int]:
	if ship_id == attacker_id:
		return attacker_sections
	if ship_id == defender_id:
		return defender_sections
	return []


func to_dict() -> Dictionary:
	return {
		"id": id, "attacker_id": attacker_id, "defender_id": defender_id,
		"attacker_sections": attacker_sections.duplicate(), "defender_sections": defender_sections.duplicate(),
		"started_turn": started_turn, "rounds": rounds, "state": state, "prize_size": prize_size,
		"finished_turn": finished_turn, "outcome": outcome, "struck_target": struck_target,
		"prize_aboard": prize_aboard, "helper_id": helper_id, "helper_sections": helper_sections.duplicate(),
		"original_crew_joins": original_crew_joins, "prize_action": prize_action, "retaken": retaken,
		"shared_with": shared_with,
	}


static func from_dict(data: Dictionary) -> BoardingAction:
	var a := BoardingAction.new()
	a.id = int(data.get("id", 0))
	a.attacker_id = str(data.get("attacker_id", ""))
	a.defender_id = str(data.get("defender_id", ""))
	for s in data.get("attacker_sections", []):
		a.attacker_sections.append(int(s))
	for s in data.get("defender_sections", []):
		a.defender_sections.append(int(s))
	a.started_turn = int(data.get("started_turn", 0))
	a.rounds = int(data.get("rounds", 0))
	a.state = str(data.get("state", DECLARED))
	a.prize_size = int(data.get("prize_size", 0))
	a.finished_turn = int(data.get("finished_turn", -1))
	a.outcome = str(data.get("outcome", ""))
	a.struck_target = bool(data.get("struck_target", false))
	a.prize_aboard = bool(data.get("prize_aboard", false))
	a.helper_id = str(data.get("helper_id", ""))
	for s in data.get("helper_sections", []):
		a.helper_sections.append(int(s))
	a.original_crew_joins = bool(data.get("original_crew_joins", false))
	a.prize_action = int(data.get("prize_action", -1))
	a.retaken = bool(data.get("retaken", false))
	a.shared_with = int(data.get("shared_with", -1))
	return a


func duplicate_action() -> BoardingAction:
	return BoardingAction.from_dict(to_dict())
