extends GutTest
## Tests for DriftResolver (Close Action 1997, 10) and the fouled/struck/dismasted plotting lock.
## Wind from direction 0 (east), so the downwind neighbour is direction 3 (west, -1,0).

const PHASE := 5

var resolver: DriftResolver
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _grid := HexGrid.new()


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.active_scenario = {}
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	resolver = DriftResolver.new(GameState)


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, sail: String = "MS", player: int = 0) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.player_id = player
	state.hex_position = hex
	state.facing = 1
	state.sail_state = sail
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.marine_count = 2
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


func _dismast(state: ShipState) -> void:
	var rigging: Array[int] = [0, 0, 0, 0]
	state.rigging_current_hp = rigging


func _drift_events() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.DRIFT)


func _downwind(hex: Vector2i) -> Vector2i:
	return _grid.get_neighbor(hex.x, hex.y, 3)


# --- basic drift -------------------------------------------------------------

func test_stationary_ship_drifts_one_hex_downwind() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	_dice.queue([3])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, _downwind(Vector2i(5, 5)))
	assert_eq(s.facing, 1, "Facing unchanged")
	var events := _drift_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0].ship_id, "a")
	assert_eq(events[0].data["roll"], 3)
	assert_eq(events[0].data["needed"], 4)
	assert_true(events[0].data["drifted"])
	assert_eq(events[0].data["from"], {"q": 5, "r": 5})
	assert_eq(events[0].data["to"], {"q": 4, "r": 5})


func test_roll_below_number_no_drift() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	_dice.queue([2])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, Vector2i(5, 5))
	var events := _drift_events()
	assert_eq(events.size(), 1)
	assert_false(events[0].data["drifted"])


func test_ship_that_moved_does_not_drift() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	s.moved_this_turn = true
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, Vector2i(5, 5))
	assert_eq(_drift_events().size(), 0)


func test_collided_ship_that_moved_is_eligible() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	s.moved_this_turn = true
	s.collision_this_turn = true
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, _downwind(Vector2i(5, 5)))


func test_wind_speed_zero_no_drift() -> void:
	GameState.environment.wind_speed = 0
	var s := _make_ship("a", Vector2i(5, 5))
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, Vector2i(5, 5))
	assert_eq(_drift_events().size(), 0)


func test_plain_sail_wind_4_always_drifts() -> void:
	GameState.environment.wind_speed = 4
	var s := _make_ship("a", Vector2i(5, 5), "PS")
	_dice.queue([0])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, _downwind(Vector2i(5, 5)))


func test_dismasted_uses_dismasted_row() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	_dismast(s)
	_dice.queue([6])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, Vector2i(5, 5), "6 + 1 = 7 < 8")
	assert_eq(_drift_events()[0].data["needed"], 8)


func test_struck_ship_still_drifts() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	s.status = ShipState.Status.STRUCK
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, _downwind(Vector2i(5, 5)))


func test_destroyed_ship_never_drifts() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	s.status = ShipState.Status.DESTROYED
	resolver.resolve(PHASE)  # no die is rolled (after_each checks the queue is empty)
	assert_eq(s.hex_position, Vector2i(5, 5))
	assert_eq(_drift_events().size(), 0)


func test_drift_blocked_by_wreck_rolls_no_fouling() -> void:
	var drifter := _make_ship("a", Vector2i(5, 5))
	var wreck := _make_ship("b", Vector2i(4, 5))
	wreck.status = ShipState.Status.DESTROYED
	_dice.queue([9])  # the drift roll only; a wreck never fouls, so no fouling d10
	resolver.resolve(PHASE)
	assert_eq(drifter.hex_position, Vector2i(5, 5), "the wreck blocks the drift")
	assert_eq(drifter.fouled_with, "")
	assert_false(_drift_events()[0].data.has("fouled"))


# --- ordering and blocking ---------------------------------------------------

