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
	assert_eq(FirePanel.fire_button_text(0, 2), "Fire 2 half broadsides")
	assert_eq(FirePanel.fire_button_text(1, 1), "Fire 1 broadside and 1 half broadside")


func test_fire_button_counts_a_split_side_as_two_half_broadsides() -> void:
	var sides := {ShipState.STARBOARD: {"bow": "t1", "stern": "t2"}, ShipState.PORT: {"bow": "", "stern": ""}}
	var orders := FirePanel.panel_orders("own", sides, {"t1": 3, "t2": 4})
	assert_eq(orders.size(), 2, "setup: one order per battery")
	assert_eq(FirePanel.fire_button_text_for(orders), "Fire 2 half broadsides")
	sides[ShipState.PORT] = {"bow": "t1", "stern": "t1"}
	orders = FirePanel.panel_orders("own", sides, {"t1": 3, "t2": 4})
	assert_eq(FirePanel.fire_button_text_for(orders), "Fire 1 broadside and 2 half broadsides")
	# The panel's get_all_orders() hands over an untyped Array.
	var untyped: Array = []
	untyped.append_array(orders)
	assert_eq(FirePanel.fire_button_text_for(untyped), "Fire 1 broadside and 2 half broadsides")


func test_locked_toggles_explain_why() -> void:
	assert_eq(FirePanel.aim_note(true), "Range 10+: must fire high")
	assert_eq(FirePanel.aim_note(false), "")
	assert_eq(FirePanel.dismantling_note(7, true), "")
	assert_eq(FirePanel.dismantling_note(8, false), "Dismantling shot reaches 7 hexes")
	assert_string_contains(FirePanel.dismantling_note(8, true), "roundshot")


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


func test_nearest_enemy_measures_footprint_to_footprint() -> void:
	# Own bow (0,0) facing E, stern (-1,0). "b" has the nearer bow (3 hexes) but its closest hex is 3
	# away; "a" points away (bow (-4,0) facing W, stern (-3,0)): bow 4 hexes off, closest hex 2.
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var a := _state("a", "Astern", 1, Vector2i(-4, 0))
	a.facing = 3
	var b := _state("b", "Ahead", 1, Vector2i(3, 0))
	b.facing = 3
	var grid := HexGrid.new(1.0)
	assert_eq(FirePanel.nearest_enemy(own, [own, b, a], grid), a)


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
	var both: Array = [_shot(0, "a", "stern"), _shot(0, "a", "full"), _shot(0, "a", "bow")]
	assert_eq(FirePanel.battery_options(both), ["full", "bow", "stern"] as Array[String],
		"both bear: full first, and each half broadside gets its own row")
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


# --- Row choices (explicit battery per row) ---------------------------------------------------

func test_choose_split_between_two_double_covered_targets() -> void:
	# A and B are both covered by both batteries: every row is explicit.
	var s: Dictionary = FirePanel.choose_battery({"bow": "", "stern": ""}, "a", "full")
	assert_eq(s, {"bow": "a", "stern": "a"})
	s = FirePanel.choose_battery(s, "b", "bow")
	assert_eq(s, {"bow": "b", "stern": "a"}, "bow at B, stern stays at A: a split side")
	s = FirePanel.choose_battery({"bow": "", "stern": ""}, "a", "bow")
	s = FirePanel.choose_battery(s, "b", "stern")
	assert_eq(s, {"bow": "a", "stern": "b"}, "bow at A, stern at B")
	s = FirePanel.choose_battery(s, "b", "full")
	assert_eq(s, {"bow": "b", "stern": "b"}, "full at B moves both batteries")


func test_choose_half_battery_at_double_covered_target() -> void:
	var s: Dictionary = FirePanel.choose_battery({"bow": "a", "stern": "a"}, "a", "bow")
	assert_eq(s, {"bow": "a", "stern": ""}, "bow only at A, stern held: the full broadside becomes the half")
	assert_true(FirePanel.row_chosen(s["bow"], s["stern"], "a", "bow"))
	assert_false(FirePanel.row_chosen(s["bow"], s["stern"], "a", "full"))
	s = FirePanel.choose_battery(s, "a", "stern")
	assert_eq(s, {"bow": "", "stern": "a"}, "stern only")
	s = FirePanel.choose_battery(s, "a", "stern")
	assert_eq(s, {"bow": "", "stern": ""}, "picking the chosen row again holds it")
	assert_eq(FirePanel.choose_battery({"bow": "a", "stern": "b"}, "", ""), {"bow": "", "stern": ""})


