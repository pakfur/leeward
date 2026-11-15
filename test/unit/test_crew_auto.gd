extends GutTest
## Tests for CrewAuto (crew-tasks spec §3.3, rules A0, A2, A3, A6) and CrewRules (spec §3.2).
## Expected values from the rules: 4.B.1-4 (any section may alter sail, one task per section,
## unplotted sailors serve the guns), 5.F.9 (a sail change must be completed), the ship log's Crew
## Task Order Codes (MS<->PS 2 CS) and gunfire chart (-3 per sailor section missing).
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")

var ship: ShipState


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	ship = _make_ship("own", 0, Vector2i(0, 0))


func after_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, player: int, hex: Vector2i) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex
	state.facing = 0
	state.sail_state = "MS"
	state.crew_quality = "B"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	GameState.add_ship(state)
	return state


func _ctx() -> Dictionary:
	return CrewRules.context(GameState, ship)


func _orders(target: String) -> Dictionary:
	return {"sail_target": target}


# --- CrewAuto ---

func test_a3_minor_change_goes_to_the_marines() -> void:
	# Spec §8 #21: no fire, FS->MS ordered, no enemy near: M alters sail; four sections at the guns
	# (4.B.4: marines cost no gunfire).
	ship.sail_state = "FS"
	var result := CrewAuto.allocate(ship, _orders("MS"), _ctx())
	assert_eq(result["assignments"].keys(), [ShipState.MARINES])
	assert_eq(result["assignments"][ShipState.MARINES]["code"], "SAIL")
	assert_eq(result["auto"], [ShipState.MARINES] as Array[int])
	var guns := CrewRules.guns_preview(ship, {"assignments": result["assignments"]})
	assert_eq(guns["sections"], 4)
	assert_eq(guns["modifier"], 0)


func test_a3_major_change_takes_marines_and_s4() -> void:
	# Ship log: MS->PS needs 2 CS. Worker order M, S4 (spec §3.3).
	var result := CrewAuto.allocate(ship, _orders("PS"), _ctx())
	var sections: Array = result["assignments"].keys()
	sections.sort()
	assert_eq(sections, [3, ShipState.MARINES])
	var guns := CrewRules.guns_preview(ship, {"assignments": result["assignments"]})
	assert_eq(guns["modifier"], -3, "ship log: -3 per sailor CS missing")


func test_a3_marines_held_back_by_an_enemy_alongside() -> void:
	# Spec §3.3: an adjacent enemy holds the marines back (marine fire); S4 then S3 work the sails.
	_make_ship("enemy", 1, Vector2i(0, 1))
	assert_true(_ctx()["enemy_adjacent"])
	var result := CrewAuto.allocate(ship, _orders("PS"), _ctx())
	var sections: Array = result["assignments"].keys()
	sections.sort()
	assert_eq(sections, [2, 3])
	assert_eq(CrewRules.marines_held_back(ship, _ctx()), CrewRules.HOLD_ENEMY)


func test_a3_marines_held_back_by_a_fixable_critical_effect() -> void:
	# Spec §3.3: a fix roll is +1 with the marines busy (chart DRM), so they stay free.
	ship.critical_effects = [{"seq": 1, "id": "braces_cut", "turn": 1, "side": -1, "attempts": 0,
		"expires_after_turn": -1}] as Array[Dictionary]
	var result := CrewAuto.allocate(ship, _orders("FS"), _ctx())
	assert_eq(result["assignments"].keys(), [3])


func test_a3_enemy_at_range_two_does_not_hold_the_marines_back() -> void:
	_make_ship("enemy", 1, Vector2i(0, 3))
	assert_eq(_ctx()["enemy_adjacent"], false)
	assert_true(_ctx()["enemy_in_gun_range"])
	var result := CrewAuto.allocate(ship, _orders("FS"), _ctx())
	assert_eq(result["assignments"].keys(), [ShipState.MARINES])