func test_leeward_ship_resolved_first() -> void:
	var windward := _make_ship("a", Vector2i(5, 5))
	var leeward := _make_ship("b", Vector2i(4, 5))
	_dice.queue([3, 3])
	resolver.resolve(PHASE)
	assert_eq(leeward.hex_position, Vector2i(3, 5))
	assert_eq(windward.hex_position, Vector2i(4, 5), "Not blocked by the leeward ship")
	assert_eq(_drift_events()[0].ship_id, "b", "Leeward ship logged first")


func test_blocked_by_ship_no_drift_and_may_foul() -> void:
	var drifter := _make_ship("a", Vector2i(5, 5))
	var blocker := _make_ship("b", Vector2i(4, 5))
	blocker.moved_this_turn = true
	_dice.queue([9, 9])  # drift roll, then fouling roll: 9 - 1 + 1 + 1 (MS each) ... >= 6
	resolver.resolve(PHASE)
	assert_eq(drifter.hex_position, Vector2i(5, 5))
	assert_eq(blocker.hex_position, Vector2i(4, 5))
	assert_eq(drifter.fouled_with, "b")
	assert_eq(blocker.fouled_with, "a")
	var events := _drift_events()
	assert_eq(events.size(), 1)
	assert_false(events[0].data["drifted"])
	assert_eq(events[0].data["blocked"], "ship")
	assert_eq(events[0].target_id, "b", "the drift names the ship in the way")
	assert_true(events[0].data["fouled"], "the fouling outcome rides on the drift line")
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.FOULED).size(), 0,
		"no separate fouled line to contradict the drift line")
	var text: String = events[0].to_text({"a": "Topaze", "b": "HMS Lively"})
	assert_string_contains(text, "Topaze drifts onto HMS Lively (rolled 9")
	assert_string_contains(text, "but cannot pass; the two ships are fouled together")
	assert_false(text.contains("holds position"), text)


func test_blocked_by_ship_low_fouling_roll_does_not_foul() -> void:
	var drifter := _make_ship("a", Vector2i(5, 5))
	var blocker := _make_ship("b", Vector2i(4, 5))
	blocker.moved_this_turn = true
	_dice.queue([9, 0])
	resolver.resolve(PHASE)
	assert_eq(drifter.fouled_with, "")
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.FOULED).size(), 0)
	var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
	assert_eq(ev.target_id, "b")
	assert_false(ev.data["fouled"])
	var text := ev.to_text({"a": "Topaze", "b": "HMS Lively"})
	assert_string_contains(text, "Topaze would drift onto HMS Lively (rolled 9")
	assert_string_contains(text, "but is blocked and holds position")
	assert_false(text.contains("fouled"), text)


func test_fouling_roll_modifiers() -> void:
	## Chart: d10, 6+ fouls; drifting ship -1; +1 per ship at MS; +2 per ship at PS.
	var a := _make_ship("a", Vector2i(5, 5), "PS")
	var b := _make_ship("b", Vector2i(4, 5), "PS")
	# a drifting: -1 + 2 + 2 = +3. Roll 2 -> 5 (no foul); roll 3 -> 6 (foul).
	_dice.queue([2])
	assert_false(GameState.movement_resolver.roll_fouling(a, b, true))
	_dice.queue([3])
	assert_true(GameState.movement_resolver.roll_fouling(a, b, true))
	var c := _make_ship("c", Vector2i(0, 0), "FS")
	var d := _make_ship("d", Vector2i(0, 1), "FS")
	# FS: -1 only. Roll 6 -> 5 (no); roll 7 -> 6 (foul).
	_dice.queue([6])
	assert_false(GameState.movement_resolver.roll_fouling(c, d, true))
	_dice.queue([7])
	assert_true(GameState.movement_resolver.roll_fouling(c, d, true))


