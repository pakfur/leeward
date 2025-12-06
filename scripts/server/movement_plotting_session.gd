class_name MovementPlottingSession
extends RefCounted
## MovementPlottingSession - Server-side state for a single ship's movement plotting
## Each session tracks the incremental hex selection during PLANNING phase

enum SessionState {
	PLOTTING,      # Active session, player can select hexes
	SUBMITTED,     # Movement plan submitted and locked
	CANCELLED,     # Session cancelled by player
	EXPIRED        # Session timed out
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
var valid_next_hexes: Array[MovementTypes.ValidMove] = []

# Submission state
var can_submit: bool = true

# Timing
var created_at: float = 0.0  # Unix timestamp
var timeout_ms: int = 300000  # 5 minutes default, configurable
var last_activity_at: float = 0.0

# Idempotency tracking
var last_request_id: String = ""
var last_response: MovementTypes.PlottingResponse = null


func _init() -> void:
	session_id = _generate_uuid()
	created_at = Time.get_unix_time_from_system()
	last_activity_at = created_at
	plotted_path = []
	valid_next_hexes = []


func initialize(p_ship_id: String, p_player_id: int, p_origin_hex: Vector2i, p_origin_facing: int) -> void:
	"""Initialize session for a ship at its current position"""
	ship_id = p_ship_id
	player_id = p_player_id
	origin_hex = p_origin_hex
	origin_facing = p_origin_facing
	version = 0
	state = SessionState.PLOTTING
	plotted_path.clear()
	_touch()


func select_hex(hex: Vector2i, new_facing: int, new_valid_hexes: Array[MovementTypes.ValidMove], new_can_submit: bool) -> void:
	"""Add a hex to the plotted path (called after validation)"""
	var step = MovementTypes.PlotStep.new(hex, new_facing)
	plotted_path.append(step)
	version += 1
	valid_next_hexes = new_valid_hexes
	can_submit = new_can_submit
	_touch()


func undo_to_version(target_version: int, new_valid_hexes: Array[MovementTypes.ValidMove], new_can_submit: bool) -> void:
	"""Revert path to a previous version"""
	if target_version < 0 or target_version > version:
		push_error("MovementPlottingSession: Invalid revert_to_version %d (current: %d)" % [target_version, version])
		return

	# Truncate path to target version
	while plotted_path.size() > target_version:
		plotted_path.pop_back()

	version = target_version
	valid_next_hexes = new_valid_hexes
	can_submit = new_can_submit
	_touch()


func submit() -> void:
	"""Mark session as submitted"""
	state = SessionState.SUBMITTED
	_touch()


func cancel() -> void:
	"""Mark session as cancelled"""
	state = SessionState.CANCELLED
	_touch()


func expire() -> void:
	"""Mark session as expired"""
	state = SessionState.EXPIRED


func is_active() -> bool:
	"""Check if session is still active for plotting"""
	return state == SessionState.PLOTTING


func is_terminated() -> bool:
	"""Check if session has ended (submitted, cancelled, or expired)"""
	return state != SessionState.PLOTTING


func is_expired_by_timeout() -> bool:
	"""Check if session should be expired due to timeout"""
	var now = Time.get_unix_time_from_system()
	var elapsed_ms = (now - last_activity_at) * 1000
	return elapsed_ms > timeout_ms


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
		copy.append(MovementTypes.PlotStep.new(step.hex, step.facing))
	return copy


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

	var valid_hexes_data: Array = []
	for vh in valid_next_hexes:
		valid_hexes_data.append(vh.to_dict())

	return {
		"session_id": session_id,
		"ship_id": ship_id,
		"player_id": player_id,
		"state": SessionState.keys()[state],
		"version": version,
		"origin_hex": {"q": origin_hex.x, "r": origin_hex.y},
		"origin_facing": origin_facing,
		"plotted_path": path_data,
		"valid_next_hexes": valid_hexes_data,
		"can_submit": can_submit
	}


func _touch() -> void:
	"""Update last activity timestamp"""
	last_activity_at = Time.get_unix_time_from_system()


func _generate_uuid() -> String:
	"""Generate a simple UUID v4"""
	var chars = "0123456789abcdef"
	var uuid = ""
	for i in range(32):
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		uuid += chars[randi() % 16]
	return uuid
