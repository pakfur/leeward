extends GutTest
## Tests for crew-tasks spec phase 3, the crew overlay: CrewRules.stations, the fire draft
## (§3.4, with fake fires: phase 4 makes real ones), the summary line (§4.8), the progress-loss
## warning (4.A.3), the sail order in manual mode, the server requests player_plot_crew and
## player_set_crew_auto (phase, ownership, submission), Automatic on and off, the braces kept
## until End Planning, and the overlay's text (Guns readout, bearings, deck notes).
## Expected values from the rules: 8.E.2 (every fire fought; RO and engaged boarders exempt),
## 4.B.4 (-3 per sailor section off the guns), 5.F.9 (a sail change must be completed).
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
const PLANNING := TurnPhaseController.GamePhase.PLANNING
const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION

var ship: ShipState
var _old_phase: TurnPhaseController.GamePhase
var _old_ready: Array[bool]
var _old_log: PhaseEvents.PhaseLog


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_old_phase = GameState.phase_controller.current_phase
	_old_ready = GameState.phase_controller.players_ready.duplicate()
	_old_log = GameState.turn_log
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.phase_controller.current_phase = PLANNING
	GameState.phase_controller.players_ready = [false, false] as Array[bool]
	ship = _make_ship("own", 0, Vector2i(0, 0))


func after_each() -> void:
	GameState.phase_controller.current_phase = _old_phase
	GameState.phase_controller.players_ready = _old_ready
	GameState.turn_log = _old_log
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, player: int, hex: Vector2i, facing: int = 0) -> ShipState:
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
	state.facing = facing
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


func _task(code: String, sections: Array, done: int = 0, params: Dictionary = {}, forced: bool = false) -> void:
	ship.task_seq += 1
	ship.crew_tasks.append(ShipState.crew_task_from({
		"seq": ship.task_seq, "code": code, "sections": sections, "done": done, "started_turn": 1,
		"params": params, "forced": forced, "marines_available": false, "ended": "",
	}))


func _ids(stations: Array) -> Array:
	var out: Array = []
	for st in stations:
		out.append(st["id"])
	return out


func _station(stations: Array, id: String) -> Dictionary:
	for st in stations:
		if st["id"] == id:
			return st
	return {}


# --- CrewRules.stations (spec §4.3) ---

func test_default_stations_guns_marines_and_sails() -> void:
	ship.crew_auto = false
	var plan := CrewRules.normalize(ship, CrewRules.plan_of(ship), _ctx())
	var stations := CrewRules.stations(ship, plan, _ctx())
	assert_eq(_ids(stations), [CrewRules.STATION_FIRE_WATCH, CrewRules.STATION_GUNS, CrewRules.STATION_MARINE_FIRE,
		CrewRules.STATION_BOARDERS, CrewRules.STATION_SAILS],
		"no braces without a turn at MA 0, no reorganizing, no fires; fire watch (8.E.2 HINT); Boarders for a ship in play (boarding spec §4.1)")
	assert_false(_station(stations, CrewRules.STATION_FIRE_WATCH)["menu_only"], "drawn while no fire burns")
	var guns := _station(stations, CrewRules.STATION_GUNS)
	assert_eq(guns["occupants"], [0, 1, 2, 3], "4.B.4: unplotted sailors serve the guns")
	assert_eq(guns["capacity"], 4)
	assert_eq(_station(stations, CrewRules.STATION_MARINE_FIRE)["occupants"], [ShipState.MARINES])
	var sails := _station(stations, CrewRules.STATION_SAILS)
	assert_eq(sails["occupants"], [])
	assert_eq(sails["note"], "Order a sail change first.")
	var targets: Array = []
	for c in sails["choices"]:
		targets.append(c["target"])
	assert_eq(targets, ["FS", "PS"], "one step down or up from MS")
	assert_eq(sails["choices"][1]["text"], "MS → PS (2 CS, 2 turns)", "ship log: MS<->PS 2 CS, 2 g-t's at CQ B")


func test_stations_lost_section_has_no_counter() -> void:
	ship.crew_auto = false
	ship.crew_count = [0, 3, 3, 3] as Array[int]
	var stations := CrewRules.stations(ship, CrewRules.plan_of(ship), _ctx())
	assert_eq(_station(stations, CrewRules.STATION_GUNS)["occupants"], [1, 2, 3])


