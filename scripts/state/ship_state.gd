class_name ShipState
extends Resource
## ShipState - Pure data representation of a ship (no visual components)
## This class is serializable and can run on both server and client

# Ship identification
@export var ship_id: String = ""
@export var player_id: int = 0
@export var ship_name: String = "Unknown Ship"

# Ship definition (from data files)
@export var ship_type: String = ""
@export var definition: Dictionary = {}

# Position and movement (hex-based, deterministic)
@export var hex_position: Vector2i = Vector2i.ZERO
@export var facing: int = 0  # 0-5, hex direction
@export var current_speed: int = 0  # hexes per turn
@export var last_speed: int = 0

# Sail and rigging state
@export var sail_state: String = "MS"  # FS, MS, PS, NS
@export var rigging_quality: int = 4  # 0-4
@export var rigging_damage: Array[int] = [0, 0, 0, 0]  # damage per section

# Hull state
@export var hull_max_hp: Array[int] = [8, 8, 8]
@export var hull_current_hp: Array[int] = [8, 8, 8]

# Crew
@export var crew_count: int = 0
@export var crew_quality: String = "Trained"
@export var crew_morale: int = 4  # 2-5

# Plotted actions for this turn
var plotted_actions: Dictionary = {
	"movement": [],  # Array of movement commands
	"sail_change": "",
	"crew_assignments": {},
	"gunnery": [],
	"boarding": false,
	"repairs": []
}

func _init() -> void:
	# Initialize arrays properly
	if rigging_damage.is_empty():
		rigging_damage = [0, 0, 0, 0]
	if hull_max_hp.is_empty():
		hull_max_hp = [8, 8, 8]
	if hull_current_hp.is_empty():
		hull_current_hp = [8, 8, 8]

func get_ship_size() -> int:
	"""Determine ship size in hexes based on type"""
	if "corvette" in ship_type.to_lower():
		return 1
	else:
		return 2

func get_movement_allowance() -> int:
	"""Calculate current movement allowance"""
	var wind_dir = GameState.wind_direction
	var hex_grid = HexGrid.new()
	var wind_facing = hex_grid.get_wind_facing(facing, wind_dir)

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
		"size": get_ship_size(),
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

func serialize() -> Dictionary:
	"""Serialize state for network transmission or save/load"""
	return {
		"ship_id": ship_id,
		"player_id": player_id,
		"ship_name": ship_name,
		"ship_type": ship_type,
		"definition": definition,
		"position": {"q": hex_position.x, "r": hex_position.y},
		"facing": facing,
		"current_speed": current_speed,
		"last_speed": last_speed,
		"sail_state": sail_state,
		"rigging_quality": rigging_quality,
		"rigging_damage": rigging_damage,
		"hull_max_hp": hull_max_hp,
		"hull_current_hp": hull_current_hp,
		"crew_count": crew_count,
		"crew_quality": crew_quality,
		"crew_morale": crew_morale,
		"plotted_actions": plotted_actions
	}

static func deserialize(data: Dictionary) -> ShipState:
	"""Deserialize state from network or save file"""
	var state = ShipState.new()

	state.ship_id = data.get("ship_id", "")
	state.player_id = data.get("player_id", 0)
	state.ship_name = data.get("ship_name", "Unknown")
	state.ship_type = data.get("ship_type", "")
	state.definition = data.get("definition", {})

	var pos = data.get("position", {"q": 0, "r": 0})
	state.hex_position = Vector2i(pos.q, pos.r)

	state.facing = data.get("facing", 0)
	state.current_speed = data.get("current_speed", 0)
	state.last_speed = data.get("last_speed", 0)
	state.sail_state = data.get("sail_state", "MS")
	state.rigging_quality = data.get("rigging_quality", 4)
	state.rigging_damage = data.get("rigging_damage", [0, 0, 0, 0])
	state.hull_max_hp = data.get("hull_max_hp", [8, 8, 8])
	state.hull_current_hp = data.get("hull_current_hp", [8, 8, 8])
	state.crew_count = data.get("crew_count", 0)
	state.crew_quality = data.get("crew_quality", "Trained")
	state.crew_morale = data.get("crew_morale", 4)
	state.plotted_actions = data.get("plotted_actions", {
		"movement": [],
		"sail_change": "",
		"crew_assignments": {},
		"gunnery": [],
		"boarding": false,
		"repairs": []
	})

	return state

func initialize_from_scenario(data: Dictionary, ship_def: Dictionary) -> void:
	"""Initialize the ship state from scenario data"""
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

	print("ShipState initialized: %s (%s) at %s facing %d" % [ship_name, ship_type, hex_position, facing])

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
