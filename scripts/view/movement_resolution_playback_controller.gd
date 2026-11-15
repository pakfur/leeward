class_name MovementResolutionPlaybackController
extends Node
## Consumes a ResolutionLog and animates ships hex-by-hex, from the log's resume_impulse.
## A complete log ends with playback_completed. An incomplete one (a potential collision waiting for
## the player's bear-off decision, 6.D.3) is played up to that segment and ends with playback_paused;
## the re-run log that follows the answer is played from there.

signal playback_completed()
signal playback_paused()

const IMPULSE_DURATION_MS: float = 200.0
const IMPULSE_GAP_MS: float = 50.0
const EVENT_PAUSE_MS: float = 400.0

var _hex_grid: HexGrid = null
var _ship_views: Dictionary = {}  # ship_id -> ShipView
var _log: MovementTypes.ResolutionLog = null
var _playing: bool = false
var _aborted: bool = false  # the game is being left: stop and never report completion
var _player_id: int = 0
var _swung_out: Dictionary = {}  # ship_id -> true while a rolled-back turn is shown swung out


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

	var last_impulse: int = _log.max_impulses if _log.is_complete() else _log.pending_bear_off.segment
	for impulse in range(_log.resume_impulse, last_impulse):
		if _aborted:
			return
		var impulse_events: Array = events_by_impulse.get(impulse, [])
		if impulse_events.is_empty():
			continue

		# Separate the events that pose a ship from special events for this impulse
		var move_events: Array = _posed_events(impulse_events)
		var special_events: Array = _special_events(impulse_events, pre_events)

		# Animate all moves for this impulse simultaneously
		if not move_events.is_empty():
			await _animate_moves(move_events)

		# Play special events (contests, collisions, etc.) with pauses
		if not special_events.is_empty():
			await _play_event_batch(special_events)

		# Brief gap between impulses
		if impulse < _log.max_impulses - 1:
			await _wait_ms(IMPULSE_GAP_MS)


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
				or t == MovementTypes.ResolutionEventType.SKIP_NO_PLOT \
				or t == MovementTypes.ResolutionEventType.IMMOBILIZED:
				pre.append(ev)
	return pre


## ============================================================================
## Animation
## ============================================================================

## Each posed event is one tween per ship: an ahead step slides the ship one hex along its keel; a
## turn (or an overlap swing out or back) keeps the bow hex and swings the stern round it. The ship
## view is placed by its centre, midway between bow and stern (HexGrid.ship_center_world), so both are
## driven from the bow.
func _animate_moves(move_events: Array) -> void:
	if _aborted:
		return
	var tweens: Array = []
	for ev in move_events:
		var view: ShipView = _ship_views.get(ev.ship_id)
		if not view or not _hex_grid:
			continue

		var from_bow: Vector3 = _hex_grid.axial_to_world(ev.from_hex.x, ev.from_hex.y)
		var to_bow: Vector3 = _hex_grid.axial_to_world(ev.to_hex.x, ev.to_hex.y)
		var from_angle: float = _model_angle(ev.from_facing)
		if view.model_node:
			from_angle = view.model_node.rotation_degrees.y
		var to_angle: float = from_angle + _shortest_angle(from_angle, _model_angle(ev.facing))

		var tween: Tween = view.create_tween()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_method(_pose_ship.bind(view, from_bow, to_bow, from_angle, to_angle),
			0.0, 1.0, IMPULSE_DURATION_MS / 1000.0)
		tweens.append(tween)

	# Wait for all tweens to finish
	for tween in tweens:
		if tween.is_running():
			await tween.finished


## Model Y rotation (degrees) for a facing; matches ShipView._update_rotation_from_state.
static func _model_angle(facing: int) -> float:
	return -facing * 60.0 - 90.0


## Pose `view` a fraction `t` of the way through a step: the bow slides from `from_bow` to
## `to_bow` (both world positions of hex centres) while the heading turns from `from_angle` to
## `to_angle`; the centre lies half a hex astern of the bow along the current heading.
func _pose_ship(t: float, view: ShipView, from_bow: Vector3, to_bow: Vector3, from_angle: float, to_angle: float) -> void:
	if not is_instance_valid(view):
		return
	var angle := lerpf(from_angle, to_angle, t)
	var rad := deg_to_rad(angle)
	var astern := Vector3(sin(rad), 0.0, cos(rad))  # the model's +Z (its bow is -Z) in world space
	var bow := from_bow.lerp(to_bow, t)
	var half_length := _hex_grid.hex_size * HexGrid.SQRT3 / 2.0
	view.base_position = Vector3(bow.x, 0.0, bow.z) + astern * half_length
	if view.model_node:
		view.model_node.rotation_degrees = Vector3(0, angle, 0)


func _shortest_angle(from_deg: float, to_deg: float) -> float:
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
