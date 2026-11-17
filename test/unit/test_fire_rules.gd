extends GutTest
## Tests for FireRules: the fire declaration rules shared by the calculator, the AI and the panel.


func _order(side: int, target_id: String, battery: String, ship_id: String = "me") -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = side
	order.target_id = target_id
	order.battery = battery
	return order


func test_effective_ammo_falls_back_without_forgetting_the_wish() -> void:
	assert_eq(FireRules.effective_ammo(true, 5), "dismantling")
	assert_eq(FireRules.effective_ammo(true, 9), "round", "beyond 7 hexes: roundshot")
	assert_eq(FireRules.effective_ammo(false, 5), "round")


func test_dismantling_allowed_only_within_range_seven() -> void:
	assert_true(FireRules.dismantling_allowed(7))
	assert_false(FireRules.dismantling_allowed(8))
	assert_eq(FireRules.max_range("dismantling"), 7)
	assert_eq(FireRules.max_range("round"), 15)


func test_effective_aim_is_locked_high_when_high_only() -> void:
	assert_eq(FireRules.effective_aim("low", true), "high")
	assert_eq(FireRules.effective_aim("low", false), "low")
	assert_eq(FireRules.effective_aim("high", false), "high")
	assert_true(FireRules.high_only(10))
	assert_false(FireRules.high_only(9))


func test_side_shots_full_when_both_batteries_name_one_target() -> void:
	assert_eq(FireRules.side_shots("a", "a"), [{"target_id": "a", "battery": "full"}])
	assert_eq(FireRules.side_shots("a", "b"),
		[{"target_id": "a", "battery": "bow"}, {"target_id": "b", "battery": "stern"}])
	assert_eq(FireRules.side_shots("", "b"), [{"target_id": "b", "battery": "stern"}])
	assert_eq(FireRules.side_shots("", ""), [])


func test_make_order_carries_forced_aim_and_ammo() -> void:
	var o := FireRules.make_order("me", 1, "foe", "bow", false, true, 12)
	assert_eq(o.to_dict(), {"ship_id": "me", "side": 1, "target_id": "foe",
		"aim": "high", "ammo": "round", "battery": "bow", "mgn_reduction": 0})
	o = FireRules.make_order("me", 0, "foe", "full", true, true, 4)
	assert_eq([o.aim, o.ammo], ["high", "dismantling"])


func test_limit_targets_keeps_at_most_two_per_ship() -> void:
	var sides := {0: {"bow": "a", "stern": "b"}, 1: {"bow": "c", "stern": "c"}}
	var limited: Dictionary = FireRules.limit_targets(sides, 1)
	assert_eq(limited[1], {"bow": "c", "stern": "c"}, "the side just changed is kept")
	assert_eq(limited[0], {"bow": "a", "stern": ""}, "the other side drops its stern target first")
	var fine := {0: {"bow": "a", "stern": "b"}, 1: {"bow": "a", "stern": "a"}}
	assert_eq(FireRules.limit_targets(fine, 1), fine)


func test_declaration_error_rules() -> void:
	assert_eq(FireRules.declaration_error([_order(1, "a", "bow"), _order(1, "b", "stern")]), "")
	assert_eq(FireRules.declaration_error([_order(1, "a", "full"), _order(1, "b", "bow")]), "battery fired twice")
	assert_string_contains(FireRules.declaration_error([_order(1, "a", "bow"), _order(1, "a", "stern")]),
		"declare a full broadside")
	assert_eq(FireRules.declaration_error([_order(1, "a", "bow"), _order(1, "b", "stern"), _order(0, "c", "full")]),
		"more than two targets")
	assert_string_contains(FireRules.declaration_error([_order(1, "a", "middle")]), "unknown battery")


func test_full_broadside_ranks_before_half() -> void:
	assert_true(FireRules.battery_rank("full") < FireRules.battery_rank("bow"))
	assert_eq(FireRules.battery_rank("bow"), FireRules.battery_rank("stern"))


# --- 7.F.2 lower-deck guns, the rule shared by the calculator and the ship card ---

func test_lower_deck_closed_rule() -> void:
	var stbd := ShipState.STARBOARD
	var port := ShipState.PORT
	assert_false(FireRules.lower_deck_closed(4, 3, stbd, stbd), "sea below freeboard: open")
	assert_false(FireRules.lower_deck_closed(0, 0, stbd, stbd), "calm: open")
	assert_true(FireRules.lower_deck_closed(4, 4, stbd, stbd), "sea = freeboard: leeward side shut")
	assert_false(FireRules.lower_deck_closed(4, 4, port, stbd), "sea = freeboard: windward side open")
	assert_false(FireRules.lower_deck_closed(4, 4, port, -1), "sea = freeboard at WF=L/R: open")
	assert_false(FireRules.lower_deck_closed(4, 4, stbd, -1))
	assert_true(FireRules.lower_deck_closed(4, 5, port, -1), "sea above freeboard: both sides shut")
	assert_true(FireRules.lower_deck_closed(4, 5, stbd, port))


func test_lower_deck_modifier_reads_the_ship() -> void:
	var s := ShipState.new()
	s.ship = Ship.new()
	s.ship.freeboard = 4
	s.ship.lower_deck_modifier = -5
	s.facing = 1  # wind from 0: WF=C, starboard leeward
	assert_eq(FireRules.lower_deck_modifier(s, ShipState.STARBOARD, 4, 0), -5)
	assert_eq(FireRules.lower_deck_modifier(s, ShipState.PORT, 4, 0), 0)
	assert_eq(FireRules.lower_deck_modifier(s, ShipState.PORT, 5, 0), -5)
	assert_eq(FireRules.lower_deck_modifier(s, ShipState.PORT, 3, 0), 0)
