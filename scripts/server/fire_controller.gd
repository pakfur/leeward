class_name FireController
extends CrewTaskHandler
## FireController - fires and explosions (Close Action 1997, 8.E, 9.B.1c-d, Sequence of Play V.F;
## crew-tasks spec §3.5) and the FF crew-task handler (8.E.2).
##
## - start_fire: a fire breaks out (hull criticals #10 and #12, spread, growth, flaming debris). It
##   notes one morale check (8.E.7, 9.B.1c; trigger "fire_<seq>", none for a struck ship) and a
##   section standing by on fire watch (FF with no fire, 8.E.2 HINT) is attached to it at once.
##   A fire made in the Combat Phase burns that g-t; one made in the Fire & Explosions sub-phase
##   burns from the next (spec 0.3 #5).
## - resolve: the Fire & Explosions sub-phase, in STATUS_ADJUSTMENT after the fix rolls.
## - explode: the ship is destroyed (the wreck stays, spec Q10), then blast (8.E.10) and flaming
##   debris (8.E.11) on the other ships.
##
## Readings (crew-tasks spec §9 Q1, Q5): better crews resist fire, so hull #10 sets a fire on
## d10 + SK >= 6 and a fire spreads on d10 <= 4 + SK. Wiped-out marines are not "not available".
## Struck ships fight fires as CQ G (9.C.4) and take no morale checks.
##
## Rolls only through game_state.dice. All mutations go through ShipStateController,
## DamageController and CrewTaskController.

const CODE := "FF"
const CAUSE_CRIT := "crit"
const CAUSE_SPREAD := "spread"
const CAUSE_GROWTH := "growth"
const CAUSE_DEBRIS := "debris"
## DAMAGE "cause" for boxes lost to a fire and to a blast
const DAMAGE_FIRE := "fire"
const DAMAGE_BLAST := "blast"
## Crew-task end reason when the fire is put out
const ENDED_OUT := "fire out"
## DESTROYED reason (shared with hull #12)
const REASON_EXPLOSION := "explosion"
## Struck ships fight fires as crew quality G (9.C.4)
const STRUCK_QUALITY := "G"


func _init(p_game_state: Node) -> void:
	super(p_game_state)


# --- The FF handler (8.E.2) ---

## A plot continues an FF task when it names the same fire (and, for fire watch, the same section).
func same_task(task: Dictionary, params: Dictionary) -> bool:
	var a: Dictionary = task.get("params", {})
	return int(a.get("fire", -1)) == int(params.get("fire", -1)) \
		and int(a.get("section", -1)) == int(params.get("section", -1))


func prepare(ship: ShipState, candidate: Dictionary) -> String:
	var fire := int(candidate.get("params", {}).get("fire", -1))
	if fire >= 0 and ship.fire_by_seq(fire).is_empty():
		return ENDED_OUT
	return ""


func cancel_reason(ship: ShipState, task: Dictionary) -> String:
	var reason := super(ship, task)
	if reason != "":
		return reason
	var fire := int(task.get("params", {}).get("fire", -1))
	if fire >= 0 and ship.fire_by_seq(fire).is_empty():
		return ENDED_OUT
	return ""


## Only g-t's in which the section rolled count (spec 0.2 Q5: the column is the g-t's the same
## section has fought that fire; fire-watch time earns none, 0.3 #4).
func counts_turn(_ship: ShipState, task: Dictionary) -> bool:
	return int(task.get("fought_turn", -1)) == _turn()


# --- Fires breaking out ---

## Ship's SK for fire rolls: CQ G once struck (9.C.4).
func skill(ship: ShipState) -> int:
	return DataManager.combat_tables.skill_modifier(STRUCK_QUALITY if ship.is_struck() else ship.crew_quality)


