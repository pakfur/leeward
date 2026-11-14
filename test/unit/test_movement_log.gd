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
		"Alpha stops short of its plotted course",
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
