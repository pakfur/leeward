extends GutTest
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
## Tests for ShipState combat fields and the ShipStateController mutators added for them.

var state: ShipState


func before_all() -> void:
	DataManager.load_ship_definitions()


var _saved_turn := 0


func before_each() -> void:
	_saved_turn = GameState.current_turn
	state = _make_state({})
	GameState.ships.clear()
	GameState.ships_by_player.clear()
	GameState.add_ship(state)


func after_each() -> void:
	GameState.ship_controller.is_server = true
	GameState.current_turn = _saved_turn
	GameState.ship_history.erase("ss_ship")
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


func test_max_and_movement_sail_state_follow_rigging_level() -> void:
	state.sail_state = "PS"
	state.rigging_current_hp = [0, 5, 6, 6] as Array[int]
	assert_eq(state.max_sail_state(), "MS")
	assert_eq(state.movement_sail_state(), "MS")
	assert_eq(state.sail_state, "PS", "carried sail is not forced down")
	state.rigging_current_hp = [0, 0, 6, 6] as Array[int]
	assert_eq(state.max_sail_state(), "FS")
	state.rigging_current_hp = [0, 0, 0, 6] as Array[int]
	assert_eq(state.max_sail_state(), "FS")
	state.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(state.max_sail_state(), "NS")
	assert_eq(state.movement_sail_state(), "NS")


func test_movement_sail_state_uses_lower_of_carried_and_max() -> void:
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.sail_state = "FS"
	assert_eq(state.movement_sail_state(), "FS")
	state.sail_state = "NS"
	assert_eq(state.movement_sail_state(), "NS")


func test_controller_rigging_quality_is_section_count() -> void:
	state.rigging_current_hp = [0, 5, 6, 6] as Array[int]
	assert_eq(GameState.ship_controller.get_rigging_quality(state.ship_id), 3)


func test_sections_able_to_fire_excludes_sail_change_and_empty() -> void:
	# 4.B.4: sailor sections plotted to a task, and empty ones, do not serve the guns.
	state.crew_count = [0, 3, 3, 3] as Array[int]
	CrewFixtures.give_sail_change(state, "FS", [3])
	assert_eq(state.sections_able_to_fire(), 2)


func test_sections_able_to_fire_ignores_marines() -> void:
	# 4.B.4: only sailor sections serve the guns; marines altering sail cost no gunfire.
	CrewFixtures.give_sail_change(state, "FS", [ShipState.MARINES])
	assert_eq(state.sections_able_to_fire(), 4)


func test_total_crew_boxes_sums_sailors_and_marines() -> void:
	assert_eq(state.total_crew_boxes(), 14)


# --- serialisation ---

func test_serialize_round_trip_keeps_new_fields() -> void:
	state.status = ShipState.Status.STRUCK
	state.morale_rating = 2
	state.crew_quality = "E"
	state.guns_dismounted = [2, 1] as Array[int]
	state.initial_broadside_fired = [true, false] as Array[bool]
	CrewFixtures.give_sail_change(state, "PS", [0, 1], 1)
	state.crew_auto = false
	state.mp_used_this_turn = 5
	state.plotted_actions["crew_assignments"] = {2: {"code": "SAIL", "params": {"target": "PS"}}}
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
	assert_eq(restored.sail_change_info().get("target"), "PS")
	assert_eq(restored.sail_change_info().get("sections").size(), 2)
	assert_eq(restored.crew_tasks[0]["done"], 1)
	assert_eq(restored.task_seq, state.task_seq)
	assert_eq(restored.plotted_sections, [0, 1] as Array[int])
	assert_false(restored.crew_auto)
	assert_eq(restored.mp_used_this_turn, 5)
	assert_eq(restored.plotted_actions["crew_assignments"].keys(), [2], "section keys stay ints")
	assert_true(restored.moved_this_turn)
	assert_eq(restored.pending_morale_checks, 2)
	assert_eq(restored.morale_triggers_used, ["hull_1"] as Array[String])
	assert_eq(restored.unfoul_attempts, 3)
	assert_eq(restored.crew_count.size(), 4)


