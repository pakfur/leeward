class_name ShipState
extends Resource
## ShipState - Mutable game state for a ship (no visual components)
## This class is serializable and can run on both server and client
## Immutable identity/definition data lives in the Ship reference

# Ship reference (immutable identity + type definition)
var ship: Ship = null

# Convenience getters for immutable identity fields
var ship_id: String:
	get: return ship.ship_id if ship else ""
var player_id: int:
	get: return ship.player_id if ship else 0
var ship_name: String:
	get: return ship.ship_name if ship else "Unknown"
var ship_type: String:
	get: return ship.ship_type if ship else ""

# Position and movement (hex-based, deterministic)
@export var hex_position: Vector2i = Vector2i.ZERO
@export var facing: int = 0  # 0-5, hex direction
@export var speed: int = 0  # hexes per turn
@export var immobilized: bool = false  # ship cannot move
@export var tacking: bool = false # user has indicated they are tacking
@export var fouled_with: String = ""  # ship_id of fouled partner, empty if not fouled
@export var collision_this_turn: bool = false  # set during resolution, cleared at turn start
@export var movement_allowance: int = 0 # current turns movement points
@export var min_ma: int = 0 # current ma + any deceleration considerations
@export var max_ma: int = 0 # current speed + acceleration and ma considerations
@export var acceleration: int = 0 # current ships acceleration, negative value indicates deceleration

# Towing
@export var towing: bool = false

# Sail and rigging state
@export var sail_state: String = "MS"  # FS, MS, PS, NS
@export var rigging_current_hp: Array[int] = [0, 0, 0, 0]  # damage per section

# Hull state
@export var hull_current_hp: Array[int] = [0, 0, 0, 0]

# Crew
@export var crew_morale: int = 4  # 2-5
@export var crew_count: Array[int] = [0, 0, 0] # number of "crew" in each section, 1-12 per section (does not reflect actual crew count)
@export var marine_count: int = 0 # number of "marines" 0-12
@export var crew_quality: String = "B" # A=Elite, B=Veteran, C-D=Trained, E=Green, F-G=Demoralized

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
	# deprecated - setting to 1 for all ships. May revert in the future
	return 1
	#"""Determine ship size in hexes based on type"""
	#if "corvette" in ship_type.to_lower():
		#return 1
	#else:
		#return 2

func get_movement_allowance() -> int:
	"""Calculate current movement allowance"""
	var wind_dir = GameState.wind_direction
	var hex_grid = HexGrid.new()
	var wind_facing = hex_grid.get_wind_facing(facing, wind_dir)

	var spd_type = ship.speed_type if ship else "F/F"
	# Calculate rigging quality from current HP (1-4 based on average HP percentage)
	var rigging_quality = get_rigging_quality()
	var ma = DataManager.get_movement_allowance(
		spd_type,
		GameState.wind_speed,
		wind_facing,
		sail_state,
		rigging_quality
	)

	Trace.trace_log("ShipState", "MA: %d | wind: %s | facing: %s | speed: %s | sail: %s" % [ma, wind_dir, wind_facing, GameState.wind_speed, sail_state])
	return ma

func get_rigging_quality() -> int:
	"""Calculate rigging quality (1-4) based on current HP compared to definition max"""
	if ship == null:
		return 4  # Default to best quality if no definition

	var max_hp_array = ship.rigging_hp
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
	var hull_max = ship.hull_hp if ship else [0, 0, 0, 0]
	var ship_def_name = ship.name if ship else ship_type
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
		"crew_count": crew_count,
		"marine_count": marine_count,
		"morale": crew_morale,
		"rigging": get_rigging_quality(),
		"rigging_hp": rigging_current_hp,
		"movement_allowance": get_movement_allowance()
	}

