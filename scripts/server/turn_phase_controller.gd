class_name TurnPhaseController
extends Node
## TurnPhaseController - Server-authoritative turn phase management
## Handles all phase transitions and validates player readiness

signal phase_changed(new_phase: int)
signal turn_changed(turn_number: int)
signal resolution_log_ready(log: MovementTypes.ResolutionLog)

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
var is_server: bool = true  # Set to true on server, false on clients
var _pending_resolution_log: MovementTypes.ResolutionLog = null

# Reference to game state (authoritative on server)
var game_state: Node = null

func _init(state: Node = null) -> void:
	game_state = state if state else GameState

func start_new_game() -> void:
	"""Initialize a new game - SERVER ONLY"""
	if not is_server:
		push_error("TurnPhaseController: Cannot start game on client")
		return

	current_turn = 1
	current_phase = GamePhase.SETUP  # Start in SETUP so advance_phase() enters ENVIRONMENT

	print("[Server] Game started - Turn: %d" % current_turn)
	advance_phase()  # This will transition SETUP -> ENVIRONMENT

func advance_phase() -> void:
	"""Progress to the next game phase - SERVER ONLY"""
	if not is_server:
		push_error("TurnPhaseController: Cannot advance phase on client")
		return

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
	"""SERVER ONLY: Enter environment phase and update conditions"""
	current_phase = GamePhase.ENVIRONMENT
	phase_changed.emit(current_phase)
	print("[Server] Phase: ENVIRONMENT")

	# Update environment (using controller for RNG management and shader updates)
	if game_state.environment:
		if game_state.environment_controller:
			# Use controller which manages RNG and updates shader
			game_state.environment_controller.tick_environment(game_state.environment, current_turn)
		else:
			# Fallback to direct update (no RNG, no shader)
			game_state.environment.tick_environment(current_turn)

		print("[Server] Environment: Wind %s (%d), Speed %s (%d), Sea %s (%d)" % [
			game_state.environment.get_wind_direction_name(),
			game_state.environment.wind_direction,
			game_state.environment.get_wind_speed_name(),
			game_state.environment.wind_speed,
			game_state.environment.get_sea_state_name(),
			game_state.environment.sea_state
		])

	# TODO: Perform sail checks based on new wind conditions
	advance_phase()

func _enter_planning_phase() -> void:
	"""SERVER ONLY: Enter planning phase"""
	current_phase = GamePhase.PLANNING
	phase_changed.emit(current_phase)
	players_ready = [false, false]
	print("[Server] Phase: PLANNING - Players plot their actions")

	if game_state.stub_ai:
		game_state.stub_ai.plot_all_ai_ships()

func player_submit_plan(player_id: int) -> bool:
	"""SERVER ONLY: Validate and accept player plan submission"""
	if not is_server:
		push_error("TurnPhaseController: Cannot submit plan on client")
		return false

	if current_phase != GamePhase.PLANNING:
		push_error("[Server] Cannot submit plan outside PLANNING phase")
		return false

	if player_id < 0 or player_id >= players_ready.size():
		push_error("[Server] Invalid player_id: %d" % player_id)
		return false

	players_ready[player_id] = true
	print("[Server] Player %d submitted plan" % player_id)

	# Check if all players are ready
	if players_ready.all(func(is_ready): return is_ready):
		print("[Server] All players ready, advancing phase")
		advance_phase()

	return true

func _enter_movement_resolution_phase() -> void:
	"""SERVER ONLY: Enter movement resolution phase.
	Runs the resolver and emits resolution_log_ready. Does NOT auto-advance.
	The view layer plays back the log and calls on_playback_completed() when done."""
	current_phase = GamePhase.MOVEMENT_RESOLUTION
	phase_changed.emit(current_phase)
	print("[Server] Phase: MOVEMENT_RESOLUTION")

	if game_state.movement_resolver and game_state.environment:
		var all_ships = game_state.get_all_ships()
		var log = game_state.movement_resolver.run(all_ships, game_state.environment)
		_pending_resolution_log = log
		Trace.trace_log("TurnPhase", "MOVEMENT_RESOLUTION resolver done", {"turn": log.turn, "ships": log.ship_results.size()})
		resolution_log_ready.emit(log)
	else:
		advance_phase()


