class_name WaveCalculator
extends RefCounted
## WaveCalculator - Calculates wave heights matching the ocean shader

# Wave parameters (matching shader defaults)
var waves: Array[Vector4] = [
	Vector4(0.3, 6.0, 0.2, 0.6),
	Vector4(-0.26, -0.19, 0.01, 0.47),
	Vector4(-14.67, 8.63, 0.1, 0.38),
	Vector4(-0.42, -1.63, 0.1, 0.28),
	Vector4(1.66, 0.07, 0.15, 1.81),
	Vector4(1.2, 1.14, 0.01, 0.33),
	Vector4(-1.6, 7.3, 0.11, 0.73),
	Vector4(-0.42, -1.63, 0.15, 1.52)
]

var time_factor: float = 2.5
var noise_zoom: float = 2.0
var noise_amp: float = 0.05

# Hash function for noise (matching shader's fract)
func hash(p: Vector2) -> float:
	var val = sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return val - floor(val)  # fract equivalent

# 2D noise function
func noise(x: Vector2) -> float:
	var p = x.floor()
	var f = Vector2(x.x - floor(x.x), x.y - floor(x.y))  # fract equivalent
	f = Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))

	var a = Vector2(1.0, 0.0)
	return lerp(
		lerp(hash(p + Vector2(0, 0)), hash(p + Vector2(1, 0)), f.x),
		lerp(hash(p + Vector2(0, 1)), hash(p + Vector2(1, 1)), f.x),
		f.y
	)

# Fractional Brownian Motion
func fbm(x: Vector2) -> float:
	var height = 0.0
	var amplitude = 0.5
	var frequency = 3.0
	for i in range(6):
		height += noise(x * frequency) * amplitude
		amplitude *= 0.5
		frequency *= 2.0
	return height

# Dynamic amplitude based on position and time
func dynamic_amplitude(pos: Vector2, time: float) -> float:
	return 1.0 + 0.5 * sin(time + pos.length() * 0.1)

# Single Gerstner wave calculation
func gerstner_wave(wave_params: Vector4, pos: Vector2, time: float) -> Vector3:
	var steepness = wave_params.z * dynamic_amplitude(pos, time)
	var wavelength = wave_params.w

	# Prevent division by zero or tiny wavelengths
	if wavelength < 0.01:
		return Vector3.ZERO

	var k = 2.0 * PI / wavelength
	var c = sqrt(9.81 / k)
	var d = Vector2(wave_params.x, wave_params.y).normalized()
	var f = k * (d.dot(pos) - c * time)
	var a = steepness / k

	# Clamp amplitude to reasonable values
	a = clamp(a, -2.0, 2.0)

	return Vector3(
		d.x * (a * cos(f)),
		a * sin(f),
		d.y * (a * cos(f))
	)

# Calculate total wave displacement at a position
func get_wave_displacement(world_pos: Vector3, current_time: float) -> Vector3:
	var pos = Vector2(world_pos.x, world_pos.z)
	var time = current_time / time_factor
	var displacement = Vector3.ZERO

	# Sum all 8 waves
	for wave in waves:
		var wave_displacement = gerstner_wave(wave, pos, time)
		displacement += wave_displacement

	# Add noise (temporarily disabled for debugging)
	#displacement.y += fbm(pos * (noise_zoom / 50.0)) * noise_amp

	# Clamp total displacement to reasonable values
	displacement.x = clamp(displacement.x, -5.0, 5.0)
	displacement.y = clamp(displacement.y, -2.0, 2.0)
	displacement.z = clamp(displacement.z, -5.0, 5.0)

	return displacement

# Get just the height (Y component) at a position
func get_wave_height(world_pos: Vector3, current_time: float) -> float:
	return get_wave_displacement(world_pos, current_time).y

# Calculate wave normal for tilting
func get_wave_normal(world_pos: Vector3, current_time: float, sample_distance: float = 0.1) -> Vector3:
	var center = get_wave_height(world_pos, current_time)
	var dx = get_wave_height(world_pos + Vector3(sample_distance, 0, 0), current_time) - center
	var dz = get_wave_height(world_pos + Vector3(0, 0, sample_distance), current_time) - center

	var tangent = Vector3(sample_distance, dx, 0).normalized()
	var bitangent = Vector3(0, dz, sample_distance).normalized()

	return tangent.cross(bitangent).normalized()
