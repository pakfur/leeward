extends GutTest
## TowRules (12.A, towing spec §1, §3, §4, §6): the tow station, the follow pose, the 12.A.7 MA
## loss, the tow order, task legality, the legality of a tow and why a tow breaks.
## Tower t: bow (5, 5), facing 3, stern (6, 5). Towed w: bow (7, 5), facing 3, stern (8, 5),
## dismasted unless stated.

var sc: ShipStateController


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	sc = autofree(ShipStateController.new(GameState))


func after_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _ship(id: String, hex: Vector2i, facing: int = 3, side: int = 0, ship_class: int = 3) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({
		"ship_id": id, "side": side, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": ship_class,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	s.hex_position = hex
	s.facing = facing
	s.sail_state = "FS"
	s.crew_quality = "C"
	s.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	s.hull_current_hp = [5, 5, 5, 6] as Array[int]
	s.crew_count = [3, 3, 3, 3] as Array[int]
	s.marine_count = 2
	GameState.ships[id] = s
	GameState.ships_by_side[side].append(id)
	return s


func _t() -> ShipState:
	return _ship("t", Vector2i(5, 5))


func _w() -> ShipState:
	var w := _ship("w", Vector2i(7, 5))
	w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	return w


## A legal pair: t prepared, CQ C, neither has used an MP.
func _pair() -> Array[ShipState]:
	var t := _t()
	t.tow_prepared = true
	return [t, _w()]


func _pose(bow: Vector2i, facing: int, stern: Vector2i) -> Dictionary:
	return {"bow": bow, "facing": facing, "stern": stern}


func test_station_and_position() -> void:
	var t := _t()
	var w := _w()
	assert_eq(TowRules.station_hex(w), Vector2i(6, 5))
	assert_true(TowRules.in_position(t, w))
	t.hex_position = Vector2i(4, 5)
	assert_false(TowRules.in_position(t, w))


func test_follow_pose_ahead() -> void:
	assert_eq(TowRules.follow_pose(Vector2i(5, 5), 3, Vector2i(4, 5), 3),
		_pose(Vector2i(6, 5), 3, Vector2i(7, 5)))


func test_follow_pose_starboard_turn() -> void:
	assert_eq(TowRules.follow_pose(Vector2i(5, 5), 3, Vector2i(5, 5), 4),
		_pose(Vector2i(6, 5), 2, Vector2i(7, 4)))


func test_follow_pose_port_turn() -> void:
	assert_eq(TowRules.follow_pose(Vector2i(5, 5), 3, Vector2i(5, 5), 2),
		_pose(Vector2i(6, 5), 4, Vector2i(6, 6)))


func test_follow_pose_all_facings() -> void:
	var bow := Vector2i(5, 5)
	for f in 6:
		var steps := [
			[bow + HexGrid.DIRECTIONS[f], f],  # ahead
			[bow, (f + 5) % 6],  # port
			[bow, (f + 1) % 6],  # starboard
		]
		for step in steps:
			var new_bow: Vector2i = step[0]
			var new_facing: int = step[1]
			var new_stern := HexGrid.stern_of(new_bow, new_facing)
			var pose := TowRules.follow_pose(bow, f, new_bow, new_facing)
			assert_eq(pose["bow"], HexGrid.stern_of(bow, f), "bow takes the old stern, f %d" % f)
			assert_eq(pose["bow"] + HexGrid.DIRECTIONS[pose["facing"]], new_stern,
				"points at the new stern, f %d -> %d" % [f, new_facing])
			assert_ne(pose["stern"], new_bow, "stern clear of the tower's bow, f %d" % f)
			assert_ne(pose["stern"], new_stern, "stern clear of the tower's stern, f %d" % f)


func test_follow_pose_refuses_a_jump() -> void:
	var pose := TowRules.follow_pose(Vector2i(5, 5), 3, Vector2i(2, 5), 3)
	assert_eq(pose, {})
	assert_push_error("not neighbours")


func test_ma_loss() -> void:
	# 12.A.7 example: class 3 tows a dismasted class 1
	var t := _ship("t", Vector2i(5, 5), 3, 0, 3)
	var w := _ship("w", Vector2i(7, 5), 3, 0, 1)
	w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	assert_eq(TowRules.ma_loss(t, w), 4)
	var small := _ship("s", Vector2i(0, 0), 3, 0, 1)
	var big := _ship("b", Vector2i(2, 0), 3, 0, 3)
	big.sail_state = "MS"
	assert_eq(TowRules.ma_loss(small, big), 1)
	var mid := _ship("m", Vector2i(4, 0), 3, 0, 2)
	mid.sail_state = "NS"
	assert_eq(TowRules.ma_loss(t, mid), 3)
	var two := _ship("two", Vector2i(6, 0), 3, 0, 2)
	assert_eq(TowRules.ma_loss(two, big), 1)


func test_parse_order() -> void:
	assert_eq(TowRules.parse_order(""), {"kind": "", "target": ""})
	assert_eq(TowRules.parse_order("cut"), {"kind": "cut", "target": ""})
	assert_eq(TowRules.parse_order("take:w"), {"kind": "take", "target": "w"})
	assert_eq(TowRules.parse_order("take:")["kind"], "bad")
	assert_eq(TowRules.parse_order("tow")["kind"], "bad")


func test_take_target_error() -> void:
	var t := _t()
	assert_eq(TowRules.take_target_error(t, null), "Unknown ship")
	assert_eq(TowRules.take_target_error(t, t), "a ship cannot tow itself")
	var enemy := _ship("e", Vector2i(0, 0), 3, 1)
	assert_eq(TowRules.take_target_error(t, enemy), "only friendly ships may be towed (12.A.2)")
	var struck := _ship("s", Vector2i(2, 0))
	struck.status = ShipState.Status.STRUCK
	assert_eq(TowRules.take_target_error(t, struck),
		"s has struck: a ship that has surrendered is not towed (ruling)")
	var gone := _ship("g", Vector2i(4, 0))
	gone.status = ShipState.Status.DESTROYED
	assert_eq(TowRules.take_target_error(t, gone), "g has blown up")
	var prize := _ship("p", Vector2i(6, 0), 3, 1)
	prize.status = ShipState.Status.CAPTURED
	prize.controller_side = 0
	assert_eq(TowRules.take_target_error(t, prize), "")
	assert_eq(TowRules.take_target_error(t, _w()), "")


func test_refusal_pt_and_tx() -> void:
	var t := _t()
	assert_eq(TowRules.refusal(t, "PT", []), "")
	assert_eq(TowRules.refusal(t, "PT", ["PT"]), "one section prepares the tow (12.A.3)")
	t.tow_prepared = true
	assert_eq(TowRules.refusal(t, "PT", []), "already prepared to tow (12.A.3)")
	t.tow_prepared = false
	t.towed_by = "x"
	assert_eq(TowRules.refusal(t, "PT", []), "a towed ship cannot tow (12.A.2)")
	assert_eq(TowRules.refusal(t, "TX", []), "")
	t.towed_by = ""
	assert_eq(TowRules.refusal(t, "TX", []), "no tow to cut (12.A.9)")
	t.towing_id = "w"
	assert_eq(TowRules.refusal(t, "PT", []), "already towing (12.A.2)")
	assert_eq(TowRules.refusal(t, "TX", []), "")
	assert_eq(TowRules.refusal(t, "TX", ["TX"]), "one section cuts the tow (12.A.9)")
	assert_eq(TowRules.refusal(t, "RH", []), "not a towing task")
	var prize := _ship("p", Vector2i(0, 0), 3, 1)
	prize.status = ShipState.Status.CAPTURED
	prize.controller_side = 0
	prize.prize = {"prize_crew_aboard": true}
	assert_eq(TowRules.refusal(prize, "PT", []), "a prize plots only boarding and repairs (10.H.2)")
	var struck := _ship("s", Vector2i(2, 0))
	struck.status = ShipState.Status.STRUCK
	assert_eq(TowRules.refusal(struck, "PT", []), "the crew cannot act")


func test_order_task() -> void:
	var t := _t()
	assert_eq(TowRules.order_task(t, "take:w"), {"code": "PT", "params": {}})
	assert_eq(TowRules.order_task(t, ""), {})
	assert_eq(TowRules.order_task(t, "cut"), {})
	t.tow_prepared = true
	assert_eq(TowRules.order_task(t, "take:w"), {})
	t.tow_prepared = false
	t.crew_tasks = [{"seq": 1, "code": "PT", "sections": [0], "ended": ""}] as Array[Dictionary]
	assert_eq(TowRules.order_task(t, "take:w"), {})
	t.crew_tasks = [{"seq": 1, "code": "PT", "sections": [0], "ended": "complete"}] as Array[Dictionary]
	assert_eq(TowRules.order_task(t, "take:w"), {"code": "PT", "params": {}})
	t.towing_id = "w"
	assert_eq(TowRules.order_task(t, "cut"), {"code": "TX", "params": {}})
	assert_eq(TowRules.order_task(t, "take:w"), {})


func _error_with(change: Callable) -> String:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var pair := _pair()
	change.call(pair[0], pair[1])
	return TowRules.pair_error(pair[0], pair[1])


func test_pair_error_in_order() -> void:
	var pair := _pair()
	assert_eq(TowRules.pair_error(pair[0], pair[1]), "")
	assert_string_contains(TowRules.pair_error(pair[0], pair[0]), "itself")
	assert_string_contains(_error_with(func(_t, w): w.ship.side = 1), "12.A.2")
	assert_string_contains(_error_with(func(_t, w): w.status = ShipState.Status.STRUCK), "surrendered")
	assert_string_contains(_error_with(func(_t, w): w.anchor = {"hex": Vector2i(7, 5), "end": "bow"}),
		"anchored")
	assert_string_contains(_error_with(func(t, _w): t.aground = true), "13.G.3")
	assert_string_contains(_error_with(func(t, _w): t.rigging_current_hp = [0, 0, 0, 0] as Array[int]),
		"dismasted")
	assert_string_contains(_error_with(func(t, _w): t.hex_position = Vector2i(4, 5)), "12.A.4a")
	assert_string_contains(_error_with(func(_t, w): w.grappled_with = ["x"] as Array[String]), "12.A.4b")
	assert_string_contains(_error_with(func(t, _w): t.tow_prepared = false), "12.A.3")
	assert_string_contains(_error_with(func(t, _w): sc.add_fire(t.ship_id, "test")), "8.C.3")
	assert_string_contains(_error_with(func(t, _w): t.crew_quality = "F"), "8.C.3")
	assert_string_contains(_error_with(func(t, _w): t.mp_used_this_turn = 3), "8.C.1")
	assert_string_contains(_error_with(func(_t, w): w.mp_used_this_turn = 3), "8.C.1")


func test_pair_error_tows_already_made() -> void:
	assert_string_contains(_error_with(func(t, _w): t.towing_id = "x"), "already tows")
	assert_string_contains(_error_with(func(_t, w): w.towed_by = "x"), "already in tow")
	assert_string_contains(_error_with(func(t, _w): t.towed_by = "x"), "12.A.2")


func test_pair_error_setup_skips_preparation_and_mps() -> void:
	var pair := _pair()
	pair[0].tow_prepared = false
	pair[0].mp_used_this_turn = 3
	pair[1].mp_used_this_turn = 3
	assert_ne(TowRules.pair_error(pair[0], pair[1]), "")
	assert_eq(TowRules.pair_error(pair[0], pair[1], true), "")


func test_prize_may_be_towed_not_tow() -> void:
	var pair := _pair()
	var w: ShipState = pair[1]
	w.ship.side = 1
	w.status = ShipState.Status.CAPTURED
	w.controller_side = 0
	assert_eq(TowRules.pair_error(pair[0], w), "")
	GameState.ships.clear()
	var t := _ship("t", Vector2i(5, 5), 3, 1)
	t.status = ShipState.Status.CAPTURED
	t.controller_side = 0
	t.prize = {"prize_crew_aboard": true}
	t.tow_prepared = true
	var w2 := _w()
	assert_string_contains(TowRules.pair_error(t, w2), "10.H.2")


func test_broken_reason() -> void:
	var pair := _pair()
	var t: ShipState = pair[0]
	var w: ShipState = pair[1]
	assert_eq(TowRules.broken_reason(t, w), "")
	# each cause alone, at either end
	t.status = ShipState.Status.DESTROYED
	assert_eq(TowRules.broken_reason(t, w), "destroyed")
	t.status = ShipState.Status.ACTIVE
	w.status = ShipState.Status.STRUCK
	assert_eq(TowRules.broken_reason(t, w), "struck")
	w.status = ShipState.Status.ACTIVE
	t.aground = true
	assert_eq(TowRules.broken_reason(t, w), "aground")
	t.aground = false
	w.aground = true
	assert_eq(TowRules.broken_reason(t, w), "aground")
	w.aground = false
	t.status = ShipState.Status.CAPTURED
	t.controller_side = 1
	assert_eq(TowRules.broken_reason(t, w), "taken")
	t.status = ShipState.Status.ACTIVE
	t.controller_side = -1
	w.controller_side = 1
	assert_eq(TowRules.broken_reason(t, w), "taken")
	# in order: destroyed before struck before aground before taken
	w.aground = true
	assert_eq(TowRules.broken_reason(t, w), "aground")
	t.status = ShipState.Status.STRUCK
	assert_eq(TowRules.broken_reason(t, w), "struck")
	w.status = ShipState.Status.DESTROYED
	assert_eq(TowRules.broken_reason(t, w), "destroyed")
