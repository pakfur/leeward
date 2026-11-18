extends GutTest
## Tests for FireGeometry: broadside arcs, battery bearing, range, rakes, line of sight.

const GameControllerScript = preload("res://scripts/core/game_controller.gd")

var grid: HexGrid
var geo: FireGeometry


func before_each() -> void:
	grid = HexGrid.new()
	geo = FireGeometry.new(grid)


func _n(d: int) -> Vector2i:
	return HexGrid.DIRECTIONS[d]


func _steps(d: int, count: int) -> Vector2i:
	return HexGrid.DIRECTIONS[d] * count


# --- leeward_side (7.F.2) ---

func test_leeward_side_all_facings() -> void:
	# Wind from direction 0: r = facing, so 1,2 -> starboard; 4,5 -> port; 0,3 -> none.
	assert_eq(FireGeometry.leeward_side(1, 0), ShipState.STARBOARD)
	assert_eq(FireGeometry.leeward_side(2, 0), ShipState.STARBOARD)
	assert_eq(FireGeometry.leeward_side(4, 0), ShipState.PORT)
	assert_eq(FireGeometry.leeward_side(5, 0), ShipState.PORT)
	assert_eq(FireGeometry.leeward_side(0, 0), -1)
	assert_eq(FireGeometry.leeward_side(3, 0), -1)
	# A rotated wind: wind from 2, facing 3 -> r = 1 -> starboard; facing 0 -> r = 4 -> port.
	assert_eq(FireGeometry.leeward_side(3, 2), ShipState.STARBOARD)
	assert_eq(FireGeometry.leeward_side(0, 2), ShipState.PORT)


# --- bearing_side ---

func test_bearing_side_starboard_neighbours() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(1)), ShipState.STARBOARD)
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(2)), ShipState.STARBOARD)


func test_bearing_side_port_neighbours() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(5)), ShipState.PORT)
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(4)), ShipState.PORT)


func test_bearing_side_bow_and_stern_are_neither() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(0)), -1)
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(3)), -1)


func test_bearing_side_three_steps_along_direction_1() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _steps(1, 3)), ShipState.STARBOARD)


func test_bearing_side_due_beam_range_two() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(1) + _n(2)), ShipState.STARBOARD)


func test_bearing_side_thirty_degrees_off_bow_is_neither() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, _n(0) + _n(1)), -1)


func test_bearing_side_facing_three() -> void:
	assert_eq(geo.bearing_side(Vector2i.ZERO, 3, _n(4)), ShipState.STARBOARD)


# --- range_between ---

func test_range_is_closest_hexes() -> void:
	# Firer bow (6,0) facing W, stern (7,0); target bow (2,0) facing W, stern (3,0).
	# Firer bow to target stern is 3; every other pair is farther.
	var firer: Array[Vector2i] = [Vector2i(6, 0), Vector2i(7, 0)]
	var target: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	assert_eq(geo.range_between(firer, target), 3)
	assert_eq(geo.range_between(target, firer), 3)


# --- battery_bears ---

func test_battery_bears_when_both_target_hexes_in_arc_and_clear() -> void:
	var target: Array[Vector2i] = [_n(1) * 2, _n(1) * 3]
	assert_true(geo.battery_bears(Vector2i.ZERO, 0, ShipState.STARBOARD, target, {}))


func test_battery_does_not_bear_on_other_side() -> void:
	var target: Array[Vector2i] = [_n(1) * 2, _n(1) * 3]
	assert_false(geo.battery_bears(Vector2i.ZERO, 0, ShipState.PORT, target, {}))


func test_battery_does_not_bear_when_in_arc_hex_blocked() -> void:
	var target: Array[Vector2i] = [_n(1) * 2, _n(1) * 3]
	assert_false(geo.battery_bears(Vector2i.ZERO, 0, ShipState.STARBOARD, target, {_n(1): true}))


