class_name MovementResolutionPlaybackController
extends Node
## Consumes a ResolutionLog and animates the ships' moves, from the log's resume_impulse.
## One clock runs for the whole turn (proportional-movement spec §6): a segment's clock is its time ×
## the longest plot (see `segment_clocks`), so one clock unit is one MP of the fastest ship. Each ship
## glides at its own pace on that clock (an N-MP ship takes longest_plot / N units a step), so every
## ship that completes its plot arrives at the same moment. The clock halts at every segment that
## carries an event (collision, contested hex, overlap rollback, stern contest, bear-off roll, ...)
## for its pause, every ship holding its pose, mid-glide if it is between steps, and then goes on.
## `glide_seconds` per clock unit comes from the sea state's preset.
## A complete log ends with playback_completed. An incomplete one (a potential collision waiting for
## the player's bear-off decision, 6.D.3) is played up to that segment and ends with playback_paused;
## the re-run log that follows the answer is played from there, starting from the paused poses.

signal playback_completed()
signal playback_paused()

const EVENT_PAUSE_MS: float = 400.0
const DEFAULT_GLIDE_SECONDS: float = 0.8  # without a sea model (headless tests)


## One ship's glide through the log: its poses (bow world position, model angle in degrees, unwrapped
## so each step turns the short way) before its first step and after each step, and the clock span
## [start, end] of each glide from one key to the next (keys.size() == spans.size() + 1).
class GlideTrack:
	var view: ShipView = null
	var keys: Array = []  # [[bow: Vector3, angle: float]]
	var spans: Array = []  # [[start_clock: float, end_clock: float]], one per glide


var _hex_grid: HexGrid = null
var _ship_views: Dictionary = {}  # ship_id -> ShipView
var _log: MovementTypes.ResolutionLog = null
var _playing: bool = false
var _aborted: bool = false  # the game is being left: stop and never report completion
var _player_id: int = 0
var _swung_out: Dictionary = {}  # ship_id -> true while a rolled-back turn is shown swung out
var _posed_by_impulse: Dictionary = {}  # impulse -> the events that pose a ship (see _posed_events)


func _init(p_hex_grid: HexGrid = null, p_ship_views: Dictionary = {}, p_player_id: int = 0) -> void:
	_hex_grid = p_hex_grid
	_ship_views = p_ship_views
	_player_id = p_player_id


@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func play(log: MovementTypes.ResolutionLog) -> void:
	if _playing:
		return
	_log = log
	_swung_out = {}
	_playing = true
	Trace.trace_log("Playback", "start", {"turn": log.turn, "max_impulses": log.max_impulses, "longest_plot": log.longest_plot, "ships": log.ship_results.size()})
	# Yield one frame so callers can set up signal listeners before we emit
	await _yield_frame()
	if not _aborted:
		await _play_all_impulses()
	_playing = false
	if _aborted:
		return
	if not log.is_complete():
		Trace.trace_log("Playback", "paused", {"turn": log.turn, "segment": log.pending_bear_off.segment})
		playback_paused.emit()
		return
	Trace.trace_log("Playback", "complete", {"turn": log.turn})
	playback_completed.emit()


func is_playing() -> bool:
	return _playing


## Abandon the playback (leaving the game): no further steps, playback_completed never emitted.
func abort() -> void:
	_aborted = true
	_playing = false


func is_aborted() -> bool:
	return _aborted


## ============================================================================
## Core playback loop
## ============================================================================

func _play_all_impulses() -> void:
	var events_by_impulse: Dictionary = _group_events_by_impulse(_log)

	# Play pre-impulse events (impulse -1 equivalent: tacking rolls, in-irons, skip_no_plot at impulse 0),
	# unless an earlier log of this turn already showed them.
	var pre_events: Array = _collect_pre_movement_events()
	if not pre_events.is_empty() and _log.resume_impulse == 0:
		await _play_event_batch(pre_events)
	if _aborted:
		return

	# One clock from the resume clock to the stop clock: the end of the last posed event for a complete
	# log, the segment before the pending decision for a paused one (its tracks stop there too).
	var clocks: Array[float] = segment_clocks(_log.segment_times, _log.longest_plot)
	var last_impulse: int = _log.max_impulses if _log.is_complete() else _log.pending_bear_off.segment
	var start_clock: float = _clock_before(clocks, _log.resume_impulse)
	var stop_clock: float = end_clock(_log) if _log.is_complete() else _clock_before(clocks, last_impulse)

	# Sort every segment's events, in order (_posed_events follows the swing outs from one to the next).
	_posed_by_impulse = {}
	var halts: Array = []  # [clock, special events] per segment with special events, in order
	for impulse in range(_log.resume_impulse, last_impulse):
		var impulse_events: Array = events_by_impulse.get(impulse, [])
		_posed_by_impulse[impulse] = _posed_events(impulse_events)
		var special: Array = _special_events(impulse_events, pre_events)
		if not special.is_empty():
			halts.append([_clock_at(clocks, impulse), special])

	var tracks: Array = _tracks(clocks, start_clock)
	var clock := start_clock
	for halt in halts:
		if halt[0] > clock:
			await _glide_clock(clock, halt[0], tracks)
			clock = halt[0]
		if _aborted:
			return
		# Play special events (contests, collisions, etc.) with pauses, every ship holding its pose
		await _play_event_batch(halt[1])
		if _aborted:
			return
	if stop_clock > clock:
		await _glide_clock(clock, stop_clock, tracks)


