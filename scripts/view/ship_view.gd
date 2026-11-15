class_name ShipView
extends Node3D
## ShipView - Visual representation of a ship (presentation only, no game state)

@warning_ignore("unused_signal")  # Connected externally (game_controller); emitted only by 3D click handling
signal selected()

var state_id: String = ""  # Reference to ShipState in GameState
var model_node: Node3D
# Wave interaction (visual only, not part of game state)
var wave_calculator: WaveCalculator
var base_position: Vector3  # Position without wave offset
var hex_grid_ref: HexGrid = null
var _struck_flag: MeshInstance3D = null  # white flag shown while the ship is struck

## Owner colours, shared with the minimap: green = the human player's ships, red = the enemy's.
const PLAYER_COLOR := Color(0.183, 0.927, 0.479)
const ENEMY_COLOR := Color(1.0, 0.3, 0.3)
const HUMAN_PLAYER_ID := 0
## Above the fire arcs and the target outline drawn by HexOverlay, so the owner always shows.
const OWNER_RING_RENDER_PRIORITY := 3
const OWNER_RING_MID_RADIUS := 0.75  # torus centre line (inner 0.68, outer 0.82), before stretching
const OWNER_RING_CLEARANCE := 0.2    # water between the bow or stern and the ring
var _owner_ring: MeshInstance3D = null   # coloured ring on the water around the ship
var _owner_pennant: MeshInstance3D = null  # coloured pennant at the masthead (hidden when struck)
var _owner_player_id: int = -1
var _spec: ProceduralShipSpec = null  # placeholder model shape, from the ship's data
var _rigging_level: int = 4  # last synced, so the pennant and flag sit on a standing mast

## Wreck look for a destroyed ship (hull #12 explosion): charred, dismasted, settled low with a
## heel, and a few pieces of floating debris in its hexes. Built once, never undone.
const WRECK_CHAR_COLOR := Color(0.05, 0.045, 0.04)
const WRECK_CHAR_AMOUNT := 0.85
const WRECK_SINK := 0.12          # how far the hull settles (world units)
const WRECK_HEEL_DEG := 14.0      # list to one side
const WRECK_TRIM_DEG := 5.0       # bow down
const WRECK_DEBRIS_COUNT := 7
const WRECK_DEBRIS_COLOR := Color(0.13, 0.10, 0.07)
var _wrecked := false
var _wreck_debris: Node3D = null

static func owner_color(player_id: int) -> Color:
	"""Owner colour for a player id (matches the minimap ship icons)."""
	return PLAYER_COLOR if player_id == HUMAN_PLAYER_ID else ENEMY_COLOR

func _ready() -> void:
	wave_calculator = WaveCalculator.new()

func _process(_delta: float) -> void:
	# Visual update only - wave bobbing
	if wave_calculator != null:
		_update_wave_position()

func initialize(ship_state: ShipState, hex_grid: HexGrid) -> void:
	"""Initialize view from state"""
	state_id = ship_state.ship_id
	hex_grid_ref = hex_grid

	# Placeholder model built from the ship's data (rating, class) and its footprint
	_create_ship_model(ship_state)

	# Sync to initial state
	sync_to_state(ship_state, hex_grid)

func sync_to_state(ship_state: ShipState, hex_grid: HexGrid) -> void:
	"""Update visual representation to match state"""
	state_id = ship_state.ship_id
	hex_grid_ref = hex_grid

	# Update position
	_update_position_from_state(ship_state, hex_grid)

	# Owner marker (ring + pennant) in the owner's colour; before the rotation, which turns the ring
	_update_owner_marker(ship_state.player_id)

	# Update rotation
	_update_rotation_from_state(ship_state)

	if ship_state.is_destroyed():
		_apply_wreck(ship_state)
		return

	# Masts still standing and sails set; the pennant flies from the highest mast left
	if _spec:
		_rigging_level = ship_state.rigging_level()
		ProceduralShipBuilder.apply_state(model_node, _spec, ship_state.sail_state, _rigging_level)

	# Struck ships look different (flag + desaturated); the ring keeps the owner's colour
	_update_struck_visual(ship_state.is_struck())
	if _owner_pennant:
		_owner_pennant.visible = not ship_state.is_struck()
		_owner_pennant.position = _masthead_position(0.24)
	if _struck_flag:
		_struck_flag.position = _masthead_position(0.3) - Vector3(0, 0.1, 0)

