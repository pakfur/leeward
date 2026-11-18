extends GutTest
## Tow state on the ship (towing spec): towing_id / towed_by / tow_prepared, the controller mutators,
## the drift group, serialisation, the standing tow order and the 5.E.5 acceleration reduction.

var _old_scenario: Dictionary
var _old_env: EnvironmentState


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()


func before_each() -> void:
	_old_scenario = GameState.active_scenario
	_old_env = GameState.environment
	GameState.active_scenario = {}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env


func after_each() -> void:
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, maneuverability: String = "C") -> ShipState:
	var ship_def := Ship.from_dict({
		"ship_id": id, "player_id": 0, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": maneuverability, "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	var state := ShipState.new()
	state.initialize_from_scenario({"position": {"q": hex.x, "r": hex.y}, "facing": 3}, ship_def)
	state.side = 0
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_side[0].append(id)
	return state


func _ctl() -> ShipStateController:
	return GameState.ship_controller


func test_new_ship_in_no_tow() -> void:
	var t := _make_ship("t", Vector2i(0, 0))
	assert_false(t.is_towing())
	assert_false(t.is_towed())
	assert_eq(t.tow_partner(), "")
	assert_false(t.tow_prepared)
	assert_true(t.drift_group_ids().is_empty())


func test_begin_tow_sets_both_ends() -> void:
	var t := _make_ship("t", Vector2i(0, 0))
	var w := _make_ship("w", Vector2i(0, 2))
	assert_true(_ctl().set_tow_prepared("t", true))
	assert_true(t.tow_prepared)
	assert_true(_ctl().begin_tow("t", "w"))
	assert_eq(t.towing_id, "w")
	assert_eq(w.towed_by, "t")
	assert_false(t.tow_prepared, "the prepared tow is used up")
	assert_eq(t.tow_partner(), "w")
	assert_eq(w.tow_partner(), "t")
	assert_true(t.is_towing())
	assert_true(w.is_towed())
	assert_false(t.is_linked(), "a tow is not a link")
	assert_true(t.linked_ids().is_empty())


func test_begin_tow_refuses_bad_pairs() -> void:
	_make_ship("t", Vector2i(0, 0))
	_make_ship("w", Vector2i(0, 2))
	_make_ship("x", Vector2i(0, 4))
	_make_ship("y", Vector2i(0, 6))
	assert_false(_ctl().begin_tow("t", "t"))
	assert_push_error(1, "a ship cannot tow herself")
	assert_true(_ctl().begin_tow("t", "w"))
	assert_false(_ctl().begin_tow("t", "x"))
	assert_push_error(2, "a tower already towing is refused")
	assert_false(_ctl().begin_tow("y", "w"))
	assert_push_error(3, "a ship already in tow is refused")
	assert_false(_ctl().begin_tow("t", "nope"))
	assert_push_error("Ship not found", "unknown ship")


func test_cut_tow_from_either_end() -> void:
	var t := _make_ship("t", Vector2i(0, 0))
	var w := _make_ship("w", Vector2i(0, 2))
	_ctl().begin_tow("t", "w")
	assert_true(_ctl().cut_tow("w"))
	assert_eq(t.towing_id, "")
	assert_eq(w.towed_by, "")
	assert_false(_ctl().cut_tow("w"))
	assert_push_error(0, "no error for a ship in no tow")
	_ctl().begin_tow("t", "w")
	assert_true(_ctl().cut_tow("t"))
	assert_false(t.is_towing())
	assert_false(w.is_towed())


func test_drift_group_ids_adds_partner() -> void:
	var t := _make_ship("t", Vector2i(0, 0))
	var w := _make_ship("w", Vector2i(0, 2))
	_make_ship("x", Vector2i(1, 0))
	_ctl().set_fouled_with("t", "x")
	_ctl().set_fouled_with("x", "t")
	_ctl().begin_tow("t", "w")
	assert_eq(t.drift_group_ids(), ["w", "x"] as Array[String])
	assert_eq(w.drift_group_ids(), ["t"] as Array[String])
	assert_eq(t.linked_ids(), ["x"] as Array[String], "linked_ids leaves the tow out")


func test_remove_from_map_clears_tow() -> void:
	var t := _make_ship("t", Vector2i(0, 0))
	var w := _make_ship("w", Vector2i(0, 2))
	_ctl().begin_tow("t", "w")
	assert_true(_ctl().remove_from_map("w"))
	assert_eq(t.towing_id, "")
	assert_eq(w.towed_by, "")


func test_serialize_round_trip_tow() -> void:
	var t := _make_ship("t", Vector2i(0, 0))
	var w := _make_ship("w", Vector2i(0, 2))
	_ctl().begin_tow("t", "w")
	_ctl().set_tow_prepared("t", true)
	var data := t.serialize()
	assert_false(data.has("towing"), "the old flag is gone")
	var copy := ShipState.deserialize(data)
	assert_eq(copy.towing_id, "w")
	assert_eq(copy.towed_by, "")
	assert_true(copy.tow_prepared)
	var copy_w := ShipState.deserialize(w.serialize())
	assert_eq(copy_w.towed_by, "t")
	assert_eq(copy_w.towing_id, "")
	assert_false(copy_w.tow_prepared)


func test_take_order_stands_cut_lapses() -> void:
	var t := _make_ship("t", Vector2i(0, 0))
	_ctl().set_crew_orders("t", {"tow": "take:w"})
	_ctl().clear_crew_plot("t")
	assert_eq(t.tow_order(), "take:w")
	_ctl().clear_plotted_actions("t")
	assert_eq(t.tow_order(), "take:w")
	_ctl().set_crew_orders("t", {"tow": "cut"})
	_ctl().clear_crew_plot("t")
	assert_eq(t.tow_order(), "")
	_ctl().set_crew_orders("t", {"tow": "cut"})
	_ctl().clear_plotted_actions("t")
	assert_eq(t.tow_order(), "")


func test_towing_reduces_acceleration() -> void:
	var t := _make_ship("t", Vector2i(0, 0), "D")
	assert_eq(_ctl().speed_change_limits(t).accel, 3, "type D accelerates 3")
	t.towing_id = "w"
	assert_eq(_ctl().speed_change_limits(t).accel, 2, "towing: -1 (5.E.5)")
