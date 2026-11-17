extends GutTest
## A ship's owner is its side (players/side split, step 1): new names, old keys still read.

func _ship_dict(extra: Dictionary) -> Dictionary:
	var d := {"ship_id": "s1", "ship_name": "S", "ship_type": "frigate_38"}
	d.merge(extra, true)
	return d


func test_ship_reads_player_id_alias() -> void:
	assert_eq(Ship.from_dict(_ship_dict({"player_id": 1})).side, 1)
	assert_eq(Ship.from_dict(_ship_dict({"side": 1})).side, 1)


func test_ship_state_reads_controller_id_alias() -> void:
	var base := ShipState.new()
	base.ship = Ship.from_dict(_ship_dict({"side": 1}))
	var d: Dictionary = base.serialize()
	d.erase("controller_side")
	d["controller_id"] = 0
	assert_eq(ShipState.deserialize(d).controller_side, 0)
	d.erase("controller_id")
	d["controller_side"] = 0
	assert_eq(ShipState.deserialize(d).controller_side, 0)


func test_to_dict_writes_new_keys() -> void:
	var ship := Ship.from_dict(_ship_dict({"side": 1}))
	var sd := ship.to_dict()
	assert_true(sd.has("side"))
	assert_false(sd.has("player_id"))
	var state := ShipState.new()
	state.ship = ship
	var d: Dictionary = state.serialize()
	assert_true(d.has("controller_side"))
	assert_false(d.has("controller_id"))
	assert_false(d.has("player_id"))


func test_scenario_ship_side_key() -> void:
	var scenario := DataManager.load_scenario("test_basic").duplicate(true)
	for ship in scenario["ships"]:
		ship.erase("player_id")
		ship["side"] = 1
	GameState.start_scenario(scenario, [] as Array[int])
	assert_eq(GameState.get_side_ships(1).size(), scenario["ships"].size())
	assert_eq(GameState.get_side_ships(0).size(), 0)
	_reset_game()


func _reset_game() -> void:
	var pc: TurnPhaseController = GameState.phase_controller
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	pc.players_ready = {0: false, 1: false}
	GameState.clear_ships()


func test_fallback_names_count_per_side_with_side_key() -> void:
	var by_side := [
		{"ship_type": "frigate_38", "side": 0}, {"ship_type": "frigate_38", "side": 1},
		{"ship_type": "frigate_38", "side": 1},
	]
	var by_player := [
		{"ship_type": "frigate_38", "player_id": 0}, {"ship_type": "frigate_38", "player_id": 1},
		{"ship_type": "frigate_38", "player_id": 1},
	]
	DataManager.assign_fallback_ship_names(by_side)
	DataManager.assign_fallback_ship_names(by_player)
	for i in 3:
		assert_eq(by_side[i]["ship_name"], by_player[i]["ship_name"])
	assert_true(by_side[0]["ship_name"].ends_with(" 1"))
	assert_true(by_side[1]["ship_name"].ends_with(" 1"))
	assert_true(by_side[2]["ship_name"].ends_with(" 2"))
