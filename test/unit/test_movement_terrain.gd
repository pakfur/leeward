extends GutTest
## MovementResolver at typed map edges and over land and shallows (map and scenario spec §3-§4,
## 13.G.2): open edges stop a forced step, `none` and crossable escape edges take the ship off the
## map, land and shoals run it aground where it stands. The depth die comes from the resolver's rng,
## before the ship's rigging dice, so re-runs repeat it.
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")

var resolver: MovementResolver
var rng: RandomNumberGenerator
var env: EnvironmentState
var _saved_turn_log: PhaseEvents.PhaseLog
var _saved_turn: int
var _saved_scenario: Dictionary
var _saved_env: EnvironmentState


func before_all() -> void:
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_turning_table()
	DataManager.load_movement_allowance_table()
	DataManager.load_speed_change_table()


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 12345
	resolver = MovementResolver.new(GameState, rng)
	env = EnvironmentState.new()
	env.wind_direction = 3  # from the west: a ship heading east runs, so turns need no Tacking roll
	env.wind_speed = 3
	env.sea_state = 1
	_saved_env = GameState.environment
	GameState.environment = env
	GameState.ships.clear()
	_saved_turn_log = GameState.turn_log
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	_saved_turn = GameState.current_turn
	GameState.current_turn = 1
	_saved_scenario = GameState.active_scenario
	GameState.active_scenario = {}


func after_each() -> void:
	GameState.current_turn = _saved_turn
	GameState.turn_log = _saved_turn_log
	GameState.active_scenario = _saved_scenario
	GameState.environment = _saved_env
	GameState.ships.clear()


func _make_ship_def(ship_id: String, side: int, maneuverability: String) -> Ship:
	return Ship.from_dict({
		"ship_id": ship_id,
		"player_id": side,
		"ship_name": "Ship " + ship_id,
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": maneuverability,
		"speed_type": "F/F",
		"draft": 16,
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
	})


func _ship(ship_id: String, hex_pos: Vector2i, facing: int = 0, speed: int = 3, side: int = 0,
		maneuverability: String = "C", crew_quality: String = "B") -> ShipState:
	var state = ShipState.new()
	state.ship = _make_ship_def(ship_id, side, maneuverability)
	state.hex_position = hex_pos
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3]
	state.crew_count = crew
	state.marine_count = 2
	state.crew_quality = crew_quality
	CrewFixtures.give_tack_crew(state, 3)
	GameState.ships[ship_id] = state
	return state


## `steps` ahead on the ship's facing, written straight into the plot (no validator).
func _plot_straight(state: ShipState, steps: int) -> void:
	var movement: Array = []
	var current_hex = state.hex_position
	for i in range(steps):
		current_hex = current_hex + HexGrid.DIRECTIONS[state.facing]
		movement.append({"hex": {"q": current_hex.x, "r": current_hex.y}, "facing": state.facing})
	GameState.ship_controller.set_plotted_movement(state.ship_id, movement)


func _plot_turn(state: ShipState, new_facing: int) -> void:
	GameState.ship_controller.set_plotted_movement(state.ship_id,
		[{"hex": {"q": state.hex_position.x, "r": state.hex_position.y}, "facing": new_facing}])


func _hexes(list: Array) -> Array:
	var out: Array = []
	for h in list:
		out.append([h.x, h.y])
	return out


func _scenario(terrain: Dictionary, extra: Dictionary = {}) -> Dictionary:
	return {"terrain": terrain}.merged(extra)


func _bounded(edges: Dictionary, extra: Dictionary = {}) -> Dictionary:
	return {"map_bounds": {"width": 10, "height": 10}, "terrain": {"edges": edges}}.merged(extra)


func _events_of(result: MovementTypes.ShipResolutionResult, event_type: int) -> Array:
	var out: Array = []
	for ev in result.events:
		if ev.event_type == event_type:
			out.append(ev)
	return out


func _probe() -> RandomNumberGenerator:
	var probe := RandomNumberGenerator.new()
	probe.state = rng.state
	return probe


func _turn_log_of(type: int) -> Array:
	var out: Array = []
	for ev in GameState.turn_log.events:
		if ev.type == type:
			out.append(ev)
	return out


# ===========================================================================
# Land and shallows (13.G.2)
# ===========================================================================