func test_partial_target_only_in_arc_hexes_need_los() -> void:
	# Diagram 17 ship E: target stern (0,2) is in the starboard bow arc of a battery at the
	# origin facing E; its bow (1,2) is outside that arc and the LOS to it is blocked at (1,1).
	var in_arc := Vector2i(0, 2)
	var out_of_arc := Vector2i(1, 2)
	var occupied := {Vector2i(1, 1): true}
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, in_arc), ShipState.STARBOARD)
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, out_of_arc), -1)
	assert_false(geo.has_line_of_sight(Vector2i.ZERO, out_of_arc, occupied), "setup: far LOS blocked")
	var target: Array[Vector2i] = [out_of_arc, in_arc]
	assert_true(geo.battery_bears(Vector2i.ZERO, 0, ShipState.STARBOARD, target, occupied))


func test_battery_does_not_bear_beyond_fifteen_hexes() -> void:
	var target: Array[Vector2i] = [_n(1) * 16, _n(1) * 17]
	assert_false(geo.battery_bears(Vector2i.ZERO, 0, ShipState.STARBOARD, target, {}))


# --- rake_type_ships (target bow at the origin facing E, stern at (-1,0)) ---

func test_rake_stern_adjacent_astern() -> void:
	# Firer bow directly astern of the target's stern; its own stern is in the target's port stern arc.
	var firer: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(-2, -1)]
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "stern")


func test_rake_stern_by_clause_b_when_a_firer_hex_is_in_an_arc() -> void:
	# Firer bow (-2,1) facing SE: its stern (-2,0) is the hex directly astern of the target's stern
	# (-1,0) (7.E.2b). Clause a fails: (-2,1) is in the target's stern-battery starboard arc.
	var firer: Array[Vector2i] = [Vector2i(-2, 1), HexGrid.stern_of(Vector2i(-2, 1), 1)]
	assert_eq(firer[1], Vector2i(-2, 0), "setup: firer stern")
	assert_eq(firer[1], Vector2i(-1, 0) + _n(3), "setup: directly astern of the target's stern")
	assert_eq(geo.bearing_side(Vector2i(-1, 0), 0, firer[0]), ShipState.STARBOARD, "setup: bow in an arc")
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "stern")


func test_rake_bow_dead_ahead() -> void:
	var firer: Array[Vector2i] = [_steps(0, 2), _n(0)]
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "bow")


func test_rake_beam_is_none() -> void:
	var firer: Array[Vector2i] = [Vector2i(-1, 1), Vector2i(-2, 1)]
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "")


func test_rake_firer_hex_on_arc_boundary_is_none() -> void:
	# (2,-2) is exactly 60 degrees off the target's bow: inside the port bow arc.
	var firer: Array[Vector2i] = [_steps(5, 2), _steps(5, 2) + _n(0)]
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "")


func test_rake_inside_stern_wedge() -> void:
	var firer: Array[Vector2i] = [_steps(3, 3) + _n(2), _steps(3, 4) + _n(2)]
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "stern")


func test_rake_zone_is_outside_all_arcs() -> void:
	# Firer bow (3,-2) facing SW, stern (4,-3): about 45 degrees off the target's bow line
	# (bow hex 41 degrees, ship centre 43), range 3, outside all four target arcs.
	# The old +/-30 degree wedge did not count this as a rake.
	var firer: Array[Vector2i] = [Vector2i(3, -2), Vector2i(4, -3)]
	assert_eq(geo.range_between(firer, [Vector2i.ZERO, Vector2i(-1, 0)] as Array[Vector2i]), 3)
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "bow")


func test_adjacent_dead_ahead_is_rake() -> void:
	# Firer bow (1,0) adjacent and directly ahead of the target's bow; firer facing SE, so its
	# stern (1,-1) lies in the target's port bow arc. Clause 7.E.2b still makes it a bow rake.
	var firer: Array[Vector2i] = [_n(0), HexGrid.stern_of(_n(0), 1)]
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, firer[1]), ShipState.PORT, "setup: stern in arc")
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "bow")


func test_rake_needs_range_five_or_less() -> void:
	var firer: Array[Vector2i] = [_steps(0, 7), _steps(0, 6)]
	assert_eq(geo.rake_type_ships(Vector2i.ZERO, 0, firer), "")


# --- line of sight ---

func test_los_clear() -> void:
	assert_true(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), {}))


func test_los_blocked_by_intermediate() -> void:
	assert_false(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), {Vector2i(2, 0): true}))


func test_los_endpoints_do_not_block() -> void:
	var occ := {Vector2i(0, 0): true, Vector2i(4, 0): true}
	assert_true(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), occ))


