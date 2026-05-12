extends GutTest
## Tests for MovementResolutionPlaybackController
## Verifies: signal emission, event grouping, impulse sequencing, timing

var playback: MovementResolutionPlaybackController
var hex_grid: HexGrid


func before_each() -> void:
	hex_grid = HexGrid.new()
	playback = MovementResolutionPlaybackController.new(hex_grid, {}, 0)
	add_child_autofree(playback)


## ============================================================================
## Signal and lifecycle tests
## ============================================================================

func test_playback_completed_signal_emits_on_empty_log() -> void:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 0

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 2.0)
	assert_signal_emitted(playback, "playback_completed", "playback_completed should emit for empty log")


func test_playback_completed_signal_emits_after_single_move() -> void:
	var log = _make_single_move_log()

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 3.0)
	assert_signal_emitted(playback, "playback_completed", "playback_completed should emit after single move")


func test_is_playing_during_playback() -> void:
	var log = _make_single_move_log()
	assert_false(playback.is_playing(), "should not be playing before play()")

	playback.play(log)
	assert_true(playback.is_playing(), "should be playing immediately after play()")
	await wait_for_signal(playback.playback_completed, 3.0)
	assert_false(playback.is_playing(), "should not be playing after completion")


func test_cannot_play_while_already_playing() -> void:
	var log = _make_multi_impulse_log(3)
	watch_signals(playback)
	playback.play(log)
	assert_true(playback.is_playing())

	# Try to play again — should warn and return
	playback.play(_make_single_move_log())

	await wait_for_signal(playback.playback_completed, 5.0)
	assert_false(playback.is_playing())


## ============================================================================
## Event processing tests
## ============================================================================

func test_multi_impulse_log_completes() -> void:
	var log = _make_multi_impulse_log(3)

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 5.0)
	assert_signal_emitted(playback, "playback_completed", "should complete multi-impulse log")


func test_log_with_tacking_roll_completes() -> void:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 1

	var result = MovementTypes.ShipResolutionResult.new("ship_1")
	result.final_hex = Vector2i(5, 5)
	result.final_facing = 0

	var tack_ev = MovementTypes.ResolutionEvent.new("ship_1", 0, MovementTypes.ResolutionEventType.TACKING_ROLL)
	tack_ev.from_hex = Vector2i(5, 5)
	tack_ev.to_hex = Vector2i(5, 5)
	tack_ev.facing = 0
	tack_ev.roll = 0.3
	tack_ev.threshold = 0.5
	tack_ev.success = true
	result.events.append(tack_ev)

	var move_ev = MovementTypes.ResolutionEvent.new("ship_1", 0, MovementTypes.ResolutionEventType.MOVE)
	move_ev.from_hex = Vector2i(5, 5)
	move_ev.to_hex = Vector2i(6, 5)
	move_ev.facing = 0
	result.events.append(move_ev)

	log.add_result(result)

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 5.0)
	assert_signal_emitted(playback, "playback_completed")


func test_log_with_collision_completes() -> void:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 2

	var result_a = MovementTypes.ShipResolutionResult.new("ship_a")
	result_a.final_hex = Vector2i(5, 5)
	result_a.final_facing = 0
	result_a.collided_with = "ship_b"

	var move_a = MovementTypes.ResolutionEvent.new("ship_a", 0, MovementTypes.ResolutionEventType.MOVE)
	move_a.from_hex = Vector2i(4, 5)
	move_a.to_hex = Vector2i(5, 5)
	move_a.facing = 0
	result_a.events.append(move_a)

	var col_a = MovementTypes.ResolutionEvent.new("ship_a", 1, MovementTypes.ResolutionEventType.COLLISION)
	col_a.from_hex = Vector2i(5, 5)
	col_a.to_hex = Vector2i(5, 5)
	col_a.detail = "collided with ship_b"
	result_a.events.append(col_a)

	var result_b = MovementTypes.ShipResolutionResult.new("ship_b")
	result_b.final_hex = Vector2i(6, 5)
	result_b.final_facing = 3
	result_b.collided_with = "ship_a"

	var col_b = MovementTypes.ResolutionEvent.new("ship_b", 1, MovementTypes.ResolutionEventType.COLLISION)
	col_b.from_hex = Vector2i(6, 5)
	col_b.to_hex = Vector2i(6, 5)
	col_b.detail = "hit by ship_a"
	result_b.events.append(col_b)

	log.add_result(result_a)
	log.add_result(result_b)

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 5.0)
	assert_signal_emitted(playback, "playback_completed", "collision log should complete")


