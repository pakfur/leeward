extends GutTest
## The shipped scenarios load and place cleanly; the coastal and reinforcement scenarios play
## through the whole turn loop with every player AI (map and scenario spec §14).

const PHASES := TurnPhaseController.GamePhase

var pc: TurnPhaseController
var _errors: Array[String] = []


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller


func after_each() -> void:
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = PHASES.SETUP
	pc.game_result = {}
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()
	GameState.turn_logs = {}


func _scenario_names() -> Array[String]:
	var names: Array[String] = []
	for file in DirAccess.get_files_at("res://data/scenarios/"):
		if file.ends_with(".json"):
			names.append(file.trim_suffix(".json"))
	names.sort()
	return names


func _start(scenario_name: String) -> bool:
	var scenario := DataManager.load_scenario(scenario_name)
	var humans: Array[int] = []
	return GameState.start_scenario(scenario, humans)


## Plays one turn with every player AI: planning ends at once, so the loop answers the movement and
## combat playback (and End Turn) until the turn counter moves on or the game ends.
func _play_turn() -> void:
	var start_turn := pc.current_turn
	var guard := 0
	while pc.game_result.is_empty() and pc.current_turn == start_turn and guard < 40:
		guard += 1
		match pc.current_phase:
			PHASES.MOVEMENT_RESOLUTION:
				pc.on_playback_completed()
			PHASES.COMBAT_RESOLUTION:
				if pc.combat_step != TurnPhaseController.CombatStep.RESOLVE:
					break
				pc.on_combat_playback_completed()
			PHASES.POST_COMBAT:
				for id in GameState.player_ids():
					pc.player_end_turn(id)
			_:
				break


func _on_map_and_dry() -> bool:
	var terrain := TerrainMap.of(GameState.active_scenario)
	for ship: ShipState in GameState.ships_on_map():
		for hex in ship.occupied_hexes():
			if not terrain.in_bounds(hex) or terrain.is_land(hex):
				return false
	return true


func test_every_scenario_places_cleanly() -> void:
	for scenario_name in _scenario_names():
		assert_true(_start(scenario_name), "%s starts" % scenario_name)
		assert_eq(GameState.placement_errors(), [] as Array[String], "%s places cleanly" % scenario_name)


func test_coastal_plays_twenty_turns_cleanly() -> void:
	assert_true(_start("test_coastal"))
	var side1: ShipState = GameState.ships["p1"]
	for i in range(20):
		if not pc.game_result.is_empty():
			break
		_play_turn()
		assert_true(_on_map_and_dry(), "turn %d: no ship on land or off the map" % pc.current_turn)
	assert_true(pc.current_turn >= 20 or not pc.game_result.is_empty(), "the loop ran its turns")
	assert_true(side1.escape_declared or side1.status == ShipState.Status.ESCAPED,
			"the side-1 ship tried to escape")


func test_reinforcements_arrive_on_their_turns() -> void:
	assert_true(_start("test_reinforcements"))
	for i in range(6):
		if not pc.game_result.is_empty():
			break
		_play_turn()
	var log3: PhaseEvents.PhaseLog = GameState.turn_logs[3]
	var turn3 := log3.of_type(PhaseEvents.Type.ARRIVED)
	assert_eq(turn3.size(), 1)
	assert_eq(turn3[0].ship_id, "e_reinf")
	var log5: PhaseEvents.PhaseLog = GameState.turn_logs[5]
	var turn5 := log5.of_type(PhaseEvents.Type.ARRIVED)
	assert_eq(turn5.size(), 1)
	assert_eq(turn5[0].ship_id, "p_reinf")
	assert_eq(GameState.ships["p_reinf"].sail_state, "MS")
