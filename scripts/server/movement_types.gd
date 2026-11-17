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
	var resulting_hex: Vector2i = Vector2i.ZERO  # Bow hex after this move (a turn keeps the bow hex; 5.C.2)

	func _init(p_move_type: MoveType = MoveType.NONE, p_resulting_facing: int = 0, p_ma_cost: int = 1, p_resulting_hex: Vector2i = Vector2i.ZERO) -> void:
		move_type = p_move_type
		resulting_facing = p_resulting_facing
		ma_cost = p_ma_cost
		resulting_hex = p_resulting_hex

	func to_dict() -> Dictionary:
		return {
			"move_type": move_type,
			"resulting_facing": resulting_facing,
			"ma_cost": ma_cost,
			"resulting_hex": {"q": resulting_hex.x, "r": resulting_hex.y}
		}

	static func from_dict(data: Dictionary) -> MoveMetadata:
		var hex: Dictionary = data.get("resulting_hex", {})
		return MoveMetadata.new(
			data.get("move_type", ""),
			data.get("resulting_facing", 0),
			data.get("ma_cost", 1),
			Vector2i(int(hex.get("q", 0)), int(hex.get("r", 0)))
		)


## A single valid hex move, relative to the previous move/facing
class ValidMove extends RefCounted:
	var hex: Vector2i = Vector2i.ZERO
	var move: MoveType = MoveType.NONE
	var metadata: MoveMetadata = null

	func _init(p_hex: Vector2i = Vector2i.ZERO, p_move: MoveType = MoveType.NONE, p_metadata: MoveMetadata = null) -> void:
		hex = p_hex
		move = p_move
		metadata = p_metadata if p_metadata else MoveMetadata.new()

	func to_dict() -> Dictionary:
		return {
			"hex": {"q": hex.x, "r": hex.y},
			"move": move,
			"metadata": metadata.to_dict() if metadata else {}
		}

	static func from_dict(data: Dictionary) -> ValidMove:
		var hex_data = data.get("hex", {})
		var p_hex = Vector2i(hex_data.get("q", 0), hex_data.get("r", 0))
		var move_data = data.get("move", {})
		var move_enum = MoveType.get(move_data)
		var meta = MoveMetadata.from_dict(data.get("metadata", {}))
		return ValidMove.new(p_hex, move_enum, meta)


## Valid moves organized by direction relative to ship's bow
class ValidNextHexes extends RefCounted:
	var port: ValidMove = null             ## Single port (left) move, or null if blocked
	var forward: Array[ValidMove] = []     ## Forward moves, empty if blocked
	var starboard: ValidMove = null        ## Single starboard (right) move, or null if blocked

	func _init() -> void:
		forward = []

	func has_any_moves() -> bool:
		return port != null or not forward.is_empty() or starboard != null

	func get_all_valid_moves() -> Array[ValidMove]:
		"""Flatten all valid moves into a single array for rendering"""
		var moves: Array[ValidMove] = []
		if port:
			moves.append(port)
		moves.append_array(forward)
		if starboard:
			moves.append(starboard)
		return moves

	func to_dict() -> Dictionary:
		var fwd_array: Array = []
		for vm in forward:
			fwd_array.append(vm.to_dict())
		var result := {
			"port": null,
			"forward": fwd_array,
			"starboard": null,
		}
		if port:
			result["port"] = port.to_dict()
		if starboard:
			result["starboard"] = starboard.to_dict()
		return result

	static func from_dict(data: Dictionary) -> ValidNextHexes:
		var vnh = ValidNextHexes.new()
		if data.get("port"):
			vnh.port = ValidMove.from_dict(data["port"])
		for fwd in data.get("forward", []):
			vnh.forward.append(ValidMove.from_dict(fwd))
		if data.get("starboard"):
			vnh.starboard = ValidMove.from_dict(data["starboard"])
		return vnh


