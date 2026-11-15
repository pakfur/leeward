extends GutTest
## Tests for the procedural placeholder ships: ProceduralShipSpec (ship data -> shape, which masts
## and sails show) and ProceduralShipBuilder (meshes, state updates).

func _ship(rating: int, ship_class: int) -> Ship:
	return Ship.from_dict({
		"ship_id": "s", "ship_type": "t", "name": "Test", "nationality": "British",
		"rating": rating, "class": ship_class, "maneuverability": "B", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6], "crew_count": [3, 3, 3, 3],
	})


func _built(rating: int = 74, ship_class: int = 2) -> Array:
	var spec := ProceduralShipSpec.for_ship(_ship(rating, ship_class), 1)
	var root := Node3D.new()
	add_child_autofree(root)
	ProceduralShipBuilder.build(spec, root)
	return [spec, root]


# --- Spec: ship data -> shape ---

func test_ship_of_the_line_has_two_gun_decks_and_three_masts() -> void:
	var spec := ProceduralShipSpec.for_ship(_ship(74, 2), 1)
	assert_eq(spec.gun_decks, 2)
	assert_eq(spec.masts, 3)

func test_frigate_has_one_gun_deck_and_three_masts() -> void:
	var spec := ProceduralShipSpec.for_ship(_ship(38, 3), 1)
	assert_eq(spec.gun_decks, 1)
	assert_eq(spec.masts, 3)

func test_first_rate_has_three_gun_decks() -> void:
	assert_eq(ProceduralShipSpec.for_ship(_ship(100, 1), 1).gun_decks, 3)

func test_small_ship_has_two_masts() -> void:
	assert_eq(ProceduralShipSpec.for_ship(_ship(18, 4), 1).masts, 2, "brig/sloop")

func test_frigate_shorter_than_ship_of_the_line() -> void:
	assert_lt(ProceduralShipSpec.for_ship(_ship(38, 3), 1).length, ProceduralShipSpec.for_ship(_ship(74, 2), 1).length)

func test_one_hex_ship_fits_inside_its_hex() -> void:
	# The owner ring's inner radius is 0.68; the hull must not poke far past a 1.0 hex.
	assert_lte(ProceduralShipSpec.for_ship(_ship(74, 2), 1).length, 1.35)

func test_two_hex_ship_is_twice_as_long() -> void:
	assert_almost_eq(ProceduralShipSpec.for_ship(_ship(74, 2), 2).length, 2.0 * ProceduralShipSpec.for_ship(_ship(74, 2), 1).length, 0.001)

func test_ports_per_side_follow_rating() -> void:
	assert_eq(ProceduralShipSpec.for_ship(_ship(74, 2), 1).ports_per_side, 14, "74 guns on 2 decks: capped at 14")
	assert_eq(ProceduralShipSpec.for_ship(_ship(32, 3), 1).ports_per_side, 14)
	assert_eq(ProceduralShipSpec.for_ship(_ship(18, 4), 1).ports_per_side, 9)

func test_missing_ship_data_gives_a_frigate() -> void:
	var spec := ProceduralShipSpec.for_ship(null, 1)
	assert_eq(spec.gun_decks, 1)
	assert_eq(spec.masts, 3)

# --- Spec: rigging level -> mast tiers, sail state -> sails ---

func test_mast_tiers_by_rigging_level() -> void:
	assert_eq(ProceduralShipSpec.mast_tiers(4), 3, "lower masts, topmasts, topgallants")
	assert_eq(ProceduralShipSpec.mast_tiers(3), 2, "topgallants gone")
	assert_eq(ProceduralShipSpec.mast_tiers(2), 2)
	assert_eq(ProceduralShipSpec.mast_tiers(1), 1, "lower masts only")
	assert_eq(ProceduralShipSpec.mast_tiers(0), 0, "dismasted: stumps")

func test_sails_by_sail_state() -> void:
	assert_eq(ProceduralShipSpec.sail_tiers("PS", 4), [1, 2, 3], "plain sail: courses, topsails, topgallants")
	assert_eq(ProceduralShipSpec.sail_tiers("MS", 4), [1, 2], "courses and topsails")
	assert_eq(ProceduralShipSpec.sail_tiers("FS", 4), [2], "fighting sail: topsails")
	assert_eq(ProceduralShipSpec.sail_tiers("NS", 4), [], "furled")

