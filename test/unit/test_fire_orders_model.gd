extends GutTest
## Tests for FireOrdersModel: the fire declaration's order logic (moved from the fire panel's tests)
## and its per-ship selection state, which the board's fire step drives.


func _preview(range_hexes: int, mgn: int) -> GunneryTypes.ShotPreview:
	var p := GunneryTypes.ShotPreview.new()
	p.can_fire = true
	p.range_hexes = range_hexes
	p.mgn = mgn
	return p


func _shot(side: int, target_id: String, battery: String, mgn: int = 10) -> GunneryTypes.ShotPreview:
	var p := _preview(3, mgn)
	p.order = GunneryTypes.FireOrder.new()
	p.order.side = side
	p.order.target_id = target_id
	p.order.battery = battery
	p.batteries = 2 if battery == "full" else 1
	return p


# --- Ranking and the default choice --------------------------------------------------------------

func test_rank_targets_best_number_then_nearest_then_name() -> void:
	var ranked: Array = FireOrdersModel.rank_targets([
		{"target_id": "far", "mgn": 10, "range": 8, "name": "B"},
		{"target_id": "best", "mgn": 14, "range": 9, "name": "Z"},
		{"target_id": "near", "mgn": 10, "range": 3, "name": "C"},
		{"target_id": "tie", "mgn": 10, "range": 3, "name": "A"},
	])
	var ids: Array = ranked.map(func(e): return e["target_id"])
	assert_eq(ids, ["best", "tie", "near", "far"])


func test_default_side_is_the_single_best_one_target_shot() -> void:
	var port := FireOrdersModel.rank_targets([{"target_id": "a", "mgn": 10, "range": 3, "name": "A"}])
	var starboard := FireOrdersModel.rank_targets([{"target_id": "b", "mgn": 14, "range": 6, "name": "B"},
		{"target_id": "c", "mgn": 9, "range": 2, "name": "C"}])
	assert_eq(FireOrdersModel.default_side({ShipState.PORT: port, ShipState.STARBOARD: starboard}),
		ShipState.STARBOARD)


func test_default_side_ties_go_to_nearest_then_name_then_port() -> void:
	var near := [{"target_id": "a", "mgn": 10, "range": 2, "name": "Z"}]
	var far := [{"target_id": "b", "mgn": 10, "range": 5, "name": "A"}]
	assert_eq(FireOrdersModel.default_side({ShipState.PORT: far, ShipState.STARBOARD: near}), ShipState.STARBOARD)
	var named_a := [{"target_id": "a", "mgn": 10, "range": 2, "name": "A"}]
	var named_b := [{"target_id": "b", "mgn": 10, "range": 2, "name": "B"}]
	assert_eq(FireOrdersModel.default_side({ShipState.PORT: named_b, ShipState.STARBOARD: named_a}),
		ShipState.STARBOARD)
	assert_eq(FireOrdersModel.default_side({ShipState.PORT: named_a, ShipState.STARBOARD: named_a.duplicate(true)}),
		ShipState.PORT)


func test_default_side_with_one_broadside_or_none() -> void:
	var rows := [{"target_id": "a", "mgn": 4, "range": 9, "name": "A"}]
	assert_eq(FireOrdersModel.default_side({ShipState.STARBOARD: rows}), ShipState.STARBOARD)
	assert_eq(FireOrdersModel.default_side({}), -1)


func test_default_side_prefers_broadside() -> void:
	var chase := [{"target_id": "a", "mgn": 9, "range": 2, "name": "A"}]
	var broadside := [{"target_id": "b", "mgn": 3, "range": 6, "name": "B"}]
	assert_eq(FireOrdersModel.default_side({GunneryTypes.CHASE_BOW: chase, ShipState.STARBOARD: broadside}),
		ShipState.STARBOARD)
	assert_eq(FireOrdersModel.default_side({GunneryTypes.CHASE_STERN: [{"target_id": "a", "mgn": 2, "range": 4, "name": "A"}]}),
		GunneryTypes.CHASE_STERN)


