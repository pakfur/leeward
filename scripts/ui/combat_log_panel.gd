class_name CombatLogPanel
extends PanelContainer
## CombatLogPanel - Collapsible, scrollable log of the turn's events (read-only view of
## GameState.turn_log and earlier turns in GameState.turn_logs).
##
## Collapsed it is a one-line bar showing the latest event. Events are grouped under
## "Turn N — <Phase>" headings. A reveal limit lets the game controller show the current
## turn's events one at a time during combat playback.

signal skip_requested()

const EXPANDED_HEIGHT := 260.0
const BAR_HEIGHT := 42.0
const MAX_TURNS_SHOWN := 10  # most recent turns kept in the list

var _toggle_button: Button
var _latest_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _expanded: bool = false
var _reveal_limit: int = -1  # -1: show every event of the current turn
var _signature: String = ""
var _dirty: bool = false  # list is behind the logs (set while collapsed)
var _sections: Dictionary = {}  # turn -> {"box": VBoxContainer, "count": int, "last_phase": int, "log": PhaseLog}
var _earlier_label: Label
var _skip_label: Label
## The player's own collapse/expand only holds within the phase step in which they made it.
var _manual_key: String = ""
var _manual_expanded: bool = false

const SKIP_HINT := "Space or click to skip"


# --- Pure presentation helpers (unit tested) ---------------------------------

## Phases whose log heading is a plain word rather than the phase name.
const PHASE_HEADINGS := {
	TurnPhaseController.GamePhase.ENVIRONMENT: "Weather",
	TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION: "Movement",
}


## "Turn 3 — Combat Resolution", "Turn 3 — Movement"
static func phase_heading(turn: int, phase: int) -> String:
	if PHASE_HEADINGS.has(phase):
		return "Turn %d — %s" % [turn, PHASE_HEADINGS[phase]]
	var keys := TurnPhaseController.GamePhase.keys()
	var phase_name: String = keys[phase] if phase >= 0 and phase < keys.size() else "Unknown"
	return "Turn %d — %s" % [turn, phase_name.replace("_", " ").capitalize()]


## Display entries for events [from_index, to_index) of a turn log: {"heading": bool, "text": String}.
## A heading entry precedes the first event and every event whose phase differs from the previous
## one (`last_phase` is the phase of the event before from_index, -1 for none).
static func entries(turn_log: PhaseEvents.PhaseLog, from_index: int, to_index: int,
		last_phase: int, ship_names: Dictionary) -> Array:
	var result: Array = []
	if turn_log == null:
		return result
	var stop := mini(to_index, turn_log.events.size())
	for i in range(maxi(from_index, 0), stop):
		var ev := turn_log.events[i]
		if ev.phase != last_phase:
			result.append({"heading": true, "text": phase_heading(turn_log.turn, ev.phase)})
			last_phase = ev.phase
		result.append({"heading": false, "text": ev.to_text(ship_names)})
	return result


## What the list must do to match the logs. `built` and `available` map turn -> number of events
## rendered / currently showable. Returns {"window": turns to show (most recent max_turns, ascending),
## "drop": built turns outside the window, "append": {turn: number of new events},
## "truncated": whether older turns were left out}.
static func plan_update(built: Dictionary, available: Dictionary, max_turns: int = MAX_TURNS_SHOWN) -> Dictionary:
	var turns := available.keys()
	turns.sort()
	var window: Array = turns.slice(maxi(turns.size() - max_turns, 0))
	var drop: Array = []
	for turn in built.keys():
		if not window.has(turn):
			drop.append(turn)
	drop.sort()
	var append := {}
	for turn in window:
		var extra: int = available[turn] - built.get(turn, 0)
		if extra > 0:
			append[turn] = extra
	return {"window": window, "drop": drop, "append": append, "truncated": turns.size() > window.size()}


## Identifies one phase step ("turn:phase:combat step"); a manual toggle is remembered only
## while this key stays the same.
static func phase_key(turn: int, phase: int, combat_step: int) -> String:
	return "%d:%d:%d" % [turn, phase, combat_step]


## Whether the log should be expanded when the game asks for `auto_value`: the player's manual
## choice wins only if it was made in the current phase step.
static func choose_expanded(auto_value: bool, manual_key: String, current_key: String,
		manual_value: bool) -> bool:
	if manual_key != "" and manual_key == current_key:
		return manual_value
	return auto_value


## The list is only rebuilt while visible; otherwise it is just marked dirty.
static func needs_build(expanded: bool, dirty: bool) -> bool:
	return expanded and dirty


