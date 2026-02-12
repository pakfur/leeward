class_name ShipState
extends Resource
## ShipState - Pure data representation of a ship (no visual components)
## This class is serializable and can run on both server and client

# Ship identification
@export var ship_id: String = ""
@export var player_id: int = 0
@export var ship_name: String = "Unknown Ship"

# Ship definition (from data files)
@export var ship_type: String = "" # from ships.json (ie "frigate_38")
var definition: ShipDefinition = null  # loaded from ships.json

# Position and movement (hex-based, deterministic)
@export var hex_position: Vector2i = Vector2i.ZERO
@export var facing: int = 0  # 0-5, hex direction
@export var speed: int = 0  # hexes per turn
@export var movement_points: int = 0 # current turns movement points
@export var acceleration: int = 0 # current ships acceleration, negative value indicates deceleration

# Sail and rigging state
@export var sail_state: String = "MS"  # FS, MS, PS, NS
@export var rigging_current_hp: Array[int] = [0, 0, 0, 0]  # damage per section

# Hull state
@export var hull_current_hp: Array[int] = [0, 0, 0, 0]

# Crew
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
	if rigging_current_hp.is_empty():
		rigging_current_hp = [0, 0, 0, 0]
	if hull_current_hp.is_empty():
		hull_current_hp = [0, 0, 0, 0]

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

	var speed_type = definition.speed_type if definition else "F/F"
	# Calculate rigging quality from current HP (1-4 based on average HP percentage)
	var rigging_quality = get_rigging_quality()
	var ma = DataManager.get_movement_allowance(
		speed_type,
		GameState.wind_speed,
		wind_facing,
		sail_state,
		rigging_quality
	)

	return ma

func get_rigging_quality() -> int:
	"""Calculate rigging quality (1-4) based on current HP compared to definition max"""
	if definition == null:
		return 4  # Default to best quality if no definition

	var max_hp_array = definition.rigging_hp
	var total_max = 0
	var total_current = 0

	for i in range(4):
		total_max += max_hp_array[i] if i < max_hp_array.size() else 0
		total_current += rigging_current_hp[i]

	if total_max == 0:
		return 4

	var hp_percentage = float(total_current) / float(total_max)

	# Convert percentage to quality (1-4)
	if hp_percentage >= 0.85:
		return 4
	elif hp_percentage >= 0.60:
		return 3
	elif hp_percentage >= 0.35:
		return 2
	else:
		return 1

func get_status_summary() -> Dictionary:
	"""Get a summary of ship status for UI display"""
	var hull_max = definition.hull_hp if definition else [0, 0, 0, 0]
	var ship_def_name = definition.name if definition else ship_type
	return {
		"name": ship_name,
		"type": ship_def_name,
		"size": get_ship_size(),
		"position": hex_position,
		"facing": facing,
		"speed": speed,
		"sail_state": sail_state,
		"hull_hp": hull_current_hp,
		"hull_max": hull_max,
		"crew_quality": crew_quality,
		"morale": crew_morale,
		"rigging": get_rigging_quality(),
		"rigging_hp": rigging_current_hp,
		"movement_allowance": get_movement_allowance()
	}

func serialize() -> Dictionary:
	"""Serialize state for network transmission or save/load"""
	return {
		"ship_id": ship_id,
		"player_id": player_id,
		"ship_name": ship_name,
		"ship_type": ship_type,
		"position": {"q": hex_position.x, "r": hex_position.y},
		"facing": facing,
		"speed": speed,
		"movement_points": movement_points,
		"acceleration": acceleration,
		"sail_state": sail_state,
		"rigging_current_hp": rigging_current_hp,
		"hull_current_hp": hull_current_hp,
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

	# Look up ShipDefinition from DataManager using ship_type
	state.definition = DataManager.get_ship_definition(state.ship_type)
	if state.definition == null:
		push_error("Failed to find ShipDefinition for ship_type '%s' during deserialization" % state.ship_type)

	var pos = data.get("position", {"q": 0, "r": 0})
	state.hex_position = Vector2i(pos.q, pos.r)

	state.facing = data.get("facing", 0)
	state.speed = data.get("speed", 0)
	state.movement_points = data.get("movement_points", 0)
	state.acceleration = data.get("acceleration", 0)
	state.sail_state = data.get("sail_state", "MS")

	# Load rigging HP
	var rigging_hp_data = data.get("rigging_current_hp", [0, 0, 0, 0])
	state.rigging_current_hp.clear()
	for hp in rigging_hp_data:
		state.rigging_current_hp.append(int(hp))

	# Load hull HP
	var hull_hp_data = data.get("hull_current_hp", [0, 0, 0, 0])
	state.hull_current_hp.clear()
	for hp in hull_hp_data:
		state.hull_current_hp.append(int(hp))

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

func initialize_from_scenario(data: Dictionary, ship_def: ShipDefinition) -> void:
	"""Initialize the ship state from scenario data with a ShipDefinition"""
	# Basic identification
	ship_id = data.get("id", "ship_" + str(randi()))
	player_id = data.get("player_id", 0)
	ship_type = data.get("ship_type", "")
	definition = ship_def
	ship_name = data.get("ship_name", ship_def.name if ship_def else "Unknown")

	# Position and movement
	hex_position = Vector2i(data.get("position", {}).get("q", 0), data.get("position", {}).get("r", 0))
	facing = data.get("facing", 0)
	speed = data.get("speed", data.get("current_speed", 0))  # Support both "speed" and legacy "current_speed"
	movement_points = data.get("movement_points", 0)
	acceleration = data.get("acceleration", 0)

	# Sail state
	sail_state = data.get("sail_state", "MS")

	# Rigging HP - from scenario or copy from definition
	var rigging_hp_scenario = data.get("rigging_current_hp", null)
	rigging_current_hp.clear()
	if rigging_hp_scenario != null:
		for hp in rigging_hp_scenario:
			rigging_current_hp.append(int(hp))
	elif ship_def:
		for hp in ship_def.rigging_hp:
			rigging_current_hp.append(hp)
	else:
		rigging_current_hp = [0, 0, 0, 0]

	# Hull HP - from scenario or copy from definition
	var hull_hp_scenario = data.get("hull_current_hp", null)
	hull_current_hp.clear()
	if hull_hp_scenario != null:
		for hp in hull_hp_scenario:
			hull_current_hp.append(int(hp))
	elif ship_def:
		for hp in ship_def.hull_hp:
			hull_current_hp.append(hp)
	else:
		hull_current_hp = [0, 0, 0, 0]

	# Crew
	crew_quality = data.get("crew_quality", "Trained")
	crew_morale = data.get("crew_morale", 4)

	print("ShipState initialized: %s (%s) at %s facing %d, speed %d" % [ship_name, ship_type, hex_position, facing, speed])

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
