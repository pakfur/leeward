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
const BAR_HEIGHT := 34.0

var _toggle_button: Button
var _latest_label: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _expanded: bool = false
var _reveal_limit: int = -1  # -1: show every event of the current turn
var _signature: String = ""


# --- Pure presentation helpers (unit tested) ---------------------------------

## "Turn 3 — Combat Resolution"
static func phase_heading(turn: int, phase: int) -> String:
	var keys := TurnPhaseController.GamePhase.keys()
	var phase_name: String = keys[phase] if phase >= 0 and phase < keys.size() else "Unknown"
	return "Turn %d — %s" % [turn, phase_name.replace("_", " ").capitalize()]


## Consecutive events of the same phase share a group: [{"heading": String, "lines": Array[String]}].
## `limit` (>= 0) shows only the first N events of the log.
static func group_events(turn_log: PhaseEvents.PhaseLog, ship_names: Dictionary, limit: int = -1) -> Array:
	var groups: Array = []
	if turn_log == null:
		return groups
	var shown: int = turn_log.events.size() if limit < 0 else mini(limit, turn_log.events.size())
	var last_phase := -1
	for i in range(shown):
		var ev := turn_log.events[i]
		if groups.is_empty() or ev.phase != last_phase:
			groups.append({"heading": phase_heading(turn_log.turn, ev.phase), "lines": [] as Array[String]})
			last_phase = ev.phase
		groups[groups.size() - 1]["lines"].append(ev.to_text(ship_names))
	return groups


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
	offset_left = 400.0
	offset_right = -440.0
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
	_toggle_button.pressed.connect(toggle)
	header.add_child(_toggle_button)
	_latest_label = Label.new()
	_latest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_latest_label.clip_text = true
	_latest_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_latest_label)

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
			_scroll_to_end()


func _apply_height() -> void:
	offset_top = offset_bottom - (EXPANDED_HEIGHT if _expanded else BAR_HEIGHT)


func toggle() -> void:
	set_expanded(not _expanded)


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
	var names := _ship_names()
	# Latest event overall: a fresh turn's log is empty, so fall back to the previous turn's.
	var logs := _logs_in_order()
	_latest_label.text = "No events yet"
	for i in range(logs.size() - 1, -1, -1):
		var limit: int = _reveal_limit if logs[i] == GameState.turn_log else -1
		if logs[i].events.size() > 0 and limit != 0:
			_latest_label.text = latest_line(logs[i], names, limit)
			break

	for child in _list.get_children():
		child.queue_free()
	for entry in _logs_in_order():
		var limit: int = _reveal_limit if entry == GameState.turn_log else -1
		for group in group_events(entry, names, limit):
			_list.add_child(_heading_label(group["heading"]))
			for line in group["lines"]:
				_list.add_child(_line_label(line))
	if _expanded:
		_scroll_to_end()


func _logs_in_order() -> Array:
	var by_turn: Dictionary = {}
	for turn in GameState.turn_logs.keys():
		by_turn[turn] = GameState.turn_logs[turn]
	if GameState.turn_log:
		by_turn[GameState.turn_log.turn] = GameState.turn_log
	var turns := by_turn.keys()
	turns.sort()
	var result: Array = []
	for turn in turns:
		result.append(by_turn[turn])
	return result


func _signature_now() -> String:
	var count := GameState.turn_log.events.size() if GameState.turn_log else 0
	var turn := GameState.turn_log.turn if GameState.turn_log else 0
	return "%d:%d:%d" % [turn, count, GameState.turn_logs.size()]


func _ship_names() -> Dictionary:
	var names := {}
	for ship in GameState.get_all_ships():
		names[ship.ship_id] = ship.ship_name
	return names


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
