extends Control
## Plain sea with a pointy-top hex grid and two ship silhouettes, as the HTML's
## sea canvas. inset = true draws the tactical inset (340 x 150 units, scaled).

const Style := preload("res://prototypes/crew_overlay/proto_style.gd")

var inset := false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var s := size
	var scale_f := 1.0
	if inset:
		scale_f = s.x / 340.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_f, scale_f))
		s = Vector2(340, 150)
	draw_rect(Rect2(Vector2.ZERO, s), Style.SEA)
	var r: float = 16.0 if inset else float(Style.px(30))
	var w := sqrt(3.0) * r
	var row := -1
	while row * r * 1.5 < s.y + r:
		var col := -1
		while col * w < s.x + w:
			_hex(Vector2(col * w + (w / 2.0 if row % 2 != 0 else 0.0), row * r * 1.5), r, 1.0 / scale_f)
			col += 1
		row += 1
	if inset:
		_ship(Vector2(110, 92), 0.0, 38, Style.OK)
		_ship(Vector2(230, 168), PI, 38, Style.BAD)
		# wind from SW
		var c := Vector2(36, 196)
		var rot := -PI / 4 - PI / 2 + PI
		var f := func(p: Vector2) -> Vector2: return c + p.rotated(rot)
		draw_line(f.call(Vector2(0, 14)), f.call(Vector2(0, -14)), Style.FG, 3)
		draw_polyline(PackedVector2Array([f.call(Vector2(-6, -6)), f.call(Vector2(0, -14)), f.call(Vector2(6, -6))]), Style.FG, 3)
		var font := Style.bold_font()
		draw_string(font, Vector2(150, 140), "starboard", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Style.FG)
	else:
		var ln := float(Style.px(70))
		_ship(Vector2(s.x * 0.32, s.y * 0.5), 0.0, ln, Style.OK)
		_ship(Vector2(s.x * 0.32 + 4 * w * 0.9, s.y * 0.5 + 3 * r * 1.5 * 0.9), PI, ln, Style.BAD)


func _hex(c: Vector2, r: float, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var a := PI / 6 + i * PI / 3
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polyline(pts, Style.SEA_LINE, width)


func _ship(at: Vector2, ang: float, ln: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var bow := Vector2(ln * 0.55, 0)
	var stern_t := Vector2(-ln * 0.45, -ln * 0.16)
	var stern_b := Vector2(-ln * 0.45, ln * 0.16)
	for k in 13:
		var t := k / 12.0
		pts.append(_q(bow, Vector2(ln * 0.3, -ln * 0.2), stern_t, t))
	for k in 13:
		var t := k / 12.0
		pts.append(_q(stern_b, Vector2(ln * 0.3, ln * 0.2), bow, t))
	var xf := Transform2D(ang, at)
	draw_colored_polygon(xf * pts, Color("#e9e1cc"))
	var ring := PackedVector2Array()
	for k in 41:
		var a := TAU * k / 40.0
		ring.append(Vector2(cos(a) * ln * 0.62, sin(a) * ln * 0.3))
	draw_polyline(xf * ring, col, maxf(2.0, ln * 0.06))


static func _q(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)
