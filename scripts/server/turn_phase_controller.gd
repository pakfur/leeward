class_name TurnPhaseController
extends Node
## TurnPhaseController - Server-authoritative turn phase management
## Handles all phase transitions and validates player readiness

signal phase_changed(new_phase: int)
signal turn_changed(turn_number: int)
signal resolution_log_ready(log: MovementTypes.ResolutionLog)
signal fire_declaration_requested()
signal combat_log_ready(log: PhaseEvents.PhaseLog)

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

## Steps inside COMBAT_RESOLUTION: orders are declared (hidden, simultaneous), then resolved.
enum CombatStep { NONE, DECLARE, RESOLVE }

var current_phase: GamePhase = GamePhase.SETUP
var current_turn: int = 0
var players_ready: Array[bool] = [false, false]
var is_server: bool = true  # Set to true on server, false on clients
var _pending_resolution_log: MovementTypes.ResolutionLog = null
var combat_step: CombatStep = CombatStep.NONE
var _fire_orders: Array = [[], []]  # per player: Array[GunneryTypes.FireOrder]
var _fire_ready: Array[bool] = [false, false]

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

	Trace.trace_log("TurnPhase", "Game started - Turn: %d" % current_turn)
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
	Trace.trace_log("TurnPhase", "Phase: ENVIRONMENT")

	# Update environment (using controller for RNG management and shader updates)
	if game_state.environment:
		if game_state.environment_controller:
			# Use controller which manages RNG and updates shader
			game_state.environment_controller.tick_environment(game_state.environment, current_turn)
		else:
			push_warning("TurnPhaseController: No environment_controller available for tick")

		Trace.trace_log("TurnPhase", "Environment: Wind %s (%d), Speed %s (%d), Sea %s (%d)" % [
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
	Trace.trace_log("TurnPhase", "Phase: PLANNING - Players plot their actions")

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
	Trace.trace_log("TurnPhase", "Player %d submitted plan" % player_id)

	# Check if all players are ready
	if players_ready.all(func(is_ready): return is_ready):
		Trace.trace_log("TurnPhase", "All players ready, advancing phase")
		advance_phase()

	return true

func _enter_movement_resolution_phase() -> void:
	"""SERVER ONLY: Enter movement resolution phase.
	Runs the resolver and emits resolution_log_ready. Does NOT auto-advance.
	The view layer plays back the log and calls on_playback_completed() when done."""
	current_phase = GamePhase.MOVEMENT_RESOLUTION
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: MOVEMENT_RESOLUTION")

	# Plotted sail changes start now, before movement resolution clears the plots
	if game_state.sail_controller:
		game_state.sail_controller.begin_plotted_changes()

	if game_state.movement_resolver and game_state.environment:
		var all_ships = game_state.get_all_ships()
		@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
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
	"""SERVER ONLY: Enter combat resolution phase.
	Skipped entirely when no ship has a legal shot. Otherwise waits in DECLARE for both
	players' fire orders, then resolves them (RESOLVE) and waits for the view to finish
	playback via on_combat_playback_completed()."""
	current_phase = GamePhase.COMBAT_RESOLUTION
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: COMBAT_RESOLUTION")

	var calculator = game_state.gunnery_calculator
	if calculator == null or not calculator.any_eligible_shot():
		combat_step = CombatStep.NONE
		advance_phase()
		return

	combat_step = CombatStep.DECLARE
	_fire_orders = [[], []]
	_fire_ready = [false, false]
	fire_declaration_requested.emit()
	if game_state.stub_ai:
		game_state.stub_ai.submit_fire_orders()

func player_submit_fire_orders(player_id: int, orders: Array) -> String:
	"""SERVER ONLY: Validate and store a player's fire orders (Array of FireOrder dictionaries).
	Returns "" on success, otherwise the reason it was rejected (nothing changes on rejection).
	A later valid submission replaces an earlier one until both players are ready."""
	if not is_server:
		push_error("TurnPhaseController: Cannot submit fire orders on client")
		return "fire orders can only be submitted on the server"
	if current_phase != GamePhase.COMBAT_RESOLUTION or combat_step != CombatStep.DECLARE:
		return "fire orders are not being accepted now"
	if player_id < 0 or player_id >= _fire_ready.size():
		return "invalid player %d" % player_id

	var typed: Array[GunneryTypes.FireOrder] = []
	for entry in orders:
		if not entry is Dictionary:
			return "malformed fire order"
		typed.append(GunneryTypes.FireOrder.from_dict(entry))

	var reason: String = game_state.gunnery_calculator.validate_orders(player_id, typed)
	if reason != "":
		return reason

	_fire_orders[player_id] = typed
	_fire_ready[player_id] = true
	Trace.trace_log("TurnPhase", "Player %d declared %d fire orders" % [player_id, typed.size()])

	if _fire_ready.all(func(is_ready): return is_ready):
		_resolve_combat()
	return ""

func _resolve_combat() -> void:
	"""SERVER ONLY: Resolve all declared fire simultaneously, then wait for playback."""
	combat_step = CombatStep.RESOLVE
	var all_orders: Array[GunneryTypes.FireOrder] = []
	for player_orders in _fire_orders:
		all_orders.append_array(player_orders)
	game_state.gunnery_resolver.resolve(all_orders, GamePhase.COMBAT_RESOLUTION)
	Trace.trace_log("TurnPhase", "COMBAT_RESOLUTION resolved", {"orders": all_orders.size()})
	combat_log_ready.emit(game_state.turn_log)

func on_combat_playback_completed() -> void:
	"""Called by the view layer after combat playback finishes. Advances past combat."""
	if current_phase != GamePhase.COMBAT_RESOLUTION or combat_step != CombatStep.RESOLVE:
		push_error("TurnPhaseController: on_combat_playback_completed called outside combat RESOLVE")
		return
	combat_step = CombatStep.NONE
	advance_phase()

func _enter_drift_calculation_phase() -> void:
	"""SERVER ONLY: Enter drift calculation phase"""
	current_phase = GamePhase.DRIFT_CALCULATION
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: DRIFT_CALCULATION")
	game_state.drift_resolver.resolve(GamePhase.DRIFT_CALCULATION)
	advance_phase()

func _enter_status_adjustment_phase() -> void:
	"""SERVER ONLY: Enter status adjustment phase"""
	current_phase = GamePhase.STATUS_ADJUSTMENT
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: STATUS_ADJUSTMENT")
	if game_state.fouling_controller:
		game_state.fouling_controller.resolve_unfouling(current_phase)
	if game_state.sail_controller:
		game_state.sail_controller.advance_changes(current_phase)
	# TODO: Resolve explosions, sinking, repairs, crew reorg, anchors
	advance_phase()

func _enter_morale_check_phase() -> void:
	"""SERVER ONLY: Enter morale check phase"""
	current_phase = GamePhase.MORALE_CHECK
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: MORALE_CHECK")
	# TODO: Update crew morale
	advance_phase()

func _enter_message_delivery_phase() -> void:
	"""SERVER ONLY: Enter message delivery phase"""
	current_phase = GamePhase.MESSAGE_DELIVERY
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: MESSAGE_DELIVERY")
	# TODO: Deliver flag messages
	advance_phase()

func _enter_post_combat_phase() -> void:
	"""SERVER ONLY: Enter post combat phase"""
	current_phase = GamePhase.POST_COMBAT
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: POST_COMBAT - Player interaction required")
	# TODO: Allow grappling/ungrappling, unfouling, fire fighting
	# Server waits for manual advance

func _enter_end_turn_phase() -> void:
	"""SERVER ONLY: Enter end turn phase"""
	current_phase = GamePhase.END_TURN
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: END_TURN")
	# TODO: Check victory/defeat conditions

func _start_new_turn() -> void:
	"""SERVER ONLY: Start a new turn"""
	current_turn += 1
	turn_changed.emit(current_turn)
	Trace.trace_log("TurnPhase", "=== Turn %d ===" % current_turn)
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
		"players_ready": players_ready,
		"combat_step": combat_step
	}

func apply_phase_state(data: Dictionary) -> void:
	"""Apply phase state from server (CLIENT ONLY)"""
	current_phase = data.get("current_phase", GamePhase.SETUP)
	current_turn = data.get("current_turn", 0)
	players_ready = data.get("players_ready", [false, false])
	combat_step = data.get("combat_step", CombatStep.NONE)

	# Emit signals so UI can update
	phase_changed.emit(current_phase)
