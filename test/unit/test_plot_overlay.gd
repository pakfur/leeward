extends GutTest
## The plotting overlay draws only what the server would accept: when the plot can go no further
## (head to wind, or nothing offered), no offered or blocked hexes are drawn around the ship.

const GameControllerScript = preload("res://scripts/core/game_controller.gd")

var grid := HexGrid.new()


func _forward_only(hex: Vector2i, facing: int) -> MovementTypes.ValidNextHexes:
	var vnh := MovementTypes.ValidNextHexes.new()
	var to := grid.get_neighbor(hex.x, hex.y, facing)
	var meta := MovementTypes.MoveMetadata.new(MovementTypes.MoveType.FORWARD, facing, 1)
	vnh.forward.append(MovementTypes.ValidMove.new(to, MovementTypes.MoveType.FORWARD, meta))
	return vnh


func test_nothing_offered_draws_no_blocked_hexes() -> void:
	var vnh := MovementTypes.ValidNextHexes.new()
	assert_eq(GameControllerScript.blocked_hexes_for(vnh, Vector2i(0, 0), 0, grid).size(), 0)


func test_null_offer_draws_nothing() -> void:
	assert_eq(GameControllerScript.blocked_hexes_for(null, Vector2i(0, 0), 0, grid).size(), 0)


func test_forward_only_marks_both_pivots_blocked() -> void:
	var blocked := GameControllerScript.blocked_hexes_for(_forward_only(Vector2i(0, 0), 0), Vector2i(0, 0), 0, grid)
	assert_eq(blocked.size(), 2)
	assert_has(blocked, grid.get_neighbor(0, 0, 5))
	assert_has(blocked, grid.get_neighbor(0, 0, 1))


# The server side (a pivot head to wind leaves no further move to offer) is pinned by
# test_movement_validator.gd::test_pivot_into_luffing_ends_movement; together with
# test_nothing_offered_draws_no_blocked_hexes, the picture matches what a click would do.


func _ship(id: String, bow: Vector2i, facing: int) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": id, "ship_name": id.capitalize()})
	s.hex_position = bow
	s.facing = facing
	return s


# --- picking: a click on either hex of a ship picks it ---

func test_ship_at_hex_matches_stern() -> void:
	var ships: Array = [_ship("a", Vector2i(2, 2), 1), _ship("b", Vector2i(5, 0), 0)]
	assert_eq(GameControllerScript.ship_at_hex(HexGrid.stern_of(Vector2i(2, 2), 1), ships), "a")
	assert_eq(GameControllerScript.ship_at_hex(HexGrid.stern_of(Vector2i(5, 0), 0), ships), "b")


func test_ship_at_hex_matches_bow_and_misses_open_water() -> void:
	var ships: Array = [_ship("a", Vector2i(2, 2), 1)]
	assert_eq(GameControllerScript.ship_at_hex(Vector2i(2, 2), ships), "a")
	assert_eq(GameControllerScript.ship_at_hex(Vector2i(3, 2), ships), "")
	assert_eq(GameControllerScript.ship_at_hex(Vector2i(2, 2), []), "")


# --- collision warnings: keyed on the click target, judged on the hex actually entered ---

func _offer(bow: Vector2i, facing: int) -> MovementTypes.ValidNextHexes:
	var T := MovementTypes.MoveType
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


func test_turn_warns_when_the_stern_swings_into_a_ship() -> void:
	# Plotting ship: bow (0,0) facing E. A starboard turn swings the stern into (0,-1), where the
	# other ship's stern lies (bow (1,-1) facing E); the port turn's click target (1,-1) holds the
	# other ship's bow, but that turn's stern swings into open water at (-1,1).
	var me := _ship("me", Vector2i(0, 0), 0)
	var other := _ship("other", Vector2i(1, -1), 0)
	var vnh := _offer(Vector2i(0, 0), 0)
	var found := GameControllerScript.offered_collisions(vnh, [me, other], "me")
	var swung := HexGrid.stern_of(Vector2i(0, 0), 1)
	assert_eq(swung, Vector2i(0, -1))
	assert_eq(found["warnings"], {vnh.starboard.hex: "Stern would swing into Other"},
		"the risky choice warns on hover, naming the swing")
	assert_eq(found["marks"], [vnh.starboard.hex, swung] as Array[Vector2i],
		"both the click target and the hex the stern swings into are marked")


func test_ahead_move_warns_on_the_new_bow_hex_including_a_stern() -> void:
	var me := _ship("me", Vector2i(0, 0), 0)
	var other := _ship("other", Vector2i(1, 1), 5)  # bow (1,1), stern (0,2): not ahead of me
	var blocker := _ship("blocker", Vector2i(2, 0), 0)  # stern (1,0): right ahead of me
	var vnh := _offer(Vector2i(0, 0), 0)
	var found := GameControllerScript.offered_collisions(vnh, [me, other, blocker], "me")
	assert_eq(found["warnings"], {Vector2i(1, 0): "Collision risk: Blocker is here"})
	assert_eq(found["marks"], [Vector2i(1, 0)] as Array[Vector2i], "one mark: the hex entered is the click target")


