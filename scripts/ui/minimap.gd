extends Control
## MiniMap - Top-down minimap with viewport indicator and ship positions
## Shows entire map with camera frustum visualization and interactive controls

@export var minimap_size_percent: Vector2 = Vector2(0.2, 0.2)  # 20% of screen
@export var margin_pixels: Vector2 = Vector2(20, 20)  # Margin from top-right corner

# References
var camera: Camera3D
var hex_map: Node3D

# Map configuration (loaded from scenario)
var map_bounds: Vector2 = Vector2(100, 100)  # Default hex grid size
var map_world_size: Vector2 = Vector2(173.2, 150.0)  # Default world size

# Child nodes
@onready var background: TextureRect = $Background
@onready var ship_layer: Control = $ShipLayer
@onready var viewport_overlay: Control = $ViewportOverlay
@onready var north_indicator: Control = $NorthIndicator
@onready var wind_indicator: Control = $WindIndicator

# Viewport interaction
var is_dragging: bool = false
var drag_start_pos: Vector2
var viewport_hovered: bool = false

# Ship tracking
var ship_icons: Dictionary = {}  # ship_id -> TextureRect

func _ready() -> void:
	# Set size and position
	_update_minimap_transform()

	# Find camera reference
	_find_camera()

	# Connect to GameState
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.turn_changed.connect(_on_turn_changed)

	# Initialize from scenario
	_load_scenario_config()

	# Create initial ship icons
	_refresh_ship_icons()

	# Set z-index below DevUI
	z_index = 10

	Trace.trace_log("MiniMap", "Initialized: size=%s, bounds=%s, camera=%s" % [size, map_bounds, camera != null])

func _find_camera() -> void:
	"""Auto-find the camera in the scene"""
	var viewport = get_viewport()
	if viewport:
		camera = viewport.get_camera_3d()
		if camera:
			Trace.trace_log("MiniMap", "Found camera: %s" % camera.name)
		else:
			push_warning("MiniMap: No camera found")

func _load_scenario_config() -> void:
	"""Load minimap configuration from active scenario"""
	if GameState.active_scenario.is_empty():
		return

	# Load map bounds from scenario
	var scenario_bounds = GameState.active_scenario.get("map_bounds", {})
	if scenario_bounds.has("width") and scenario_bounds.has("height"):
		map_bounds = Vector2(scenario_bounds.width, scenario_bounds.height)

	# Calculate world size (hex grid dimensions)
	# Assuming hex width = sqrt(3), height = 1.5 per hex
	map_world_size = Vector2(
		map_bounds.x * sqrt(3),
		map_bounds.y * 1.5
	)

	# Load minimap texture if specified
	var minimap_texture_path = GameState.active_scenario.get("minimap_texture", "")
	if minimap_texture_path != "" and ResourceLoader.exists(minimap_texture_path):
		background.texture = load(minimap_texture_path)
	else:
		# Use placeholder blue
		_create_placeholder_texture()

func _create_placeholder_texture() -> void:
	"""Create a simple blue placeholder texture"""
	var img = Image.create(512, 512, false, Image.FORMAT_RGB8)
	img.fill(Color(0.476, 0.669, 0.968, 1.0))  # Ocean blue
	background.texture = ImageTexture.create_from_image(img)

func _update_minimap_transform() -> void:
	"""Update minimap size and position based on screen size"""
	var screen_size = get_viewport_rect().size
	var minimap_pixel_size = screen_size * minimap_size_percent

	# Set size
	custom_minimum_size = minimap_pixel_size
	size = minimap_pixel_size

	# Position in top-right corner
	position = Vector2(
		screen_size.x - minimap_pixel_size.x - margin_pixels.x,
		margin_pixels.y
	)

func _process(_delta: float) -> void:
	"""Update viewport indicator and ship positions"""
	if viewport_overlay:
		viewport_overlay.queue_redraw()

	_update_ship_positions()

