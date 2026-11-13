class_name StubAI
extends RefCounted
## StubAI - Drives the plotting protocol for non-player ships
## Uses the real MovementPlottingController so all AI plots are rule-validated.
##
## Strategies:
##   "engage"  — steer toward the nearest enemy, presenting a broadside when close (default)
##   "forward" — move straight ahead, consuming all available MA
##   "hold"    — submit immediately with empty path
##
## Fire: each ship fires each broadside at its best-odds target (see choose_fire_orders).

## A broadside shot at or inside this range scores as a firing position.
const FIRING_RANGE := 5
const FIRING_POSITION_BASE := 1000
## Two-target modifier from the chart; a second broadside is held when it would not survive it.
const TWO_TARGET_PENALTY := 12

## Plotting errors for ships that legitimately cannot move; the AI skips them without error.
const LOCKED_ERROR_CODES := ["SHIP_FOULED", "SHIP_STRUCK", "SHIP_DISMASTED"]

var game_state: Node = null
var _request_counter: int = 0
## When non-empty, forces this strategy for every AI ship (used by tests).
var strategy_override: String = ""


func _init(p_game_state: Node = null) -> void:
	game_state = p_game_state if p_game_state else GameState


func plot_all_ai_ships() -> void:
	assert(game_state.is_server, "StubAI: Must only run on server")
	var controller: MovementPlottingController = game_state.movement_plotting_controller
	if not controller:
		push_error("StubAI: No movement_plotting_controller on game_state")
		return

	var ai_ships := _get_ai_ships()
	Trace.trace_log("StubAI", "plot_all_ai_ships: %d AI ships" % ai_ships.size())

	for ship_state in ai_ships:
		var strategy := _get_strategy(ship_state)
		_plot_ship(ship_state, controller, strategy)


## Declare fire for the AI side (player 1).
func submit_fire_orders() -> void:
	assert(game_state.is_server, "StubAI: Must only run on server")
	var reason: String = game_state.phase_controller.player_submit_fire_orders(1, choose_fire_orders())
	if reason != "":
		push_error("StubAI: fire orders rejected: %s" % reason)


## FireOrder dictionaries for every AI ship: per broadside the highest-mgn shot (ties: nearest,
## then target_id), roundshot. When both broadsides have a target both fire only if each shot
## still has mgn >= 1 under the two-target penalty; otherwise only the better one fires.
func choose_fire_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var calculator: GunneryCalculator = game_state.gunnery_calculator
	for ship_state in _get_ai_ships():
		var best_per_side: Array[GunneryTypes.ShotPreview] = []
		for side in GunneryCalculator.SIDES:
			var best: GunneryTypes.ShotPreview = null
			for shot in calculator.eligible_shots(ship_state.ship_id):
				if shot.order.side == side and (best == null or _shot_beats(shot, best)):
					best = shot
			if best != null:
				best_per_side.append(best)

		var kept: Array[GunneryTypes.ShotPreview] = best_per_side
		if best_per_side.size() == 2:
			var both_worthwhile := true
			for shot in best_per_side:
				if calculator.preview(shot.order, true).mgn < 1:
					both_worthwhile = false
			if not both_worthwhile:
				kept = [best_per_side[1] if _shot_beats(best_per_side[1], best_per_side[0]) else best_per_side[0]]
		for shot in kept:
			result.append(shot.order.to_dict())
	return result


func _shot_beats(a: GunneryTypes.ShotPreview, b: GunneryTypes.ShotPreview) -> bool:
	if a.mgn != b.mgn:
		return a.mgn > b.mgn
	if a.range_hexes != b.range_hexes:
		return a.range_hexes < b.range_hexes
	return a.order.target_id < b.order.target_id


func _get_ai_ships() -> Array[ShipState]:
	var result: Array[ShipState] = []
	for ship_state in game_state.get_all_ships():
		if ship_state.player_id != 0:
			result.append(ship_state)
	return result


func _get_strategy(_ship_state: ShipState) -> String:
	if strategy_override != "":
		return strategy_override
	return "engage"


