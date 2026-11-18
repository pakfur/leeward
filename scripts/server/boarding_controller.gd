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
## her own side's attackers at CQ G (10.G.5; user decision 2026-11-15, ORIGINAL_CREW_WITH_ATTACKERS;
## the B5 reading put it in the defence); if the captors hold, RO starts again. When the prize's own side
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
##   With a side made of several contingents (10.G.5: the defence is the prize's live crew, then the
##   captor's boarders; the attack is the boarders, then the original crew below), that side's loss
##   d6s are rolled box by box across all of them, and each box is taken from the first contingent
##   in that order that has that type (DamageController.apply_boarding_losses_shared).
##
## Several ships (10.F; boarding spec B6): every action is one attacker against one defender. Ships
## boarding one target in the same g-t each get an action, the defender's sections shared out among
## them (_defend; later FB/BR sections the same way, _join_defenders); a sixth boarding ship takes
## her outright (10.F.2). A ship may board one enemy while defending against others. Rounds are
## simultaneous (10.F.3, _apply_outcomes); a ship taken in one action is taken in all her others
## (_share_capture), and her own boarders elsewhere are cut off (_cut_off).

const QUALITY_ORDER := "ABCDEFG"
## Morale-check trigger prefix for "attacker repulsed and takes n MC" (unique per action and g-t).
const MC_TRIGGER := "boarding_%d_%d"
## 10.H.4 (and a prize boarded back by her own side): the crew that retakes the ship.
const RETAKEN_QUALITY := "G"
const RETAKEN_MORALE := 6
## 10.G.5: the original crew joins a new boarding action at CQ G.
const BELOW_QUALITY := "G"
## 10.G.5 does not say which side the original crew joins. User decision 2026-11-15: it joins its
## own side's attackers (true). false = the earlier reading, the defence of the prize with her
## reorganizing captors (boarding spec B5).
const ORIGINAL_CREW_WITH_ATTACKERS := true
## 10.F.2: a ship can fight off at most five boarding ships (one section each); a sixth boarding
## ship takes her outright.
const MAX_SHIPS_ENGAGED := 5

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
## once, with no roll. Several ships boarding one (10.F.2): one action each, the defender's sections
## shared out among them (_defend); a sixth boarding ship takes her outright. Targets are handled in
## ship_id order, each target's boarders in ship_id order. Returns true when anything was announced
## (the combat phase then shows it).
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
	# 10.F.2: the boardings of each target together, so its defence can be shared out.
	var by_target := {}
	for p in pairs:
		var t := str(p[1])
		if not by_target.has(t):
			by_target[t] = []
		by_target[t].append(p)
	var targets: Array = by_target.keys()
	targets.sort()
	for t in targets:
		var group: Array = by_target[t]
		group.sort_custom(func(x: Array, y: Array) -> bool: return str(x[0]) < str(y[0]))
		if _board_target(str(t), group, phase):
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


## Every boarding of `target_id` this g-t: `group` is [[attacker, target, sections, defending_ba]]
## in attacker order (`defending_ba`: the target's BA sections aimed back at that attacker, which
## defend against it, spec 0.4 #2). Refused boardings go back to BR; boarders of a ship already in
## an action with the target join it (10.E.1); a struck target is taken by the first boarder
## (10.A.3; she is then friendly to the others, who are refused); the rest open new actions and
## the target's defence is shared out among them (_defend). Returns true when announced.
func _board_target(target_id: String, group: Array, phase: int) -> bool:
	var target: ShipState = game_state.get_ship(target_id)
	var announced := false
	var fresh: Array = []  # [action, defending_ba]
	for p in group:
		var attacker_id := str(p[0])
		var sections: Array = p[2]
		var attacker: ShipState = game_state.get_ship(attacker_id)
		var why := BoardingRules.boardable_error(attacker, target, game_state.linked_at_plot.get(attacker_id, []))
		if why == "" and attacker.is_burning():
			why = BoardingRules.FIRE_REFUSAL
		if why == "" and not attacker.crew_can_act():
			why = "%s is out of the fight" % attacker.ship_name
		if why != "":
			for s in sections:
				_back_to_ready(attacker_id, int(s), why, phase)
			Trace.trace_log("Boarding", "%s cannot board %s: %s" % [attacker_id, target_id, why])
			continue
		var existing := live_action_between(attacker_id, target_id)
		if existing != null:
			# 10.E.1: more sections join a live action.
			var side := existing.sections_of(attacker_id)
			for s in sections:
				if not side.has(int(s)):
					side.append(int(s))
			side.sort()
			_engage_tasks(existing)
			game_state.turn_log.add(PhaseEvents.Type.BOARDERS_AWAY, phase, attacker_id,
				{"sections": sections.duplicate(), "joins": true, "action": existing.id}, target_id)
			_set_order(attacker_id, "ready")
			announced = true
			continue
		var action := _new_action(attacker_id, target_id, sections, phase)
		announced = true
		if target.is_struck():
			capture(action, true, phase)  # 10.A.3, 10.E.2a
			continue
		fresh.append([action, p[3]])
	if not fresh.is_empty():
		_defend(target, fresh, phase)
	return announced


