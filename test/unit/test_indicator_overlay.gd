extends GutTest
## Tests for IndicatorOverlay.label_position: the on-map speed / point-of-sail label is placed
## beside the ship, clear of its centre (model and info button) along the chosen direction.

const Overlay = preload("res://scripts/ui/indicator_overlay.gd")


func test_label_sits_past_the_clearance_along_the_direction() -> void:
	var pos: Vector2 = Overlay.label_position(Vector2(500, 500), Vector2(-1, 0), 60.0, Vector2(100, 40))
	# Pointing left: the label's right edge is 60 px left of the centre, vertically centred.
	assert_eq(pos, Vector2(340, 480))
	assert_eq(pos.x + 100, 440.0)


func test_label_clearance_can_be_pushed_past_the_info_button() -> void:
	# The selected label sits astern beyond the info button: any clearance at or past the button's
	# far corner keeps the two apart.
	var center := Vector2(400, 300)
	var button := Rect2(center + Vector2(-40, -9), Vector2(18, 18))
	var clearance: float = Overlay.clearance_past(center, button, 4.0)
	var size := Vector2(130, 48)
	var rect := Rect2(Overlay.label_position(center, Vector2(-1, 0), clearance, size), size)
	assert_false(rect.intersects(button))


func test_zero_direction_falls_back_below() -> void:
	var pos: Vector2 = Overlay.label_position(Vector2(100, 100), Vector2.ZERO, 10.0, Vector2(20, 10))
	assert_eq(pos, Vector2(90, 110))


# ---------------------------------------------------------------------------------------------
# Info button placement: never over the ship's hex centre or a neighbouring hex centre.
# ---------------------------------------------------------------------------------------------

const BUTTON := Vector2(18, 22)


## The seven projected hex centres (ship, then neighbours in direction order) under a simple
## tilted top-down projection: `scale` px per world unit (the zoom), `yaw` the camera turn.
func _centers(scale: float, yaw_deg: float, tilt: float = 0.7) -> Array:
	var grid := HexGrid.new(1.0)
	var origin := Vector2i(3, -2)
	var hexes: Array = [origin]
	for d in range(6):
		hexes.append(grid.get_neighbor(origin.x, origin.y, d))
	var out: Array = []
	for h in hexes:
		var w := grid.axial_to_world(h.x, h.y) - grid.axial_to_world(origin.x, origin.y)
		var v := Vector2(w.x, w.z).rotated(deg_to_rad(yaw_deg))
		out.append(Vector2(640, 360) + Vector2(v.x, v.y * tilt) * scale)
	return out


func test_info_button_never_covers_any_of_the_seven_hex_centres() -> void:
	for scale in [18.0, 30.0, 45.0, 60.0, 90.0]:
		for yaw in [0.0, 30.0, 73.0]:
			var centers := _centers(scale, yaw)
			for facing in range(6):
				var rect: Rect2 = Overlay.info_button_rect(centers, facing, BUTTON)
				if rect.size == Vector2.ZERO:
					continue  # hidden: too small to fit beside the centres at this zoom
				for i in range(centers.size()):
					assert_false(rect.has_point(centers[i]),
						"zoom %.0f yaw %.0f facing %d covers hex centre %d" % [scale, yaw, facing, i])


func test_info_button_shows_astern_at_normal_zoom() -> void:
	for scale in [60.0, 90.0]:
		var centers := _centers(scale, 0.0)
		for facing in range(6):
			var rect: Rect2 = Overlay.info_button_rect(centers, facing, BUTTON)
			assert_ne(rect.size, Vector2.ZERO, "zoom %.0f facing %d: button hidden" % [scale, facing])
			assert_eq(rect.size, BUTTON)
			# Astern: closer to the hex behind the ship than to the hex ahead of it.
			var astern: Vector2 = centers[1 + (facing + 3) % 6]
			var ahead: Vector2 = centers[1 + facing]
			assert_lt(rect.get_center().distance_to(astern), rect.get_center().distance_to(ahead))


func test_info_button_hides_when_hexes_are_too_small() -> void:
	var centers := _centers(8.0, 0.0)
	for facing in range(6):
		assert_eq(Overlay.info_button_rect(centers, facing, BUTTON).size, Vector2.ZERO)


func test_info_button_keeps_a_margin_around_each_centre() -> void:
	var centers := _centers(60.0, 0.0)
	for facing in range(6):
		var rect: Rect2 = Overlay.info_button_rect(centers, facing, BUTTON)
		for c in centers:
			assert_false(rect.grow(4.0).has_point(c), "facing %d: closer than 4 px to a centre" % facing)


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
