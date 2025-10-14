extends Window
## DeveloperUI - Debug/testing UI for manipulating game state
## Toggle with F12, draggable, shows all editable state fields

@onready var tab_container: TabContainer = %TabContainer
@onready var environment_tab: VBoxContainer = %Environment
@onready var ships_tab: VBoxContainer = %Ships
@onready var controls_tab: VBoxContainer = %Controls

@onready var turn_label: Label = %TurnLabel
@onready var phase_label: Label = %PhaseLabel
@onready var advance_phase_btn: Button = %AdvancePhaseButton
@onready var advance_turn_btn: Button = %AdvanceTurnButton
@onready var reset_btn: Button = %ResetButton

var ship_selector: OptionButton = null
var ship_fields_container: VBoxContainer = null

@onready var console_output: TextEdit = %ConsoleOutput

var game_state: Node = null
var initial_scenario: Dictionary = {}  # For reset functionality

# Field tracking for dynamic updates
var environment_fields: Dictionary = {}  # field_name -> Control
var ship_fields: Dictionary = {}  # field_name -> Control

# Dragging
var dragging := false
var drag_offset := Vector2.ZERO

func _ready() -> void:
	game_state = GameState

	# Setup window
	title = "Developer UI"
	size = Vector2i(500, 700)
	position = Vector2i(50, 50)

	# Connect signals
	if game_state:
		game_state.phase_changed.connect(_on_phase_changed)
		game_state.turn_changed.connect(_on_turn_changed)

	advance_phase_btn.pressed.connect(_on_advance_phase_pressed)
	advance_turn_btn.pressed.connect(_on_advance_turn_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)

	# Build UI
	_build_environment_tab()
	_build_ships_tab()
	_update_turn_phase_display()

	# Store initial scenario for reset
	if game_state:
		initial_scenario = game_state.active_scenario.duplicate(true)

	_log("Developer UI initialized. Press F12 to toggle.")

func _input(event: InputEvent) -> void:
	# Handle window dragging
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _is_in_title_bar(mb.position):
				dragging = true
				drag_offset = mb.position
			else:
				dragging = false

	elif event is InputEventMouseMotion and dragging:
		position += Vector2i(event.position - drag_offset)

func _is_in_title_bar(pos: Vector2) -> bool:
	"""Check if position is in window title bar (top 30 pixels)"""
	return pos.y < 30

## Tab Building

func _build_environment_tab() -> void:
	"""Build the environment state editor tab"""
	if not game_state or not game_state.environment:
		_log("No environment state available")
		return

	var env = game_state.environment

	# Clear existing fields
	for child in environment_tab.get_children():
		child.queue_free()
	environment_fields.clear()

	# Add header
	var header = Label.new()
	header.text = "Environment State (All @export fields)"
	header.add_theme_font_size_override("font_size", 16)
	environment_tab.add_child(header)

	var separator = HSeparator.new()
	environment_tab.add_child(separator)

	# Add scroll container for fields
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	environment_tab.add_child(scroll)

	var fields_container = VBoxContainer.new()
	scroll.add_child(fields_container)

	# Add editable fields for all @export properties
	_add_field(fields_container, env, "wind_direction", 0, 5, "int")
	_add_field(fields_container, env, "wind_speed", 0, 5, "int")
	_add_field(fields_container, env, "wind_speed_change", ["steady", "gusty"], null, "string")
	_add_field(fields_container, env, "environment", ["oceanic", "coastal"], null, "string")
	_add_field(fields_container, env, "wind_direction_change", ["none", "veering", "backing"], null, "string")
	_add_field(fields_container, env, "sea_state", 0, 3, "int")
	_add_field(fields_container, env, "visibility", ["clear", "hazy", "fog", "storm"], null, "string")
	_add_field(fields_container, env, "time_of_day", ["dawn", "day", "dusk", "night"], null, "string")
	_add_field(fields_container, env, "precipitation", ["none", "rain", "snow", "storm"], null, "string")

