extends Node
## GameState - Manages the overall game state
## This is now a data container. Authority is managed by server controllers.
## On server: Full read/write access via controllers
## On client: Read-only, updated via network sync

signal phase_changed(new_phase: GamePhase)
signal turn_changed(turn_number: int)
signal player_ready(player_id: int)
signal state_synced()  # Emitted when state is synced from server

enum GamePhase {
	SETUP,
	ENVIRONMENT,
	PLANNING,
	MOVEMENT_RESOLUTION,
	COMBAT_RESOLUTION,
	DRIFT_CALCULATION,
	STATUS_ADJUSTMENT,
	MORALE_CHECK,
	MESSAGE_DELIVERY,
	POST_COMBAT,
	END_TURN
}

var current_phase: GamePhase = GamePhase.SETUP
var current_turn: int = 0
var players_ready: Array[bool] = [false, false]
var active_scenario: Dictionary = {}
var selected_scenario: String = ""  # Scenario name selected from menu

# Server-side controllers (only active on server)
var is_server: bool = true  # Set by network manager
var phase_controller: TurnPhaseController = null
var ship_controller: ShipStateController = null
var environment_controller: EnvironmentController = null
var command_validator: CommandValidator = null
var network_sync: NetworkSync = null
var movement_plotting_controller: MovementPlottingController = null
var movement_resolver: MovementResolver = null
var stub_ai: StubAI = null

# State objects (authoritative on server, read-only on client)
var environment: EnvironmentState = null  # Environmental conditions
var ships: Dictionary = {}  # ship_id -> ShipState
var ships_by_player: Dictionary = {0: [], 1: []}  # player_id -> Array[ship_id]

# Shared seeded RNG — seeded from scenario on game start; all controllers share this instance
var rng: RandomNumberGenerator = null

# State history tracking (indexed by turn number)
var environment_history: Array[EnvironmentState] = []  # Historical environment states
var ship_history: Dictionary = {}  # ship_id -> Array[ShipState] for historical ship states

# Legacy accessors for backward compatibility
var wind_direction: int:
	get: return environment.wind_direction if environment else 0
var wind_speed: int:
	get: return environment.wind_speed if environment else 2
var sea_state: int:
	get: return environment.sea_state if environment else 1

func _ready() -> void:
	Trace.trace_log("GameState", "Initialized (server: %s)" % is_server)
	# Initialize server controllers if this is the server
	if is_server:
		_initialize_server_controllers()

func _initialize_server_controllers() -> void:
	"""Initialize server-side controllers - SERVER ONLY"""
	phase_controller = TurnPhaseController.new(self)
	ship_controller = ShipStateController.new(self)
	environment_controller = EnvironmentController.new(self)
	command_validator = CommandValidator.new(self, ship_controller, phase_controller)
	network_sync = NetworkSync.new(self)
	network_sync.is_server = is_server
	movement_plotting_controller = MovementPlottingController.new(self)
	movement_resolver = MovementResolver.new(self)
	stub_ai = StubAI.new(self)

	# Add Node-based controllers to the tree so _ready/_process fire and they're freed on exit
	add_child(phase_controller)
	add_child(ship_controller)
	add_child(environment_controller)
	add_child(command_validator)
	add_child(network_sync)
	add_child(movement_plotting_controller)

	# Connect signals
	phase_controller.phase_changed.connect(_on_server_phase_changed)
	phase_controller.turn_changed.connect(_on_server_turn_changed)

	# Connect movement plotting signals
	movement_plotting_controller.session_submitted.connect(_on_movement_submitted)

	# Connect state change signals to trigger sync
	if is_server:
		phase_changed.connect(_on_state_changed_broadcast)
		turn_changed.connect(_on_state_changed_broadcast)
		if ship_controller:
			ship_controller.ship_state_changed.connect(_on_state_changed_broadcast)

	Trace.trace_log("GameState", "Server controllers initialized")

