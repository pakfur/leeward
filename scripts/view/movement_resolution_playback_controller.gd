class_name MovementResolutionPlaybackController
extends Node
## Consumes a ResolutionLog and animates ships hex-by-hex.
## Pauses for contested-hex surrender / bear-off prompts on player ships.
## Emits playback_completed when done.

signal playback_completed()

const IMPULSE_DURATION_MS: float = 200.0
const IMPULSE_GAP_MS: float = 50.0
const EVENT_PAUSE_MS: float = 400.0

var _hex_grid: HexGrid = null
var _ship_views: Dictionary = {}  # ship_id -> ShipView
var _log: MovementTypes.ResolutionLog = null
var _playing: bool = false
var _player_id: int = 0


func _init(p_hex_grid: HexGrid = null, p_ship_views: Dictionary = {}, p_player_id: int = 0) -> void:
	_hex_grid = p_hex_grid
	_ship_views = p_ship_views
	_player_id = p_player_id


@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func play(log: MovementTypes.ResolutionLog) -> void:
	if _playing:
		return
	_log = log
	_playing = true
	Trace.trace_log("Playback", "start", {"turn": log.turn, "max_impulses": log.max_impulses, "ships": log.ship_results.size()})
	# Yield one frame so callers can set up signal listeners before we emit
	await _yield_frame()
	await _play_all_impulses()
	_playing = false
	Trace.trace_log("Playback", "complete", {"turn": log.turn})
	playback_completed.emit()


func is_playing() -> bool:
	return _playing


## ============================================================================
## Core playback loop
## ============================================================================

func _play_all_impulses() -> void:
	var events_by_impulse: Dictionary = _group_events_by_impulse()

	# Play pre-impulse events (impulse -1 equivalent: tacking rolls, in-irons, skip_no_plot at impulse 0)
	var pre_events: Array = _collect_pre_movement_events()
	if not pre_events.is_empty():
		await _play_event_batch(pre_events)

	for impulse in range(_log.max_impulses):
		var impulse_events: Array = events_by_impulse.get(impulse, [])
		if impulse_events.is_empty():
			continue

		# Separate move events from special events for this impulse
		var move_events: Array = []
		var special_events: Array = []
		for ev in impulse_events:
			if ev.event_type == MovementTypes.ResolutionEventType.MOVE:
				move_events.append(ev)
			else:
				special_events.append(ev)

		# Animate all moves for this impulse simultaneously
		if not move_events.is_empty():
			await _animate_moves(move_events)

		# Play special events (contests, collisions, etc.) with pauses
		if not special_events.is_empty():
			await _play_event_batch(special_events)

		# Brief gap between impulses
		if impulse < _log.max_impulses - 1:
			await _wait_ms(IMPULSE_GAP_MS)


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

func _animate_moves(move_events: Array) -> void:
	var tweens: Array = []
	for ev in move_events:
		var view: ShipView = _ship_views.get(ev.ship_id)
		if not view or not _hex_grid:
			continue

		var from_world: Vector3 = _hex_grid.axial_to_world(ev.from_hex.x, ev.from_hex.y)
		var to_world: Vector3 = _hex_grid.axial_to_world(ev.to_hex.x, ev.to_hex.y)
		from_world.y = 0.0
		to_world.y = 0.0

		var tween: Tween = view.create_tween()
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_SINE)

		# Animate position
		tween.tween_property(view, "base_position", to_world, IMPULSE_DURATION_MS / 1000.0)

		# Animate facing if changed
		var target_angle: float = -ev.facing * 60.0 - 90.0
		if view.model_node:
			var current_angle: float = view.model_node.rotation_degrees.y
			var diff: float = _shortest_angle(current_angle, target_angle)
			if abs(diff) > 0.5:
				tween.parallel().tween_property(
					view.model_node, "rotation_degrees",
					Vector3(0, current_angle + diff, 0),
					IMPULSE_DURATION_MS / 1000.0
				)

		tweens.append(tween)

	# Wait for all tweens to finish
	for tween in tweens:
		if tween.is_running():
			await tween.finished


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
			MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
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
	if not is_inside_tree():
		return
	await get_tree().create_timer(ms / 1000.0).timeout


func _yield_frame() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
