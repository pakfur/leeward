extends GutTest
## Tests for DataManager scenario loading.
##
## Validates loading of scenario JSON files and the default scenario fallback.

var dm: Node

func before_all() -> void:
	dm = DataManager

# --- Scenario Loading ---

func test_load_test_basic_scenario() -> void:
	var scenario = dm.load_scenario("test_basic")
	assert_gt(scenario.size(), 0, "Scenario should not be empty")

func test_scenario_has_name() -> void:
	var scenario = dm.load_scenario("test_basic")
	assert_eq(scenario["name"], "Test Scenario - Two Ships")

func test_scenario_has_wind_direction() -> void:
	var scenario = dm.load_scenario("test_basic")
	assert_true(scenario.has("wind_direction"), "Scenario should have wind_direction")
	assert_eq(int(scenario["wind_direction"]), 0)

func test_scenario_has_wind_speed() -> void:
	var scenario = dm.load_scenario("test_basic")
	assert_true(scenario.has("wind_speed"), "Scenario should have wind_speed")
	assert_eq(int(scenario["wind_speed"]), 2)

func test_scenario_has_ships() -> void:
	var scenario = dm.load_scenario("test_basic")
	assert_true(scenario.has("ships"), "Scenario should have ships array")
	assert_eq(scenario["ships"].size(), 2, "Test scenario should have 2 ships")

func test_scenario_ship_has_required_fields() -> void:
	var scenario = dm.load_scenario("test_basic")
	var ship = scenario["ships"][0]
	assert_true(ship.has("id"), "Ship should have id")
	assert_true(ship.has("player_id"), "Ship should have player_id")
	assert_true(ship.has("ship_type"), "Ship should have ship_type")
	assert_true(ship.has("position"), "Ship should have position")
	assert_true(ship.has("facing"), "Ship should have facing")
	assert_true(ship.has("sail_state"), "Ship should have sail_state")

func test_scenario_ship_position_has_q_r() -> void:
	var scenario = dm.load_scenario("test_basic")
	var pos = scenario["ships"][0]["position"]
	assert_true(pos.has("q"), "Position should have q coordinate")
	assert_true(pos.has("r"), "Position should have r coordinate")

func test_scenario_player_ship_values() -> void:
	var scenario = dm.load_scenario("test_basic")
	var ship = scenario["ships"][0]
	assert_eq(ship["id"], "player_ship")
	assert_eq(int(ship["player_id"]), 0)
	assert_eq(ship["ship_type"], "frigate_38")
	assert_eq(int(ship["facing"]), 0)
	assert_eq(ship["sail_state"], "MS")

func test_scenario_enemy_ship_values() -> void:
	var scenario = dm.load_scenario("test_basic")
	var ship = scenario["ships"][1]
	assert_eq(ship["id"], "enemy_ship")
	assert_eq(int(ship["player_id"]), 1)
	assert_eq(ship["ship_type"], "corvette_24")
	assert_eq(int(ship["facing"]), 3)

# --- Seed Validation ---

func test_scenario_has_seed_field() -> void:
	var scenario = dm.load_scenario("test_basic")
	assert_true(scenario.has("seed"), "Scenario should have seed field")
	assert_eq(int(scenario["seed"]), 42, "test_basic seed should be 42")

func test_seed_minus_one_generates_fresh_seed() -> void:
	var temp_path = "user://test_seed_minus_one.json"
	var content = '{"name":"seed test","seed":-1,"wind_direction":0,"wind_speed":2,"ships":[]}'
	var f = FileAccess.open(temp_path, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	var scenario = dm.load_scenario("seed_test", temp_path)
	assert_true(scenario.has("seed"), "Scenario should have seed after loading")
	assert_true(int(scenario["seed"]) > 0, "Fresh seed should be positive, got %d" % int(scenario["seed"]))
	assert_true(int(scenario["seed"]) != -1, "Seed should no longer be -1")
	DirAccess.remove_absolute(temp_path)

func test_missing_seed_hard_errors() -> void:
	var temp_path = "user://test_no_seed.json"
	var content = '{"name":"no seed","wind_direction":0,"wind_speed":2,"ships":[]}'
	var f = FileAccess.open(temp_path, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	var scenario = dm.load_scenario("no_seed", temp_path)
	assert_eq(scenario.size(), 0, "Missing seed should return empty dict")
	assert_push_error("missing required 'seed' field")
	DirAccess.remove_absolute(temp_path)

# --- Crew Quality Normalization ---

func test_crew_quality_normalized_to_letters() -> void:
	var scenario = dm.load_scenario("test_basic")
	var ship = scenario["ships"][0]
	var cq = ship["crew_quality"]
	assert_eq(cq.length(), 1, "crew_quality should be a single letter, got '%s'" % cq)
	assert_true(cq >= "A" and cq <= "G", "crew_quality should be A-G, got '%s'" % cq)

func test_trained_maps_to_d() -> void:
	var scenario = dm.load_scenario("test_basic")
	var cq = scenario["ships"][0]["crew_quality"]
	assert_eq(cq, "D", "'Trained' should normalize to 'D'")

# --- Nonexistent Scenario Falls Back to Default ---

func test_nonexistent_scenario_returns_default() -> void:
	var scenario = dm.load_scenario("this_scenario_does_not_exist")
	assert_gt(scenario.size(), 0, "Nonexistent scenario should return non-empty default")
	assert_true(scenario.has("ships"), "Default scenario should have ships")
	assert_engine_error("Scenario not found")

func test_default_scenario_has_valid_structure() -> void:
	var scenario = dm.load_scenario("nonexistent")
	assert_true(scenario.has("name"), "Default scenario should have name")
	assert_true(scenario.has("wind_direction"), "Default scenario should have wind_direction")
	assert_true(scenario.has("wind_speed"), "Default scenario should have wind_speed")
	assert_true(scenario.has("ships"), "Default scenario should have ships")
	assert_eq(scenario["ships"].size(), 2, "Default scenario should have 2 ships")
	assert_engine_error("Scenario not found")
