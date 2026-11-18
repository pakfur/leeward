class_name ResolutionDice
extends Control
## The dice of a resolution step, drawn in `_draw()`: bone d6s with ink pips and red horn d10s
## (faces 0-9) that tumble for about `TUMBLE_SECONDS`, slowing as they go, then land with a small
## thud on the values the server rolled. View only: the tumbling faces are cosmetic and use their own
## RandomNumberGenerator, never the game's dice.
##
## A dice entry is {"sides": 6|10, "values": Array[int]} (one die per value). An entry with
## "count": n and a single value is a roll the log keeps only as a total (2d6, 2d10): n dice tumble,
## then settle into one total badge ("2d6 = 7"). Its faces are never shown, since the panel must not
## show a split of the total that was not rolled.

signal settled()

const TUMBLE_SECONDS := 0.8
const LAND_SECONDS := 0.22
const DIE := 54.0
const GAP := 14.0
const BADGE_W := DIE * 2.0 + 8.0
const HEIGHT := 86.0

const BONE := Color("#eadfc4")
const BONE_SHADE := Color("#c9b98f")
const BONE_EDGE := Color("#8d7b57")
const INK := Color("#2a2116")
const HORN := Color("#8e2a24")
const HORN_SHADE := Color("#5e1a17")
const HORN_EDGE := Color("#3b0f0d")
const BRASS := Color("#d6b25e")
const SHADOW := Color(0, 0, 0, 0.35)

## Pip layouts on a unit square (-1..1).
const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-0.5, -0.5), Vector2(0.5, 0.5)],
	3: [Vector2(-0.5, -0.5), Vector2(0, 0), Vector2(0.5, 0.5)],
	4: [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)],
	5: [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0, 0), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)],
	6: [Vector2(-0.5, -0.55), Vector2(0.5, -0.55), Vector2(-0.5, 0), Vector2(0.5, 0),
		Vector2(-0.5, 0.55), Vector2(0.5, 0.55)],
}

## One drawn group per entry: {"sides", "values" (the landing faces), "total" (-1 = faces shown),
## "count" (dice tumbling), "faces" (what is drawn while tumbling), "spin" (per-die phase)}.
var _groups: Array = []
var _rolling := false
var _elapsed := 0.0
var _land := 1.0  ## 0..1 through the landing thud; 1 = at rest
var _next_flip := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_rng.randomize()


## Shows `dice` and tumbles them onto their values; `instant` lands them at once. `settled` is
## emitted when they are at rest (at once, synchronously, for an instant or empty roll).
func roll(dice: Array, instant: bool) -> void:
	_groups.clear()
	for entry in dice:
		var sides := int(entry.get("sides", 6))
		var values: Array = entry.get("values", [])
		var count := int(entry.get("count", 1))
		var g := {"sides": sides, "values": values.duplicate(), "total": -1, "count": values.size()}
		if count > 1 and values.size() == 1:
			g["total"] = int(values[0])
			g["count"] = count
		g["faces"] = []
		g["spin"] = []
		for i in g["count"]:
			g["faces"].append(_random_face(sides))
			g["spin"].append(_rng.randf_range(0.0, TAU))
		_groups.append(g)
	queue_redraw()
	if instant or _groups.is_empty():
		_finish(false)
		return
	_rolling = true
	_elapsed = 0.0
	_next_flip = 0.0
	_land = 1.0
	set_process(true)


func is_rolling() -> bool:
	return _rolling


## What the dice show at rest, one string per die or badge: "4", "0", "2d6 = 7".
func shown_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for g in _groups:
		if int(g["total"]) >= 0:
			out.append("%dd%d = %d" % [int(g["count"]), int(g["sides"]), int(g["total"])])
		else:
			for v in g["values"]:
				out.append(str(int(v)))
	return out


