extends GutTest
## Tests for the pure presentation helpers of the fire declaration panel.

const FirePanel = preload("res://scripts/ui/fire_declaration_panel.gd")
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


func test_aim_note_shows_the_gunfire_limit() -> void:
	assert_eq(FirePanel.aim_note(false, ["crew"], "E"), "Low aim holds only on a d6 of 1–3 (14.E: crew CQ E)")
	assert_true(FirePanel.aim_note(false, ["crew", "heel"], "F").ends_with(
			"(14.E: crew CQ F, firing to windward)"))
	assert_eq(FirePanel.aim_note(false, [], "E"), "")
	assert_eq(FirePanel.aim_note(true, ["crew"], "E"), FirePanel.aim_note(true))


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

func _state(id: String, ship_name: String, player: int, hex: Vector2i) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": id, "ship_name": ship_name, "player_id": player})
	s.hex_position = hex
	return s


func test_no_shot_line_names_the_ship_and_the_reason() -> void:
	assert_eq(FirePanel.no_shot_line("HMS Phoebe", "out of both broadside arcs"),
		"HMS Phoebe — no broadside bears: out of both broadside arcs")


func test_more_below_hint_only_while_content_is_hidden_below() -> void:
	assert_true(FirePanel.more_below(0, 300, 800))
	assert_true(FirePanel.more_below(400, 300, 800))
	assert_false(FirePanel.more_below(500, 300, 800), "scrolled to the end")
	assert_false(FirePanel.more_below(0, 300, 280), "everything fits")


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


# --- Fixtures: two double-covered targets ---------------------------------------------------------

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
	GameState.ships_by_side[player].append(id)
	return state


## Two enemies on the starboard side, each covered by both batteries (searched, not hand-placed).
func _double_covered_setup(calc: GunneryCalculator) -> Array[String]:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
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
				GameState.ships_by_side[1].erase(id)
	return placed


# --- Row order, summary line and the instantiated panel -----------------------------------------

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


# --- Marine fire block (7.G; boarding spec §4.4) ---------------------------------------------------

func test_marine_option_text() -> void:
	var p := {"boxes": 7, "column": "7-8", "modifiers": [{"name": "grappled_or_fouled", "value": -1}],
		"modifier": -1, "hit_max": 5, "chance": 83, "most": 1}
	assert_eq(FirePanel.marine_option_text("Hermione", p),
		"Hermione — 7 marines, column 7-8, alongside −1 — hits on 5 or less (83%)")
	var big := {"boxes": 11, "column": "11+", "modifiers": [], "modifier": 0, "hit_max": 5, "chance": 83, "most": 2}
	assert_eq(FirePanel.marine_option_text("X", big), "X — 11 marines, column 11+ — hits on 5 or less (83%), up to 2 boxes")
	var none := {"boxes": 1, "column": "1-2", "modifiers": [{"name": "cq_g", "value": 2}], "modifier": 2,
		"hit_max": 0, "chance": 0, "most": 0}
	assert_eq(FirePanel.marine_option_text("Y", none), "Y — 1 marine, column 1-2, crew +2 — cannot hit")


func test_fire_button_text_with_marines() -> void:
	assert_eq(FirePanel.fire_button_text_with_marines([], 0), "Hold all fire")
	assert_eq(FirePanel.fire_button_text_with_marines([], 1), "Fire muskets")
	assert_eq(FirePanel.fire_button_text_with_marines([{"battery": "full"}], 1), "Fire 1 broadside and muskets")
	const GameControllerScript = preload("res://scripts/core/game_controller.gd")
	assert_eq(GameControllerScript.orders_summary_line([], 1), "Your orders: Fire muskets.")


func test_panel_lists_a_ship_with_only_a_marine_shot() -> void:
	# 7.G.1: an enemy dead ahead gives no broadside but is a marine target, so the panel opens.
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	var firer := _armed("firer", 0, Vector2i.ZERO, 0)
	firer.marine_count = 7
	_armed("foe", 1, Vector2i(2, 0), 0)  # stern (1,0) alongside the firer's bow
	# The bow chaser bears on the foe (every adjacent ship lies in some arc), so every sailor section
	# is put on a task: no gun bears.
	firer.plotted_sections = [0, 1, 2, 3] as Array[int]
	assert_true(GameState.gunnery_calculator.eligible_shots("firer").is_empty(), "no gun bears (every section busy)")
	var panel: Control = load("res://scenes/ui/fire_declaration_panel.tscn").instantiate()
	add_child_autofree(panel)
	assert_eq(panel.setup(["firer"]), 1, "listed for its marines")
	assert_eq(panel.get_all_orders(), [], "no gun orders")
	assert_eq(panel.get_marine_orders(), [{"ship_id": "firer", "target_id": "foe"}], "the marine shot is chosen")
	assert_eq(panel.fire_button.text, "Fire muskets")
	var hold: Button = panel._marines["firer"]["rows"][""]
	hold.pressed.emit()
	assert_eq(panel.get_marine_orders(), [], "hold musket fire")
	assert_eq(panel.fire_button.text, "Hold all fire")
	var row: Button = panel._marines["firer"]["rows"]["foe"]
	row.pressed.emit()
	assert_true(row.button_pressed)
	assert_string_contains(row.text, "7 marines, column 7-8")
	assert_eq(GameState.marine_fire_resolver.validate_orders(0, panel.get_marine_orders()), "",
		"the panel's marine orders pass the server's validation")
	GameState.ships.clear()


# --- chasers (house rule, register §5) ---

func test_fire_button_counts_chasers() -> void:
	assert_eq(FirePanel.fire_button_text(1, 0, 1), "Fire 1 broadside and 1 chaser")
	assert_eq(FirePanel.fire_button_text(0, 0, 2), "Fire 2 chasers")
	assert_eq(FirePanel.fire_button_text(0), "Hold all fire")
	var orders := FirePanel.panel_orders("own", {
		GunneryTypes.CHASE_BOW: {"bow": "y", "stern": "", "want_high": false, "want_dismantling": false},
		ShipState.PORT: {"bow": "y", "stern": "", "want_high": false, "want_dismantling": false}}, {"y": 2})
	assert_eq(FirePanel.fire_button_text_for(orders), "Fire 1 half broadside and 1 chaser")


func test_side_names_cover_chasers() -> void:
	assert_eq(FirePanel.SIDE_NAMES[GunneryTypes.CHASE_BOW], "Bow chaser")
	assert_eq(FirePanel.SIDE_NAMES[GunneryTypes.CHASE_STERN], "Stern chaser")
	assert_eq(FirePanel.battery_label("chase"), "Chaser")
	assert_eq(FirePanel.ALL_SIDES, [0, 1, 2, 3] as Array[int])


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
	assert_eq(FirePanel.two_target_note(-12, true), "Two targets: −12 on each shot")
	assert_eq(FirePanel.two_target_note(-12), "Two targets: −12 on each broadside")


func test_gun_rows_flag_the_chasers() -> void:
	var rows := CrewOverlayText.gun_rows(_state("o", "HMS Phoebe", 0, Vector2i.ZERO))
	var flagged := rows.filter(func(r): return r.get("chase", false))
	assert_eq(flagged.size(), 2)
	assert_eq(rows.size() - flagged.size(), 2, "the broadside rows carry no flag")