func test_display_order_nearest_target_first() -> void:
	var rows := FireOrdersModel.display_order([
		{"target_id": "far", "mgn": 20, "range": 6, "name": "A"},
		{"target_id": "near_b", "mgn": 5, "range": 2, "name": "B"},
		{"target_id": "near_a", "mgn": 9, "range": 2, "name": "A"},
	])
	assert_eq(rows.map(func(r): return r["target_id"]), ["near_a", "near_b", "far"])


func test_default_marine_target_best_chance_then_drm_then_id() -> void:
	var rows := [
		{"target_id": "b", "hit_max": 1, "modifier": 0},
		{"target_id": "c", "hit_max": 2, "modifier": -1},
		{"target_id": "a", "hit_max": 2, "modifier": -1},
	]
	assert_eq(FireOrdersModel.default_marine_target(rows), "a")
	assert_eq(FireOrdersModel.default_marine_target([{"target_id": "z", "hit_max": 0, "modifier": 2}]), "",
		"a shot that cannot hit is not chosen")


# --- No-shot reasons -------------------------------------------------------------------------------

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


func test_no_shot_words_map_calculator_reasons_to_plain_words() -> void:
	var arc := "target is not in that broadside's arc"
	assert_eq(FireOrdersModel.no_shot_words([arc, arc]), "out of both broadside arcs")
	assert_eq(FireOrdersModel.no_shot_words([arc, "target is out of range (16 hexes, maximum 15)"]), "out of range")
	assert_eq(FireOrdersModel.no_shot_words(["no line of sight to target", arc]), "line of sight blocked")
	assert_eq(FireOrdersModel.no_shot_words(["no sailor sections able to fire", "no sailor sections able to fire"]),
		"no crew to serve the guns")
	assert_eq(FireOrdersModel.no_shot_words(["a struck ship cannot fire or be fired on"]), "struck")
	assert_eq(FireOrdersModel.no_shot_words(["no gunnery factor at this range"]), "out of range")
	assert_eq(FireOrdersModel.no_shot_words([]), "no enemy afloat")


func test_no_shot_words_name_the_blocking_friend() -> void:
	# 7.B.10: the calculator's "Blocked by friendly ship <name>" is shown as it is, even when the
	# name holds a word the other reasons are matched by.
	var arc := "target is not in that broadside's arc"
	assert_eq(FireOrdersModel.no_shot_words([arc, "Blocked by friendly ship Orange"]),
		"Blocked by friendly ship Orange")
	assert_eq(FireOrdersModel.no_shot_words(["Blocked by friendly ship Arcturus", arc]),
		"Blocked by friendly ship Arcturus")


func test_ship_no_shot_reason_previews_against_the_nearest_enemy() -> void:
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var far := _state("f", "Far", 1, Vector2i(9, 0))
	var near := _state("n", "Near", 1, Vector2i(3, 0))
	var calc := FakeCalculator.new()
	calc.reasons = {ShipState.PORT: "target is not in the port arc",
		ShipState.STARBOARD: "target is out of range (16 hexes, maximum 15)"}
	var grid := HexGrid.new(1.0)
	assert_eq(FireOrdersModel.nearest_enemy(own, [own, far, near], grid), near)
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own, far, near], calc, grid), "out of range")


func test_nearest_enemy_measures_footprint_to_footprint() -> void:
	# Own bow (0,0) facing E, stern (-1,0). "b" has the nearer bow (3 hexes) but its closest hex is 3
	# away; "a" points away (bow (-4,0) facing W, stern (-3,0)): bow 4 hexes off, closest hex 2.
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var a := _state("a", "Astern", 1, Vector2i(-4, 0))
	a.facing = 3
	var b := _state("b", "Ahead", 1, Vector2i(3, 0))
	b.facing = 3
	var grid := HexGrid.new(1.0)
	assert_eq(FireOrdersModel.nearest_enemy(own, [own, b, a], grid), a)


func test_ship_no_shot_reason_for_struck_ships_and_no_enemy() -> void:
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var calc := FakeCalculator.new()
	var grid := HexGrid.new(1.0)
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own], calc, grid), "no enemy afloat")
	own.status = ShipState.Status.STRUCK
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own], calc, grid), "struck")


