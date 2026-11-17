extends GutTest
## SeaModel (view): zoom intensity, grid fade, presets from data/ui/sea_presets.json, swell scaling
## and the effective sea state. Pure parts only; the model is used outside the scene tree.

var model: SeaModel


func before_each() -> void:
	model = SeaModel.new()


func after_each() -> void:
	model.free()


func test_intensity_zero_at_flat_distance():
	assert_eq(SeaModel.intensity_for(20.5, 20.5, 7.5), 0.0)
	assert_eq(SeaModel.intensity_for(40.0, 20.5, 7.5), 0.0)


func test_intensity_one_at_full_distance():
	assert_eq(SeaModel.intensity_for(7.5, 20.5, 7.5), 1.0)
	assert_eq(SeaModel.intensity_for(2.0, 20.5, 7.5), 1.0)


func test_intensity_smooth_between():
	assert_almost_eq(SeaModel.intensity_for(14.0, 20.5, 7.5), 0.5, 0.0001)
	var near := SeaModel.intensity_for(10.0, 20.5, 7.5)
	var far := SeaModel.intensity_for(18.0, 20.5, 7.5)
	assert_true(near > 0.5 and near < 1.0, "closer than halfway is above 0.5")
	assert_true(far > 0.0 and far < 0.5, "farther than halfway is below 0.5")


func test_presets_match_table():
	assert_eq(model.preset(4).glide_seconds, 1.5)
	assert_eq(model.preset(5).whitecap_strength, 2.6)
	assert_eq(model.preset(0).whitecap_strength, 0.0)
	assert_eq(model.preset(3).swell_wavelength, 5.5)
	assert_eq(model.preset(1).inertia_mult, 0.8)
	for sea in range(EnvironmentState.SEA_STATE_MAX + 1):
		assert_eq(model.preset(sea).size(), 10, "sea %d preset has every field" % sea)


func test_globals_loaded():
	assert_eq(model.flat_distance, 20.5)
	assert_eq(model.full_distance, 7.5)
	assert_eq(model.grid_fade_start, 0.5)
	assert_eq(model.grid_fade_end, 1.0)
	assert_eq(model.whitecap_min_sea, 1)


func test_grid_opacity_degenerate_fade_is_a_step():
	model.grid_fade_start = 0.6
	model.grid_fade_end = 0.6
	model.intensity = 0.59
	assert_eq(model.grid_opacity(), 1.0)
	model.intensity = 0.6
	assert_eq(model.grid_opacity(), 0.0)
	model.grid_fade_end = 0.3  # inverted
	model.intensity = 0.9
	var o := model.grid_opacity()
	assert_true(is_equal_approx(o, 0.0) and not is_nan(o), "no NaN or inverted fade")


func test_grid_opacity_fades():
	model.intensity = 0.5
	assert_eq(model.grid_opacity(), 1.0)
	model.intensity = 0.75
	assert_almost_eq(model.grid_opacity(), 0.5, 0.0001)
	model.intensity = 1.0
	assert_eq(model.grid_opacity(), 0.0)
	model.intensity = 0.2
	assert_eq(model.grid_opacity(), 1.0)


func test_swell_zero_when_flat():
	model.set_environment(2, 4, 5)
	model.sea_time = 3.7
	model.intensity = 0.0
	model.recompute()
	for p in [Vector2.ZERO, Vector2(3.2, -1.5), Vector2(-7.0, 11.0)]:
		assert_eq(model.swell_height(p), 0.0)
		assert_eq(model.swell_displacement(p), Vector3.ZERO)


func test_full_swell_ignores_the_zoom():
	model.set_environment(2, 4, 5)
	model.sea_time = 3.7
	model.recompute()
	var p := Vector2(3.2, -1.5)
	model.intensity = 1.0
	var full := model.swell_height(p)
	assert_ne(full, 0.0)
	assert_eq(model.swell_height_full(p), full, "the full swell is the swell at intensity 1")
	model.intensity = 0.0
	assert_eq(model.swell_height_full(p), full, "and does not change with the zoom")


