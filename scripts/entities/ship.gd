class_name Ship
extends Node3D
## Ship - Represents a naval ship in the game

@warning_ignore("shadowed_global_identifier")
const WaveCalculator = preload("res://scripts/core/wave_calculator.gd")

signal selected()
@warning_ignore("unused_signal")
signal status_changed()

# Ship identification
var ship_id: String = ""
var player_id: int = 0
var ship_name: String = "Unknown Ship"

# Ship definition (from data files)
var ship_type: String = ""
var definition: Dictionary = {}

# Position and movement
var hex_position: Vector2i = Vector2i.ZERO
var facing: int = 0  # 0-5, hex direction
var speed: int = 0  # hexes per turn

# Sail and rigging state
var sail_state: String = "MS"  # FS, MS, PS, NS
var rigging_quality: int = 4  # 0-4
var rigging_damage: Array[int] = [0, 0, 0, 0]  # damage per section

# Hull state
var hull_max_hp: Array[int] = [8, 8, 8]
var hull_current_hp: Array[int] = [8, 8, 8]

# Crew
var crew_count: int = 0
var crew_quality: String = "Trained"
var crew_morale: int = 4  # 2-5

# Plotted actions for this turn
var plotted_actions: Dictionary = {
	"movement": [],  # Array of movement commands
	"sail_change": "",
	"crew_assignments": {},
	"gunnery": [],
	"boarding": false,
	"repairs": []
}

# Visual representation
var model_node: Node3D
var selection_indicator: MeshInstance3D

# Wave interaction
var wave_calculator: WaveCalculator
var base_position: Vector3  # Position without wave offset

# Grid reference (needed for 2-hex ship positioning)
var hex_grid_ref: HexGrid = null

func _ready() -> void:
	wave_calculator = WaveCalculator.new()
	_create_selection_indicator()

@warning_ignore("unused_parameter")
func _process(delta: float) -> void:
	# Always update wave position if wave calculator exists
	if wave_calculator != null:
		_update_wave_position()

func initialize(data: Dictionary, ship_def: Dictionary) -> void:
	"""Initialize the ship with data from scenario and definition"""
	ship_id = data.get("id", "ship_" + str(randi()))
	player_id = data.get("player_id", 0)
	ship_type = data.get("ship_type", "")
	definition = ship_def

	ship_name = ship_def.get("name", "Unknown")
	hex_position = Vector2i(data.get("position", {}).get("q", 0), data.get("position", {}).get("r", 0))
	facing = data.get("facing", 0)
	sail_state = data.get("sail_state", "MS")
	speed = data.get("speed", 0)

	# Initialize from definition
	rigging_quality = ship_def.get("rigging_quality", 4)

	# Convert hull_max_hp from untyped array
	var hp_data = ship_def.get("hull_max_hp", [8, 8, 8])
	hull_max_hp.clear()
	for hp in hp_data:
		hull_max_hp.append(int(hp))

	# Copy to current HP
	hull_current_hp.clear()
	for hp in hull_max_hp:
		hull_current_hp.append(hp)

	crew_count = ship_def.get("crew_count", 200)

	# Create ship model based on type
	_create_ship_model()

	print("Ship initialized: %s (%s) at %s facing %d" % [ship_name, ship_type, hex_position, facing])

func _get_ship_size() -> int:
	"""Determine ship size in hexes based on type"""
	# Corvettes are 1 hex, all others are 2 hexes
	if "corvette" in ship_type.to_lower():
		return 1
	else:
		return 2

func _create_ship_model() -> void:
	"""Create ship model based on ship type and size"""
	model_node = Node3D.new()
	add_child(model_node)

	var ship_size = _get_ship_size()

	if ship_size == 1:
		_create_1hex_model()
	else:
		_create_2hex_model()

func _create_1hex_model() -> void:
	"""Create a small corvette-sized ship (1 hex, 1 mast)"""
	# Hull - 2x thicker height (0.25 * 2 = 0.50), positioned so half is below waterline
	var hull = MeshInstance3D.new()
	var hull_mesh = BoxMesh.new()
	hull_mesh.size = Vector3(0.5, 0.5, 1.3)  # 200% thicker = 3x original height
	hull.mesh = hull_mesh

	var hull_material = StandardMaterial3D.new()
	hull_material.albedo_color = Color(0.4, 0.25, 0.1)  # Brown wood
	hull.material_override = hull_material
	hull.position = Vector3(0, 0.0, 0)  # Center at waterline, so half hull is below
	model_node.add_child(hull)

	# Single mast - positioned on top of hull
	var mast = MeshInstance3D.new()
	var mast_mesh = CylinderMesh.new()
	mast_mesh.height = 1.2
	mast_mesh.top_radius = 0.04
	mast_mesh.bottom_radius = 0.04
	mast.mesh = mast_mesh

	var mast_material = StandardMaterial3D.new()
	mast_material.albedo_color = Color(0.6, 0.4, 0.2)
	mast.material_override = mast_material
	mast.position = Vector3(0, 0.90, 0)  
	model_node.add_child(mast)

	# Bow indicator - positioned at deck level
	var bow = MeshInstance3D.new()
	var bow_mesh = CylinderMesh.new()
	bow_mesh.height = 0.25
	bow_mesh.top_radius = 0.0
	bow_mesh.bottom_radius = 0.15
	bow.mesh = bow_mesh

	var bow_material = StandardMaterial3D.new()
	bow_material.albedo_color = Color(0.8, 0.6, 0.2)
	bow.material_override = bow_material
	bow.position = Vector3(0, 0.35, -0.7)  # Top of hull deck level
	bow.rotation_degrees = Vector3(-90, 0, 0)
	model_node.add_child(bow)

