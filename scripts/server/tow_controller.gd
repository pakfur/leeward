class_name TowController
extends CrewTaskHandler
## TowController - towing (Close Action 1997, 12.A; towing spec §3, §4, §6) and the crew-task
## handler of PT (prepare to tow, 12.A.3) and TX (cut the tow, 12.A.9). One instance
## (game_state.tow_controller) is registered for every TowRules.CODES code.
##
## - §3, the tasks: whether one may start is TowRules.refusal (prepare). A completed PT makes the
##   tow ready (ShipState.tow_prepared); a completed TX does nothing here (the cut is made in V.B,
##   §6). A PT ends once the ship is towing; a TX once the tow is gone, unless it began this g-t
##   (its own cut in V.B removed the tow, and it then completes).
## - §4, the tow attempt (resolve_tow_attempts): at the start of STATUS_ADJUSTMENT, before the
##   grapple prompt (SoP V.C), every ship with a standing "take:<id>" order, by ship id. A target
##   that may no longer be taken in tow at all (TowRules.take_target_error: unknown, own, enemy,
##   struck or destroyed) clears the order, logged as one TOW_BEGUN with `lapsed` and no roll; any
##   other TowRules.pair_error is traced and the order stands. Else the tower rolls the grapple
##   roll with the towing -1 (12.A.4b, GrapplingController.grapple_chance) and logs TOW_BEGUN;
##   success begins the tow (begin), which clears the order.
## - §6, cutting (resolve_cuts, SoP V.B, after anchoring in DRIFT_CALCULATION): a live TX begun
##   this g-t on either ship cuts its tow (TOW_CUT "tx"). Automatic cuts (on_ship_changed, called
##   by DamageController.strike / destroy, BoardingController.capture / retake and
##   MapController.ground): TowRules.broken_reason ("destroyed", "struck", "aground", "taken").
##
## Dice order (game_state.dice): STATUS_ADJUSTMENT, before the grapple prompt, one d10 per tow
## attempt made, towers by ship id (no die for a lapsed order or a pair_error). V.B rolls nothing.


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
			# A TX begun this g-t made its own cut in V.B: it completes rather than being cancelled.
			if ship.tow_partner() == "" and int(task.get("started_turn", -1)) != _current_turn():
				return "no tow"
	return ""


# --- the tow step (spec §4, §6) ---

## The tow attempts (spec §4, 12.A.4), at the start of STATUS_ADJUSTMENT before the grapple prompt.
func resolve_tow_attempts(phase: int) -> void:
	if not is_server:
		push_error("TowController: Cannot resolve tow attempts on client")
		return
	for tower_id in _sorted_ids():
		var tower: ShipState = game_state.get_ship(tower_id)
		var parsed := TowRules.parse_order(tower.tow_order())
		if str(parsed["kind"]) != "take":
			continue
		var towed_id := str(parsed["target"])
		var towed: ShipState = game_state.get_ship(towed_id)
		var lapsed := TowRules.take_target_error(tower, towed)
		if lapsed != "":
			# The standing order can never be carried out: it lapses (controller ruling).
			game_state.ship_controller.set_crew_orders(tower_id, {"tow": ""})
			game_state.turn_log.add(PhaseEvents.Type.TOW_BEGUN, phase, tower_id,
				{"success": false, "lapsed": lapsed}, towed_id)
			Trace.trace_log("Tow", "order lapsed", {"tower": tower_id, "towed": towed_id, "reason": lapsed})
			continue
		var why := TowRules.pair_error(tower, towed)
		if why != "":
			Trace.trace_log("Tow", "attempt not made", {"tower": tower_id, "towed": towed_id, "reason": why})
			continue
		var chance: Dictionary = game_state.grappling_controller.grapple_chance(tower_id, towed_id, true)
		var roll: int = game_state.dice.d10()
		var total: int = roll + int(chance["modifier"])
		var needed: int = DataManager.combat_tables.grapple_success_max()
		var success: bool = total <= needed
		game_state.turn_log.add(PhaseEvents.Type.TOW_BEGUN, phase, tower_id, {"roll": roll,
			"modifier": chance["modifier"], "modifiers": chance["modifiers"], "total": total,
			"needed": needed, "success": success}, towed_id)
		Trace.trace_log("Tow", "%s -> %s: d10 %d %+d = %d, %s" % [tower_id, towed_id, roll,
			int(chance["modifier"]), total, "in tow" if success else "failed"])
		if success:
			begin(tower_id, towed_id, phase)


## The tow begins (12.A.4): ShipStateController.begin_tow, and the tower's tow order lapses.
func begin(tower_id: String, towed_id: String, phase: int) -> bool:
	if not is_server:
		push_error("TowController: Cannot begin a tow on client")
		return false
	if not game_state.ship_controller.begin_tow(tower_id, towed_id):
		return false
	game_state.ship_controller.set_crew_orders(tower_id, {"tow": ""})
	Trace.trace_log("Tow", "tow begun", {"tower": tower_id, "towed": towed_id, "phase": phase})
	return true


## Cuts the tow `ship_id` is in, from either end (12.A.9, spec §6); `by` the ship that cut it, if
## any. False when she is in no tow. Logs TOW_CUT.
func cut(ship_id: String, cause: String, phase: int, by: String = "") -> bool:
	if not is_server:
		push_error("TowController: Cannot cut a tow on client")
		return false
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.tow_partner() == "":
		return false
	var tower_id: String = ship_id if ship.is_towing() else ship.towed_by
	var towed_id: String = ship.towing_id if ship.is_towing() else ship_id
	game_state.turn_log.add(PhaseEvents.Type.TOW_CUT, phase, tower_id, {"cause": cause, "by": by}, towed_id)
	Trace.trace_log("Tow", "tow cut", {"tower": tower_id, "towed": towed_id, "cause": cause, "by": by})
	return game_state.ship_controller.cut_tow(ship_id)


## SoP V.B (spec §6): a live TX begun this g-t cuts that ship's tow. Ships on the map by ship id;
## each tow is cut once (once cut, her partner is in no tow).
func resolve_cuts(phase: int) -> void:
	if not is_server:
		push_error("TowController: Cannot resolve tow cuts on client")
		return
	for ship_id in _sorted_ids():
		var ship: ShipState = game_state.get_ship(ship_id)
		if not ship.is_on_map() or ship.tow_partner() == "":
			continue
		for task in ship.tasks_with("TX"):
			if int(task.get("started_turn", -1)) == _current_turn():
				cut(ship_id, "tx", phase, ship_id)
				break


## An automatic cut (spec §6): the tow `ship_id` is in parts when TowRules.broken_reason says so.
func on_ship_changed(ship_id: String, phase: int) -> void:
	if not is_server:
		push_error("TowController: Cannot check a tow on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.tow_partner() == "":
		return
	var tower: ShipState = ship if ship.is_towing() else game_state.get_ship(ship.towed_by)
	var towed: ShipState = game_state.get_ship(ship.towing_id) if ship.is_towing() else ship
	if tower == null or towed == null:
		return
	var reason := TowRules.broken_reason(tower, towed)
	if reason != "":
		cut(tower.ship_id, reason, phase)


func _sorted_ids() -> Array:
	var ids: Array = game_state.ships.keys()
	ids.sort()
	return ids


func _current_turn() -> int:
	var turn = game_state.get("current_turn") if game_state != null else null
	return int(turn) if turn != null else -1