## The clock value of each segment of `segment_times` (MoveSchedule times): a time t <= 1 is
## t × `longest_plot`, a trailing time k (step k - 1 past a plot) is longest_plot + (k - 1), and the end
## check (MoveSchedule.END) is one unit after the segment before it.
static func segment_clocks(segment_times: Array, longest_plot: int) -> Array[float]:
	var clocks: Array[float] = []
	for t in segment_times:
		if t.y == 0:
			clocks.append((clocks[-1] if not clocks.is_empty() else 0.0) + 1.0)
		elif t.x <= t.y:
			clocks.append(float(t.x) / t.y * longest_plot)
		else:
			clocks.append(float(longest_plot + t.x - 1))
	return clocks


## The clock of `segment`: `clocks[segment]`, or one unit a segment past the last listed one (a log
## built without segment times plays one unit a segment).
static func _clock_at(clocks: Array, segment: int) -> float:
	if segment < 0:
		return 0.0
	if segment < clocks.size():
		return clocks[segment]
	return (clocks[-1] if not clocks.is_empty() else 0.0) + float(segment - clocks.size() + 1)


## The clock at the start of `segment`: the clock of the segment before it, 0.0 for the first.
static func _clock_before(clocks: Array, segment: int) -> float:
	return _clock_at(clocks, segment - 1) if segment > 0 else 0.0


## The clock at which the last posed event of `log` ends (0.0 if none): where a complete log stops.
@warning_ignore("shadowed_global_identifier")
static func end_clock(log: MovementTypes.ResolutionLog) -> float:
	var clocks: Array[float] = segment_clocks(log.segment_times, log.longest_plot)
	var grouped: Dictionary = _group_events_by_impulse(log)
	var impulses: Array = grouped.keys()
	impulses.sort()
	var swung_out: Dictionary = {}
	var last := 0.0
	for impulse in impulses:
		if _posed_in(grouped[impulse], log, swung_out).size() > 0:
			last = maxf(last, _clock_at(clocks, impulse))
	return last


## The events of one impulse that move a ship view (see _posed_in), following this playback's swing
## outs from one impulse to the next.
func _posed_events(impulse_events: Array) -> Array:
	return _posed_in(impulse_events, _log, _swung_out)


## The events of one impulse that move a ship view: every MOVE, and a rolled-back turn (6.B.4) shown
## as the stern swinging out (OVERLAP) and, on the next impulse, back (OVERLAP_ROLLBACK). The swing is
## shown only when the ship makes no step on the overlap impulse; a ship that moves ahead instead (to
## meet its deceleration) just plays its moves, which start from the pose before the turn.
## `swung_out` (ship_id -> true) carries the ships shown swung out from one impulse to the next.
@warning_ignore("shadowed_global_identifier")
static func _posed_in(impulse_events: Array, log: MovementTypes.ResolutionLog, swung_out: Dictionary) -> Array:
	var moving: Dictionary = {}
	for ev in impulse_events:
		if ev.event_type == MovementTypes.ResolutionEventType.MOVE:
			moving[ev.ship_id] = true
	var posed: Array = []
	for ev in impulse_events:
		match ev.event_type:
			MovementTypes.ResolutionEventType.MOVE:
				posed.append(ev)
			MovementTypes.ResolutionEventType.OVERLAP:
				if not moving.has(ev.ship_id) and _was_rolled_back(log, ev.ship_id):
					swung_out[ev.ship_id] = true
					posed.append(ev)
			MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK:
				if swung_out.has(ev.ship_id):
					swung_out.erase(ev.ship_id)
					posed.append(ev)
	return posed


## The events of one impulse played as special events (contests, collisions, ...): everything but
## the MOVEs and OVERLAPs, less those already played before the first impulse (`pre_events`), so a
## tacking roll or a ship with no plot is not told (and paused for) twice. An OVERLAP is shown by the
## swing animation when it is posed (see _posed_events) and needs no pause otherwise; the rollback that
## may follow it is the special event.
static func _special_events(impulse_events: Array, pre_events: Array) -> Array:
	var special: Array = []
	for ev in impulse_events:
		if ev.event_type in [MovementTypes.ResolutionEventType.MOVE, MovementTypes.ResolutionEventType.OVERLAP]:
			continue
		if not pre_events.has(ev):
			special.append(ev)
	return special


