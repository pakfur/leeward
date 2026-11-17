class_name ShipStatusOverlay
extends Node3D
## ShipStatusOverlay - lays a ship's ShipStatusBars flat on the water beside it, at a fixed size
## in the world (about six hexes long). One plate stays by the pinned (clicked) ship for as long
## as it is pinned; another appears by a ship the mouse has rested on for HOVER_DELAY seconds and
## goes when the mouse leaves it. GameController shows it for enemy ships only
## (GameController.shows_status_plate): the planning panel's card covers the player's own.
##
## The plate lies with its long side parallel to the ship. It goes astern if that water is clear,
## otherwise ahead, to port, to starboard; if none is clear it goes astern anyway. Water is
## clear when the plate covers no other ship, no other plate and stays on the map. The text is
## turned end for end whenever needed so it never reads upside down from the camera.
## Reads state only. (View layer.)

enum Side { STERN, BOW, PORT, STARBOARD }
const SIDE_ORDER: Array[int] = [Side.STERN, Side.BOW, Side.PORT, Side.STARBOARD]

const HOVER_DELAY := 0.4
const HEXES_LONG := 6.0
## Clear water (world units, hex size 1) between the ship's centre (midway between its bow and
## stern hexes) and the near edge of the plate: past the bow or stern hex along the heading (end
## face at 1.73) and across the ship (hex corners at 1.0).
const GAP_ALONG := 1.9
const GAP_ACROSS := 1.1
## A ship counts as covered when its centre is within this distance of the plate.
const SHIP_MARGIN := 0.7
const PLATE_Y := 0.1            # with the hex overlays, just above the water
const RENDER_PRIORITY := 1      # above the transparent ocean (priority 0)
const TEXTURE_DETAIL := 4.0     # the bars are drawn at this multiple of their base size

var _camera: Camera3D = null
var _hex_grid: HexGrid = null
var _bounds: Rect2 = Rect2()    # the map in world X/Z; no area: nothing is off the map
var _pinned: Plate = null
var _hover: Plate = null
var _pinned_id: String = ""
var _pinned_state: ShipState = null
var _hover_id: String = ""      # ship under the mouse (shown or still waiting out the delay)
var _hover_state: ShipState = null
var _hover_time: float = 0.0
var _suppressed: bool = false   # true while plotting, moving or showing broadside arcs


## One status display on the water: the bars drawn into a texture, shown on a flat quad.
class Plate extends Node3D:
	var bars: ShipStatusBars
	var quad: MeshInstance3D
	var rect: Dictionary = {}  # where it lies now ({} while hidden): see plate_rect()

	func _init(world_size: Vector2) -> void:
		var viewport := SubViewport.new()
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.size = Vector2i(ShipStatusBars.panel_size(TEXTURE_DETAIL).ceil())
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		bars = ShipStatusBars.new(TEXTURE_DETAIL)
		viewport.add_child(bars)

		var mesh := QuadMesh.new()
		mesh.size = world_size
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = viewport.get_texture()
		mat.no_depth_test = true  # the waves rise through a flat plate otherwise
		mat.render_priority = RENDER_PRIORITY
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad = MeshInstance3D.new()
		quad.mesh = mesh
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)
		visible = false


func setup(camera: Camera3D, hex_grid: HexGrid, map_bounds: Rect2 = Rect2()) -> void:
	_camera = camera
	_hex_grid = hex_grid
	_bounds = map_bounds
	_pinned = Plate.new(plate_size())
	_pinned.name = "PinnedStatus"
	add_child(_pinned)
	_hover = Plate.new(plate_size())
	_hover.name = "HoverStatus"
	add_child(_hover)


## World size of a plate: HEXES_LONG hex widths long, as deep as the bars' own proportions make it.
static func plate_size() -> Vector2:
	var px := ShipStatusBars.panel_size()
	var length := HEXES_LONG * HexGrid.SQRT3
	return Vector2(length, length * px.y / px.x)


## Keep the status by this ship until unpin().
func pin(ship_id: String, state: ShipState) -> void:
	_pinned_id = ship_id
	_pinned_state = state
	if _hover_id == ship_id:
		_hide(_hover)  # one display per ship
	_refresh()


