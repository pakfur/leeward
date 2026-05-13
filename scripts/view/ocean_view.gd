class_name OceanView
extends Node
## OceanView - Updates water shader based on environment state
## Listens to EnvironmentController.environment_updated signal

var hex_map: Node3D = null
var game_state: Node = null

const HEX_DIRECTIONS = {
	0: Vector2(1.0, 0.0),      # E
	1: Vector2(0.5, 0.866),    # SE
	2: Vector2(-0.5, 0.866),   # SW
	3: Vector2(-1.0, 0.0),     # W
	4: Vector2(-0.5, -0.866),  # NW
	5: Vector2(0.5, -0.866)    # NE
}

func _init(p_game_state: Node = null, p_hex_map: Node3D = null) -> void:
	game_state = p_game_state if p_game_state else GameState
	hex_map = p_hex_map

func set_hex_map(map: Node3D) -> void:
	hex_map = map

func connect_to_controller(controller: EnvironmentController) -> void:
	controller.environment_updated.connect(update_water_shader)

func update_water_shader() -> void:
	if not hex_map or not game_state or not game_state.environment:
		return

	var ocean_material = hex_map.ocean_material as ShaderMaterial
	if not ocean_material:
		push_error("OceanView: No ocean material found on HexMap")
		return

	var env = game_state.environment
	var wind_dir = env.wind_direction
	var wind_speed = env.wind_speed
	var sea_state = env.sea_state

	_update_wave_parameters(ocean_material, wind_dir, wind_speed, sea_state)
	_update_wave_speed(ocean_material, wind_speed, sea_state)

	Trace.trace_log("Environment", "Updated water shader - Wind: %s (%d), Speed: %s (%d), Sea: %s (%d)" % [
		env.get_wind_direction_name(), wind_dir,
		env.get_wind_speed_name(), wind_speed,
		env.get_sea_state_name(), sea_state
	])

func _update_wave_parameters(material: ShaderMaterial, wind_dir: int, wind_speed: int, sea_state: int) -> void:
	var wind_vec = HEX_DIRECTIONS.get(wind_dir, Vector2(1.0, 0.0))
	var base_amplitude = 0.05 + (wind_speed * 0.03) + (sea_state * 0.05)
	var base_frequency = 1.0 - (sea_state * 0.15)

	var wave_1 = Vector4(
		wind_vec.x * 2.0,
		wind_vec.y * 2.0,
		base_amplitude * 0.2,
		base_frequency * 0.8
	)
	material.set_shader_parameter("wave_1", wave_1)

	var rotated_vec_1 = _rotate_vector2(wind_vec, 30.0)
	var wave_3 = Vector4(
		rotated_vec_1.x * 1.5,
		rotated_vec_1.y * 1.5,
		base_amplitude * 0.15,
		base_frequency * 0.6
	)
	material.set_shader_parameter("wave_3", wave_3)

	var rotated_vec_2 = _rotate_vector2(wind_vec, -45.0)
	var wave_5 = Vector4(
		rotated_vec_2.x * 1.2,
		rotated_vec_2.y * 1.2,
		base_amplitude * 0.1,
		base_frequency * 1.2
	)
	material.set_shader_parameter("wave_5", wave_5)

	var wave_7 = Vector4(
		wind_vec.x * 1.0,
		wind_vec.y * 1.0,
		base_amplitude * 0.18,
		base_frequency * 1.5
	)
	material.set_shader_parameter("wave_7", wave_7)

	material.set_shader_parameter("wave_2", Vector4(-0.3, -0.2, base_amplitude * 0.02, 0.5))
	material.set_shader_parameter("wave_4", Vector4(0.2, -0.4, base_amplitude * 0.08, 0.4))
	material.set_shader_parameter("wave_6", Vector4(0.8, 0.3, base_amplitude * 0.03, 0.4))
	material.set_shader_parameter("wave_8", Vector4(-0.3, 0.5, base_amplitude * 0.12, 0.6))

func _update_wave_speed(material: ShaderMaterial, wind_speed: int, sea_state: int) -> void:
	var time_factor = 3.5 - (wind_speed * 0.25) - (sea_state * 0.15)
	time_factor = clamp(time_factor, 1.5, 3.5)
	material.set_shader_parameter("time_factor", time_factor)

	var noise_amp = 0.05 + (sea_state * 0.03)
	material.set_shader_parameter("noise_amp", noise_amp)

func _rotate_vector2(vec: Vector2, angle_deg: float) -> Vector2:
	var angle_rad = deg_to_rad(angle_deg)
	var cos_a = cos(angle_rad)
	var sin_a = sin(angle_rad)
	return Vector2(
		vec.x * cos_a - vec.y * sin_a,
		vec.x * sin_a + vec.y * cos_a
	)
