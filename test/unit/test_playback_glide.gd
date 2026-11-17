extends GutTest
## The glide playback (sea-state spec D): each ship's move is split into stretches at every segment
## that carries an event; within a stretch it glides and arrives exactly on the resolver's pose.


var hex_grid: HexGrid


## Records the ship views' poses at the end of every stretch.
class StretchPoseSpy extends MovementResolutionPlaybackController:
	var stretches: Array = []  # [first, last] per glided stretch
	var poses: Array = []  # {ship_id: [base_position, model yaw]} at each stretch end

	func _glide_stretch(first: int, last: int) -> void:
		await super(first, last)
		stretches.append([first, last])
		var snap := {}
		for sid in _ship_views:
			var view: ShipView = _ship_views[sid]
			snap[sid] = [view.base_position, view.model_node.rotation_degrees.y]
		poses.append(snap)


func before_each() -> void:
	hex_grid = HexGrid.new()


## ============================================================================
## Stretches
## ============================================================================

func test_stretches_split_at_events() -> void:
	assert_eq(MovementResolutionPlaybackController.glide_stretches([3] as Array[int], 1, 6), [[1, 3], [4, 6]])
	assert_eq(MovementResolutionPlaybackController.glide_stretches([1, 4] as Array[int], 0, 5), [[0, 1], [2, 4], [5, 5]],
		"every event segment ends a stretch")


func test_no_events_one_stretch() -> void:
	assert_eq(MovementResolutionPlaybackController.glide_stretches([] as Array[int], 0, 4), [[0, 4]])
	assert_eq(MovementResolutionPlaybackController.glide_stretches([4] as Array[int], 0, 4), [[0, 4]], "an event on the last segment splits nothing")
	assert_eq(MovementResolutionPlaybackController.glide_stretches([7, -1] as Array[int], 0, 4), [[0, 4]], "events outside the range are ignored")
	assert_eq(MovementResolutionPlaybackController.glide_stretches([] as Array[int], 3, 2), [], "an empty range has no stretch")


## ============================================================================
## Poses
## ============================================================================

## A ship sailing east from (2, 5): ahead on every segment of `segments`, turning to SE on `turn_at`.
func _moves(ship_id: String, segments: Array, turn_at: int = -1) -> Array:
	var events: Array = []
	var hex := Vector2i(2, 5)
	var facing := 0
	for seg in segments:
		var ev := MovementTypes.ResolutionEvent.new(ship_id, seg, MovementTypes.ResolutionEventType.MOVE)
		ev.from_hex = hex
		ev.from_facing = facing
		if seg == turn_at:
			facing = 1
		else:
			hex = hex_grid.get_neighbor(hex.x, hex.y, facing)
		ev.to_hex = hex
		ev.facing = facing
		events.append(ev)
	return events


func _in_range(events: Array, first: int, last: int) -> Array:
	return events.filter(func(ev): return ev.impulse >= first and ev.impulse <= last)


func _assert_pose(pose: Array, ev: MovementTypes.ResolutionEvent, what: String) -> void:
	var bow := hex_grid.axial_to_world(ev.to_hex.x, ev.to_hex.y)
	assert_almost_eq(pose[0].x, bow.x, 0.0001, what + ": bow x")
	assert_almost_eq(pose[0].z, bow.z, 0.0001, what + ": bow z")
	assert_almost_eq(fposmod(pose[1] - MovementResolutionPlaybackController._model_angle(ev.facing) + 180.0, 360.0) - 180.0, 0.0, 0.0001,
		what + ": heading")


