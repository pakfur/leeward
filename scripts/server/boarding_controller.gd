class_name BoardingController
extends RefCounted
## BoardingController - boarding actions and capture (Close Action 1997, 10.A-10.E, 10.G; boarding
## spec §3.4). Server only; every mutation goes through ShipStateController, DamageController, the
## CrewTaskController and GameState.transfer_control. Actions live in GameState.boarding_actions.
##
## Turn placement (boarding spec §3.1):
##   PLANNING, on entry      take_link_snapshot(): GameState.linked_at_plot (10.A.2)
##   COMBAT_RESOLUTION entry declare(): BA announced, the defender's marines replotted to FB
##                            (10.C.3), struck or undefended defenders captured at once (10.E.2a-b)
##   COMBAT RESOLVE          resolve(): after all gunfire and marine fire (10.C.4)
##   STATUS_ADJUSTMENT       advance_reorganizing(): after the crew tasks are counted (and the prize-
##                            crew size chosen, prize_size_options / set_prize_size), the prize crew
##                            of an action whose RO tasks all ended is put aboard (10.G.6-7)
##   END_TURN                end_of_turn(): finished actions dropped, the turn's snapshot kept
##   next turn's start       start_of_turn(): 10.H.4, a prize crew below the minimum against an
##                            original crew of twice its boxes loses the ship (RECAPTURED)
##
## Prizes (10.G.5, 10.H; boarding spec B5): a prize with its prize crew aboard plots boarding and
## repairs like any ship (CrewRules); it may be boarded. Boarded while its captors reorganize aboard
## her, their RO ends, they defend (forced FB, BoardingAction.helper_*), and her original crew joins
## the defence at CQ G (spec §1.5, §3.4); if they hold, RO starts again. When the prize's own side
## wins, she is retaken: back to her side, ACTIVE, her original crew freed at G6 (as 10.H.4), the
## defenders taken prisoner; the winning boarders reorganize (10.G.2) and then return with no prize
## crew (spec §8 Q5: she scores by her state at the end).
##
## Dice order (the contract for ScriptedDice; boarding spec §3.3):
##   declare: per mutual boarding (both ships BA at each other, 10.C.5b) in (defender, attacker) id
##     order, one d6 only when TBCF and CQ tie (1-3: the lower ship_id attacks).
##   resolve, per action in (defender_id, attacker_id) order: attacker 2d6, defender 2d6; the
##     defender's loss d6s, then the attacker's (one per box, none while one crew type is in the
##     action, DamageController.apply_boarding_losses); the special-result d10 only for a "< MR"
##     result that survives 10.D.5. TBCFs are all taken before any result (10.F.3).
##
##   With defenders from several contingents (10.G.5: the prize's live crew, the captor's boarders,
##   the original crew below), the defender's loss d6s are rolled box by box across all of them, and
##   each box is taken from the first contingent in that order that has that type
##   (DamageController.apply_boarding_losses_shared).
##
## Not here yet (boarding spec B6): several ships in one action (10.F; a second boarder of a ship
## already in an action is refused).

const QUALITY_ORDER := "ABCDEFG"
## Morale-check trigger prefix for "attacker repulsed and takes n MC" (unique per action and g-t).
const MC_TRIGGER := "boarding_%d_%d"
## 10.H.4 (and a prize boarded back by her own side): the crew that retakes the ship.
const RETAKEN_QUALITY := "G"
const RETAKEN_MORALE := 6
## 10.G.5: the original crew joins a new boarding action at CQ G.
const BELOW_QUALITY := "G"

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


# --- Queries (pure) ---

func actions() -> Array:
	return game_state.boarding_actions


func action_by_id(id: int) -> BoardingAction:
	for a in game_state.boarding_actions:
		if a.id == id:
			return a
	return null


## The live (declared or engaged) action the ship is in, or null.
func live_action_of(ship_id: String) -> BoardingAction:
	for a in game_state.boarding_actions:
		if a.is_live() and a.involves(ship_id):
			return a
	return null


## The live action between two ships, or null.
func live_action_between(a_id: String, b_id: String) -> BoardingAction:
	for a in game_state.boarding_actions:
		if a.is_live() and a.involves(a_id) and a.involves(b_id):
			return a
	return null


## Ships locked in a boarding action with each other may not ungrapple or unfoul from each other
## (8.C.5, 8.D.4, 10.D.8).
func locked_in_boarding(a_id: String, b_id: String) -> bool:
	return live_action_between(a_id, b_id) != null


## The ship's marines fight in a boarding action (8.C.5: +1 "marines not available").
func marines_in_boarding(ship: ShipState) -> bool:
	return ship != null and ship.marines_in_boarding()


## Counter-boarding (10.E.4): enemy_id -> the sections of `ship_id` that defended in an action the
## attacker lost by repulse on the previous g-t (S4 excluded).
func counter_board(ship_id: String) -> Dictionary:
	var out := {}
	var turn := _turn()
	for a in game_state.boarding_actions:
		if a.state == BoardingAction.DEFENDER_WON and a.defender_id == ship_id \
				and a.finished_turn == turn - 1 and a.outcome == "repulsed":
			var secs: Array = []
			for s in a.defender_sections:
				if s != BoardingRules.MINIMUM_CREW_SECTION:
					secs.append(s)
			out[a.attacker_id] = secs
	return out


## Total Boarding Combat Factor of `sections` of the ship (10.D.1): BCF per box at its current CQ.
func tbcf(ship_id: String, sections: Array) -> int:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return 0
	return tbcf_of(ship, sections, ship.crew_quality)


static func tbcf_of(ship: ShipState, sections: Array, quality: String) -> int:
	var tables: CombatTables = DataManager.combat_tables
	var total := 0
	for s in sections:
		total += ship.section_boxes(int(s)) * tables.bcf(quality, int(s) == ShipState.MARINES)
	return total


## The DRMs of a fight between attacker TBCF `att` and defender TBCF `def` (10.D.2):
## {"attacker": {"odds", "other", "total"}, "defender": {"odds", "other", "total"}}.
func drms_for(attacker: ShipState, defender: ShipState, att: int, def: int) -> Dictionary:
	var tables: CombatTables = DataManager.combat_tables
	var a_odds := tables.odds_drm(att, def)
	var d_odds := tables.odds_drm(def, att)
	var other := tables.boarding_class_drm(_class(defender), _class(attacker))
	return {"attacker": {"odds": a_odds, "other": other, "total": a_odds + other},
		"defender": {"odds": d_odds, "other": 0, "total": d_odds}}