func _update_owner_marker(player_id: int) -> void:
	"""Create (once) or recolour the owner ring and pennant for player_id."""
	if model_node == null or player_id == _owner_player_id:
		return
	_owner_player_id = player_id
	var color := owner_color(player_id)
	if _owner_ring == null:
		_owner_ring = MeshInstance3D.new()
		_owner_ring.name = "OwnerRing"
		var ring := TorusMesh.new()
		ring.inner_radius = 0.68
		ring.outer_radius = 0.82
		ring.rings = 48
		_owner_ring.mesh = ring
		# Flatten onto the water and stretch along the keel (local Z, turned with the hull in
		# _sync_ring_heading) so the ring goes round the whole two-hex hull with a little water clear.
		var keel_reach := (_spec.length * 0.5 + OWNER_RING_CLEARANCE) if _spec else OWNER_RING_MID_RADIUS
		_owner_ring.scale = Vector3(1.0, 0.15, maxf(1.0, keel_reach / OWNER_RING_MID_RADIUS))
		_owner_ring.position = Vector3(0, 0.12, 0)
		var ring_material := StandardMaterial3D.new()
		ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_material.no_depth_test = true  # stays visible over wave crests at any zoom
		ring_material.render_priority = OWNER_RING_RENDER_PRIORITY
		_owner_ring.material_override = ring_material
		add_child(_owner_ring)  # on the ship root, not the model: it does not tilt with the hull
	(_owner_ring.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 0.9)
	if _owner_pennant == null:
		_owner_pennant = MeshInstance3D.new()
		_owner_pennant.name = "OwnerPennant"
		var pennant := BoxMesh.new()
		pennant.size = Vector3(0.02, 0.12, 0.3)
		_owner_pennant.mesh = pennant
		_owner_pennant.position = _masthead_position(0.24)  # streaming aft
		var pennant_material := StandardMaterial3D.new()
		pennant_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_owner_pennant.material_override = pennant_material
		model_node.add_child(_owner_pennant)
	(_owner_pennant.material_override as StandardMaterial3D).albedo_color = color

func _update_struck_visual(struck: bool) -> void:
	"""Show a white flag and desaturate the model while the ship is struck; undo it otherwise."""
	if model_node == null or struck == (_struck_flag != null):
		return
	for child in model_node.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null or mesh == _struck_flag or mesh == _owner_pennant:
			continue
		var material := mesh.material_override as StandardMaterial3D
		if material == null:
			continue
		if struck:
			material.set_meta("unstruck_color", material.albedo_color)
			var gray := material.albedo_color.get_luminance()
			material.albedo_color = material.albedo_color.lerp(Color(gray, gray, gray), 0.8)
		elif material.has_meta("unstruck_color"):
			material.albedo_color = material.get_meta("unstruck_color")
	if struck:
		_struck_flag = MeshInstance3D.new()
		_struck_flag.name = "StruckFlag"
		var flag_mesh := BoxMesh.new()
		flag_mesh.size = Vector3(0.04, 0.35, 0.5)
		_struck_flag.mesh = flag_mesh
		var flag_material := StandardMaterial3D.new()
		flag_material.albedo_color = Color(1, 1, 1)
		flag_material.emission_enabled = true
		flag_material.emission = Color(0.9, 0.9, 0.9)
		_struck_flag.material_override = flag_material
		_struck_flag.position = _masthead_position(0.3) - Vector3(0, 0.1, 0)
		model_node.add_child(_struck_flag)
	else:
		_struck_flag.queue_free()
		_struck_flag = null

func is_wrecked() -> bool:
	return _wrecked

func _apply_wreck(ship_state: ShipState) -> void:
	"""Swap to the wreck look (once): masts down to the stumps, no sails, the hull charred, the
	owner markers and struck flag removed, a few dark debris pieces on the water."""
	if _wrecked or model_node == null:
		return
	_wrecked = true
	if _spec:
		_rigging_level = 0
		ProceduralShipBuilder.apply_state(model_node, _spec, "NS", 0)
	if _struck_flag:
		model_node.remove_child(_struck_flag)
		_struck_flag.queue_free()
		_struck_flag = null
	if _owner_pennant:
		_owner_pennant.visible = false
	if _owner_ring:
		_owner_ring.visible = false
	for child in model_node.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		var material := mesh.material_override as StandardMaterial3D
		if material:
			material.albedo_color = material.albedo_color.lerp(WRECK_CHAR_COLOR, WRECK_CHAR_AMOUNT)
			material.emission_enabled = false
	_build_debris(ship_state)

