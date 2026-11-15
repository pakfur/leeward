class_name ShipStatusBars
extends Control
## ShipStatusBars - a ship's condition as three same-width bars: hull, rigging and crew.
## Each bar is cut into one segment per section, the segment's width in proportion to the
## section's full box count; the lost part of a segment is drawn solid dark grey. Everything but
## the black backing is fully opaque. Drawn at `detail` times its base size, so it stays sharp
## when shown large on the water. The crew bar is double
## height: sailor sections on top (coloured by morale), marines as one unbroken white line
## beneath, and the crew's skill name under that. A last line gives speed and point of sail. Reads ShipState only. (View layer.)

const SKILL_NAMES := {
	"A": "Prime Seaman", "B": "Able Seaman", "C": "Ordinary Seaman", "D": "Landsman",
	"E": "Waister", "F": "Green Hand", "G": "Lubber",
}

const HULL_COLOR := Color(0.86, 0.22, 0.2)
const RIGGING_COLOR := Color(0.27, 0.52, 0.95)
const MARINE_COLOR := Color(1, 1, 1)
const MORALE_COLORS := {
	2: Color(0.1, 0.62, 0.2),    # green
	3: Color(0.55, 0.88, 0.5),   # light green
	4: Color(0.27, 0.52, 0.95),  # blue
	5: Color(0.95, 0.82, 0.2),   # yellow
	6: Color(0.86, 0.22, 0.2),   # red
}
const TEXT_COLOR := Color(0.91, 0.93, 0.96)
const BACKING_COLOR := Color(0, 0, 0, 0.3)
const LOST_COLOR := Color(0.2, 0.21, 0.23)  # the lost part of a segment: opaque, clearly empty

const PAD := 6.0
const LABEL_WIDTH := 56.0
const BAR_WIDTH := 150.0
const BAR_HEIGHT := 9.0
const SEGMENT_GAP := 4.0
const ROW_GAP := 5.0
const MARINE_GAP := 1.0
const FONT_SIZE := 12

var ship_state: ShipState = null
var point_of_sail: String = ""  # e.g. "Broad Reach"; set by the owner (it depends on the wind)
var detail: float = 1.0  # every measure and the font are multiplied by this


func _init(p_detail: float = 1.0) -> void:
	detail = p_detail
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never takes a click meant for the map
	custom_minimum_size = panel_size(detail)
	size = custom_minimum_size


## Size of the whole display at `p_detail` (1.0: the base size the constants describe).
static func panel_size(p_detail: float = 1.0) -> Vector2:
	var rows := BAR_HEIGHT * 4.0 + MARINE_GAP + ROW_GAP * 4.0 + (FONT_SIZE + 2.0) * 2.0
	return Vector2(PAD * 2.0 + LABEL_WIDTH + BAR_WIDTH, PAD * 2.0 + rows) * p_detail


static func skill_name(quality: String) -> String:
	return SKILL_NAMES.get(quality.to_upper(), quality)


## Colour of the sailor segments for a morale rating (2 best - 6 worst); out-of-range ratings
## take the nearest end.
static func morale_color(rating: int) -> Color:
	return MORALE_COLORS[clampi(rating, 2, 6)]


## Lays `maximums.size()` segments across `width`, separated by `gap`, each as wide as its share
## of the total. Returns one Vector2(x offset, width) per section; a section whose full count is
## 0 gets width 0. Pure; unit tested.
static func segment_spans(maximums: Array, width: float, gap: float) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	var total := 0
	for m in maximums:
		total += maxi(int(m), 0)
	var n := maximums.size()
	if n == 0 or total <= 0:
		return spans
	var usable := maxf(width - gap * (n - 1), 0.0)
	var x := 0.0
	for m in maximums:
		var w := usable * maxi(int(m), 0) / float(total)
		spans.append(Vector2(x, w))
		x += w + gap
	return spans


## Share of a section still standing, 0-1 (0 when the section never had boxes).
static func fill_fraction(current: int, maximum: int) -> float:
	if maximum <= 0:
		return 0.0
	return clampf(float(current) / float(maximum), 0.0, 1.0)


