extends Control
## WindCompass - Asset-based compass with camera-relative rotation
## Displays north needle and wind direction indicator that rotate to compensate for camera orientation

@export var compass_size: Vector2 = Vector2(120, 120)
@export var camera: Camera3D  # Reference to the isometric camera

# Child node references (set up in scene)
@onready var compass_base: TextureRect = $CompassBase
@onready var north_needle: TextureRect = $NorthNeedle
@onready var wind_icon: TextureRect = $WindIcon

var wind_direction: int = 0  # 0-5 hex direction (0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE)
var camera_rotation_y: float = 0.0  # Cached camera rotation

func _ready() -> void:
	custom_minimum_size = compass_size

	# Connect to GameState for wind updates
	GameState.phase_changed.connect(_on_phase_changed)
	_update_wind_direction()

	# Find camera if not assigned
	if not camera:
		_find_camera()

	# Set initial pivot points for proper rotation
	if compass_base:
		compass_base.pivot_offset = compass_base.size / 2.0
	if north_needle:
		north_needle.pivot_offset = north_needle.size / 2.0
	if wind_icon:
		wind_icon.pivot_offset = wind_icon.size / 2.0

func _process(_delta: float) -> void:
	"""Update compass rotations every frame to track camera"""
	if camera:
		_update_camera_rotation()
		_update_compass_rotations()

func _find_camera() -> void:
	"""Auto-find the camera in the scene if not assigned"""
	var viewport = get_viewport()
	if viewport:
		camera = viewport.get_camera_3d()
		if camera:
			Trace.trace_log("WindCompass", "Auto-found camera: %s" % camera.name)
		else:
			push_warning("WindCompass: No camera found in viewport")

func _update_camera_rotation() -> void:
	"""Get current camera rotation from IsometricCamera"""
	# Access the camera_rotation_y property
	if camera.has_method("get") or "camera_rotation_y" in camera:
		camera_rotation_y = camera.get("camera_rotation_y")

func _update_compass_rotations() -> void:
	"""Update needle and wind icon rotations based on camera orientation"""

	# North needle: rotate to compensate for camera rotation
	# So it always points north regardless of camera angle
	if north_needle:
		north_needle.rotation = deg_to_rad(-camera_rotation_y)

	# Wind icon: show wind direction relative to north, compensated for camera
	if wind_icon:
		# Convert hex direction to world angle (0=E is 0°, goes clockwise)
		var wind_angle_world = wind_direction * 60.0

		# Adjust for coordinate system (hex 0=E is at 0°, but we want N as reference)
		# In hex system: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE
		# We want to display relative to North, so rotate by 90° and compensate camera
		wind_angle_world = wind_angle_world - 90.0  # Convert E-based to N-based

		# Compensate for camera rotation
		var wind_angle_screen = wind_angle_world - camera_rotation_y

		wind_icon.rotation = deg_to_rad(wind_angle_screen)

func set_wind_direction(direction: int) -> void:
	"""Update the displayed wind direction (0-5 hex direction)"""
	wind_direction = direction % 6
	_update_compass_rotations()

func _update_wind_direction() -> void:
	"""Update from GameState (server-authoritative)"""
	set_wind_direction(GameState.wind_direction)
	Trace.trace_log("WindCompass", "Wind direction updated to %d (%s)" % [wind_direction, _get_direction_name()])

func _get_direction_name() -> String:
	"""Get human-readable wind direction for debugging"""
	var directions = ["E", "SE", "SW", "W", "NW", "NE"]
	return directions[wind_direction]

func _on_phase_changed(_phase) -> void:
	"""Handle game phase changes (wind may change per turn)"""
	_update_wind_direction()