## A new boarding action by `attacker_id` at `target_id` with `sections`, logged BOARDERS_AWAY.
func _new_action(attacker_id: String, target_id: String, sections: Array, phase: int) -> BoardingAction:
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
	return action


## The defence of `target` against the new actions `fresh` ([[action, defending_ba]]):
## 10.F.2: a sixth enemy ship boarding her (counting those already in an action with her) takes
##   her outright ("overwhelmed"); the others share the capture.
## 10.C.3: her marines, if on no boarding task, are replotted to FB.
## Each action gets her BA sections aimed back at its attacker (0.4 #2); her other FB and BR
## sections not engaged elsewhere (the marines first, then the sailors in order) are dealt out
## round robin to the attackers in descending TBCF, then ship_id (boarding spec §3.4; one combat
## per enemy, each section with one enemy, 10.F.2). Logged DEFENCE_SPLIT when there are several.
## The 10.G.5 helpers (a prize's reorganizing captors, and the crew below with its own side) join
## the first.
## An action left with no defender is won at once (10.E.2b).
func _defend(target: ShipState, fresh: Array, phase: int) -> void:
	var boarders: Array = []
	for a in game_state.boarding_actions:
		if a.is_live() and a.defender_id == target.ship_id and not boarders.has(a.attacker_id):
			boarders.append(a.attacker_id)
	if boarders.size() > MAX_SHIPS_ENGAGED:
		var sixth := live_action_between(str(boarders[MAX_SHIPS_ENGAGED]), target.ship_id)
		Trace.trace_log("Boarding", "%s is overwhelmed by %d boarding ships (10.F.2)" % [target.ship_id, boarders.size()])
		capture(sixth, false, phase, "overwhelmed")
		return
	var tbcfs := {}
	for f in fresh:
		var a: BoardingAction = f[0]
		tbcfs[a.id] = tbcf(a.attacker_id, a.attacker_sections)
	fresh.sort_custom(func(x: Array, y: Array) -> bool:
		var ax: BoardingAction = x[0]
		var ay: BoardingAction = y[0]
		if int(tbcfs[ax.id]) != int(tbcfs[ay.id]):
			return int(tbcfs[ax.id]) > int(tbcfs[ay.id])
		return ax.attacker_id < ay.attacker_id)
	var first: BoardingAction = fresh[0][0]
	if target.section_alive(ShipState.MARINES) and target.boarding_task(ShipState.MARINES).is_empty():
		var old := target.task_of(ShipState.MARINES)
		game_state.crew_task_controller.force_task(target.ship_id, [ShipState.MARINES], "FB",
			{"reason": "repel boarders", "section": ShipState.MARINES}, phase)
		game_state.turn_log.add(PhaseEvents.Type.MARINES_DEFEND, phase, target.ship_id,
			{"cancelled_task": str(old.get("code", "")), "done": int(old.get("done", 0))}, first.attacker_id)
	var taken := {}
	for f in fresh:
		var a: BoardingAction = f[0]
		for s in f[1]:
			var task := target.boarding_task(int(s))
			if target.section_alive(int(s)) and str(task.get("code", "")) == "BA" and not BoardingTaskHandler.engaged(task):
				a.defender_sections.append(int(s))
				taken[int(s)] = true
	var free: Array[int] = []
	for s in [ShipState.MARINES, 0, 1, 2, 3]:
		if taken.has(s) or not target.section_alive(s):
			continue
		var task := target.boarding_task(s)
		var code := str(task.get("code", ""))
		if (code == "FB" or code == "BR") and not BoardingTaskHandler.engaged(task):
			free.append(s)
	for i in free.size():
		(fresh[i % fresh.size()][0] as BoardingAction).defender_sections.append(free[i])
	var split: Array = []
	for f in fresh:
		var a: BoardingAction = f[0]
		a.defender_sections.sort()
		split.append({"attacker_id": a.attacker_id, "action": a.id, "sections": a.defender_sections.duplicate()})
	if fresh.size() > 1:
		game_state.turn_log.add(PhaseEvents.Type.DEFENCE_SPLIT, phase, target.ship_id, {"split": split})
	_reorganizers_defend(first, target, phase)  # 10.G.5
	for f in fresh:
		var a: BoardingAction = f[0]
		if not a.is_live():
			continue  # she was taken in another of these actions
		if _defence_empty(a):
			capture(a, false, phase, "undefended")  # 10.E.2b
			continue
		_engage_tasks(a)


