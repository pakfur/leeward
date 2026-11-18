extends GutTest
## DisplayStates: detached ship copies for the resolution replay (view only).

var _a: ShipState
var _b: ShipState
var _ds: DisplayStates


func before_each() -> void:
	_ds = DisplayStates.new()
	_a = _ship("a")
	_b = _ship("b")


func _ship(id: String) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": 0, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F", "rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6], "crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	return state


func _step(phase: int, ship: String, target: String = "") -> ResolutionStep:
	var s := ResolutionStep.new()
	s.phase = phase
	s.ship_id = ship
	s.target_id = target
	return s


func _steps(list: Array) -> Array[ResolutionStep]:
	var out: Array[ResolutionStep] = []
	for s in list:
		out.append(s)
	return out


func _damage(state: ShipState) -> void:
	var r: Array[int] = [0, 0, 0, 0]
	state.rigging_current_hp = r


func test_record_ignores_second_emit() -> void:
	_ds.record_phase(4, 1, [_a, _b])
	_damage(_a)
	_ds.record_phase(4, 1, [_a, _b])
	_ds.begin([4] as Array[int])
	assert_eq(_ds.state_for("a").rigging_current_hp[0], 5)


func test_begin_shows_pre_phase_copy() -> void:
	_ds.record_phase(4, 1, [_a, _b])
	_damage(_a)
	_ds.begin([4] as Array[int])
	assert_true(_ds.active())
	assert_ne(_ds.state_for("a"), _a)
	assert_eq(_ds.state_for("a").rigging_current_hp[0], 5)
	assert_eq(_a.rigging_current_hp[0], 0)
	assert_not_null(_ds.state_for("a").ship)


func test_ship_switches_after_its_last_step() -> void:
	_ds.record_phase(4, 1, [_a, _b])
	_damage(_a)
	_ds.record_phase(5, 1, [_a, _b])
	_ds.begin([4, 5] as Array[int])
	var steps := _steps([_step(4, "a", "b"), _step(4, "b"), _step(4, "a")])
	_ds.step_shown(steps[0], steps, 0)
	assert_eq(_ds.state_for("a").rigging_current_hp[0], 5, "a has another step")
	_ds.step_shown(steps[2], steps, 2)
	assert_eq(_ds.state_for("a").rigging_current_hp[0], 0, "now the copy before phase 5")


func test_other_ship_waits_for_its_own_step() -> void:
	_ds.record_phase(4, 1, [_a, _b])
	_damage(_b)
	_ds.record_phase(5, 1, [_a, _b])
	_ds.begin([4, 5] as Array[int])
	var steps := _steps([_step(4, "a"), _step(4, "b")])
	_ds.step_shown(steps[0], steps, 0)
	assert_eq(_ds.state_for("b").rigging_current_hp[0], 5)
	_ds.step_shown(steps[1], steps, 1)
	assert_eq(_ds.state_for("b").rigging_current_hp[0], 0)


func test_last_phase_switches_to_live() -> void:
	_ds.record_phase(4, 1, [_a])
	_ds.begin([4] as Array[int])
	var steps := _steps([_step(4, "a")])
	_ds.step_shown(steps[0], steps, 0)
	assert_null(_ds.state_for("a"))


func test_phase_reached_and_new_turn() -> void:
	_ds.record_phase(4, 1, [_a])
	_damage(_a)
	_ds.record_phase(5, 1, [_a])
	_ds.begin([4, 5] as Array[int])
	_ds.phase_reached(5)
	assert_eq(_ds.state_for("a").rigging_current_hp[0], 0)
	_ds.record_phase(4, 2, [_b])
	_ds.begin([4] as Array[int])
	assert_null(_ds.state_for("a"), "older turn's copies are dropped")


func test_end_returns_live() -> void:
	_ds.record_phase(4, 1, [_a])
	_ds.begin([4] as Array[int])
	_ds.end()
	assert_false(_ds.active())
	assert_null(_ds.state_for("a"))


func test_copy_is_detached() -> void:
	_ds.record_phase(4, 1, [_a])
	_damage(_a)
	_a.facing = 3
	_ds.begin([4] as Array[int])
	assert_eq(_ds.state_for("a").rigging_current_hp[0], 5)
	assert_eq(_ds.state_for("a").facing, 0)
