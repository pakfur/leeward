extends GutTest
## Tests for FireText (the fire step's words, moved from the retired fire declaration panel) and the
## fire overlay's colours and arcs.

const GameControllerScript = preload("res://scripts/core/game_controller.gd")


func _preview(range_hexes: int, mgn: int, rake: String = "", initial: bool = false,
		high_only: bool = false) -> GunneryTypes.ShotPreview:
	var p := GunneryTypes.ShotPreview.new()
	p.can_fire = true
	p.range_hexes = range_hexes
	p.mgn = mgn
	p.rake = rake
	p.initial_broadside = initial
	p.high_only = high_only
	return p


func test_breakdown_text_in_plain_words() -> void:
	var p := _preview(2, 22)
	p.bgn = 18
	p.modifiers = [{"name": "initial_broadside", "value": 4}]
	assert_eq(FireText.breakdown_text(p),
		"Base 18, initial broadside +4 = 22. A d6 is added when you fire; higher is better.")
	var plain := _preview(9, 5)
	plain.bgn = 5
	assert_eq(FireText.breakdown_text(plain), "Base 5. A d6 is added when you fire; higher is better.")


func test_fire_button_text_always_says_what_it_does() -> void:
	assert_eq(FireText.fire_button_text(0), "Hold all fire")
	assert_eq(FireText.fire_button_text(1), "Fire 1 broadside")
	assert_eq(FireText.fire_button_text(2), "Fire 2 broadsides")
	assert_eq(FireText.fire_button_text(0, 2), "Fire 2 half broadsides")
	assert_eq(FireText.fire_button_text(1, 1), "Fire 1 broadside and 1 half broadside")


func test_fire_button_counts_a_split_side_as_two_half_broadsides() -> void:
	var sides := {ShipState.STARBOARD: {"bow": "t1", "stern": "t2"}, ShipState.PORT: {"bow": "", "stern": ""}}
	var orders := FireOrdersModel.orders_for_sides("own", sides, {"t1": 3, "t2": 4})
	assert_eq(orders.size(), 2, "setup: one order per battery")
	assert_eq(FireText.fire_button_text_for(orders), "Fire 2 half broadsides")
	sides[ShipState.PORT] = {"bow": "t1", "stern": "t1"}
	orders = FireOrdersModel.orders_for_sides("own", sides, {"t1": 3, "t2": 4})
	assert_eq(FireText.fire_button_text_for(orders), "Fire 1 broadside and 2 half broadsides")
	# The orders sent (FireOrdersModel.order_dicts) are an untyped Array.
	var untyped: Array = []
	untyped.append_array(orders)
	assert_eq(FireText.fire_button_text_for(untyped), "Fire 1 broadside and 2 half broadsides")


func test_locked_toggles_explain_why() -> void:
	assert_eq(FireText.aim_note(true), "Range 10+: must fire high")
	assert_eq(FireText.aim_note(false), "")
	assert_eq(FireText.dismantling_note(7, true), "")
	assert_eq(FireText.dismantling_note(8, false), "Dismantling shot reaches 7 hexes")
	assert_string_contains(FireText.dismantling_note(8, true), "roundshot")


func test_aim_note_shows_the_gunfire_limit() -> void:
	assert_eq(FireText.aim_note(false, ["crew"], "E"), "Low aim holds only on a d6 of 1–3 (14.E: crew CQ E)")
	assert_true(FireText.aim_note(false, ["crew", "heel"], "F").ends_with(
			"(14.E: crew CQ F, firing to windward)"))
	assert_eq(FireText.aim_note(false, [], "E"), "")
	assert_eq(FireText.aim_note(true, ["crew"], "E"), FireText.aim_note(true))


func test_broadside_colors_one_opaque_colour_per_side() -> void:
	assert_ne(BroadsideColors.color(ShipState.PORT), BroadsideColors.color(ShipState.STARBOARD))
	assert_eq(BroadsideColors.color(ShipState.PORT).a, 1.0)
	var fill := BroadsideColors.fill(ShipState.PORT)
	var solid := BroadsideColors.color(ShipState.PORT)
	assert_eq(Color(fill.r, fill.g, fill.b), Color(solid.r, solid.g, solid.b), "fill is the same hue")


func test_arc_on_the_map_uses_the_swatch_colour() -> void:
	var overlay = load("res://scripts/view/hex_overlay.gd").new()
	add_child_autofree(overlay)
	overlay.arc_grid = HexGrid.new()
	var hexes: Array[Vector2i] = [Vector2i(1, 0)]
	overlay.show_arc(hexes, ShipState.PORT)
	var rim_colors: Array = []
	for child in overlay.arcs_node.get_children():
		if child.name.begins_with("ArcRim"):
			rim_colors.append(child.material_override.albedo_color)
	assert_eq(rim_colors, [BroadsideColors.color(ShipState.PORT)])