## 10.G.5: the prize `target` is boarded while the boarders who took her reorganize aboard her:
## their reorganization is aborted and they defend (forced FB on the parent's log), and the prize's
## original crew "may participate in the new boarding action at CQ=G": on the side of the attackers
## when they are her own side (ORIGINAL_CREW_WITH_ATTACKERS, user decision 2026-11-15), else with
## the defence (the B5 reading).
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
	var attacker: ShipState = game_state.get_ship(action.attacker_id)
	action.original_crew_joins = target.original_crew_boxes() > 0 and (not ORIGINAL_CREW_WITH_ATTACKERS
		or (attacker != null and attacker.side == target.original_side))
	game_state.turn_log.add(PhaseEvents.Type.REORGANIZING_ABORTED, phase, captor.ship_id,
		{"sections": secs.duplicate(), "action": action.id, "original_crew": target.original_crew_boxes()},
		target.ship_id)


## The won action whose boarders are still reorganizing aboard the prize `prize_id` (RO tasks
## live for it), or null.
func reorganizing_capture_of(prize_id: String) -> BoardingAction:
	for a in game_state.boarding_actions:
		if a.state != BoardingAction.ATTACKER_WON or a.prize_aboard or a.retaken or a.shared_with >= 0 \
				or a.defender_id != prize_id:
			continue
		var captor: ShipState = game_state.get_ship(a.attacker_id)
		if captor == null:
			continue
		for task in captor.tasks_with(ReorganizeHandler.CODE):
			if int(task.get("params", {}).get("action", -1)) == a.id:
				return a
	return null


## The original crew below fights on the defending side of this action (10.G.5, the B5 reading).
static func below_defends(action: BoardingAction) -> bool:
	return action.original_crew_joins and not ORIGINAL_CREW_WITH_ATTACKERS


## The original crew below fights with the attackers of this action (10.G.5, user decision).
static func below_attacks(action: BoardingAction) -> bool:
	return action.original_crew_joins and ORIGINAL_CREW_WITH_ATTACKERS


## The defence has nothing left: no section of the defender, none of the captor's boarders
## (10.G.5) and no original crew joining it.
func _defence_empty(action: BoardingAction) -> bool:
	if not action.defender_sections.is_empty() or not action.helper_sections.is_empty():
		return false
	if below_defends(action):
		var def: ShipState = game_state.get_ship(action.defender_id)
		return def == null or def.original_crew_boxes() <= 0
	return true


## The attack's TBCF (10.D.1): the attacker's sections at its CQ, and, with 10.G.5's original crew
## joining its own side's attackers, the crew below at CQ G.
func attack_tbcf(action: BoardingAction) -> int:
	var att: ShipState = game_state.get_ship(action.attacker_id)
	if att == null:
		return 0
	var total := tbcf_of(att, action.attacker_sections, att.crew_quality)
	if below_attacks(action):
		var def: ShipState = game_state.get_ship(action.defender_id)
		if def != null:
			total += below_tbcf(def)
	return total


## The defence's TBCF (10.D.1): the defender's sections at its CQ, the captor's boarders at theirs
## and, under the B5 reading of 10.G.5, the original crew below at CQ G.
func defence_tbcf(action: BoardingAction) -> int:
	var def: ShipState = game_state.get_ship(action.defender_id)
	if def == null:
		return 0
	var total := tbcf_of(def, action.defender_sections, def.crew_quality)
	var helper: ShipState = game_state.get_ship(action.helper_id) if action.helper_id != "" else null
	if helper != null:
		total += tbcf_of(helper, action.helper_sections, helper.crew_quality)
	if below_defends(action):
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