func show_ship(state: ShipState, p_point_of_sail: String = "") -> void:
	ship_state = state
	point_of_sail = p_point_of_sail
	queue_redraw()


## "2 · Broad Reach": hexes moved last turn and the point of sail (speed alone when unknown).
static func motion_text(speed: int, p_point_of_sail: String) -> String:
	return "%d · %s" % [speed, p_point_of_sail] if p_point_of_sail != "" else str(speed)


## The plate's last line, [label, text]: speed and point of sail, or the status of a ship that
## is out of play ("Destroyed" / "Struck").
static func last_line(state: ShipState, p_point_of_sail: String) -> Array[String]:
	if state.is_destroyed():
		return ["Status", "Destroyed"]
	if state.is_struck():
		return ["Status", "Struck"]
	return ["Speed", motion_text(state.speed, p_point_of_sail)]


func _draw() -> void:
	if ship_state == null:
		return
	var s := ship_state
	var ship: Ship = s.ship
	var no_max: Array[int] = []
	var font := get_theme_default_font()
	var k := detail

	draw_rect(Rect2(Vector2.ZERO, size), BACKING_COLOR)

	var bar_x := (PAD + LABEL_WIDTH) * k
	var y := PAD * k

	_draw_label(font, "Hull", y)
	_draw_segments(Vector2(bar_x, y), s.hull_current_hp, ship.hull_hp if ship else no_max, HULL_COLOR)
	y += (BAR_HEIGHT + ROW_GAP) * k

	_draw_label(font, "Rigging", y)
	_draw_segments(Vector2(bar_x, y), s.rigging_current_hp, ship.rigging_hp if ship else no_max, RIGGING_COLOR)
	y += (BAR_HEIGHT + ROW_GAP) * k

	_draw_label(font, "Crew", y)
	_draw_segments(Vector2(bar_x, y), s.crew_count, ship.crew_count if ship else no_max,
		morale_color(s.morale_rating))
	y += (BAR_HEIGHT + MARINE_GAP) * k
	var marine_max: int = ship.marine_count if ship else 0
	_draw_bar(Rect2(bar_x, y, BAR_WIDTH * k, BAR_HEIGHT * k), fill_fraction(s.marine_count, marine_max), MARINE_COLOR)
	y += (BAR_HEIGHT + ROW_GAP) * k

	draw_string(font, Vector2(bar_x, y + (FONT_SIZE - 1) * k), skill_name(s.crew_quality),
		HORIZONTAL_ALIGNMENT_LEFT, BAR_WIDTH * k, roundi(FONT_SIZE * k), TEXT_COLOR)
	y += (FONT_SIZE + 2.0 + ROW_GAP) * k

	var last := last_line(s, point_of_sail)
	_draw_label(font, last[0], y + (FONT_SIZE - 1 - BAR_HEIGHT) * k)
	draw_string(font, Vector2(bar_x, y + (FONT_SIZE - 1) * k), last[1],
		HORIZONTAL_ALIGNMENT_LEFT, BAR_WIDTH * k, roundi(FONT_SIZE * k), TEXT_COLOR)


func _draw_label(font: Font, text: String, y: float) -> void:
	draw_string(font, Vector2(PAD * detail, y + BAR_HEIGHT * detail), text, HORIZONTAL_ALIGNMENT_LEFT,
		LABEL_WIDTH * detail, roundi(FONT_SIZE * detail), TEXT_COLOR)


func _draw_segments(origin: Vector2, current: Array, maximum: Array, color: Color) -> void:
	var spans := segment_spans(maximum, BAR_WIDTH * detail, SEGMENT_GAP * detail)
	for i in range(spans.size()):
		var cur: int = current[i] if i < current.size() else 0
		_draw_bar(Rect2(origin.x + spans[i].x, origin.y, spans[i].y, BAR_HEIGHT * detail),
			fill_fraction(cur, maximum[i]), color)


## One bar: the whole length in the lost colour, the standing share in `color` from the left.
func _draw_bar(rect: Rect2, fraction: float, color: Color) -> void:
	if rect.size.x <= 0.0:
		return
	draw_rect(rect, LOST_COLOR)
	if fraction > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * fraction, rect.size.y)), color)