func unpin() -> void:
	_pinned_id = ""
	_pinned_state = null
	_hide(_pinned)


func pinned_ship_id() -> String:
	return _pinned_id


## Report the ship under the mouse every frame ("" and null for none). The status appears once
## the same ship has been reported for HOVER_DELAY seconds and goes as soon as another is.
func set_hover_target(ship_id: String, state: ShipState) -> void:
	if ship_id == _hover_id:
		return
	_hover_id = ship_id
	_hover_state = state
	_hover_time = 0.0
	_hide(_hover)


## Hide every status (true) or allow them again (false). The pin is kept, so the selected ship's
## status returns afterwards; a hover has to wait out its delay again.
func set_suppressed(suppressed: bool) -> void:
	if suppressed == _suppressed:
		return
	_suppressed = suppressed
	_hover_time = 0.0
	if suppressed:
		_hide(_pinned)
		_hide(_hover)
	else:
		_refresh()


func is_suppressed() -> bool:
	return _suppressed


func is_pinned_shown() -> bool:
	return _pinned != null and _pinned.visible


func is_hover_shown() -> bool:
	return _hover != null and _hover.visible


## Whether a ship that has been under the mouse for `elapsed` seconds gets a hover status: only
## after the delay, and never the pinned ship (it already has one). Pure; unit tested.
static func hover_due(hover_id: String, pinned_id: String, elapsed: float) -> bool:
	return hover_id != "" and hover_id != pinned_id and elapsed >= HOVER_DELAY


## The plate for a ship at `ship_pos` (world X/Z) heading along the unit vector `heading`, placed
## on `side`: {"center": Vector2, "axis": Vector2 (unit, along its long side), "half": Vector2
## (half length, half depth)}. Port is to the left of the heading seen from above. Pure.
static func plate_rect(ship_pos: Vector2, heading: Vector2, side: int, size: Vector2) -> Dictionary:
	var h := heading.normalized()
	var port := Vector2(h.y, -h.x)  # east-heading ship: port is north (-Z)
	var center := ship_pos
	match side:
		Side.STERN: center -= h * (GAP_ALONG + size.x * 0.5)
		Side.BOW: center += h * (GAP_ALONG + size.x * 0.5)
		Side.PORT: center += port * (GAP_ACROSS + size.y * 0.5)
		Side.STARBOARD: center -= port * (GAP_ACROSS + size.y * 0.5)
	return {"center": center, "axis": h, "half": size * 0.5}


## Whether `point` lies on the plate or within `margin` of it. Pure.
static func rect_covers(rect: Dictionary, point: Vector2, margin: float) -> bool:
	var axis: Vector2 = rect["axis"]
	var half: Vector2 = rect["half"]
	var d: Vector2 = point - rect["center"]
	return absf(d.dot(axis)) < half.x + margin and absf(d.dot(Vector2(-axis.y, axis.x))) < half.y + margin


static func rect_corners(rect: Dictionary) -> Array[Vector2]:
	var axis: Vector2 = rect["axis"]
	var across := Vector2(-axis.y, axis.x)
	var half: Vector2 = rect["half"]
	var c: Vector2 = rect["center"]
	return [c + axis * half.x + across * half.y, c + axis * half.x - across * half.y,
		c - axis * half.x - across * half.y, c - axis * half.x + across * half.y]


## Whether two plates overlap (separating-axis test on their four edge directions). Pure.
static func rects_overlap(a: Dictionary, b: Dictionary) -> bool:
	var ca := rect_corners(a)
	var cb := rect_corners(b)
	for axis in [a["axis"], Vector2(-a["axis"].y, a["axis"].x), b["axis"], Vector2(-b["axis"].y, b["axis"].x)]:
		var a_lo := INF; var a_hi := -INF; var b_lo := INF; var b_hi := -INF
		for p in ca:
			a_lo = minf(a_lo, p.dot(axis)); a_hi = maxf(a_hi, p.dot(axis))
		for p in cb:
			b_lo = minf(b_lo, p.dot(axis)); b_hi = maxf(b_hi, p.dot(axis))
		if a_hi <= b_lo or b_hi <= a_lo:
			return false
	return true


