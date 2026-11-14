class_name ShipStatusOverlay
extends Control
## ShipStatusOverlay - floats ShipStatusBars over ships on the map. One stays over the pinned
## (selected) ship for as long as it is pinned; another pops up over a ship the mouse has rested
## on for HOVER_DELAY seconds and goes when the mouse leaves it. Follows the ship's view node, so
## it tracks the ship during movement playback. Reads state only. (View layer.)

const HOVER_DELAY := 0.4
## Gap (screen px) between the bottom of the bars and the ship's projected centre.
const LIFT_PX := 46.0
const MAP_EDGE_GAP_PX := 6.0

## Returns the screen rect of the map area; the bars are kept inside it. Unset: the whole overlay.
var map_rect_provider: Callable = Callable()

var _camera: Camera3D = null
var _pinned_bars: ShipStatusBars = null
var _hover_bars: ShipStatusBars = null
var _pinned_anchor: Node3D = null
var _hover_anchor: Node3D = null
var _pinned_id: String = ""
var _hover_id: String = ""      # ship under the mouse (shown or still waiting out the delay)
var _hover_state: ShipState = null
var _hover_time: float = 0.0
var _suppressed: bool = false   # true while a course is being plotted: nothing covers the hexes


func setup(camera: Camera3D) -> void:
	_camera = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_pinned_bars = _make_bars("PinnedStatus")
	_hover_bars = _make_bars("HoverStatus")


func _make_bars(node_name: String) -> ShipStatusBars:
	var bars := ShipStatusBars.new()
	bars.name = node_name
	bars.visible = false
	add_child(bars)
	return bars


## Keep the status up over `anchor` (the ship's view node) until unpin().
func pin(ship_id: String, state: ShipState, anchor: Node3D) -> void:
	_pinned_id = ship_id
	_pinned_anchor = anchor
	_pinned_bars.show_ship(state)
	if _hover_id == ship_id:
		_hover_bars.visible = false  # one display per ship
	if not _suppressed:
		_place(_pinned_bars, _pinned_anchor)


func unpin() -> void:
	_pinned_id = ""
	_pinned_anchor = null
	_pinned_bars.visible = false


func pinned_ship_id() -> String:
	return _pinned_id


## Report the ship under the mouse every frame ("" and nulls for none). The status appears once
## the same ship has been reported for HOVER_DELAY seconds and goes as soon as another is.
func set_hover_target(ship_id: String, state: ShipState, anchor: Node3D) -> void:
	if ship_id == _hover_id:
		return
	_hover_id = ship_id
	_hover_state = state
	_hover_anchor = anchor
	_hover_time = 0.0
	_hover_bars.visible = false


## Hide every status (true) or allow them again (false). The pin is kept, so the selected ship's
## status returns when plotting ends; a hover has to wait out its delay again.
func set_suppressed(suppressed: bool) -> void:
	if suppressed == _suppressed:
		return
	_suppressed = suppressed
	_hover_time = 0.0
	if suppressed:
		_pinned_bars.visible = false
		_hover_bars.visible = false
	elif _pinned_id != "":
		_place(_pinned_bars, _pinned_anchor)


func is_pinned_shown() -> bool:
	return _pinned_bars != null and _pinned_bars.visible


func is_hover_shown() -> bool:
	return _hover_bars != null and _hover_bars.visible


## Whether a ship that has been under the mouse for `elapsed` seconds gets a hover status: only
## after the delay, and never the pinned ship (it already has one). Pure; unit tested.
static func hover_due(hover_id: String, pinned_id: String, elapsed: float) -> bool:
	return hover_id != "" and hover_id != pinned_id and elapsed >= HOVER_DELAY


## Top-left corner for bars of `bars_size` centred above `ship_px`, kept inside `rect`.
## Pure; unit tested.
static func bars_position(ship_px: Vector2, bars_size: Vector2, rect: Rect2) -> Vector2:
	var pos := Vector2(ship_px.x - bars_size.x * 0.5, ship_px.y - LIFT_PX - bars_size.y).round()
	var lo := rect.position + Vector2(MAP_EDGE_GAP_PX, MAP_EDGE_GAP_PX)
	var hi := rect.end - bars_size - Vector2(MAP_EDGE_GAP_PX, MAP_EDGE_GAP_PX)
	return Vector2(clampf(pos.x, lo.x, maxf(lo.x, hi.x)), clampf(pos.y, lo.y, maxf(lo.y, hi.y)))


func _process(delta: float) -> void:
	if _suppressed:
		return
	if _pinned_id != "":
		_pinned_bars.queue_redraw()  # state changes under it (damage, morale)
		_place(_pinned_bars, _pinned_anchor)
	if _hover_id == "":
		return
	_hover_time += delta
	if hover_due(_hover_id, _pinned_id, _hover_time):
		_hover_bars.show_ship(_hover_state)
		_place(_hover_bars, _hover_anchor)
	else:
		_hover_bars.visible = false


func _place(bars: ShipStatusBars, anchor: Node3D) -> void:
	if _camera == null or anchor == null or not is_instance_valid(anchor) \
			or _camera.is_position_behind(anchor.global_position):
		bars.visible = false
		return
	var rect: Rect2 = map_rect_provider.call() if map_rect_provider.is_valid() else get_rect()
	bars.position = bars_position(_camera.unproject_position(anchor.global_position), bars.size, rect)
	bars.visible = true
