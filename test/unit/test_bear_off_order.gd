extends GutTest
## 6.D.3c: when two or more bearing-off situations occur on the same segment, a d10 decides which
## is resolved first (highest first, ties re-rolled among the tied: planner's call). The d10s come
## from the resolver's RNG after the segment's moves, so a re-run after an answer repeats them.

var resolver: MovementResolver
var rng: RandomNumberGenerator
var env: EnvironmentState
var _saved_turn_log: PhaseEvents.PhaseLog


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
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	GameState.ships.clear()
	_saved_turn_log = GameState.turn_log
	GameState.turn_log = PhaseEvents.PhaseLog.new()


func after_each() -> void:
	GameState.turn_log = _saved_turn_log
	GameState.ships.clear()


func _make_ship(id: String, hex: Vector2i, facing: int, speed: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": 0, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "D", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
	})
	state.hex_position = hex
	state.facing = facing
	state.speed = speed
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	state.crew_quality = "A"
	GameState.ships[id] = state
	return state


func _plot_east(state: ShipState, steps: int) -> void:
	var movement: Array = []
	var hex := state.hex_position
	for i in range(steps):
		hex += HexGrid.DIRECTIONS[0]
		movement.append({"hex": {"q": hex.x, "r": hex.y}, "facing": 0})
	GameState.ship_controller.set_plotted_movement(state.ship_id, movement)


## Two ships each sail three hexes east into their own stopped ship: two potential collisions on
## segment 1, far apart. `ship_a` comes first in the ship order.
func _two_situations() -> Array[ShipState]:
	var a := _make_ship("ship_a", Vector2i(5, 5), 0, 7)
	_plot_east(a, 3)
	var block_a := _make_ship("block_a", Vector2i(7, 5), 1, 0)
	var b := _make_ship("ship_b", Vector2i(5, 10), 0, 7)
	_plot_east(b, 3)
	var block_b := _make_ship("block_b", Vector2i(7, 10), 1, 0)
	return [a, block_a, b, block_b] as Array[ShipState]


## A seed whose first two d10s (the order rolls: ship_a, then ship_b, in ship order) satisfy `want`.
func _seed_where(want: Callable) -> int:
	var probe := RandomNumberGenerator.new()
	for s in range(1, 5000):
		probe.seed = s
		var first := probe.randi_range(0, 9)
		var second := probe.randi_range(0, 9)
		if want.call(first, second, probe):
			return s
	return -1


func _order_events(log: MovementTypes.ResolutionLog) -> Array:
	var found: Array = []
	for sid in ["ship_a", "ship_b", "block_a", "block_b"]:
		var result: MovementTypes.ShipResolutionResult = log.get_result(sid)
		if result == null:
			continue
		for ev in result.events:
			if ev.event_type == MovementTypes.ResolutionEventType.BEAR_OFF_ORDER:
				found.append(ev)
	return found


func test_two_bear_offs_same_segment_ordered_by_d10() -> void:
	# 6.D.3c: two bearing-off situations on the same segment; a d10 decides which is resolved first.
	# Seeded so ship_b (second in ship order) rolls higher: it is asked first.
	var ships := _two_situations()
	var s := _seed_where(func(a, b, _p): return b > a)
	rng.seed = s
	var probe := RandomNumberGenerator.new()
	probe.seed = s
	var roll_a := probe.randi_range(0, 9)
	var roll_b := probe.randi_range(0, 9)
	var log = resolver.run(ships, env, {}, ["ship_a", "ship_b"])
	assert_false(log.is_complete())
	assert_eq(log.pending_bear_off.ship_id, "ship_b", "6.D.3c: the higher d10 decides first")
	assert_eq(log.pending_bear_off.segment, 1)
	var orders := _order_events(log)
	assert_eq(orders.size(), 1, "One BEAR_OFF_ORDER entry for the segment")
	assert_eq(orders[0].ship_id, "ship_b", "Told on the ship resolved first")
	assert_eq(orders[0].impulse, 1)
	assert_eq(orders[0].detail, "ship_b=%d ship_a=%d" % [roll_b, roll_a], "Ships in order with their d10s")


