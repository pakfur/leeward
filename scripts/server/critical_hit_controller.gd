class_name CriticalHitController
extends RefCounted
## CriticalHitController - Critical hits, Rigging Checks and Hull Checks (Close Action 1997,
## 7.D.7, 7.D.8a, 7.D.11, 7.D.12; Rigging and Hull Critical Hits tables, p.112-113).
##
## Gunfire: GunneryResolver calls hold(), applies the shot's hits, calls check_gunfire_crit()
## and then release(), which drains the check queue. DamageController queues a Rigging Check for
## every rigging section it empties and a Hull Check for hull sections 1-3 (any cause: gunfire,
## a critical hit's extra boxes, a collision); it drains the queue itself after apply_hits unless
## this controller is holding or already draining. The queue is FIFO, so checks caused by a
## check's own boxes are rolled after the checks already waiting (7.D.12 chaining).
##
## Rolls only through game_state.dice. Struck and destroyed ships roll no critical hits, checks or fixes.
## All mutations go through ShipStateController and DamageController.
##
## Critical context `ctx` (one per shot, shared by the checks the shot causes):
##   source_id: firing ship ("" outside gunfire), aim, ammo, rake ("", "bow", "stern"),
##   engaged_side: ShipState.PORT / STARBOARD, SIDE_BOTH (stern rake, 7.E.5b) or SIDE_RANDOM
##     (bow rake, or the firer on the target's centre line; a d6 is rolled the first time a
##     result needs the side, 1-3 port, and the answer is kept in ctx),
##   dismasted_at_start: the target was dismasted before this combat phase,
##   target_id, fgn, d6: the shot (check_gunfire_crit only).
## An empty ctx (collisions) means: no firer, side rolled if needed, not dismasted at start.

const SIDE_BOTH := 2
const SIDE_RANDOM := -2

const SOURCE_GUNFIRE := "gunfire"
const SOURCE_RIGGING_CHECK := "rigging_check"
const SOURCE_HULL_CHECK := "hull_check"
const SOURCE_HULL_7 := "hull_7"

const TABLE_RIGGING := "rigging"
const TABLE_HULL := "hull"

## CRITICAL_HIT "ignored" reasons
const IGNORED_DISMASTED := "dismasted"
const IGNORED_DISMASTED_BEFORE := "dismasted before this combat phase"
const IGNORED_DISMANTLING := "dismantling shot"
const IGNORED_SHEETS_THIS_TURN := "sheets already cut this turn"
const IGNORED_RUDDER_DESTROYED := "rudder already destroyed"
const IGNORED_RUDDER_JAMMED := "rudder already jammed"

## 8.D.5: lasting effects fixed by a roll on the Unfouling table in STATUS_ADJUSTMENT.
## signal_halyards_cut is recorded and fixed (rigging #3; a dismasted ship still rolls), but there is
## no signalling yet for it to block (crew-tasks spec §0.2, critical-hits spec Q16).
const FIXABLE_IDS: Array[String] = ["broadside_obscured", "braces_cut", "lines_jammed", "rudder_jammed",
	"signal_halyards_cut"]

## Hull #12: scenario years up to this one take the explosion DRM (spec Q14)
const EARLY_YEAR := 1783
## DESTROYED reason
const REASON_EXPLOSION := "explosion"

## CRITICAL_ENDED reasons
const ENDED_EXPIRED := "expired"
const ENDED_DISMASTED := "dismasted"

## Crew-task cancellation reason for a section disorganized by hull #4.
const CANCEL_DISORGANIZED := "crew disorganized"

## CRITICAL_HIT "note" values (deferred or unimplemented parts of a result)
const NOTE_NOT_SIMULATED := "not_simulated"
const NOTE_FIRE_NOT_SIMULATED := "fire_not_simulated"
const NOTE_NOT_IMPLEMENTED := "not_implemented"
const NOTE_SINKING_NOT_SIMULATED := "sinking_not_simulated"

var is_server: bool = true
var game_state: Node = null

