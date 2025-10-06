class_name GameCommand
extends Resource
## GameCommand - Base class for all player commands
## Commands are validated and executed on game state

@export var player_id: int = 0
@export var turn_number: int = 0

func validate() -> bool:
	"""Validate if this command can be executed. Override in subclasses."""
	return true

func execute() -> bool:
	"""Execute this command on the game state. Override in subclasses."""
	push_error("GameCommand.execute() must be overridden")
	return false

func serialize() -> Dictionary:
	"""Serialize command for network transmission"""
	return {
		"type": get_script().get_path(),
		"player_id": player_id,
		"turn_number": turn_number
	}

static func deserialize(data: Dictionary) -> GameCommand:
	"""Deserialize command from network data"""
	var script_path = data.get("type", "")
	if script_path.is_empty():
		return null

	var script = load(script_path)
	if not script:
		return null

	var command = script.new()
	command.player_id = data.get("player_id", 0)
	command.turn_number = data.get("turn_number", 0)

	return command
