extends GutTest
## The chosen fire target is outlined, not filled: the target ship, its owner ring and pennant stay
## visible inside the highlight, and the outline stays distinct from the broadside arc fills.

const HexOverlayScript = preload("res://scripts/view/hex_overlay.gd")

var overlay: Node3D


func before_each() -> void:
	overlay = HexOverlayScript.new()
	add_child_autofree(overlay)
	overlay.arc_grid = HexGrid.new()


func test_target_highlight_is_a_ring_not_a_filled_hex() -> void:
	overlay.show_target_highlights([Vector2i(2, 1)] as Array[Vector2i])
	var children: Array = overlay.targets_node.get_children()
	assert_eq(children.size(), 1)
	var ring: MeshInstance3D = children[0]
	assert_eq(ring.name, "TargetRing")
	var verts: PackedVector3Array = ring.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var nearest := INF
	for v in verts:
		nearest = minf(nearest, Vector2(v.x, v.z).length())
	# Nothing drawn over the middle of the hex, where the ship and its owner ring sit.
	assert_gt(nearest, 0.75, "the ring leaves the hex centre open (nearest vertex %.2f)" % nearest)


func test_target_ring_draws_beneath_the_owner_ring() -> void:
	overlay.show_target_highlights([Vector2i(0, 0)] as Array[Vector2i])
	var ring: MeshInstance3D = overlay.targets_node.get_child(0)
	var mat: StandardMaterial3D = ring.material_override
	assert_lt(mat.render_priority, 1, "owner rings (priority 1) draw over the target ring")


func test_target_colour_is_distinct_from_both_broadsides() -> void:
	var target: Color = HexOverlayScript.COLOR_TARGET
	for side in [ShipState.PORT, ShipState.STARBOARD]:
		var arc: Color = BroadsideColors.color(side)
		var diff := absf(target.r - arc.r) + absf(target.g - arc.g) + absf(target.b - arc.b)
		assert_gt(diff, 0.35, "target vs side %d" % side)
	assert_eq(target.a, 1.0, "an opaque outline, unlike the translucent arc fills")