func test_plotted_path_warning_names_the_swing() -> void:
	var me := _ship("me", Vector2i(0, 0), 0)
	var other := _ship("other", Vector2i(2, -1), 0)  # stern (1,-1)
	var path: Array = [
		MovementTypes.PlotStep.new(Vector2i(1, 0), 0),  # ahead into (1,0): clear
		MovementTypes.PlotStep.new(Vector2i(1, 0), 1),  # starboard turn: stern swings into (1,-1)
	]
	assert_eq(GameControllerScript.path_collision_text(path, Vector2i(0, 0), 0, [me, other], "me"),
		"Stern would swing into Other")
	assert_eq(GameControllerScript.path_collision_text(path.slice(0, 1), Vector2i(0, 0), 0, [me, other], "me"), "")


func test_plotted_ahead_step_keeps_the_collision_wording() -> void:
	var me := _ship("me", Vector2i(0, 0), 0)
	var other := _ship("other", Vector2i(2, 0), 0)  # stern (1,0)
	var path: Array = [MovementTypes.PlotStep.new(Vector2i(1, 0), 0)]
	assert_eq(GameControllerScript.path_collision_text(path, Vector2i(0, 0), 0, [me, other], "me"),
		"Collision risk: Other is here")


func test_plotted_turn_enters_its_swung_stern_hex() -> void:
	var path: Array = [
		MovementTypes.PlotStep.new(Vector2i(1, 0), 0),  # ahead: enters (1,0)
		MovementTypes.PlotStep.new(Vector2i(1, 0), 1),  # starboard turn: stern swings into (1,-1)
	]
	assert_eq(GameControllerScript.path_entered_hexes(path, Vector2i(0, 0), 0),
		[Vector2i(1, 0), HexGrid.stern_of(Vector2i(1, 0), 1)] as Array[Vector2i])


func test_overlay_paints_the_swung_into_hex_but_does_not_offer_it() -> void:
	var overlay: Node3D = preload("res://scripts/view/hex_overlay.gd").new()
	add_child_autofree(overlay)
	var vnh := _offer(Vector2i(0, 0), 0)
	var swung := Vector2i(0, -1)
	overlay.show_valid_hexes(vnh.get_all_valid_moves(), grid, [vnh.starboard.hex, swung])
	assert_eq(overlay.valid_hexes_node.get_child_count(), 4, "three offered hexes and the swung-into hex")
	var collision_meshes := 0
	for child in overlay.valid_hexes_node.get_children():
		if (child as MeshInstance3D).material_override == overlay._collision_material:
			collision_meshes += 1
	assert_eq(collision_meshes, 2, "the risky click target and the swung-into hex")
	var swung_world := grid.axial_to_world(swung.x, swung.y)
	assert_eq(overlay.get_valid_hex_at_world_pos(swung_world, grid), Vector2i(-99, -99), "not clickable")


# --- hover candidates and fire-target outlines ------------------------------------

func test_hover_candidates_hold_the_move_metadata() -> void:
	# A turn's click target is the neighbour the bow turns towards; the hover must show the ship on
	# its resulting bow hex (unchanged by a turn) and facing, which only the metadata carries.
	var gc: Node = GameControllerScript.new()
	autofree(gc)
	var vnh := _offer(Vector2i(0, 0), 0)
	gc._rebuild_hover_candidates(vnh)
	assert_eq(gc._hover_candidates.size(), 3)
	var meta = gc._hover_candidates[vnh.starboard.hex]
	assert_true(meta is MovementTypes.MoveMetadata)
	assert_same(meta, vnh.starboard.metadata)
	assert_eq(meta.resulting_hex, Vector2i(0, 0), "a turn keeps the bow hex")
	assert_eq(meta.resulting_facing, 1)
	assert_eq(gc._hover_candidates[vnh.forward[0].hex].resulting_hex, vnh.forward[0].hex)
	gc._rebuild_hover_candidates(null)
	assert_eq(gc._hover_candidates.size(), 0)


func test_fire_target_outline_covers_bow_and_stern() -> void:
	var old_ships: Dictionary = GameState.ships
	GameState.ships = {}
	GameState.ships["a"] = _ship("a", Vector2i(2, 2), 1)
	var hexes := GameControllerScript.fire_target_hexes(["a", "missing"])
	GameState.ships = old_ships
	assert_eq(hexes, [Vector2i(2, 2), HexGrid.stern_of(Vector2i(2, 2), 1)] as Array[Vector2i])
	var overlay: Node3D = preload("res://scripts/view/hex_overlay.gd").new()
	add_child_autofree(overlay)
	overlay.arc_grid = grid
	overlay.show_target_highlights(hexes)
	assert_eq(overlay.targets_node.get_child_count(), 2, "one ring on each of the target's hexes")
	var ring_hexes: Array[Vector2i] = []
	for ring in overlay.targets_node.get_children():
		ring_hexes.append(grid.world_to_axial((ring as Node3D).position))
	assert_eq(ring_hexes, hexes)
