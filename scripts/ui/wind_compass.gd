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
	# The camera's screen-up points at compass bearing (camera_rotation_y - 90): rotation 90
	# is the default north-up view. A world bearing b (clockwise from north) therefore shows
	# on screen at b - (camera_rotation_y - 90), clockwise from screen-up.
	var screen_up_bearing = camera_rotation_y - 90.0

	# North needle (texture points up): bearing 0
	if north_needle:
		north_needle.rotation = deg_to_rad(-screen_up_bearing)

	# Wind icon: a rim marker (texture at the top, pointing inward) placed on the side the wind
	# blows FROM. Hex direction d (0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE) has bearing 90 + 60d.
	if wind_icon:
		var wind_from_bearing = 90.0 + wind_direction * 60.0
		wind_icon.rotation = deg_to_rad(wind_from_bearing - screen_up_bearing)

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
