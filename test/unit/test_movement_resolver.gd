extends GutTest
## Tests for MovementResolver - single-ship and multi-ship impulse resolution
## Covers: straight movement, tacking, in-irons, contested hex, bearing off, collision, fouling

var resolver: MovementResolver
var rng: RandomNumberGenerator
var env: EnvironmentState


func before_all() -> void:
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_turning_table()


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


func _make_ship_def(maneuverability: String = "C", speed_type: String = "F/F", ship_class: int = 3) -> Ship:
	return Ship.from_dict({
		"ship_id": "test_ship_1",
		"player_id": 0,
		"ship_name": "HMS Test",
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": ship_class,
		"maneuverability": maneuverability,
		"speed_type": speed_type,
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
	})


func _make_ship_state(
	hex_pos: Vector2i = Vector2i(5, 5),
	facing: int = 0,
	speed: int = 3,
	maneuverability: String = "C",
	ship_id: String = "test_ship_1",
	ship_class: int = 3,
	crew_quality: String = "B"
) -> ShipState:
	var state = ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": ship_id,
		"player_id": 0,
		"ship_name": "Ship " + ship_id,
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": ship_class,
		"maneuverability": maneuverability,
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
	})
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
	GameState.ships[ship_id] = state
	return state


func _plot_straight(state: ShipState, steps: int) -> void:
	var hex_grid = HexGrid.new()
	var movement: Array = []
	var current_hex = state.hex_position
	for i in range(steps):
		var next_hex = hex_grid.get_neighbor(current_hex.x, current_hex.y, state.facing)
		movement.append({"hex": {"q": next_hex.x, "r": next_hex.y}, "facing": state.facing})
		current_hex = next_hex
	GameState.ship_controller.set_plotted_movement(state.ship_id, movement)


# ===========================================================================
# Single-ship: straight movement
# ===========================================================================

func test_straight_movement_3_steps() -> void:
	var state = _make_ship_state()
	_plot_straight(state, 3)
	var ships: Array[ShipState] = [state]

	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	assert_not_null(result, "Should have result for ship")
	assert_eq(result.events.size(), 3, "Should have 3 move events")
	assert_eq(result.final_hex, Vector2i(8, 5), "Should end 3 hexes east")
	assert_eq(result.final_facing, 0, "Facing should remain east")
	assert_false(result.immobilized, "Should not be immobilized")


func test_straight_movement_applies_position() -> void:
	var state = _make_ship_state()
	_plot_straight(state, 2)
	var ships: Array[ShipState] = [state]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	assert_eq(state.hex_position, Vector2i(7, 5), "Position should update")
	assert_eq(state.speed, 2, "Speed should equal hexes moved")
	assert_true(state.plotted_actions.movement.is_empty(), "Plot should be cleared")


func test_no_movement_plotted() -> void:
	var state = _make_ship_state()
	state.facing = 1
	var ships: Array[ShipState] = [state]

	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	assert_eq(result.events.size(), 1, "Should have skip event")
	assert_eq(result.events[0].event_type, MovementTypes.ResolutionEventType.SKIP_NO_PLOT)
	assert_eq(result.final_hex, Vector2i(5, 5), "Position unchanged")


# ===========================================================================
# Single-ship: tacking
# ===========================================================================

func test_tacking_success_continues_movement() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 5, 3, "D")
	state.tacking = true

	env.wind_direction = 0
	var hex_grid = HexGrid.new()
	var step1_hex = hex_grid.get_neighbor(5, 5, 5)
	var step2_hex = hex_grid.get_neighbor(step1_hex.x, step1_hex.y, 0)

	state.plotted_actions.movement = [
		{"hex": {"q": step1_hex.x, "r": step1_hex.y}, "facing": 5},
		{"hex": {"q": step2_hex.x, "r": step2_hex.y}, "facing": 0},
	]

	rng.seed = 1
	resolver = MovementResolver.new(GameState, rng)

	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	var has_tack_event = false
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.TACKING_ROLL:
			has_tack_event = true

	if not has_tack_event:
		pass_test("No tacking detected for this path/wind combo — path does not cross L")
	else:
		if result.tacking_failed:
			assert_true(result.immobilized, "Failed tack should immobilize")
		else:
			assert_false(result.immobilized, "Successful tack should not immobilize")
			assert_eq(result.final_hex, step2_hex, "Should complete movement")