func test_a3_not_enough_sections_places_nobody() -> void:
	# A change short of its sections does not start (5.F.6b); nobody leaves the guns for it.
	ship.crew_count = [0, 0, 0, 3] as Array[int]
	ship.marine_count = 0
	var result := CrewAuto.allocate(ship, _orders("PS"), _ctx())
	assert_eq(result["assignments"], {})


func test_a0_change_in_progress_keeps_its_sections() -> void:
	# 5.F.9: a sail change in progress is continued by the same sections (locked, A0).
	CrewFixtures.give_sail_change(ship, "PS", [1, 2], 1, false)
	var result := CrewAuto.allocate(ship, _orders(""), _ctx())
	var sections: Array = result["assignments"].keys()
	sections.sort()
	assert_eq(sections, [1, 2])


func test_a2_task_in_progress_continues() -> void:
	# Spec §3.3 A2: tasks in progress continue with the same sections.
	GameState.ship_controller.add_task("own", {"code": "RR", "sections": [2], "params": {}})
	var result := CrewAuto.allocate(ship, _orders(""), _ctx())
	assert_eq(result["assignments"], {2: {"code": "RR", "params": {}}})


func test_a2_task_of_a_lost_section_is_not_continued() -> void:
	# 4.B.3: a section with no boxes loses its task.
	GameState.ship_controller.add_task("own", {"code": "RR", "sections": [0], "params": {}})
	ship.crew_count = [0, 3, 3, 3] as Array[int]
	assert_eq(CrewAuto.allocate(ship, _orders(""), _ctx())["assignments"], {})


func test_automatic_is_deterministic() -> void:
	# Spec §8 #23: Automatic twice on the same state gives identical plans.
	ship.sail_state = "FS"
	var first := CrewRules.normalize(ship, {"assignments": {}, "orders": _orders("MS")}, _ctx())
	var second := CrewRules.normalize(ship, {"assignments": {}, "orders": _orders("MS")}, _ctx())
	assert_eq(first, second)


func test_automatic_replaces_a_hand_plan() -> void:
	# Spec §3.2 normalize (3): with Automatic on, everything not locked is placed by CrewAuto.
	var plan := {"assignments": {0: {"code": "SAIL", "params": {"target": "FS"}}}, "orders": _orders("FS")}
	var result := CrewRules.normalize(ship, plan, _ctx())
	assert_eq(result["assignments"].keys(), [ShipState.MARINES])


# --- CrewRules: manual plans ---

func test_one_task_per_section() -> void:
	# Spec §8 #1, 4.B.2: a second station for S3 replaces the first.
	ship.crew_auto = false
	var plan := {"assignments": {}, "orders": _orders("FS")}
	plan = CrewRules.assign(ship, plan, _ctx(), 2, CrewRules.STATION_SAILS)
	assert_eq(plan["assignments"].keys(), [2])
	plan = CrewRules.assign(ship, plan, _ctx(), 2, CrewRules.STATION_GUNS)
	assert_eq(plan["assignments"], {}, "back at the guns: unplotted")


func test_marines_cannot_serve_the_guns() -> void:
	ship.crew_auto = false
	var plan := {"assignments": {}, "orders": _orders("")}
	assert_eq(CrewRules.refusal(ship, plan, _ctx(), ShipState.MARINES, CrewRules.STATION_GUNS),
		"Only sailor sections serve the guns. Marines fire muskets instead.")
	assert_eq(CrewRules.refusal(ship, plan, _ctx(), 0, CrewRules.STATION_MARINE_FIRE),
		"Only the marine section gives marine fire.")


func test_any_section_may_alter_sail() -> void:
	# 4.B.1 (spec Q12): any section, marines included, may alter sail.
	ship.crew_auto = false
	var plan := {"assignments": {}, "orders": _orders("FS")}
	for section in range(ShipState.MARINES + 1):
		assert_eq(CrewRules.refusal(ship, plan, _ctx(), section, CrewRules.STATION_SAILS), "")


