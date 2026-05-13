extends Window
## DeveloperUI - Debug/testing UI for manipulating game state
## Toggle with F12, draggable, shows all editable state fields

@onready var tab_container: TabContainer = %TabContainer
@onready var environment_tab: VBoxContainer = %Environment
@onready var ships_tab: VBoxContainer = %Ships
@onready var controls_tab: VBoxContainer = %Controls
@onready var trace_tab: VBoxContainer = %Trace

@onready var hex_coords_checkbox: CheckBox = %HexCoordsCheckbox

signal hex_coords_toggled(enabled: bool)
signal hex_labels_toggled(enabled: bool)

@onready var turn_label: Label = %TurnLabel
@onready var phase_label: Label = %PhaseLabel
@onready var advance_phase_btn: Button = %AdvancePhaseButton
@onready var advance_turn_btn: Button = %AdvanceTurnButton
@onready var reset_btn: Button = %ResetButton
@onready var collapse_btn: Button = %CollapseButton

var ship_selector: OptionButton = null
var ship_fields_container: VBoxContainer = null

@onready var console_output: TextEdit = %ConsoleOutput

var game_state: Node = null
var initial_scenario: Dictionary = {}  # For reset functionality
var collapsed := false
var expanded_size := Vector2i(500, 700)

# Field tracking for dynamic updates
var environment_fields: Dictionary = {}  # field_name -> Control
var ship_fields: Dictionary = {}  # field_name -> Control

# Trace tab controls
var trace_category_selector: OptionButton = null
var trace_text_display: TextEdit = null
var trace_follow_enabled: bool = true
var trace_follow_btn: Button = null
var trace_current_category: String = ""
var _trace_known_category_count: int = 0

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
	collapse_btn.pressed.connect(_toggle_collapsed)
	hex_coords_checkbox.toggled.connect(_on_hex_coords_toggled)

	# Build UI
	_build_environment_tab()
	_build_ships_tab()
	_build_trace_tab()
	_update_turn_phase_display()

	# Connect to Trace autoload
	Trace.trace_added.connect(_on_trace_added)
	tree_exiting.connect(_on_tree_exiting)

	# Store initial scenario for reset
	if game_state:
		initial_scenario = game_state.active_scenario.duplicate(true)

	_log("Developer UI initialized. Press F12 to toggle.")

func _input(event: InputEvent) -> void:
	# F12 toggles visibility even when this window has focus
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		visible = false
		return

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

func _toggle_collapsed() -> void:
	collapsed = not collapsed
	if collapsed:
		expanded_size = size
		# Hide all Header children after TitleRow
		var header = $MainContainer/Header
		for i in range(1, header.get_child_count()):
			header.get_child(i).visible = false
		tab_container.visible = false
		size = Vector2i(size.x, 60)
		collapse_btn.text = "▶"
		collapse_btn.tooltip_text = "Expand"
	else:
		var header = $MainContainer/Header
		for i in range(1, header.get_child_count()):
			header.get_child(i).visible = true
		tab_container.visible = true
		size = expanded_size
		collapse_btn.text = "▼"
		collapse_btn.tooltip_text = "Collapse"

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

	# Debug overlay options
	var overlay_sep = HSeparator.new()
	fields_container.add_child(overlay_sep)

	var overlay_header = Label.new()
	overlay_header.text = "Debug Overlays"
	overlay_header.add_theme_font_size_override("font_size", 14)
	fields_container.add_child(overlay_header)

	var hex_labels_hbox = HBoxContainer.new()
	fields_container.add_child(hex_labels_hbox)

	var hex_labels_label = Label.new()
	hex_labels_label.text = "view_hex_coordinates:"
	hex_labels_label.custom_minimum_size = Vector2(200, 0)
	hex_labels_hbox.add_child(hex_labels_label)

	var hex_labels_option = OptionButton.new()
	hex_labels_option.add_item("false")
	hex_labels_option.add_item("true")
	hex_labels_option.select(0)  # Default false
	hex_labels_option.item_selected.connect(func(index): _on_hex_labels_toggled(index == 1))
	hex_labels_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hex_labels_hbox.add_child(hex_labels_option)

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
	_add_ship_field(ship_fields_container, ship, "speed", 0, 10, "int")
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
	if not game_state or not game_state.environment_controller:
		return
	game_state.environment_controller.set_environment_property(property, value)
	_log("Environment.%s = %s" % [property, value])