func test_arc_outside_the_chosen_battery_has_no_rim() -> void:
	var overlay = load("res://scripts/view/hex_overlay.gd").new()
	add_child_autofree(overlay)
	overlay.arc_grid = HexGrid.new()
	var hexes: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	overlay.show_arc(hexes, ShipState.STARBOARD, false)
	var rims := 0
	for child in overlay.arcs_node.get_children():
		if child.name.begins_with("ArcRim"):
			rims += 1
	assert_eq(rims, 0, "faint fill only")
	assert_eq(overlay.arcs_node.get_child_count(), 2, "one fill per hex")


func test_modifier_lines_use_labels_and_signed_values() -> void:
	var p := _preview(3, 9)
	p.modifiers = [{"name": "rake", "value": 2}, {"name": "two_targets", "value": -12}]
	var lines: Array[String] = FireText.modifier_lines(p)
	assert_eq(lines, ["rake +2", "two targets -12"] as Array[String])


func test_modifier_lines_unknown_name_falls_back_to_spaced_name() -> void:
	var p := _preview(3, 9)
	p.modifiers = [{"name": "wind_gust", "value": 1}]
	assert_eq(FireText.modifier_lines(p), ["wind gust +1"] as Array[String])


func test_two_target_note_shows_the_penalty_on_each_broadside() -> void:
	assert_eq(FireText.two_target_note(-12), "Two targets: −12 on each broadside")


func test_target_names_give_name_and_type() -> void:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": "e1", "player_id": 1, "ship_name": "Topaze", "name": "32-gun Frigate"})
	assert_eq(FireOrdersModel.target_names([s]), {"e1": "Topaze — 32-gun Frigate"})


# --- Ships without a shot ----------------------------------------------------------------------

func _state(id: String, ship_name: String, player: int, hex: Vector2i) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": id, "ship_name": ship_name, "player_id": player})
	s.hex_position = hex
	return s


func test_no_shot_line_names_the_ship_and_the_reason() -> void:
	assert_eq(FireText.no_shot_line("HMS Phoebe", "out of both broadside arcs"),
		"HMS Phoebe — no broadside bears: out of both broadside arcs")


# --- Batteries -------------------------------------------------------------------------------

func _shot(side: int, target_id: String, battery: String, mgn: int = 10) -> GunneryTypes.ShotPreview:
	var p := _preview(3, mgn)
	p.order = GunneryTypes.FireOrder.new()
	p.order.side = side
	p.order.target_id = target_id
	p.order.battery = battery
	p.batteries = 2 if battery == "full" else 1
	return p


func test_battery_label_text() -> void:
	assert_eq(FireText.battery_label("full"), "Full broadside")
	assert_eq(FireText.battery_label("bow"), "Bow battery")
	assert_eq(FireText.battery_label("stern"), "Stern battery")
	assert_eq(FireText.battery_label("chase"), "Chaser")


func test_breakdown_shows_half_broadside() -> void:
	var p := _shot(0, "a", "bow", 11)
	p.bgn = 18
	p.modifiers = [{"name": "crew_quality", "value": 1}, {"name": "half_broadside", "value": -8}]
	var text: String = FireText.breakdown_text(p)
	assert_string_contains(text, "Half broadside −8")
	assert_string_contains(text, "= 11")
	assert_false(text.contains("half broadside -8"), "shown once")


func test_breakdown_without_half_broadside_modifier_does_not_mention_it() -> void:
	# 7.C.12g: with two targets the calculator gives -12 and no -8; the text follows the modifiers.
	var p := _shot(0, "a", "bow", 6)
	p.bgn = 18
	p.modifiers = [{"name": "two_targets", "value": -12}]
	assert_false(FireText.breakdown_text(p).contains("alf broadside"))


# --- The side panel's summary line ---------------------------------------------------------------

func test_orders_summary_counts_a_split_side_as_half_broadsides() -> void:
	const GameControllerScript = preload("res://scripts/core/game_controller.gd")
	var split := [{"battery": "bow"}, {"battery": "stern"}]
	assert_eq(GameControllerScript.orders_summary_line(split), "Your orders: Fire 2 half broadsides.")
	assert_eq(GameControllerScript.orders_summary_line([{"battery": "full"}]), "Your orders: Fire 1 broadside.")
	assert_eq(GameControllerScript.orders_summary_line([]), "Your orders: Hold all fire.")


