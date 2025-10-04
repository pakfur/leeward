extends Camera3D
## IsometricCamera - Handles isometric view with zoom and pan controls

@export var zoom_speed: float = 0.1
@export var min_zoom: float = 5.0
@export var max_zoom: float = 40.0
@export var pan_speed: float = 0.5
@export var initial_distance: float = 25.0
@export var isometric_angle: float = 85.0  # degrees from horizontal (5 degrees off vertical)

var camera_distance: float = 25.0
var camera_target: Vector3 = Vector3.ZERO
var is_panning: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

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

		# Middle mouse for panning
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_panning = true
				last_mouse_pos = event.position
			else:
				is_panning = false
			get_viewport().set_input_as_handled()

	# Mouse motion for panning
	if event is InputEventMouseMotion and is_panning:
		var delta = event.position - last_mouse_pos
		last_mouse_pos = event.position
		pan_camera(delta)
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
	# Convert screen space pan to world space
	var right = global_transform.basis.x
	var forward = global_transform.basis.z

	# Adjust pan speed by zoom level
	var adjusted_speed = pan_speed * camera_distance / initial_distance

	camera_target -= right * mouse_delta.x * adjusted_speed * 0.01
	camera_target -= forward * mouse_delta.y * adjusted_speed * 0.01

	_update_camera_transform()

func set_target(target: Vector3) -> void:
	camera_target = target
	_update_camera_transform()

func _update_camera_transform() -> void:
	# Calculate isometric position
	# Isometric view: camera looks down at ~35.264 degrees and rotated 45 degrees
	var rad_angle = deg_to_rad(isometric_angle)
	var offset = Vector3(
		cos(deg_to_rad(45)) * camera_distance * cos(rad_angle),
		camera_distance * sin(rad_angle),
		sin(deg_to_rad(45)) * camera_distance * cos(rad_angle)
	)

	position = camera_target + offset
	look_at(camera_target, Vector3.UP)