var _queue: Array[Dictionary] = []
var _hold: int = 0
var _draining: bool = false


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## Critical context for a shot (see the class doc). Positions are those the shot was fired from.
func shot_context(order: GunneryTypes.FireOrder, rake: String, target_dismasted: bool) -> Dictionary:
	var engaged := SIDE_RANDOM
	if rake == "stern":
		engaged = SIDE_BOTH
	elif rake == "":
		# Spec Q12: the side the firer lies on by relative bearing; d6 on the centre line.
		var target: ShipState = game_state.get_ship(order.target_id)
		var firer: ShipState = game_state.get_ship(order.ship_id)
		if target != null and firer != null:
			var side: int = game_state.fire_geometry.relative_side(target.hex_position, target.facing,
					firer.occupied_hexes())
			if side != -1:
				engaged = side
	return {
		"source_id": order.ship_id,
		"target_id": order.target_id,
		"aim": order.aim,
		"ammo": order.ammo,
		"rake": rake,
		"engaged_side": engaged,
		"dismasted_at_start": target_dismasted,
	}


## While held, DamageController queues checks but does not drain them.
func hold() -> void:
	_hold += 1


func release(phase: int) -> void:
	_hold = maxi(_hold - 1, 0)
	if _hold == 0:
		drain(phase)


func is_holding() -> bool:
	return _hold > 0 or _draining


func pending_checks() -> int:
	return _queue.size()


## 7.D.11: a natural 6 on the gunnery d6 (ctx.d6) rolls another d6; d6 + the target's CH mod
## <= the CH# of the FGN row is a critical hit, and 2d6 is rolled on the Hull (aim low) or
## Rigging (aim high) Crit column. Dismantling shot aimed low causes no hull crits (7.C.12b), so
## no roll is made. Returns true on a critical hit.
func check_gunfire_crit(ctx: Dictionary, phase: int) -> bool:
	if not is_server:
		push_error("CriticalHitController: Cannot roll critical hits on client")
		return false
	var ship_id := str(ctx.get("target_id", ""))
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.is_out_of_play():
		return false
	var fgn := int(ctx.get("fgn", 0))
	if int(ctx.get("d6", 0)) != 6 or fgn < 1:
		return false
	var aim_low: bool = ctx.get("aim", "") == GunneryTypes.AIM_LOW
	if aim_low and ctx.get("ammo", "") == GunneryTypes.AMMO_DISMANTLING:
		return false
	var ch_number: int = DataManager.combat_tables.critical_hit_number(fgn)
	var ch_mod: int = ship.ship.ch_modifier if ship.ship else 0
	var roll: int = game_state.dice.d6()
	var hit := roll + ch_mod <= ch_number
	game_state.turn_log.add(PhaseEvents.Type.CRITICAL_ROLL, phase, ship_id, {
		"d6": roll, "ch_mod": ch_mod, "ch_number": ch_number, "hit": hit,
	}, str(ctx.get("source_id", "")))
	if not hit:
		return false
	var crit_roll: int = game_state.dice.two_d6()
	if aim_low:
		var row: Dictionary = DataManager.combat_tables.hull_crit(crit_roll)
		_resolve_hull(ship_id, row, _log_crit(ship_id, SOURCE_GUNFIRE, TABLE_HULL, crit_roll, row, ctx, phase),
				ctx, phase, true)
	else:
		var row: Dictionary = DataManager.combat_tables.rigging_crit(crit_roll)
		_resolve_rigging(ship_id, row,
				_log_crit(ship_id, SOURCE_GUNFIRE, TABLE_RIGGING, crit_roll, row, ctx, phase), ctx, phase, true)
	return true


## 7.D.7: a rigging section was completely marked out.
func queue_rigging_check(ship_id: String, ctx: Dictionary = {}, section: int = -1) -> void:
	_enqueue(ship_id, TABLE_RIGGING, ctx, section)


## 7.D.8a: hull section 1-3 was completely marked out (section 4 strikes the ship; spec Q5).
func queue_hull_check(ship_id: String, ctx: Dictionary = {}, section: int = -1) -> void:
	_enqueue(ship_id, TABLE_HULL, ctx, section)


## Rolls the queued checks in order until the queue is empty, including the checks they cause.
func drain(phase: int) -> void:
	if not is_server:
		push_error("CriticalHitController: Cannot roll checks on client")
		return
	if _draining:
		return
	_draining = true
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		var ship_id: String = item["ship_id"]
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.is_out_of_play():
			continue
		var ctx: Dictionary = item["ctx"]
		var roll: int = game_state.dice.d6()
		if item["table"] == TABLE_RIGGING:
			var row: Dictionary = DataManager.combat_tables.rigging_check(roll)
			var data := _log_crit(ship_id, SOURCE_RIGGING_CHECK, TABLE_RIGGING, roll, row, ctx, phase)
			data["section"] = item["section"]
			_resolve_rigging(ship_id, row, data, ctx, phase, false)
		else:
			var row: Dictionary = DataManager.combat_tables.hull_check(roll)
			var data := _log_crit(ship_id, SOURCE_HULL_CHECK, TABLE_HULL, roll, row, ctx, phase)
			data["section"] = item["section"]
			_resolve_hull(ship_id, row, data, ctx, phase, false)
	_draining = false