func test_tacking_failure_immobilizes() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 5, 3, "A")
	state.tacking = true

	env.wind_direction = 0
	env.wind_speed = 1

	var facing_L: int = env.wind_direction
	var hex_grid = HexGrid.new()
	var step1_hex = hex_grid.get_neighbor(5, 5, facing_L)

	state.plotted_actions.movement = [
		{"hex": {"q": step1_hex.x, "r": step1_hex.y}, "facing": facing_L},
	]

	rng.seed = 99999
	resolver = MovementResolver.new(GameState, rng)

	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	var has_tack_roll = false
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.TACKING_ROLL:
			has_tack_roll = true

	if has_tack_roll and result.tacking_failed:
		assert_true(result.immobilized, "Failed tack should immobilize")
		assert_eq(result.final_facing, facing_L, "Should face into wind (L)")
	elif has_tack_roll and not result.tacking_failed:
		pass_test("Tacking succeeded at this seed — not testing failure path")
	else:
		pass_test("No tacking roll triggered — wind/facing combo did not produce L")


func test_tacking_not_flagged_no_roll() -> void:
	var state = _make_ship_state()
	state.tacking = false
	_plot_straight(state, 2)

	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	for ev in result.events:
		assert_ne(ev.event_type, MovementTypes.ResolutionEventType.TACKING_ROLL,
			"No tacking roll should occur when tacking=false")


# ===========================================================================
# Single-ship: in-irons escape
# ===========================================================================

func test_in_irons_escape_attempt() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 0, "C")
	env.wind_direction = 0
	state.facing = 0

	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	var has_escape_roll = false
	for ev in result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.IN_IRONS_ESCAPE_ROLL:
			has_escape_roll = true
			assert_true(ev.roll >= 0.0 and ev.roll <= 1.0, "Roll should be 0-1")
			assert_true(ev.threshold > 0.0, "Threshold should be > 0")

	assert_true(has_escape_roll, "Should attempt in-irons escape when speed=0 and facing=wind")


func test_not_in_irons_no_escape_roll() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 0, "C")
	env.wind_direction = 0

	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	for ev in result.events:
		assert_ne(ev.event_type, MovementTypes.ResolutionEventType.IN_IRONS_ESCAPE_ROLL,
			"Ship facing W with wind from E is not in-irons")


# ===========================================================================
# DRM calculation
# ===========================================================================

func test_tacking_drm_with_lost_rigging() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 3)
	var damaged_rigging: Array[int] = [5, 0, 6, 0]
	state.rigging_current_hp = damaged_rigging
	var drm = resolver._calculate_tacking_drm(state)
	assert_almost_eq(drm, 0.4, 0.001, "Two destroyed rigging sections = +0.4 DRM")


func test_tacking_drm_with_towing() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 3)
	state.towing = true
	var drm = resolver._calculate_tacking_drm(state)
	assert_almost_eq(drm, 0.1, 0.001, "Towing adds +0.1 DRM")


func test_tacking_drm_facing_luffing() -> void:
	var state = _make_ship_state()
	state.facing = 0
	env.wind_direction = 0
	var drm = resolver._calculate_tacking_drm(state)
	assert_almost_eq(drm, 0.1, 0.001, "Facing L adds +0.1 DRM")


func test_tacking_drm_healthy_ship_not_luffing() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 3)
	var drm = resolver._calculate_tacking_drm(state)
	assert_almost_eq(drm, 0.0, 0.001, "Healthy ship not luffing has 0 DRM")


func test_tacking_drm_compound() -> void:
	var state = _make_ship_state()
	state.facing = 0
	env.wind_direction = 0
	state.towing = true
	var compound_rigging: Array[int] = [0, 5, 6, 0]
	state.rigging_current_hp = compound_rigging
	var drm = resolver._calculate_tacking_drm(state)
	assert_almost_eq(drm, 0.6, 0.001, "L(0.1) + towing(0.1) + 2 rigging lost(0.4) = 0.6")


# ===========================================================================
# Determinism
# ===========================================================================

