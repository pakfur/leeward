extends GutTest
## Scenario anchoring permission and starting anchors (anchoring spec §7), and the Developer UI
## commands that drop and cut an anchor (DevCommands.anchor_ship / cut_anchor_cable).

const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func after_each() -> void:
	var pc := GameState.phase_controller
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.ai_player_ids = [] as Array[int]
	pc.current_phase = TurnPhaseController.GamePhase.SETUP


func _scenario(anchor, facing: int = 0, wind: int = 0, extra: Dictionary = {}) -> Dictionary:
	var s := DataManager.load_scenario("test_basic").duplicate(true)
	s["wind_direction"] = wind
	s["wind_speed"] = 2
	s["wind_speed_change"] = "steady"
	s["anchoring"] = true
	var ship := {"id": "a", "ship_name": "A", "player_id": 0, "ship_type": "frigate_38",
		"position": {"q": 0, "r": 0}, "facing": facing, "speed": 0, "sail_state": "FS",
		"crew_quality": "B", "crew_morale": 4}
	if anchor != null:
		ship["anchor"] = anchor
	s["ships"] = [ship]
	s.merge(extra, true)
	return s


func _start(scenario: Dictionary) -> ShipState:
	assert_true(GameState.start_scenario(scenario, [0] as Array[int]))
	return GameState.get_ship("a")


func test_starting_anchor_upwind_of_bow() -> void:
	var ship := _start(_scenario({"end": "bow", "springs": true, "cable": 1}))
	assert_eq(ship.anchor.hex, Vector2i(1, 0))
	assert_true(ship.has_springs())
	assert_eq(ship.anchorings_used, 1)
	assert_eq(int(ship.anchor.turn), 0)
	assert_eq(int(ship.anchor.cable), 1)
	assert_eq(int(ship.anchor.veered), 0)
	assert_eq(ship.hex_position, Vector2i(0, 0))
	GameState.current_turn = 1
	GameState.anchor_controller.resolve_anchoring(STATUS)
	assert_eq(ship.hex_position, Vector2i(0, 0))
	assert_eq(ship.facing, 0)


func test_starting_stern_anchor_cable_two() -> void:
	var ship := _start(_scenario({"end": "stern", "cable": 2}, 3))
	assert_eq(ship.stern_hex(), Vector2i(1, 0))
	assert_eq(ship.anchor.hex, Vector2i(3, 0))
	assert_eq(int(ship.anchor.veered), 1)


func test_explicit_anchor_hex() -> void:
	var ship := _start(_scenario({"end": "bow", "hex": [2, 0]}))
	assert_eq(ship.anchor.hex, Vector2i(2, 0))


func test_bad_anchor_entry_places_nothing() -> void:
	var ship := _start(_scenario({"end": "bow", "cable": 7}))
	assert_push_error("cable must be 1-4")
	assert_false(ship.is_anchored())
	assert_eq(ship.anchorings_used, 0)


func test_placement_errors_report_anchor_mistakes() -> void:
	_start(_scenario({"end": "bow", "cable": 7}, 0, 0, {"anchoring": "yes"}))
	assert_push_error(2, "start_scenario reports both")
	var found := 0
	for message in GameState.placement_errors():
		if message.begins_with("Anchoring: "):
			found += 1
	assert_eq(found, 2)


## Ruling 2026-11-18: a reinforcement enters under way; her starting anchor is reported and skipped.
func test_reinforcement_starts_with_no_anchor() -> void:
	var s := _scenario({"end": "bow", "cable": 1})
	s["ships"][0]["arrives"] = 3
	var ship := _start(s)
	assert_push_error("is a reinforcement and cannot start at anchor")
	assert_false(ship.is_anchored())
	assert_eq(ship.anchorings_used, 0)
	assert_true(GameState.placement_errors().has(
		"Anchoring: ship 'a' is a reinforcement and cannot start at anchor"))


## placement_errors: an explicit anchor hex whose footprint lies on land or off the map.
func test_placement_errors_report_anchor_footprint() -> void:
	# Wind from the east: the bow rides 1 hex west of the anchor at (3, 0), on (2, 0) and (1, 0).
	var ship := _start(_scenario({"end": "bow", "hex": [3, 0]}, 0, 0, {"terrain": {"land": [[1, 0]]}}))
	assert_push_error("which is land")
	assert_true(ship.is_anchored())
	var found: Array[String] = []
	for message in GameState.placement_errors():
		if message.begins_with("Anchoring: ") and message.contains("rides to"):
			found.append(message)
	assert_eq(found.size(), 1, str(found))


func test_dev_anchor_and_cut() -> void:
	var ship := _start(_scenario(null))
	var dev: DevCommands = GameState.dev_commands
	assert_eq(dev.anchor_ship("a"), "")
	assert_true(ship.is_anchored())
	assert_eq(str(ship.anchor.end), "bow")
	assert_eq(ship.anchor.hex, ship.hex_position)
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.ANCHORED).size(), 1)
	assert_ne(dev.anchor_ship("a"), "")
	assert_eq(dev.cut_anchor_cable("a"), "")
	assert_false(ship.is_anchored())
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.CABLE_CUT).size(), 1)
	assert_ne(dev.cut_anchor_cable("a"), "")
	assert_ne(dev.anchor_ship("nobody"), "")
