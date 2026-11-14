extends GutTest
## While movement plays back, the side panel says ships are moving and offers no planning controls.

const GameControllerScript = preload("res://scripts/core/game_controller.gd")

var gc: Node


func before_each() -> void:
	gc = GameControllerScript.new()  # not added to the tree: _ready (scene set-up) does not run
	autofree(gc)


func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.find_children("*", "Label", true, false):
		out.append((child as Label).text)
	return out


func test_movement_panel_says_ships_are_moving() -> void:
	gc._show_movement_panel()
	assert_not_null(gc.combat_panel)
	assert_eq(gc.combat_panel.name, "MovementPanel")
	assert_has(_texts(gc.combat_panel), "Ships are moving…")


func test_movement_panel_has_no_planning_controls() -> void:
	gc._show_movement_panel()
	assert_null(gc.current_planning_ui, "the planning UI is gone from the side panel")
	assert_eq(gc.combat_panel.find_children("*", "Button", true, false).size(), 0)


func test_movement_panel_promises_no_skip_that_does_not_exist() -> void:
	assert_false(GameControllerScript.MOVEMENT_PLAYBACK_SKIPPABLE)
	gc._show_movement_panel()
	for text in _texts(gc.combat_panel):
		assert_false(text.to_lower().contains("skip"), text)


func test_movement_panel_lines_offer_skip_only_when_skippable() -> void:
	assert_eq(GameControllerScript.movement_panel_lines(false), ["Ships are moving…"] as Array[String])
	assert_eq(GameControllerScript.movement_panel_lines(true).size(), 2)
	assert_string_contains(GameControllerScript.movement_panel_lines(true)[1], "skip")
