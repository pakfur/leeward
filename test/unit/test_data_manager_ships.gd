extends GutTest
## Tests for DataManager ship definitions loading and lookups.
##
## Validates ship definition parsing from ships.json, Ship.from_dict(),
## and DataManager.get_ship_definition().

var dm: Node

func before_all() -> void:
	dm = DataManager
	dm.load_ship_definitions()

# --- Ship Definitions Loading ---

func test_ship_definitions_load_successfully() -> void:
	assert_gt(dm.ship_definitions.size(), 0, "Ship definitions should not be empty")

func test_expected_ship_ids_present() -> void:
	assert_true(dm.ship_definitions.has("frigate_38"), "Should have frigate_38")
	assert_true(dm.ship_definitions.has("corvette_24"), "Should have corvette_24")
	assert_true(dm.ship_definitions.has("ship_of_line_74"), "Should have ship_of_line_74")

func test_ship_definition_count() -> void:
	assert_eq(dm.ship_definitions.size(), 3, "Should have 3 ship definitions from ships.json")

# --- get_ship_definition() ---

func test_get_ship_definition_returns_ship_definition() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_not_null(def, "get_ship_definition should return non-null for valid ID")

func test_get_ship_definition_unknown_returns_null() -> void:
	var def = dm.get_ship_definition("nonexistent_ship")
	assert_null(def, "get_ship_definition should return null for unknown ID")
	assert_engine_error("Ship definition not found", "Expected warning for missing ship ID")

# --- Frigate 38 Properties ---

func test_frigate_38_name() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.name, "38-gun Frigate")

func test_frigate_38_nationality() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.nationality, "British")

func test_frigate_38_rating() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.rating, 38)

func test_frigate_38_class() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.ship_class, 3)

func test_frigate_38_maneuverability() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.maneuverability, "C")

func test_frigate_38_speed_type() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.speed_type, "F/F")

func test_frigate_38_type() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.type, "Frigate")

func test_frigate_38_draft() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.draft, 18)

func test_frigate_38_freeboard() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.freeboard, 8)

func test_frigate_38_rigging_hp() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.rigging_hp[0], 5)
	assert_eq(def.rigging_hp[1], 5)
	assert_eq(def.rigging_hp[2], 6)
	assert_eq(def.rigging_hp[3], 6)

func test_frigate_38_hull_hp() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.hull_hp[0], 5)
	assert_eq(def.hull_hp[1], 5)
	assert_eq(def.hull_hp[2], 5)
	assert_eq(def.hull_hp[3], 6)

func test_frigate_38_crew_count() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.crew_count[0], 3)
	assert_eq(def.crew_count[1], 3)
	assert_eq(def.crew_count[2], 3)
	assert_eq(def.crew_count[3], 3)

func test_frigate_38_marine_count() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.marine_count, 2)

# --- Corvette 24 Properties ---

func test_corvette_24_speed_type() -> void:
	var def = dm.get_ship_definition("corvette_24")
	assert_eq(def.speed_type, "C/F")

func test_corvette_24_class() -> void:
	var def = dm.get_ship_definition("corvette_24")
	assert_eq(def.ship_class, 5)

func test_corvette_24_maneuverability() -> void:
	var def = dm.get_ship_definition("corvette_24")
	assert_eq(def.maneuverability, "D")

# --- Ship of the Line 74 Properties ---

func test_sol_74_speed_type() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	assert_eq(def.speed_type, "L/F")

func test_sol_74_type() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	assert_eq(def.type, "SOL")

func test_sol_74_rating() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	assert_eq(def.rating, 74)

func test_sol_74_rigging_hp() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	assert_eq(def.rigging_hp[0], 7)
	assert_eq(def.rigging_hp[3], 7)

func test_sol_74_hull_hp() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	assert_eq(def.hull_hp[0], 9)
	assert_eq(def.hull_hp[3], 10)

# --- Ship Helper Methods ---

func test_get_total_crew_frigate() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.get_total_crew(), 12, "Frigate total crew: 3+3+3+3 = 12")

func test_get_total_crew_sol() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	assert_eq(def.get_total_crew(), 26, "SOL total crew: 6+6+7+7 = 26")

func test_get_total_rigging_hp_frigate() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.get_total_rigging_hp(), 22, "Frigate total rigging HP: 5+5+6+6 = 22")

func test_get_total_hull_hp_frigate() -> void:
	var def = dm.get_ship_definition("frigate_38")
	assert_eq(def.get_total_hull_hp(), 21, "Frigate total hull HP: 5+5+5+6 = 21")

func test_get_total_rigging_hp_sol() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	assert_eq(def.get_total_rigging_hp(), 28, "SOL total rigging HP: 7+7+7+7 = 28")

func test_get_total_hull_hp_sol() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	assert_eq(def.get_total_hull_hp(), 37, "SOL total hull HP: 9+9+9+10 = 37")

# --- Gun Counting ---

func test_frigate_38_gun_count() -> void:
	var def = dm.get_ship_definition("frigate_38")
	# 19 port + 19 starboard + 2 bow chasers + 2 stern chasers = 42
	assert_eq(def.get_gun_count(), 42, "Frigate should have 42 total guns")

func test_corvette_24_gun_count() -> void:
	var def = dm.get_ship_definition("corvette_24")
	# 12 port + 12 starboard = 24
	assert_eq(def.get_gun_count(), 24, "Corvette should have 24 total guns")

func test_sol_74_gun_count() -> void:
	var def = dm.get_ship_definition("ship_of_line_74")
	# All SOL guns are under long_guns (doubly-nested), so get_gun_count works correctly
	# 14*6 = 84 (lower port/starboard, main port/starboard, gun deck port/starboard)
	assert_eq(def.get_gun_count(), 84, "SOL should have 84 total guns")

# --- Ship.from_dict() / to_dict() Roundtrip ---

func test_to_dict_roundtrip() -> void:
	var original = dm.get_ship_definition("frigate_38")
	var dict = original.to_dict()
	var restored = Ship.from_dict(dict)
	assert_eq(restored.name, original.name)
	assert_eq(restored.rating, original.rating)
	assert_eq(restored.speed_type, original.speed_type)
	assert_eq(restored.draft, original.draft)
	assert_eq(restored.marine_count, original.marine_count)

func test_to_dict_preserves_arrays() -> void:
	var original = dm.get_ship_definition("ship_of_line_74")
	var dict = original.to_dict()
	var restored = Ship.from_dict(dict)
	for i in range(4):
		assert_eq(restored.rigging_hp[i], original.rigging_hp[i], "rigging_hp[%d] should match" % i)
		assert_eq(restored.hull_hp[i], original.hull_hp[i], "hull_hp[%d] should match" % i)
		assert_eq(restored.crew_count[i], original.crew_count[i], "crew_count[%d] should match" % i)

# --- from_dict() Defaults ---

func test_from_dict_with_minimal_data() -> void:
	var def = Ship.from_dict({})
	assert_eq(def.name, "Unknown Ship", "Missing name should default to 'Unknown Ship'")
	assert_eq(def.nationality, "Unknown", "Missing nationality should default to 'Unknown'")
	assert_eq(def.rating, 0, "Missing rating should default to 0")
	assert_eq(def.speed_type, "F/F", "Missing speed_type should default to 'F/F'")

func test_from_dict_with_partial_data() -> void:
	var def = Ship.from_dict({"name": "Test Ship", "rating": 20})
	assert_eq(def.name, "Test Ship")
	assert_eq(def.rating, 20)
	assert_eq(def.ship_class, 0, "Missing class should default to 0")
