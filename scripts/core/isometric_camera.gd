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
var camera_rotation_y: float = 45.0  # horizontal rotation around target
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
	var old_distance = camera_distance
	camera_distance = clamp(camera_distance - zoom_speed * camera_distance, min_zoom, max_zoom)
	_update_camera_transform()
	#print("Zoom in: %f -> %f" % [old_distance, camera_distance])

func zoom_out() -> void:
	var old_distance = camera_distance
	camera_distance = clamp(camera_distance + zoom_speed * camera_distance, min_zoom, max_zoom)
	_update_camera_transform()
	#print("Zoom out: %f -> %f" % [old_distance, camera_distance])

func pan_camera(mouse_delta: Vector2) -> void:
	# Convert screen space pan to world space, but only on XZ plane
	var right = global_transform.basis.x
	var forward = global_transform.basis.z

	# Flatten vectors to XZ plane (remove Y component) to prevent zoom effect
	right.y = 0
	right = right.normalized()
	forward.y = 0
	forward = forward.normalized()

	# Adjust pan speed by zoom level (higher speed for better responsiveness)
	var adjusted_speed = pan_speed * camera_distance / initial_distance

	# Pan on XZ plane only (no vertical movement)
	camera_target -= right * mouse_delta.x * adjusted_speed * 0.05
	camera_target -= forward * mouse_delta.y * adjusted_speed * 0.05

	_update_camera_transform()

func rotate_camera(mouse_delta: Vector2) -> void:
	# Horizontal rotation (left-right mouse movement)
	camera_rotation_y += mouse_delta.x * rotation_speed

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
	var required_distance = max(max_size * padding_factor, min_zoom)

	# Clamp to zoom limits
	required_distance = clamp(required_distance, min_zoom, max_zoom)

	# Set camera parameters
	camera_target = center
	camera_distance = required_distance
	isometric_angle = 85.0  # Reset to 85 degrees

	_update_camera_transform()
	Trace.trace_log("Camera", "Centered on %d ships at distance %f" % [ship_positions.size(), camera_distance])

func focus_on_ship(world_pos: Vector3, ship_facing: int, zoom_distance: float = -1.0) -> void:
	"""
	Focus camera on a specific ship with smooth animation.
	Ship will appear facing "up" on screen.

	Args:
		world_pos: Ship's world position
		ship_facing: Ship's facing direction (0-5, hex directions)
		zoom_distance: Optional override for focus distance (uses focus_zoom_distance if -1)
	"""
	# Use default focus distance if not specified
	var target_distance = focus_zoom_distance if zoom_distance < 0 else zoom_distance
	target_distance = clamp(target_distance, min_zoom, max_zoom)

	# Calculate camera rotation so ship faces "up" on screen
	# Ship model rotation is: -facing * 60 + 90
	# Camera should be positioned behind the ship, so add 180 degrees
	var target_rotation = -ship_facing * 60.0 + 270.0

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

	# Right vector: perpendicular to forward, on the horizontal rotation circle
	# This is tangent to the circle at the current rotation_y position
	var right = Vector3(-sin(rad_rotation), 0, cos(rad_rotation)).normalized()

	# Up vector: perpendicular to both forward and right
	# Cross product order matters: forward × right gives up vector pointing "up" on screen
	var up = forward.cross(right).normalized()

	# Construct the basis (right, up, -forward for Godot's coordinate system)
	# Note: Godot cameras look along -Z, so we use -forward for the Z axis
	var basis = Basis(right, up, -forward)

	# Apply the basis to the camera
	transform.basis = basis
