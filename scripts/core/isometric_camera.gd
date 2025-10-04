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

var camera_distance: float = 25.0
var camera_target: Vector3 = Vector3.ZERO
var camera_rotation_y: float = 45.0  # horizontal rotation around target
var is_panning: bool = false
var is_rotating: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var mouse_down_pos: Vector2 = Vector2.ZERO
var drag_threshold: float = 5.0  # pixels before considering it a drag

func _ready() -> void:
	camera_distance = initial_distance
	_update_camera_transform()
	print("Camera initialized at position: %s, looking at: %s" % [position, camera_target])

func _unhandled_input(event: InputEvent) -> void:
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

	# When looking straight down, use a different up vector to avoid colinearity
	var up_vector = Vector3.UP
	if isometric_angle > 89.0:
		# Use camera's forward direction offset as up vector
		up_vector = Vector3(cos(rad_rotation), 0, sin(rad_rotation))

	look_at(camera_target, up_vector)