func test_destroyed_ship_has_no_shot_and_is_no_enemy() -> void:
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var wreck := _state("w", "Wreck", 1, Vector2i(3, 0))
	var grid := HexGrid.new(1.0)
	wreck.status = ShipState.Status.DESTROYED
	assert_null(FireOrdersModel.nearest_enemy(own, [own, wreck], grid), "a wreck is not an enemy afloat")
	own.status = ShipState.Status.DESTROYED
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own], FakeCalculator.new(), grid), "destroyed")
	assert_eq(FireOrdersModel.no_shot_words(["a destroyed ship cannot fire or be fired on"]), "destroyed")


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
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own, foe], calc, grid), "no crew to serve the guns")
	calc.reasons["1:bow"] = "target is out of range (16 hexes, maximum 15)"
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own, foe], calc, grid), "out of range")


## The shared fallback behind ship_no_shot_reason and side_reason: a full broadside that "needs
## both" takes the bearing battery's own reason, skipping arc and line-of-sight refusals.
func test_broadside_reason_falls_back_to_the_bearing_battery() -> void:
	var arc := "target is not in that broadside's arc"
	var calc := FakeCalculator.new()
	calc.reasons = {"1:full": "only the stern battery bears: a full broadside needs both",
		"1:bow": arc, "1:stern": "no sailor sections able to fire"}
	assert_eq(FireOrdersModel._broadside_reason(calc, "o", 1, "f"), "no sailor sections able to fire")
	calc.reasons["1:stern"] = "no line of sight to target"
	assert_eq(FireOrdersModel._broadside_reason(calc, "o", 1, "f"),
		"only the stern battery bears: a full broadside needs both", "no better reason: the full one stays")
	calc.reasons = {1: "target is out of range (16 hexes, maximum 15)"}
	assert_eq(FireOrdersModel._broadside_reason(calc, "o", 1, "f"), "target is out of range (16 hexes, maximum 15)")


func test_ship_no_shot_reason_also_previews_the_chasers() -> void:
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var foe := _state("f", "Foe", 1, Vector2i(3, 0))
	var arc := "target is not in that broadside's arc"
	var calc := FakeCalculator.new()
	calc.reasons = {ShipState.PORT: arc, ShipState.STARBOARD: arc,
		"2:chase": "target is out of range (8 hexes, maximum 7)",
		"3:chase": "target is not in the stern chaser's arc"}
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own, foe], calc, HexGrid.new(1.0)), "out of range")
	calc.reasons["2:chase"] = "target is not in the bow chaser's arc"
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own, foe], calc, HexGrid.new(1.0)),
		"out of both broadside arcs")


func test_no_shot_words_for_surrender() -> void:
	assert_eq(FireOrdersModel.no_shot_words(["a ship that is surrendering does not fire (14.B)"]), "surrendering")
	var own := _state("o", "HMS Phoebe", 0, Vector2i(0, 0))
	var grid := HexGrid.new(1.0)
	own.surrender_ordered = true
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own], null, grid), "surrendering")
	own.surrender_ordered = false
	own.status = ShipState.Status.STRUCK
	own.surrendered = true
	assert_eq(FireOrdersModel.ship_no_shot_reason(own, [own], null, grid), "surrendered")


# --- Batteries and row choices ------------------------------------------------------------------

func test_options_offer_full_only_when_both_bear() -> void:
	var both: Array = [_shot(0, "a", "stern"), _shot(0, "a", "full"), _shot(0, "a", "bow")]
	assert_eq(FireOrdersModel.battery_options(both), ["full", "bow", "stern"] as Array[String],
		"both bear: full first, and each half broadside gets its own row")
	assert_eq(FireOrdersModel.battery_options([_shot(0, "a", "bow")]), ["bow"] as Array[String])
	assert_eq(FireOrdersModel.battery_options([_shot(0, "a", "stern")]), ["stern"] as Array[String])
	var refused := _shot(0, "a", "full")
	refused.can_fire = false
	assert_eq(FireOrdersModel.battery_options([refused, _shot(0, "a", "stern")]), ["stern"] as Array[String])
	assert_eq(FireOrdersModel.battery_options([]), [] as Array[String])