func test_serialize_round_trip_keeps_destroyed_status() -> void:
	state.status = ShipState.Status.DESTROYED
	var restored := ShipState.deserialize(state.serialize())
	assert_eq(restored.status, ShipState.Status.DESTROYED)
	assert_true(restored.is_destroyed())


func test_out_of_play_covers_struck_and_destroyed() -> void:
	assert_false(state.is_out_of_play())
	state.status = ShipState.Status.STRUCK
	assert_true(state.is_out_of_play())
	assert_false(state.is_destroyed())
	state.status = ShipState.Status.DESTROYED
	assert_true(state.is_out_of_play())
	assert_true(state.is_destroyed())
	assert_false(state.is_struck(), "destroyed is its own status, not struck")


func test_deserialize_old_snapshot_uses_defaults() -> void:
	var data := state.serialize()
	for key in ["status", "guns_dismounted", "initial_broadside_fired", "crew_tasks",
			"moved_this_turn", "pending_morale_checks", "morale_triggers_used",
			"unfoul_attempts", "morale_rating", "crew_quality"]:
		data.erase(key)
	var restored := ShipState.deserialize(data)
	assert_eq(restored.status, ShipState.Status.ACTIVE)
	assert_eq(restored.guns_dismounted, [0, 0] as Array[int])
	assert_eq(restored.sail_change_info(), {})
	assert_true(restored.crew_auto, "Automatic crew is on by default (spec §3.3)")
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
	var seq := c.add_task("ss_ship", {"code": "SAIL", "sections": [0], "params": {"target": "FS"}})
	assert_eq(state.sail_change_info().target, "FS")
	assert_true(c.end_task("ss_ship", seq, "test"))
	assert_eq(state.sail_change_info(), {})
	assert_true(c.set_moved_this_turn("ss_ship", true))
	assert_true(state.moved_this_turn)
	assert_true(c.set_crew_quality("ss_ship", "C"))
	assert_eq(state.crew_quality, "C")
	assert_true(c.set_morale_rating("ss_ship", 9))
	assert_eq(state.morale_rating, 6, "clamped to the rulebook maximum 6")
	assert_true(c.set_unfoul_attempts("ss_ship", 2))
	assert_eq(state.unfoul_attempts, 2)


func test_morale_rating_range_is_2_to_6() -> void:
	var c := GameState.ship_controller
	c.set_morale_rating("ss_ship", 6)
	assert_eq(state.morale_rating, 6, "6 is a legal rating")
	c.set_morale_rating("ss_ship", 1)
	assert_eq(state.morale_rating, 2, "clamped to the minimum 2")


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


# --- GameState.add_ship ---

func test_add_ship_rejects_duplicate_id() -> void:
	var duplicate := _make_state({})
	assert_false(GameState.add_ship(duplicate), "a second ship with the same id is rejected")
	assert_push_error("ss_ship")
	assert_eq(GameState.ships.size(), 1, "one entry in ships")
	assert_same(GameState.ships["ss_ship"], state, "the first ship is kept")
	assert_eq(GameState.ships_by_player[1], ["ss_ship"], "one entry in ships_by_player")


func test_add_ship_rejects_ship_on_occupied_hex() -> void:
	var stacked := _make_state({"id": "ss_other", "position": {"q": 1, "r": 1}})
	assert_false(GameState.add_ship(stacked), "a ship starting on an occupied hex is rejected")
	assert_push_error("ship 'ss_other' starts on (1, 1), already occupied by 'ss_ship'")
	assert_false(GameState.ships.has("ss_other"), "not added to ships")
	assert_eq(GameState.ships_by_player[1], ["ss_ship"], "not added to ships_by_player")


func test_add_ship_rejects_stern_on_occupied_hex() -> void:
	# ss_ship: bow (1,1) facing E, stern (0,1). A bow at (2,1) facing E puts its stern on (1,1).
	var astern := _make_state({"id": "ss_other", "position": {"q": 2, "r": 1}})
	assert_false(GameState.add_ship(astern), "a stern on another ship's bow is rejected")
	assert_push_error("ship 'ss_other' starts on (1, 1), already occupied by 'ss_ship'")
	# A bow at (0,2) facing SE puts its stern on ss_ship's stern (0,1).
	var stern_on_stern := _make_state({"id": "ss_third", "position": {"q": 0, "r": 2}, "facing": 1})
	assert_false(GameState.add_ship(stern_on_stern), "a stern on another ship's stern is rejected")
	assert_push_error("ship 'ss_third' starts on (0, 1), already occupied by 'ss_ship'")
	assert_eq(GameState.ships.size(), 1)
	assert_eq(GameState.ships_by_player[1], ["ss_ship"])


