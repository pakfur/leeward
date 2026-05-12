class_name CommandValidator
extends Node
## CommandValidator - Server-side command validation and execution
## Validates all player commands before execution on authoritative game state

var is_server: bool = true
var game_state: Node = null
var ship_controller: ShipStateController = null
var phase_controller: TurnPhaseController = null

func _init(state: Node = null, ship_ctrl: ShipStateController = null, phase_ctrl: TurnPhaseController = null) -> void:
	game_state = state if state else GameState
	ship_controller = ship_ctrl
	phase_controller = phase_ctrl

## Command Validation

func validate_command(command: GameCommand) -> Dictionary:
	"""Validate a command and return result with error message if invalid"""
	if not is_server:
		return {"valid": false, "error": "Can only validate commands on server"}

	# Check if command has required fields
	if command.player_id < 0:
		return {"valid": false, "error": "Invalid player_id"}

	if command.turn_number != phase_controller.current_turn:
		return {"valid": false, "error": "Command for wrong turn (expected %d, got %d)" % [
			phase_controller.current_turn, command.turn_number
		]}

	# Dispatch to specific validation based on command type
	if command is MoveCommand:
		return _validate_move_command(command)
	else:
		return {"valid": false, "error": "Unknown command type"}

func _validate_move_command(command: MoveCommand) -> Dictionary:
	"""Validate a movement command"""
	# Check if ship exists
	var ship = game_state.get_ship(command.ship_id)
	if not ship:
		return {"valid": false, "error": "Ship %s not found" % command.ship_id}

	# Check if ship belongs to player
	if ship.player_id != command.player_id:
		return {"valid": false, "error": "Ship %s does not belong to player %d" % [
			command.ship_id, command.player_id
		]}

	# Check if it's the planning phase
	if phase_controller.current_phase != TurnPhaseController.GamePhase.PLANNING:
		return {"valid": false, "error": "Can only plot movement during PLANNING phase"}

	# Validate movement allowance
	var validation_result = _validate_movement_allowance(ship, command.movement_commands)
	if not validation_result.valid:
		return validation_result

	return {"valid": true}

func _validate_movement_allowance(ship: ShipState, movement_commands: Array[String]) -> Dictionary:
	"""Validate that movement commands don't exceed movement allowance"""
	var ma = ship.get_movement_allowance()
	var total_movement = 0

	for cmd in movement_commands:
		var cmd_upper = cmd.to_upper()

		# Parse movement cost
		if cmd_upper.begins_with("F"):
			# Forward movement: F1, F2, etc.
			var num_str = cmd_upper.substr(1)
			if num_str.is_empty():
				total_movement += 1
			else:
				var num = num_str.to_int()
				if num <= 0:
					return {"valid": false, "error": "Invalid forward command: %s" % cmd}
				total_movement += num

		elif cmd_upper in ["P", "S"]:
			# Port/Starboard turn: costs 1 MA
			total_movement += 1

		elif cmd_upper in ["B", "BR", "BL"]:
			# Backward movement (if allowed): costs 2 MA
			total_movement += 2

		else:
			return {"valid": false, "error": "Unknown movement command: %s" % cmd}

	if total_movement > ma:
		return {"valid": false, "error": "Movement exceeds allowance (MA: %d, Used: %d)" % [ma, total_movement]}

	return {"valid": true}

## Command Execution

func execute_command(command: GameCommand) -> Dictionary:
	"""Validate and execute a command on the server"""
	if not is_server:
		return {"success": false, "error": "Can only execute commands on server"}

	# Validate first
	var validation = validate_command(command)
	if not validation.valid:
		push_error("[Server] Command validation failed: %s" % validation.error)
		return {"success": false, "error": validation.error}

	# Execute based on command type
	var result = false
	if command is MoveCommand:
		result = _execute_move_command(command)
	else:
		return {"success": false, "error": "Unknown command type"}

	if result:
		Trace.trace_log("Command", "Command executed successfully: %s" % command.get_class())
		return {"success": true}
	else:
		return {"success": false, "error": "Command execution failed"}

func _execute_move_command(command: MoveCommand) -> bool:
	"""Execute a movement command"""
	if not ship_controller:
		push_error("[Server] ShipStateController not set")
		return false

	return ship_controller.set_plotted_movement(command.ship_id, command.movement_commands)

## Batch Command Processing

func process_command_batch(commands: Array[GameCommand]) -> Dictionary:
	"""Process multiple commands and return results"""
	var results = []
	var success_count = 0
	var failure_count = 0

	for command in commands:
		var result = execute_command(command)
		results.append(result)

		if result.success:
			success_count += 1
		else:
			failure_count += 1

	return {
		"total": commands.size(),
		"success": success_count,
		"failed": failure_count,
		"results": results
	}
