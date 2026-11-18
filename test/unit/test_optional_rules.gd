extends GutTest
## Optional rules switches (14.B, 14.D, 14.E): the scenario block, its validation and the
## start_scenario override.

func after_each() -> void:
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


func _with(block: Variant) -> Dictionary:
	return {"optional_rules": block}


func test_all_off_by_default() -> void:
	assert_eq(OptionalRules.of({}), {"voluntary_surrender": false, "fatigue": false,
		"gunfire_limits": "none"})
	for s in [{}, _with({})]:
		assert_false(OptionalRules.voluntary_surrender(s))
		assert_false(OptionalRules.fatigue(s))
		assert_false(OptionalRules.crew_limit(s))
		assert_false(OptionalRules.heel_limit(s))


func test_reads_each_switch() -> void:
	var s := _with({"voluntary_surrender": true})
	assert_true(OptionalRules.voluntary_surrender(s))
	assert_false(OptionalRules.fatigue(s))
	s = _with({"fatigue": true})
	assert_true(OptionalRules.fatigue(s))
	assert_false(OptionalRules.voluntary_surrender(s))
	s = _with({"gunfire_limits": "crew"})
	assert_true(OptionalRules.crew_limit(s))
	assert_false(OptionalRules.heel_limit(s))
	s = _with({"gunfire_limits": "heel"})
	assert_false(OptionalRules.crew_limit(s))
	assert_true(OptionalRules.heel_limit(s))
	s = _with({"gunfire_limits": "both"})
	assert_true(OptionalRules.crew_limit(s))
	assert_true(OptionalRules.heel_limit(s))
	s = _with({"gunfire_limits": "none"})
	assert_false(OptionalRules.crew_limit(s))
	assert_false(OptionalRules.heel_limit(s))


func test_bad_values_read_as_off() -> void:
	assert_eq(OptionalRules.of(_with([])), OptionalRules.of({}))
	assert_eq(OptionalRules.of(_with({"fatigue": 1, "gunfire_limits": "french"})),
		OptionalRules.of({}))


func test_errors() -> void:
	assert_eq(OptionalRules.errors({}), [] as Array[String])
	assert_eq(OptionalRules.errors(_with({"fatigue": true, "gunfire_limits": "both"})),
		[] as Array[String])
	var e := OptionalRules.errors(_with({"fatigu": true}))
	assert_eq(e.size(), 1)
	assert_string_contains(e[0], "unknown optional rule")
	e = OptionalRules.errors(_with({"fatigue": 1}))
	assert_eq(e.size(), 1)
	assert_string_contains(e[0], "true or false")
	e = OptionalRules.errors(_with({"gunfire_limits": "french"}))
	assert_eq(e.size(), 1)
	assert_string_contains(e[0], "none, crew, heel or both")
	e = OptionalRules.errors(_with([]))
	assert_eq(e.size(), 1)
	assert_string_contains(e[0], "must be an object")


func test_merged_overrides_keys() -> void:
	assert_eq(OptionalRules.merged({"fatigue": true}, {"gunfire_limits": "crew"}),
		{"fatigue": true, "gunfire_limits": "crew"})
	assert_eq(OptionalRules.merged({"fatigue": true}, {"fatigue": false})["fatigue"], false)


func test_start_scenario_merges_the_override() -> void:
	var s := DataManager.load_scenario("test_basic")
	assert_true(GameState.start_scenario(s, [] as Array[int], {"fatigue": true}))
	assert_true(OptionalRules.fatigue(GameState.active_scenario))
	assert_false(s.has("optional_rules"), "the loaded scenario is copied, not changed")


func test_start_scenario_refuses_bad_rules() -> void:
	var s := DataManager.load_scenario("test_basic")
	assert_false(GameState.start_scenario(s, [] as Array[int], {"gunfire_limits": "french"}))
	assert_push_error("gunfire_limits must be")
	assert_push_error("bad optional_rules")


func test_start_scenario_refuses_a_non_object_block() -> void:
	var s := DataManager.load_scenario("test_basic").duplicate(true)
	s["optional_rules"] = []
	assert_false(GameState.start_scenario(s, [] as Array[int], {"fatigue": true}))
	assert_push_error("must be an object")
	assert_push_error("bad optional_rules")