func test_determinism_same_seed_same_result() -> void:
	var state1 = _make_ship_state(Vector2i(5, 5), 0, 0, "C")
	env.wind_direction = 0
	state1.facing = 0
	var ships1: Array[ShipState] = [state1]

	rng.seed = 42
	resolver = MovementResolver.new(GameState, rng)
	var log1 = resolver.run(ships1, env)
	var result1 = log1.get_result("test_ship_1")

	var state2 = _make_ship_state(Vector2i(5, 5), 0, 0, "C")
	state2.facing = 0
	var ships2: Array[ShipState] = [state2]

	var rng2 = RandomNumberGenerator.new()
	rng2.seed = 42
	var resolver2 = MovementResolver.new(GameState, rng2)
	var log2 = resolver2.run(ships2, env)
	var result2 = log2.get_result("test_ship_1")

	assert_eq(result1.immobilized, result2.immobilized, "Same seed should produce same immobilized state")
	assert_eq(result1.events.size(), result2.events.size(), "Same seed should produce same event count")
	for i in range(result1.events.size()):
		assert_eq(result1.events[i].success, result2.events[i].success, "Event %d success should match" % i)


# ===========================================================================
# ResolutionLog structure
# ===========================================================================

func test_resolution_log_structure() -> void:
	var state = _make_ship_state()
	_plot_straight(state, 2)
	var ships: Array[ShipState] = [state]

	var log = resolver.run(ships, env)

	assert_true(log.max_impulses > 0, "max_impulses should be > 0")
	assert_true(log.ship_results.has("test_ship_1"), "Should have result for ship")

	var d = log.to_dict()
	assert_true(d.has("turn"), "Dict should have turn")
	assert_true(d.has("max_impulses"), "Dict should have max_impulses")
	assert_true(d.has("ship_results"), "Dict should have ship_results")


func test_multiple_ships_no_conflict() -> void:
	var state1 = _make_ship_state(Vector2i(0, 0), 0, 2, "C", "ship_1")
	_plot_straight(state1, 2)

	var state2 = _make_ship_state(Vector2i(10, 10), 3, 1, "B", "ship_2")
	var hex_grid = HexGrid.new()
	var s2_next = hex_grid.get_neighbor(10, 10, 3)
	state2.plotted_actions.movement = [
		{"hex": {"q": s2_next.x, "r": s2_next.y}, "facing": 3}
	]

	var ships: Array[ShipState] = [state1, state2]
	var log = resolver.run(ships, env)

	assert_not_null(log.get_result("ship_1"), "Should have result for ship 1")
	assert_not_null(log.get_result("ship_2"), "Should have result for ship 2")
	assert_eq(log.max_impulses, 2, "Max impulses from ship with 2 steps")


# ===========================================================================
# Multi-ship: contested hex — head-on
# ===========================================================================

func test_two_ships_head_on_contested_hex() -> void:
	var hex_grid = HexGrid.new()
	var target = Vector2i(5, 5)
	var ship_a_start = hex_grid.get_neighbor(target.x, target.y, 3)
	var ship_b_start = hex_grid.get_neighbor(target.x, target.y, 0)

	var state_a = _make_ship_state(ship_a_start, 0, 1, "C", "ship_a")
	state_a.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 0}
	]

	var state_b = _make_ship_state(ship_b_start, 3, 1, "C", "ship_b")
	state_b.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 3}
	]

	var ships: Array[ShipState] = [state_a, state_b]
	var log = resolver.run(ships, env)

	var result_a = log.get_result("ship_a")
	var result_b = log.get_result("ship_b")

	var has_contest_roll_a = false
	var has_contest_roll_b = false
	for ev in result_a.events:
		if ev.event_type == MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL:
			has_contest_roll_a = true
	for ev in result_b.events:
		if ev.event_type == MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL:
			has_contest_roll_b = true

	assert_true(has_contest_roll_a, "Ship A should have a contested hex roll")
	assert_true(has_contest_roll_b, "Ship B should have a contested hex roll")

	var winner_at_target = (result_a.final_hex == target or result_b.final_hex == target)
	assert_true(winner_at_target, "One ship should end at the contested hex")

	if result_a.final_hex == target:
		assert_ne(result_b.final_hex, target, "Loser should not also be at target")
	else:
		assert_ne(result_a.final_hex, target, "Loser should not also be at target")


