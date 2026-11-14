extends GutTest
## Tests for IsometricCamera's basis: it must be right-handed (a left-handed camera basis
## renders the world mirrored) and the default rotation must put north up / east right.

const IsometricCameraScript = preload("res://scripts/core/isometric_camera.gd")

const ROTATIONS := [0.0, 30.0, 45.0, 90.0, 135.0, 180.0, 270.0, 315.0, -60.0]
const TILTS := [25.0, 45.0, 60.0, 85.0, 89.9, 90.0]

var camera: Camera3D


func before_each() -> void:
	camera = IsometricCameraScript.new()
	camera.camera_distance = 25.0
	camera.camera_target = Vector3.ZERO


func after_each() -> void:
	camera.free()


func _apply(rotation_y: float, tilt: float) -> Basis:
	camera.camera_rotation_y = rotation_y
	camera.isometric_angle = tilt
	camera._update_camera_transform()
	return camera.transform.basis


func test_basis_is_right_handed_across_rotations_and_tilts() -> void:
	for rot in ROTATIONS:
		for tilt in TILTS:
			var b := _apply(rot, tilt)
			var label := "rot=%.1f tilt=%.1f" % [rot, tilt]
			assert_gt(b.determinant(), 0.0, "determinant must be positive (%s)" % label)
			var cross := b.x.cross(b.y)
			assert_almost_eq(cross.x, b.z.x, 0.001, "x cross y == z, x component (%s)" % label)
			assert_almost_eq(cross.y, b.z.y, 0.001, "x cross y == z, y component (%s)" % label)
			assert_almost_eq(cross.z, b.z.z, 0.001, "x cross y == z, z component (%s)" % label)


func test_basis_is_orthonormal() -> void:
	for rot in ROTATIONS:
		for tilt in TILTS:
			var b := _apply(rot, tilt)
			assert_almost_eq(b.x.length(), 1.0, 0.001)
			assert_almost_eq(b.y.length(), 1.0, 0.001)
			assert_almost_eq(b.z.length(), 1.0, 0.001)
			assert_almost_eq(b.x.dot(b.y), 0.0, 0.001)
			assert_almost_eq(b.x.dot(b.z), 0.0, 0.001)
			assert_almost_eq(b.y.dot(b.z), 0.0, 0.001)


func test_camera_looks_at_target() -> void:
	for rot in ROTATIONS:
		for tilt in TILTS:
			var b := _apply(rot, tilt)
			var to_target: Vector3 = (camera.camera_target - camera.position).normalized()
			# Godot cameras look along -Z
			assert_almost_eq((-b.z).dot(to_target), 1.0, 0.001, "looks at target rot=%.1f tilt=%.1f" % [rot, tilt])


func test_default_rotation_is_north_up_east_right() -> void:
	var fresh: Camera3D = IsometricCameraScript.new()
	assert_eq(fresh.camera_rotation_y, 90.0, "default rotation is the north-up view")
	fresh.free()
	for tilt in [85.0, 90.0]:
		var b := _apply(90.0, tilt)
		# Screen-right (camera +X) is world east (+X)
		assert_almost_eq(b.x.dot(Vector3(1, 0, 0)), 1.0, 0.001, "east is screen-right (tilt %.1f)" % tilt)
		# Screen-up (camera +Y) leans toward world north (-Z)
		assert_gt(b.y.dot(Vector3(0, 0, -1)), 0.0, "north is screen-up (tilt %.1f)" % tilt)


func test_clockwise_hex_directions_appear_clockwise_on_screen() -> void:
	# Project hex directions 0 (E) and 1 (SE) onto the camera's screen axes (y up). Going
	# from E to SE must turn clockwise on screen, i.e. the 2D cross product is negative.
	var grid := HexGrid.new()
	for rot in ROTATIONS:
		var b := _apply(rot, 85.0)
		var e := grid.axial_to_world(1, 0)
		var se := grid.axial_to_world(0, 1)
		var e2 := Vector2(b.x.dot(e), b.y.dot(e))
		var se2 := Vector2(b.x.dot(se), b.y.dot(se))
		assert_lt(e2.cross(se2), 0.0, "E -> SE turns clockwise on screen (rot %.1f)" % rot)


func test_pan_moves_target_with_drag_at_straight_down() -> void:
	# Straight down used to zero the forward vector; pan must still work on both axes.
	_apply(90.0, 90.0)
	camera.pan_camera(Vector2(10, 0))
	assert_lt(camera.camera_target.x, 0.0, "dragging right moves the target west (map follows mouse)")
	camera.camera_target = Vector3.ZERO
	camera.pan_camera(Vector2(0, 10))
	assert_lt(camera.camera_target.z, 0.0, "dragging down moves the target north (map follows mouse)")