## SoP IV.B, 10.D: every live action fights one round, after all gunfire and marine fire. 10.F.3:
## the actions are fought simultaneously: every strength is taken first, then each action rolls and
## takes its losses (per action in (defender_id, attacker_id) order, the dice order in the header),
## and only then are the results applied (_apply_outcomes), so no result changes another action
## this g-t.
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
	_join_defenders(live)
	# 10.F.3: every action's strength is taken before any result.
	var plans: Array = []
	for a in live:
		_prune(a)
		var att: ShipState = game_state.get_ship(a.attacker_id)
		var def: ShipState = game_state.get_ship(a.defender_id)
		var helper: ShipState = game_state.get_ship(a.helper_id) if a.helper_id != "" else null
		plans.append({"action": a,
			"att_tbcf": attack_tbcf(a),
			"def_tbcf": defence_tbcf(a),
			"att_cq": att.crew_quality if att != null else "", "def_cq": def.crew_quality if def != null else "",
			"helper_cq": helper.crew_quality if helper != null else ""})
	var outcomes: Array = []
	for plan in plans:
		outcomes.append(_fight(plan, phase))
	_apply_outcomes(outcomes, phase)


## 10.E.1: sections the defender formed (FB) or keeps ready (BR) since its actions began, and not
## engaged, join its defence ("additional CSs may be added; they must first FB if defending").
## Defending against several ships (10.F.2), they are dealt out as in _defend: the marines first,
## then the sailors in order, round robin to the attackers in descending TBCF, then ship_id.
func _join_defenders(live: Array) -> void:
	var by_def := {}
	for a in live:
		if not by_def.has(a.defender_id):
			by_def[a.defender_id] = []
		by_def[a.defender_id].append(a)
	var def_ids: Array = by_def.keys()
	def_ids.sort()
	for def_id in def_ids:
		var def: ShipState = game_state.get_ship(str(def_id))
		if def == null or not def.crew_can_act():
			continue
		var free: Array[int] = []
		for s in [ShipState.MARINES, 0, 1, 2, 3]:
			if not def.section_alive(s):
				continue
			var task := def.boarding_task(s)
			var code := str(task.get("code", ""))
			if (code == "FB" or code == "BR") and not BoardingTaskHandler.engaged(task):
				free.append(s)
		if free.is_empty():
			continue
		var acts: Array = by_def[def_id].duplicate()
		var tbcfs := {}
		for a in acts:
			tbcfs[a.id] = tbcf(a.attacker_id, a.attacker_sections)
		acts.sort_custom(func(x: BoardingAction, y: BoardingAction) -> bool:
			if int(tbcfs[x.id]) != int(tbcfs[y.id]):
				return int(tbcfs[x.id]) > int(tbcfs[y.id])
			return x.attacker_id < y.attacker_id)
		for i in free.size():
			(acts[i % acts.size()] as BoardingAction).defender_sections.append(free[i])
		for a in acts:
			a.defender_sections.sort()
			_engage_tasks(a)


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


