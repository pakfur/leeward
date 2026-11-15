extends GutTest
## Tests for MovementResolutionPlaybackController
## Verifies: signal emission, event grouping, impulse sequencing, timing

var playback: MovementResolutionPlaybackController
var hex_grid: HexGrid


## Records every ship view's pose after each impulse's animation.
class PoseSpy extends MovementResolutionPlaybackController:
	var poses: Array = []  # [{ship_id: [base_position, model rotation y]}] per animated batch

	func _animate_moves(move_events: Array) -> void:
		await super(move_events)
		var snap := {}
		for sid in _ship_views:
			var view: ShipView = _ship_views[sid]
			snap[sid] = [view.base_position, view.model_node.rotation_degrees.y if view.model_node else 0.0]
		poses.append(snap)


## Records which impulses' moves are animated (no ship views needed).
class ImpulseSpy extends MovementResolutionPlaybackController:
	var animated: Array = []

	func _animate_moves(move_events: Array) -> void:
		for ev in move_events:
			if not animated.has(ev.impulse):
				animated.append(ev.impulse)


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

	var expected_pos = hex_grid.ship_center_world(Vector2i(6, 5), 0)
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


func test_playback_turn_keeps_bow_hex() -> void:
	var ship_state := _two_hex_state("pivoting_ship", Vector2i(5, 5), 0)
	var view := ShipView.new()
	add_child_autofree(view)
	view.initialize(ship_state, hex_grid)
	var pb = MovementResolutionPlaybackController.new(hex_grid, {"pivoting_ship": view}, 0)
	add_child_autofree(pb)

	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 1
	var result = MovementTypes.ShipResolutionResult.new("pivoting_ship")
	result.final_hex = Vector2i(5, 5)
	result.final_facing = 1
	# A turn: the bow stays in its hex and the stern swings round it.
	var turn_ev = MovementTypes.ResolutionEvent.new("pivoting_ship", 0, MovementTypes.ResolutionEventType.MOVE)
	turn_ev.from_hex = Vector2i(5, 5)
	turn_ev.to_hex = Vector2i(5, 5)
	turn_ev.from_facing = 0
	turn_ev.facing = 1
	result.events.append(turn_ev)
	log.add_result(result)

	pb.play(log)
	await wait_for_signal(pb.playback_completed, 5.0)

	var expected := hex_grid.ship_center_world(Vector2i(5, 5), 1)
	assert_almost_eq(view.base_position.x, expected.x, 0.01, "centre between the same bow and the swung stern")
	assert_almost_eq(view.base_position.z, expected.z, 0.01)
	assert_almost_eq(view.model_node.rotation_degrees.y, -1 * 60.0 - 90.0, 1.0, "now facing SE")


