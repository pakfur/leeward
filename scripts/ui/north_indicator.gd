extends Control
## NorthIndicator - Simple arrow pointing north on minimap

@export var arrow_size: float = 30.0
@export var arrow_color: Color = Color.WHITE

func _ready() -> void:
	custom_minimum_size = Vector2(arrow_size, arrow_size)
	mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	"""Draw a simple north-pointing arrow"""
	var center = size / 2.0

	# Arrow points up (north)
	var tip = Vector2(center.x, 5)
	var left = Vector2(center.x - 8, 20)
	var right = Vector2(center.x + 8, 20)
	var neck_left = Vector2(center.x - 3, 20)
	var neck_right = Vector2(center.x + 3, 20)
	var bottom_left = Vector2(center.x - 3, size.y - 5)
	var bottom_right = Vector2(center.x + 3, size.y - 5)

	# Draw arrow shape
	var arrow_points = PackedVector2Array([
		tip, left, neck_left, bottom_left,
		bottom_right, neck_right, right
	])

	draw_colored_polygon(arrow_points, arrow_color)
	draw_polyline(arrow_points, Color.BLACK, 1.0)

	# Draw "N" text
	var font = ThemeDB.fallback_font
	var font_size = 12
	var text = "N"
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(center.x - text_size.x / 2.0, size.y - 10)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.BLACK)