@warning_ignore("shadowed_global_identifier")
static func _was_rolled_back(log: MovementTypes.ResolutionLog, ship_id: String) -> bool:
	var result: MovementTypes.ShipResolutionResult = log.get_result(ship_id) if log else null
	if result == null:
		return false
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK:
			return true
	return false


## ============================================================================
## Event grouping
## ============================================================================

@warning_ignore("shadowed_global_identifier")
static func _group_events_by_impulse(log: MovementTypes.ResolutionLog) -> Dictionary:
	var grouped: Dictionary = {}
	for ship_id in log.ship_results:
		var result: MovementTypes.ShipResolutionResult = log.ship_results[ship_id]
		for ev in result.events:
			if not grouped.has(ev.impulse):
				grouped[ev.impulse] = []
			grouped[ev.impulse].append(ev)
	return grouped


func _collect_pre_movement_events() -> Array:
	var pre: Array = []
	for ship_id in _log.ship_results:
		var result: MovementTypes.ShipResolutionResult = _log.ship_results[ship_id]
		for ev in result.events:
			var t = ev.event_type
			if t == MovementTypes.ResolutionEventType.TACKING_ROLL \
				or t == MovementTypes.ResolutionEventType.IN_IRONS_ESCAPE_ROLL \
				or t == MovementTypes.ResolutionEventType.IMMOBILIZED:
				pre.append(ev)
	return pre


## ============================================================================
## Animation
## ============================================================================

## One track per ship view with posed events in this log (in segment order), each glide starting no
## earlier than `start_clock`.
func _tracks(clocks: Array, start_clock: float) -> Array:
	var tracks: Array = []
	if not _hex_grid:
		return tracks
	for ship_id in _ship_views:
		var view: ShipView = _ship_views[ship_id]
		if not is_instance_valid(view):
			continue
		var steps: Array = []
		for impulse in _posed_by_impulse:
			for ev in _posed_by_impulse[impulse]:
				if ev.ship_id == ship_id:
					steps.append(ev)
		if steps.is_empty():
			continue
		var start_angle: float = view.model_node.rotation_degrees.y if view.model_node \
			else _model_angle(steps[0].from_facing)
		var track := track_for(steps, _hex_grid, start_angle, clocks, _log.longest_plot,
			int(_log.plot_steps.get(ship_id, 0)), start_clock)
		track.view = view
		tracks.append(track)
	return tracks


## Run the clock from `from_clock` to `to_clock`, `glide_seconds` a unit, posing every track; every
## ship ends on its pose at `to_clock`.
func _glide_clock(from_clock: float, to_clock: float, tracks: Array) -> void:
	if tracks.is_empty() or _aborted:
		return
	if not is_inside_tree():
		_pose_tracks(to_clock, tracks)
		return
	var tween := create_tween()
	tween.tween_method(_pose_tracks.bind(tracks), from_clock, to_clock, (to_clock - from_clock) * glide_seconds())
	await tween.finished
	_pose_tracks(to_clock, tracks)  # exactly on the poses, whatever the last frame's time


## Seconds per clock unit (one MP of the longest plot): the current sea state's preset, or the default
## without a model.
static func glide_seconds() -> float:
	var sea := SeaModel.instance
	return sea.glide_seconds if is_instance_valid(sea) else DEFAULT_GLIDE_SECONDS


## The glide track for one ship's posed events `events` (in order), starting at model angle
## `start_angle` (the view's current heading, so the angle stays continuous). Glide i ends at the clock
## of its event's segment (`clocks`, from `segment_clocks`) and lasts one step at the ship's pace: `unit`
## = longest_plot / plot_steps for a step within the g-t, 1 for a trailing step or the end check. It
## starts no earlier than the previous glide's end (or `start_clock`, the resume clock, for the first).
static func track_for(events: Array, hex_grid: HexGrid, start_angle: float, clocks: Array, longest_plot: int,
		plot_steps: int, start_clock: float = 0.0) -> GlideTrack:
	var track := GlideTrack.new()
	track.keys.append([hex_grid.axial_to_world(events[0].from_hex.x, events[0].from_hex.y), start_angle])
	var previous_end := start_clock
	for ev in events:
		var prev_angle: float = track.keys[-1][1]
		var to_angle: float = prev_angle + _shortest_angle(prev_angle, _model_angle(ev.facing))
		track.keys.append([hex_grid.axial_to_world(ev.to_hex.x, ev.to_hex.y), to_angle])
		var end := _clock_at(clocks, ev.impulse)
		var unit := float(longest_plot) / plot_steps if plot_steps > 0 and end <= float(longest_plot) else 1.0
		var start := maxf(maxf(previous_end, end - unit), start_clock)
		track.spans.append([start, end])
		previous_end = end
	return track