## A fire breaks out aboard `ship_id`. `extra` is added to the FIRE_STARTED event (rolls).
## Returns the fire's seq, or -1 (no ship, or a wreck: a destroyed ship does not burn).
func start_fire(ship_id: String, cause: String, phase: int, source_id: String = "",
		in_fire_subphase: bool = false, extra: Dictionary = {}) -> int:
	if not is_server:
		push_error("FireController: Cannot start a fire on client")
		return -1
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.is_destroyed():
		return -1
	var sc: ShipStateController = game_state.ship_controller
	var seq: int = sc.add_fire(ship_id, cause, in_fire_subphase)
	if seq < 0:
		return -1
	var trigger := "fire_%d" % seq
	var mc := false
	if not ship.is_out_of_play():
		mc = sc.note_morale_check(ship_id, trigger)  # 8.E.7, 9.B.1c
	var data := {"fire": seq, "fires": ship.fire_count(), "cause": cause, "mc": mc}
	data.merge(extra, false)
	game_state.turn_log.add(PhaseEvents.Type.FIRE_STARTED, phase, ship_id, data, source_id)
	if mc:
		game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, ship_id, {"trigger": trigger, "count": 1})
	_attach_watch(ship, seq, phase)
	var ctc = game_state.get("crew_task_controller")
	if ctc != null:
		ctc.notify_fire_breaks_out(ship_id)
	Trace.trace_log("Fire", "Fire %d breaks out aboard %s (%s)" % [seq, ship_id, cause])
	return seq


## 8.E.2 HINT: the lowest-numbered section standing by on fire watch turns to the new fire. It
## starts in the "1" column (standing-by time earns none).
func _attach_watch(ship: ShipState, seq: int, phase: int) -> void:
	var best: Dictionary = {}
	for task in ship.tasks_with(CODE):
		if int(task.get("params", {}).get("fire", -1)) >= 0:
			continue
		var sections: Array = task.get("sections", [])
		if sections.is_empty():
			continue
		if best.is_empty() or int(sections.min()) < int((best["sections"] as Array).min()):
			best = task
	if best.is_empty():
		return
	game_state.ship_controller.update_task(ship.ship_id, int(best["seq"]), {"params": {"fire": seq}, "done": 0})
	game_state.turn_log.add(PhaseEvents.Type.CREW_TASK, phase, ship.ship_id, {
		"code": CODE, "sections": (best["sections"] as Array).duplicate(), "params": {"fire": seq},
		"state": "attached", "done": 0, "needed": -1,
	})


# --- The Fire & Explosions sub-phase (SoP V.F) ---

