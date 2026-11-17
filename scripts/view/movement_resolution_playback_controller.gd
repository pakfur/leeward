class_name MovementResolutionPlaybackController
extends Node
## Consumes a ResolutionLog and animates the ships' moves, from the log's resume_impulse.
## Each ship's move is a continuous glide (sea-state spec D): the segments are split into stretches
## at every segment that carries an event (collision, contested hex, overlap rollback, stern contest,
## bear-off roll, ...); within a stretch each ship speeds up and slows down along its steps and
## arrives exactly on its resolved pose for the stretch's last segment, the event pause plays, and the
## next stretch starts from there. `glide_seconds` per segment comes from the sea state's preset.
## A complete log ends with playback_completed. An incomplete one (a potential collision waiting for
## the player's bear-off decision, 6.D.3) is played up to that segment and ends with playback_paused;
## the re-run log that follows the answer is played from there, starting from the paused poses.

signal playback_completed()
signal playback_paused()

const EVENT_PAUSE_MS: float = 400.0
const DEFAULT_GLIDE_SECONDS: float = 0.8  # without a sea model (headless tests)


## One ship's glide through one stretch: its poses (bow world position, model angle in degrees,
## unwrapped so each step turns the short way) before its first step and after each step, played
## over the clock span [t0, t1] (in segments) with a trapezoidal speed profile.
class GlideTrack:
	var view: ShipView = null
	var keys: Array = []  # [[bow: Vector3, angle: float]]
	var t0: float = 0.0
	var t1: float = 0.0


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
	Trace.trace_log("Playback", "start", {"turn": log.turn, "max_impulses": log.max_impulses, "ships": log.ship_results.size()})
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
	var events_by_impulse: Dictionary = _group_events_by_impulse()

	# Play pre-impulse events (impulse -1 equivalent: tacking rolls, in-irons, skip_no_plot at impulse 0),
	# unless an earlier log of this turn already showed them.
	var pre_events: Array = _collect_pre_movement_events()
	if not pre_events.is_empty() and _log.resume_impulse == 0:
		await _play_event_batch(pre_events)

	# Sort every segment's events, in order (_posed_events follows the swing outs from one to the next).
	var last_impulse: int = _log.max_impulses if _log.is_complete() else _log.pending_bear_off.segment
	_posed_by_impulse = {}
	var special_by_impulse: Dictionary = {}
	var event_segments: Array[int] = []
	for impulse in range(_log.resume_impulse, last_impulse):
		var impulse_events: Array = events_by_impulse.get(impulse, [])
		_posed_by_impulse[impulse] = _posed_events(impulse_events)
		var special: Array = _special_events(impulse_events, pre_events)
		if not special.is_empty():
			special_by_impulse[impulse] = special
			event_segments.append(impulse)

	for stretch in glide_stretches(event_segments, _log.resume_impulse, last_impulse - 1):
		if _aborted:
			return
		await _glide_stretch(stretch[0], stretch[1])
		if _aborted:
			return
		# Play special events (contests, collisions, etc.) with pauses, every ship on its pose
		if special_by_impulse.has(stretch[1]):
			await _play_event_batch(special_by_impulse[stretch[1]])


## The segment ranges [first, last] (inclusive) of the glide from `first_segment` to `last_segment`,
## split after every segment in `event_segments`: each stretch ends on an event segment or on the last.
static func glide_stretches(event_segments: Array[int], first_segment: int, last_segment: int) -> Array:
	var stretches: Array = []
	var start := first_segment
	for seg in range(first_segment, last_segment + 1):
		if seg == last_segment or event_segments.has(seg):
			stretches.append([start, seg])
			start = seg + 1
	return stretches


## The events of one impulse that move a ship view: every MOVE, and a rolled-back turn (6.B.4) shown
## as the stern swinging out (OVERLAP) and, on the next impulse, back (OVERLAP_ROLLBACK). The swing is
## shown only when the ship makes no step on the overlap impulse; a ship that moves ahead instead (to
## meet its deceleration) just plays its moves, which start from the pose before the turn.
func _posed_events(impulse_events: Array) -> Array:
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
				if not moving.has(ev.ship_id) and _was_rolled_back(ev.ship_id):
					_swung_out[ev.ship_id] = true
					posed.append(ev)
			MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK:
				if _swung_out.has(ev.ship_id):
					_swung_out.erase(ev.ship_id)
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


func _was_rolled_back(ship_id: String) -> bool:
	var result: MovementTypes.ShipResolutionResult = _log.get_result(ship_id) if _log else null
	if result == null:
		return false
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK:
			return true
	return false


## ============================================================================
## Event grouping
## ============================================================================

func _group_events_by_impulse() -> Dictionary:
	var grouped: Dictionary = {}
	for ship_id in _log.ship_results:
		var result: MovementTypes.ShipResolutionResult = _log.ship_results[ship_id]
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