func start_new_game(scenario_data: Dictionary) -> void:
	"""Initialize a new game with scenario data - SERVER ONLY"""
	if not is_server:
		push_error("GameState: Cannot start game on client")
		return

	active_scenario = scenario_data

	# Seed the shared RNG from scenario (default to 0 if no seed provided)
	var seed_value: int = scenario_data.get("seed", 0)
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	Trace.trace_log("GameState", "RNG seeded", seed_value)

	# Clear any existing state history
	clear_state_history()

	# Initialize environment from scenario
	environment = EnvironmentState.new()
	environment.initialize_from_scenario(scenario_data)

	Trace.trace_log("GameState", "Game started - Turn: 1, Wind: %s (%d), Speed: %s (%d)" % [
		environment.get_wind_direction_name(),
		environment.wind_direction,
		environment.get_wind_speed_name(),
		environment.wind_speed
	])

	# Start the game via phase controller
	if phase_controller:
		phase_controller.start_new_game()

func _on_server_phase_changed(new_phase: int) -> void:
	"""Handle phase change from server controller"""
	current_phase = new_phase as GamePhase
	phase_changed.emit(current_phase)

func _on_server_turn_changed(turn_number: int) -> void:
	"""Handle turn change from server controller"""
	# Save snapshots of previous turn's state before updating to new turn
	# This happens when advancing from turn N to turn N+1
	if turn_number > 1:  # Don't save for turn 1 (no previous state to save)
		var previous_turn = turn_number - 1
		save_environment_snapshot(previous_turn)
		save_all_ships_snapshot(previous_turn)
		Trace.trace_log("GameState", "Saved state snapshots for turn %d" % previous_turn)

	current_turn = turn_number
	turn_changed.emit(current_turn)

func _on_state_changed_broadcast(_arg = null) -> void:
	"""Broadcast state changes to clients when state changes"""
	if is_server and network_sync:
		# Note: This gets called frequently. In production, you might want to
		# debounce this or use delta syncing for efficiency
		pass  # network_sync.broadcast_state() called automatically via timer


func _on_movement_submitted(session_id: String, ship_id: String, final_path: Array) -> void:
	"""Handle movement submission from plotting controller
	final_path is Array[MovementTypes.PlotStep]"""
	Trace.trace_log("GameState", "Movement submitted for ship %s (%d hexes)" % [ship_id, final_path.size()])
	# The movement is already applied to ship_state.plotted_actions by the controller
	# Additional handling (e.g., checking if all ships have submitted) can go here


func get_phase_name() -> String:
	"""Get human-readable phase name"""
	return GamePhase.keys()[current_phase]

## Ship Management Functions

func add_ship(ship_state: ShipState) -> void:
	"""Add a ship to game state"""
	ships[ship_state.ship_id] = ship_state

	# Track by player
	if not ships_by_player.has(ship_state.player_id):
		ships_by_player[ship_state.player_id] = []
	ships_by_player[ship_state.player_id].append(ship_state.ship_id)

	Trace.trace_log("GameState", "Added ship %s (player %d)" % [ship_state.ship_id, ship_state.player_id])

func remove_ship(ship_id: String) -> void:
	"""Remove a ship from game state"""
	if not ships.has(ship_id):
		return

	var ship_state = ships[ship_id]
	var player_id = ship_state.player_id

	ships.erase(ship_id)

	if ships_by_player.has(player_id):
		ships_by_player[player_id].erase(ship_id)

	Trace.trace_log("GameState", "Removed ship %s" % ship_id)

func get_ship(ship_id: String) -> ShipState:
	"""Get ship state by ID"""
	return ships.get(ship_id)

func get_player_ships(player_id: int) -> Array[ShipState]:
	"""Get all ships for a player"""
	var result: Array[ShipState] = []
	if ships_by_player.has(player_id):
		for ship_id in ships_by_player[player_id]:
			if ships.has(ship_id):
				result.append(ships[ship_id])
	return result

func get_all_ships() -> Array[ShipState]:
	"""Get all ships in game"""
	var result: Array[ShipState] = []
	for ship_state in ships.values():
		result.append(ship_state)
	return result

func clear_ships() -> void:
	"""Clear all ships (for new game)"""
	ships.clear()
	ships_by_player.clear()

## State History Management