func _on_ship_field_changed(ship: Object, property: String, value) -> void:
	if not game_state or not game_state.ship_controller:
		return
	var sid: String = ship.ship_id
	match property:
		"facing":
			game_state.ship_controller.set_ship_facing(sid, value)
		"speed":
			game_state.ship_controller.set_ship_speed(sid, value)
		"sail_state":
			game_state.ship_controller.set_sail_state(sid, value)
		_:
			push_warning("DeveloperUI: No controller method for ship property '%s'" % property)
	_log("Ship %s.%s = %s" % [sid, property, value])

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

func _on_hex_coords_toggled(enabled: bool) -> void:
	hex_coords_toggled.emit(enabled)
	_log("Hex coordinates display: %s" % ("ON" if enabled else "OFF"))

func _on_hex_labels_toggled(enabled: bool) -> void:
	hex_labels_toggled.emit(enabled)
	_log("Hex coordinate labels: %s" % ("ON" if enabled else "OFF"))

func _on_advance_phase_pressed() -> void:
	if not GameState.is_server:
		_log("ERROR: Cannot advance phase on client")
		return
	if game_state and game_state.phase_controller:
		game_state.phase_controller.advance_phase()
		_log("Advanced phase")
	else:
		_log("ERROR: No phase controller available")

func _on_advance_turn_pressed() -> void:
	if not GameState.is_server:
		_log("ERROR: Cannot advance turn on client")
		return
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
	if not GameState.is_server:
		_log("ERROR: Cannot reset game on client")
		return
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

	Trace.trace_log("DevUI", message)

func _on_tree_exiting() -> void:
	if Trace.trace_added.is_connected(_on_trace_added):
		Trace.trace_added.disconnect(_on_trace_added)

## Trace Tab

func _build_trace_tab() -> void:
	"""Build the trace log viewer tab"""
	for child in trace_tab.get_children():
		child.queue_free()

	# Header
	var header = Label.new()
	header.text = "Trace Log Viewer"
	header.add_theme_font_size_override("font_size", 16)
	trace_tab.add_child(header)

	var separator = HSeparator.new()
	trace_tab.add_child(separator)

	# Category selector row
	var selector_row = HBoxContainer.new()
	trace_tab.add_child(selector_row)

	var selector_label = Label.new()
	selector_label.text = "Category:"
	selector_label.custom_minimum_size = Vector2(80, 0)
	selector_row.add_child(selector_label)

	trace_category_selector = OptionButton.new()
	trace_category_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trace_category_selector.item_selected.connect(_on_trace_category_selected)
	selector_row.add_child(trace_category_selector)

	_refresh_trace_categories()

	var sep2 = HSeparator.new()
	trace_tab.add_child(sep2)

	# Control buttons row
	var button_row = HBoxContainer.new()
	trace_tab.add_child(button_row)

	var scroll_top_btn = Button.new()
	scroll_top_btn.text = "Top"
	scroll_top_btn.tooltip_text = "Scroll to top"
	scroll_top_btn.pressed.connect(_on_trace_scroll_top)
	button_row.add_child(scroll_top_btn)

	var scroll_bottom_btn = Button.new()
	scroll_bottom_btn.text = "Bottom"
	scroll_bottom_btn.tooltip_text = "Scroll to bottom"
	scroll_bottom_btn.pressed.connect(_on_trace_scroll_bottom)
	button_row.add_child(scroll_bottom_btn)

	trace_follow_btn = Button.new()
	trace_follow_btn.text = "Follow: ON"
	trace_follow_btn.tooltip_text = "Auto-scroll on new messages"
	trace_follow_btn.toggle_mode = true
	trace_follow_btn.button_pressed = true
	trace_follow_btn.toggled.connect(_on_trace_follow_toggled)
	button_row.add_child(trace_follow_btn)

	var copy_btn = Button.new()
	copy_btn.text = "Copy"
	copy_btn.tooltip_text = "Copy to clipboard"
	copy_btn.pressed.connect(_on_trace_copy)
	button_row.add_child(copy_btn)

	var clear_btn = Button.new()
	clear_btn.text = "Clear"
	clear_btn.tooltip_text = "Clear current category"
	clear_btn.pressed.connect(_on_trace_clear)
	button_row.add_child(clear_btn)

	# Text display
	trace_text_display = TextEdit.new()
	trace_text_display.editable = false
	trace_text_display.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	trace_text_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trace_tab.add_child(trace_text_display)


