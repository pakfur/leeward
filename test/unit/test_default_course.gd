extends GutTest
## 6.G.2: the default course of a ship whose owner plotted nothing (DefaultCourse).

var mock_gs: MockGameState
var hex_grid: HexGrid


class MockGameState extends Node:
	var environment: EnvironmentState = null
	var ship_controller: ShipStateController = null
	var ships: Dictionary = {}
	var active_scenario: Dictionary = {}
	func _init() -> void:
		environment = EnvironmentState.new()
		ship_controller = ShipStateController.new(self)
	func get_ship(ship_id: String) -> ShipState:
		return ships.get(ship_id, null)


func _make_ship_state(facing: int, speed: int) -> ShipState:
	var ss := ShipState.new()
	ss.ship = Ship.from_dict({
		"ship_id": "test_ship",
		"player_id": 0,
		"ship_name": "Test Frigate",
		"ship_type": "frigate",
		"name": "Test Frigate",
		"nationality": "British",
		"maneuverability": "b",
		"speed_type": "F/F",
		"rigging_hp": [10, 10, 10, 10],
		"hull_hp": [8, 8, 8, 8],
	})
	ss.hex_position = Vector2i(5, 5)
	ss.facing = facing
	ss.speed = speed
	ss.sail_state = "MS"
	for i in range(4):
		ss.rigging_current_hp[i] = 10
		ss.hull_current_hp[i] = 8
	mock_gs.ships[ss.ship_id] = ss
	return ss


func before_each() -> void:
	mock_gs = MockGameState.new()
	mock_gs.environment.wind_direction = 3  # from the west: a ship facing east runs before it
	mock_gs.environment.wind_speed = 3
	hex_grid = HexGrid.new()


func after_each() -> void:
	if mock_gs:
		mock_gs.free()


func _ma(ss: ShipState) -> int:
	return mock_gs.ship_controller.get_movement_allowance(ss.ship_id)


func test_default_course_keeps_last_speed() -> void:
	var ss := _make_ship_state(0, 3)
	assert_gte(_ma(ss), 3, "fixture gives MA of at least 3")
	var steps := DefaultCourse.for_ship(mock_gs, ss)
	assert_eq(steps.size(), 3)
	var cur := ss.hex_position
	for step in steps:
		cur = hex_grid.get_neighbor(cur.x, cur.y, 0)
		assert_eq(step.hex, cur)
		assert_eq(step.facing, 0)
		assert_eq(step.move_type, MovementTypes.MoveType.FORWARD)


func test_default_course_capped_by_movement_allowance() -> void:
	var ss := _make_ship_state(0, 40)
	var ma := _ma(ss)
	assert_gt(ma, 0)
	assert_eq(DefaultCourse.for_ship(mock_gs, ss).size(), ma)


func test_default_course_empty_at_ma_zero() -> void:
	var ss := _make_ship_state(3, 3)  # facing west, into the wind (WF L)
	assert_eq(_ma(ss), 0)
	assert_eq(DefaultCourse.for_ship(mock_gs, ss).size(), 0)


func test_default_course_empty_at_speed_zero() -> void:
	var ss := _make_ship_state(0, 0)
	assert_eq(DefaultCourse.for_ship(mock_gs, ss).size(), 0)


func test_default_course_none_for_a_ship_that_cannot_plot() -> void:
	var ss := _make_ship_state(0, 3)
	ss.fouled_with = "x"
	assert_false(DefaultCourse.can_plot(ss))
	assert_eq(DefaultCourse.for_ship(mock_gs, ss).size(), 0)


func test_as_dicts() -> void:
	var ss := _make_ship_state(0, 2)
	var dicts := DefaultCourse.as_dicts(DefaultCourse.for_ship(mock_gs, ss))
	assert_eq(dicts.size(), 2)
	assert_eq(dicts[0]["facing"], 0)
	assert_eq(dicts[0]["hex"], {"q": 6, "r": 5})


func test_set_plotted_movement_marks_the_plot() -> void:
	var ss := _make_ship_state(0, 2)
	assert_false(ShipState.empty_plot()["movement_plotted"])
	assert_false(ss.plotted_actions["movement_plotted"])
	mock_gs.ship_controller.is_server = true
	mock_gs.ship_controller.set_plotted_movement(ss.ship_id, [])
	assert_true(ss.plotted_actions["movement_plotted"])