func test_log_with_contested_hex_completes() -> void:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 1

	var result = MovementTypes.ShipResolutionResult.new("ship_1")
	result.final_hex = Vector2i(6, 5)
	result.final_facing = 0

	var contest_ev = MovementTypes.ResolutionEvent.new("ship_1", 0, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL)
	contest_ev.from_hex = Vector2i(5, 5)
	contest_ev.roll = 4.0
	contest_ev.threshold = 1.0
	contest_ev.success = true
	contest_ev.detail = "base=4 drm=1 adjusted=5"
	result.events.append(contest_ev)

	var move_ev = MovementTypes.ResolutionEvent.new("ship_1", 0, MovementTypes.ResolutionEventType.MOVE)
	move_ev.from_hex = Vector2i(5, 5)
	move_ev.to_hex = Vector2i(6, 5)
	move_ev.facing = 0
	result.events.append(move_ev)

	log.add_result(result)

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 5.0)
	assert_signal_emitted(playback, "playback_completed")


func test_log_with_bearing_off_completes() -> void:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 2

	var result = MovementTypes.ShipResolutionResult.new("ship_1")
	result.final_hex = Vector2i(5, 5)
	result.final_facing = 0
	result.stopped_at_impulse = 1

	var move_ev = MovementTypes.ResolutionEvent.new("ship_1", 0, MovementTypes.ResolutionEventType.MOVE)
	move_ev.from_hex = Vector2i(4, 5)
	move_ev.to_hex = Vector2i(5, 5)
	move_ev.facing = 0
	result.events.append(move_ev)

	var bear_ev = MovementTypes.ResolutionEvent.new("ship_1", 1, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
	bear_ev.from_hex = Vector2i(5, 5)
	bear_ev.to_hex = Vector2i(5, 5)
	bear_ev.roll = 0.3
	bear_ev.threshold = 0.5
	bear_ev.success = true
	bear_ev.detail = "bore off successfully"
	result.events.append(bear_ev)

	var stop_ev = MovementTypes.ResolutionEvent.new("ship_1", 1, MovementTypes.ResolutionEventType.STOPPED)
	stop_ev.from_hex = Vector2i(5, 5)
	stop_ev.to_hex = Vector2i(5, 5)
	stop_ev.detail = "bore off successfully, movement ends"
	result.events.append(stop_ev)

	log.add_result(result)

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 5.0)
	assert_signal_emitted(playback, "playback_completed")


func test_log_with_immobilized_completes() -> void:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 0

	var result = MovementTypes.ShipResolutionResult.new("ship_1")
	result.final_hex = Vector2i(5, 5)
	result.final_facing = 0
	result.immobilized = true

	var skip_ev = MovementTypes.ResolutionEvent.new("ship_1", 0, MovementTypes.ResolutionEventType.SKIP_NO_PLOT)
	skip_ev.from_hex = Vector2i(5, 5)
	skip_ev.to_hex = Vector2i(5, 5)
	skip_ev.detail = "no movement plotted"
	result.events.append(skip_ev)

	log.add_result(result)

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 3.0)
	assert_signal_emitted(playback, "playback_completed")