func _refresh_trace_categories() -> void:
	"""Refresh the category dropdown from Trace autoload"""
	if not trace_category_selector:
		return

	var previous_selection = trace_current_category
	trace_category_selector.clear()

	var categories = Trace.get_categories()
	if categories.is_empty():
		trace_category_selector.add_item("(no categories)")
		trace_category_selector.set_item_disabled(0, true)
		trace_current_category = ""
		return

	for i in range(categories.size()):
		trace_category_selector.add_item(categories[i])

	# Restore previous selection if still valid
	var idx = categories.find(previous_selection)
	if idx >= 0:
		trace_category_selector.select(idx)
		trace_current_category = previous_selection
	else:
		trace_category_selector.select(0)
		trace_current_category = categories[0]


func _rebuild_trace_display() -> void:
	"""Rebuild the full text display for the current category"""
	if not trace_text_display or trace_current_category.is_empty():
		return

	var entries = Trace.get_traces(trace_current_category)
	var text = ""
	for entry in entries:
		text += "[%s] %s\n" % [entry.timestamp, entry.message]
		if entry.context != "":
			text += "  -> %s\n" % entry.context

	trace_text_display.text = text

	if trace_follow_enabled:
		trace_text_display.scroll_vertical = trace_text_display.get_line_count()


func _on_trace_category_selected(index: int) -> void:
	"""Handle category selection change"""
	var categories = Trace.get_categories()
	if index >= 0 and index < categories.size():
		trace_current_category = categories[index]
		_rebuild_trace_display()


func _on_trace_added(category: String) -> void:
	"""Handle new trace message from Trace autoload"""
	# Refresh categories dropdown if new category appeared
	var categories = Trace.get_categories()
	if trace_category_selector and _trace_known_category_count != categories.size():
		_refresh_trace_categories()
		_trace_known_category_count = categories.size()

	# Append to display if matching current category
	if category == trace_current_category and trace_text_display:
		var entries = Trace.get_traces(category)
		if entries.size() > 0:
			var entry = entries[entries.size() - 1]
			var line = "[%s] %s\n" % [entry.timestamp, entry.message]
			if entry.context != "":
				line += "  -> %s\n" % entry.context
			trace_text_display.text += line

			if trace_follow_enabled:
				trace_text_display.scroll_vertical = trace_text_display.get_line_count()


func _on_trace_scroll_top() -> void:
	if trace_text_display:
		trace_text_display.scroll_vertical = 0


func _on_trace_scroll_bottom() -> void:
	if trace_text_display:
		trace_text_display.scroll_vertical = trace_text_display.get_line_count()


func _on_trace_follow_toggled(toggled_on: bool) -> void:
	trace_follow_enabled = toggled_on
	if trace_follow_btn:
		trace_follow_btn.text = "Follow: ON" if toggled_on else "Follow: OFF"
	if toggled_on and trace_text_display:
		trace_text_display.scroll_vertical = trace_text_display.get_line_count()


func _on_trace_copy() -> void:
	if trace_text_display:
		DisplayServer.clipboard_set(trace_text_display.text)
		_log("Trace text copied to clipboard")


func _on_trace_clear() -> void:
	if trace_current_category.is_empty():
		return
	Trace.clear_category(trace_current_category)
	if trace_text_display:
		trace_text_display.text = ""
	_log("Cleared trace category: %s" % trace_current_category)


## Public API

func refresh_all() -> void:
	"""Refresh all UI fields from current state"""
	_build_environment_tab()
	_build_ships_tab()
	_update_turn_phase_display()
	_refresh_trace_categories()
	_rebuild_trace_display()
	_log("UI refreshed")
