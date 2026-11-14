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


func test_arc_colors_one_per_side() -> void:
	assert_eq(FirePanel.ARC_COLORS.size(), 2)
	assert_ne(FirePanel.ARC_COLORS[0], FirePanel.ARC_COLORS[1])


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
		0: {"target_id": "", "aim": "low", "ammo": "round"},
		1: {"target_id": "foe", "aim": "high", "ammo": "dismantling"},
	}
	var orders: Array = FirePanel.build_orders("me", sides)
	assert_eq(orders.size(), 1)
	assert_eq(orders[0], {"ship_id": "me", "side": 1, "target_id": "foe",
		"aim": "high", "ammo": "dismantling"})


func test_build_orders_two_sides_in_side_order() -> void:
	var sides := {
		1: {"target_id": "b", "aim": "low", "ammo": "round"},
		0: {"target_id": "a", "aim": "low", "ammo": "round"},
	}
	var orders: Array = FirePanel.build_orders("me", sides)
	assert_eq(orders.size(), 2)
	assert_eq(orders[0]["side"], 0)
	assert_eq(orders[1]["side"], 1)


func test_build_orders_all_hold_is_empty() -> void:
	var sides := {0: {"target_id": "", "aim": "low", "ammo": "round"}}
	assert_eq(FirePanel.build_orders("me", sides).size(), 0)
