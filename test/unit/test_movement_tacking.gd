extends GutTest
## Tests for tacking attempt detection and probability lookup.
##
## Tacking occurs when a ship pivots into luffing (wind facing L) and uses
## 2+ pivots. The is_tacking_attempt flag should flip true when triggered
## and false when undone past the trigger point.

var validator: MovementValidator
var mock_gs: MockGameState
var hex_grid: HexGrid


class MockGameState extends Node:
	var environment: EnvironmentState = null
	func _init() -> void:
		environment = EnvironmentState.new()


func _make_ship(speed_type: String = "F/F", maneuverability: String = "b") -> Ship:
	return Ship.from_dict({
		"ship_id": "test_ship",
		"player_id": 0,
		"ship_name": "Test Frigate",
		"ship_type": "frigate",
		"name": "Test Frigate",
		"nationality": "British",
		"maneuverability": maneuverability,
		"speed_type": speed_type,
		"rigging_hp": [10, 10, 10, 10],
		"hull_hp": [8, 8, 8, 8],
	})


func _make_ship_state(
	ship: Ship,
	facing: int = 0,
	speed: int = 3,
	sail_state: String = "MS",
) -> ShipState:
	var ss = ShipState.new()
	ss.ship = ship
	ss.hex_position = Vector2i(5, 5)
	ss.facing = facing
	ss.speed = speed
	ss.sail_state = sail_state
	for i in range(4):
		ss.rigging_current_hp[i] = 10
		ss.hull_current_hp[i] = 8
	return ss


func before_each() -> void:
	mock_gs = MockGameState.new()
	mock_gs.environment.wind_direction = 3  # W
	mock_gs.environment.wind_speed = 3
	validator = MovementValidator.new(mock_gs)
	hex_grid = HexGrid.new()


func after_each() -> void:
	if mock_gs:
		mock_gs.free()


# ============================================================================
# Tacking attempt detection
# ============================================================================

func test_tacking_attempt_detected_on_pivot_through_luffing() -> void:
	# Wind from W (3). Ship facing NE (5) = broad reach (B).
	# Pivot port 5→4 (NW) = C. Forward. Pivot port 4→3 (W) = L (luffing).
	# After 2 pivots with luffing on 2nd: is_tacking_attempt should be true.
	var ship = _make_ship("F/F", "d")
	var ss = _make_ship_state(ship, 5, 4, "MS")

	var wf_start = hex_grid.get_wind_facing(5, 3)
	assert_eq(wf_start, "B", "Ship starts at broad reach")

	# Step 1: pivot port, facing 5→4 = NW = C
	var port_facing1 = (5 + 5) % 6  # = 4
	var hex1 = hex_grid.get_neighbor(ss.hex_position.x, ss.hex_position.y, port_facing1)
	var wf_after_pivot1 = hex_grid.get_wind_facing(port_facing1, 3)
	assert_eq(wf_after_pivot1, "C", "First pivot reaches close-hauled")

	# Step 2: forward in facing 4
	var hex2 = hex_grid.get_neighbor(hex1.x, hex1.y, port_facing1)

	# Step 3: pivot port, facing 4→3 = W = L (luffing)
	var port_facing2 = (4 + 5) % 6  # = 3
	var hex3 = hex_grid.get_neighbor(hex2.x, hex2.y, port_facing2)

	var wf_luffing = hex_grid.get_wind_facing(port_facing2, 3)
	assert_eq(wf_luffing, "L", "Second pivot should reach luffing")

	var path: Array[MovementTypes.PlotStep] = [
		MovementTypes.PlotStep.new(hex1, port_facing1, MovementTypes.MoveType.PORT),
		MovementTypes.PlotStep.new(hex2, port_facing1, MovementTypes.MoveType.FORWARD),
		MovementTypes.PlotStep.new(hex3, port_facing2, MovementTypes.MoveType.PORT),
	]

	var result = validator.calculate_valid_moves(ss, hex3, port_facing2, path)
	assert_true(result.is_tacking_attempt, "Should detect tacking attempt after pivot through luffing")