func test_blocked_by_dismasted_ship_no_fouling_roll() -> void:
	var drifter := _make_ship("a", Vector2i(5, 5))
	var blocker := _make_ship("b", Vector2i(4, 5))
	blocker.moved_this_turn = true
	_dismast(blocker)
	_dice.queue([9])  # only the drift roll; a fouling roll would hit the empty queue
	resolver.resolve(PHASE)
	assert_eq(drifter.hex_position, Vector2i(5, 5))
	assert_eq(drifter.fouled_with, "")
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.FOULED).size(), 0)
	var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
	assert_eq(ev.target_id, "b")
	assert_false(ev.data.has("fouled"), "no fouling roll, no fouling outcome")
	assert_string_contains(ev.to_text({}), "a would drift onto b")


func test_drift_blocked_at_map_edge() -> void:
	GameState.active_scenario = {"map_bounds": {"width": 100, "height": 100}}
	var s := _make_ship("a", Vector2i(-50, 0))  # q range is -50..49
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, Vector2i(-50, 0))
	var events := _drift_events()
	assert_false(events[0].data["drifted"])
	assert_eq(events[0].data["blocked"], "map edge")
	assert_eq(events[0].target_id, "")
	assert_string_contains(events[0].to_text({}), "is at the edge of the map and holds position")


func test_no_map_bounds_means_nothing_out_of_bounds() -> void:
	var s := _make_ship("a", Vector2i(-500, 0))
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, Vector2i(-501, 0))


# --- fouled pairs ------------------------------------------------------------

func _foul_together(a: ShipState, b: ShipState) -> void:
	a.fouled_with = b.ship.ship_id
	b.fouled_with = a.ship.ship_id


func test_fouled_pair_moves_together_or_not_at_all() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	var b := _make_ship("b", Vector2i(4, 5))
	_foul_together(a, b)
	_dice.queue([3])  # one roll for the pair
	resolver.resolve(PHASE)
	assert_eq(a.hex_position, Vector2i(4, 5))
	assert_eq(b.hex_position, Vector2i(3, 5))
	assert_eq(_drift_events().size(), 2, "One event per ship")



func test_fouled_pair_low_roll_neither_moves() -> void:
	var c := _make_ship("c", Vector2i(5, 9))
	var d := _make_ship("d", Vector2i(4, 9))
	_foul_together(c, d)
	_dice.queue([2])
	resolver.resolve(PHASE)
	assert_eq(c.hex_position, Vector2i(5, 9))
	assert_eq(d.hex_position, Vector2i(4, 9))


func test_fouled_pair_uses_higher_drift_number() -> void:
	var a := _make_ship("a", Vector2i(5, 5), "PS")  # needs 2
	var b := _make_ship("b", Vector2i(4, 5), "MS")  # needs 4
	_foul_together(a, b)
	_dice.queue([2])  # 2 + 1 = 3 < 4: the harder ship decides
	resolver.resolve(PHASE)
	assert_eq(a.hex_position, Vector2i(5, 5))
	assert_eq(b.hex_position, Vector2i(4, 5))
	assert_eq(_drift_events()[0].data["needed"], 4)


func test_fouled_pair_blocked_member_holds_both() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	var b := _make_ship("b", Vector2i(4, 5))
	var blocker := _make_ship("c", Vector2i(3, 5))
	blocker.moved_this_turn = true
	_foul_together(a, b)
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_eq(a.hex_position, Vector2i(5, 5))
	assert_eq(b.hex_position, Vector2i(4, 5))
	assert_eq(blocker.fouled_with, "", "A pair does not foul a third ship")
	var by_ship := {}
	for ev in _drift_events():
		by_ship[ev.ship_id] = ev
	assert_eq(by_ship["b"].data["blocked"], "ship")
	assert_eq(by_ship["b"].target_id, "c", "b is the member with a ship in its way")
	assert_eq(by_ship["a"].data["blocked"], "partner")
	assert_eq(by_ship["a"].target_id, "b", "a is held by its fouled partner")
	assert_string_contains(by_ship["a"].to_text({}), "held back by b")