## STATUS_ADJUSTMENT (Unfouling & Fixing sub-phase, 8.D.5). Dice order: ships by ship_id, then
## each ship's effects by seq; every FIXABLE_IDS entry rolls d10, fixed when
## d10 + SK mod <= the Unfouling number for that entry's attempt (1: <= 2, 2: <= 3, 3+: <= 4).
## Each obscured side is its own entry and is fixed separately. Struck ships do not roll.
## Then sheets cut whose expires_after_turn has come ends (inflicted on turn T, it limits
## turn T+1's movement and is removed in T+1's STATUS_ADJUSTMENT), with no roll.
func resolve_fixes(phase: int) -> void:
	if not is_server:
		push_error("CriticalHitController: Cannot resolve fixes on client")
		return
	var tables: CombatTables = DataManager.combat_tables
	var sc: ShipStateController = game_state.ship_controller
	var ids: Array = game_state.ships.keys()
	ids.sort()
	for ship_id: String in ids:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.critical_effects.is_empty():
			continue
		var effects: Array[Dictionary] = ship.critical_effects.duplicate(true)
		effects.sort_custom(func(x, y): return int(x["seq"]) < int(y["seq"]))
		for effect in effects:
			var id := str(effect.get("id", ""))
			var seq := int(effect["seq"])
			var side := int(effect.get("side", -1))
			if FIXABLE_IDS.has(id):
				if ship.is_out_of_play():
					continue
				var attempt := int(effect.get("attempts", 0)) + 1
				var roll: int = game_state.dice.d10()
				# 8.D.5 rolls on the Unfouling table: ± SK, +1 when the marines are busy.
				var modifier: int = tables.skill_modifier(ship.crew_quality)
				if ship.marines_busy():
					modifier += tables.marines_unavailable_modifier()
				var needed: int = tables.unfouling_success_max(attempt)
				var success := roll + modifier <= needed
				if success:
					sc.remove_critical_effect(ship_id, seq)
				else:
					sc.update_critical_effect(ship_id, seq, {"attempts": attempt})
				game_state.turn_log.add(PhaseEvents.Type.CRITICAL_FIXED, phase, ship_id, {
					"result_id": id, "side": side, "roll": roll, "modifier": modifier,
					"needed": needed, "attempt": attempt, "success": success,
				})
			elif id == "sheets_cut":
				var expires := int(effect.get("expires_after_turn", -1))
				if expires >= 0 and expires <= game_state.current_turn:
					end_effect(ship_id, seq, ENDED_EXPIRED, phase)


## Removes a lasting effect that ends without a roll and logs CRITICAL_ENDED with `reason`
## (ENDED_EXPIRED, ENDED_DISMASTED).
func end_effect(ship_id: String, seq: int, reason: String, phase: int) -> void:
	if not is_server:
		push_error("CriticalHitController: Cannot end critical effects on client")
		return
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return
	for effect in ship.critical_effects:
		if int(effect.get("seq", -1)) == seq:
			var data := {"result_id": str(effect.get("id", "")), "side": int(effect.get("side", -1)),
					"reason": reason}
			game_state.ship_controller.remove_critical_effect(ship_id, seq)
			game_state.turn_log.add(PhaseEvents.Type.CRITICAL_ENDED, phase, ship_id, data)
			return


