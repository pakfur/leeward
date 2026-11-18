extends GutTest
## Escape at the end of the turn (Scenario Book V.D.1-4): by distance (31+ hexes from every
## pursuer) or by speed (20-30 hexes, and no pursuer of the same or larger class 20-30 hexes off
## is faster), resolved in END_TURN after the 8.G.1f removals and before the victory check; the
## declaration is reported to the enemy only then.

const PHASES := TurnPhaseController.GamePhase
const WIND_FROM_E := 0  # a ship heading west (facing 3) runs before it: wind facing "R"
const WIND_SPEED := 3
const ESCAPER_BOW := Vector2i(-20, 0)  # facing 3: hexes (-20, 0) and (-19, 0)

var pc: TurnPhaseController
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_logs: Dictionary
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _old_turn: int


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_speed_change_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_logs = GameState.turn_logs
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	_old_turn = GameState.current_turn
	GameState.dice = Dice.new(GameState.rng)
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.turn_logs = {}
	GameState.active_scenario = {"map_bounds": {"width": 100, "height": 100}, "escape": {"1": {}}}
	var env := EnvironmentState.new()
	env.wind_speed = WIND_SPEED
	env.sea_state = 1
	env.wind_direction = WIND_FROM_E
	GameState.environment = env
	GameState.current_turn = 1
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	pc.game_result = {}
	pc.combat_step = TurnPhaseController.CombatStep.NONE


func after_each() -> void:
	pc.game_result = {}
	pc.current_phase = PHASES.SETUP
	pc.players_ready = {}
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.turn_logs = _old_logs
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


## A ship of `type_id` (its ships.json data), class overridable, facing west in row 0.
func _make_ship(id: String, side: int, bow: Vector2i, type_id: String = "frigate_38",
		ship_class: int = -1) -> ShipState:
	var def := DataManager.get_ship_definition(type_id)
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": type_id, "name": def.name, "nationality": "British",
		"rating": def.rating, "class": def.ship_class if ship_class < 0 else ship_class,
		"maneuverability": def.maneuverability, "speed_type": def.speed_type,
		"rigging_hp": def.rigging_hp, "hull_hp": def.hull_hp,
		"crew_count": def.crew_count, "marine_count": def.marine_count,
		"gun_factors": {"lg": 10, "mg": 0, "cr": 0},
		"point_costs": def.point_costs,
	})
	state.hex_position = bow
	state.facing = 3
	state.speed = 1
	state.sail_state = "PS"
	var rigging: Array[int] = []
	rigging.assign(def.rigging_hp)
	state.rigging_current_hp = rigging
	var hull: Array[int] = []
	hull.assign(def.hull_hp)
	state.hull_current_hp = hull
	var crew: Array[int] = []
	crew.assign(def.crew_count)
	state.crew_count = crew
	state.marine_count = def.marine_count
	state.crew_quality = "D"
	state.starting_crew_quality = "D"
	state.morale_rating = 4
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


## The declared side-1 escaper (frigate_32) at ESCAPER_BOW.
func _escaper() -> ShipState:
	var s := _make_ship("esc", 1, ESCAPER_BOW, "frigate_32")
	s.escape_declared = true
	return s


## A side-0 ship whose nearest hex is `range` hexes from the escaper's stern (-19, 0).
func _pursuer(id: String, range: int, type_id: String = "frigate_38", ship_class: int = -1) -> ShipState:
	return _make_ship(id, 0, Vector2i(-19 + range, 0), type_id, ship_class)


## The table MA at wind facing R and WIND_SPEED for `type_id`, at `sail` and rigging level `level`.
func _table(type_id: String, sail: String, level: int) -> int:
	return DataManager.get_movement_allowance(DataManager.get_ship_definition(type_id).speed_type,
			WIND_SPEED, "R", sail, level)


func _resolve() -> void:
	GameState.map_controller.resolve_escapes(GameState.current_turn, PHASES.END_TURN)


func _events(type: int, log: PhaseEvents.PhaseLog = null) -> Array:
	var out: Array = []
	for ev in (log if log != null else GameState.turn_log).events:
		if ev.type == type:
			out.append(ev)
	return out


func _empty_rigging(ship: ShipState, sections: int) -> void:
	for i in sections:
		ship.rigging_current_hp[i] = 0


func _end_turn(turn: int = 1) -> void:
	pc.current_turn = turn
	GameState.current_turn = turn
	GameState.turn_log.turn = turn
	pc.current_phase = PHASES.POST_COMBAT
	assert_true(pc.player_end_turn(0), "End Turn accepted in POST_COMBAT")


# ---------- MapRules ----------

