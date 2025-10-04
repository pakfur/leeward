@tool
extends EditorScript
## Utility script to generate a simple water texture
## Run this from the Godot editor via File > Run to generate water_default.png

func _run() -> void:
	var size = 512
	var image = Image.create(size, size, false, Image.FORMAT_RGB8)

	# Generate simple blue gradient water texture
	for y in range(size):
		for x in range(size):
			var noise_x = float(x) / size * 4.0
			var noise_y = float(y) / size * 4.0

			# Simple wavy pattern using sine waves
			var wave1 = sin(noise_x * 10.0 + noise_y * 5.0) * 0.1
			var wave2 = sin(noise_x * 7.0 - noise_y * 8.0) * 0.08

			# Base blue color with slight variation
			var brightness = 0.4 + wave1 + wave2
			var r = brightness * 0.2
			var g = brightness * 0.5
			var b = brightness * 0.8

			image.set_pixel(x, y, Color(r, g, b))

	# Save the image
	var path = "res://assets/textures/water_default.png"
	var error = image.save_png(path)

	if error == OK:
		print("Water texture created successfully at: %s" % path)
	else:
		push_error("Failed to save water texture: %d" % error)
