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
	assert_almost_eq(view.position.x, 0.0, 0.5, "x at origin hex (allowing wave bob)")
	assert_almost_eq(view.position.z, 0.0, 0.5, "z at origin hex (allowing wave bob)")