func test_battery_rows_within_a_target_go_full_bow_stern() -> void:
	var options := FireOrdersModel.battery_options([_shot(1, "t", "stern"), _shot(1, "t", "full"), _shot(1, "t", "bow")])
	assert_eq(options, ["full", "bow", "stern"] as Array[String])


func test_options_by_target_groups_shots_per_side_and_target() -> void:
	var shots: Array[GunneryTypes.ShotPreview] = [_shot(0, "a", "full"), _shot(0, "a", "bow"),
		_shot(0, "a", "stern"), _shot(1, "b", "stern")]
	var by: Dictionary = FireOrdersModel.options_by_target(shots)
	assert_eq(by.keys().size(), 2)
	assert_eq(by[0]["a"].keys(), ["full", "bow", "stern"])
	assert_eq(by[1]["b"].keys(), ["stern"])


func test_options_group_chasers_by_side() -> void:
	var shots: Array[GunneryTypes.ShotPreview] = [
		_shot(GunneryTypes.CHASE_BOW, "a", GunneryTypes.BATTERY_CHASE),
		_shot(GunneryTypes.CHASE_STERN, "b", GunneryTypes.BATTERY_CHASE)]
	var by_side := FireOrdersModel.options_by_target(shots)
	assert_true(by_side.has(GunneryTypes.CHASE_BOW))
	assert_true(by_side.has(GunneryTypes.CHASE_STERN))
	var previews := [_shot(1, "a", "chase"), _shot(1, "a", "bow"), _shot(1, "a", "full")]
	assert_eq(FireOrdersModel.battery_options(previews), ["full", "bow", "chase"] as Array[String])


func test_choose_split_between_two_double_covered_targets() -> void:
	# A and B are both covered by both batteries: every row is explicit.
	var s: Dictionary = FireOrdersModel.choose_battery({"bow": "", "stern": ""}, "a", "full")
	assert_eq(s, {"bow": "a", "stern": "a"})
	s = FireOrdersModel.choose_battery(s, "b", "bow")
	assert_eq(s, {"bow": "b", "stern": "a"}, "bow at B, stern stays at A: a split side")
	s = FireOrdersModel.choose_battery({"bow": "", "stern": ""}, "a", "bow")
	s = FireOrdersModel.choose_battery(s, "b", "stern")
	assert_eq(s, {"bow": "a", "stern": "b"}, "bow at A, stern at B")
	s = FireOrdersModel.choose_battery(s, "b", "full")
	assert_eq(s, {"bow": "b", "stern": "b"}, "full at B moves both batteries")


func test_choose_half_battery_at_double_covered_target() -> void:
	var s: Dictionary = FireOrdersModel.choose_battery({"bow": "a", "stern": "a"}, "a", "bow")
	assert_eq(s, {"bow": "a", "stern": ""}, "bow only at A, stern held: the full broadside becomes the half")
	assert_true(FireOrdersModel.row_chosen(s["bow"], s["stern"], "a", "bow"))
	assert_false(FireOrdersModel.row_chosen(s["bow"], s["stern"], "a", "full"))
	s = FireOrdersModel.choose_battery(s, "a", "stern")
	assert_eq(s, {"bow": "", "stern": "a"}, "stern only")
	s = FireOrdersModel.choose_battery(s, "a", "stern")
	assert_eq(s, {"bow": "", "stern": ""}, "picking the chosen row again holds it")
	assert_eq(FireOrdersModel.choose_battery({"bow": "a", "stern": "b"}, "", ""), {"bow": "", "stern": ""})


func test_choose_and_row_chosen_for_chaser() -> void:
	var state := FireOrdersModel.choose_battery({"bow": "", "stern": ""}, "a", "chase")
	assert_eq(state, {"bow": "a", "stern": ""})
	assert_eq(FireOrdersModel.choose_battery(state, "a", "chase"), {"bow": "", "stern": ""})
	assert_true(FireOrdersModel.row_chosen("a", "", "a", "chase"))
	assert_false(FireOrdersModel.row_chosen("", "", "a", "chase"))


