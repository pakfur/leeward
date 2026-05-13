extends Node
## DataManager - Loads and manages game data from JSON/CSV files

# Cached data
var movement_allowance_table: Dictionary = {}
var speed_change_table: Dictionary = {}
var tacking_table: Dictionary = {}
var turning_table: Dictionary = {}
var ship_definitions: Dictionary = {}  # Dictionary[String, Ship]
var bearing_off_table: Dictionary = {}
var scenarios: Dictionary = {}

func _ready() -> void:
	Trace.trace_log("DataManager", "Initialized")

func load_movement_allowance_table(file_path: String = "res://data/rules/movement_allowance.json") -> bool:
	"""Load the movement allowance lookup table from JSON (nested format)"""
	if not FileAccess.file_exists(file_path):
		push_warning("Movement allowance table not found at: %s" % file_path)
		_create_default_movement_table()
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open movement allowance table: %s" % file_path)
		return false

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		push_error("Failed to parse movement allowance JSON")
		return false

	# Store the nested dictionary structure
	if json.data is Dictionary:
		movement_allowance_table = json.data
		Trace.trace_log("DataManager", "Loaded movement allowance table with %d speed types" % movement_allowance_table.size())
		return true
	else:
		push_error("Movement allowance JSON must be a nested dictionary")
		return false

func load_speed_change_table(file_path: String = "res://data/rules/speed_change_table.json") -> bool:
	"""Load the speed change lookup table from JSON"""
	if not FileAccess.file_exists(file_path):
		push_warning("Speed change table not found at: %s" % file_path)
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open speed change table: %s" % file_path)
		return false

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		push_error("Failed to parse speed change JSON")
		return false

	if json.data is Dictionary:
		speed_change_table = json.data
		speed_change_table.erase("_doc")
		Trace.trace_log("DataManager", "Loaded speed change table with %d change types" % speed_change_table.size())
		return true
	else:
		push_error("Speed change JSON must be a dictionary")
		return false

func get_speed_change(change_type: String, maneuverability: String) -> int:
	"""Look up speed change cost from the table.

	change_type: 'acceleration' or 'deceleration'
	maneuverability: 'a' through 'd' (case-insensitive)
	"""
	assert(
		change_type == "acceleration" or change_type == "deceleration",
		"Invalid change_type '%s'. Valid values: acceleration, deceleration" % change_type
	)

	var maneuverability_lower = maneuverability.to_lower()
	assert(
		maneuverability_lower == "a" or maneuverability_lower == "b" or
		maneuverability_lower == "c" or maneuverability_lower == "d",
		"Invalid maneuverability '%s'. Valid values: a, b, c, d" % maneuverability
	)

	if not speed_change_table.has(change_type):
		push_error("Speed change table missing change_type: %s" % change_type)
		return 0

	var maneuverability_dict = speed_change_table[change_type]
	if not maneuverability_dict is Dictionary:
		push_error("Speed change table: change_type '%s' value is not a Dictionary" % change_type)
		return 0

	if not maneuverability_dict.has(maneuverability_lower):
		push_error("Speed change table missing maneuverability '%s' for change_type '%s'" % [maneuverability_lower, change_type])
		return 0

	return int(maneuverability_dict[maneuverability_lower])

func load_tacking_table(file_path: String = "res://data/rules/tacking_table.json") -> bool:
	"""Load the tacking percentage lookup table from JSON"""
	if not FileAccess.file_exists(file_path):
		push_warning("Tacking table not found at: %s" % file_path)
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open tacking table: %s" % file_path)
		return false

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		push_error("Failed to parse tacking table JSON")
		return false

	if json.data is Dictionary:
		tacking_table = json.data
		tacking_table.erase("_doc")
		Trace.trace_log("DataManager", "Loaded tacking table with %d maneuverability grades" % tacking_table.size())
		return true
	else:
		push_error("Tacking table JSON must be a dictionary")
		return false

