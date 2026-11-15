extends GutTest
## Tests for the pure presentation helpers of the fire declaration panel.

const FirePanel = preload("res://scripts/ui/fire_declaration_panel.gd")


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


func test_option_text_labels_range_and_gunfire() -> void:
	var text: String = FirePanel.option_text("32-gun Frigate (enemy)", _preview(10, 4))
	assert_eq(text, "32-gun Frigate (enemy) — range 10 — gunfire 4")


func test_option_text_includes_rake_and_initial_broadside_tags() -> void:
	var text: String = FirePanel.option_text("Foe", _preview(2, 14, "stern", true))
	assert_eq(text, "Foe — range 2 — gunfire 14 — stern rake — initial broadside")


func test_option_text_without_tags_has_no_stray_separator() -> void:
	var text: String = FirePanel.option_text("Foe", _preview(6, 3))
	assert_false(text.ends_with("— "))
	assert_false(text.contains("rake"))


func test_breakdown_text_in_plain_words() -> void:
	var p := _preview(2, 22)
	p.bgn = 18
	p.modifiers = [{"name": "initial_broadside", "value": 4}]
	assert_eq(FirePanel.breakdown_text(p),
		"Base 18, initial broadside +4 = 22. A d6 is added when you fire; higher is better.")
	var plain := _preview(9, 5)
	plain.bgn = 5
	assert_eq(FirePanel.breakdown_text(plain), "Base 5. A d6 is added when you fire; higher is better.")


func test_fire_button_text_always_says_what_it_does() -> void:
	assert_eq(FirePanel.fire_button_text(0), "Hold all fire")
	assert_eq(FirePanel.fire_button_text(1), "Fire 1 broadside")
	assert_eq(FirePanel.fire_button_text(2), "Fire 2 broadsides")


func test_locked_toggles_explain_why() -> void:
	assert_eq(FirePanel.aim_note(true), "Range 10+: must fire high")
	assert_eq(FirePanel.aim_note(false), "")
	assert_eq(FirePanel.dismantling_note(7, true), "")
	assert_eq(FirePanel.dismantling_note(8, false), "Dismantling shot reaches 7 hexes")
	assert_string_contains(FirePanel.dismantling_note(8, true), "roundshot")


func test_effective_ammo_falls_back_without_forgetting_the_wish() -> void:
	assert_eq(FirePanel.effective_ammo(true, 5), "dismantling")
	assert_eq(FirePanel.effective_ammo(true, 9), "round", "beyond 7 hexes: roundshot")
	assert_eq(FirePanel.effective_ammo(true, 5), "dismantling", "back in range: dismantling again")
	assert_eq(FirePanel.effective_ammo(false, 5), "round")


func test_rank_targets_best_number_then_nearest_then_name() -> void:
	var ranked: Array = FirePanel.rank_targets([
		{"target_id": "far", "mgn": 10, "range": 8, "name": "B"},
		{"target_id": "best", "mgn": 14, "range": 9, "name": "Z"},
		{"target_id": "near", "mgn": 10, "range": 3, "name": "C"},
		{"target_id": "tie", "mgn": 10, "range": 3, "name": "A"},
	])
	var ids: Array = ranked.map(func(e): return e["target_id"])
	assert_eq(ids, ["best", "tie", "near", "far"])


func test_no_shot_reason_maps_calculator_reasons_to_plain_words() -> void:
	var arc := "target is not in that broadside's arc"
	assert_eq(FirePanel.no_shot_reason([arc, arc]), "out of both broadside arcs")
	assert_eq(FirePanel.no_shot_reason([arc, "target is out of range (16 hexes, maximum 15)"]), "out of range")
	assert_eq(FirePanel.no_shot_reason(["no line of sight to target", arc]), "line of sight blocked")
	assert_eq(FirePanel.no_shot_reason(["no sailor sections able to fire", "no sailor sections able to fire"]),
		"no crew to serve the guns")
	assert_eq(FirePanel.no_shot_reason(["a struck ship cannot fire or be fired on"]), "struck")
	assert_eq(FirePanel.no_shot_reason(["no gunnery factor at this range"]), "out of range")
	assert_eq(FirePanel.no_shot_reason([]), "no enemy afloat")


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
	var lines: Array[String] = FirePanel.modifier_lines(p)
	assert_eq(lines, ["rake +2", "two targets -12"] as Array[String])


func test_modifier_lines_unknown_name_falls_back_to_spaced_name() -> void:
	var p := _preview(3, 9)
	p.modifiers = [{"name": "wind_gust", "value": 1}]
	assert_eq(FirePanel.modifier_lines(p), ["wind gust +1"] as Array[String])


func test_dismantling_allowed_only_within_range_seven() -> void:
	assert_true(FirePanel.dismantling_allowed(7))
	assert_false(FirePanel.dismantling_allowed(8))