## Whether the water under `rect` is taken: by one of `other_ships` (world X/Z centres), by one
## of the `other_plates` already lying there, or by the edge of the map (`bounds`; no area: the
## map has no edge). Pure; unit tested.
static func is_obstructed(rect: Dictionary, other_ships: Array, other_plates: Array, bounds: Rect2) -> bool:
	for ship_pos in other_ships:
		if rect_covers(rect, ship_pos, SHIP_MARGIN):
			return true
	for plate in other_plates:
		if rects_overlap(rect, plate):
			return true
	if bounds.has_area():
		for corner in rect_corners(rect):
			if not bounds.has_point(corner):
				return true
	return false


## The side the plate goes on: the first of astern, ahead, port, starboard with clear water;
## astern when none is clear. Pure; unit tested.
static func choose_side(ship_pos: Vector2, heading: Vector2, size: Vector2, other_ships: Array,
		other_plates: Array, bounds: Rect2) -> int:
	for side in SIDE_ORDER:
		if not is_obstructed(plate_rect(ship_pos, heading, side, size), other_ships, other_plates, bounds):
			return side
	return SIDE_ORDER[0]


## Direction the text runs along the plate: along `axis`, or the other way when that would read
## upside down from a camera whose screen-right is `camera_right` (both world X/Z). Pure.
static func reading_direction(axis: Vector2, camera_right: Vector2) -> Vector2:
	return -axis if axis.dot(camera_right) < -0.0001 else axis


func _process(delta: float) -> void:
	if _suppressed:
		return
	if _hover_id != "":
		_hover_time += delta
	_refresh()


## Place (or hide) both plates from the current state. The pinned plate takes its water first;
## the hover plate then keeps clear of it.
func _refresh() -> void:
	if _suppressed or _hex_grid == null:
		return
	# A ship removed from the map (8.G.1f) shows no plate.
	if _pinned_id != "" and _pinned_state and _pinned_state.is_on_map():
		_place(_pinned, _pinned_state, [])
	else:
		_hide(_pinned)
	if hover_due(_hover_id, _pinned_id, _hover_time) and _hover_state and _hover_state.is_on_map():
		_place(_hover, _hover_state, [_pinned.rect] if not _pinned.rect.is_empty() else [])
	else:
		_hide(_hover)


func _hide(plate: Plate) -> void:
	if plate:
		plate.visible = false
		plate.rect = {}


func _place(plate: Plate, state: ShipState, other_plates: Array) -> void:
	var centre := _hex_grid.ship_center_world(state.hex_position, state.facing)
	var here := Vector2(centre.x, centre.z)
	var heading := (_world_xz(state.hex_position) - _world_xz(state.stern_hex())).normalized()
	var others: Array = []
	for other in GameState.get_all_ships():  # read-only  SCV:ALLOW
		if other != state and other.is_on_map():
			for h in other.occupied_hexes():  # bow and stern
				others.append(_world_xz(h))
	var size := plate_size()
	var side := choose_side(here, heading, size, others, other_plates, _bounds)
	plate.rect = plate_rect(here, heading, side, size)

	var camera_right := Vector2.RIGHT
	if _camera:
		var r := _camera.global_transform.basis.x
		camera_right = Vector2(r.x, r.z)
	var u := reading_direction(plate.rect["axis"], camera_right)
	var along := Vector3(u.x, 0, u.y)       # the text runs this way
	var text_up := Vector3(u.y, 0, -u.x)    # and its tops point this way (east-running: north)
	var center: Vector2 = plate.rect["center"]
	plate.quad.transform = Transform3D(Basis(along, text_up, Vector3.UP), Vector3(center.x, PLATE_Y, center.y))
	# Every frame: the state changes under it (damage, morale, speed, the wind).
	var env = GameState.environment  # read-only  SCV:ALLOW
	plate.bars.show_ship(state, ShipIndicatorModel.point_of_sail_label(
		_hex_grid.get_wind_facing(state.facing, env.wind_direction)) if env else "")
	plate.visible = true


func _world_xz(hex: Vector2i) -> Vector2:
	var w := _hex_grid.axial_to_world(hex.x, hex.y)
	return Vector2(w.x, w.z)
