class_name MovementTypes
extends RefCounted
## MovementTypes - Typed data classes for the movement plotting system
##
## This file contains all typed classes used by:
## - MovementValidator
## - MovementPlottingSession
## - MovementPlottingController


## ============================================================================
## Movement Validation Types
## ============================================================================

enum MoveType { FORWARD, PORT, STARBOARD, NONE }

## Metadata describing a single move option
class MoveMetadata extends RefCounted:
	var move_type: MoveType = MoveType.NONE     
	var resulting_facing: int = 0        # Ship facing after this move (0-5)
	var ma_cost: int = 1                 # Movement allowance cost

	func _init(p_move_type: MoveType = MoveType.NONE, p_resulting_facing: int = 0, p_ma_cost: int = 1) -> void:
		move_type = p_move_type
		resulting_facing = p_resulting_facing
		ma_cost = p_ma_cost

	func to_dict() -> Dictionary:
		return {
			"move_type": move_type,
			"resulting_facing": resulting_facing,
			"ma_cost": ma_cost
		}

	static func from_dict(data: Dictionary) -> MoveMetadata:
		return MoveMetadata.new(
			data.get("move_type", ""),
			data.get("resulting_facing", 0),
			data.get("ma_cost", 1)
		)


## A single valid hex move, relative to the previous move/facing
class ValidMove extends RefCounted:
	var move: MoveType = MoveType.NONE
	var metadata: MoveMetadata = null

	func _init(p_move: MoveType = MoveType.NONE, p_metadata: MoveMetadata = null) -> void:
		move = p_move
		metadata = p_metadata if p_metadata else MoveMetadata.new()

	func to_dict() -> Dictionary:
		return {
			"move": move,
			"metadata": metadata.to_dict() if metadata else {}
		}

	static func from_dict(data: Dictionary) -> ValidMove:
		var move_data = data.get("move", {})
		var move_enum = MoveType.get(move_data)
		var meta = MoveMetadata.from_dict(data.get("metadata", {}))
		return ValidMove.new(move_enum, meta)


## Result from MovementValidator.calculate_valid_moves()
class ValidMovesResult extends RefCounted:
	var valid_hexes: Array[ValidMove] = []
	var can_submit: bool = true
	var remaining_ma: int = 0

	func _init() -> void:
		valid_hexes = []

	func add_option(move: MoveType, metadata: MoveMetadata) -> void:
		valid_hexes.append(ValidMove.new(move, metadata))


## Result from MovementValidator.validate_hex_selection()
class HexValidationResult extends RefCounted:
	var is_valid: bool = false
	var new_facing: int = 0
	var metadata: MoveMetadata = null
	var error_code: String = ""
	var error_message: String = ""

	static func success(p_new_facing: int, p_metadata: MoveMetadata) -> HexValidationResult:
		var result = HexValidationResult.new()
		result.is_valid = true
		result.new_facing = p_new_facing
		result.metadata = p_metadata
		return result

	static func failure(p_error_code: String, p_error_message: String) -> HexValidationResult:
		var result = HexValidationResult.new()
		result.is_valid = false
		result.error_code = p_error_code
		result.error_message = p_error_message
		return result


## Result from MovementValidator.validate_submission()
class SubmissionValidationResult extends RefCounted:
	var can_submit: bool = true
	var error_code: String = ""
	var error_message: String = ""

	static func success() -> SubmissionValidationResult:
		var result = SubmissionValidationResult.new()
		result.can_submit = true
		return result

	static func failure(p_error_code: String, p_error_message: String) -> SubmissionValidationResult:
		var result = SubmissionValidationResult.new()
		result.can_submit = false
		result.error_code = p_error_code
		result.error_message = p_error_message
		return result


## ============================================================================
## Session Types
## ============================================================================

## A single step in the plotted path
class PlotStep extends RefCounted:
	var hex: Vector2i = Vector2i.ZERO
	var facing: int = 0

	func _init(p_hex: Vector2i = Vector2i.ZERO, p_facing: int = 0) -> void:
		hex = p_hex
		facing = p_facing

	func to_dict() -> Dictionary:
		return {
			"hex": {"q": hex.x, "r": hex.y},
			"facing": facing
		}

	static func from_dict(data: Dictionary) -> PlotStep:
		var hex_data = data.get("hex", {})
		return PlotStep.new(
			Vector2i(hex_data.get("q", 0), hex_data.get("r", 0)),
			data.get("facing", 0)
		)


