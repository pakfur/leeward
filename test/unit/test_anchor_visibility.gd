extends GutTest
## 7.C.12c (anchored gunfire +1) and limited information about anchor preparations (14.C).

var _old_scenario: Dictionary
var _old_env: EnvironmentState
var _old_turn: int


func before_each() -> void:
	_old_scenario = GameState.active_scenario
	_old_env = GameState.environment
	_old_turn = GameState.current_turn
	GameState.active_scenario = {}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 3
	GameState.players.clear()


func after_each() -> void:
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	GameState.players.clear()


func _make_ship(id: String, side: int, hex: Vector2i) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.side = side
	state.hex_position = hex
	state.facing = 0
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = "C"
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


func _anchor() -> Dictionary:
	return {"hex": Vector2i(0, 0), "end": "bow", "springs": false, "cable": 2, "veered": 0,
		"swing_dir": 0, "wind_dir": 0, "turn": 2}


func _task(code: String, turn: int = 3) -> Dictionary:
	return ShipState.crew_task_from({"seq": 1, "code": code, "sections": [0], "started_turn": turn})


func _order(ship_id: String, target_id: String) -> GunneryTypes.FireOrder:
	var o := GunneryTypes.FireOrder.new()
	o.ship_id = ship_id
	o.side = ShipState.STARBOARD
	o.target_id = target_id
	o.ammo = "round"
	o.aim = "low"
	o.battery = "full"
	return o


func _mod(p: GunneryTypes.ShotPreview, name: String) -> int:
	for m in p.modifiers:
		if m["name"] == name:
			return m["value"]
	return 0


func _two_firers() -> Array:
	var f1 := _make_ship("f1", 0, Vector2i.ZERO)
	var f2 := _make_ship("f2", 0, Vector2i(0, 8))
	_make_ship("t1", 1, HexGrid.DIRECTIONS[1] * 3)
	_make_ship("t2", 1, Vector2i(0, 8) + HexGrid.DIRECTIONS[1] * 3)
	return [f1, f2]


func test_anchored_firer_gets_plus_one() -> void:
	var f: Array = _two_firers()
	f[0].anchor = _anchor()
	var calc := GunneryCalculator.new(GameState)
	var a := calc.preview(_order("f1", "t1"))
	var b := calc.preview(_order("f2", "t2"))
	assert_true(a.can_fire, a.reason)
	assert_true(b.can_fire, b.reason)
	assert_eq(a.range_hexes, b.range_hexes)
	assert_eq(_mod(a, "anchored"), 1)
	assert_false(b.modifiers.any(func(m): return m["name"] == "anchored"))
	assert_eq(a.mgn, b.mgn + 1)


func test_no_bonus_on_anchoring_turn() -> void:
	var f: Array = _two_firers()
	f[0].anchor_ready = "bow"
	f[0].crew_tasks.append(_task("A"))
	var p := GunneryCalculator.new(GameState).preview(_order("f1", "t1"))
	assert_true(p.can_fire, p.reason)
	assert_eq(_mod(p, "anchored"), 0)


func test_bonus_on_cut_turn() -> void:
	var f: Array = _two_firers()
	f[0].anchor = _anchor()
	f[0].crew_tasks.append(_task("AX"))
	var p := GunneryCalculator.new(GameState).preview(_order("f1", "t1"))
	assert_true(p.can_fire, p.reason)
	assert_eq(_mod(p, "anchored"), 1)


func _view_ship() -> ShipState:
	var a := _make_ship("a", 0, Vector2i.ZERO)
	_make_ship("b", 1, Vector2i(0, 4))
	a.anchor_ready = "bow"
	a.springs_ready = true
	a.crew_tasks.append(_task("PBS"))
	a.crew_tasks.append(_task("RR"))
	return a


func test_preparation_hidden_from_enemy() -> void:
	_view_ship()
	var view := PlayerView.new(GameState)
	var d: Dictionary = view.ship_for(1, "a")
	assert_false(d.has("anchor_ready"))
	assert_false(d.has("springs_ready"))
	var codes: Array = d["crew_tasks"].map(func(t): return t["code"])
	assert_false(codes.has("PBS"))
	assert_true(codes.has("RR"))
	var own: Dictionary = view.ship_for(0, "a")
	assert_eq(own["anchor_ready"], "bow")
	assert_true(own["springs_ready"])
	assert_true((own["crew_tasks"] as Array).any(func(t): return t["code"] == "PBS"))


func test_anchor_public() -> void:
	var a := _view_ship()
	a.anchor = _anchor()
	a.anchorings_used = 1
	var d: Dictionary = PlayerView.new(GameState).ship_for(1, "a")
	assert_eq(d["anchor"]["cable"], 2)
	assert_eq(d["anchorings_used"], 1)
	assert_true(d.has("cable_cut_turn"))


func test_prep_events_hidden() -> void:
	_view_ship()
	var log := GameState.new_turn_log(3)
	GameState.turn_log = log
	log.add(PhaseEvents.Type.CREW_TASK, 5, "a", {"code": "PBA", "state": "started"})
	log.add(PhaseEvents.Type.CREW_TASK, 5, "a", {"code": "A", "state": "started"})
	var view := PlayerView.new(GameState)
	assert_eq(_codes(view.events_for(1, 3)), ["A"])
	assert_eq(_codes(view.events_for(0, 3)), ["PBA", "A"])
	GameState.active_scenario = {"tournament": true}
	assert_eq(_codes(view.events_for(1, 3)), ["PBA", "A"])


func _codes(events: Array[Dictionary]) -> Array:
	var out: Array = []
	for e in events:
		if int(e["type"]) == PhaseEvents.Type.CREW_TASK:
			out.append(e["data"]["code"])
	return out
