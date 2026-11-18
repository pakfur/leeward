extends GutTest
## test_towing: HMS Hazard has HMS Bellerophon in tow and runs for the west edge while the French
## frigate Sirene looks for the cripple Cybele; every player AI (towing spec §7, §11).

const PHASES := TurnPhaseController.GamePhase

var pc: TurnPhaseController
var _logs: Array[MovementTypes.ResolutionLog] = []


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller
	_logs.clear()


func after_each() -> void:
	if pc.resolution_log_ready.is_connected(_on_resolution_log):
		pc.resolution_log_ready.disconnect(_on_resolution_log)
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


func _on_resolution_log(log: MovementTypes.ResolutionLog) -> void:
	_logs.append(log)


func _start() -> bool:
	var humans: Array[int] = []
	return GameState.start_scenario(DataManager.load_scenario("test_towing"), humans)


## One turn with every player AI (as test_anchorage_scenario.gd).
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


## The tow invariant (spec §1): the towed ship's bow plus her facing is her tower's stern hex.
func _invariant_errors() -> Array[String]:
	var errors: Array[String] = []
	for ship: ShipState in GameState.get_all_ships():
		if ship.towing_id == "":
			continue
		var towed: ShipState = GameState.get_ship(ship.towing_id)
		if towed.towed_by != ship.ship_id:
			errors.append("%s tows %s who is not marked towed by her" % [ship.ship_id, towed.ship_id])
		elif towed.hex_position + HexGrid.DIRECTIONS[towed.facing] != ship.stern_hex():
			errors.append("%s: tow station %s is not %s's stern %s" % [towed.ship_id,
					towed.hex_position + HexGrid.DIRECTIONS[towed.facing], ship.ship_id, ship.stern_hex()])
	return errors


func test_towing_places_cleanly() -> void:
	assert_true(_start())
	assert_eq(GameState.placement_errors(), [] as Array[String])
	var hazard: ShipState = GameState.get_ship("br_frigate_32")
	var bellerophon: ShipState = GameState.get_ship("br_74")
	assert_eq(hazard.towing_id, "br_74", "Hazard tows Bellerophon at the start")
	assert_eq(bellerophon.towed_by, "br_frigate_32")
	assert_eq(_invariant_errors(), [] as Array[String])
	assert_false(GameState.get_ship("fr_frigate_32").is_towed(), "Cybele is not yet in tow")


func test_towing_plays_twelve_turns_cleanly() -> void:
	assert_true(_start())
	pc.resolution_log_ready.connect(_on_resolution_log)
	var errors: Array[String] = []
	var sirene_prepared := false
	var cybele_towed := false
	for i in range(12):
		if not pc.game_result.is_empty():
			break
		_play_turn()
		errors.append_array(_invariant_errors())
		var sirene: ShipState = GameState.get_ship("fr_frigate_38")
		if sirene.tow_prepared or sirene.is_towing():
			sirene_prepared = true
		if GameState.get_ship("fr_frigate_32").is_towed():
			cybele_towed = true
	assert_eq(errors, [] as Array[String], "the tow invariant held at every end of turn")
	assert_true(pc.current_turn >= 12 or not pc.game_result.is_empty(), "the loop ran its turns")
	var follows := 0
	for log in _logs:
		var result: MovementTypes.ShipResolutionResult = log.get_result("br_74")
		if result == null:
			continue
		for ev in result.events:
			if ev.event_type == MovementTypes.ResolutionEventType.TOW_FOLLOW:
				follows += 1
	assert_true(follows >= 1, "Bellerophon followed her tower at least once (%d follows)" % follows)
	# The scripted run: the scenario cannot damage a ship, so Cybele is only under no sail (NS), not
	# dismasted, and the AI tows only a dismasted ship or a prize (StubAI._tow_candidates). Sirene
	# therefore never prepares to tow and Cybele is never taken in tow; Cybele is there for a human
	# or the Developer UI (take_in_tow) to pass a tow to.
	assert_false(sirene_prepared, "Sirene never prepares to tow: Cybele is no cripple")
	assert_false(cybele_towed, "Cybele is never in tow")
