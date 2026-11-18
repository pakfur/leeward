class_name ResolutionPicture
extends Control
## The picture of a resolution step: a procedural placeholder per step `kind`, drawn like a small
## framed print: dusk sky, a sea band, the ship in ink silhouette (two ships when the action is
## between ships) and one motif for the action (smoke for gunfire, waves and an arrow for drift, a
## flag for morale, hooks for a grapple, flames for fire, a hawser for a tow, a question mark for a
## prompt), with the kind's name as a caption. Keeps a 16:9 shape at the width it is given. View only.

const ASPECT := 9.0 / 16.0

const SKY_TOP := Color("#18222e")
const SKY_LOW := Color("#4a5866")
const HAZE := Color("#9a8a6c")
const SEA_TOP := Color("#2a4a68")
const SEA_DEEP := Color("#132536")
const SEA_LINE := Color("#5a83a6")
const HULL := Color("#0e151d")
const SAIL := Color("#1c2733")
const SMOKE := Color("#cfd3d6")
const FLASH := Color("#ffd27a")
const FLAME := Color("#e8692a")
const FLAME_CORE := Color("#ffc65c")
const ROPE := Color("#b38c55")
const IRON := Color("#9aa4ae")
const ENSIGN := Color("#a3322a")
const FRAME := Color("#8d7b57")
const CAPTION_BG := Color(0.05, 0.07, 0.1, 0.72)
const CAPTION_FG := Color("#eadfc4")

const CAPTIONS := {
	"gunfire": "Gunfire",
	"marine_fire": "Musketry",
	"morale": "Morale",
	"drift": "Drift",
	"grapple": "Grapple",
	"ungrapple": "Cast off grapples",
	"unfoul": "Unfouling",
	"boarding": "Boarding",
	"fire": "Fire",
	"explosion": "Explosion",
	"tow": "Tow",
	"rally": "Rally",
	"aim": "Aim",
	"crit_fix": "Repairing damage",
	"anchor": "Anchor",
	"prompt_bear_off": "Bear off?",
	"prompt_maintenance": "Orders",
}

## Kinds that show a second ship to starboard of the first.
const TWO_SHIPS := ["gunfire", "marine_fire", "grapple", "ungrapple", "unfoul", "boarding", "tow",
	"prompt_bear_off"]

var kind: String = "":
	set(value):
		kind = value
		queue_redraw()

var _time := 0.0


static func caption_for(step_kind: String) -> String:
	if CAPTIONS.has(step_kind):
		return CAPTIONS[step_kind]
	return step_kind.replace("_", " ").capitalize() if step_kind != "" else "Resolution"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		var h := roundf(size.x * ASPECT)
		if absf(custom_minimum_size.y - h) > 0.5:
			custom_minimum_size = Vector2(0, h)
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree())


func _ready() -> void:
	set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		return
	var horizon := h * 0.58
	_draw_sky(w, horizon)
	_draw_sea(w, h, horizon)
	var two := kind in TWO_SHIPS
	# One unit: a hundredth of the picture's height, smaller when two ships share the picture.
	var u := h / 100.0 * (0.82 if two else 1.0)
	var a := Vector2(w * (0.3 if two else 0.5), horizon + 8.0 * u)
	var b := Vector2(w * 0.74, horizon + 6.0 * u)
	if kind == "tow":
		a = Vector2(w * 0.66, horizon + 8.0 * u)
		b = Vector2(w * 0.24, horizon + 7.0 * u)
	_draw_motif_behind(a, b, u)
	if two:
		_draw_ship(b, u * 0.85, kind == "tow")
	_draw_ship(a, u, kind == "tow")
	_draw_motif_front(a, b, u, w, h, horizon)
	_draw_caption(w, h)
	draw_rect(Rect2(Vector2.ZERO, size), FRAME, false, 2.0)
	draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color(FRAME, 0.35), false, 1.0)


func _draw_sky(w: float, horizon: float) -> void:
	var bands := 12
	for i in bands:
		var t0 := float(i) / bands
		var c := SKY_TOP.lerp(SKY_LOW, t0 * t0)
		draw_rect(Rect2(0, horizon * t0, w, horizon / bands + 1.0), c)
	# A low band of warm haze on the horizon.
	draw_rect(Rect2(0, horizon - 6.0, w, 6.0), Color(HAZE, 0.35))


