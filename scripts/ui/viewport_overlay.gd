extends Control
## ViewportOverlay - Custom draw layer for camera viewport indicator on minimap

var minimap: Control  # Reference to parent minimap

func _ready() -> void:
	minimap = get_parent()
	mouse_filter = MOUSE_FILTER_IGNORE  # Let clicks pass through to minimap

func _draw() -> void:
	"""Draw the camera viewport trapezoid"""
	if not minimap or not minimap.camera:
		#if Engine.get_process_frames() % 60 == 0:
			#print("ViewportOverlay: No minimap (%s) or camera (%s)" % [minimap != null, minimap.camera if minimap else "null"])
		return

	# Get camera frustum corners at ground level (y=0)
	var frustum_corners = minimap._get_camera_frustum_corners()
	if frustum_corners.size() != 4:
		#if Engine.get_process_frames() % 60 == 0:
			#print("ViewportOverlay: Invalid frustum corners count: %d" % frustum_corners.size())
		return

	# Convert world positions to minimap coordinates and clip to bounds
	var minimap_corners: PackedVector2Array = []
	for corner in frustum_corners:
		var pos = minimap._world_to_minimap(corner)
		minimap_corners.append(pos)

	# Debug log (once per second)
	#if Engine.get_process_frames() % 60 == 0:
		#print("ViewportOverlay: Raw corners: %s" % [minimap_corners])

	# Choose color based on state
	var color = Color.WHITE
	if minimap.viewport_hovered:
		color = Color.YELLOW
	if minimap.is_dragging:
		color = Color.GREEN

	# Clip polygon to minimap rectangle before drawing
	var clipped_polygon = _clip_polygon_to_rect(minimap_corners, Rect2(Vector2.ZERO, size))

	#if Engine.get_process_frames() % 60 == 0:
		#print("ViewportOverlay: Clipped polygon size: %d, rect: %s" % [clipped_polygon.size(), Rect2(Vector2.ZERO, size)])

	if clipped_polygon.size() >= 3:
		# Draw filled polygon with transparency
		draw_colored_polygon(clipped_polygon, Color(color, 0.2))

		# Draw border
		for i in range(clipped_polygon.size()):
			var next_i = (i + 1) % clipped_polygon.size()
			draw_line(clipped_polygon[i], clipped_polygon[next_i], color, 2.0)
	#else:
		#if Engine.get_process_frames() % 60 == 0:
			#print("ViewportOverlay: Clipped polygon too small to draw: %d vertices" % clipped_polygon.size())

func _clip_polygon_to_rect(polygon: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	"""Clip a polygon to a rectangle using Sutherland-Hodgman algorithm"""
	var output = polygon

	# Clip against each edge of the rectangle
	# Left edge (x >= rect.position.x)
	output = _clip_polygon_component(output, rect.position.x, 0, true)
	# Right edge (x <= rect.end.x)
	output = _clip_polygon_component(output, rect.end.x, 0, false)
	# Top edge (y >= rect.position.y)
	output = _clip_polygon_component(output, rect.position.y, 1, true)
	# Bottom edge (y <= rect.end.y)
	output = _clip_polygon_component(output, rect.end.y, 1, false)

	return output

func _clip_polygon_component(polygon: PackedVector2Array, edge: float, axis: int, inside_is_greater: bool) -> PackedVector2Array:
	"""Clip polygon against a single edge

	Args:
		polygon: Input polygon
		edge: Edge position
		axis: 0 for x, 1 for y
		inside_is_greater: true if inside is >= edge, false if inside is <= edge
	"""
	if polygon.size() == 0:
		return PackedVector2Array()

	var output: PackedVector2Array = []

	for i in range(polygon.size()):
		var current = polygon[i]
		var next = polygon[(i + 1) % polygon.size()]

		var current_val = current.x if axis == 0 else current.y
		var next_val = next.x if axis == 0 else next.y

		var current_inside = (current_val >= edge) if inside_is_greater else (current_val <= edge)
		var next_inside = (next_val >= edge) if inside_is_greater else (next_val <= edge)

		if current_inside:
			output.append(current)

			if not next_inside:
				# Exiting, add intersection
				var intersection = _line_intersect_edge(current, next, edge, axis)
				output.append(intersection)
		elif next_inside:
			# Entering, add intersection
			var intersection = _line_intersect_edge(current, next, edge, axis)
			output.append(intersection)

	return output

func _line_intersect_edge(p1: Vector2, p2: Vector2, edge: float, axis: int) -> Vector2:
	"""Find intersection of line segment with edge"""
	var p1_val = p1.x if axis == 0 else p1.y
	var p2_val = p2.x if axis == 0 else p2.y

	var t = (edge - p1_val) / (p2_val - p1_val)
	t = clamp(t, 0.0, 1.0)

	return p1.lerp(p2, t)