# --- two-hex footprints ------------------------------------------------------

func test_drift_moves_bow_and_stern() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	var bow := s.hex_position
	var stern := s.stern_hex()
	_dice.queue([3])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, _downwind(bow))
	assert_eq(s.stern_hex(), _downwind(stern))
	var new_bow := _downwind(bow)
	assert_eq(_drift_events()[0].data["to"], {"q": new_bow.x, "r": new_bow.y}, "to is the new bow hex")


func test_drift_blocked_by_ship_at_stern_target() -> void:
	var drifter := _make_ship("a", Vector2i(5, 5))
	drifter.facing = 0  # bow (5,5), stern (4,5): drifting along its own axis, the free bow cannot pivot
	var blocker := _make_ship("b", Vector2i(3, 5))  # holds (3,5) and (3,4): the stern target, not the bow target
	blocker.moved_this_turn = true
	_dice.queue([9, 0])
	resolver.resolve(PHASE)
	assert_eq(drifter.hex_position, Vector2i(5, 5))
	var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
	assert_eq(ev.data["blocked"], "ship")
	assert_eq(ev.target_id, "b")


func test_drift_blocked_when_stern_leaves_map() -> void:
	GameState.active_scenario = {"map_bounds": {"width": 100, "height": 100}}
	var s := _make_ship("a", Vector2i(-49, 0))
	s.facing = 0  # stern to the west at (-50, 0); its downwind hex is off the map
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_eq(s.hex_position, Vector2i(-49, 0))
	assert_eq(_drift_events()[0].data["blocked"], "map edge")


func test_fouled_pair_drifts_as_four_hexes() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	var b := _make_ship("b", Vector2i(4, 5))
	_foul_together(a, b)
	_dice.queue([3])
	resolver.resolve(PHASE)
	assert_eq(a.hex_position, Vector2i(4, 5), "partners' own hexes do not block each other")
	assert_eq(b.hex_position, Vector2i(3, 5))
	assert_eq(a.stern_hex(), _downwind(Vector2i(5, 4)))
	assert_eq(b.stern_hex(), _downwind(Vector2i(4, 4)))


func test_fouled_pair_blocked_at_a_far_stern_target() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	var b := _make_ship("b", Vector2i(4, 5))
	_foul_together(a, b)
	# Third ship on the far stern target of the pair: (3,4) is b's stern (4,4) shifted downwind.
	var c := _make_ship("c", _downwind(b.stern_hex()))
	c.moved_this_turn = true
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_eq(a.hex_position, Vector2i(5, 5))
	assert_eq(b.hex_position, Vector2i(4, 5))
	assert_eq(c.fouled_with, "", "a pair does not foul a third ship")
	var by_ship := {}
	for ev in _drift_events():
		by_ship[ev.ship_id] = ev
	assert_eq(by_ship["b"].data["blocked"], "ship")
	assert_eq(by_ship["b"].target_id, "c", "b names the ship in its way")
	assert_eq(by_ship["a"].data["blocked"], "partner")
	assert_eq(by_ship["a"].target_id, "b", "a is held by its fouled partner")
	assert_eq(_dice.remaining(), 0, "one drift roll, no fouling roll")


# --- drift order (8.A.2) -----------------------------------------------------
# Downwind-most ships drift first, judged by the middle of the two-hex footprint: a ship that has
# drifted away no longer blocks, and one that stayed put still does. (A ship that has drifted can
# never block a later drifter: every hex moves by the same step, so the later ship's target hex
# would be one of the earlier ship's old hexes, an overlap.)