## Rigging #5 note: a dismasted ship's jammed lines are fixed automatically.
func clear_lines_jammed_on_dismasting(ship_id: String, phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or not ship.is_dismasted():
		return
	for effect in ship.critical_effects.duplicate(true):
		if effect.get("id") == "lines_jammed":
			end_effect(ship_id, int(effect["seq"]), ENDED_DISMASTED, phase)


func _enqueue(ship_id: String, table: String, ctx: Dictionary, section: int) -> void:
	if not is_server:
		push_error("CriticalHitController: Cannot queue checks on client")
		return
	_queue.append({
		"ship_id": ship_id,
		"table": table,
		"section": section,
		"ctx": ctx if not ctx.is_empty() else {},
	})


func _log_crit(ship_id: String, source: String, table: String, roll: int, row: Dictionary,
		ctx: Dictionary, phase: int) -> Dictionary:
	var data := {
		"source": source,
		"table": table,
		"roll": roll,
		"crit": int(row.get("crit", -1)),
		"result_id": str(row.get("id", "")),
		"side": -1,
		"sub_rolls": [],
	}
	game_state.turn_log.add(PhaseEvents.Type.CRITICAL_HIT, phase, ship_id, data,
			str(ctx.get("source_id", "")))
	return data


# --- Rigging Critical Hits (p.112) ---

## `own_crit`: the shot's own 2d6 crit, the only result [D] filters (spec Q4).
func _resolve_rigging(ship_id: String, row: Dictionary, data: Dictionary, ctx: Dictionary,
		phase: int, own_crit: bool) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or row.is_empty():
		return
	var flags: Array = row.get("flags", [])
	if ship.is_dismasted():
		# Chart notes: no rigging crits on a ship dismasted before this combat phase; diamond
		# results are ignored if it became dismasted in this one.
		if ctx.get("dismasted_at_start", false):
			data["ignored"] = IGNORED_DISMASTED_BEFORE
			return
		if flags.has("diamond"):
			data["ignored"] = IGNORED_DISMASTED
			return
	if own_crit and flags.has("D") and ctx.get("ammo", "") == GunneryTypes.AMMO_DISMANTLING:
		data["ignored"] = IGNORED_DISMANTLING
		return
	var sail := ship.sail_state.to_lower()
	var turn: int = game_state.current_turn
	var sc: ShipStateController = game_state.ship_controller
	match str(row.get("id", "")):
		"mast_may_fall":
			var d6: int = game_state.dice.d6()
			var drm: Dictionary = row.get("drm", {})
			var modifier := int(drm.get(sail, 0))
			modifier += int(drm.get("per_section_lost", 0)) * (ship.rigging_current_hp.size() - ship.rigging_level())
			var ws: int = game_state.environment.wind_speed if game_state.environment else 0
			if ws == 4:
				modifier += int(drm.get("ws4", 0))
			elif ws <= 1:
				modifier += int(drm.get("ws_le_1", 0))
			var needed := int(row.get("fall_at", 8))
			data["sub_rolls"].append(d6)
			data["modifier"] = modifier
			data["needed"] = needed
			data["falls"] = d6 + modifier >= needed
			if data["falls"]:
				_cross_out_rigging(ship_id, ctx, phase)
		"signal_halyards_cut":
			# 1R at MS or PS; no new messages until fixed (8.D.5 roll). Signalling (ch. 11) is not
			# implemented, so the entry blocks nothing yet.
			_rigging_boxes(ship_id, int(row.get("rigging", {}).get(sail, 0)), ctx, phase)
			sc.add_critical_effect(ship_id, {"id": "signal_halyards_cut", "turn": turn})
		"braces_cut":
			sc.add_critical_effect(ship_id, {"id": "braces_cut", "turn": turn})
		"lines_jammed":
			sc.add_critical_effect(ship_id, {"id": "lines_jammed", "turn": turn})
			# 5.F.9c: a sail change in progress is abandoned at once.
			if game_state.sail_controller:
				game_state.sail_controller.cancel_change(ship_id, SailController.CANCEL_LINES_JAMMED, phase)
		"broadside_obscured":
			var d6: int = game_state.dice.d6()
			var side := ShipState.PORT if d6 <= int(row.get("port_max", 3)) else ShipState.STARBOARD
			data["sub_rolls"].append(d6)
			data["side"] = side
			_rigging_boxes(ship_id, int(row.get("rigging", {}).get(sail, 0)), ctx, phase)
			sc.add_critical_effect(ship_id, {"id": "broadside_obscured", "side": side, "turn": turn})
		"sheets_cut":
			for effect in ship.critical_effects:
				if effect.get("id") == "sheets_cut" and int(effect.get("turn", -1)) == turn:
					data["ignored"] = IGNORED_SHEETS_THIS_TURN
					return
			sc.add_critical_effect(ship_id, {"id": "sheets_cut", "turn": turn,
					"expires_after_turn": turn + int(row.get("turns", 1))})
		"leadership_casualties":
			_leadership(ship_id, row, data, ctx, phase)
		"shrouds_severed":
			_rigging_boxes(ship_id, int(row.get("rigging_all", 1)), ctx, phase)
			sc.add_critical_effect(ship_id, {"id": "shrouds_severed", "turn": turn})
		"yard_shot_away":
			_rigging_boxes(ship_id, int(row.get("rigging", {}).get(sail, 0)), ctx, phase)
			# Both broadsides -2 until fixed, each side separately: one obscured entry per side.
			data["side"] = SIDE_BOTH
			for side in [ShipState.PORT, ShipState.STARBOARD]:
				sc.add_critical_effect(ship_id, {"id": "broadside_obscured", "side": side, "turn": turn})
		"stays_cut":
			var d10: int = game_state.dice.d10()
			data["sub_rolls"].append(d10)
			data["speed"] = ship.speed
			data["falls"] = d10 <= ship.speed
			if data["falls"]:
				_cross_out_rigging(ship_id, ctx, phase)
				_note_crit_morale(ship_id, data, phase)
			_rigging_boxes(ship_id, int(row.get("extra_rigging", 1)), ctx, phase)
		"mast_falls_on_deck":
			_cross_out_rigging(ship_id, ctx, phase)
			var crew := int(row.get("crew_by_class", {}).get(str(_ship_class(ship)), 0))
			if crew > 0:
				game_state.damage_controller.apply_crew_boxes(ship_id, crew, true, phase,
						str(ctx.get("source_id", "")))
			_note_crit_morale(ship_id, data, phase)
		_:
			push_error("CriticalHitController: unknown rigging result '%s'" % row.get("id", ""))


# --- Hull Critical Hits (p.113) ---

func _resolve_hull(ship_id: String, row: Dictionary, data: Dictionary, ctx: Dictionary,
		phase: int, own_crit: bool) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or row.is_empty():
		return
	var flags: Array = row.get("flags", [])
	if own_crit and flags.has("D") and ctx.get("ammo", "") == GunneryTypes.AMMO_DISMANTLING:
		data["ignored"] = IGNORED_DISMANTLING
		return
	var sc: ShipStateController = game_state.ship_controller
	match str(row.get("id", "")):
		"rudder":
			if ctx.get("rake", "") == "bow":
				# 7.E.6 (spec Q13: bow rake only): one extra hull hit instead.
				data["converted"] = true
				_hull_boxes(ship_id, int(row.get("bow_hull", 1)), ctx, phase)
				return
			var d6: int = game_state.dice.d6()
			data["sub_rolls"].append(d6)
			if d6 <= int(row.get("destroyed_max", 3)):
				data["rudder"] = "destroyed"
				if ship.rudder_destroyed:
					data["ignored"] = IGNORED_RUDDER_DESTROYED
					return
				sc.set_rudder_destroyed(ship_id, true)
				for effect in ship.critical_effects.duplicate():
					if effect.get("id") == "rudder_jammed":
						sc.remove_critical_effect(ship_id, int(effect["seq"]))
			else:
				data["rudder"] = "jammed"
				if ship.rudder_destroyed:
					data["ignored"] = IGNORED_RUDDER_DESTROYED
					return
				if ship.has_critical("rudder_jammed"):
					data["ignored"] = IGNORED_RUDDER_JAMMED
					return
				# Jammed in the direction of the last step the ship executed (spec Q15): this g-t's
				# last step, else its previous move's; -1 (straight) when it has none.
				data["jam"] = ship.last_step_direction
				sc.add_critical_effect(ship_id, {"id": "rudder_jammed", "side": ship.last_step_direction,
						"turn": game_state.current_turn})
		"wheel_shot_away":
			sc.set_wheel_shot_away(ship_id, true)
		"crew_disorganized":
			var sailors := int(row.get("sailors_by_class", {}).get(str(_ship_class(ship)), 0))
			if sailors > 0:
				game_state.damage_controller.apply_crew_boxes(ship_id, sailors, false, phase,
						str(ctx.get("source_id", "")))
			_disorganize(ship_id, data, phase)
		"leadership_casualties":
			_leadership(ship_id, row, data, ctx, phase)
		"hull_structural_damage":
			_hull_boxes(ship_id, int(row.get("hull", 1)), ctx, phase)
		"rigging_damage":
			var roll: int = game_state.dice.two_d6()
			data["sub_rolls"].append(roll)
			var rigging_row: Dictionary = DataManager.combat_tables.rigging_crit(roll)
			_resolve_rigging(ship_id, rigging_row,
					_log_crit(ship_id, SOURCE_HULL_7, TABLE_RIGGING, roll, rigging_row, ctx, phase),
					ctx, phase, false)
		"guns_dismounted":
			_guns(ship_id, int(row.get("guns", 1)), data, ctx, phase)
		"minor_explosion":
			# Deferred (spec Q10): 1H and the guns; no fire roll.
			_hull_boxes(ship_id, int(row.get("hull", 1)), ctx, phase)
			_guns(ship_id, int(row.get("guns", 2)), data, ctx, phase)
			data["note"] = NOTE_FIRE_NOT_SIMULATED
		"waterline_damage":
			var needed := int(row.get("pumps_by_class", {}).get(str(_ship_class(ship)), 0))
			data["pumps"] = needed
			var source := str(ctx.get("source_id", ""))
			if ship.total_crew_boxes() < needed:
				# Not enough crew for the pumps: the ship strikes (sinking is not simulated).
				game_state.damage_controller.strike(ship_id, "waterline", phase)
				game_state.damage_controller.apply_crew_boxes(ship_id, ship.total_crew_boxes(), false,
						phase, source)
				data["note"] = NOTE_SINKING_NOT_SIMULATED
			elif needed > 0:
				game_state.damage_controller.apply_crew_boxes(ship_id, needed, false, phase, source)
		"afire_major_explosion":
			_afire_major_explosion(ship_id, row, data, ctx, phase)
		_:
			push_error("CriticalHitController: unknown hull result '%s'" % row.get("id", ""))


## Hull #12: afire (fires + 1; fire itself is not simulated, spec §3.3), 1H, guns dismounted on
## each broadside, an MC, then the explosion roll: 2d10 (0-18) + explosion_modifier() < the ship's
## class explodes and destroys the ship (spec Q2). Rolled even if the 1H made the ship strike.
## data gets "guns", side SIDE_BOTH and "explosion": {roll, modifier, total, needed, explodes}.
func _afire_major_explosion(ship_id: String, row: Dictionary, data: Dictionary, ctx: Dictionary,
		phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	var sc: ShipStateController = game_state.ship_controller
	var fires_before := ship.fires  # the "each existing fire" DRM counts fires before this one
	sc.add_fire(ship_id)
	game_state.turn_log.add(PhaseEvents.Type.FIRE_STARTED, phase, ship_id,
			{"fires": ship.fires, "result_id": str(row.get("id", ""))}, str(ctx.get("source_id", "")))
	_hull_boxes(ship_id, int(row.get("hull", 1)), ctx, phase)
	var guns := int(row.get("guns_both", 2))
	data["side"] = SIDE_BOTH
	data["guns"] = guns
	sc.add_guns_dismounted(ship_id, guns)
	game_state.turn_log.add(PhaseEvents.Type.GUNS_DISMOUNTED, phase, ship_id, {"amount": guns})
	_note_crit_morale(ship_id, data, phase)
	if ship.is_destroyed():
		return
	var roll: int = game_state.dice.two_d10()
	var modifier := explosion_modifier(ship, fires_before, row)
	var needed := _ship_class(ship)
	var explodes := roll + modifier < needed
	data["explosion"] = {"roll": roll, "modifier": modifier, "total": roll + modifier,
			"needed": needed, "explodes": explodes}
	if explodes:
		game_state.damage_controller.destroy(ship_id, REASON_EXPLOSION, phase)


## Hull #12 explosion DRM: crew quality (A +3 ... G -3), -2 per fire already burning
## (`fires_before`), -1 when the scenario has a `year` <= 1783 (spec Q14).
func explosion_modifier(ship: ShipState, fires_before: int, row: Dictionary = {}) -> int:
	if row.is_empty():
		row = DataManager.combat_tables.hull_crit(12)
	var drm: Dictionary = row.get("explode_drm", {})
	var modifier := int(drm.get(ship.crew_quality, 0)) + int(drm.get("per_fire", -2)) * fires_before
	var year: Variant = game_state.active_scenario.get("year")
	if (year is int or year is float) and int(year) <= EARLY_YEAR:
		modifier += int(drm.get("year_le_1783", -1))
	return modifier


# --- shared result parts ---

## Rigging #8 / Hull #5: one marine box (none for class 4; a sailor if no marines), and an MC.
## Hull #4: the highest-numbered sailor section with boxes that is not already disorganized ends
## its task (a sail change it shares ends for both sections, 5.F.9a) and must reorganize: a forced
## RO task of 5 g-t's ± SK, counted from the next g-t. With no such section only the box is lost.
func _disorganize(ship_id: String, data: Dictionary, phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	var ctc: CrewTaskController = game_state.get("crew_task_controller")
	if ship == null or ctc == null or ship.is_out_of_play():
		return
	for section in range(ShipState.SAILOR_SECTIONS - 1, -1, -1):
		if ship.section_alive(section) and not ship.is_disorganized(section):
			data["section"] = section
			ctc.cancel_section(ship_id, section, CANCEL_DISORGANIZED, phase)
			ctc.force_task(ship_id, [section], ReorganizeHandler.CODE,
				{"reason": ReorganizeHandler.REASON_DISORGANIZED}, phase)
			return
	data["section"] = -1


func _leadership(ship_id: String, row: Dictionary, data: Dictionary, ctx: Dictionary,
		phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	var marines := int(row.get("marines_by_class", {}).get(str(_ship_class(ship)), 0))
	if marines > 0:
		game_state.damage_controller.apply_crew_boxes(ship_id, marines, true, phase,
				str(ctx.get("source_id", "")))
	_note_crit_morale(ship_id, data, phase)


## Guns dismounted on the engaged broadside; both broadsides on a stern rake (7.E.5b).
func _guns(ship_id: String, amount: int, data: Dictionary, ctx: Dictionary, phase: int) -> void:
	var side := _engaged_side(ctx, data)
	data["side"] = side
	data["guns"] = amount
	if side == SIDE_BOTH:
		game_state.ship_controller.add_guns_dismounted(ship_id, amount)
		game_state.turn_log.add(PhaseEvents.Type.GUNS_DISMOUNTED, phase, ship_id, {"amount": amount})
	else:
		game_state.ship_controller.add_guns_dismounted(ship_id, amount, side)
		game_state.turn_log.add(PhaseEvents.Type.GUNS_DISMOUNTED, phase, ship_id,
				{"amount": amount, "side": side})


func _engaged_side(ctx: Dictionary, data: Dictionary) -> int:
	var side := int(ctx.get("engaged_side", SIDE_RANDOM))
	if side == SIDE_RANDOM:
		var d6: int = game_state.dice.d6()
		data["sub_rolls"].append(d6)
		data["side_roll"] = d6
		side = ShipState.PORT if d6 <= 3 else ShipState.STARBOARD
		ctx["engaged_side"] = side
	return side


## Crosses out the current rigging section (the lowest-numbered one with boxes left) by marking
## out its remaining boxes, so the section's Rigging Check, dismasting and MCs follow as usual.
func _cross_out_rigging(ship_id: String, ctx: Dictionary, phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	for hp in ship.rigging_current_hp:
		if hp > 0:
			_rigging_boxes(ship_id, hp, ctx, phase)
			return


func _rigging_boxes(ship_id: String, amount: int, ctx: Dictionary, phase: int) -> void:
	if amount > 0:
		game_state.damage_controller.apply_hits(ship_id, amount, 0, 0, "other", phase,
				str(ctx.get("source_id", "")), ctx, DamageController.CAUSE_CRITICAL)


func _hull_boxes(ship_id: String, amount: int, ctx: Dictionary, phase: int) -> void:
	if amount > 0:
		game_state.damage_controller.apply_hits(ship_id, 0, amount, 0, "other", phase,
				str(ctx.get("source_id", "")), ctx, DamageController.CAUSE_CRITICAL)


## 9.B.1e: an MC called for by a critical hit; each has its own trigger, so two in a turn
## are two MCs.
func _note_crit_morale(ship_id: String, data: Dictionary, phase: int) -> void:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.is_out_of_play():
		return
	var seq: int = game_state.ship_controller.next_critical_seq(ship_id)
	if seq < 0:
		return
	var trigger := "crit_%d" % seq
	if game_state.ship_controller.note_morale_check(ship_id, trigger):
		game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, ship_id,
				{"trigger": trigger, "count": 1})
		data["mc"] = true


func _ship_class(ship: ShipState) -> int:
	return ship.ship.ship_class if ship != null and ship.ship != null else 0
