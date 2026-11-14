extends Camera3D
## IsometricCamera - Handles isometric view with zoom and pan controls

@export var zoom_speed: float = 0.1
@export var min_zoom: float = 2.0  # Allow closer zoom
@export var max_zoom: float = 40.0
@export var pan_speed: float = 2.0  # Increased for better responsiveness
@export var initial_distance: float = 25.0
@export var isometric_angle: float = 85.0  # degrees from horizontal (5 degrees off vertical)
@export var min_rotation_angle: float = 25.0  # minimum angle from horizontal
@export var max_rotation_angle: float = 90.0  # maximum angle (top-down)
@export var rotation_speed: float = 0.2
@export var focus_zoom_distance: float = 15.0  # Distance when focusing on a single ship
@export var focus_animation_duration: float = 0.5  # Duration of focus animation in seconds

var camera_distance: float = 25.0
var camera_target: Vector3 = Vector3.ZERO
## Horizontal orbit angle in degrees: the camera sits at azimuth (cos r, sin r) on the XZ plane
## around its target. 90 puts it south of the target looking north, so north (-Z) is up on
## screen and east (+X) is to the right — the default "north up" view.
const NORTH_UP_ROTATION := 90.0
var camera_rotation_y: float = NORTH_UP_ROTATION
var is_panning: bool = false
var is_rotating: bool = false
var is_tweening: bool = false  # Flag to enable continuous updates during camera tweens
var last_mouse_pos: Vector2 = Vector2.ZERO
var mouse_down_pos: Vector2 = Vector2.ZERO
var drag_threshold: float = 5.0  # pixels before considering it a drag

func _ready() -> void:
	camera_distance = initial_distance
	_update_camera_transform()
	Trace.trace_log("Camera", "Initialized at position: %s, looking at: %s" % [position, camera_target])

func _process(_delta: float) -> void:
	"""Update camera transform continuously during tweening"""
	if is_tweening:
		_update_camera_transform()

func _unhandled_input(event: InputEvent) -> void:
	# Keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			# Center camera hotkey - handled by GameController
			pass  # Don't mark as handled, let GameController handle it

	# macOS trackpad gestures
	# Two-finger pinch for zooming
	if event is InputEventMagnifyGesture:
		var magnify_event = event as InputEventMagnifyGesture
		# factor > 1.0 means zoom in (pinch out), < 1.0 means zoom out (pinch in)
		if magnify_event.factor > 1.0:
			# Zoom in by the magnitude of the gesture
			var zoom_amount = (magnify_event.factor - 1.0) * 2.0  # Scale the gesture
			camera_distance = clamp(camera_distance - zoom_amount * camera_distance * 0.1, min_zoom, max_zoom)
		else:
			# Zoom out
			var zoom_amount = (1.0 - magnify_event.factor) * 2.0
			camera_distance = clamp(camera_distance + zoom_amount * camera_distance * 0.1, min_zoom, max_zoom)
		_update_camera_transform()
		get_viewport().set_input_as_handled()

	# Two-finger pan/scroll for camera panning (or rotation with shift)
	if event is InputEventPanGesture:
		var pan_event = event as InputEventPanGesture
		# Convert trackpad pan delta to camera movement
		var pan_delta = Vector2(pan_event.delta.x, pan_event.delta.y) * 20.0  # Scale for responsiveness

		# If shift is held, rotate camera instead of panning
		if pan_event.shift_pressed:
			rotate_camera(pan_delta)
		else:
			pan_camera(pan_delta)
		get_viewport().set_input_as_handled()

	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()
			get_viewport().set_input_as_handled()

		# Left mouse button for panning (only if dragging)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				mouse_down_pos = event.position
				last_mouse_pos = event.position
			else:
				# If we were panning, mark as handled so click doesn't propagate
				if is_panning:
					get_viewport().set_input_as_handled()
				is_panning = false

		# Right mouse button for rotation
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_rotating = true
				last_mouse_pos = event.position
			else:
				is_rotating = false
			get_viewport().set_input_as_handled()

	# Mouse motion for panning or rotating
	if event is InputEventMouseMotion:
		# Check if left button is held and we've moved enough to start panning
		if not is_panning and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if mouse_down_pos.distance_to(event.position) > drag_threshold:
				is_panning = true

		if is_panning:
			var delta = event.position - last_mouse_pos
			last_mouse_pos = event.position
			pan_camera(delta)
			get_viewport().set_input_as_handled()
		elif is_rotating:
			var delta = event.position - last_mouse_pos
			last_mouse_pos = event.position
			rotate_camera(delta)
			get_viewport().set_input_as_handled()