func test_no_tacking_before_luffing_pivot() -> void:
	# Same setup as tacking test but only first pivot (B→C) — no tacking yet
	var ship = _make_ship("F/F", "d")
	var ss = _make_ship_state(ship, 5, 4, "MS")

	# Pivot port 5→4 (NW) = C — no luffing, only 1 pivot
	var port_facing1 = (5 + 5) % 6  # = 4
	var hex1 = hex_grid.get_neighbor(ss.hex_position.x, ss.hex_position.y, port_facing1)

	var path: Array[MovementTypes.PlotStep] = [
		MovementTypes.PlotStep.new(hex1, port_facing1, MovementTypes.MoveType.PORT),
	]

	var result = validator.calculate_valid_moves(ss, hex1, port_facing1, path)
	assert_false(result.is_tacking_attempt, "One pivot without luffing should not trigger tacking")


func test_no_tacking_with_two_pivots_no_luffing() -> void:
	# Two pivots in same direction but never hitting luffing (L)
	# Wind from W (3). Ship facing E (0) = R (running).
	# Pivot starboard 0→1 (SE). Forward. Pivot starboard 1→2 (SW).
	# Neither is luffing, so no tacking.
	var ship = _make_ship("F/F", "d")
	var ss = _make_ship_state(ship, 0, 4, "MS")

	var hex1 = hex_grid.get_neighbor(ss.hex_position.x, ss.hex_position.y, 1)
	var hex2 = hex_grid.get_neighbor(hex1.x, hex1.y, 1)
	var hex3 = hex_grid.get_neighbor(hex2.x, hex2.y, 2)

	var path: Array[MovementTypes.PlotStep] = [
		MovementTypes.PlotStep.new(hex1, 1, MovementTypes.MoveType.STARBOARD),
		MovementTypes.PlotStep.new(hex2, 1, MovementTypes.MoveType.FORWARD),
		MovementTypes.PlotStep.new(hex3, 2, MovementTypes.MoveType.STARBOARD),
	]

	var result = validator.calculate_valid_moves(ss, hex3, 2, path)
	assert_false(result.is_tacking_attempt, "Two pivots without luffing should not trigger tacking")


func test_tacking_false_at_empty_path() -> void:
	var ship = _make_ship("F/F", "b")
	var ss = _make_ship_state(ship, 0, 3, "MS")
	var result = validator.calculate_valid_moves(ss, ss.hex_position, ss.facing, [])
	assert_false(result.is_tacking_attempt, "No tacking at start of plotting")


# ============================================================================
# ValidMovesResult carries is_tacking_attempt
# ============================================================================

func test_valid_moves_result_serializes_tacking() -> void:
	var result = MovementTypes.ValidMovesResult.new()
	result.is_tacking_attempt = true
	var d = result.to_dict()
	assert_true(d.has("is_tacking_attempt"), "Serialized result should include is_tacking_attempt")
	assert_true(d["is_tacking_attempt"], "Serialized value should be true")


# ============================================================================
# Session recompute_tracking on undo
# ============================================================================

func test_session_recompute_clears_tacking_on_undo() -> void:
	var session = MovementPlottingSession.new()
	session.initialize("ship1", 0, Vector2i(5, 5), 5)

	var vnh = MovementTypes.ValidNextHexes.new()
	var port_facing1 = (5 + 5) % 6  # = 4
	var hex1 = hex_grid.get_neighbor(5, 5, port_facing1)
	session.select_hex(hex1, port_facing1, vnh, true, MovementTypes.MoveType.PORT)

	var hex2 = hex_grid.get_neighbor(hex1.x, hex1.y, port_facing1)
	session.select_hex(hex2, port_facing1, vnh, true, MovementTypes.MoveType.FORWARD)

	var port_facing2 = (4 + 5) % 6  # = 3
	var hex3 = hex_grid.get_neighbor(hex2.x, hex2.y, port_facing2)
	session.select_hex(hex3, port_facing2, vnh, true, MovementTypes.MoveType.PORT)

	# Manually set tacking (as controller would after validator)
	session.is_tacking_attempt = true
	assert_true(session.is_tacking_attempt, "Tacking should be set")

	# Undo to version 1 (only the first pivot)
	session.undo_to_version(1, vnh, true)
	# Session._recompute_tracking resets is_tacking_attempt to false
	# (controller would then set it from validator, but session itself resets)
	assert_false(session.is_tacking_attempt, "Tacking should be cleared after undo past trigger")


