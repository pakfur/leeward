extends GutTest
## ShipStatusBars / ShipStatusOverlay: the pure layout, colour and hover-delay rules.


func test_segments_share_the_width_in_proportion_to_their_boxes() -> void:
	var spans := ShipStatusBars.segment_spans([3, 4, 5, 5], 182.0, 4.0)
	assert_eq(spans.size(), 4)
	# 182 - 3 gaps of 4 = 170 px for 17 boxes: 10 px a box
	assert_almost_eq(spans[0].y, 30.0, 0.001)
	assert_almost_eq(spans[1].y, 40.0, 0.001)
	assert_almost_eq(spans[2].y, 50.0, 0.001)
	assert_almost_eq(spans[3].y, 50.0, 0.001)
	assert_almost_eq(spans[0].x, 0.0, 0.001)
	assert_almost_eq(spans[1].x, 34.0, 0.001)
	assert_almost_eq(spans[3].x + spans[3].y, 182.0, 0.001, "the last segment ends at the full width")


func test_every_bar_spans_the_same_width_whatever_its_sections() -> void:
	for maximums in [[5, 5, 6, 6], [3, 3, 3, 3], [1, 9], [7]]:
		var spans := ShipStatusBars.segment_spans(maximums, 150.0, 4.0)
		var last: Vector2 = spans[spans.size() - 1]
		assert_almost_eq(last.x + last.y, 150.0, 0.001, str(maximums))


func test_no_sections_or_no_boxes_gives_no_segments() -> void:
	assert_eq(ShipStatusBars.segment_spans([], 150.0, 4.0).size(), 0)
	assert_eq(ShipStatusBars.segment_spans([0, 0], 150.0, 4.0).size(), 0)


func test_fill_fraction_is_the_share_still_standing() -> void:
	assert_almost_eq(ShipStatusBars.fill_fraction(3, 6), 0.5, 0.001)
	assert_eq(ShipStatusBars.fill_fraction(0, 6), 0.0)
	assert_eq(ShipStatusBars.fill_fraction(6, 6), 1.0)
	assert_eq(ShipStatusBars.fill_fraction(9, 6), 1.0, "never more than full")
	assert_eq(ShipStatusBars.fill_fraction(2, 0), 0.0, "a section that never had boxes")


func test_skill_names_replace_the_quality_letters() -> void:
	var expected := ["Prime Seaman", "Able Seaman", "Ordinary Seaman", "Landsman",
		"Waister", "Green Hand", "Lubber"]
	var letters := "ABCDEFG"
	for i in range(letters.length()):
		assert_eq(ShipStatusBars.skill_name(letters[i]), expected[i])
	assert_eq(ShipStatusBars.skill_name("b"), "Able Seaman")


func test_morale_colours_run_green_to_red() -> void:
	assert_eq(ShipStatusBars.morale_color(2), ShipStatusBars.MORALE_COLORS[2])
	assert_eq(ShipStatusBars.morale_color(6), ShipStatusBars.MORALE_COLORS[6])
	assert_eq(ShipStatusBars.morale_color(1), ShipStatusBars.MORALE_COLORS[2], "below range: best")
	assert_eq(ShipStatusBars.morale_color(9), ShipStatusBars.MORALE_COLORS[6], "above range: worst")
	var seen := {}
	for rating in range(2, 7):
		seen[ShipStatusBars.morale_color(rating)] = true
	assert_eq(seen.size(), 5, "five distinct colours")
	assert_gt(ShipStatusBars.morale_color(2).g, ShipStatusBars.morale_color(2).r, "2 is green")
	assert_gt(ShipStatusBars.morale_color(6).r, ShipStatusBars.morale_color(6).g, "6 is red")


