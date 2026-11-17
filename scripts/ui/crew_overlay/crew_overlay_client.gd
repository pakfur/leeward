class_name CrewOverlayClient
extends RefCounted
## CrewOverlayClient - the crew overlay's client side (crew-tasks spec §4): which ship is shown,
## which deck is large, which counter is picked up, and the requests the player makes. Shared by
## the overlay (map area) and the planning panel's crew block (Guns readout, DAMAGE, roster).
##
## View code. It reads state through read-only queries (CrewTaskController.current_plan,
## CrewRules) and changes crew plots only through the server's request methods, which take the
## player id and return "" or the reason: TurnPhaseController.player_plot_crew and
## player_set_crew_auto. It never writes a ShipState field or calls a controller mutator.

signal changed()
## kind: "bad" (refusal, fades), "warn" (needs an answer: actions), "clear".
signal message(text: String, kind: String, actions: Array)
signal open_changed(is_open: bool)

var game_state: Node = null
var player_id: int = 0
var ship_id: String = ""
var is_open: bool = false
var deck: String = "upper"
## The picked-up counter (click-then-click), or -1.
var selected: int = -1
## {section, station} awaiting the 4.A.3 progress-loss answer.
var pending: Dictionary = {}


func _init(p_game_state: Node, p_player_id: int = 0) -> void:
	game_state = p_game_state
	player_id = p_player_id


# --- Reading ---

func ship() -> ShipState:
	return game_state.get_ship(ship_id) if game_state != null and ship_id != "" else null


func ctx() -> Dictionary:
	var s := ship()
	return CrewRules.context(game_state, s) if s != null else {}


## The ship's crew plan as the server would store it (normalized, read-only query).
func plan() -> Dictionary:
	var s := ship()
	if s == null or game_state.crew_task_controller == null:
		return {"assignments": {}, "orders": {"sail_target": ""}, "auto": [], "warnings": []}
	return game_state.crew_task_controller.current_plan(ship_id)


func stations() -> Array[Dictionary]:
	var s := ship()
	if s == null:
		return []
	return CrewRules.stations(s, plan(), ctx())


func station(id: String) -> Dictionary:
	for st in stations():
		if st["id"] == id:
			return st
	return {}


## The station the section sits on in the current plan.
func station_of(section: int) -> String:
	return CrewRules.station_of(section, plan().get("assignments", {}).get(section, {}))


func is_submitted() -> bool:
	var pc = game_state.phase_controller
	return pc != null and pc.is_player_ready(player_id)


func phase() -> int:
	return game_state.phase_controller.current_phase if game_state.phase_controller else -1


## "" when the player may change this ship's crew now, else why not (header note).
func read_only_note() -> String:
	var s := ship()
	if s == null:
		return "No ship selected."
	return CrewOverlayText.read_only_note(phase(), s, game_state.commands(player_id, s.ship_id), is_submitted())


func editable() -> bool:
	return read_only_note() == ""


## Why `section` cannot go to `station_id`, or "".
func refusal(section: int, station_id: String) -> String:
	var s := ship()
	if s == null:
		return "No ship selected."
	var note := read_only_note()
	if note != "":
		return note
	var st := station(station_id)
	if st.is_empty():
		return "That station is not available now."
	if str(st.get("accepts", "")) == "none":
		return CrewRules.refusal(s, plan(), ctx(), section, CrewRules.STATION_REORGANIZING)
	if str(st.get("disabled_reason", "")) != "":
		return st["disabled_reason"]
	return CrewRules.refusal(s, plan(), ctx(), section, station_id)


## "valid" / "invalid" / "" (nothing lifted, or the section's own station) for station highlights.
func mark_for(station_id: String, section: int) -> String:
	if section < 0 or station_of(section) == station_id:
		return ""
	return "invalid" if refusal(section, station_id) != "" else "valid"


## State changed elsewhere (phase, movement plot, sail order): redraw.
func refresh() -> void:
	changed.emit()


# --- Opening ---

func open_for(p_ship_id: String) -> void:
	var s: ShipState = game_state.get_ship(p_ship_id)
	if s == null or not game_state.commands(player_id, s.ship_id):
		return  # enemy plots are secret
	if p_ship_id != ship_id:
		deck = "upper"
		selected = -1
		pending = {}
	ship_id = p_ship_id
	if not is_open:
		is_open = true
		open_changed.emit(true)
	changed.emit()


func close() -> void:
	selected = -1
	pending = {}
	if is_open:
		is_open = false
		open_changed.emit(false)
		message.emit("", "clear", [])
	changed.emit()


## Selecting another ship while open switches the overlay to it.
func follow_ship(p_ship_id: String) -> void:
	var s: ShipState = game_state.get_ship(p_ship_id) if p_ship_id != "" else null
	if s == null or not game_state.commands(player_id, s.ship_id):
		return
	if is_open:
		open_for(p_ship_id)
	else:
		ship_id = p_ship_id
		changed.emit()


func set_deck(deck_id: String) -> void:
	deck = deck_id
	changed.emit()