func test_max_ma_values() -> void:
	var s := _make_ship("a", 0, Vector2i(0, 0), "frigate_38")
	var expected := _table("frigate_38", "ps", 4)
	assert_gt(expected, 0)
	assert_eq(MapRules.max_ma(s, "R", WIND_SPEED), expected, "full rig: plain sail, level 4")
	assert_eq(MapRules.max_ma(s, "L", WIND_SPEED), 0, "luffing")
	assert_eq(MapRules.max_ma(s, "R", 0), 0, "calm")
	_empty_rigging(s, 4)
	assert_eq(MapRules.max_ma(s, "R", WIND_SPEED), 0, "dismasted")
	var d := _make_ship("b", 0, Vector2i(0, 4), "frigate_38")
	_empty_rigging(d, 1)
	assert_eq(MapRules.max_ma(d, "R", WIND_SPEED), _table("frigate_38", "ms", 3), "3 sections: MS")
	assert_eq(MapRules.max_ma_heading(d, 3, WIND_FROM_E, WIND_SPEED),
			MapRules.max_ma(d, "R", WIND_SPEED), "heading west with the wind from the east runs")


func test_footprint_range_closest_hexes() -> void:
	var a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var b: Array[Vector2i] = [Vector2i(5, 0), Vector2i(6, 0)]
	assert_eq(MapRules.footprint_range(a, b), 4)
	assert_eq(MapRules.footprint_range(b, a), 4)


# ---------- resolve_escapes ----------

func test_distance_31_escapes_30_does_not() -> void:
	var esc := _escaper()
	_pursuer("p", 31)
	_resolve()
	assert_eq(esc.status, ShipState.Status.ESCAPED)
	assert_false(esc.is_on_map(), "an escaped ship leaves the map")
	assert_false(Occupancy.build(GameState.get_all_ships()).has(ESCAPER_BOW), "and holds no hex")
	var escaped := _events(PhaseEvents.Type.ESCAPED)
	assert_eq(escaped.size(), 1)
	assert_eq(escaped[0].data["how"], "distance")
	assert_eq(escaped[0].data["range"], 31)

	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	esc = _escaper()
	var p := _pursuer("p", 30)
	assert_gt(MapRules.max_ma(p, "R", WIND_SPEED), MapRules.max_ma(esc, "R", WIND_SPEED),
		"the pursuer is faster")
	_resolve()
	assert_eq(esc.status, ShipState.Status.ACTIVE)
	assert_true(esc.is_on_map())
	assert_eq(_events(PhaseEvents.Type.ESCAPED).size(), 0)


func test_speed_condition_counts_same_or_larger_class() -> void:
	# A slower class-3 pursuer at 25: escapes by speed.
	var esc := _escaper()
	var p := _pursuer("p", 25)
	_empty_rigging(p, 2)  # 2 sections: fighting sail only
	assert_eq(MapRules.max_ma(p, "R", WIND_SPEED), _table("frigate_38", "fs", 2))
	assert_eq(MapRules.max_ma(esc, "R", WIND_SPEED), _table("frigate_32", "ps", 4))
	assert_lt(_table("frigate_38", "fs", 2), _table("frigate_32", "ps", 4))
	_resolve()
	assert_eq(esc.status, ShipState.Status.ESCAPED)
	var escaped := _events(PhaseEvents.Type.ESCAPED)
	assert_eq(escaped[0].data["how"], "speed")
	assert_eq(escaped[0].data["range"], 25)

	# The escaper's rigging cut below a full-rigged class-3 pursuer: stays.
	var cases := [
		{"class": 3, "escapes": false, "why": "the same class counts"},
		{"class": 4, "escapes": true, "why": "a smaller class does not count"},
		{"class": 2, "escapes": false, "why": "a larger class counts"},
	]
	for c in cases:
		GameState.ships.clear()
		GameState.ships_by_side = {0: [], 1: []}
		GameState.turn_log = PhaseEvents.PhaseLog.new()
		esc = _escaper()
		_empty_rigging(esc, 1)  # 3 sections: manoeuvring sail
		p = _pursuer("p", 25, "frigate_38", c["class"])
		assert_eq(MapRules.max_ma(esc, "R", WIND_SPEED), _table("frigate_32", "ms", 3))
		assert_eq(MapRules.max_ma(p, "R", WIND_SPEED), _table("frigate_38", "ps", 4))
		assert_lt(_table("frigate_32", "ms", 3), _table("frigate_38", "ps", 4))
		_resolve()
		assert_eq(esc.status == ShipState.Status.ESCAPED, c["escapes"], c["why"])