func test_log_with_fouling_completes() -> void:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 1

	var result_a = MovementTypes.ShipResolutionResult.new("ship_a")
	result_a.final_hex = Vector2i(5, 5)
	result_a.final_facing = 0
	result_a.fouled_with = "ship_b"

	var col_a = MovementTypes.ResolutionEvent.new("ship_a", 0, MovementTypes.ResolutionEventType.COLLISION)
	col_a.from_hex = Vector2i(5, 5)
	result_a.events.append(col_a)

	var foul_a = MovementTypes.ResolutionEvent.new("ship_a", 0, MovementTypes.ResolutionEventType.FOULING)
	foul_a.from_hex = Vector2i(5, 5)
	foul_a.detail = "fouled with ship_b"
	result_a.events.append(foul_a)

	log.add_result(result_a)

	watch_signals(playback)
	playback.play(log)
	await wait_for_signal(playback.playback_completed, 5.0)
	assert_signal_emitted(playback, "playback_completed")


## ============================================================================
## ShipView animation tests (with real views in tree)
## ============================================================================

func test_ship_view_position_updated_after_move() -> void:
	var view = ShipView.new()
	view.name = "TestShipView"
	add_child_autofree(view)

	var ship_state = ShipState.new()
	ship_state.ship = Ship.from_dict({
		"ship_id": "animated_ship",
		"player_id": 0,
		"ship_name": "Animated",
		"ship_type": "frigate_38",
		"name": "Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "C",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3],
		"marine_count": 2,
	})
	ship_state.hex_position = Vector2i(5, 5)
	ship_state.facing = 0
	ship_state.speed = 3
	ship_state.sail_state = "MS"
	ship_state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	ship_state.hull_current_hp = [5, 5, 5, 6] as Array[int]

	view.initialize(ship_state, hex_grid)

	var views = {"animated_ship": view}
	var pb = MovementResolutionPlaybackController.new(hex_grid, views, 0)
	add_child_autofree(pb)

	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 1

	var result = MovementTypes.ShipResolutionResult.new("animated_ship")
	result.final_hex = Vector2i(6, 5)
	result.final_facing = 0

	var move_ev = MovementTypes.ResolutionEvent.new("animated_ship", 0, MovementTypes.ResolutionEventType.MOVE)
	move_ev.from_hex = Vector2i(5, 5)
	move_ev.to_hex = Vector2i(6, 5)
	move_ev.facing = 0
	result.events.append(move_ev)

	log.add_result(result)

	pb.play(log)
	await wait_for_signal(pb.playback_completed, 5.0)

	var expected_pos = hex_grid.axial_to_world(6, 5)
	expected_pos.y = 0.0
	assert_almost_eq(view.base_position.x, expected_pos.x, 0.1, "x position should match target")
	assert_almost_eq(view.base_position.z, expected_pos.z, 0.1, "z position should match target")


func test_ship_view_facing_updated_after_turn() -> void:
	var view = ShipView.new()
	view.name = "TestShipView2"
	add_child_autofree(view)

	var ship_state = ShipState.new()
	ship_state.ship = Ship.from_dict({
		"ship_id": "turning_ship",
		"player_id": 0,
		"ship_name": "Turner",
		"ship_type": "frigate_38",
		"name": "Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "C",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3],
		"marine_count": 2,
	})
	ship_state.hex_position = Vector2i(5, 5)
	ship_state.facing = 0
	ship_state.speed = 3
	ship_state.sail_state = "MS"
	ship_state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	ship_state.hull_current_hp = [5, 5, 5, 6] as Array[int]

	view.initialize(ship_state, hex_grid)

	var views = {"turning_ship": view}
	var pb = MovementResolutionPlaybackController.new(hex_grid, views, 0)
	add_child_autofree(pb)

	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 1

	var result = MovementTypes.ShipResolutionResult.new("turning_ship")
	result.final_hex = Vector2i(5, 6)
	result.final_facing = 1

	var move_ev = MovementTypes.ResolutionEvent.new("turning_ship", 0, MovementTypes.ResolutionEventType.MOVE)
	move_ev.from_hex = Vector2i(5, 5)
	move_ev.to_hex = Vector2i(5, 6)
	move_ev.facing = 1
	result.events.append(move_ev)

	log.add_result(result)

	pb.play(log)
	await wait_for_signal(pb.playback_completed, 5.0)

	var expected_angle = -1 * 60.0 - 90.0  # facing 1 -> -150 degrees
	if view.model_node:
		assert_almost_eq(view.model_node.rotation_degrees.y, expected_angle, 1.0, "facing should match target")


