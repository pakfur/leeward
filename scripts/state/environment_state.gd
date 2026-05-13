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
	state.wind_speed = data.get("wind_speed", 2)
	state.wind_speed_change = data.get("wind_speed_change", "steady")
	state.wind_direction_change = data.get("wind_direction_change", "none")
	state.region = data.get("region", "oceanic")
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

	Trace.trace_log("Environment", "EnvironmentState initialized: %s, Wind %s (%d), Speed %s (%d), Sea %s (%d)" % [
		region,
		get_wind_direction_name(), wind_direction,
		get_wind_speed_name(), wind_speed,
		get_sea_state_name(), sea_state
	])