func test_effective_aim_is_locked_high_when_high_only() -> void:
	assert_eq(FirePanel.effective_aim("low", true), "high")
	assert_eq(FirePanel.effective_aim("low", false), "low")
	assert_eq(FirePanel.effective_aim("high", false), "high")


func test_build_orders_skips_held_sides_and_uses_order_dicts() -> void:
	var sides := {
		0: [],
		1: [{"target_id": "foe", "battery": "full", "aim": "high", "ammo": "dismantling"}],
	}
	var orders: Array = FirePanel.build_orders("me", sides)
	assert_eq(orders.size(), 1)
	assert_eq(orders[0], {"ship_id": "me", "side": 1, "target_id": "foe",
		"aim": "high", "ammo": "dismantling", "battery": "full"})


func test_build_orders_two_sides_in_side_order() -> void:
	var sides := {
		1: [{"target_id": "b", "battery": "full", "aim": "low", "ammo": "round"}],
		0: [{"target_id": "a", "battery": "full", "aim": "low", "ammo": "round"}],
	}
	var orders: Array = FirePanel.build_orders("me", sides)
	assert_eq(orders.size(), 2)
	assert_eq(orders[0]["side"], 0)
	assert_eq(orders[1]["side"], 1)


func test_build_orders_all_hold_is_empty() -> void:
	var sides := {0: []}
	assert_eq(FirePanel.build_orders("me", sides).size(), 0)


func test_default_side_is_the_single_best_one_target_shot() -> void:
	var port := FirePanel.rank_targets([{"target_id": "a", "mgn": 10, "range": 3, "name": "A"}])
	var starboard := FirePanel.rank_targets([{"target_id": "b", "mgn": 14, "range": 6, "name": "B"},
		{"target_id": "c", "mgn": 9, "range": 2, "name": "C"}])
	assert_eq(FirePanel.default_side({ShipState.PORT: port, ShipState.STARBOARD: starboard}), ShipState.STARBOARD)


func test_default_side_ties_go_to_nearest_then_name_then_port() -> void:
	var near := [{"target_id": "a", "mgn": 10, "range": 2, "name": "Z"}]
	var far := [{"target_id": "b", "mgn": 10, "range": 5, "name": "A"}]
	assert_eq(FirePanel.default_side({ShipState.PORT: far, ShipState.STARBOARD: near}), ShipState.STARBOARD)
	var named_a := [{"target_id": "a", "mgn": 10, "range": 2, "name": "A"}]
	var named_b := [{"target_id": "b", "mgn": 10, "range": 2, "name": "B"}]
	assert_eq(FirePanel.default_side({ShipState.PORT: named_b, ShipState.STARBOARD: named_a}), ShipState.STARBOARD)
	assert_eq(FirePanel.default_side({ShipState.PORT: named_a, ShipState.STARBOARD: named_a.duplicate(true)}), ShipState.PORT)


func test_default_side_with_one_broadside_or_none() -> void:
	var rows := [{"target_id": "a", "mgn": 4, "range": 9, "name": "A"}]
	assert_eq(FirePanel.default_side({ShipState.STARBOARD: rows}), ShipState.STARBOARD)
	assert_eq(FirePanel.default_side({}), -1)


func test_two_target_note_shows_the_penalty_on_each_broadside() -> void:
	assert_eq(FirePanel.two_target_note(-12), "Two targets: −12 on each broadside")


func test_target_names_give_name_and_type() -> void:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": "e1", "player_id": 1, "ship_name": "Topaze", "name": "32-gun Frigate"})
	assert_eq(FirePanel.target_names([s]), {"e1": "Topaze — 32-gun Frigate"})


func test_footer_follows_the_selection() -> void:
	assert_string_contains(FirePanel.footer_text(1, false), "best shot is chosen")
	assert_string_contains(FirePanel.footer_text(1, true), "You changed the target")
	assert_string_contains(FirePanel.footer_text(0, true), "Holding all fire")
	assert_string_contains(FirePanel.footer_text(0, false), "Holding all fire")
	assert_false(FirePanel.footer_text(0, true).contains("best shot"), "no best-shot hint while holding fire")


# --- Ships without a shot ----------------------------------------------------------------------

class FakeCalculator:
	extends RefCounted
	var reasons := {}  # side -> reason, or "side:battery" -> reason (takes precedence)
	func preview(order: GunneryTypes.FireOrder, _two := false) -> GunneryTypes.ShotPreview:
		var p := GunneryTypes.ShotPreview.new()
		var key := "%d:%s" % [order.side, order.battery]
		p.reason = str(reasons.get(key, reasons.get(order.side, "")))
		return p


func _state(id: String, ship_name: String, player: int, hex: Vector2i) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": id, "ship_name": ship_name, "player_id": player})
	s.hex_position = hex
	return s


