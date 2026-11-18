extends GutTest
## VictoryController with escaped, aground and waiting ships and any number of sides
## (Scenario Book VI.A.1c, VI.B.4-6; map-and-scenario spec §10).

var controller: VictoryController
var _old_scenario: Dictionary
var _old_ships_by_side: Dictionary


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	_old_scenario = GameState.active_scenario
	_old_ships_by_side = GameState.ships_by_side
	GameState.active_scenario = {}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	GameState.end_offers = {}
	controller = VictoryController.new(GameState)


func after_each() -> void:
	GameState.active_scenario = _old_scenario
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


## A quality-D, rating-4 frigate worth 38 (as test_victory_controller.gd).
func _make_ship(id: String, side: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	state.hex_position = Vector2i(5 + side * 10, 5)
	state.facing = 3
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.marine_count = 2
	state.crew_quality = "D"
	state.starting_crew_quality = "D"
	state.morale_rating = 4
	GameState.ships[id] = state
	if not GameState.ships_by_side.has(side):
		GameState.ships_by_side[side] = []
	GameState.ships_by_side[side].append(id)
	return state


func test_escaped_ship_yields_only_damaged_sections() -> void:
	var ship := _make_ship("a", 1)
	ship.status = ShipState.Status.ESCAPED
	assert_eq(controller.points_lost(ship), 0.0, "undamaged escaped ship")
	ship.rigging_current_hp[0] = 0
	assert_true(is_equal_approx(controller.points_lost(ship), 1.9), "5% of 38")
	assert_false(controller.is_lost(ship))
	assert_false(controller.can_move_or_fight(ship))


func test_escape_share_goes_to_own_side() -> void:
	GameState.active_scenario = {"escape": {"1": {"share": 0.5}}, "turn_limit": 5}
	_make_ship("a", 0)
	var b := _make_ship("b", 1)
	var c := _make_ship("c", 1)
	b.status = ShipState.Status.ESCAPED
	assert_eq(controller.escape_points(b), 19.0)
	assert_eq(controller.escape_points(c), 0.0, "not escaped")
	var result := controller.check(5)
	assert_eq(result.get("reason"), "turn limit")
	assert_eq(result["points"][1], 19.0)
	assert_eq(result["points"][0], 0.0)
	assert_eq(result["winner"], 1)


func test_aground_counts_lost_by_default() -> void:
	_make_ship("a", 0)
	var b := _make_ship("b", 1)
	b.aground = true
	assert_true(controller.is_lost(b))
	assert_eq(controller.points_lost(b), 38.0)
	assert_false(controller.can_move_or_fight(b))
	var result := controller.check(1)
	assert_eq(result.get("reason"), "all struck")
	assert_eq(result["winner"], 0)


func test_aground_flag_off_scores_sections() -> void:
	GameState.active_scenario = {"aground_counts_lost": false}
	_make_ship("a", 0)
	var b := _make_ship("b", 1)
	b.aground = true
	b.hull_current_hp[0] = 0
	assert_false(controller.is_lost(b))
	assert_true(is_equal_approx(controller.points_lost(b), 3.8), "10% of 38")
	assert_false(controller.can_move_or_fight(b))
	var result := controller.check(1)
	assert_eq(result.get("reason"), "no ship able to move or fight")


func test_waiting_reinforcement_keeps_its_side_alive() -> void:
	_make_ship("a", 0)
	var b := _make_ship("b", 1)
	b.status = ShipState.Status.STRUCK
	var c := _make_ship("c", 1)
	c.awaiting_arrival = true
	assert_eq(controller.check(1), {})
	assert_eq(controller.points_lost(c), 0.0)
	assert_false(controller.is_lost(c))
	assert_true(controller.can_move_or_fight(c))


func test_side_all_struck_or_escaped_is_done() -> void:
	_make_ship("a", 0)
	var b := _make_ship("b", 1)
	b.status = ShipState.Status.STRUCK
	var c := _make_ship("c", 1)
	c.status = ShipState.Status.ESCAPED
	var result := controller.check(1)
	assert_eq(result.get("reason"), "all struck")


func test_three_sides_score_every_other_side() -> void:
	_make_ship("a", 0)
	_make_ship("b", 1)
	var c := _make_ship("c", 2)
	c.status = ShipState.Status.STRUCK
	assert_eq(controller._sides(), [0, 1, 2] as Array[int])
	var result := controller.check(1)
	assert_eq(result.get("reason"), "all struck")
	assert_eq(result["points"][0], 38.0)
	assert_eq(result["points"][1], 38.0)
	assert_eq(result["points"][2], 0.0)
	assert_eq(result["winner"], -1)


func test_sides_default_when_no_ships() -> void:
	assert_eq(controller._sides(), [0, 1] as Array[int])
