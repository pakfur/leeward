extends GutTest
## ShipMotion (view): the pure parts of a ship riding the swell (sea-state spec C): the heel to
## leeward, the time constants by ship class, and a level ship on a flat sea.

var sea: SeaModel


func before_each() -> void:
	sea = SeaModel.new()


func after_each() -> void:
	sea.free()


func test_heel_toward_leeward():
	# Facing 0 (east), wind from 5 (NE): r = 1, leeward is starboard -> starboard down (roll < 0).
	assert_eq(FireGeometry.leeward_side(0, 5), ShipState.STARBOARD)
	assert_eq(ShipMotion.heel_sign(0, 5), -1.0)
	assert_eq(ShipMotion.heel_sign(0, 4), -1.0, "r = 2 is starboard too")
	# Wind from 1 (SE): r = 5, leeward is port -> port down (roll > 0).
	assert_eq(FireGeometry.leeward_side(0, 1), ShipState.PORT)
	assert_eq(ShipMotion.heel_sign(0, 1), 1.0)
	assert_eq(ShipMotion.heel_sign(0, 2), 1.0, "r = 4 is port too")


func test_heel_follows_the_wind_for_every_facing():
	for facing in range(6):
		for wind in range(6):
			var side := FireGeometry.leeward_side(facing, wind)
			var expected := 0.0
			if side == ShipState.STARBOARD:
				expected = -1.0
			elif side == ShipState.PORT:
				expected = 1.0
			assert_eq(ShipMotion.heel_sign(facing, wind), expected, "facing %d wind %d" % [facing, wind])


func test_no_heel_head_to_wind():
	assert_eq(ShipMotion.heel_sign(3, 3), 0.0, "WF=L: head to wind")
	assert_eq(ShipMotion.heel_sign(3, 0), 0.0, "WF=R: running before it")
	sea.wind_speed = 5
	sea.wind_direction = 3
	assert_eq(ShipMotion.steady_heel(sea, 3, "PS"), 0.0)


func test_steady_heel_is_beam_wind_heel_by_sail_and_beam_component():
	sea.wind_speed = 3
	sea.wind_direction = 5
	sea.intensity = 1.0
	var expected: float = -deg_to_rad(sea.beam_heel_deg()) * ShipMotion.SAIL_HEEL["ps"] * sin(deg_to_rad(60.0))
	assert_almost_eq(ShipMotion.steady_heel(sea, 0, "PS"), expected, 0.00001)
	assert_true(absf(ShipMotion.steady_heel(sea, 0, "FS")) < absf(expected), "less sail, less heel")


func test_larger_ship_slower():
	var ratio := ShipMotion.time_constant(2, 1.0) / ShipMotion.time_constant(3, 1.0)
	assert_between(ratio, 1.35, 1.55)
	assert_almost_eq(ShipMotion.time_constant(3, 2.4), 2.4 * ShipMotion.time_constant(3, 1.0), 0.00001,
			"the preset's inertia_mult scales it")


func test_ship_level_when_flat():
	sea.wind_speed = 5
	sea.wind_direction = 5
	sea.sea_state_override = 5
	sea.apply_preset_if_changed()
	sea.sea_time = 3.7
	sea.intensity = 0.0
	sea.recompute()
	var m := ShipMotion.targets(sea, Vector2(4.0, 2.0), deg_to_rad(-90.0), 0.9, "PS")
	assert_eq(m, Vector4.ZERO, "heave, pitch, roll and heel all 0")


func test_ship_moves_on_a_full_sea():
	sea.wind_speed = 5
	sea.wind_direction = 5
	sea.sea_state_override = 5
	sea.apply_preset_if_changed()
	sea.sea_time = 3.7
	sea.intensity = 1.0
	sea.recompute()
	var m := ShipMotion.targets(sea, Vector2(4.0, 2.0), deg_to_rad(-90.0), 0.9, "PS")
	assert_true(m.w < 0.0, "heels to starboard (leeward)")
	assert_true(absf(m.x) + absf(m.y) + absf(m.z) > 0.0, "heaves, pitches or rolls")


func test_no_sea_model_means_level():
	assert_eq(ShipMotion.targets(null, Vector2.ZERO, 0.0, 0.9, "PS"), Vector4.ZERO)


func test_facing_from_yaw():
	for f in range(6):
		assert_eq(ShipMotion.facing_from_yaw(deg_to_rad(-f * 60.0 - 90.0)), f)
	assert_eq(ShipMotion.facing_from_yaw(deg_to_rad(-90.0 - 25.0)), 0, "nearest facing mid-turn")


func test_low_pass_approaches_target():
	var v := ShipMotion.low_pass(0.0, 1.0, 0.1, 1.0)
	assert_true(v > 0.0 and v < 0.2)
	assert_eq(ShipMotion.low_pass(0.0, 1.0, 0.1, 0.0), 1.0, "no time constant: at the target")