## One round of one action (10.D): the rolls, the losses and the special result, logged. The result
## is returned, not applied (10.F.3; _apply_outcomes): {"action", "kind": "capture" | "repulse" |
## "attackers_lost" | "end" | "fight_on", "outcome", "mcs"}.
func _fight(plan: Dictionary, phase: int) -> Dictionary:
	var action: BoardingAction = plan["action"]
	var att: ShipState = game_state.get_ship(action.attacker_id)
	var def: ShipState = game_state.get_ship(action.defender_id)
	if def == null or def.is_destroyed() or not def.is_on_map():  # gone: blown up or escaped
		return _no_round(action, "end", "target_gone", phase)
	if att == null or att.is_out_of_play():  # struck, destroyed or escaped
		return _no_round(action, "attackers_lost", "surrendered", phase)  # 10.D.6
	if def.is_struck():
		return _no_round(action, "capture", "struck_in_action", phase)  # 10.E.2c
	if action.attacker_sections.is_empty():
		return _no_round(action, "attackers_lost", "attackers_lost", phase)  # 10.E.3a
	if _defence_empty(action):
		return _no_round(action, "capture", "all_defenders_lost", phase)  # 10.E.2e
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
	var below_crew: Dictionary = def.prize.get("original_crew", {})
	var below_marines := mini(int(below_crew.get("marine_count", 0)), below_before)
	var def_lost: Dictionary
	if action.helper_id == "" and not below_defends(action):
		def_lost = game_state.damage_controller.apply_boarding_losses(
			def.ship_id, def_need, def_secs_before, plan["def_cq"], phase, att.ship_id)
	else:
		# 10.G.5: the prize's crew, the captor's boarders, then (B5 reading) the original crew below.
		var contingents: Array = [{"ship_id": def.ship_id, "sections": def_secs_before, "quality": plan["def_cq"]}]
		var helper: ShipState = game_state.get_ship(action.helper_id) if action.helper_id != "" else null
		if helper != null:
			contingents.append({"ship_id": helper.ship_id, "sections": helper_secs_before, "quality": plan["helper_cq"]})
			var hb := _boxes_by_type(helper, helper_secs_before)
			def_boxes = [def_boxes[0] + hb[0], def_boxes[1] + hb[1]]
		if below_defends(action):
			contingents.append({"ship_id": def.ship_id, "below": true, "quality": BELOW_QUALITY})
			def_boxes = [def_boxes[0] + below_before - below_marines, def_boxes[1] + below_marines]
		def_lost = game_state.damage_controller.apply_boarding_losses_shared(contingents, def_need, phase, att.ship_id)
	var att_lost: Dictionary
	if below_attacks(action):
		# 10.G.5 (user decision): the boarders, then the original crew below fighting with them.
		att_boxes = [att_boxes[0] + below_before - below_marines, att_boxes[1] + below_marines]
		att_lost = game_state.damage_controller.apply_boarding_losses_shared([
			{"ship_id": att.ship_id, "sections": att_secs_before, "quality": plan["att_cq"]},
			{"ship_id": def.ship_id, "below": true, "quality": BELOW_QUALITY}], att_need, phase, def.ship_id)
	else:
		att_lost = game_state.damage_controller.apply_boarding_losses(
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
	var result := {"special": "none", "side": side, "d10": -1, "mr": 0, "mcs": 0, "result": "fight_on",
		"action": action.id, "round": action.rounds + 1}
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
			"lost_sailors": int(att_lost.get("sailors", 0)), "lost_marines": int(att_lost.get("marines", 0)),
			"below": below_before if below_attacks(action) else 0},
		"defender": {"sections": def_secs_before, "sailors": def_boxes[0], "marines": def_boxes[1],
			"cq": plan["def_cq"], "tbcf": def_tbcf, "odds": drms["defender"]["odds"],
			"other": 0, "drm": drms["defender"]["total"], "roll": d_roll,
			"total": d_total, "pct": d_row["pct"], "inflicts": att_need,
			"lost_sailors": int(def_lost.get("sailors", 0)), "lost_marines": int(def_lost.get("marines", 0)),
			"helper_id": action.helper_id, "helper_sections": helper_secs_before,
			"below": below_before if below_defends(action) else 0},
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
	Trace.trace_log("Boarding", "Action %d round %d: %s %d (%d%+d) v %s %d (%d%+d): %s" % [action.id,
		action.rounds, att.ship_id, a_total, a_roll, int(drms["attacker"]["total"]), def.ship_id, d_total,
		d_roll, int(drms["defender"]["total"]), result["result"]])
	match str(result["result"]):
		"captured":
			return {"action": action, "kind": "capture", "mcs": 0,
				"outcome": "captured" if captured else ("struck_in_action" if def.is_struck() else "all_defenders_lost")}
		"repulsed":
			return {"action": action, "kind": "repulse", "outcome": "repulsed", "mcs": int(result["mcs"])}
		"driven_off":
			return {"action": action, "kind": "attackers_lost", "mcs": 0,
				"outcome": "attackers_lost" if not att.is_out_of_play() else "surrendered"}
	return {"action": action, "kind": "fight_on", "outcome": "", "mcs": 0}


## An action decided before its round is fought (10.D.6, 10.E.2c, 10.E.2e, 10.E.3a, the target
## gone): logged as a BOARDING_RESULT with no round, returned for _apply_outcomes.
func _no_round(action: BoardingAction, kind: String, outcome: String, phase: int) -> Dictionary:
	var result := {"special": "none", "side": "", "d10": -1, "mr": 0, "mcs": 0, "action": action.id,
		"result": "captured" if kind == "capture" else outcome, "reason": outcome}
	game_state.turn_log.add(PhaseEvents.Type.BOARDING_RESULT, phase, action.attacker_id, result, action.defender_id)
	return {"action": action, "kind": kind, "outcome": outcome, "mcs": 0}


