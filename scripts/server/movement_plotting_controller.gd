class_name MovementPlottingController
extends Node
## MovementPlottingController - Server-authoritative movement plotting management
## Implements the movement plotting protocol from docs/02.1-movement-protocol.md
##
## This controller manages all active plotting sessions and handles:
## - START_PLOTTING: Initialize a new session for a ship
## - SELECT_HEX: Add a hex to the plotted path
## - UNDO: Revert to a previous version
## - CANCEL_PLOTTING: Discard the session
## - SUBMIT_MOVEMENT: Finalize the movement plan

signal session_started(session_id: String, ship_id: String)
signal session_updated(session_id: String, version: int)
signal session_submitted(session_id: String, ship_id: String, final_path: Array)  # Array[MovementTypes.PlotStep]
signal session_cancelled(session_id: String, ship_id: String)
signal plotting_error(request_id: String, error_code: String, message: String)

# Reference to game state
var game_state: Node = null
var movement_validator: MovementValidator = null

# Active sessions: session_id -> MovementPlottingSession
var sessions: Dictionary = {}

# Ship to session mapping: ship_id -> session_id
var ship_sessions: Dictionary = {}

func _init(p_game_state: Node = null) -> void:
	game_state = p_game_state if p_game_state else GameState
	movement_validator = MovementValidator.new(game_state)


## ============================================================================
## Protocol Handlers
## ============================================================================

## START_PLOTTING - Initialize a new plotting session for a ship
func handle_start_plotting(player_id: int, ship_id: String, request_id: String) -> MovementTypes.PlottingResponse:
	# Validate request
	if ship_id.is_empty():
		Trace.trace_log(Trace.MOVEMENT_PLOTTING_CATEGORY, "INVALID_REQUEST - ship_id is required")
		return MovementTypes.PlottingErrorResponse.create(request_id, "INVALID_REQUEST", "ship_id is required")

	# Check if ship exists
	var ship_state = game_state.get_ship(ship_id)
	if not ship_state:
		Trace.trace_log(Trace.MOVEMENT_PLOTTING_CATEGORY, "SHIP_NOT_FOUND - Ship %s not found" % ship_id)
		return MovementTypes.PlottingErrorResponse.create(request_id, "SHIP_NOT_FOUND", "Ship %s not found" % ship_id)

	# Check if player owns this ship
	if ship_state.player_id != player_id:
		Trace.trace_log(Trace.MOVEMENT_PLOTTING_CATEGORY, "SHIP_NOT_FOUND - Player %d does not own ship %s" % [player_id, ship_id])
		return MovementTypes.PlottingErrorResponse.create(request_id, "UNAUTHORIZED", "Player %d does not own ship %s" % [player_id, ship_id])

	# Check if ship already has an active session
	if ship_sessions.has(ship_id):
		var existing_session_id = ship_sessions[ship_id]
		var existing_session = sessions.get(existing_session_id)
		if existing_session and existing_session.is_active():
			Trace.trace_log(Trace.MOVEMENT_PLOTTING_CATEGORY, "SHIP_NOT_FOUND - Player %d does not own ship %s" % [player_id, ship_id])
			return MovementTypes.PlottingErrorResponse.create(request_id, "PIECE_UNAVAILABLE", "Ship %s already has an active plotting session" % ship_id)
		else:
			# Clean up stale reference
			ship_sessions.erase(ship_id)
			if existing_session:
				sessions.erase(existing_session_id)

	# Create new session
	var session = MovementPlottingSession.new()
	session.initialize(
		ship_id,
		player_id,
		ship_state.hex_position,
		ship_state.facing
	)
	# Calculate initial valid moves
	var empty_path: Array[MovementTypes.PlotStep] = []
	var valid_moves = movement_validator.calculate_valid_moves(
		ship_state,
		ship_state.hex_position,
		ship_state.facing,
		empty_path
	)
	session.valid_next_hexes = valid_moves.valid_hexes
	session.can_submit = valid_moves.can_submit

	# Store session
	sessions[session.session_id] = session
	ship_sessions[ship_id] = session.session_id

	# Update session tacking state
	session.is_tacking_attempt = valid_moves.is_tacking_attempt

	# Build response
	var response = MovementTypes.PlottingStartedResponse.new()
	response.request_id = request_id
	response.session_id = session.session_id
	response.session_version = session.version
	response.ship_id = ship_id
	response.origin_hex = session.origin_hex
	response.valid_next_hexes = session.valid_next_hexes
	response.can_submit = session.can_submit
	response.remaining_ma = valid_moves.remaining_ma
	response.is_tacking_attempt = session.is_tacking_attempt

	session.cache_response(request_id, response)
	session_started.emit(session.session_id, ship_id)

	print("[MovementPlotting] Session started: %s for ship %s" % [session.session_id, ship_id])
	Trace.trace_log("MovementPlotting", "START_PLOTTING: Session Started", response.to_dict())
	return response