func _draw_sea(w: float, h: float, horizon: float) -> void:
	var bands := 8
	for i in bands:
		var t0 := float(i) / bands
		draw_rect(Rect2(0, horizon + (h - horizon) * t0, w, (h - horizon) / bands + 1.0),
				SEA_TOP.lerp(SEA_DEEP, t0))
	# Engraved wave strokes, wider and slower nearer the viewer.
	for row in 6:
		var y := horizon + 6.0 + row * (h - horizon) / 6.5
		var amp := 1.0 + row * 0.8
		var step := 16.0 + row * 9.0
		var pts := PackedVector2Array()
		var x := -step
		while x <= w + step:
			pts.append(Vector2(x, y + sin(x / step * PI + _time * (0.6 + row * 0.15) + row) * amp))
			x += step / 4.0
		draw_polyline(pts, Color(SEA_LINE, 0.28 - row * 0.03), 1.2, true)


## A ship in silhouette, bow to the right, waterline on `p.y`; `u` is the size unit. `bare` draws
## her with furled sails (a tow or a dismasted look).
func _draw_ship(p: Vector2, u: float, bare := false) -> void:
	var bob := sin(_time * 1.3 + p.x * 0.01) * 0.8 * u
	var o := p + Vector2(0, bob)
	var hull := PackedVector2Array([
		o + Vector2(-30, -6) * u, o + Vector2(-27, -11) * u, o + Vector2(24, -10) * u,
		o + Vector2(34, -14) * u, o + Vector2(30, -4) * u, o + Vector2(22, 2) * u,
		o + Vector2(-24, 2) * u,
	])
	draw_colored_polygon(hull, HULL)
	# Gun-port line.
	draw_line(o + Vector2(-24, -6) * u, o + Vector2(24, -6) * u, Color(HAZE, 0.45), maxf(1.0, u * 0.6))
	var masts := [-15.0, 2.0, 17.0]
	var heights := [30.0, 38.0, 32.0]
	for i in masts.size():
		var mx: float = masts[i]
		var mh: float = heights[i]
		draw_line(o + Vector2(mx, -10) * u, o + Vector2(mx, -10 - mh) * u, HULL, maxf(1.0, u * 0.9))
		if bare:
			for y in [mh * 0.45, mh * 0.8]:
				draw_line(o + Vector2(mx - 7, -10 - y) * u, o + Vector2(mx + 7, -10 - y) * u, HULL, maxf(1.0, u * 0.7))
			continue
		var top := mh - 2.0
		var sail := PackedVector2Array([
			o + Vector2(mx - 9, -14) * u, o + Vector2(mx + 9, -14) * u,
			o + Vector2(mx + 7.5, -10 - top) * u, o + Vector2(mx - 7.5, -10 - top) * u,
		])
		draw_colored_polygon(sail, SAIL)
		draw_polyline(PackedVector2Array([sail[0], sail[1], sail[2], sail[3], sail[0]]), HULL, 1.0, true)
	# Bowsprit and jib.
	draw_line(o + Vector2(30, -12) * u, o + Vector2(44, -18) * u, HULL, maxf(1.0, u * 0.7))
	if not bare:
		draw_colored_polygon(PackedVector2Array([
			o + Vector2(42, -17) * u, o + Vector2(19, -46) * u, o + Vector2(20, -14) * u]), SAIL)


func _draw_motif_behind(a: Vector2, b: Vector2, u: float) -> void:
	match kind:
		"gunfire":
			# Powder smoke rolling off her starboard side towards the enemy.
			for i in 7:
				var t := float(i) / 6.0
				var drift := fmod(_time * 6.0 + i * 3.0, 10.0)
				var c := a.lerp(b, 0.12 + t * 0.32) + Vector2(drift, -8.0 - t * 6.0 - drift * 0.4) * u
				draw_circle(c, (6.0 + t * 5.0) * u, Color(SMOKE, 0.55 - t * 0.3), true, -1.0, true)
		"fire", "explosion":
			for i in 5:
				var rise := fmod(_time * 10.0 + i * 9.0, 40.0)
				draw_circle(a + Vector2(-6 + i * 3 + rise * 0.3, -30 - rise) * u, (5.0 + rise * 0.25) * u,
						Color(0.15, 0.15, 0.16, 0.55 - rise / 90.0), true, -1.0, true)