func test_pose_at_event_segment_matches_resolver() -> void:
	var events := _moves("a", [0, 1, 2, 3, 4, 5], 2)
	var stretches: Array = MovementResolutionPlaybackController.glide_stretches([2] as Array[int], 0, 5)
	assert_eq(stretches, [[0, 2], [3, 5]])
	var angle := MovementResolutionPlaybackController._model_angle(0)
	for stretch in stretches:
		var part := _in_range(events, stretch[0], stretch[1])
		var track: MovementResolutionPlaybackController.GlideTrack = MovementResolutionPlaybackController.track_for(part, hex_grid, angle)
		var end_pose: Array = MovementResolutionPlaybackController.pose_at(track, float(stretch[1] + 1))
		_assert_pose(end_pose, part[-1], "end of stretch %s" % [stretch])
		var start_pose: Array = MovementResolutionPlaybackController.pose_at(track, float(stretch[0]))
		var start_bow := hex_grid.axial_to_world(part[0].from_hex.x, part[0].from_hex.y)
		assert_almost_eq(start_pose[0].distance_to(start_bow), 0.0, 0.0001, "starts where the last stretch ended")
		angle = end_pose[1]


func test_pose_at_event_segment_for_ship_idle_at_the_event() -> void:
	# Moved on segment 0 only; the event is on segment 2: the ship has arrived long before the pause.
	var events := _moves("b", [0])
	var track: MovementResolutionPlaybackController.GlideTrack = MovementResolutionPlaybackController.track_for(events, hex_grid, MovementResolutionPlaybackController._model_angle(0))
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 3.0), events[0], "at the event")
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 1.0), events[0], "on arrival")


func test_glide_accelerates_and_decelerates() -> void:
	var events := _moves("c", [0, 1, 2, 3])
	var track: MovementResolutionPlaybackController.GlideTrack = MovementResolutionPlaybackController.track_for(events, hex_grid, MovementResolutionPlaybackController._model_angle(0))
	var start: Vector3 = MovementResolutionPlaybackController.pose_at(track, 0.0)[0]
	var finish: Vector3 = MovementResolutionPlaybackController.pose_at(track, 4.0)[0]
	var total := start.distance_to(finish)
	var early: float = start.distance_to(MovementResolutionPlaybackController.pose_at(track, 0.4)[0])
	var middle: float = MovementResolutionPlaybackController.pose_at(track, 1.8)[0].distance_to(MovementResolutionPlaybackController.pose_at(track, 2.2)[0])
	assert_lt(early, middle, "slow off the mark, fastest mid-glide")
	assert_almost_eq(MovementResolutionPlaybackController.pose_at(track, 2.0)[0].distance_to(start), total * 0.5, 0.0001, "halfway at mid-time")


func test_segments_where_nobody_moves_take_no_clock_time() -> void:
	var clock := MovementResolutionPlaybackController.moving_clock([4, 0, 3])
	assert_eq(clock, {0: 0, 3: 1, 4: 2})
	var events := _moves("d", [0, 3, 4])
	var track: MovementResolutionPlaybackController.GlideTrack = MovementResolutionPlaybackController.track_for(events, hex_grid, MovementResolutionPlaybackController._model_angle(0), clock)
	assert_eq(track.t0, 0.0)
	assert_eq(track.t1, 3.0, "three moving segments, not five")
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 3.0), events[-1], "still exact on arrival")
	assert_eq(MovementResolutionPlaybackController.moving_clock([]), {})


func test_glide_seconds_default_without_sea_model() -> void:
	var saved := SeaModel.instance
	SeaModel.instance = null
	assert_eq(MovementResolutionPlaybackController.glide_seconds(), 0.8)
	SeaModel.instance = saved


## ============================================================================
## Live playback
## ============================================================================

func _state(ship_id: String, bow: Vector2i, facing: int) -> ShipState:
	var ship_state = ShipState.new()
	ship_state.ship = Ship.from_dict({
		"ship_id": ship_id, "player_id": 0, "ship_name": ship_id, "ship_type": "frigate_38",
		"rating": 38, "class": 3, "rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3], "marine_count": 2,
	})
	ship_state.hex_position = bow
	ship_state.facing = facing
	ship_state.sail_state = "MS"
	ship_state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	ship_state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	return ship_state