func test_ship_that_drifted_away_no_longer_blocks() -> void:
	# a's bow (6,3) projects exactly as far downwind as b's bow (5,5), but a's stern (6,4) lies
	# windward of b's stern (5,4), into which it drifts. b is the downwind-most ship and goes first.
	var a := _make_ship("a", Vector2i(6, 3))
	a.facing = 4
	var b := _make_ship("b", Vector2i(5, 5))
	assert_eq(_downwind(a.stern_hex()), b.stern_hex(), "fixture: a drifts into b's stern hex")
	_dice.queue([9, 9])  # b's drift roll, then a's; a fouling roll would take the second 9
	resolver.resolve(PHASE)
	assert_eq(b.hex_position, _downwind(Vector2i(5, 5)))
	assert_eq(a.hex_position, _downwind(Vector2i(6, 3)), "b has drifted out of a's way")
	assert_eq(a.fouled_with, "")
	var events := _drift_events()
	assert_eq(events[0].ship_id, "b", "the downwind-most ship rolls first")
	assert_true(events[1].data["drifted"])


func test_ship_that_stayed_put_still_blocks() -> void:
	var a := _make_ship("a", Vector2i(6, 3))
	a.facing = 4
	var b := _make_ship("b", Vector2i(5, 5))
	_dice.queue([0, 9, 0])  # b fails its drift roll; a's drift is blocked; a does not foul
	resolver.resolve(PHASE)
	assert_eq(b.hex_position, Vector2i(5, 5))
	assert_eq(a.hex_position, Vector2i(6, 3))
	var ev: PhaseEvents.PhaseEvent = _drift_events()[1]
	assert_eq(ev.ship_id, "a")
	assert_eq(ev.data["blocked"], "ship")
	assert_eq(ev.target_id, "b")
	assert_false(ev.data["fouled"])
	assert_eq(_dice.remaining(), 0)


# --- plotting lock -----------------------------------------------------------

func _start_plotting(state: ShipState) -> MovementTypes.PlottingResponse:
	GameState.movement_plotting_controller.sessions.clear()
	GameState.movement_plotting_controller.ship_sessions.clear()
	return GameState.movement_plotting_controller.handle_start_plotting(
			state.player_id, state.ship.ship_id, "req")


func test_fouled_ship_cannot_plot() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	a.fouled_with = "b"
	var response := _start_plotting(a)
	assert_true(response is MovementTypes.PlottingErrorResponse)
	assert_eq((response as MovementTypes.PlottingErrorResponse).error_code, "SHIP_FOULED")


func test_struck_ship_cannot_plot() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	a.status = ShipState.Status.STRUCK
	var response := _start_plotting(a)
	assert_eq((response as MovementTypes.PlottingErrorResponse).error_code, "SHIP_STRUCK")


func test_destroyed_ship_cannot_plot() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	a.status = ShipState.Status.DESTROYED
	var response := _start_plotting(a)
	assert_eq((response as MovementTypes.PlottingErrorResponse).error_code, "SHIP_DESTROYED")
	assert_true(StubAI.LOCKED_ERROR_CODES.has("SHIP_DESTROYED"))


func test_dismasted_ship_cannot_plot() -> void:
	var a := _make_ship("a", Vector2i(5, 5))
	_dismast(a)
	var response := _start_plotting(a)
	assert_eq((response as MovementTypes.PlottingErrorResponse).error_code, "SHIP_DISMASTED")


func test_stub_ai_skips_locked_ships_quietly() -> void:
	var fouled := _make_ship("f", Vector2i(5, 5), "MS", 1)
	fouled.fouled_with = "x"
	var struck := _make_ship("s", Vector2i(5, 9), "MS", 1)
	struck.status = ShipState.Status.STRUCK
	var masts := _make_ship("m", Vector2i(5, 13), "MS", 1)
	_dismast(masts)
	GameState.movement_plotting_controller.sessions.clear()
	GameState.movement_plotting_controller.ship_sessions.clear()
	StubAI.new(GameState).plot_all_ai_ships()
	assert_eq(fouled.plotted_actions.movement.size(), 0)
	assert_eq(struck.plotted_actions.movement.size(), 0)
	assert_eq(masts.plotted_actions.movement.size(), 0)


