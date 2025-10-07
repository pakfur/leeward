extends Node
## GameState - Manages the overall game state, turn flow, and phase management

signal phase_changed(new_phase: GamePhase)
signal turn_changed(turn_number: int)
signal player_ready(player_id: int)

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

# State objects (authoritative)
var environment: EnvironmentState = null  # Environmental conditions
var ships: Dictionary = {}  # ship_id -> ShipState
var ships_by_player: Dictionary = {0: [], 1: []}  # player_id -> Array[ship_id]

# Legacy accessors for backward compatibility
var wind_direction: int:
	get: return environment.wind_direction if environment else 0
var wind_speed: int:
	get: return environment.wind_speed if environment else 2
var sea_state: int:
	get: return environment.sea_state if environment else 1

func _ready() -> void:
	print("GameState initialized")

func start_new_game(scenario_data: Dictionary) -> void:
	"""Initialize a new game with scenario data"""
	active_scenario = scenario_data
	current_turn = 1
	current_phase = GamePhase.ENVIRONMENT

	# Initialize environment from scenario
	environment = EnvironmentState.new()
	environment.initialize_from_scenario(scenario_data)

	print("Game started - Turn: %d, Wind: %s (%d), Speed: %s (%d)" % [
		current_turn,
		environment.get_wind_direction_name(),
		environment.wind_direction,
		environment.get_wind_speed_name(),
		environment.wind_speed
	])
	advance_phase()

func advance_phase() -> void:
	"""Progress to the next game phase"""
	match current_phase:
		GamePhase.SETUP:
			_enter_environment_phase()
		GamePhase.ENVIRONMENT:
			_enter_planning_phase()
		GamePhase.PLANNING:
			_enter_movement_resolution_phase()
		GamePhase.MOVEMENT_RESOLUTION:
			_enter_combat_resolution_phase()
		GamePhase.COMBAT_RESOLUTION:
			_enter_drift_calculation_phase()
		GamePhase.DRIFT_CALCULATION:
			_enter_status_adjustment_phase()
		GamePhase.STATUS_ADJUSTMENT:
			_enter_morale_check_phase()
		GamePhase.MORALE_CHECK:
			_enter_message_delivery_phase()
		GamePhase.MESSAGE_DELIVERY:
			_enter_post_combat_phase()
		GamePhase.POST_COMBAT:
			_enter_end_turn_phase()
		GamePhase.END_TURN:
			_start_new_turn()

func _enter_environment_phase() -> void:
	current_phase = GamePhase.ENVIRONMENT
	phase_changed.emit(current_phase)
	print("Phase: ENVIRONMENT")

	# Update environment (deterministic based on turn number)
	if environment:
		environment.tick_environment(current_turn)
		print("Environment: Wind %s (%d), Speed %s (%d), Sea %s (%d)" % [
			environment.get_wind_direction_name(),
			environment.wind_direction,
			environment.get_wind_speed_name(),
			environment.wind_speed,
			environment.get_sea_state_name(),
			environment.sea_state
		])

	# TODO: Perform sail checks based on new wind conditions
	advance_phase()

func _enter_planning_phase() -> void:
	current_phase = GamePhase.PLANNING
	phase_changed.emit(current_phase)
	players_ready = [false, false]
	print("Phase: PLANNING - Players plot their actions")
	# Players will call player_submit_plan() when ready

func player_submit_plan(player_id: int) -> void:
	"""Called when a player submits their planned actions"""
	players_ready[player_id] = true
	player_ready.emit(player_id)
	print("Player %d submitted plan" % player_id)

	# Check if all players are ready
	if players_ready.all(func(is_ready): return is_ready):
		print("All players ready, advancing phase")
		advance_phase()

func _enter_movement_resolution_phase() -> void:
	current_phase = GamePhase.MOVEMENT_RESOLUTION
	phase_changed.emit(current_phase)
	print("Phase: MOVEMENT_RESOLUTION")
	# TODO: Resolve movement, collisions, ramming
	advance_phase()

