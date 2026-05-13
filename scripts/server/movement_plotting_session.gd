class_name MovementPlottingSession
extends RefCounted
## MovementPlottingSession - Server-side state for a single ship's movement plotting
## Each session tracks the incremental hex selection during PLANNING phase

enum SessionState {
	PLOTTING,      # Active session, player can select hexes
	SUBMITTED,     # Movement plan submitted and locked
	CANCELLED,     # Session cancelled by player
}

# Session identification
var session_id: String = ""
var ship_id: String = ""
var player_id: int = 0

# Session state
var state: SessionState = SessionState.PLOTTING
var version: int = 0  # Increments with each hex selection

# Movement data
var origin_hex: Vector2i = Vector2i.ZERO
var origin_facing: int = 0
var plotted_path: Array[MovementTypes.PlotStep] = []
var valid_next_hexes: MovementTypes.ValidNextHexes = null

# Movement tracking for rule enforcement
var pivots_used: int = 0
var forward_hexes_since_last_pivot: int = 0
var last_pivot_direction: MovementTypes.MoveType = MovementTypes.MoveType.NONE
var is_tacking_attempt: bool = false
var remaining_ma: int = 0

# Submission state
var can_submit: bool = true

# Timing
var created_at: float = 0.0  # Unix timestamp
var last_activity_at: float = 0.0

# Idempotency tracking
var last_request_id: String = ""
var last_response: MovementTypes.PlottingResponse = null


func _init() -> void:
	session_id = _generate_uuid()
	created_at = Time.get_unix_time_from_system()
	last_activity_at = created_at
	plotted_path = []
	valid_next_hexes = MovementTypes.ValidNextHexes.new()


func initialize(p_ship_id: String, p_player_id: int, p_origin_hex: Vector2i, p_origin_facing: int) -> void:
	"""Initialize session for a ship at its current position"""
	ship_id = p_ship_id
	player_id = p_player_id
	origin_hex = p_origin_hex
	origin_facing = p_origin_facing
	version = 0
	state = SessionState.PLOTTING
	plotted_path.clear()
	pivots_used = 0
	forward_hexes_since_last_pivot = 0
	last_pivot_direction = MovementTypes.MoveType.NONE
	is_tacking_attempt = false
	remaining_ma = 0
	_touch()


func select_hex(hex: Vector2i, new_facing: int, new_valid_hexes: MovementTypes.ValidNextHexes, new_can_submit: bool, move_type: MovementTypes.MoveType = MovementTypes.MoveType.NONE, p_remaining_ma: int = -1) -> void:
	"""Add a hex to the plotted path (called after validation)"""
	var step = MovementTypes.PlotStep.new(hex, new_facing, move_type)
	plotted_path.append(step)
	version += 1
	valid_next_hexes = new_valid_hexes
	can_submit = new_can_submit
	if p_remaining_ma >= 0:
		remaining_ma = p_remaining_ma

	if move_type == MovementTypes.MoveType.FORWARD:
		forward_hexes_since_last_pivot += 1
	elif move_type == MovementTypes.MoveType.PORT or move_type == MovementTypes.MoveType.STARBOARD:
		pivots_used += 1
		forward_hexes_since_last_pivot = 0
		last_pivot_direction = move_type
	_touch()


func undo_to_version(target_version: int, new_valid_hexes: MovementTypes.ValidNextHexes, new_can_submit: bool, p_remaining_ma: int = -1) -> void:
	"""Revert path to a previous version"""
	if target_version < 0 or target_version > version:
		push_error("MovementPlottingSession: Invalid revert_to_version %d (current: %d)" % [target_version, version])
		return

	while plotted_path.size() > target_version:
		plotted_path.pop_back()

	version = target_version
	valid_next_hexes = new_valid_hexes
	can_submit = new_can_submit
	if p_remaining_ma >= 0:
		remaining_ma = p_remaining_ma
	_recompute_tracking()
	_touch()


func submit() -> void:
	"""Mark session as submitted"""
	state = SessionState.SUBMITTED
	_touch()


func cancel() -> void:
	"""Mark session as cancelled"""
	state = SessionState.CANCELLED
	_touch()


func is_active() -> bool:
	"""Check if session is still active for plotting"""
	return state == SessionState.PLOTTING


func is_terminated() -> bool:
	"""Check if session has ended (submitted or cancelled)"""
	return state != SessionState.PLOTTING


func get_current_hex() -> Vector2i:
	"""Get the current position (last hex in path, or origin if empty)"""
	if plotted_path.is_empty():
		return origin_hex
	return plotted_path.back().hex


func get_current_facing() -> int:
	"""Get the current facing (last facing in path, or origin facing if empty)"""
	if plotted_path.is_empty():
		return origin_facing
	return plotted_path.back().facing


func get_path_copy() -> Array[MovementTypes.PlotStep]:
	"""Get a copy of the plotted path"""
	var copy: Array[MovementTypes.PlotStep] = []
	for step in plotted_path:
		copy.append(MovementTypes.PlotStep.new(step.hex, step.facing, step.move_type))
	return copy


func _recompute_tracking() -> void:
	"""Recompute tracking fields from the current plotted_path after an undo."""
	pivots_used = 0
	forward_hexes_since_last_pivot = 0
	last_pivot_direction = MovementTypes.MoveType.NONE
	is_tacking_attempt = false
	for step in plotted_path:
		if step.move_type == MovementTypes.MoveType.FORWARD:
			forward_hexes_since_last_pivot += 1
		elif step.move_type == MovementTypes.MoveType.PORT or step.move_type == MovementTypes.MoveType.STARBOARD:
			pivots_used += 1
			forward_hexes_since_last_pivot = 0
			last_pivot_direction = step.move_type


func cache_response(request_id: String, response: MovementTypes.PlottingResponse) -> void:
	"""Cache the last response for idempotency"""
	last_request_id = request_id
	last_response = response


func get_cached_response(request_id: String) -> MovementTypes.PlottingResponse:
	"""Get cached response if request_id matches"""
	if request_id == last_request_id:
		return last_response
	return null


func serialize() -> Dictionary:
	"""Serialize session state for debugging or network sync"""
	var path_data: Array = []
	for step in plotted_path:
		path_data.append(step.to_dict())

	return {
		"session_id": session_id,
		"ship_id": ship_id,
		"player_id": player_id,
		"state": SessionState.keys()[state],
		"version": version,
		"origin_hex": {"q": origin_hex.x, "r": origin_hex.y},
		"origin_facing": origin_facing,
		"plotted_path": path_data,
		"valid_next_hexes": valid_next_hexes.to_dict() if valid_next_hexes else {},
		"can_submit": can_submit,
		"pivots_used": pivots_used,
		"forward_hexes_since_last_pivot": forward_hexes_since_last_pivot,
		"last_pivot_direction": last_pivot_direction,
		"is_tacking_attempt": is_tacking_attempt,
		"remaining_ma": remaining_ma
	}


func _touch() -> void:
	"""Update last activity timestamp"""
	last_activity_at = Time.get_unix_time_from_system()


func _generate_uuid() -> String:
	var chars = "0123456789abcdef"
	var uuid = ""
	# Uses OS entropy, not game_state.rng — session IDs must not consume deterministic RNG rolls
	var local_rng = RandomNumberGenerator.new()
	local_rng.randomize()
	for i in range(32):
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		uuid += chars[local_rng.randi() % 16]
	return uuid