# --- Marine fire block (7.G; boarding spec §4.4) ---------------------------------------------------

func test_marine_option_text() -> void:
	var p := {"boxes": 7, "column": "7-8", "modifiers": [{"name": "grappled_or_fouled", "value": -1}],
		"modifier": -1, "hit_max": 5, "chance": 83, "most": 1}
	assert_eq(FireText.marine_option_text("Hermione", p),
		"Hermione — 7 marines, column 7-8, alongside −1 — hits on 5 or less (83%)")
	var big := {"boxes": 11, "column": "11+", "modifiers": [], "modifier": 0, "hit_max": 5, "chance": 83, "most": 2}
	assert_eq(FireText.marine_option_text("X", big), "X — 11 marines, column 11+ — hits on 5 or less (83%), up to 2 boxes")
	var none := {"boxes": 1, "column": "1-2", "modifiers": [{"name": "cq_g", "value": 2}], "modifier": 2,
		"hit_max": 0, "chance": 0, "most": 0}
	assert_eq(FireText.marine_option_text("Y", none), "Y — 1 marine, column 1-2, crew +2 — cannot hit")


func test_fire_button_text_with_marines() -> void:
	assert_eq(FireText.fire_button_text_with_marines([], 0), "Hold all fire")
	assert_eq(FireText.fire_button_text_with_marines([], 1), "Fire muskets")
	assert_eq(FireText.fire_button_text_with_marines([{"battery": "full"}], 1), "Fire 1 broadside and muskets")
	const GameControllerScript = preload("res://scripts/core/game_controller.gd")
	assert_eq(GameControllerScript.orders_summary_line([], 1), "Your orders: Fire muskets.")


# --- chasers (house rule, register §5) ---

func test_fire_button_counts_chasers() -> void:
	assert_eq(FireText.fire_button_text(1, 0, 1), "Fire 1 broadside and 1 chaser")
	assert_eq(FireText.fire_button_text(0, 0, 2), "Fire 2 chasers")
	assert_eq(FireText.fire_button_text(0), "Hold all fire")
	var orders := FireOrdersModel.orders_for_sides("own", {
		GunneryTypes.CHASE_BOW: {"bow": "y", "stern": "", "want_high": false, "want_dismantling": false},
		ShipState.PORT: {"bow": "y", "stern": "", "want_high": false, "want_dismantling": false}}, {"y": 2})
	assert_eq(FireText.fire_button_text_for(orders), "Fire 1 half broadside and 1 chaser")


func test_chase_arc_drawn_from_its_end() -> void:
	var geo := FireGeometry.new(HexGrid.new())
	var ship := ShipState.new()
	ship.hex_position = Vector2i(0, 0)
	ship.facing = 0
	var own := ship.occupied_hexes()
	var astern: Array[Vector2i] = GameControllerScript.battery_arc(geo, ship, GunneryTypes.CHASE_STERN,
		["bow"] as Array[String])
	assert_true(astern.has(Vector2i(-2, 0)), "the stern chaser covers the hex astern of the stern")
	assert_false(astern.has(Vector2i(1, 0)))
	var ahead: Array[Vector2i] = GameControllerScript.battery_arc(geo, ship, GunneryTypes.CHASE_BOW,
		["stern"] as Array[String])
	assert_true(ahead.has(Vector2i(2, 0)))
	assert_false(ahead.has(Vector2i(-2, 0)))
	for h in own:
		assert_false(astern.has(h))
		assert_false(ahead.has(h))


func test_chase_colour() -> void:
	assert_eq(BroadsideColors.color(GunneryTypes.CHASE_BOW), BroadsideColors.CHASE)
	assert_eq(BroadsideColors.color(GunneryTypes.CHASE_STERN), BroadsideColors.CHASE)
	assert_eq(BroadsideColors.color(ShipState.STARBOARD), BroadsideColors.STARBOARD)


func test_two_target_note_says_shot_when_a_chaser_is_involved() -> void:
	assert_eq(FireText.two_target_note(-12, true), "Two targets: −12 on each shot")
	assert_eq(FireText.two_target_note(-12), "Two targets: −12 on each broadside")


func test_gun_rows_flag_the_chasers() -> void:
	var rows := CrewOverlayText.gun_rows(_state("o", "HMS Phoebe", 0, Vector2i.ZERO))
	var flagged := rows.filter(func(r): return r.get("chase", false))
	assert_eq(flagged.size(), 2)
	assert_eq(rows.size() - flagged.size(), 2, "the broadside rows carry no flag")