func test_row_key_separates_batteries_of_one_target() -> void:
	assert_eq(FireOrdersModel.row_key("a", "bow"), "a|bow")
	assert_ne(FireOrdersModel.row_key("a", "bow"), FireOrdersModel.row_key("a", "stern"))
	assert_eq(FireOrdersModel.row_key("", ""), "")


func test_order_key_names_ship_side_and_row() -> void:
	assert_eq(FireOrdersModel.order_key("firer", 1, "a", "bow"), "firer|1|a|bow")


# --- Orders for sides ---------------------------------------------------------------------------

# 7.C.14: the firer may reduce the MGN voluntarily; the model keeps it per order (row).
func test_orders_carry_row_reduction() -> void:
	var side := {"bow": "t1", "stern": "t1", "want_high": false, "want_dismantling": false}
	var state := FireOrdersModel.with_reduction(side, "t1", "full", 3)
	var orders := FireOrdersModel.orders_for_sides("own", {ShipState.STARBOARD: state}, {"t1": 3})
	assert_eq(orders.size(), 1)
	assert_eq(orders[0].mgn_reduction, 3)


func test_split_side_reduces_one_shot_only() -> void:
	var side := {"bow": "t1", "stern": "t2", "want_high": false, "want_dismantling": false}
	var state := FireOrdersModel.with_reduction(side, "t2", "stern", 2)
	var orders := FireOrdersModel.orders_for_sides("own", {ShipState.STARBOARD: state}, {"t1": 3, "t2": 4})
	assert_eq(orders.size(), 2)
	for o in orders:
		assert_eq(o.mgn_reduction, 2 if o.target_id == "t2" else 0, "only the t2 shot is reduced")


func test_reduction_clamped_at_zero() -> void:
	var state := FireOrdersModel.with_reduction({"bow": "t1", "stern": ""}, "t1", "bow", -4)
	assert_eq(FireOrdersModel.reduction_of(state, "t1", "bow"), 0)
	state = FireOrdersModel.with_reduction(state, "t1", "bow", 2)
	state = FireOrdersModel.with_reduction(state, "t1", "bow", FireOrdersModel.reduction_of(state, "t1", "bow") - 5)
	assert_eq(FireOrdersModel.reduction_of(state, "t1", "bow"), 0)


func test_orders_for_chasers() -> void:
	var sides := {
		ShipState.STARBOARD: {"bow": "x", "stern": "x", "want_high": false, "want_dismantling": false, "reductions": {}},
		GunneryTypes.CHASE_BOW: {"bow": "y", "stern": "", "want_high": false, "want_dismantling": true, "reductions": {}},
	}
	var orders := FireOrdersModel.orders_for_sides("own", sides, {"x": 3, "y": 2})
	assert_eq(orders.size(), 2)
	assert_eq(orders[0].side, ShipState.STARBOARD)
	assert_eq(orders[0].battery, "full")
	assert_eq(orders[1].side, GunneryTypes.CHASE_BOW)
	assert_eq(orders[1].battery, "chase")
	assert_eq(orders[1].target_id, "y")
	assert_eq(orders[1].ammo, "round", "a chaser fires round shot only")


# --- Fixtures on GameState --------------------------------------------------------------------------

func after_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


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


func _environment() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env


## Two enemies on the starboard side, each covered by both batteries (searched, not hand-placed).
func _double_covered_setup(calc: GunneryCalculator) -> Array[String]:
	_environment()
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


func test_order_sets_pass_validate_orders() -> void:
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
			var chosen: Dictionary = FireOrdersModel.choose_battery(sides[1], click[0], click[1])
			sides[1]["bow"] = chosen["bow"]
			sides[1]["stern"] = chosen["stern"]
			sides = FireRules.limit_targets(sides, 1)
		var orders: Array[GunneryTypes.FireOrder] = FireOrdersModel.orders_for_sides("firer", sides, ranges)
		assert_false(orders.is_empty(), "%s fires" % [clicks])
		assert_eq(calc.validate_orders(0, orders), "", "validate_orders accepts %s" % [clicks])


