class_name CrewCounterToken
extends Control
## A cardboard crew-section counter (S1–S4, M): one crew section (crew-tasks spec §4.2). Drag
## source (built-in drag and drop), click to pick up, right-click (or Shift+F10 / the menu key) for
## the assign-to menu. Drawn with _draw(); ported from prototypes/crew_overlay/counter_token.gd.
## View only: it shows what it is given and reports clicks to the overlay.

signal clicked(section: int)
signal context_requested(section: int, screen_pos: Vector2)

var section := -1
var marine := false
var boxes := 3
## Progress tag in the band: "T2/4", or the fire attempt column ("1st", "2nd", "3rd+").
var prog_text := ""
## AUTO tag: placed by the rules (fire draft, or Automatic on) rather than by the player.
var auto_mark := false
## Cannot be moved (forced task, sail change in progress, Automatic on); the reason is the tooltip.
var locked := false
## Crew disorganized (RO): greyed face.
var disorganized := false
var selected := false
var is_preview := false
## Returns a fresh preview Control for a drag; set by the overlay.
var make_preview: Callable
## Whether a drag may start (read-only overlay: false).
var draggable := true


func setup(p_section: int, p_boxes: int, p_size: float) -> void:
	section = p_section
	marine = p_section == ShipState.MARINES
	boxes = p_boxes
	custom_minimum_size = Vector2(p_size, p_size)
	size = custom_minimum_size
	mouse_filter = MOUSE_FILTER_IGNORE if is_preview else MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	tooltip_text = "" if is_preview else section_name()


func section_name() -> String:
	return ShipState.SECTION_NAMES[section] if section >= 0 and section <= ShipState.MARINES else "?"


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
		lifted = d is Dictionary and int(d.get("section", -1)) == section
	modulate.a = 0.35 if lifted else 1.0


func _get_drag_data(_at: Vector2) -> Variant:
	if is_preview or section < 0 or not draggable:
		return null
	if make_preview.is_valid():
		set_drag_preview(make_preview.call(section))
	return {"section": section}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_MENU or (event.keycode == KEY_F10 and event.shift_pressed)):
		accept_event()
		context_requested.emit(section, get_global_rect().get_center())
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		accept_event()
		clicked.emit(section)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		accept_event()
		context_requested.emit(section, get_global_transform() * mb.position)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()


func _draw() -> void:
	var s := size.x
	var r := Rect2(Vector2.ZERO, Vector2(s, s))
	var rad := maxi(3, int(s * 0.09))
	# drop shadow and edge
	draw_style_box(CrewStyle.box(Color(0, 0, 0, 0.35), Color.TRANSPARENT, 0, rad + 2), Rect2(Vector2(1, 4), r.size))
	draw_style_box(CrewStyle.box(CrewStyle.CARD_EDGE, Color.TRANSPARENT, 0, rad), Rect2(Vector2(0, 2), r.size))
	var face_color := CrewStyle.CARD.darkened(0.35) if disorganized else CrewStyle.CARD
	draw_style_box(CrewStyle.box(face_color, CrewStyle.CARD_EDGE, 1, rad), r)
	# coloured band across the top; taller when it carries a tag (progress, AUTO), which sits in the
	# band so it never covers the section number
	var font := CrewStyle.bold_font()
	var tag_fs := maxi(9, int(s * 0.19))
	var has_tag := prog_text != "" or auto_mark or disorganized
	var band_h := maxf(s * 0.2, font.get_height(tag_fs) + 1.0) if has_tag else s * 0.2
	var band_color := CrewStyle.MARINE if marine else CrewStyle.SAILOR
	if disorganized:
		band_color = band_color.darkened(0.4)
	var band := CrewStyle.box(band_color, Color.TRANSPARENT, 0, 0)
	band.corner_radius_top_left = rad
	band.corner_radius_top_right = rad
	draw_style_box(band, Rect2(1, 1, s - 2, band_h))
	var right_tag := "RO" if disorganized and prog_text == "" else prog_text
	if right_tag != "":
		var pw := font.get_string_size(right_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs).x
		draw_string(font, Vector2(s - pw - 3, 1 + font.get_ascent(tag_fs)), right_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, Color.WHITE)
	if auto_mark:
		draw_string(font, Vector2(3, 1 + font.get_ascent(tag_fs)), "AUTO", HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, Color("#ffd2b8"))
	# id, centred in the space between the band and the pips
	var label := section_name()
	var fs := int(s * (0.34 if has_tag else 0.38))
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((s - tw) / 2.0, band_h + s * 0.04 + font.get_ascent(fs)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		CrewStyle.CARD_INK if not disorganized else Color(CrewStyle.CARD_INK, 0.6))
	# pips: one per box, at most 6, then a number
	var pip := maxf(4.0, s * 0.1)
	var py := s - pip - maxf(3.0, s * 0.07)
	if boxes > 6:
		var txt := "%d" % boxes
		var nfs := maxi(9, int(s * 0.2))
		var nw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
		draw_string(font, Vector2((s - nw) / 2.0, py + pip), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, CrewStyle.CARD_INK)
	else:
		var n := boxes
		var gap := 2.0
		var total := n * pip + (n - 1) * gap
		var x0 := (s - total) / 2.0
		for i in n:
			draw_rect(Rect2(x0 + i * (pip + gap), py, pip, pip), CrewStyle.CARD_INK)
	if locked:
		# a small padlock in the lower right corner
		var lw := maxf(6.0, s * 0.14)
		var lo := Vector2(s - lw - 3, s - lw - 3)
		draw_rect(Rect2(lo + Vector2(0, lw * 0.4), Vector2(lw, lw * 0.6)), Color("#5a4a30"))
		draw_arc(lo + Vector2(lw / 2.0, lw * 0.4), lw * 0.32, PI, TAU, 8, Color("#5a4a30"), maxf(1.5, s * 0.03))
	if selected:
		draw_style_box(CrewStyle.box(Color.TRANSPARENT, CrewStyle.ACCENT, 3, rad + 3), Rect2(Vector2(-5, -5), r.size + Vector2(10, 10)))
