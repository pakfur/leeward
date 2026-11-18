extends GutTest
## MovementResolver casting the lead (13.G.4, map and scenario spec §5): a ship that casts the lead
## with a plot of at most 2 MPs sounds each shallow or land hex before its bow enters it. Too shallow,
## it bears off to the deeper side without a Bearing Off roll (not the 6.D.5 bear-off), holds back when
## no turn will do, or (Poor Maneuvering, a failed d10) sails on and runs aground. Deep enough, it
## enters.
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


func _hexes(list: Array) -> Array:
	var out: Array = []
	for h in list:
		out.append([h.x, h.y])
	return out


func _scenario(terrain: Dictionary) -> Dictionary:
	return {"terrain": terrain}


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


## Bow (0, 0) facing E, a plot of `steps` ahead, casting the lead.
func _caster(speed: int = 2, steps: int = 2, maneuverability: String = "C") -> ShipState:
	var a := _ship("a", Vector2i(0, 0), 0, speed, 0, maneuverability)
	_plot_straight(a, steps)
	GameState.ship_controller.set_cast_lead("a", true)
	return a


func _soundings(r: MovementTypes.ShipResolutionResult) -> Array:
	return _events_of(r, MovementTypes.ResolutionEventType.LEAD_SOUNDING)


func _lead_cast_log(log: MovementTypes.ResolutionLog, ships: Array[ShipState]) -> Array:
	resolver.log_outcomes(log, ships, GameState.turn_log)
	return _turn_log_of(PhaseEvents.Type.LEAD_CAST)


# ===========================================================================
# Geometry from bow (0, 0) facing E: ahead is (1, 0). A port turn heads NE, new stern (-1, 1), hex
# ahead (1, -1); a starboard turn heads SE, new stern (0, -1), hex ahead (0, 1).
# ===========================================================================

func test_lead_bears_off_from_certain_shoal_to_the_deeper_side() -> void:
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(1, -1)]),
		"shallow": [{"name": "bar", "base": 10, "hexes": _hexes([Vector2i(1, 0)])}]})
	var a := _caster()
	var ships: Array[ShipState] = [a]
	var log = resolver.run(ships, env)
	var r = log.get_result("a")
	assert_eq(r.final_facing, 1, "Bore off to starboard, away from the land")
	assert_false(r.aground)
	assert_eq(r.rigging_damage, 0)
	var soundings := _soundings(r)
	assert_eq(soundings.size(), 1)
	if soundings.size() == 1:
		assert_string_contains(soundings[0].detail, "outcome=bore_off side=starboard")
		assert_eq(int(soundings[0].threshold), 16, "The draft")
	assert_eq(_events_of(r, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL).size(), 0,
		"13.G.4b: a casting ship always bears off")
	var cast := _lead_cast_log(log, ships)
	assert_eq(cast.size(), 1)
	if cast.size() == 1:
		assert_eq(cast[0].data.get("outcome"), "bore_off")
		assert_eq(cast[0].data.get("side"), ShipState.STARBOARD)
		assert_eq(cast[0].data.get("hex"), {"q": 1, "r": 0})
		assert_eq(cast[0].data.get("draft"), 16)
		assert_between(int(cast[0].data.get("depth")), 11, 16)


func test_lead_bears_off_from_land() -> void:
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(1, 0)])})
	var a := _caster()
	var log = resolver.run([a] as Array[ShipState], env)
	var r = log.get_result("a")
	assert_false(r.aground)
	assert_eq(r.final_facing, 1, "Both sides deep: starboard")
	var soundings := _soundings(r)
	assert_eq(soundings.size(), 1)
	if soundings.size() == 1:
		assert_eq(int(soundings[0].roll), -1, "No depth die for land")
		assert_string_contains(soundings[0].detail, "outcome=bore_off side=starboard depth=-1")


func test_lead_enters_when_deep_enough() -> void:
	GameState.active_scenario = _scenario({"shallow": [{"name": "bank", "base": 16, "hexes": _hexes([Vector2i(1, 0)])}]})
	var a := _caster()
	var ships: Array[ShipState] = [a]
	var log = resolver.run(ships, env)
	var r = log.get_result("a")
	assert_eq(r.final_hex, Vector2i(2, 0))
	assert_false(r.aground)
	var soundings := _soundings(r)
	assert_eq(soundings.size(), 1)
	if soundings.size() == 1:
		assert_string_contains(soundings[0].detail, "outcome=entered side= ")
	var cast := _lead_cast_log(log, ships)
	assert_eq(cast.size(), 1)
	if cast.size() == 1:
		assert_eq(cast[0].data.get("outcome"), "entered")


func test_lead_ignored_over_two_mps() -> void:
	GameState.active_scenario = _scenario({"shallow": [{"name": "bar", "base": 10, "hexes": _hexes([Vector2i(1, 0)])}]})
	var a := _caster(3, 3)
	var log = resolver.run([a] as Array[ShipState], env)
	var r = log.get_result("a")
	assert_eq(_soundings(r).size(), 0, "13.G.4a: only a plot of at most 2 MPs casts the lead")
	assert_true(r.aground)