func test_los_edge_case_one_side_occupied_is_clear() -> void:
	assert_true(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 1), {Vector2i(1, 0): true}))


func test_los_edge_case_both_sides_occupied_is_blocked() -> void:
	var occ := {Vector2i(1, 0): true, Vector2i(0, 1): true}
	assert_false(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 1), occ))


# --- broadside_hexes ---

func test_broadside_hexes_from_stern_battery() -> void:
	var stern := HexGrid.stern_of(Vector2i.ZERO, 0)
	var hexes := geo.broadside_hexes(stern, 0, ShipState.STARBOARD, 2)
	assert_true(hexes.has(stern + _n(1)))
	assert_false(hexes.has(Vector2i.ZERO))

func test_broadside_hexes_starboard_range_two() -> void:
	var hexes := geo.broadside_hexes(Vector2i.ZERO, 0, ShipState.STARBOARD, 2)
	assert_true(hexes.has(_n(1)))
	assert_true(hexes.has(_n(2)))
	assert_true(hexes.has(_n(1) + _n(2)))
	for h in hexes:
		assert_eq(geo.bearing_side(Vector2i.ZERO, 0, h), ShipState.STARBOARD, "hex %s" % h)
		assert_true(grid.hex_distance(0, 0, h.x, h.y) <= 2)


# --- arc drawn for a broadside (GameController.broadside_arc) ---

func test_arc_hexes_union_of_batteries() -> void:
	var ship := ShipState.new()
	ship.hex_position = Vector2i(0, 0)
	ship.facing = 0
	var arc: Array[Vector2i] = GameControllerScript.broadside_arc(geo, ship, ShipState.STARBOARD)
	var own := ship.occupied_hexes()
	for battery in own:
		for h in geo.broadside_hexes(battery, 0, ShipState.STARBOARD, FireGeometry.MAX_RANGE):
			if not own.has(h):
				assert_true(arc.has(h), "hex %s of the battery at %s" % [h, battery])
	for h in arc:
		assert_false(own.has(h), "never the ship's own hexes")
		assert_true(geo.in_battery_arc(own[0], 0, ShipState.STARBOARD, h) or geo.in_battery_arc(own[1], 0, ShipState.STARBOARD, h),
			"hex %s bears from one of the batteries" % h)
	var stern_only := HexGrid.stern_of(Vector2i.ZERO, 0) + _steps(2, 3)
	assert_true(arc.has(stern_only), "a hex only the stern battery covers is drawn")
	assert_false(geo.broadside_hexes(Vector2i.ZERO, 0, ShipState.STARBOARD).has(stern_only))


func test_battery_arc_is_the_chosen_battery_only() -> void:
	var ship := ShipState.new()
	ship.hex_position = Vector2i(0, 0)
	ship.facing = 0
	var own := ship.occupied_hexes()
	var bow: Array[Vector2i] = GameControllerScript.battery_arc(geo, ship, ShipState.STARBOARD, ["bow"] as Array[String])
	var stern: Array[Vector2i] = GameControllerScript.battery_arc(geo, ship, ShipState.STARBOARD, ["stern"] as Array[String])
	for h in bow:
		assert_true(geo.in_battery_arc(own[0], 0, ShipState.STARBOARD, h), "bow arc hex %s bears from the bow" % h)
		assert_false(own.has(h))
	for h in stern:
		assert_true(geo.in_battery_arc(own[1], 0, ShipState.STARBOARD, h), "stern arc hex %s bears from the stern" % h)
	var stern_only := HexGrid.stern_of(Vector2i.ZERO, 0) + _steps(2, 3)
	assert_true(stern.has(stern_only))
	assert_false(bow.has(stern_only), "the bow battery's arc leaves out a stern-only hex")
	var full: Array[Vector2i] = GameControllerScript.broadside_arc(geo, ship, ShipState.STARBOARD)
	for h in bow + stern:
		assert_true(full.has(h), "full = union")
	assert_eq(full.size(), GameControllerScript.battery_arc(geo, ship, ShipState.STARBOARD,
		["bow", "stern"] as Array[String]).size())


# --- friendly blocking hexes (7.B.10-12, Diagram 18) ---
# Firer A: bow (0,0) facing E, stern (-1,0); its starboard beam runs down the (-1,2) diagonal.

