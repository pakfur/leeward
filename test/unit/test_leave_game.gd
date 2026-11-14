extends GutTest
## Leaving from the pause menu takes effect on one confirmation in every state, abandons any
## playback, and never tells the phase controller a playback finished afterwards.

const GameControllerScript = preload("res://scripts/core/game_controller.gd")

var gc: Node
var _left: int = 0


func before_each() -> void:
	_left = 0
	gc = GameControllerScript.new()  # not added to the tree: _ready (scene set-up) does not run
	autofree(gc)
	gc.back_to_scenarios_requested.connect(func(): _left += 1)


func test_leave_while_waiting_leaves_at_once() -> void:
	gc._leave_game()
	assert_eq(_left, 1)


func test_leave_during_combat_playback_leaves_at_once() -> void:
	gc._combat_playback_active = true
	gc._leave_game()
	assert_eq(_left, 1, "one confirmation is enough")
	assert_false(gc._combat_playback_active, "playback abandoned")


func test_combat_playback_ending_after_leave_does_not_advance_the_game() -> void:
	gc._combat_playback_active = true
	gc._leave_game()
	gc._combat_playback_active = true  # the coroutine's last step running late
	gc._finish_combat_playback()  # would push_error (outside RESOLVE) if it reached the server
	assert_eq(_left, 1)


func test_leave_during_movement_playback_aborts_it() -> void:
	var playback := MovementResolutionPlaybackController.new(HexGrid.new(), {}, 0)
	add_child_autofree(playback)
	gc.playback_controller = playback
	gc._leave_game()
	assert_eq(_left, 1)
	assert_true(playback.is_aborted())
	assert_null(gc.playback_controller)
	gc._on_playback_completed()  # would push_error (outside MOVEMENT_RESOLUTION) if forwarded
	assert_eq(_left, 1)


func test_a_second_leave_is_ignored() -> void:
	gc._leave_game()
	gc._leave_game()
	assert_eq(_left, 1)
