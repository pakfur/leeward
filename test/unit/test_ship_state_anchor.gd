extends GutTest
## Anchor state on the ship (anchoring spec §1): the fields, the controller mutators, serialisation,
## and that an anchored ship cannot plot.

var _old_dice: Dice
var _old_scenario: Dictionary
var _old_env: EnvironmentState


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	_old_dice = GameState.dice
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
	GameState.dice = _old_dice
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, entry: Dictionary = {}) -> ShipState:
	var ship_def := Ship.from_dict({
		"ship_id": id, "player_id": 0, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	var state := ShipState.new()
	var data := {"position": {"q": hex.x, "r": hex.y}, "facing": 3}
	data.merge(entry, true)
	state.initialize_from_scenario(data, ship_def)
	state.side = 0
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_side[0].append(id)
	return state


func _anchor_data(end: String = "bow", springs: bool = false) -> Dictionary:
	return {"hex": Vector2i(0, 0), "end": end, "springs": springs, "cable": 0, "veered": 0,
		"swing_dir": 0, "wind_dir": 0, "turn": 2}


func test_new_ship_not_anchored() -> void:
	var a := _make_ship("a", Vector2i(3, 3))
	assert_false(a.is_anchored())
	assert_false(a.has_springs())
	assert_eq(a.anchor_ready, "")
	assert_eq(a.anchorings_used, 0)
	assert_eq(a.cable_cut_turn, -1)
	assert_eq(a.anchored_end_hex(), a.hex_position)


func test_drop_anchor_sets_state() -> void:
	var a := _make_ship("a", Vector2i(0, 0))
	a.speed = 3
	a.irons_entry_turn = 1
	assert_true(GameState.ship_controller.set_anchor_ready("a", "bow"))
	assert_true(GameState.ship_controller.set_springs_ready("a", true))
	assert_eq(a.anchor_ready, "bow")
	assert_true(a.springs_ready)
	assert_true(GameState.ship_controller.drop_anchor("a", _anchor_data("bow", true)))
	assert_true(a.is_anchored())
	assert_true(a.has_springs())
	assert_eq(a.anchorings_used, 1)
	assert_eq(a.speed, 0)
	assert_eq(a.irons_entry_turn, -1)
	assert_eq(a.anchor_ready, "")
	assert_false(a.springs_ready)


func test_anchored_end_hex() -> void:
	var a := _make_ship("a", Vector2i(0, 0))
	GameState.ship_controller.drop_anchor("a", _anchor_data("stern"))
	assert_eq(a.anchored_end_hex(), Vector2i(1, 0))
	GameState.ship_controller.update_anchor("a", {"end": "bow"})
	assert_eq(a.anchored_end_hex(), Vector2i(0, 0))


func test_update_and_cut() -> void:
	var a := _make_ship("a", Vector2i(0, 0))
	GameState.ship_controller.drop_anchor("a", _anchor_data())
	assert_true(GameState.ship_controller.update_anchor("a", {"cable": 2}))
	assert_eq(a.anchor.cable, 2)
	assert_true(GameState.ship_controller.cut_cable("a", 5))
	assert_false(a.is_anchored())
	assert_eq(a.cable_cut_turn, 5)
	assert_false(GameState.ship_controller.update_anchor("a", {"cable": 1}))
	assert_push_error("not anchored")


func test_set_anchor_ready_rejects_unknown_end() -> void:
	var a := _make_ship("a", Vector2i(0, 0))
	assert_false(GameState.ship_controller.set_anchor_ready("a", "mast"))
	assert_push_error("anchor")
	assert_eq(a.anchor_ready, "")


func test_remove_from_map_clears_anchor() -> void:
	var a := _make_ship("a", Vector2i(0, 0))
	GameState.ship_controller.drop_anchor("a", _anchor_data())
	assert_true(GameState.ship_controller.remove_from_map("a"))
	assert_false(a.is_anchored())


func test_serialize_round_trip_anchor() -> void:
	var a := _make_ship("a", Vector2i(0, 0))
	GameState.ship_controller.drop_anchor("a", {"hex": Vector2i(-2, 1), "end": "stern",
		"springs": true, "cable": 3, "veered": 1, "swing_dir": 1, "wind_dir": 4, "turn": 7})
	a.anchor_ready = "stern"
	a.springs_ready = true
	a.cable_cut_turn = 4
	var b := ShipState.deserialize(a.serialize())
	assert_eq(b.anchor.hex, Vector2i(-2, 1))
	assert_eq(b.anchor.end, "stern")
	assert_true(b.anchor.springs)
	assert_eq(b.anchor.cable, 3)
	assert_eq(b.anchor.veered, 1)
	assert_eq(b.anchor.swing_dir, 1)
	assert_eq(b.anchor.wind_dir, 4)
	assert_eq(b.anchor.turn, 7)
	assert_eq(b.anchor_ready, "stern")
	assert_true(b.springs_ready)
	assert_eq(b.anchorings_used, 1)
	assert_eq(b.cable_cut_turn, 4)
	var c := ShipState.deserialize(_make_ship("c", Vector2i(5, 5)).serialize())
	assert_true(c.anchor.is_empty())


func test_anchored_ship_cannot_plot() -> void:
	var a := _make_ship("a", Vector2i(0, 0))
	GameState.ship_controller.drop_anchor("a", _anchor_data())
	a.speed = 3
	assert_false(DefaultCourse.can_plot(a))
	assert_true(DefaultCourse.for_ship(GameState, a).is_empty())
	GameState.movement_plotting_controller.sessions.clear()
	GameState.movement_plotting_controller.ship_sessions.clear()
	var response := GameState.movement_plotting_controller.handle_start_plotting(0, "a", "req")
	assert_true(response is MovementTypes.PlottingErrorResponse)
	assert_eq((response as MovementTypes.PlottingErrorResponse).error_code, "SHIP_ANCHORED")