## SELECT_HEX - Add a hex to the plotted path
func handle_select_hex(session_id: String, expected_version: int, selected_hex: Vector2i, request_id: String) -> MovementTypes.PlottingResponse:
	# Get session
	var session = _get_session(session_id)
	if not session:
		return MovementTypes.PlottingErrorResponse.create(request_id, "SESSION_NOT_FOUND", "Session %s not found" % session_id)

	# Check session state
	if session.is_terminated():
		return MovementTypes.PlottingErrorResponse.create(request_id, "SESSION_TERMINATED", "Session has already ended")

	# Version validation with idempotency check
	var version_result = _validate_version(session, expected_version, request_id)
	if version_result != null:
		return version_result

	# Validate hex selection
	var ship_state = game_state.get_ship(session.ship_id)
	var validation = movement_validator.validate_hex_selection(
		ship_state,
		session.get_current_hex(),
		session.get_current_facing(),
		selected_hex,
		session.plotted_path
	)

	if not validation.is_valid:
		return MovementTypes.PlottingErrorResponse.create(
			request_id,
			validation.error_code,
			validation.error_message
		)

	# Calculate new valid moves from the selected position
	var move_type = validation.metadata.move_type if validation.metadata else MovementTypes.MoveType.NONE
	var new_path = session.get_path_copy()
	new_path.append(MovementTypes.PlotStep.new(selected_hex, validation.new_facing, move_type))

	var new_valid_moves = movement_validator.calculate_valid_moves(
		ship_state,
		selected_hex,
		validation.new_facing,
		new_path
	)

	# Apply the selection
	session.select_hex(
		selected_hex,
		validation.new_facing,
		new_valid_moves.valid_hexes,
		new_valid_moves.can_submit,
		move_type,
		new_valid_moves.remaining_ma
	)
	session.is_tacking_attempt = new_valid_moves.is_tacking_attempt

	# Build response
	var response = MovementTypes.HexSelectedResponse.new()
	response.request_id = request_id
	response.session_id = session_id
	response.session_version = session.version
	response.plotted_path = session.get_path_copy()
	response.valid_next_hexes = session.valid_next_hexes
	response.can_submit = session.can_submit
	response.remaining_ma = new_valid_moves.remaining_ma
	response.is_tacking_attempt = session.is_tacking_attempt

	session.cache_response(request_id, response)
	session_updated.emit(session_id, session.version)

	print("[MovementPlotting] Hex selected: session %s, version %d, hex (%d, %d)" % [
		session_id, session.version, selected_hex.x, selected_hex.y
	])
	Trace.trace_log("MovementPlotting", "SELECT_HEX: Add a Hex [selected_hex: %s]" % [selected_hex], response.to_dict())
	return response


## UNDO - Revert the path to a previous version
func handle_undo(session_id: String, expected_version: int, revert_to_version: int, request_id: String) -> MovementTypes.PlottingResponse:
	# Get session
	var session = _get_session(session_id)
	if not session:
		return MovementTypes.PlottingErrorResponse.create(request_id, "SESSION_NOT_FOUND", "Session %s not found" % session_id)

	# Check session state
	if session.is_terminated():
		return MovementTypes.PlottingErrorResponse.create(request_id, "SESSION_TERMINATED", "Session has already ended")

	# Validate expected version
	if expected_version != session.version:
		var error = MovementTypes.PlottingErrorResponse.create(
			request_id,
			"VERSION_CONFLICT",
			"Expected version %d but session is at version %d" % [expected_version, session.version],
			session.version
		)
		return error

	# Validate revert_to_version
	if revert_to_version < 0 or revert_to_version >= expected_version:
		return MovementTypes.PlottingErrorResponse.create(
			request_id,
			"INVALID_VERSION",
			"revert_to_version must be in range [0, %d)" % expected_version
		)

	# Calculate position and facing after undo
	var new_hex: Vector2i
	var new_facing: int

	if revert_to_version == 0:
		new_hex = session.origin_hex
		new_facing = session.origin_facing
	else:
		var target_step = session.plotted_path[revert_to_version - 1]
		new_hex = target_step.hex
		new_facing = target_step.facing

	# Calculate valid moves from the reverted position
	var ship_state = game_state.get_ship(session.ship_id)
	var path_after_undo: Array[MovementTypes.PlotStep] = []
	for i in range(revert_to_version):
		path_after_undo.append(session.plotted_path[i])

	var new_valid_moves = movement_validator.calculate_valid_moves(
		ship_state,
		new_hex,
		new_facing,
		path_after_undo
	)

	# Apply the undo
	session.undo_to_version(
		revert_to_version,
		new_valid_moves.valid_hexes,
		new_valid_moves.can_submit,
		new_valid_moves.remaining_ma
	)
	session.is_tacking_attempt = new_valid_moves.is_tacking_attempt

	# Build response
	var response = MovementTypes.UndoCompleteResponse.new()
	response.request_id = request_id
	response.session_id = session_id
	response.session_version = session.version
	response.plotted_path = session.get_path_copy()
	response.valid_next_hexes = session.valid_next_hexes
	response.can_submit = session.can_submit
	response.remaining_ma = new_valid_moves.remaining_ma
	response.is_tacking_attempt = session.is_tacking_attempt

	session.cache_response(request_id, response)
	session_updated.emit(session_id, session.version)

	print("[MovementPlotting] Undo: session %s, reverted to version %d" % [session_id, session.version])
	Trace.trace_log("MovementPlotting", "UNDO: Revert [revert_to_version: %d]" % [revert_to_version], response.to_dict())
	return response