func test_bars_never_take_mouse_input() -> void:
	var bars := ShipStatusBars.new()
	assert_eq(bars.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(bars.size, ShipStatusBars.panel_size())
	bars.free()


func test_hover_status_waits_out_the_delay() -> void:
	assert_false(ShipStatusOverlay.hover_due("a", "", ShipStatusOverlay.HOVER_DELAY - 0.01))
	assert_true(ShipStatusOverlay.hover_due("a", "", ShipStatusOverlay.HOVER_DELAY))
	assert_false(ShipStatusOverlay.hover_due("", "", 5.0), "nothing under the mouse")
	assert_false(ShipStatusOverlay.hover_due("a", "a", 5.0), "the pinned ship already shows its status")
	assert_true(ShipStatusOverlay.hover_due("b", "a", 5.0))


func test_bars_drawn_larger_keep_their_proportions() -> void:
	var base := ShipStatusBars.panel_size()
	var big := ShipStatusBars.panel_size(4.0)
	assert_almost_eq(big.x, base.x * 4.0, 0.001)
	assert_almost_eq(big.y, base.y * 4.0, 0.001)
	var bars := ShipStatusBars.new(4.0)
	assert_eq(bars.size, big)
	bars.free()


func test_backing_is_thirty_percent_black_and_everything_else_opaque() -> void:
	assert_eq(ShipStatusBars.BACKING_COLOR, Color(0, 0, 0, 0.3))
	for c in [ShipStatusBars.LOST_COLOR, ShipStatusBars.HULL_COLOR, ShipStatusBars.RIGGING_COLOR,
			ShipStatusBars.MARINE_COLOR, ShipStatusBars.TEXT_COLOR]:
		assert_eq(c.a, 1.0)
	for rating in range(2, 7):
		assert_eq(ShipStatusBars.morale_color(rating).a, 1.0)


# --- Placement on the water -------------------------------------------------

const SIZE := Vector2(10.0, 3.0)
const EAST := Vector2(1, 0)
const NO_EDGE := Rect2()


func _side(others: Array, plates: Array = [], bounds: Rect2 = NO_EDGE, heading: Vector2 = EAST) -> int:
	return ShipStatusOverlay.choose_side(Vector2.ZERO, heading, SIZE, others, plates, bounds)


func test_plate_is_about_six_hexes_long() -> void:
	var size := ShipStatusOverlay.plate_size()
	assert_almost_eq(size.x, 6.0 * HexGrid.SQRT3, 0.001)
	var px := ShipStatusBars.panel_size()
	assert_almost_eq(size.y / size.x, px.y / px.x, 0.001, "same proportions as the bars")


func test_plate_lies_parallel_to_the_ship_on_every_side() -> void:
	for side in ShipStatusOverlay.SIDE_ORDER:
		var rect := ShipStatusOverlay.plate_rect(Vector2(2, 3), Vector2(0, -1), side, SIZE)
		assert_eq(rect["axis"], Vector2(0, -1), "long side along the heading")
		assert_false(ShipStatusOverlay.rect_covers(rect, Vector2(2, 3), 0.0), "never over the ship itself")


func test_plate_centres_for_an_east_heading_ship() -> void:
	var S := ShipStatusOverlay.Side
	var stern := ShipStatusOverlay.plate_rect(Vector2.ZERO, EAST, S.STERN, SIZE)
	var bow := ShipStatusOverlay.plate_rect(Vector2.ZERO, EAST, S.BOW, SIZE)
	var port := ShipStatusOverlay.plate_rect(Vector2.ZERO, EAST, S.PORT, SIZE)
	var starboard := ShipStatusOverlay.plate_rect(Vector2.ZERO, EAST, S.STARBOARD, SIZE)
	assert_eq(stern["center"], Vector2(-(ShipStatusOverlay.GAP_ALONG + 5.0), 0))
	assert_eq(bow["center"], Vector2(ShipStatusOverlay.GAP_ALONG + 5.0, 0))
	# world -Z is north: port of an east-heading ship
	assert_eq(port["center"], Vector2(0, -(ShipStatusOverlay.GAP_ACROSS + 1.5)))
	assert_eq(starboard["center"], Vector2(0, ShipStatusOverlay.GAP_ACROSS + 1.5))


func test_port_matches_the_hex_grid_port_directions() -> void:
	# Port is facing - 1 / facing - 2: for a ship facing east (0) that is NE (5) and NW (4).
	var grid := HexGrid.new()
	var here := grid.axial_to_world(0, 0)
	var port := ShipStatusOverlay.plate_rect(Vector2.ZERO, EAST, ShipStatusOverlay.Side.PORT, SIZE)
	for direction in [5, 4]:
		var n := grid.get_neighbor(0, 0, direction)
		var w := grid.axial_to_world(n.x, n.y) - here
		assert_gt(Vector2(w.x, w.z).dot(port["center"]), 0.0, "direction %d is on the port side" % direction)


func test_clear_water_puts_the_plate_astern() -> void:
	assert_eq(_side([]), ShipStatusOverlay.Side.STERN)
	assert_eq(_side([Vector2(0, 30)]), ShipStatusOverlay.Side.STERN, "a distant ship is no obstruction")


func test_sides_are_tried_astern_ahead_port_starboard() -> void:
	var S := ShipStatusOverlay.Side
	var astern := Vector2(-4, 0)
	var ahead := Vector2(4, 0)
	var to_port := Vector2(0, -2.5)
	var to_starboard := Vector2(0, 2.5)
	assert_eq(_side([astern]), S.BOW)
	assert_eq(_side([astern, ahead]), S.PORT)
	assert_eq(_side([astern, ahead, to_port]), S.STARBOARD)
	assert_eq(_side([astern, ahead, to_port, to_starboard]), S.STERN, "all taken: astern anyway")


func test_a_ship_just_off_the_plate_edge_still_obstructs() -> void:
	var rect := ShipStatusOverlay.plate_rect(Vector2.ZERO, EAST, ShipStatusOverlay.Side.STERN, SIZE)
	var edge_z := SIZE.y * 0.5
	assert_true(ShipStatusOverlay.is_obstructed(rect, [Vector2(-5, edge_z + 0.5)], [], NO_EDGE))
	assert_false(ShipStatusOverlay.is_obstructed(rect, [Vector2(-5, edge_z + 1.0)], [], NO_EDGE))


func test_another_plate_obstructs() -> void:
	var S := ShipStatusOverlay.Side
	var taken := ShipStatusOverlay.plate_rect(Vector2.ZERO, EAST, S.STERN, SIZE)
	assert_eq(_side([], [taken]), S.BOW, "the water astern already holds a plate")
	# a plate lying across at an angle is found too
	var slanted := ShipStatusOverlay.plate_rect(Vector2(-6, -8), Vector2(0.5, 0.866), S.BOW, SIZE)
	assert_true(ShipStatusOverlay.rects_overlap(taken, slanted))
	var far := ShipStatusOverlay.plate_rect(Vector2(0, 40), EAST, S.STERN, SIZE)
	assert_false(ShipStatusOverlay.rects_overlap(taken, far))


func test_the_map_edge_obstructs() -> void:
	var S := ShipStatusOverlay.Side
	# the map ends 3 units west of the ship: no room astern, plenty ahead
	assert_eq(_side([], [], Rect2(-3, -50, 103, 100)), S.BOW)
	assert_eq(_side([], [], Rect2(-50, -50, 100, 100)), S.STERN)


func test_text_never_reads_upside_down() -> void:
	var right := Vector2(1, 0)  # north-up camera: screen right is east
	assert_eq(ShipStatusOverlay.reading_direction(Vector2(1, 0), right), Vector2(1, 0))
	assert_eq(ShipStatusOverlay.reading_direction(Vector2(-1, 0), right), Vector2(1, 0), "west-heading: flipped")
	var sw := Vector2(-0.5, 0.866)
	assert_eq(ShipStatusOverlay.reading_direction(sw, right), -sw)
	var ne := Vector2(0.5, -0.866)
	assert_eq(ShipStatusOverlay.reading_direction(ne, right), ne)
	# with the camera turned to face south, east-running text would be upside down
	assert_eq(ShipStatusOverlay.reading_direction(Vector2(1, 0), Vector2(-1, 0)), Vector2(-1, 0))


func _overlay() -> ShipStatusOverlay:
	var overlay := ShipStatusOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(null, HexGrid.new())
	return overlay


func _state(hex: Vector2i, facing: int = 0) -> ShipState:
	var state := ShipState.new()
	state.hex_position = hex
	state.facing = facing
	return state


func test_overlay_pins_until_unpinned_and_hover_follows_the_mouse() -> void:
	GameState.ships.clear()
	var overlay := _overlay()
	var a := _state(Vector2i(0, 0))
	var b := _state(Vector2i(20, 0))
	overlay.pin("a", a)
	assert_eq(overlay.pinned_ship_id(), "a")
	assert_true(overlay.is_pinned_shown())
	overlay.set_hover_target("b", b)
	overlay._process(ShipStatusOverlay.HOVER_DELAY / 2.0)
	assert_false(overlay.is_hover_shown(), "not before the delay")
	overlay.set_hover_target("b", b)
	overlay._process(ShipStatusOverlay.HOVER_DELAY)
	assert_true(overlay.is_hover_shown(), "the same ship keeps its dwell time")
	overlay.set_hover_target("", null)
	assert_false(overlay.is_hover_shown(), "gone as soon as the mouse leaves")
	assert_eq(overlay._hover_time, 0.0, "leaving the ship resets the delay")
	overlay.unpin()
	assert_eq(overlay.pinned_ship_id(), "")
	assert_false(overlay.is_pinned_shown())


func test_hover_plate_keeps_clear_of_the_pinned_plate() -> void:
	GameState.ships.clear()
	var overlay := _overlay()
	# two ships in line ahead, both heading east: the follower's bow water is the leader's stern water
	overlay.pin("lead", _state(Vector2i(8, 0)))
	overlay.set_hover_target("follow", _state(Vector2i(0, 0)))
	overlay._process(ShipStatusOverlay.HOVER_DELAY)
	assert_true(overlay.is_hover_shown())
	assert_false(ShipStatusOverlay.rects_overlap(overlay._pinned.rect, overlay._hover.rect))


func test_suppressing_hides_every_status_and_keeps_the_pin() -> void:
	GameState.ships.clear()
	var overlay := _overlay()
	overlay.pin("a", _state(Vector2i(0, 0)))
	overlay.set_hover_target("b", _state(Vector2i(20, 0)))
	overlay._process(ShipStatusOverlay.HOVER_DELAY)
	assert_true(overlay.is_pinned_shown() and overlay.is_hover_shown())
	overlay.set_suppressed(true)
	assert_false(overlay.is_pinned_shown(), "nothing on the water while plotting or showing arcs")
	assert_false(overlay.is_hover_shown())
	overlay._process(ShipStatusOverlay.HOVER_DELAY * 2.0)
	assert_false(overlay.is_hover_shown(), "a hover does not appear while suppressed")
	assert_eq(overlay.pinned_ship_id(), "a", "the pin survives")
	overlay.set_suppressed(false)
	assert_true(overlay.is_pinned_shown(), "and the status returns afterwards")
	assert_false(overlay.is_hover_shown(), "a hover waits out its delay again")


func test_motion_line_gives_speed_and_point_of_sail() -> void:
	assert_eq(ShipStatusBars.motion_text(2, "Broad Reach"), "2 · Broad Reach")
	assert_eq(ShipStatusBars.motion_text(0, ""), "0", "no wind known: speed alone")