func get_tacking_percent(maneuverability: String, wind_speed: int) -> float:
	"""Look up tacking failure percentage from the table.

	maneuverability: 'a' through 'd' (case-insensitive)
	wind_speed: 0-4 (0 returns 0.0; 1-4 indexes into the array)
	"""
	var maneuverability_lower = maneuverability.to_lower()
	assert(
		maneuverability_lower == "a" or maneuverability_lower == "b" or
		maneuverability_lower == "c" or maneuverability_lower == "d",
		"Invalid maneuverability '%s'. Valid values: a, b, c, d" % maneuverability
	)

	assert(
		wind_speed >= 0 and wind_speed <= 4,
		"Invalid wind_speed %d. Valid range: 0-4" % wind_speed
	)

	if wind_speed == 0:
		return 0.0

	if not tacking_table.has(maneuverability_lower):
		push_error("Tacking table missing maneuverability: %s" % maneuverability_lower)
		return 0.0

	var wind_array = tacking_table[maneuverability_lower]
	if not wind_array is Array:
		push_error("Tacking table: maneuverability '%s' value is not an Array" % maneuverability_lower)
		return 0.0

	var index = wind_speed - 1
	if index < 0 or index >= wind_array.size():
		push_error("Tacking table: wind_speed %d out of range for maneuverability '%s'" % [wind_speed, maneuverability_lower])
		return 0.0

	return float(wind_array[index])

func load_turning_table(file_path: String = "res://data/rules/turning_table.json") -> bool:
	"""Load the turning table from JSON"""
	if not FileAccess.file_exists(file_path):
		push_warning("Turning table not found at: %s" % file_path)
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open turning table: %s" % file_path)
		return false

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		push_error("Failed to parse turning table JSON")
		return false

	if json.data is Dictionary:
		turning_table = json.data
		turning_table.erase("_doc")
		Trace.trace_log("DataManager", "Loaded turning table with %d direction types" % turning_table.size())
		return true
	else:
		push_error("Turning table JSON must be a dictionary")
		return false

func get_min_heading_change_movement_required(direction: String, ship_speed: int, maneuverability: String) -> int:
	"""Look up minimum forward movement required between heading changes.

	direction: 'same_direction' or 'opposite_direction'
	ship_speed: 1-10 (returns -1 if <= 0)
	maneuverability: 'a' through 'd' (case-insensitive)
	"""
	if ship_speed <= 0:
		return -1

	assert(
		direction == "same_direction" or direction == "opposite_direction",
		"Invalid direction '%s'. Valid values: same_direction, opposite_direction" % direction
	)

	assert(
		ship_speed >= 1 and ship_speed <= 10,
		"Invalid ship_speed %d. Valid range: 1-10" % ship_speed
	)

	var maneuverability_lower = maneuverability.to_lower()
	assert(
		maneuverability_lower == "a" or maneuverability_lower == "b" or
		maneuverability_lower == "c" or maneuverability_lower == "d",
		"Invalid maneuverability '%s'. Valid values: a, b, c, d" % maneuverability
	)

	if not turning_table.has(direction):
		push_error("Turning table missing direction: %s" % direction)
		return 0

	var speed_dict = turning_table[direction]
	if not speed_dict is Dictionary:
		push_error("Turning table: direction '%s' value is not a Dictionary" % direction)
		return 0

	var speed_key = str(ship_speed)
	if not speed_dict.has(speed_key):
		push_error("Turning table missing speed '%s' for direction '%s'" % [speed_key, direction])
		return 0

	var maneuverability_dict = speed_dict[speed_key]
	if not maneuverability_dict is Dictionary:
		push_error("Turning table: speed '%s' value is not a Dictionary" % speed_key)
		return 0

	if not maneuverability_dict.has(maneuverability_lower):
		push_error("Turning table missing maneuverability '%s' for direction '%s', speed '%s'" % [maneuverability_lower, direction, speed_key])
		return 0

	return int(maneuverability_dict[maneuverability_lower])

func load_bearing_off_table(file_path: String = "res://data/rules/bearing_off_table.json") -> bool:
	if not FileAccess.file_exists(file_path):
		push_warning("Bearing off table not found at: %s" % file_path)
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open bearing off table: %s" % file_path)
		return false

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		push_error("Failed to parse bearing off table JSON")
		return false

	if json.data is Dictionary:
		bearing_off_table = json.data
		var grade_count = bearing_off_table.size()
		if bearing_off_table.has("_doc"):
			grade_count -= 1
		Trace.trace_log("DataManager", "Loaded bearing off table with %d crew quality grades" % grade_count)
		return true
	else:
		push_error("Bearing off table JSON must be a dictionary")
		return false

