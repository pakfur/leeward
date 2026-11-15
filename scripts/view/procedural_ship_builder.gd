class_name ProceduralShipBuilder
extends RefCounted
## ProceduralShipBuilder - Builds a placeholder sailing-ship model from a ProceduralShipSpec and
## shows the masts and sails that match the ship's state (presentation only, no game state).
##
## Every mesh is a direct child of the parent with its own material_override: ShipView greys a
## struck ship by editing each child's material, so materials must never be shared between ships.
## Node names: Hull, Bow, Deck, Quarterdeck, Bowsprit, Band_<deck>, Ports_<deck>,
## Mast_<mast>_<tier>, Yard_<mast>_<tier>, Sail_<mast>_<tier>, Stump_<mast> (mast 0 = fore,
## deck 1 = lowest, tier 1 = course).

const HULL_COLOR := Color(0.09, 0.08, 0.07)
const BAND_COLOR := Color(0.80, 0.62, 0.26)
const PORT_COLOR := Color(0.04, 0.03, 0.03)
const DECK_COLOR := Color(0.62, 0.50, 0.34)
const MAST_COLOR := Color(0.55, 0.38, 0.20)
const YARD_COLOR := Color(0.32, 0.22, 0.13)
const SAIL_COLOR := Color(0.94, 0.91, 0.83)
## Course yard width as a multiple of the beam; each tier above is narrower.
const YARD_SPAN := 2.3
const TIER_NARROWING := 0.78
## Sail depth (the belly of the canvas) as a fraction of hull length.
const SAIL_BILLOW := 0.06


## Adds the full model (every mast and sail) to `parent`. Call apply_state to show the right ones.
static func build(spec: ProceduralShipSpec, parent: Node3D) -> void:
	var l := spec.length
	var hull_depth := spec.hull_height + spec.draft
	var hull_y := (spec.hull_height - spec.draft) / 2.0

	_box(parent, "Hull", Vector3(spec.beam, hull_depth, l * 0.8), Vector3(0, hull_y, l * 0.06), HULL_COLOR)
	var bow := _mesh(parent, "Bow", _prism(Vector3(spec.beam, l * 0.16, hull_depth)), HULL_COLOR)
	bow.position = Vector3(0, hull_y, -l * 0.42)
	bow.rotation_degrees = Vector3(-90, 0, 0)  # wedge apex points forward (-Z)
	_box(parent, "Deck", Vector3(spec.beam * 0.92, 0.01, l * 0.78), Vector3(0, spec.hull_height + 0.005, l * 0.05), DECK_COLOR)
	_box(parent, "Quarterdeck", Vector3(spec.beam * 0.96, l * 0.04, l * 0.22), Vector3(0, spec.hull_height + l * 0.02, l * 0.35), HULL_COLOR)

	var bowsprit := _cylinder(parent, "Bowsprit", l * 0.32, l * 0.012, MAST_COLOR)
	bowsprit.position = Vector3(0, spec.hull_height + l * 0.04, -l * 0.55)
	bowsprit.rotation_degrees = Vector3(-70, 0, 0)  # forward and up

	_build_gun_decks(spec, parent)
	for m in range(spec.masts):
		_build_mast(spec, parent, m)


## Shows the masts still standing at `rigging_level` and the sails set at `sail_state`.
static func apply_state(parent: Node3D, spec: ProceduralShipSpec, sail_state: String, rigging_level: int) -> void:
	var standing := ProceduralShipSpec.mast_tiers(rigging_level)
	var sails := ProceduralShipSpec.sail_tiers(sail_state, rigging_level)
	for m in range(spec.masts):
		_set_visible(parent, "Stump_%d" % m, standing == 0)
		for tier in ProceduralShipSpec.TIERS:
			var up: bool = tier <= standing
			_set_visible(parent, "Mast_%d_%d" % [m, tier], up)
			_set_visible(parent, "Yard_%d_%d" % [m, tier], up)
			_set_visible(parent, "Sail_%d_%d" % [m, tier], tier in sails)


static func _build_gun_decks(spec: ProceduralShipSpec, parent: Node3D) -> void:
	var l := spec.length
	var band_h := spec.hull_height / spec.gun_decks * 0.38
	var run := l * 0.62  # length of hull side carrying gunports
	var port_size := Vector3(0.012, band_h * 0.62, run / spec.ports_per_side * 0.45)
	for deck in range(1, spec.gun_decks + 1):
		var y := spec.hull_height * (deck - 0.45) / spec.gun_decks
		_box(parent, "Band_%d" % deck, Vector3(spec.beam + 0.012, band_h, l * 0.72), Vector3(0, y, l * 0.05), BAND_COLOR)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var port := BoxMesh.new()
		port.size = port_size
		for side in [-1.0, 1.0]:
			for i in range(spec.ports_per_side):
				var z := -run / 2.0 + l * 0.05 + (i + 0.5) * run / spec.ports_per_side
				var x: float = side * (spec.beam / 2.0 + 0.008)
				st.append_from(port, 0, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
		_mesh(parent, "Ports_%d" % deck, st.commit(), PORT_COLOR)


static func _build_mast(spec: ProceduralShipSpec, parent: Node3D, m: int) -> void:
	var z: float = spec.mast_z[m]
	var radius := spec.length * 0.014
	var yard_width := spec.beam * YARD_SPAN
	for tier in ProceduralShipSpec.TIERS:
		var height: float = spec.mast_tier_heights[m][tier - 1]
		var base := spec.tier_base_y(m, tier)
		var mast := _cylinder(parent, "Mast_%d_%d" % [m, tier], height, radius, MAST_COLOR)
		mast.position = Vector3(0, base + height / 2.0, z)
		radius *= 0.8

		var yard_y := base + height * 0.88
		var yard := _cylinder(parent, "Yard_%d_%d" % [m, tier], yard_width, spec.length * 0.007, YARD_COLOR)
		yard.position = Vector3(0, yard_y, z - 0.01)
		yard.rotation_degrees = Vector3(0, 0, 90)  # across the ship

		var sail_h := height * 0.78
		var billow := spec.length * SAIL_BILLOW  # depth, so sails still read from above
		_box(parent, "Sail_%d_%d" % [m, tier], Vector3(yard_width * 0.92, sail_h, billow),
			Vector3(0, yard_y - sail_h / 2.0, z - billow / 2.0 - 0.01), SAIL_COLOR)
		yard_width *= TIER_NARROWING

	var stump_h: float = spec.stump_height(m)
	var stump := _cylinder(parent, "Stump_%d" % m, stump_h, spec.length * 0.016, MAST_COLOR)
	stump.position = Vector3(0, spec.hull_height + stump_h / 2.0, z)
	stump.visible = false


static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var node := _mesh(parent, node_name, box, color)
	node.position = pos
	return node


static func _cylinder(parent: Node3D, node_name: String, height: float, radius: float, color: Color) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.height = height
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.radial_segments = 8
	cyl.rings = 1
	return _mesh(parent, node_name, cyl, color)


static func _prism(size: Vector3) -> PrismMesh:
	var prism := PrismMesh.new()
	prism.size = size
	return prism


static func _mesh(parent: Node3D, node_name: String, mesh: Mesh, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	var material := StandardMaterial3D.new()  # one per mesh: see the class comment
	material.albedo_color = color
	node.material_override = material
	parent.add_child(node)
	return node


static func _set_visible(parent: Node3D, node_name: String, shown: bool) -> void:
	var node := parent.get_node_or_null(node_name) as Node3D
	if node:
		node.visible = shown