func test_ahead_into_land_runs_aground_in_place() -> void:
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(2, 0)])})
	var a := _ship("a", Vector2i(0, 0))
	_plot_straight(a, 3)
	var probe := _probe()
	var log = resolver.run([a] as Array[ShipState], env)
	var r = log.get_result("a")
	assert_eq(r.final_hex, Vector2i(1, 0), "The ship stays in the hexes it held before the step")
	assert_true(r.aground)
	assert_eq(r.aground_data.get("terrain"), "land")
	assert_eq(r.aground_data.get("depth"), -1)
	assert_eq(r.aground_data.get("draft"), 16)
	assert_eq(r.aground_data.get("hex"), {"q": 2, "r": 0})
	assert_eq(r.rigging_damage, probe.randi_range(1, 6) + 1, "6.E.3 at MS: d6+1, no depth die for land")
	assert_eq(_events_of(r, MovementTypes.ResolutionEventType.AGROUND).size(), 1)
	assert_eq(r.stopped_at_impulse, 1)


func test_turn_swinging_stern_onto_land_runs_aground() -> void:
	# Bow (0,0) facing E: a starboard turn swings the stern into (0,-1), the NW neighbour.
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(0, -1)])})
	var a := _ship("a", Vector2i(0, 0))
	_plot_turn(a, 1)
	var log = resolver.run([a] as Array[ShipState], env)
	var r = log.get_result("a")
	assert_true(r.aground, "13.G.2b: bow or stern")
	assert_eq(r.final_facing, 0, "The turn is not made")
	assert_eq(r.aground_data.get("hex"), {"q": 0, "r": -1})


func test_certain_shoal_grounds() -> void:
	GameState.active_scenario = _scenario({"shallow": [{"name": "bar", "base": 10, "hexes": _hexes([Vector2i(2, 0)])}]})
	var a := _ship("a", Vector2i(0, 0))
	_plot_straight(a, 3)
	var probe := _probe()
	var log = resolver.run([a] as Array[ShipState], env)
	var r = log.get_result("a")
	assert_eq(r.final_hex, Vector2i(1, 0))
	assert_true(r.aground)
	assert_eq(r.aground_data.get("terrain"), "shallow")
	assert_eq(r.aground_data.get("depth"), 10 + probe.randi_range(1, 6), "Depth die first")
	assert_eq(r.rigging_damage, probe.randi_range(1, 6) + 1, "Then the rigging die")


func test_deep_enough_shoal_is_entered() -> void:
	GameState.active_scenario = _scenario({"shallow": [{"name": "bank", "base": 16, "hexes": _hexes([Vector2i(2, 0)])}]})
	var a := _ship("a", Vector2i(0, 0))
	_plot_straight(a, 3)
	var log = resolver.run([a] as Array[ShipState], env)
	var r = log.get_result("a")
	assert_eq(r.final_hex, Vector2i(3, 0))
	assert_false(r.aground, "Depth 17-22 is more than draft 16")


func test_doubtful_shoal_uses_the_resolver_rng() -> void:
	for seed_value in range(1, 13):
		rng.seed = seed_value
		GameState.active_scenario = _scenario({"shallow": [{"name": "bank", "base": 15, "hexes": _hexes([Vector2i(2, 0)])}]})
		var a := _ship("a", Vector2i(0, 0))
		_plot_straight(a, 3)
		var probe := _probe()
		var log = resolver.run([a] as Array[ShipState], env)
		assert_eq(log.get_result("a").aground, probe.randi_range(1, 6) == 1,
			"seed %d: depth 15+d6 <= 16 only on a 1" % seed_value)


func test_stern_entry_into_shoal_never_rolls() -> void:
	var a := _ship("a", Vector2i(0, 0))
	_plot_turn(a, 1)
	var start := rng.state
	var plain = resolver.run([a] as Array[ShipState], env).to_dict()
	var plain_state := rng.state
	GameState.active_scenario = _scenario({"shallow": [{"name": "bar", "base": 10, "hexes": _hexes([Vector2i(0, -1)])}]})
	rng.state = start
	var log = resolver.run([a] as Array[ShipState], env)
	assert_false(log.get_result("a").aground, "A turn does not move the bow: no depth roll")
	assert_eq(log.to_dict(), plain)
	assert_eq(rng.state, plain_state, "No die drawn")


func test_aground_ship_is_an_obstacle() -> void:
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(1, 0)])})
	var a := _ship("a", Vector2i(0, 0))  # bow (0,0), stern (-1,0): grounds on its first step
	_plot_straight(a, 2)
	var b := _ship("b", Vector2i(0, 2), 4)  # heading NW: (0,1) on segment 0, then a's bow (0,0)
	_plot_straight(b, 2)
	var log = resolver.run([a, b] as Array[ShipState], env)
	assert_true(log.get_result("a").aground)
	var grounded := _events_of(log.get_result("a"), MovementTypes.ResolutionEventType.AGROUND)
	assert_eq(grounded.size(), 1)
	if not grounded.is_empty():
		assert_eq(grounded[0].impulse, 0)
	assert_eq(log.get_result("b").blocked_by, "a", "A ship aground is in the way like any stopped ship")


