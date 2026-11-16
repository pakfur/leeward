class_name CrewDeckView
extends Control
## Ported from prototypes/crew_overlay/deck_view.gd (approved design), unchanged in drawing.
## A deck drawing, procedural (_draw), in the HTML prototype's landscape units
## (1000 x 360). Portrait (bow up) rotates the geometry 90 degrees and widens the
## beam by PK: landscape (x, y) -> portrait (y * PK, 1000 - x) in a PW x 1000 box.
## Children placed with place() keep their landscape rect through the mapping.

const Style = preload("res://scripts/ui/crew_overlay/crew_style.gd")

const PK := 1.4
const PW := 360.0 * PK

var deck: Dictionary = {}
var gun_decks: Array = []
var portrait := false
var small := false

var _placed: Array = []  # [control, rect, is_marker]
var _hull: PackedVector2Array
var _orlop_inner: PackedVector2Array


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_hull = _path([[70, 58], ["L", 690, 50], ["Q", 900, 66, 968, 180], ["Q", 900, 294, 690, 310], ["L", 70, 302], ["Q", 46, 180, 70, 58]])
	_orlop_inner = _path([[110, 92], ["L", 690, 86], ["Q", 860, 100, 912, 180], ["Q", 860, 260, 690, 274], ["L", 110, 268], ["Q", 92, 180, 110, 92]])


func setup(p_deck: Dictionary, p_gun_decks: Array, p_portrait: bool, p_small: bool) -> void:
	deck = p_deck
	gun_decks = p_gun_decks
	portrait = p_portrait
	small = p_small
	resized.connect(_layout)


func _ready() -> void:
	_layout()


## Aspect ratio (width / height) of the drawing.
func aspect() -> float:
	return PW / 1000.0 if portrait else 1000.0 / 360.0


func place(c: Control, rect: Array) -> void:
	add_child(c)
	_placed.append([c, rect, false])
	_layout()


func add_marker(x: float, y: float, text: String, info := false) -> void:
	var l := Style.label(text, 12, Color.WHITE, true)
	var sb := Style.box(Color("#6b4a2a") if info else Style.BAD, Color(1, 1, 1, 0.2), 2, 4)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	l.mouse_filter = MOUSE_FILTER_PASS
	l.tooltip_text = text
	add_child(l)
	_placed.append([l, [x, y], true])
	_layout()


func _layout() -> void:
	var sx := size.x / (PW if portrait else 1000.0)
	var sy := size.y / (1000.0 if portrait else 360.0)
	for p in _placed:
		var c: Control = p[0]
		var r: Array = p[1]
		if p[2]:
			var pt := Vector2(r[1] * PK * sx, (1000.0 - r[0]) * sy) if portrait else Vector2(r[0] * sx, r[1] * sy)
			c.reset_size()
			c.position = (pt - c.get_combined_minimum_size() / 2.0).round()
			continue
		var x: float = r[0]
		var y: float = r[1]
		var w: float = r[2]
		var h: float = r[3]
		if portrait:
			c.position = Vector2(y * PK * sx, (1000.0 - x - w) * sy).round()
			c.size = Vector2(h * PK * sx, w * sy).round()
		else:
			c.position = Vector2(x * sx, y * sy).round()
			c.size = Vector2(w * sx, h * sy).round()
	queue_redraw()


# ---------------- geometry ----------------

