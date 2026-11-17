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
# The scenario's starting wind; high wind rolls step the wind back toward it
@export var original_wind_direction: int = 0
@export var original_wind_speed: int = 2
# A change rolled this turn takes effect at the start of next turn's weather phase (3.B.6).
# -1 = no change pending.
@export var pending_wind_direction: int = -1
@export var pending_wind_speed: int = -1
# The turn a calm ended (wind speed rose from 0, 3.B.6); -1 = none. Ships at WF=L are not in
# irons in that g-t (3.D.4, 5.D.4c).
@export var calm_ended_turn: int = -1

# Sea State
# 0-5: 0 calm (an extension, no rule effect), 1-5 as the Sea State chart (3.B.5).
const SEA_STATE_MAX := 5
const SEA_STATE_NAMES := ["calm", "slight", "moderate", "rough", "very rough", "high"]
@export var sea_state: int = 1

# Weather (for future expansion)
@export var visibility: String = "clear"  # "clear", "hazy", "fog", "storm"
@export var time_of_day: String = "day"  # "dawn", "day", "dusk", "night"

# Weather change patterns (optional, for more complex scenarios)
@export var precipitation: String = "none"  # "none", "rain", "snow", "storm"

## True in the g-t the wind rose from a calm: no ship is in irons then (3.D.4, 5.D.4c).
func calm_just_ended(turn: int) -> bool:
	return calm_ended_turn >= 0 and calm_ended_turn == turn


func has_pending_wind_change() -> bool:
	return pending_wind_direction >= 0 or pending_wind_speed >= 0

func get_wind_direction_name() -> String:
	"""Get human-readable wind direction"""
	var directions = ["E", "SE", "SW", "W", "NW", "NE"]
	return directions[wind_direction]

func get_wind_speed_name() -> String:
	"""Get human-readable wind speed"""
	return wind_speed_name(wind_speed)

const WIND_SPEED_NAMES := ["Calm", "Light", "Moderate", "Fresh", "Strong", "Gale"]

static func wind_speed_name(speed: int) -> String:
	return WIND_SPEED_NAMES[speed] if speed >= 0 and speed < WIND_SPEED_NAMES.size() else "?"

static func sea_state_name(sea: int) -> String:
	return SEA_STATE_NAMES[clampi(sea, 0, SEA_STATE_MAX)]

## Scenario and saved values are held to 0-5.
static func clamp_sea_state(sea: int) -> int:
	return clampi(sea, 0, SEA_STATE_MAX)

func get_sea_state_name() -> String:
	"""Get human-readable sea state"""
	return sea_state_name(sea_state)

func serialize() -> Dictionary:
	"""Serialize environment state for network transmission or save/load"""
	return {
		"wind_direction": wind_direction,
		"wind_speed": wind_speed,
		"wind_speed_change": wind_speed_change,
		"wind_direction_change": wind_direction_change,
		"region": region,
		"original_wind_direction": original_wind_direction,
		"original_wind_speed": original_wind_speed,
		"pending_wind_direction": pending_wind_direction,
		"pending_wind_speed": pending_wind_speed,
		"calm_ended_turn": calm_ended_turn,
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
	state.original_wind_direction = data.get("original_wind_direction", state.wind_direction)
	state.original_wind_speed = data.get("original_wind_speed", state.wind_speed)
	state.pending_wind_direction = data.get("pending_wind_direction", -1)
	state.pending_wind_speed = data.get("pending_wind_speed", -1)
	state.calm_ended_turn = data.get("calm_ended_turn", -1)
	state.sea_state = clamp_sea_state(int(data.get("sea_state", 1)))
	state.visibility = data.get("visibility", "clear")
	state.time_of_day = data.get("time_of_day", "day")
	state.precipitation = data.get("precipitation", "none")

	return state

func initialize_from_scenario(scenario_data: Dictionary) -> void:
	## One-time setup during game init, called from GameState.start_new_game() (guarded by is_server).  SCV:ALLOW
	wind_direction = scenario_data.get("wind_direction", 0)
	wind_speed = scenario_data.get("wind_speed", 2)
	original_wind_direction = wind_direction
	original_wind_speed = wind_speed
	wind_speed_change = scenario_data.get("wind_speed_change", "steady")
	region = scenario_data.get("region", "oceanic")
	wind_direction_change = scenario_data.get("wind_direction_change", "none")
	sea_state = clamp_sea_state(int(scenario_data.get("sea_state", 1)))
	visibility = scenario_data.get("visibility", "clear")
	time_of_day = scenario_data.get("time_of_day", "day")
	precipitation = scenario_data.get("precipitation", "none")

	Trace.trace_log("Environment", "EnvironmentState initialized: %s, Wind %s (%d), Speed %s (%d), Sea %s (%d)" % [
		region,
		get_wind_direction_name(), wind_direction,
		get_wind_speed_name(), wind_speed,
		get_sea_state_name(), sea_state
	])
