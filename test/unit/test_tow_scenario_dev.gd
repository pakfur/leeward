extends GutTest
## Towing, Task 10: tow preparation hidden from every non-commander (14.C), the Developer UI
## commands take_in_tow / cast_off_tow, and a scenario's starting tow.

var _old_scenario: Dictionary
var _old_env: EnvironmentState
var _old_turn: int
var _old_log: PhaseEvents.PhaseLog
var _old_phase: TurnPhaseController.GamePhase


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	_old_scenario = GameState.active_scenario
	_old_env = GameState.environment
	_old_turn = GameState.current_turn
	_old_log = GameState.turn_log
	_old_phase = GameState.phase_controller.current_phase


func after_each() -> void:
	var pc := GameState.phase_controller
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.ai_player_ids = [] as Array[int]
	pc.current_phase = _old_phase
	GameState.active_scenario = _old_scenario
	GameState.environment = _old_env
	GameState.current_turn = _old_turn
	GameState.turn_log = _old_log
	GameState.players.clear()
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, side: int) -> ShipState:
	var ship_def := Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
		"point_costs": {"C4": 100},
	})
	var state := ShipState.new()
	state.initialize_from_scenario({"position": {"q": hex.x, "r": hex.y}, "facing": 3}, ship_def)
	state.side = side
	state.crew_quality = "C"
	state.starting_crew_quality = "C"
	state.morale_rating = 4
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


## t (side 0) may tow w: t's stern (6, 5) is the hex ahead of w's bow (7, 5).
func _pair() -> ShipState:
	GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}}
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	GameState.players.clear()
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.current_turn = 5
	GameState.turn_log = GameState.new_turn_log(5)
	var t := _make_ship("t", Vector2i(5, 5), 0)
	_make_ship("w", Vector2i(7, 5), 0)
	_make_ship("e", Vector2i(5, 9), 1)
	return t


func _task(code: String) -> Dictionary:
	return ShipState.crew_task_from({"seq": 1, "code": code, "sections": [0], "started_turn": 5})


func test_prepared_hidden_tow_public() -> void:
	var t := _pair()
	t.tow_prepared = true
	t.towing_id = "w"
	GameState.get_ship("w").towed_by = "t"
	t.crew_tasks.append(_task("PT"))
	t.crew_tasks.append(_task("RR"))
	var view := PlayerView.new(GameState)
	var d: Dictionary = view.ship_for(1, "t")
	assert_false(d.has("tow_prepared"))
	var codes: Array = d["crew_tasks"].map(func(x): return x["code"])
	assert_false(codes.has("PT"))
	assert_true(codes.has("RR"))
	assert_eq(d["towing_id"], "w")
	assert_eq(view.ship_for(1, "w")["towed_by"], "t")
	var own: Dictionary = view.ship_for(0, "t")
	assert_true(own["tow_prepared"])
	assert_true((own["crew_tasks"] as Array).any(func(x): return x["code"] == "PT"))
	GameState.active_scenario = {"tournament": true}
	var open: Dictionary = view.ship_for(1, "t")
	assert_true(open["tow_prepared"])
	assert_true((open["crew_tasks"] as Array).any(func(x): return x["code"] == "PT"))


func test_pt_events_hidden() -> void:
	_pair()
	var log := GameState.new_turn_log(3)
	GameState.turn_log = log
	log.add(PhaseEvents.Type.CREW_TASK, 5, "t", {"code": "PT", "state": "started"})
	log.add(PhaseEvents.Type.CREW_TASK, 5, "t", {"code": "RR", "state": "started"})
	var view := PlayerView.new(GameState)
	assert_eq(_codes(view.events_for(1, 3)), ["RR"])
	assert_eq(_codes(view.events_for(0, 3)), ["PT", "RR"])


func _codes(events: Array[Dictionary]) -> Array:
	var out: Array = []
	for e in events:
		if int(e["type"]) == PhaseEvents.Type.CREW_TASK:
			out.append(e["data"]["code"])
	return out


func test_take_in_tow_dev() -> void:
	var t := _pair()
	var dev := GameState.dev_commands
	assert_eq(dev.take_in_tow("t"), "")
	assert_eq(t.towing_id, "w")
	assert_eq(GameState.get_ship("w").towed_by, "t")
	assert_true(dev.take_in_tow("t").contains("already"))
	assert_eq(dev.cast_off_tow("w"), "")
	assert_eq(t.towing_id, "")
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.TOW_CUT).size(), 1)
	assert_true(dev.cast_off_tow("w").contains("in no tow"))
	t.hex_position = Vector2i(5, 6)
	assert_true(dev.take_in_tow("t").contains("no ship lies in tow position"))
	assert_true(dev.take_in_tow("t", "w").contains("12.A.4a"))
	assert_true(dev.take_in_tow("t", "nobody").contains("no ship"))


func _scenario(tow: Variant, w_pos: Dictionary = {"q": 2, "r": 0}, w_side: int = 0) -> Dictionary:
	var s := DataManager.load_scenario("test_basic").duplicate(true)
	s["wind_direction"] = 0
	s["wind_speed"] = 2
	s["wind_speed_change"] = "steady"
	var t := {"id": "t", "ship_name": "T", "player_id": 0, "ship_type": "frigate_38",
		"position": {"q": 0, "r": 0}, "facing": 3, "speed": 0, "sail_state": "FS",
		"crew_quality": "B", "crew_morale": 4}
	if tow != null:
		t["tow"] = tow
	var w := {"id": "w", "ship_name": "W", "player_id": w_side, "ship_type": "frigate_38",
		"position": w_pos, "facing": 3, "speed": 0, "sail_state": "FS",
		"crew_quality": "B", "crew_morale": 4}
	s["ships"] = [t, w]
	return s


func test_scenario_tow_places() -> void:
	var s := _scenario("w")
	assert_true(GameState.start_scenario(s, [0] as Array[int]))
	assert_eq(GameState.get_ship("t").towing_id, "w")
	assert_eq(GameState.get_ship("w").towed_by, "t")
	assert_true(GameState.placement_errors().is_empty(), str(GameState.placement_errors()))
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.TOW_BEGUN).size(), 0)


func _tow_errors(tow: Variant, w_pos: Dictionary = {"q": 2, "r": 0}, w_side: int = 0) -> Array[String]:
	var s := _scenario(tow, w_pos, w_side)
	GameState.start_scenario(s, [0] as Array[int])
	return TowRules.scenario_errors(s, GameState.get_all_ships())


func test_scenario_tow_errors() -> void:
	var unknown := _tow_errors("nobody")
	assert_eq(unknown.size(), 1)
	assert_true(unknown[0].begins_with("Towing: ") and unknown[0].contains("unknown"), unknown[0])
	var itself := _tow_errors("t")
	assert_eq(itself.size(), 1)
	assert_true(itself[0].begins_with("Towing: "), itself[0])
	var enemy := _tow_errors("w", {"q": 2, "r": 0}, 1)
	assert_eq(enemy.size(), 1)
	assert_true(enemy[0].contains("friendly"), enemy[0])
	var away := _tow_errors("w", {"q": 4, "r": 0})
	assert_eq(away.size(), 1)
	assert_true(away[0].contains("12.A.4a"), away[0])
	assert_true(_tow_errors("w").is_empty())
	assert_push_error(4, "Towing: ")
