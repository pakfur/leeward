class_name MoveCommand
extends GameCommand
## MoveCommand - Command to plot ship movement

@export var ship_id: String = ""
@export var movement_commands: Array[String] = []  # ["F2", "S", "F1"]

func validate() -> bool:
	"""DEPRECATED: Use CommandValidator on server instead"""
	push_warning("MoveCommand.validate() is deprecated. Use server-side CommandValidator.")

	# Basic validation for backward compatibility
	var ship_state = GameState.get_ship(ship_id)
	if not ship_state:
		push_error("MoveCommand: Ship %s not found" % ship_id)
		return false

	if ship_state.player_id != player_id:
		push_error("MoveCommand: Ship %s does not belong to player %d" % [ship_id, player_id])
		return false

	return true

func execute() -> bool:
	"""Execute the move command via server authority"""
	# If this is the server, use command validator
	if GameState.is_server and GameState.command_validator:
		var result = GameState.command_validator.execute_command(self)
		return result.get("success", false)

	# If this is a client, commands should be sent to server
	# For now, we'll push a warning and fail
	push_warning("MoveCommand.execute() called on client - should send to server instead")
	return false

func execute_local_for_testing() -> bool:
	"""Direct execution for single-player testing (bypasses server validation)"""
	if not validate():
		return false

	var ship_state = GameState.get_ship(ship_id)
	if not ship_state:
		return false

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
