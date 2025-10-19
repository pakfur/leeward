extends Control
## ViewportOverlay - Custom draw layer for camera viewport indicator on minimap

var minimap: Control  # Reference to parent minimap

func _ready() -> void:
	minimap = get_parent()
	mouse_filter = MOUSE_FILTER_IGNORE  # Let clicks pass through to minimap

func _draw() -> void:
	"""Draw the camera viewport trapezoid"""
	if not minimap or not minimap.camera:
		return

	# Get camera frustum corners at ground level (y=0)
	var frustum_corners = minimap._get_camera_frustum_corners()
	if frustum_corners.size() != 4:
		return

	# Convert world positions to minimap coordinates
	var minimap_corners: PackedVector2Array = []
	for corner in frustum_corners:
		minimap_corners.append(minimap._world_to_minimap(corner))

	# Choose color based on state
	var color = Color.WHITE
	if minimap.viewport_hovered:
		color = Color.YELLOW
	if minimap.is_dragging:
		color = Color.GREEN

	# Draw filled polygon with transparency
	draw_colored_polygon(minimap_corners, Color(color, 0.2))

	# Draw border
	for i in range(minimap_corners.size()):
		var next_i = (i + 1) % minimap_corners.size()
		draw_line(minimap_corners[i], minimap_corners[next_i], color, 2.0)
