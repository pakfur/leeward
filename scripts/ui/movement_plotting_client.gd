class_name MovementPlottingClient
extends RefCounted
## MovementPlottingClient - Client-side orchestrator for the movement plotting flow
##
## Manages the request/response cycle with MovementPlottingController.
## Currently calls handle_*() directly for single-player; will use RPC for multiplayer.

signal plotting_started(ship_id: String, valid_hexes: Array, remaining_ma: int)
signal hex_selected(plotted_path: Array, valid_hexes: Array, can_submit: bool, remaining_ma: int)
signal undo_complete(plotted_path: Array, valid_hexes: Array, can_submit: bool, remaining_ma: int)
signal plotting_cancelled(ship_id: String)
signal movement_submitted(ship_id: String, final_path: Array)
signal plotting_error(error_code: String, message: String)

var _controller: MovementPlottingController = null
var _request_counter: int = 0

# Session state
var active_session_id: String = ""
var active_ship_id: String = ""
var session_version: int = 0
var valid_next_hexes: MovementTypes.ValidNextHexes = null
var plotted_path: Array = []  # Array[MovementTypes.PlotStep]
var can_submit: bool = false
var remaining_ma: int = 0


func _init(controller: MovementPlottingController) -> void:
	_controller = controller


func start_plotting(player_id: int, ship_id: String) -> void:
	var request_id = _next_request_id()
	var response = _controller.handle_start_plotting(player_id, ship_id, request_id)

	if response is MovementTypes.PlottingErrorResponse:
		plotting_error.emit(response.error_code, response.message)
		return

	var r = response as MovementTypes.PlottingStartedResponse
	active_session_id = r.session_id
	active_ship_id = r.ship_id
	session_version = r.session_version
	valid_next_hexes = r.valid_next_hexes
	plotted_path = []
	can_submit = r.can_submit
	remaining_ma = r.remaining_ma

	plotting_started.emit(ship_id, valid_next_hexes, remaining_ma)


func select_hex(hex: Vector2i) -> void:
	if active_session_id.is_empty():
		plotting_error.emit("NO_SESSION", "No active plotting session")
		return

	var request_id = _next_request_id()
	var response = _controller.handle_select_hex(active_session_id, session_version, hex, request_id)

	if response is MovementTypes.PlottingErrorResponse:
		plotting_error.emit(response.error_code, response.message)
		return

	var r = response as MovementTypes.HexSelectedResponse
	session_version = r.session_version
	plotted_path = Array(r.plotted_path)
	valid_next_hexes = r.valid_next_hexes
	can_submit = r.can_submit
	remaining_ma = r.remaining_ma

	hex_selected.emit(plotted_path, valid_next_hexes, can_submit, remaining_ma)


func undo() -> void:
	if active_session_id.is_empty() or session_version <= 0:
		return

	var request_id = _next_request_id()
	var response = _controller.handle_undo(active_session_id, session_version, session_version - 1, request_id)

	if response is MovementTypes.PlottingErrorResponse:
		plotting_error.emit(response.error_code, response.message)
		return

	var r = response as MovementTypes.UndoCompleteResponse
	session_version = r.session_version
	plotted_path = Array(r.plotted_path)
	valid_next_hexes = r.valid_next_hexes
	can_submit = r.can_submit
	remaining_ma = r.remaining_ma

	undo_complete.emit(plotted_path, valid_next_hexes, can_submit, remaining_ma)


func undo_all() -> void:
	if active_session_id.is_empty() or session_version <= 0:
		return

	var request_id = _next_request_id()
	var response = _controller.handle_undo(active_session_id, session_version, 0, request_id)

	if response is MovementTypes.PlottingErrorResponse:
		plotting_error.emit(response.error_code, response.message)
		return

	var r = response as MovementTypes.UndoCompleteResponse
	session_version = r.session_version
	plotted_path = Array(r.plotted_path)
	valid_next_hexes = r.valid_next_hexes
	can_submit = r.can_submit
	remaining_ma = r.remaining_ma

	undo_complete.emit(plotted_path, valid_next_hexes, can_submit, remaining_ma)


func cancel() -> void:
	if active_session_id.is_empty():
		return

	var ship_id = active_ship_id
	var request_id = _next_request_id()
	_controller.handle_cancel_plotting(active_session_id, request_id)

	_clear_session()
	plotting_cancelled.emit(ship_id)


func submit() -> void:
	if active_session_id.is_empty():
		return

	var request_id = _next_request_id()
	var response = _controller.handle_submit_movement(active_session_id, session_version, request_id)

	if response is MovementTypes.PlottingErrorResponse:
		plotting_error.emit(response.error_code, response.message)
		return

	var r = response as MovementTypes.MovementSubmittedResponse
	var ship_id = r.piece_id
	var final_path = Array(r.final_path)

	_clear_session()
	movement_submitted.emit(ship_id, final_path)


func is_plotting() -> bool:
	return not active_session_id.is_empty()


func is_plotting_ship(ship_id: String) -> bool:
	return active_ship_id == ship_id and is_plotting()


func get_active_ship_id() -> String:
	return active_ship_id


func _clear_session() -> void:
	active_session_id = ""
	active_ship_id = ""
	session_version = 0
	valid_next_hexes = null
	plotted_path = []
	can_submit = false
	remaining_ma = 0


func _next_request_id() -> String:
	_request_counter += 1
	return "req_%d_%d" % [Time.get_ticks_msec(), _request_counter]
