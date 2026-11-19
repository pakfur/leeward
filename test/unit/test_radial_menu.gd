extends GutTest
## RadialMenu and RadialItem (board planning, view only). Hover, focus and choice are driven through
## the menu's own methods, so nothing here waits on frame timing or the pop-in tween.

var menu: RadialMenu


func before_each() -> void:
	menu = RadialMenu.new()
	add_child_autofree(menu)


func _item(id: String, off_reason := "", hint := "") -> RadialItem:
	var item := RadialItem.new()
	item.id = id
	item.label = id.capitalize()
	item.hint = hint
	item.off_reason = off_reason
	return item


func _items(n: int) -> Array[RadialItem]:
	var items: Array[RadialItem] = []
	for i in n:
		items.append(_item("item_%d" % i))
	return items


func _open_at(items: Array[RadialItem], point: Vector2) -> void:
	menu.set_anchor_provider(func() -> Vector2: return point)
	menu.open(items, "Bellerophon", "Speed 3 · MA 5")


func test_items_laid_out_on_circle() -> void:
	var centre := Vector2(900, 500)
	_open_at(_items(5), centre)
	assert_eq(menu.item_count(), 5)
	assert_eq(menu.ring_center(), centre)
	var first := menu.item_center(0) - centre
	assert_almost_eq(first.x, 0.0, 0.01, "first item at the top")
	assert_almost_eq(first.y, -RadialMenu.RADIUS, 0.01, "first item at the top")
	for i in 5:
		var offset := menu.item_center(i) - centre
		assert_almost_eq(offset.length(), RadialMenu.RADIUS, 0.01, "item %d on the circle" % i)
		var expected := -PI / 2.0 + i * TAU / 5.0
		assert_almost_eq(angle_difference(offset.angle(), expected), 0.0, 0.0001,
				"item %d at an equal angle" % i)


func test_radius_follows_ui_scale() -> void:
	menu.ui_scale = 1.5
	var centre := Vector2(900, 500)
	_open_at(_items(3), centre)
	assert_almost_eq((menu.item_center(1) - centre).length(), RadialMenu.RADIUS * 1.5, 0.01)


func test_disabled_item_emits_nothing() -> void:
	var items: Array[RadialItem] = [_item("move", "Anchored: she cannot move."), _item("crew")]
	_open_at(items, Vector2(900, 500))
	watch_signals(menu)
	menu.choose(0)
	assert_signal_not_emitted(menu, "item_chosen")


func test_enabled_item_emits_id() -> void:
	var items: Array[RadialItem] = [_item("move", "Anchored: she cannot move."), _item("crew")]
	_open_at(items, Vector2(900, 500))
	watch_signals(menu)
	menu.choose(1)
	assert_signal_emitted_with_parameters(menu, "item_chosen", ["crew"])


func test_caption_shows_reason_on_hover() -> void:
	var items: Array[RadialItem] = [
		_item("move", "Anchored: she cannot move.", "Plot her course hex by hex."),
		_item("crew", "", "Open the crew overlay."),
	]
	_open_at(items, Vector2(900, 500))
	assert_eq(menu.caption_text(), "", "nothing hovered, no caption")
	menu.hover_item(0)
	assert_eq(menu.caption_text(), "Move\nAnchored: she cannot move.", "a greyed item shows its reason")
	assert_true(menu.caption_is_reason())
	menu.hover_item(1)
	assert_eq(menu.caption_text(), "Crew\nOpen the crew overlay.", "an enabled item shows its hint")
	assert_false(menu.caption_is_reason())
	menu.hover_item(-1)
	assert_eq(menu.caption_text(), "")


func test_no_ring_control_takes_keyboard_focus() -> void:
	var items: Array[RadialItem] = [_item("move", "", "Plot."), _item("done", "", "Done.")]
	_open_at(items, Vector2(900, 500))
	var stack: Array = [menu]
	var seen := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Control:
			seen += 1
			assert_eq(n.focus_mode, Control.FOCUS_NONE, "%s takes no focus" % n.name)
	assert_gt(seen, 2)
	menu.focus_item(1)
	assert_null(menu.get_viewport().gui_get_focus_owner(), "focus_item only highlights")


