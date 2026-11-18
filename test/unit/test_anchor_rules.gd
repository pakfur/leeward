extends GutTest
## AnchorRules (13.A-F, anchoring spec §1, §3, §7): legality, permission and geometry.
## Wind 0 unless stated, so downwind is 3 (W).

const TEN := {"map_bounds": {"width": 10, "height": 10}}


func _ship(hex: Vector2i = Vector2i.ZERO, facing: int = 0) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({
		"ship_id": "a", "player_id": 0, "ship_name": "a", "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
		"point_costs": {"B4": 100},
	})
	s.hex_position = hex
	s.facing = facing
	s.sail_state = "FS"
	s.crew_quality = "B"
	s.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	s.hull_current_hp = [5, 5, 5, 6] as Array[int]
	s.crew_count = [3, 3, 3, 3] as Array[int]
	s.marine_count = 2
	return s


func _anchored(end: String = "bow", springs: bool = false, veered: int = 0) -> ShipState:
	var s := _ship(Vector2i(-1, 0), 0)
	s.anchor = {"hex": Vector2i.ZERO, "end": end, "springs": springs, "cable": 1 + veered,
		"veered": veered, "swing_dir": 0, "wind_dir": 0, "turn": 0}
	return s


func _ctx(extra: Dictionary = {}) -> Dictionary:
	var c := {"wind_speed": 3, "anchoring_here": true, "plotted_mps": 0, "final": false}
	c.merge(extra, true)
	return c


func _refusal(s: ShipState, code: String, params: Dictionary = {}, ctx: Dictionary = {},
		plan_codes: Array = []) -> String:
	return AnchorRules.refusal(s, code, params, _ctx(ctx), plan_codes)


func test_proper_facing() -> void:
	assert_eq(AnchorRules.proper_facing("bow", 0), 0)
	assert_eq(AnchorRules.proper_facing("stern", 0), 3)
	assert_eq(AnchorRules.proper_facing("bow", 4), 4)
	assert_eq(AnchorRules.downwind(4), 1)


func test_footprint_bow_anchor() -> void:
	assert_eq(AnchorRules.footprint(Vector2i(0, 0), "bow", 1, 0, 0), [Vector2i(-1, 0), Vector2i(-2, 0)] as Array[Vector2i])
	assert_eq(AnchorRules.footprint(Vector2i(0, 0), "bow", 2, 0, 0), [Vector2i(-2, 0), Vector2i(-3, 0)] as Array[Vector2i])
	assert_eq(AnchorRules.footprint(Vector2i(0, 0), "bow", 0, 0, 0), [Vector2i(0, 0), Vector2i(-1, 0)] as Array[Vector2i])


func test_footprint_stern_anchor() -> void:
	assert_eq(AnchorRules.footprint(Vector2i(1, 0), "stern", 1, 3, 0), [Vector2i(-1, 0), Vector2i(0, 0)] as Array[Vector2i])


func test_footprint_oblique_after_wind_shift() -> void:
	# 13.C.6: the wind shifts to 1 before the ship has swung: the end lies downwind of the anchor
	assert_eq(AnchorRules.footprint(Vector2i(0, 0), "bow", 1, 1, 1), [Vector2i(0, -1), Vector2i(0, -2)] as Array[Vector2i])


func test_drop_hex() -> void:
	var s := _ship(Vector2i(2, 1), 0)
	assert_eq(AnchorRules.drop_hex(s), Vector2i(2, 1))
	s.anchor_ready = "bow"
	assert_eq(AnchorRules.drop_hex(s), Vector2i(2, 1))
	s.anchor_ready = "stern"
	assert_eq(AnchorRules.drop_hex(s), Vector2i(1, 1))


func test_spring_turn_bow_pivots_on_bow() -> void:
	var s := _anchored("bow", true)
	var port := AnchorRules.spring_turn(s, -1)
	assert_eq(port["facing"], 5)
	assert_eq(port["hexes"], [Vector2i(-1, 0), Vector2i(-2, 1)] as Array[Vector2i])
	var stbd := AnchorRules.spring_turn(s, 1)
	assert_eq(stbd["facing"], 1)
	assert_eq(stbd["hexes"], [Vector2i(-1, 0), Vector2i(-1, -1)] as Array[Vector2i])


