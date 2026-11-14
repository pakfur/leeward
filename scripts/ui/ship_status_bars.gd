class_name ShipStatusBars
extends Control
## ShipStatusBars - a ship's condition as three same-width bars: hull, rigging and crew.
## Each bar is cut into one segment per section, the segment's width in proportion to the
## section's full box count; the lost part of a segment is drawn dim. The crew bar is double
## height: sailor sections on top (coloured by morale), marines as one unbroken white line
## beneath, and the crew's skill name under that. Reads ShipState only. (View layer.)

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
const BACKING_COLOR := Color(0.06, 0.09, 0.13, 0.82)
const BORDER_COLOR := Color(0.75, 0.82, 0.9, 0.55)
const LOST_ALPHA := 0.22  # how strongly the lost part of a segment shows

const PAD := 6.0
const LABEL_WIDTH := 56.0
const BAR_WIDTH := 150.0
const BAR_HEIGHT := 9.0
const SEGMENT_GAP := 4.0
const ROW_GAP := 5.0
const MARINE_GAP := 1.0
const FONT_SIZE := 12

var ship_state: ShipState = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never takes a click meant for the map
	custom_minimum_size = panel_size()
	size = custom_minimum_size


static func panel_size() -> Vector2:
	var rows := BAR_HEIGHT * 4.0 + MARINE_GAP + ROW_GAP * 3.0 + FONT_SIZE + 2.0
	return Vector2(PAD * 2.0 + LABEL_WIDTH + BAR_WIDTH, PAD * 2.0 + rows)


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


func show_ship(state: ShipState) -> void:
	ship_state = state
	queue_redraw()


func _draw() -> void:
	if ship_state == null:
		return
	var s := ship_state
	var ship: Ship = s.ship
	var no_max: Array[int] = []
	var font := get_theme_default_font()

	var panel := StyleBoxFlat.new()
	panel.bg_color = BACKING_COLOR
	panel.border_color = BORDER_COLOR
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))

	var bar_x := PAD + LABEL_WIDTH
	var y := PAD

	_draw_label(font, "Hull", y)
	_draw_segments(Vector2(bar_x, y), s.hull_current_hp, ship.hull_hp if ship else no_max, HULL_COLOR)
	y += BAR_HEIGHT + ROW_GAP

	_draw_label(font, "Rigging", y)
	_draw_segments(Vector2(bar_x, y), s.rigging_current_hp, ship.rigging_hp if ship else no_max, RIGGING_COLOR)
	y += BAR_HEIGHT + ROW_GAP

	_draw_label(font, "Crew", y)
	_draw_segments(Vector2(bar_x, y), s.crew_count, ship.crew_count if ship else no_max,
		morale_color(s.morale_rating))
	y += BAR_HEIGHT + MARINE_GAP
	var marine_max: int = ship.marine_count if ship else 0
	_draw_bar(Rect2(bar_x, y, BAR_WIDTH, BAR_HEIGHT), fill_fraction(s.marine_count, marine_max), MARINE_COLOR)
	y += BAR_HEIGHT + ROW_GAP

	draw_string(font, Vector2(bar_x, y + FONT_SIZE - 1), skill_name(s.crew_quality),
		HORIZONTAL_ALIGNMENT_LEFT, BAR_WIDTH, FONT_SIZE, TEXT_COLOR)


func _draw_label(font: Font, text: String, y: float) -> void:
	draw_string(font, Vector2(PAD, y + BAR_HEIGHT), text, HORIZONTAL_ALIGNMENT_LEFT,
		LABEL_WIDTH, FONT_SIZE, TEXT_COLOR)


func _draw_segments(origin: Vector2, current: Array, maximum: Array, color: Color) -> void:
	var spans := segment_spans(maximum, BAR_WIDTH, SEGMENT_GAP)
	for i in range(spans.size()):
		var cur: int = current[i] if i < current.size() else 0
		_draw_bar(Rect2(origin.x + spans[i].x, origin.y, spans[i].y, BAR_HEIGHT),
			fill_fraction(cur, maximum[i]), color)


## One bar: the whole length dim, the standing share at full colour from the left.
func _draw_bar(rect: Rect2, fraction: float, color: Color) -> void:
	if rect.size.x <= 0.0:
		return
	draw_rect(rect, Color(color.r, color.g, color.b, LOST_ALPHA))
	if fraction > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * fraction, rect.size.y)), color)