func test_caption_follows_focus() -> void:
	var items: Array[RadialItem] = [_item("move", "", "Plot her course."), _item("done", "", "Mark her done.")]
	_open_at(items, Vector2(900, 500))
	menu.focus_item(1)
	assert_eq(menu.caption_text(), "Done\nMark her done.")
	menu.hover_item(0)
	assert_eq(menu.caption_text(), "Move\nPlot her course.", "hover wins over focus")
	menu.hover_item(-1)
	assert_eq(menu.caption_text(), "Done\nMark her done.", "back to the focused item")


func test_clamped_inside_safe_rect() -> void:
	var safe := Rect2(320, 40, 1500, 1000)
	menu.set_safe_rect(safe)
	_open_at(_items(5), Vector2(330, 1035))
	var half := RadialMenu.BUTTON_SIZE / 2.0
	for i in 5:
		var c := menu.item_center(i)
		var r := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
		assert_true(safe.encloses(r), "item %d inside the safe rect (%s)" % [i, r])
	# The anchor is read every frame: a new point moves the ring, still clamped.
	menu.set_anchor_provider(func() -> Vector2: return Vector2(1900, 20))
	menu._process(0.016)
	for i in 5:
		var c := menu.item_center(i)
		var r := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
		assert_true(safe.encloses(r), "item %d inside after the anchor moved (%s)" % [i, r])


func test_caption_stays_inside_safe_rect_at_the_sides() -> void:
	var safe := Rect2(320, 40, 1500, 1000)
	menu.set_safe_rect(safe)
	var long_hint := "Plot her course hex by hex on the board, then mark her done."
	for point: Vector2 in [Vector2(330, 500), Vector2(1810, 500), Vector2(330, 1035)]:
		var items: Array[RadialItem] = [_item("move", "", long_hint), _item("crew", "", long_hint)]
		_open_at(items, point)
		menu.hover_item(0)
		# The labels' new wrap width reaches the containers' cached sizes a frame later; the menu
		# places itself every frame.
		await get_tree().process_frame
		menu._process(0.016)
		var r := menu.caption_rect()
		assert_gt(r.size.x, 0.0, "the caption has a width")
		assert_true(safe.encloses(r), "caption inside the safe rect at %s (%s)" % [point, r])
		menu.close()
	# Clear of the edges, the caption stays centred on the ring.
	_open_at([_item("move", "", long_hint)] as Array[RadialItem], Vector2(1000, 500))
	menu.hover_item(0)
	assert_almost_eq(menu.caption_rect().get_center().x, menu.ring_center().x, 0.5)


func test_follows_anchor_each_frame() -> void:
	var point := [Vector2(900, 500)]
	menu.set_anchor_provider(func() -> Vector2: return point[0])
	menu.open(_items(3), "Bellerophon", "")
	point[0] = Vector2(1000, 600)
	menu._process(0.016)
	assert_eq(menu.ring_center(), Vector2(1000, 600))


func test_close_emits_closed() -> void:
	_open_at(_items(3), Vector2(900, 500))
	assert_true(menu.is_open())
	watch_signals(menu)
	menu.close()
	assert_false(menu.is_open())
	assert_eq(menu.item_count(), 0)
	assert_signal_emit_count(menu, "closed", 1)
	menu.close()
	assert_signal_emit_count(menu, "closed", 1, "closing a closed menu emits nothing")


func test_title_and_subtitle_in_centre() -> void:
	_open_at(_items(3), Vector2(900, 500))
	assert_eq(menu.title_text(), "Bellerophon")
	assert_eq(menu.subtitle_text(), "Speed 3 · MA 5")


func test_reopen_replaces_items() -> void:
	_open_at(_items(5), Vector2(900, 500))
	_open_at(_items(2), Vector2(900, 500))
	assert_eq(menu.item_count(), 2)


func test_icons_load() -> void:
	for name in ["move", "crew", "orders", "signal", "reset", "done", "undo"]:
		var tex := load("res://assets/ui/radial/%s.svg" % name) as Texture2D
		assert_not_null(tex, "%s icon imports as a texture" % name)
