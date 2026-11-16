class_name CourseView
extends RefCounted
## Pure helpers (no state) from the server's course_options (TurnPhaseController.course_options:
## path, valid_next, remaining_ma, is_tacking_attempt, rudder_error) to what the view reads: the
## CourseClicks input, the hover candidates and the card's course readout.


## One CourseClicks entry: `path_hexes` (each step's bow hex; a turn keeps its bow hex),
## `next_hexes` (the offered moves' click targets) and `end_hex` (the bow after the last step,
## else the ship's bow).
static func course_input(options: Dictionary, ship: ShipState) -> Dictionary:
	var path_hexes: Array[Vector2i] = []
	for step in options.get("path", []):
		path_hexes.append(step.hex)
	var next_hexes: Array[Vector2i] = []
	var vnh: MovementTypes.ValidNextHexes = options.get("valid_next")
	if vnh != null:
		for vm in vnh.get_all_valid_moves():
			next_hexes.append(vm.hex)
	var end_hex: Vector2i = path_hexes[-1] if not path_hexes.is_empty() else ship.hex_position
	return {"path_hexes": path_hexes, "next_hexes": next_hexes, "end_hex": end_hex}


## The card's "Course: used of allowance MP": `allowance` is this turn's movement allowance, `used`
## what the stored course spends of it (allowance less the server's remaining movement).
static func course_info(options: Dictionary, _ship: ShipState, allowance: int) -> Dictionary:
	var used := clampi(allowance - int(options.get("remaining_ma", 0)), 0, maxi(allowance, 0))
	return {"used": used, "allowance": allowance}


## Click target -> MoveMetadata (resulting bow hex and facing) for the hover preview.
static func hover_candidates(vnh: MovementTypes.ValidNextHexes) -> Dictionary:
	var result := {}
	if vnh == null:
		return result
	for vm in vnh.get_all_valid_moves():
		result[vm.hex] = vm.metadata
	return result


## The card's warning line: the refusal of the last click on this ship if any, else the course's
## collision warning, then the jammed-rudder text ("" when there is nothing to say).
static func warning_text(refusal: String, collision: String, rudder_error: String) -> String:
	var lines: Array[String] = []
	var first := refusal if refusal != "" else collision
	if first != "":
		lines.append(first)
	if rudder_error != "":
		lines.append(rudder_error)
	return "\n".join(lines)
