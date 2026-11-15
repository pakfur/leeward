class_name TackCrewHandler
extends CrewTaskHandler
## TackCrewHandler - the T crew task: sections at the braces for a turn at MA 0 (Close Action
## 1997, 5.D.1-2; crew-tasks spec §3.6). Plotted only when the movement plot holds a turn at MA 0
## (CrewRules.context ma0_turn_plotted); 1-3 sections; the task lasts the g-t it is plotted. The
## Tacking roll (MovementResolver._calculate_tacking_drm) adds +2 for each section short of 3, at
## most +6 (5.D.2a). Its sections do not serve the guns that g-t, even if the tack fails (spec
## §0.3 #2; Majestic g-t 17).

const CODE := "T"


func _init(p_game_state: Node) -> void:
	super(p_game_state)
	one_turn = true


## Most sections the braces take (crew_tasks.json "T" sections [1, 3]).
static func max_sections() -> int:
	var sections: Array = DataManager.combat_tables.task_sections(CODE)
	return int(sections[1]) if sections.size() > 1 else 3


func can_plot(_ship: ShipState, sections: Array, _params: Dictionary, _plan: Dictionary) -> String:
	if sections.size() > max_sections():
		return "Braces (tacking) is full (%d sections)." % max_sections()
	return ""


func prepare(_ship: ShipState, candidate: Dictionary) -> String:
	if (candidate.get("sections", []) as Array).size() > max_sections():
		return "too many sections"
	return ""
