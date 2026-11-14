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


func test_bars_sit_centred_above_the_ship_and_inside_the_map() -> void:
	var size := Vector2(200, 60)
	var rect := Rect2(300, 0, 900, 700)
	var pos := ShipStatusOverlay.bars_position(Vector2(700, 400), size, rect)
	assert_eq(pos.x, 600.0)
	assert_eq(pos.y, 400.0 - ShipStatusOverlay.LIFT_PX - 60.0)
	# near the left panel and the top edge it is pushed back onto the map
	pos = ShipStatusOverlay.bars_position(Vector2(310, 20), size, rect)
	assert_eq(pos, Vector2(306, 6))


func test_overlay_pins_until_unpinned_and_hover_follows_the_mouse() -> void:
	var overlay := ShipStatusOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(null)
	var state := ShipState.new()
	overlay.pin("a", state, null)
	assert_eq(overlay.pinned_ship_id(), "a")
	overlay.set_hover_target("b", state, null)
	overlay._process(ShipStatusOverlay.HOVER_DELAY / 2.0)
	assert_eq(overlay._hover_time, ShipStatusOverlay.HOVER_DELAY / 2.0)
	overlay.set_hover_target("b", state, null)
	assert_gt(overlay._hover_time, 0.0, "the same ship keeps its dwell time")
	overlay.set_hover_target("", null, null)
	assert_eq(overlay._hover_time, 0.0, "leaving the ship resets the delay")
	assert_false(overlay.is_hover_shown())
	overlay.unpin()
	assert_eq(overlay.pinned_ship_id(), "")


func test_suppressing_hides_every_status_and_keeps_the_pin() -> void:
	var overlay := ShipStatusOverlay.new()
	add_child_autofree(overlay)
	overlay.setup(null)
	var state := ShipState.new()
	overlay.pin("a", state, null)
	overlay.set_hover_target("b", state, null)
	overlay._hover_bars.visible = true
	overlay._pinned_bars.visible = true
	overlay.set_suppressed(true)
	assert_false(overlay.is_pinned_shown(), "nothing over the map while plotting")
	assert_false(overlay.is_hover_shown())
	overlay._process(ShipStatusOverlay.HOVER_DELAY * 2.0)
	assert_false(overlay.is_hover_shown(), "a hover does not appear while suppressed")
	assert_eq(overlay.pinned_ship_id(), "a", "the pin survives, so the status returns afterwards")
	overlay.set_suppressed(false)
	assert_eq(overlay._hover_time, 0.0, "a hover waits out its delay again")
