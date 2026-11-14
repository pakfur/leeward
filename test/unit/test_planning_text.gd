extends GutTest
## Tests for PlanningText: planning panel card text, movement readout, instructions, collisions.


func _ship(id: String = "a", ship_name: String = "Alpha", hex: Vector2i = Vector2i.ZERO) -> ShipState:
	var t := Ship.new()
	t.ship_id = id
	t.ship_name = ship_name
	t.hull_hp = [5, 5, 5, 6] as Array[int]
	t.rigging_hp = [5, 5, 6, 6] as Array[int]
	var s := ShipState.new()
	s.ship = t
	s.hex_position = hex
	s.hull_current_hp = [4, 5, 5, 6] as Array[int]
	s.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	s.sail_state = "FS"
	s.crew_quality = "D"
	s.morale_rating = 4
	return s


func test_card_lines_show_all_four_sections_names_and_no_codes() -> void:
	var lines := PlanningText.card_lines(_ship())
	assert_eq(lines, ["Hull 4/5 5/5 5/5 6/6", "Rigging 5/5 5/5 6/6 6/6", "Fighting sail",
		"Crew quality D, morale 4"] as Array[String])
	for line in lines:
		assert_false(line.contains("["), "no raw arrays: %s" % line)


func test_movement_line_reads_n_of_m_left() -> void:
	assert_eq(PlanningText.movement_line(3, 3), "Movement: 3 of 3 left")
	assert_eq(PlanningText.movement_line(2, 3), "Movement: 2 of 3 left")


func test_movement_limit_note_only_when_the_table_allows_more() -> void:
	assert_eq(PlanningText.movement_limit_note(3, 3, 0, 3), "")
	assert_eq(PlanningText.movement_limit_note(2, 3, 2, 1), "")
	assert_eq(PlanningText.movement_limit_note(7, 3, 0, 3),
		"Limited by acceleration: speed last turn 0, may gain 3 (wind and sail allow 7).")


func test_instructions_singular_plural_and_done() -> void:
	assert_eq(PlanningText.instructions(1, 2, 0), "1 ship still needs orders. Select it and press Movement.")
	assert_eq(PlanningText.instructions(2, 2, 0), "2 ships still need orders. Select each and press Movement.")
	assert_eq(PlanningText.instructions(0, 2, 0), "All ships have orders. Press End Planning.")
	assert_eq(PlanningText.instructions(0, 2, 1), "All ships have orders. Press End Planning.")
	assert_eq(PlanningText.instructions(0, 2, 2), "No ship can move this turn. Press End Planning.")


func test_occupied_hexes_names_other_ships_only() -> void:
	var me := _ship("me", "Mine", Vector2i(0, 0))
	var foe := _ship("foe", "Foe", Vector2i(1, 0))
	var far := _ship("far", "Far", Vector2i(5, 5))
	var offered := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 0)]
	var result := PlanningText.occupied_hexes(offered, [me, foe, far], "me")
	assert_eq(result, {Vector2i(1, 0): "Foe"})


func test_collision_text() -> void:
	assert_eq(PlanningText.collision_text("Foe"), "Collision risk: Foe is here")


func test_name_and_type_reads_name_then_type() -> void:
	var s := _ship("a", "HMS Lively")
	s.ship.name = "38-gun Frigate"
	assert_eq(PlanningText.name_and_type(s), "HMS Lively — 38-gun Frigate")


func test_name_and_type_skips_a_type_the_name_already_says() -> void:
	var s := _ship("a", "38-gun Frigate 2")
	s.ship.name = "38-gun Frigate"
	assert_eq(PlanningText.name_and_type(s), "38-gun Frigate 2")
	s.ship.name = ""
	s.ship.ship_name = "Topaze"
	assert_eq(PlanningText.name_and_type(s), "Topaze")


# --- Allowance change after a pivot -----------------------------------------------------------

func test_allowance_note_when_a_pivot_changes_the_point_of_sail_and_the_allowance() -> void:
	# 1 left before the pivot; spending a point would leave 0, but the new heading allows more.
	assert_eq(PlanningText.allowance_change_note(1, 3, "B", "C"),
		"Allowance changed on the new heading (broad reach → close hauled)")
	assert_eq(PlanningText.allowance_change_note(3, 0, "C", "L"),
		"Allowance changed on the new heading (close hauled → in irons)")


func test_no_allowance_note_for_an_ordinary_step() -> void:
	assert_eq(PlanningText.allowance_change_note(4, 3, "B", "B"), "", "forward step spends one point")
	assert_eq(PlanningText.allowance_change_note(4, 3, "B", "C"), "", "pivot that only spends its point")
	assert_eq(PlanningText.allowance_change_note(2, 2, "B", "B"), "", "same point of sail: not a heading change")
	assert_eq(PlanningText.allowance_change_note(0, 0, "B", "C"), "", "nothing left either way")