func serialize() -> Dictionary:
	"""Serialize state for network transmission or save/load"""
	var data = {
		"ship": ship.to_dict() if ship else {},
		"position": {"q": hex_position.x, "r": hex_position.y},
		"facing": facing,
		"speed": speed,
		"immobilized": immobilized,
		"tacking": tacking,
		"fouled_with": fouled_with,
		"collision_this_turn": collision_this_turn,
		"movement_allowance": movement_allowance,
		"min_ma": min_ma,
		"max_ma": max_ma,
		"towing": towing,
		"acceleration": acceleration,
		"sail_state": sail_state,
		"rigging_current_hp": rigging_current_hp,
		"hull_current_hp": hull_current_hp,
		"crew_morale": crew_morale,
		"crew_count": crew_count,
		"marine_count": marine_count,
		"plotted_actions": plotted_actions
	}
	return data

static func deserialize(data: Dictionary) -> ShipState:
	"""Deserialize state from network or save file"""
	var state = ShipState.new()

	# Reconstruct Ship from serialized data
	var ship_data = data.get("ship", {})
	if not ship_data.is_empty():
		state.ship = Ship.from_dict(ship_data)
	else:
		push_error("Missing 'ship' key during ShipState deserialization")

	var pos = data.get("position", {"q": 0, "r": 0})
	state.hex_position = Vector2i(pos.q, pos.r)

	state.facing = data.get("facing", 0)
	state.speed = data.get("speed", 0)
	state.movement_allowance = data.get("movement_allowance", 0)
	state.immobilized = data.get("immobilized", false)
	state.tacking = data.get("tacking", false)
	state.fouled_with = data.get("fouled_with", "")
	state.collision_this_turn = data.get("collision_this_turn", false)
	state.min_ma = data.get("min_ma")
	state.max_ma = data.get("max_ma")
	state.towing = data.get("towing")
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

	state.crew_morale = data.get("crew_morale", 4)
	var crew_count_data = data.get("crew_count", [0, 0, 0])
	state.crew_count.clear()
	for ct in crew_count_data:
		state.crew_count.append(int(ct))
	state.marine_count = data.get("marine_count", 0)
	
	state.plotted_actions = data.get("plotted_actions", {
		"movement": [],
		"sail_change": "",
		"crew_assignments": {},
		"gunnery": [],
		"boarding": false,
		"repairs": []
	})

	return state

func initialize_from_scenario(data: Dictionary, ship_ref: Ship) -> void:
	"""Initialize the ship state from scenario data with a Ship instance"""
	ship = ship_ref

	# Position and movement
	hex_position = Vector2i(data.get("position", {}).get("q", 0), data.get("position", {}).get("r", 0))
	facing = data.get("facing", 0)
	speed = data.get("speed", data.get("current_speed", 0))  # Support both "speed" and legacy "current_speed"
	movement_allowance = data.get("movement_allowance", 0)
	acceleration = data.get("acceleration", 0)

	# Sail state
	sail_state = data.get("sail_state", "MS")

	# Rigging HP - from scenario or copy from ship definition
	var rigging_hp_scenario = data.get("rigging_current_hp", null)
	rigging_current_hp.clear()
	if rigging_hp_scenario != null:
		for hp in rigging_hp_scenario:
			rigging_current_hp.append(int(hp))
	elif ship_ref:
		for hp in ship_ref.rigging_hp:
			rigging_current_hp.append(hp)
	else:
		rigging_current_hp = [0, 0, 0, 0]

	# Hull HP - from scenario or copy from ship definition
	var hull_hp_scenario = data.get("hull_current_hp", null)
	hull_current_hp.clear()
	if hull_hp_scenario != null:
		for hp in hull_hp_scenario:
			hull_current_hp.append(int(hp))
	elif ship_ref:
		for hp in ship_ref.hull_hp:
			hull_current_hp.append(hp)
	else:
		hull_current_hp = [0, 0, 0, 0]

	# Crew
	crew_morale = data.get("crew_morale", 4)

	Trace.trace_log("ShipState", "Initialized: %s (%s) at %s facing %d, speed %d" % [ship_name, ship_type, hex_position, facing, speed])

func clear_turn_flags() -> void:
	collision_this_turn = false

func clear_plot() -> void:
	plotted_actions = {
		"movement": [],
		"sail_change": "",
		"crew_assignments": {},
		"gunnery": [],
		"boarding": false,
		"repairs": []
	}