func test_session_tracking_fields_after_undo() -> void:
	var session = MovementPlottingSession.new()
	session.initialize("ship1", 0, Vector2i(5, 5), 0)

	var vnh = MovementTypes.ValidNextHexes.new()

	# Forward, forward, pivot
	var hex1 = hex_grid.get_neighbor(5, 5, 0)
	session.select_hex(hex1, 0, vnh, true, MovementTypes.MoveType.FORWARD)
	var hex2 = hex_grid.get_neighbor(hex1.x, hex1.y, 0)
	session.select_hex(hex2, 0, vnh, true, MovementTypes.MoveType.FORWARD)
	var hex3 = hex_grid.get_neighbor(hex2.x, hex2.y, 1)
	session.select_hex(hex3, 1, vnh, true, MovementTypes.MoveType.STARBOARD)

	assert_eq(session.pivots_used, 1, "One pivot used")
	assert_eq(session.forward_hexes_since_last_pivot, 0, "Reset after pivot")

	# Undo back to version 2 (two forwards, no pivots)
	session.undo_to_version(2, vnh, true)
	assert_eq(session.pivots_used, 0, "Pivots reset after undo")
	assert_eq(session.forward_hexes_since_last_pivot, 2, "Two forward hexes tracked")


# ============================================================================
# Tacking probability from DataManager
# ============================================================================

func test_tacking_probability_lookup() -> void:
	# Verify DataManager returns expected tacking percentages
	var prob_b_ws3 = DataManager.get_tacking_percent("b", 3)
	assert_eq(prob_b_ws3, 0.7, "Maneuverability b, wind speed 3 should be 70%")

	var prob_a_ws1 = DataManager.get_tacking_percent("a", 1)
	assert_eq(prob_a_ws1, 0.2, "Maneuverability a, wind speed 1 should be 20%")

	var prob_d_ws4 = DataManager.get_tacking_percent("d", 4)
	assert_eq(prob_d_ws4, 0.8, "Maneuverability d, wind speed 4 should be 80%")


func test_tacking_probability_wind_speed_zero() -> void:
	var prob = DataManager.get_tacking_percent("b", 0)
	assert_eq(prob, 0.0, "Wind speed 0 should return 0% tacking chance")


# ============================================================================
# Response types carry is_tacking_attempt
# ============================================================================

func test_hex_selected_response_has_tacking_field() -> void:
	var r = MovementTypes.HexSelectedResponse.new()
	r.is_tacking_attempt = true
	var d = r.to_dict()
	assert_true(d.has("is_tacking_attempt"), "HexSelectedResponse should serialize tacking")
	assert_true(d["is_tacking_attempt"], "Value should be true")


func test_undo_response_has_tacking_field() -> void:
	var r = MovementTypes.UndoCompleteResponse.new()
	r.is_tacking_attempt = false
	var d = r.to_dict()
	assert_true(d.has("is_tacking_attempt"), "UndoCompleteResponse should serialize tacking")
	assert_false(d["is_tacking_attempt"], "Value should be false")


func test_plotting_started_response_has_tacking_field() -> void:
	var r = MovementTypes.PlottingStartedResponse.new()
	r.is_tacking_attempt = false
	var d = r.to_dict()
	assert_true(d.has("is_tacking_attempt"), "PlottingStartedResponse should serialize tacking")
	assert_false(d["is_tacking_attempt"], "Value should be false at start")
