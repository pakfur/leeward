class_name EnvironmentController
extends Node
## EnvironmentController - Manages environment state and visuals
## Uses GameState.rng for deterministic environment changes; updates water shader based on conditions

signal environment_updated()

var is_server: bool = true
var hex_map: Node3D = null  # Reference to HexMap for accessing ocean_material
var game_state: Node = null  # Reference to GameState for accessing environment

# Constants for wind direction (hex facing)
const HEX_DIRECTIONS = {
	0: Vector2(1.0, 0.0),      # E
	1: Vector2(0.5, 0.866),    # SE  (sqrt(3)/2 ≈ 0.866)
	2: Vector2(-0.5, 0.866),   # SW
	3: Vector2(-1.0, 0.0),     # W
	4: Vector2(-0.5, -0.866),  # NW
	5: Vector2(0.5, -0.866)    # NE
}

func _init(state: Node = null, map: Node3D = null) -> void:
	game_state = state if state else GameState
	hex_map = map

func _ready():
	# Connect to phase changes
	if game_state:
		game_state.phase_changed.connect(_on_phase_changed)

	print("EnvironmentController initialized (server: %s)" % is_server)

func set_hex_map(map: Node3D) -> void:
	"""Set the hex map reference (needed if not passed in constructor)"""
	hex_map = map

func _on_phase_changed(phase: int) -> void:
	"""Handle phase changes - update shader on ENVIRONMENT phase"""
	# GamePhase.ENVIRONMENT = 1
	if phase == 1:  # ENVIRONMENT phase
		update_water_shader()

func tick_environment(env_state: EnvironmentState, turn_number: int) -> void:
	"""SERVER ONLY: Update environment with random elements"""
	if not is_server:
		return

	# Get environment history from game state
	var history: Array[EnvironmentState] = []
	if game_state:
		history = game_state.environment_history

	# Pass results to the Resource's deterministic methods
	# Include history array (passed by reference, no performance cost)
	env_state.tick_environment(turn_number, game_state.rng, history)

	# After environment state is updated, update the shader
	update_water_shader()

func update_water_shader() -> void:
	"""Update water shader parameters based on current environment state"""
	if not hex_map or not game_state or not game_state.environment:
		push_warning("EnvironmentController: Cannot update shader - missing references")
		return

	var ocean_material = hex_map.ocean_material as ShaderMaterial
	if not ocean_material:
		push_error("EnvironmentController: No ocean material found on HexMap")
		return

	var env = game_state.environment

	# Get wind and sea parameters
	var wind_dir = env.wind_direction  # 0-5
	var wind_speed = env.wind_speed    # 0-5
	var sea_state = env.sea_state      # 0-3

	# Update shader parameters
	_update_wave_parameters(ocean_material, wind_dir, wind_speed, sea_state)
	_update_wave_speed(ocean_material, wind_speed, sea_state)

	environment_updated.emit()

	print("EnvironmentController: Updated water shader - Wind: %s (%d), Speed: %s (%d), Sea: %s (%d)" % [
		env.get_wind_direction_name(), wind_dir,
		env.get_wind_speed_name(), wind_speed,
		env.get_sea_state_name(), sea_state
	])

func _update_wave_parameters(material: ShaderMaterial, wind_dir: int, wind_speed: int, sea_state: int) -> void:
	"""Update wave direction and amplitude based on wind and sea state"""

	# Get base wind direction vector
	var wind_vec = HEX_DIRECTIONS.get(wind_dir, Vector2(1.0, 0.0))

	# Calculate wave amplitude based on wind speed and sea state
	# Base amplitude ranges from 0.05 (calm) to 0.35 (storm)
	var base_amplitude = 0.05 + (wind_speed * 0.03) + (sea_state * 0.05)

	# Calculate wave frequency based on sea state
	# Higher sea state = longer wavelengths (lower frequency)
	var base_frequency = 1.0 - (sea_state * 0.15)

	# Update primary wave (wave_1) - aligned with wind direction
	var wave_1 = Vector4(
		wind_vec.x * 2.0,           # direction.x (scaled for effect)
		wind_vec.y * 2.0,           # direction.y
		base_amplitude * 0.2,       # amplitude (steepness)
		base_frequency * 0.8        # wavelength
	)
	material.set_shader_parameter("wave_1", wave_1)

	# Update secondary wave (wave_3) - slightly offset from wind direction
	var angle_offset_1 = 30.0  # degrees
	var rotated_vec_1 = _rotate_vector2(wind_vec, angle_offset_1)
	var wave_3 = Vector4(
		rotated_vec_1.x * 1.5,
		rotated_vec_1.y * 1.5,
		base_amplitude * 0.15,
		base_frequency * 0.6
	)
	material.set_shader_parameter("wave_3", wave_3)

	# Update tertiary wave (wave_5) - cross waves
	var angle_offset_2 = -45.0
	var rotated_vec_2 = _rotate_vector2(wind_vec, angle_offset_2)
	var wave_5 = Vector4(
		rotated_vec_2.x * 1.2,
		rotated_vec_2.y * 1.2,
		base_amplitude * 0.1,
		base_frequency * 1.2
	)
	material.set_shader_parameter("wave_5", wave_5)

	# Update wave 7 - larger swell
	var wave_7 = Vector4(
		wind_vec.x * 1.0,
		wind_vec.y * 1.0,
		base_amplitude * 0.18,
		base_frequency * 1.5
	)
	material.set_shader_parameter("wave_7", wave_7)

	# Keep other waves (2, 4, 6, 8) with smaller amplitudes for detail
	# These create texture variation without dominating the direction
	material.set_shader_parameter("wave_2", Vector4(-0.3, -0.2, base_amplitude * 0.02, 0.5))
	material.set_shader_parameter("wave_4", Vector4(0.2, -0.4, base_amplitude * 0.08, 0.4))
	material.set_shader_parameter("wave_6", Vector4(0.8, 0.3, base_amplitude * 0.03, 0.4))
	material.set_shader_parameter("wave_8", Vector4(-0.3, 0.5, base_amplitude * 0.12, 0.6))

func _update_wave_speed(material: ShaderMaterial, wind_speed: int, sea_state: int) -> void:
	"""Update wave animation speed based on wind and sea conditions"""

	# time_factor controls overall wave speed
	# Lower = faster waves, Higher = slower waves
	# Calm: 3.5 (slow), Gale: 1.5 (fast)
	var time_factor = 3.5 - (wind_speed * 0.25) - (sea_state * 0.15)
	time_factor = clamp(time_factor, 1.5, 3.5)

	material.set_shader_parameter("time_factor", time_factor)

	# Adjust noise amplitude for rougher seas
	var noise_amp = 0.05 + (sea_state * 0.03)
	material.set_shader_parameter("noise_amp", noise_amp)

func _rotate_vector2(vec: Vector2, angle_deg: float) -> Vector2:
	"""Rotate a 2D vector by angle in degrees"""
	var angle_rad = deg_to_rad(angle_deg)
	var cos_a = cos(angle_rad)
	var sin_a = sin(angle_rad)
	return Vector2(
		vec.x * cos_a - vec.y * sin_a,
		vec.x * sin_a + vec.y * cos_a
	)

func force_update() -> void:
	"""Manually trigger a shader update (for testing or initial setup)"""
	update_water_shader()
