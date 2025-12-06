class_name MovementValidator
extends RefCounted
## MovementValidator - Calculates valid movement options for ships
## This is a MOCK implementation - real rules to be implemented later
##
## The validator needs access to:
## - Ship state (position, facing, speed, sail_state, rigging, etc.)
## - Environment state (wind direction, wind speed, sea state)
## - Other ships (for collision detection)
## - Movement rules (from DataManager)

var game_state: Node = null
var hex_grid: HexGrid = null


func _init(p_game_state: Node = null) -> void:
	game_state = p_game_state if p_game_state else GameState
	hex_grid = HexGrid.new()


## Calculate valid next hexes from a given position
## This is the main entry point for movement validation
##
## Parameters:
## - ship_state: The ship being moved
## - current_hex: Current position in the path
## - current_facing: Current facing direction (0-5)
## - path_so_far: Array[PlotStep] representing moves already made
## - environment: Current environment state
##
## Returns: ValidMovesResult
func calculate_valid_moves(
	ship_state: ShipState,
	current_hex: Vector2i,
	current_facing: int,
	path_so_far: Array[MovementTypes.PlotStep],
	environment: EnvironmentState
) -> MovementTypes.ValidMovesResult:
	# TODO: Implement real movement rules
	# For now, return mocked response based on ship's movement allowance

	var ma = _get_movement_allowance(ship_state, current_facing, environment)
	var moves_made = path_so_far.size()
	var remaining_ma = max(0, ma - moves_made)

	var result = MovementTypes.ValidMovesResult.new()
	result.remaining_ma = remaining_ma
	result.can_submit = true  # For now, always allow submit

	if remaining_ma > 0:
		var valid_options = _mock_valid_hexes(current_hex, current_facing, ship_state)
		result.valid_hexes = valid_options

	return result


## Validate if a specific hex selection is legal
##
## Parameters:
## - ship_state: The ship being moved
## - current_hex: Current position before this move
## - current_facing: Current facing before this move
## - selected_hex: The hex the player wants to move to
## - path_so_far: Moves already made this turn
## - environment: Current environment state
##
## Returns: HexValidationResult
func validate_hex_selection(
	ship_state: ShipState,
	current_hex: Vector2i,
	current_facing: int,
	selected_hex: Vector2i,
	path_so_far: Array[MovementTypes.PlotStep],
	environment: EnvironmentState
) -> MovementTypes.HexValidationResult:
	# Get valid moves and check if selected hex is among them
	var valid_moves = calculate_valid_moves(
		ship_state,
		current_hex,
		current_facing,
		path_so_far,
		environment
	)

	for valid_hex_option in valid_moves.valid_hexes:
		if valid_hex_option.hex == selected_hex:
			return MovementTypes.HexValidationResult.success(
				valid_hex_option.metadata.resulting_facing,
				valid_hex_option.metadata
			)

	return MovementTypes.HexValidationResult.failure(
		"ILLEGAL_HEX",
		"Selected hex is not a valid move option"
	)


## Check if the current path can be submitted
##
## Parameters:
## - ship_state: The ship being moved
## - path: The complete plotted path
## - environment: Current environment state
##
## Returns: SubmissionValidationResult
func validate_submission(
	ship_state: ShipState,
	path: Array[MovementTypes.PlotStep],
	environment: EnvironmentState
) -> MovementTypes.SubmissionValidationResult:
	# TODO: Implement real validation
	# Check things like:
	# - Minimum movement requirements
	# - Luffing restrictions
	# - Other game-specific rules

	return MovementTypes.SubmissionValidationResult.success()


## MOCK: Generate valid hex options from current position
## This is a placeholder that returns neighboring hexes based on facing
func _mock_valid_hexes(current_hex: Vector2i, current_facing: int, ship_state: ShipState) -> Array[MovementTypes.ValidHexOption]:
	var valid: Array[MovementTypes.ValidHexOption] = []

	# Mock: Allow forward movement (in facing direction)
	var forward_hex = hex_grid.get_neighbor(current_hex.x, current_hex.y, current_facing)
	var forward_metadata = MovementTypes.MoveMetadata.new("forward", current_facing, 1)
	valid.append(MovementTypes.ValidHexOption.new(forward_hex, forward_metadata))

	# Mock: Allow port turn (turn left, 60 degrees)
	var port_facing = (current_facing + 5) % 6  # -1 mod 6
	var port_hex = hex_grid.get_neighbor(current_hex.x, current_hex.y, port_facing)
	var port_metadata = MovementTypes.MoveMetadata.new("port_turn", port_facing, 1)
	valid.append(MovementTypes.ValidHexOption.new(port_hex, port_metadata))

	# Mock: Allow starboard turn (turn right, 60 degrees)
	var starboard_facing = (current_facing + 1) % 6
	var starboard_hex = hex_grid.get_neighbor(current_hex.x, current_hex.y, starboard_facing)
	var starboard_metadata = MovementTypes.MoveMetadata.new("starboard_turn", starboard_facing, 1)
	valid.append(MovementTypes.ValidHexOption.new(starboard_hex, starboard_metadata))

	return valid


## Get movement allowance for ship based on current state
func _get_movement_allowance(ship_state: ShipState, facing: int, environment: EnvironmentState) -> int:
	# Use the ship's built-in MA calculation if available
	if ship_state:
		return ship_state.get_movement_allowance()

	# Fallback default
	return 4


## FUTURE IMPLEMENTATION NOTES:
## ============================
##
## The real implementation should consider:
##
## 1. Movement Allowance (MA):
##    - Lookup from movement_allowance.json based on:
##      - Ship speed_type (F/F, L/S, etc.)
##      - Wind speed (0-5)
##      - Wind facing (L/C/B/R)
##      - Sail state (FS/MS/PS/NS)
##      - Rigging quality (0-4)
##
## 2. Turn Restrictions:
##    - When can a ship turn?
##    - Cost of turning (MA or free?)
##    - Maximum turns per movement phase
##
## 3. Luffing Rules:
##    - What happens when facing into wind (wind_facing = "L")?
##    - Forced turns? Drift?
##
## 4. 2-Hex Ships:
##    - Frigates occupy 2 hexes
##    - Different pivot/turn mechanics?
##
## 5. Collision Detection:
##    - Check other ship positions
##    - Ramming rules?
##
## 6. Terrain/Map Bounds:
##    - Stay within map boundaries
##    - Shoals, land, etc.
##
## 7. Speed Continuity:
##    - Last turn's speed affects this turn
##    - Acceleration/deceleration limits
