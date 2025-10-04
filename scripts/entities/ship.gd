class_name Ship
extends Node3D
## Ship - Represents a naval ship in the game

signal selected()
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
var current_speed: int = 0  # hexes per turn
var last_speed: int = 0

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

func _ready() -> void:
	_create_placeholder_model()
	_create_selection_indicator()

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
	current_speed = data.get("current_speed", 0)

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

	print("Ship initialized: %s (%s) at %s facing %d" % [ship_name, ship_type, hex_position, facing])

func _create_placeholder_model() -> void:
	"""Create a simple placeholder ship model"""
	model_node = Node3D.new()
	add_child(model_node)

	# Hull (box)
	var hull = MeshInstance3D.new()
	var hull_mesh = BoxMesh.new()
	hull_mesh.size = Vector3(0.4, 0.3, 1.2)
	hull.mesh = hull_mesh

	var hull_material = StandardMaterial3D.new()
	hull_material.albedo_color = Color(0.4, 0.25, 0.1)  # Brown wood
	hull.material_override = hull_material
	hull.position = Vector3(0, 0.15, 0)
	model_node.add_child(hull)

	# Masts (3 cylinders)
	for i in range(3):
		var mast = MeshInstance3D.new()
		var mast_mesh = CylinderMesh.new()
		mast_mesh.height = 1.0
		mast_mesh.top_radius = 0.05
		mast_mesh.bottom_radius = 0.05
		mast.mesh = mast_mesh

		var mast_material = StandardMaterial3D.new()
		mast_material.albedo_color = Color(0.6, 0.4, 0.2)
		mast.material_override = mast_material
		mast.position = Vector3(0, 0.8, -0.4 + i * 0.4)
		model_node.add_child(mast)

	# Bow indicator (cone pointing forward)
	var bow = MeshInstance3D.new()
	var bow_mesh = CylinderMesh.new()
	bow_mesh.height = 0.3
	bow_mesh.top_radius = 0.0
	bow_mesh.bottom_radius = 0.2
	bow.mesh = bow_mesh

	var bow_material = StandardMaterial3D.new()
	bow_material.albedo_color = Color(0.8, 0.6, 0.2)  # Gold/brass
	bow.material_override = bow_material
	bow.position = Vector3(0, 0.3, -0.7)
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
	position = hex_grid.axial_to_world(coord.x, coord.y)
	position.y = 0.3  # Slight elevation above water

func set_facing(new_facing: int) -> void:
	"""Update ship's facing direction"""
	facing = new_facing % 6
	_update_rotation()

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

func plot_movement(commands: Array) -> void:
	"""Store planned movement for this turn"""
	plotted_actions.movement = commands
	print("Ship %s plotted movement: %s" % [ship_id, commands])

func clear_plot() -> void:
	"""Clear all plotted actions"""
	plotted_actions = {
		"movement": [],
		"sail_change": "",
		"crew_assignments": {},
		"gunnery": [],
		"boarding": false,
		"repairs": []
	}

func get_movement_allowance() -> int:
	"""Calculate current movement allowance"""
	# Get wind facing from GameState
	var wind_dir = GameState.wind_direction
	var wind_facing = HexGrid.new().get_wind_facing(facing, wind_dir)

	# Look up MA from data
	var speed_type = definition.get("speed_type", "F/F")
	var ma = DataManager.get_movement_allowance(
		speed_type,
		GameState.wind_speed,
		wind_facing,
		sail_state,
		rigging_quality
	)

	return ma

func get_status_summary() -> Dictionary:
	"""Get a summary of ship status for UI display"""
	return {
		"name": ship_name,
		"type": definition.get("name", ship_type),
		"position": hex_position,
		"facing": facing,
		"speed": current_speed,
		"sail_state": sail_state,
		"hull_hp": hull_current_hp,
		"hull_max": hull_max_hp,
		"crew": crew_count,
		"crew_quality": crew_quality,
		"morale": crew_morale,
		"rigging": rigging_quality,
		"movement_allowance": get_movement_allowance()
	}