## 10.F.3: the round's results, applied together once every action has rolled. Repulses and
## attackers lost first (those boarders are back aboard their ships, whatever else happens);
## then captures, a capture made by a ship that is itself taken this g-t before the capture of
## that ship (the 10.F.3 example: Mars takes Themis as Hermione takes Mars); a capture also takes
## the defender's other live actions with it (_share_capture). Then every action still live goes
## on (engaged, 10.E.1). Results for an action already ended by another result are dropped.
func _apply_outcomes(outcomes: Array, phase: int) -> void:
	var taken := {}
	for o in outcomes:
		if str(o["kind"]) == "capture":
			taken[(o["action"] as BoardingAction).defender_id] = true
	for o in outcomes:
		var a: BoardingAction = o["action"]
		if not a.is_live():
			continue
		match str(o["kind"]):
			"repulse":
				_repulse(a, int(o["mcs"]), phase)
			"attackers_lost":
				_attackers_lost(a, str(o["outcome"]), phase)
			"end":
				_end_action(a, BoardingAction.DEFENDER_WON, str(o["outcome"]), phase)
	var captures: Array = []
	for o in outcomes:
		if str(o["kind"]) == "capture" and taken.has((o["action"] as BoardingAction).attacker_id):
			captures.append(o)
	for o in outcomes:
		if str(o["kind"]) == "capture" and not taken.has((o["action"] as BoardingAction).attacker_id):
			captures.append(o)
	for o in captures:
		var a: BoardingAction = o["action"]
		if a.is_live():
			capture(a, false, phase, str(o["outcome"]))
	for o in outcomes:
		var a: BoardingAction = o["action"]
		if str(o["kind"]) == "fight_on" and a.is_live():
			a.state = BoardingAction.ENGAGED
			_engage_tasks(a)


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
	_disband_all(att_id, "repulsed", phase, action.id)
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


## Every FB, BR and BA task of the ship ends (10.D.5a "cross out their plots"), except sections
## locked in another boarding action than `action_id` (10.E.1, 10.F.3: one action's result does not
## touch another).
func _disband_all(ship_id: String, reason: String, phase: int, action_id: int = -1) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	for code in ShipState.BOARDER_CODES:
		for task in ship.tasks_with(code):
			var engaged_in := int(task.get("params", {}).get("action", -1))
			if BoardingTaskHandler.engaged(task) and engaged_in != action_id and action_by_id(engaged_in) != null \
					and action_by_id(engaged_in).is_live():
				continue
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
	_cut_off(def, phase)
	if def.is_captured() and att.side == def.original_side:
		# A prize boarded back by her own side: retaken (boarding spec §8 Q5). The winners reorganize
		# (10.G.2) and then come home; she needs no prize crew.
		action.retaken = true
		retake(def.ship_id, "boarded", phase, action)
		for s in _alive(att, action.attacker_sections):
			ctc.force_task(att.ship_id, [s], ReorganizeHandler.CODE,
				{"reason": "boarding", "prize": def.ship_id, "action": action.id}, phase)
		_set_order(att.ship_id, "")
		_share_capture(action, phase)
		return
	var original_crew := {"crew_count": def.crew_count.duplicate(), "marine_count": def.marine_count,
		"crew_quality": def.crew_quality, "morale_rating": def.morale_rating}
	var original_navy := def.gunnery_navy()
	var original_commander: int = game_state.commander_of(def.ship_id)
	if def.is_captured():
		# Taken from her captor by a third side: the old original crew stays below.
		original_crew = (def.prize.get("original_crew", {}) as Dictionary).duplicate(true)
		original_navy = str(def.prize.get("original_navy", original_navy))
		original_commander = int(def.prize.get("original_commander", original_commander))
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
		"original_commander": original_commander,
		"prize_crew_aboard": false,
	}, true)
	sc.set_crew(def.ship_id, [0, 0, 0, 0], 0)
	sc.set_navy(def.ship_id, att.gunnery_navy())  # 1.G.8: the navy using her (a prize does not fire, §8 Q2)
	sc.set_status(def.ship_id, ShipState.Status.CAPTURED)
	# Logged before control passes, so the line labels her by the side she was taken from.
	game_state.turn_log.add(PhaseEvents.Type.SHIP_CAPTURED, phase, def.ship_id,
		{"captor_id": att.ship_id, "struck_before": struck_before, "action": action.id, "outcome": action.outcome}, att.ship_id)
	game_state.transfer_control(def.ship_id, att.side)
	# Spec 2 (Prizes): commanded by the player commanding the ship whose boarders took her.
	sc.set_commander(def.ship_id, game_state.commander_of(att.ship_id))
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
	_share_capture(action, phase)
	Trace.trace_log("Boarding", "%s captured by %s (action %d, %s)" % [def.ship_id, att.ship_id, action.id, action.outcome])