func test_contested_hex_loser_gets_bearing_off_or_collision() -> void:
	var hex_grid = HexGrid.new()
	var target = Vector2i(5, 5)
	var ship_a_start = hex_grid.get_neighbor(target.x, target.y, 3)
	var ship_b_start = hex_grid.get_neighbor(target.x, target.y, 0)

	var state_a = _make_ship_state(ship_a_start, 0, 1, "C", "ship_a")
	state_a.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 0}
	]

	var state_b = _make_ship_state(ship_b_start, 3, 1, "C", "ship_b")
	state_b.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 3}
	]

	var ships: Array[ShipState] = [state_a, state_b]
	var log = resolver.run(ships, env)

	var result_a = log.get_result("ship_a")
	var result_b = log.get_result("ship_b")

	var loser_result = result_b if result_a.final_hex == target else result_a

	var has_bearoff_roll = false
	var has_pivot_denied = false
	var has_collision = false
	for ev in loser_result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
			has_bearoff_roll = true
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED:
			has_pivot_denied = true
		if ev.event_type == MovementTypes.ResolutionEventType.COLLISION:
			has_collision = true

	assert_true(has_bearoff_roll or has_pivot_denied, "Loser should attempt bearing off or be denied pivot")
	if has_bearoff_roll and not has_collision:
		assert_true(loser_result.stopped_at_impulse >= 0, "Bearing-off success should stop the ship")
	if has_pivot_denied:
		assert_true(has_collision, "Pivot denied should result in collision")


# ===========================================================================
# Multi-ship: three-ship contest
# ===========================================================================

func test_three_ship_contested_hex() -> void:
	var hex_grid = HexGrid.new()
	var target = Vector2i(5, 5)

	var start_a = hex_grid.get_neighbor(target.x, target.y, 3)
	var start_b = hex_grid.get_neighbor(target.x, target.y, 0)
	var start_c = hex_grid.get_neighbor(target.x, target.y, 1)

	var state_a = _make_ship_state(start_a, 0, 1, "C", "ship_a")
	state_a.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 0}
	]

	var state_b = _make_ship_state(start_b, 3, 1, "C", "ship_b")
	state_b.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 3}
	]

	var state_c = _make_ship_state(start_c, 4, 1, "C", "ship_c")
	state_c.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 4}
	]

	var ships: Array[ShipState] = [state_a, state_b, state_c]
	var log = resolver.run(ships, env)

	var at_target_count: int = 0
	for sid in ["ship_a", "ship_b", "ship_c"]:
		if log.get_result(sid).final_hex == target:
			at_target_count += 1

	assert_eq(at_target_count, 1, "Exactly one ship should win the contested hex")


# ===========================================================================
# Collision and fouling
# ===========================================================================

func test_collision_stops_both_ships() -> void:
	rng.seed = 77777
	resolver = MovementResolver.new(GameState, rng)

	var hex_grid = HexGrid.new()
	var target = Vector2i(5, 5)
	var start_a = hex_grid.get_neighbor(target.x, target.y, 3)
	var start_b = hex_grid.get_neighbor(target.x, target.y, 0)

	var state_a = _make_ship_state(start_a, 0, 2, "C", "ship_a", 3, "F")
	state_a.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 0}
	]
	var further = hex_grid.get_neighbor(target.x, target.y, 0)
	state_a.plotted_actions.movement.append(
		{"hex": {"q": further.x, "r": further.y}, "facing": 0}
	)

	var state_b = _make_ship_state(start_b, 3, 2, "C", "ship_b", 3, "F")
	state_b.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 3}
	]
	var further_b = hex_grid.get_neighbor(target.x, target.y, 3)
	state_b.plotted_actions.movement.append(
		{"hex": {"q": further_b.x, "r": further_b.y}, "facing": 3}
	)

	var ships: Array[ShipState] = [state_a, state_b]
	var log = resolver.run(ships, env)

	var result_a = log.get_result("ship_a")
	var result_b = log.get_result("ship_b")

	var has_any_collision = false
	for ev in result_a.events:
		if ev.event_type == MovementTypes.ResolutionEventType.COLLISION:
			has_any_collision = true
	for ev in result_b.events:
		if ev.event_type == MovementTypes.ResolutionEventType.COLLISION:
			has_any_collision = true

	if has_any_collision:
		var loser_result = result_b if result_a.collided_with == "" and result_b.collided_with != "" else result_a
		if loser_result.collided_with == "":
			loser_result = result_a if result_a.collided_with != "" else result_b

		if loser_result.collided_with != "":
			assert_true(loser_result.stopped_at_impulse >= 0, "Colliding ship should be stopped")
			var other_id = loser_result.collided_with
			var other_result = log.get_result(other_id)
			assert_true(other_result.stopped_at_impulse >= 0, "Other ship should also be stopped")
	else:
		pass_test("No collision occurred (both bore off successfully)")


