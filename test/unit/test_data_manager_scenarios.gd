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
	assert_eq(int(scenario["wind_direction"]), 2)

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
	assert_eq(ship["ship_type"], "frigate_32")
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

# --- Every shipped scenario ---

func _shipped_scenarios() -> Dictionary:
	var result := {}
	var dir := DirAccess.open("res://data/scenarios")
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			var text := FileAccess.get_file_as_string("res://data/scenarios/" + file_name)
			result[file_name] = JSON.parse_string(text)
	return result

func test_shipped_scenarios_have_unique_ship_ids() -> void:
	var scenarios := _shipped_scenarios()
	assert_gt(scenarios.size(), 0, "found the shipped scenarios")
	for file_name in scenarios:
		var seen := {}
		for ship in scenarios[file_name]["ships"]:
			assert_false(seen.has(ship["id"]), "%s: ship id %s is unique" % [file_name, ship["id"]])
			seen[ship["id"]] = true

func test_shipped_scenarios_have_no_stacked_ships() -> void:
	var scenarios := _shipped_scenarios()
	assert_gt(scenarios.size(), 0, "found the shipped scenarios")
	for file_name in scenarios:
		var occupied := {}
		for ship in scenarios[file_name]["ships"]:
			var hex := Vector2i(int(ship["position"]["q"]), int(ship["position"]["r"]))
			assert_false(occupied.has(hex), "%s: %s starts on %s, already taken by %s" % [
				file_name, ship["id"], hex, occupied.get(hex, "")])
			occupied[hex] = ship["id"]

func test_shipped_scenarios_have_a_turn_limit() -> void:
	var scenarios := _shipped_scenarios()
	for file_name in ["test_basic.json", "test_fleet.json"]:
		assert_true(scenarios.has(file_name), "%s is shipped" % file_name)
		if scenarios.has(file_name):
			assert_gt(int(scenarios[file_name].get("turn_limit", 0)), 0, "%s has a positive turn_limit" % file_name)

func test_shipped_scenarios_name_every_ship_uniquely() -> void:
	var scenarios := _shipped_scenarios()
	for file_name in ["test_basic.json", "test_fleet.json"]:
		assert_true(scenarios.has(file_name), "%s is shipped" % file_name)
		var seen := {}
		for ship in scenarios.get(file_name, {}).get("ships", []):
			var ship_name := str(ship.get("ship_name", ""))
			assert_ne(ship_name.strip_edges(), "", "%s: %s has a name" % [file_name, ship["id"]])
			assert_false(seen.has(ship_name), "%s: name %s is unique" % [file_name, ship_name])
			seen[ship_name] = true

func test_loaded_scenarios_have_unique_names_after_fallback() -> void:
	for scenario_name in ["test_basic", "test_fleet"]:
		var scenario := DataManager.load_scenario(scenario_name)
		var seen := {}
		for ship in scenario["ships"]:
			assert_false(seen.has(ship["ship_name"]), "%s: %s unique" % [scenario_name, ship["ship_name"]])
			seen[ship["ship_name"]] = true

func test_unnamed_ships_get_numbered_fallback_names_per_side() -> void:
	var ships := [
		{"id": "a", "player_id": 0, "ship_type": "frigate_38"},
		{"id": "b", "player_id": 0, "ship_type": "frigate_38"},
		{"id": "c", "player_id": 1, "ship_type": "frigate_38"},
		{"id": "d", "player_id": 1, "ship_type": "frigate_32", "ship_name": "Topaze"},
		{"id": "e", "player_id": 1, "ship_type": "frigate_32", "ship_name": ""},
	]
	DataManager.assign_fallback_ship_names(ships)
	assert_eq(ships[0]["ship_name"], "38-gun Frigate 1")
	assert_eq(ships[1]["ship_name"], "38-gun Frigate 2")
	assert_eq(ships[2]["ship_name"], "38-gun Frigate 1", "numbered per side")
	assert_eq(ships[3]["ship_name"], "Topaze", "a given name is kept")
	assert_eq(ships[4]["ship_name"], "32-gun Frigate 1")


# --- Placement validation ---

func _start_with_ships(scenario: Dictionary) -> void:
	GameState.clear_ships()
	for ship_data in scenario["ships"]:
		var ref := Ship.initialize_from_scenario(
				ship_data, DataManager.get_ship_definition(ship_data["ship_type"]).to_dict())
		var state := ShipState.new()
		state.initialize_from_scenario(ship_data, ref)
		GameState.add_ship(state)
	GameState.start_new_game(scenario)

func test_shipped_scenarios_have_valid_placement() -> void:
	for scenario_name in ["test_basic", "test_fleet"]:
		_start_with_ships(DataManager.load_scenario(scenario_name))
		assert_gt(GameState.ships.size(), 1, "%s: ships were placed" % scenario_name)
		assert_eq(GameState.placement_errors(), [] as Array[String], scenario_name)
	GameState.clear_ships()

func test_overlapping_placement_reported() -> void:
	# Both sterns are on (-1, 0)
	var scenario := {
		"name": "overlap", "wind_direction": 0, "wind_speed": 2, "sea_state": 1,
		"ships": [
			{"id": "a", "player_id": 0, "ship_type": "frigate_38", "ship_name": "A",
				"position": {"q": 0, "r": 0}, "facing": 0, "sail_state": "MS"},
			{"id": "b", "player_id": 1, "ship_type": "frigate_38", "ship_name": "B",
				"position": {"q": -2, "r": 0}, "facing": 3, "sail_state": "MS"},
		],
	}
	_start_with_ships(scenario)
	assert_push_error("overlap")
	assert_eq(GameState.placement_errors().size(), 1)
	GameState.clear_ships()

func test_stern_outside_map_bounds_reported() -> void:
	# 10x10 map spans q,r -5..4; the bow is on the map, the stern at q=5 is not
	var scenario := {
		"name": "edge", "wind_direction": 0, "wind_speed": 2, "sea_state": 1,
		"map_bounds": {"width": 10, "height": 10},
		"ships": [
			{"id": "a", "player_id": 0, "ship_type": "frigate_38", "ship_name": "A",
				"position": {"q": 4, "r": 0}, "facing": 3, "sail_state": "MS"},
		],
	}
	_start_with_ships(scenario)
	assert_push_error("outside map_bounds")
	assert_eq(GameState.placement_errors().size(), 1)
	GameState.clear_ships()