func zoom_in() -> void:
	camera_distance = clamp(camera_distance - zoom_speed * camera_distance, min_zoom, max_zoom)
	_update_camera_transform()
	#print("Zoom in: %f -> %f" % [old_distance, camera_distance])

func zoom_out() -> void:
	camera_distance = clamp(camera_distance + zoom_speed * camera_distance, min_zoom, max_zoom)
	_update_camera_transform()
	#print("Zoom out: %f -> %f" % [old_distance, camera_distance])

func pan_camera(mouse_delta: Vector2) -> void:
	"""Grab-drag pan: the map follows the mouse. Works on the XZ plane only (no zoom effect)."""
	var rad_rotation = deg_to_rad(camera_rotation_y)
	# Ground-plane directions that appear as screen-right and screen-down. Derived from the
	# orbit angle rather than the camera basis so they stay valid looking straight down.
	var screen_right = Vector3(sin(rad_rotation), 0, -cos(rad_rotation))
	var screen_down = Vector3(cos(rad_rotation), 0, sin(rad_rotation))

	# Adjust pan speed by zoom level (higher speed for better responsiveness)
	var adjusted_speed = pan_speed * camera_distance / initial_distance

	camera_target -= screen_right * mouse_delta.x * adjusted_speed * 0.05
	camera_target -= screen_down * mouse_delta.y * adjusted_speed * 0.05

	_update_camera_transform()

func rotate_camera(mouse_delta: Vector2) -> void:
	# Horizontal rotation (left-right mouse movement): dragging right turns the map clockwise
	camera_rotation_y -= mouse_delta.x * rotation_speed

	# Vertical rotation (up-down mouse movement) - adjusts viewing angle
	isometric_angle -= mouse_delta.y * rotation_speed
	isometric_angle = clamp(isometric_angle, min_rotation_angle, max_rotation_angle)

	_update_camera_transform()

func set_target(target: Vector3) -> void:
	camera_target = target
	_update_camera_transform()

func center_on_ships(ship_positions: Array[Vector3]) -> void:
	"""Center camera on all ships with appropriate zoom to see them all"""
	if ship_positions.is_empty():
		return

	# Calculate bounding box
	var min_pos = ship_positions[0]
	var max_pos = ship_positions[0]

	for pos in ship_positions:
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.z = min(min_pos.z, pos.z)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.z = max(max_pos.z, pos.z)

	# Calculate center of bounding box
	var center = (min_pos + max_pos) / 2.0
	center.y = 0.0  # Keep target at water level

	# Calculate size of bounding box
	var size_x = max_pos.x - min_pos.x
	var size_z = max_pos.z - min_pos.z
	var max_size = max(size_x, size_z)

	# Calculate required distance to fit all ships
	# At 85 degrees, we're almost looking straight down
	# Distance calculation: use diagonal size with padding
	var padding_factor = 2.0  # Extra padding for comfortable view
	# Never frame tighter than the single-ship focus distance (adjacent ships would otherwise
	# zoom in to a few units).
	var required_distance = max(max_size * padding_factor, focus_zoom_distance)

	# Clamp to zoom limits
	required_distance = clamp(required_distance, min_zoom, max_zoom)

	# Set camera parameters (pan/zoom/tilt only: rotation is left to the player)
	camera_target = center
	camera_distance = required_distance
	isometric_angle = 85.0  # Reset to 85 degrees

	_update_camera_transform()
	Trace.trace_log("Camera", "Centered on %d ships at distance %f" % [ship_positions.size(), camera_distance])

func is_world_pos_near_edge(world_pos: Vector3, edge_margin: float = 0.15) -> bool:
	"""True if world_pos is off-screen, behind the camera, or within edge_margin (fraction of
	the viewport size) of a screen edge."""
	if is_position_behind(world_pos):
		return true
	var rect := get_viewport().get_visible_rect()
	var screen_pos := unproject_position(world_pos)
	var margin := rect.size * edge_margin
	var inner := Rect2(rect.position + margin, rect.size - margin * 2.0)
	return not inner.has_point(screen_pos)

