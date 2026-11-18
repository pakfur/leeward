extends GutTest
## MapRules (escape permission, crossing outcomes) and MapController (ground, escape, lose_off_map),
## and the map event texts.

const PHASE := 4

var _old_log: PhaseEvents.PhaseLog
var _old_scenario: Dictionary


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	_old_log = GameState.turn_log
	_old_scenario = GameState.active_scenario
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func after_each() -> void:
	GameState.turn_log = _old_log
	GameState.active_scenario = _old_scenario
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, player: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	state.hex_position = Vector2i(0, 0)
	state.facing = 3
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.marine_count = 2
	GameState.ships[id] = state
	GameState.ships_by_side[player].append(id)
	return state


func _names() -> Dictionary:
	var out := {}
	for id in GameState.ships:
		out[id] = id
	return out


func _text(index: int = 0) -> String:
	return GameState.turn_log.events[index].to_text(_names())


func test_ground_sets_aground_and_logs() -> void:
	var a := _make_ship("a", 0)
	GameState.map_controller.ground("a", {"cause": "movement", "terrain": "shallow",
		"hex": {"q": 2, "r": 0}, "depth": 16, "draft": 16}, PHASE)
	assert_true(a.is_aground())
	assert_eq(a.aground_turn, GameState.current_turn)
	assert_eq(GameState.turn_log.events.size(), 1)
	assert_eq(GameState.turn_log.events[0].type, PhaseEvents.Type.AGROUND)
	assert_string_contains(_text(), "runs aground")
	assert_string_contains(_text(), "16 ft")


func test_escape_removes_and_frees_partner() -> void:
	var a := _make_ship("a", 1)
	var b := _make_ship("b", 1)
	GameState.ship_controller.set_fouled_with("a", "b")
	GameState.ship_controller.set_fouled_with("b", "a")
	GameState.map_controller.escape("a", {"how": "edge", "edge": "W"}, PHASE)
	assert_eq(a.status, ShipState.Status.ESCAPED)
	assert_false(a.is_on_map())
	assert_eq(b.fouled_with, "")
	assert_string_contains(_text(), "escapes off the west edge")


func test_escape_of_ship_out_of_play_is_a_noop() -> void:
	var a := _make_ship("a", 1)
	a.status = ShipState.Status.STRUCK
	GameState.map_controller.escape("a", {"how": "edge", "edge": "W"}, PHASE)
	assert_eq(a.status, ShipState.Status.STRUCK)
	assert_eq(GameState.turn_log.events.size(), 0)


func test_lose_off_map_destroys_and_removes() -> void:
	var a := _make_ship("a", 1)
	GameState.map_controller.lose_off_map("a", "E", PHASE)
	assert_true(a.is_destroyed())
	assert_false(a.is_on_map())
	var ev := GameState.turn_log.events[0]
	assert_eq(ev.type, PhaseEvents.Type.DESTROYED)
	assert_eq(ev.data["reason"], "no_sea_room")
	assert_eq(ev.data["edge"], "E")
	assert_string_contains(_text(), "no sea room")


func test_permission_defaults_and_values() -> void:
	var s := {"escape": {"1": {"from_turn": 5, "edges": ["W"], "share": 0.9}}}
	assert_eq(MapRules.permission(s, 1), {"from_turn": 5, "edges": ["W"], "share": 0.9})
	assert_eq(MapRules.permission(s, 0), {})
	assert_false(MapRules.may_declare(s, 1, 4))
	assert_true(MapRules.may_declare(s, 1, 5))
	assert_string_contains(MapRules.declare_error(s, 0, 9), "may not escape")
	assert_string_contains(MapRules.declare_error(s, 1, 4), "from turn 5")
	assert_eq(MapRules.declare_error(s, 1, 5), "")
	assert_eq(MapRules.share(s, 1), 0.9)
	assert_eq(MapRules.share(s, 0), 0.0)
	assert_eq(MapRules.permission({"escape": {"1": {}}}, 1), {"from_turn": 1, "edges": [], "share": 0.0})


func test_crossing_outcome_table() -> void:
	var s := {"map_bounds": {"width": 10, "height": 10},
		"terrain": {"edges": {"N": "open", "E": "none", "S": "open", "W": "escape"}},
		"escape": {"1": {}}}
	var ship := _make_ship("a", 1)
	var out := MapRules.crossing_outcome(s, ship, Vector2i(0, 0), Vector2i(1, 0), 1)
	assert_eq(out["outcome"], MapRules.CLEAR)
	out = MapRules.crossing_outcome(s, ship, Vector2i(0, -5), Vector2i(0, -6), 1)
	assert_eq(out["outcome"], MapRules.BLOCKED)
	assert_eq(out["edge"], "N")
	out = MapRules.crossing_outcome(s, ship, Vector2i(4, 0), Vector2i(5, 0), 1)
	assert_eq(out["outcome"], MapRules.LOST)
	assert_eq(out["edge"], "E")
	out = MapRules.crossing_outcome(s, ship, Vector2i(-5, 0), Vector2i(-6, 0), 1)
	assert_eq(out["outcome"], MapRules.BLOCKED)
	ship.escape_declared = true
	out = MapRules.crossing_outcome(s, ship, Vector2i(-5, 0), Vector2i(-6, 0), 1)
	assert_eq(out["outcome"], MapRules.ESCAPE)
	assert_eq(out["edge"], "W")
	var enemy := _make_ship("b", 0)
	enemy.escape_declared = true
	out = MapRules.crossing_outcome(s, enemy, Vector2i(-5, 0), Vector2i(-6, 0), 1)
	assert_eq(out["outcome"], MapRules.BLOCKED)


func test_new_event_texts() -> void:
	_make_ship("a", 0)
	_make_ship("b", 0)
	var log := GameState.turn_log
	log.add(PhaseEvents.Type.LEAD_CAST, PHASE, "a", {"hex": {"q": 3, "r": 10}, "depth": 16,
		"draft": 18, "outcome": "bears_off", "side": 1})
	log.add(PhaseEvents.Type.ESCAPE_DECLARED, PHASE, "a")
	log.add(PhaseEvents.Type.ESCAPED, PHASE, "a", {"how": "range", "range": 31})
	log.add(PhaseEvents.Type.ARRIVED, PHASE, "a", {"hex": {"q": -18, "r": 0}, "facing": 0,
		"sail_state": "PS", "speed": 2})
	log.add(PhaseEvents.Type.ARRIVAL_DELAYED, PHASE, "a", {}, "b")
	assert_string_contains(_text(0), "casts the lead")
	assert_string_contains(_text(0), "bears off to starboard")
	assert_string_contains(_text(1), "is trying to escape")
	assert_string_contains(_text(2), "31 hexes")
	assert_string_contains(_text(3), "arrives at")
	assert_string_contains(_text(3), "plain sail")
	assert_string_contains(_text(4), "will try next turn")
	assert_eq(PhaseEvents.edge_label("N"), "north")
	assert_eq(PhaseEvents.edge_label("Reef"), "Reef")


func test_map_edge_stop_drift_aground_texts() -> void:
	_make_ship("a", 0)
	var log := GameState.turn_log
	log.add(PhaseEvents.Type.STOPPED_SHORT, PHASE, "a", {"cause": "map_edge"})
	log.add(PhaseEvents.Type.DRIFT, PHASE, "a", {"blocked": "aground"})
	assert_string_contains(_text(0), "stops at the edge of the map")
	assert_string_contains(_text(1), "drifts aground")