func _build_ships_tab() -> void:
	"""Build the ships editor tab"""
	if not game_state:
		return

	# Clear existing
	for child in ships_tab.get_children():
		child.queue_free()

	# Header
	var header = Label.new()
	header.text = "Ship State Editor"
	header.add_theme_font_size_override("font_size", 16)
	ships_tab.add_child(header)

	var separator = HSeparator.new()
	ships_tab.add_child(separator)

	# Ship selector
	var selector_label = Label.new()
	selector_label.text = "Select Ship:"
	ships_tab.add_child(selector_label)

	# Create ship selector dynamically
	ship_selector = OptionButton.new()
	var ships = game_state.get_all_ships()
	for i in range(ships.size()):
		var ship = ships[i]
		ship_selector.add_item("%s (%s)" % [ship.ship_name, ship.ship_id], i)

	ship_selector.item_selected.connect(_on_ship_selected)
	ships_tab.add_child(ship_selector)

	var sep2 = HSeparator.new()
	ships_tab.add_child(sep2)

	# Ship fields container (populated when ship selected)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ships_tab.add_child(scroll)

	ship_fields_container = VBoxContainer.new()
	ship_fields_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ship_fields_container)

	# Select first ship by default
	if ships.size() > 0:
		ship_selector.select(0)
		_on_ship_selected(0)

func _on_ship_selected(index: int) -> void:
	"""When a ship is selected from dropdown"""
	var ships = game_state.get_all_ships()
	if index < 0 or index >= ships.size():
		return

	var ship = ships[index]

	# Clear existing fields
	for child in ship_fields_container.get_children():
		child.queue_free()
	ship_fields.clear()

	# Add read-only fields
	_add_readonly_field(ship_fields_container, "ship_id", ship.ship_id)
	_add_readonly_field(ship_fields_container, "ship_name", ship.ship_name)

	var sep = HSeparator.new()
	ship_fields_container.add_child(sep)

	# Add editable fields
	_add_ship_field(ship_fields_container, ship, "facing", 0, 5, "int")
	_add_ship_field(ship_fields_container, ship, "current_speed", 0, 10, "int")
	_add_ship_field(ship_fields_container, ship, "last_speed", 0, 10, "int")
	_add_ship_field(ship_fields_container, ship, "sail_state", ["FS", "MS", "PS", "NS"], null, "string")

## Field Creation

func _add_field(container: Control, object: Object, property: String, min_val, max_val, type: String) -> void:
	"""Add an editable field for environment state"""
	var hbox = HBoxContainer.new()
	container.add_child(hbox)

	var label = Label.new()
	label.text = property + ":"
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)

	var control: Control

	if type == "int":
		var spinbox = SpinBox.new()
		spinbox.min_value = min_val
		spinbox.max_value = max_val
		spinbox.step = 1
		spinbox.value = object.get(property)
		spinbox.value_changed.connect(func(value): _on_environment_field_changed(property, int(value)))
		control = spinbox

	elif type == "string":
		if typeof(min_val) == TYPE_ARRAY:
			# Dropdown for string options
			var option_btn = OptionButton.new()
			for option in min_val:
				option_btn.add_item(option)
			var current_val = object.get(property)
			var idx = min_val.find(current_val)
			if idx >= 0:
				option_btn.select(idx)
			option_btn.item_selected.connect(func(index): _on_environment_field_changed(property, min_val[index]))
			control = option_btn
		else:
			# Text field
			var line_edit = LineEdit.new()
			line_edit.text = str(object.get(property))
			line_edit.text_changed.connect(func(text): _on_environment_field_changed(property, text))
			control = line_edit

	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(control)

	environment_fields[property] = control