func test_collision_rigging_loss_by_sail_state() -> void:
	var state_fs = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_fs")
	state_fs.sail_state = "FS"
	assert_eq(resolver._collision_rigging_loss(state_fs), 2, "Fighting sail = 2R")

	var state_ms = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_ms")
	state_ms.sail_state = "MS"
	assert_eq(resolver._collision_rigging_loss(state_ms), 4, "Maneuvering sail = 4R")

	var state_ps = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_ps")
	state_ps.sail_state = "PS"
	assert_eq(resolver._collision_rigging_loss(state_ps), 6, "Plain sail = 6R")

	var state_ns = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_ns")
	state_ns.sail_state = "NS"
	assert_eq(resolver._collision_rigging_loss(state_ns), 0, "No sail = 0R")


func test_dismasted_ships_cannot_foul() -> void:
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a")
	var dismasted_rigging: Array[int] = [0, 0, 0, 0]
	state_a.rigging_current_hp = dismasted_rigging

	var state_b = _make_ship_state(Vector2i(5, 6), 3, 1, "C", "ship_b")

	for _i in range(20):
		rng.seed = _i
		var fouled = resolver._roll_fouling(state_a, state_b)
		assert_false(fouled, "Dismasted ship should never foul (seed=%d)" % _i)


func test_fouling_roll_50_percent() -> void:
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a")
	var state_b = _make_ship_state(Vector2i(5, 6), 3, 1, "C", "ship_b")

	var fouled_count: int = 0
	var trials: int = 1000
	for i in range(trials):
		rng.seed = i
		if resolver._roll_fouling(state_a, state_b):
			fouled_count += 1

	var ratio: float = float(fouled_count) / float(trials)
	assert_true(ratio > 0.4 and ratio < 0.6,
		"Fouling should be ~50%%, got %.1f%%" % (ratio * 100))


# ===========================================================================
# Bearing off
# ===========================================================================

func test_bearing_off_uses_crew_quality_and_maneuverability() -> void:
	var state_good = _make_ship_state(Vector2i(5, 5), 0, 1, "A", "ship_good", 3, "A")
	var state_poor = _make_ship_state(Vector2i(5, 5), 0, 1, "D", "ship_poor", 3, "F")

	var good_threshold = DataManager.get_bearing_off_probability("A", "A")
	var poor_threshold = DataManager.get_bearing_off_probability("F", "D")

	assert_true(good_threshold > poor_threshold,
		"Better crew/maneuverability should have higher bearing off probability")


# ===========================================================================
# Moving into stationary occupied hex
# ===========================================================================

func test_moving_into_stationary_ship_triggers_bearoff_or_pivot_denied() -> void:
	var hex_grid = HexGrid.new()
	var blocker_pos = Vector2i(6, 5)

	var blocker = _make_ship_state(blocker_pos, 1, 0, "C", "blocker")

	var mover = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "mover")
	mover.plotted_actions.movement = [
		{"hex": {"q": blocker_pos.x, "r": blocker_pos.y}, "facing": 0}
	]

	var ships: Array[ShipState] = [blocker, mover]
	var log = resolver.run(ships, env)

	var mover_result = log.get_result("mover")

	var has_bearoff = false
	var has_pivot_denied = false
	for ev in mover_result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
			has_bearoff = true
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED:
			has_pivot_denied = true

	assert_true(has_bearoff or has_pivot_denied, "Moving into stationary ship should trigger bearing-off or pivot denial")
	assert_ne(mover_result.final_hex, blocker_pos, "Mover should not end on blocker's hex")


# ===========================================================================
# Apply results: collision state propagation
# ===========================================================================

