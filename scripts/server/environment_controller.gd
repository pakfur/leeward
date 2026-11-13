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

	_update_wind_speed(env_state, history)
	_update_wind_direction(env_state, history)
	_update_weather(env_state, game_state.rng, history)

	environment_updated.emit()

func _update_wind_speed(env_state: EnvironmentState, history: Array[EnvironmentState]) -> void:
	var dice: Dice = game_state.dice
	var original_wind_speed = env_state.wind_speed
	if history.size() > 0 and history[0] != null:
		original_wind_speed = history[0].wind_speed

	var temp_wind_speed = env_state.wind_speed
	var wind_speed_roll = dice.two_d10()
	var changes_threshold = 1 if env_state.wind_speed_change == "steady" else 3

	if wind_speed_roll <= changes_threshold:
		# Chart follow-up d10: 0-4 decreases, 5-9 increases
		if dice.d10() <= 4:
			env_state.wind_speed -= 1
		else:
			env_state.wind_speed += 1
	elif wind_speed_roll >= 16:
		if env_state.wind_speed > original_wind_speed:
			env_state.wind_speed -= 1
		if env_state.wind_speed < original_wind_speed:
			env_state.wind_speed += 1

	env_state.wind_speed = clampi(env_state.wind_speed, 0, 4)
	if temp_wind_speed != env_state.wind_speed:
		Trace.trace_log("Environment", "Wind speed changed from %d to %d" % [temp_wind_speed, env_state.wind_speed])

func _update_wind_direction(env_state: EnvironmentState, history: Array[EnvironmentState]) -> void:
	var dice: Dice = game_state.dice
	var original_wind_direction = env_state.wind_direction
	if history.size() > 0 and history[0] != null:
		original_wind_direction = history[0].wind_direction

	var temp_wind_direction = env_state.wind_direction
	var wind_dir_roll = dice.two_d10()
	var changes := false
	match env_state.region:
		"oceanic":
			changes = wind_dir_roll <= 1
		"coastal":
			changes = wind_dir_roll >= 2 and wind_dir_roll <= 3

	if changes:
		# Chart follow-up d10: 0-4 veers left, 5-9 veers right
		if dice.d10() <= 4:
			env_state.wind_direction = (env_state.wind_direction - 1 + 6) % 6
		else:
			env_state.wind_direction = (env_state.wind_direction + 1 + 6) % 6
	elif wind_dir_roll >= 16:
		if env_state.wind_direction > original_wind_direction:
			env_state.wind_direction = (env_state.wind_direction - 1 + 6) % 6
		elif env_state.wind_direction < original_wind_direction:
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