func test_lower_roll_of_the_first_ship_in_order_goes_second() -> void:
	# 6.D.3c: the order is the dice's, not the ship order: ship_a first when it rolls higher.
	var ships := _two_situations()
	rng.seed = _seed_where(func(a, b, _p): return a > b)
	var log = resolver.run(ships, env, {}, ["ship_a", "ship_b"])
	assert_eq(log.pending_bear_off.ship_id, "ship_a")


func test_tied_order_rolls_are_rolled_again() -> void:
	# Planner's call: ties are re-rolled among the tied ships, highest first.
	var ships := _two_situations()
	var s := _seed_where(func(a, b, p):
		if a != b:
			return false
		return p.randi_range(0, 9) != p.randi_range(0, 9))
	rng.seed = s
	var probe := RandomNumberGenerator.new()
	probe.seed = s
	var first := probe.randi_range(0, 9)
	probe.randi_range(0, 9)
	var again_a := probe.randi_range(0, 9)
	var again_b := probe.randi_range(0, 9)
	var log = resolver.run(ships, env, {}, ["ship_a", "ship_b"])
	var winner := "ship_a" if again_a > again_b else "ship_b"
	assert_eq(log.pending_bear_off.ship_id, winner)
	var expected := "ship_a=%d,%d ship_b=%d,%d" % [first, again_a, first, again_b]
	if winner == "ship_b":
		expected = "ship_b=%d,%d ship_a=%d,%d" % [first, again_b, first, again_a]
	assert_eq(_order_events(log)[0].detail, expected, "Both rolls of each tied ship are kept")


func test_order_rolls_repeat_on_replay() -> void:
	# 6.D.3c with 6.D.3 prompting: the answer for the first ship re-runs from the same dice, so the
	# order rolls repeat and the second ship is asked next.
	var ships := _two_situations()
	var s := _seed_where(func(a, b, _p): return b > a)
	rng.seed = s
	var paused = resolver.run(ships, env, {}, ["ship_a", "ship_b"])
	var first_order: String = _order_events(paused)[0].detail
	rng.seed = s
	var answered = resolver.run(ships, env,
		{"ship_b": {"choice": MovementTypes.BEAR_OFF_COLLIDE, "segment": 1}}, ["ship_a", "ship_b"])
	assert_eq(_order_events(answered).size(), 1)
	assert_eq(_order_events(answered)[0].detail, first_order, "Same order rolls on the re-run")
	assert_eq(answered.get_result("ship_b").collided_with, "block_b", "ship_b held course")
	assert_false(answered.is_complete())
	assert_eq(answered.pending_bear_off.ship_id, "ship_a", "Then the second ship is asked")


func test_ai_ships_decide_in_the_rolled_order() -> void:
	# 6.D.3c: with no prompt the ships decide by the AI rule in the d10 order: the dice of the ship
	# resolved first come first. Seeded so both bear off (a legal turn is open, 6.D.2), so the final
	# log keeps both rolls of the first pass.
	var ships := _two_situations()
	var number := DataManager.get_bearing_off_number("A", "D")
	var s := _seed_where(func(a, b, p):
		return b > a and p.randi_range(0, 9) <= number and p.randi_range(0, 9) <= number)
	rng.seed = s
	var probe := RandomNumberGenerator.new()
	probe.seed = s
	probe.randi_range(0, 9)
	probe.randi_range(0, 9)
	var first_bear_off := probe.randi_range(0, 9)
	var second_bear_off := probe.randi_range(0, 9)
	var log = resolver.run(ships, env)
	assert_eq(_rolls(log, "ship_b"), [first_bear_off], "ship_b, first in order, rolls the first die after the order")
	assert_eq(_rolls(log, "ship_a"), [second_bear_off], "ship_a rolls next")
	assert_eq(_order_events(log).size(), 1, "The order stays in the final log after the bear-off replay")