func pan_to_if_needed(world_pos: Vector3, edge_margin: float = 0.15) -> bool:
	"""Smoothly pan so world_pos is centred, but only if it is off-screen or near the edge.
	Never rotates and never changes zoom or tilt. Returns true if a pan was started."""
	if not is_world_pos_near_edge(world_pos, edge_margin):
		return false
	var target_pos = world_pos
	target_pos.y = 0.0
	is_tweening = true
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "camera_target", target_pos, focus_animation_duration)
	tween.finished.connect(func():
		is_tweening = false
		_update_camera_transform()
	)
	return true

func focus_on_ship(world_pos: Vector3, ship_facing: int, zoom_distance: float = -1.0) -> void:
	"""
	Focus camera on a specific ship with smooth animation.
	Ship will appear facing "up" on screen. NOTE: this rotates and zooms the camera, so normal
	play does not call it (selection uses pan_to_if_needed); kept for tools/debugging.

	Args:
		world_pos: Ship's world position
		ship_facing: Ship's facing direction (0-5, hex directions)
		zoom_distance: Optional override for focus distance (uses focus_zoom_distance if -1)
	"""
	# Use default focus distance if not specified
	var target_distance = focus_zoom_distance if zoom_distance < 0 else zoom_distance
	target_distance = clamp(target_distance, min_zoom, max_zoom)

	# Calculate camera rotation so ship faces "up" on screen.
	# Hex facing f points at compass bearing 90 + 60f (0=E, 1=SE, ...); screen-up has bearing
	# camera_rotation_y - 90, so the camera must sit at rotation 180 + 60f (behind the ship).
	var target_rotation = ship_facing * 60.0 + 180.0

	# Normalize rotation to 0-360 range
	while target_rotation < 0:
		target_rotation += 360.0
	while target_rotation >= 360.0:
		target_rotation -= 360.0

	# Target position at water level
	var target_pos = world_pos
	target_pos.y = 0.0

	# Target isometric angle (straight down view)
	var target_angle = 85.0

	# Enable continuous transform updates during tween
	is_tweening = true

	# Animate with tween
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Tween all camera parameters
	tween.tween_property(self, "camera_target", target_pos, focus_animation_duration)
	tween.tween_property(self, "camera_distance", target_distance, focus_animation_duration)
	tween.tween_property(self, "camera_rotation_y", target_rotation, focus_animation_duration)
	tween.tween_property(self, "isometric_angle", target_angle, focus_animation_duration)

	# Disable tweening flag when animation completes
	tween.finished.connect(func():
		is_tweening = false
		_update_camera_transform()  # Final update
	)

	Trace.trace_log("Camera", "Focusing on ship at %s (facing: %d, rotation: %.1f°, distance: %.1f)" %
		[world_pos, ship_facing, target_rotation, target_distance])

func _update_camera_transform() -> void:
	# Calculate camera position using spherical coordinates
	var rad_angle = deg_to_rad(isometric_angle)
	var rad_rotation = deg_to_rad(camera_rotation_y)

	var offset = Vector3(
		cos(rad_rotation) * camera_distance * cos(rad_angle),
		camera_distance * sin(rad_angle),
		sin(rad_rotation) * camera_distance * cos(rad_angle)
	)

	position = camera_target + offset

	# Manually construct camera basis to avoid gimbal lock at 90 degrees
	# This ensures consistent orientation at all angles

	# Forward vector: from camera to target (look direction)
	var forward = (camera_target - position).normalized()

	# Right vector: screen-right on the ground plane, tangent to the orbit circle.
	# Independent of tilt, so there is no gimbal lock looking straight down.
	var right = Vector3(sin(rad_rotation), 0, -cos(rad_rotation))

	# Back vector (camera +Z): Godot cameras look along -Z.
	var back = -forward

	# Up vector completes a RIGHT-HANDED basis: up = back x right (so right x up = back).
	# A left-handed basis here renders the whole world mirrored.
	var up = back.cross(right).normalized()

	transform.basis = Basis(right, up, back)