func _build_debris(ship_state: ShipState) -> void:
	"""A few flat planks on the water around the hull, inside its two hexes. Placement is seeded by
	the ship id so the wreck looks the same every time it is rebuilt."""
	_wreck_debris = Node3D.new()
	_wreck_debris.name = "WreckDebris"
	add_child(_wreck_debris)  # on the ship root: stays flat on the water, does not heel with the hull
	_wreck_debris.rotation_degrees = Vector3(0, -ship_state.facing * 60.0 - 90.0, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = WRECK_DEBRIS_COLOR
	material.roughness = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ship_state.ship_id)
	var reach := (_spec.length * 0.5) if _spec else 0.8
	var beam := _spec.beam if _spec else 0.34
	for i in range(WRECK_DEBRIS_COUNT):
		var plank := MeshInstance3D.new()
		plank.name = "Debris_%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(0.05, 0.1), 0.025, rng.randf_range(0.14, 0.32))
		plank.mesh = box
		plank.material_override = material
		var side := -1.0 if i % 2 == 0 else 1.0
		plank.position = Vector3(side * rng.randf_range(beam * 0.8, beam * 1.8), 0.03,
				rng.randf_range(-reach, reach))
		plank.rotation_degrees = Vector3(0, rng.randf_range(0.0, 180.0), rng.randf_range(-8.0, 8.0))
		_wreck_debris.add_child(plank)

func _update_position_from_state(ship_state: ShipState, hex_grid: HexGrid) -> void:
	"""Calculate and set position based on ship state"""
	# The model is centred midway between its bow hex (hex_position) and its stern hex.
	base_position = hex_grid.ship_center_world(ship_state.hex_position, ship_state.facing)

	base_position.y = 0.0  # Ship center at waterline, hull extends above/below
	_update_wave_position()

func _update_rotation_from_state(ship_state: ShipState) -> void:
	"""Update the 3D rotation based on state"""
	# Each hex face is 60 degrees, facing 0 is east. The model's bow is local -Z; a Y rotation
	# of -(60f + 90) degrees points it along HexGrid.DIRECTIONS[f] in world space
	# (f=0 -> +X/east, f=1 -> south-east), which reads correctly with the north-up camera.
	var angle_deg = -ship_state.facing * 60.0 - 90.0
	if model_node:
		model_node.rotation_degrees = Vector3(0, angle_deg, 0)
	_sync_ring_heading()

func _sync_ring_heading() -> void:
	"""Turn the owner ring with the hull (heading only: it stays flat on the water)."""
	if _owner_ring and model_node:
		_owner_ring.rotation_degrees = Vector3(0, model_node.rotation_degrees.y, 0)

func _create_ship_model(ship_state: ShipState) -> void:
	"""Build the procedural placeholder model for this ship."""
	model_node = Node3D.new()
	add_child(model_node)
	_spec = ProceduralShipSpec.for_ship(ship_state.ship, ship_state.get_ship_size())
	ProceduralShipBuilder.build(_spec, model_node)
	_add_click_collision()

func _masthead_position(aft: float) -> Vector3:
	"""Just above the main masthead, `aft` behind the mast (model space)."""
	if _spec == null:
		return Vector3(0, 1.4, aft)
	return Vector3(0, _spec.standing_masthead_y(_rigging_level) + 0.05, _spec.mast_z[_spec.main_mast()] + aft)

func _add_click_collision() -> void:
	"""Add a static body so the camera raycast in game_controller can pick this ship. The box runs
	the hull's length (into both hexes) and sits on the model, so it turns with the keel."""
	var body := StaticBody3D.new()
	body.name = "ClickBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, _spec.masthead_y(), _spec.length + 0.5)
	shape.shape = box
	shape.position = Vector3(0, _spec.masthead_y() / 2.0, 0)
	body.add_child(shape)
	model_node.add_child(body)

func _update_wave_position() -> void:
	"""Update ship position and rotation based on wave motion (visual only)"""
	if wave_calculator == null:
		position = base_position
		return

	var current_time = Time.get_ticks_msec() / 1000.0

	# Get wave displacement at ship position
	var wave_offset = wave_calculator.get_wave_displacement(base_position, current_time)

	# Dampen the wave motion by 70% (reduce amplitude to 30% of original)
	var damping_factor = 0.3
	wave_offset *= damping_factor

	# Apply dampened wave height to ship position
	position = base_position + wave_offset
	if _wrecked and model_node:
		model_node.position.y = -WRECK_SINK  # the hull settles; the debris stays on the surface

	# Get wave normal for tilting the ship
	var wave_normal = wave_calculator.get_wave_normal(base_position, current_time, 0.5)

	# Calculate tilt angles from wave normal and dampen them too
	var tilt_forward = -asin(clamp(wave_normal.z, -1.0, 1.0)) * damping_factor
	var tilt_side = asin(clamp(wave_normal.x, -1.0, 1.0)) * damping_factor

	# Apply rotation: first the ship's facing, then dampened wave tilt
	# Get facing from current rotation (stored in model_node)
	if model_node:
		var facing_angle = model_node.rotation_degrees.y
		if _wrecked:
			tilt_forward += deg_to_rad(WRECK_TRIM_DEG)
			tilt_side += deg_to_rad(WRECK_HEEL_DEG)
		model_node.rotation = Vector3(tilt_forward, deg_to_rad(facing_angle), tilt_side)
		_sync_ring_heading()  # follows the playback's turn tween too