func _draw_motif_front(a: Vector2, b: Vector2, u: float, w: float, h: float, horizon: float) -> void:
	match kind:
		"gunfire":
			for i in 4:
				var port := a + Vector2(-18 + i * 12, -6) * u
				var flick := 0.7 + 0.3 * sin(_time * 9.0 + i * 1.7)
				draw_colored_polygon(PackedVector2Array([
					port + Vector2(0, -2.2) * u, port + Vector2(9.0 * flick, 0) * u, port + Vector2(0, 2.2) * u]),
					FLASH)
			_splash(b + Vector2(-26, 3) * u, u)
		"marine_fire":
			for i in 6:
				var c := a.lerp(b, 0.2 + i * 0.1) + Vector2(0, -14 - (i % 2) * 3) * u
				draw_circle(c, 2.8 * u, Color(SMOKE, 0.6), true, -1.0, true)
				draw_circle(c + Vector2(-2, 0) * u, 1.0 * u, FLASH, true, -1.0, true)
		"morale", "rally":
			# A large ensign at the mizzen peak: lowered for morale, hoisted high for a rally.
			# The ensign at the mainmast truck: close up for a rally, at half-mast for morale.
			var high := kind == "rally"
			var truck := a + Vector2(2, -52) * u
			draw_line(a + Vector2(2, -46) * u, truck, HULL, maxf(1.0, u * 0.9))
			var hoist := truck + Vector2(0, (0.0 if high else 14.0)) * u
			var wave := sin(_time * 3.0)
			var flag := PackedVector2Array([
				hoist, hoist + Vector2(-16, 1 + wave) * u, hoist + Vector2(-17, 9 + wave) * u, hoist + Vector2(0, 9) * u])
			draw_colored_polygon(flag, ENSIGN if high else CAPTION_FG)
			draw_polyline(PackedVector2Array([flag[0], flag[1], flag[2], flag[3]]), HULL, 1.0, true)
		"drift":
			var y := horizon + (h - horizon) * 0.72
			var arrow_from := Vector2(w * 0.3, y)
			var arrow_to := Vector2(w * 0.7 + sin(_time) * 4.0, y)
			draw_line(arrow_from, arrow_to, CAPTION_FG, maxf(2.0, u * 1.2), true)
			draw_colored_polygon(PackedVector2Array([arrow_to + Vector2(4, 0) * u,
				arrow_to + Vector2(-4, -3.5) * u, arrow_to + Vector2(-4, 3.5) * u]), CAPTION_FG)
			for i in 3:
				var c := Vector2(w * (0.2 + i * 0.25), y + 9.0 * u)
				draw_arc(c, 5.0 * u, PI * 1.1, PI * 1.9, 12, Color(SEA_LINE, 0.9), maxf(1.5, u * 0.8), true)
		"grapple", "ungrapple", "unfoul":
			for i in 3:
				var from := a + Vector2(10 + i * 7, -11) * u
				var to := b + Vector2(-22 + i * 6, -9) * u
				var sag := Vector2(0, 6.0 * u if kind != "ungrapple" else 12.0 * u)
				var mid := from.lerp(to, 0.5) + sag
				if kind == "ungrapple" and i == 1:
					to = mid + Vector2(4, 6) * u  # one line cut and hanging
				draw_polyline(PackedVector2Array([from, mid, to]), ROPE, maxf(1.0, u * 0.6), true)
				_hook(to, u)
		"boarding":
			var c := a.lerp(b, 0.5) + Vector2(0, -24) * u
			for s in [-1.0, 1.0]:
				var dir := Vector2(s * 0.7, -1.0).normalized()
				draw_line(c - dir * 12.0 * u, c + dir * 12.0 * u, IRON, maxf(2.0, u * 1.2), true)
				draw_line(c - dir * 8.0 * u + dir.orthogonal() * 3.0 * u,
						c - dir * 8.0 * u - dir.orthogonal() * 3.0 * u, ROPE, maxf(2.0, u), true)
		"fire":
			for i in 5:
				_flame(a + Vector2(-18 + i * 9, -9) * u, u * (0.9 + 0.3 * sin(_time * 7.0 + i)))
		"explosion":
			var c := a + Vector2(0, -16) * u
			var pulse := 1.0 + 0.08 * sin(_time * 12.0)
			var star := PackedVector2Array()
			for i in 16:
				var r := (24.0 if i % 2 == 0 else 11.0) * u * pulse
				star.append(c + Vector2.from_angle(i * TAU / 16.0) * r)
			draw_colored_polygon(star, FLAME)
			draw_circle(c, 8.0 * u * pulse, FLAME_CORE, true, -1.0, true)
		"tow":
			var from := a + Vector2(-28, -5) * u
			var to := b + Vector2(38, -14) * u
			var mid := from.lerp(to, 0.5) + Vector2(0, 6.0 + sin(_time * 1.6) * 1.5) * u
			draw_polyline(PackedVector2Array([from, mid, to]), ROPE, maxf(1.5, u * 0.9), true)
		"aim":
			var c := b + Vector2(-4, -16) * u
			draw_arc(c, 10.0 * u, 0.0, TAU, 32, CAPTION_FG, maxf(1.5, u * 0.7), true)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				draw_line(c + d * 5.0 * u, c + d * 14.0 * u, CAPTION_FG, maxf(1.5, u * 0.7), true)
		"crit_fix":
			var c := a + Vector2(2, -34) * u
			draw_arc(c, 7.0 * u, 0.0, TAU, 24, ROPE, maxf(2.0, u * 1.2), true)
			draw_arc(c, 4.0 * u, 0.0, TAU, 20, ROPE, maxf(2.0, u * 1.0), true)
		"anchor":
			var top := a + Vector2(30, -2) * u
			var bottom := top + Vector2(0, 24) * u
			draw_line(a + Vector2(30, -12) * u, top, ROPE, maxf(1.0, u * 0.6), true)
			draw_line(top, bottom, IRON, maxf(2.0, u * 1.1), true)
			draw_line(top + Vector2(-5, 3) * u, top + Vector2(5, 3) * u, IRON, maxf(2.0, u), true)
			draw_arc(bottom + Vector2(0, -6) * u, 6.0 * u, 0.2, PI - 0.2, 16, IRON, maxf(2.0, u * 1.1), true)
		"prompt_bear_off", "prompt_maintenance":
			var font := get_theme_font("font", &"HeaderLabel")
			var fs := int(h * 0.46)
			var pulse := 0.8 + 0.2 * sin(_time * 2.5)
			var size_q := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var pos := Vector2((w - size_q.x) * 0.5, horizon * 0.82)
			draw_circle(Vector2(w * 0.5, pos.y - fs * 0.3), fs * 0.42, Color(SKY_TOP, 0.75), true, -1.0, true)
			draw_string(font, pos + Vector2(2, 3), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
			draw_string(font, pos, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(CAPTION_FG, pulse))


func _splash(p: Vector2, u: float) -> void:
	for i in 3:
		var hgt := (6.0 + i * 3.0) * (0.8 + 0.2 * sin(_time * 5.0 + i))
		draw_line(p + Vector2(i * 3 - 3, 0) * u, p + Vector2(i * 3 - 3 + (i - 1) * 1.5, -hgt) * u,
				Color(SMOKE, 0.8), maxf(1.5, u * 0.9), true)


func _hook(p: Vector2, u: float) -> void:
	draw_arc(p + Vector2(0, 2.5) * u, 2.5 * u, 0.0, PI, 10, IRON, maxf(1.5, u * 0.7), true)


func _flame(p: Vector2, u: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-4, 0) * u, p + Vector2(-2, -9) * u, p + Vector2(0, -16) * u,
		p + Vector2(2, -9) * u, p + Vector2(4, 0) * u]), FLAME)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-2, 0) * u, p + Vector2(0, -8) * u, p + Vector2(2, 0) * u]), FLAME_CORE)


func _draw_caption(_w: float, h: float) -> void:
	var font := get_theme_font("font", &"HeaderLabel")
	var fs := clampi(int(h * 0.1), 14, 22)
	var text := caption_for(kind)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(8, h - fs - 16, tw + 20, fs + 10)
	draw_rect(box, CAPTION_BG)
	draw_line(box.position + Vector2(0, box.size.y), box.end, Color(FRAME, 0.8), 1.0)
	draw_string(font, Vector2(box.position.x + 10, box.position.y + 5 + font.get_ascent(fs)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CAPTION_FG)