## The pose [bow world position, model angle] of `track` at clock `t`: before the first glide the pose
## before the first step, after the last the pose after the last step, inside a glide between its two
## keys, and between glides the pose the last finished glide ended on. Each glide is linear, but the
## track eases in on its first glide and out on its last (smoothstep when there is only one), so the
## ship starts and stops gently without a hitch between steps.
static func pose_at(track: GlideTrack, t: float) -> Array:
	var count: int = track.spans.size()
	if count == 0 or t <= track.spans[0][0]:
		return track.keys[0]
	for i in count:
		var span: Array = track.spans[i]
		if t < span[0]:
			return track.keys[i]
		if t <= span[1]:
			var length: float = span[1] - span[0]
			if length <= 0.0:
				return track.keys[i + 1]
			var f := _ease((t - span[0]) / length, i == 0, i == count - 1)
			var a: Array = track.keys[i]
			var b: Array = track.keys[i + 1]
			return [a[0].lerp(b[0], f), lerpf(a[1], b[1], f)]
	return track.keys[-1]


## Distance (0..1) along a glide at time f (0..1): linear, easing in from rest (leaving at full speed,
## so the next glide carries on smoothly), out to rest, or both (smoothstep).
static func _ease(f: float, ease_in: bool, ease_out: bool) -> float:
	if ease_in and ease_out:
		return smoothstep(0.0, 1.0, f)
	if ease_in:
		return f * f * (2.0 - f)
	if ease_out:
		var u := 1.0 - f
		return 1.0 - u * u * (2.0 - u)
	return f


func _pose_tracks(t: float, tracks: Array) -> void:
	for track in tracks:
		if is_instance_valid(track.view):
			var pose: Array = pose_at(track, t)
			_place(track.view, pose[0], pose[1])


## Model Y rotation (degrees) for a facing; matches ShipView._update_rotation_from_state.
static func _model_angle(facing: int) -> float:
	return -facing * 60.0 - 90.0


## Place `view` with its bow at world position `bow` and model angle `angle` (degrees): the centre lies
## half a hex astern of the bow along the heading. Ship motion reads `base_position` and the yaw; the
## sea's pitch and roll on the model are kept.
func _place(view: ShipView, bow: Vector3, angle: float) -> void:
	var rad := deg_to_rad(angle)
	var astern := Vector3(sin(rad), 0.0, cos(rad))  # the model's +Z (its bow is -Z) in world space
	var half_length := _hex_grid.hex_size * HexGrid.SQRT3 / 2.0
	view.base_position = Vector3(bow.x, 0.0, bow.z) + astern * half_length
	if view.model_node:
		var r: Vector3 = view.model_node.rotation_degrees
		view.model_node.rotation_degrees = Vector3(r.x, angle, r.z)


static func _shortest_angle(from_deg: float, to_deg: float) -> float:
	var diff: float = fmod(to_deg - from_deg + 180.0, 360.0) - 180.0
	if diff < -180.0:
		diff += 360.0
	return diff


## ============================================================================
## Special event handling
## ============================================================================

func _play_event_batch(events: Array) -> void:
	# Group by type for consolidated display
	var has_contest: bool = false
	var has_bearing_off: bool = false
	var has_collision: bool = false
	var has_fouling: bool = false

	for ev in events:
		match ev.event_type:
			MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL:
				has_contest = true
			MovementTypes.ResolutionEventType.BEARING_OFF_ROLL, MovementTypes.ResolutionEventType.STERN_BLOCKED, \
					MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK:
				has_bearing_off = true
			MovementTypes.ResolutionEventType.COLLISION:
				has_collision = true
			MovementTypes.ResolutionEventType.FOULING:
				has_fouling = true

	# Log all events
	for ev in events:
		Trace.trace_log("Playback", "event", ev.to_dict())

	# Pause on dramatic events so the player can observe
	if has_collision or has_fouling:
		await _wait_ms(EVENT_PAUSE_MS * 2)
	elif has_contest or has_bearing_off:
		await _wait_ms(EVENT_PAUSE_MS)
	else:
		await _wait_ms(EVENT_PAUSE_MS * 0.5)


## ============================================================================
## Utility
## ============================================================================

func _wait_ms(ms: float) -> void:
	if not is_inside_tree() or _aborted:
		return
	# process_always = false: the wait holds while the tree is paused (pause menu open).
	await get_tree().create_timer(ms / 1000.0, false).timeout


func _yield_frame() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