func _process(delta: float) -> void:
	if _rolling:
		_elapsed += delta
		if _elapsed >= _next_flip:
			for g in _groups:
				for i in g["faces"].size():
					g["faces"][i] = _random_face(int(g["sides"]))
			# Faces change quickly at first, then slow as the dice lose speed.
			var t := _elapsed / TUMBLE_SECONDS
			_next_flip = _elapsed + lerpf(0.045, 0.16, t * t)
		if _elapsed >= TUMBLE_SECONDS:
			_finish(true)
	elif _land < 1.0:
		_land = minf(1.0, _land + delta / LAND_SECONDS)
		if _land >= 1.0:
			set_process(false)
	queue_redraw()


func _finish(animated: bool) -> void:
	_rolling = false
	_land = 0.0 if animated else 1.0
	set_process(animated)
	queue_redraw()
	settled.emit()


func _random_face(sides: int) -> int:
	return _rng.randi_range(1, 6) if sides == 6 else _rng.randi_range(0, 9)


# --- drawing -------------------------------------------------------------------------------------

func _group_width(g: Dictionary) -> float:
	if int(g["total"]) >= 0 and not _rolling:
		return BADGE_W
	var n: int = g["count"]
	return n * DIE + maxi(n - 1, 0) * 8.0


func _draw() -> void:
	if _groups.is_empty():
		return
	var total_w := 0.0
	for g in _groups:
		total_w += _group_width(g)
	total_w += GAP * (_groups.size() - 1)
	var x := (size.x - total_w) * 0.5
	var cy := size.y * 0.5
	var t := clampf(_elapsed / TUMBLE_SECONDS, 0.0, 1.0)
	for g in _groups:
		var w := _group_width(g)
		if int(g["total"]) >= 0 and not _rolling:
			_draw_badge(Rect2(x, cy - DIE * 0.5, w, DIE), g)
		else:
			for i in g["count"]:
				var c := Vector2(x + DIE * 0.5 + i * (DIE + 8.0), cy)
				var face: int
				if _rolling:
					face = g["faces"][i]
				else:
					face = int(g["values"][i])
				_draw_die(c, int(g["sides"]), face, t, float(g["spin"][i]))
		x += w + GAP


## A die centred on `c`. While rolling it hops and rocks, the motion dying away with `t`; at rest
## it gives a short thud (squash, then a brass ring that fades).
func _draw_die(c: Vector2, sides: int, face: int, t: float, spin: float) -> void:
	var angle := 0.0
	var hop := 0.0
	var scale_v := Vector2.ONE
	if _rolling:
		var decay := (1.0 - t) * (1.0 - t)
		angle = sin(_elapsed * 22.0 + spin) * 0.55 * decay
		hop = -absf(sin(_elapsed * 14.0 + spin)) * 16.0 * decay
	elif _land < 1.0:
		var k := sin(_land * PI) * (1.0 - _land)
		scale_v = Vector2(1.0 + 0.16 * k, 1.0 - 0.12 * k)
	# The shadow stays on the table and shrinks as the die leaves it.
	var shadow_w := DIE * 0.46 * (1.0 + hop / 40.0)
	draw_set_transform(c + Vector2(0, DIE * 0.5 + 4.0), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, shadow_w, SHADOW)
	draw_set_transform(c + Vector2(0, hop), angle, scale_v)
	if sides == 6:
		_draw_d6(face)
	else:
		_draw_d10(face)
	draw_set_transform(Vector2.ZERO)
	if not _rolling and _land < 1.0:
		var ring := Color(BRASS, 0.75 * (1.0 - _land))
		draw_arc(c, DIE * (0.62 + 0.3 * _land), 0.0, TAU, 40, ring, 2.0, true)


func _draw_d6(face: int) -> void:
	var h := DIE * 0.5
	var body := StyleBoxFlat.new()
	body.bg_color = BONE
	body.set_corner_radius_all(int(DIE * 0.2))
	body.border_color = BONE_EDGE
	body.set_border_width_all(2)
	body.shadow_color = BONE_SHADE
	body.shadow_offset = Vector2(0, 3)
	body.anti_aliasing = true
	draw_style_box(body, Rect2(-h, -h, DIE, DIE))
	# A worn highlight along the upper edge.
	draw_line(Vector2(-h * 0.55, -h * 0.78), Vector2(h * 0.55, -h * 0.78), Color(1, 1, 1, 0.35), 2.0, true)
	for p in PIPS.get(clampi(face, 1, 6), []):
		draw_circle(p * h * 0.95, DIE * 0.085, INK, true, -1.0, true)