func test_row_key_separates_batteries_of_one_target() -> void:
	assert_eq(FirePanel.row_key("a", "bow"), "a|bow")
	assert_ne(FirePanel.row_key("a", "bow"), FirePanel.row_key("a", "stern"))
	assert_eq(FirePanel.row_key("", ""), "")


# --- Panel order sets agree with GunneryCalculator.validate_orders ------------------------------

func _armed(id: String, player: int, hex: Vector2i, facing: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British", "rating": 38,
		"class": 3, "maneuverability": "C", "speed_type": "F/F", "rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6], "crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4}})
	state.hex_position = hex
	state.facing = facing
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


## Two enemies on the starboard side, each covered by both batteries (searched, not hand-placed).
func _double_covered_setup(calc: GunneryCalculator) -> Array[String]:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	_armed("firer", 0, Vector2i.ZERO, 0)
	var placed: Array[String] = []
	var taken: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0)]
	for r in range(2, 9):
		for q in range(-8, 3):
			if placed.size() == 2:
				break
			var bow := Vector2i(q, r)
			var stern := HexGrid.stern_of(bow, 0)
			if taken.has(bow) or taken.has(stern) or taken.has(bow + Vector2i(1, 0)) or taken.has(stern - Vector2i(1, 0)):
				continue
			var id := "t%d" % placed.size()
			_armed(id, 1, bow, 0)
			var ok := true
			for battery in ["full", "bow", "stern"]:
				var o := FireRules.make_order("firer", 1, id, battery, false, false, 0)
				var p := calc.preview(o)
				ok = ok and p.can_fire and not p.high_only
			if ok:
				placed.append(id)
				taken.append_array([bow, stern])
			else:
				GameState.ships.erase(id)
				GameState.ships_by_player[1].erase(id)
	return placed


func test_panel_order_sets_pass_validate_orders() -> void:
	var calc := GunneryCalculator.new(GameState)
	var ids := _double_covered_setup(calc)
	assert_eq(ids.size(), 2, "two double-covered targets found")
	if ids.size() < 2:
		return
	var a := ids[0]
	var b := ids[1]
	var ranges := {}
	for id in ids:
		ranges[id] = calc.preview(FireRules.make_order("firer", 1, id, "full", false, false, 0)).range_hexes
	var click_sequences := [
		[[a, "full"]],
		[[a, "bow"]],
		[[a, "stern"]],
		[[a, "full"], [b, "bow"]],
		[[a, "bow"], [b, "stern"]],
		[[a, "full"], [a, "bow"]],
		[[a, "bow"], [b, "stern"], [b, "full"]],
		[[a, "full"], [b, "stern"], [a, "bow"]],
	]
	for clicks in click_sequences:
		var sides := {1: {"bow": "", "stern": "", "want_high": false, "want_dismantling": false}}
		for click in clicks:
			var chosen: Dictionary = FirePanel.choose_battery(sides[1], click[0], click[1])
			sides[1]["bow"] = chosen["bow"]
			sides[1]["stern"] = chosen["stern"]
			sides = FireRules.limit_targets(sides, 1)
		var orders: Array[GunneryTypes.FireOrder] = FirePanel.panel_orders("firer", sides, ranges)
		assert_false(orders.is_empty(), "%s fires" % [clicks])
		assert_eq(calc.validate_orders(0, orders), "", "validate_orders accepts %s" % [clicks])
	GameState.ships.clear()


# --- Row order, summary line and the instantiated panel -----------------------------------------

func test_display_order_nearest_target_first() -> void:
	var rows := FirePanel.display_order([
		{"target_id": "far", "mgn": 20, "range": 6, "name": "A"},
		{"target_id": "near_b", "mgn": 5, "range": 2, "name": "B"},
		{"target_id": "near_a", "mgn": 9, "range": 2, "name": "A"},
	])
	assert_eq(rows.map(func(r): return r["target_id"]), ["near_a", "near_b", "far"])