func test_spring_turn_stern_pivots_on_stern() -> void:
	# 13.D.2: anchored by the stern, the bow swings round the stern
	var s := _anchored("stern", true)
	s.facing = 3
	assert_eq(s.stern_hex(), Vector2i(0, 0))
	var stbd := AnchorRules.spring_turn(s, 1)
	assert_eq(stbd["facing"], 4)
	assert_eq(stbd["hexes"], [Vector2i(0, -1), Vector2i(0, 0)] as Array[Vector2i])
	var port := AnchorRules.spring_turn(s, -1)
	assert_eq(port["facing"], 2)
	assert_eq(port["hexes"], [Vector2i(-1, 1), Vector2i(0, 0)] as Array[Vector2i])


func test_swing_step() -> void:
	assert_eq(AnchorRules.swing_step(1, 0, 0, 0), {"facing": 0, "swing_dir": 0})
	assert_eq(AnchorRules.swing_step(0, 0, 0, 0), {"facing": 0, "swing_dir": 0})
	assert_eq(AnchorRules.swing_step(2, 0, 0, 0), {"facing": 1, "swing_dir": -1})
	assert_eq(AnchorRules.swing_step(3, 0, 0, 2), {"facing": 2, "swing_dir": -1})
	assert_eq(AnchorRules.swing_step(3, 0, 0, 5), {"facing": 4, "swing_dir": 1})
	# already turning to starboard: keeps on that way (13.C.4)
	assert_eq(AnchorRules.swing_step(2, 0, 1, 0), {"facing": 3, "swing_dir": 1})
	assert_true(AnchorRules.needs_swing_roll(3, 0, 0))
	assert_false(AnchorRules.needs_swing_roll(3, 0, 1))
	assert_false(AnchorRules.needs_swing_roll(2, 0, 0))


func test_permitted() -> void:
	assert_false(AnchorRules.permitted({}, Vector2i.ZERO))
	assert_false(AnchorRules.permitted({"anchoring": false}, Vector2i.ZERO))
	assert_true(AnchorRules.permitted({"anchoring": true}, Vector2i.ZERO))
	var rows := {"anchoring": {"rows": [-2, 2]}}
	assert_true(AnchorRules.permitted(rows, Vector2i(0, 2)))
	assert_false(AnchorRules.permitted(rows, Vector2i(0, 3)))
	var areas := TEN.duplicate(true)
	areas["terrain"] = {"shallow": [{"name": "A", "base": 1, "hexes": [[2, 0]]}]}
	areas["anchoring"] = {"areas": ["A"]}
	assert_true(AnchorRules.permitted(areas, Vector2i(2, 0)))
	assert_false(AnchorRules.permitted(areas, Vector2i(3, 0)))
	assert_false(AnchorRules.permitted({"anchoring": 3}, Vector2i.ZERO))


func _valid_scenario() -> Dictionary:
	var s := TEN.duplicate(true)
	s["terrain"] = {"shallow": [{"name": "A", "base": 1, "hexes": [[2, 0]]}]}
	s["anchoring"] = {"rows": [-2, 2], "areas": ["A"]}
	s["ships"] = [{"id": "a", "anchor": {"end": "bow", "springs": true, "cable": 2, "hex": [1, 0]}},
		{"id": "b"}]
	return s


func test_scenario_errors() -> void:
	assert_eq(AnchorRules.scenario_errors(_valid_scenario()), [] as Array[String])
	assert_eq(AnchorRules.scenario_errors({"anchoring": true}), [] as Array[String])
	assert_eq(AnchorRules.scenario_errors({}), [] as Array[String])
	var cases := [
		{"anchoring": 3},
		{"anchoring": {"rows": [3, 1]}},
		{"anchoring": {"areas": ["Q"]}},
		{"anchoring": {}},
		{"ships": [{"id": "a", "anchor": {"end": "mast"}}]},
		{"ships": [{"id": "a", "anchor": {"end": "bow", "cable": 5}}]},
		{"map_bounds": {"width": 10, "height": 10},
			"ships": [{"id": "a", "anchor": {"end": "bow", "hex": [20, 0]}}]},
	]
	for c in cases:
		var errors := AnchorRules.scenario_errors(c)
		assert_eq(errors.size(), 1, str(c))
		if errors.size() == 1:
			assert_true(errors[0].begins_with("Anchoring: "), errors[0])