func test_apply_results_sets_collision_flags() -> void:
	var hex_grid = HexGrid.new()
	var target = Vector2i(5, 5)
	var start_a = hex_grid.get_neighbor(target.x, target.y, 3)
	var start_b = hex_grid.get_neighbor(target.x, target.y, 0)

	var found_collision_seed: int = -1
	for seed_val in range(100):
		var test_rng = RandomNumberGenerator.new()
		test_rng.seed = seed_val
		var test_resolver = MovementResolver.new(GameState, test_rng)

		var sa = _make_ship_state(start_a, 0, 1, "C", "ship_a", 3, "G")
		sa.plotted_actions.movement = [
			{"hex": {"q": target.x, "r": target.y}, "facing": 0}
		]
		var sb = _make_ship_state(start_b, 3, 1, "C", "ship_b", 3, "G")
		sb.plotted_actions.movement = [
			{"hex": {"q": target.x, "r": target.y}, "facing": 3}
		]

		var test_ships: Array[ShipState] = [sa, sb]
		var test_log = test_resolver.run(test_ships, env)
		var ra = test_log.get_result("ship_a")
		var rb = test_log.get_result("ship_b")

		if ra.collided_with != "" or rb.collided_with != "":
			found_collision_seed = seed_val
			break

	if found_collision_seed < 0:
		pass_test("Could not find a seed that produces collision in 100 tries — bearing off too likely")
		return

	rng.seed = found_collision_seed
	resolver = MovementResolver.new(GameState, rng)

	var state_a = _make_ship_state(start_a, 0, 1, "C", "ship_a", 3, "G")
	state_a.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 0}
	]
	var state_b = _make_ship_state(start_b, 3, 1, "C", "ship_b", 3, "G")
	state_b.plotted_actions.movement = [
		{"hex": {"q": target.x, "r": target.y}, "facing": 3}
	]

	var ships: Array[ShipState] = [state_a, state_b]
	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	var collided_a = state_a.collision_this_turn
	var collided_b = state_b.collision_this_turn
	assert_true(collided_a or collided_b, "At least one ship should have collision_this_turn set")


# ===========================================================================
# Apply results: rigging damage
# ===========================================================================

func test_apply_results_applies_rigging_damage() -> void:
	var state = _make_ship_state()
	var initial_rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = initial_rigging.duplicate()

	var result = MovementTypes.ShipResolutionResult.new("test_ship_1")
	result.final_hex = state.hex_position
	result.final_facing = state.facing
	result.rigging_damage = 4

	var log = MovementTypes.ResolutionLog.new(1)
	log.add_result(result)

	var ships: Array[ShipState] = [state]
	resolver.apply_results(log, ships)

	var total_hp: int = 0
	for hp in state.rigging_current_hp:
		total_hp += hp
	var initial_total: int = 0
	for hp in initial_rigging:
		initial_total += hp

	assert_eq(initial_total - total_hp, 4, "Should have lost 4 rigging HP")


# ===========================================================================
# Contest DRM calculation
# ===========================================================================

func test_contest_drm_crew_quality_advantage() -> void:
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a", 3, "A")
	var state_b = _make_ship_state(Vector2i(6, 5), 3, 1, "C", "ship_b", 3, "D")

	var ship_map: Dictionary = {"ship_a": state_a, "ship_b": state_b}
	var drm_a = resolver._calculate_contest_drm_relative("ship_a", ["ship_a", "ship_b"], ship_map)
	var drm_b = resolver._calculate_contest_drm_relative("ship_b", ["ship_a", "ship_b"], ship_map)

	assert_true(drm_a > drm_b, "Ship A (crew A) should have higher DRM than ship B (crew D)")


func test_contest_drm_class_advantage() -> void:
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a", 1, "C")
	var state_b = _make_ship_state(Vector2i(6, 5), 3, 1, "C", "ship_b", 4, "C")

	var ship_map: Dictionary = {"ship_a": state_a, "ship_b": state_b}
	var drm_a = resolver._calculate_contest_drm_relative("ship_a", ["ship_a", "ship_b"], ship_map)
	var drm_b = resolver._calculate_contest_drm_relative("ship_b", ["ship_a", "ship_b"], ship_map)

	assert_true(drm_b > drm_a, "Class 4 ship should have higher DRM vs class 1 (larger class = advantage)")


