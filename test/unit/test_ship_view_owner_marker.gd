extends GutTest
## Tests for ShipView's owner marker (ring + pennant in the owner's colour) and that a ship
## at hex (0,0) is positioned there (the origin used to be treated as "unset").

var hex_grid: HexGrid


func before_each() -> void:
	hex_grid = HexGrid.new()


func _make_state(ship_id: String, player_id: int, hex: Vector2i) -> ShipState:
	var ship_state = ShipState.new()
	ship_state.ship = Ship.from_dict({
		"ship_id": ship_id,
		"player_id": player_id,
		"ship_name": ship_id,
		"ship_type": "frigate_38",
		"name": "Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "C",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3],
		"marine_count": 2,
	})
	ship_state.hex_position = hex
	ship_state.facing = 0
	ship_state.sail_state = "MS"
	ship_state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	ship_state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	return ship_state


func _make_view(ship_state: ShipState) -> ShipView:
	var view := ShipView.new()
	add_child_autofree(view)
	view.initialize(ship_state, hex_grid)
	return view


func _ring_color(view: ShipView) -> Color:
	var ring := view.get_node("OwnerRing") as MeshInstance3D
	return (ring.material_override as StandardMaterial3D).albedo_color


func test_player_ship_has_green_ring_and_pennant() -> void:
	var view := _make_view(_make_state("p", 0, Vector2i(2, 2)))
	assert_not_null(view.get_node_or_null("OwnerRing"), "ring exists")
	var c := _ring_color(view)
	assert_almost_eq(c.g, ShipView.PLAYER_COLOR.g, 0.01)
	assert_almost_eq(c.r, ShipView.PLAYER_COLOR.r, 0.01)
	var pennant := view.model_node.get_node("OwnerPennant") as MeshInstance3D
	assert_eq((pennant.material_override as StandardMaterial3D).albedo_color, ShipView.PLAYER_COLOR)
	assert_true(pennant.visible)


func test_enemy_ship_has_red_ring() -> void:
	var view := _make_view(_make_state("e", 1, Vector2i(2, 2)))
	var c := _ring_color(view)
	assert_almost_eq(c.r, ShipView.ENEMY_COLOR.r, 0.01)
	assert_almost_eq(c.g, ShipView.ENEMY_COLOR.g, 0.01)


func test_struck_ship_keeps_owner_ring_and_hides_pennant() -> void:
	var state := _make_state("e", 1, Vector2i(2, 2))
	var view := _make_view(state)
	state.status = ShipState.Status.STRUCK
	view.sync_to_state(state, hex_grid)
	var c := _ring_color(view)
	assert_almost_eq(c.r, ShipView.ENEMY_COLOR.r, 0.01, "ring still shows whose ship it was")
	assert_almost_eq(c.g, ShipView.ENEMY_COLOR.g, 0.01)
	assert_false(view.model_node.get_node("OwnerPennant").visible, "colours struck: pennant hidden")
	assert_not_null(view.model_node.get_node_or_null("StruckFlag"), "white flag shown")


func test_ship_moved_to_origin_hex_is_positioned_there() -> void:
	var state := _make_state("p", 0, Vector2i(3, 1))
	var view := _make_view(state)
	state.hex_position = Vector2i(0, 0)
	view.sync_to_state(state, hex_grid)
	var expected := hex_grid.ship_center_world(Vector2i(0, 0), 0)
	assert_almost_eq(view.position.x, expected.x, 0.5, "x by the origin bow hex (allowing wave bob)")
	assert_almost_eq(view.position.z, expected.z, 0.5, "z by the origin bow hex (allowing wave bob)")


func test_ship_view_sits_between_bow_and_stern() -> void:
	for facing in range(6):
		var state := _make_state("p", 0, Vector2i(2, 1))
		state.facing = facing
		var view := _make_view(state)
		var expected := hex_grid.ship_center_world(Vector2i(2, 1), facing)
		assert_almost_eq(view.base_position.x, expected.x, 0.001, "facing %d: x midway" % facing)
		assert_almost_eq(view.base_position.z, expected.z, 0.001, "facing %d: z midway" % facing)
		assert_almost_eq(view.position.x, expected.x, 0.5, "facing %d: shown midway (wave bob)" % facing)
		assert_almost_eq(view.position.z, expected.z, 0.5, "facing %d: shown midway (wave bob)" % facing)


func test_two_hex_ship_model_and_click_box_span_both_hexes() -> void:
	var view := _make_view(_make_state("p", 0, Vector2i(2, 2)))
	var hex_spacing := HexGrid.SQRT3  # bow centre to stern centre
	var box := ((view.model_node.get_node("ClickBody") as StaticBody3D).get_child(0) as CollisionShape3D).shape as BoxShape3D
	assert_gt(box.size.z, hex_spacing, "click box reaches into both hexes")
	assert_lt(box.size.z, 2.0 * hex_spacing, "but not past the footprint")
	var keel := (view.model_node.get_node("ClickBody") as Node3D).global_transform.basis.z.normalized()
	assert_gt(absf(keel.x), 0.9, "an east-facing ship's box runs east-west, along the keel")


func test_owner_ring_turns_with_the_ship() -> void:
	var state := _make_state("p", 0, Vector2i(2, 2))
	var view := _make_view(state)
	state.facing = 2
	view.sync_to_state(state, hex_grid)
	var ring := view.get_node("OwnerRing") as MeshInstance3D
	assert_almost_eq(ring.rotation_degrees.y, view.model_node.rotation_degrees.y, 0.01, "ring follows the keel")
	assert_gt(ring.scale.z, ring.scale.x, "stretched along the keel")