func get_bearing_off_probability(crew_quality: String, maneuverability: String) -> float:
	var crew_quality_upper = crew_quality.to_upper()
	assert(
		crew_quality_upper == "A" or crew_quality_upper == "B" or crew_quality_upper == "C" or
		crew_quality_upper == "D" or crew_quality_upper == "E" or crew_quality_upper == "F" or
		crew_quality_upper == "G",
		"Invalid crew_quality '%s'. Valid values: A, B, C, D, E, F, G" % crew_quality
	)

	var maneuverability_lower = maneuverability.to_lower()
	assert(
		maneuverability_lower == "a" or maneuverability_lower == "b" or
		maneuverability_lower == "c" or maneuverability_lower == "d",
		"Invalid maneuverability '%s'. Valid values: a, b, c, d" % maneuverability
	)

	if not bearing_off_table.has(crew_quality_upper):
		push_error("Bearing off table missing crew_quality: %s" % crew_quality_upper)
		return 0.0

	var maneuverability_dict = bearing_off_table[crew_quality_upper]
	if not maneuverability_dict is Dictionary:
		push_error("Bearing off table: crew_quality '%s' value is not a Dictionary" % crew_quality_upper)
		return 0.0

	if not maneuverability_dict.has(maneuverability_lower):
		push_error("Bearing off table missing maneuverability '%s' for crew_quality '%s'" % [maneuverability_lower, crew_quality_upper])
		return 0.0

	return float(maneuverability_dict[maneuverability_lower])

func load_ship_definitions(file_path: String = "res://data/rules/ships.json") -> bool:
	"""Load ship definitions from JSON and convert to Ship instances"""
	if not FileAccess.file_exists(file_path):
		push_warning("Ship definitions not found at: %s" % file_path)
		_create_default_ships()
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open ship definitions: %s" % file_path)
		return false

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		push_error("Failed to parse ship definitions JSON")
		return false

	# Convert JSON dictionary to Dictionary[String, Ship]
	ship_definitions.clear()
	var raw_data = json.data
	if raw_data is Dictionary:
		for ship_id in raw_data.keys():
			var ship_data = raw_data[ship_id]
			if ship_data is Dictionary:
				ship_definitions[ship_id] = Ship.from_dict(ship_data)
			else:
				push_warning("Invalid ship data for '%s'" % ship_id)

	Trace.trace_log("DataManager", "Loaded %d ship definitions" % ship_definitions.size())
	return true

func load_scenario(scenario_name: String, file_path: String = "") -> Dictionary:
	if file_path == "":
		file_path = "res://data/scenarios/%s.json" % scenario_name

	if not FileAccess.file_exists(file_path):
		push_warning("Scenario not found: %s" % file_path)
		return _create_default_scenario()

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open scenario: %s" % file_path)
		return {}

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		push_error("Failed to parse scenario JSON")
		return {}

	var scenario_dict: Dictionary = json.data

	if not scenario_dict.has("seed") or not (scenario_dict["seed"] is int or scenario_dict["seed"] is float):
		push_error("Scenario '%s' missing required 'seed' field (must be an integer)" % scenario_name)
		return {}

	var seed_val = int(scenario_dict["seed"])
	if seed_val == -1:
		seed_val = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
		scenario_dict["seed"] = seed_val
		Trace.trace_log("ScenarioLoad", "Generated fresh seed for scenario '%s': %d" % [scenario_name, seed_val])
	else:
		scenario_dict["seed"] = seed_val
		Trace.trace_log("ScenarioLoad", "Loaded scenario '%s' with seed %d" % [scenario_name, seed_val])

	if scenario_dict.has("ships") and scenario_dict["ships"] is Array:
		for ship in scenario_dict["ships"]:
			if ship is Dictionary and ship.has("crew_quality"):
				ship["crew_quality"] = _normalize_crew_quality(ship["crew_quality"])

	Trace.trace_log("DataManager", "Loaded scenario: %s" % scenario_name)
	return scenario_dict

