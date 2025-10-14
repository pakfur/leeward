extends Node
## Utility script to generate placeholder compass assets
## Run this once to create placeholder images, then can be removed

const ASSET_PATH = "res://assets/ui/compass/"
const IMAGE_SIZE = 256

func _ready() -> void:
	print("Generating compass placeholder assets...")

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(ASSET_PATH)

	# Generate each asset
	_generate_compass_base()
	#_generate_north_needle()
	_generate_wind_icon()

	print("Compass assets generated in: %s" % ASSET_PATH)
	print("You can now remove this script or replace with custom assets")

func _generate_compass_base() -> void:
	"""Generate compass background"""
	var img = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # Transparent background

	var center = IMAGE_SIZE / 2
	var radius = IMAGE_SIZE / 2 - 20

	# Draw filled circle background
	_draw_filled_circle(img, center, center, radius, Color(0.2, 0.15, 0.1, 0.8))

	# Draw outer ring
	_draw_circle_outline(img, center, center, radius, Color(0.6, 0.5, 0.4), 3)

	# Draw inner circle
	_draw_circle_outline(img, center, center, radius * 0.8, Color(0.4, 0.35, 0.3), 2)

	## Draw cardinal direction markers (6 directions for hex grid)
	#for i in range(6):
		#var angle = -i * PI / 3.0 + PI / 2.0  # Start from east, go clockwise
		#var outer = radius * 0.9
		#var inner = radius * 0.75
#
		#var x1 = center + cos(angle) * inner
		#var y1 = center - sin(angle) * inner
		#var x2 = center + cos(angle) * outer
		#var y2 = center - sin(angle) * outer
#
		#_draw_thick_line(img, x1, y1, x2, y2, Color.WHITE, 3)

	# Save
	var err = img.save_png(ASSET_PATH + "compass_base.png")
	if err == OK:
		print("✓ Generated compass_base.png")
	else:
		push_error("Failed to save compass_base.png: %d" % err)

func _generate_north_needle() -> void:
	"""Generate north-pointing needle (red/white arrow)"""
	var img = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center = IMAGE_SIZE / 2
	var length = IMAGE_SIZE / 2 - 40

	# Arrow shaft (vertical, pointing up)
	var shaft_width = 8
	var shaft_top = center - length
	var shaft_bottom = center + length * 0.3

	_draw_filled_rect(img, center - shaft_width/2, shaft_top, shaft_width, shaft_bottom - shaft_top,
					  Color(0.9, 0.2, 0.2))  # Red for north

	# Arrow head (triangle pointing up)
	var head_height = 30
	var head_width = 25

	# Simple triangle approximation with thick lines
	for y in range(int(head_height)):
		var width_at_y = head_width * (1.0 - float(y) / head_height)
		var y_pos = shaft_top - head_height + y
		_draw_horizontal_line(img, center - width_at_y/2, center + width_at_y/2, y_pos,
							  Color(0.9, 0.2, 0.2))

	# Southern tail (lighter color)
	_draw_filled_rect(img, center - shaft_width/2, shaft_bottom, shaft_width, 20,
					  Color(0.7, 0.7, 0.7))  # Gray for south

	var err = img.save_png(ASSET_PATH + "north_needle.png")
	if err == OK:
		print("✓ Generated north_needle.png")
	else:
		push_error("Failed to save north_needle.png: %d" % err)

func _generate_wind_icon() -> void:
	"""Generate wind direction indicator (yellow/gold arrow)"""
	var img = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center = IMAGE_SIZE / 2
	var length = IMAGE_SIZE / 2 - 50

	var shaft_width = 0
	var shaft_top = center - length
	var shaft_bottom = center

	_draw_filled_rect(img, center - shaft_width/2, shaft_top, shaft_width, shaft_bottom - shaft_top,
					  Color(0.9, 0.9, 0.3))  # Yellow/gold

	# Larger arrow head
	var head_height = 40
	var head_width = 35

	for y in range(int(head_height)):
		var width_at_y = head_width * (1.0 - float(y) / head_height)
		var y_pos = shaft_top - head_height + y
		_draw_horizontal_line(img, center - width_at_y/2, center + width_at_y/2, y_pos,
							  Color(0.9, 0.9, 0.3))

	# Add outline for better visibility
	_draw_circle_outline(img, center, center, length + head_height, Color(0.6, 0.6, 0.2), 2)

	var err = img.save_png(ASSET_PATH + "wind_icon.png")
	if err == OK:
		print("✓ Generated wind_icon.png")
	else:
		push_error("Failed to save wind_icon.png: %d" % err)

# Helper drawing functions

func _draw_filled_circle(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	"""Draw a filled circle"""
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx = x - cx
			var dy = y - cy
			if dx * dx + dy * dy <= radius * radius:
				if x >= 0 and x < IMAGE_SIZE and y >= 0 and y < IMAGE_SIZE:
					img.set_pixel(x, y, color)

func _draw_circle_outline(img: Image, cx: int, cy: int, radius: int, color: Color, thickness: int) -> void:
	"""Draw a circle outline with thickness"""
	for y in range(cy - radius - thickness, cy + radius + thickness + 1):
		for x in range(cx - radius - thickness, cx + radius + thickness + 1):
			var dx = x - cx
			var dy = y - cy
			var dist_sq = dx * dx + dy * dy
			var outer_sq = (radius + thickness) * (radius + thickness)
			var inner_sq = (radius - thickness) * (radius - thickness)

			if dist_sq <= outer_sq and dist_sq >= inner_sq:
				if x >= 0 and x < IMAGE_SIZE and y >= 0 and y < IMAGE_SIZE:
					img.set_pixel(x, y, color)

func _draw_thick_line(img: Image, x1: float, y1: float, x2: float, y2: float, color: Color, thickness: int) -> void:
	"""Draw a thick line"""
	var dx = x2 - x1
	var dy = y2 - y1
	var length = sqrt(dx * dx + dy * dy)
	var steps = int(length)

	for i in range(steps + 1):
		var t = float(i) / float(steps) if steps > 0 else 0.0
		var x = int(x1 + dx * t)
		var y = int(y1 + dy * t)

		# Draw thickness around point
		for ty in range(-thickness/2, thickness/2 + 1):
			for tx in range(-thickness/2, thickness/2 + 1):
				var px = x + tx
				var py = y + ty
				if px >= 0 and px < IMAGE_SIZE and py >= 0 and py < IMAGE_SIZE:
					img.set_pixel(px, py, color)

func _draw_horizontal_line(img: Image, x1: float, x2: float, y: float, color: Color) -> void:
	"""Draw a horizontal line"""
	var start_x = int(min(x1, x2))
	var end_x = int(max(x1, x2))
	var yi = int(y)

	if yi >= 0 and yi < IMAGE_SIZE:
		for x in range(start_x, end_x + 1):
			if x >= 0 and x < IMAGE_SIZE:
				img.set_pixel(x, yi, color)

func _draw_filled_rect(img: Image, x: float, y: float, width: float, height: float, color: Color) -> void:
	"""Draw a filled rectangle"""
	var xi = int(x)
	var yi = int(y)
	var wi = int(width)
	var hi = int(height)

	for py in range(yi, yi + hi):
		for px in range(xi, xi + wi):
			if px >= 0 and px < IMAGE_SIZE and py >= 0 and py < IMAGE_SIZE:
				img.set_pixel(px, py, color)