## ============================================================================
## Protocol Response Types
## ============================================================================

## Base class for all protocol responses
class PlottingResponse extends RefCounted:
	var type: String = ""
	var request_id: String = ""

	func to_dict() -> Dictionary:
		return {
			"type": type,
			"request_id": request_id
		}


## Response for START_PLOTTING request
class PlottingStartedResponse extends PlottingResponse:
	var session_id: String = ""
	var session_version: int = 0
	var ship_id: String = ""
	var origin_hex: Vector2i = Vector2i.ZERO
	var valid_next_hexes: Array[ValidMove] = []
	var can_submit: bool = true

	func _init() -> void:
		type = "PLOTTING_STARTED"
		valid_next_hexes = []

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		var hexes_array: Array = []
		for vh in valid_next_hexes:
			hexes_array.append(vh.to_dict())

		base.merge({
			"session_id": session_id,
			"session_version": session_version,
			"ship_id": ship_id,
			"origin_hex": {"q": origin_hex.x, "r": origin_hex.y},
			"valid_next_hexes": hexes_array,
			"can_submit": can_submit
		})
		return base


## Response for SELECT_HEX request
class HexSelectedResponse extends PlottingResponse:
	var session_id: String = ""
	var session_version: int = 0
	var plotted_path: Array[PlotStep] = []
	var valid_next_hexes: Array[ValidMove] = []
	var can_submit: bool = true

	func _init() -> void:
		type = "HEX_SELECTED"
		plotted_path = []
		valid_next_hexes = []

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		var path_array: Array = []
		for step in plotted_path:
			path_array.append({"q": step.hex.x, "r": step.hex.y})

		var hexes_array: Array = []
		for vh in valid_next_hexes:
			hexes_array.append(vh.to_dict())

		base.merge({
			"session_id": session_id,
			"session_version": session_version,
			"plotted_path": path_array,
			"valid_next_hexes": hexes_array,
			"can_submit": can_submit
		})
		return base


## Response for UNDO request
class UndoCompleteResponse extends PlottingResponse:
	var session_id: String = ""
	var session_version: int = 0
	var plotted_path: Array[PlotStep] = []
	var valid_next_hexes: Array[ValidMove] = []
	var can_submit: bool = true

	func _init() -> void:
		type = "UNDO_COMPLETE"
		plotted_path = []
		valid_next_hexes = []

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		var path_array: Array = []
		for step in plotted_path:
			path_array.append({"q": step.hex.x, "r": step.hex.y})

		var hexes_array: Array = []
		for vh in valid_next_hexes:
			hexes_array.append(vh.to_dict())

		base.merge({
			"session_id": session_id,
			"session_version": session_version,
			"plotted_path": path_array,
			"valid_next_hexes": hexes_array,
			"can_submit": can_submit
		})
		return base


## Response for CANCEL_PLOTTING request
class PlottingCancelledResponse extends PlottingResponse:
	var session_id: String = ""

	func _init() -> void:
		type = "PLOTTING_CANCELLED"

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		base["session_id"] = session_id
		return base


## Response for SUBMIT_MOVEMENT request
class MovementSubmittedResponse extends PlottingResponse:
	var session_id: String = ""
	var piece_id: String = ""
	var final_path: Array[PlotStep] = []
	var path_version: int = 0

	func _init() -> void:
		type = "MOVEMENT_SUBMITTED"
		final_path = []

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		var path_array: Array = []
		for step in final_path:
			path_array.append({"q": step.hex.x, "r": step.hex.y})

		base.merge({
			"session_id": session_id,
			"piece_id": piece_id,
			"final_path": path_array,
			"path_version": path_version
		})
		return base


## Error response for any failed request
class PlottingErrorResponse extends PlottingResponse:
	var error_code: String = ""
	var message: String = ""
	var current_version: int = -1  # -1 means not applicable

	func _init() -> void:
		type = "ERROR"

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		base.merge({
			"error_code": error_code,
			"message": message
		})
		if current_version >= 0:
			base["current_version"] = current_version
		return base

	static func create(p_request_id: String, p_error_code: String, p_message: String, p_current_version: int = -1) -> PlottingErrorResponse:
		var response = PlottingErrorResponse.new()
		response.request_id = p_request_id
		response.error_code = p_error_code
		response.message = p_message
		response.current_version = p_current_version
		return response
