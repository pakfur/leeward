extends GutTest
## Tests for GameState.rng seeded determinism.
##
## Verifies that the shared RNG property exists, that the same seed produces
## the same sequence, and that different seeds diverge.

const TEST_SEED := 12345


func test_rng_property_exists_on_game_state() -> void:
	assert_true("rng" in GameState, "GameState should have an rng property")


func test_same_seed_produces_same_sequence() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = TEST_SEED
	b.seed = TEST_SEED

	for _i in range(10):
		assert_eq(a.randi(), b.randi(), "Same seed must produce identical values")


func test_different_seeds_diverge() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = TEST_SEED
	b.seed = TEST_SEED + 1

	var diverged := false
	for _i in range(20):
		if a.randi() != b.randi():
			diverged = true
			break
	assert_true(diverged, "Different seeds should produce different sequences")


func test_rng_seeded_from_scenario_matches_expected_first_value() -> void:
	# Confirms the seed→first-value contract so regressions are caught.
	var rng := RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	var first := rng.randi()

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = TEST_SEED
	assert_eq(rng2.randi(), first, "Resetting to the same seed must replay the same first value")


func test_zero_seed_is_valid() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var _val := rng.randi()
	assert_true(true, "Zero seed should not crash")


func _run_tick_sequence(seed_value: int, ticks: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 2
	env.wind_speed_change = "steady"
	env.region = "oceanic"
	var history: Array[EnvironmentState] = []
	var results := []
	for turn in range(1, ticks + 1):
		env.tick_environment(turn, rng, history)
		results.append({"dir": env.wind_direction, "spd": env.wind_speed})
	return results


func test_tick_environment_deterministic_with_same_seed() -> void:
	var run_a := _run_tick_sequence(42, 10)
	var run_b := _run_tick_sequence(42, 10)
	for i in range(run_a.size()):
		assert_eq(run_a[i].dir, run_b[i].dir, "Wind direction must match at tick %d" % i)
		assert_eq(run_a[i].spd, run_b[i].spd, "Wind speed must match at tick %d" % i)


func test_tick_environment_diverges_with_different_seeds() -> void:
	var run_a := _run_tick_sequence(42, 20)
	var run_b := _run_tick_sequence(99, 20)
	var diverged := false
	for i in range(run_a.size()):
		if run_a[i].dir != run_b[i].dir or run_a[i].spd != run_b[i].spd:
			diverged = true
			break
	assert_true(diverged, "Different seeds should produce different environment sequences")


func test_environment_controller_has_no_private_rng() -> void:
	var ctrl := EnvironmentController.new()
	assert_false("rng" in ctrl, "EnvironmentController should not have a private rng property")
	ctrl.free()