## STATUS_ADJUSTMENT, after the fix rolls. Each step runs over every ship (ascending ship_id) before
## the next step; within a ship, fires by seq. Dice order (the contract for ScriptedDice):
##   1. firefighting: one d10 per fire with a live FF task (8.E.3; out when
##      d10 + SK + 1 if the marines are busy <= Unfouling number for the section's attempt 1/2/3+);
##   2. damage: per ship, 1R and 1H for each fire burning since this g-t or earlier (8.E.8); the
##      crew-loss rolls (none) and the Rigging/Hull Check d6s it causes come here;
##   3. growth (no dice: every growth_turns g-t's a fire grows another, 8.E.5), then spread: per
##      burning ship, per ship fouled to it, one d10 for that ship (8.E.4: d10 <= 4 + its SK).
##      Fires that existed at the start of this step are the ones that grow and spread;
##   4. explosions: per burning ship with no hull boxes, 2d6 <= 2 + earlier rolls (8.E.8); an
##      explosion rolls its blast d6s (with slashed, half-box and crew-loss d6s) and debris d6s in
##      ship order (see explode). A ship later in id order that loses its last hull box to a blast
##      in this step rolls in this step;
##   5. unfought fires: no dice; one MC per fire that existed at plotting and has no FF task (8.E.6).
## Fires made in steps 3-4 do no damage this g-t (spec 0.2 Q4).
func resolve(phase: int) -> void:
	if not is_server:
		push_error("FireController: Cannot resolve fires on client")
		return
	var turn := _turn()
	var tables: CombatTables = DataManager.combat_tables
	var sc: ShipStateController = game_state.ship_controller
	var ids := _sorted_ids()
	# 1. Firefighting
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.is_destroyed():
			continue
		for seq in ship.fire_seqs():
			var task := ship.fire_task(seq).duplicate(true)
			if task.is_empty() or cancel_reason(ship, task) != "":
				continue
			var attempt := int(task.get("done", 0)) + 1
			var roll: int = game_state.dice.d10()
			var modifier := skill(ship)
			if ship.marines_busy():
				modifier += tables.marines_unavailable_modifier()
			var needed: int = tables.unfouling_success_max(attempt)
			var success := roll + modifier <= needed
			sc.update_task(ship_id, int(task["seq"]), {"fought_turn": turn})
			game_state.turn_log.add(PhaseEvents.Type.FIRE_FOUGHT, phase, ship_id, {
				"fire": seq, "number": ship.fire_seqs().find(seq) + 1,
				"sections": (task.get("sections", []) as Array).duplicate(),
				"roll": roll, "modifier": modifier, "needed": needed, "attempt": attempt, "success": success,
			})
			if success:
				sc.remove_fire(ship_id, seq)
				game_state.crew_task_controller.cancel_task(ship_id, int(task["seq"]), ENDED_OUT, phase, false)
	# 2. Damage
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.is_destroyed():
			continue
		var burning := 0
		for fire in ship.fire_list:
			if int(fire.get("started_turn", turn)) <= turn:
				burning += 1
		if burning > 0:
			game_state.damage_controller.apply_hits(ship_id, burning, burning, 0, "other", phase, "", {}, DAMAGE_FIRE)
	# 3. Growth, then spread (fires existing at the start of the step)
	var at_start := {}
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship != null and not ship.is_destroyed() and ship.is_burning():
			at_start[ship_id] = ship.fire_list.duplicate(true)
	var growth := tables.fire_rule("growth_turns")
	for ship_id: String in ids:
		for fire in at_start.get(ship_id, []):
			var age := turn - int(fire["started_turn"]) + 1
			if growth > 0 and age > 0 and age % growth == 0:
				start_fire(ship_id, CAUSE_GROWTH, phase, "", true, {"from_fire": int(fire["seq"]), "age": age})
	for ship_id: String in ids:
		if not at_start.has(ship_id):
			continue
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.is_destroyed():
			continue
		for partner_id in _attached_ids(ship):
			var partner: ShipState = game_state.get_ship(partner_id)
			if partner == null or partner.is_destroyed():
				continue
			var roll: int = game_state.dice.d10()
			var needed: int = tables.fire_rule("spread_number") + skill(partner)
			var spreads := roll <= needed
			game_state.turn_log.add(PhaseEvents.Type.FIRE_SPREAD, phase, ship_id,
				{"roll": roll, "needed": needed, "spreads": spreads}, partner_id)
			if spreads:
				start_fire(partner_id, CAUSE_SPREAD, phase, ship_id, true, {"roll": roll, "needed": needed})
	# 4. Explosions
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.is_destroyed() or not ship.is_burning() or _hull_boxes(ship) > 0:
			continue
		game_state.damage_controller.strike(ship_id, "hull destroyed", phase)  # no-op if already struck
		var roll: int = game_state.dice.two_d6()
		var needed: int = tables.fire_rule("explode_max") + ship.explosion_checks
		var explodes := roll <= needed
		game_state.turn_log.add(PhaseEvents.Type.EXPLOSION_CHECK, phase, ship_id,
			{"roll": roll, "needed": needed, "explodes": explodes})
		if explodes:
			explode(ship_id, phase)
		else:
			sc.set_explosion_checks(ship_id, ship.explosion_checks + 1)
	# 5. Unfought fires (8.E.6, 9.B.1d)
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.is_out_of_play():
			continue
		for seq in ship.fire_seqs():
			var fire := ship.fire_by_seq(seq)
			if int(fire.get("created_turn", turn)) >= turn or not ship.fire_task(seq).is_empty():
				continue
			var trigger := "unfought_%d_%d" % [seq, turn]
			var mc := sc.note_morale_check(ship_id, trigger)
			game_state.turn_log.add(PhaseEvents.Type.FIRE_UNFOUGHT, phase, ship_id,
				{"fire": seq, "number": ship.fire_seqs().find(seq) + 1, "mc": mc})
			if mc:
				game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, ship_id, {"trigger": trigger, "count": 1})


# --- Explosions (8.E.8-11, hull #12) ---