## CANCEL_PLOTTING - Discard the session entirely
func handle_cancel_plotting(session_id: String, request_id: String) -> MovementTypes.PlottingResponse:
	# Get session (idempotent - return success even if already cancelled/expired)
	var session = sessions.get(session_id)

	var response = MovementTypes.PlottingCancelledResponse.new()
	response.request_id = request_id
	response.session_id = session_id

	if session:
		var ship_id = session.ship_id
		session.cancel()
		_cleanup_session(session_id)
		session_cancelled.emit(session_id, ship_id)
		print("[MovementPlotting] Session cancelled: %s" % session_id)
	else:
		# Already gone - that's fine, return success
		print("[MovementPlotting] Cancel requested for unknown/expired session: %s" % session_id)
	Trace.trace_log("MovementPlotting", "CANCEL_PLOTTING: Cancel", response.to_dict())
	return response


## SUBMIT_MOVEMENT - Finalize the plotted path
func handle_submit_movement(session_id: String, expected_version: int, request_id: String) -> MovementTypes.PlottingResponse:
	# Get session
	var session = _get_session(session_id)
	if not session:
		return MovementTypes.PlottingErrorResponse.create(request_id, "SESSION_NOT_FOUND", "Session %s not found" % session_id)

	# Check session state
	if session.is_terminated():
		return MovementTypes.PlottingErrorResponse.create(request_id, "SESSION_TERMINATED", "Session has already ended")

	# Validate expected version
	if expected_version != session.version:
		var error = MovementTypes.PlottingErrorResponse.create(
			request_id,
			"VERSION_CONFLICT",
			"Expected version %d but session is at version %d" % [expected_version, session.version],
			session.version
		)
		return error

	# Check if submission is allowed
	if not session.can_submit:
		return MovementTypes.PlottingErrorResponse.create(request_id, "CANNOT_SUBMIT", "Current path state does not allow submission")

	# Final validation
	var ship_state = game_state.get_ship(session.ship_id)
	var submission_check = movement_validator.validate_submission(
		ship_state,
		session.plotted_path
	)

	if not submission_check.can_submit:
		return MovementTypes.PlottingErrorResponse.create(
			request_id,
			submission_check.error_code,
			submission_check.error_message
		)

	# Mark session as submitted
	session.submit()

	# Store the plotted movement in the ship state
	var final_path = session.get_path_copy()
	_apply_movement_to_ship(session.ship_id, session.plotted_path)

	# Build response
	var response = MovementTypes.MovementSubmittedResponse.new()
	response.request_id = request_id
	response.session_id = session_id
	response.piece_id = session.ship_id
	response.final_path = final_path
	response.path_version = session.version

	session_submitted.emit(session_id, session.ship_id, final_path)

	# Clean up session
	_cleanup_session(session_id)

	print("[MovementPlotting] Movement submitted: session %s, ship %s, %d hexes" % [
		session_id, session.ship_id, final_path.size()
	])
	Trace.trace_log("MovementPlotting", "SUBMIT_MOVEMENT: Finalize", response.to_dict())
	return response


## ============================================================================
## RPC Methods (for Godot multiplayer)
## ============================================================================

