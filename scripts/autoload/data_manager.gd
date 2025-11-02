extends Node
## DataManager - Loads and manages game data from JSON/CSV files

# Cached data
var movement_allowance_table: Array[Dictionary] = []
var ship_definitions: Dictionary = {}
var scenarios: Dictionary = {}

func _ready() -> void:
	print("DataManager initialized")

func load_movement_allowance_table(file_path: String = "res://data/rules/movement_allowance.json") -> bool:
	"""Load the movement allowance lookup table from JSON"""
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

	# Convert untyped array to typed array
	movement_allowance_table.clear()
	if json.data is Array:
		for entry in json.data:
			if entry is Dictionary:
				movement_allowance_table.append(entry)

	print("Loaded %d movement allowance entries" % movement_allowance_table.size())
	return true

func load_ship_definitions(file_path: String = "res://data/rules/ships.json") -> bool:
	"""Load ship definitions from JSON"""
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

	ship_definitions = json.data
	print("Loaded %d ship definitions" % ship_definitions.size())
	return true

func load_scenario(scenario_name: String) -> Dictionary:
	"""Load a scenario by name"""
	var file_path = "res://data/scenarios/%s.json" % scenario_name

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

	print("Loaded scenario: %s" % scenario_name)
	return json.data

func get_movement_allowance(speed_type: String, wind_speed: int, wind_facing: String,
							 sail_state: String, rigging_quality: int) -> int:
	"""Look up movement allowance from the table"""
	for entry in movement_allowance_table:
		if (entry.speed_type == speed_type and
			entry.wind_speed == wind_speed and
			entry.wind_facing == wind_facing and
			entry.sail_state == sail_state and
			entry.rigging_quality == rigging_quality):
			return entry.ma if entry.has("ma") else 0

	push_warning("No MA found for: speed_type: %s | wind_speed: %d | wind_facing: %s| sail_state: %s| rigging: %d" % [speed_type, wind_speed, wind_facing, sail_state, rigging_quality])
	return 0

func get_ship_definition(ship_id: String) -> Dictionary:
	"""Get a ship definition by ID"""
	if ship_definitions.has(ship_id):
		return ship_definitions[ship_id]

	push_warning("Ship definition not found: %s" % ship_id)
	return {}

func _create_default_movement_table() -> void:
	"""Create a small default movement table for testing"""
	movement_allowance_table = [
		{"speed_type": "F/F", "wind_speed": 3, "wind_facing": "C", "sail_state": "MS", "rigging_quality": 4, "ma": 4},
		{"speed_type": "F/F", "wind_speed": 3, "wind_facing": "B", "sail_state": "MS", "rigging_quality": 4, "ma": 7},
		{"speed_type": "F/F", "wind_speed": 3, "wind_facing": "R", "sail_state": "MS", "rigging_quality": 4, "ma": 5},
		{"speed_type": "F/F", "wind_speed": 2, "wind_facing": "C", "sail_state": "FS", "rigging_quality": 4, "ma": 2},
		{"speed_type": "F/F", "wind_speed": 2, "wind_facing": "B", "sail_state": "FS", "rigging_quality": 4, "ma": 4},
		{"speed_type": "F/F", "wind_speed": 2, "wind_facing": "R", "sail_state": "FS", "rigging_quality": 4, "ma": 3},
	]
	print("Created default movement allowance table with %d entries" % movement_allowance_table.size())

func _create_default_ships() -> void:
	"""Create default ship definitions for testing"""
	ship_definitions = {
		"frigate_38": {
			"name": "38-gun Frigate",
			"nationality": "British",
			"rating": 38,
			"class": 4,
			"maneuverability": "B",
			"speed_type": "F/F",
			"type": "Frigate",
			"draft": 12.5,
			"freeboard": 8,
			"rigging_sections": 4,
			"rigging_quality": 4,
			"sail_quality": 3,
			"hull_sections": 3,
			"hull_max_hp": [8, 8, 8],
			"acceleration": 1,
			"deceleration": 2,
			"crew_count": 280
		},
		"corvette_24": {
			"name": "24-gun Corvette",
			"nationality": "British",
			"rating": 24,
			"class": 5,
			"maneuverability": "C",
			"speed_type": "C/F",
			"type": "Corvette",
			"draft": 10,
			"freeboard": 6,
			"rigging_sections": 3,
			"rigging_quality": 4,
			"sail_quality": 3,
			"hull_sections": 3,
			"hull_max_hp": [6, 6, 6],
			"acceleration": 2,
			"deceleration": 1,
			"crew_count": 180
		}
	}
	print("Created default ship definitions: %d ships" % ship_definitions.size())

func _create_default_scenario() -> Dictionary:
	"""Create a default test scenario"""
	return {
		"name": "Test Scenario - Two Ships",
		"description": "Basic test scenario with two opposing ships",
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
