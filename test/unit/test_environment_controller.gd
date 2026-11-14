extends GutTest
## Tests for wind rolls against the 1997 chart (d10 = 0-9, 2d10 = 0-18).

var _saved_dice: Dice
var _dice: ScriptedDice
var _ctrl: EnvironmentController

func before_each() -> void:
	_saved_dice = GameState.dice
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	_ctrl = EnvironmentController.new(GameState)

func after_each() -> void:
	_ctrl.free()
	GameState.dice = _saved_dice

func _env(speed: int, direction: int, change: String, region: String) -> EnvironmentState:
	var env := EnvironmentState.new()
	env.wind_speed = speed
	env.wind_direction = direction
	env.wind_speed_change = change
	env.region = region
	env.original_wind_speed = speed
	env.original_wind_direction = direction
	return env

func test_wind_speed_followup_low_roll_decreases() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([0, 1, 3])
	_ctrl._update_wind_speed(env)
	assert_eq(env.wind_speed, 1)

func test_wind_speed_followup_high_roll_increases() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([0, 1, 7])
	_ctrl._update_wind_speed(env)
	assert_eq(env.wind_speed, 3)

func test_steady_wind_speed_unchanged_above_1() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([1, 1])
	_ctrl._update_wind_speed(env)
	assert_eq(env.wind_speed, 2)

func test_gusty_wind_speed_changes_on_3() -> void:
	var env := _env(2, 0, "gusty", "oceanic")
	_dice.queue([1, 2, 9])
	_ctrl._update_wind_speed(env)
	assert_eq(env.wind_speed, 3)

func test_wind_speed_reverts_on_16_plus() -> void:
	var env := _env(3, 0, "steady", "oceanic")
	env.original_wind_speed = 2
	_dice.queue([8, 8])
	_ctrl._update_wind_speed(env)
	assert_eq(env.wind_speed, 2)

func test_wind_speed_reverts_upward_toward_original() -> void:
	var env := _env(1, 0, "steady", "oceanic")
	env.original_wind_speed = 3
	_dice.queue([9, 9])
	_ctrl._update_wind_speed(env)
	assert_eq(env.wind_speed, 2, "one step back up toward the original")

func test_wind_speed_at_original_unchanged_on_16_plus() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	env.original_wind_speed = 2
	_dice.queue([8, 8])
	_ctrl._update_wind_speed(env)
	assert_eq(env.wind_speed, 2)

func test_tick_reverts_toward_scenario_wind() -> void:
	# Through the real tick: the original comes from the scenario, not from state history
	var env := EnvironmentState.new()
	env.initialize_from_scenario({"wind_speed": 2, "wind_direction": 5, "region": "oceanic"})
	env.wind_speed = 3
	env.wind_direction = 0
	var saved_history := GameState.environment_history
	GameState.environment_history = [] as Array[EnvironmentState]
	_dice.queue([8, 8, 9, 9])
	_ctrl.tick_environment(env, 4)
	GameState.environment_history = saved_history
	assert_eq(env.wind_speed, 2, "speed steps back toward the scenario's 2")
	assert_eq(env.wind_direction, 5, "direction steps back toward the scenario's 5")

func test_coastal_direction_changes_on_2_or_3() -> void:
	var env := _env(2, 0, "steady", "coastal")
	_dice.queue([1, 2, 2])
	_ctrl._update_wind_direction(env)
	assert_eq(env.wind_direction, 5, "Follow-up 2 turns left (-1 mod 6)")

func test_coastal_direction_unchanged_on_5() -> void:
	var env := _env(2, 0, "steady", "coastal")
	_dice.queue([2, 3])
	_ctrl._update_wind_direction(env)
	assert_eq(env.wind_direction, 0)

func test_oceanic_direction_changes_on_0_or_1() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([0, 1, 8])
	_ctrl._update_wind_direction(env)
	assert_eq(env.wind_direction, 1, "Follow-up 8 turns right (+1)")

func test_oceanic_direction_unchanged_on_2() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([1, 1])
	_ctrl._update_wind_direction(env)
	assert_eq(env.wind_direction, 0)

func test_direction_reverts_on_16_to_18() -> void:
	var env := _env(2, 2, "steady", "oceanic")
	env.original_wind_direction = 0
	_dice.queue([9, 9])
	_ctrl._update_wind_direction(env)
	assert_eq(env.wind_direction, 1)

func test_direction_reverts_the_shorter_way_across_the_wrap() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	env.original_wind_direction = 5
	_dice.queue([8, 8])
	_ctrl._update_wind_direction(env)
	assert_eq(env.wind_direction, 5, "0 -> 5 is one step backwards, not five forwards")

func test_direction_reverts_forward_across_the_wrap() -> void:
	var env := _env(2, 5, "steady", "oceanic")
	env.original_wind_direction = 1
	_dice.queue([8, 8])
	_ctrl._update_wind_direction(env)
	assert_eq(env.wind_direction, 0, "5 -> 1 goes round through 0")

func test_direction_at_original_unchanged_on_16_plus() -> void:
	var env := _env(2, 3, "steady", "oceanic")
	env.original_wind_direction = 3
	_dice.queue([9, 9])
	_ctrl._update_wind_direction(env)
	assert_eq(env.wind_direction, 3)

func test_original_wind_set_from_scenario_and_serialized() -> void:
	var env := EnvironmentState.new()
	env.initialize_from_scenario({"wind_speed": 3, "wind_direction": 4})
	assert_eq(env.original_wind_speed, 3)
	assert_eq(env.original_wind_direction, 4)
	env.wind_speed = 1
	env.wind_direction = 0
	var copy := EnvironmentState.deserialize(env.serialize())
	assert_eq(copy.original_wind_speed, 3)
	assert_eq(copy.original_wind_direction, 4)

# --- Wind changes are logged in ENVIRONMENT ---

func _tick_logged(env: EnvironmentState, rolls: Array) -> PhaseEvents.PhaseLog:
	var saved_log := GameState.turn_log
	var turn_log := PhaseEvents.PhaseLog.new()
	GameState.turn_log = turn_log
	_dice.queue(rolls)
	_ctrl.tick_environment(env, 2)
	GameState.turn_log = saved_log
	return turn_log

func test_wind_shift_and_freshening_are_logged() -> void:
	var env := _env(2, 2, "steady", "oceanic")
	var turn_log := _tick_logged(env, [0, 1, 7, 0, 1, 7])  # speed +1, direction +1 (SW -> W)
	var winds := turn_log.of_type(PhaseEvents.Type.WIND)
	assert_eq(winds.size(), 1)
	assert_eq(winds[0].phase, TurnPhaseController.GamePhase.ENVIRONMENT)
	assert_eq(winds[0].to_text({}), "The wind veers to west and freshens to 3 (fresh)")

func test_wind_backing_and_easing_are_logged() -> void:
	var env := _env(2, 2, "steady", "oceanic")
	var turn_log := _tick_logged(env, [0, 1, 2, 0, 1, 2])  # speed -1, direction -1 (SW -> SE)
	assert_eq(turn_log.of_type(PhaseEvents.Type.WIND)[0].to_text({}),
		"The wind backs to south-east and eases to 1 (light)")

func test_steady_wind_logs_nothing() -> void:
	var env := _env(2, 2, "steady", "oceanic")
	var turn_log := _tick_logged(env, [5, 5, 5, 5])
	assert_eq(turn_log.events.size(), 0)
