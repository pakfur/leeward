class_name RepairController
extends CrewTaskHandler
## RepairController - the RR, RH and RS crew tasks (Close Action 1997, 8.F, 9.B.2; crew-tasks spec
## §3.7). One instance is registered for all three codes (game_state.repair_controller).
##
## - 8.F.2 / ship log: one section each; RR 6 ± SK g-t's, RH 10 ± SK, RS 5 ± SK, recomputed from the
##   current crew quality every g-t (9.A.2).
## - 8.F.3: a repair may begin only once a box of that type is marked out (or the shrouds are
##   severed). Plotting comes before any damage in a g-t, so "missing at plot time" is "the g-t
##   after". 8.F.3a: RR only at FS, furled (NS) or dismasted. 8.F.3b: RH only if the ship moves
##   <= 4 MPs (turns included); the limit is checked after movement (after_movement_reason).
## - 8.F.4: one section per repair type; different types at once are fine. Failing to plot a
##   repair continuously, or being unable to (8.F.3), cancels its progress.
## - 8.F.5: completion adds one box to the section taking damage, or the next-lowest-numbered one
##   if that section is full (ShipStateController.repair_box). RS removes a shrouds severed effect.
## - 8.F.6: a dismasted ship hit in the rigging loses all RR progress (CrewTaskController.reset_progress,
##   called by DamageController); the g-t of the hit does not count.
## Struck and destroyed ships plot no repairs.

const CODE_RR := "RR"
const CODE_RH := "RH"
const CODE_RS := "RS"
## In the order rule A5 places them (spec §3.3).
const CODES: Array[String] = ["RS", "RR", "RH"]
## 8.F.3b: most MPs a ship may move in a g-t of hull repair (crew_tasks.json "RH" max_mp).
const DEFAULT_MAX_MP := 4
const SHROUDS := "shrouds_severed"
## Crew-task end reasons
const ENDED_MOVED := "moved more than 4 MPs"
const ENDED_NOTHING := "nothing left to repair"
## reset_progress reason (8.F.6)
const RESET_DISMASTED := "rigging hit while dismasted"


func _init(p_game_state: Node) -> void:
	super(p_game_state)


static func is_repair(code: String) -> bool:
	return CODES.has(code)


## 8.F.3b limit from crew_tasks.json.
static func max_mp() -> int:
	var row: Dictionary = DataManager.combat_tables.crew_task(CODE_RH)
	return int(row.get("max_mp", DEFAULT_MAX_MP))


## "" when the ship may plot repair `code` now, else the reason (quoting the rule). The 8.F.3b MP
## limit is not part of it (see mp_warning): it is checked against the movement actually made.
static func refusal(ship: ShipState, code: String) -> String:
	if ship.is_out_of_play():
		return "A struck ship makes no repairs."
	match code:
		CODE_RR:
			if ship.missing_boxes("rigging") <= 0:
				return "No rigging boxes are lost: nothing to repair (8.F.3)."
			var sail := ship.sail_state.to_upper()
			if not ship.is_dismasted() and sail != "FS" and sail != "NS":
				return "Rigging can be repaired only at fighting sail, furled or dismasted (8.F.3a). You carry %s." % sail
		CODE_RH:
			if ship.missing_boxes("hull") <= 0:
				return "No hull boxes are lost: nothing to repair (8.F.3)."
		CODE_RS:
			if not ship.has_critical(SHROUDS):
				return "The shrouds are not severed: nothing to repair (8.F.3)."
		_:
			return "Unknown repair %s" % code
	return ""


## The 8.F.3b warning for a hull repair when the movement plot already uses more than 4 MPs, or "".
static func mp_warning(code: String, ctx: Dictionary) -> String:
	if code != CODE_RH:
		return ""
	var mps := int(ctx.get("plotted_mps", 0))
	if mps <= max_mp():
		return ""
	return "Hull repair is lost if the ship moves more than %d MPs (8.F.3b): %d are plotted." % [max_mp(), mps]


# --- Handler ---

func prepare(ship: ShipState, candidate: Dictionary) -> String:
	var code := str(candidate.get("code", ""))
	var why := refusal(ship, code)
	if why != "":
		return why
	if (candidate.get("sections", []) as Array).size() != 1:
		return "one section per repair (8.F.4)"
	return ""


func cancel_reason(ship: ShipState, task: Dictionary) -> String:
	var reason := super(ship, task)
	if reason != "":
		return reason
	var code := str(task.get("code", ""))
	if code == CODE_RS and not ship.has_critical(SHROUDS):
		return ENDED_NOTHING
	if code == CODE_RR and ship.missing_boxes("rigging") <= 0:
		return ENDED_NOTHING
	if code == CODE_RH and ship.missing_boxes("hull") <= 0:
		return ENDED_NOTHING
	return after_movement_reason(ship, task)


## 8.F.3b: a hull repair ends when the ship moved more than 4 MPs this g-t.
func after_movement_reason(ship: ShipState, task: Dictionary) -> String:
	if str(task.get("code", "")) == CODE_RH and ship.mp_used_this_turn > max_mp():
		return ENDED_MOVED
	return ""


## 8.F.6: the g-t of a rigging hit on a dismasted ship does not count.
func counts_turn(_ship: ShipState, task: Dictionary) -> bool:
	return int(task.get("reset_turn", -1)) != _turn()


## 8.F.5: one box regained (RR, RH), or the oldest severed shrouds spliced (RS). Logs REPAIR.
func on_complete(ship: ShipState, task: Dictionary, phase: int) -> void:
	var sc: ShipStateController = game_state.ship_controller
	var code := str(task.get("code", ""))
	var data := {"code": code, "sections": (task.get("sections", []) as Array).duplicate()}
	match code:
		CODE_RR, CODE_RH:
			var kind := "rigging" if code == CODE_RR else "hull"
			data["kind"] = kind
			data["section"] = sc.repair_box(ship.ship_id, kind)
		CODE_RS:
			data["kind"] = "shrouds"
			var oldest := -1
			for effect in ship.critical_effects:
				if str(effect.get("id", "")) == SHROUDS and (oldest < 0 or int(effect["seq"]) < oldest):
					oldest = int(effect["seq"])
			if oldest >= 0:
				sc.remove_critical_effect(ship.ship_id, oldest)
	game_state.turn_log.add(PhaseEvents.Type.REPAIR, phase, ship.ship_id, data)
	Trace.trace_log("Repair", "%s completes %s" % [ship.ship_id, code], data)


func _turn() -> int:
	var turn = game_state.get("current_turn") if game_state != null else null
	return int(turn) if turn != null else 0