func test_stations_sail_change_in_progress_is_locked() -> void:
	# 5.F.9: a sail change in progress must be completed: its section is locked on Sails.
	ship.crew_auto = false
	CrewFixtures.give_sail_change(ship, "FS", [3], 0, false)
	var plan := CrewRules.normalize(ship, CrewRules.plan_of(ship), _ctx())
	var sails := _station(CrewRules.stations(ship, plan, _ctx()), CrewRules.STATION_SAILS)
	assert_eq(sails["occupants"], [3])
	assert_eq(sails["locked"], [3])
	assert_eq(sails["target"], "FS")
	assert_string_contains(sails["note"], "Must be completed (5.F.9)")


func test_stations_automatic_locks_every_counter() -> void:
	ship.crew_auto = true
	var plan := CrewRules.normalize(ship, CrewRules.plan_of(ship), _ctx())
	var guns := _station(CrewRules.stations(ship, plan, _ctx()), CrewRules.STATION_GUNS)
	assert_eq(guns["locked"], [0, 1, 2, 3], "Automatic on: the officers place the sections")


func test_stations_reorganizing_holds_ro_sections() -> void:
	# Hull #4: a disorganized section sits in Reorganizing, locked, and is not a drop target.
	ship.crew_auto = false
	_task("RO", [3], 0, {"reason": "crew_disorganized"}, true)
	var plan := CrewRules.normalize(ship, CrewRules.plan_of(ship), _ctx())
	var stations := CrewRules.stations(ship, plan, _ctx())
	var ro := _station(stations, CrewRules.STATION_REORGANIZING)
	assert_eq(ro["occupants"], [3])
	assert_eq(ro["locked"], [3])
	assert_eq(ro["accepts"], "none")
	assert_ne(CrewRules.refusal(ship, plan, _ctx(), 2, CrewRules.STATION_REORGANIZING), "")


func test_stations_braces_with_ma0_turn() -> void:
	ship.crew_auto = false
	var ctx := _ctx()
	ctx["ma0_turn_plotted"] = true
	var stations := CrewRules.stations(ship, CrewRules.plan_of(ship), ctx)
	var braces := _station(stations, CrewRules.STATION_BRACES)
	assert_eq(braces["capacity"], 3, "5.D.2a: the Tacking table assumes 3 sections")
	assert_eq(braces["warning"], "")


func test_stations_lists_fake_fires_first() -> void:
	ship.crew_auto = false
	var ctx := _ctx()
	ctx["fires"] = [7, 4]
	var plan := CrewRules.normalize(ship, CrewRules.plan_of(ship), ctx)
	var stations := CrewRules.stations(ship, plan, ctx)
	assert_eq(_ids(stations).slice(0, 2), ["fire_4", "fire_7"], "fires in seq order, first")
	assert_eq(stations[0]["label"], "Fire 1")
	assert_eq(stations[0]["occupants"], [0], "the draft filled fire 1 with S1")
	assert_eq(stations[1]["occupants"], [1], "and fire 2 with S2")
	assert_eq(plan["auto"], [0, 1])


# --- The fire draft (spec §3.4, §8 #24-26, #44) ---

func test_draft_lowest_unplotted_sailor() -> void:
	assert_eq(CrewRules.fire_draft(ship, {0: {"code": "SAIL", "params": {"target": "FS"}}}, 1), 1)


func test_draft_standing_by_first() -> void:
	# 8.E.2 HINT: a section standing by (fire watch) goes before an unplotted one.
	assert_eq(CrewRules.fire_draft(ship, {3: {"code": "FF", "params": {"fire": -1}}}, 1), 3)


func test_draft_marines_when_sailors_all_on_tasks() -> void:
	# Spec §8 #24.
	var a := {}
	for s in range(4):
		a[s] = {"code": "SAIL", "params": {"target": "PS"}}
	assert_eq(CrewRules.fire_draft(ship, a, 1), ShipState.MARINES)