static func _path(cmds: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cur := Vector2(cmds[0][0], cmds[0][1])
	pts.append(cur)
	for i in range(1, cmds.size()):
		var c: Array = cmds[i]
		if c[0] == "L":
			cur = Vector2(c[1], c[2])
			pts.append(cur)
		else:
			var ctrl := Vector2(c[1], c[2])
			var end := Vector2(c[3], c[4])
			for k in range(1, 17):
				var t := k / 16.0
				pts.append(cur.lerp(ctrl, t).lerp(ctrl.lerp(end, t), t))
			cur = end
	if pts[pts.size() - 1].is_equal_approx(pts[0]):
		pts.remove_at(pts.size() - 1)
	return pts


## Horizontal span [xmin, xmax] of the hull at height y, or [] outside it.
func _span(y: float) -> Array:
	var xs: Array = []
	var n := _hull.size()
	for i in n:
		var a := _hull[i]
		var b := _hull[(i + 1) % n]
		if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
			xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
	if xs.size() < 2:
		return []
	xs.sort()
	return [xs[0], xs[xs.size() - 1]]


func _transform() -> Transform2D:
	if portrait:
		var sx := size.x / PW
		var sy := size.y / 1000.0
		# landscape x runs up the screen, landscape y runs right (widened by PK)
		return Transform2D(Vector2(0, -sy), Vector2(PK * sx, 0), Vector2(0, 1000.0 * sy))
	return Transform2D(Vector2(size.x / 1000.0, 0), Vector2(0, size.y / 360.0), Vector2.ZERO)


func _draw() -> void:
	if deck.is_empty() or size.x <= 0:
		return
	draw_set_transform_matrix(_transform())
	var id: String = deck["id"]
	draw_colored_polygon(_hull, Color("#8f6f43") if id == "orlop" else Style.DECK)
	# planks, clipped to the hull
	var y := 64.0
	while y < 300.0:
		var sp := _span(y)
		if not sp.is_empty():
			draw_line(Vector2(sp[0], y), Vector2(sp[1], y), Color(Style.PLANK, 0.7), 1.5)
		y += 16.0
	var x := 120.0
	while x < 960.0:
		var k := 0
		y = 64.0
		while y < 300.0:
			var bx := x + (k % 2) * 60.0
			var s0 := _span(y + 0.5)
			var s1 := _span(y + 15.5)
			if not s0.is_empty() and not s1.is_empty() and bx > maxf(s0[0], s1[0]) and bx < minf(s0[1], s1[1]):
				draw_line(Vector2(bx, y), Vector2(bx, y + 16), Color(Style.PLANK, 0.55), 1.2)
			y += 16.0
			k += 1
		x += 130.0
	var closed := _hull.duplicate()
	closed.append(_hull[0])
	draw_polyline(closed, Style.DECK_DARK, 6.0)

	var guns: int = deck.get("guns", 0)
	for i in guns:
		var gx: float
		if id == "upper":
			gx = 110.0 + i * 46.0 if i < guns / 2.0 else 620.0 + (i - guns / 2.0) * 60.0
		else:
			gx = 130.0 + 700.0 * (i / float(maxi(1, guns - 1)))
		for side in [0, 1]:
			var gy := 288.0 if side else 72.0
			draw_rect(Rect2(gx - 7, gy - (16.0 if side else 0.0), 14, 16), Color("#6b4a2a"))
			draw_rect(Rect2(gx - 3, gy if side else gy - 14.0, 6, 14), Color("#2b2b2b"))
	if id == "upper":
		for mx in [215.0, 470.0, 735.0]:
			_circle(Vector2(mx, 180), 15, Color("#5a3d1f"), Color("#2e1f10"), 3)
		# wheel
		draw_arc(Vector2(262, 180), 17, 0, TAU, 24, Color("#4a3018"), 4)
		for a in 8:
			var ang := a * PI / 4.0
			draw_line(Vector2(262, 180), Vector2(262, 180) + Vector2(cos(ang), sin(ang)) * 22.0, Color("#4a3018"), 3)
		_box(Rect2(520, 166, 70, 28))
		_box(Rect2(330, 166, 60, 28))
	if gun_decks.has(id):
		_circle(Vector2(470, 180), 26, Color("#6b4a2a"), Color("#3a2814"), 3)
		_box(Rect2(560, 166, 70, 28))
	if id == "orlop":
		var inner := _orlop_inner.duplicate()
		inner.append(_orlop_inner[0])
		for i in inner.size() - 1:
			draw_dashed_line(inner[i], inner[i + 1], Color("#3a2814"), 3, 10)
		_box(Rect2(140, 140, 120, 80), Color("#5a3d1f"), Color("#2e1f10"))
		_box(Rect2(700, 140, 120, 80), Color("#5a3d1f"), Color("#2e1f10"))
		draw_circle(Vector2(470, 180), 10, Color("#2e1f10"))
	# rudder at the stern
	if id == "upper" or id == "orlop":
		draw_rect(Rect2(34, 168, 22, 24), Color("#4a3018"))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _circle(c: Vector2, r: float, fill: Color, stroke: Color, w: float) -> void:
	draw_circle(c, r, fill)
	draw_arc(c, r, 0, TAU, 24, stroke, w)


func _box(r: Rect2, fill := Color("#7a5a32"), stroke := Color("#4a3018")) -> void:
	draw_rect(r, fill)
	draw_rect(r, stroke, false, 2)