# --- partial drift (8.A.5) ---------------------------------------------------
# Wind from the east, so downwind is west (-1, 0). A ship facing 4 (NW) has its bow at (5,5) and
# its stern at (5,6); stern and downwind are 120 degrees apart, so a free stern can pivot.

func _partial_setup() -> Dictionary:
	var drifter := _make_ship("a", Vector2i(5, 5))
	drifter.facing = 4
	# The blocker holds the bow's downwind hex (4,5) and (4,4), not the stern's (4,6).
	var blocker := _make_ship("b", Vector2i(4, 5))
	blocker.moved_this_turn = true
	return {"drifter": drifter, "blocker": blocker}


func test_partial_drift_stern_free() -> void:
	var s := _partial_setup()
	var drifter: ShipState = s["drifter"]
	_dice.queue([9, 0])  # drift roll, then the fouling roll (a success would be 5 or less)
	resolver.resolve(PHASE)
	assert_eq(drifter.hex_position, Vector2i(5, 5), "bow hex unchanged")
	assert_eq(drifter.stern_hex(), Vector2i(4, 6), "stern one hex downwind")
	assert_eq(drifter.facing, 5, "facing changed by one step")
	var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
	assert_true(ev.data["drifted"])
	assert_eq(ev.data["partial"], "stern")
	assert_eq(ev.data["facing"], 5)
	assert_eq(ev.target_id, "b")
	assert_true(ev.data.has("fouled"), "a fouling roll was made")
	assert_eq(_dice.remaining(), 0, "drift roll and fouling roll both consumed")


func test_partial_drift_bow_free() -> void:
	var drifter := _make_ship("a", Vector2i(5, 5))  # facing 1: stern at (5,4)
	var blocker := _make_ship("b", Vector2i(4, 4))
	blocker.facing = 0  # holds (4,4), the stern's downwind hex, and (3,4)
	blocker.moved_this_turn = true
	_dice.queue([9, 9])
	resolver.resolve(PHASE)
	assert_eq(drifter.hex_position, Vector2i(4, 5), "bow one hex downwind")
	assert_eq(drifter.stern_hex(), Vector2i(5, 4), "stern unchanged")
	assert_eq(drifter.facing, 2)
	var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
	assert_eq(ev.data["partial"], "bow")
	assert_eq(ev.data["facing"], 2)


func test_fouled_ship_never_partially_drifts() -> void:
	var s := _partial_setup()
	var drifter: ShipState = s["drifter"]
	var blocker: ShipState = s["blocker"]
	# Fouled with a third ship far away: it drifts as a group, which is blocked as a whole.
	var third := _make_ship("c", Vector2i(10, 5))
	drifter.fouled_with = "c"
	third.fouled_with = "a"
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_eq(drifter.hex_position, Vector2i(5, 5))
	assert_eq(drifter.facing, 4, "facing unchanged")
	assert_false(_drift_events()[0].data.has("partial"))
	assert_false(_drift_events()[0].data["drifted"])


func test_partial_drift_never_lies_on_hex_spine() -> void:
	# Facing 1: bow (5,5), stern (5,4). A free stern would go to (4,4), two hexes from the bow.
	var drifter := _make_ship("a", Vector2i(5, 5))
	var blocker := _make_ship("b", Vector2i(4, 5))
	blocker.facing = 0  # holds (4,5) and (3,5)
	blocker.moved_this_turn = true
	_dice.queue([9, 9])
	resolver.resolve(PHASE)
	assert_eq(drifter.hex_position, Vector2i(5, 5))
	assert_eq(drifter.facing, 1)
	var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
	assert_false(ev.data["drifted"])
	assert_false(ev.data.has("partial"))
	assert_eq(ev.data["blocked"], "ship")
	assert_eq(ev.target_id, "b")
	assert_eq(_dice.remaining(), 0, "the fouling die was rolled for the blocked drift")
	assert_true(ev.data["fouled"], "9 - 1 + 1 + 1 (both at MS) fouls")


