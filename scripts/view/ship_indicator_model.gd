class_name ShipIndicatorModel
extends RefCounted
## ShipIndicatorModel - Pure, read-only presentation DTO + builders for the
## selected-ship and plotting-hover indicators.
##
## View layer: computes geometry and labels from primitive values it is handed.
## No game-state access, no mutation. Renderers consume this DTO only.

var windward_visible: bool = false
var windward_anchor: Vector3 = Vector3.ZERO   # where the wind meets the two-hex footprint, level with the ship centre (world)
var windward_dir: Vector3 = Vector3.ZERO       # outward face normal (world, XZ unit)
var direction_anchor: Vector3 = Vector3.ZERO   # bow hex-face midpoint (world)
var direction_dir: Vector3 = Vector3.ZERO      # outward face normal (world, XZ unit)
var center_anchor: Vector3 = Vector3.ZERO      # bow hex center (world) — for the info icon
var label_anchor: Vector3 = Vector3.ZERO       # world point to project the label near
var neighbor_anchors: Array[Vector3] = []      # the six neighbouring hex centres, by direction 0..5
var beyond_stern_anchor: Vector3 = Vector3.ZERO  # centre of the hex astern of the stern hex — for the info icon
var heading: int = 0                           # heading the indicators show (0=E .. 5=NE)
var speed: int = 0
var point_of_sail: String = ""
var opacity: float = 1.0

const POS_LABELS := {
	"L": "In Irons",
	"C": "Close Hauled",
	"B": "Broad Reach",
	"R": "Running",
}

static func point_of_sail_label(wind_facing_code: String) -> String:
	return POS_LABELS.get(wind_facing_code, "")

## distance: camera-to-anchor world distance; factor: scale coefficient; min/max_world: output clamp (world units).
static func clamp_scale(distance: float, factor: float, min_world: float, max_world: float) -> float:
	return clampf(distance * factor, min_world, max_world)

static func build_selected(hex_position: Vector2i, facing: int, ship_speed: int, wind_direction: int, wind_speed: int, hex_grid: HexGrid) -> ShipIndicatorModel:
	return _build(hex_position, facing, ship_speed, wind_direction, wind_speed, hex_grid, 1.0)

static func build_hover(hex_position: Vector2i, resulting_facing: int, ship_speed: int, wind_direction: int, wind_speed: int, hex_grid: HexGrid) -> ShipIndicatorModel:
	return _build(hex_position, resulting_facing, ship_speed, wind_direction, wind_speed, hex_grid, 0.6)

static func _build(hex_position: Vector2i, facing: int, ship_speed: int, wind_direction: int, wind_speed: int, hex_grid: HexGrid, opacity_val: float) -> ShipIndicatorModel:
	var m := ShipIndicatorModel.new()
	var q := hex_position.x
	var r := hex_position.y
	var center := hex_grid.axial_to_world(q, r)

	m.center_anchor = center
	m.heading = facing
	for d in range(6):
		var n := hex_grid.get_neighbor(q, r, d)
		m.neighbor_anchors.append(hex_grid.axial_to_world(n.x, n.y))
	var beyond := HexGrid.stern_of(HexGrid.stern_of(hex_position, facing), facing)
	m.beyond_stern_anchor = hex_grid.axial_to_world(beyond.x, beyond.y)

	# Direction indicator anchored on the bow face (= facing / resulting_facing)
	m.direction_anchor = hex_grid.axial_to_edge_world(q, r, facing)
	m.direction_dir = (m.direction_anchor - center).normalized()

	# Windward indicator: from the ship centre (midway between bow and stern) out to the footprint's
	# face in the wind direction. Abeam or on a quarter that face is half a hex out (an outer face of
	# the bow or stern hex); dead ahead or astern it is the bow or stern hex's end face, a hex out.
	# Hidden when calm.
	m.windward_visible = wind_speed > 0  # windward_anchor/dir are computed regardless; consumers must gate on windward_visible.
	var face_offset := hex_grid.axial_to_edge_world(q, r, wind_direction) - center
	var along_keel := wind_direction == facing or wind_direction == (facing + 3) % 6
	m.windward_anchor = hex_grid.ship_center_world(hex_position, facing) + face_offset * (2.0 if along_keel else 1.0)
	m.windward_dir = face_offset.normalized()

	m.label_anchor = m.direction_anchor
	m.speed = ship_speed
	m.point_of_sail = point_of_sail_label(hex_grid.get_wind_facing(facing, wind_direction))
	m.opacity = opacity_val
	return m
