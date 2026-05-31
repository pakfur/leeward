class_name NetworkSync
extends Node
## NetworkSync - Handles state synchronization between server and clients
## Server broadcasts authoritative state, clients apply updates

signal sync_requested()

var is_server: bool = true
var game_state: Node = null

# Sync settings — disabled until a network transport layer exists
var auto_sync_enabled: bool = false
var sync_interval: float = 0.1
var _sync_timer: float = 0.0

const TRACE_CATEGORY = "NetworkSync"

func _init(state: Node = null) -> void:
	game_state = state if state else GameState

func _ready() -> void:
	if is_server:
		Trace.trace_log(TRACE_CATEGORY, "Server sync initialized")
	else:
		Trace.trace_log(TRACE_CATEGORY, "Client sync initialized")

func _process(delta: float) -> void:
	if not auto_sync_enabled or not is_server:
		return

	_sync_timer += delta
	if _sync_timer >= sync_interval:
		_sync_timer = 0.0
		broadcast_state()

## Server Functions

func broadcast_state() -> void:
	"""SERVER ONLY: Broadcast full game state to all clients"""
	if not is_server:
		push_error("NetworkSync: Cannot broadcast state on client")
		return

	var _state_data = _serialize_game_state()

	# TODO: Send state_data to all connected clients via network
	# For now, this is a placeholder for future network implementation
	# Example: rpc("receive_state_update", state_data)

	Trace.trace_log(TRACE_CATEGORY, "State broadcast ready (awaiting network layer)")

func broadcast_state_delta(_changes: Dictionary) -> void:
	"""SERVER ONLY: Broadcast incremental state changes (optimization)"""
	if not is_server:
		push_error("NetworkSync: Cannot broadcast delta on client")
		return

	# TODO: Send delta changes instead of full state for bandwidth optimization
	# This would include only what changed since last sync
	Trace.trace_log(TRACE_CATEGORY, "Delta sync ready (awaiting network layer)")

func _serialize_game_state() -> Dictionary:
	"""Serialize current game state for network transmission"""
	return {
		"turn": game_state.current_turn,
		"phase": game_state.current_phase,
		"players_ready": game_state.players_ready,
		"environment": game_state.environment.serialize() if game_state.environment else {},
		"ships": _serialize_ships()
	}

func _serialize_ships() -> Array:
	"""Serialize all ships"""
	var ships_data = []
	for ship_id in game_state.ships.keys():
		var ship = game_state.ships[ship_id]
		ships_data.append(ship.serialize())
	return ships_data

## Client Functions

func receive_state_update(state_data: Dictionary) -> void:
	"""CLIENT ONLY: Receive and apply state update from server"""
	if is_server:
		push_warning("NetworkSync: Server received state update (ignoring)")
		return

	Trace.trace_log(TRACE_CATEGORY, "Receiving state update from server")
	game_state.sync_from_server(state_data)

func receive_delta_update(delta_data: Dictionary) -> void:
	"""CLIENT ONLY: Receive and apply incremental update"""
	if is_server:
		push_warning("NetworkSync: Server received delta update (ignoring)")
		return

	Trace.trace_log(TRACE_CATEGORY, "Receiving delta update from server")
	_apply_delta_changes(delta_data)

func _apply_delta_changes(delta: Dictionary) -> void:
	## CLIENT ONLY: Apply state changes received from server.  SCV:ALLOW
	## Direct mutation is intentional — caller (receive_delta_update) guards against server-side use.
	# Update phase if changed
	if delta.has("phase"):
		game_state.current_phase = delta.phase
		game_state.phase_changed.emit(game_state.current_phase)

	# Update turn if changed
	if delta.has("turn"):
		game_state.current_turn = delta.turn
		game_state.turn_changed.emit(game_state.current_turn)

	# Update environment if changed
	if delta.has("environment"):
		var env = delta.environment
		if game_state.environment:
			for key in env.keys():
				game_state.environment.set(key, env[key])

	# Update ships if changed
	if delta.has("ships"):
		for ship_update in delta.ships:
			var ship_id = ship_update.get("ship_id")
			if game_state.ships.has(ship_id):
				game_state._update_ship_from_data(game_state.ships[ship_id], ship_update)

	game_state.state_synced.emit()

## Command Transmission

func send_command_to_server(command: GameCommand) -> void:
	"""CLIENT ONLY: Send command to server for validation and execution"""
	if is_server:
		push_error("NetworkSync: Cannot send command to self on server")
		return

	var _command_data = command.serialize()

	# TODO: Send command to server via network
	# Example: rpc_id(1, "receive_command", command_data)

	Trace.trace_log(TRACE_CATEGORY, "Command queued for server: %s" % command.get_class())

func receive_command(command_data: Dictionary) -> void:
	"""SERVER ONLY: Receive command from client and execute"""
	if not is_server:
		push_error("NetworkSync: Client cannot receive commands")
		return

	# Deserialize command
	var command = GameCommand.deserialize(command_data)
	if not command:
		push_error("[Server] Failed to deserialize command")
		return

	# Execute via command validator
	if game_state.command_validator:
		var result = game_state.command_validator.execute_command(command)
		Trace.trace_log(TRACE_CATEGORY, "Command executed: %s (success: %s)" % [
			command.get_class(),
			result.get("success", false)
		])

		# TODO: Send result back to client
		# rpc_id(sender_id, "receive_command_result", result)
	else:
		push_error("[Server] CommandValidator not initialized")

func receive_command_result(result: Dictionary) -> void:
	"""CLIENT ONLY: Receive command execution result from server"""
	if is_server:
		return

	if result.get("success", false):
		Trace.trace_log(TRACE_CATEGORY, "Command executed successfully on server")
	else:
		push_error("[Client] Command failed on server: %s" % result.get("error", "Unknown error"))

## Utility Functions

func request_full_sync() -> void:
	"""Request a full state sync from server (useful for reconnection)"""
	if is_server:
		broadcast_state()
	else:
		Trace.trace_log(TRACE_CATEGORY, "Full sync requested from server")
		sync_requested.emit()

func client_requests_sync() -> void:
	"""SERVER ONLY: Handle sync request from client"""
	if not is_server:
		return

	Trace.trace_log(TRACE_CATEGORY, "Client requested full sync")
	# TODO: Send full state to requesting client
	# rpc_id(sender_id, "receive_state_update", _serialize_game_state())