# --- The model over GameState -------------------------------------------------------------------------

func _model_with_two_targets() -> Array:
	var ids := _double_covered_setup(GameState.gunnery_calculator)
	assert_eq(ids.size(), 2, "fixture: two double-covered targets")
	var model := FireOrdersModel.new()
	model.setup(["firer"])
	return [model, ids]


## A firer with a foe alongside its bow: a bow chaser shot and a marine shot.
func _alongside_setup() -> void:
	_environment()
	var firer := _armed("firer", 0, Vector2i.ZERO, 0)
	firer.marine_count = 7
	_armed("foe", 1, Vector2i(2, 0), 0)  # stern (1,0) alongside the firer's bow


func test_setup_lists_ships_and_their_targets() -> void:
	var setup := _model_with_two_targets()
	var model: FireOrdersModel = setup[0]
	var ids: Array = setup[1]
	assert_eq(model.ships_with_shots(), ["firer"] as Array[String])
	assert_eq(model.no_shot_reason("firer"), "", "a ship with a shot has no reason")
	var bearing: Dictionary = model.sides_bearing("firer")
	assert_true(bearing.has(ShipState.STARBOARD))
	var sorted_ids: Array = bearing[ShipState.STARBOARD].duplicate()
	sorted_ids.sort()
	var expected: Array = ids.duplicate()
	expected.sort()
	assert_eq(sorted_ids, expected)
	var rows: Array[Dictionary] = model.targets("firer", ShipState.STARBOARD)
	assert_eq(rows.size(), 2)
	for row in rows:
		assert_eq(row["batteries"], ["full", "bow", "stern"] as Array[String])
		assert_eq((row["preview"] as GunneryTypes.ShotPreview).order.battery, "full")
		assert_eq(int(row["range"]), (row["preview"] as GunneryTypes.ShotPreview).range_hexes)
	assert_eq(model.orders().size(), 1, "the best shot is chosen by default")


func test_no_shot_ship_gets_the_reason() -> void:
	_environment()
	_armed("firer", 0, Vector2i.ZERO, 0)
	_armed("far", 1, Vector2i(0, 30), 0)
	var model := FireOrdersModel.new()
	model.setup(["firer"])
	assert_eq(model.ships_with_shots(), [] as Array[String])
	assert_eq(model.no_shot_ships(), ["firer"] as Array[String])
	assert_eq(model.no_shot_reason("firer"), FireOrdersModel.ship_no_shot_reason(GameState.get_ship("firer"),
		GameState.get_all_ships(), GameState.gunnery_calculator, GameState.fire_geometry.hex_grid))
	assert_ne(model.no_shot_reason("firer"), "")


func test_marine_only_ship_is_listed_with_its_marine_target() -> void:
	_alongside_setup()
	var firer := GameState.get_ship("firer")
	firer.plotted_sections = [0, 1, 2, 3] as Array[int]
	var model := FireOrdersModel.new()
	model.setup(["firer"])
	assert_eq(model.ships_with_shots(), ["firer"] as Array[String], "listed for its marines")
	assert_true(model.sides_bearing("firer").is_empty(), "no gun bears")
	assert_ne(model.no_shot_reason("firer"), "", "the guns' reason is kept")
	var marine_rows := model.marine_targets("firer")
	assert_eq(marine_rows.size(), 1)
	assert_eq(marine_rows[0]["target_id"], "foe")
	assert_eq(model.marine_orders(), [{"ship_id": "firer", "target_id": "foe"}])
	assert_eq(GameState.marine_fire_resolver.validate_orders(0, model.marine_orders()), "",
		"the marine orders pass the server's validation")
	assert_true(model.select_marine_target("firer", ""))
	assert_eq(model.marine_orders(), [])
	assert_false(model.select_marine_target("firer", "nobody"), "not a marine target")