func test_draft_one_turn_task_before_multi_turn() -> void:
	var a := {0: {"code": "T", "params": {}}, 1: {"code": "T", "params": {}}, 2: {"code": "SAIL", "params": {}},
		3: {"code": "SAIL", "params": {}}, 4: {"code": "SAIL", "params": {}}}
	assert_eq(CrewRules.fire_draft(ship, a, 1), 1, "the braces, highest-numbered first")


func test_draft_fewest_turns_done() -> void:
	# Spec §8 #25: S1 RO, S2 RR 3 done, S3 RH 1 done, S4 and M lost: S3.
	ship.crew_count = [3, 3, 3, 0] as Array[int]
	ship.marine_count = 0
	_task("RO", [0], 0, {"reason": "crew_disorganized"}, true)
	_task("RR", [1], 3)
	_task("RH", [2], 1)
	var a := {0: {"code": "RO", "params": {"reason": "crew_disorganized"}}, 1: {"code": "RR", "params": {}},
		2: {"code": "RH", "params": {}}}
	assert_eq(CrewRules.fire_draft(ship, a, 1), 2)


func test_draft_only_ro_left_is_unfought() -> void:
	# Spec §8 #26 and #44: RO is never called to a fire (8.E.2).
	ship.crew_count = [0, 0, 3, 0] as Array[int]
	ship.marine_count = 0
	_task("RO", [2], 0, {"reason": "crew_disorganized"}, true)
	assert_eq(CrewRules.fire_draft(ship, {2: {"code": "RO", "params": {}}}, 1), -1)


func test_fill_fires_ends_a_shared_sail_change() -> void:
	# A section called away from a two-section sail change ends it for both (5.F.9a).
	ship.crew_auto = false
	var a := {0: {"code": "RO", "params": {}}, 1: {"code": "RO", "params": {}}, 2: {"code": "RO", "params": {}},
		3: {"code": "SAIL", "params": {"target": "PS"}}, 4: {"code": "SAIL", "params": {"target": "PS"}}}
	for s in [0, 1, 2]:
		_task("RO", [s], 0, {}, true)
	var filled := CrewRules.fill_fires(ship, a, [5])
	assert_eq(filled["auto"], [ShipState.MARINES], "tie: the highest-numbered section")
	assert_eq(filled["assignments"][ShipState.MARINES], {"code": "FF", "params": {"fire": 5}})
	assert_false(filled["assignments"].has(3), "S4 goes back to the guns")


func test_automatic_fire_first_then_tasks_then_braces() -> void:
	# Spec §8 #20: fire aboard, S1 on RR in progress, MA-0 turn plotted: fire S2, S1 keeps RR,
	# braces S4 and S3 (M held back: fire), nothing left for a third.
	ship.fire_list = [{"seq": 1, "created_turn": 1, "started_turn": 1, "cause": "crit"}] as Array[Dictionary]
	ship.sail_state = "FS"
	ship.rigging_current_hp[0] -= 1  # a rigging box to repair (8.F.3)
	_task("RR", [0], 2)
	var ctx := _ctx()
	ctx["ma0_turn_plotted"] = true
	ctx["fires"] = [1]
	var a: Dictionary = CrewAuto.allocate(ship, {"sail_target": ""}, ctx)["assignments"]
	assert_eq(a[1], {"code": "FF", "params": {"fire": 1}})
	assert_eq(a[0]["code"], "RR")
	assert_eq(a[3]["code"], "T")
	assert_eq(a[2]["code"], "T")
	assert_false(a.has(ShipState.MARINES), "marines held back: fire aboard")


# --- Summary line (spec §4.8) ---

func test_summary_line_groups_by_station() -> void:
	ship.crew_auto = false
	var ctx := _ctx()
	ctx["fires"] = [3]
	var plan := {"assignments": {0: {"code": "SAIL", "params": {"target": "FS"}}}, "orders": {"sail_target": "FS"}}
	var n := CrewRules.normalize(ship, plan, ctx)
	assert_eq(CrewRules.summary_text(CrewRules.summary(ship, n, ctx)), "S1 sails · S2 FF1 · S3 S4 guns · M fire")
	var kinds: Array = []
	for chip in CrewRules.summary(ship, n, ctx):
		kinds.append(chip["kind"])
	assert_eq(kinds, ["task", "fire", "default", "default"])