func save_environment_snapshot(turn_number: int) -> void:
	"""Save a snapshot of the current environment state for the given turn"""
	if not environment:
		push_warning("GameState: Cannot save environment snapshot - environment is null")
		return

	# Create deep copy of current environment state
	var snapshot = environment.duplicate(true)

	# Ensure array has space for this turn
	while environment_history.size() <= turn_number:
		environment_history.append(null)

	environment_history[turn_number] = snapshot
	Trace.trace_log("GameState", "Saved environment snapshot for turn %d" % turn_number)

func get_environment_at_turn(turn_number: int) -> EnvironmentState:
	"""Get environment state from a specific turn (returns null if not found)"""
	if turn_number >= 0 and turn_number < environment_history.size():
		return environment_history[turn_number]
	return null

func get_previous_environment(turns_ago: int = 1) -> EnvironmentState:
	"""Get environment from N turns ago relative to current turn"""
	var target_turn = current_turn - turns_ago
	return get_environment_at_turn(target_turn)

func save_ship_snapshot(ship_id: String, turn_number: int) -> void:
	"""Save a snapshot of a specific ship's state for the given turn"""
	if not ships.has(ship_id):
		push_warning("GameState: Cannot save ship snapshot - ship %s not found" % ship_id)
		return

	var ship = ships[ship_id]

	# Create deep copy of ship state
	var snapshot = ship.duplicate(true)

	# Initialize ship history array if needed
	if not ship_history.has(ship_id):
		ship_history[ship_id] = []

	var history = ship_history[ship_id]

	# Ensure array has space for this turn
	while history.size() <= turn_number:
		history.append(null)

	history[turn_number] = snapshot
	Trace.trace_log("GameState", "Saved ship %s snapshot for turn %d" % [ship_id, turn_number])

func save_all_ships_snapshot(turn_number: int) -> void:
	"""Save snapshots of all ships for the given turn"""
	for ship_id in ships.keys():
		save_ship_snapshot(ship_id, turn_number)

func get_ship_at_turn(ship_id: String, turn_number: int) -> ShipState:
	"""Get a ship's state from a specific turn (returns null if not found)"""
	if not ship_history.has(ship_id):
		return null

	var history = ship_history[ship_id]
	if turn_number >= 0 and turn_number < history.size():
		return history[turn_number]
	return null

func get_previous_ship_state(ship_id: String, turns_ago: int = 1) -> ShipState:
	"""Get a ship's state from N turns ago relative to current turn"""
	var target_turn = current_turn - turns_ago
	return get_ship_at_turn(ship_id, target_turn)

func clear_state_history() -> void:
	"""Clear all historical state data (for new game)"""
	environment_history.clear()
	ship_history.clear()
	Trace.trace_log("GameState", "Cleared all state history")

## State Serialization (for save/load and multiplayer)

func serialize_full_state() -> Dictionary:
	"""Serialize entire game state for network transmission or save/load"""
	var ship_states = []
	for ship_id in ships.keys():
		ship_states.append(ships[ship_id].serialize())

	# Serialize environment history
	var env_history = []
	for env_state in environment_history:
		if env_state:
			env_history.append(env_state.serialize())
		else:
			env_history.append(null)

	# Serialize ship history
	var ships_history = {}
	for ship_id in ship_history.keys():
		var history_array = []
		for ship_state in ship_history[ship_id]:
			if ship_state:
				history_array.append(ship_state.serialize())
			else:
				history_array.append(null)
		ships_history[ship_id] = history_array

	return {
		"turn": current_turn,
		"phase": current_phase,
		"environment": environment.serialize() if environment else {},
		"ships": ship_states,
		"environment_history": env_history,
		"ship_history": ships_history
	}

