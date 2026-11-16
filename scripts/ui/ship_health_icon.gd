class_name ShipHealthIcon
extends Control
## The health icon at the left of a ship card (planning panel rework C2): two bars, hull and
## rigging, filled to the share of boxes left (amber under two thirds, red under one third),
## inside a frame in the owner green, red when a status locks the ship (fouled, struck, …) and
## orange when she is afire. View only: reads the ShipState given to `show_ship`.

const Style = preload("res://scripts/ui/crew_overlay/crew_style.gd")

const OWN := Color("#3ddc6e")
const TRACK := Color("#2a3440")
const BACK := Color("#11181f")
const RIGGING := Color("#e4dbc4")

var hull_share := 1.0
var rigging_share := 1.0
var frame_color := OWN


func _init() -> void:
	custom_minimum_size = Vector2(32, 32)
	mouse_filter = MOUSE_FILTER_PASS


func show_ship(ship: ShipState) -> void:
	hull_share = _share(ship.hull_current_hp, ship.ship.hull_hp if ship.ship else [])
	rigging_share = _share(ship.rigging_current_hp, ship.ship.rigging_hp if ship.ship else [])
	if PlanningSailUi.status_badge(ship) != "":
		frame_color = Style.BAD
	elif ship.is_burning() and not ship.is_destroyed():
		frame_color = Style.FIRE
	else:
		frame_color = OWN
	tooltip_text = "Hull %d%% · Rigging %d%%" % [roundi(hull_share * 100.0), roundi(rigging_share * 100.0)]
	queue_redraw()


static func _share(now: Array, full: Array) -> float:
	var left := 0
	var all := 0
	for v in now:
		left += int(v)
	for v in full:
		all += int(v)
	return clampf(float(left) / float(all), 0.0, 1.0) if all > 0 else 1.0


static func tone(share: float, base: Color) -> Color:
	if share > 2.0 / 3.0:
		return base
	if share > 1.0 / 3.0:
		return Style.WARN
	return Style.BAD


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BACK)
	draw_rect(r.grow(-1.0), frame_color, false, 2.0)
	var pad := 5.0
	var gap := 3.0
	var w := (size.x - pad * 2.0 - gap) / 2.0
	var h := size.y - pad * 2.0
	for i in 2:
		var share := hull_share if i == 0 else rigging_share
		var base := Style.DECK if i == 0 else RIGGING
		var x := pad + i * (w + gap)
		draw_rect(Rect2(x, pad, w, h), TRACK)
		var fill := h * share
		draw_rect(Rect2(x, pad + h - fill, w, fill), tone(share, base))
