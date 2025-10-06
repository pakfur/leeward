extends PanelContainer
## PlanningPanel - UI for plotting ship actions during planning phase (uses command pattern)

signal plan_submitted()

@onready var ship_selector: OptionButton = %ShipSelector
@onready var movement_input: LineEdit = %MovementInput
@onready var sail_state_selector: OptionButton = %SailStateSelector
@onready var submit_button: Button = %SubmitButton
@onready var clear_button: Button = %ClearButton
@onready var instructions_label: Label = %InstructionsLabel

var available_ships: Array[ShipState] = []
var current_ship_id: String = ""

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

func show_for_planning_with_states(ships: Array[ShipState]) -> void:
	"""Show the planning panel for the given ships (using ShipState)"""
	available_ships = ships
	visible = true
	_populate_ship_selector()
	_update_display()

func _populate_ship_selector() -> void:
	if not ship_selector:
		return

	ship_selector.clear()
	for i in range(available_ships.size()):
		var ship_state = available_ships[i]
		ship_selector.add_item(ship_state.ship_name, i)

	if available_ships.size() > 0:
		ship_selector.selected = 0
		_on_ship_selected(0)

func _on_ship_selected(index: int) -> void:
	if index >= 0 and index < available_ships.size():
		current_ship_id = available_ships[index].ship_id
		_update_display()

func _update_display() -> void:
	var current_ship = GameState.get_ship(current_ship_id)
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
	"""Submit planned actions as commands"""
	var current_ship = GameState.get_ship(current_ship_id)
	if not current_ship:
		return

	# Parse movement commands
	var movement_text = movement_input.text if movement_input else ""
	var movement_commands = _parse_movement_input(movement_text)

	# Create and execute MoveCommand
	var move_command = MoveCommand.new()
	move_command.player_id = current_ship.player_id
	move_command.turn_number = GameState.current_turn
	move_command.ship_id = current_ship_id
	move_command.movement_commands = movement_commands

	if move_command.execute():
		print("PlanningPanel: Move command executed for %s" % current_ship.ship_name)
	else:
		print("PlanningPanel: Move command failed for %s" % current_ship.ship_name)

	# Emit plan submitted signal
	plan_submitted.emit()

func _parse_movement_input(text: String) -> Array[String]:
	"""Parse movement input string into command array"""
	var commands: Array[String] = []
	var parts = text.split(" ", false)  # Split by space, skip empty

	for part in parts:
		var cmd = part.strip_edges().to_upper()
		if not cmd.is_empty():
			commands.append(cmd)

	return commands

func _on_clear_pressed() -> void:
	"""Clear current ship's plotted actions"""
	var current_ship = GameState.get_ship(current_ship_id)
	if not current_ship:
		return

	current_ship.clear_plot()

	if movement_input:
		movement_input.text = ""

	if sail_state_selector:
		sail_state_selector.selected = 1  # Reset to MS

func _on_phase_changed(phase: GameState.GamePhase) -> void:
	"""Hide panel when not in planning phase"""
	if phase != GameState.GamePhase.PLANNING:
		visible = false