func test_final_pose_unchanged() -> void:
	var events := _moves("live", [0, 1, 2], 1)
	var view := ShipView.new()
	add_child_autofree(view)
	view.initialize(_state("live", Vector2i(2, 5), 0), hex_grid)
	var pb := StretchPoseSpy.new(hex_grid, {"live": view}, 0)
	add_child_autofree(pb)

	var log := MovementTypes.ResolutionLog.new(1)
	log.max_impulses = 3
	var result := MovementTypes.ShipResolutionResult.new("live")
	for ev in events:
		result.events.append(ev)
	var contest := MovementTypes.ResolutionEvent.new("live", 1, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL)
	result.events.append(contest)
	result.final_hex = events[-1].to_hex
	result.final_facing = events[-1].facing
	log.add_result(result)

	pb.play(log)
	await wait_for_signal(pb.playback_completed, 10.0)

	assert_eq(pb.stretches, [[0, 1], [2, 2]], "split at the contest")
	if pb.poses.size() == 2:
		var at_event: Array = pb.poses[0]["live"]
		var expected := hex_grid.ship_center_world(events[1].to_hex, events[1].facing)
		assert_almost_eq(at_event[0].x, expected.x, 0.001, "on the event hex when the pause starts")
		assert_almost_eq(at_event[0].z, expected.z, 0.001)
		assert_almost_eq(at_event[1], MovementResolutionPlaybackController._model_angle(events[1].facing), 0.01)
	var final := hex_grid.ship_center_world(result.final_hex, result.final_facing)
	assert_almost_eq(view.base_position.x, final.x, 0.001, "final pose unchanged")
	assert_almost_eq(view.base_position.z, final.z, 0.001)
	assert_almost_eq(view.model_node.rotation_degrees.y, MovementResolutionPlaybackController._model_angle(result.final_facing), 0.01)


## Records the pose the first glide frame puts the view in.
class FirstFrameSpy extends MovementResolutionPlaybackController:
	var first_pose: Array = []  # [base_position, model yaw]

	func _pose_tracks(t: float, tracks: Array) -> void:
		super(t, tracks)
		if first_pose.is_empty() and not tracks.is_empty():
			var view: ShipView = tracks[0].view
			first_pose = [view.base_position, view.model_node.rotation_degrees.y]


func test_resume_after_bear_off_pause_starts_from_the_paused_pose() -> void:
	var events := _moves("live", [0, 1, 2, 3], 1)
	var view := ShipView.new()
	add_child_autofree(view)
	view.initialize(_state("live", Vector2i(2, 5), 0), hex_grid)

	var paused_log := MovementTypes.ResolutionLog.new(1)
	paused_log.max_impulses = 4
	paused_log.pending_bear_off = MovementTypes.BearOffSituation.new()
	paused_log.pending_bear_off.segment = 2
	var r1 := MovementTypes.ShipResolutionResult.new("live")
	for ev in _in_range(events, 0, 1):
		r1.events.append(ev)
	paused_log.add_result(r1)
	var first := MovementResolutionPlaybackController.new(hex_grid, {"live": view}, 0)
	add_child_autofree(first)
	first.play(paused_log)
	await wait_for_signal(first.playback_paused, 10.0)
	var paused_position := view.base_position
	var paused_yaw := view.model_node.rotation_degrees.y

	var resumed_log := MovementTypes.ResolutionLog.new(1)
	resumed_log.max_impulses = 4
	resumed_log.resume_impulse = 2
	var r2 := MovementTypes.ShipResolutionResult.new("live")
	for ev in events:
		r2.events.append(ev)
	resumed_log.add_result(r2)
	var second := FirstFrameSpy.new(hex_grid, {"live": view}, 0)
	add_child_autofree(second)
	second.play(resumed_log)
	await wait_for_signal(second.playback_completed, 10.0)

	assert_false(second.first_pose.is_empty(), "the resumed log glided")
	assert_lt(second.first_pose[0].distance_to(paused_position), 0.05, "no jump in position on resume")
	assert_almost_eq(second.first_pose[1], paused_yaw, 1.0, "no jump in heading on resume")
