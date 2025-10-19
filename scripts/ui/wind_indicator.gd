extends Control
## WindIndicator - Wind direction arrow for minimap (matching WindCompass style)

@export var arrow_size: float = 40.0
@export var arrow_color: Color = Color(0.8, 0.8, 1.0)  # Light blue

var wind_direction: int = 0  # 0-5 hex direction

func _ready() -> void:
	custom_minimum_size = Vector2(arrow_size, arrow_size)
	mouse_filter = MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(arrow_size / 2.0, arrow_size / 2.0)

	# Connect to GameState for wind updates
	GameState.phase_changed.connect(_on_wind_changed)
	_update_wind_direction()

func _draw() -> void:
	"""Draw wind direction arrow"""
	var center = size / 2.0

	# Arrow points in wind direction
	var tip = Vector2(center.x, 2)
	var left = Vector2(center.x - 6, 15)
	var right = Vector2(center.x + 6, 15)
	var tail = Vector2(center.x, size.y - 2)

	# Draw arrow shape
	var arrow_points = PackedVector2Array([tip, left, tail, right])
	draw_colored_polygon(arrow_points, arrow_color)
	draw_polyline(arrow_points + PackedVector2Array([tip]), Color.BLACK, 1.5)

func _update_wind_direction() -> void:
	"""Update from GameState"""
	wind_direction = GameState.wind_direction

	# Convert hex direction to degrees
	# Hex: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE
	# Each hex face is 60 degrees apart
	var wind_angle = wind_direction * 60.0

	# Adjust for coordinate system (hex 0=E is 0°, convert to N-based)
	wind_angle = wind_angle - 90.0

	# Rotate the arrow
	rotation = deg_to_rad(wind_angle)

	queue_redraw()

func _on_wind_changed(_phase) -> void:
	"""Handle wind direction changes"""
	_update_wind_direction()