func test_aground_applied() -> void:
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(2, 0)])})
	var a := _ship("a", Vector2i(0, 0))
	_plot_straight(a, 3)
	var ships: Array[ShipState] = [a]
	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	assert_eq(a.speed, 0, "5.E.3b, as after a collision")
	assert_true(a.is_aground())
	assert_eq(a.hex_position, Vector2i(1, 0))
	var aground := _turn_log_of(PhaseEvents.Type.AGROUND)
	var damage := _turn_log_of(PhaseEvents.Type.DAMAGE)
	assert_eq(aground.size(), 1)
	assert_eq(damage.size(), 1, "The rigging loss goes through DamageController")
	if aground.is_empty() or damage.is_empty():
		return
	assert_eq(aground[0].data.get("cause"), "movement")
	assert_eq(aground[0].data.get("terrain"), "land")
	assert_false(aground[0].data.has("rigging_loss"), "DAMAGE carries the boxes")
	var events: Array = GameState.turn_log.events
	assert_lt(events.find(aground[0]), events.find(damage[0]), "AGROUND before DAMAGE")
	assert_eq(_turn_log_of(PhaseEvents.Type.STOPPED_SHORT).size(), 0, "Aground is not stopping short")


# ===========================================================================
# Map edges (spec §3)
# ===========================================================================

func test_open_edge_stops_forced_step() -> void:
	# 10 x 10: columns -5..4. Bow (3,0) facing E: (4,0) is on the map, (5,0) is not.
	GameState.active_scenario = _bounded({})
	var a := _ship("a", Vector2i(3, 0))
	_plot_straight(a, 3)
	var ships: Array[ShipState] = [a]
	var log = resolver.run(ships, env)
	var r = log.get_result("a")
	assert_eq(r.final_hex, Vector2i(4, 0))
	var blocked := _events_of(r, MovementTypes.ResolutionEventType.EDGE_BLOCKED)
	assert_eq(blocked.size(), 1)
	if not blocked.is_empty():
		assert_eq(blocked[0].detail, "E")
	assert_eq(r.left_map, "")
	resolver.apply_results(log, ships)
	var short := _turn_log_of(PhaseEvents.Type.STOPPED_SHORT)
	assert_eq(short.size(), 1)
	if not short.is_empty():
		assert_eq(short[0].data.get("cause"), "map_edge")
		assert_eq(short[0].data.get("edge"), "E")
		assert_eq(short[0].data.get("moved"), 1)