func test_summary_line_automatic_and_warning() -> void:
	ship.crew_auto = true
	var plan := CrewRules.normalize(ship, CrewRules.plan_of(ship), _ctx())
	assert_eq(CrewRules.summary_text(CrewRules.summary(ship, plan, _ctx())), "Auto · S1 S2 S3 S4 guns · M fire")
	ship.crew_auto = false
	var short := CrewRules.normalize(ship, {"assignments": {3: {"code": "SAIL", "params": {}}},
		"orders": {"sail_target": "PS"}}, _ctx())
	var chips := CrewRules.summary(ship, short, _ctx())
	assert_eq(chips[-1]["kind"], "warn")
	assert_eq(chips[-1]["text"], "Needs 2 sections: 1 placed. The change will not start.")


func test_summary_line_lost_section_left_out() -> void:
	ship.crew_auto = false
	ship.crew_count = [3, 0, 3, 3] as Array[int]
	var plan := CrewRules.normalize(ship, CrewRules.plan_of(ship), _ctx())
	assert_eq(CrewRules.summary_text(CrewRules.summary(ship, plan, _ctx())), "S1 S3 S4 guns · M fire")


# --- Progress warning (4.A.3) and the sail order ---

func test_progress_warning_for_an_abandonable_task_with_progress() -> void:
	_task("RR", [2], 2)
	var warn := CrewRules.progress_warning(ship, CrewRules.plan_of(ship), 2, CrewRules.STATION_GUNS)
	assert_eq(warn, "S3 has 2 of 4 turns on rigging repair. Moving it loses them (4.A.3).",
		"RR 6 ± SK: CQ B (SK -2) needs 4")
	assert_eq(CrewRules.progress_warning(ship, CrewRules.plan_of(ship), 1, CrewRules.STATION_GUNS), "")


func test_no_progress_warning_for_a_sail_change() -> void:
	CrewFixtures.give_sail_change(ship, "PS", [3, 4], 1, false)
	assert_eq(CrewRules.progress_warning(ship, CrewRules.plan_of(ship), 3, CrewRules.STATION_GUNS), "",
		"locked, not abandonable (5.F.9)")


func test_with_sail_order_manual_places_worker_order() -> void:
	ship.crew_auto = false
	var plan := CrewRules.with_sail_order(ship, CrewRules.plan_of(ship), _ctx(), "PS")
	var on_sails: Array = plan["assignments"].keys()
	on_sails.sort()
	assert_eq(on_sails, [3, ShipState.MARINES], "MS->PS: 2 sections, M then S4")
	var back := CrewRules.with_sail_order(ship, plan, _ctx(), "FS")
	assert_eq(back["assignments"].keys(), [3], "FS needs one: the lowest placed stays")
	var none := CrewRules.with_sail_order(ship, back, _ctx(), "")
	assert_eq(none["assignments"], {})


# --- Server requests ---

func test_player_plot_crew_stores_the_normalized_plan() -> void:
	ship.crew_auto = false
	var pc := GameState.phase_controller
	var plan := CrewRules.with_sail_order(ship, CrewRules.plan_of(ship), _ctx(), "FS")
	plan = CrewRules.assign(ship, plan, _ctx(), ShipState.MARINES, CrewRules.STATION_MARINE_FIRE)
	plan = CrewRules.assign(ship, plan, _ctx(), 1, CrewRules.STATION_SAILS)
	assert_eq(pc.player_plot_crew(0, "own", plan), "")
	assert_eq(CrewRules.plan_of(ship)["assignments"], {1: {"code": "SAIL", "params": {"target": "FS"}}})
	assert_eq(ship.ordered_sail_target(), "FS")