## ============================================================================
## TurnPhaseController integration tests
## ============================================================================

func test_phase_controller_emits_resolution_log_ready() -> void:
	# Ensure resolver exists so the resolution path fires
	var rng_local = RandomNumberGenerator.new()
	rng_local.seed = 99
	GameState.movement_resolver = MovementResolver.new(GameState, rng_local)
	GameState.environment = EnvironmentState.new()
	GameState.environment.wind_direction = 0
	GameState.environment.wind_speed = 3
	GameState.environment.sea_state = 1

	var phase_ctrl = TurnPhaseController.new(GameState)
	add_child_autofree(phase_ctrl)
	phase_ctrl.is_server = true

	watch_signals(phase_ctrl)

	phase_ctrl.current_phase = TurnPhaseController.GamePhase.PLANNING
	phase_ctrl.advance_phase()

	assert_signal_emitted(phase_ctrl, "resolution_log_ready", "resolution_log_ready should have emitted")
	assert_eq(phase_ctrl.current_phase, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION,
		"should stay in MOVEMENT_RESOLUTION (not auto-advance)")


func test_phase_controller_advances_after_on_playback_completed() -> void:
	var rng_local = RandomNumberGenerator.new()
	rng_local.seed = 99
	GameState.movement_resolver = MovementResolver.new(GameState, rng_local)
	GameState.environment = EnvironmentState.new()
	GameState.environment.wind_direction = 0
	GameState.environment.wind_speed = 3
	GameState.environment.sea_state = 1

	var phase_ctrl = TurnPhaseController.new(GameState)
	add_child_autofree(phase_ctrl)
	phase_ctrl.is_server = true

	phase_ctrl.current_phase = TurnPhaseController.GamePhase.PLANNING
	phase_ctrl.advance_phase()

	assert_eq(phase_ctrl.current_phase, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION,
		"should be in MOVEMENT_RESOLUTION before playback completes")

	phase_ctrl.on_playback_completed()

	# After on_playback_completed, the phase controller advances through all
	# stubbed phases until it hits one that doesn't auto-advance (POST_COMBAT or END_TURN).
	# COMBAT_RESOLUTION -> DRIFT -> STATUS -> MORALE -> MESSAGE -> POST_COMBAT all auto-advance.
	# We just verify it moved past MOVEMENT_RESOLUTION.
	assert_ne(phase_ctrl.current_phase, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION,
		"should have advanced past MOVEMENT_RESOLUTION after playback")


## ============================================================================
## Helpers
## ============================================================================

func _make_single_move_log() -> MovementTypes.ResolutionLog:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 1

	var result = MovementTypes.ShipResolutionResult.new("ship_1")
	result.final_hex = Vector2i(6, 5)
	result.final_facing = 0

	var ev = MovementTypes.ResolutionEvent.new("ship_1", 0, MovementTypes.ResolutionEventType.MOVE)
	ev.from_hex = Vector2i(5, 5)
	ev.to_hex = Vector2i(6, 5)
	ev.facing = 0
	result.events.append(ev)

	log.add_result(result)
	return log


func _make_multi_impulse_log(impulse_count: int) -> MovementTypes.ResolutionLog:
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = impulse_count

	var result = MovementTypes.ShipResolutionResult.new("ship_1")
	var current_hex = Vector2i(5, 5)

	for i in range(impulse_count):
		var next_hex = Vector2i(current_hex.x + 1, current_hex.y)
		var ev = MovementTypes.ResolutionEvent.new("ship_1", i, MovementTypes.ResolutionEventType.MOVE)
		ev.from_hex = current_hex
		ev.to_hex = next_hex
		ev.facing = 0
		result.events.append(ev)
		current_hex = next_hex

	result.final_hex = current_hex
	result.final_facing = 0
	log.add_result(result)
	return log
