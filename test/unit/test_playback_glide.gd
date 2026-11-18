extends GutTest
## The glide playback (sea-state spec D, proportional-movement spec §6): one clock for the turn, each
## ship gliding at its own pace; the clock halts on every segment that carries an event, and every
## ship arrives exactly on the resolver's pose.


var hex_grid: HexGrid


## Records the ship views' poses at the end of every glide of the clock.
class StretchPoseSpy extends MovementResolutionPlaybackController:
	var stretches: Array = []  # [from_clock, to_clock] per glide of the clock
	var poses: Array = []  # {ship_id: [base_position, model yaw]} at each glide end

	func _glide_clock(from_clock: float, to_clock: float, tracks: Array) -> void:
		await super(from_clock, to_clock, tracks)
		stretches.append([from_clock, to_clock])
		var snap := {}
		for sid in _ship_views:
			var view: ShipView = _ship_views[sid]
			snap[sid] = [view.base_position, view.model_node.rotation_degrees.y]
		poses.append(snap)


func before_each() -> void:
	hex_grid = HexGrid.new()


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


## Clocks for `n` equal segments: segment i ends at clock i + 1.
func _clocks(n: int) -> Array:
	var clocks: Array = []
	for i in range(n):
		clocks.append(float(i + 1))
	return clocks


## Gives a hand-built log the resolver's timing for equal plots of `max_impulses` steps.
@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func _timed(log: MovementTypes.ResolutionLog) -> MovementTypes.ResolutionLog:
	var n: int = log.max_impulses
	log.segment_times = []
	for i in range(n):
		log.segment_times.append(Vector2i(i + 1, n))
	log.longest_plot = n
	for ship_id in log.ship_results:
		log.plot_steps[ship_id] = n
	return log


func _assert_pose(pose: Array, ev: MovementTypes.ResolutionEvent, what: String) -> void:
	var bow := hex_grid.axial_to_world(ev.to_hex.x, ev.to_hex.y)
	assert_almost_eq(pose[0].x, bow.x, 0.0001, what + ": bow x")
	assert_almost_eq(pose[0].z, bow.z, 0.0001, what + ": bow z")
	assert_almost_eq(fposmod(pose[1] - MovementResolutionPlaybackController._model_angle(ev.facing) + 180.0, 360.0) - 180.0, 0.0, 0.0001,
		what + ": heading")


func test_pose_at_event_segment_matches_resolver() -> void:
	var events := _moves("a", [0, 1, 2, 3, 4, 5], 2)
	var track := MovementResolutionPlaybackController.track_for(events, hex_grid,
		MovementResolutionPlaybackController._model_angle(0), _clocks(6), 6, 6)
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 3.0), events[2], "at the clock of the event segment")
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 6.0), events[-1], "at the end")
	var start_bow := hex_grid.axial_to_world(events[0].from_hex.x, events[0].from_hex.y)
	assert_almost_eq(MovementResolutionPlaybackController.pose_at(track, 0.0)[0].distance_to(start_bow), 0.0, 0.0001,
		"starts on the pose before the first step")


func test_pose_at_event_segment_for_ship_idle_at_the_event() -> void:
	# Moved on segment 0 only; the event is on segment 2: the ship has arrived long before the pause.
	var events := _moves("b", [0])
	var track := MovementResolutionPlaybackController.track_for(events, hex_grid,
		MovementResolutionPlaybackController._model_angle(0), _clocks(3), 3, 3)
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 3.0), events[0], "at the event")
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 1.0), events[0], "on arrival")


func test_glide_accelerates_and_decelerates() -> void:
	var events := _moves("c", [0, 1, 2, 3])
	var track := MovementResolutionPlaybackController.track_for(events, hex_grid,
		MovementResolutionPlaybackController._model_angle(0), _clocks(4), 4, 4)
	var start: Vector3 = MovementResolutionPlaybackController.pose_at(track, 0.0)[0]
	var finish: Vector3 = MovementResolutionPlaybackController.pose_at(track, 4.0)[0]
	var total := start.distance_to(finish)
	var early: float = start.distance_to(MovementResolutionPlaybackController.pose_at(track, 0.4)[0])
	var middle: float = MovementResolutionPlaybackController.pose_at(track, 1.8)[0].distance_to(MovementResolutionPlaybackController.pose_at(track, 2.2)[0])
	assert_lt(early, middle, "slow off the mark, fastest mid-glide")
	var late: float = finish.distance_to(MovementResolutionPlaybackController.pose_at(track, 3.6)[0])
	assert_lt(late, middle, "slows to a stop")
	assert_almost_eq(MovementResolutionPlaybackController.pose_at(track, 2.0)[0].distance_to(start), total * 0.5, 0.0001, "halfway at mid-time")


func test_ship_holds_its_pose_between_its_steps() -> void:
	# A 4-MP ship that moved on segments 0 and 3 only (it waited in between): it holds the pose after
	# its first step until its second step's glide starts, one unit before that step's clock.
	var events := _moves("d", [0, 3])
	var track := MovementResolutionPlaybackController.track_for(events, hex_grid,
		MovementResolutionPlaybackController._model_angle(0), _clocks(4), 4, 4)
	assert_eq(track.spans, [[0.0, 1.0], [3.0, 4.0]])
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 2.0), events[0], "waiting")
	_assert_pose(MovementResolutionPlaybackController.pose_at(track, 4.0), events[-1], "still exact on arrival")


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
	_timed(log)

	pb.play(log)
	await wait_for_signal(pb.playback_completed, 10.0)

	assert_eq(pb.stretches, [[0.0, 2.0], [2.0, 3.0]], "the clock halts at the contest")
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
	_timed(paused_log)
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
	_timed(resumed_log)
	var second := FirstFrameSpy.new(hex_grid, {"live": view}, 0)
	add_child_autofree(second)
	second.play(resumed_log)
	await wait_for_signal(second.playback_completed, 10.0)

	assert_false(second.first_pose.is_empty(), "the resumed log glided")
	assert_lt(second.first_pose[0].distance_to(paused_position), 0.05, "no jump in position on resume")
	assert_almost_eq(second.first_pose[1], paused_yaw, 1.0, "no jump in heading on resume")