func on_playback_completed() -> void:
	"""Called by the view layer after resolution playback finishes.
	Applies results to state and advances to the next phase."""
	if current_phase != GamePhase.MOVEMENT_RESOLUTION:
		push_error("TurnPhaseController: on_playback_completed called outside MOVEMENT_RESOLUTION")
		return
	if _pending_resolution_log:
		var all_ships = game_state.get_all_ships()
		game_state.movement_resolver.apply_results(_pending_resolution_log, all_ships)
		Trace.trace_log("TurnPhase", "MOVEMENT_RESOLUTION results applied", _pending_resolution_log.to_dict())
		_pending_resolution_log = null
	advance_phase()

func _enter_combat_resolution_phase() -> void:
	"""SERVER ONLY: Enter combat resolution phase"""
	current_phase = GamePhase.COMBAT_RESOLUTION
	phase_changed.emit(current_phase)
	print("[Server] Phase: COMBAT_RESOLUTION")
	# TODO: Resolve gunnery, marine fire, boarding
	advance_phase()

func _enter_drift_calculation_phase() -> void:
	"""SERVER ONLY: Enter drift calculation phase"""
	current_phase = GamePhase.DRIFT_CALCULATION
	phase_changed.emit(current_phase)
	print("[Server] Phase: DRIFT_CALCULATION")
	# TODO: Resolve drifting/fouling
	advance_phase()

func _enter_status_adjustment_phase() -> void:
	"""SERVER ONLY: Enter status adjustment phase"""
	current_phase = GamePhase.STATUS_ADJUSTMENT
	phase_changed.emit(current_phase)
	print("[Server] Phase: STATUS_ADJUSTMENT")
	# TODO: Resolve explosions, sinking, repairs, crew reorg, anchors
	advance_phase()

func _enter_morale_check_phase() -> void:
	"""SERVER ONLY: Enter morale check phase"""
	current_phase = GamePhase.MORALE_CHECK
	phase_changed.emit(current_phase)
	print("[Server] Phase: MORALE_CHECK")
	# TODO: Update crew morale
	advance_phase()

func _enter_message_delivery_phase() -> void:
	"""SERVER ONLY: Enter message delivery phase"""
	current_phase = GamePhase.MESSAGE_DELIVERY
	phase_changed.emit(current_phase)
	print("[Server] Phase: MESSAGE_DELIVERY")
	# TODO: Deliver flag messages
	advance_phase()

func _enter_post_combat_phase() -> void:
	"""SERVER ONLY: Enter post combat phase"""
	current_phase = GamePhase.POST_COMBAT
	phase_changed.emit(current_phase)
	print("[Server] Phase: POST_COMBAT - Player interaction required")
	# TODO: Allow grappling/ungrappling, unfouling, fire fighting
	# Server waits for manual advance

func _enter_end_turn_phase() -> void:
	"""SERVER ONLY: Enter end turn phase"""
	current_phase = GamePhase.END_TURN
	phase_changed.emit(current_phase)
	print("[Server] Phase: END_TURN")
	# TODO: Check victory/defeat conditions

func _start_new_turn() -> void:
	"""SERVER ONLY: Start a new turn"""
	current_turn += 1
	turn_changed.emit(current_turn)
	print("[Server] === Turn %d ===" % current_turn)
	# Directly enter environment phase (we're already inside advance_phase() call chain)
	_enter_environment_phase()

func get_phase_name() -> String:
	"""Get human-readable phase name"""
	return GamePhase.keys()[current_phase]

func serialize_phase_state() -> Dictionary:
	"""Serialize phase state for network sync"""
	return {
		"current_phase": current_phase,
		"current_turn": current_turn,
		"players_ready": players_ready
	}

func apply_phase_state(data: Dictionary) -> void:
	"""Apply phase state from server (CLIENT ONLY)"""
	current_phase = data.get("current_phase", GamePhase.SETUP)
	current_turn = data.get("current_turn", 0)
	players_ready = data.get("players_ready", [false, false])

	# Emit signals so UI can update
	phase_changed.emit(current_phase)