func _get_camera_frustum_corners() -> Array[Vector3]:
	"""Calculate the 4 corners of camera view at ground level (y=0)"""
	if not camera:
		return []

	var corners: Array[Vector3] = []

	# For a top-down-ish camera, we need the 4 corners where view rays intersect y=0 plane
	# We'll raycast from camera through the 4 screen corners
	var viewport_size = get_viewport().get_visible_rect().size
	var screen_corners = [
		Vector2(0, 0),  # Top-left
		Vector2(viewport_size.x, 0),  # Top-right
		Vector2(viewport_size.x, viewport_size.y),  # Bottom-right
		Vector2(0, viewport_size.y)  # Bottom-left
	]

	#var _intersection_count = 0
	#var _fallback_count = 0

	for screen_pos in screen_corners:
		var ray_origin = camera.project_ray_origin(screen_pos)
		var ray_dir = camera.project_ray_normal(screen_pos)

		# Intersect ray with y=0 plane
		var intersection = _ray_intersect_plane(ray_origin, ray_dir, Vector3(0, 1, 0), 0.0)
		if intersection:
			corners.append(intersection)
			#_intersection_count += 1
		else:
			# If ray doesn't intersect (nearly parallel to ground), use a fallback
			# Project the ray far out and use that point
			var fallback_point = ray_origin + ray_dir * 1000.0
			fallback_point.y = 0.0  # Force to ground plane
			corners.append(fallback_point)
			#_fallback_count += 1

	# Debug log (only on first frame or when count changes)
	#if Engine.get_process_frames() % 60 == 0:  # Log once per second at 60fps
		#print("MiniMap frustum: %d intersections, %d fallbacks, corners=%d" % [intersection_count, fallback_count, corners.size()])

	return corners

func _ray_intersect_plane(ray_origin: Vector3, ray_dir: Vector3, plane_normal: Vector3, plane_d: float) -> Variant:
	"""Intersect a ray with a plane. Returns Vector3 or null"""
	var denom = plane_normal.dot(ray_dir)
	if abs(denom) < 0.0001:
		return null  # Ray parallel to plane

	var t = -(plane_normal.dot(ray_origin) + plane_d) / denom
	if t < 0:
		return null  # Intersection behind ray

	return ray_origin + ray_dir * t

func _world_to_minimap(world_pos: Vector3) -> Vector2:
	"""Convert world XZ coordinates to minimap pixel coordinates"""
	# Normalize world position to 0-1 range
	var normalized = Vector2(
		(world_pos.x + map_world_size.x / 2.0) / map_world_size.x,
		(world_pos.z + map_world_size.y / 2.0) / map_world_size.y
	)

	# Map to minimap size
	return normalized * size

func _minimap_to_world(minimap_pos: Vector2) -> Vector3:
	"""Convert minimap pixel coordinates to world XZ coordinates (y=0)"""
	# Normalize minimap position to 0-1 range
	var normalized = minimap_pos / size

	# Map to world coordinates
	var world_x = (normalized.x * map_world_size.x) - (map_world_size.x / 2.0)
	var world_z = (normalized.y * map_world_size.y) - (map_world_size.y / 2.0)

	return Vector3(world_x, 0, world_z)

func _refresh_ship_icons() -> void:
	"""Create or update ship icon nodes for all ships"""
	# Remove icons for ships that no longer exist
	var ships_to_remove = []
	for ship_id in ship_icons.keys():
		if not GameState.ships.has(ship_id):
			ships_to_remove.append(ship_id)

	for ship_id in ships_to_remove:
		ship_icons[ship_id].queue_free()
		ship_icons.erase(ship_id)

	# Create icons for new ships
	for ship_id in GameState.ships.keys():
		if not ship_icons.has(ship_id):
			_create_ship_icon(ship_id)