func _firer() -> Array[Vector2i]:
	var hexes: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0)]
	return hexes


func _friend(bow: Vector2i, facing: int) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = [bow, HexGrid.stern_of(bow, facing)]
	return hexes


func _blocking(friends: Array, side: int = ShipState.STARBOARD, battery := Vector2i(0, 0)) -> Dictionary:
	return geo.blocking_hexes(battery, 0, side, _firer(), friends)


func test_friend_at_range_4_makes_no_blocking_hexes() -> void:
	# 7.B.10, Diagram 18 ships B and C: a friend 1-4 hexes away makes none, even with one hex at 5.
	var friend := _friend(Vector2i(-2, 4), 3)
	assert_eq(geo.range_between(_firer(), friend), 4, "setup: range 4")
	assert_true(_blocking([friend]).is_empty())


func test_friend_at_medium_range_blocks_adjacent_hexes_beyond_it() -> void:
	# 7.B.10a: a friend 5-9 hexes away blocks the hexes adjacent to it at least as far from the
	# firer as itself (Diagram 18 ships D, E, F).
	var friend := _friend(Vector2i(-3, 6), 3)
	assert_eq(geo.range_between(_firer(), friend), 6, "setup: range 6")
	var blocking := _blocking([friend])
	assert_true(blocking.has(Vector2i(-3, 7)), "adjacent and farther (range 7)")
	assert_true(blocking.has(Vector2i(-4, 6)), "adjacent at the same range (6)")
	assert_false(blocking.has(Vector2i(-3, 5)), "adjacent but nearer (range 5)")
	assert_false(blocking.has(Vector2i(-3, 8)), "two hexes out is beyond medium-range blocking")


func test_friend_at_long_range_blocks_two_hexes_out() -> void:
	# 7.B.10b: a friend 10-15 hexes away blocks every hex up to two away from it that is at least
	# as far from the firer (Diagram 18 ships G and H).
	var friend := _friend(Vector2i(-6, 12), 3)
	assert_eq(geo.range_between(_firer(), friend), 12, "setup: range 12")
	var blocking := _blocking([friend])
	assert_true(blocking.has(Vector2i(-6, 14)), "two out, range 14")
	assert_true(blocking.has(Vector2i(-3, 12)), "two out from the stern, range 12")
	assert_false(blocking.has(Vector2i(-6, 10)), "two out but nearer (range 10)")
	assert_false(blocking.has(Vector2i(-6, 15)), "three out")


func test_friend_outside_arc_makes_none() -> void:
	# 7.B.11, Diagram 18 ships X: a friend entirely outside this battery's arc makes none.
	var ahead := _friend(Vector2i(7, 0), 0)
	assert_true(_blocking([ahead]).is_empty(), "dead ahead")
	var abeam := _friend(Vector2i(-3, 6), 3)
	assert_true(_blocking([abeam], ShipState.PORT).is_empty(), "in the starboard arc, not the port one")


func test_los_through_blocking_hex_is_blocked() -> void:
	# 7.B.10c: any LOS which passes through a blocking hex is blocked.
	assert_false(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), {}, {Vector2i(2, 0): true}))


func test_los_along_spine_between_occupied_and_blocking_hex_is_blocked() -> void:
	# 7.B.8: a spine blocks when both hexes beside it block, an occupied one and a blocking one alike.
	assert_false(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 1), {Vector2i(1, 0): true},
		{Vector2i(0, 1): true}))
	assert_true(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(1, 1), {}, {Vector2i(0, 1): true}),
		"one blocking hex beside the spine leaves it clear")


func test_target_in_blocking_hex_can_be_hit() -> void:
	# 7.B.10c: "An LOS may enter a blocking hex": the end hexes never block.
	assert_true(geo.has_line_of_sight(Vector2i(0, 0), Vector2i(4, 0), {}, {Vector2i(4, 0): true}))
	var target: Array[Vector2i] = [_n(1) * 2, _n(1) * 3]
	var blocking := {target[0]: true, target[1]: true, Vector2i(0, 0): true}
	assert_false(geo.battery_bears(Vector2i.ZERO, 0, ShipState.STARBOARD, target, {}, blocking),
		"the far target hex lies behind the near one, a blocking hex (Diagram 19, ship 3 on E)")
	var near_only: Array[Vector2i] = [target[0]]
	assert_true(geo.battery_bears(Vector2i.ZERO, 0, ShipState.STARBOARD, near_only, {}, blocking),
		"a target hex that is itself blocking can be fired on")


