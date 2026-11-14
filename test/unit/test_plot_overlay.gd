extends GutTest
## The plotting overlay draws only what the server would accept: when the plot can go no further
## (head to wind, or nothing offered), no offered or blocked hexes are drawn around the ship.

const GameControllerScript = preload("res://scripts/core/game_controller.gd")

var grid := HexGrid.new()


func _forward_only(hex: Vector2i, facing: int) -> MovementTypes.ValidNextHexes:
	var vnh := MovementTypes.ValidNextHexes.new()
	var to := grid.get_neighbor(hex.x, hex.y, facing)
	var meta := MovementTypes.MoveMetadata.new(MovementTypes.MoveType.FORWARD, facing, 1)
	vnh.forward.append(MovementTypes.ValidMove.new(to, MovementTypes.MoveType.FORWARD, meta))
	return vnh


func test_nothing_offered_draws_no_blocked_hexes() -> void:
	var vnh := MovementTypes.ValidNextHexes.new()
	assert_eq(GameControllerScript.blocked_hexes_for(vnh, Vector2i(0, 0), 0, grid).size(), 0)


func test_null_offer_draws_nothing() -> void:
	assert_eq(GameControllerScript.blocked_hexes_for(null, Vector2i(0, 0), 0, grid).size(), 0)


func test_forward_only_marks_both_pivots_blocked() -> void:
	var blocked := GameControllerScript.blocked_hexes_for(_forward_only(Vector2i(0, 0), 0), Vector2i(0, 0), 0, grid)
	assert_eq(blocked.size(), 2)
	assert_has(blocked, grid.get_neighbor(0, 0, 5))
	assert_has(blocked, grid.get_neighbor(0, 0, 1))


# The server side (a pivot head to wind leaves no further move to offer) is pinned by
# test_movement_validator.gd::test_pivot_into_luffing_ends_movement; together with
# test_nothing_offered_draws_no_blocked_hexes, the picture matches what a click would do.