func _create_ship_icon(ship_id: String) -> void:
	"""Create a ship icon TextureRect"""
	var ship = GameState.get_ship(ship_id)
	if not ship:
		return

	var icon = TextureRect.new()
	icon.name = "Ship_" + ship_id
	icon.custom_minimum_size = Vector2(8, 8)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Create placeholder texture (simple colored square)
	var img = Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	icon.texture = ImageTexture.create_from_image(img)

	# Color modulate by player
	if ship.player_id == 0:
		icon.modulate = Color(0.183, 0.927, 0.479, 1.0)  # Blue for player 0
	else:
		icon.modulate = Color(1.0, 0.3, 0.3)  # Red for player 1

	ship_layer.add_child(icon)
	ship_icons[ship_id] = icon

	Trace.trace_log("MiniMap", "Created icon for ship %s" % ship_id)

func _update_ship_positions() -> void:
	"""Update positions of all ship icons"""
	for ship_id in ship_icons.keys():
		var ship = GameState.get_ship(ship_id)
		if not ship:
			continue

		var icon = ship_icons[ship_id]

		# Convert hex position to world coordinates
		# Hex grid: q = x offset, r = y offset
		# World position formula for flat-top hexes
		var hex_pos = ship.hex_position
		var world_x = hex_pos.x * sqrt(3)
		var world_z = hex_pos.y * 1.5

		# Convert to minimap coordinates
		var minimap_pos = _world_to_minimap(Vector3(world_x, 0, world_z))

		# Center icon on position
		icon.position = minimap_pos - icon.size / 2.0

func _gui_input(event: InputEvent) -> void:
	"""Handle click and drag on minimap"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check if clicking on viewport indicator
				var local_pos = event.position
				if _is_point_in_viewport_indicator(local_pos):
					is_dragging = true
					drag_start_pos = local_pos
				else:
					# Click to center
					_center_camera_on_minimap_pos(local_pos)
				accept_event()
			else:
				is_dragging = false
				accept_event()

	elif event is InputEventMouseMotion:
		# Update hover state
		var local_pos = event.position
		viewport_hovered = _is_point_in_viewport_indicator(local_pos)

		# Handle dragging
		if is_dragging and camera:
			var delta = event.position - drag_start_pos
			drag_start_pos = event.position

			# Convert minimap pixel delta to world delta
			var world_delta = Vector2(
				(delta.x / size.x) * map_world_size.x,
				(delta.y / size.y) * map_world_size.y
			)

			# Move camera target
			if camera.has_method("pan_camera_world"):
				camera.pan_camera_world(world_delta)
			elif "camera_target" in camera:
				camera.camera_target += Vector3(world_delta.x, 0, world_delta.y)
				if camera.has_method("_update_camera_transform"):
					camera._update_camera_transform()

			accept_event()

func _is_point_in_viewport_indicator(point: Vector2) -> bool:
	"""Check if a point is inside the viewport trapezoid"""
	if not camera:
		return false

	var frustum_corners = _get_camera_frustum_corners()
	if frustum_corners.size() != 4:
		return false

	var minimap_corners: Array[Vector2] = []
	for corner in frustum_corners:
		minimap_corners.append(_world_to_minimap(corner))

	# Point-in-polygon test
	return _point_in_polygon(point, minimap_corners)

func _point_in_polygon(point: Vector2, polygon: Array[Vector2]) -> bool:
	"""Ray casting algorithm for point-in-polygon test"""
	var inside = false
	var j = polygon.size() - 1

	for i in range(polygon.size()):
		if ((polygon[i].y > point.y) != (polygon[j].y > point.y)) and \
		   (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x):
			inside = not inside
		j = i

	return inside

func _center_camera_on_minimap_pos(minimap_pos: Vector2) -> void:
	"""Center camera on the clicked minimap position"""
	if not camera:
		return

	var world_pos = _minimap_to_world(minimap_pos)

	# Update camera target
	if "camera_target" in camera:
		camera.camera_target = world_pos
		if camera.has_method("_update_camera_transform"):
			camera._update_camera_transform()

func _on_phase_changed(_phase) -> void:
	"""Handle phase changes (may need to refresh ships)"""
	_refresh_ship_icons()

func _on_turn_changed(_turn) -> void:
	"""Handle turn changes"""
	_refresh_ship_icons()
