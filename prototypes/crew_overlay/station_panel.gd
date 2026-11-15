extends Control
## One station (one task) on a deck drawing: a dashed panel that accepts dropped
## counters, highlights valid/invalid while a counter is dragged or selected, and
## takes the second click of click-then-click.

const Style := preload("res://prototypes/crew_overlay/proto_style.gd")

var target := ""
var fire := false
var unfought := false
var disabled := false
var small := false
## The overlay: provides mark_for(target), drop_on(target, sec), station_clicked(target).
var ov: Object
var content: VBoxContainer

var _mark := ""
var _over := false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_PASS
	clip_contents = true
	content = VBoxContainer.new()
	content.mouse_filter = MOUSE_FILTER_IGNORE
	content.set_anchors_preset(PRESET_FULL_RECT)
	add_child(content)


func set_padding(p: int) -> void:
	content.offset_left = p + 2
	content.offset_top = p
	content.offset_right = -p - 2
	content.offset_bottom = -p
	content.add_theme_constant_override("separation", maxi(1, p))


func _ready() -> void:
	refresh_mark()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN or what == NOTIFICATION_DRAG_END:
		_over = false
		refresh_mark()


func refresh_mark() -> void:
	if ov == null or not is_inside_tree():
		return
	_mark = ov.mark_for(target)
	queue_redraw()


func _process(_d: float) -> void:
	# Hover comes from the drop queries, not the OS cursor, so injected drags (godot-mcp) show it too.
	var over: bool = get_viewport().gui_is_dragging() and ov != null and ov.drop_hover_id == get_instance_id()
	if over != _over:
		_over = over
		queue_redraw()


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	# Accept every counter: an invalid drop is refused with the reason, as in the HTML.
	ov.note_drop_hover(self)
	return data is Dictionary and data.has("sec")


func _drop_data(_at: Vector2, data: Variant) -> void:
	ov.drop_on(target, data["sec"])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if ov.station_clicked(target):
			accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := 5 if small else 8
	var bw := 1.5 if small else 2.0
	var bg := Color(0.965, 0.925, 0.84, 0.28)
	var border := Color(Style.CARD_INK, 0.55)
	var solid := false
	if fire:
		solid = true
		border = Style.FIRE
		bg = Color(Style.FIRE, 0.28)
		if unfought:
			border = Style.BAD
			bg = Color(Style.BAD, 0.32)
	if _mark == "valid":
		border = Style.OK
		bg = Color(Style.OK, 0.32)
	elif _mark == "invalid":
		border = Style.BAD
		bg = Color(Style.BAD, 0.18)
	if disabled:
		bg = Color(0.235, 0.235, 0.235, 0.25)
	draw_style_box(Style.box(bg, Color.TRANSPARENT, 0, rad), r)
	if solid:
		draw_style_box(Style.box(Color.TRANSPARENT, border, int(bw), rad), r)
	else:
		var a := Vector2(bw / 2, bw / 2)
		var b := size - a
		var dash := 6.0 if small else 8.0
		draw_dashed_line(Vector2(a.x + rad, a.y), Vector2(b.x - rad, a.y), border, bw, dash)
		draw_dashed_line(Vector2(a.x + rad, b.y), Vector2(b.x - rad, b.y), border, bw, dash)
		draw_dashed_line(Vector2(a.x, a.y + rad), Vector2(a.x, b.y - rad), border, bw, dash)
		draw_dashed_line(Vector2(b.x, a.y + rad), Vector2(b.x, b.y - rad), border, bw, dash)
		for c in [[Vector2(a.x + rad, a.y + rad), PI], [Vector2(b.x - rad, a.y + rad), -PI / 2],
				[Vector2(b.x - rad, b.y - rad), 0.0], [Vector2(a.x + rad, b.y - rad), PI / 2]]:
			draw_arc(c[0], rad, c[1], c[1] + PI / 2, 6, border, bw)
	if _over:
		draw_style_box(Style.box(Color.TRANSPARENT, Style.WARN, 3, rad), r)
	if disabled:
		modulate.a = 0.55