## 10.F: the defender of `action` has just been taken (or retaken). Every other live action in which
## she defends against the same side ends with her: those boarders are aboard her as she is taken,
## and reorganize too (10.G.2; the 10.F.3 example: "All French CSs boarding the Mars must now
## reorganize"), then come home; the prize crew comes from `action` only (a reading of 10.G.8).
## Her own sections engaged in those actions go below with the rest of her crew (taken prisoner).
## Logged BOARDING_RESULT "shared_capture".
func _share_capture(action: BoardingAction, phase: int) -> void:
	var winner: ShipState = game_state.get_ship(action.attacker_id)
	var ctc: CrewTaskController = game_state.crew_task_controller
	for a in game_state.boarding_actions:
		if a == action or not a.is_live() or a.defender_id != action.defender_id:
			continue
		var att: ShipState = game_state.get_ship(a.attacker_id)
		if att == null or winner == null or att.side != winner.side:
			continue
		a.state = BoardingAction.ATTACKER_WON
		a.outcome = "shared_capture"
		a.finished_turn = _turn()
		a.shared_with = action.id
		a.retaken = action.retaken
		for s in _alive(att, a.attacker_sections):
			ctc.force_task(att.ship_id, [s], ReorganizeHandler.CODE,
				{"reason": "boarding", "prize": a.defender_id, "action": a.id}, phase)
		_set_order(att.ship_id, "")
		var data := {"result": "shared_capture", "action": a.id, "with": action.id, "captor_id": action.attacker_id,
			"special": "none", "d10": -1, "mr": 0, "mcs": 0}
		# Both actions may have rolled a capture this round (10.F.3): she is taken once, so this
		# action's own "captured" line gives way to the shared one, which keeps its roll.
		var rolled := _capture_result_of(a.id, phase)
		if rolled != null:
			for key in ["special", "side", "d10", "mr", "round"]:
				if rolled.data.has(key):
					data[key] = rolled.data[key]
			game_state.turn_log.remove(rolled)
		game_state.turn_log.add(PhaseEvents.Type.BOARDING_RESULT, phase, att.ship_id, data, a.defender_id)


## This g-t's BOARDING_RESULT "captured" line of action `action_id` in `phase`, or null.
func _capture_result_of(action_id: int, phase: int) -> PhaseEvents.PhaseEvent:
	for ev in game_state.turn_log.of_type(PhaseEvents.Type.BOARDING_RESULT):
		if ev.phase == phase and int(ev.data.get("action", -1)) == action_id \
				and str(ev.data.get("result", "")) == "captured":
			return ev
	return null


## `ship` is being taken: her own boarders elsewhere are cut off from her (10.D.6 and 10.G.2 by
## analogy). Those still fighting aboard an enemy surrender (the action is the defender's); those
## reorganizing aboard a prize she took are put aboard that prize at once as its prize crew, all of
## them, as when the ships part (spec 0.4 #6; the 10.F.3 example has Mars' boarders keep Themis as
## Mars is taken). Her sections defending a prize of hers under 10.G.5 go below with her crew.
func _cut_off(ship: ShipState, phase: int) -> void:
	for a in game_state.boarding_actions:
		if a.is_live() and a.attacker_id == ship.ship_id:
			_attackers_lost(a, "surrendered", phase)
		elif a.is_live() and a.helper_id == ship.ship_id:
			a.helper_id = ""
			a.helper_sections = []
	for a in game_state.boarding_actions:
		if a.state != BoardingAction.ATTACKER_WON or a.prize_aboard or a.attacker_id != ship.ship_id:
			continue
		var prize: ShipState = game_state.get_ship(a.defender_id)
		if a.retaken or a.shared_with >= 0 or prize == null or not prize.is_captured() \
				or str(prize.prize.get("captor_id", "")) != ship.ship_id or prize.has_prize_crew():
			a.prize_aboard = true  # the boarders go below with her crew
			continue
		_put_prize_crew_aboard(a, ship, prize, phase, true)


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
		if att == null or prize == null or att.is_destroyed() or prize.is_destroyed() \
				or not att.is_on_map() or not prize.is_on_map():  # blown up or escaped
			action.prize_aboard = true
			continue
		if _still_reorganizing(action, att):
			continue
		if action.retaken or action.shared_with >= 0 or not prize.is_captured() \
				or prize.prize.get("captor_id", "") != att.ship_id:
			action.prize_aboard = true  # retaken or shared (10.F): the boarders come home with no prize crew
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
	if action.state != BoardingAction.ATTACKER_WON or action.prize_aboard or action.retaken or action.shared_with >= 0:
		return false
	var att: ShipState = game_state.get_ship(action.attacker_id)
	var prize: ShipState = game_state.get_ship(action.defender_id)
	if att == null or prize == null or att.is_destroyed() or prize.is_destroyed() or not prize.is_captured() \
			or not att.is_on_map() or not prize.is_on_map():
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
		if not game_state.commands(player_id, att.ship_id) or not att.linked_ids().has(prize.ship_id):
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


