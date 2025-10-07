class_name EnvironmentState
extends Resource
## EnvironmentState - Environmental conditions (wind, weather, sea state)
## Pure data representation, deterministic updates, serializable

# Wind
@export var wind_direction: int = 0  # 0-5 representing hex faces (0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE)
@export var wind_speed: int = 2  # 0-5 (0=calm, 1=light, 2=moderate, 3=fresh, 4=strong, 5=gale)
@export var wind_speed_change: String = "steady"  # "steady", "increasing", "decreasing"
@export var wind_direction_change: String = "none"  # "none", "veering", "backing"

# Sea State
@export var sea_state: int = 1  # 0-3 (0=calm, 1=moderate, 2=rough, 3=storm)

# Weather (for future expansion)
@export var visibility: String = "clear"  # "clear", "hazy", "fog", "storm"
@export var time_of_day: String = "day"  # "dawn", "day", "dusk", "night"

# Weather change patterns (optional, for more complex scenarios)
@export var precipitation: String = "none"  # "none", "rain", "snow", "storm"

func tick_environment(turn_number: int) -> void:
	"""Update environment for new turn (deterministic based on turn number)"""
	_update_wind(turn_number)
	_update_sea_state(turn_number)
	_update_weather(turn_number)

func _update_wind(turn_number: int) -> void:
	"""Update wind direction and speed based on change patterns"""
	# Wind direction changes
	match wind_direction_change:
		"veering":  # Clockwise rotation
			if turn_number % 3 == 0:  # Change every 3 turns
				wind_direction = (wind_direction + 1) % 6
				print("Wind veering to direction %d" % wind_direction)
		"backing":  # Counter-clockwise rotation
			if turn_number % 3 == 0:
				wind_direction = (wind_direction - 1 + 6) % 6
				print("Wind backing to direction %d" % wind_direction)

	# Wind speed changes
	match wind_speed_change:
		"increasing":
			if turn_number % 5 == 0 and wind_speed < 5:
				wind_speed += 1
				print("Wind speed increasing to %d" % wind_speed)
		"decreasing":
			if turn_number % 5 == 0 and wind_speed > 0:
				wind_speed -= 1
				print("Wind speed decreasing to %d" % wind_speed)

func _update_sea_state(turn_number: int) -> void:
	"""Update sea state based on wind speed and other factors"""
	# Sea state generally follows wind speed with some lag
	# Simplified: sea_state tends toward wind_speed / 2
	var target_sea_state = clampi(wind_speed / 2, 0, 3)

	if sea_state < target_sea_state:
		# Sea state rising
		if turn_number % 2 == 0:
			sea_state = mini(sea_state + 1, 3)
			print("Sea state rising to %d" % sea_state)
	elif sea_state > target_sea_state:
		# Sea state calming
		if turn_number % 3 == 0:
			sea_state = maxi(sea_state - 1, 0)
			print("Sea state calming to %d" % sea_state)

func _update_weather(turn_number: int) -> void:
	"""Update weather conditions (visibility, precipitation, etc)"""
	# TODO: Implement weather patterns
	# For now, weather is static based on scenario
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
		"sea_state": sea_state,
		"visibility": visibility,
		"time_of_day": time_of_day,
		"precipitation": precipitation
	}

static func deserialize(data: Dictionary) -> EnvironmentState:
	"""Deserialize environment state from network or save file"""
	var state = EnvironmentState.new()

	state.wind_direction = data.get("wind_direction", 0)
	state.wind_speed = data.get("wind_speed", 2)
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
	wind_direction_change = scenario_data.get("wind_direction_change", "none")
	sea_state = scenario_data.get("sea_state", 1)
	visibility = scenario_data.get("visibility", "clear")
	time_of_day = scenario_data.get("time_of_day", "day")
	precipitation = scenario_data.get("precipitation", "none")

	print("EnvironmentState initialized: Wind %s (%d), Speed %s (%d), Sea %s (%d)" % [
		get_wind_direction_name(), wind_direction,
		get_wind_speed_name(), wind_speed,
		get_sea_state_name(), sea_state
	])
