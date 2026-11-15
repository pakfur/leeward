extends Node
## Self-driving check for the crew overlay prototype, used when the godot-mcp
## interaction port is held by another running game. Feeds real mouse events
## through Input.parse_input_event at window-pixel positions (canvas position
## times the root's final transform, as game_click needs) and saves screenshots.
## Enabled by: godot res://prototypes/crew_overlay/crew_overlay_proto.tscn -- --selftest=<dir>

const Counter := preload("res://prototypes/crew_overlay/counter_token.gd")
const Station := preload("res://prototypes/crew_overlay/station_panel.gd")

var out_dir := ""
var use_local := false
var proto: Control
var _shot := 0


func _ready() -> void:
	_run.call_deferred()


func _log(t: String) -> void:
	Trace.trace_log("proto_selftest", t)
	print("SELFTEST ", t)  # allow-print


func _win(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_shot += 1
	var path := "%s/%02d_%s.png" % [out_dir, _shot, name]
	get_viewport().get_texture().get_image().save_png(path)
	_log("screenshot " + path)


## Window-pixel event through the OS input path (as game_click), unless --selftest-local,
## which pushes canvas-coordinate events straight into the viewport.
func _send(e: InputEventMouse) -> void:
	if use_local:
		var inv := get_tree().root.get_final_transform().affine_inverse()
		e.position = inv * e.position
		if e is InputEventMouseMotion:
			e.relative = inv.basis_xform(e.relative)
		e.global_position = e.position
		get_viewport().push_input(e, true)
	else:
		Input.parse_input_event(e)


var _last := Vector2.ZERO


func _move(p: Vector2, mask := 0) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _win(p)
	e.relative = e.position - _last
	_last = e.position
	e.global_position = e.position
	e.button_mask = mask
	_send(e)


func _button(p: Vector2, idx: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = _win(p)
	e.global_position = e.position
	e.button_index = idx
	e.pressed = pressed
	e.button_mask = (1 << (idx - 1)) if pressed else 0
	_send(e)


func click(p: Vector2, idx := MOUSE_BUTTON_LEFT) -> void:
	_move(p)
	await _frames(2)
	_button(p, idx, true)
	await _frames(2)
	_button(p, idx, false)
	await _frames(3)


## Press at a, move in steps to b, optionally screenshot mid-drag, release.
func drag(a: Vector2, b: Vector2, mid_shot := "") -> void:
	_move(a)
	await _frames(2)
	_button(a, MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	for i in range(1, 16):
		_move(a.lerp(b, i / 15.0), MOUSE_BUTTON_MASK_LEFT)
		await _frames(1)
	await _frames(3)
	_log("mid-drag dragging=%s data=%s mouse=%s focus=%s" % [get_viewport().gui_is_dragging(), str(get_viewport().gui_get_drag_data()), str(get_viewport().get_mouse_position()), str(get_viewport().gui_get_hovered_control())])
	if mid_shot != "":
		await shot(mid_shot)
	_button(b, MOUSE_BUTTON_LEFT, false)
	await _frames(4)


func center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## Scrolls the left panel so c is on screen (the planning panel overflows 1080 px), then its centre.
func pos(c: Control) -> Vector2:
	var p := c.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		(p as ScrollContainer).ensure_control_visible(c)
		await _frames(3)
	return center(c)


func roster_counter(sec: String) -> Control:
	for n in proto._roster.find_children("*", "", true, false):
		if n.get_script() == Counter and n.sec == sec:
			return n
	return null


func big_station(target: String) -> Control:
	for n in proto._big_deck.find_children("*", "", true, false):
		if n.get_script() == Station and n.target == target:
			return n
	return null


func button(text: String) -> Button:
	for n in proto.find_children("*", "BaseButton", true, false):
		if n is Button and n.is_visible_in_tree() and n.text.begins_with(text):
			return n
	return null


func state() -> String:
	return str(proto.m.assignments) + " msg=" + (proto._msg.get_child(0).get_child(0).text if proto._msg.visible and proto._msg.get_child_count() else "-")


func _run() -> void:
	await _frames(10)
	_log("scale " + str(get_tree().root.get_final_transform().get_scale()) + " window " + str(DisplayServer.window_get_size()))
	await shot("initial")
	for n in proto._other_decks.find_children("*", "", true, false):
		if n.get_script() == Station:
			_log("small station %s rect=%s vis=%s parent=%s psize=%s" % [n.target, n.get_global_rect(), n.is_visible_in_tree(), n.get_parent().get_class(), n.get_parent().size])
	if OS.get_cmdline_user_args().has("--selftest-quick"):
		get_tree().quit()
		return
	_log("start " + state())

	# 1. drag S2 from the roster to Boarders (S1 is on the fire, so S2 is the lowest free)
	await drag(await pos(roster_counter("S2")), await pos(big_station("boarders")), "dragging_S2")
	_log("after S2 -> boarders: " + state())
	await shot("S2_on_boarders")

	# 2. refusal: S4 to Boarders while S3 is free of fire duty
	await drag(await pos(roster_counter("S4")), await pos(big_station("boarders")))
	_log("after S4 -> boarders: " + state())
	await shot("refusal_S4_boarders")

	# 3. progress loss: S3 (rigging repair, 2 turns done) to the guns -> confirm bar
	proto.m.deck = "upper"
	await drag(await pos(roster_counter("S3")), await pos(big_station("braces") if big_station("braces") else big_station("marine_fire")))
	_log("after S3 -> marine fire: " + state())
	await shot("refusal_S3_marine")
	await drag(await pos(roster_counter("S3")), await pos(big_station("boarders")))
	_log("after S3 -> boarders (progress): " + state())
	await shot("progress_confirm")
	await click(await pos(button("Keep it there")))
	_log("after keep: " + state())

	# 4. click-then-click: M to Boarders
	await click(await pos(roster_counter("M")))
	await shot("M_selected")
	await click(await pos(big_station("boarders")))
	_log("after M click-click: " + state())

	# 5. right-click S4 -> menu
	await click(await pos(roster_counter("S4")), MOUSE_BUTTON_RIGHT)
	await _frames(4)
	var menu: PopupMenu = proto._menu
	var items: Array = []
	for i in menu.item_count:
		items.append("%s%s%s" % [menu.get_item_text(i), " [disabled]" if menu.is_item_disabled(i) else "", (" {" + menu.get_item_tooltip(i) + "}") if menu.get_item_tooltip(i) != "" else ""])
	_log("menu visible=%s items=%s" % [menu.visible, "\n  ".join(items)])
	await shot("context_menu")
	# pick "Fighting fire 1" is disabled (S1 there); pick Serve the guns via a real click
	var idx := -1
	for i in menu.item_count:
		if menu.get_item_text(i).begins_with("Serve the guns"):
			idx = i
	menu.hide()
	await _frames(2)

	# 6. drag onto a small deck in the side list (orlop card) -> enlarged deck switches after 450 ms
	var orlop_card: Control = proto._other_decks.get_child(1)
	var start: Vector2 = await pos(roster_counter("S4"))
	_move(start)
	await _frames(2)
	_button(start, MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	var tgt: Vector2 = await pos(orlop_card)
	for i in range(1, 12):
		_move(start.lerp(tgt, i / 11.0), MOUSE_BUTTON_MASK_LEFT)
		await _frames(1)
	await get_tree().create_timer(0.7).timeout
	_move(tgt + Vector2(1, 1), MOUSE_BUTTON_MASK_LEFT)
	await _frames(3)
	_log("after hover over orlop card: deck=" + proto.m.deck)
	var rh := big_station("rh")
	if rh:
		var p: Vector2 = await pos(rh)
		for i in range(1, 8):
			_move(tgt.lerp(p, i / 7.0), MOUSE_BUTTON_MASK_LEFT)
			await _frames(1)
		await shot("drag_to_orlop")
		_button(p, MOUSE_BUTTON_LEFT, false)
	else:
		_button(tgt, MOUSE_BUTTON_LEFT, false)
	await _frames(4)
	_log("after S4 -> rh: " + state())
	await shot("orlop")

	# 7. switch to the 74 through the OptionButton
	var ship_opt: OptionButton = proto._ship_opt
	await click(await pos(ship_opt))
	await _frames(3)
	var pop := ship_opt.get_popup()
	_log("ship popup visible=%s rect=%s" % [pop.visible, str(Rect2(pop.position, pop.size))])
	await shot("ship_popup")
	# second item: popup is an embedded window in canvas coordinates
	var item_y := pop.position.y + pop.size.y * 0.75
	await click(Vector2(pop.position.x + pop.size.x * 0.5, item_y))
	_log("ship now " + proto.m.ship_key + " deck=" + proto.m.deck)
	await click(await pos(proto._other_decks.get_child(0)))
	await shot("sol74")

	# 8. add fires with the + stepper
	await click(await pos(button("+")))
	await click(await pos(button("+")))
	_log("fires %d: %s" % [proto.m.fires.size(), state()])
	await shot("three_fires")
	await click(await pos(button("+")))
	await shot("four_fires")
	_log("fires %d: %s" % [proto.m.fires.size(), state()])

	# 9. sail MS -> RR station disabled
	proto._sail_opt.select(1)
	proto._sail_opt.item_selected.emit(1)
	await _frames(4)
	await shot("sail_MS")
	_log("after MS: " + state())

	# 10. close overlay
	await click(await pos(button("Done")))
	await shot("closed")
	_log("DONE")
	get_tree().quit()
