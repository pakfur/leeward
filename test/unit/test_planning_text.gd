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


func test_movement_line_reads_n_of_m_left() -> void:
	assert_eq(PlanningText.movement_line(3, 3), "Movement: 3 of 3 left")
	assert_eq(PlanningText.movement_line(2, 3), "Movement: 2 of 3 left")


func test_movement_limit_note_only_when_the_table_allows_more() -> void:
	assert_eq(PlanningText.movement_limit_note(3, 3, 0, 3), "")
	assert_eq(PlanningText.movement_limit_note(2, 3, 2, 1), "")
	assert_eq(PlanningText.movement_limit_note(7, 3, 0, 3),
		"Limited by acceleration: speed last turn 0, may gain 3 (wind and sail allow 7).")


func test_instructions_text() -> void:
	assert_eq(PlanningText.instructions(),
		"Click a ship's highlighted hexes to plot its course. Click a hex on its course to cut it back.")


func test_occupied_hexes_names_other_ships_only() -> void:
	var me := _ship("me", "Mine", Vector2i(0, 0))
	var foe := _ship("foe", "Foe", Vector2i(1, 0))
	foe.facing = 3  # stern at (2,0), clear of my hex
	var far := _ship("far", "Far", Vector2i(5, 5))
	var offered := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 0)]
	var result := PlanningText.occupied_hexes(offered, [me, foe, far], "me")
	assert_eq(result, {Vector2i(1, 0): "Foe"})


func test_occupied_hexes_include_a_ships_stern() -> void:
	var me := _ship("me", "Mine", Vector2i(0, 0))
	var foe := _ship("foe", "Foe", Vector2i(3, 0))  # facing E: stern at (2,0)
	var result := PlanningText.occupied_hexes([Vector2i(1, 0), Vector2i(2, 0)], [me, foe], "me")
	assert_eq(result, {Vector2i(2, 0): "Foe"})


func test_collision_text() -> void:
	assert_eq(PlanningText.collision_text("Foe"), "Collision risk: Foe is here")
	assert_eq(PlanningText.swing_collision_text("Foe"), "Stern would swing into Foe")


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
	# The allowance at the start heading and at the course-end heading differ.
	assert_eq(PlanningText.allowance_change_note(1, 3, "B", "C"),
		"Allowance changed on the new heading (broad reach → close hauled)")
	assert_eq(PlanningText.allowance_change_note(3, 0, "C", "L"),
		"Allowance changed on the new heading (close hauled → in irons)")


func test_no_allowance_note_for_an_ordinary_step() -> void:
	assert_eq(PlanningText.allowance_change_note(4, 3, "B", "B"), "", "same heading")
	assert_eq(PlanningText.allowance_change_note(4, 4, "B", "C"), "", "new point of sail, same allowance")
	assert_eq(PlanningText.allowance_change_note(4, 3, "B", "C"),
		"Allowance changed on the new heading (broad reach → close hauled)", "one less is a change too")
	assert_eq(PlanningText.allowance_change_note(2, 2, "B", "B"), "", "same point of sail: not a heading change")
	assert_eq(PlanningText.allowance_change_note(0, 0, "B", "C"), "", "nothing left either way")


# --- Head to wind ---------------------------------------------------------------------------

func test_head_to_wind_note_shown_whenever_the_plotted_heading_is_into_the_wind() -> void:
	# The remaining movement may be unchanged by the pivot: the irons note still shows.
	assert_eq(PlanningText.plot_note("", "L"), PlanningText.IRONS_NOTE)
	assert_eq(PlanningText.IRONS_NOTE, "Head to wind: the ship will be in irons and movement ends here.")
	assert_eq(PlanningText.plot_note("Allowance changed on the new heading (close hauled → in irons)", "L"),
		"Allowance changed on the new heading (close hauled → in irons)\n" + PlanningText.IRONS_NOTE)


func test_no_irons_note_the_g_t_after_a_calm() -> void:
	# 3.D.4: no ship is in irons in the g-t after the wind rose from 0.
	assert_eq(PlanningText.plot_note("", "L", true), "")
	assert_eq(PlanningText.plot_note("note", "L", true), "note")


func test_no_head_to_wind_note_off_the_wind() -> void:
	assert_eq(PlanningText.plot_note("", "C"), "")
	assert_eq(PlanningText.plot_note("note", "B"), "note")


# --- Tacking note (5.D.2a: crew sections at the braces) ----------------------------------------

func test_tacking_note_names_the_crew_and_the_full_crew_chance() -> void:
	assert_eq(PlanningText.tacking_note(0.6, 2, 0.8), "Tack: 60 % with 2 at the braces (3: 80 %)")
	assert_eq(PlanningText.tacking_note(0.3, 0, 0.9), "Tack: 30 % with 0 at the braces (3: 90 %)")


func test_tacking_note_full_crew_has_no_comparison() -> void:
	assert_eq(PlanningText.tacking_note(0.9, 3, 0.9), "Tack: 90 % with 3 at the braces")
