class_name DefaultCourse
extends RefCounted
## 6.G.2 Failure to plot: "the ship continues at last turn's speed", straight ahead.
##
## Pure statics. The course is the plot a ship gets when its owner has not plotted movement
## (ShipState.plotted_actions["movement_plotted"] is false): forward steps, one per MP, found with
## the same MovementValidator the player's plotting uses, so it is always a legal plot.
##
## Two planner's calls (spec, 6.G.2):
## - The speed is the ship's actual speed (ShipState.speed, the hexes it moved last g-t).
## - The movement allowance wins over the deceleration minimum: a ship whose MA fell below its
##   speed sails MA hexes, not speed minus the allowed change.


## The refusals of MovementPlottingController.handle_start_plotting (SHIP_CAPTURED, SHIP_FOULED,
## SHIP_GRAPPLED, SHIP_DESTROYED, SHIP_STRUCK, SHIP_DISMASTED): such a ship cannot plot or move.
static func can_plot(ship: ShipState) -> bool:
	return not (ship.is_captured() or ship.fouled_with != "" or ship.is_grappled() \
			or ship.is_destroyed() or ship.is_struck() or ship.is_dismasted())


## The default course: up to min(speed, MA) forward steps along the facing. Empty at MA 0, at
## speed 0, for a ship that cannot plot, or when the next hex is not a legal forward move.
static func for_ship(game_state: Node, ship: ShipState) -> Array[MovementTypes.PlotStep]:
	var steps: Array[MovementTypes.PlotStep] = []
	if not can_plot(ship):
		return steps
	var count: int = mini(ship.speed, game_state.ship_controller.get_movement_allowance(ship.ship_id))
	if count <= 0:
		return steps
	var grid := HexGrid.new()
	var validator := MovementValidator.new(game_state)
	var cur_hex: Vector2i = ship.hex_position
	var cur_facing: int = ship.facing
	for i in range(count):
		var ahead: Vector2i = grid.get_neighbor(cur_hex.x, cur_hex.y, cur_facing)
		var options := validator.calculate_valid_moves(ship, cur_hex, cur_facing, steps)
		var found := false
		for move in options.valid_hexes.forward:
			if move.metadata.resulting_hex == ahead:
				found = true
				break
		if not found:
			break
		steps.append(MovementTypes.PlotStep.new(ahead, cur_facing, MovementTypes.MoveType.FORWARD))
		cur_hex = ahead
	return steps


## The steps as the dictionaries stored in plotted_actions["movement"].
static func as_dicts(steps: Array) -> Array:
	var out: Array = []
	for step in steps:
		out.append(step.to_dict())
	return out
