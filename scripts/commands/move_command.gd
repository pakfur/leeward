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

	if ship_state.side != player_id:
		push_error("MoveCommand: Ship %s does not belong to player %d" % [ship_id, player_id])
		return false

	return true

## A command is data sent to the server (NetworkSync), which runs it through CommandValidator; it is
## never executed where it is made. Movement is plotted through the plotting protocol.
func execute() -> bool:
	push_warning("MoveCommand.execute(): send the command to the server instead")
	return false

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
