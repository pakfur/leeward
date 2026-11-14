extends GutTest
## Tests for IndicatorOverlay.label_position: the on-map speed / point-of-sail label is placed
## beside the ship, clear of its centre (model and info button) along the chosen direction.

const Overlay = preload("res://scripts/ui/indicator_overlay.gd")


func test_label_sits_past_the_clearance_along_the_direction() -> void:
	var pos: Vector2 = Overlay.label_position(Vector2(500, 500), Vector2(-1, 0), 60.0, Vector2(100, 40))
	# Pointing left: the label's right edge is 60 px left of the centre, vertically centred.
	assert_eq(pos, Vector2(340, 480))
	assert_eq(pos.x + 100, 440.0)


func test_label_never_reaches_the_info_button_square() -> void:
	# The info button covers centre + (14..42, 14..42). Any direction keeps the label clear.
	var center := Vector2(400, 300)
	var button := Rect2(center + Vector2(14, 14), Vector2(28, 28))
	for deg in range(0, 360, 15):
		var dir := Vector2.RIGHT.rotated(deg_to_rad(deg))
		var size := Vector2(130, 48)
		var rect := Rect2(Overlay.label_position(center, dir, Overlay.MIN_CLEARANCE_PX, size), size)
		assert_false(rect.intersects(button), "direction %d deg overlaps the info button" % deg)


func test_zero_direction_falls_back_below() -> void:
	var pos: Vector2 = Overlay.label_position(Vector2(100, 100), Vector2.ZERO, 10.0, Vector2(20, 10))
	assert_eq(pos, Vector2(90, 110))
