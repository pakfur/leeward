extends GutTest
## Ship state for terrain, escape and arrival (map and scenario spec §7): the ESCAPED status, aground,
## the lead, and ships awaiting arrival.

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
	var data := {"position": {"q": hex.x, "r": hex.y}, "facing": 1}
	data.merge(entry, true)
	state.initialize_from_scenario(data, ship_def)
	state.side = 0
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_side[0].append(id)
	return state


func _start_plotting(state: ShipState) -> MovementTypes.PlottingResponse:
	GameState.movement_plotting_controller.sessions.clear()
	GameState.movement_plotting_controller.ship_sessions.clear()
	return GameState.movement_plotting_controller.handle_start_plotting(
			state.side, state.ship.ship_id, "req")


func test_escaped_is_out_of_play_and_not_targetable() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	a.status = ShipState.Status.ESCAPED
	assert_true(a.is_escaped())
	assert_true(a.is_out_of_play())
	assert_false(a.is_targetable())
	assert_false(a.can_be_boarded())
	assert_false(a.crew_can_act())


func test_awaiting_ship_is_off_map_and_out_of_play() -> void:
	var a := _make_ship("a", Vector2i(5, 5), {"arrives": 3})
	assert_true(a.is_awaiting_arrival())
	assert_false(a.is_on_map())
	assert_true(a.is_out_of_play())
	var list: Array[ShipState] = [a]
	assert_true(Occupancy.build(list).is_empty())


func test_scenario_arrives_sets_awaiting_and_plain_sail() -> void:
	var a := _make_ship("a", Vector2i(5, 5), {"arrives": 3})
	assert_true(a.awaiting_arrival)
	assert_eq(a.arrives_turn, 3)
	assert_eq(a.sail_state, "PS")
	var b := _make_ship("b", Vector2i(0, 0), {"arrives": 3, "sail_state": "MS"})
	assert_eq(b.sail_state, "MS")
	var c := _make_ship("c", Vector2i(0, 2), {"arrives": 1})
	assert_false(c.awaiting_arrival)
	var d := _make_ship("d", Vector2i(0, 4))
	assert_false(d.awaiting_arrival)
	assert_eq(d.arrives_turn, 1)


func test_aground_ship_stays_in_play_but_cannot_plot() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	assert_true(GameState.ship_controller.set_aground("a", 4))
	assert_true(a.is_aground())
	assert_eq(a.aground_turn, 4)
	assert_false(a.is_out_of_play())
	assert_true(a.is_targetable())
	assert_false(DefaultCourse.can_plot(a))
	var response := _start_plotting(a)
	assert_true(response is MovementTypes.PlottingErrorResponse)
	assert_eq((response as MovementTypes.PlottingErrorResponse).error_code, "SHIP_AGROUND")


func test_waiting_ship_refused_off_map() -> void:
	var a := _make_ship("a", Vector2i(5, 5), {"arrives": 3})
	var response := _start_plotting(a)
	assert_true(response is MovementTypes.PlottingErrorResponse)
	assert_eq((response as MovementTypes.PlottingErrorResponse).error_code, "SHIP_OFF_MAP")


func test_cast_lead_lives_in_the_plot() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	assert_false(a.casts_lead())
	assert_true(GameState.ship_controller.set_cast_lead("a", true))
	assert_true(a.casts_lead())
	GameState.ship_controller.clear_plotted_actions("a")
	assert_false(a.casts_lead())


func test_mutators_set_escape_arrival() -> void:
	var a := _make_ship("a", Vector2i(5, 5), {"arrives": 3})
	assert_true(GameState.ship_controller.set_escape_declared("a", true))
	assert_true(a.escape_declared)
	assert_true(GameState.ship_controller.delay_arrival("a", 5))
	assert_eq(a.arrives_turn, 5)
	assert_true(GameState.ship_controller.place_arrival("a", 4))
	assert_false(a.awaiting_arrival)
	assert_eq(a.speed, 4)
	assert_true(a.is_on_map())


func test_serialize_round_trip_terrain_fields() -> void:
	var a := _make_ship("a", Vector2i(5, 5), {"arrives": 4})
	a.aground = true
	a.aground_turn = 2
	a.escape_declared = true
	a.status = ShipState.Status.ESCAPED
	var b := ShipState.deserialize(a.serialize())
	assert_true(b.aground)
	assert_eq(b.aground_turn, 2)
	assert_true(b.escape_declared)
	assert_true(b.awaiting_arrival)
	assert_eq(b.arrives_turn, 4)
	assert_eq(b.status, ShipState.Status.ESCAPED)


func test_placement_skips_overlap_for_waiting_ship() -> void:
	GameState.active_scenario = {"terrain": {"land": [[9, 9]]}}
	var a := _make_ship("a", Vector2i(0, 0))
	# the waiting ship's entry is exactly a's footprint
	var w := _make_ship("w", Vector2i(0, 0), {"arrives": 3})
	assert_eq(GameState.placement_errors(), [] as Array[String], "no overlap error for a waiting ship")
	# an entry on land is still reported
	GameState.ships.erase("w")
	GameState.ships_by_side[0].erase("w")
	var l := _make_ship("l", Vector2i(9, 9), {"arrives": 3})
	var errors := GameState.placement_errors()
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "which is land")
	assert_not_null(a)
	assert_not_null(w)
	assert_not_null(l)


func test_waiting_ship_is_not_targetable_or_boardable_until_placed() -> void:
	var a := _make_ship("a", Vector2i(5, 5), {"arrives": 3})
	assert_false(a.is_targetable())
	assert_false(a.can_be_boarded())
	assert_true(GameState.ship_controller.place_arrival("a", 3))
	assert_true(a.is_targetable())
	assert_true(a.can_be_boarded())