func test_no_pursuer_escapes_by_distance() -> void:
	var esc := _escaper()
	var p := _pursuer("p", 5)
	p.status = ShipState.Status.STRUCK
	_resolve()
	assert_eq(esc.status, ShipState.Status.ESCAPED)
	var escaped := _events(PhaseEvents.Type.ESCAPED)
	assert_eq(escaped[0].data["how"], "distance")
	assert_eq(escaped[0].data["range"], -1)


func test_aground_enemy_is_not_a_pursuer() -> void:
	var esc := _escaper()
	var p := _pursuer("p", 5)
	GameState.ship_controller.set_aground("p", 1)
	assert_true(p.is_aground())
	assert_eq(GameState.map_controller.pursuers(esc).size(), 0)
	_resolve()
	assert_eq(esc.status, ShipState.Status.ESCAPED)
	assert_eq(_events(PhaseEvents.Type.ESCAPED)[0].data["range"], -1)


func test_undeclared_unpermitted_or_early_never_escapes() -> void:
	var undeclared := _make_ship("esc", 1, ESCAPER_BOW, "frigate_32")
	var side0 := _make_ship("s0", 0, Vector2i(-20, 10), "frigate_32")
	side0.escape_declared = true  # side 0 has no escape permission
	_make_ship("far0", 0, Vector2i(40, 40))
	_make_ship("far1", 1, Vector2i(40, -40))
	_resolve()
	assert_eq(undeclared.status, ShipState.Status.ACTIVE, "undeclared")
	assert_eq(side0.status, ShipState.Status.ACTIVE, "no permission")

	GameState.active_scenario = {"map_bounds": {"width": 100, "height": 100},
		"escape": {"1": {"from_turn": 5}}}
	undeclared.escape_declared = true
	_resolve()
	assert_eq(undeclared.status, ShipState.Status.ACTIVE, "before from_turn")
	assert_eq(_events(PhaseEvents.Type.ESCAPED).size(), 0)


func test_linked_ship_does_not_escape() -> void:
	var esc := _escaper()
	_make_ship("friend", 1, Vector2i(-20, 1))
	GameState.ship_controller.add_grapple("esc", "friend")
	_pursuer("p", 40)
	_resolve()
	assert_eq(esc.status, ShipState.Status.ACTIVE)
	assert_eq(_events(PhaseEvents.Type.ESCAPED).size(), 0)


# ---------- END_TURN ----------

func test_escape_declared_reported_at_end_turn_only() -> void:
	var esc := _make_ship("esc", 1, ESCAPER_BOW, "frigate_32")
	_pursuer("p", 25)  # faster, same class: she stays this turn
	_make_ship("friend", 1, Vector2i(-20, 20))
	pc.current_turn = 1
	pc.current_phase = PHASES.PLANNING
	pc.players_ready = {0: false, 1: false}
	assert_eq(pc.player_declare_escape(1, "esc", true), "")
	assert_true(esc.escape_declared)
	assert_false(GameState.player_view.ship_for(0, "esc").has("escape_declared"),
		"the enemy does not see the declaration")
	assert_true(GameState.player_view.ship_for(1, "esc")["escape_declared"], "her captain does")
	for ev in GameState.player_view.events_for(0, 1):
		assert_ne(ev["type"], PhaseEvents.Type.ESCAPE_DECLARED, "not reported during PLANNING")
	_end_turn(1)
	var declared := 0
	for ev in GameState.player_view.events_for(0, 1):
		if ev["type"] == PhaseEvents.Type.ESCAPE_DECLARED:
			declared += 1
	assert_eq(declared, 1, "reported at the end of the turn")


func test_end_turn_order() -> void:
	_escaper()
	_make_ship("p", 0, Vector2i(30, 0))  # 48 hexes off: escape by distance
	var wreck := _make_ship("w", 0, Vector2i(0, 30))
	GameState.damage_controller.destroy("w", "test", PHASES.COMBAT_RESOLUTION)
	_end_turn(1)
	assert_false(wreck.is_on_map(), "8.G.1f removal")
	var log: PhaseEvents.PhaseLog = GameState.turn_logs[1]
	var types: Array = []
	for ev in log.events:
		types.append(ev.type)
	var declared := types.find(PhaseEvents.Type.ESCAPE_DECLARED)
	var escaped := types.find(PhaseEvents.Type.ESCAPED)
	var victory := types.find(PhaseEvents.Type.VICTORY)
	assert_gt(declared, -1)
	assert_gt(escaped, declared, "ESCAPE_DECLARED precedes ESCAPED")
	assert_gt(victory, escaped, "the victory check runs after the escapes")
	assert_false(GameState.get_ship("esc").is_on_map(), "the escaped ship is off the map")
