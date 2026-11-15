extends GutTest
## The bear-off decision protocol in MOVEMENT_RESOLUTION (6.D.3): the resolver stops at a prompted
## player's potential collision, the view plays up to it and calls on_playback_paused(), the player
## answers with player_submit_bear_off(), and the resolution runs again from the same dice.

var pc: TurnPhaseController
var _logs: Array = []
var _requests: Array = []
var _old_env: EnvironmentState
var _old_log: PhaseEvents.PhaseLog
var _old_prompt: Array[int]


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_env = GameState.environment
	_old_log = GameState.turn_log
	_old_prompt = pc.bear_off_prompt_player_ids
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	var env := EnvironmentState.new()
	env.wind_direction = 3
	env.wind_speed = 3
	GameState.environment = env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_logs = []
	_requests = []
	pc.resolution_log_ready.connect(_on_log)
	pc.bear_off_decision_requested.connect(_on_request)
	pc.bear_off_prompt_player_ids = [0] as Array[int]


func after_each() -> void:
	pc.resolution_log_ready.disconnect(_on_log)
	pc.bear_off_decision_requested.disconnect(_on_request)
	pc.bear_off_prompt_player_ids = _old_prompt
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	pc._pending_resolution_log = null
	GameState.environment = _old_env
	GameState.turn_log = _old_log
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _on_log(log: MovementTypes.ResolutionLog) -> void:
	_logs.append(log)


func _on_request(situation: MovementTypes.BearOffSituation) -> void:
	_requests.append(situation)


func _make_ship(id: String, player: int, hex: Vector2i, facing: int, speed: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "D", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
	})
	state.hex_position = hex
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	state.crew_quality = "A"
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


## The player's ship sails three hexes east into a stopped enemy on (7,5): a potential collision on
## segment 1.
func _setup() -> void:
	var mine := _make_ship("mine", 0, Vector2i(5, 5), 0, 7)
	mine.plotted_actions.movement = [
		{"hex": {"q": 6, "r": 5}, "facing": 0}, {"hex": {"q": 7, "r": 5}, "facing": 0},
		{"hex": {"q": 8, "r": 5}, "facing": 0}]
	_make_ship("theirs", 1, Vector2i(7, 5), 1, 0)


func test_movement_pauses_for_the_players_decision() -> void:
	_setup()
	pc._enter_movement_resolution_phase()
	assert_eq(_logs.size(), 1)
	assert_false(_logs[0].is_complete(), "The log stops at the potential collision")
	assert_eq(_logs[0].resume_impulse, 0)

	pc.on_playback_completed()
	assert_push_error("decision pending")
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION, "Cannot finish yet")

	pc.on_playback_paused()
	assert_eq(_requests.size(), 1)
	assert_eq(_requests[0].ship_id, "mine")
	assert_eq(_requests[0].segment, 1)


func test_answers_are_validated() -> void:
	_setup()
	pc._enter_movement_resolution_phase()
	assert_ne(pc.player_submit_bear_off(1, "mine", "port"), "", "Not the owner")
	assert_ne(pc.player_submit_bear_off(0, "theirs", "port"), "", "Not the ship asked about")
	assert_ne(pc.player_submit_bear_off(0, "mine", "astern"), "", "Not a choice")
	assert_eq(_logs.size(), 1, "Nothing re-run")


func test_an_answer_resumes_the_resolution_at_its_segment() -> void:
	_setup()
	pc._enter_movement_resolution_phase()
	assert_eq(pc.player_submit_bear_off(0, "mine", MovementTypes.BEAR_OFF_COLLIDE), "")
	assert_eq(_logs.size(), 2)
	var log: MovementTypes.ResolutionLog = _logs[1]
	assert_true(log.is_complete())
	assert_eq(log.resume_impulse, 1, "Playback resumes where it paused")
	assert_eq(log.get_result("mine").collided_with, "theirs", "Held course")
	assert_ne(pc.player_submit_bear_off(0, "mine", "port"), "", "Nothing pending any more")


func test_no_prompt_for_players_not_wired_in() -> void:
	pc.bear_off_prompt_player_ids = [] as Array[int]
	_setup()
	pc._enter_movement_resolution_phase()
	assert_true(_logs[0].is_complete(), "The AI rule decides: no pause")


func test_the_rerun_repeats_the_dice_before_the_decision() -> void:
	# A poor-maneuvering third ship rolls for its turn on segment 0, before the decision: the re-run
	# after the answer must roll the same die (the log already played up to the decision).
	_setup()
	var other := _make_ship("helm", 1, Vector2i(5, 9), 3, 2)
	other.wheel_shot_away = true
	other.plotted_actions.movement = [{"hex": {"q": 5, "r": 9}, "facing": 2},
		{"hex": {"q": 4, "r": 10}, "facing": 2}]
	pc._enter_movement_resolution_phase()
	var first := _steering_roll(_logs[0].get_result("helm"))
	assert_eq(pc.player_submit_bear_off(0, "mine", MovementTypes.BEAR_OFF_COLLIDE), "")
	assert_eq(_steering_roll(_logs[1].get_result("helm")), first, "same Poor Maneuvering die")


func _steering_roll(result: MovementTypes.ShipResolutionResult) -> int:
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.POOR_MANEUVERING_ROLL:
			return int(ev.roll)
	return -1
