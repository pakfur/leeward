class_name EnvironmentController
extends Node
## EnvironmentController - Server-authoritative environment state management
## Uses GameState.rng for deterministic environment changes

signal environment_updated()

var is_server: bool = true
var game_state: Node = null

func _init(state: Node = null, _map: Node3D = null) -> void:
	game_state = state if state else GameState

func _ready():
	Trace.trace_log("Environment", "EnvironmentController initialized (server: %s)" % is_server)

func set_environment_property(property: String, value: Variant) -> bool:
	if not is_server:
		push_error("EnvironmentController: Cannot set property on client")
		return false
	if not game_state or not game_state.environment:
		return false
	game_state.environment.set(property, value)
	environment_updated.emit()
	return true

func tick_environment(env_state: EnvironmentState, _turn_number: int) -> void:
	if not is_server:
		return

	var history: Array[EnvironmentState] = []
	if game_state:
		history = game_state.environment_history

	_update_wind_speed(env_state, game_state.rng, history)
	_update_wind_direction(env_state, game_state.rng, history)
	_update_weather(env_state, game_state.rng, history)

	environment_updated.emit()

func _update_wind_speed(env_state: EnvironmentState, rng: RandomNumberGenerator, history: Array[EnvironmentState]) -> void:
	var original_wind_speed = env_state.wind_speed
	if history.size() > 0 and history[0] != null:
		original_wind_speed = history[0].wind_speed

	var temp_wind_speed = env_state.wind_speed
	var wind_speed_roll = rng.randi_range(1, 10) + rng.randi_range(1, 10)
	var changes_threshold = 4 if env_state.wind_speed_change == "steady" else 6

	if wind_speed_roll < changes_threshold:
		var changes = rng.randi_range(1, 10)
		if changes < 5:
			env_state.wind_speed += 1
		else:
			env_state.wind_speed -= 1
	elif wind_speed_roll > 17:
		if env_state.wind_speed > original_wind_speed:
			env_state.wind_speed -= 1
		if env_state.wind_speed < original_wind_speed:
			env_state.wind_speed += 1

	env_state.wind_speed = clampi(env_state.wind_speed, 0, 4)
	if temp_wind_speed != env_state.wind_speed:
		Trace.trace_log("Environment", "Wind speed changed from %d to %d" % [temp_wind_speed, env_state.wind_speed])

func _update_wind_direction(env_state: EnvironmentState, rng: RandomNumberGenerator, history: Array[EnvironmentState]) -> void:
	var original_wind_direction = env_state.wind_direction
	if history.size() > 0 and history[0] != null:
		original_wind_direction = history[0].wind_direction

	var temp_wind_direction = env_state.wind_direction
	var wind_dir_roll = rng.randi_range(1, 10) + rng.randi_range(1, 10)
	match env_state.region:
		"oceanic":
			if wind_dir_roll < 4:
				var wind_veer_roll = rng.randi_range(1, 10)
				if wind_veer_roll < 6:
					env_state.wind_direction = (env_state.wind_direction - 1 + 6) % 6
				else:
					env_state.wind_direction = (env_state.wind_direction + 1 + 6) % 6
			else:
				if wind_dir_roll > 17:
					if env_state.wind_direction > original_wind_direction:
						env_state.wind_direction = (env_state.wind_direction - 1 + 6) % 6
					else:
						if env_state.wind_direction < original_wind_direction:
							env_state.wind_direction = (env_state.wind_direction + 1 + 6) % 6

		"coastal":
			if wind_dir_roll > 5 && wind_dir_roll < 8:
				var wind_veer_roll = rng.randi_range(1, 10)
				if wind_veer_roll < 6:
					env_state.wind_direction = (env_state.wind_direction - 1 + 6) % 6
				else:
					env_state.wind_direction = (env_state.wind_direction + 1 + 6) % 6
			else:
				if wind_dir_roll > 17:
					if env_state.wind_direction > original_wind_direction:
						env_state.wind_direction = (env_state.wind_direction - 1 + 6) % 6
					else:
						if env_state.wind_direction < original_wind_direction:
							env_state.wind_direction = (env_state.wind_direction + 1 + 6) % 6
	if env_state.wind_direction != temp_wind_direction:
		Trace.trace_log("Environment", "Wind direction changed from %d to %d" % [temp_wind_direction, env_state.wind_direction])

func _update_weather(_env_state: EnvironmentState, _rng: RandomNumberGenerator, _history: Array[EnvironmentState]) -> void:
	pass

func force_update() -> void:
	if not is_server:
		push_error("EnvironmentController: Cannot force_update on client")
		return
	environment_updated.emit()