func test_mutators_emit_changed() -> void:
	var setup := _model_with_two_targets()
	var model: FireOrdersModel = setup[0]
	var ids: Array = setup[1]
	watch_signals(model)
	model.choose("firer", ShipState.STARBOARD, ids[0], "bow")
	model.set_high("firer", ShipState.STARBOARD, true)
	model.set_dismantling("firer", ShipState.STARBOARD, true)
	model.set_reduction("firer", ShipState.STARBOARD, ids[0], "bow", 2)
	model.clear_side("firer", ShipState.STARBOARD)
	model.hold_fire("firer")
	assert_signal_emit_count(model, "changed", 6)
	model.choose("firer", ShipState.STARBOARD, ids[0], "chase")
	model.choose("nobody", ShipState.STARBOARD, ids[0], "bow")
	assert_signal_emit_count(model, "changed", 6, "a refused choice changes nothing")


func test_hold_fire_clears_every_order_of_the_ship() -> void:
	_alongside_setup()
	var model := FireOrdersModel.new()
	model.setup(["firer"])
	assert_false(model.orders().is_empty(), "the chaser fires by default")
	assert_false(model.marine_orders().is_empty())
	model.hold_fire("firer")
	assert_eq(model.orders(), [] as Array[GunneryTypes.FireOrder])
	assert_eq(model.marine_orders(), [])
	assert_eq(model.ship_orders("firer"), [])


func test_set_reduction_clamps_and_reaches_the_order() -> void:
	var setup := _model_with_two_targets()
	var model: FireOrdersModel = setup[0]
	var ids: Array = setup[1]
	model.clear_side("firer", ShipState.STARBOARD)
	model.choose("firer", ShipState.STARBOARD, ids[0], "full")
	assert_eq(model.target_ids("firer"), [ids[0]] as Array[String])
	model.set_reduction("firer", ShipState.STARBOARD, ids[0], "full", 3)
	assert_eq(model.reduction("firer", ShipState.STARBOARD, ids[0], "full"), 3)
	assert_eq(model.orders()[0].mgn_reduction, 3)
	model.set_reduction("firer", ShipState.STARBOARD, ids[0], "full", -2)
	assert_eq(model.orders()[0].mgn_reduction, 0, "clamped at zero")


func test_ship_orders_and_batteries() -> void:
	var setup := _model_with_two_targets()
	var model: FireOrdersModel = setup[0]
	var ids: Array = setup[1]
	model.clear_side("firer", ShipState.STARBOARD)
	model.choose("firer", ShipState.STARBOARD, ids[0], "bow")
	model.choose("firer", ShipState.STARBOARD, ids[1], "stern")
	assert_eq(model.batteries("firer", ShipState.STARBOARD), ["bow", "stern"] as Array[String], "split side")
	assert_eq(model.ship_orders("firer").size(), 2)
	assert_eq(model.target_ids("firer").size(), 2)
	assert_true(model.any_ship_fires_both())
	assert_true(model.targets_changed())


## One order dictionary as player_submit_fire_orders takes it (FireOrder.to_dict).
func _o(side: int, target_id: String, battery: String, aim := "low", ammo := "round", reduction := 0) -> Dictionary:
	return {"ship_id": "firer", "side": side, "target_id": target_id, "battery": battery, "aim": aim,
		"ammo": ammo, "mgn_reduction": reduction}


## Drives a model through `steps`, each [choice..., expected order_dicts, expected marine_orders].
func _drive(model: FireOrdersModel, steps: Array) -> void:
	for step: Array in steps:
		match str(step[0]):
			"choose":
				model.choose("firer", step[1], step[2], step[3])
			"high":
				model.set_high("firer", step[1], step[2])
			"dismantling":
				model.set_dismantling("firer", step[1], step[2])
			"reduce":
				model.set_reduction("firer", step[1], step[2], step[3],
					model.reduction("firer", step[1], step[2], step[3]) + int(step[4]))
			"marines":
				model.select_marine_target("firer", step[1])
		assert_eq(model.order_dicts(), step[-2], "orders after %s" % [step.slice(0, -2)])
		assert_eq(model.marine_orders(), step[-1], "marine orders after %s" % [step.slice(0, -2)])