func test_no_shot_line_names_the_ship_and_the_reason() -> void:
	assert_eq(FirePanel.no_shot_line("HMS Phoebe", "out of both broadside arcs"),
		"HMS Phoebe — no broadside bears: out of both broadside arcs")


func test_ship_no_shot_reason_previews_against_the_nearest_enemy() -> void:
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var far := _state("f", "Far", 1, Vector2i(9, 0))
	var near := _state("n", "Near", 1, Vector2i(3, 0))
	var calc := FakeCalculator.new()
	calc.reasons = {ShipState.PORT: "target is not in the port arc",
		ShipState.STARBOARD: "target is out of range (16 hexes, maximum 15)"}
	var grid := HexGrid.new(1.0)
	assert_eq(FirePanel.nearest_enemy(own, [own, far, near], grid), near)
	assert_eq(FirePanel.ship_no_shot_reason(own, [own, far, near], calc, grid), "out of range")


func test_ship_no_shot_reason_for_struck_ships_and_no_enemy() -> void:
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var calc := FakeCalculator.new()
	var grid := HexGrid.new(1.0)
	assert_eq(FirePanel.ship_no_shot_reason(own, [own], calc, grid), "no enemy afloat")
	own.status = ShipState.Status.STRUCK
	assert_eq(FirePanel.ship_no_shot_reason(own, [own], calc, grid), "struck")


func test_more_below_hint_only_while_content_is_hidden_below() -> void:
	assert_true(FirePanel.more_below(0, 300, 800))
	assert_true(FirePanel.more_below(400, 300, 800))
	assert_false(FirePanel.more_below(500, 300, 800), "scrolled to the end")
	assert_false(FirePanel.more_below(0, 300, 280), "everything fits")


func test_ship_no_shot_reason_comes_from_the_bearing_battery() -> void:
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var foe := _state("f", "Foe", 1, Vector2i(3, 0))
	var arc := "target is not in that broadside's arc"
	var calc := FakeCalculator.new()
	calc.reasons = {ShipState.PORT: arc,
		"1:full": "only the bow battery bears: a full broadside needs both",
		"1:bow": "no sailor sections able to fire",
		"1:stern": arc}
	var grid := HexGrid.new(1.0)
	assert_eq(FirePanel.ship_no_shot_reason(own, [own, foe], calc, grid), "no crew to serve the guns")
	calc.reasons["1:bow"] = "target is out of range (16 hexes, maximum 15)"
	assert_eq(FirePanel.ship_no_shot_reason(own, [own, foe], calc, grid), "out of range")


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
	assert_eq(FirePanel.battery_label("full"), "Full broadside")
	assert_eq(FirePanel.battery_label("bow"), "Bow battery")
	assert_eq(FirePanel.battery_label("stern"), "Stern battery")


func test_options_offer_full_only_when_both_bear() -> void:
	var both: Array = [_shot(0, "a", "full"), _shot(0, "a", "bow"), _shot(0, "a", "stern")]
	assert_eq(FirePanel.battery_options(both), ["full"] as Array[String])
	assert_eq(FirePanel.battery_options([_shot(0, "a", "bow")]), ["bow"] as Array[String])
	assert_eq(FirePanel.battery_options([_shot(0, "a", "stern")]), ["stern"] as Array[String])
	var refused := _shot(0, "a", "full")
	refused.can_fire = false
	assert_eq(FirePanel.battery_options([refused, _shot(0, "a", "stern")]), ["stern"] as Array[String])
	assert_eq(FirePanel.battery_options([]), [] as Array[String])


func test_breakdown_shows_half_broadside() -> void:
	var p := _shot(0, "a", "bow", 11)
	p.bgn = 18
	p.modifiers = [{"name": "crew_quality", "value": 1}, {"name": "half_broadside", "value": -8}]
	var text: String = FirePanel.breakdown_text(p)
	assert_string_contains(text, "Half broadside −8")
	assert_string_contains(text, "= 11")
	assert_false(text.contains("half broadside -8"), "shown once")


func test_breakdown_without_half_broadside_modifier_does_not_mention_it() -> void:
	# 7.C.12g: with two targets the calculator gives -12 and no -8; the text follows the modifiers.
	var p := _shot(0, "a", "bow", 6)
	p.bgn = 18
	p.modifiers = [{"name": "two_targets", "value": -12}]
	assert_false(FirePanel.breakdown_text(p).contains("alf broadside"))


func test_option_text_names_the_battery() -> void:
	assert_eq(FirePanel.option_text("Foe", _preview(3, 9), "bow"), "Foe — Bow battery — range 3 — gunfire 9")