func test_player_plot_crew_refusals() -> void:
	var pc := GameState.phase_controller
	_make_ship("enemy", 1, Vector2i(5, 0))
	var plan := {"assignments": {}, "orders": {"sail_target": ""}}
	assert_eq(pc.player_plot_crew(0, "enemy", plan), "enemy is not this player's ship")
	assert_eq(pc.player_plot_crew(0, "nope", plan), "no ship nope")
	assert_eq(pc.player_plot_crew(5, "own", plan), "invalid player 5")
	assert_eq(pc.player_plot_crew(0, "own", {"assignments": {9: {}}, "orders": {}}), "Malformed crew plan")
	assert_eq(pc.player_plot_crew(0, "own", {"assignments": {}, "orders": {"sail_target": "NS"}}),
		"Cannot change to NS from MS", "a sail order must be a change the ship can make")
	pc.players_ready = [true, false] as Array[bool]
	assert_eq(pc.player_plot_crew(0, "own", plan), "this player's plan is already submitted")
	assert_eq(pc.player_plot_sail_change(0, "own", "FS"), "this player's plan is already submitted")
	assert_eq(ship.ordered_sail_target(), "", "a refused sail order changes nothing")
	pc.players_ready = [false, false] as Array[bool]
	pc.current_phase = MOVE
	assert_eq(pc.player_plot_crew(0, "own", plan), "crew orders are given in the planning phase")
	assert_eq(pc.player_set_crew_auto(0, "own", false), "crew orders are given in the planning phase")
	assert_true(ship.crew_auto, "a refused request changes nothing")
	pc.current_phase = PLANNING
	assert_eq(pc.player_plot_sail_change(0, "own", "FS"), "")
	assert_eq(ship.ordered_sail_target(), "FS")


func test_automatic_off_keeps_allocation_on_reallocates() -> void:
	# Spec §4.9: turning Automatic off keeps the current allocation; on re-allocates at once.
	var pc := GameState.phase_controller
	CrewFixtures.order_sail(ship, "FS")
	assert_true(ship.crew_auto, "on by default (§9 Q2)")
	assert_eq(GameState.crew_task_controller.current_plan("own")["assignments"].keys(), [ShipState.MARINES])
	assert_eq(pc.player_set_crew_auto(0, "own", false), "")
	assert_false(ship.crew_auto)
	assert_eq(CrewRules.plan_of(ship)["assignments"].keys(), [ShipState.MARINES], "nothing moves")
	# manual: move the sail change to S1
	var plan := CrewRules.assign(ship, CrewRules.plan_of(ship), _ctx(), ShipState.MARINES, CrewRules.STATION_MARINE_FIRE)
	plan = CrewRules.assign(ship, plan, _ctx(), 0, CrewRules.STATION_SAILS)
	assert_eq(pc.player_plot_crew(0, "own", plan), "")
	assert_eq(CrewRules.plan_of(ship)["assignments"].keys(), [0])
	assert_eq(pc.player_set_crew_auto(0, "own", true), "")
	assert_eq(CrewRules.plan_of(ship)["assignments"].keys(), [ShipState.MARINES], "A3: worker order again")


func test_manual_braces_kept_until_end_planning() -> void:
	# Phase 2 open issue: a manual T placed while no MA-0 turn is plotted is kept while planning
	# and dropped by finalize_plots if no such turn is plotted by then.
	ship.crew_auto = false
	var pc := GameState.phase_controller
	assert_eq(pc.player_plot_crew(0, "own", {"assignments": {3: {"code": "T", "params": {}}},
		"orders": {"sail_target": ""}}), "")
	assert_eq(CrewRules.plan_of(ship)["assignments"], {3: {"code": "T", "params": {}}}, "kept while planning")
	assert_eq(GameState.crew_task_controller.current_plan("own")["warnings"].size(), 1)
	GameState.crew_task_controller.finalize_plots()
	assert_eq(CrewRules.plan_of(ship)["assignments"], {}, "End Planning: back to the guns")


# --- Overlay text ---

func test_guns_readout_text() -> void:
	ship.crew_auto = false
	var plan := {"assignments": {3: {"code": "SAIL", "params": {"target": "FS"}}}}
	var g := CrewOverlayText.guns_readout(ship, plan)
	assert_eq(g["big"], "3 of 4 sections · −3", "4.B.4: -3 per sailor section off the guns")
	assert_false(g["bad"])
	assert_eq(g["why"], "S4 altering sail")
	assert_eq(g["marines"], "Marines: muskets at the rail.")
	ship.crew_count = [0, 3, 3, 3] as Array[int]
	g = CrewOverlayText.guns_readout(ship, plan)
	assert_eq(g["big"], "2 of 4 sections · −6")
	assert_true(g["bad"], "red at -6 or worse")
	assert_eq(g["why"], "S1 lost · S4 altering sail")


