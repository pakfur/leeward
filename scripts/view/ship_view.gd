class_name ShipView
extends Node3D
## ShipView - Visual representation of a ship (presentation only, no game state)

const WaveCalculator = preload("res://scripts/core/wave_calculator.gd")

signal selected()

var state_id: String = ""  # Reference to ShipState in GameState
var model_node: Node3D
var selection_indicator: MeshInstance3D

# Wave interaction (visual only, not part of game state)
var wave_calculator: WaveCalculator
var base_position: Vector3  # Position without wave offset
var hex_grid_ref: HexGrid = null

func _ready() -> void:
	wave_calculator = WaveCalculator.new()
	_create_selection_indicator()

func _process(_delta: float) -> void:
	# Visual update only - wave bobbing
	if wave_calculator != null:
		_update_wave_position()

func initialize(ship_state: ShipState, hex_grid: HexGrid) -> void:
	"""Initialize view from state"""
	state_id = ship_state.ship_id
	hex_grid_ref = hex_grid

	# Create ship model based on type
	_create_ship_model(ship_state.get_ship_size())

	# Sync to initial state
	sync_to_state(ship_state, hex_grid)

func sync_to_state(ship_state: ShipState, hex_grid: HexGrid) -> void:
	"""Update visual representation to match state"""
	state_id = ship_state.ship_id
	hex_grid_ref = hex_grid

	# Update position
	_update_position_from_state(ship_state, hex_grid)

	# Update rotation
	_update_rotation_from_state(ship_state)

func _update_position_from_state(ship_state: ShipState, hex_grid: HexGrid) -> void:
	"""Calculate and set position based on ship state"""
	# Position based on ship size
	# 1-hex ships (corvettes): centered in hex
	# 2-hex ships: centered on edge between two hexes
	if ship_state.get_ship_size() == 1:
		base_position = hex_grid.axial_to_world(ship_state.hex_position.x, ship_state.hex_position.y)
	else:
		# 2-hex ship: position on edge between this hex and the one in facing direction
		base_position = hex_grid.axial_to_edge_world(ship_state.hex_position.x, ship_state.hex_position.y, ship_state.facing)

	base_position.y = 0.0  # Ship center at waterline, hull extends above/below
	_update_wave_position()

func _update_rotation_from_state(ship_state: ShipState) -> void:
	"""Update the 3D rotation based on state"""
	# Each hex face is 60 degrees, facing 0 is east
	var angle_deg = -ship_state.facing * 60.0 + 90.0
	if model_node:
		model_node.rotation_degrees = Vector3(0, angle_deg, 0)

func _create_ship_model(ship_size: int) -> void:
	"""Create ship model based on ship size"""
	model_node = Node3D.new()
	add_child(model_node)

	if ship_size == 1:
		_create_1hex_model()
	else:
		_create_2hex_model()

func _create_1hex_model() -> void:
	"""Create a small corvette-sized ship (1 hex, 1 mast)"""
	# Hull - 2x thicker height (0.25 * 2 = 0.50), positioned so half is below waterline
	var hull = MeshInstance3D.new()
	var hull_mesh = BoxMesh.new()
	hull_mesh.size = Vector3(0.5, 0.5, 1.3)
	hull.mesh = hull_mesh

	var hull_material = StandardMaterial3D.new()
	hull_material.albedo_color = Color(0.4, 0.25, 0.1)  # Brown wood
	hull.material_override = hull_material
	hull.position = Vector3(0, 0.0, 0)  # Center at waterline
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
	bow.position = Vector3(0, 0.35, -0.7)
	bow.rotation_degrees = Vector3(-90, 0, 0)
	model_node.add_child(bow)

func _create_2hex_model() -> void:
	"""Create a large ship (2 hexes, 3 masts)"""
	# Hull - 2x thicker height (0.35 * 2 = .70), positioned so half is below waterline
	var hull = MeshInstance3D.new()
	var hull_mesh = BoxMesh.new()
	hull_mesh.size = Vector3(0.6, .70, 2.6)
	hull.mesh = hull_mesh

	var hull_material = StandardMaterial3D.new()
	hull_material.albedo_color = Color(0.4, 0.25, 0.1)  # Brown wood
	hull.material_override = hull_material
	hull.position = Vector3(0, 0.0, 0)  # Center at waterline
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
	bow.position = Vector3(0, 0.50, -1.4)
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

func set_selected(is_selected: bool) -> void:
	"""Show/hide selection indicator"""
	selection_indicator.visible = is_selected
	# Note: Don't emit signal here - this is for programmatic selection updates
	# The 'selected' signal should only be emitted by user interaction (3D clicks)

func _update_wave_position() -> void:
	"""Update ship position and rotation based on wave motion (visual only)"""
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
	# Get facing from current rotation (stored in model_node)
	if model_node:
		var facing_angle = model_node.rotation_degrees.y
		model_node.rotation = Vector3(tilt_forward, deg_to_rad(facing_angle), tilt_side)
