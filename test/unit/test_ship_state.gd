extends GutTest
## Tests for ShipState combat fields and the ShipStateController mutators added for them.

var state: ShipState


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	state = _make_state({})
	GameState.ships.clear()
	GameState.ships_by_player.clear()
	GameState.add_ship(state)


func after_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player.clear()


func _make_state(overrides: Dictionary) -> ShipState:
	var data := {
		"id": "ss_ship",
		"player_id": 1,
		"ship_type": "frigate_38",
		"ship_name": "Test",
		"position": {"q": 1, "r": 1},
		"facing": 0,
		"sail_state": "MS",
		"crew_quality": "B",
		"crew_morale": 4,
	}
	data.merge(overrides, true)
	var ship_ref := Ship.initialize_from_scenario(data, DataManager.get_ship_definition("frigate_38").to_dict())
	var s := ShipState.new()
	s.initialize_from_scenario(data, ship_ref)
	return s


# --- initialisation ---

func test_crew_initialised_from_definition() -> void:
	assert_eq(state.crew_count, [3, 3, 3, 3] as Array[int])
	assert_eq(state.marine_count, 2)


func test_scenario_crew_quality_word_normalised() -> void:
	var s := _make_state({"crew_quality": "Trained"})
	assert_eq(s.crew_quality, "D")


func test_morale_rating_reads_legacy_key() -> void:
	var s := _make_state({"crew_morale": 3})
	assert_eq(s.morale_rating, 3)


func test_morale_rating_reads_new_key() -> void:
	var data := {"morale_rating": 5}
	var s := ShipState.new()
	s.initialize_from_scenario(data, DataManager.get_ship_definition("frigate_38"))
	assert_eq(s.morale_rating, 5)


# --- derived queries ---

func test_rigging_level_counts_sections_with_boxes() -> void:
	state.rigging_current_hp = [0, 5, 6, 6] as Array[int]
	assert_eq(state.rigging_level(), 3)
	assert_false(state.is_dismasted())
	state.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(state.rigging_level(), 0)
	assert_true(state.is_dismasted())


func test_sections_able_to_fire_excludes_sail_change_and_empty() -> void:
	state.crew_count = [0, 3, 3, 3] as Array[int]
	state.sail_change = {"target": "FS", "turns_left": 2, "sections": [3]}
	assert_eq(state.sections_able_to_fire(), 2)


func test_total_crew_boxes_sums_sailors_and_marines() -> void:
	assert_eq(state.total_crew_boxes(), 14)


# --- serialisation ---

func test_serialize_round_trip_keeps_new_fields() -> void:
	state.status = ShipState.Status.STRUCK
	state.morale_rating = 2
	state.crew_quality = "E"
	state.guns_dismounted = [2, 1] as Array[int]
	state.initial_broadside_fired = [true, false] as Array[bool]
	state.sail_change = {"target": "PS", "turns_left": 1, "sections": [0, 1]}
	state.moved_this_turn = true
	state.pending_morale_checks = 2
	state.morale_triggers_used = ["hull_1"] as Array[String]
	state.unfoul_attempts = 3
	var restored := ShipState.deserialize(state.serialize())
	assert_eq(restored.status, ShipState.Status.STRUCK)
	assert_eq(restored.morale_rating, 2)
	assert_eq(restored.crew_quality, "E")
	assert_eq(restored.guns_dismounted, [2, 1] as Array[int])
	assert_eq(restored.initial_broadside_fired, [true, false] as Array[bool])
	assert_eq(restored.sail_change.get("target"), "PS")
	assert_eq(restored.sail_change.get("turns_left"), 1)
	assert_eq(restored.sail_change.get("sections").size(), 2)
	assert_true(restored.moved_this_turn)
	assert_eq(restored.pending_morale_checks, 2)
	assert_eq(restored.morale_triggers_used, ["hull_1"] as Array[String])
	assert_eq(restored.unfoul_attempts, 3)
	assert_eq(restored.crew_count.size(), 4)


