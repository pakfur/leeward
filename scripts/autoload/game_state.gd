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

# Environment state
var wind_direction: int = 0  # 0-5 representing hex faces
var wind_speed: int = 2  # 0-5
var sea_state: int = 1  # 0-3

func _ready() -> void:
	print("GameState initialized")

func start_new_game(scenario_data: Dictionary) -> void:
	"""Initialize a new game with scenario data"""
	active_scenario = scenario_data
	current_turn = 1
	current_phase = GamePhase.ENVIRONMENT

	# Initialize wind from scenario
	if scenario_data.has("wind_direction"):
		wind_direction = scenario_data.wind_direction
	if scenario_data.has("wind_speed"):
		wind_speed = scenario_data.wind_speed
	if scenario_data.has("sea_state"):
		sea_state = scenario_data.sea_state

	print("Game started - Turn: %d, Wind Dir: %d, Wind Speed: %d" % [current_turn, wind_direction, wind_speed])
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
	# TODO: Update wind direction/speed, perform sail checks
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