@rpc("any_peer", "call_remote", "reliable")
func rpc_start_plotting(player_id: int, ship_id: String, request_id: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	var response = handle_start_plotting(player_id, ship_id, request_id)
	_send_response_to_peer(sender_id, response)


@rpc("any_peer", "call_remote", "reliable")
func rpc_select_hex(session_id: String, expected_version: int, hex_q: int, hex_r: int, request_id: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	var selected_hex = Vector2i(hex_q, hex_r)
	var response = handle_select_hex(session_id, expected_version, selected_hex, request_id)
	_send_response_to_peer(sender_id, response)


@rpc("any_peer", "call_remote", "reliable")
func rpc_undo(session_id: String, expected_version: int, revert_to_version: int, request_id: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	var response = handle_undo(session_id, expected_version, revert_to_version, request_id)
	_send_response_to_peer(sender_id, response)


@rpc("any_peer", "call_remote", "reliable")
func rpc_cancel_plotting(session_id: String, request_id: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	var response = handle_cancel_plotting(session_id, request_id)
	_send_response_to_peer(sender_id, response)


@rpc("any_peer", "call_remote", "reliable")
func rpc_submit_movement(session_id: String, expected_version: int, request_id: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	var response = handle_submit_movement(session_id, expected_version, request_id)
	_send_response_to_peer(sender_id, response)


@rpc("authority", "call_remote", "reliable")
func rpc_plotting_response(response_json: String) -> void:
	# This is called on clients to receive responses
	# Client-side handling would parse the JSON and dispatch to appropriate handlers
	pass


## ============================================================================
## Helper Methods
## ============================================================================

func _get_session(session_id: String) -> MovementPlottingSession:
	"""Get a session by ID"""
	return sessions.get(session_id)


func _validate_version(session: MovementPlottingSession, expected_version: int, request_id: String) -> MovementTypes.PlottingResponse:
	"""Validate version with idempotency check. Returns null if valid, error response otherwise."""
	var current_version = session.version

	if expected_version == current_version:
		# Normal case - process request
		return null

	if expected_version == current_version - 1:
		# Possible retry - check if this is the same request
		var cached = session.get_cached_response(request_id)
		if cached != null:
			# Same request_id, return cached response
			return cached

		# Different request with old version
		return MovementTypes.PlottingErrorResponse.create(
			request_id,
			"VERSION_CONFLICT",
			"Expected version %d but session is at version %d" % [expected_version, current_version],
			current_version
		)

	if expected_version < current_version - 1:
		return MovementTypes.PlottingErrorResponse.create(
			request_id,
			"VERSION_CONFLICT",
			"Expected version %d but session is at version %d" % [expected_version, current_version],
			current_version
		)

	if expected_version > current_version:
		return MovementTypes.PlottingErrorResponse.create(
			request_id,
			"INVALID_VERSION",
			"Expected version %d is in the future (current: %d)" % [expected_version, current_version],
			current_version
		)

	return null


func _cleanup_session(session_id: String) -> void:
	"""Remove session and clean up references"""
	var session = sessions.get(session_id)
	if session:
		ship_sessions.erase(session.ship_id)
	sessions.erase(session_id)




func _apply_movement_to_ship(ship_id: String, plotted_path: Array[MovementTypes.PlotStep]) -> void:
	"""Store the plotted movement in the ship's state"""
	var ship_state = game_state.get_ship(ship_id)
	if ship_state:
		# Convert plotted_path to movement commands format
		var movement_commands: Array = []
		for step in plotted_path:
			movement_commands.append(step.to_dict())
		ship_state.plotted_actions.movement = movement_commands
		print("[MovementPlotting] Applied movement plan to ship %s: %d steps" % [ship_id, movement_commands.size()])


func _send_response_to_peer(peer_id: int, response: MovementTypes.PlottingResponse) -> void:
	"""Send response back to the requesting peer"""
	var response_json = JSON.stringify(response.to_dict())
	rpc_id(peer_id, "rpc_plotting_response", response_json)


## ============================================================================
## Query Methods
## ============================================================================

func get_session_for_ship(ship_id: String) -> MovementPlottingSession:
	"""Get the active plotting session for a ship, if any"""
	if ship_sessions.has(ship_id):
		return _get_session(ship_sessions[ship_id])
	return null


func has_active_session(ship_id: String) -> bool:
	"""Check if a ship has an active plotting session"""
	var session = get_session_for_ship(ship_id)
	return session != null and session.is_active()


func get_all_active_sessions() -> Array[MovementPlottingSession]:
	"""Get all currently active plotting sessions"""
	var active: Array[MovementPlottingSession] = []
	for session_id in sessions:
		var session = sessions[session_id]
		if session.is_active():
			active.append(session)
	return active


func cancel_all_sessions() -> void:
	"""Cancel all active sessions (e.g., when leaving planning phase)"""
	for session_id in sessions.keys():
		var session = sessions[session_id]
		if session.is_active():
			session.cancel()
			session_cancelled.emit(session_id, session.ship_id)
	sessions.clear()
	ship_sessions.clear()
	print("[MovementPlotting] All sessions cancelled")