func test_sails_station_is_full_at_the_needed_sections() -> void:
	# Ship log: FS needs 1 CS; a second is refused.
	ship.crew_auto = false
	var plan := CrewRules.assign(ship, {"assignments": {}, "orders": _orders("FS")}, _ctx(), 0, CrewRules.STATION_SAILS)
	assert_eq(CrewRules.refusal(ship, plan, _ctx(), 1, CrewRules.STATION_SAILS), "Sails aloft is full (1 section).")


func test_change_in_progress_section_is_locked() -> void:
	# Spec §8 #9, 5.F.9: the plan moves a section altering sail; it is restored.
	ship.crew_auto = false
	CrewFixtures.give_sail_change(ship, "FS", [1], 0, false)
	assert_eq(CrewRules.refusal(ship, {"assignments": {}, "orders": {}}, _ctx(), 1, CrewRules.STATION_GUNS),
		"S2 is altering sail. Must be completed (5.F.9).")
	var result := CrewRules.normalize(ship, {"assignments": {}, "orders": _orders("")}, _ctx())
	assert_eq(result["assignments"].keys(), [1])
	assert_eq(result["assignments"][1]["code"], "SAIL")


func test_two_section_change_short_of_sections_warns() -> void:
	# Spec §8 #56, 5.F.6b: MS->PS needs 2 sections; one placed gives a warning.
	ship.crew_auto = false
	var plan := CrewRules.assign(ship, {"assignments": {}, "orders": _orders("PS")}, _ctx(), 3, CrewRules.STATION_SAILS)
	var result := CrewRules.normalize(ship, plan, _ctx())
	assert_eq(result["assignments"].keys(), [3], "the section is kept")
	assert_eq(result["warnings"], ["Needs 2 sections: 1 placed. The change will not start."])


func test_lost_section_is_dropped() -> void:
	ship.crew_auto = false
	ship.crew_count = [0, 3, 3, 3] as Array[int]
	var plan := {"assignments": {0: {"code": "SAIL", "params": {"target": "FS"}}}, "orders": _orders("FS")}
	var result := CrewRules.normalize(ship, plan, _ctx())
	assert_eq(result["assignments"], {})
	assert_eq(result["dropped"], [0])


func test_sail_without_an_order_is_dropped() -> void:
	ship.crew_auto = false
	var plan := {"assignments": {1: {"code": "SAIL", "params": {"target": "FS"}}}, "orders": _orders("")}
	var result := CrewRules.normalize(ship, plan, _ctx())
	assert_eq(result["assignments"], {})
	assert_eq(result["warnings"], ["S2: No sail change is ordered"])


func test_guns_preview_counts_lost_sections_as_missing() -> void:
	# Ship log: -3 per sailor CS missing, lost or tasked (Majestic g-t 7, 17); 0 left: cannot fire.
	ship.crew_count = [0, 3, 3, 3] as Array[int]
	var plan := {"assignments": {1: {"code": "SAIL", "params": {}}}}
	var guns := CrewRules.guns_preview(ship, plan)
	assert_eq(guns["sections"], 2)
	assert_eq(guns["modifier"], -6)
	assert_eq(guns["missing"], [{"section": 0, "why": "lost"}, {"section": 1, "why": "SAIL"}])
	plan = {"assignments": {1: {}, 2: {}, 3: {}}}
	assert_eq(CrewRules.guns_preview(ship, plan)["modifier"], null, "no sailor section left: cannot fire")


# --- A4 tacking crew (5.D.2a; spec §3.3, §3.6) ---

func _ma0_ctx() -> Dictionary:
	var ctx := _ctx()
	ctx["ma0_turn_plotted"] = true
	return ctx


func test_a4_three_sections_at_the_braces_in_worker_order() -> void:
	# Spec §3.3 A4: a turn at MA 0 plotted: as many of 3 sections as are free, M, S4, S3.
	var result := CrewAuto.allocate(ship, _orders(""), _ma0_ctx())
	var sections: Array = result["assignments"].keys()
	sections.sort()
	assert_eq(sections, [2, 3, ShipState.MARINES])
	for section in sections:
		assert_eq(result["assignments"][section]["code"], "T")
	var guns := CrewRules.guns_preview(ship, {"assignments": result["assignments"]})
	assert_eq(guns["modifier"], -6, "S4 and S3 at the braces do not serve the guns (4.B.4)")