func test_refusal_preparation() -> void:
	var s := _ship()
	assert_eq(_refusal(s, "PBA"), "")
	s.anchor_ready = "bow"
	assert_eq(_refusal(s, "PBA"), "An anchor is already ready (13.B.3).")
	assert_eq(_refusal(s, "PSA"), "An anchor is already ready (13.B.3).")
	assert_eq(_refusal(s, "PBS"), "")
	assert_eq(_refusal(s, "PSS"), "Prepare the stern anchor first (13.B.3).")
	var t := _ship()
	t.crew_tasks.append({"seq": 1, "code": "PBA", "params": {}, "sections": [0], "ended": ""})
	assert_eq(_refusal(t, "PSA"), "Only one anchor at a time (13.B.3).")
	assert_eq(_refusal(_ship(), "PSA", {}, {}, ["PBA"]), "Only one anchor at a time (13.B.3).")
	assert_eq(_refusal(_ship(), "PBA", {}, {}, ["PBA"]), "One section is enough for PBA.")
	var u := _ship()
	u.anchorings_used = 2
	assert_eq(_refusal(u, "PBA"), "Anchored twice already (13.A.5).")
	assert_eq(_refusal(_anchored(), "PBA"), "Already anchored: cut the cable first (13.F).")


func test_refusal_anchor() -> void:
	var s := _ship()
	assert_eq(_refusal(s, "A"), "Prepare an anchor first (13.B.1).")
	s.anchor_ready = "bow"
	assert_eq(_refusal(s, "A", {}, {"anchoring_here": false}),
		"The scenario does not allow anchoring here (Scenario Book V.B).")
	assert_eq(_refusal(s, "A", {}, {"plotted_mps": 2, "final": false}), "")
	assert_eq(_refusal(s, "A", {}, {"plotted_mps": 2, "final": true}),
		"MPs plotted: the anchoring is erased (13.C.1).")
	assert_eq(_refusal(_anchored(), "A"), "Already anchored: cut the cable first (13.F).")


func test_refusal_while_anchored() -> void:
	var s := _anchored("bow", true, 3)
	assert_eq(_refusal(s, "VO"), "Three VOs already (13.E.1c).")
	assert_eq(_refusal(s, "VI"), "")
	assert_eq(_refusal(s, "HS", {"turn": "port"}), "")
	assert_eq(_refusal(s, "HS", {"turn": "port"}, {"wind_speed": 0}), "No wind: springs cannot be used (13.E.3).")
	assert_eq(_refusal(s, "HS"), "Handle springs needs a turn to port or starboard (13.D.2).")
	assert_eq(_refusal(s, "AX", {}, {}, ["VO"]), "No turn or veering on the g-t the cable is cut (13.F.2).")
	assert_eq(_refusal(s, "AX"), "")
	var v := _anchored("bow", true, 1)
	assert_eq(_refusal(v, "VO", {}, {}, ["HS"]), "Not on a g-t it turns (13.E.1d).")
	assert_eq(_refusal(v, "VO", {}, {"wind_speed": 0}), "No wind: a ship cannot veer out (13.E.3).")
	assert_eq(_refusal(v, "VO", {}, {}, ["VI"]), "Veer out or veer in, not both.")
	assert_eq(_refusal(v, "VI", {}, {}, ["HS"]), "Not on a g-t it turns (13.E.2).")
	assert_eq(_refusal(v, "HS", {"turn": "starboard"}, {}, ["AX"]),
		"No turn or veering on the g-t the cable is cut (13.F.2).")
	assert_eq(_refusal(_anchored(), "VI"), "Nothing to veer in (13.E.2).")
	assert_eq(_refusal(_anchored(), "HS", {"turn": "port"}), "Springs are not rigged (13.D).")
	var f := _anchored("bow", true, 1)
	f.fouled_with = "b"
	assert_eq(_refusal(f, "HS", {"turn": "port"}), "Fouled or grappled ships cannot turn (13.D.2).")
	assert_eq(_refusal(f, "VO"), "Fouled or grappled: cannot veer out.")
	assert_eq(_refusal(_anchored("bow", true), "PBS"), "The springs are already ready (13.B.4).")
	assert_eq(_refusal(_anchored("bow", false), "PBS"), "")
	assert_eq(_refusal(_anchored("bow", false), "PSS"), "Prepare the stern anchor first (13.B.3).")
	for code in ["AX", "VO", "VI", "HS"]:
		assert_eq(_refusal(_ship(), code, {"turn": "port"}), "Not anchored.", code)