func test_battery_rows_within_a_target_go_full_bow_stern() -> void:
	var options := FirePanel.battery_options([_shot(1, "t", "stern"), _shot(1, "t", "full"), _shot(1, "t", "bow")])
	assert_eq(options, ["full", "bow", "stern"] as Array[String])


func test_orders_summary_counts_a_split_side_as_half_broadsides() -> void:
	const GameControllerScript = preload("res://scripts/core/game_controller.gd")
	var split := [{"battery": "bow"}, {"battery": "stern"}]
	assert_eq(GameControllerScript.orders_summary_line(split), "Your orders: Fire 2 half broadsides.")
	assert_eq(GameControllerScript.orders_summary_line([{"battery": "full"}]), "Your orders: Fire 1 broadside.")
	assert_eq(GameControllerScript.orders_summary_line([]), "Your orders: Hold all fire.")


func _panel_with_two_targets() -> Array:
	var ids := _double_covered_setup(GameState.gunnery_calculator)
	assert_eq(ids.size(), 2, "fixture: two double-covered targets")
	var panel: Control = load("res://scenes/ui/fire_declaration_panel.tscn").instantiate()
	add_child_autofree(panel)
	assert_eq(panel.setup(["firer"]), 1)
	return [panel, ids]


func _click(panel: Control, side: int, target_id: String, battery: String) -> void:
	var row: Button = panel._ships["firer"]["widgets"][side]["targets"][FirePanel.row_key(target_id, battery)]
	row.pressed.emit()


func test_clicking_a_chosen_row_holds_that_battery() -> void:
	var setup := _panel_with_two_targets()
	var panel: Control = setup[0]
	var ids: Array = setup[1]
	_click(panel, ShipState.STARBOARD, ids[0], "bow")
	_click(panel, ShipState.STARBOARD, ids[1], "stern")
	assert_eq(panel.get_batteries("firer", ShipState.STARBOARD), ["bow", "stern"] as Array[String], "split side")
	_click(panel, ShipState.STARBOARD, ids[0], "bow")  # the chosen bow row again
	assert_eq(panel.get_batteries("firer", ShipState.STARBOARD), ["stern"] as Array[String], "the bow battery holds")
	assert_eq(panel.get_target_ids("firer"), [ids[1]] as Array[String])
	var bow_row: Button = panel._ships["firer"]["widgets"][ShipState.STARBOARD]["targets"][FirePanel.row_key(ids[0], "bow")]
	assert_false(bow_row.button_pressed)
	_click(panel, ShipState.STARBOARD, ids[1], "stern")
	assert_eq(panel.get_batteries("firer", ShipState.STARBOARD), [] as Array[String], "the whole side holds")
	var hold_row: Button = panel._ships["firer"]["widgets"][ShipState.STARBOARD]["targets"][""]
	assert_true(hold_row.button_pressed)
	assert_eq(panel.fire_button.text, "Hold all fire")
	GameState.ships.clear()


func test_panel_rows_list_nearest_target_first() -> void:
	var setup := _panel_with_two_targets()
	var panel: Control = setup[0]
	var keys: Array = panel._ships["firer"]["widgets"][ShipState.STARBOARD]["targets"].keys()
	var ranges := {}
	for id in setup[1]:
		ranges[id] = GameState.gunnery_calculator.preview(
			FireRules.make_order("firer", ShipState.STARBOARD, id, "full", false, false, 0)).range_hexes
	var listed: Array = []
	for key in keys:
		if key != "" and not listed.has(key.get_slice("|", 0)):
			listed.append(key.get_slice("|", 0))
	var expected: Array = setup[1].duplicate()
	var names := FirePanel.target_names(GameState.get_all_ships())
	expected.sort_custom(func(x, y):
		if ranges[x] != ranges[y]:
			return ranges[x] < ranges[y]
		if names[x] != names[y]:
			return names[x] < names[y]
		return x < y)
	assert_eq(listed, expected)
	assert_eq(keys.slice(0, 3), [FirePanel.row_key(listed[0], "full"), FirePanel.row_key(listed[0], "bow"),
		FirePanel.row_key(listed[0], "stern")])
	GameState.ships.clear()