func test_guns_silent() -> void:
	var a := {}
	for s in range(4):
		a[s] = {"code": "T", "params": {}}
	assert_eq(CrewOverlayText.guns_readout(ship, {"assignments": a})["big"], "Guns silent")


func test_progress_tag() -> void:
	CrewFixtures.give_sail_change(ship, "PS", [3, 4], 1, false)
	assert_eq(CrewOverlayText.progress_tag(ship, 3, {"code": "SAIL", "params": {"target": "PS"}}), "T2/2",
		"MS->PS at CQ B: 2 g-t's, the second being worked")
	assert_eq(CrewOverlayText.progress_tag(ship, 0, {}), "")


func test_bearing_words() -> void:
	# Own ship facing E (0) at (0,0): an enemy straight east is ahead; due west astern.
	var ahead := _make_ship("ahead", 1, Vector2i(6, 0))
	var astern := _make_ship("astern", 1, Vector2i(-6, 0))
	var south := _make_ship("south", 1, Vector2i(-3, 6))
	assert_eq(CrewOverlayText.bearing_words(ship, ahead), "ahead")
	assert_eq(CrewOverlayText.bearing_words(ship, astern), "astern")
	assert_eq(CrewOverlayText.bearing_words(ship, south), "on the starboard beam", "south of an east-going ship")


func test_tactical_caption() -> void:
	var env := EnvironmentState.new()
	env.wind_direction = 2
	env.wind_speed = 2
	assert_eq(CrewOverlayText.tactical_caption(ship, GameState.get_all_ships(), GameState.fire_geometry, env),
		"No enemy within gun range · wind %s 2" % PhaseEvents.wind_direction_word(2))
	_make_ship("Topaze", 1, Vector2i(6, 0))
	assert_string_starts_with(CrewOverlayText.tactical_caption(ship, GameState.get_all_ships(), GameState.fire_geometry, env),
		"Topaze 5 hexes ahead")


func test_deck_note_from_armament() -> void:
	var deck := {"id": "gun", "armament": "main_deck", "note": ""}
	var arm := {"long_guns": {"main_deck_port": {"count": 19, "size": 18}}}
	assert_eq(CrewOverlayText.deck_note(deck, arm), "19 eighteen-pounders a side")
	assert_eq(CrewOverlayText.deck_note(deck, {}), "", "frigate_32 has no armament: no note")


func test_deck_layouts_by_ship_type() -> void:
	var frigate := CrewDeckLayouts.layout_for("frigate_38")
	var ids: Array = []
	for d in frigate["decks"]:
		ids.append(d["id"])
	assert_eq(ids, ["upper", "gun", "orlop"])
	var sol := CrewDeckLayouts.layout_for("ship_of_line_74")
	assert_eq(sol["gun_decks"], ["gun_up", "gun_low"])
	assert_eq(CrewDeckLayouts.station_decks(sol, "guns"), ["gun_up", "gun_low"], "guns on every gun deck")
	assert_eq(CrewDeckLayouts.station_decks(frigate, "braces"), ["upper"])
	assert_eq(CrewDeckLayouts.station_rect("guns"), [190.0, 118.0, 620.0, 124.0])


# --- Marine fire station note (boarding spec §4.1, 7.G.1) ---

func test_marine_fire_note_names_the_adjacent_enemy() -> void:
	ship.crew_auto = false
	var marine := _station(CrewRules.stations(ship, CrewRules.plan_of(ship), _ctx()), CrewRules.STATION_MARINE_FIRE)
	assert_eq(marine["note"], "No enemy alongside.")
	_make_ship("Hermione", 1, Vector2i(-1, 1), 3)  # abeam, adjacent
	marine = _station(CrewRules.stations(ship, CrewRules.plan_of(ship), _ctx()), CrewRules.STATION_MARINE_FIRE)
	assert_eq(marine["note"], "Adjacent enemy: Hermione. Targets are chosen with the guns.")


func test_marine_fire_note_lists_several_enemies() -> void:
	assert_eq(CrewRules.marine_fire_note(["A", "B"]), "Adjacent enemies: A, B. Targets are chosen with the guns.")