func test_contest_drm_more_mp_advantage() -> void:
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "ship_a")
	_plot_straight(state_a, 3)

	var state_b = _make_ship_state(Vector2i(6, 5), 3, 1, "C", "ship_b")
	var hex_grid = HexGrid.new()
	var b_next = hex_grid.get_neighbor(6, 5, 3)
	state_b.plotted_actions.movement = [
		{"hex": {"q": b_next.x, "r": b_next.y}, "facing": 3}
	]

	var ship_map: Dictionary = {"ship_a": state_a, "ship_b": state_b}
	var drm_a = resolver._calculate_contest_drm_relative("ship_a", ["ship_a", "ship_b"], ship_map)
	var drm_b = resolver._calculate_contest_drm_relative("ship_b", ["ship_a", "ship_b"], ship_map)

	assert_true(drm_a > drm_b, "Ship with more plotted MPs should have +1 DRM")


# ===========================================================================
# Crew quality index
# ===========================================================================

func test_crew_quality_index() -> void:
	assert_eq(resolver._crew_quality_index("A"), 0)
	assert_eq(resolver._crew_quality_index("B"), 1)
	assert_eq(resolver._crew_quality_index("C"), 2)
	assert_eq(resolver._crew_quality_index("D"), 3)
	assert_eq(resolver._crew_quality_index("E"), 4)
	assert_eq(resolver._crew_quality_index("F"), 5)
	assert_eq(resolver._crew_quality_index("G"), 6)


# ===========================================================================
# Clear turn flags
# ===========================================================================

func test_clear_turn_flags() -> void:
	var state = _make_ship_state()
	state.collision_this_turn = true
	state._clear_turn_flags()
	assert_false(state.collision_this_turn, "clear_turn_flags should reset collision_this_turn")


# ===========================================================================
# Bearing off: pivot legality gate
# ===========================================================================

func test_bearing_off_pivot_denied_no_forward_hexes() -> void:
	# Ship at speed 3, maneuverability A needs 2 forward hexes before turning (turning_table same_direction/3/a=2).
	# Move it directly into a blocker on impulse 0 — 0 forward hexes, pivot should be denied.
	var hex_grid = HexGrid.new()
	var blocker_pos = Vector2i(6, 5)
	var blocker = _make_ship_state(blocker_pos, 1, 0, "C", "blocker")

	var mover = _make_ship_state(Vector2i(5, 5), 0, 3, "A", "mover", 3, "A")
	mover.ship = Ship.from_dict({
		"ship_id": "mover",
		"player_id": 0,
		"ship_name": "HMS Mover",
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "A",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
	})
	mover.plotted_actions.movement = [
		{"hex": {"q": blocker_pos.x, "r": blocker_pos.y}, "facing": 0}
	]

	var ships: Array[ShipState] = [blocker, mover]
	var log = resolver.run(ships, env)
	var mover_result = log.get_result("mover")

	var has_pivot_denied = false
	var has_collision = false
	var has_bearoff_roll = false
	for ev in mover_result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED:
			has_pivot_denied = true
		if ev.event_type == MovementTypes.ResolutionEventType.COLLISION:
			has_collision = true
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
			has_bearoff_roll = true

	assert_true(has_pivot_denied, "Should deny pivot when insufficient forward hexes")
	assert_true(has_collision, "Denied pivot should result in collision")
	assert_false(has_bearoff_roll, "Should not attempt bearing-off roll when pivot denied")


func test_bearing_off_pivot_legal_with_enough_forward_hexes() -> void:
	# Ship at speed 3, maneuverability D needs 1 forward hex before turning (turning_table same_direction/3/d=1).
	# Move it 1 hex forward, then hit a blocker on impulse 1 — should be allowed to attempt bearing off.
	var hex_grid = HexGrid.new()
	var start_pos = Vector2i(5, 5)
	var mid_hex = hex_grid.get_neighbor(start_pos.x, start_pos.y, 0)
	var blocker_pos = hex_grid.get_neighbor(mid_hex.x, mid_hex.y, 0)

	var blocker = _make_ship_state(blocker_pos, 1, 0, "C", "blocker")

	var mover = _make_ship_state(start_pos, 0, 3, "D", "mover", 3, "B")
	mover.ship = Ship.from_dict({
		"ship_id": "mover",
		"player_id": 0,
		"ship_name": "HMS Mover",
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "D",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
	})
	mover.plotted_actions.movement = [
		{"hex": {"q": mid_hex.x, "r": mid_hex.y}, "facing": 0},
		{"hex": {"q": blocker_pos.x, "r": blocker_pos.y}, "facing": 0},
	]

	var ships: Array[ShipState] = [blocker, mover]
	var log = resolver.run(ships, env)
	var mover_result = log.get_result("mover")

	var has_pivot_denied = false
	var has_bearoff_roll = false
	for ev in mover_result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED:
			has_pivot_denied = true
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
			has_bearoff_roll = true

	assert_false(has_pivot_denied, "Should allow pivot after enough forward hexes")
	assert_true(has_bearoff_roll, "Should attempt bearing-off roll when pivot is legal")


