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
