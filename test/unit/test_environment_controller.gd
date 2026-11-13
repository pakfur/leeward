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
	return env

func _no_history() -> Array[EnvironmentState]:
	return [] as Array[EnvironmentState]

func test_wind_speed_followup_low_roll_decreases() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([0, 1, 3])
	_ctrl._update_wind_speed(env, _no_history())
	assert_eq(env.wind_speed, 1)

func test_wind_speed_followup_high_roll_increases() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([0, 1, 7])
	_ctrl._update_wind_speed(env, _no_history())
	assert_eq(env.wind_speed, 3)

func test_steady_wind_speed_unchanged_above_1() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([1, 1])
	_ctrl._update_wind_speed(env, _no_history())
	assert_eq(env.wind_speed, 2)

func test_gusty_wind_speed_changes_on_3() -> void:
	var env := _env(2, 0, "gusty", "oceanic")
	_dice.queue([1, 2, 9])
	_ctrl._update_wind_speed(env, _no_history())
	assert_eq(env.wind_speed, 3)

func test_wind_speed_reverts_on_16_plus() -> void:
	var original := _env(2, 0, "steady", "oceanic")
	var env := _env(3, 0, "steady", "oceanic")
	_dice.queue([8, 8])
	_ctrl._update_wind_speed(env, [original] as Array[EnvironmentState])
	assert_eq(env.wind_speed, 2)

func test_coastal_direction_changes_on_2_or_3() -> void:
	var env := _env(2, 0, "steady", "coastal")
	_dice.queue([1, 2, 2])
	_ctrl._update_wind_direction(env, _no_history())
	assert_eq(env.wind_direction, 5, "Follow-up 2 turns left (-1 mod 6)")

func test_coastal_direction_unchanged_on_5() -> void:
	var env := _env(2, 0, "steady", "coastal")
	_dice.queue([2, 3])
	_ctrl._update_wind_direction(env, _no_history())
	assert_eq(env.wind_direction, 0)

func test_oceanic_direction_changes_on_0_or_1() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([0, 1, 8])
	_ctrl._update_wind_direction(env, _no_history())
	assert_eq(env.wind_direction, 1, "Follow-up 8 turns right (+1)")

func test_oceanic_direction_unchanged_on_2() -> void:
	var env := _env(2, 0, "steady", "oceanic")
	_dice.queue([1, 1])
	_ctrl._update_wind_direction(env, _no_history())
	assert_eq(env.wind_direction, 0)

func test_direction_reverts_on_16_to_18() -> void:
	var original := _env(2, 0, "steady", "oceanic")
	var env := _env(2, 2, "steady", "oceanic")
	_dice.queue([9, 9])
	_ctrl._update_wind_direction(env, [original] as Array[EnvironmentState])
	assert_eq(env.wind_direction, 1)