func get_movement_allowance(speed_type: String, wind_speed: int, wind_facing: String,
							 sail_state: String, rigging_quality: int) -> int:
	"""Look up movement allowance from the nested table structure

	Hierarchy: speed_type -> wind_facing -> wind_speed -> rigging_quality -> sail_state -> value
	Returns 0 if any key is not found

	All parameters are validated with assertions to fail fast on invalid input.
	"""
	# Validate parameters with assertions (fail fast instead of masking errors with 0)
	assert(
		speed_type == "L/F" or speed_type == "L/S" or speed_type == "L/VS" or
		speed_type == "F/F" or speed_type == "F/S" or speed_type == "F/VS" or
		speed_type == "C/F" or speed_type == "C/S" or speed_type == "C/VS",
		"Invalid speed_type '%s'. Valid values: L/F, L/S, L/VS, F/F, F/S, F/VS, C/F, C/S, C/VS" % speed_type
	)

	assert(
		wind_facing == "C" or wind_facing == "B" or wind_facing == "R" or wind_facing == "L",
		"Invalid wind_facing '%s'. Valid values: C (Close-hauled), B (Broad reach), R (Reach), L (Luffing)" % wind_facing
	)

	assert(
		wind_speed >= 1 and wind_speed <= 4,
		"Invalid wind_speed %d. Valid range: 1-4" % wind_speed
	)

	assert(
		rigging_quality >= 1 and rigging_quality <= 4,
		"Invalid rigging_quality %d. Valid range: 1-4" % rigging_quality
	)

	var sail_state_upper = sail_state.to_upper()
	assert(
		sail_state_upper == "FS" or sail_state_upper == "MS" or sail_state_upper == "PS" or sail_state_upper == "NS",
		"Invalid sail_state '%s'. Valid values: FS (Fighting Sail), MS (Maneuvering Sail), PS (Plain Sail), NS (No Sail)" % sail_state
	)
	
	# Wind facing of "L" (Luff, or into the wind) returns a MA of 0
	if wind_facing == "L":
		return 0

	# Navigate the nested dictionary structure
	# Level 1: speed_type
	if not movement_allowance_table.has(speed_type):
		push_error("Movement allowance table missing speed_type: %s" % speed_type)
		return 0

	var wind_facing_dict = movement_allowance_table[speed_type]
	if not wind_facing_dict is Dictionary:
		push_error("Movement allowance table: speed_type '%s' value is not a Dictionary" % speed_type)
		return 0

	# Level 2: wind_facing
	if not wind_facing_dict.has(wind_facing):
		push_error("Movement allowance table missing wind_facing '%s' for speed_type '%s'" % [wind_facing, speed_type])
		return 0

	var wind_speed_dict = wind_facing_dict[wind_facing]
	if not wind_speed_dict is Dictionary:
		push_error("Movement allowance table: wind_facing '%s' value is not a Dictionary" % wind_facing)
		return 0

	# Level 3: wind_speed (convert int to string for dictionary key)
	var wind_speed_key = str(wind_speed)
	if not wind_speed_dict.has(wind_speed_key):
		push_error("Movement allowance table missing wind_speed %s for speed_type '%s', wind_facing '%s'" % [wind_speed_key, speed_type, wind_facing])
		return 0

	var rigging_quality_dict = wind_speed_dict[wind_speed_key]
	if not rigging_quality_dict is Dictionary:
		push_error("Movement allowance table: wind_speed '%s' value is not a Dictionary" % wind_speed_key)
		return 0

	# Level 4: rigging_quality (convert int to string for dictionary key)
	var rigging_key = str(rigging_quality)
	if not rigging_quality_dict.has(rigging_key):
		push_error("Movement allowance table missing rigging_quality %s for speed_type '%s', wind_facing '%s', wind_speed %s" % [rigging_key, speed_type, wind_facing, wind_speed_key])
		return 0

	var sail_state_dict = rigging_quality_dict[rigging_key]
	if not sail_state_dict is Dictionary:
		push_error("Movement allowance table: rigging_quality '%s' value is not a Dictionary" % rigging_key)
		return 0

	# Level 5: sail_state (convert to lowercase to match JSON format)
	var sail_state_key = sail_state.to_lower()
	if not sail_state_dict.has(sail_state_key):
		# MA table does not have define all possible sail states. Missing sail states are assumed to be 0
		return 0

	# Return the movement allowance value
	var ma = sail_state_dict[sail_state_key]
	return int(ma) if ma != null else 0

func get_ship_definition(ship_id: String) -> Ship:
	"""Get a ship definition by ID"""
	if ship_definitions.has(ship_id):
		return ship_definitions[ship_id]

	push_warning("Ship definition not found: %s" % ship_id)
	return null