## Result from MovementValidator.calculate_valid_moves()
class ValidMovesResult extends RefCounted:
	var valid_hexes: ValidNextHexes = null
	var can_submit: bool = true
	var remaining_ma: int = 0
	var max_ma: int = 0  ## the most the ship may move this g-t at the plotted heading (acceleration capped)
	var mp_spent: int = 0  ## movement points the path spends (turns included)
	var is_tacking_attempt: bool = false

	func _init() -> void:
		valid_hexes = ValidNextHexes.new()

	func to_dict() -> Dictionary:
		return {
			"valid_hexes": valid_hexes.to_dict() if valid_hexes else {},
			"can_submit": can_submit,
			"remaining_ma": remaining_ma,
			"is_tacking_attempt": is_tacking_attempt
		}


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
	var move_type: MoveType = MoveType.NONE

	func _init(p_hex: Vector2i = Vector2i.ZERO, p_facing: int = 0, p_move_type: MoveType = MoveType.NONE) -> void:
		hex = p_hex
		facing = p_facing
		move_type = p_move_type

	func to_dict() -> Dictionary:
		return {
			"hex": {"q": hex.x, "r": hex.y},
			"facing": facing,
			"move_type": move_type
		}

	static func from_dict(data: Dictionary) -> PlotStep:
		var hex_data = data.get("hex", {})
		return PlotStep.new(
			Vector2i(hex_data.get("q", 0), hex_data.get("r", 0)),
			data.get("facing", 0),
			data.get("move_type", MoveType.NONE)
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
	var valid_next_hexes: ValidNextHexes = null
	var can_submit: bool = true
	var remaining_ma: int = 0
	var is_tacking_attempt: bool = false

	func _init() -> void:
		type = "PLOTTING_STARTED"
		valid_next_hexes = ValidNextHexes.new()

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		base.merge({
			"session_id": session_id,
			"session_version": session_version,
			"ship_id": ship_id,
			"origin_hex": {"q": origin_hex.x, "r": origin_hex.y},
			"valid_next_hexes": valid_next_hexes.to_dict() if valid_next_hexes else {},
			"can_submit": can_submit,
			"remaining_ma": remaining_ma,
			"is_tacking_attempt": is_tacking_attempt
		})
		return base


## Response for SELECT_HEX request
class HexSelectedResponse extends PlottingResponse:
	var session_id: String = ""
	var session_version: int = 0
	var plotted_path: Array[PlotStep] = []
	var valid_next_hexes: ValidNextHexes = null
	var can_submit: bool = true
	var remaining_ma: int = 0
	var is_tacking_attempt: bool = false

	func _init() -> void:
		type = "HEX_SELECTED"
		plotted_path = []
		valid_next_hexes = ValidNextHexes.new()

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		var path_array: Array = []
		for step in plotted_path:
			path_array.append({"q": step.hex.x, "r": step.hex.y})

		base.merge({
			"session_id": session_id,
			"session_version": session_version,
			"plotted_path": path_array,
			"valid_next_hexes": valid_next_hexes.to_dict() if valid_next_hexes else {},
			"can_submit": can_submit,
			"remaining_ma": remaining_ma,
			"is_tacking_attempt": is_tacking_attempt
		})
		return base


## Response for UNDO request
class UndoCompleteResponse extends PlottingResponse:
	var session_id: String = ""
	var session_version: int = 0
	var plotted_path: Array[PlotStep] = []
	var valid_next_hexes: ValidNextHexes = null
	var can_submit: bool = true
	var remaining_ma: int = 0
	var is_tacking_attempt: bool = false

	func _init() -> void:
		type = "UNDO_COMPLETE"
		plotted_path = []
		valid_next_hexes = ValidNextHexes.new()

	func to_dict() -> Dictionary:
		var base = super.to_dict()
		var path_array: Array = []
		for step in plotted_path:
			path_array.append({"q": step.hex.x, "r": step.hex.y})

		base.merge({
			"session_id": session_id,
			"session_version": session_version,
			"plotted_path": path_array,
			"valid_next_hexes": valid_next_hexes.to_dict() if valid_next_hexes else {},
			"can_submit": can_submit,
			"remaining_ma": remaining_ma,
			"is_tacking_attempt": is_tacking_attempt
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


## ============================================================================
## Resolution Types
## ============================================================================

enum ResolutionEventType {
	MOVE,
	TACKING_ROLL,
	IN_IRONS_ESCAPE_ROLL,
	IMMOBILIZED,
	CONTESTED_HEX_ROLL,
	BEARING_OFF_ROLL,
	BEARING_OFF_PIVOT_DENIED,
	COLLISION,
	FOULING,
	COLLISION_RIGGING_LOSS,
	STOPPED,
	STERN_BLOCKED,  # a turn cancelled outright; detail "lost stern contest to <id>" (6.B.4c, 6.B.5, 6.C.5)
	OVERLAP,  # a swinging stern entered a hex another ship holds or enters (6.B.2); detail "overlaps <id>[, <id>]"
	OVERLAP_ROLLBACK,  # the overlap was not cleared on the next segment: the turn is undone (6.B.4)
	BEARING_OFF_DECLINED,  # the ship held its course and collides on purpose (6.D.3, 6.E.1)
	POOR_MANEUVERING_ROLL,  # 6.F.3 d10 for a plotted turn; detail on failure: "one hex ahead", "carried over", "turn at MA 0"
	## 6.D.3c: two or more potential collisions on one segment, ordered by d10 (highest first, ties
	## re-rolled). On the ship resolved first; detail "<id>=<d10>[,<re-roll>…] …" in resolution order.
	BEAR_OFF_ORDER,
}

## Choices for a potential collision (6.D): bear off to port or starboard, or hold course and collide.
const BEAR_OFF_PORT := "port"
const BEAR_OFF_STARBOARD := "starboard"
const BEAR_OFF_COLLIDE := "collide"


## A potential collision waiting for its owner's decision (6.D.1-6.D.3). `eligible` lists the
## directions a turn is legal in at that point of the plot (6.D.2); "collide" is always allowed.
## `number` is the Bearing Off chart's "roll <= n" (-1 = NA), `drm` its modifiers; `chance` the odds.
class BearOffSituation extends RefCounted:
	var ship_id: String = ""
	var blocker_id: String = ""
	var segment: int = 0
	var bow: Vector2i = Vector2i.ZERO
	var facing: int = 0
	var eligible: Array[String] = []
	var number: int = -1
	var drm: int = 0
	var chance: float = 0.0
	## 6.D.3a: the player may see every other ship's plot. ship_id -> the bow hexes (Array[Vector2i])
	## of its steps from this segment on.
	var other_plots: Dictionary = {}

	func choices() -> Array[String]:
		var all: Array[String] = eligible.duplicate()
		all.append(BEAR_OFF_COLLIDE)
		return all

	func to_dict() -> Dictionary:
		return {"ship_id": ship_id, "blocker_id": blocker_id, "segment": segment,
			"bow": {"q": bow.x, "r": bow.y}, "facing": facing, "eligible": eligible,
			"number": number, "drm": drm, "chance": chance}

class ResolutionEvent extends RefCounted:
	var ship_id: String = ""
	var impulse: int = 0
	var event_type: ResolutionEventType = ResolutionEventType.MOVE
	var from_hex: Vector2i = Vector2i.ZERO
	var to_hex: Vector2i = Vector2i.ZERO
	var facing: int = 0
	var from_facing: int = 0  # facing before the step (MOVE events)
	var roll: float = -1.0
	var threshold: float = -1.0
	var success: bool = true
	var detail: String = ""

	func _init(p_ship_id: String = "", p_impulse: int = 0, p_type: ResolutionEventType = ResolutionEventType.MOVE) -> void:
		ship_id = p_ship_id
		impulse = p_impulse
		event_type = p_type

	func to_dict() -> Dictionary:
		var d := {
			"ship_id": ship_id,
			"impulse": impulse,
			"event_type": event_type,
			"from_hex": {"q": from_hex.x, "r": from_hex.y},
			"to_hex": {"q": to_hex.x, "r": to_hex.y},
			"facing": facing,
			"from_facing": from_facing,
			"success": success,
		}
		if roll >= 0.0:
			d["roll"] = roll
			d["threshold"] = threshold
		if detail != "":
			d["detail"] = detail
		return d


class ShipResolutionResult extends RefCounted:
	var ship_id: String = ""
	var events: Array[ResolutionEvent] = []
	var final_hex: Vector2i = Vector2i.ZERO
	var final_facing: int = 0
	var immobilized: bool = false
	var tacking_failed: bool = false
	var collided_with: String = ""
	var fouled_with: String = ""
	var blocked_by: String = ""  ## the ship whose hex this one could not enter (bear-off or collision)
	var rigging_damage: int = 0
	var stopped_at_impulse: int = -1
	## 6.F.4-5: the turn carried over to the next g-t's first MP (-1 none, PORT, STARBOARD).
	var pending_turn: int = -1

	func _init(p_ship_id: String = "") -> void:
		ship_id = p_ship_id
		events = []

	func to_dict() -> Dictionary:
		var ev_array: Array = []
		for ev in events:
			ev_array.append(ev.to_dict())
		var d := {
			"ship_id": ship_id,
			"events": ev_array,
			"final_hex": {"q": final_hex.x, "r": final_hex.y},
			"final_facing": final_facing,
			"immobilized": immobilized,
			"tacking_failed": tacking_failed,
		}
		if collided_with != "":
			d["collided_with"] = collided_with
		if fouled_with != "":
			d["fouled_with"] = fouled_with
		if blocked_by != "":
			d["blocked_by"] = blocked_by
		if rigging_damage > 0:
			d["rigging_damage"] = rigging_damage
		if stopped_at_impulse >= 0:
			d["stopped_at_impulse"] = stopped_at_impulse
		if pending_turn >= 0:
			d["pending_turn"] = pending_turn
		return d


class ResolutionLog extends RefCounted:
	var turn: int = 0
	var ship_results: Dictionary = {}
	var max_impulses: int = 0
	## A potential collision waiting for the player's decision: the log is complete only before
	## `pending_bear_off.segment`; play it up to there, then ask (see TurnPhaseController).
	var pending_bear_off: BearOffSituation = null
	## Playback starts here: segments before it were shown from an earlier log of the same turn,
	## which this one repeats exactly.
	var resume_impulse: int = 0

	func is_complete() -> bool:
		return pending_bear_off == null

	func _init(p_turn: int = 0) -> void:
		turn = p_turn

	func add_result(result: ShipResolutionResult) -> void:
		ship_results[result.ship_id] = result

	func get_result(ship_id: String) -> ShipResolutionResult:
		return ship_results.get(ship_id)

	func to_dict() -> Dictionary:
		var results_dict := {}
		for sid in ship_results:
			results_dict[sid] = ship_results[sid].to_dict()
		return {
			"turn": turn,
			"max_impulses": max_impulses,
			"ship_results": results_dict,
		}


## ============================================================================
## Protocol Response Types (continued)
## ============================================================================

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