## For the overlay's "Board ‹enemy›!" entry (spec §4.2): the odds as they stand. `sections` are the
## ship's sections that would go; the enemy counts only its announced boarders and its marines.
## {"tbcf", "enemy_tbcf", "drm"}.
func preview(ship_id: String, enemy_id: String, sections: Array) -> Dictionary:
	var ship: ShipState = game_state.get_ship(ship_id)
	var enemy: ShipState = game_state.get_ship(enemy_id)
	if ship == null or enemy == null:
		return {"tbcf": 0, "enemy_tbcf": 0, "drm": 0}
	var att := tbcf_of(ship, sections, ship.crew_quality)
	var def := tbcf_of(enemy, visible_defence(enemy), enemy.crew_quality)
	return {"tbcf": att, "enemy_tbcf": def, "drm": int(drms_for(ship, enemy, att, def)["attacker"]["total"])}


## The sections an enemy can see defending `ship`: its boarders (FB, BR, BA; public, 10.B.6) and its
## marines (who defend whenever it is boarded, 10.C.3).
static func visible_defence(ship: ShipState) -> Array[int]:
	var out: Array[int] = []
	for s in range(ShipState.MARINES + 1):
		if not ship.section_alive(s):
			continue
		var code := str(ship.boarding_task(s).get("code", ""))
		if ShipState.BOARDER_CODES.has(code) or s == ShipState.MARINES:
			out.append(s)
	return out


## Whether any action is to be fought this g-t (declared or engaged).
func has_actions_to_resolve() -> bool:
	for a in game_state.boarding_actions:
		if a.is_live():
			return true
	return false


# --- PLANNING ---

## PLANNING begins: every ship's fouled and grappled partners now are the ones it may board this
## g-t (10.A.2: "fouled or grappled at the beginning of the current g-t").
func take_link_snapshot() -> void:
	if not is_server:
		push_error("BoardingController: Cannot take the link snapshot on client")
		return
	var links := {}
	for ship: ShipState in game_state.get_all_ships():
		links[ship.ship_id] = Array(ship.linked_ids())
	game_state.linked_at_plot = links


# --- COMBAT_RESOLUTION: declare ---

## SoP IV.A, 10.C.4a: boarders away. For each ship with BA tasks begun this g-t, by target: refused
## if the target can no longer be boarded (back to BR); joined to the live action if there is one
## (10.E.1); else a new action, its attacker by 10.C.5. The defender's marines are replotted to FB
## (10.C.3). A struck defender (10.E.2a) or one with no section to defend (10.E.2b) is captured at
## once, with no roll. Returns true when anything was announced (the combat phase then shows it).
func declare(phase: int) -> bool:
	if not is_server:
		push_error("BoardingController: Cannot declare boarding on client")
		return false
	var announced := false
	var boardings := {}  # "attacker|target" -> sections
	for ship_id in _sorted_ids():
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or not ship.crew_can_act():
			continue
		for task in ship.tasks_with(BoardingRules.BA):
			if BoardingTaskHandler.engaged(task):
				continue
			var section := int(task.get("params", {}).get("section", -1))
			var target := str(task.get("params", {}).get("target", ""))
			var key := "%s|%s" % [ship_id, target]
			if not boardings.has(key):
				boardings[key] = []
			boardings[key].append(section)
	# Mutual boardings (10.C.5b) become one, decided by TBCF, then CQ, then a d6.
	var keys: Array = boardings.keys()
	var pairs: Array = []  # [attacker, target, sections, defending_ba_sections]
	var seen := {}
	keys.sort_custom(func(a: String, b: String) -> bool:
		var pa := a.split("|")
		var pb := b.split("|")
		return [pa[1], pa[0]] < [pb[1], pb[0]])
	for key in keys:
		if seen.has(key):
			continue
		var parts: PackedStringArray = key.split("|")
		var a_id := parts[0]
		var t_id := parts[1]
		var back := "%s|%s" % [t_id, a_id]
		seen[key] = true
		var a_secs: Array = boardings[key]
		var t_secs: Array = []
		if boardings.has(back) and not seen.has(back):
			seen[back] = true
			t_secs = boardings[back]
			var attacker := _mutual_attacker(a_id, a_secs, t_id, t_secs)
			if attacker == t_id:
				pairs.append([t_id, a_id, t_secs, a_secs])
				continue
		pairs.append([a_id, t_id, a_secs, t_secs])
	for p in pairs:
		if _board(str(p[0]), str(p[1]), p[2], p[3], phase):
			announced = true
	return announced


## 10.C.5b: the attacker of a mutual boarding: higher TBCF, then better CQ, then a d6 (1-3: the
## lower ship_id).
func _mutual_attacker(a_id: String, a_secs: Array, b_id: String, b_secs: Array) -> String:
	var a := tbcf(a_id, a_secs)
	var b := tbcf(b_id, b_secs)
	if a != b:
		return a_id if a > b else b_id
	var qa := QUALITY_ORDER.find(game_state.get_ship(a_id).crew_quality)
	var qb := QUALITY_ORDER.find(game_state.get_ship(b_id).crew_quality)
	if qa != qb:
		return a_id if qa < qb else b_id
	var low := a_id if a_id < b_id else b_id
	var high := b_id if a_id < b_id else a_id
	return low if game_state.dice.d6() <= 3 else high


## One boarding by `attacker_id` at `target_id` with `sections`; `defending_ba` are the target's BA
## sections aimed back at the attacker (they defend, spec 0.4 #2). Returns true when announced.
func _board(attacker_id: String, target_id: String, sections: Array, defending_ba: Array, phase: int) -> bool:
	var attacker: ShipState = game_state.get_ship(attacker_id)
	var target: ShipState = game_state.get_ship(target_id)
	var why := BoardingRules.boardable_error(attacker, target, game_state.linked_at_plot.get(attacker_id, []))
	if why == "" and attacker.is_burning():
		why = BoardingRules.FIRE_REFUSAL
	var existing := live_action_between(attacker_id, target_id)
	if why == "" and existing == null and (live_action_of(attacker_id) != null or live_action_of(target_id) != null):
		why = "boarding with more than one enemy ship is not yet simulated (10.F)"
	if why != "":
		for s in sections:
			_back_to_ready(attacker_id, int(s), why, phase)
		Trace.trace_log("Boarding", "%s cannot board %s: %s" % [attacker_id, target_id, why])
		return false
	if existing != null:
		# 10.E.1: more sections join a live action.
		var side := existing.sections_of(attacker_id)
		for s in sections:
			if not side.has(int(s)):
				side.append(int(s))
		side.sort()
		_engage_tasks(existing)
		game_state.turn_log.add(PhaseEvents.Type.BOARDERS_AWAY, phase, attacker_id,
			{"sections": sections.duplicate(), "joins": true}, target_id)
		_set_order(attacker_id, "ready")
		return true
	var action := BoardingAction.new()
	game_state.boarding_seq += 1
	action.id = game_state.boarding_seq
	action.attacker_id = attacker_id
	action.defender_id = target_id
	for s in sections:
		action.attacker_sections.append(int(s))
	action.attacker_sections.sort()
	action.started_turn = _turn()
	game_state.boarding_actions.append(action)
	game_state.turn_log.add(PhaseEvents.Type.BOARDERS_AWAY, phase, attacker_id,
		{"sections": action.attacker_sections.duplicate(), "action": action.id}, target_id)
	_set_order(attacker_id, "ready")
	if target.is_struck():
		capture(action, true, phase)  # 10.A.3, 10.E.2a
		return true
	# The defenders: every FB/BR section, its BA sections aimed back (0.4 #2), and the marines (10.C.3).
	var defenders: Array[int] = []
	for s in range(ShipState.MARINES + 1):
		if not target.section_alive(s):
			continue
		var code := str(target.boarding_task(s).get("code", ""))
		if code == "FB" or code == "BR" or (code == "BA" and defending_ba.has(s)):
			defenders.append(s)
	if target.section_alive(ShipState.MARINES) and not defenders.has(ShipState.MARINES):
		var old := target.task_of(ShipState.MARINES)
		game_state.crew_task_controller.force_task(target_id, [ShipState.MARINES], "FB",
			{"reason": "repel boarders", "section": ShipState.MARINES}, phase)
		defenders.append(ShipState.MARINES)
		game_state.turn_log.add(PhaseEvents.Type.MARINES_DEFEND, phase, target_id,
			{"cancelled_task": str(old.get("code", "")), "done": int(old.get("done", 0))}, attacker_id)
	defenders.sort()
	action.defender_sections = defenders
	_reorganizers_defend(action, target, phase)  # 10.G.5
	if _defence_empty(action):
		capture(action, false, phase, "undefended")  # 10.E.2b
		return true
	_engage_tasks(action)
	return true