func test_swell_scales_with_intensity():
	model.set_environment(2, 4, 5)
	model.sea_time = 3.7
	model.intensity = 1.0
	model.recompute()
	var p := Vector2(3.2, -1.5)
	var full := model.swell_displacement(p)
	assert_true(full.length() > 0.0, "full swell moves the surface")
	model.intensity = 0.5
	assert_almost_eq(model.swell_displacement(p).y, full.y * 0.5, 0.0001)


func test_effective_sea_state_override_and_clamp():
	model.set_environment(0, 2, 3)
	assert_eq(model.effective_sea_state(), 3)
	model.set_environment(0, 2, 9)
	assert_eq(model.effective_sea_state(), 5)
	model.set_environment(0, 2, -2)
	assert_eq(model.effective_sea_state(), 0)
	model.sea_state_override = 4
	assert_eq(model.effective_sea_state(), 4)
	model.sea_state_override = 7
	assert_eq(model.effective_sea_state(), 5)


func test_preset_loaded_on_sea_state_change():
	model.set_environment(0, 2, 4)
	model.apply_preset_if_changed()
	assert_eq(model.glide_seconds, 1.5)
	assert_eq(model.swell_height_mult, 1.6)
	model.swell_height_mult = 0.1  # a live tweak holds until the sea state changes
	model.apply_preset_if_changed()
	assert_eq(model.swell_height_mult, 0.1)
	model.sea_state_override = 0
	model.apply_preset_if_changed()
	assert_eq(model.glide_seconds, 0.8)
	assert_eq(model.swell_height_mult, 0.5)


func test_downwind_and_heel():
	model.set_environment(3, 5, 2)  # wind from W blows toward E
	assert_eq(model.downwind(), Vector2(1.0, 0.0))
	model.heel_mult = 1.5
	assert_almost_eq(model.beam_heel_deg(), 13.5, 0.0001)


func test_starts_flat_without_a_camera():
	assert_eq(model.camera_distance, model.flat_distance)
	assert_eq(SeaModel.intensity_for(model.camera_distance, model.flat_distance, model.full_distance), 0.0)


func test_whitecap_sea_factor_by_sea_state():
	model.set_environment(0, 2, 0)  # below whitecap_min_sea (1): no whitecaps
	assert_eq(model.shader_uniforms()["whitecap_sea_factor"], 0.0)
	model.sea_state_override = 1
	assert_eq(model.shader_uniforms()["whitecap_sea_factor"], 0.8)
	model.sea_state_override = 5
	assert_eq(model.shader_uniforms()["whitecap_sea_factor"], 1.6)


func test_shader_uniforms_carry_full_swell():
	model.set_environment(0, 4, 5)
	model.apply_preset_if_changed()
	model.recompute()
	var u := model.shader_uniforms()
	var expected: float = SeaModel.SWELL_AMP_BY_SEA[5] * model.swell_height_mult * (0.6 + 0.3 + 0.25)
	assert_almost_eq(u["swell_amp_total"], expected, 0.0001)
	assert_eq(u["whitecap_strength"], 2.6)
	assert_false(u.has("wave_1"), "no legacy wave uniforms")


func test_base_chop_ignores_sea_state():
	model.set_environment(0, 3, 1)
	var calm := model.shader_uniforms()
	model.sea_state_override = 5
	var heavy := model.shader_uniforms()
	for key in ["chop_amplitude", "chop_wavelength", "chop_noise"]:
		assert_eq(heavy[key], calm[key], key)
	var calm_scale := model.chop_time_scale()
	model.sea_state_override = 5
	assert_eq(model.chop_time_scale(), calm_scale, "chop clock ignores the sea state")
	model.set_environment(0, 5, 1)
	assert_true(model.shader_uniforms()["chop_amplitude"] > calm["chop_amplitude"], "follows the wind")