## The ship explodes: it is destroyed (fires and tasks cleared; the wreck stays), then every other
## ship not destroyed, in ascending id, takes blast at range 1-2 (8.E.10), then, in the same order,
## flaming debris within 6 hexes (8.E.11). Ships fouled to it catch fire with no roll.
## Dice: per ship in blast range, the blast d6, one d6 per slashed result, the half-box d6 for a
## furled ship with odd rigging, the crew-loss d6s, then any Rigging/Hull Check d6s (at once, or
## after the shot when the critical-hit queue is held in the Combat Phase); then per ship in debris
## range, not fouled to it, one d6.
func explode(ship_id: String, phase: int) -> void:
	if not is_server:
		push_error("FireController: Cannot explode a ship on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.is_destroyed():
		return
	var attached := _attached_ids(ship)
	var hexes := ship.occupied_hexes()
	var ship_class: int = ship.ship.ship_class if ship.ship != null else 0
	game_state.damage_controller.destroy(ship_id, REASON_EXPLOSION, phase)
	var tables: CombatTables = DataManager.combat_tables
	var in_subphase := phase == TurnPhaseController.GamePhase.STATUS_ADJUSTMENT
	var ids := _sorted_ids()
	for other_id: String in ids:
		var other: ShipState = game_state.get_ship(other_id)
		if other_id == ship_id or other == null or other.is_destroyed():
			continue
		var r: int = game_state.fire_geometry.range_between(hexes, other.occupied_hexes())
		var mgn: int = tables.blast_mgn(ship_class, r)
		if mgn >= 0:
			_blast(ship_id, other, r, mgn, phase)
	var radius: int = tables.fire_rule("debris_radius")
	var never: int = tables.fire_rule("debris_never")
	for other_id: String in ids:
		var other: ShipState = game_state.get_ship(other_id)
		if other_id == ship_id or other == null or other.is_destroyed():
			continue
		var r: int = game_state.fire_geometry.range_between(hexes, other.occupied_hexes())
		if r < 0 or r > radius:
			continue
		if attached.has(other_id):
			game_state.turn_log.add(PhaseEvents.Type.DEBRIS, phase, ship_id,
				{"range": r, "attached": true, "afire": true}, other_id)
			start_fire(other_id, CAUSE_DEBRIS, phase, ship_id, in_subphase, {"range": r, "attached": true})
			continue
		var roll: int = game_state.dice.d6()
		var afire := roll != never and roll >= r
		game_state.turn_log.add(PhaseEvents.Type.DEBRIS, phase, ship_id,
			{"range": r, "roll": roll, "afire": afire}, other_id)
		if afire:
			start_fire(other_id, CAUSE_DEBRIS, phase, ship_id, in_subphase, {"range": r, "roll": roll})


## 8.E.10: FGN = blast MGN + d6 on the "firing high" side, columns by the target's carried sail
## state, no modifiers and no critical-hit roll (spec 0.2 Q8). Results are read as for gunfire
## (slashed results by d6, furled rigging halved, nothing on a dismasted ship's rigging); crew boxes
## use the Crew Loss "All Other Causes" row.
func _blast(source_id: String, target: ShipState, range_hexes: int, mgn: int, phase: int) -> void:
	var d6: int = game_state.dice.d6()
	var fgn := mgn + d6
	var sail := target.sail_state.to_upper()
	var columns: Array[String] = ["fs"]
	if sail == "MS" or sail == "PS":
		columns.append("ms")
	if sail == "PS":
		columns.append("ps")
	var totals := {"r": 0, "h": 0, "c": 0}
	for column in columns:
		for token in DataManager.combat_tables.gunfire_result(fgn, GunneryTypes.AIM_HIGH, column):
			var alternative: Dictionary = token[0]
			if token.size() > 1:
				alternative = token[0] if game_state.dice.d6() <= 3 else token[1]
			if alternative.has("type"):
				totals[alternative["type"]] += int(alternative["count"])
	var rigging: int = totals["r"]
	if target.is_dismasted():
		rigging = 0
	elif sail == "NS":
		@warning_ignore("integer_division")
		var half := rigging / 2
		if rigging % 2 == 1 and game_state.dice.d6() <= 3:
			half += 1
		rigging = half
	game_state.turn_log.add(PhaseEvents.Type.BLAST, phase, source_id, {
		"range": range_hexes, "mgn": mgn, "d6": d6, "fgn": fgn,
		"rigging": rigging, "hull": totals["h"], "crew": totals["c"],
	}, target.ship_id)
	game_state.damage_controller.apply_hits(target.ship_id, rigging, totals["h"], totals["c"], "other",
		phase, source_id, {}, DAMAGE_BLAST)


# --- helpers ---

## Ships fouled (later: grappled) to `ship`, in id order.
func _attached_ids(ship: ShipState) -> Array:
	var out: Array = []
	if ship.fouled_with != "":
		out.append(ship.fouled_with)
	out.sort()
	return out


func _hull_boxes(ship: ShipState) -> int:
	var total := 0
	for hp in ship.hull_current_hp:
		total += int(hp)
	return total


func _sorted_ids() -> Array:
	var ids: Array = game_state.ships.keys()
	ids.sort()
	return ids


func _turn() -> int:
	var turn = game_state.get("current_turn") if game_state != null else null
	return int(turn) if turn != null else 0