func _enter_combat_resolution_phase() -> void:
	current_phase = GamePhase.COMBAT_RESOLUTION
	phase_changed.emit(current_phase)
	print("Phase: COMBAT_RESOLUTION")
	# TODO: Resolve gunnery, marine fire, boarding
	advance_phase()

func _enter_drift_calculation_phase() -> void:
	current_phase = GamePhase.DRIFT_CALCULATION
	phase_changed.emit(current_phase)
	print("Phase: DRIFT_CALCULATION")
	# TODO: Resolve drifting/fouling
	advance_phase()

func _enter_status_adjustment_phase() -> void:
	current_phase = GamePhase.STATUS_ADJUSTMENT
	phase_changed.emit(current_phase)
	print("Phase: STATUS_ADJUSTMENT")
	# TODO: Resolve explosions, sinking, repairs, crew reorg, anchors
	advance_phase()

func _enter_morale_check_phase() -> void:
	current_phase = GamePhase.MORALE_CHECK
	phase_changed.emit(current_phase)
	print("Phase: MORALE_CHECK")
	# TODO: Update crew morale
	advance_phase()

func _enter_message_delivery_phase() -> void:
	current_phase = GamePhase.MESSAGE_DELIVERY
	phase_changed.emit(current_phase)
	print("Phase: MESSAGE_DELIVERY")
	# TODO: Deliver flag messages
	advance_phase()

func _enter_post_combat_phase() -> void:
	current_phase = GamePhase.POST_COMBAT
	phase_changed.emit(current_phase)
	print("Phase: POST_COMBAT - Player interaction required")
	# TODO: Allow grappling/ungrappling, unfouling, fire fighting
	# Player will manually advance when done

func _enter_end_turn_phase() -> void:
	current_phase = GamePhase.END_TURN
	phase_changed.emit(current_phase)
	print("Phase: END_TURN")
	# TODO: Check victory/defeat conditions

func _start_new_turn() -> void:
	current_turn += 1
	turn_changed.emit(current_turn)
	print("=== Turn %d ===" % current_turn)
	current_phase = GamePhase.ENVIRONMENT
	advance_phase()

func get_phase_name() -> String:
	return GamePhase.keys()[current_phase]

## Ship Management Functions

func add_ship(ship_state: ShipState) -> void:
	"""Add a ship to game state"""
	ships[ship_state.ship_id] = ship_state

	# Track by player
	if not ships_by_player.has(ship_state.player_id):
		ships_by_player[ship_state.player_id] = []
	ships_by_player[ship_state.player_id].append(ship_state.ship_id)

	print("GameState: Added ship %s (player %d)" % [ship_state.ship_id, ship_state.player_id])

func remove_ship(ship_id: String) -> void:
	"""Remove a ship from game state"""
	if not ships.has(ship_id):
		return

	var ship_state = ships[ship_id]
	var player_id = ship_state.player_id

	ships.erase(ship_id)

	if ships_by_player.has(player_id):
		ships_by_player[player_id].erase(ship_id)

	print("GameState: Removed ship %s" % ship_id)

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

## State Serialization (for save/load and multiplayer)

func serialize_full_state() -> Dictionary:
	"""Serialize entire game state for network transmission or save/load"""
	var ship_states = []
	for ship_id in ships.keys():
		ship_states.append(ships[ship_id].serialize())

	return {
		"turn": current_turn,
		"phase": current_phase,
		"environment": environment.serialize() if environment else {},
		"ships": ship_states
	}

func deserialize_full_state(data: Dictionary) -> void:
	"""Load full game state from network or save file"""
	current_turn = data.get("turn", 1)
	current_phase = data.get("phase", GamePhase.SETUP)

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

	print("GameState: Loaded state for turn %d, phase %s, %d ships" % [
		current_turn,
		get_phase_name(),
		ships.size()
	])