func _add_ship_field(container: Control, ship: Object, property: String, min_val, max_val, type: String) -> void:
	"""Add an editable field for ship state"""
	var hbox = HBoxContainer.new()
	container.add_child(hbox)

	var label = Label.new()
	label.text = property + ":"
	label.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(label)

	var control: Control

	if type == "int":
		var spinbox = SpinBox.new()
		spinbox.min_value = min_val
		spinbox.max_value = max_val
		spinbox.step = 1
		spinbox.value = ship.get(property)
		spinbox.value_changed.connect(func(value): _on_ship_field_changed(ship, property, int(value)))
		control = spinbox

	elif type == "string":
		if typeof(min_val) == TYPE_ARRAY:
			var option_btn = OptionButton.new()
			for option in min_val:
				option_btn.add_item(option)
			var current_val = ship.get(property)
			var idx = min_val.find(current_val)
			if idx >= 0:
				option_btn.select(idx)
			option_btn.item_selected.connect(func(index): _on_ship_field_changed(ship, property, min_val[index]))
			control = option_btn

	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(control)

	ship_fields[property] = control

func _add_readonly_field(container: Control, label_text: String, value: String) -> void:
	"""Add a read-only field"""
	var hbox = HBoxContainer.new()
	container.add_child(hbox)

	var label = Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(label)

	var value_label = Label.new()
	value_label.text = value
	value_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hbox.add_child(value_label)

## Field Change Handlers

func _on_environment_field_changed(property: String, value) -> void:
	"""Immediately update environment state when field changes"""
	if not game_state or not game_state.environment:
		return

	game_state.environment.set(property, value)
	_log("Environment.%s = %s (visual update on next turn)" % [property, value])

func _on_ship_field_changed(ship: Object, property: String, value) -> void:
	"""Immediately update ship state when field changes"""
	ship.set(property, value)
	_log("Ship %s.%s = %s" % [ship.ship_id, property, value])

## Controls

func _update_turn_phase_display() -> void:
	"""Update the turn and phase display"""
	if not game_state:
		return

	turn_label.text = "Turn: %d" % game_state.current_turn
	phase_label.text = "Phase: %s" % game_state.get_phase_name()

func _on_phase_changed(_phase) -> void:
	"""Handle phase changes"""
	_update_turn_phase_display()
	_log("Phase changed to: %s" % game_state.get_phase_name())

func _on_turn_changed(_turn) -> void:
	"""Handle turn changes"""
	_update_turn_phase_display()
	_log("Turn advanced to: %d" % game_state.current_turn)

func _on_advance_phase_pressed() -> void:
	"""Advance to next phase"""
	if game_state and game_state.phase_controller:
		game_state.phase_controller.advance_phase()
		_log("Advanced phase")
	else:
		_log("ERROR: No phase controller available")

func _on_advance_turn_pressed() -> void:
	"""Advance to next turn (skip through all phases)"""
	if game_state and game_state.phase_controller:
		# Keep advancing phases until we reach the next turn
		var start_turn = game_state.current_turn
		while game_state.current_turn == start_turn:
			game_state.phase_controller.advance_phase()
			await get_tree().process_frame  # Allow phase to process
		_log("Advanced to turn %d" % game_state.current_turn)
	else:
		_log("ERROR: No phase controller available")

func _on_reset_pressed() -> void:
	"""Reset game state to initial scenario"""
	if initial_scenario.is_empty():
		_log("ERROR: No initial scenario stored")
		return

	_log("Resetting to initial scenario...")

	# Reset game state
	if game_state:
		game_state.deserialize_full_state({
			"turn": 1,
			"phase": 0,  # SETUP
			"environment": initial_scenario,
			"ships": initial_scenario.get("ships", [])
		})

	# Rebuild UI
	_build_environment_tab()
	_build_ships_tab()
	_update_turn_phase_display()

	_log("Reset complete")

## Console Logging

func _log(message: String) -> void:
	"""Add message to console output"""
	var timestamp = Time.get_time_string_from_system()
	console_output.text += "[%s] %s\n" % [timestamp, message]

	# Auto-scroll to bottom
	console_output.scroll_vertical = console_output.get_line_count()

	# Also print to Godot console
	print("[DevUI] %s" % message)

## Public API

func refresh_all() -> void:
	"""Refresh all UI fields from current state"""
	_build_environment_tab()
	_build_ships_tab()
	_update_turn_phase_display()
	_log("UI refreshed")