func test_lead_with_no_legal_turn_holds() -> void:
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(-1, 1), Vector2i(0, -1)]),
		"shallow": [{"name": "bar", "base": 10, "hexes": _hexes([Vector2i(1, 0)])}]})
	var a := _caster()
	var ships: Array[ShipState] = [a]
	var log = resolver.run(ships, env)
	var r = log.get_result("a")
	assert_eq(r.final_hex, Vector2i(0, 0))
	assert_eq(r.final_facing, 0)
	assert_false(r.aground, "It knows the depth and stops before the hex")
	assert_eq(r.rigging_damage, 0)
	var soundings := _soundings(r)
	assert_eq(soundings.size(), 1)
	if soundings.size() == 1:
		assert_string_contains(soundings[0].detail, "outcome=held side= ")
	var cast := _lead_cast_log(log, ships)
	assert_eq(cast.size(), 1)
	if cast.size() == 1:
		assert_eq(cast[0].data.get("outcome"), "held")


func test_poor_maneuvering_lead_can_fail() -> void:
	var seen := {}
	for seed_value in range(1, 25):
		GameState.ships.clear()
		GameState.turn_log = PhaseEvents.PhaseLog.new()
		GameState.active_scenario = _scenario({"shallow": [{"name": "bar", "base": 10, "hexes": _hexes([Vector2i(1, 0)])}]})
		var a := _caster()
		a.rudder_destroyed = true
		var ships: Array[ShipState] = [a]
		rng.seed = seed_value
		var probe := _probe()
		var depth := 10 + probe.randi_range(1, 6)
		var d10 := probe.randi_range(0, 9)
		var log = resolver.run(ships, env)
		var r = log.get_result("a")
		var cast := _lead_cast_log(log, ships)
		assert_eq(cast.size(), 1, "seed %d" % seed_value)
		if cast.size() != 1:
			continue
		assert_eq(int(cast[0].data.get("depth")), depth, "seed %d: depth die first" % seed_value)
		if d10 <= resolver.poor_maneuvering_number(a):
			seen["bore_off"] = true
			assert_eq(cast[0].data.get("outcome"), "bore_off", "seed %d" % seed_value)
			assert_false(r.aground, "seed %d" % seed_value)
			assert_eq(r.final_facing, 1, "seed %d" % seed_value)
		else:
			seen["pm_failed"] = true
			assert_eq(cast[0].data.get("outcome"), "pm_failed", "seed %d" % seed_value)
			assert_eq(r.final_hex, Vector2i(0, 0), "seed %d: stays in the hexes it held" % seed_value)
			assert_true(r.aground, "seed %d" % seed_value)
			assert_eq(r.aground_data.get("depth"), depth, "seed %d" % seed_value)
			assert_eq(r.rigging_damage, probe.randi_range(1, 6) + 1, "seed %d: then the rigging die" % seed_value)
		assert_eq(_turn_log_of(PhaseEvents.Type.POOR_MANEUVERING).size(), 1,
			"seed %d: the PM roll is logged" % seed_value)
	assert_eq(seen.size(), 2, "Both outcomes over the seeds")


func test_lead_bear_off_does_not_use_the_6_d_5_bear_off() -> void:
	# Speed 4, maneuverability A (deceleration 2): after the starboard turn the ship must go on one
	# hex ahead, into (0, 1), held by a stopped blocker (bow (1, 1), stern (0, 1)). Within 2 MPs that
	# step follows the lead's turn, so no second turn is legal there (no consecutive pivots): the
	# potential collision is judged as any other, "no legal turn", never "already bore off".
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(1, 0)])})
	var a := _caster(4, 2, "A")
	var blocker := _ship("blocker", Vector2i(1, 1), 0, 0)
	var ships: Array[ShipState] = [a, blocker]
	var log = resolver.run(ships, env)
	var r = log.get_result("a")
	assert_eq(_soundings(r).size(), 1)
	assert_eq(r.final_facing, 1)
	var denied := _events_of(r, MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED)
	assert_eq(denied.size(), 1, "The ship in the way is a potential collision (6.D)")
	if denied.size() == 1:
		assert_true(denied[0].detail.begins_with("no legal turn"),
			"13.G.4 is not the 6.D.5 bear-off: %s" % denied[0].detail)
	assert_eq(r.collided_with, "blocker")


func test_lead_rerun_is_deterministic() -> void:
	GameState.active_scenario = _scenario({"land": _hexes([Vector2i(1, -1)]),
		"shallow": [{"name": "bar", "base": 13, "hexes": _hexes([Vector2i(1, 0)])}]})
	for seed_value in range(1, 9):
		GameState.ships.clear()
		var a := _caster()
		var ships: Array[ShipState] = [a]
		rng.seed = seed_value
		var start := rng.state
		var first = resolver.run(ships, env).to_dict()
		rng.state = start
		var second = resolver.run(ships, env).to_dict()
		assert_eq(second, first, "seed %d" % seed_value)