func test_bear_off_amendment_stops_at_open_edge() -> void:
	# 10 x 10: rows -5..4. The mover sails east along row 4 into a stopped ship; bearing off to
	# starboard (SE, away from the blocker) and then one hex ahead would leave the map by the S edge.
	GameState.active_scenario = _bounded({})
	var blocker := _ship("blocker", Vector2i(0, 4), 1, 0)  # bow (0,4), stern (0,3)
	var mover := _ship("mover", Vector2i(-2, 4), 0, 7, 0, "D", "A")
	_plot_straight(mover, 3)
	var ships: Array[ShipState] = [mover, blocker]
	var found := false
	for seed_value in range(1, 40):
		rng.seed = seed_value
		var log = resolver.run(ships, env)
		var r = log.get_result("mover")
		var rolls := _events_of(r, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
		if rolls.is_empty() or not rolls[0].success:
			continue
		found = true
		assert_eq(r.final_facing, 1, "Bore off to starboard")
		assert_eq(r.final_hex, Vector2i(-1, 4), "The step ahead off the map is not made")
		assert_eq(_events_of(r, MovementTypes.ResolutionEventType.EDGE_BLOCKED).size(), 1)
		assert_true(TerrainMap.of(GameState.active_scenario).in_bounds(r.final_hex))
		assert_eq(r.left_map, "")
		break
	assert_true(found, "Some seed bears off")


func test_none_edge_loses_the_ship() -> void:
	GameState.active_scenario = _bounded({"E": "none"})
	var a := _ship("a", Vector2i(3, 0))
	_plot_straight(a, 3)
	var ships: Array[ShipState] = [a]
	var log = resolver.run(ships, env)
	var r = log.get_result("a")
	assert_eq(r.left_map, MapRules.LOST)
	assert_eq(r.left_edge, "E")
	assert_eq(r.final_hex, Vector2i(5, 0), "The step is made, then the ship stops")
	assert_eq(_events_of(r, MovementTypes.ResolutionEventType.LEFT_MAP).size(), 1)
	assert_eq(_events_of(r, MovementTypes.ResolutionEventType.MOVE).size(), 2)
	resolver.apply_results(log, ships)
	assert_true(a.is_destroyed())
	assert_false(a.is_on_map())
	var destroyed := _turn_log_of(PhaseEvents.Type.DESTROYED)
	assert_eq(destroyed.size(), 1)
	if not destroyed.is_empty():
		assert_eq(destroyed[0].data.get("reason"), "no_sea_room")
	assert_eq(_turn_log_of(PhaseEvents.Type.STOPPED_SHORT).size(), 0)


func test_declared_ship_escapes_off_escape_edge() -> void:
	# Bow (-4,0) facing W: (-5,0) is the last column, (-6,0) is off the map.
	GameState.active_scenario = _bounded({"W": "escape"}, {"escape": {"1": {}}})
	var a := _ship("a", Vector2i(-4, 0), 3, 3, 1)
	GameState.ship_controller.set_escape_declared("a", true)
	_plot_straight(a, 3)
	var ships: Array[ShipState] = [a]
	var log = resolver.run(ships, env)
	var r = log.get_result("a")
	assert_eq(r.left_map, MapRules.ESCAPE)
	assert_eq(r.left_edge, "W")
	assert_eq(r.final_hex, Vector2i(-6, 0))
	resolver.apply_results(log, ships)
	assert_eq(a.status, ShipState.Status.ESCAPED)
	assert_false(a.is_on_map())
	assert_eq(_turn_log_of(PhaseEvents.Type.ESCAPED).size(), 1)

	# Undeclared, the same plot meets a wall.
	GameState.ships.clear()
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	var b := _ship("b", Vector2i(-4, 0), 3, 3, 1)
	_plot_straight(b, 3)
	var ships_b: Array[ShipState] = [b]
	var log_b = resolver.run(ships_b, env)
	var rb = log_b.get_result("b")
	assert_eq(rb.left_map, "")
	assert_eq(rb.final_hex, Vector2i(-5, 0))
	assert_eq(_events_of(rb, MovementTypes.ResolutionEventType.EDGE_BLOCKED).size(), 1)
	resolver.apply_results(log_b, ships_b)
	assert_true(b.is_on_map())
	assert_eq(b.status, ShipState.Status.ACTIVE)


# ===========================================================================
# Determinism (spec §16)
# ===========================================================================

func test_depth_roll_repeats_on_bear_off_rerun() -> void:
	# a crosses a doubtful shoal on segment 0; the prompted mover meets the blocker on segment 1,
	# after a's last step.
	for seed_value in range(1, 9):
		GameState.ships.clear()
		GameState.active_scenario = _scenario({"shallow": [{"name": "bank", "base": 15, "hexes": _hexes([Vector2i(1, -3)])}]})
		var a := _ship("a", Vector2i(0, -3))
		_plot_straight(a, 2)
		var mover := _ship("mover", Vector2i(5, 5), 0, 7, 0, "D", "A")
		_plot_straight(mover, 2)
		var blocker := _ship("blocker", Vector2i(7, 5), 1, 0)
		var ships: Array[ShipState] = [a, mover, blocker]
		rng.seed = seed_value
		var paused = resolver.run(ships, env, {}, ["mover"])
		assert_false(paused.is_complete(), "seed %d: the owner decides" % seed_value)
		rng.seed = seed_value
		var decided = resolver.run(ships, env, {"mover": {"choice": "starboard", "segment": 1}}, ["mover"])
		assert_true(decided.is_complete())
		assert_eq(decided.get_result("a").to_dict(), paused.get_result("a").to_dict(),
			"seed %d: the depth die repeats" % seed_value)


func test_terrain_free_run_is_unchanged() -> void:
	var far := {"land": _hexes([Vector2i(30, 0)]),
		"shallow": [{"name": "bank", "base": 5, "hexes": _hexes([Vector2i(-30, 10)])}]}
	for seed_value in range(1, 6):
		GameState.ships.clear()
		var blocker := _ship("blocker", Vector2i(7, 5), 1, 0)
		var mover := _ship("mover", Vector2i(5, 5), 0, 7, 0, "D", "A")
		_plot_straight(mover, 3)
		var other := _ship("other", Vector2i(0, 0), 0, 3)
		_plot_straight(other, 3)
		var ships: Array[ShipState] = [mover, blocker, other]
		GameState.active_scenario = {}
		rng.seed = seed_value
		var plain = resolver.run(ships, env).to_dict()
		var plain_state := rng.state
		GameState.active_scenario = _scenario(far)
		rng.seed = seed_value
		var with_terrain = resolver.run(ships, env).to_dict()
		assert_eq(with_terrain, plain, "seed %d" % seed_value)
		assert_eq(rng.state, plain_state)