func deserialize_full_state(data: Dictionary) -> void:
	"""Load full game state from network or save file"""
	current_turn = data.get("turn", 1)
	current_phase = data.get("phase", GamePhase.SETUP) as GamePhase

	# Load environment
	if data.has("environment"):
		environment = EnvironmentState.deserialize(data.environment)
	else:
		environment = EnvironmentState.new()

	# Load ships
	clear_ships()
	for ship_data in data.get("ships", []):
		var ship_state = ShipState.deserialize(ship_data)
		add_ship(ship_state)

	# Load environment history
	environment_history.clear()
	if data.has("environment_history"):
		for env_data in data.environment_history:
			if env_data:
				environment_history.append(EnvironmentState.deserialize(env_data))
			else:
				environment_history.append(null)

	# Load ship history
	ship_history.clear()
	if data.has("ship_history"):
		for ship_id in data.ship_history.keys():
			var history_array: Array[ShipState] = []
			for ship_data in data.ship_history[ship_id]:
				if ship_data:
					history_array.append(ShipState.deserialize(ship_data))
				else:
					history_array.append(null)
			ship_history[ship_id] = history_array

	Trace.trace_log("GameState", "Loaded state for turn %d, phase %s, %d ships, %d turns of history" % [
		current_turn,
		get_phase_name(),
		ships.size(),
		environment_history.size()
	])

## State Synchronization (for multiplayer)

func sync_from_server(state_data: Dictionary) -> void:
	"""Apply full state update from server - CLIENT ONLY"""
	if is_server:
		push_error("GameState: Cannot sync from server on server")
		return

	# Update phase state
	current_turn = state_data.get("turn", 1)
	current_phase = state_data.get("phase", GamePhase.SETUP) as GamePhase
	players_ready = state_data.get("players_ready", [false, false])

	# Update environment
	if state_data.has("environment"):
		if environment:
			# Update existing environment
			var env_data = state_data.environment
			environment.wind_direction = env_data.get("wind_direction", 0)
			environment.wind_speed = env_data.get("wind_speed", 2)
			environment.wind_speed_change = env_data.get("wind_speed_change", "steady")
			environment.wind_direction_change = env_data.get("wind_direction_change", "none")
			environment.sea_state = env_data.get("sea_state", 1)
			environment.visibility = env_data.get("visibility", "clear")
			environment.time_of_day = env_data.get("time_of_day", "day")
			environment.precipitation = env_data.get("precipitation", "none")
		else:
			environment = EnvironmentState.deserialize(state_data.environment)

	# Update ships
	var ship_ids_to_remove = []
	for ship_id in ships.keys():
		var found = false
		for ship_data in state_data.get("ships", []):
			if ship_data.get("ship_id") == ship_id:
				found = true
				break
		if not found:
			ship_ids_to_remove.append(ship_id)

	# Remove ships that no longer exist
	for ship_id in ship_ids_to_remove:
		remove_ship(ship_id)

	# Update or add ships
	for ship_data in state_data.get("ships", []):
		var ship_id = ship_data.get("ship_id")
		if ships.has(ship_id):
			# Update existing ship
			_update_ship_from_data(ships[ship_id], ship_data)
		else:
			# Add new ship
			var ship_state = ShipState.deserialize(ship_data)
			add_ship(ship_state)

	# Emit sync signal
	state_synced.emit()
	Trace.trace_log("GameState", "State synced from server: Turn %d, Phase %s, %d ships" % [
		current_turn,
		get_phase_name(),
		ships.size()
	])

func _update_ship_from_data(ship: ShipState, data: Dictionary) -> void:
	"""Update ship state from serialized data"""
	var pos = data.get("position", {"q": ship.hex_position.x, "r": ship.hex_position.y})
	ship.hex_position = Vector2i(pos.q, pos.r)
	ship.facing = data.get("facing", ship.facing)
	ship.speed = data.get("speed", ship.speed)
	ship.sail_state = data.get("sail_state", ship.sail_state)
	ship.rigging_quality = data.get("rigging_quality", ship.rigging_quality)
	ship.rigging_damage = data.get("rigging_damage", ship.rigging_damage)
	ship.hull_current_hp = data.get("hull_current_hp", ship.hull_current_hp)
	ship.crew_count = data.get("crew_count", ship.crew_count)
	ship.crew_morale = data.get("crew_morale", ship.crew_morale)
	ship.plotted_actions = data.get("plotted_actions", ship.plotted_actions)
