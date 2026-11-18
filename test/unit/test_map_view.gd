extends GutTest
## The view of the board (map and scenario spec §15): the rectangle HexMap tracks, the terrain layer
## of HexOverlay, ship views for arriving ships, no explosion off the map, and the new badges.

const HexMapScript = preload("res://scripts/core/hex_map.gd")
const HexOverlayScript = preload("res://scripts/view/hex_overlay.gd")
const GameControllerScript = preload("res://scripts/core/game_controller.gd")


func _ship(id: String) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.new()
	s.ship.ship_id = id
	s.sail_state = "MS"
	s.rigging_current_hp = [4, 4, 4, 4]
	return s


func _children_named(node: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	for c in node.get_children():
		if str(c.name).begins_with(prefix):
			out.append(c)
	return out


func test_hex_map_tracks_the_rectangle() -> void:
	var hex_map: Node3D = HexMapScript.new()
	autofree(hex_map)
	hex_map.hex_grid = HexGrid.new(1.0)
	hex_map.grid_width = 10
	hex_map.grid_height = 10
	hex_map._initialize_hex_tracking()
	var expected := TerrainMap.rect_hexes(10, 10)
	assert_eq(hex_map.hex_meshes.size(), expected.size())
	for h in expected:
		assert_true(hex_map.hex_meshes.has(h), str(h))
	assert_true(hex_map.hex_meshes.has(Vector2i(2, 4)))
	assert_false(hex_map.hex_meshes.has(Vector2i(3, 4)))


func test_show_terrain_tints_labels_and_edges() -> void:
	var overlay: Node3D = HexOverlayScript.new()
	add_child_autofree(overlay)
	var terrain := TerrainMap.from_scenario({
		"map_bounds": {"width": 10, "height": 10},
		"terrain": {
			"edges": {"W": "escape"},
			"land": [[0, 0], [1, 0]],
			"shallow": [{"name": "A", "base": 15, "hexes": [[2, 0], [3, 0], [2, 1]]}],
		},
	})
	overlay.show_terrain(terrain, HexGrid.new(1.0))
	var node: Node3D = overlay.terrain_node
	assert_eq(_children_named(node, "Land_").size(), 2)
	assert_eq(_children_named(node, "Shallow_").size(), 3)
	var label := node.get_node_or_null("DepthLabel_A") as Label3D
	assert_not_null(label)
	if label:
		assert_eq(label.text, "A 16–21 ft")
	assert_gt(_children_named(node, "Edge_W_").size(), 0)
	assert_eq(_children_named(node, "Edge_N_").size(), 0, "open edges are not marked")
	overlay.clear_terrain()
	assert_eq(overlay.terrain_node.get_child_count(), 0)
	await wait_process_frames(1)  # let the queued frees run


func test_views_to_spawn() -> void:
	var a := _ship("a")
	var b := _ship("b")
	var c := _ship("c")
	c.awaiting_arrival = true
	var d := _ship("d")
	d.removed_from_map = true
	var ships: Array[ShipState] = [d, c, b, a]
	assert_eq(GameControllerScript.views_to_spawn(["a"], ships), ["b"] as Array[String])


func test_no_explosion_off_the_map() -> void:
	var ship := _ship("x")
	ship.status = ShipState.Status.DESTROYED
	assert_true(ShipView.explodes_on_sync(true, false, ship), "destroyed on the map: explodes")
	ship.removed_from_map = true
	assert_false(ShipView.explodes_on_sync(true, false, ship), "lost off the map: no explosion")
	ship.removed_from_map = false
	assert_false(ShipView.explodes_on_sync(false, false, ship), "never seen afloat")
	assert_false(ShipView.explodes_on_sync(true, true, ship), "already a wreck")


func test_badges() -> void:
	var aground := _ship("a")
	aground.aground = true
	assert_eq(PlanningSailUi.status_badge(aground), "AGROUND")
	assert_false(PlanningSailUi.can_plot_movement(aground))
	assert_eq(PlanningSailUi.movement_block_reason(aground), "Ship is aground and cannot move (13.G.3).")

	var escaped := _ship("e")
	escaped.status = ShipState.Status.ESCAPED
	assert_eq(PlanningSailUi.status_badge(escaped), "ESCAPED")
	assert_eq(PlanningSailUi.movement_block_reason(escaped), "Ship has escaped.")

	var declared := _ship("d")
	declared.escape_declared = true
	assert_eq(PlanningSailUi.escape_badge(declared), "ESCAPING")
	assert_string_contains(PlanningSailUi.card_badge(declared), "ESCAPING")
	assert_eq(PlanningSailUi.escape_badge(_ship("n")), "")
	escaped.escape_declared = true
	assert_eq(PlanningSailUi.escape_badge(escaped), "", "an escaped ship is no longer escaping")


func test_badge_order() -> void:
	var ship := _ship("p")
	ship.status = ShipState.Status.CAPTURED
	ship.aground = true
	assert_eq(PlanningSailUi.status_badge(ship), "PRIZE", "PRIZE before AGROUND")
	ship.status = ShipState.Status.ACTIVE
	ship.rigging_current_hp = [0, 0, 0, 0]
	assert_eq(PlanningSailUi.status_badge(ship), "AGROUND", "AGROUND before DISMASTED")