func test_options_by_target_groups_shots_per_side_and_target() -> void:
	var shots: Array[GunneryTypes.ShotPreview] = [_shot(0, "a", "full"), _shot(0, "a", "bow"),
		_shot(0, "a", "stern"), _shot(1, "b", "stern")]
	var by: Dictionary = FirePanel.options_by_target(shots)
	assert_eq(by.keys().size(), 2)
	assert_eq(by[0]["a"].keys(), ["full", "bow", "stern"])
	assert_eq(by[1]["b"].keys(), ["stern"])


func test_row_battery_full_unless_the_other_battery_fires_elsewhere() -> void:
	var full: Array[String] = ["full"]
	assert_eq(FirePanel.row_battery(full, "a", "", ""), "full")
	assert_eq(FirePanel.row_battery(full, "a", "a", "a"), "full")
	assert_eq(FirePanel.row_battery(full, "a", "x", ""), "stern", "bow fires at x: the stern is free")
	assert_eq(FirePanel.row_battery(full, "a", "", "x"), "bow")
	assert_eq(FirePanel.row_battery(full, "a", "x", "y"), "full", "picking it moves both batteries")
	assert_eq(FirePanel.row_battery(["bow"] as Array[String], "a", "", "x"), "bow")


func test_choose_full_bow_and_split() -> void:
	var opts := {"a": ["bow"] as Array[String], "b": ["stern"] as Array[String], "c": ["full"] as Array[String]}
	var s: Dictionary = FirePanel.choose_battery({"bow": "", "stern": ""}, "c", "full", opts)
	assert_eq(s, {"bow": "c", "stern": "c"})
	s = FirePanel.choose_battery(s, "a", "bow", opts)
	assert_eq(s, {"bow": "a", "stern": "c"}, "the bow leaves the full broadside; the stern stays on c")
	s = FirePanel.choose_battery(s, "b", "stern", opts)
	assert_eq(s, {"bow": "a", "stern": "b"}, "split: bow at a, stern at b")
	s = FirePanel.choose_battery(s, "b", "stern", opts)
	assert_eq(s, {"bow": "a", "stern": ""}, "picking a chosen row again holds that battery")
	s = FirePanel.choose_battery(s, "", "", opts)
	assert_eq(s, {"bow": "", "stern": ""}, "hold fire")


func test_choose_a_free_battery_joins_a_full_broadside_target() -> void:
	var opts := {"a": ["bow"] as Array[String], "c": ["full"] as Array[String]}
	var s: Dictionary = FirePanel.choose_battery({"bow": "a", "stern": ""}, "c", "stern", opts)
	assert_eq(s, {"bow": "a", "stern": "c"})
	s = FirePanel.choose_battery(s, "a", "bow", opts)
	assert_eq(s, {"bow": "c", "stern": "c"}, "with the bow free, both fire at c: a full broadside")


func test_side_shots_full_when_both_batteries_name_one_target() -> void:
	assert_eq(FirePanel.side_shots("a", "a"), [{"target_id": "a", "battery": "full"}])
	assert_eq(FirePanel.side_shots("a", "b"),
		[{"target_id": "a", "battery": "bow"}, {"target_id": "b", "battery": "stern"}])
	assert_eq(FirePanel.side_shots("", "b"), [{"target_id": "b", "battery": "stern"}])
	assert_eq(FirePanel.side_shots("", ""), [])


func test_limit_targets_keeps_at_most_two_per_ship() -> void:
	var sides := {0: {"bow": "a", "stern": "b"}, 1: {"bow": "c", "stern": "c"}}
	var limited: Dictionary = FirePanel.limit_targets(sides, 1)
	assert_eq(limited[1], {"bow": "c", "stern": "c"}, "the side just changed is kept")
	assert_eq(limited[0], {"bow": "a", "stern": ""}, "the other side drops its stern target first")
	var fine := {0: {"bow": "a", "stern": "b"}, 1: {"bow": "a", "stern": "a"}}
	assert_eq(FirePanel.limit_targets(fine, 1), fine)


func test_panel_orders_pass_validation() -> void:
	# Every state choose_battery + limit_targets reach names at most two targets per ship
	# (side_shots already turns bow+stern at one target into a full broadside).
	var opts := {"a": ["bow"] as Array[String], "b": ["stern"] as Array[String], "c": ["full"] as Array[String]}
	var clicks := [["a", "bow"], ["b", "stern"], ["c", "full"], ["c", "stern"], ["a", "bow"], ["b", "stern"]]
	var sides := {0: {"bow": "", "stern": ""}, 1: {"bow": "", "stern": ""}}
	for side in [0, 1]:
		for click in clicks:
			sides[side] = FirePanel.choose_battery(sides[side], click[0], click[1], opts)
			sides = FirePanel.limit_targets(sides, side)
			var targets := {}
			for s in sides:
				for shot in FirePanel.side_shots(sides[s]["bow"], sides[s]["stern"]):
					targets[shot["target_id"]] = true
			assert_true(targets.size() <= 2, "at most two targets after %s" % [click])
