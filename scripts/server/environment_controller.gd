class_name EnvironmentController 
extends Node

var rng: RandomNumberGenerator
var is_server: bool = true

func _ready():
	if is_server:
		rng = RandomNumberGenerator.new()
		rng.seed = Time.get_ticks_msec()
		print("EnvironmentController RNG seed: ", rng.seed)

func tick_environment(env_state: EnvironmentState, turn_number: int) -> void:
	"""SERVER ONLY: Update environment with random elements"""
	if not is_server:
		return

	# Generate random values
	var wind_change_chance = rng.randf()
	var weather_roll = rng.randi_range(1, 6)

	# Pass results to the Resource's deterministic methods
	env_state.tick_environment(turn_number, rng)

	# Or add new methods that accept random parameters 
	if wind_change_chance < 0.2:
		env_state.apply_wind_shift(weather_roll)
