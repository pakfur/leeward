extends GutTest
## CourseView: the pure helpers that turn the server's course_options into what the map, the click
## router and the card read.

const T := MovementTypes.MoveType

var grid := HexGrid.new()


func _ship(id: String, bow: Vector2i, facing: int) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": id, "ship_name": id.capitalize()})
	s.hex_position = bow
	s.facing = facing
	return s


## Ahead from `bow`, plus a port and a starboard turn that keep the bow hex.
func _offer(bow: Vector2i, facing: int) -> MovementTypes.ValidNextHexes:
	var vnh := MovementTypes.ValidNextHexes.new()
	var ahead := grid.get_neighbor(bow.x, bow.y, facing)
	vnh.forward.append(MovementTypes.ValidMove.new(ahead, T.FORWARD, MovementTypes.MoveMetadata.new(T.FORWARD, facing, 1, ahead)))
	var port_facing := posmod(facing - 1, 6)
	var starboard_facing := posmod(facing + 1, 6)
	vnh.port = MovementTypes.ValidMove.new(grid.get_neighbor(bow.x, bow.y, port_facing), T.PORT,
		MovementTypes.MoveMetadata.new(T.PORT, port_facing, 1, bow))
	vnh.starboard = MovementTypes.ValidMove.new(grid.get_neighbor(bow.x, bow.y, starboard_facing), T.STARBOARD,
		MovementTypes.MoveMetadata.new(T.STARBOARD, starboard_facing, 1, bow))
	return vnh


func _options(path: Array, vnh: MovementTypes.ValidNextHexes, remaining: int) -> Dictionary:
	var steps: Array[MovementTypes.PlotStep] = []
	steps.assign(path)
	return {"path": steps, "valid_next": vnh, "remaining_ma": remaining,
		"is_tacking_attempt": false, "rudder_error": ""}


func test_course_input_lists_path_and_next_hexes() -> void:
	var ship := _ship("a", Vector2i(0, 0), 0)
	var path := [
		MovementTypes.PlotStep.new(Vector2i(1, 0), 0, T.FORWARD),
		MovementTypes.PlotStep.new(Vector2i(2, 0), 0, T.FORWARD),
		MovementTypes.PlotStep.new(Vector2i(2, 0), 1, T.STARBOARD),
	]
	var vnh := _offer(Vector2i(2, 0), 1)
	var input := CourseView.course_input(_options(path, vnh, 2), ship)
	assert_eq(input["path_hexes"], [Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 0)] as Array[Vector2i],
		"one hex per step, a turn on the bow hex it keeps")
	var next: Array[Vector2i] = []
	for vm in vnh.get_all_valid_moves():
		next.append(vm.hex)
	assert_eq(input["next_hexes"], next, "the click targets of the offered moves")
	assert_eq(input["end_hex"], Vector2i(2, 0), "the bow after the last step")
	assert_eq(CourseClicks.route(next[0], {"a": input}, "a")["kind"], "extend", "the router reads it")


func test_course_input_of_an_empty_course_ends_at_the_ship() -> void:
	var ship := _ship("a", Vector2i(4, 3), 2)
	var input := CourseView.course_input(_options([], null, 0), ship)
	assert_eq(input["path_hexes"], [] as Array[Vector2i])
	assert_eq(input["next_hexes"], [] as Array[Vector2i], "nothing offered")
	assert_eq(input["end_hex"], Vector2i(4, 3))


func test_course_info_counts_mp_used_and_allowance() -> void:
	var ship := _ship("a", Vector2i(0, 0), 0)
	var path := [MovementTypes.PlotStep.new(Vector2i(1, 0), 0, T.FORWARD),
		MovementTypes.PlotStep.new(Vector2i(2, 0), 0, T.FORWARD)]
	var info := CourseView.course_info(_options(path, _offer(Vector2i(2, 0), 0), 3), ship, 5)
	assert_eq(info["used"], 2, "allowance less what is left")
	assert_eq(info["allowance"], 5)
	var none := CourseView.course_info(_options([], null, 0), ship, 0)
	assert_eq(none["used"], 0)
	assert_eq(none["allowance"], 0)
	var odd := CourseView.course_info(_options([], null, 7), ship, 5)
	assert_eq(odd["used"], 0, "never below nothing")


func test_hover_candidates_hold_the_move_metadata() -> void:
	# A turn's click target is the neighbour the bow turns towards; the hover must show the ship on
	# its resulting bow hex (unchanged by a turn) and facing, which only the metadata carries.
	var vnh := _offer(Vector2i(0, 0), 0)
	var cands := CourseView.hover_candidates(vnh)
	assert_eq(cands.size(), 3)
	var meta = cands[vnh.starboard.hex]
	assert_true(meta is MovementTypes.MoveMetadata)
	assert_same(meta, vnh.starboard.metadata)
	assert_eq(meta.resulting_hex, Vector2i(0, 0), "a turn keeps the bow hex")
	assert_eq(meta.resulting_facing, 1)
	assert_eq(cands[vnh.forward[0].hex].resulting_hex, vnh.forward[0].hex)
	assert_eq(CourseView.hover_candidates(null).size(), 0)


func test_warning_prefers_a_refusal_and_adds_the_rudder_text() -> void:
	assert_eq(CourseView.warning_text("", "Collision risk: B is here", ""), "Collision risk: B is here")
	assert_eq(CourseView.warning_text("refused", "Collision risk: B is here", ""), "refused")
	assert_eq(CourseView.warning_text("", "", "Rudder jammed"), "Rudder jammed")
	assert_eq(CourseView.warning_text("", "Collision risk: B is here", "Rudder jammed"),
		"Collision risk: B is here\nRudder jammed")
	assert_eq(CourseView.warning_text("", "", ""), "")
