class_name CrewTacticalInset
extends Control
## The crew overlay's tactical picture (crew-tasks spec §4.7): a small sea with the hex grid, the
## selected ship in the centre, every ship within 8 hexes in owner colours (green own, red enemy,
## grey out of play, as the minimap), and the wind arrow. North up, as the map. Ships are drawn
## where they are now. Drawing style from prototypes/crew_overlay/sea_backdrop.gd. View only.

const RADIUS_HEXES := 8
const VIEW_W := 340.0
const VIEW_H := 150.0

var _ships: Array = []  # [{center: Vector2 (world x,z), heading: float, color: Color, own: bool}]
var _focus := Vector2.ZERO
var _wind_dir := -1
var _grid := HexGrid.new()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)


## Reads the ships' positions (read-only) around `focus_ship`.
func show_ships(focus_ship: ShipState, ships: Array, wind_direction: int) -> void:
	_ships.clear()
	_wind_dir = wind_direction
	if focus_ship == null:
		queue_redraw()
		return
	var c := _grid.ship_center_world(focus_ship.hex_position, focus_ship.facing)
	_focus = Vector2(c.x, c.z)
	for s: ShipState in ships:
		var d := _grid.hex_distance(s.hex_position.x, s.hex_position.y, focus_ship.hex_position.x, focus_ship.hex_position.y)
		if d > RADIUS_HEXES:
			continue
		var w := _grid.ship_center_world(s.hex_position, s.facing)
		var bow := _grid.axial_to_world(s.hex_position.x, s.hex_position.y)
		var st := s.stern_hex()
		var stern := _grid.axial_to_world(st.x, st.y)
		var color := CrewStyle.OK if s.player_id == focus_ship.player_id else CrewStyle.BAD
		if s.is_out_of_play():
			color = CrewStyle.MUTED
		_ships.append({"center": Vector2(w.x, w.z), "heading": Vector2(bow.x - stern.x, bow.z - stern.z).angle(),
			"color": color, "focus": s.ship_id == focus_ship.ship_id})
	queue_redraw()


func _draw() -> void:
	var k := size.x / VIEW_W
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var s := Vector2(VIEW_W, VIEW_H)
	draw_rect(Rect2(Vector2.ZERO, s), CrewStyle.SEA)
	# one hex = R units across the inset: 8 hexes each way fit the height
	var px_per_world := VIEW_H / (RADIUS_HEXES * 1.5 * 0.9)
	var mid := s / 2.0
	# hex grid aligned with the map's hexes (pointy top, unit size)
	var center_hex := _grid.world_to_axial(Vector3(_focus.x, 0, _focus.y))
	for hx in _grid.hex_range(center_hex.x, center_hex.y, RADIUS_HEXES + 3):
		var w := _grid.axial_to_world(hx.x, hx.y)
		var p := mid + (Vector2(w.x, w.z) - _focus) * px_per_world
		if p.x < -20 or p.x > s.x + 20 or p.y < -20 or p.y > s.y + 20:
			continue
		_hex(p, px_per_world, 1.0 / k)
	for sh in _ships:
		var p: Vector2 = mid + (sh["center"] - _focus) * px_per_world
		_ship(p, sh["heading"], px_per_world * 2.0, sh["color"], sh["focus"])
	if _wind_dir >= 0:
		# arrow pointing where the wind blows (from wind_direction towards the opposite side)
		var from_vec := _grid.axial_to_world(0, 0).direction_to(_grid.axial_to_world(
			_grid.get_neighbor(0, 0, _wind_dir).x, _grid.get_neighbor(0, 0, _wind_dir).y))
		var blow := -Vector2(from_vec.x, from_vec.z).normalized()
		var c := Vector2(24, VIEW_H - 24)
		var tip := c + blow * 14.0
		draw_line(c - blow * 14.0, tip, CrewStyle.FG, 3)
		var side := blow.orthogonal() * 6.0
		draw_polyline(PackedVector2Array([tip - blow * 8.0 + side, tip, tip - blow * 8.0 - side]), CrewStyle.FG, 3)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _hex(c: Vector2, r: float, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var a := PI / 6 + i * PI / 3
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polyline(pts, CrewStyle.SEA_LINE, width)


func _ship(at: Vector2, ang: float, ln: float, col: Color, focus: bool) -> void:
	var pts := PackedVector2Array()
	var bow := Vector2(ln * 0.55, 0)
	var stern_t := Vector2(-ln * 0.45, -ln * 0.16)
	var stern_b := Vector2(-ln * 0.45, ln * 0.16)
	for k in 13:
		pts.append(_q(bow, Vector2(ln * 0.3, -ln * 0.2), stern_t, k / 12.0))
	for k in 13:
		pts.append(_q(stern_b, Vector2(ln * 0.3, ln * 0.2), bow, k / 12.0))
	var xf := Transform2D(ang, at)
	draw_colored_polygon(xf * pts, Color("#e9e1cc"))
	var ring := PackedVector2Array()
	for k in 41:
		var a := TAU * k / 40.0
		ring.append(Vector2(cos(a) * ln * 0.62, sin(a) * ln * 0.3))
	draw_polyline(xf * ring, col, maxf(2.0, ln * (0.09 if focus else 0.06)))


static func _q(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)
