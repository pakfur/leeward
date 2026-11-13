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


func test_option_text_shows_name_range_and_number() -> void:
	var text: String = FirePanel.option_text("HMS Enemy", _preview(4, 11))
	assert_eq(text, "HMS Enemy — range 4 · 11")


func test_option_text_includes_rake_and_initial_broadside_tags() -> void:
	var text: String = FirePanel.option_text("Foe", _preview(2, 14, "stern", true))
	assert_string_contains(text, "range 2")
	assert_string_contains(text, "stern rake")
	assert_string_contains(text, "initial broadside")
	assert_true(text.ends_with("14"))


func test_option_text_without_tags_has_no_stray_separator() -> void:
	var text: String = FirePanel.option_text("Foe", _preview(6, 3))
	assert_false(text.contains("· ·"))
	assert_false(text.contains("rake"))


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
