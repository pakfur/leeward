class_name ShipExplosionEffect
extends Node3D
## ShipExplosionEffect - a one-shot flash and ring of flying debris where a ship explodes
## (presentation only; crew-tasks spec §9 Q6). Frees itself when done.

const DURATION := 2.6
const FLASH_COLOR := Color(1.0, 0.85, 0.45)

var _flash: MeshInstance3D = null
var _light: OmniLight3D = null
var _t := 0.0


func _ready() -> void:
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	_flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = FLASH_COLOR
	_flash.material_override = mat
	_flash.position = Vector3(0, 0.3, 0)
	_flash.scale = Vector3.ONE * 0.2
	add_child(_flash)
	_light = OmniLight3D.new()
	_light.name = "FlashLight"
	_light.light_color = FLASH_COLOR
	_light.omni_range = 6.0
	_light.light_energy = 8.0
	_light.position = Vector3(0, 0.6, 0)
	add_child(_light)
	add_child(_debris_ring())
	add_child(_fireball())


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / 0.6, 0.0, 1.0)
	if _flash != null:
		_flash.scale = Vector3.ONE * lerpf(0.2, 3.2, k)
		(_flash.material_override as StandardMaterial3D).albedo_color = Color(FLASH_COLOR, 1.0 - k)
		_flash.visible = k < 1.0
	if _light != null:
		_light.light_energy = 8.0 * maxf(0.0, 1.0 - _t / 1.0)
	if _t >= DURATION:
		queue_free()


## Dark planks and spars thrown out in a ring, falling back to the water.
func _debris_ring() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "DebrisRing"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 48
	p.lifetime = 1.8
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.35
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.05
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -6.0, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.03, 0.18)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.09, 0.06)
	mat.roughness = 1.0
	box.material = mat
	p.mesh = box
	p.emitting = true
	return p


## A short-lived ball of flame and smoke at the heart of the blast.
func _fireball() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Fireball"
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 40
	p.lifetime = 1.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.1, 0.8), Color(0.15, 0.13, 0.12, 0)])
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = ShipFireEffect.soft_dot()
	quad.material = mat
	p.mesh = quad
	p.emitting = true
	return p