## 10.G.5: the prize `target` is boarded while the boarders who took her reorganize aboard her:
## their reorganization is aborted and they defend (forced FB on the parent's log), and the prize's
## original crew joins the defence at CQ G (boarding spec §1.5, §3.4).
func _reorganizers_defend(action: BoardingAction, target: ShipState, phase: int) -> void:
	if not target.is_captured():
		return
	var taking := reorganizing_capture_of(target.ship_id)
	if taking == null:
		return
	var captor: ShipState = game_state.get_ship(taking.attacker_id)
	var secs: Array[int] = []
	for task in captor.tasks_with(ReorganizeHandler.CODE):
		var params: Dictionary = task.get("params", {})
		if int(params.get("action", -1)) != taking.id:
			continue
		for s in task.get("sections", []):
			if captor.section_alive(int(s)) and not secs.has(int(s)):
				secs.append(int(s))
	secs.sort()
	for s in secs:
		game_state.crew_task_controller.force_task(captor.ship_id, [s], "FB",
			{"reason": "defend the prize", "section": s, "prize": target.ship_id}, phase)
	action.helper_id = captor.ship_id
	action.helper_sections = secs
	action.prize_action = taking.id
	action.original_crew_joins = target.original_crew_boxes() > 0
	game_state.turn_log.add(PhaseEvents.Type.REORGANIZING_ABORTED, phase, captor.ship_id,
		{"sections": secs.duplicate(), "action": action.id, "original_crew": target.original_crew_boxes()},
		target.ship_id)


## The won action whose boarders are still reorganizing aboard the prize `prize_id` (RO tasks
## live for it), or null.
func reorganizing_capture_of(prize_id: String) -> BoardingAction:
	for a in game_state.boarding_actions:
		if a.state != BoardingAction.ATTACKER_WON or a.prize_aboard or a.retaken or a.defender_id != prize_id:
			continue
		var captor: ShipState = game_state.get_ship(a.attacker_id)
		if captor == null:
			continue
		for task in captor.tasks_with(ReorganizeHandler.CODE):
			if int(task.get("params", {}).get("action", -1)) == a.id:
				return a
	return null


## The defence has nothing left: no section of the defender, none of the captor's boarders
## (10.G.5) and no original crew joining.
func _defence_empty(action: BoardingAction) -> bool:
	if not action.defender_sections.is_empty() or not action.helper_sections.is_empty():
		return false
	if action.original_crew_joins:
		var def: ShipState = game_state.get_ship(action.defender_id)
		return def == null or def.original_crew_boxes() <= 0
	return true


## The defence's TBCF (10.D.1): the defender's sections at its CQ, the captor's boarders at theirs
## and the original crew below at CQ G (10.G.5).
func defence_tbcf(action: BoardingAction) -> int:
	var def: ShipState = game_state.get_ship(action.defender_id)
	if def == null:
		return 0
	var total := tbcf_of(def, action.defender_sections, def.crew_quality)
	var helper: ShipState = game_state.get_ship(action.helper_id) if action.helper_id != "" else null
	if helper != null:
		total += tbcf_of(helper, action.helper_sections, helper.crew_quality)
	if action.original_crew_joins:
		total += below_tbcf(def)
	return total


## BCF of the prize's original crew below at CQ G (10.G.5).
static func below_tbcf(prize: ShipState) -> int:
	var tables: CombatTables = DataManager.combat_tables
	var crew: Dictionary = prize.prize.get("original_crew", {})
	var total := int(crew.get("marine_count", 0)) * tables.bcf(BELOW_QUALITY, true)
	for b in crew.get("crew_count", []):
		total += int(b) * tables.bcf(BELOW_QUALITY, false)
	return total