func test_sails_need_their_mast() -> void:
	assert_eq(ProceduralShipSpec.sail_tiers("PS", 3), [1, 2], "no topgallant mast")
	assert_eq(ProceduralShipSpec.sail_tiers("FS", 1), [1], "fighting sail set on the lower mast")
	assert_eq(ProceduralShipSpec.sail_tiers("FS", 0), [], "dismasted")

func test_sail_state_is_case_insensitive() -> void:
	assert_eq(ProceduralShipSpec.sail_tiers("ms", 4), [1, 2])

# --- Builder ---

func test_build_makes_hull_masts_and_sails() -> void:
	var built := _built(74, 2)
	var root: Node3D = built[1]
	assert_not_null(root.get_node_or_null("Hull"))
	assert_not_null(root.get_node_or_null("Ports_2"), "second gun deck")
	assert_null(root.get_node_or_null("Ports_3"))
	assert_not_null(root.get_node_or_null("Mast_2_3"), "mizzen topgallant")
	assert_not_null(root.get_node_or_null("Sail_0_1"), "fore course")
	assert_not_null(root.get_node_or_null("Stump_1"))

func test_every_mesh_has_its_own_material() -> void:
	# ShipView greys out a struck ship by editing each child's material; shared materials would
	# grey every ship at once.
	var root_a: Node3D = _built()[1]
	var root_b: Node3D = _built()[1]
	var seen := {}
	for root in [root_a, root_b]:
		for child in root.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null:
				continue
			assert_not_null(mesh.material_override, "%s has a material" % mesh.name)
			assert_false(seen.has(mesh.material_override), "%s shares a material" % mesh.name)
			seen[mesh.material_override] = true

func test_apply_state_shows_sails_for_sail_state() -> void:
	var built := _built()
	var spec: ProceduralShipSpec = built[0]
	var root: Node3D = built[1]
	ProceduralShipBuilder.apply_state(root, spec, "FS", 4)
	assert_false(root.get_node("Sail_1_1").visible, "main course furled at fighting sail")
	assert_true(root.get_node("Sail_1_2").visible, "main topsail set")
	assert_false(root.get_node("Sail_1_3").visible)
	ProceduralShipBuilder.apply_state(root, spec, "PS", 4)
	assert_true(root.get_node("Sail_1_1").visible)
	assert_true(root.get_node("Sail_1_3").visible)

func test_apply_state_dismasted_shows_stumps_only() -> void:
	var built := _built()
	var root: Node3D = built[1]
	ProceduralShipBuilder.apply_state(root, built[0], "MS", 0)
	for m in range(3):
		assert_true(root.get_node("Stump_%d" % m).visible)
		for tier in [1, 2, 3]:
			assert_false(root.get_node("Mast_%d_%d" % [m, tier]).visible)
			assert_false(root.get_node("Sail_%d_%d" % [m, tier]).visible)

func test_apply_state_loses_topgallants_first() -> void:
	var built := _built()
	var root: Node3D = built[1]
	ProceduralShipBuilder.apply_state(root, built[0], "PS", 3)
	assert_true(root.get_node("Mast_0_2").visible)
	assert_false(root.get_node("Mast_0_3").visible)
	assert_false(root.get_node("Yard_0_3").visible)
	assert_false(root.get_node("Stump_0").visible)

func test_masthead_above_the_hull() -> void:
	var spec := ProceduralShipSpec.for_ship(_ship(38, 3), 1)
	assert_gt(spec.masthead_y(), spec.hull_height + 0.5)


func test_standing_masthead_drops_with_rigging() -> void:
	var spec := ProceduralShipSpec.for_ship(_ship(38, 3), 1)
	assert_almost_eq(spec.standing_masthead_y(4), spec.masthead_y(), 0.001)
	assert_lt(spec.standing_masthead_y(3), spec.standing_masthead_y(4), "topgallants gone")
	assert_lt(spec.standing_masthead_y(1), spec.standing_masthead_y(2))
	assert_almost_eq(spec.standing_masthead_y(0), spec.hull_height + spec.stump_height(1), 0.001)
