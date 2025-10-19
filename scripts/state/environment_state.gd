class_name EnvironmentState
extends Resource
## EnvironmentState - Environmental conditions (wind, weather, sea state)
## Pure data representation, deterministic updates, serializable

# Wind
@export var wind_direction: int = 0  # 0-5 representing hex faces (0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE)
@export var wind_speed: int = 2  # 0-5 (0=calm, 1=light, 2=moderate, 3=fresh, 4=strong, 5=gale)
@export var wind_speed_change: String = "steady"  # "steady", "gusty"
@export var region: String = "oceanic" # "oceanic", "coastal"
@export var wind_direction_change: String = "none"  # "none", "veering", "backing"

# Sea State
@export var sea_state: int = 1  # 0-3 (0=calm, 1=moderate, 2=rough, 3=storm)

# Weather (for future expansion)
@export var visibility: String = "clear"  # "clear", "hazy", "fog", "storm"
@export var time_of_day: String = "day"  # "dawn", "day", "dusk", "night"

# Weather change patterns (optional, for more complex scenarios)
@export var precipitation: String = "none"  # "none", "rain", "snow", "storm"

func tick_environment(turn_number: int, rng: RandomNumberGenerator, history: Array[EnvironmentState] = []) -> void:
	"""Update environment for new turn

	Args:
		turn_number: Current turn number
		rng: Random number generator for changes
		history: Array of previous environment states indexed by turn number (passed by reference, no performance cost)
	"""
	_update_wind_speed(rng, history)
	_update_wind_direction(rng, history)
	_update_weather(rng, history)
	
func _update_wind_speed(rng: RandomNumberGenerator, history: Array[EnvironmentState]) -> void:
	"""Update wind speed based on change patterns

	Args:
		rng: Random number generator for changes
		history: Array of previous environment states
	"""
	# Get original state (turn 0) if available
	var original_wind_speed = wind_speed  # Default to current if no history
	if history.size() > 0 and history[0] != null:
		original_wind_speed = history[0].wind_speed

	# Wind speed changes
	var temp_wind_speed = wind_speed
	var wind_speed_roll = rng.randi_range(1, 10) + rng.randi_range(1, 10) # 2d10
	var changes_threshold = 4 if wind_speed_change == "steady" else 6

	if wind_speed_roll < changes_threshold:
		var changes = rng.randi_range(1,10)
		if changes < 5:
			wind_speed += 1
		else:
			wind_speed -= 1
	elif wind_speed_roll > 17:
		# revert back towards original wind speed
		if wind_speed > original_wind_speed:
			wind_speed -= 1
		if wind_speed < original_wind_speed:
			wind_speed += 1

	wind_speed = clampi(wind_speed, 0, 4)
	if temp_wind_speed != wind_speed:
		print("Wind speed changed from %d to %d" % [temp_wind_speed, wind_speed])

func _update_wind_direction(rng: RandomNumberGenerator, history: Array[EnvironmentState]) -> void:
	"""Update wind direction based on change patterns

	Args:
		rng: Random number generator for changes
		history: Array of previous environment states
	"""
	# Get original state (turn 0) if available
	var original_wind_direction = wind_direction  # Default to current if no history
	if history.size() > 0 and history[0] != null:
		original_wind_direction = history[0].wind_direction

	# Wind direction changes
	var temp_wind_direction = wind_direction
	var wind_dir_roll = rng.randi_range(1, 10) + rng.randi_range(1, 10) # 2d10
	match region:
		"oceanic":
			if wind_dir_roll < 4:
				# veer clockwise or counter-clockwise
				var wind_veer_roll = rng.randi_range(1, 10)
				if wind_veer_roll < 6:
					wind_direction = (wind_direction - 1 + 6) % 6
				else:
					wind_direction = (wind_direction + 1 + 6) % 6
			else:
				if wind_dir_roll > 17:
					# revert the wind direction towards original wind_direction
					if wind_direction > original_wind_direction:
						wind_direction = (wind_direction - 1 + 6) % 6
					else:
						if wind_direction < original_wind_direction:
							wind_direction = (wind_direction + 1 + 6) % 6

		"coastal":
			if wind_dir_roll > 5 && wind_dir_roll < 8:
				var wind_veer_roll = rng.randi_range(1, 10)
				if wind_veer_roll < 6:
					wind_direction = (wind_direction - 1 + 6) % 6
				else:
					wind_direction = (wind_direction + 1 + 6) % 6
			else:
				if wind_dir_roll > 17:
					# revert the wind direction towards original wind_direction
					if wind_direction > original_wind_direction:
						wind_direction = (wind_direction - 1 + 6) % 6
					else:
						if wind_direction < original_wind_direction:
							wind_direction = (wind_direction + 1 + 6) % 6
	if wind_direction != temp_wind_direction:
		print("Wind direction changed from %d to %d" % [temp_wind_direction, wind_direction])


