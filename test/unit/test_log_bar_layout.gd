extends GutTest
## The combat log bar (collapsed or expanded) stops short of the ship status panel, so the two
## never overlap; the decision is a pure helper on CombatLogPanel.

const W := 1920.0  # logical UI width (canvas_items stretch: 1920x1080 and 1280x720 both lay out at 1920)


func _right_edge(status_left: float, visible: bool) -> float:
	return W + CombatLogPanel.bar_right_offset(W, status_left, visible)


func test_hidden_status_panel_keeps_the_default_right_margin() -> void:
	assert_eq(CombatLogPanel.bar_right_offset(W, 0.0, false), CombatLogPanel.DEFAULT_RIGHT_OFFSET)


func test_status_panel_at_its_scene_position_is_cleared() -> void:
	var status_left := W - 460.0
	assert_lt(_right_edge(status_left, true), status_left)


func test_status_panel_grown_wider_pushes_the_bar_edge_left() -> void:
	# Content wider than the scene's 440 px makes the panel grow left (grow_horizontal = begin).
	var status_left := W - 520.0
	var edge := _right_edge(status_left, true)
	assert_lt(edge, status_left)
	assert_almost_eq(edge, status_left - CombatLogPanel.STATUS_GAP, 0.01)


func test_bar_keeps_a_usable_width() -> void:
	var edge := _right_edge(600.0, true)
	assert_gte(edge - CombatLogPanel.LEFT_OFFSET, CombatLogPanel.MIN_BAR_WIDTH)