func _create_2hex_model() -> void:
	"""Create a large ship (2 hexes, 3 masts)"""
	# Hull - 2x thicker height (0.35 * 2 = .70), positioned so half is below waterline
	var hull = MeshInstance3D.new()
	var hull_mesh = BoxMesh.new()
	hull_mesh.size = Vector3(0.6, .70, 2.6)  # 200% thicker = 3x original height
	hull.mesh = hull_mesh

	var hull_material = StandardMaterial3D.new()
	hull_material.albedo_color = Color(0.4, 0.25, 0.1)  # Brown wood
	hull.material_override = hull_material
	hull.position = Vector3(0, 0.0, 0)  # Center at waterline, so half hull is below
	model_node.add_child(hull)

	# Three masts - positioned on top of hull
	for i in range(3):
		var mast = MeshInstance3D.new()
		var mast_mesh = CylinderMesh.new()
		mast_mesh.height = 1.4
		mast_mesh.top_radius = 0.05
		mast_mesh.bottom_radius = 0.05
		mast.mesh = mast_mesh

		var mast_material = StandardMaterial3D.new()
		mast_material.albedo_color = Color(0.6, 0.4, 0.2)
		mast.material_override = mast_material
		mast.position = Vector3(0, 1.2, -0.8 + i * 0.9)  
		model_node.add_child(mast)

	# Bow indicator - positioned at deck level
	var bow = MeshInstance3D.new()
	var bow_mesh = CylinderMesh.new()
	bow_mesh.height = 0.35
	bow_mesh.top_radius = 0.0
	bow_mesh.bottom_radius = 0.25
	bow.mesh = bow_mesh

	var bow_material = StandardMaterial3D.new()
	bow_material.albedo_color = Color(0.8, 0.6, 0.2)  # Gold/brass
	bow.material_override = bow_material
	bow.position = Vector3(0, 0.50, -1.4)  # Top of hull deck level
	bow.rotation_degrees = Vector3(-90, 0, 0)
	model_node.add_child(bow)

func _create_selection_indicator() -> void:
	"""Create a selection indicator ring"""
	selection_indicator = MeshInstance3D.new()
	var torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = 0.6
	torus_mesh.outer_radius = 0.7
	selection_indicator.mesh = torus_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 0, 0.8)  # Yellow
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_indicator.material_override = material

	selection_indicator.position = Vector3(0, 0.05, 0)
	selection_indicator.visible = false
	add_child(selection_indicator)

func set_hex_position(coord: Vector2i, hex_grid: HexGrid) -> void:
	"""Update ship's hex position and world position"""
	hex_position = coord
	hex_grid_ref = hex_grid  # Store reference for future updates

	# Position based on ship size
	# 1-hex ships (corvettes): centered in hex
	# 2-hex ships: centered on edge between two hexes
	if _get_ship_size() == 1:
		base_position = hex_grid.axial_to_world(coord.x, coord.y)
	else:
		# 2-hex ship: position on edge between this hex and the one in facing direction
		base_position = hex_grid.axial_to_edge_world(coord.x, coord.y, facing)

	base_position.y = 0.0  # Ship center at waterline, hull extends above/below
	_update_wave_position()

func set_facing(new_facing: int) -> void:
	"""Update ship's facing direction"""
	facing = new_facing % 6
	_update_rotation()

	# Update position if 2-hex ship (position depends on facing)
	if _get_ship_size() == 2 and hex_position != Vector2i.ZERO and hex_grid_ref != null:
		# Recalculate edge position with new facing
		base_position = hex_grid_ref.axial_to_edge_world(hex_position.x, hex_position.y, facing)
		base_position.y = 0.0
		_update_wave_position()

func _update_rotation() -> void:
	"""Update the 3D rotation based on hex facing"""
	# Each hex face is 60 degrees, facing 0 is east
	var angle_deg = -facing * 60.0 + 90.0  # Adjust so facing 0 points along +X
	model_node.rotation_degrees = Vector3(0, angle_deg, 0)

func set_selected(is_selected: bool) -> void:
	"""Show/hide selection indicator"""
	selection_indicator.visible = is_selected
	if is_selected:
		selected.emit()

func get_ship_size() -> int:
	"""Public accessor for ship size"""
	return _get_ship_size()

func _update_wave_position() -> void:
	"""Update ship position and rotation based on wave motion"""
	if wave_calculator == null or base_position == Vector3.ZERO:
		return

	var current_time = Time.get_ticks_msec() / 1000.0

	# Get wave displacement at ship position
	var wave_offset = wave_calculator.get_wave_displacement(base_position, current_time)

	# Dampen the wave motion by 70% (reduce amplitude to 30% of original)
	var damping_factor = 0.3
	wave_offset *= damping_factor

	# Apply dampened wave height to ship position
	position = base_position + wave_offset

	# Get wave normal for tilting the ship
	var wave_normal = wave_calculator.get_wave_normal(base_position, current_time, 0.5)

	# Calculate tilt angles from wave normal and dampen them too
	var tilt_forward = -asin(clamp(wave_normal.z, -1.0, 1.0)) * damping_factor
	var tilt_side = asin(clamp(wave_normal.x, -1.0, 1.0)) * damping_factor

	# Apply rotation: first the ship's facing, then dampened wave tilt
	var facing_angle = -facing * 60.0 + 90.0
	model_node.rotation = Vector3(tilt_forward, deg_to_rad(facing_angle), tilt_side)
