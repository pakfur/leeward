extends GutTest
## Tests for IndicatorOverlay.label_position: the on-map speed / point-of-sail label is placed
## beside the ship, clear of its centre (the model) along the chosen direction.

const Overlay = preload("res://scripts/ui/indicator_overlay.gd")


func test_label_sits_past_the_clearance_along_the_direction() -> void:
	var pos: Vector2 = Overlay.label_position(Vector2(500, 500), Vector2(-1, 0), 60.0, Vector2(100, 40))
	# Pointing left: the label's right edge is 60 px left of the centre, vertically centred.
	assert_eq(pos, Vector2(340, 480))
	assert_eq(pos.x + 100, 440.0)


func test_selected_label_clears_the_stern_hex() -> void:
	# `hex_px` is one hex width on screen. Astern (the selected ship) the label clears the stern hex:
	# its nearest edge is past the stern's far edge, 1.5 hex widths from the bow centre.
	assert_gt(Overlay.label_clearance(100.0, -1.0, 0.0), 150.0)
	# Ahead (the hover preview) it stays just past the hovered hex.
	assert_almost_eq(Overlay.label_clearance(200.0, 1.0, 0.0), 110.0, 0.01)
	assert_eq(Overlay.label_clearance(10.0, 1.0, 0.0), Overlay.MIN_CLEARANCE_PX, "never closer than the minimum")
	assert_eq(Overlay.label_clearance(100.0, -1.0, 400.0), 400.0, "pushed out to the minimum given")


func test_zero_direction_falls_back_below() -> void:
	var pos: Vector2 = Overlay.label_position(Vector2(100, 100), Vector2.ZERO, 10.0, Vector2(20, 10))
	assert_eq(pos, Vector2(90, 110))


# --- Kept inside the map area ----------------------------------------------------------------

func test_label_is_pushed_out_from_under_the_side_panel() -> void:
	# Map area starts at x = 460 (side panel on the left); a label placed at x = 430 moves right.
	var map_rect := Rect2(460, 0, 1460, 1000)
	var pos: Vector2 = Overlay.keep_inside(Vector2(430, 300), Vector2(100, 40), map_rect, 4.0)
	assert_eq(pos, Vector2(464, 300))


func test_label_inside_the_map_area_is_left_alone() -> void:
	var map_rect := Rect2(460, 0, 1460, 1000)
	assert_eq(Overlay.keep_inside(Vector2(800, 300), Vector2(100, 40), map_rect, 4.0), Vector2(800, 300))


func test_label_kept_above_the_bottom_and_left_of_the_right_edge() -> void:
	var map_rect := Rect2(0, 0, 1000, 800)
	assert_eq(Overlay.keep_inside(Vector2(950, 790), Vector2(100, 40), map_rect, 4.0), Vector2(896, 756))


func test_overlay_clamps_to_the_map_rect_it_is_given() -> void:
	var overlay = Overlay.new()
	autofree(overlay)
	overlay.map_rect_provider = func() -> Rect2: return Rect2(460, 0, 1460, 1000)
	assert_eq(overlay._map_rect(), Rect2(460, 0, 1460, 1000))