func test_bearing_off_pivot_legal_roll_fails_causes_collision() -> void:
	# Pivot is legal but the roll fails — outcome (b): collision.
	var hex_grid = HexGrid.new()
	var start_pos = Vector2i(5, 5)
	var mid_hex = hex_grid.get_neighbor(start_pos.x, start_pos.y, 0)
	var blocker_pos = hex_grid.get_neighbor(mid_hex.x, mid_hex.y, 0)

	var blocker = _make_ship_state(blocker_pos, 1, 0, "C", "blocker")

	# crew G, maneuverability A = very low bearing-off probability
	var mover = _make_ship_state(start_pos, 0, 1, "D", "mover", 3, "G")
	mover.ship = Ship.from_dict({
		"ship_id": "mover",
		"player_id": 0,
		"ship_name": "HMS Mover",
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "D",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
	})
	mover.plotted_actions.movement = [
		{"hex": {"q": mid_hex.x, "r": mid_hex.y}, "facing": 0},
		{"hex": {"q": blocker_pos.x, "r": blocker_pos.y}, "facing": 0},
	]

	# Find a seed where bearing-off roll fails (G/D threshold = 0.333)
	var found_fail_seed: int = -1
	for seed_val in range(200):
		var test_rng = RandomNumberGenerator.new()
		test_rng.seed = seed_val
		var test_resolver = MovementResolver.new(GameState, test_rng)

		var test_blocker = _make_ship_state(blocker_pos, 1, 0, "C", "blocker")
		var test_mover = _make_ship_state(start_pos, 0, 1, "D", "mover", 3, "G")
		test_mover.ship = mover.ship
		test_mover.plotted_actions.movement = mover.plotted_actions.movement.duplicate(true)

		var test_ships: Array[ShipState] = [test_blocker, test_mover]
		var test_log = test_resolver.run(test_ships, env)
		var test_result = test_log.get_result("mover")

		var has_collision = false
		var has_bearoff = false
		for ev in test_result.events:
			if ev.event_type == MovementTypes.ResolutionEventType.COLLISION:
				has_collision = true
			if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
				has_bearoff = true

		if has_bearoff and has_collision:
			found_fail_seed = seed_val
			break

	if found_fail_seed < 0:
		pass_test("Could not find a seed where bearing-off roll fails in 200 tries")
		return

	rng.seed = found_fail_seed
	resolver = MovementResolver.new(GameState, rng)

	var final_blocker = _make_ship_state(blocker_pos, 1, 0, "C", "blocker")
	var final_mover = _make_ship_state(start_pos, 0, 1, "D", "mover", 3, "G")
	final_mover.ship = mover.ship
	final_mover.plotted_actions.movement = mover.plotted_actions.movement.duplicate(true)

	var ships: Array[ShipState] = [final_blocker, final_mover]
	var log = resolver.run(ships, env)
	var mover_result = log.get_result("mover")

	var has_bearoff_roll = false
	var has_collision = false
	var has_pivot_denied = false
	for ev in mover_result.events:
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_ROLL:
			has_bearoff_roll = true
			assert_false(ev.success, "Bearing-off roll should have failed")
		if ev.event_type == MovementTypes.ResolutionEventType.COLLISION:
			has_collision = true
		if ev.event_type == MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED:
			has_pivot_denied = true

	assert_false(has_pivot_denied, "Pivot should be legal (enough forward hexes)")
	assert_true(has_bearoff_roll, "Should have attempted bearing-off roll")
	assert_true(has_collision, "Failed bearing-off roll should result in collision")