func test_deserialize_old_snapshot_uses_defaults() -> void:
	var data := state.serialize()
	for key in ["status", "guns_dismounted", "initial_broadside_fired", "sail_change",
			"moved_this_turn", "pending_morale_checks", "morale_triggers_used",
			"unfoul_attempts", "morale_rating", "crew_quality"]:
		data.erase(key)
	var restored := ShipState.deserialize(data)
	assert_eq(restored.status, ShipState.Status.ACTIVE)
	assert_eq(restored.guns_dismounted, [0, 0] as Array[int])
	assert_eq(restored.sail_change, {})
	assert_eq(restored.morale_rating, 4)


func test_snapshot_duplicate_keeps_new_fields() -> void:
	state.guns_dismounted = [1, 0] as Array[int]
	state.unfoul_attempts = 2
	GameState.save_ship_snapshot("ss_ship", 1)
	var snap: ShipState = GameState.ship_history["ss_ship"][1]
	assert_eq(snap.guns_dismounted, [1, 0] as Array[int])
	assert_eq(snap.unfoul_attempts, 2)


# --- controller mutators ---

func test_remove_crew_box_order() -> void:
	var c := GameState.ship_controller
	state.crew_count = [1, 2, 0, 0] as Array[int]
	assert_eq(c.remove_crew_box("ss_ship", false), 0, "section 0 emptied")
	assert_eq(state.crew_count[0], 0)
	assert_eq(c.remove_crew_box("ss_ship", false), -1, "section 1 not emptied")
	assert_eq(c.remove_crew_box("ss_ship", false), 1, "section 1 emptied")


func test_remove_crew_box_marine_and_fallback() -> void:
	var c := GameState.ship_controller
	state.crew_count = [0, 0, 0, 1] as Array[int]
	state.marine_count = 1
	assert_eq(c.remove_crew_box("ss_ship", true), 4, "marines emptied")
	assert_eq(state.marine_count, 0)
	assert_eq(c.remove_crew_box("ss_ship", true), 3, "no marines: takes a sailor")
	assert_eq(c.remove_crew_box("ss_ship", false), -1, "nothing left")


func test_note_morale_check_once_per_trigger() -> void:
	var c := GameState.ship_controller
	assert_true(c.note_morale_check("ss_ship", "hull_1"))
	assert_false(c.note_morale_check("ss_ship", "hull_1"))
	assert_eq(state.pending_morale_checks, 1)
	assert_true(c.note_morale_check("ss_ship", "crew_1", 2))
	assert_eq(state.pending_morale_checks, 3)
	assert_true(c.clear_pending_morale_checks("ss_ship"))
	assert_eq(state.pending_morale_checks, 0)


func test_simple_mutators() -> void:
	var c := GameState.ship_controller
	assert_true(c.set_status("ss_ship", ShipState.Status.STRUCK))
	assert_true(state.is_struck())
	assert_true(c.add_guns_dismounted("ss_ship", 2))
	assert_eq(state.guns_dismounted, [2, 2] as Array[int])
	assert_true(c.set_initial_broadside_fired("ss_ship", ShipState.STARBOARD))
	assert_eq(state.initial_broadside_fired, [false, true] as Array[bool])
	assert_true(c.set_sail_change("ss_ship", {"target": "FS", "turns_left": 2, "sections": [0]}))
	assert_eq(state.sail_change.target, "FS")
	assert_true(c.set_moved_this_turn("ss_ship", true))
	assert_true(state.moved_this_turn)
	assert_true(c.set_crew_quality("ss_ship", "C"))
	assert_eq(state.crew_quality, "C")
	assert_true(c.set_morale_rating("ss_ship", 9))
	assert_eq(state.morale_rating, 5)
	assert_true(c.set_unfoul_attempts("ss_ship", 2))
	assert_eq(state.unfoul_attempts, 2)


func test_set_fouled_with_resets_unfoul_attempts() -> void:
	var c := GameState.ship_controller
	c.set_unfoul_attempts("ss_ship", 2)
	c.set_fouled_with("ss_ship", "other")
	assert_eq(state.unfoul_attempts, 0)
	c.set_unfoul_attempts("ss_ship", 1)
	c.set_fouled_with("ss_ship", "")
	assert_eq(state.unfoul_attempts, 0)


func test_mutators_unknown_ship_return_false() -> void:
	var c := GameState.ship_controller
	assert_false(c.set_status("nope", ShipState.Status.STRUCK))
	assert_push_error("Ship not found")