func test_refusal_struck() -> void:
	var s := _anchored("bow", true, 1)
	s.status = ShipState.Status.STRUCK
	for code in AnchorRules.CODES:
		assert_eq(_refusal(s, code), "The crew cannot handle the anchors (struck, or a prize).", code)


func test_is_code() -> void:
	for code in AnchorRules.CODES:
		assert_true(AnchorRules.is_code(code), code)
	assert_false(AnchorRules.is_code("RR"))
	assert_false(AnchorRules.is_code(""))


func test_order_task() -> void:
	var s := _ship()
	assert_eq(AnchorRules.order_task(s, "prepare_bow"), {"code": "PBA", "params": {}})
	assert_eq(AnchorRules.order_task(s, "prepare_stern"), {"code": "PSA", "params": {}})
	assert_eq(AnchorRules.order_task(s, "anchor"), {"code": "A", "params": {}})
	assert_eq(AnchorRules.order_task(s, "cut"), {"code": "AX", "params": {}})
	assert_eq(AnchorRules.order_task(s, "veer_out"), {"code": "VO", "params": {}})
	assert_eq(AnchorRules.order_task(s, "veer_in"), {"code": "VI", "params": {}})
	s.anchor_ready = "stern"
	assert_eq(AnchorRules.order_task(s, "prepare_springs"), {"code": "PSS", "params": {}})
	assert_eq(AnchorRules.order_task(_anchored("bow"), "prepare_springs"), {"code": "PBS", "params": {}})
	assert_eq(AnchorRules.order_task(_anchored("stern"), "prepare_springs"), {"code": "PSS", "params": {}})
	assert_eq(AnchorRules.order_task(s, "turn_port"), {"code": "HS", "params": {"turn": "port"}})
	assert_eq(AnchorRules.order_task(s, "turn_starboard"), {"code": "HS", "params": {"turn": "starboard"}})
	assert_eq(AnchorRules.order_task(s, ""), {})
	assert_eq(AnchorRules.order_task(s, "bogus"), {})


func test_forced_check() -> void:
	var sc := TEN.duplicate(true)
	sc["terrain"] = {"land": [[-3, 0]], "shallow": [{"name": "S", "base": 1, "hexes": [[-1, 0]]}]}
	var old: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(-2, 0)]
	var land := AnchorRules.forced_check(sc, old, [Vector2i(-2, 0), Vector2i(-3, 0)] as Array[Vector2i], {})
	assert_eq(land["result"], "land")
	var edge := AnchorRules.forced_check(sc, old, [Vector2i(-6, 0), Vector2i(-7, 0)] as Array[Vector2i], {})
	assert_eq(edge["result"], "edge")
	var ship := AnchorRules.forced_check(sc, [Vector2i(0, 0), Vector2i(-1, 0)] as Array[Vector2i],
		[Vector2i(-1, 0), Vector2i(-2, 0)] as Array[Vector2i], {Vector2i(-2, 0): "b"})
	assert_eq(ship["result"], "ship")
	assert_eq(ship["blocker"], "b")
	var onto_stern := AnchorRules.forced_check(sc, [Vector2i(0, 0), Vector2i(-1, 0)] as Array[Vector2i],
		[Vector2i(-1, 0), Vector2i(-2, 0)] as Array[Vector2i], {})
	assert_eq(onto_stern["result"], "clear")
	assert_eq(onto_stern["blocker"], "")
	assert_true(onto_stern["shallow_bow"], "the bow enters her old stern hex, in the shallows")
	var kept := AnchorRules.forced_check(sc, [Vector2i(-1, 0), Vector2i(-2, 0)] as Array[Vector2i],
		[Vector2i(-1, 0), Vector2i(-1, -1)] as Array[Vector2i], {})
	assert_eq(kept["result"], "clear")
	assert_false(kept["shallow_bow"], "the bow stays in her hex: a swing rolls no depth")
	var entered := AnchorRules.forced_check(sc, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i],
		[Vector2i(-1, 0), Vector2i(-2, 0)] as Array[Vector2i], {})
	assert_eq(entered["result"], "clear")
	assert_true(entered["shallow_bow"])
	# a none edge is still just the edge: the cable holds the ship on the map
	var none_edge := sc.duplicate(true)
	none_edge["terrain"]["edges"] = {"W": "none"}
	var lost := AnchorRules.forced_check(none_edge, [Vector2i(-5, 0), Vector2i(-4, 0)] as Array[Vector2i],
		[Vector2i(-6, 0), Vector2i(-5, 0)] as Array[Vector2i], {})
	assert_eq(lost["result"], "edge")


