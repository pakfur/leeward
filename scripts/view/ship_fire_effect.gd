class_name ShipFireEffect
extends Node3D
## ShipFireEffect - procedural flame and smoke on a burning ship (presentation only; crew-tasks
## spec §9 Q6). One flame-and-smoke cluster per fire, spread along the hull (at most MAX_CLUSTERS),
## plus a flickering light. ShipView sets the fire count it reads from the ship's state; this node
## never reads or changes game state.

const MAX_CLUSTERS := 4
const FLAME_COLORS := [Color(1.0, 0.95, 0.6, 0.95), Color(1.0, 0.55, 0.12, 0.85), Color(0.75, 0.12, 0.03, 0.0)]
const SMOKE_COLORS := [Color(0.3, 0.28, 0.26, 1.0), Color(0.22, 0.21, 0.2, 0.9), Color(0.2, 0.2, 0.2, 0.0)]
const LIGHT_COLOR := Color(1.0, 0.5, 0.15)

var fires: int = 0
var ship_length: float = 1.6  ## world units, bow to stern
var deck_height: float = 0.18  ## above the waterline
## Smoke starts here (model space, above the deck): from the near-overhead camera smoke below the
## sails would be hidden for most of its life.
var smoke_height: float = 1.2
## World-space drift of the smoke (downwind); from overhead a straight-up column would sit on the
## ship and hide behind the flames.
var smoke_drift: Vector3 = Vector3(0.6, 0.0, -0.4)
var _clusters: Array[Node3D] = []
var _light: OmniLight3D = null
var _time := 0.0


## Shows `count` fires (0 hides everything). Clusters are added or removed to match.
func set_fires(count: int) -> void:
	fires = maxi(0, count)
	var want := mini(fires, MAX_CLUSTERS)
	while _clusters.size() < want:
		_clusters.append(_make_cluster(_clusters.size()))
	while _clusters.size() > want:
		var c: Node3D = _clusters.pop_back()
		c.queue_free()
	if fires > 0 and _light == null:
		_light = OmniLight3D.new()
		_light.name = "FireLight"
		_light.light_color = LIGHT_COLOR
		_light.omni_range = 2.5
		_light.position = Vector3(0, deck_height + 0.35, 0)
		add_child(_light)
	if _light != null:
		_light.visible = fires > 0
		_light.light_energy = 0.8 + 0.4 * want
	# More fires burn harder: every cluster grows with the count beyond the clusters shown.
	var boost := 1.0 + 0.25 * maxi(0, fires - MAX_CLUSTERS)
	for c in _clusters:
		var flame := c.get_node("Flame") as CPUParticles3D
		flame.amount = int(36 * boost)
		flame.scale_amount_min = 0.7 * boost
		flame.scale_amount_max = 1.2 * boost


func _process(delta: float) -> void:
	if _light == null or not _light.visible:
		return
	_time += delta
	_light.light_energy = (0.8 + 0.4 * _clusters.size()) * (0.85 + 0.15 * sin(_time * 17.0) * cos(_time * 7.3))


## A round soft-edged white dot (radial gradient) for particle quads.
static func soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


## Position along the hull for cluster i: amidships first, then forward and aft.
func _cluster_offset(i: int) -> float:
	var steps := [0.0, 0.28, -0.28, 0.12]
	return steps[i % steps.size()] * ship_length


func _make_cluster(i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire_%d" % i
	root.position = Vector3(0, deck_height, _cluster_offset(i))
	add_child(root)
	var flame := _particles("Flame", FLAME_COLORS, 36, 0.7, Vector3(0, 1.0, 0), 0.3, true)
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flame.emission_box_extents = Vector3(0.15, 0.02, 0.28)
	# Drawn over the sails: from the near-overhead camera the deck is hidden by the canvas, and a
	# burning ship must read at a glance (spec §9 Q6).
	(flame.mesh.material as StandardMaterial3D).no_depth_test = true
	(flame.mesh.material as StandardMaterial3D).render_priority = 2
	root.add_child(flame)
	var smoke := _particles("Smoke", SMOKE_COLORS, 36, 3.2, Vector3(0, 0.5, 0), 0.4, false)
	smoke.position = Vector3(0, maxf(0.25, smoke_height - deck_height), 0)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.08
	smoke.gravity = smoke_drift + Vector3(0, 0.1, 0)  # global: particles use world coordinates
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0, 0.8))
	grow.add_point(Vector2(1, 3.5))
	smoke.scale_amount_curve = grow
	root.add_child(smoke)
	return root


func _particles(node_name: String, colors: Array, amount: int, lifetime: float, velocity: Vector3,
		size: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.direction = velocity.normalized()
	p.spread = 12.0
	p.initial_velocity_min = velocity.length() * 0.6
	p.initial_velocity_max = velocity.length()
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray(colors)
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * 1.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_texture = soft_dot()
	quad.material = mat
	p.mesh = quad
	p.emitting = true
	return p