func test_add_ship_accepts_ship_on_free_hex() -> void:
	# Bow (3,1), stern (2,1): clear of ss_ship's bow (1,1) and stern (0,1).
	var other := _make_state({"id": "ss_other", "position": {"q": 3, "r": 1}})
	assert_true(GameState.add_ship(other))
	assert_eq(GameState.ships.size(), 2)


# --- critical hits: helpers ---

func _effect(id: String, side: int = -1) -> Dictionary:
	return {"seq": 0, "id": id, "turn": 1, "side": side, "attempts": 0, "expires_after_turn": -1}


func test_new_ship_has_no_criticals() -> void:
	assert_eq(state.critical_effects.size(), 0)
	assert_eq(state.critical_seq, 0)
	assert_false(state.rudder_destroyed)
	assert_false(state.wheel_shot_away)
	assert_eq(state.fire_count(), 0)
	assert_false(state.is_burning())
	assert_false(state.has_critical("braces_cut"))
	assert_eq(state.critical_mp_loss(), 0)
	assert_false(state.is_poor_maneuvering())
	assert_eq(state.max_turns_per_gt(), ShipState.UNLIMITED_TURNS)


func test_has_critical_and_count_by_side() -> void:
	state.critical_effects = [
		_effect("broadside_obscured", ShipState.PORT),
		_effect("broadside_obscured", ShipState.PORT),
		_effect("broadside_obscured", ShipState.STARBOARD),
		_effect("braces_cut"),
	] as Array[Dictionary]
	assert_true(state.has_critical("braces_cut"))
	assert_false(state.has_critical("lines_jammed"))
	assert_eq(state.critical_count("broadside_obscured"), 3)
	assert_eq(state.critical_count("broadside_obscured", ShipState.PORT), 2)
	assert_eq(state.critical_count("broadside_obscured", ShipState.STARBOARD), 1)


func test_obscured_penalty_is_minus_two_per_entry_on_that_side() -> void:
	# 7.C.11: falling rigging / yard shot away, -2 per entry on the broadside.
	state.critical_effects = [
		_effect("broadside_obscured", ShipState.PORT),
		_effect("broadside_obscured", ShipState.PORT),
		_effect("broadside_obscured", ShipState.STARBOARD),
	] as Array[Dictionary]
	assert_eq(state.obscured_penalty(ShipState.PORT), -4)
	assert_eq(state.obscured_penalty(ShipState.STARBOARD), -2)


func test_critical_mp_loss_caps_sheets_cut_at_one() -> void:
	# Rigging #7: only one sheets cut per ship per g-t; #9 shrouds stack.
	state.critical_effects = [
		_effect("sheets_cut"), _effect("sheets_cut"),
		_effect("shrouds_severed"), _effect("shrouds_severed"),
	] as Array[Dictionary]
	assert_eq(state.critical_mp_loss(), 3)


func test_poor_maneuvering_from_rudder_or_wheel() -> void:
	# Hull #2 (rudder destroyed) and #3 (wheel shot away): one 60-degree turn per g-t.
	state.rudder_destroyed = true
	assert_true(state.is_poor_maneuvering())
	assert_eq(state.max_turns_per_gt(), 1)
	state.rudder_destroyed = false
	state.wheel_shot_away = true
	assert_true(state.is_poor_maneuvering())
	assert_eq(state.max_turns_per_gt(), 1)


