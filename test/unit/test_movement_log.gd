extends GutTest
## Movement outcomes in the per-turn log: collisions, movement cut short, fouling, missed stays.

const MOVE := TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
const T := MovementTypes.ResolutionEventType

var resolver: MovementResolver
var turn_log: PhaseEvents.PhaseLog


func before_each() -> void:
	resolver = MovementResolver.new(GameState, RandomNumberGenerator.new())
	turn_log = PhaseEvents.PhaseLog.new()


func _ship(id: String, plotted: int) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": id, "ship_name": id})
	var steps: Array = []
	for i in range(plotted):
		steps.append({"hex": {"q": i + 1, "r": 0}, "facing": 0})
	if plotted > 0:
		s.plotted_actions["movement"] = steps
	return s


func _move(result: MovementTypes.ShipResolutionResult, impulse: int, from: Vector2i, to: Vector2i) -> void:
	var ev := MovementTypes.ResolutionEvent.new(result.ship_id, impulse, T.MOVE)
	ev.from_hex = from
	ev.to_hex = to
	result.events.append(ev)


func _collision_log(fouled: bool) -> MovementTypes.ResolutionLog:
	var log := MovementTypes.ResolutionLog.new(1)
	var a := MovementTypes.ShipResolutionResult.new("a")
	var b := MovementTypes.ShipResolutionResult.new("b")
	_move(a, 0, Vector2i(0, 0), Vector2i(1, 0))
	var col_a := MovementTypes.ResolutionEvent.new("a", 1, T.COLLISION)
	col_a.from_hex = Vector2i(1, 0)
	col_a.to_hex = Vector2i(1, 0)
	col_a.detail = "collided with b, rigging_loss=4"
	a.events.append(col_a)
	var col_b := MovementTypes.ResolutionEvent.new("b", 1, T.COLLISION)
	col_b.from_hex = Vector2i(2, 0)
	col_b.detail = "hit by a"
	b.events.append(col_b)
	a.collided_with = "b"
	b.collided_with = "a"
	a.stopped_at_impulse = 1
	b.stopped_at_impulse = 1
	if fouled:
		a.fouled_with = "b"
		b.fouled_with = "a"
	log.add_result(a)
	log.add_result(b)
	return log


func test_collision_stop_short_and_fouling_are_logged_in_order() -> void:
	var ships: Array[ShipState] = [_ship("a", 3), _ship("b", 0)]
	resolver.log_outcomes(_collision_log(true), ships, turn_log)
	var texts: Array = []
	for ev in turn_log.events:
		assert_eq(ev.phase, MOVE)
		texts.append(ev.to_text({"a": "Alpha", "b": "Bravo"}))
	assert_eq(texts, [
		"Alpha collides with Bravo at (2, 0)",
		"Alpha stops short of its plotted course after colliding with Bravo",
		"Alpha and Bravo are fouled together",
	])


func test_fouling_is_logged_once_per_pair() -> void:
	var ships: Array[ShipState] = [_ship("b", 0), _ship("a", 3)]
	resolver.log_outcomes(_collision_log(true), ships, turn_log)
	assert_eq(turn_log.of_type(PhaseEvents.Type.FOULED).size(), 1)
	assert_eq(turn_log.of_type(PhaseEvents.Type.COLLISION).size(), 1, "only the ship that ran in")


func test_no_fouling_line_without_fouling() -> void:
	var ships: Array[ShipState] = [_ship("a", 3), _ship("b", 0)]
	resolver.log_outcomes(_collision_log(false), ships, turn_log)
	assert_eq(turn_log.of_type(PhaseEvents.Type.FOULED).size(), 0)


func test_full_move_logs_nothing() -> void:
	var log := MovementTypes.ResolutionLog.new(1)
	var a := MovementTypes.ShipResolutionResult.new("a")
	_move(a, 0, Vector2i(0, 0), Vector2i(1, 0))
	_move(a, 1, Vector2i(1, 0), Vector2i(2, 0))
	log.add_result(a)
	var ships: Array[ShipState] = [_ship("a", 2)]
	resolver.log_outcomes(log, ships, turn_log)
	assert_eq(turn_log.events.size(), 0)


func test_failed_tack_says_in_irons_not_stopped_short() -> void:
	var log := MovementTypes.ResolutionLog.new(1)
	var a := MovementTypes.ShipResolutionResult.new("a")
	a.tacking_failed = true
	a.immobilized = true
	log.add_result(a)
	var ships: Array[ShipState] = [_ship("a", 3)]
	resolver.log_outcomes(log, ships, turn_log)
	assert_eq(turn_log.events.size(), 1)
	assert_eq(turn_log.events[0].to_text({"a": "Alpha"}), "Alpha misses stays and is in irons")


func test_failed_escape_from_irons_is_logged() -> void:
	var log := MovementTypes.ResolutionLog.new(1)
	var a := MovementTypes.ShipResolutionResult.new("a")
	a.immobilized = true
	log.add_result(a)
	var ships: Array[ShipState] = [_ship("a", 0)]
	resolver.log_outcomes(log, ships, turn_log)
	assert_eq(turn_log.events[0].to_text({"a": "Alpha"}), "Alpha is still in irons")