func _create_default_movement_table() -> void:
	"""Create a small default movement table for testing (nested format)"""
	movement_allowance_table = {
		"F/F": {
			"C": {
				"2": {
					"4": {
						"fs": 2,
						"ms": 3,
						"ps": 4,
						"ns": 0
					}
				},
				"3": {
					"4": {
						"fs": 3,
						"ms": 4,
						"ps": 5,
						"ns": 0
					}
				}
			},
			"B": {
				"2": {
					"4": {
						"fs": 4,
						"ms": 5,
						"ps": 6,
						"ns": 0
					}
				},
				"3": {
					"4": {
						"fs": 5,
						"ms": 7,
						"ps": 8,
						"ns": 0
					}
				}
			},
			"R": {
				"2": {
					"4": {
						"fs": 3,
						"ms": 4,
						"ps": 5,
						"ns": 0
					}
				},
				"3": {
					"4": {
						"fs": 4,
						"ms": 5,
						"ps": 6,
						"ns": 0
					}
				}
			},
			"L": {
				"2": {
					"4": {
						"fs": 0,
						"ms": 0,
						"ps": 0,
						"ns": 0
					}
				},
				"3": {
					"4": {
						"fs": 0,
						"ms": 0,
						"ps": 0,
						"ns": 0
					}
				}
			}
		}
	}
	Trace.trace_log("DataManager", "Created default movement allowance table (nested format)")

func _create_default_ships() -> void:
	"""Create default ship definitions for testing"""
	ship_definitions.clear()

	# Create frigate_38
	var frigate = Ship.new()
	frigate.name = "38-gun Frigate"
	frigate.nationality = "British"
	frigate.rating = 38
	frigate.ship_class = 4
	frigate.maneuverability = "B"
	frigate.speed_type = "F/F"
	frigate.type = "Frigate"
	frigate.draft = 12
	frigate.freeboard = 8
	frigate.rigging_hp = [5, 5, 6, 6]
	frigate.hull_hp = [5, 5, 5, 6]
	frigate.crew_count = [3, 3, 3, 3]
	frigate.marine_count = 2
	ship_definitions["frigate_38"] = frigate

	# Create corvette_24
	var corvette = Ship.new()
	corvette.name = "24-gun Corvette"
	corvette.nationality = "British"
	corvette.rating = 24
	corvette.ship_class = 5
	corvette.maneuverability = "C"
	corvette.speed_type = "C/F"
	corvette.type = "Corvette"
	corvette.draft = 10
	corvette.freeboard = 6
	corvette.rigging_hp = [3, 4, 4, 4]
	corvette.hull_hp = [3, 4, 4, 4]
	corvette.crew_count = [2, 2, 2, 2]
	corvette.marine_count = 2
	ship_definitions["corvette_24"] = corvette

	Trace.trace_log("DataManager", "Created default ship definitions: %d ships" % ship_definitions.size())

func _normalize_crew_quality(text: String) -> String:
	var upper = text.strip_edges().to_upper()
	var word_map = {
		"ELITE": "A", "VETERAN": "B", "CRACK": "C", "TRAINED": "D",
		"GREEN": "E", "POOR": "F", "DEMORALIZED": "G"
	}
	if word_map.has(upper):
		return word_map[upper]
	if upper.length() == 1 and upper >= "A" and upper <= "G":
		return upper
	push_warning("Unknown crew_quality '%s', passing through unchanged" % text)
	return text

func _create_default_scenario() -> Dictionary:
	return {
		"name": "Test Scenario - Two Ships",
		"description": "Basic test scenario with two opposing ships",
		"seed": -1,
		"wind_direction": 0,
		"wind_speed": 2,
		"wind_speed_change": "steady",
		"sea_state": 1,
		"map_texture": "res://assets/textures/water_default.png",
		"ships": [
			{
				"id": "player_ship",
				"player_id": 0,
				"ship_type": "frigate_38",
				"position": {"q": 5, "r": 15},
				"facing": 0,
				"sail_state": "MS",
				"speed": 0
			},
			{
				"id": "enemy_ship",
				"player_id": 1,
				"ship_type": "corvette_24",
				"position": {"q": 20, "r": 15},
				"facing": 3,
				"sail_state": "MS",
				"speed": 0
			}
		]
	}
