extends Control
## WindCompass - Displays wind direction as a compass widget

@export var compass_size: Vector2 = Vector2(120, 120)
@export var wind_arrow_color: Color = Color(0.9, 0.9, 0.3)
@export var compass_bg_color: Color = Color(0.2, 0.15, 0.1, 0.8)

var wind_direction: int = 0  # 0-5

func _ready() -> void:
	custom_minimum_size = compass_size
	GameState.phase_changed.connect(_on_phase_changed)
	_update_wind_direction()

func _draw() -> void:
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 10.0

	# Draw compass background
	draw_circle(center, radius, compass_bg_color)

	# Draw compass ring
	draw_arc(center, radius, 0, TAU, 32, Color(0.6, 0.5, 0.4), 2.0)

	# Draw cardinal directions (simplified hex directions)
	var direction_labels = ["E", "SE", "SW", "W", "NW", "NE"]
	for i in range(6):
		var angle = deg_to_rad(-i * 60.0 + 90.0)  # Start from east, go clockwise
		var label_pos = center + Vector2(cos(angle), -sin(angle)) * (radius * 0.7)
		draw_string(ThemeDB.fallback_font, label_pos - Vector2(8, -4), direction_labels[i],
					HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

	# Draw wind direction arrow
	_draw_wind_arrow(center, radius * 0.5)

	# Draw center dot
	draw_circle(center, 4, Color.WHITE)

func _draw_wind_arrow(center: Vector2, length: float) -> void:
	"""Draw an arrow showing wind direction"""
	var angle = deg_to_rad(-wind_direction * 60.0 + 90.0)  # Convert hex facing to angle
	var direction = Vector2(cos(angle), -sin(angle))

	# Arrow shaft
	var arrow_end = center + direction * length
	draw_line(center, arrow_end, wind_arrow_color, 3.0)

	# Arrow head
	var head_size = 12.0
	var perpendicular = Vector2(-direction.y, direction.x)
	var head_left = arrow_end - direction * head_size + perpendicular * head_size * 0.5
	var head_right = arrow_end - direction * head_size - perpendicular * head_size * 0.5

	var points = PackedVector2Array([arrow_end, head_left, head_right])
	draw_colored_polygon(points, wind_arrow_color)

func set_wind_direction(direction: int) -> void:
	"""Update the displayed wind direction (0-5)"""
	wind_direction = direction % 6
	queue_redraw()

func _update_wind_direction() -> void:
	"""Update from GameState"""
	set_wind_direction(GameState.wind_direction)

func _on_phase_changed(_phase) -> void:
	_update_wind_direction()