func test_serialize_round_trip_keeps_critical_fields() -> void:
	state.critical_effects = [_effect("rudder_jammed", ShipState.STARBOARD)] as Array[Dictionary]
	state.critical_effects[0]["seq"] = 4
	state.critical_effects[0]["attempts"] = 2
	state.critical_seq = 5
	state.rudder_destroyed = true
	state.wheel_shot_away = true
	state.fire_list = [{"seq": 1, "created_turn": 2, "started_turn": 2, "cause": "crit"},
		{"seq": 3, "created_turn": 4, "started_turn": 5, "cause": "growth"}] as Array[Dictionary]
	state.fire_seq = 3
	state.explosion_checks = 1
	var restored := ShipState.deserialize(JSON.parse_string(JSON.stringify(state.serialize())))
	assert_eq(restored.critical_effects.size(), 1)
	assert_eq(restored.critical_effects[0]["id"], "rudder_jammed")
	assert_eq(restored.critical_effects[0]["side"], ShipState.STARBOARD)
	assert_eq(restored.critical_effects[0]["seq"], 4)
	assert_eq(restored.critical_effects[0]["attempts"], 2)
	assert_eq(restored.critical_seq, 5)
	assert_true(restored.rudder_destroyed)
	assert_true(restored.wheel_shot_away)
	assert_eq(restored.fire_seqs(), [1, 3] as Array[int], "spec §8 #57: fires round-trip")
	assert_eq(restored.fire_by_seq(3), {"seq": 3, "created_turn": 4, "started_turn": 5, "cause": "growth"})
	assert_eq(restored.fire_seq, 3)
	assert_eq(restored.explosion_checks, 1)
	restored.critical_effects[0]["attempts"] = 9
	assert_eq(state.critical_effects[0]["attempts"], 2, "restored effects are copies")


func test_deserialize_old_snapshot_has_no_criticals() -> void:
	var data := state.serialize()
	for key in ["critical_effects", "critical_seq", "rudder_destroyed", "wheel_shot_away", "fire_list",
			"fire_seq", "explosion_checks"]:
		data.erase(key)
	var restored := ShipState.deserialize(data)
	assert_eq(restored.critical_effects.size(), 0)
	assert_eq(restored.critical_seq, 0)
	assert_false(restored.rudder_destroyed)
	assert_eq(restored.fire_count(), 0)


func test_deserialize_old_fires_count_becomes_fire_list() -> void:
	# Saves from before fire was simulated stored only "fires": n.
	var data := state.serialize()
	for key in ["fire_list", "fire_seq", "explosion_checks"]:
		data.erase(key)
	data["fires"] = 2
	var restored := ShipState.deserialize(data)
	assert_eq(restored.fire_seqs(), [1, 2] as Array[int])
	assert_eq(restored.fire_seq, 2)


func test_snapshot_does_not_share_critical_effects() -> void:
	GameState.ship_controller.add_critical_effect("ss_ship", {"id": "braces_cut"})
	GameState.save_ship_snapshot("ss_ship", 1)
	GameState.ship_controller.update_critical_effect("ss_ship", 0, {"attempts": 3})
	GameState.ship_controller.add_critical_effect("ss_ship", {"id": "lines_jammed"})
	var snap: ShipState = GameState.ship_history["ss_ship"][1]
	assert_eq(snap.critical_effects.size(), 1)
	assert_eq(snap.critical_effects[0]["attempts"], 0)


# --- critical hits: controller mutators ---

func test_add_critical_effect_fills_defaults_and_numbers_seq() -> void:
	var c := GameState.ship_controller
	GameState.current_turn = 3
	assert_eq(c.add_critical_effect("ss_ship", {"id": "broadside_obscured", "side": ShipState.PORT}), 0)
	assert_eq(c.add_critical_effect("ss_ship", {"id": "sheets_cut", "expires_after_turn": 4}), 1)
	assert_eq(state.critical_seq, 2)
	var first: Dictionary = state.critical_effects[0]
	assert_eq(first, {"seq": 0, "id": "broadside_obscured", "turn": 3, "side": ShipState.PORT,
			"attempts": 0, "expires_after_turn": -1})
	assert_eq(state.critical_effects[1]["expires_after_turn"], 4)
	assert_eq(state.critical_effects[1]["side"], -1)