# --- fix wave ------------------------------------------------------------------------

## forced_check tests crossings for no ship (MapRules.NO_SHIP): an escape boundary holds her, even
## one open to every side from turn 1.
func test_forced_check_escape_boundary_holds() -> void:
	var sc := TEN.duplicate(true)
	sc["terrain"] = {"boundaries": [{"name": "gap", "kind": "escape", "sides": [[[-1, 0], [-2, 0]]]}]}
	sc["escape"] = {"0": {}, "1": {}}
	var r := AnchorRules.forced_check(sc, [Vector2i(-1, 0), Vector2i(0, 0)] as Array[Vector2i],
		[Vector2i(-2, 0), Vector2i(-1, 0)] as Array[Vector2i], {})
	assert_eq(r["result"], "edge")
	assert_eq(MapRules.crossing_outcome(sc, MapRules.NO_SHIP, Vector2i(-1, 0), Vector2i(-2, 0), 1)["outcome"],
		MapRules.BLOCKED)


func test_downwind_wraps() -> void:
	assert_eq(AnchorRules.downwind(-1), 2)
	assert_eq(AnchorRules.downwind(5), 2)
	assert_eq(AnchorRules.downwind(3), 0)


## Item 8: a plan with both springs tasks is told why, whichever end is ready.
func test_refusal_both_springs_in_one_plan() -> void:
	var s := _ship()
	s.anchor_ready = "bow"
	assert_eq(_refusal(s, "PSS", {}, {}, ["PBS"]), AnchorRules.R_ONE_ANCHOR)
	assert_eq(_refusal(_anchored("stern"), "PBS", {}, {}, ["PSS"]), AnchorRules.R_ONE_ANCHOR)
	var t := _ship()
	t.anchor_ready = "stern"
	t.crew_tasks.append({"seq": 1, "code": "PSS", "params": {}, "sections": [0], "ended": ""})
	assert_eq(_refusal(t, "PBS"), AnchorRules.R_ONE_ANCHOR)


## Ruling 2026-11-18: a reinforcement may not start at anchor.
func test_scenario_errors_reinforcement_anchor() -> void:
	var sc := {"map_bounds": {"width": 10, "height": 10},
		"ships": [{"id": "a", "arrives": 3, "anchor": {"end": "bow"}}]}
	var errors := AnchorRules.scenario_errors(sc)
	assert_eq(errors, ["Anchoring: ship 'a' is a reinforcement and cannot start at anchor"] as Array[String])
	sc["ships"][0]["arrives"] = 1
	assert_eq(AnchorRules.scenario_errors(sc), [] as Array[String], "on the map from the start")


## placement_errors: an anchored ship's footprint must be on the map and in the water.
func test_footprint_errors() -> void:
	var sc := TEN.duplicate(true)
	sc["terrain"] = {"land": [[-2, 0]]}
	var on_land := _anchored("bow")  # anchor (0, 0), cable 1: rides to (-1, 0), (-2, 0)
	assert_eq(AnchorRules.footprint_errors(sc, on_land).size(), 1)
	assert_string_contains(AnchorRules.footprint_errors(sc, on_land)[0], "which is land")
	var off := _anchored("bow")
	off.anchor["hex"] = Vector2i(-4, 0)  # rides to (-5, 0), (-6, 0): the map ends at column -5
	var errors := AnchorRules.footprint_errors(TEN, off)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].begins_with("Anchoring: ") and errors[0].contains("outside map_bounds"), errors[0])
	assert_eq(AnchorRules.footprint_errors(TEN, _anchored("bow")), [] as Array[String])
	assert_eq(AnchorRules.footprint_errors(TEN, _ship()), [] as Array[String], "not anchored")


func test_status_text() -> void:
	assert_eq(AnchorRules.status_text(_ship()), "")
	var r := _ship()
	r.anchor_ready = "bow"
	assert_eq(AnchorRules.status_text(r), "Bow anchor ready.")
	assert_eq(AnchorRules.status_text(_anchored("bow", true, 1)),
		"Anchored by the bow, 2 hexes of cable, springs rigged.")
	assert_eq(AnchorRules.status_text(_anchored("stern", false, 0)), "Anchored by the stern, 1 hex of cable.")