## A BA section whose boarding was refused stays a readied boarder (BR).
func _back_to_ready(ship_id: String, section: int, reason: String, phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	var task := ship.boarding_task(section)
	if task.is_empty():
		return
	game_state.crew_task_controller.cancel_task(ship_id, int(task["seq"]), reason, phase)
	game_state.ship_controller.add_task(ship_id, {"code": "BR", "sections": [section],
		"params": {"section": section}, "forced": false, "marines_available": true})


## Marks every section of a live action as engaged: forced, with the action and the enemy (10.E.1).
func _engage_tasks(action: BoardingAction) -> void:
	var sides := [[action.attacker_id, action.attacker_sections, action.defender_id],
			[action.defender_id, action.defender_sections, action.attacker_id]]
	if action.helper_id != "":
		sides.append([action.helper_id, action.helper_sections, action.attacker_id])
	for side in sides:
		var ship: ShipState = game_state.get_ship(side[0])
		if ship == null:
			continue
		for s in side[1]:
			var task := ship.boarding_task(int(s))
			if task.is_empty():
				continue
			var params: Dictionary = (task.get("params", {}) as Dictionary).duplicate(true)
			params["action"] = action.id
			params["enemy"] = side[2]
			params["section"] = int(s)
			game_state.ship_controller.update_task(side[0], int(task["seq"]), {"forced": true, "params": params})


## The boarding order after the boarders go away or come back (boarding spec §2.4 #6).
func _set_order(ship_id: String, order: String) -> void:
	game_state.ship_controller.set_crew_orders(ship_id, {"boarding": order})


# --- COMBAT_RESOLUTION: resolve ---

## SoP IV.B, 10.D: every live action fights one round, after all gunfire and marine fire.
func resolve(phase: int) -> void:
	if not is_server:
		push_error("BoardingController: Cannot resolve boarding on client")
		return
	var live: Array = []
	for a in game_state.boarding_actions:
		if a.is_live():
			live.append(a)
	live.sort_custom(func(a: BoardingAction, b: BoardingAction) -> bool:
		return [a.defender_id, a.attacker_id] < [b.defender_id, b.attacker_id])
	# 10.F.3: every action's strength is taken before any result.
	var plans: Array = []
	for a in live:
		_join_defenders(a)
		_prune(a)
		var att: ShipState = game_state.get_ship(a.attacker_id)
		var def: ShipState = game_state.get_ship(a.defender_id)
		var helper: ShipState = game_state.get_ship(a.helper_id) if a.helper_id != "" else null
		plans.append({"action": a,
			"att_tbcf": tbcf_of(att, a.attacker_sections, att.crew_quality),
			"def_tbcf": defence_tbcf(a),
			"att_cq": att.crew_quality, "def_cq": def.crew_quality,
			"helper_cq": helper.crew_quality if helper != null else ""})
	for plan in plans:
		_fight(plan, phase)


## 10.E.1: sections the defender formed (FB) or keeps ready (BR) since the action began join the
## defence ("additional CSs may be added; they must first FB if defending").
func _join_defenders(action: BoardingAction) -> void:
	var def: ShipState = game_state.get_ship(action.defender_id)
	if def == null or def.is_out_of_play():
		return
	var joined := false
	for s in range(ShipState.MARINES + 1):
		if action.defender_sections.has(s) or not def.section_alive(s):
			continue
		var task := def.boarding_task(s)
		var code := str(task.get("code", ""))
		if (code == "FB" or code == "BR") and not BoardingTaskHandler.engaged(task):
			action.defender_sections.append(s)
			joined = true
	if joined:
		action.defender_sections.sort()
		_engage_tasks(action)


## Drops sections with no boxes left from the action (4.B.3).
func _prune(action: BoardingAction) -> void:
	var att: ShipState = game_state.get_ship(action.attacker_id)
	var def: ShipState = game_state.get_ship(action.defender_id)
	action.attacker_sections = _alive(att, action.attacker_sections)
	action.defender_sections = _alive(def, action.defender_sections)
	if action.helper_id != "":
		action.helper_sections = _alive(game_state.get_ship(action.helper_id), action.helper_sections)


static func _alive(ship: ShipState, sections: Array[int]) -> Array[int]:
	var out: Array[int] = []
	if ship == null:
		return out
	for s in sections:
		if ship.section_alive(s):
			out.append(s)
	return out


func _fight(plan: Dictionary, phase: int) -> void:
	var action: BoardingAction = plan["action"]
	var att: ShipState = game_state.get_ship(action.attacker_id)
	var def: ShipState = game_state.get_ship(action.defender_id)
	if def == null or def.is_destroyed():
		_end_action(action, BoardingAction.DEFENDER_WON, "target_gone", phase)
		return
	if att == null or att.is_out_of_play():
		_attackers_lost(action, "surrendered", phase)  # 10.D.6
		return
	if def.is_struck():
		capture(action, false, phase, "struck_in_action")  # 10.E.2c
		return
	if action.attacker_sections.is_empty():
		_attackers_lost(action, "attackers_lost", phase)  # 10.E.3a
		return
	if _defence_empty(action):
		capture(action, false, phase, "all_defenders_lost")  # 10.E.2e
		return
	var tables: CombatTables = DataManager.combat_tables
	var att_tbcf: int = plan["att_tbcf"]
	var def_tbcf: int = plan["def_tbcf"]
	var drms := drms_for(att, def, att_tbcf, def_tbcf)
	var a_roll: int = game_state.dice.two_d6()
	var d_roll: int = game_state.dice.two_d6()
	var a_total: int = a_roll + int(drms["attacker"]["total"])
	var d_total: int = d_roll + int(drms["defender"]["total"])
	var a_row := tables.boarding_row(a_total)
	var d_row := tables.boarding_row(d_total)
	var def_need := CombatTables.boarding_loss_bcf(int(a_row["pct"]), att_tbcf)
	var att_need := CombatTables.boarding_loss_bcf(int(d_row["pct"]), def_tbcf)
	var round_index: int = game_state.turn_log.events.size()
	var att_secs_before := action.attacker_sections.duplicate()
	var def_secs_before := action.defender_sections.duplicate()
	var att_boxes := _boxes_by_type(att, att_secs_before)
	var def_boxes := _boxes_by_type(def, def_secs_before)
	var helper_secs_before := action.helper_sections.duplicate()
	var below_before := def.original_crew_boxes() if action.original_crew_joins else 0
	var def_lost: Dictionary
	if action.helper_id == "" and not action.original_crew_joins:
		def_lost = game_state.damage_controller.apply_boarding_losses(
			def.ship_id, def_need, def_secs_before, plan["def_cq"], phase, att.ship_id)
	else:
		# 10.G.5: the prize's crew, the captor's boarders, then the original crew below.
		var contingents: Array = [{"ship_id": def.ship_id, "sections": def_secs_before, "quality": plan["def_cq"]}]
		var helper: ShipState = game_state.get_ship(action.helper_id) if action.helper_id != "" else null
		if helper != null:
			contingents.append({"ship_id": helper.ship_id, "sections": helper_secs_before, "quality": plan["helper_cq"]})
			var hb := _boxes_by_type(helper, helper_secs_before)
			def_boxes = [def_boxes[0] + hb[0], def_boxes[1] + hb[1]]
		if action.original_crew_joins:
			contingents.append({"ship_id": def.ship_id, "below": true, "quality": BELOW_QUALITY})
			var crew: Dictionary = def.prize.get("original_crew", {})
			def_boxes = [def_boxes[0] + below_before - int(crew.get("marine_count", 0)),
				def_boxes[1] + int(crew.get("marine_count", 0))]
		def_lost = game_state.damage_controller.apply_boarding_losses_shared(contingents, def_need, phase, att.ship_id)
	var att_lost: Dictionary = game_state.damage_controller.apply_boarding_losses(
		att.ship_id, att_need, att_secs_before, plan["att_cq"], phase, def.ship_id)
	# 10.D.5: one special result at most.
	var a_special := str(a_row["attacker"])
	var d_special := str(d_row["defender"])
	var side := ""
	if a_special != "none" and d_special != "none":
		if a_total != d_total:
			side = "attacker" if a_total > d_total else "defender"
		elif att_tbcf != def_tbcf:
			side = "attacker" if att_tbcf > def_tbcf else "defender"
	elif a_special != "none":
		side = "attacker"
	elif d_special != "none":
		side = "defender"
	var result := {"special": "none", "side": side, "d10": -1, "mr": 0, "mcs": 0, "result": "fight_on"}
	var captured := false
	var repulsed := false
	if side == "attacker":
		result["special"] = a_special
		if a_special == "capture":
			captured = true
		elif a_special == "capture_if_lt_mr":
			result["d10"] = game_state.dice.d10()
			result["mr"] = _defence_morale(action, def)
			captured = int(result["d10"]) < int(result["mr"])
	elif side == "defender":
		result["special"] = d_special
		match d_special:
			"repulse_if_lt_mr":
				result["d10"] = game_state.dice.d10()
				result["mr"] = att.morale_rating
				repulsed = int(result["d10"]) < att.morale_rating
			"repulse_mc1":
				repulsed = true
				result["mcs"] = 1
			"repulse_mc2":
				repulsed = true
				result["mcs"] = 2
	var round_data := {
		"action": action.id, "round": action.rounds + 1,
		"attacker": {"sections": att_secs_before, "sailors": att_boxes[0], "marines": att_boxes[1],
			"cq": plan["att_cq"], "tbcf": att_tbcf, "odds": drms["attacker"]["odds"],
			"other": drms["attacker"]["other"], "drm": drms["attacker"]["total"], "roll": a_roll,
			"total": a_total, "pct": a_row["pct"], "inflicts": def_need,
			"lost_sailors": int(att_lost.get("sailors", 0)), "lost_marines": int(att_lost.get("marines", 0))},
		"defender": {"sections": def_secs_before, "sailors": def_boxes[0], "marines": def_boxes[1],
			"cq": plan["def_cq"], "tbcf": def_tbcf, "odds": drms["defender"]["odds"],
			"other": 0, "drm": drms["defender"]["total"], "roll": d_roll,
			"total": d_total, "pct": d_row["pct"], "inflicts": att_need,
			"lost_sailors": int(def_lost.get("sailors", 0)), "lost_marines": int(def_lost.get("marines", 0)),
			"helper_id": action.helper_id, "helper_sections": helper_secs_before, "below": below_before},
	}
	game_state.turn_log.insert(round_index, PhaseEvents.Type.BOARDING_ROUND, phase, att.ship_id, round_data, def.ship_id)
	action.rounds += 1
	_prune(action)
	if captured:
		result["result"] = "captured"
	elif repulsed:
		result["result"] = "repulsed"
	elif _defence_empty(action) or def.is_struck():
		result["result"] = "captured"
	elif action.attacker_sections.is_empty() or att.is_out_of_play():
		result["result"] = "driven_off"
	game_state.turn_log.add(PhaseEvents.Type.BOARDING_RESULT, phase, att.ship_id, result, def.ship_id)
	match str(result["result"]):
		"captured":
			capture(action, false, phase, "captured" if captured else ("struck_in_action" if def.is_struck() else "all_defenders_lost"))
		"repulsed":
			_repulse(action, int(result["mcs"]), phase)
		"driven_off":
			_attackers_lost(action, "attackers_lost" if not att.is_out_of_play() else "surrendered", phase)
		_:
			action.state = BoardingAction.ENGAGED
			_engage_tasks(action)
	Trace.trace_log("Boarding", "Action %d round %d: %s %d (%d%+d) v %s %d (%d%+d): %s" % [action.id,
		action.rounds, att.ship_id, a_total, a_roll, int(drms["attacker"]["total"]), def.ship_id, d_total,
		d_roll, int(drms["defender"]["total"]), result["result"]])


## The MR the "d10 < defender's MR" capture test reads: the prize's crew's, or while its captors
## defend her (10.G.5) with no prize crew aboard, the captor's.
func _defence_morale(action: BoardingAction, def: ShipState) -> int:
	if action.helper_id != "" and not def.has_prize_crew():
		var helper: ShipState = game_state.get_ship(action.helper_id)
		if helper != null:
			return helper.morale_rating
	return def.morale_rating


## [sailor boxes, marine boxes] in `sections` of the ship.
static func _boxes_by_type(ship: ShipState, sections: Array) -> Array[int]:
	var sailors := 0
	var marines := 0
	for s in sections:
		if int(s) == ShipState.MARINES:
			marines += ship.section_boxes(int(s))
		else:
			sailors += ship.section_boxes(int(s))
	return [sailors, marines]


## 10.D.5a: attacker repulsed: its boarding sections are disbanded (and every other FB/BR it has),
## and it notes its morale checks. The defender wins (10.E.3b).
func _repulse(action: BoardingAction, mcs: int, phase: int) -> void:
	var att_id := action.attacker_id
	_disband_all(att_id, "repulsed", phase)
	if mcs > 0:
		var trigger := MC_TRIGGER % [action.id, _turn()]
		if game_state.ship_controller.note_morale_check(att_id, trigger, mcs):
			game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, att_id,
				{"trigger": trigger, "count": mcs})
	_set_order(att_id, "")
	_end_action(action, BoardingAction.DEFENDER_WON, "repulsed", phase)