func _plot_ship(ship_state: ShipState, controller: MovementPlottingController, strategy: String) -> void:
	var ship_id := ship_state.ship_id
	var player_id := ship_state.player_id

	var start_response := controller.handle_start_plotting(player_id, ship_id, _next_request_id())

	if start_response is MovementTypes.PlottingErrorResponse:
		var err := start_response as MovementTypes.PlottingErrorResponse
		if err.error_code in LOCKED_ERROR_CODES:
			Trace.trace_log("StubAI", "ship cannot move, skipped", {"ship_id": ship_id, "reason": err.error_code})
			return
		push_error("StubAI: start_plotting failed for %s: %s" % [ship_id, err.message])
		Trace.trace_log("StubAI", "start_plotting FAILED", {"ship_id": ship_id, "error": err.error_code})
		return

	var started := start_response as MovementTypes.PlottingStartedResponse
	var session_id := started.session_id
	var version := started.session_version

	match strategy:
		"engage":
			version = _strategy_engage(ship_state, controller, session_id, version, started)
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


func _strategy_engage(
	ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	var enemy := _nearest_enemy(ship_state)
	if enemy == null:
		return version  # nothing to engage: submit the session with an empty path

	var occupied: Dictionary = {}
	for other in game_state.get_all_ships():
		if other.ship_id != ship_state.ship_id:
			occupied[other.hex_position] = true

	var current_hex := ship_state.hex_position
	var current_facing := ship_state.facing
	var current_valid := started.valid_next_hexes
	var current_version := version

	while current_valid and current_valid.has_any_moves():
		var stay_score := _score_position(current_hex, current_facing, enemy.hex_position, occupied)
		var best: MovementTypes.ValidMove = null
		var best_score := 0
		for move in current_valid.get_all_valid_moves():
			var move_score := _score_position(move.hex, move.metadata.resulting_facing, enemy.hex_position, occupied)
			if best == null or _option_beats(move, move_score, best, best_score, current_facing):
				best = move
				best_score = move_score
		if best_score <= stay_score:
			break

		var response := controller.handle_select_hex(session_id, current_version, best.hex, _next_request_id())
		if response is MovementTypes.PlottingErrorResponse:
			break
		var selected := response as MovementTypes.HexSelectedResponse
		current_version = selected.session_version
		current_valid = selected.valid_next_hexes
		current_hex = best.hex
		current_facing = best.metadata.resulting_facing

	return current_version


## Nearest unstruck ship of another player; ties by ship_id. Null when there is none.
func _nearest_enemy(ship_state: ShipState) -> ShipState:
	var nearest: ShipState = null
	var nearest_distance := 0
	for other in game_state.get_all_ships():
		if other.player_id == ship_state.player_id or other.is_struck():
			continue
		var distance := HexGrid.new().hex_distance(
			ship_state.hex_position.x, ship_state.hex_position.y, other.hex_position.x, other.hex_position.y)
		if nearest == null or distance < nearest_distance \
				or (distance == nearest_distance and other.ship_id < nearest.ship_id):
			nearest = other
			nearest_distance = distance
	return nearest


## 1000 - range when the enemy lies in a broadside arc, within range 5 with clear line of sight;
## otherwise the negative distance to the enemy.
func _score_position(hex: Vector2i, facing: int, enemy_hex: Vector2i, occupied: Dictionary) -> int:
	var geometry: FireGeometry = game_state.fire_geometry
	var distance := geometry.hex_grid.hex_distance(hex.x, hex.y, enemy_hex.x, enemy_hex.y)
	if distance <= FIRING_RANGE \
			and geometry.bearing_side(hex, facing, enemy_hex) != -1 \
			and geometry.has_line_of_sight(hex, enemy_hex, occupied):
		return FIRING_POSITION_BASE - distance
	return -distance


## Higher score wins; ties keep the current facing, then lowest q, then lowest r.
func _option_beats(
	a: MovementTypes.ValidMove, a_score: int, b: MovementTypes.ValidMove, b_score: int, current_facing: int
) -> bool:
	if a_score != b_score:
		return a_score > b_score
	var a_keeps := a.metadata.resulting_facing == current_facing
	var b_keeps := b.metadata.resulting_facing == current_facing
	if a_keeps != b_keeps:
		return a_keeps
	if a.hex.x != b.hex.x:
		return a.hex.x < b.hex.x
	return a.hex.y < b.hex.y


func _next_request_id() -> String:
	_request_counter += 1
	return "stub_ai_%d" % _request_counter
