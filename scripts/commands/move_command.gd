class_name MoveCommand
extends GameCommand
## MoveCommand - Command to plot ship movement

@export var ship_id: String = ""
@export var movement_commands: Array[String] = []  # ["F2", "S", "F1"]

func validate() -> bool:
	"""Validate if this move command is legal"""
	# Check if ship exists
	var ship_state = GameState.get_ship(ship_id)
	if not ship_state:
		push_error("MoveCommand: Ship %s not found" % ship_id)
		return false

	# Check if ship belongs to player
	if ship_state.player_id != player_id:
		push_error("MoveCommand: Ship %s does not belong to player %d" % [ship_id, player_id])
		return false

	# Check if it's the planning phase
	if GameState.current_phase != GameState.GamePhase.PLANNING:
		push_error("MoveCommand: Can only plot movement during PLANNING phase")
		return false

	# TODO: Add movement allowance validation
	# var ma = ship_state.get_movement_allowance()
	# Check if movement_commands are within allowance

	return true

func execute() -> bool:
	"""Execute the move command - store plotted movement"""
	if not validate():
		return false

	var ship_state = GameState.get_ship(ship_id)
	ship_state.plotted_actions["movement"] = movement_commands

	print("MoveCommand: Ship %s plotted movement: %s" % [ship_id, movement_commands])
	return true

func serialize() -> Dictionary:
	var data = super.serialize()
	data["ship_id"] = ship_id
	data["movement_commands"] = movement_commands
	return data

static func deserialize_move(data: Dictionary) -> MoveCommand:
	var command = MoveCommand.new()
	command.player_id = data.get("player_id", 0)
	command.turn_number = data.get("turn_number", 0)
	command.ship_id = data.get("ship_id", "")
	command.movement_commands = data.get("movement_commands", [])
	return command
