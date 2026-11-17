extends GutTest
## Players, commanders, flagships and groups (players/side split, step 2).

func after_each() -> void:
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
	GameState.players.clear()
	GameState.groups.clear()


func _squadron() -> Dictionary:
	return DataManager.load_scenario("test_squadron").duplicate(true)


func _start(scenario: Dictionary) -> bool:
	return GameState.start_scenario(scenario, [0] as Array[int])


func test_default_one_player_per_side() -> void:
	assert_true(_start(DataManager.load_scenario("test_basic").duplicate(true)))
	assert_eq(GameState.players.size(), 2)
	var ship: ShipState = GameState.get_side_ships(0)[0]
	assert_true(GameState.commands(0, ship.ship_id))
	assert_false(GameState.commands(1, ship.ship_id))
	assert_false(GameState.get_player(0).is_ai)
	assert_true(GameState.get_player(1).is_ai)


func test_squadron_players_and_commanders() -> void:
	assert_true(_start(_squadron()))
	assert_eq(GameState.side_of_player(1), 0)
	assert_eq(GameState.side_of_player(9), -1)
	assert_eq(GameState.ships_of_player(0).size(), 2)
	assert_eq(GameState.commander_of("brit_b1"), 1)
	assert_eq(GameState.players_of_side(1).size(), 2)
	assert_true(GameState.placement_errors().is_empty())
	assert_true(GameState.ships["brit_a1"].is_fleet_flagship())
	assert_true(GameState.ships["fr_b1"].is_flagship())
	assert_false(GameState.ships["fr_b1"].is_fleet_flagship())


func test_unlisted_ship_goes_to_lowest_player() -> void:
	var s := _squadron()
	s["players"][0]["ships"] = ["brit_a1"]
	assert_true(_start(s))
	assert_eq(GameState.commander_of("brit_a2"), 0)


func test_duplicate_ship_is_a_load_error() -> void:
	var s := _squadron()
	s["players"][1]["ships"] = ["brit_b1", "brit_a1"]
	assert_false(_start(s))
	assert_push_error("listed under two players")


func test_player_without_ships_is_a_load_error() -> void:
	var s := _squadron()
	s["players"].append({"id": 7, "side": 5, "name": "Y", "ships": []})
	assert_false(_start(s))
	assert_push_error("has no ships")


func test_unknown_ship_is_a_load_error() -> void:
	var s := _squadron()
	s["players"][0]["ships"] = ["brit_a1", "nope"]
	assert_false(_start(s))
	assert_push_error("unknown ship")


func test_two_fleet_flagships_is_a_load_error() -> void:
	var s := _squadron()
	s["ships"][1]["flag"] = "fleet"
	assert_false(_start(s))
	assert_push_error("two fleet flagships")


func test_flagship_out_of_play_is_not_a_flagship() -> void:
	assert_true(_start(_squadron()))
	var ship: ShipState = GameState.ships["brit_a1"]
	assert_true(ship.is_flagship())
	GameState.damage_controller.strike("brit_a1", "test", TurnPhaseController.GamePhase.COMBAT_RESOLUTION)
	assert_false(ship.is_flagship())
	assert_eq(GameState.in_play_ships_of_player(0).size(), 1)


func test_groups_loaded() -> void:
	assert_true(_start(_squadron()))
	assert_eq(GameState.groups[0]["Rear"], ["brit_b1"])


func test_players_serialise() -> void:
	var p := PlayerState.new()
	p.id = 3
	p.side = 1
	p.name = "Dumanoir"
	p.is_ai = true
	var q := PlayerState.from_dict(p.to_dict())
	assert_eq([q.id, q.side, q.name, q.is_ai], [3, 1, "Dumanoir", true])


func test_commander_id_serialises() -> void:
	assert_true(_start(_squadron()))
	var d: Dictionary = GameState.ships["brit_b1"].serialize()
	assert_eq(d["commander_id"], 1)
	assert_eq(ShipState.deserialize(d).commander_id, 1)
