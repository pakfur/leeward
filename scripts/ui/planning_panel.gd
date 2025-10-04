extends PanelContainer
## PlanningPanel - UI for plotting ship actions during planning phase

signal plan_submitted()

@onready var ship_selector: OptionButton = %ShipSelector
@onready var movement_input: LineEdit = %MovementInput
@onready var sail_state_selector: OptionButton = %SailStateSelector
@onready var submit_button: Button = %SubmitButton
@onready var clear_button: Button = %ClearButton
@onready var instructions_label: Label = %InstructionsLabel

var available_ships: Array[Ship] = []
var current_ship: Ship = null

func _ready() -> void:
	visible = false
	GameState.phase_changed.connect(_on_phase_changed)

	if submit_button:
		submit_button.pressed.connect(_on_submit_pressed)
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	if ship_selector:
		ship_selector.item_selected.connect(_on_ship_selected)

	_setup_sail_state_selector()

func _setup_sail_state_selector() -> void:
	if not sail_state_selector:
		return

	sail_state_selector.clear()
	sail_state_selector.add_item("Fighting Sail (FS)", 0)
	sail_state_selector.add_item("Maneuvering Sail (MS)", 1)
	sail_state_selector.add_item("Plain Sail (PS)", 2)
	sail_state_selector.add_item("No Sail (NS)", 3)
	sail_state_selector.selected = 1  # Default to MS

func show_for_planning(ships: Array[Ship]) -> void:
	"""Show the planning panel for the given ships"""
	available_ships = ships
	visible = true
	_populate_ship_selector()
	_update_display()

func _populate_ship_selector() -> void:
	if not ship_selector:
		return

	ship_selector.clear()
	for i in range(available_ships.size()):
		var ship = available_ships[i]
		ship_selector.add_item(ship.ship_name, i)

	if available_ships.size() > 0:
		ship_selector.selected = 0
		_on_ship_selected(0)

func _on_ship_selected(index: int) -> void:
	if index >= 0 and index < available_ships.size():
		current_ship = available_ships[index]
		_update_display()

func _update_display() -> void:
	if not current_ship:
		return

	# Update instructions
	if instructions_label:
		var ma = current_ship.get_movement_allowance()
		instructions_label.text = "Movement Allowance: %d\nCommands: F# (forward), P (port), S (starboard)\nExample: F2 S F1" % ma

	# Load current plotted actions if any
	if movement_input:
		var plotted = current_ship.plotted_actions.get("movement", [])
		movement_input.text = " ".join(plotted)

	# Set sail state
	if sail_state_selector:
		var sail_map = {"FS": 0, "MS": 1, "PS": 2, "NS": 3}
		sail_state_selector.selected = sail_map.get(current_ship.sail_state, 1)

func _on_submit_pressed() -> void:
	"""Submit the plan for the current ship"""
	if not current_ship:
		return

	# Parse movement input
	var movement_text = movement_input.text.strip_edges().to_upper()
	var movement_commands = movement_text.split(" ", false)

	# Validate movement commands
	if not _validate_movement(movement_commands):
		push_warning("Invalid movement commands")
		return

	# Store the plot
	current_ship.plotted_actions.movement = movement_commands

	# Store sail state change if different
	var sail_codes = ["FS", "MS", "PS", "NS"]
	var new_sail_state = sail_codes[sail_state_selector.selected]
	if new_sail_state != current_ship.sail_state:
		current_ship.plotted_actions.sail_change = new_sail_state

	print("Plan submitted for %s: %s" % [current_ship.ship_name, movement_commands])

	# Move to next ship or finish
	var current_index = available_ships.find(current_ship)
	if current_index < available_ships.size() - 1:
		ship_selector.selected = current_index + 1
		_on_ship_selected(current_index + 1)
	else:
		# All ships planned
		visible = false
		plan_submitted.emit()

func _on_clear_pressed() -> void:
	"""Clear the current plot"""
	if movement_input:
		movement_input.text = ""
	if current_ship:
		current_ship.clear_plot()

func _validate_movement(commands: Array) -> bool:
	"""Validate movement commands"""
	if commands.is_empty():
		return true  # Empty is valid (no movement)

	for cmd in commands:
		var cmd_str = str(cmd)
		if cmd_str.begins_with("F"):
			var num_str = cmd_str.substr(1)
			if not num_str.is_valid_int():
				return false
			var num = num_str.to_int()
			if num < 1 or num > 10:
				return false
		elif cmd_str == "P" or cmd_str == "S":
			continue
		else:
			return false

	return true

func _on_phase_changed(phase: GameState.GamePhase) -> void:
	visible = (phase == GameState.GamePhase.PLANNING)