func test_push_resends_after_preset_change_only():
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/ocean_water.gdshader")
	model.material = mat
	model.set_environment(0, 2, 1)
	model._push_to_shader()
	assert_eq(mat.get_shader_parameter("whitecap_strength"), 1.1)
	mat.set_shader_parameter("whitecap_strength", 9.0)  # a stale value the model should not overwrite
	model._push_to_shader()
	assert_eq(mat.get_shader_parameter("whitecap_strength"), 9.0, "unchanged uniforms are not re-sent")
	model.sea_state_override = 5
	model.apply_preset_if_changed()
	model.recompute()
	model._push_to_shader()
	assert_eq(mat.get_shader_parameter("whitecap_strength"), 2.6, "re-sent after the preset change")
	model.material = null


func test_override_does_not_touch_environment():
	var env_before := GameState.environment.sea_state
	model.set_environment(0, 2, 1)
	model.sea_state_override = 5
	assert_eq(model.effective_sea_state(), 5)
	assert_eq(GameState.environment.sea_state, env_before, "the override changes the look only")
	assert_eq(model.game_sea_state, 1)
	model.sea_state_override = -1
	assert_eq(model.effective_sea_state(), 1)


func test_settings_lists_every_tunable():
	var s := model.settings()
	for key: String in SeaModel.PRESET_FIELDS + SeaModel.GLOBAL_FIELDS:
		assert_true(s.has(key), key)
	assert_true(s.has("sea_state_override"))
	assert_true(s.has("effective_sea_state"))


func test_speed_change_does_not_jump_the_phase():
	model.set_environment(0, 3, 3)
	for i in 600:  # ten seconds of sea
		model.advance(1.0 / 60.0)
	var before: Vector3 = model._phase
	model.swell_speed *= 3.0
	model.swell_wavelength *= 1.5
	model.recompute()
	assert_eq(model._phase, before, "a speed or wavelength edit changes the rate, not the phase")
	model.advance(1.0 / 60.0)
	for i in 3:
		var step := absf(angle_difference(before[i], model._phase[i]))
		assert_almost_eq(step, model.phase_speed(i) / 60.0, 0.0001, "one frame at the new speed")


func test_chop_clock_accumulates():
	model.set_environment(0, 2, 1)
	model.advance(1.0)
	var t := model.chop_time
	assert_almost_eq(t, 1.0 / model.chop_time_scale(), 0.0001)
	model.set_environment(0, 5, 1)  # a stronger wind runs the chop faster from here, no jump
	assert_eq(model.chop_time, t)
	model.advance(1.0)
	assert_almost_eq(model.chop_time, t + 1.0 / model.chop_time_scale(), 0.0001)


func test_swell_direction_blends_to_new_downwind():
	model.set_environment(3, 3, 3)  # first environment snaps: toward E
	assert_almost_eq(model.swell_direction().distance_to(Vector2(1.0, 0.0)), 0.0, 0.0001)
	model.set_environment(0, 3, 3)  # wind now from E: downwind is W
	assert_almost_eq(model.swell_direction().distance_to(Vector2(1.0, 0.0)), 0.0, 0.0001,
		"no snap on a wind shift")
	model.advance(SeaModel.DIR_BLEND_SECONDS * 0.5)
	var mid := model.swell_direction()
	assert_true(mid.distance_to(Vector2(1.0, 0.0)) > 0.1 and mid.distance_to(Vector2(-1.0, 0.0)) > 0.1,
		"on its way round halfway through")
	model.advance(SeaModel.DIR_BLEND_SECONDS)
	assert_almost_eq(model.swell_direction().distance_to(model.downwind()), 0.0, 0.0001, "settled downwind")
	assert_almost_eq(model.shader_uniforms()["wind_dir"].distance_to(model.downwind()), 0.0, 0.0001)


func test_sea_moves_before_the_ships():
	var view := ShipView.new()
	assert_true(model.process_priority < view.process_priority, "SeaModel processes before ShipView")
	view.free()