func _put_prize_crew_aboard(action: BoardingAction, att: ShipState, prize: ShipState, phase: int,
		every_boarder: bool = false) -> void:
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
	if every_boarder or not att.linked_ids().has(prize.ship_id):
		size = available  # parted while reorganizing, or cut off: every boarder is aboard the prize (0.4 #6)
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
	# The captor's boarders aboard her, and those of ships that shared her capture (10.F).
	var aboard := {captor_id: helper_secs}
	for a in game_state.boarding_actions:
		if a.state != BoardingAction.ATTACKER_WON or a.defender_id != ship_id or aboard.has(a.attacker_id):
			continue
		var holder_ship: ShipState = game_state.get_ship(a.attacker_id)
		if holder_ship != null and holder_ship.side != ship.original_side:
			aboard[a.attacker_id] = [] as Array[int]
	for holder_id in aboard:
		var holder: ShipState = game_state.get_ship(str(holder_id))
		if holder == null:
			continue
		var secs: Array[int] = aboard[holder_id]
		for task in holder.tasks_with(ReorganizeHandler.CODE):
			if str(task.get("params", {}).get("prize", "")) == ship_id:
				for s in task.get("sections", []):
					if not secs.has(int(s)):
						secs.append(int(s))
		for s in secs:
			prisoners += _cross_off(str(holder_id), s, phase)
	data["prisoners"] = prisoners
	data["captor_id"] = captor_id  # whose boxes the prisoners are (PlayerView, 14.C)
	ctc.cancel_all_except(ship_id, "", "retaken", phase)
	sc.clear_crew_plot(ship_id)
	sc.set_crew_orders(ship_id, {"boarding": ""})
	sc.clear_pending_morale_checks(ship_id)
	sc.set_value_morale_rating(ship_id, ship.original_morale_rating())
	sc.set_crew(ship_id, original.get("crew_count", [0, 0, 0, 0]), int(original.get("marine_count", 0)))
	sc.set_crew_quality(ship_id, RETAKEN_QUALITY)
	sc.set_morale_rating(ship_id, RETAKEN_MORALE)
	sc.set_navy(ship_id, str(ship.prize.get("original_navy", "")))
	var commander := _retaken_commander(ship)
	sc.set_prize(ship_id, {}, true)
	sc.set_status(ship_id, ShipState.Status.ACTIVE)
	game_state.transfer_control(ship_id, ship.original_side)
	sc.set_commander(ship_id, commander)
	_finish_captures_of(ship_id, action.id if action != null else -1, phase)
	game_state.turn_log.add(PhaseEvents.Type.RECAPTURED, phase, ship_id, data,
		action.attacker_id if action != null else captor_id)
	Trace.trace_log("Boarding", "%s retaken (%s)" % [ship_id, cause], data)


## Spec 2 (Prizes): a retaken ship goes back to the player who commanded her before her capture;
## when that player no longer exists or commands no other ship in play, to the lowest-id player of
## her side (-1, her side's default player, in a game without a roster).
func _retaken_commander(ship: ShipState) -> int:
	var before := int(ship.prize.get("original_commander", -1))
	var player = game_state.get_player(before)
	if player != null and player.side == ship.original_side:
		for other: ShipState in game_state.in_play_ships_of_player(before):
			if other.ship_id != ship.ship_id:
				return before
	var of_side: Array = game_state.players_of_side(ship.original_side)
	if not of_side.is_empty():
		return of_side[0].id
	return -1


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