func _overlap_rollback_log(with_ahead_move: bool) -> MovementTypes.ResolutionLog:
	# The resolver's record of a rolled-back turn: OVERLAP (the swing out) at the overlap segment,
	# OVERLAP_ROLLBACK (the swing back) at the next one. With a deceleration step the ship moves
	# ahead at the overlap segment instead.
	var log = MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 2
	var result = MovementTypes.ShipResolutionResult.new("swinging_ship")
	var overlap = MovementTypes.ResolutionEvent.new("swinging_ship", 0, MovementTypes.ResolutionEventType.OVERLAP)
	overlap.from_hex = Vector2i(5, 5)
	overlap.to_hex = Vector2i(5, 5)
	overlap.from_facing = 0
	overlap.facing = 1
	overlap.detail = "overlaps other"
	if with_ahead_move:
		var mv = MovementTypes.ResolutionEvent.new("swinging_ship", 0, MovementTypes.ResolutionEventType.MOVE)
		mv.from_hex = Vector2i(5, 5)
		mv.to_hex = Vector2i(6, 5)
		mv.from_facing = 0
		mv.facing = 0
		result.events.append(mv)
	result.events.append(overlap)
	var rollback = MovementTypes.ResolutionEvent.new("swinging_ship", 1, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	rollback.from_hex = Vector2i(5, 5)
	rollback.to_hex = Vector2i(5, 5)
	rollback.from_facing = 1
	rollback.facing = 0
	rollback.success = false
	rollback.detail = "already occupied"
	result.events.append(rollback)
	result.final_hex = Vector2i(6, 5) if with_ahead_move else Vector2i(5, 5)
	result.final_facing = 0
	log.add_result(result)
	return log


func test_rolled_back_turn_swings_out_and_back() -> void:
	var pb = MovementResolutionPlaybackController.new(hex_grid, {}, 0)
	add_child_autofree(pb)
	var log := _overlap_rollback_log(false)
	pb._log = log
	var events: Array = log.get_result("swinging_ship").events
	var out: Array = pb._posed_events([events[0]])
	assert_eq(out.size(), 1, "The swing out is animated")
	if out.size() == 1:
		assert_eq(out[0].event_type, MovementTypes.ResolutionEventType.OVERLAP)
	var back: Array = pb._posed_events([events[1]])
	assert_eq(back.size(), 1, "The swing back is animated")
	if back.size() == 1:
		assert_eq(back[0].event_type, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)


func test_rolled_back_turn_with_ahead_move_animates_only_the_move() -> void:
	var pb = MovementResolutionPlaybackController.new(hex_grid, {}, 0)
	add_child_autofree(pb)
	var log := _overlap_rollback_log(true)
	pb._log = log
	var events: Array = log.get_result("swinging_ship").events
	var posed: Array = pb._posed_events([events[0], events[1]])
	assert_eq(posed.size(), 1)
	assert_eq(posed[0].event_type, MovementTypes.ResolutionEventType.MOVE)
	assert_eq(pb._posed_events([events[2]]), [], "Nothing swung out, so nothing swings back")


func test_pre_movement_events_are_not_played_again_on_impulse_0() -> void:
	var skip := MovementTypes.ResolutionEvent.new("a", 0, MovementTypes.ResolutionEventType.SKIP_NO_PLOT)
	var tack := MovementTypes.ResolutionEvent.new("b", 0, MovementTypes.ResolutionEventType.TACKING_ROLL)
	var move := MovementTypes.ResolutionEvent.new("b", 0, MovementTypes.ResolutionEventType.MOVE)
	var contest := MovementTypes.ResolutionEvent.new("c", 0, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL)
	var special: Array = MovementResolutionPlaybackController._special_events([skip, tack, move, contest], [skip, tack])
	assert_eq(special, [contest])


func test_playback_rolled_back_turn_ends_in_the_old_pose() -> void:
	var ship_state := _two_hex_state("swinging_ship", Vector2i(5, 5), 0)
	var view := ShipView.new()
	add_child_autofree(view)
	view.initialize(ship_state, hex_grid)
	var pb := PoseSpy.new(hex_grid, {"swinging_ship": view}, 0)
	add_child_autofree(pb)

	pb.play(_overlap_rollback_log(false))
	await wait_for_signal(pb.playback_completed, 5.0)

	assert_eq(pb.poses.size(), 2, "Two animated impulses: the swing out and the swing back")
	if pb.poses.size() == 2:
		var out: Array = pb.poses[0]["swinging_ship"]
		var swung := hex_grid.ship_center_world(Vector2i(5, 5), 1)
		assert_almost_eq(out[0].x, swung.x, 0.01, "after the OVERLAP impulse the stern is swung out")
		assert_almost_eq(out[0].z, swung.z, 0.01)
		assert_almost_eq(out[1], -1 * 60.0 - 90.0, 1.0, "facing SE while swung out")
	var expected := hex_grid.ship_center_world(Vector2i(5, 5), 0)
	assert_almost_eq(view.base_position.x, expected.x, 0.01, "back where it started")
	assert_almost_eq(view.base_position.z, expected.z, 0.01)
	assert_almost_eq(view.model_node.rotation_degrees.y, -90.0, 1.0, "facing E again")


## The ship's centre for a bow world position and a model angle: half a hex astern of the bow.
func _centre_for(bow: Vector3, angle: float) -> Vector3:
	var rad := deg_to_rad(angle)
	var half_length := hex_grid.hex_size * HexGrid.SQRT3 / 2.0
	return Vector3(bow.x, 0.0, bow.z) + Vector3(sin(rad), 0.0, cos(rad)) * half_length


func test_mid_swing_the_stern_orbits_a_fixed_bow() -> void:
	var view := ShipView.new()
	add_child_autofree(view)
	view.initialize(_two_hex_state("turning", Vector2i(5, 5), 0), hex_grid)
	var pb = MovementResolutionPlaybackController.new(hex_grid, {"turning": view}, 0)
	add_child_autofree(pb)
	var bow := hex_grid.axial_to_world(5, 5)
	var from_angle := MovementResolutionPlaybackController._model_angle(0)
	var to_angle := MovementResolutionPlaybackController._model_angle(1)
	var half_length := hex_grid.hex_size * HexGrid.SQRT3 / 2.0

	for t in [0.25, 0.5, 0.75]:
		pb._pose_ship(t, view, bow, bow, from_angle, to_angle)
		var angle := lerpf(from_angle, to_angle, t)
		var expected := _centre_for(bow, angle)
		assert_almost_eq(view.base_position.x, expected.x, 0.01, "t=%s: centre on the arc round the bow" % t)
		assert_almost_eq(view.base_position.z, expected.z, 0.01)
		var flat_bow := Vector3(bow.x, 0.0, bow.z)
		assert_almost_eq(view.base_position.distance_to(flat_bow), half_length, 0.01, "t=%s: the bow stays put" % t)
		assert_almost_eq(view.model_node.rotation_degrees.y, angle, 0.01)


func test_ahead_step_slides_along_the_keel() -> void:
	var view := ShipView.new()
	add_child_autofree(view)
	view.initialize(_two_hex_state("sailing", Vector2i(5, 5), 0), hex_grid)
	var pb = MovementResolutionPlaybackController.new(hex_grid, {"sailing": view}, 0)
	add_child_autofree(pb)
	var from_bow := hex_grid.axial_to_world(5, 5)
	var to_bow := hex_grid.axial_to_world(6, 5)
	var angle := MovementResolutionPlaybackController._model_angle(0)

	pb._pose_ship(0.5, view, from_bow, to_bow, angle, angle)

	var expected := _centre_for(from_bow.lerp(to_bow, 0.5), angle)
	assert_almost_eq(view.base_position.x, expected.x, 0.01, "halfway: the bow is midway between the hexes")
	assert_almost_eq(view.base_position.z, expected.z, 0.01)
	assert_almost_eq(view.model_node.rotation_degrees.y, angle, 0.01, "the heading does not change")
	var start := _centre_for(from_bow, angle)
	var finish := _centre_for(to_bow, angle)
	assert_almost_eq(view.base_position.distance_to(start), view.base_position.distance_to(finish), 0.01,
		"halfway along the keel")


func test_overlap_events_add_no_pause() -> void:
	# An OVERLAP is told by the swing animation (when posed) or not at all: it is never a special event,
	# so it adds no unflagged pause to its impulse.
	var overlap := MovementTypes.ResolutionEvent.new("a", 0, MovementTypes.ResolutionEventType.OVERLAP)
	var rollback := MovementTypes.ResolutionEvent.new("b", 0, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	var move := MovementTypes.ResolutionEvent.new("c", 0, MovementTypes.ResolutionEventType.MOVE)
	var special: Array = MovementResolutionPlaybackController._special_events([overlap, rollback, move], [])
	assert_eq(special, [rollback], "Only the rollback is played as a special event")


func _two_hex_state(ship_id: String, bow: Vector2i, facing: int) -> ShipState:
	var ship_state = ShipState.new()
	ship_state.ship = Ship.from_dict({
		"ship_id": ship_id,
		"player_id": 0,
		"ship_name": ship_id,
		"ship_type": "frigate_38",
		"rating": 38,
		"class": 3,
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3],
		"marine_count": 2,
	})
	ship_state.hex_position = bow
	ship_state.facing = facing
	ship_state.sail_state = "MS"
	ship_state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	ship_state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	return ship_state


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


func test_aborted_playback_never_reports_completion() -> void:
	var log = _make_single_move_log()
	watch_signals(playback)
	playback.play(log)
	playback.abort()
	await wait_seconds(1.0)
	assert_signal_not_emitted(playback, "playback_completed", "leaving the game abandons playback")
	assert_false(playback.is_playing())



## ============================================================================
## Bear-off pause and resume (6.D.3)
## ============================================================================

func test_incomplete_log_plays_up_to_the_decision_and_pauses() -> void:
	var log = _make_multi_impulse_log(4)
	log.pending_bear_off = MovementTypes.BearOffSituation.new()
	log.pending_bear_off.segment = 2
	var spy := ImpulseSpy.new(hex_grid, {}, 0)
	add_child_autofree(spy)
	watch_signals(spy)
	spy.play(log)
	await wait_for_signal(spy.playback_paused, 3.0)
	assert_signal_emitted(spy, "playback_paused")
	assert_signal_not_emitted(spy, "playback_completed", "Not finished: a decision is pending")
	assert_eq(spy.animated, [0, 1], "Segments before the potential collision only")


func test_resumed_log_plays_from_its_resume_impulse() -> void:
	var log = _make_multi_impulse_log(4)
	log.resume_impulse = 2
	var spy := ImpulseSpy.new(hex_grid, {}, 0)
	add_child_autofree(spy)
	watch_signals(spy)
	spy.play(log)
	await wait_for_signal(spy.playback_completed, 3.0)
	assert_signal_emitted(spy, "playback_completed")
	assert_eq(spy.animated, [2, 3], "The segments already shown are not played again")
