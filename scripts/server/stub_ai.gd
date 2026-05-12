class_name StubAI
extends RefCounted
## StubAI - Drives the plotting protocol for non-player ships
## Uses the real MovementPlottingController so all AI plots are rule-validated.
##
## Strategies:
##   "hold"    — submit immediately with empty path (default)
##   "forward" — move straight ahead, consuming all available MA

var game_state: Node = null
var _request_counter: int = 0


func _init(p_game_state: Node = null) -> void:
	game_state = p_game_state if p_game_state else GameState


func plot_all_ai_ships() -> void:
	var controller: MovementPlottingController = game_state.movement_plotting_controller
	if not controller:
		push_error("StubAI: No movement_plotting_controller on game_state")
		return

	var ai_ships := _get_ai_ships()
	Trace.trace_log("StubAI", "plot_all_ai_ships: %d AI ships" % ai_ships.size())

	for ship_state in ai_ships:
		var strategy := _get_strategy(ship_state)
		_plot_ship(ship_state, controller, strategy)


func _get_ai_ships() -> Array[ShipState]:
	var result: Array[ShipState] = []
	for ship_state in game_state.get_all_ships():
		if ship_state.player_id != 0:
			result.append(ship_state)
	return result


func _get_strategy(_ship_state: ShipState) -> String:
	return "forward"


func _plot_ship(ship_state: ShipState, controller: MovementPlottingController, strategy: String) -> void:
	var ship_id := ship_state.ship_id
	var player_id := ship_state.player_id

	var start_response := controller.handle_start_plotting(player_id, ship_id, _next_request_id())

	if start_response is MovementTypes.PlottingErrorResponse:
		var err := start_response as MovementTypes.PlottingErrorResponse
		push_error("StubAI: start_plotting failed for %s: %s" % [ship_id, err.message])
		Trace.trace_log("StubAI", "start_plotting FAILED", {"ship_id": ship_id, "error": err.error_code})
		return

	var started := start_response as MovementTypes.PlottingStartedResponse
	var session_id := started.session_id
	var version := started.session_version

	match strategy:
		"forward":
			version = _strategy_forward(ship_state, controller, session_id, version, started)
		"hold":
			pass

	var submit_response := controller.handle_submit_movement(session_id, version, _next_request_id())

	if submit_response is MovementTypes.PlottingErrorResponse:
		var err := submit_response as MovementTypes.PlottingErrorResponse
		push_error("StubAI: submit failed for %s: %s" % [ship_id, err.message])
		Trace.trace_log("StubAI", "submit FAILED", {"ship_id": ship_id, "error": err.error_code})
		return

	Trace.trace_log("StubAI", "plotted ship", {
		"ship_id": ship_id,
		"strategy": strategy,
		"steps": ship_state.plotted_actions.get("movement", []).size()
	})


func _strategy_forward(
	_ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	var current_valid := started.valid_next_hexes
	var current_version := version

	while current_valid and not current_valid.forward.is_empty():
		var forward_move: MovementTypes.ValidMove = current_valid.forward[0]
		var target_hex := forward_move.hex

		var response := controller.handle_select_hex(session_id, current_version, target_hex, _next_request_id())

		if response is MovementTypes.PlottingErrorResponse:
			break

		var selected := response as MovementTypes.HexSelectedResponse
		current_version = selected.session_version
		current_valid = selected.valid_next_hexes

	return current_version


func _next_request_id() -> String:
	_request_counter += 1
	return "stub_ai_%d" % _request_counter