func test_add_critical_effect_rejects_unknown_id() -> void:
	assert_eq(GameState.ship_controller.add_critical_effect("ss_ship", {"id": "made_up"}), -1)
	assert_push_error("unknown critical effect")
	assert_eq(state.critical_effects.size(), 0)
	assert_eq(state.critical_seq, 0)


func test_update_and_remove_critical_effect() -> void:
	var c := GameState.ship_controller
	c.add_critical_effect("ss_ship", {"id": "braces_cut"})
	var seq := c.add_critical_effect("ss_ship", {"id": "lines_jammed"})
	assert_true(c.update_critical_effect("ss_ship", seq, {"attempts": 1, "seq": 99, "id": "x"}))
	assert_eq(state.critical_effects[1]["attempts"], 1)
	assert_eq(state.critical_effects[1]["seq"], seq, "seq cannot be changed")
	assert_eq(state.critical_effects[1]["id"], "lines_jammed", "id cannot be changed")
	assert_true(c.remove_critical_effect("ss_ship", 0))
	assert_eq(state.critical_effects.size(), 1)
	assert_eq(state.critical_effects[0]["id"], "lines_jammed")
	assert_false(c.remove_critical_effect("ss_ship", 0), "already removed")
	assert_false(c.update_critical_effect("ss_ship", 42, {"attempts": 1}))
	assert_push_error(2, "one error per missing seq")


func test_steering_and_fire_mutators() -> void:
	var c := GameState.ship_controller
	assert_true(c.set_rudder_destroyed("ss_ship", true))
	assert_true(state.rudder_destroyed)
	assert_true(c.set_wheel_shot_away("ss_ship", true))
	assert_true(state.wheel_shot_away)
	assert_eq(c.add_fire("ss_ship", "crit"), 1)
	assert_eq(c.add_fire("ss_ship", "spread", true), 2)
	assert_eq(state.fire_count(), 2)
	var turn: int = GameState.current_turn
	assert_eq(state.fire_by_seq(1)["started_turn"], turn, "a Combat Phase fire burns this g-t")
	assert_eq(state.fire_by_seq(2)["started_turn"], turn + 1, "a Fire sub-phase fire burns from the next (0.3 #5)")
	assert_true(c.remove_fire("ss_ship", 1))
	assert_eq(state.fire_seqs(), [2] as Array[int])
	assert_true(c.set_explosion_checks("ss_ship", 2))
	assert_eq(state.explosion_checks, 2)
	assert_true(c.clear_fires("ss_ship"))
	assert_false(state.is_burning())


func test_cross_out_rigging_section_takes_current_section() -> void:
	# Current rigging section = lowest-numbered section with boxes left.
	var c := GameState.ship_controller
	state.rigging_current_hp = [0, 3, 2, 4] as Array[int]
	assert_eq(c.cross_out_rigging_section("ss_ship"), 1)
	assert_eq(state.rigging_current_hp, [0, 0, 2, 4] as Array[int])
	state.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(c.cross_out_rigging_section("ss_ship"), -1, "dismasted: nothing to cross out")


func test_critical_mutators_refused_on_client() -> void:
	var c := GameState.ship_controller
	c.add_critical_effect("ss_ship", {"id": "braces_cut"})
	state.rigging_current_hp = [3, 3, 3, 3] as Array[int]
	c.is_server = false
	assert_eq(c.add_critical_effect("ss_ship", {"id": "lines_jammed"}), -1)
	assert_false(c.update_critical_effect("ss_ship", 0, {"attempts": 2}))
	assert_false(c.remove_critical_effect("ss_ship", 0))
	assert_false(c.set_rudder_destroyed("ss_ship", true))
	assert_false(c.set_wheel_shot_away("ss_ship", true))
	assert_eq(c.add_fire("ss_ship", "crit"), -1)
	assert_eq(c.cross_out_rigging_section("ss_ship"), -1)
	c.is_server = true
	assert_push_error(7, "seven client refusals")
	assert_eq(state.critical_effects.size(), 1)
	assert_eq(state.critical_effects[0]["attempts"], 0)
	assert_false(state.rudder_destroyed)
	assert_false(state.wheel_shot_away)
	assert_eq(state.fire_count(), 0)
	assert_eq(state.rigging_current_hp, [3, 3, 3, 3] as Array[int])