## Review Focus 1: the orders sent for a run of choices are exactly those the fire declaration
## panel sent before it was retired (recorded from the panel-equality test of Task 1, which drove
## the panel and the model side by side): split sides, two targets, reductions, high, dismantling,
## re-picking a chosen row, hold, the preferred battery, a chaser and marines.
func test_orders_follow_the_choices() -> void:
	var ids := _double_covered_setup(GameState.gunnery_calculator)
	assert_eq(ids, ["t0", "t1"] as Array[String], "fixture: two double-covered targets")
	if ids.size() < 2:
		return
	var sb := ShipState.STARBOARD
	var model := FireOrdersModel.new()
	model.setup(["firer"])
	assert_eq(model.order_dicts(), [_o(sb, "t0", "full")], "the best shot by default")
	_drive(model, [
		["choose", sb, "t0", "full", [], []],          # the chosen row again holds it
		["choose", sb, "t1", "bow", [_o(sb, "t1", "bow")], []],
		["reduce", sb, "t1", "bow", 2, [_o(sb, "t1", "bow", "low", "round", 2)], []],
		["reduce", sb, "t1", "bow", -5, [_o(sb, "t1", "bow")], []],
		["choose", sb, "t0", "stern", [_o(sb, "t1", "bow"), _o(sb, "t0", "stern")], []],  # split: two targets
		["high", sb, true, [_o(sb, "t1", "bow", "high"), _o(sb, "t0", "stern", "high")], []],
		["dismantling", sb, true, [_o(sb, "t1", "bow", "high", "dismantling"),
			_o(sb, "t0", "stern", "high", "dismantling")], []],
		["choose", sb, "t0", "stern", [_o(sb, "t1", "bow", "high", "dismantling")], []],
		["choose", sb, "", "", [], []],
		["choose", sb, "t1", "", [_o(sb, "t1", "full", "high", "dismantling")], []],  # the preferred battery
		["reduce", sb, "t1", "full", 1, [_o(sb, "t1", "full", "high", "dismantling", 1)], []],
	])
	# Chasers and marines: a foe alongside the bow.
	_alongside_setup()
	var model2 := FireOrdersModel.new()
	model2.setup(["firer"])
	var bow := GunneryTypes.CHASE_BOW
	var chase := _o(bow, "foe", "chase")
	var muskets := [{"ship_id": "firer", "target_id": "foe"}]
	assert_eq(model2.sides_bearing("firer").keys(), [bow], "fixture: only the bow chaser bears")
	assert_eq(model2.order_dicts(), [chase], "the best shot by default")
	assert_eq(model2.marine_orders(), muskets, "the marine shot by default")
	_drive(model2, [
		["marines", "", [chase], []],
		["marines", "foe", [chase], muskets],
		["choose", bow, "", "", [], muskets],
		["choose", bow, "foe", "", [chase], muskets],
		["high", bow, true, [_o(bow, "foe", "chase", "high")], muskets],
		["dismantling", bow, true, [_o(bow, "foe", "chase", "high")], muskets],  # chasers: round shot only
	])


func test_order_previews_match_preview_orders() -> void:
	var setup := _model_with_two_targets()
	var model: FireOrdersModel = setup[0]
	var ids: Array = setup[1]
	model.clear_side("firer", ShipState.STARBOARD)
	model.choose("firer", ShipState.STARBOARD, ids[0], "bow")
	model.choose("firer", ShipState.STARBOARD, ids[1], "stern")
	var orders := model.orders()
	var expected := GameState.gunnery_calculator.preview_orders(orders)
	var previews := model.order_previews()
	assert_eq(previews.size(), orders.size())
	for p in expected:
		var key := FireOrdersModel.order_key(p.order.ship_id, p.order.side, p.order.target_id, p.order.battery)
		assert_true(previews.has(key), key)
		var got: GunneryTypes.ShotPreview = previews[key]
		assert_eq(got.mgn, p.mgn, "%s: the number the resolver rolls" % key)
		assert_eq(got.modifiers, p.modifiers)
		var names: Array = got.modifiers.map(func(m): return str(m.get("name", "")))
		assert_true(names.has("two_targets"), "two targets: −12 on each shot")