## The events the combat playback reveals one at a time: everything logged in COMBAT_RESOLUTION.
static func playback_events(turn_log: PhaseEvents.PhaseLog) -> Array[PhaseEvents.PhaseEvent]:
	var result: Array[PhaseEvents.PhaseEvent] = []
	if turn_log == null:
		return result
	for ev in turn_log.events:
		if ev.phase == TurnPhaseController.GamePhase.COMBAT_RESOLUTION:
			result.append(ev)
	return result


## Damage and strikes change what ships look like, so the views are re-synced after them.
static func syncs_views(event: PhaseEvents.PhaseEvent) -> bool:
	return event.type == PhaseEvents.Type.DAMAGE or event.type == PhaseEvents.Type.STRIKE


## ship_id -> "<name> (yours)" / "<name> (enemy)". The suffix is always added so ships that
## share a type name (scenarios do not name ships individually) stay distinguishable in the log.
static func log_names(ships: Array) -> Dictionary:
	var names := {}
	for ship in ships:
		names[ship.ship_id] = "%s (%s)" % [ship.ship_name, "yours" if ship.player_id == 0 else "enemy"]
	return names


## Text of the most recent visible event, for the collapsed bar.
static func latest_line(turn_log: PhaseEvents.PhaseLog, ship_names: Dictionary, limit: int = -1) -> String:
	if turn_log == null:
		return "No events yet"
	var shown: int = turn_log.events.size() if limit < 0 else mini(limit, turn_log.events.size())
	if shown == 0:
		return "No events yet"
	return turn_log.events[shown - 1].to_text(ship_names)


# --- Panel -------------------------------------------------------------------

func _ready() -> void:
	name = "CombatLogPanel"
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Bottom strip between the context panel (left) and the ship status panel (right).
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 480.0  # clear of the context panel (24% of 1920)
	offset_right = -480.0  # clear of the ship status panel
	offset_bottom = -10.0
	_apply_height()

	var box := VBoxContainer.new()
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_toggle_button = Button.new()
	_toggle_button.text = "Log ▲"
	_toggle_button.custom_minimum_size = Vector2(80, 0)
	_toggle_button.focus_mode = Control.FOCUS_NONE  # keep Space/Enter free for skipping playback
	_toggle_button.pressed.connect(_on_toggle_pressed)
	header.add_child(_toggle_button)
	_latest_label = Label.new()
	_latest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_latest_label.clip_text = true
	_latest_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_latest_label)
	_skip_label = Label.new()
	_skip_label.name = "SkipHint"
	_skip_label.text = SKIP_HINT
	_skip_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_skip_label.visible = false
	header.add_child(_skip_label)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, EXPANDED_HEIGHT - BAR_HEIGHT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.visible = false
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS  # clicks reach the panel (skip playback)
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_earlier_label = _line_label("Earlier turns not shown")
	_earlier_label.visible = false
	_list.add_child(_earlier_label)

	GameState.phase_changed.connect(_on_state_event)
	GameState.turn_changed.connect(_on_state_event)
	if GameState.phase_controller:
		GameState.phase_controller.combat_log_ready.connect(_on_state_event)
	refresh()


func _process(_delta: float) -> void:
	# Events are appended by server controllers without a signal; catch any change cheaply.
	if _signature_now() != _signature:
		refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		skip_requested.emit()


func is_expanded() -> bool:
	return _expanded


func set_expanded(expanded: bool) -> void:
	_expanded = expanded
	if _scroll:
		_scroll.visible = expanded
		_toggle_button.text = "Log ▼" if expanded else "Log ▲"
		_apply_height()
		if expanded:
			if needs_build(true, _dirty):
				_update_list(_logs_by_turn())
			_scroll_to_end()


func _apply_height() -> void:
	offset_top = offset_bottom - (EXPANDED_HEIGHT if _expanded else BAR_HEIGHT)


func toggle() -> void:
	set_expanded(not _expanded)


## The game's wish for this phase (expand for playback / review, collapse for planning and fire
## orders). Ignored when the player toggled the log by hand earlier in this same phase step.
func auto_expand(expanded: bool) -> void:
	set_expanded(choose_expanded(expanded, _manual_key, _current_key(), _manual_expanded))


## Show or hide the "Space or click to skip" cue in the header bar (combat playback).
func set_skip_hint(on: bool) -> void:
	if _skip_label:
		_skip_label.visible = on


func is_skip_hint_visible() -> bool:
	return _skip_label != null and _skip_label.visible


func _on_toggle_pressed() -> void:
	toggle()
	_manual_key = _current_key()
	_manual_expanded = _expanded


func _current_key() -> String:
	var pc = GameState.phase_controller
	if pc == null:
		return ""
	return phase_key(pc.current_turn, pc.current_phase, pc.combat_step)


## Show only the first `limit` events of the current turn's log (-1 shows all).
func set_reveal_limit(limit: int) -> void:
	_reveal_limit = limit
	refresh()


