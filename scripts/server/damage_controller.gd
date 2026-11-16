class_name DamageController
extends RefCounted
## DamageController - Applies rigging, hull and crew hits to a ship (Close Action 1997, 9.5).
## Boxes come off the lowest-numbered section first. All mutations go through ShipStateController.

## Morale checks noted when hull section 1, 2 or 3 is emptied
const HULL_MORALE_CHECKS: Array[int] = [1, 1, 2]
## DAMAGE "cause" for boxes lost to a critical hit (7.D.12)
const CAUSE_CRITICAL := "critical"

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## Marks out boxes, lowest-numbered section first. Each rigging section and hull section 1-3
## emptied queues a Rigging/Hull Check (7.D.7, 7.D.8a, 7.D.12) on the CriticalHitController with
## `ctx` (the shot's critical context, see CriticalHitController; {} outside gunfire). The queue
## is drained at the end unless the controller is holding or already draining.
## `damage_cause` ("", CAUSE_CRITICAL, or FireController's "fire" / "blast") is recorded on the DAMAGE event.
func apply_hits(ship_id: String, rigging: int, hull: int, crew: int, crew_cause: String,
		phase: int, source_id: String = "", ctx: Dictionary = {}, damage_cause: String = "") -> void:
	if not is_server:
		push_error("DamageController: Cannot apply hits on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return
	if ship.is_destroyed():
		return  # a wreck takes no damage
	var struck_before := ship.is_struck()
	var dismasted_before := ship.is_dismasted()
	# The DAMAGE line is the cause; guns dismounted, morale checks and a strike logged while the
	# hits are applied are its consequences, so it goes in ahead of them.
	var damage_index: int = game_state.turn_log.events.size()

	if rigging > 0 and dismasted_before:
		rigging_hit_while_dismasted(ship_id, phase)  # 8.F.6 (a fire's 1R, a critical's rigging loss)
	var rigging_applied := _apply_rigging(ship, ship_id, rigging, phase, struck_before, ctx)
	var hull_applied := _apply_hull(ship, ship_id, hull, phase, struck_before, ctx)
	var crew_rolls: Array = []
	var marines_before := ship.marine_count
	var crew_applied := _apply_crew(ship, ship_id, crew, crew_cause, phase, struck_before, crew_rolls)
	var marines_lost := marines_before - ship.marine_count

	var data := {
		"rigging": rigging_applied,
		"hull": hull_applied,
		"crew": crew_applied,
		"sailors_lost": crew_applied - marines_lost,
		"marines_lost": marines_lost,
		"crew_rolls": crew_rolls,
	}
	if damage_cause != "":
		data["cause"] = damage_cause
	game_state.turn_log.insert(damage_index, PhaseEvents.Type.DAMAGE, phase, ship_id, data, source_id)
	_drain_checks(phase)


## Marks out `count` crew boxes, each rolled on the Crew Loss table row `crew_cause`
## ("gunfire_at_hull" or "other"), one d6 per box, except that no d6 is rolled while the ship has only
## one type of crew left (7.D.9, 7.G.3: the loss is that type). Marine fire uses it (7.G.3). Emptied
## sections note morale checks and cancel their tasks, and a ship left with no crew strikes, as for
## gunfire. Logged as DAMAGE with `damage_cause` (e.g. "marine_fire"). Returns the boxes marked out.
func apply_crew_losses(ship_id: String, count: int, crew_cause: String, phase: int,
		source_id: String = "", damage_cause: String = "") -> int:
	if not is_server:
		push_error("DamageController: Cannot apply crew losses on client")
		return 0
	var ship: ShipState = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return 0
	if ship.is_destroyed():
		return 0  # a wreck takes no damage
	var struck_before := ship.is_struck()
	var damage_index: int = game_state.turn_log.events.size()
	var marines_before := ship.marine_count
	var rolls: Array = []
	var applied := _apply_crew(ship, ship_id, count, crew_cause, phase, struck_before, rolls, false)
	var marines_lost := marines_before - ship.marine_count
	var data := {
		"rigging": 0,
		"hull": 0,
		"crew": applied,
		"sailors_lost": applied - marines_lost,
		"marines_lost": marines_lost,
		"crew_rolls": rolls,
	}
	if damage_cause != "":
		data["cause"] = damage_cause
	game_state.turn_log.insert(damage_index, PhaseEvents.Type.DAMAGE, phase, ship_id, data, source_id)
	return applied


## Marks out `count` crew boxes directly, with no Crew Loss roll (critical-hit crew losses:
## leadership casualties, mast falls on deck, men sent to the pumps). Takes marines first when
## `marines_first`, else sailors from the lowest-numbered section; when one type runs out the
## other is taken. Emptied sections note morale checks and a ship left with no crew strikes, as
## for gunfire. Logged as DAMAGE with cause "critical". Returns the boxes marked out.
func apply_crew_boxes(ship_id: String, count: int, marines_first: bool, phase: int,
		source_id: String = "") -> int:
	if not is_server:
		push_error("DamageController: Cannot apply crew losses on client")
		return 0
	var ship: ShipState = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return 0
	if ship.is_destroyed():
		return 0  # a wreck takes no damage
	var struck_before := ship.is_struck()
	var damage_index: int = game_state.turn_log.events.size()
	var marines_before := ship.marine_count
	var applied := 0
	for i in range(count):
		if ship.total_crew_boxes() == 0:
			break
		var emptied: int = game_state.ship_controller.remove_crew_box(ship_id, marines_first)
		applied += 1
		if emptied >= 0 and game_state.get("crew_task_controller") != null:
			# 4.B.3: a section completely marked out loses its task and its progress.
			game_state.crew_task_controller.cancel_section(ship_id, emptied, "crew lost", phase)
		if emptied >= 0 and not struck_before:
			_note_morale(ship_id, "crew_%d" % emptied, 1, phase)
	if applied > 0 and ship.total_crew_boxes() == 0 and not struck_before:
		strike(ship_id, "no crew", phase)
	var marines_lost := marines_before - ship.marine_count
	game_state.turn_log.insert(damage_index, PhaseEvents.Type.DAMAGE, phase, ship_id, {
		"rigging": 0,
		"hull": 0,
		"crew": applied,
		"sailors_lost": applied - marines_lost,
		"marines_lost": marines_lost,
		"cause": CAUSE_CRITICAL,
	}, source_id)
	return applied


## 8.F.6: a dismasted ship that suffers a rigging hit (a gunfire or blast result with an r, a
## fire's 1R, a critical hit's rigging loss; spec 0.3 #6) loses all its rigging-repair progress;
## the repair goes on from 0. Gunfire and blast call this themselves, since they mark no rigging
## on a dismasted ship.
func rigging_hit_while_dismasted(ship_id: String, phase: int) -> void:
	if not is_server:
		push_error("DamageController: Cannot cancel repairs on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or not ship.is_dismasted():
		return
	if game_state.get("crew_task_controller") != null:
		game_state.crew_task_controller.reset_progress(ship_id, RepairController.CODE_RR,
			RepairController.RESET_DISMASTED, phase)


func strike(ship_id: String, reason: String, phase: int) -> void:
	if not is_server:
		push_error("DamageController: Cannot strike a ship on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return
	if ship.is_out_of_play():
		return
	game_state.ship_controller.set_status(ship_id, ShipState.Status.STRUCK)
	game_state.turn_log.add(PhaseEvents.Type.STRIKE, phase, ship_id, {"reason": reason})
	if game_state.get("crew_task_controller") != null:
		# A struck ship only fights its fires (8.E.3, 9.C.3): every other task ends.
		game_state.crew_task_controller.cancel_all_except(ship_id, "FF", "struck", phase)
	Trace.trace_log("Damage", "Ship %s strikes: %s" % [ship_id, reason])


## An explosion (hull #12, or a burning hulk, 8.E.8): the ship is destroyed and leaves play (spec Q2). Its fires go, its fouling is cleared on
## both ships (the partner is freed), a sail change in progress or ordered is dropped and its
## pending morale checks are cleared. The wreck keeps its two hexes, which still block movement
## and line of sight. A struck ship can still be destroyed. Logs DESTROYED.
func destroy(ship_id: String, reason: String, phase: int) -> void:
	if not is_server:
		push_error("DamageController: Cannot destroy a ship on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return
	if ship.is_destroyed():
		return
	var sc: ShipStateController = game_state.ship_controller
	sc.set_status(ship_id, ShipState.Status.DESTROYED)
	var partner_id := ship.fouled_with
	if partner_id != "":
		sc.set_fouled_with(ship_id, "")
		var partner: ShipState = game_state.get_ship(partner_id)
		if partner != null and partner.fouled_with == ship_id:
			sc.set_fouled_with(partner_id, "")
	for grappled_id in ship.grappled_with.duplicate():
		sc.remove_grapple(ship_id, grappled_id)  # a wreck holds no grapples (8.C)
	if game_state.get("crew_task_controller") != null:
		game_state.crew_task_controller.drop_all(ship_id, "destroyed")
	sc.clear_fires(ship_id)  # a wreck does not burn (spec Q10)
	sc.clear_pending_morale_checks(ship_id)
	game_state.turn_log.add(PhaseEvents.Type.DESTROYED, phase, ship_id, {"reason": reason}, partner_id)
	Trace.trace_log("Damage", "Ship %s destroyed: %s" % [ship_id, reason])


func _apply_rigging(ship: ShipState, ship_id: String, amount: int, phase: int,
		struck_before: bool, ctx: Dictionary) -> int:
	var applied := 0
	for section in range(ship.rigging_current_hp.size()):
		var emptied := false
		while applied < amount and ship.rigging_current_hp[section] > 0:
			game_state.ship_controller.apply_rigging_damage(ship_id, section, 1)
			applied += 1
			emptied = ship.rigging_current_hp[section] == 0
		# 8.F.5, 9.B.2: a section restored by a repair and lost again is not checked again.
		if emptied and not ship.checked_sections["rigging"][section]:
			game_state.ship_controller.mark_section_checked(ship_id, "rigging", section)
			if not struck_before:
				_queue_check(ship_id, "rigging", section, ctx)
	if applied > 0 and ship.is_dismasted():
		game_state.ship_controller.set_sail_state(ship_id, "NS")
		if game_state.get("crew_task_controller") != null:
			game_state.crew_task_controller.cancel_code(ship_id, SailController.CODE, "dismasted", phase, false)
		var crits = game_state.get("critical_hit_controller")
		if crits != null:
			crits.clear_lines_jammed_on_dismasting(ship_id, phase)
		if not struck_before:
			_note_morale(ship_id, "dismasted", 1, phase)
	return applied


func _apply_hull(ship: ShipState, ship_id: String, amount: int, phase: int,
		struck_before: bool, ctx: Dictionary) -> int:
	var applied := 0
	for section in range(ship.hull_current_hp.size()):
		var emptied := false
		while applied < amount and ship.hull_current_hp[section] > 0:
			game_state.ship_controller.apply_hull_damage(ship_id, section, 1)
			applied += 1
			emptied = ship.hull_current_hp[section] == 0
		if not emptied:
			continue
		if section < HULL_MORALE_CHECKS.size():
			# 8.F.5, 9.B.2, spec 0.3 #7: a hull section repaired and lost again dismounts no guns
			# and gives no Hull Check or morale check.
			if ship.checked_sections["hull"][section]:
				continue
			game_state.ship_controller.mark_section_checked(ship_id, "hull", section)
			var guns := section + 1
			game_state.ship_controller.add_guns_dismounted(ship_id, guns)
			game_state.turn_log.add(PhaseEvents.Type.GUNS_DISMOUNTED, phase, ship_id, {"amount": guns})
			if not struck_before:
				_note_morale(ship_id, "hull_%d" % (section + 1), HULL_MORALE_CHECKS[section], phase)
				_queue_check(ship_id, "hull", section, ctx)
		elif not struck_before:
			# No Hull Check for the last section: the ship strikes (spec Q5).
			strike(ship_id, "hull destroyed", phase)
	return applied


func _apply_crew(ship: ShipState, ship_id: String, amount: int, cause: String, phase: int,
		struck_before: bool, rolls: Array, roll_single_type: bool = true) -> int:
	var applied := 0
	for i in range(amount):
		if ship.total_crew_boxes() == 0:
			break
		var sailor: bool
		var sailors_left := ship.total_crew_boxes() - ship.marine_count
		if not roll_single_type and (ship.marine_count == 0 or sailors_left == 0):
			# 7.D.9, 7.G.3: only one type of crew remains, so the loss is that type; no roll.
			sailor = ship.marine_count == 0
		else:
			var roll: int = game_state.dice.d6()
			rolls.append(roll)
			sailor = DataManager.combat_tables.crew_loss_is_sailor(cause, roll)
		var emptied: int = game_state.ship_controller.remove_crew_box(ship_id, not sailor)
		applied += 1
		if emptied >= 0 and game_state.get("crew_task_controller") != null:
			# 4.B.3: a section completely marked out loses its task and its progress.
			game_state.crew_task_controller.cancel_section(ship_id, emptied, "crew lost", phase)
		if emptied >= 0 and not struck_before:
			_note_morale(ship_id, "crew_%d" % emptied, 1, phase)
	if applied > 0 and ship.total_crew_boxes() == 0 and not struck_before:
		strike(ship_id, "no crew", phase)
	return applied


func _queue_check(ship_id: String, table: String, section: int, ctx: Dictionary) -> void:
	var crits = game_state.get("critical_hit_controller")
	if crits == null:
		return
	if table == "rigging":
		crits.queue_rigging_check(ship_id, ctx, section)
	else:
		crits.queue_hull_check(ship_id, ctx, section)


func _drain_checks(phase: int) -> void:
	var crits = game_state.get("critical_hit_controller")
	if crits != null and not crits.is_holding():
		crits.drain(phase)


func _note_morale(ship_id: String, trigger: String, count: int, phase: int) -> void:
	if game_state.ship_controller.note_morale_check(ship_id, trigger, count):
		game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, ship_id,
				{"trigger": trigger, "count": count})
