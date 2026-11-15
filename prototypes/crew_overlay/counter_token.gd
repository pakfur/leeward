extends Control
## A cardboard crew-section counter (S1–S4, M). Drag source (built-in drag and drop),
## click to select, right-click for the task menu. Drawn with _draw().

const Style := preload("res://prototypes/crew_overlay/proto_style.gd")

signal clicked(sec: String)
signal context_requested(sec: String, screen_pos: Vector2)

var sec := ""
var marine := false
var boxes := 3
var prog_text := ""
var auto_mark := false
var selected := false
var is_preview := false
## Returns a fresh preview Control for a drag; set by the overlay.
var make_preview: Callable


func setup(p_sec: String, p_boxes: int, p_size: float) -> void:
	sec = p_sec
	marine = p_sec == "M"
	boxes = p_boxes
	custom_minimum_size = Vector2(p_size, p_size)
	size = custom_minimum_size
	mouse_filter = MOUSE_FILTER_IGNORE if is_preview else MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	tooltip_text = "" if is_preview else sec


func _ready() -> void:
	_update_lifted()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN or what == NOTIFICATION_DRAG_END:
		_update_lifted()


func _update_lifted() -> void:
	if is_preview or not is_inside_tree():
		return
	var lifted := false
	if get_viewport().gui_is_dragging():
		var d = get_viewport().gui_get_drag_data()
		lifted = d is Dictionary and d.get("sec", "") == sec
	modulate.a = 0.35 if lifted else 1.0


func _get_drag_data(_at: Vector2) -> Variant:
	if is_preview or sec == "":
		return null
	if make_preview.is_valid():
		set_drag_preview(make_preview.call(sec))
	return {"sec": sec}


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		accept_event()
		clicked.emit(sec)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		accept_event()
		context_requested.emit(sec, get_global_transform() * mb.position)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()


func _draw() -> void:
	var s := size.x
	var r := Rect2(Vector2.ZERO, Vector2(s, s))
	var rad := maxi(3, int(s * 0.09))
	# drop shadow and edge (box-shadow: 0 2px 0 edge, 0 3px 6px black)
	draw_style_box(Style.box(Color(0, 0, 0, 0.35), Color.TRANSPARENT, 0, rad + 2), Rect2(Vector2(1, 4), r.size))
	draw_style_box(Style.box(Style.CARD_EDGE, Color.TRANSPARENT, 0, rad), Rect2(Vector2(0, 2), r.size))
	var face := Style.box(Style.CARD, Style.CARD_EDGE, 1, rad)
	draw_style_box(face, r)
	# coloured band across the top; taller when it carries a tag (turn progress, AUTO), which sits in
	# the band so it never covers the section number
	var font := Style.bold_font()
	var tag_fs := maxi(9, int(s * 0.19))
	var has_tag := prog_text != "" or auto_mark
	var band_h := maxf(s * 0.2, font.get_height(tag_fs) + 1.0) if has_tag else s * 0.2
	var band := Style.box(Style.MARINE if marine else Style.SAILOR, Color.TRANSPARENT, 0, 0)
	band.corner_radius_top_left = rad
	band.corner_radius_top_right = rad
	draw_style_box(band, Rect2(1, 1, s - 2, band_h))
	if prog_text != "":
		var pw := font.get_string_size(prog_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs).x
		draw_string(font, Vector2(s - pw - 3, 1 + font.get_ascent(tag_fs)), prog_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, Color.WHITE)
	if auto_mark:
		draw_string(font, Vector2(3, 1 + font.get_ascent(tag_fs)), "AUTO", HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, Color("#ffd2b8"))
	# id, centred in the space between the band and the pips
	var fs := int(s * (0.34 if has_tag else 0.38))
	var tw := font.get_string_size(sec, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((s - tw) / 2.0, band_h + s * 0.04 + font.get_ascent(fs)), sec, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Style.CARD_INK)
	# pips: one per box, at most 6
	var n := mini(boxes, 6)
	var pip := maxf(4.0, s * 0.1)
	var gap := 2.0
	var total := n * pip + (n - 1) * gap
	var x0 := (s - total) / 2.0
	for i in n:
		draw_rect(Rect2(x0 + i * (pip + gap), s - pip - maxf(3.0, s * 0.07), pip, pip), Style.CARD_INK)
	if selected:
		var o := Style.box(Color.TRANSPARENT, Style.ACCENT, 3, rad + 3)
		draw_style_box(o, Rect2(Vector2(-5, -5), r.size + Vector2(10, 10)))