func test_drift_fouling_text_is_unchanged() -> void:
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.FOULED, 5, "a", {}, "b")
	assert_eq(ev.to_text({"a": "Alpha", "b": "Bravo"}), "Alpha drifts into Bravo; the two ships are fouled")


func test_log_headings_name_movement_and_weather() -> void:
	assert_eq(CombatLogPanel.phase_heading(2, MOVE), "Turn 2 — Movement")
	assert_eq(CombatLogPanel.phase_heading(2, TurnPhaseController.GamePhase.ENVIRONMENT), "Turn 2 — Weather")


# --- Why a ship stopped short ------------------------------------------------------------------

func _bear_off_log() -> MovementTypes.ResolutionLog:
	var log := MovementTypes.ResolutionLog.new(1)
	var a := MovementTypes.ShipResolutionResult.new("a")
	_move(a, 0, Vector2i(0, 0), Vector2i(1, 0))
	var roll := MovementTypes.ResolutionEvent.new("a", 1, T.BEARING_OFF_ROLL)
	roll.success = true
	a.events.append(roll)
	var stop := MovementTypes.ResolutionEvent.new("a", 1, T.STOPPED)
	stop.detail = "bore off successfully, movement ends"
	a.events.append(stop)
	a.blocked_by = "b"
	a.stopped_at_impulse = 1
	log.add_result(a)
	log.add_result(MovementTypes.ShipResolutionResult.new("b"))
	return log


func test_stop_short_after_bearing_off_names_the_ship_in_the_way() -> void:
	var ships: Array[ShipState] = [_ship("a", 3), _ship("b", 0)]
	resolver.log_outcomes(_bear_off_log(), ships, turn_log)
	var stops := turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT)
	assert_eq(stops.size(), 1)
	assert_eq(stops[0].to_text({"a": "Alpha", "b": "HMS Lively"}),
		"Alpha stops short of its plotted course after bearing off — HMS Lively was in the way")


func test_stop_short_after_a_collision_names_the_other_ship() -> void:
	var ships: Array[ShipState] = [_ship("a", 3), _ship("b", 0)]
	resolver.log_outcomes(_collision_log(false), ships, turn_log)
	var stops := turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT)
	assert_eq(stops[0].to_text({"a": "Alpha", "b": "Bravo"}),
		"Alpha stops short of its plotted course after colliding with Bravo")


func test_ship_run_into_also_says_it_collided() -> void:
	# b had a plot of its own and was hit before finishing it.
	var ships: Array[ShipState] = [_ship("a", 3), _ship("b", 2)]
	resolver.log_outcomes(_collision_log(false), ships, turn_log)
	var texts: Array = []
	for ev in turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT):
		texts.append(ev.to_text({"a": "Alpha", "b": "Bravo"}))
	assert_has(texts, "Bravo stops short of its plotted course after colliding with Alpha")


func test_stop_short_without_a_known_cause_keeps_the_plain_wording() -> void:
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.STOPPED_SHORT, MOVE, "a", {"moved": 1, "planned": 3})
	assert_eq(ev.to_text({"a": "Alpha"}), "Alpha stops short of its plotted course")


func test_bear_off_cause_survives_without_the_other_ships_name() -> void:
	var ev := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.STOPPED_SHORT, MOVE, "a", {"cause": "bore_off"})
	assert_eq(ev.to_text({"a": "Alpha"}), "Alpha stops short of its plotted course after bearing off")


func test_resolver_records_which_ship_was_in_the_way() -> void:
	# A plotted mover into a stationary ship's hex: whatever the bear-off roll, the result names it.
	GameState.clear_ships()
	DataManager.load_movement_allowance_table()
	DataManager.load_ship_definitions()
	DataManager.load_bearing_off_table()
	var mover := ShipState.new()
	mover.ship = Ship.from_dict({"ship_id": "m", "ship_name": "Mover", "maneuverability": "B"})
	mover.hex_position = Vector2i(0, 0)
	mover.facing = 0
	mover.speed = 2
	mover.crew_quality = "C"
	mover.plotted_actions["movement"] = [{"hex": {"q": 1, "r": 0}, "facing": 0, "move_type": 1}]
	var still := ShipState.new()
	still.ship = Ship.from_dict({"ship_id": "s", "ship_name": "Still", "maneuverability": "B"})
	still.hex_position = Vector2i(1, 0)
	var env := EnvironmentState.new()
	var ships: Array[ShipState] = [mover, still]
	var log := MovementResolver.new(null, RandomNumberGenerator.new()).run(ships, env)
	var r: MovementTypes.ShipResolutionResult = log.get_result("m")
	assert_true(r.blocked_by == "s" or r.collided_with == "s", "the blocker is named")
	assert_eq(r.blocked_by, "s")