func _draw_d10(face: int) -> void:
	var h := DIE * 0.56
	# The kite of a pentagonal trapezohedron seen face on, with its two lower facets.
	var top := Vector2(0, -h)
	var left := Vector2(-h * 0.86, -h * 0.12)
	var right := Vector2(h * 0.86, -h * 0.12)
	var bottom := Vector2(0, h * 0.95)
	var waist_l := Vector2(-h * 0.52, h * 0.42)
	var waist_r := Vector2(h * 0.52, h * 0.42)
	var mid := Vector2(0, h * 0.52)
	draw_colored_polygon(PackedVector2Array([left, waist_l, bottom, mid]), HORN_SHADE)
	draw_colored_polygon(PackedVector2Array([right, waist_r, bottom, mid]), HORN_SHADE.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([top, right, mid, left]), HORN)
	var outline := PackedVector2Array([top, right, waist_r, bottom, waist_l, left, top])
	draw_polyline(outline, HORN_EDGE, 2.0, true)
	draw_polyline(PackedVector2Array([left, mid, right]), HORN_EDGE, 1.5, true)
	draw_line(mid, bottom, HORN_EDGE, 1.5, true)
	draw_line(top + Vector2(-h * 0.1, h * 0.14), left + Vector2(h * 0.16, 0), Color(1, 1, 1, 0.22), 2.0, true)
	var font := get_theme_font("font", &"CounterBoldLabel")
	var fs := int(DIE * 0.46)
	var text := str(face)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2(-tw.x * 0.5, h * 0.05 + font.get_ascent(fs) * 0.32)
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BONE)
	if face == 6 or face == 9:
		# The underline that tells a 6 from a 9.
		draw_line(base + Vector2(tw.x * 0.15, 4), base + Vector2(tw.x * 0.85, 4), BONE, 2.0)


## The total of a roll the log keeps only as a sum: a bone tablet "2d6" over the total.
func _draw_badge(r: Rect2, g: Dictionary) -> void:
	var k := 0.0 if _land >= 1.0 else sin(_land * PI) * (1.0 - _land)
	var grown := r.grow(6.0 * k)
	var body := StyleBoxFlat.new()
	body.bg_color = BONE if int(g["sides"]) == 6 else HORN
	body.border_color = BRASS
	body.set_border_width_all(2)
	body.set_corner_radius_all(int(DIE * 0.22))
	body.shadow_color = SHADOW
	body.shadow_size = 4
	body.shadow_offset = Vector2(0, 3)
	body.anti_aliasing = true
	draw_style_box(body, grown)
	var ink := INK if int(g["sides"]) == 6 else BONE
	var small := get_theme_font("font", &"CounterLabel")
	var big := get_theme_font("font", &"CounterBoldLabel")
	var cap := "%dd%d =" % [int(g["count"]), int(g["sides"])]
	var cap_fs := 20
	var big_fs := int(DIE * 0.62)
	var total := str(int(g["total"]))
	var cw := small.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
	var bw := big.get_string_size(total, HORIZONTAL_ALIGNMENT_LEFT, -1, big_fs).x
	var x := grown.position.x + (grown.size.x - cw - 8.0 - bw) * 0.5
	var base_y := grown.get_center().y + big.get_ascent(big_fs) * 0.36
	draw_string(small, Vector2(x, base_y), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs, Color(ink, 0.75))
	draw_string(big, Vector2(x + cw + 8.0, base_y), total, HORIZONTAL_ALIGNMENT_LEFT, -1, big_fs, ink)
	if _land < 1.0:
		draw_style_box(_ring_box(1.0 - _land), grown.grow(4.0 + 10.0 * _land))


func _ring_box(alpha: float) -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color(BRASS, 0.7 * alpha)
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(int(DIE * 0.3))
	ring.anti_aliasing = true
	return ring