func _update_weather(rng: RandomNumberGenerator, history: Array[EnvironmentState]) -> void:
	"""Update weather conditions (visibility, precipitation, etc)

	Args:
		rng: Random number generator for changes
		history: Array of previous environment states
	"""
	# TODO: Implement weather patterns
	# For now, weather is static based on scenario
	# When implemented, history can be used for weather progression
	# Example: var previous_weather = history[history.size() - 1].precipitation if history.size() > 0 else "none"
	pass

func get_wind_direction_name() -> String:
	"""Get human-readable wind direction"""
	var directions = ["E", "SE", "SW", "W", "NW", "NE"]
	return directions[wind_direction]

func get_wind_speed_name() -> String:
	"""Get human-readable wind speed"""
	var speeds = ["Calm", "Light", "Moderate", "Fresh", "Strong", "Gale"]
	return speeds[wind_speed]

func get_sea_state_name() -> String:
	"""Get human-readable sea state"""
	var states = ["Calm", "Moderate", "Rough", "Storm"]
	return states[sea_state]

func serialize() -> Dictionary:
	"""Serialize environment state for network transmission or save/load"""
	return {
		"wind_direction": wind_direction,
		"wind_speed": wind_speed,
		"wind_speed_change": wind_speed_change,
		"wind_direction_change": wind_direction_change,
		"region": region,
		"sea_state": sea_state,
		"visibility": visibility,
		"time_of_day": time_of_day,
		"precipitation": precipitation
	}

static func deserialize(data: Dictionary) -> EnvironmentState:
	"""Deserialize environment state from network or save file"""
	var state = EnvironmentState.new()

	state.wind_direction = data.get("wind_direction", 0)
	state.original_wind_direction = state.wind_direction
	state.wind_speed = data.get("wind_speed", 2)
	state.original_wind_speed = state.wind_speed
	state.wind_speed_change = data.get("wind_speed_change", "steady")
	state.wind_direction_change = data.get("wind_direction_change", "none")
	state.sea_state = data.get("sea_state", 1)
	state.visibility = data.get("visibility", "clear")
	state.time_of_day = data.get("time_of_day", "day")
	state.precipitation = data.get("precipitation", "none")

	return state

func initialize_from_scenario(scenario_data: Dictionary) -> void:
	"""Initialize environment from scenario data"""
	wind_direction = scenario_data.get("wind_direction", 0)
	wind_speed = scenario_data.get("wind_speed", 2)
	wind_speed_change = scenario_data.get("wind_speed_change", "steady")
	region = scenario_data.get("region", "oceanic")
	wind_direction_change = scenario_data.get("wind_direction_change", "none")
	sea_state = scenario_data.get("sea_state", 1)
	visibility = scenario_data.get("visibility", "clear")
	time_of_day = scenario_data.get("time_of_day", "day")
	precipitation = scenario_data.get("precipitation", "none")

	print("EnvironmentState initialized: Environment %s, Wind %s (%d), Speed %s (%d), Sea %s (%d)" % [
		region,
		get_wind_direction_name(), wind_direction,
		get_wind_speed_name(), wind_speed,
		get_sea_state_name(), sea_state
	])