## The attackers are gone (10.E.3a) or have surrendered with their ship (10.D.6): the defender wins.
func _attackers_lost(action: BoardingAction, outcome: String, phase: int) -> void:
	var att: ShipState = game_state.get_ship(action.attacker_id)
	if att != null:
		for s in action.attacker_sections:
			var task := att.boarding_task(s)
			if not task.is_empty():
				game_state.crew_task_controller.cancel_task(att.ship_id, int(task["seq"]), outcome, phase)
		if not att.is_out_of_play():
			_set_order(att.ship_id, "")
	_end_action(action, BoardingAction.DEFENDER_WON, outcome, phase)


## Every FB, BR and BA task of the ship ends (10.D.5a "cross out their plots").
func _disband_all(ship_id: String, reason: String, phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	for code in ShipState.BOARDER_CODES:
		for task in ship.tasks_with(code):
			game_state.crew_task_controller.cancel_task(ship_id, int(task["seq"]), reason, phase)


## The action is over: finished, and the winning defenders are released (they may BD, BR or
## counter-board, 10.G.3, 10.E.4).
func _end_action(action: BoardingAction, state: String, outcome: String, phase: int) -> void:
	action.state = state
	action.outcome = outcome
	action.finished_turn = _turn()
	if state == BoardingAction.DEFENDER_WON:
		_release(action.defender_id, action.defender_sections, phase)
		_reorganize_again(action, phase)


## 10.G.5: the captors held their prize: they begin reorganizing again from the beginning.
func _reorganize_again(action: BoardingAction, phase: int) -> void:
	if action.helper_id == "":
		return
	var helper: ShipState = game_state.get_ship(action.helper_id)
	var prize: ShipState = game_state.get_ship(action.defender_id)
	if helper == null or helper.is_out_of_play() or prize == null or not prize.is_captured():
		return
	for s in _alive(helper, action.helper_sections):
		game_state.crew_task_controller.force_task(helper.ship_id, [s], ReorganizeHandler.CODE,
			{"reason": "boarding", "prize": prize.ship_id, "action": action.prize_action}, phase)


## Engaged tasks of a ship's sections go back to plain boarders: FB completes into BR as usual, BA
## (a defender's own boarders, 0.4 #2) becomes BR.
func _release(ship_id: String, sections: Array, phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.is_out_of_play():
		return
	for s in sections:
		var task := ship.boarding_task(int(s))
		if task.is_empty():
			continue
		if str(task["code"]) == "BA":
			game_state.crew_task_controller.cancel_task(ship_id, int(task["seq"]), "action over", phase)
			game_state.ship_controller.add_task(ship_id, {"code": "BR", "sections": [int(s)],
				"params": {"section": int(s)}, "forced": false, "marines_available": true})
			continue
		var params: Dictionary = (task.get("params", {}) as Dictionary).duplicate(true)
		params.erase("action")
		params.erase("enemy")
		params.erase("reason")
		game_state.ship_controller.update_task(ship_id, int(task["seq"]), {"forced": false, "params": params})


## 10.E.2, 10.H.1: the defender is captured. Its crew goes below (prize.original_crew) and the live
## crew is empty until the prize crew is put aboard; its tasks (but firefighting), plots and pending
## morale checks are dropped; status CAPTURED under the captor's side. The surviving attacking
## sections reorganize (RO, 5 + SK g-t's, 10.G.2-4), except after boarding a struck ship (10.A.3),
## whose prize crew goes aboard in this g-t's STATUS_ADJUSTMENT.
func capture(action: BoardingAction, struck_target: bool, phase: int, outcome: String = "") -> void:
	if not is_server:
		push_error("BoardingController: Cannot capture on client")
		return
	var att: ShipState = game_state.get_ship(action.attacker_id)
	var def: ShipState = game_state.get_ship(action.defender_id)
	var struck_before := def.is_struck()
	action.struck_target = struck_target
	_end_action(action, BoardingAction.ATTACKER_WON, outcome if outcome != "" else ("struck" if struck_target else "captured"), phase)
	var sc: ShipStateController = game_state.ship_controller
	var ctc: CrewTaskController = game_state.crew_task_controller
	if def.is_captured() and att.player_id == def.original_player_id:
		# A prize boarded back by her own side: retaken (boarding spec §8 Q5). The winners reorganize
		# (10.G.2) and then come home; she needs no prize crew.
		action.retaken = true
		retake(def.ship_id, "boarded", phase, action)
		for s in _alive(att, action.attacker_sections):
			ctc.force_task(att.ship_id, [s], ReorganizeHandler.CODE,
				{"reason": "boarding", "prize": def.ship_id, "action": action.id}, phase)
		_set_order(att.ship_id, "")
		return
	var original_crew := {"crew_count": def.crew_count.duplicate(), "marine_count": def.marine_count,
		"crew_quality": def.crew_quality, "morale_rating": def.morale_rating}
	var original_navy := def.gunnery_navy()
	if def.is_captured():
		# Taken from her captor by a third side: the old original crew stays below.
		original_crew = (def.prize.get("original_crew", {}) as Dictionary).duplicate(true)
		original_navy = str(def.prize.get("original_navy", original_navy))
		_finish_captures_of(def.ship_id, action.id, phase)
	ctc.cancel_all_except(def.ship_id, "FF", "captured", phase)
	ctc.cancel_code(def.ship_id, "FF", "captured", phase, false)
	sc.clear_crew_plot(def.ship_id)
	sc.set_crew_orders(def.ship_id, {"boarding": ""})
	sc.clear_pending_morale_checks(def.ship_id)
	sc.set_prize(def.ship_id, {
		"captor_id": att.ship_id,
		"original_crew": original_crew,
		"original_navy": original_navy,
		"prize_crew_aboard": false,
	}, true)
	sc.set_crew(def.ship_id, [0, 0, 0, 0], 0)
	sc.set_navy(def.ship_id, att.gunnery_navy())  # 1.G.8: the navy using her (a prize does not fire, §8 Q2)
	sc.set_status(def.ship_id, ShipState.Status.CAPTURED)
	game_state.transfer_control(def.ship_id, att.player_id)
	game_state.turn_log.add(PhaseEvents.Type.SHIP_CAPTURED, phase, def.ship_id,
		{"captor_id": att.ship_id, "struck_before": struck_before, "action": action.id}, att.ship_id)
	if action.struck_target:
		for s in action.attacker_sections:
			var task := att.boarding_task(s)
			if not task.is_empty():
				ctc.cancel_task(att.ship_id, int(task["seq"]), "boarding", phase)
	else:
		for s in _alive(att, action.attacker_sections):
			ctc.force_task(att.ship_id, [s], ReorganizeHandler.CODE,
				{"reason": "boarding", "prize": def.ship_id, "action": action.id}, phase)
	_set_order(att.ship_id, "")
	Trace.trace_log("Boarding", "%s captured by %s (action %d, %s)" % [def.ship_id, att.ship_id, action.id, action.outcome])


# --- STATUS_ADJUSTMENT ---

## SoP V.G, 10.G.7: for each won action whose boarders have finished reorganizing (no live RO task
## for it; at once after boarding a struck ship), the prize crew is put aboard: the minimum for the
## prize's class, taken from the surviving boarders only (fewer: all of them; spec §8 Q3), sailors
## from the lowest-numbered sections first, then marines; all of them if the two ships have parted
## meanwhile (10.G.2, spec 0.4 #6). The boxes leave the parent with no morale check and are formed
## into sections of the prize's original sizes; the prize crew takes the captor's current CQ and MR
## (10.G.8). Logs PRIZE_CREW.
func advance_reorganizing(phase: int) -> void:
	if not is_server:
		push_error("BoardingController: Cannot advance reorganizing on client")
		return
	for action in game_state.boarding_actions:
		if action.state != BoardingAction.ATTACKER_WON or action.prize_aboard:
			continue
		var att: ShipState = game_state.get_ship(action.attacker_id)
		var prize: ShipState = game_state.get_ship(action.defender_id)
		if att == null or prize == null or att.is_destroyed() or prize.is_destroyed():
			action.prize_aboard = true
			continue
		if _still_reorganizing(action, att):
			continue
		if action.retaken or not prize.is_captured() or prize.prize.get("captor_id", "") != att.ship_id:
			action.prize_aboard = true  # retaken: the boarders come home with no prize crew
			continue
		if live_action_of(prize.ship_id) != null:
			continue  # 10.G.5: being boarded; the prize crew waits for the action
		_put_prize_crew_aboard(action, att, prize, phase)


func _still_reorganizing(action: BoardingAction, att: ShipState) -> bool:
	for task in att.tasks_with(ReorganizeHandler.CODE):
		if int(task.get("params", {}).get("action", -1)) == action.id:
			return true
	return false


## An action ready for its prize crew this STATUS_ADJUSTMENT (RO over, or a struck prize).
func _awaiting_prize_crew(action: BoardingAction) -> bool:
	if action.state != BoardingAction.ATTACKER_WON or action.prize_aboard or action.retaken:
		return false
	var att: ShipState = game_state.get_ship(action.attacker_id)
	var prize: ShipState = game_state.get_ship(action.defender_id)
	if att == null or prize == null or att.is_destroyed() or prize.is_destroyed() or not prize.is_captured():
		return false
	if prize.prize.get("captor_id", "") != att.ship_id:
		return false
	return not _still_reorganizing(action, att) and live_action_of(prize.ship_id) == null


## The surviving boarders of a won action: {"sailors", "marines"} boxes.
func _boarders_left(action: BoardingAction, att: ShipState) -> Dictionary:
	var out := {"sailors": 0, "marines": 0}
	for s in _alive(att, action.attacker_sections):
		out["marines" if s == ShipState.MARINES else "sailors"] += att.section_boxes(s)
	return out


## The prize-crew sizes the captor may choose this g-t (10.G.6, spec §4.3 and §8 Q3: from the
## minimum up to the surviving boarders; none from sections that did not board). One entry per won
## action of `player_id` awaiting its prize crew where there is a choice (more boarders than the
## minimum, the ships still together): {"action_id", "prize_id", "captor_id", "minimum", "maximum",
## "size" (current choice), "previews": [{"size", "sailors", "marines", "prize": "0-0-1-2:0",
## "parent": "0-5-6-6:2"}]}. Pure.
func prize_size_options(player_id: int) -> Array:
	var out: Array = []
	for action in game_state.boarding_actions:
		if not _awaiting_prize_crew(action):
			continue
		var att: ShipState = game_state.get_ship(action.attacker_id)
		var prize: ShipState = game_state.get_ship(action.defender_id)
		if att.player_id != player_id or not att.linked_ids().has(prize.ship_id):
			continue
		var left := _boarders_left(action, att)
		var available := int(left["sailors"]) + int(left["marines"])
		var minimum := DataManager.combat_tables.prize_minimum(_class(prize))
		if available <= minimum:
			continue  # no choice: the minimum, or all of them (spec §8 Q3)
		var previews: Array = []
		for n in range(minimum, available + 1):
			previews.append(prize_preview(att, prize, left, n))
		out.append({"action_id": action.id, "prize_id": prize.ship_id, "captor_id": att.ship_id,
			"minimum": minimum, "maximum": available, "size": clampi(action.prize_size, minimum, available),
			"previews": previews})
	return out


## Both crews after a prize crew of `size` (10.G.7): sailors from the parent's lowest-numbered
## sections first, then marines, formed into the prize's original section sizes. Pure.
static func prize_preview(att: ShipState, prize: ShipState, left: Dictionary, size: int) -> Dictionary:
	var sailors := mini(size, int(left["sailors"]))
	var marines := mini(size - sailors, int(left["marines"]))
	var crew: Array = att.crew_count.duplicate()
	var take := sailors
	for k in range(crew.size()):
		var t := mini(take, int(crew[k]))
		crew[k] = int(crew[k]) - t
		take -= t
	var formed := BoardingRules.form_prize_sections(prize.ship.crew_count if prize.ship else [0, 0, 0, 0],
		prize.ship.marine_count if prize.ship else 0, sailors, marines)
	return {"size": size, "sailors": sailors, "marines": marines,
		"prize": crew_text(formed["crew_count"], int(formed["marine_count"])),
		"parent": crew_text(crew, att.marine_count - marines)}


## "0-5-6-6:2": the four sailor sections and the marines.
static func crew_text(crew: Array, marines: int) -> String:
	var parts := PackedStringArray()
	for b in crew:
		parts.append(str(int(b)))
	return "%s:%d" % ["-".join(parts), marines]


## Records the prize-crew size the captor chose for a won action (10.G.6); "" or the reason it is
## refused (only from the minimum to the surviving boarders, spec §8 Q3).
func set_prize_size(action_id: int, size: int) -> String:
	if not is_server:
		push_error("BoardingController: Cannot set a prize-crew size on client")
		return "not the server"
	var action := action_by_id(action_id)
	if action == null or not _awaiting_prize_crew(action):
		return "no prize crew is to be put aboard for action %d" % action_id
	var att: ShipState = game_state.get_ship(action.attacker_id)
	var prize: ShipState = game_state.get_ship(action.defender_id)
	var left := _boarders_left(action, att)
	var available := int(left["sailors"]) + int(left["marines"])
	var minimum := DataManager.combat_tables.prize_minimum(_class(prize))
	if size < minimum:
		return "the prize crew of %s must be at least %d boxes (10.G.6)" % [prize.ship_name, minimum]
	if size > available:
		return "only %d boarders are aboard %s: the prize crew comes from the boarders (10.G.6)" % [available, prize.ship_name]
	action.prize_size = size
	return ""


func _put_prize_crew_aboard(action: BoardingAction, att: ShipState, prize: ShipState, phase: int) -> void:
	var sailors_avail := 0
	var marines_avail := 0
	for s in _alive(att, action.attacker_sections):
		if s == ShipState.MARINES:
			marines_avail += att.section_boxes(s)
		else:
			sailors_avail += att.section_boxes(s)
	var available := sailors_avail + marines_avail
	var minimum := DataManager.combat_tables.prize_minimum(_class(prize))
	var size := mini(maxi(minimum, action.prize_size), available)
	if not att.linked_ids().has(prize.ship_id):
		size = available  # parted while reorganizing: every boarder is aboard the prize (0.4 #6)
	var sailors := mini(size, sailors_avail)
	var marines := mini(size - sailors, marines_avail)
	var taken: Dictionary = game_state.damage_controller.detach_prize_crew(att.ship_id, sailors, marines, phase)
	var formed := BoardingRules.form_prize_sections(prize.ship.crew_count if prize.ship else [0, 0, 0, 0],
		prize.ship.marine_count if prize.ship else 0, int(taken["sailors"]), int(taken["marines"]))
	var sc: ShipStateController = game_state.ship_controller
	sc.set_crew(prize.ship_id, formed["crew_count"], int(formed["marine_count"]))
	sc.set_crew_quality(prize.ship_id, att.crew_quality)
	sc.set_morale_rating(prize.ship_id, att.morale_rating)
	sc.set_prize(prize.ship_id, {"prize_crew_aboard": true})
	action.prize_aboard = true
	game_state.turn_log.add(PhaseEvents.Type.PRIZE_CREW, phase, prize.ship_id, {
		"sailors": int(taken["sailors"]), "marines": int(taken["marines"]), "cq": att.crew_quality,
		"mr": att.morale_rating, "crew_count": (formed["crew_count"] as Array).duplicate(),
		"marine_count": int(formed["marine_count"])}, att.ship_id)


# --- Recapture (10.H.4; a prize boarded back) ---

## Start of a g-t (10.H.4): a prize whose prize crew is below the minimum for her class (10.G.6)
## and whose original crew below has at least twice its boxes is retaken. Not while she is in a
## boarding action. No dice. Ships in id order.
func start_of_turn(phase: int) -> void:
	if not is_server:
		push_error("BoardingController: Cannot check recaptures on client")
		return
	for ship_id in _sorted_ids():
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or not ship.has_prize_crew() or live_action_of(ship_id) != null:
			continue
		if recapture_due(ship):
			retake(ship_id, "rose", phase)


## 10.H.4: the prize crew is below the minimum and the original crew has at least twice its boxes
## (and at least one). Pure.
static func recapture_due(ship: ShipState) -> bool:
	if not ship.has_prize_crew():
		return false
	var prize_boxes := ship.total_crew_boxes()
	var below := ship.original_crew_boxes()
	return prize_boxes < DataManager.combat_tables.prize_minimum(_class(ship)) \
		and below > 0 and below >= 2 * prize_boxes


## The prize is back with her own side (10.H.4, or boarded back by `action`): ACTIVE, controlled by
## her original owner, her original crew freed from below as her crew at CQ G and MR 6 (10.H.4; the
## same for a ship boarded back, spec reading); her point value keeps her original MR. The prize
## crew aboard is taken prisoner (gone from her), as are the captor's boarders still aboard her
## (reorganizing, or defending under 10.G.5), crossed off the captor's log. Every task and plot of
## hers ends. Logs RECAPTURED.
func retake(ship_id: String, cause: String, phase: int, action: BoardingAction = null) -> void:
	if not is_server:
		push_error("BoardingController: Cannot retake a ship on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or not ship.is_captured():
		return
	var sc: ShipStateController = game_state.ship_controller
	var ctc: CrewTaskController = game_state.crew_task_controller
	var original: Dictionary = (ship.prize.get("original_crew", {}) as Dictionary).duplicate(true)
	var data := {"cause": cause, "original_boxes": ship.original_crew_boxes(),
		"prize_boxes": ship.total_crew_boxes(), "cq": RETAKEN_QUALITY, "mr": RETAKEN_MORALE}
	var prisoners := 0
	var captor_id := str(ship.prize.get("captor_id", ""))
	var helper_secs: Array[int] = []
	if action != null and action.helper_id == captor_id:
		helper_secs = action.helper_sections.duplicate()
	var captor: ShipState = game_state.get_ship(captor_id)
	if captor != null:
		for task in captor.tasks_with(ReorganizeHandler.CODE):
			if str(task.get("params", {}).get("prize", "")) == ship_id:
				for s in task.get("sections", []):
					if not helper_secs.has(int(s)):
						helper_secs.append(int(s))
		for s in helper_secs:
			prisoners += _cross_off(captor_id, s, phase)
	data["prisoners"] = prisoners
	ctc.cancel_all_except(ship_id, "", "retaken", phase)
	sc.clear_crew_plot(ship_id)
	sc.set_crew_orders(ship_id, {"boarding": ""})
	sc.clear_pending_morale_checks(ship_id)
	sc.set_value_morale_rating(ship_id, ship.original_morale_rating())
	sc.set_crew(ship_id, original.get("crew_count", [0, 0, 0, 0]), int(original.get("marine_count", 0)))
	sc.set_crew_quality(ship_id, RETAKEN_QUALITY)
	sc.set_morale_rating(ship_id, RETAKEN_MORALE)
	sc.set_navy(ship_id, str(ship.prize.get("original_navy", "")))
	sc.set_prize(ship_id, {}, true)
	sc.set_status(ship_id, ShipState.Status.ACTIVE)
	game_state.transfer_control(ship_id, ship.original_player_id)
	_finish_captures_of(ship_id, action.id if action != null else -1, phase)
	game_state.turn_log.add(PhaseEvents.Type.RECAPTURED, phase, ship_id, data,
		action.attacker_id if action != null else captor_id)
	Trace.trace_log("Boarding", "%s retaken (%s)" % [ship_id, cause], data)


## Every box of `section` of the ship is crossed off (taken prisoner aboard a retaken prize); an
## emptied section loses its task and notes a morale check as for crew lost. Returns the boxes.
func _cross_off(ship_id: String, section: int, phase: int) -> int:
	var ship: ShipState = game_state.get_ship(ship_id)
	var n := 0
	while ship != null and ship.section_alive(section):
		var emptied: int = game_state.ship_controller.remove_crew_box_from(ship_id, section) \
			if section < ShipState.SAILOR_SECTIONS else game_state.ship_controller.remove_crew_box(ship_id, true)
		n += 1
		if emptied >= 0:
			game_state.crew_task_controller.cancel_section(ship_id, emptied, "taken prisoner", phase)
			if not ship.is_out_of_play() and game_state.ship_controller.note_morale_check(ship_id, "crew_%d" % emptied):
				game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, ship_id,
					{"trigger": "crew_%d" % emptied, "count": 1})
	return n


## Won actions that took `prize_id` (other than `except_id`) are finished: no prize crew follows.
func _finish_captures_of(prize_id: String, except_id: int, _phase: int) -> void:
	for a in game_state.boarding_actions:
		if a.id != except_id and a.state == BoardingAction.ATTACKER_WON and a.defender_id == prize_id:
			a.prize_aboard = true


# --- END_TURN ---

## END_TURN: the turn's actions are kept in GameState.boarding_history[turn]; actions finished on an
## earlier g-t are dropped (a repulse is kept one g-t for counter-boarding, 10.E.4), as are won
## actions whose prize crew is aboard.
func end_of_turn(turn: int) -> void:
	if not is_server:
		push_error("BoardingController: Cannot end the boarding turn on client")
		return
	var snapshot: Array = []
	for a in game_state.boarding_actions:
		snapshot.append(a.to_dict())
	game_state.boarding_history[turn] = snapshot
	var keep: Array = []
	for a in game_state.boarding_actions:
		if a.is_live():
			keep.append(a)
		elif a.state == BoardingAction.ATTACKER_WON and not a.prize_aboard:
			keep.append(a)
		elif a.state == BoardingAction.DEFENDER_WON and a.finished_turn >= turn:
			keep.append(a)
	game_state.boarding_actions = keep


# --- Internals ---

func _turn() -> int:
	var t = game_state.get("current_turn")
	if game_state.get("phase_controller") != null:
		t = game_state.phase_controller.current_turn
	return int(t) if t != null else 0


static func _class(ship: ShipState) -> int:
	return ship.ship.ship_class if ship != null and ship.ship != null else 0


func _sorted_ids() -> Array:
	var ids: Array = game_state.ships.keys()
	ids.sort()
	return ids