# --- chase arcs (house rule: chasers dead ahead of the bow hex, astern of the stern hex) ---

func test_chase_arc_ahead_and_astern() -> void:
	var o := Vector2i(0, 0)
	for h in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, -1), Vector2i(1, 1)]:
		assert_eq(geo.chase_arc(o, 0, h), FireGeometry.ARC_AHEAD, "%s ahead (30° is the boundary)" % h)
	for h in [Vector2i(1, -1), Vector2i(0, 1)]:
		assert_eq(geo.chase_arc(o, 0, h), -1, "%s at 60° is neither" % h)
	assert_eq(geo.chase_arc(o, 0, Vector2i(3, -2)), -1, "about 40.9° is outside the chase arc")
	for h in [Vector2i(-1, 0), Vector2i(-2, 1), Vector2i(-1, -1)]:
		assert_eq(geo.chase_arc(o, 0, h), FireGeometry.ARC_ASTERN, "%s astern (150° is the boundary)" % h)
	assert_eq(geo.chase_arc(o, 0, Vector2i(-1, 1)), -1, "120° is neither")
	assert_eq(geo.chase_arc(o, 0, o), -1, "own hex")


func test_chase_arc_turns_with_facing() -> void:
	for f in 6:
		assert_eq(geo.chase_arc(Vector2i.ZERO, f, _n(f)), FireGeometry.ARC_AHEAD, "facing %d ahead" % f)
		assert_eq(geo.chase_arc(Vector2i.ZERO, f, _n((f + 3) % 6)), FireGeometry.ARC_ASTERN,
			"facing %d astern" % f)


func test_in_battery_arc_for_chase_arcs() -> void:
	assert_true(geo.in_battery_arc(Vector2i.ZERO, 0, 2, Vector2i(15, 0)))
	assert_false(geo.in_battery_arc(Vector2i.ZERO, 0, 2, Vector2i(16, 0)), "beyond MAX_RANGE")
	assert_false(geo.in_battery_arc(Vector2i.ZERO, 0, 2, Vector2i(0, 1)), "on the beam")
	assert_eq(geo.bearing_side(Vector2i.ZERO, 0, Vector2i(2, 0)), -1, "bearing_side unchanged")


func test_battery_bears_for_chaser_needs_line_of_sight() -> void:
	var target: Array[Vector2i] = [Vector2i(3, 0), Vector2i(2, 0)]
	assert_false(geo.battery_bears(Vector2i.ZERO, 0, 2, target, {Vector2i(1, 0): "x"}))
	assert_true(geo.battery_bears(Vector2i.ZERO, 0, 2, target, {}))


func test_chase_arc_hexes() -> void:
	var ahead := geo.broadside_hexes(Vector2i.ZERO, 0, 2, 2)
	assert_eq(ahead.size(), 4)
	for h in [Vector2i(1, 0), Vector2i(2, -1), Vector2i(2, 0), Vector2i(1, 1)]:
		assert_has(ahead, h)
	assert_eq(geo.broadside_hexes(Vector2i.ZERO, 0, 3, 1), [Vector2i(-1, 0)] as Array[Vector2i])


func test_chase_constants_agree() -> void:
	assert_eq(GunneryTypes.CHASE_BOW, FireGeometry.ARC_AHEAD)
	assert_eq(GunneryTypes.CHASE_STERN, FireGeometry.ARC_ASTERN)


func test_chase_battery_hex_is_the_chasers_end() -> void:
	var s := ShipState.new()
	s.hex_position = Vector2i(4, 2)
	s.facing = 1
	assert_eq(FireGeometry.chase_battery_hex(s, FireGeometry.ARC_AHEAD), Vector2i(4, 2), "bow chaser at the bow")
	assert_eq(FireGeometry.chase_battery_hex(s, FireGeometry.ARC_ASTERN), s.stern_hex(),
		"stern chaser at the stern")