## Glide every ship through the segments [first, last]: one clock for all of them, from the first
## step any ship makes to the last, `glide_seconds` per segment. Every ship ends on its resolved pose.
func _glide_stretch(first: int, last: int) -> void:
	var tracks: Array = []
	for ship_id in _ship_views:
		var steps: Array = []
		for impulse in range(first, last + 1):
			for ev in _posed_by_impulse.get(impulse, []):
				if ev.ship_id == ship_id:
					steps.append(ev)
		var view: ShipView = _ship_views[ship_id]
		if steps.is_empty() or not is_instance_valid(view) or not _hex_grid:
			continue
		var start_angle: float = view.model_node.rotation_degrees.y if view.model_node \
			else _model_angle(steps[0].from_facing)
		var track := track_for(steps, _hex_grid, start_angle)
		track.view = view
		tracks.append(track)
	if tracks.is_empty() or _aborted:
		return
	var t0: float = tracks[0].t0
	var t1: float = tracks[0].t1
	for track in tracks:
		t0 = minf(t0, track.t0)
		t1 = maxf(t1, track.t1)
	if not is_inside_tree():
		_pose_tracks(t1, tracks)
		return
	var tween := create_tween()
	tween.tween_method(_pose_tracks.bind(tracks), t0, t1, (t1 - t0) * glide_seconds())
	await tween.finished
	_pose_tracks(t1, tracks)  # exactly on the resolved poses, whatever the last frame's time


## Seconds per segment of the glide: the current sea state's preset, or the default without a model.
static func glide_seconds() -> float:
	var sea := SeaModel.instance
	return sea.glide_seconds if is_instance_valid(sea) else DEFAULT_GLIDE_SECONDS


## The glide track for one ship's posed events `steps` (in order, all in one stretch), starting at
## model angle `start_angle` (the view's current heading, so the angle stays continuous).
static func track_for(steps: Array, hex_grid: HexGrid, start_angle: float) -> GlideTrack:
	var track := GlideTrack.new()
	track.t0 = float(steps[0].impulse)
	track.t1 = float(steps[-1].impulse + 1)
	track.keys.append([hex_grid.axial_to_world(steps[0].from_hex.x, steps[0].from_hex.y), start_angle])
	for ev in steps:
		var prev_angle: float = track.keys[-1][1]
		var to_angle: float = prev_angle + _shortest_angle(prev_angle, _model_angle(ev.facing))
		track.keys.append([hex_grid.axial_to_world(ev.to_hex.x, ev.to_hex.y), to_angle])
	return track


## The pose [bow world position, model angle] of `track` at clock time `t` (segments): before t0 the
## pose before the first step, after t1 the pose after the last, in between the steps spread over the
## span with a gentle start and stop.
static func pose_at(track: GlideTrack, t: float) -> Array:
	var steps: int = track.keys.size() - 1
	if steps <= 0:
		return track.keys[0]
	var s := clampf((t - track.t0) / maxf(track.t1 - track.t0, 0.001), 0.0, 1.0)
	var accel := clampf(0.6 / float(steps), 0.15, 0.5)
	var u := _trapezoid(s, accel) * float(steps)
	var k := mini(floori(u), steps - 1)
	var a: Array = track.keys[k]
	var b: Array = track.keys[k + 1]
	var f := u - float(k)
	return [a[0].lerp(b[0], f), lerpf(a[1], b[1], f)]


## Distance (0..1) at time s (0..1) for a speed that ramps up over `a`, holds, and ramps down over `a`.
static func _trapezoid(s: float, a: float) -> float:
	var vmax := 1.0 / (1.0 - a)
	if s < a:
		return vmax * s * s / (2.0 * a)
	if s > 1.0 - a:
		var r := 1.0 - s
		return 1.0 - vmax * r * r / (2.0 * a)
	return vmax * (s - a * 0.5)


func _pose_tracks(t: float, tracks: Array) -> void:
	for track in tracks:
		if is_instance_valid(track.view):
			var pose: Array = pose_at(track, t)
			_place(track.view, pose[0], pose[1])


## Model Y rotation (degrees) for a facing; matches ShipView._update_rotation_from_state.
static func _model_angle(facing: int) -> float:
	return -facing * 60.0 - 90.0


## Pose `view` a fraction `t` of the way through a step: the bow slides from `from_bow` to
## `to_bow` (both world positions of hex centres) while the heading turns from `from_angle` to
## `to_angle`.
func _pose_ship(t: float, view: ShipView, from_bow: Vector3, to_bow: Vector3, from_angle: float, to_angle: float) -> void:
	if not is_instance_valid(view):
		return
	_place(view, from_bow.lerp(to_bow, t), lerpf(from_angle, to_angle, t))


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