func pick(section: int) -> void:
	selected = -1 if selected == section else section
	changed.emit()


func drop_pick() -> bool:
	if selected < 0:
		return false
	selected = -1
	changed.emit()
	return true


# --- Requests ---

## Moves `section` to `station_id` (drag, click-then-click, menu). Refusals and the 4.A.3 warning
## go to the message bar. Returns true when the server took the new plan.
func assign(section: int, station_id: String, confirmed: bool = false) -> bool:
	var s := ship()
	selected = -1
	if s == null or station_of(section) == station_id:
		changed.emit()
		return false
	var why := refusal(section, station_id)
	if why != "":
		var actions: Array = []
		if s.crew_auto and editable():
			actions = [{"label": "Turn off", "id": "turn_off_auto", "primary": true}, {"label": "OK", "id": "ok"}]
		message.emit(why, "bad", actions)
		changed.emit()
		return false
	var current := plan()
	if not confirmed:
		var warn := CrewRules.progress_warning(s, current, section, station_id)
		if warn != "":
			pending = {"section": section, "station": station_id}
			message.emit(warn, "warn", [{"label": "Move anyway", "id": "confirm_move", "primary": true},
				{"label": "Keep it there", "id": "cancel_move"}])
			changed.emit()
			return false
	var next := CrewRules.assign(s, current, ctx(), section, station_id)
	var ok := _send(next, "%s to %s" % [CrewOverlayText.section_name(section), station_id])
	if ok and s.is_readied(section) and station_id != CrewRules.STATION_BOARDERS:
		# 10.B.5: a readied section cannot simply leave the boarders.
		message.emit("%s stands down this turn and is free next turn (10.B.5)." % CrewOverlayText.section_name(section), "info", [])
	return ok


func confirm_pending() -> void:
	var p := pending
	pending = {}
	if not p.is_empty():
		assign(int(p["section"]), str(p["station"]), true)


func cancel_pending() -> void:
	pending = {}
	message.emit("", "clear", [])
	changed.emit()


## The sail change ordered from the Sails station's picker ("" withdraws it).
func set_sail_target(target: String) -> bool:
	var s := ship()
	if s == null:
		return false
	var next := CrewRules.with_sail_order(s, plan(), ctx(), target)
	return _send(next, "sail target %s" % target)


## The boarding order from the Boarders station's picker (boarding spec §4.2): "", "ready",
## "board:<ship_id>" or "stand_down". With Automatic on, rule A2b places the sections.
func set_boarding_order(order: String) -> bool:
	var s := ship()
	if s == null:
		return false
	return _send(BoardingRules.with_order(s, plan(), ctx(), order), "boarding order %s" % order)


## A readied counter on the Boarders station clicked under a "Board" order: it toggles between going
## away (BA) and staying ready (BR); a refusal quotes the rule (10.C.1, 10.B.2).
func toggle_away(section: int) -> bool:
	var s := ship()
	if s == null or not editable():
		return false
	if s.crew_auto:
		message.emit("Automatic crew is on: the marines and the lowest sailor section go. Turn it off to choose.", "bad",
			[{"label": "Turn off", "id": "turn_off_auto", "primary": true}, {"label": "OK", "id": "ok"}])
		return false
	var r := BoardingRules.toggle_away(s, plan(), ctx(), section)
	if str(r["error"]) != "":
		message.emit(str(r["error"]), "bad", [])
		changed.emit()
		return false
	return _send(r["plan"], "%s board toggle" % CrewOverlayText.section_name(section))


## Reset to defaults (spec §4.1): tasks in progress stay, everyone else at the default stations;
## the sail order stands.
func reset_defaults() -> bool:
	var s := ship()
	if s == null:
		return false
	var target := str(plan().get("orders", {}).get("sail_target", ""))
	var base := CrewRules.default_plan(s, ctx())
	return _send(CrewRules.with_sail_order(s, base, ctx(), target), "reset to defaults")


func set_automatic(on: bool) -> bool:
	if ship() == null:
		return false
	var reason: String = game_state.phase_controller.player_set_crew_auto(player_id, ship_id, on)
	Trace.trace_log("CrewOverlay", "Automatic crew %s for %s: %s" % ["on" if on else "off", ship_id,
		reason if reason != "" else "accepted"])
	if reason != "":
		message.emit(reason, "bad", [])
	else:
		message.emit("", "clear", [])
	changed.emit()
	return reason == ""


func _send(next: Dictionary, what: String) -> bool:
	var request := {"assignments": next.get("assignments", {}), "orders": next.get("orders", {"sail_target": ""})}
	var reason: String = game_state.phase_controller.player_plot_crew(player_id, ship_id, request)
	Trace.trace_log("CrewOverlay", "Crew plot %s (%s): %s" % [ship_id, what, reason if reason != "" else "accepted"])
	if reason != "":
		message.emit(reason, "bad", [])
	else:
		message.emit("", "clear", [])
	changed.emit()
	return reason == ""