func _rolls(log: MovementTypes.ResolutionLog, sid: String) -> Array:
	var rolls: Array = []
	for ev in log.get_result(sid).events:
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
			rolls.append(int(ev.roll))
	return rolls


func test_single_bear_off_rolls_no_order() -> void:
	# One situation: no BEAR_OFF_ORDER event, and the bear-off roll is the first die drawn.
	var a := _make_ship("ship_a", Vector2i(5, 5), 0, 7)
	_plot_east(a, 3)
	var block_a := _make_ship("block_a", Vector2i(7, 5), 1, 0)
	rng.seed = 99
	var probe := RandomNumberGenerator.new()
	probe.seed = 99
	var log = resolver.run([a, block_a] as Array[ShipState], env)
	assert_eq(_order_events(log).size(), 0, "No order to decide")
	assert_eq(_rolls(log, "ship_a"), [probe.randi_range(0, 9)], "RNG consumption unchanged: the bear-off roll is the first die")


func test_order_is_logged_for_the_combat_log() -> void:
	# The order is shown in the combat log (spec item 5: only when it decided something, i.e. 2+ ships).
	var ships := _two_situations()
	rng.seed = _seed_where(func(a, b, _p): return b > a)
	var log = resolver.run(ships, env)
	var turn_log := PhaseEvents.PhaseLog.new()
	resolver.log_outcomes(log, ships, turn_log)
	var orders := turn_log.of_type(PhaseEvents.Type.BEAR_OFF_ORDER)
	assert_eq(orders.size(), 1)
	assert_eq(orders[0].ship_id, "ship_b")
	assert_eq(orders[0].data.get("order", []).size(), 2)
	assert_eq(orders[0].data.order[1].ship_id, "ship_a")
	assert_true("ship_a" in orders[0].ship_ids(), "Both ships are named (side labels)")


func test_order_log_text() -> void:
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BEAR_OFF_ORDER,
		TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION, "b",
		{"order": [{"ship_id": "b", "rolls": [7]}, {"ship_id": "a", "rolls": [3]}]})
	assert_eq(ev.to_text({"a": "Alpha", "b": "Bravo"}),
		"Two ships must bear off on the same segment; by d10 Bravo (7) decides first, then Alpha (3)")
	var tied := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BEAR_OFF_ORDER,
		TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION, "a",
		{"order": [{"ship_id": "a", "rolls": [4, 8]}, {"ship_id": "b", "rolls": [4, 2]}]})
	assert_eq(tied.to_text({"a": "Alpha", "b": "Bravo"}),
		"Two ships must bear off on the same segment; by d10 Alpha (4, 8) decides first, then Bravo (4, 2)")


func test_a_situation_caused_by_another_follows_it_without_a_roll() -> void:
	# ship_a sails into a stopped ship and keeps its stern (4,5); ship_b, sailing into that stern, meets
	# a potential collision only because ship_a stopped: it is decided after ship_a's, with no d10
	# (reading of 6.D.3c: the two are not independent situations).
	var stopped := _make_ship("stopped", Vector2i(6, 5), 1, 0)
	var a := _make_ship("ship_a", Vector2i(5, 5), 0, 3)
	a.plotted_actions.movement = [{"hex": {"q": 6, "r": 5}, "facing": 0}]
	var b := _make_ship("ship_b", Vector2i(4, 6), 4, 1)
	b.plotted_actions.movement = [{"hex": {"q": 4, "r": 5}, "facing": 4}]
	var log = resolver.run([b, a, stopped] as Array[ShipState], env, {}, ["ship_a", "ship_b"])
	assert_eq(_order_events(log).size(), 0, "No order roll")
	assert_eq(log.pending_bear_off.ship_id, "ship_a", "The cause is decided first")