func test_partial_drift_fouling_roll_fouls() -> void:
	var s := _partial_setup()
	_dice.queue([9, 9])  # fouling: 9 - 1 (drifting) + 1 + 1 (both at MS) = 10, 6+ fouls
	resolver.resolve(PHASE)
	var drifter: ShipState = s["drifter"]
	var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
	assert_eq(ev.data["partial"], "stern")
	assert_true(ev.data["fouled"])
	assert_eq(drifter.fouled_with, "b")
	assert_eq((s["blocker"] as ShipState).fouled_with, "a")


func test_partial_drift_fouling_roll_misses() -> void:
	var s := _partial_setup()
	_dice.queue([9, 0])  # fouling: 0 - 1 + 1 + 1 = 1
	resolver.resolve(PHASE)
	var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
	assert_eq(ev.data["partial"], "stern")
	assert_false(ev.data["fouled"])
	assert_eq((s["drifter"] as ShipState).fouled_with, "")
	assert_eq((s["blocker"] as ShipState).fouled_with, "")


## Wind from the east, downwind 3 (west). A free stern can swing when downwind is facing +-1, a
## free bow when downwind is facing +-2 (5.A.2c: the result must still be two neighbouring hexes).
## Facing 0 cannot have its bow blocked (its bow drifts into its own stern hex), nor facing 3 its
## stern; a free end that would drift onto its own other end does not drift.
const PARTIAL_TABLE := {
	0: {"bow": false},
	1: {"bow": true, "stern": false},
	2: {"bow": false, "stern": true},
	3: {"stern": false},
	4: {"bow": false, "stern": true},
	5: {"bow": true, "stern": false},
}


func test_partial_drift_by_facing() -> void:
	for facing in PARTIAL_TABLE:
		var cases: Dictionary = PARTIAL_TABLE[facing]
		for free_end in cases:
			GameState.ships.clear()
			GameState.ships_by_player = {0: [], 1: []}
			GameState.turn_log = PhaseEvents.PhaseLog.new()
			var drifter := _make_ship("a", Vector2i(5, 5))
			drifter.facing = facing
			var bow := drifter.hex_position
			var stern := drifter.stern_hex()
			var free_hex: Vector2i = _downwind(stern if free_end == "stern" else bow)
			var held_hex: Vector2i = _downwind(bow if free_end == "stern" else stern)
			var blocker := _make_ship("b", held_hex)
			blocker.moved_this_turn = true
			for f in 6:
				blocker.facing = f
				if not blocker.stern_hex() in [free_hex, bow, stern]:
					break
			_dice.queue([9, 0])
			resolver.resolve(PHASE)
			var label := "facing %d, free %s" % [facing, free_end]
			var ev: PhaseEvents.PhaseEvent = _drift_events()[0]
			assert_eq(_dice.remaining(), 0, label + ": drift and fouling rolls")
			assert_eq(ev.target_id, "b", label)
			if cases[free_end]:
				assert_eq(ev.data.get("partial", ""), free_end, label)
				var moved_hex: Vector2i = drifter.stern_hex() if free_end == "stern" else drifter.hex_position
				assert_eq(moved_hex, free_hex, label + ": the free end drifted")
				var kept_hex: Vector2i = drifter.hex_position if free_end == "stern" else drifter.stern_hex()
				assert_eq(kept_hex, bow if free_end == "stern" else stern, label + ": the held end stayed")
			else:
				assert_false(ev.data.has("partial"), label)
				assert_false(ev.data["drifted"], label)
				assert_eq(ev.data["blocked"], "ship", label)
				assert_eq(drifter.hex_position, bow, label)
				assert_eq(drifter.facing, facing, label)