func test_a4_no_turn_at_ma0_no_braces() -> void:
	assert_eq(CrewAuto.allocate(ship, _orders(""), _ctx())["assignments"], {})


func test_a4_after_tasks_in_progress_and_held_back_marines() -> void:
	# Spec §8 #20 (no fire yet: phase 4): S1 on RR in progress keeps it (A2); an adjacent enemy
	# holds the marines back; T gets S4, S3, S2.
	_make_ship("enemy", 1, Vector2i(0, 1))
	GameState.ship_controller.add_task("own", {"code": "RR", "sections": [0], "params": {}})
	var result := CrewAuto.allocate(ship, _orders(""), _ma0_ctx())
	assert_eq(result["assignments"][0]["code"], "RR")
	var braces: Array = []
	for section in result["assignments"]:
		if result["assignments"][section]["code"] == "T":
			braces.append(section)
	braces.sort()
	assert_eq(braces, [1, 2, 3])


func test_a4_comes_after_the_ordered_sail_change() -> void:
	# A3 before A4: MS->PS takes M and S4; the braces get S3, S2, S1.
	var result := CrewAuto.allocate(ship, _orders("PS"), _ma0_ctx())
	assert_eq(result["assignments"][ShipState.MARINES]["code"], "SAIL")
	assert_eq(result["assignments"][3]["code"], "SAIL")
	assert_eq(CrewRules.tack_sections_in(result), 3)


func test_a4_only_free_sections() -> void:
	# Fewer than 3 sections left: as many as there are.
	ship.crew_count = [0, 0, 0, 3] as Array[int]
	ship.marine_count = 0
	var result := CrewAuto.allocate(ship, _orders(""), _ma0_ctx())
	assert_eq(result["assignments"], {3: {"code": "T", "params": {}}})


# --- Braces station, manual plans ---

func test_braces_refused_without_a_turn_at_ma0() -> void:
	ship.crew_auto = false
	var plan := {"assignments": {}, "orders": _orders("")}
	assert_eq(CrewRules.refusal(ship, plan, _ctx(), 3, CrewRules.STATION_BRACES),
		"Plot a turn at MA 0 first: the braces are manned only to tack (5.D.1).")
	assert_eq(CrewRules.refusal(ship, plan, _ma0_ctx(), 3, CrewRules.STATION_BRACES), "")


func test_braces_hold_three_sections() -> void:
	# crew_tasks.json T: 1-3 sections (5.D.2a assumes 3).
	ship.crew_auto = false
	var plan := {"assignments": {}, "orders": _orders("")}
	for section in [ShipState.MARINES, 3, 2]:
		plan = CrewRules.assign(ship, plan, _ma0_ctx(), section, CrewRules.STATION_BRACES)
	assert_eq(CrewRules.tack_sections_in(plan), 3)
	assert_eq(CrewRules.refusal(ship, plan, _ma0_ctx(), 1, CrewRules.STATION_BRACES),
		"Braces (tacking) is full (3 sections).")
	assert_eq(CrewRules.refusal(ship, plan, _ma0_ctx(), 2, CrewRules.STATION_BRACES), "",
		"a section already there may be placed again")


func test_manual_normalize_drops_braces_without_a_turn_at_ma0() -> void:
	ship.crew_auto = false
	var plan := {"assignments": {3: {"code": "T", "params": {}}, 2: {"code": "T", "params": {}}},
		"orders": _orders("")}
	var kept := CrewRules.normalize(ship, plan, _ma0_ctx())
	assert_eq(CrewRules.tack_sections_in(kept), 2)
	var dropped := CrewRules.normalize(ship, plan, _ctx())
	assert_eq(dropped["assignments"], {})
	assert_eq(dropped["warnings"].size(), 2)