func clear_reveal_limit() -> void:
	set_reveal_limit(-1)


func refresh() -> void:
	if _list == null:
		return
	_signature = _signature_now()
	var by_turn := _logs_by_turn()
	_update_latest_label(by_turn)
	# "Earlier turns not shown" only when turns of this game fall outside the list's window.
	_earlier_label.visible = by_turn.size() > MAX_TURNS_SHOWN
	_dirty = true
	if needs_build(_expanded, _dirty):
		_update_list(by_turn)


## Bring the list up to date: build new turns, append new lines, drop turns that left the window.
func _update_list(by_turn: Dictionary) -> void:
	_dirty = false
	var names := _ship_names()
	var available := {}
	for turn in by_turn.keys():
		var turn_log: PhaseEvents.PhaseLog = by_turn[turn]
		var shown: int = turn_log.events.size()
		if turn_log == GameState.turn_log and _reveal_limit >= 0:
			shown = mini(_reveal_limit, shown)
		available[turn] = shown
		var section: Dictionary = _sections.get(turn, {})
		# A different log object (new game) or fewer visible events than rendered: rebuild that section.
		if not section.is_empty() and (section["log"] != turn_log or section["count"] > shown):
			_remove_section(turn)
	# Sections for turns the logs no longer contain (new game) go too.
	for turn in _sections.keys():
		if not by_turn.has(turn):
			_remove_section(turn)

	var built := {}
	for turn in _sections.keys():
		built[turn] = _sections[turn]["count"]
	var plan := plan_update(built, available)
	for turn in plan["drop"]:
		_remove_section(turn)
	_earlier_label.visible = plan["truncated"]
	for turn in plan["window"]:
		if not _sections.has(turn):
			var box := VBoxContainer.new()
			_list.add_child(box)
			_sections[turn] = {"box": box, "count": 0, "last_phase": -1, "log": by_turn[turn]}
		var extra: int = plan["append"].get(turn, 0)
		if extra > 0:
			_append_events(_sections[turn], by_turn[turn], extra, names)
	if _expanded:
		_scroll_to_end()


func _append_events(section: Dictionary, turn_log: PhaseEvents.PhaseLog, extra: int, names: Dictionary) -> void:
	var from_index: int = section["count"]
	var to_index := from_index + extra
	for entry in entries(turn_log, from_index, to_index, section["last_phase"], names):
		section["box"].add_child(_heading_label(entry["text"]) if entry["heading"] else _line_label(entry["text"]))
	section["count"] = to_index
	section["last_phase"] = turn_log.events[to_index - 1].phase


func _remove_section(turn: int) -> void:
	var section: Dictionary = _sections[turn]
	section["box"].queue_free()
	_sections.erase(turn)


func _update_latest_label(by_turn: Dictionary) -> void:
	# Latest event overall: a fresh turn's log is empty, so fall back to the previous turn's.
	var names := _ship_names()
	var turns := by_turn.keys()
	turns.sort()
	_latest_label.text = "No events yet"
	for i in range(turns.size() - 1, -1, -1):
		var turn_log: PhaseEvents.PhaseLog = by_turn[turns[i]]
		var limit: int = _reveal_limit if turn_log == GameState.turn_log else -1
		if turn_log.events.size() > 0 and limit != 0:
			_latest_label.text = latest_line(turn_log, names, limit)
			break


func _logs_by_turn() -> Dictionary:
	return current_game_logs(GameState.turn_logs, GameState.turn_log)


## turn -> log for the game being played: the finished turns before the current one, then the
## current turn's log. Logs numbered after the current turn are left over from an earlier game
## (the panel can be built before the new game replaces them) and are never shown.
static func current_game_logs(turn_logs: Dictionary, current: PhaseEvents.PhaseLog) -> Dictionary:
	var by_turn: Dictionary = {}
	var current_turn: int = current.turn if current else 1 << 30
	for turn in turn_logs.keys():
		if turn < current_turn:
			by_turn[turn] = turn_logs[turn]
	if current:
		by_turn[current.turn] = current
	return by_turn


func _signature_now() -> String:
	var count := GameState.turn_log.events.size() if GameState.turn_log else 0
	var turn := GameState.turn_log.turn if GameState.turn_log else 0
	var id := GameState.turn_log.get_instance_id() if GameState.turn_log else 0
	return "%d:%d:%d:%d" % [turn, count, GameState.turn_logs.size(), id]


func _ship_names() -> Dictionary:
	return log_names(GameState.get_all_ships())


func _heading_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	return label


func _line_label(text: String) -> Label:
	var label := Label.new()
	label.text = "  " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


func _on_state_event(_arg = null) -> void:
	refresh()


func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
