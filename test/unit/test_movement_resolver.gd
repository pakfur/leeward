extends GutTest
## Tests for MovementResolver - single-ship and multi-ship impulse resolution
## Covers: straight movement, tacking, in-irons, contested hex, bearing off, collision, fouling
## Ships are made with three crew sections at the braces (a live T task, as Automatic crew places
## for a turn at MA 0), so the Tacking roll has no crew-section DRM unless a test changes it (5.D.2a).
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")

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
	# apply_results logs collision damage through DamageController
	_saved_turn_log = GameState.turn_log
	GameState.turn_log = PhaseEvents.PhaseLog.new()


func after_each() -> void:
	GameState.turn_log = _saved_turn_log


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
	CrewFixtures.give_tack_crew(state, 3)
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
	assert_eq(state.mp_used_this_turn, 2, "8.F.3b / 8.C.1: MPs used this g-t")


func test_unplotted_ship_moves_on_its_6g2_course() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 2)  # wind from E (0): facing W runs before it
	var ships: Array[ShipState] = [state]

	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	assert_eq(result.final_hex, Vector2i(3, 5), "Two hexes ahead on its default course")


func test_stored_course_breaking_a_jammed_rudder_holds_position() -> void:
	# 6.F: the course goes straight with the rudder jammed to port, so it is not executed.
	var state = _make_ship_state(Vector2i(5, 5), 3, 2)
	state.critical_effects.append({"id": "rudder_jammed", "side": ShipState.PORT})
	_plot_straight(state, 2)
	var ships: Array[ShipState] = [state]

	var log = resolver.run(ships, env)

	assert_eq(log.get_result("test_ship_1").final_hex, Vector2i(5, 5), "The jam-breaking course holds")


func test_explicit_empty_plot_holds_position() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 2)
	GameState.ship_controller.set_plotted_movement(state.ship_id, [])
	var ships: Array[ShipState] = [state]

	var log = resolver.run(ships, env)

	assert_eq(log.get_result("test_ship_1").final_hex, Vector2i(5, 5), "Position unchanged")


# ===========================================================================
# Single-ship: turning at MA=0 (tacking, irons) — Close Action 5.D
# ===========================================================================

## Plot a single turn from the ship's current hex, as the validator would at MA=0: the step keeps
## the bow hex and carries the new facing (5.C.2). Returns the bow hex the ship ends on.
func _plot_turn(state: ShipState, new_facing: int) -> Vector2i:
	var bow: Vector2i = state.hex_position
	GameState.ship_controller.set_plotted_movement(state.ship_id, [
		{"hex": {"q": bow.x, "r": bow.y}, "facing": new_facing},
	])
	return bow


## A seed whose first d10 (randi_range(0, 9)) is not 0, so a natural-0 success cannot rescue a roll.
func _seed_without_natural_zero() -> int:
	for s in range(1, 1000):
		var probe = RandomNumberGenerator.new()
		probe.seed = s
		if probe.randi_range(0, 9) != 0:
			return s
	return 1


func _run_one(state: ShipState) -> MovementTypes.ShipResolutionResult:
	var ships: Array[ShipState] = [state]
	return resolver.run(ships, env).get_result(state.ship_id)


func _has_event(result, event_type) -> bool:
	for ev in result.events:
		if ev.event_type == event_type:
			return true
	return false


func test_tack_from_luffing_rolls_and_completes_turn() -> void:
	# Wind from E (0), facing E = WF L, MA 0. The ship luffed last turn (speed 2), so it is not in irons.
	var state = _make_ship_state(Vector2i(5, 5), 0, 2, "D")
	env.wind_speed = 3  # D at WS 3: <=9; CQ B (SK -2) at WF=L: DRM -2, so every roll passes
	var turn_hex = _plot_turn(state, 1)
	var result = _run_one(state)

	assert_true(_has_event(result, MovementTypes.ResolutionEventType.TACKING_ROLL),
		"A turn plotted at MA=0 must roll on the Tacking table")
	assert_false(result.tacking_failed, "Low roll should pass")
	assert_false(result.immobilized, "Successful tack should not immobilize")
	assert_eq(result.final_facing, 1, "Ship completes the turn")
	assert_eq(result.final_hex, turn_hex, "The turn pivots on the bow hex")
	assert_eq(turn_hex, Vector2i(5, 5))


func test_turn_only_counts_as_an_mp_used() -> void:
	# 8.C.1 example 2 counts turns as MPs (S1P2 = 5): a ship that only turns is stopped (speed 0,
	# 5.E.2) but has used 1 MP (8.F.3b).
	var state = _make_ship_state(Vector2i(5, 5), 0, 2, "D")
	env.wind_speed = 3
	_plot_turn(state, 1)
	var ships: Array[ShipState] = [state]
	resolver.apply_results(resolver.run(ships, env), ships)
	assert_eq(state.speed, 0)
	assert_eq(state.mp_used_this_turn, 1)


func test_failed_tack_erases_the_turn() -> void:
	# Maneuver A at WS 1 needs <=2; CQ B (-2) and three rigging sections gone (+6) give +4,
	# so only a natural 0 could pass, and the seed avoids one.
	var state = _make_ship_state(Vector2i(5, 5), 0, 2, "A")
	env.wind_speed = 1
	var damaged: Array[int] = [0, 0, 0, 6]
	state.rigging_current_hp = damaged
	_plot_turn(state, 5)
	rng.seed = _seed_without_natural_zero()
	resolver = MovementResolver.new(GameState, rng)

	var result = _run_one(state)

	assert_true(_has_event(result, MovementTypes.ResolutionEventType.TACKING_ROLL), "Tacking roll made")
	assert_true(result.tacking_failed, "Tack should fail")
	assert_true(result.immobilized, "Failed tack leaves the ship in irons")
	assert_eq(result.final_facing, 0, "Turn erased: heading unchanged")
	assert_eq(result.final_hex, Vector2i(5, 5), "Turn erased: hex unchanged")


func test_moving_ship_makes_no_tacking_roll() -> void:
	# Wind from E (0), facing W (3) = running, MA > 0: an ordinary turn needs no roll.
	var state = _make_ship_state(Vector2i(5, 5), 3, 3)
	var hex_grid = HexGrid.new()
	var ahead = hex_grid.get_neighbor(5, 5, 3)
	GameState.ship_controller.set_plotted_movement(state.ship_id, [
		{"hex": {"q": ahead.x, "r": ahead.y}, "facing": 3},
		{"hex": {"q": ahead.x, "r": ahead.y}, "facing": 4},  # the turn pivots on the bow hex
	])

	var result = _run_one(state)

	assert_false(_has_event(result, MovementTypes.ResolutionEventType.TACKING_ROLL),
		"No tacking roll when the ship has movement allowance")
	assert_eq(result.final_hex, ahead, "The turn keeps the bow hex")
	assert_eq(result.final_facing, 4, "The turn is made")


# ===========================================================================
# Single-ship: in irons
# ===========================================================================

func test_in_irons_without_a_plotted_turn_stays_in_irons() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 0, "C")
	env.wind_direction = 0

	var result = _run_one(state)

	assert_true(result.immobilized, "Ship stays in irons")
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.TACKING_ROLL), "No roll without a plotted turn")
	assert_eq(result.final_facing, 0, "Heading unchanged")


func test_in_irons_plotted_turn_can_turn_out() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 0, "D")
	env.wind_speed = 3  # <=9; CQ B (-2) in irons (+1): DRM -1, so every roll passes
	var turn_hex = _plot_turn(state, 5)
	var result = _run_one(state)

	assert_true(_has_event(result, MovementTypes.ResolutionEventType.TACKING_ROLL), "Turning out of irons rolls")
	assert_false(result.immobilized, "Ship is out of irons")
	assert_eq(result.final_facing, 5, "Ship turns out of the wind")
	assert_eq(result.final_hex, turn_hex, "The turn pivots on the bow hex")
	assert_eq(turn_hex, Vector2i(5, 5))


func test_rolled_back_tack_keeps_its_roll_and_later_dice() -> void:
	# I is in irons (speed 0, WF L) and tacks out (maneuverability D at WS 3: every roll passes); its
	# stern swings onto stopped B's bow (4,6) and stays there, so the turn is rolled back and I's plot is
	# amended to nothing. X, listed after I, tacks out of irons too. The replay still draws I's tacking
	# die, so X's roll is the same second die as in the first pass, and I's log tells the tack and the
	# rollback, not "no turn plotted".
	env.wind_direction = 0
	env.wind_speed = 3
	var ship_i = _make_ship_state(Vector2i(5, 5), 0, 0, "D", "ship_i")  # bow (5,5), stern (4,5)
	var ship_x = _make_ship_state(Vector2i(10, 5), 0, 0, "D", "ship_x")
	var blocker = _make_ship_state(Vector2i(4, 6), 0, 0, "C", "blocker")  # bow (4,6), stern (3,6)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 5), Vector2i(4, 6), "I's stern swings onto the blocker")
	_plot_turn(ship_i, 5)
	_plot_turn(ship_x, 5)
	rng.seed = 2024
	var probe := RandomNumberGenerator.new()
	probe.seed = 2024
	var first_die := probe.randi_range(0, 9)
	var second_die := probe.randi_range(0, 9)
	resolver = MovementResolver.new(GameState, rng)
	var ships: Array[ShipState] = [ship_i, ship_x, blocker]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result_i = log.get_result("ship_i")
	var result_x = log.get_result("ship_x")

	assert_eq(ship_i.facing, 0, "I's turn is rolled back")
	assert_eq(_events_of(result_i, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK).size(), 1)
	var tacks_i = _events_of(result_i, MovementTypes.ResolutionEventType.TACKING_ROLL)
	assert_eq(tacks_i.size(), 1, "I's tacking roll stays in the log")
	if tacks_i.size() == 1:
		assert_eq(int(tacks_i[0].roll), first_die)
	var tacks_x = _events_of(result_x, MovementTypes.ResolutionEventType.TACKING_ROLL)
	assert_eq(tacks_x.size(), 1)
	if tacks_x.size() == 1:
		assert_eq(int(tacks_x[0].roll), second_die, "X's die is not shifted by I's rollback")
	assert_eq(ship_x.facing, 5, "X turns out of irons")
	for ev in _events_of(result_i, MovementTypes.ResolutionEventType.IMMOBILIZED):
		assert_ne(ev.detail, "in irons, no turn plotted", "I did plot a turn")
	var irons = _events_of(result_i, MovementTypes.ResolutionEventType.IMMOBILIZED)
	assert_eq(irons.size(), 1)
	if irons.size() == 1:
		assert_eq(irons[0].detail, "in irons, turn rolled back")
	assert_true(result_i.immobilized, "I is still in irons")
	_assert_no_overlap(ships)


func test_not_in_irons_when_off_the_wind() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 0, "C")
	env.wind_direction = 0

	var result = _run_one(state)

	assert_false(result.immobilized, "Ship facing W with wind from E is not in irons")


# ===========================================================================
# DRM calculation
# ===========================================================================

func test_tacking_drm_with_lost_rigging() -> void:
	# Facing W, wind from E: not at WF=L (-2); CQ B (-2); two sections lost (+4)
	var state = _make_ship_state(Vector2i(5, 5), 3, 3)
	var damaged_rigging: Array[int] = [5, 0, 6, 0]
	state.rigging_current_hp = damaged_rigging
	assert_eq(resolver._calculate_tacking_drm(state), 0, "-2 SK -2 off the wind +4 rigging")


func test_tacking_drm_with_towing() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 3)
	state.towing = true
	assert_eq(resolver._calculate_tacking_drm(state), -3, "-2 SK -2 off the wind +1 towing")


func test_tacking_drm_at_wind_facing_l() -> void:
	var state = _make_ship_state()  # facing E into a wind from E, speed 3
	env.wind_direction = 0
	assert_eq(resolver._calculate_tacking_drm(state), -2, "At WF=L only the SK mod applies")


func test_tacking_drm_in_irons() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 0)
	env.wind_direction = 0
	assert_eq(resolver._calculate_tacking_drm(state), -1, "SK -2, in irons +1")


# 5.D.3b: reverse tack. Wind from E (0): facing 0 is WF=L, facing 5 and 1 are not.

func test_turning_into_luffing_records_entry_turn() -> void:
	# A STARBOARD turn (facing 5 -> 0) ends the g-t at WF=L.
	var state = _make_ship_state(Vector2i(5, 5), 5, 3, "D")
	_plot_turn(state, 0)
	var ships: Array[ShipState] = [state]
	resolver.apply_results(resolver.run(ships, env), ships)
	assert_eq(state.facing, 0)
	assert_eq(state.irons_entry_turn, ShipState.STARBOARD)


func test_leaving_luffing_clears_entry_turn() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 0, "D")
	state.irons_entry_turn = ShipState.STARBOARD
	_plot_turn(state, 1)
	var ships: Array[ShipState] = [state]
	resolver.apply_results(resolver.run(ships, env), ships)
	assert_eq(state.irons_entry_turn, -1)


func test_wind_shift_into_luffing_has_no_entry_turn() -> void:
	# WF=L reached with no turn executed: no entry turn, and no +3 either way.
	var state = _make_ship_state(Vector2i(5, 5), 0, 0, "D")
	assert_eq(state.irons_entry_turn, -1)
	assert_false(resolver.is_reverse_tack(state, ShipState.PORT))
	assert_false(resolver.is_reverse_tack(state, ShipState.STARBOARD))


func test_reverse_tack_adds_three() -> void:
	# 5.D.3b: turning back the way it came takes the Reversing Tack DRM (+3, chart).
	var state = _make_ship_state(Vector2i(5, 5), 0, 2, "D")
	state.irons_entry_turn = ShipState.STARBOARD
	var same: int = resolver._calculate_tacking_drm(state, 3, ShipState.STARBOARD)
	var back: int = resolver._calculate_tacking_drm(state, 3, ShipState.PORT)
	assert_eq(back - same, 3)


func test_reverse_tack_reads_the_plotted_turn() -> void:
	# The first plotted step is a PORT turn (facing 0 -> 5); the ship came in by STARBOARD.
	var state = _make_ship_state(Vector2i(5, 5), 0, 2, "D")
	state.irons_entry_turn = ShipState.STARBOARD
	var same: int = resolver._calculate_tacking_drm(state)  # no plot: no turn, no +3
	_plot_turn(state, 5)
	assert_eq(resolver._calculate_tacking_drm(state) - same, 3)
	_plot_turn(state, 1)  # starboard: continues the way it came
	assert_eq(resolver._calculate_tacking_drm(state), same)


func test_reverse_tack_stacks_with_in_irons() -> void:
	# Speed 0 at WF=L (in irons, +1) and reversing (+3): both apply (SK -2).
	var state = _make_ship_state(Vector2i(5, 5), 0, 0, "D")
	state.irons_entry_turn = ShipState.STARBOARD
	assert_eq(resolver._calculate_tacking_drm(state, 3, ShipState.PORT), -2 + 1 + 3)


func test_irons_entry_turn_is_serialized() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 0, "D")
	state.irons_entry_turn = ShipState.PORT
	assert_eq(ShipState.deserialize(state.serialize()).irons_entry_turn, ShipState.PORT)


func test_tacking_drm_healthy_ship_not_luffing() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 3, 3)
	assert_eq(resolver._calculate_tacking_drm(state), -4, "SK -2, not at WF=L -2")


func test_tacking_drm_crew_quality() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "test_ship_1", 3, "G")
	assert_eq(resolver._calculate_tacking_drm(state), 3, "CQ G: SK +3")


func test_tacking_drm_compound() -> void:
	var state = _make_ship_state()
	env.wind_direction = 0
	state.towing = true
	var compound_rigging: Array[int] = [0, 5, 6, 0]
	state.rigging_current_hp = compound_rigging
	assert_eq(resolver._calculate_tacking_drm(state), 3, "SK -2 + towing 1 + 2 rigging lost 4")


# ===========================================================================
# Crew sections at the braces (5.D.2a; crew-tasks spec §3.6, §8 #10-12)
# ===========================================================================

func test_tack_crew_drm_two_per_section_short_up_to_six() -> void:
	# 5.D.2a: the table assumes 3 CSs plotted to "T"; +2 per CS not plotted, at most +6 (the
	# chart's "up to +8" is a misprint).
	assert_eq(MovementResolver.tack_crew_drm(3), 0)
	assert_eq(MovementResolver.tack_crew_drm(2), 2)
	assert_eq(MovementResolver.tack_crew_drm(1), 4)
	assert_eq(MovementResolver.tack_crew_drm(0), 6)
	assert_eq(MovementResolver.tack_crew_drm(5), 0, "never a bonus")


func test_tacking_drm_one_section_at_the_braces() -> void:
	# Spec §8 #10 (5.D.2a; Majestic g-t 18): 1 CS at T, CQ B, no rigging lost, at WF=L, not in
	# irons: -2 (SK) +4 = +2.
	var state = _make_ship_state(Vector2i(5, 5), 0, 3)
	CrewFixtures.give_tack_crew(state, 1)
	assert_eq(resolver._calculate_tacking_drm(state), 2)


func test_tacking_drm_no_section_at_the_braces_is_six_not_eight() -> void:
	# Spec §8 #11 (5.D.2a erratum): no CS at T: +6, so CQ B at WF=L is -2 +6 = +4.
	var state = _make_ship_state(Vector2i(5, 5), 0, 3)
	CrewFixtures.give_tack_crew(state, 0)
	assert_eq(state.tack_sections(), 0)
	assert_eq(resolver._calculate_tacking_drm(state), 4)
	assert_eq(resolver._calculate_tacking_drm(state, 0), 4, "an explicit planned count")


func test_tacking_chance_prince_example_three_sections() -> void:
	# Spec §8 #12 (5.D.3 example, Prince): type A, WS 3, CQ B, 3 CS at T, at WF=L: chart <= 6,
	# DRM -2: d10 0-8 succeed, 90 %.
	var state = _make_ship_state(Vector2i(5, 5), 0, 3, "A")
	env.wind_speed = 3
	assert_almost_eq(resolver.tacking_chance(state), 0.9, 0.001)
	assert_almost_eq(resolver.tacking_chance(state, 3), 0.9, 0.001)


func test_tacking_chance_with_planned_sections() -> void:
	# Same ship with 1 CS planned at the braces: DRM -2 +4 = +2, d10 + 2 <= 6: 0-4, 50 %;
	# with none, +4: 0-2, 30 %.
	var state = _make_ship_state(Vector2i(5, 5), 0, 3, "A")
	env.wind_speed = 3
	assert_almost_eq(resolver.tacking_chance(state, 1), 0.5, 0.001)
	assert_almost_eq(resolver.tacking_chance(state, 0), 0.3, 0.001)


func test_tack_without_crew_at_the_braces_can_fail_where_a_full_crew_passes() -> void:
	# Type D at WS 3 needs <= 9. CQ B at WF=L: with 3 CS the DRM is -2 and every roll passes; with
	# none it is +4, so a d10 of 6 or more fails (5.D.2a).
	var seed_value := -1
	for candidate in range(1, 2000):
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate
		if probe.randi_range(0, 9) >= 6:
			seed_value = candidate
			break
	var state = _make_ship_state(Vector2i(5, 5), 0, 2, "D")
	env.wind_speed = 3
	_plot_turn(state, 1)
	rng.seed = seed_value
	assert_false(_run_one(state).tacking_failed, "3 at the braces: passes")
	CrewFixtures.give_tack_crew(state, 0)
	_plot_turn(state, 1)
	rng.seed = seed_value
	assert_true(_run_one(state).tacking_failed, "nobody at the braces: d10 >= 6 + 4 > 9 fails")


func test_plots_ma0_turn() -> void:
	# 5.D.1: a plot that starts with a turn while the MA is 0 needs a Tacking roll.
	var state = _make_ship_state(Vector2i(5, 5), 0, 3)
	var turn := [{"hex": {"q": 5, "r": 5}, "facing": 1}]
	var ahead := [{"hex": {"q": 6, "r": 5}, "facing": 0}]
	assert_true(MovementResolver.plots_ma0_turn(state, turn, 0))
	assert_false(MovementResolver.plots_ma0_turn(state, turn, 2), "MA above 0: an ordinary turn")
	assert_false(MovementResolver.plots_ma0_turn(state, ahead, 0))
	assert_false(MovementResolver.plots_ma0_turn(state, [], 0))


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
		# 6.D.4: a successful bear-off turns the ship where it stands
		assert_ne(loser_result.final_facing, (state_a if loser_result == result_a else state_b).facing,
			"Bearing-off success turns the ship")
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
	# 6.E.3 / Collision Resolution chart: extra rigging lost is d6-1 at FS, d6+1 at MS, 2d6 at PS.
	assert_eq(MovementResolver.collision_rigging_loss("FS", 1, 6), 0, "FS: d6-1, low end 0")
	assert_eq(MovementResolver.collision_rigging_loss("FS", 6, 1), 5, "FS: d6-1, high end 5")
	assert_eq(MovementResolver.collision_rigging_loss("MS", 1, 6), 2, "MS: d6+1, low end 2")
	assert_eq(MovementResolver.collision_rigging_loss("ms", 6, 1), 7, "MS: d6+1, high end 7")
	assert_eq(MovementResolver.collision_rigging_loss("PS", 1, 1), 2, "PS: 2d6, low end 2")
	assert_eq(MovementResolver.collision_rigging_loss("PS", 6, 6), 12, "PS: 2d6, high end 12")
	assert_eq(MovementResolver.collision_rigging_loss("PS", 3, 4), 7, "PS: both dice count")
	assert_eq(MovementResolver.collision_rigging_loss("NS", 6, 6), 0, "No sail: no whiplash")


func _rigging_loss_events(result: MovementTypes.ShipResolutionResult) -> Array:
	return _events_of(result, MovementTypes.ResolutionEventType.COLLISION_RIGGING_LOSS)


func test_ramming_a_stopped_ship_only_the_rammer_loses_rigging() -> void:
	# 6.E.3: the ship that collides pointing at the other loses rigging; the ship it hits does not.
	# A cannot bear off (speed 3, maneuverability A needs 2 hexes ahead first), so it collides.
	var stopped_ship = _make_ship_state(Vector2i(6, 5), 1, 0, "C", "stopped")
	stopped_ship.sail_state = "PS"
	var ship_a = _make_ship_state(Vector2i(5, 5), 0, 3, "A", "ship_a", 3, "A")
	ship_a.sail_state = "PS"
	ship_a.plotted_actions.movement = [{"hex": {"q": 6, "r": 5}, "facing": 0}]
	var ships: Array[ShipState] = [ship_a, stopped_ship]

	var hold := {"ship_a": {"choice": MovementTypes.BEAR_OFF_COLLIDE, "segment": 0}}
	for seed_value in [1, 2, 3, 4, 5]:
		rng.seed = seed_value
		var log = resolver.run(ships, env, hold)
		var result_a = log.get_result("ship_a")
		var result_s = log.get_result("stopped")
		assert_eq(result_a.collided_with, "stopped")
		assert_between(result_a.rigging_damage, 2, 12, "PS: 2d6 rigging boxes")
		assert_eq(_rigging_loss_events(result_a).size(), 1)
		assert_eq(result_s.rigging_damage, 0, "The rammed ship loses no extra rigging")
		assert_eq(_rigging_loss_events(result_s).size(), 0)


func test_ships_running_into_each_other_both_lose_rigging() -> void:
	# 6.E.3: "If the two ships run into one another, both ships must roll". Head-on: A (bow (5,5),
	# heading E) and B (bow (6,5), heading W) each plot one hex ahead into the other's bow. Both hold
	# course instead of bearing off (6.E.1), so they collide.
	var ship_a = _make_ship_state(Vector2i(5, 5), 0, 3, "A", "ship_a", 3, "A")
	ship_a.sail_state = "PS"
	ship_a.plotted_actions.movement = [{"hex": {"q": 6, "r": 5}, "facing": 0}]
	var ship_b = _make_ship_state(Vector2i(6, 5), 3, 3, "A", "ship_b", 3, "A")
	ship_b.sail_state = "MS"
	ship_b.plotted_actions.movement = [{"hex": {"q": 5, "r": 5}, "facing": 3}]
	var ships: Array[ShipState] = [ship_a, ship_b]
	var hold := {"ship_a": {"choice": MovementTypes.BEAR_OFF_COLLIDE, "segment": 0},
		"ship_b": {"choice": MovementTypes.BEAR_OFF_COLLIDE, "segment": 0}}

	var log = resolver.run(ships, env, hold)
	var result_a = log.get_result("ship_a")
	var result_b = log.get_result("ship_b")

	assert_true(result_a.collided_with == "ship_b" and result_b.collided_with == "ship_a", "Head-on collision")
	assert_eq(result_a.final_hex, Vector2i(5, 5))
	assert_eq(result_b.final_hex, Vector2i(6, 5))
	assert_between(result_a.rigging_damage, 2, 12, "A at PS: 2d6")
	assert_between(result_b.rigging_damage, 2, 7, "B at MS: d6+1")
	assert_eq(_rigging_loss_events(result_a).size(), 1)
	assert_eq(_rigging_loss_events(result_b).size(), 1)


func test_dismasted_ships_cannot_foul() -> void:
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a")
	var dismasted_rigging: Array[int] = [0, 0, 0, 0]
	state_a.rigging_current_hp = dismasted_rigging

	var state_b = _make_ship_state(Vector2i(5, 6), 3, 1, "C", "ship_b")

	for _i in range(20):
		rng.seed = _i
		var fouled = resolver.roll_fouling(state_a, state_b)
		assert_false(fouled, "Dismasted ship should never foul (seed=%d)" % _i)


## Collision fouling (1997 Collision Resolution chart): d10 0-9 from the resolver's own rng,
## fouled on 6+, +1 per ship at MS, +2 per ship at PS, nothing for FS; no drifting penalty.
func _fouls_at_roll(sail_a: String, sail_b: String, die: int) -> bool:
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a")
	var state_b = _make_ship_state(Vector2i(5, 6), 3, 1, "C", "ship_b")
	state_a.sail_state = sail_a
	state_b.sail_state = sail_b
	# Find a seed whose first randi_range(0, 9) is the wanted die value.
	for seed_val in range(1000):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_val
		if probe.randi_range(0, 9) == die:
			rng.seed = seed_val
			return resolver.roll_fouling(state_a, state_b)
	fail_test("No seed produces die %d" % die)
	return false


func test_collision_fouling_both_fs_needs_6_or_more() -> void:
	for die in range(10):
		assert_eq(_fouls_at_roll("FS", "FS", die), die >= 6, "FS/FS die %d" % die)


func test_collision_fouling_both_ms_needs_4_or_more() -> void:
	for die in range(10):
		assert_eq(_fouls_at_roll("MS", "MS", die), die >= 4, "MS/MS die %d" % die)


func test_collision_fouling_ps_counts_two_each() -> void:
	assert_true(_fouls_at_roll("PS", "FS", 4), "PS+FS: 4+2 = 6")
	assert_false(_fouls_at_roll("PS", "FS", 3), "PS+FS: 3+2 = 5")
	assert_true(_fouls_at_roll("PS", "PS", 2), "PS+PS: 2+4 = 6")


func test_collision_fouling_dismasted_never_fouls() -> void:
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a")
	var state_b = _make_ship_state(Vector2i(5, 6), 3, 1, "C", "ship_b")
	state_b.sail_state = "PS"
	var dismasted: Array[int] = [0, 0, 0, 0]
	state_b.rigging_current_hp = dismasted
	state_a.sail_state = "PS"
	for i in range(20):
		rng.seed = i
		assert_false(resolver.roll_fouling(state_a, state_b), "seed %d" % i)


# ===========================================================================
# Movement lock: fouled and struck ships ignore plotted movement
# ===========================================================================

func test_fouled_ship_ignores_plotted_movement() -> void:
	var state = _make_ship_state()
	state.fouled_with = "other"
	_plot_straight(state, 3)
	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")
	assert_eq(result.final_hex, Vector2i(5, 5), "Fouled ship stays in place")
	resolver.apply_results(log, ships)
	assert_eq(state.hex_position, Vector2i(5, 5))
	assert_false(state.moved_this_turn, "Fouled ship did not move")


func test_struck_ship_ignores_plotted_movement() -> void:
	var state = _make_ship_state()
	state.status = ShipState.Status.STRUCK
	_plot_straight(state, 3)
	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")
	assert_eq(result.final_hex, Vector2i(5, 5), "Struck ship stays in place")
	resolver.apply_results(log, ships)
	assert_eq(state.hex_position, Vector2i(5, 5))
	assert_false(state.moved_this_turn, "Struck ship did not move")


func test_destroyed_ship_ignores_plotted_movement() -> void:
	var state = _make_ship_state()
	state.status = ShipState.Status.DESTROYED
	_plot_straight(state, 3)
	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	assert_eq(log.get_result("test_ship_1").final_hex, Vector2i(5, 5), "A wreck stays in place")


# ===========================================================================
# Bearing off
# ===========================================================================

func test_bearing_off_uses_crew_quality_and_maneuverability() -> void:
	var state_good = _make_ship_state(Vector2i(5, 5), 0, 1, "A", "ship_good", 3, "A")
	var state_poor = _make_ship_state(Vector2i(5, 5), 0, 1, "D", "ship_poor", 3, "F")

	var good_number = DataManager.get_bearing_off_number("A", "A")
	var poor_number = DataManager.get_bearing_off_number("F", "D")

	assert_true(good_number > poor_number,
		"Better crew/maneuverability should need a less demanding roll")


func test_bearing_off_drm_by_mps_plotted() -> void:
	var state = _make_ship_state()
	_plot_straight(state, 3)
	assert_eq(resolver._bearing_off_drm(state), 0, "1-3 MPs plotted: no DRM")
	_plot_straight(state, 4)
	assert_eq(resolver._bearing_off_drm(state), 1, "4-6 MPs plotted: +1")
	_plot_straight(state, 7)
	assert_eq(resolver._bearing_off_drm(state), 2, "7+ MPs plotted: +2")


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


func _apply_collision_loss(state: ShipState, loss: int) -> void:
	var result = MovementTypes.ShipResolutionResult.new(state.ship_id)
	result.final_hex = state.hex_position
	result.final_facing = state.facing
	result.collided_with = "other"
	result.rigging_damage = loss
	var log = MovementTypes.ResolutionLog.new(1)
	log.add_result(result)
	var ships: Array[ShipState] = [state]
	resolver.apply_results(log, ships)


func test_collision_loss_comes_off_lowest_section_first() -> void:
	var state = _make_ship_state()
	_apply_collision_loss(state, 4)
	assert_eq(state.rigging_current_hp, [1, 5, 6, 6] as Array[int], "section 1 loses the boxes")
	assert_eq(state.sail_state, "MS", "not dismasted: sail unchanged")
	assert_eq(state.pending_morale_checks, 0)


func test_collision_dismasting_follows_the_damage_rules() -> void:
	var state = _make_ship_state()
	var rigging: Array[int] = [0, 0, 1, 2]
	state.rigging_current_hp = rigging
	_apply_collision_loss(state, 4)
	assert_true(state.is_dismasted(), "the last rigging boxes are gone")
	assert_eq(state.sail_state, "NS", "a dismasted ship carries no sail")
	assert_eq(state.pending_morale_checks, 1, "one 'dismasted' morale check noted")
	var damage: Array = GameState.turn_log.of_type(PhaseEvents.Type.DAMAGE)
	assert_eq(damage.size(), 1, "one DAMAGE event")
	if damage.size() == 1:
		assert_eq(damage[0].ship_id, "test_ship_1")
		assert_eq(damage[0].data["rigging"], 3, "the boxes actually removed")
		assert_eq(damage[0].phase, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION)


# ===========================================================================
# Collision fouling: a ship already fouled with a third ship keeps its partner
# ===========================================================================

## Runs _apply_collision between ship_a and ship_b (both at PS, so fouling succeeds on 2+)
## for seeds 0-19; returns how many seeds fouled the pair.
func _collision_foulings(b_already_fouled_in_state: bool, b_already_fouled_this_turn: bool) -> int:
	var count := 0
	for seed_val in range(20):
		GameState.ships.clear()
		var state_a = _make_ship_state(Vector2i(4, 5), 0, 1, "C", "ship_a")
		var state_b = _make_ship_state(Vector2i(5, 5), 3, 0, "C", "ship_b")
		state_a.sail_state = "PS"
		state_b.sail_state = "PS"
		if b_already_fouled_in_state:
			state_b.fouled_with = "ship_c"
		var result_a = MovementTypes.ShipResolutionResult.new("ship_a")
		var result_b = MovementTypes.ShipResolutionResult.new("ship_b")
		if b_already_fouled_this_turn:
			result_b.fouled_with = "ship_c"
		var test_rng = RandomNumberGenerator.new()
		test_rng.seed = seed_val
		var test_resolver = MovementResolver.new(GameState, test_rng)
		var p := MovementResolver.ResolutionPass.new()
		p.ship_map = {"ship_a": state_a, "ship_b": state_b}
		p.results = {"ship_a": result_a, "ship_b": result_b}
		p.current_hexes = {"ship_a": state_a.hex_position, "ship_b": state_b.hex_position}
		test_resolver._apply_collision(p, MovementResolver.Segment.new(), "ship_a", "ship_b")
		if result_a.fouled_with != "":
			count += 1
			assert_eq(result_b.fouled_with, "ship_a", "a new fouling is mutual")
		elif b_already_fouled_this_turn:
			assert_eq(result_b.fouled_with, "ship_c", "the earlier fouling is kept")
	return count


func test_collision_fouls_free_ships() -> void:
	assert_gt(_collision_foulings(false, false), 0, "control: free ships at PS do foul")


func test_collision_does_not_foul_ship_fouled_with_a_third() -> void:
	assert_eq(_collision_foulings(true, false), 0, "ship_b stays fouled with ship_c only")


func test_collision_does_not_foul_ship_fouled_earlier_this_resolution() -> void:
	assert_eq(_collision_foulings(false, true), 0, "ship_b keeps the fouling from this turn")


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
	GameState.ship_controller.set_plotted_movement("ship_a", [])  # no 6.G.2 course: MPs count nothing
	GameState.ship_controller.set_plotted_movement("ship_b", [])

	var ship_map: Dictionary = {"ship_a": state_a, "ship_b": state_b}
	var drm_a = resolver._calculate_contest_drm_relative("ship_a", ["ship_a", "ship_b"], ship_map)
	var drm_b = resolver._calculate_contest_drm_relative("ship_b", ["ship_a", "ship_b"], ship_map)

	assert_true(drm_a > drm_b, "Class 1 (largest) should beat class 4 (6.C.2c: +1 per class larger)")
	assert_eq(drm_a, 3, "Three classes larger = +3")
	assert_eq(drm_b, 0, "The smaller ship gets no class bonus")


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
	# 6.D.2: a ship may bear off only if a turn is legal there. The mover turns starboard on segment 0
	# and meets the blocker on segment 1: it "just turned in the previous MP", so it cannot bear off.
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
	var blocker_ahead: Vector2i = Vector2i(5, 6)  # ahead of the mover after its turn to SE
	blocker.hex_position = blocker_ahead
	blocker.facing = 0  # bow (5,6), stern (4,6)
	mover.plotted_actions.movement = [
		{"hex": {"q": 5, "r": 5}, "facing": 1},
		{"hex": {"q": blocker_ahead.x, "r": blocker_ahead.y}, "facing": 1},
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

	assert_true(has_pivot_denied, "Should deny the bear-off right after a turn")
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

	# crew G, maneuverability D: bearing off needs a d10 of 0 or 1
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

	# Find a seed where bearing-off roll fails (G/D: <=1)
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


# ===========================================================================
# moved_this_turn
# ===========================================================================

func test_apply_results_sets_moved_this_turn() -> void:
	var mover = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "mover")
	var idle = _make_ship_state(Vector2i(5, 9), 0, 3, "C", "idle")
	_plot_straight(mover, 2)
	idle.moved_this_turn = true  # stale flag must be overwritten
	var ships: Array[ShipState] = [mover, idle]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	assert_true(mover.moved_this_turn, "Ship that advanced has moved_this_turn")
	assert_false(idle.moved_this_turn, "Ship with no plot has moved_this_turn false")


# ===========================================================================
# Tacking chance shown on the planning screen
# ===========================================================================

func test_tacking_chance_applies_chart_drms() -> void:
	# Type A at WS 1 needs <=2; CQ B at WF=L (not in irons): DRM -2, so d10 0-4 succeed
	var state = _make_ship_state(Vector2i(5, 5), 0, 3, "A")
	env.wind_speed = 1
	assert_almost_eq(resolver.tacking_chance(state), 0.5, 0.001)


func test_tacking_chance_in_irons() -> void:
	# Same ship stopped head to wind: +1 in irons, DRM -1, so d10 0-3 succeed
	var state = _make_ship_state(Vector2i(5, 5), 0, 0, "A")
	env.wind_speed = 1
	assert_almost_eq(resolver.tacking_chance(state), 0.4, 0.001)


func test_tacking_chance_natural_zero_floor() -> void:
	# CQ G (+3) and three rigging sections lost (+6): only a natural 0 succeeds
	var state = _make_ship_state(Vector2i(5, 5), 0, 3, "A", "test_ship_1", 3, "G")
	env.wind_speed = 1
	var damaged: Array[int] = [0, 0, 0, 6]
	state.rigging_current_hp = damaged
	assert_almost_eq(resolver.tacking_chance(state), 0.1, 0.001)


func test_tacking_chance_zero_in_calm() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 3, "A")
	env.wind_speed = 0
	assert_almost_eq(resolver.tacking_chance(state), 0.0, 0.001)


func test_turn_step_keeps_bow_hex_and_applies_new_facing() -> void:
	# A plotted turn pivots on the bow (5.C.2): the step's hex is the unchanged bow hex.
	var state = _make_ship_state(Vector2i(5, 5), 0, 3)
	GameState.ship_controller.set_plotted_movement(state.ship_id, [
		{"hex": {"q": 5, "r": 5}, "facing": 1, "move_type": MovementTypes.MoveType.STARBOARD},
	])
	var ships: Array[ShipState] = [state]

	var log = resolver.run(ships, env)
	var result = log.get_result("test_ship_1")

	assert_eq(result.final_hex, Vector2i(5, 5), "The bow stays put")
	assert_eq(result.final_facing, 1, "The new facing is applied in place")
	assert_false(result.immobilized)


func test_speed_counts_turn_steps_when_ship_moved_ahead() -> void:
	# 5.E.2: turn + 2 forward uses 3 MPs.
	var state = _make_ship_state(Vector2i(5, 5), 0, 3)
	GameState.ship_controller.set_plotted_movement(state.ship_id, [
		{"hex": {"q": 5, "r": 5}, "facing": 1},
		{"hex": {"q": 5, "r": 6}, "facing": 1},
		{"hex": {"q": 5, "r": 7}, "facing": 1},
	])
	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	assert_eq(state.speed, 3, "Turn and two forward steps are 3 MPs")
	assert_true(state.moved_this_turn)
	assert_eq(state.hex_position, Vector2i(5, 7))


func test_turn_only_ship_is_stopped() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 3)
	GameState.ship_controller.set_plotted_movement(state.ship_id, [
		{"hex": {"q": 5, "r": 5}, "facing": 1},
	])
	var ships: Array[ShipState] = [state]
	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	assert_eq(state.facing, 1)
	assert_eq(state.speed, 0, "A ship that only turns is stopped")
	assert_false(state.moved_this_turn)
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT).size(), 0)


# ===========================================================================
# Two-hex footprints (Task 4): bow-entries and stern-entries
# ===========================================================================

func _events_of(result: MovementTypes.ShipResolutionResult, event_type) -> Array:
	var found: Array = []
	for ev in result.events:
		if ev.event_type == event_type:
			found.append(ev)
	return found


func test_entered_hex_ahead_is_new_bow_turn_is_new_stern() -> void:
	assert_eq(resolver._entered_hex(Vector2i(5, 5), 0, Vector2i(6, 5), 0), Vector2i(6, 5),
		"An ahead step enters its new bow hex")
	assert_eq(resolver._entered_hex(Vector2i(5, 5), 0, Vector2i(5, 5), 1), Vector2i(5, 4),
		"A turn enters its new stern hex")


func test_bow_into_stopped_ships_stern_is_conflict() -> void:
	# B (stopped) has its bow on (6, 6) facing SE, so its stern is on (6, 5): right ahead of A.
	var blocker = _make_ship_state(Vector2i(6, 6), 1, 0, "C", "ship_b")
	assert_eq(blocker.stern_hex(), Vector2i(6, 5))
	var mover = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a")
	mover.plotted_actions.movement = [{"hex": {"q": 6, "r": 5}, "facing": 0}]
	var ships: Array[ShipState] = [blocker, mover]

	var result = resolver.run(ships, env).get_result("ship_a")

	var conflict: bool = _has_event(result, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL) \
		or _has_event(result, MovementTypes.ResolutionEventType.COLLISION)
	assert_true(conflict, "Entering a stopped ship's stern hex is a potential collision")
	assert_eq(result.blocked_by, "ship_b")
	assert_eq(result.final_hex, Vector2i(5, 5), "A does not enter B's stern hex")


func test_two_bows_same_hex_contested() -> void:
	# A and B approach (5, 5) from W and E; their sterns trail behind on (3, 5) and (7, 5).
	var state_a = _make_ship_state(Vector2i(4, 5), 0, 1, "C", "ship_a")
	state_a.plotted_actions.movement = [{"hex": {"q": 5, "r": 5}, "facing": 0}]
	var state_b = _make_ship_state(Vector2i(6, 5), 3, 1, "C", "ship_b")
	state_b.plotted_actions.movement = [{"hex": {"q": 5, "r": 5}, "facing": 3}]
	var ships: Array[ShipState] = [state_a, state_b]

	var log = resolver.run(ships, env)
	var result_a = log.get_result("ship_a")
	var result_b = log.get_result("ship_b")

	assert_true(_has_event(result_a, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL))
	assert_true(_has_event(result_b, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL))
	var at_target: int = int(result_a.final_hex == Vector2i(5, 5)) + int(result_b.final_hex == Vector2i(5, 5))
	assert_eq(at_target, 1, "Exactly one bow enters the contested hex")


func test_stern_swing_into_occupied_hex_with_no_further_mps_rolls_back() -> void:
	# 6.B.4a: A on (5, 5) facing E turns to starboard (facing 1) and plots nothing more: its new stern
	# (5, 4) overlaps B, which nobody vacates on the next segment. A swings back and stops.
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "ship_a")
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 1), Vector2i(5, 4))
	GameState.ship_controller.set_plotted_movement("ship_a", [
		{"hex": {"q": 5, "r": 5}, "facing": 1},
	])
	var state_b = _make_ship_state(Vector2i(5, 4), 3, 0, "C", "ship_b")  # bow (5,4), stern (6,4)
	var ships: Array[ShipState] = [state_a, state_b]

	var log = resolver.run(ships, env)
	var result = log.get_result("ship_a")

	assert_eq(result.final_hex, Vector2i(5, 5), "A keeps its bow hex")
	assert_eq(result.final_facing, 0, "A swings back to its old facing")
	var rollbacks = _events_of(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1, "One OVERLAP_ROLLBACK event")
	if rollbacks.size() == 1:
		assert_eq(rollbacks[0].detail, "already occupied")
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.STERN_BLOCKED))
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.COLLISION), "No collision")
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL), "No bearing off")
	assert_eq(_events_of(result, MovementTypes.ResolutionEventType.MOVE).size(), 0,
		"The rolled-back turn is not an executed step")
	assert_eq(result.blocked_by, "ship_b")


func test_stern_swing_into_occupied_hex_cleared_by_moving_ahead() -> void:
	# 6.B.2/6.B.3: the same swing followed by a step ahead clears the overlap at once, so it stands.
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "ship_a")
	GameState.ship_controller.set_plotted_movement("ship_a", [
		{"hex": {"q": 5, "r": 5}, "facing": 1},
		{"hex": {"q": 5, "r": 6}, "facing": 1},
	])
	var state_b = _make_ship_state(Vector2i(5, 4), 3, 0, "C", "ship_b")
	var ships: Array[ShipState] = [state_a, state_b]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result = log.get_result("ship_a")

	assert_eq(state_a.hex_position, Vector2i(5, 6))
	assert_eq(state_a.facing, 1)
	var overlaps = _events_of(result, MovementTypes.ResolutionEventType.OVERLAP)
	assert_eq(overlaps.size(), 1)
	if overlaps.size() == 1:
		assert_eq(overlaps[0].detail, "overlaps ship_b")
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK))
	_assert_no_overlap(ships)


func test_stern_swing_into_hex_entered_by_a_bow_yields_to_the_bow() -> void:
	# 6.B.4b: bows beat sterns. A turns its stern into (5, 4) while B's bow sails into it; neither
	# moves again, so the overlap stays and A's turn is rolled back.
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "ship_a")
	GameState.ship_controller.set_plotted_movement("ship_a", [{"hex": {"q": 5, "r": 5}, "facing": 1}])
	var state_b = _make_ship_state(Vector2i(4, 4), 0, 2, "C", "ship_b")  # bow (4,4) heading E
	GameState.ship_controller.set_plotted_movement("ship_b", [{"hex": {"q": 5, "r": 4}, "facing": 0}])
	var ships: Array[ShipState] = [state_a, state_b]

	var log = resolver.run(ships, env)

	assert_eq(log.get_result("ship_b").final_hex, Vector2i(5, 4), "B's bow enters, as if A's stern were not there")
	assert_false(_has_event(log.get_result("ship_b"), MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL))
	var result_a = log.get_result("ship_a")
	assert_eq(result_a.final_facing, 0, "A's turn is rolled back")
	var rollbacks = _events_of(result_a, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1)
	if rollbacks.size() == 1:
		assert_eq(rollbacks[0].detail, "bow precedence")
	assert_false(_has_event(log.get_result("ship_b"), MovementTypes.ResolutionEventType.COLLISION), "No collision")


func test_cancelled_turn_keeps_its_old_stern_hex() -> void:
	# A's turn overlaps B and A has no further MPs, so it is rolled back (6.B.4a) and its stern stays
	# on (4, 5): C's bow sailing into (4, 5) that same segment runs into A instead of sharing the hex.
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "ship_a")  # stern (4,5)
	GameState.ship_controller.set_plotted_movement("ship_a", [{"hex": {"q": 5, "r": 5}, "facing": 1}])
	_make_ship_state(Vector2i(5, 4), 3, 0, "C", "ship_b")  # bow (5,4), stern (6,4): blocks the swing
	var state_c = _make_ship_state(Vector2i(4, 6), 4, 2, "C", "ship_c")  # bow (4,6) heading NW, stern (4,7)
	GameState.ship_controller.set_plotted_movement("ship_c", [{"hex": {"q": 4, "r": 5}, "facing": 4}])
	var ships: Array[ShipState] = [state_a, GameState.ships["ship_b"], state_c]

	var log = resolver.run(ships, env)

	assert_eq(_events_of(log.get_result("ship_a"), MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK).size(), 1)
	assert_eq(log.get_result("ship_a").final_facing, 0)
	assert_eq(log.get_result("ship_c").blocked_by, "ship_a", "A's kept stern is in C's way")
	assert_eq(log.get_result("ship_c").final_hex, Vector2i(4, 6))

func test_failed_ahead_move_keeps_its_old_stern_hex() -> void:
	# A (bow (5,5), stern (4,5)) sails into stopped S and cannot bear off (pivot denied: speed 3,
	# maneuverability A needs 2 hexes ahead first), so it collides and stays. B's bow enters A's old
	# stern (4,5) in the same segment: A never vacated it, so B is blocked by A too.
	var stopped_ship = _make_ship_state(Vector2i(6, 5), 1, 0, "C", "stopped")  # bow (6,5), stern (6,4)
	var ship_a = _make_ship_state(Vector2i(5, 5), 0, 3, "A", "ship_a", 3, "A")
	ship_a.plotted_actions.movement = [{"hex": {"q": 6, "r": 5}, "facing": 0}]
	var ship_b = _make_ship_state(Vector2i(4, 6), 4, 1, "C", "ship_b")  # bow (4,6) heading NW, stern (4,7)
	ship_b.plotted_actions.movement = [{"hex": {"q": 4, "r": 5}, "facing": 4}]
	var ships: Array[ShipState] = [ship_b, ship_a, stopped_ship]  # B is listed first

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	var rammed_stopped := false
	for ev in _events_of(log.get_result("ship_a"), MovementTypes.ResolutionEventType.COLLISION):
		rammed_stopped = rammed_stopped or ev.detail.begins_with("collided with stopped")
	assert_true(rammed_stopped, "A's ahead move fails: it rams the stopped ship")
	assert_eq(ship_a.hex_position, Vector2i(5, 5))
	assert_eq(log.get_result("ship_b").blocked_by, "ship_a", "A's old stern is still A's")
	assert_eq(ship_b.hex_position, Vector2i(4, 6), "B does not enter A's stern hex")
	assert_eq(Occupancy.overlapping_ids(ships), [] as Array[String], "No two ships overlap")

## Run A (bow (5,5) E, plots ahead to (6,5)) and B (bow (6,5) SE, stern (6,4), plots ahead to (6,6))
## with the ships listed in `order`; returns {id: [final_hex, final_facing, speed, moved, events]}.
func _run_crossing(order: Array) -> Dictionary:
	GameState.ships.clear()
	rng.seed = 4242
	resolver = MovementResolver.new(GameState, rng)
	var by_id := {
		"ship_a": _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a"),
		"ship_b": _make_ship_state(Vector2i(6, 5), 1, 1, "C", "ship_b"),
	}
	by_id["ship_a"].plotted_actions.movement = [{"hex": {"q": 6, "r": 5}, "facing": 0}]
	by_id["ship_b"].plotted_actions.movement = [{"hex": {"q": 6, "r": 6}, "facing": 1}]
	var ships: Array[ShipState] = []
	for id in order:
		ships.append(by_id[id])
	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var out := {}
	for id in by_id:
		var events: Array = []
		for ev in log.get_result(id).events:
			events.append(ev.to_dict())
		var s: ShipState = by_id[id]
		out[id] = [s.hex_position, s.facing, s.speed, s.moved_this_turn, events]
	return out


func test_collision_with_a_moving_ship_does_not_depend_on_ship_order() -> void:
	# 6.A.5: B's own step completes before conflicts are checked, so A runs into B's new stern on
	# (6,5) and B still ends on (6,6), whichever ship is listed first.
	var ab := _run_crossing(["ship_a", "ship_b"])
	var ba := _run_crossing(["ship_b", "ship_a"])
	assert_eq(ab, ba, "Same outcome in both ship orders")
	assert_eq(ab["ship_b"][0], Vector2i(6, 6), "B completes its move")
	assert_true(ab["ship_b"][3], "B moved ahead")
	assert_eq(ab["ship_a"][0], Vector2i(5, 5), "A does not enter B's stern hex")

## Head-on pair: A bow (5,5) facing E and B bow (8,5) facing W each sail 2 ahead. On the second step
## each bow enters the other's bow hex, a cycle in which no group is ready first.
func _run_head_on(order: Array) -> Dictionary:
	GameState.ships.clear()
	rng.seed = 4242
	resolver = MovementResolver.new(GameState, rng)
	var by_id := {
		"ship_a": _make_ship_state(Vector2i(5, 5), 0, 3, "C", "ship_a"),
		"ship_b": _make_ship_state(Vector2i(8, 5), 3, 3, "C", "ship_b"),
	}
	_plot_straight(by_id["ship_a"], 2)
	_plot_straight(by_id["ship_b"], 2)
	var ships: Array[ShipState] = []
	for id in order:
		ships.append(by_id[id])
	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var out := {}
	for id in by_id:
		var events: Array = []
		for ev in log.get_result(id).events:
			events.append(ev.to_dict())
		var s: ShipState = by_id[id]
		out[id] = [s.hex_position, s.facing, s.speed, s.moved_this_turn, events]
	return out


func test_head_on_cycle_does_not_depend_on_ship_order() -> void:
	var ab := _run_head_on(["ship_a", "ship_b"])
	var ba := _run_head_on(["ship_b", "ship_a"])
	assert_eq(ab, ba, "Same outcome in both ship orders")
	assert_eq(ab["ship_a"][0], Vector2i(6, 5), "A made its first step only")
	assert_eq(ab["ship_b"][0], Vector2i(7, 5), "B made its first step only")


func test_struck_ship_both_hexes_block() -> void:
	# A struck ship lying E with bow (7, 5), stern (6, 5): A sailing E runs into its stern hex.
	var struck = _make_ship_state(Vector2i(7, 5), 0, 0, "C", "struck")
	struck.status = ShipState.Status.STRUCK
	var mover = _make_ship_state(Vector2i(4, 5), 0, 2, "C", "mover")
	_plot_straight(mover, 2)
	var ships: Array[ShipState] = [struck, mover]

	var result = resolver.run(ships, env).get_result("mover")

	assert_eq(result.blocked_by, "struck", "The struck ship's stern hex is in the way")
	assert_ne(result.final_hex, Vector2i(6, 5), "The mover does not enter the stern hex")
	assert_eq(result.final_hex, Vector2i(5, 5), "It makes its first step only")


func test_destroyed_ship_both_hexes_block_and_never_foul() -> void:
	# A wreck lying E with bow (7, 5), stern (6, 5): the mover runs into its stern hex (spec Q2).
	var wreck = _make_ship_state(Vector2i(7, 5), 0, 0, "C", "wreck")
	wreck.status = ShipState.Status.DESTROYED
	var mover = _make_ship_state(Vector2i(4, 5), 0, 2, "C", "mover")
	_plot_straight(mover, 2)
	var ships: Array[ShipState] = [wreck, mover]

	var log = resolver.run(ships, env)
	var result = log.get_result("mover")

	assert_eq(result.blocked_by, "wreck", "The wreck's stern hex is in the way")
	assert_eq(result.final_hex, Vector2i(5, 5), "It makes its first step only")
	assert_eq(result.fouled_with, "", "A wreck never fouls")
	assert_eq(log.get_result("wreck").final_hex, Vector2i(7, 5), "The wreck does not move")


func test_roll_fouling_with_a_wreck_is_false() -> void:
	var a = _make_ship_state(Vector2i(5, 5), 0, 0, "C", "a")
	var wreck = _make_ship_state(Vector2i(8, 5), 0, 0, "C", "wreck")
	a.sail_state = "PS"
	wreck.status = ShipState.Status.DESTROYED
	assert_false(resolver.roll_fouling(a, wreck))
	assert_false(resolver.roll_fouling(wreck, a))


func test_solo_ship_sails_ahead_and_turns_freely() -> void:
	# A ship never conflicts with its own hexes: alone, its ahead and turn steps all run. (No step can
	# take a bow into the ship's own old stern: that would be sailing astern.)
	var state = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "solo")
	GameState.ship_controller.set_plotted_movement("solo", [
		{"hex": {"q": 6, "r": 5}, "facing": 0},
		{"hex": {"q": 6, "r": 5}, "facing": 1},
		{"hex": {"q": 6, "r": 6}, "facing": 1},
	])
	var ships: Array[ShipState] = [state]

	var result = resolver.run(ships, env).get_result("solo")

	assert_eq(_events_of(result, MovementTypes.ResolutionEventType.MOVE).size(), 3, "All three steps execute")
	assert_eq(result.final_hex, Vector2i(6, 6))
	assert_eq(result.blocked_by, "")
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.STERN_BLOCKED))


func test_follower_enters_leaders_vacated_stern() -> void:
	# Line ahead: the follower's bow sails into the hex the leader's stern leaves (Diagram 13 A).
	var leader = _make_ship_state(Vector2i(7, 5), 0, 2, "C", "leader")  # bow (7,5), stern (6,5)
	var follower = _make_ship_state(Vector2i(5, 5), 0, 2, "C", "follower")  # bow (5,5), stern (4,5)
	_plot_straight(leader, 2)
	_plot_straight(follower, 2)
	var ships: Array[ShipState] = [follower, leader]

	var log = resolver.run(ships, env)

	assert_eq(log.get_result("leader").final_hex, Vector2i(9, 5))
	assert_eq(log.get_result("follower").final_hex, Vector2i(7, 5))
	assert_eq(log.get_result("follower").blocked_by, "")


func test_bows_meeting_head_on_cannot_pass_through() -> void:
	# Bows on adjacent hexes, heading at each other: each bow enters a hex the other ship keeps.
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a")
	var state_b = _make_ship_state(Vector2i(6, 5), 3, 1, "C", "ship_b")
	_plot_straight(state_a, 1)
	_plot_straight(state_b, 1)
	var ships: Array[ShipState] = [state_a, state_b]

	var log = resolver.run(ships, env)

	assert_eq(log.get_result("ship_a").final_hex, Vector2i(5, 5), "A cannot sail through B")
	assert_eq(log.get_result("ship_b").final_hex, Vector2i(6, 5), "B cannot sail through A")


func test_move_event_records_from_facing() -> void:
	var state = _make_ship_state(Vector2i(5, 5), 0, 3)
	GameState.ship_controller.set_plotted_movement(state.ship_id, [
		{"hex": {"q": 5, "r": 5}, "facing": 1},
		{"hex": {"q": 5, "r": 6}, "facing": 1},
	])
	var result = _run_one(state)
	var moves = _events_of(result, MovementTypes.ResolutionEventType.MOVE)
	assert_eq(moves[0].from_facing, 0)
	assert_eq(moves[0].facing, 1)
	assert_eq(moves[1].from_facing, 1)


# ===========================================================================
# Temporary overlap (6.B.2-6.B.4), laid out from Diagram 14. Wind from W (3) so no turning ship
# starts luffing (a turn at MA 0 would need a tacking roll).
# ===========================================================================

func _assert_no_overlap(ships: Array[ShipState]) -> void:
	assert_eq(Occupancy.overlapping_ids(ships), [] as Array[String], "No two ships overlap at the end")


func test_turn_away_from_adjacent_ship_allowed() -> void:
	# Diagram 14 A: ship 1 lies alongside ship 2 and turns away from it, P1 (port turn, one ahead).
	# Turning away swings ship 1's stern into ship 2's stern hex; ship 1 vacates it on the next segment
	# by moving ahead (6.B.3), so the move stands.
	env.wind_direction = 3
	var ship_1 = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "ship_1")  # bow (5,5), stern (4,5)
	var ship_2 = _make_ship_state(Vector2i(5, 6), 0, 0, "C", "ship_2")  # bow (5,6), stern (4,6)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 5), ship_2.stern_hex(), "The swing lands on ship 2's stern")
	GameState.ship_controller.set_plotted_movement("ship_1", [
		{"hex": {"q": 5, "r": 5}, "facing": 5},
		{"hex": {"q": 6, "r": 4}, "facing": 5},
	])
	var ships: Array[ShipState] = [ship_1, ship_2]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result = log.get_result("ship_1")

	assert_false(_has_event(result, MovementTypes.ResolutionEventType.TACKING_ROLL))
	assert_eq(ship_1.hex_position, Vector2i(6, 4), "Ship 1 ends at P1")
	assert_eq(ship_1.facing, 5)
	var overlaps = _events_of(result, MovementTypes.ResolutionEventType.OVERLAP)
	assert_eq(overlaps.size(), 1, "The swing is an overlap")
	if overlaps.size() == 1:
		assert_eq(overlaps[0].detail, "overlaps ship_2")
		assert_eq(overlaps[0].impulse, 0)
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK), "No rollback")
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.STERN_BLOCKED))
	assert_false(_has_event(log.get_result("ship_2"), MovementTypes.ResolutionEventType.COLLISION))
	assert_eq(ship_1.speed, 2, "Turn and one ahead are 2 MPs")
	assert_true(ship_1.moved_this_turn)
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT).size(), 0)
	_assert_no_overlap(ships)


func test_overlap_not_vacated_rolls_back() -> void:
	# Diagram 14 C (6.B.4a, Example 1). Ship 1 turns S: its stern swings into (5, 4), ship 2's bow hex.
	# Ship 2 turns S on that bow and then sails into (4, 5), the hex ship 1's stern left, so its stern
	# stays on (5, 4) and the overlap is still there after the next segment. Ship 1 was the ship turning
	# into an occupied hex: it goes back to its start and stops (it may decelerate from 2 to 0). Ship 2,
	# replaying S1, now runs into ship 1's stern on (4, 5); having just turned it cannot bear off, so it
	# collides.
	# Deviation from the printed example: ship 1 plots S, not S1. With every ship stepping each segment
	# (Leeward has no movement-segment chart), a turning ship that moves ahead always vacates its swung
	# stern hex, so S1 for both ships can never leave an overlap between two ships.
	env.wind_direction = 3
	var ship_1 = _make_ship_state(Vector2i(5, 5), 0, 2, "C", "ship_1")  # bow (5,5), stern (4,5)
	var ship_2 = _make_ship_state(Vector2i(5, 4), 1, 2, "C", "ship_2")  # bow (5,4), stern (5,3)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 1), ship_2.hex_position, "Ship 1 swings into ship 2's bow hex")
	GameState.ship_controller.set_plotted_movement("ship_1", [
		{"hex": {"q": 5, "r": 5}, "facing": 1},
	])
	GameState.ship_controller.set_plotted_movement("ship_2", [
		{"hex": {"q": 5, "r": 4}, "facing": 2},
		{"hex": {"q": 4, "r": 5}, "facing": 2},
	])
	var ships: Array[ShipState] = [ship_1, ship_2]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result_1 = log.get_result("ship_1")
	var result_2 = log.get_result("ship_2")

	assert_false(_has_event(result_1, MovementTypes.ResolutionEventType.TACKING_ROLL))
	assert_false(_has_event(result_2, MovementTypes.ResolutionEventType.TACKING_ROLL))
	assert_eq(ship_1.hex_position, Vector2i(5, 5), "Ship 1 returns to its start")
	assert_eq(ship_1.facing, 0)
	assert_eq(ship_1.speed, 0, "Ship 1 stops")
	assert_false(ship_1.moved_this_turn)
	var rollbacks = _events_of(result_1, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1)
	if rollbacks.size() == 1:
		assert_eq(rollbacks[0].detail, "already occupied")
	assert_eq(_events_of(result_1, MovementTypes.ResolutionEventType.MOVE).size(), 0)
	assert_false(_has_event(result_1, MovementTypes.ResolutionEventType.STERN_BLOCKED))

	assert_true(_has_event(result_2, MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED),
		"Ship 2 has just turned, so it cannot bear off")
	assert_true(_has_event(result_2, MovementTypes.ResolutionEventType.COLLISION))
	assert_eq(result_2.collided_with, "ship_1")
	assert_eq(ship_2.hex_position, Vector2i(5, 4), "Ship 2 made its turn only")
	assert_eq(ship_2.facing, 2)

	var stops := GameState.turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT)
	var ship_1_stop: PhaseEvents.PhaseEvent = null
	for ev in stops:
		if ev.ship_id == "ship_1":
			ship_1_stop = ev
	assert_not_null(ship_1_stop, "Ship 1's amended plot is logged as stopped short")
	if ship_1_stop:
		assert_eq(ship_1_stop.data.get("cause", ""), "overlap")
		assert_eq(ship_1_stop.target_id, "ship_2")
	_assert_no_overlap(ships)


func test_bow_beats_swinging_stern() -> void:
	# Diagram 14 D (6.B.4b, Example 2). Ship 2 plots S and swings its stern into (5, 4), the hex ship 1's
	# bow enters; ship 1 plots 2 and its stern is on (5, 4) after the next segment, while ship 2 has no
	# further MPs. Bows beat swinging sterns: ship 2's plot is amended to 0, with no collision, and ship 1
	# completes its 2.
	env.wind_direction = 3
	var ship_2 = _make_ship_state(Vector2i(5, 5), 0, 2, "C", "ship_2")  # bow (5,5), stern (4,5)
	var ship_1 = _make_ship_state(Vector2i(4, 4), 0, 2, "C", "ship_1")  # bow (4,4), stern (3,4)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 1), Vector2i(5, 4))
	GameState.ship_controller.set_plotted_movement("ship_2", [{"hex": {"q": 5, "r": 5}, "facing": 1}])
	_plot_straight(ship_1, 2)
	var ships: Array[ShipState] = [ship_2, ship_1]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result_2 = log.get_result("ship_2")
	var result_1 = log.get_result("ship_1")

	assert_eq(ship_2.hex_position, Vector2i(5, 5))
	assert_eq(ship_2.facing, 0, "Ship 2's turn is rolled back")
	assert_eq(_events_of(result_2, MovementTypes.ResolutionEventType.MOVE).size(), 0, "Plot amended to 0")
	var rollbacks = _events_of(result_2, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1)
	if rollbacks.size() == 1:
		assert_eq(rollbacks[0].detail, "bow precedence")
	assert_false(_has_event(result_2, MovementTypes.ResolutionEventType.COLLISION), "No collision")
	assert_false(_has_event(result_1, MovementTypes.ResolutionEventType.COLLISION), "No collision")
	assert_false(_has_event(result_1, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL))
	assert_eq(ship_1.hex_position, Vector2i(6, 4), "Ship 1 completes its 2")
	assert_eq(ship_1.speed, 2)
	_assert_no_overlap(ships)


func test_multiple_overlaps_invalidates_whole_move() -> void:
	# Diagram 14 E (Example 3). Ship 1 plots P1: the turn swings its stern into (4, 5), where ship 2's
	# bow arrives, and the step ahead would enter (6, 5), which ship 3's bow reaches first. Ship 1
	# cannot move ahead (it would collide with ship 3), so it is still overlapped with ship 2's bow after
	# the next segment; the bow wins and ship 1's whole move is amended to 0. Ship 1 does not collide
	# with ship 3.
	env.wind_direction = 3
	var ship_1 = _make_ship_state(Vector2i(5, 5), 1, 2, "C", "ship_1")  # bow (5,5), stern (5,4)
	var ship_2 = _make_ship_state(Vector2i(3, 5), 0, 1, "C", "ship_2")  # bow (3,5), stern (2,5)
	var ship_3 = _make_ship_state(Vector2i(6, 4), 1, 1, "C", "ship_3")  # bow (6,4), stern (6,3)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 0), Vector2i(4, 5), "Ship 1's swing hex")
	GameState.ship_controller.set_plotted_movement("ship_1", [
		{"hex": {"q": 5, "r": 5}, "facing": 0},
		{"hex": {"q": 6, "r": 5}, "facing": 0},
	])
	_plot_straight(ship_2, 1)  # bow into (4, 5)
	_plot_straight(ship_3, 1)  # bow into (6, 5), hex "x"
	var ships: Array[ShipState] = [ship_1, ship_2, ship_3]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result_1 = log.get_result("ship_1")

	assert_false(_has_event(result_1, MovementTypes.ResolutionEventType.TACKING_ROLL))
	assert_eq(ship_1.hex_position, Vector2i(5, 5))
	assert_eq(ship_1.facing, 1, "Ship 1's move is amended to 0")
	assert_eq(_events_of(result_1, MovementTypes.ResolutionEventType.MOVE).size(), 0)
	var rollbacks = _events_of(result_1, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1)
	if rollbacks.size() == 1:
		assert_eq(rollbacks[0].detail, "bow precedence")
	for sid in ["ship_1", "ship_2", "ship_3"]:
		assert_false(_has_event(log.get_result(sid), MovementTypes.ResolutionEventType.COLLISION),
			"%s does not collide" % sid)
	assert_eq(result_1.collided_with, "")
	assert_eq(ship_2.hex_position, Vector2i(4, 5))
	assert_eq(ship_3.hex_position, Vector2i(6, 5))
	_assert_no_overlap(ships)


func test_rollback_moves_ahead_to_meet_the_deceleration_minimum() -> void:
	# 6.B.4a: speed 5, maneuverability A (deceleration 2) must use at least 3 MPs. The ship plots
	# 2 ahead then a turn whose stern swings into a stopped ship's hex and is never cleared. Rolled
	# back, it has used 2 MPs, so it moves ahead once more on its old heading instead of turning.
	env.wind_direction = 3
	var ship = _make_ship_state(Vector2i(2, 5), 0, 5, "A", "ship_d")  # bow (2,5), stern (1,5)
	var blocker = _make_ship_state(Vector2i(4, 4), 0, 0, "C", "blocker")  # bow (4,4), stern (3,4)
	assert_eq(HexGrid.stern_of(Vector2i(4, 5), 1), Vector2i(4, 4))
	GameState.ship_controller.set_plotted_movement("ship_d", [
		{"hex": {"q": 3, "r": 5}, "facing": 0},
		{"hex": {"q": 4, "r": 5}, "facing": 0},
		{"hex": {"q": 4, "r": 5}, "facing": 1},
	])
	var ships: Array[ShipState] = [ship, blocker]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result = log.get_result("ship_d")

	var rollbacks = _events_of(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1)
	if rollbacks.size() == 1:
		assert_eq(rollbacks[0].detail, "already occupied")
	assert_eq(ship.hex_position, Vector2i(5, 5), "One more hex ahead instead of the turn")
	assert_eq(ship.facing, 0)
	assert_eq(ship.speed, 3, "The deceleration minimum")
	var moves = _events_of(result, MovementTypes.ResolutionEventType.MOVE)
	assert_eq(moves.size(), 3)
	for mv in moves:
		assert_eq(mv.facing, 0, "Every executed step is ahead")
	_assert_no_overlap(ships)


func _stopped_short_of(ship_id: String) -> PhaseEvents.PhaseEvent:
	for ev in GameState.turn_log.of_type(PhaseEvents.Type.STOPPED_SHORT):
		if ev.ship_id == ship_id:
			return ev
	return null


func test_stern_vs_stern_contest_no_collision() -> void:
	# Diagram 14 B (6.B.4c, 6.C.1b, 6.C.5): both sterns swing into (4, 5) on the same segment and neither
	# ship has further MPs. A contested hex: one ship turns, the other's turn is cancelled. No collision.
	env.wind_direction = 3
	var ship_a = _make_ship_state(Vector2i(5, 5), 1, 2, "C", "ship_a")  # bow (5,5), stern (5,4)
	var ship_b = _make_ship_state(Vector2i(3, 6), 1, 2, "C", "ship_b")  # bow (3,6), stern (3,5)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 0), Vector2i(4, 5))
	assert_eq(HexGrid.stern_of(Vector2i(3, 6), 2), Vector2i(4, 5))
	GameState.ship_controller.set_plotted_movement("ship_a", [{"hex": {"q": 5, "r": 5}, "facing": 0}])
	GameState.ship_controller.set_plotted_movement("ship_b", [{"hex": {"q": 3, "r": 6}, "facing": 2}])
	var ships: Array[ShipState] = [ship_a, ship_b]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	var turned: Array = []
	if ship_a.facing == 0:
		turned.append("ship_a")
	if ship_b.facing == 2:
		turned.append("ship_b")
	assert_eq(turned.size(), 1, "Exactly one ship turns")
	var winner: String = turned[0] if turned.size() == 1 else ""
	var loser: String = "ship_b" if winner == "ship_a" else "ship_a"
	assert_eq((ship_b if loser == "ship_b" else ship_a).facing, 1, "The loser keeps its heading")
	for sid in ["ship_a", "ship_b"]:
		var result = log.get_result(sid)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.COLLISION), "%s: no collision" % sid)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.TACKING_ROLL))
		assert_true(_has_event(result, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL),
			"%s rolls for the hex" % sid)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK))
	var blocked = _events_of(log.get_result(loser), MovementTypes.ResolutionEventType.STERN_BLOCKED)
	assert_eq(blocked.size(), 1, "The loser's turn is cancelled")
	if blocked.size() == 1:
		assert_eq(blocked[0].detail, "lost stern contest to %s" % winner)
	assert_false(_has_event(log.get_result(winner), MovementTypes.ResolutionEventType.STERN_BLOCKED))
	assert_eq(MovementResolver.stop_cause(log.get_result(loser)), {"cause": "stern_contest", "other": winner})
	var stop := _stopped_short_of(loser)
	assert_not_null(stop, "The loser stopped short")
	if stop:
		assert_eq(stop.data.get("cause", ""), "stern_contest")
		assert_eq(stop.target_id, winner)
		# The deciding rolls (adjusted for DRMs) go into the turn log.
		var mine = _events_of(log.get_result(loser), MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL).back()
		var theirs = _events_of(log.get_result(winner), MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL).back()
		assert_eq(stop.data.get("roll", -1), int(mine.roll + mine.threshold))
		assert_eq(stop.data.get("other_roll", -1), int(theirs.roll + theirs.threshold))
		assert_lt(stop.data.get("roll", 0), stop.data.get("other_roll", 0))
	_assert_no_overlap(ships)


func test_stern_contest_loser_moves_ahead_for_its_deceleration_minimum() -> void:
	# 6.B.4c: W (crew A) and L (crew G, +6 for W: W always wins) each sail 2 ahead, then swing their
	# sterns into (4, 4) on segment 2 with no further MPs. L (speed 5, maneuverability A) must use 3 MPs,
	# so instead of turning it moves ahead once more. The rolls stay in the log.
	env.wind_direction = 2
	var ship_l = _make_ship_state(Vector2i(2, 5), 0, 5, "A", "ship_l", 3, "G")  # bow (2,5), stern (1,5)
	var ship_w = _make_ship_state(Vector2i(6, 3), 3, 3, "C", "ship_w", 3, "A")  # bow (6,3), stern (7,3)
	assert_eq(HexGrid.stern_of(Vector2i(4, 5), 1), Vector2i(4, 4))
	assert_eq(HexGrid.stern_of(Vector2i(4, 3), 4), Vector2i(4, 4))
	GameState.ship_controller.set_plotted_movement("ship_l", [
		{"hex": {"q": 3, "r": 5}, "facing": 0},
		{"hex": {"q": 4, "r": 5}, "facing": 0},
		{"hex": {"q": 4, "r": 5}, "facing": 1},
	])
	GameState.ship_controller.set_plotted_movement("ship_w", [
		{"hex": {"q": 5, "r": 3}, "facing": 3},
		{"hex": {"q": 4, "r": 3}, "facing": 3},
		{"hex": {"q": 4, "r": 3}, "facing": 4},
	])
	var ships: Array[ShipState] = [ship_l, ship_w]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result_l = log.get_result("ship_l")
	var result_w = log.get_result("ship_w")

	assert_eq(ship_w.hex_position, Vector2i(4, 3))
	assert_eq(ship_w.facing, 4, "W wins the hex and turns")
	assert_eq(ship_l.hex_position, Vector2i(5, 5), "L moves ahead to its deceleration minimum")
	assert_eq(ship_l.facing, 0)
	assert_eq(ship_l.speed, 3)
	for mv in _events_of(result_l, MovementTypes.ResolutionEventType.MOVE):
		assert_eq(mv.facing, 0, "Every executed step of L is ahead")
	for result in [result_l, result_w]:
		var rolls = _events_of(result, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL)
		assert_eq(rolls.size(), 1, "%s's contest roll is kept in the log" % result.ship_id)
		if rolls.size() == 1:
			assert_eq(rolls[0].impulse, 2)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.COLLISION))
	var blocked = _events_of(result_l, MovementTypes.ResolutionEventType.STERN_BLOCKED)
	assert_eq(blocked.size(), 1)
	if blocked.size() == 1:
		assert_eq(blocked[0].detail, "lost stern contest to ship_w")
		assert_eq(blocked[0].impulse, 2)
	# The contest is told before L's step ahead on the same segment.
	var order: Array = []
	for ev in result_l.events:
		if ev.impulse == 2:
			order.append(ev.event_type)
	assert_eq(order, [MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL,
		MovementTypes.ResolutionEventType.STERN_BLOCKED, MovementTypes.ResolutionEventType.MOVE])
	_assert_no_overlap(ships)


func test_stern_contest_is_deterministic() -> void:
	# The contest of test_stern_contest_loser_moves_ahead_for_its_deceleration_minimum, with W (crew A)
	# fixed to beat L (crew G) by its DRM: the same result whatever the seed draws and whichever ship is
	# listed first.
	var first: Dictionary = {}
	for attempt in range(4):
		GameState.ships.clear()
		rng.seed = 4242
		resolver = MovementResolver.new(GameState, rng)
		env.wind_direction = 2
		var ship_l = _make_ship_state(Vector2i(2, 5), 0, 5, "A", "ship_l", 3, "G")
		var ship_w = _make_ship_state(Vector2i(6, 3), 3, 3, "C", "ship_w", 3, "A")
		GameState.ship_controller.set_plotted_movement("ship_l", [
			{"hex": {"q": 3, "r": 5}, "facing": 0},
			{"hex": {"q": 4, "r": 5}, "facing": 0},
			{"hex": {"q": 4, "r": 5}, "facing": 1},
		])
		GameState.ship_controller.set_plotted_movement("ship_w", [
			{"hex": {"q": 5, "r": 3}, "facing": 3},
			{"hex": {"q": 4, "r": 3}, "facing": 3},
			{"hex": {"q": 4, "r": 3}, "facing": 4},
		])
		var ships: Array[ShipState] = [ship_l, ship_w]
		if attempt % 2 == 1:
			ships.reverse()
		var log = resolver.run(ships, env)
		var out: Dictionary = {}
		for sid in ["ship_l", "ship_w"]:
			out[sid] = log.get_result(sid).to_dict()
		resolver.apply_results(log, ships)
		assert_eq(ship_w.facing, 4, "W wins the hex and turns")
		assert_eq(ship_l.facing, 0, "L's turn is cancelled")
		_assert_no_overlap(ships)
		if attempt == 0:
			first = out
		else:
			assert_eq(out, first, "Same stern contest (attempt %d)" % attempt)


func test_sterns_into_one_hex_with_further_mps_overlap_instead() -> void:
	# 6.C.1b needs both ships to have no further MPs. Ship A turns and then sails ahead, so the two sterns
	# share (4, 5) for one segment (6.B overlap, cleared when A moves on): no contest, both turns stand.
	env.wind_direction = 3
	var ship_a = _make_ship_state(Vector2i(5, 5), 1, 2, "C", "ship_a")  # bow (5,5), stern (5,4)
	var ship_b = _make_ship_state(Vector2i(3, 6), 1, 2, "C", "ship_b")  # bow (3,6), stern (3,5)
	GameState.ship_controller.set_plotted_movement("ship_a", [
		{"hex": {"q": 5, "r": 5}, "facing": 0},
		{"hex": {"q": 6, "r": 5}, "facing": 0},
	])
	GameState.ship_controller.set_plotted_movement("ship_b", [{"hex": {"q": 3, "r": 6}, "facing": 2}])
	var ships: Array[ShipState] = [ship_a, ship_b]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	assert_eq(ship_a.hex_position, Vector2i(6, 5))
	assert_eq(ship_a.facing, 0)
	assert_eq(ship_b.hex_position, Vector2i(3, 6))
	assert_eq(ship_b.facing, 2)
	for sid in ["ship_a", "ship_b"]:
		var result = log.get_result(sid)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL), "%s: no contest" % sid)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.STERN_BLOCKED))
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK))
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.COLLISION))
		assert_true(_has_event(result, MovementTypes.ResolutionEventType.OVERLAP), "%s overlaps for a segment" % sid)
	_assert_no_overlap(ships)


func test_bow_waits_for_both_sterns_sharing_a_hex() -> void:
	# Segment 0: A and B both swing their sterns into (4, 5) (both have further MPs: a 6.B overlap,
	# no contest). Segment 1: B turns again, swinging its stern out; A sails ahead into stopped D and
	# stays, keeping its stern on (4, 5); C's bow sails into (4, 5). C must wait for both ships whose
	# old stern is there, so it finds A's stern in the way. C is listed first.
	env.wind_direction = 3
	var ship_a = _make_ship_state(Vector2i(5, 5), 1, 2, "C", "ship_a")  # bow (5,5), stern (5,4)
	var ship_b = _make_ship_state(Vector2i(3, 6), 1, 2, "C", "ship_b")  # bow (3,6), stern (3,5)
	var ship_c = _make_ship_state(Vector2i(4, 7), 4, 2, "C", "ship_c")  # bow (4,7), stern (4,8)
	var ship_d = _make_ship_state(Vector2i(6, 5), 1, 0, "C", "ship_d")  # bow (6,5), stern (6,4)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 0), Vector2i(4, 5))
	assert_eq(HexGrid.stern_of(Vector2i(3, 6), 2), Vector2i(4, 5))
	GameState.ship_controller.set_plotted_movement("ship_a", [
		{"hex": {"q": 5, "r": 5}, "facing": 0},
		{"hex": {"q": 6, "r": 5}, "facing": 0},
	])
	GameState.ship_controller.set_plotted_movement("ship_b", [
		{"hex": {"q": 3, "r": 6}, "facing": 2},
		{"hex": {"q": 3, "r": 6}, "facing": 1},
	])
	GameState.ship_controller.set_plotted_movement("ship_c", [
		{"hex": {"q": 4, "r": 6}, "facing": 4},
		{"hex": {"q": 4, "r": 5}, "facing": 4},
	])
	var ships: Array[ShipState] = [ship_c, ship_a, ship_b, ship_d]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	assert_eq(ship_a.hex_position, Vector2i(5, 5), "A is stopped by D")
	assert_eq(ship_a.facing, 0, "A keeps its turn: its stern stays on (4, 5)")
	assert_eq(ship_b.facing, 1, "B swung its stern out of (4, 5)")
	assert_eq(ship_c.hex_position, Vector2i(4, 6), "C does not sail into A's stern")
	assert_eq(log.get_result("ship_c").blocked_by, "ship_a")
	_assert_no_overlap(ships)


func test_complete_overlap_one_ship_turns() -> void:
	# Diagram 14 F (6.B.5): two ships lie side by side heading opposite ways, and each swings its stern
	# onto the other's bow. Contested: the winner turns (stub rule: it always chooses itself) and sails on
	# ahead, clearing the loser's bow hex; the loser stops (speed 2, maneuverability C: it may stop).
	env.wind_direction = 2
	var ship_a = _make_ship_state(Vector2i(5, 5), 3, 2, "C", "ship_a")  # bow (5,5), stern (6,5)
	var ship_b = _make_ship_state(Vector2i(5, 6), 0, 2, "C", "ship_b")  # bow (5,6), stern (4,6)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 4), Vector2i(5, 6))
	assert_eq(HexGrid.stern_of(Vector2i(5, 6), 1), Vector2i(5, 5))
	GameState.ship_controller.set_plotted_movement("ship_a", [
		{"hex": {"q": 5, "r": 5}, "facing": 4},
		{"hex": {"q": 5, "r": 4}, "facing": 4},
	])
	GameState.ship_controller.set_plotted_movement("ship_b", [
		{"hex": {"q": 5, "r": 6}, "facing": 1},
		{"hex": {"q": 5, "r": 7}, "facing": 1},
	])
	var ships: Array[ShipState] = [ship_a, ship_b]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	var a_turned: bool = ship_a.facing == 4
	var b_turned: bool = ship_b.facing == 1
	assert_ne(a_turned, b_turned, "Exactly one ship turns")
	var winner: ShipState = ship_a if a_turned else ship_b
	var loser: ShipState = ship_b if a_turned else ship_a
	assert_eq(winner.hex_position, Vector2i(5, 4) if a_turned else Vector2i(5, 7), "The winner sails on")
	assert_eq(loser.hex_position, Vector2i(5, 6) if a_turned else Vector2i(5, 5), "The loser stops")
	assert_eq(loser.speed, 0)
	for s in [ship_a, ship_b]:
		var result = log.get_result(s.ship_id)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.TACKING_ROLL))
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.COLLISION))
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK))
		assert_true(_has_event(result, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL))
	var blocked = _events_of(log.get_result(loser.ship_id), MovementTypes.ResolutionEventType.STERN_BLOCKED)
	assert_eq(blocked.size(), 1)
	if blocked.size() == 1:
		assert_eq(blocked[0].detail, "lost stern contest to %s" % winner.ship_id)
	assert_eq(_events_of(log.get_result(loser.ship_id), MovementTypes.ResolutionEventType.MOVE).size(), 0)
	assert_false(_has_event(log.get_result(winner.ship_id), MovementTypes.ResolutionEventType.STERN_BLOCKED))
	_assert_no_overlap(ships)


func test_complete_overlap_winner_without_further_mps_cannot_turn_either() -> void:
	# 6.B.5 with turn-only plots: the winner's stern would stay on the loser's bow hex (6.B.4a), so its
	# turn is rolled back too. Neither ship turns, and nothing collides.
	env.wind_direction = 2
	var ship_a = _make_ship_state(Vector2i(5, 5), 3, 2, "C", "ship_a")
	var ship_b = _make_ship_state(Vector2i(5, 6), 0, 2, "C", "ship_b")
	GameState.ship_controller.set_plotted_movement("ship_a", [{"hex": {"q": 5, "r": 5}, "facing": 4}])
	GameState.ship_controller.set_plotted_movement("ship_b", [{"hex": {"q": 5, "r": 6}, "facing": 1}])
	var ships: Array[ShipState] = [ship_a, ship_b]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	assert_eq(ship_a.facing, 3)
	assert_eq(ship_b.facing, 0)
	for s in [ship_a, ship_b]:
		var result = log.get_result(s.ship_id)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.COLLISION))
		# The mechanism: the winner's turn is rolled back for the overlap it leaves, and in the replay the
		# loser's turn (no longer contested) is rolled back for the same reason. Neither executes a step.
		assert_eq(_events_of(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK).size(), 1,
			"%s's turn is rolled back" % s.ship_id)
		assert_eq(_events_of(result, MovementTypes.ResolutionEventType.MOVE).size(), 0,
			"%s executes no step" % s.ship_id)
	_assert_no_overlap(ships)


func test_contest_rolls_stay_in_the_log_when_the_winner_is_rolled_back() -> void:
	# Turn-only complete overlap (6.B.5): the ships contest, the winner's stern stays on the loser's bow
	# and is rolled back, and in the replay both turns are rolled back. The contest rolls stay in the log.
	env.wind_direction = 2
	var ship_a = _make_ship_state(Vector2i(5, 5), 3, 2, "C", "ship_a")
	var ship_b = _make_ship_state(Vector2i(5, 6), 0, 2, "C", "ship_b")
	GameState.ship_controller.set_plotted_movement("ship_a", [{"hex": {"q": 5, "r": 5}, "facing": 4}])
	GameState.ship_controller.set_plotted_movement("ship_b", [{"hex": {"q": 5, "r": 6}, "facing": 1}])
	var ships: Array[ShipState] = [ship_a, ship_b]

	var log = resolver.run(ships, env)

	var winners := 0
	for sid in ["ship_a", "ship_b"]:
		var result = log.get_result(sid)
		var rolls = _events_of(result, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL)
		assert_gt(rolls.size(), 0, "%s's contest roll is in the log" % sid)
		for ev in rolls:
			assert_eq(ev.impulse, 0)
		if not rolls.is_empty() and rolls.back().success:
			winners += 1
		assert_eq(_events_of(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK).size(), 1)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.STERN_BLOCKED),
			"%s: the final pass has no lost contest" % sid)
		# Told in order: the contest, then the stern swinging in, then back.
		var order: Array = []
		for ev in result.events:
			if order.is_empty() or order.back() != ev.event_type:
				order.append(ev.event_type)
		assert_eq(order, [MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL,
			MovementTypes.ResolutionEventType.OVERLAP, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK])
	assert_eq(winners, 1, "One ship won the contest")


## Chained rollbacks (6.B.4). X (bow (5,5) E) plots one ahead into (6,5), then a turn that swings its
## stern onto stopped V's bow (5,6). W (bow (6,4) NW, stern (6,5)) plots a turn on segment 0 that swings
## its stern into (5,5): X's bow hex at the start, and X's stern after its step ahead, so W overlaps X
## until X's turn swings that stern away on segment 1.
## Pass 1: X's overlap with V is never cleared, so X's turn is rolled back.
## Pass 2: without that turn X's stern stays on (5,5), so W's overlap is not cleared either and W's turn
## is rolled back.
## Pass 3: W keeps its stern on (6,5), which stops X's first step. X never reaches its turn, so the
## rollback found for it in pass 1 is stale and must not be logged.
func _run_cascade(seed_value: int) -> Dictionary:
	GameState.ships.clear()
	env.wind_direction = 3
	rng.seed = seed_value
	resolver = MovementResolver.new(GameState, rng)
	var x = _make_ship_state(Vector2i(5, 5), 0, 2, "C", "ship_x")  # bow (5,5), stern (4,5)
	var w = _make_ship_state(Vector2i(6, 4), 4, 2, "C", "ship_w")  # bow (6,4), stern (6,5)
	var v = _make_ship_state(Vector2i(5, 6), 3, 0, "C", "ship_v")  # bow (5,6), stern (6,6)
	assert_eq(HexGrid.stern_of(Vector2i(6, 4), 5), Vector2i(5, 5), "W swings onto X's bow hex")
	assert_eq(HexGrid.stern_of(Vector2i(6, 5), 5), Vector2i(5, 6), "X's later swing lands on V")
	GameState.ship_controller.set_plotted_movement("ship_x", [
		{"hex": {"q": 6, "r": 5}, "facing": 0},
		{"hex": {"q": 6, "r": 5}, "facing": 5},
	])
	GameState.ship_controller.set_plotted_movement("ship_w", [{"hex": {"q": 6, "r": 4}, "facing": 5}])
	var ships: Array[ShipState] = [x, w, v]
	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	return {"log": log, "ships": ships, "x": x, "w": w}


func test_cascaded_rollback_drops_the_stale_one() -> void:
	var out := _run_cascade(12345)
	var log = out.log
	var result_x = log.get_result("ship_x")
	var result_w = log.get_result("ship_w")

	var w_rollbacks = _events_of(result_w, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(w_rollbacks.size(), 1, "W's turn is rolled back")
	if w_rollbacks.size() == 1:
		assert_eq(w_rollbacks[0].detail, "already occupied")
	assert_eq(out.w.facing, 4)
	assert_false(_has_event(result_x, MovementTypes.ResolutionEventType.OVERLAP),
		"X never reached its turn: no swing is logged")
	assert_false(_has_event(result_x, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK))
	assert_eq(result_x.blocked_by, "ship_w", "W's kept stern stops X's first step")
	assert_eq(MovementResolver.stop_cause(result_x).get("other", ""), "ship_w")
	assert_ne(MovementResolver.stop_cause(result_x).get("cause", ""), "overlap")
	assert_eq(out.x.hex_position, Vector2i(5, 5))
	assert_eq(out.x.facing, 0)
	_assert_no_overlap(out.ships)


func test_rollback_resolution_is_deterministic() -> void:
	var first: Dictionary = _run_cascade(777).log.to_dict()
	var second: Dictionary = _run_cascade(777).log.to_dict()
	assert_eq(second, first, "Same seed, same log, with chained rollbacks")


# ===========================================================================
# Rings: each ship's bow enters the next one's old stern (a cycle, see _resolve_impulse)
# ===========================================================================


## Bear-off decisions that hold course on segment 0 (6.E.1): for tests about what blocked ships do
## next, not about bearing off.
func _hold_course(ids: Array) -> Dictionary:
	var decisions := {}
	for sid in ids:
		decisions[sid] = {"choice": MovementTypes.BEAR_OFF_COLLIDE, "segment": 0}
	return decisions

## A (bow (5,5) E), B (bow (5,6) SW) and C (bow (4,6) NW) each sail one ahead into the next one's
## old stern: A into B's (6,5), B into C's (4,7), C into A's (4,5). Returns the three ships.
func _make_ring(crew_b: String = "B") -> Array[ShipState]:
	env.wind_direction = 3
	var a = _make_ship_state(Vector2i(5, 5), 0, 1, "C", "ship_a")  # stern (4,5)
	var b = _make_ship_state(Vector2i(5, 6), 2, 1, "C", "ship_b", 3, crew_b)  # stern (6,5)
	var c = _make_ship_state(Vector2i(4, 6), 4, 1, "C", "ship_c")  # stern (4,7)
	assert_eq(b.stern_hex(), Vector2i(6, 5))
	assert_eq(c.stern_hex(), Vector2i(4, 7))
	_plot_straight(a, 1)
	_plot_straight(b, 1)
	_plot_straight(c, 1)
	return [a, b, c] as Array[ShipState]


func test_ring_of_ships_entering_each_others_old_sterns_all_move() -> void:
	var ships := _make_ring()
	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	assert_eq(ships[0].hex_position, Vector2i(6, 5), "A enters B's old stern")
	assert_eq(ships[1].hex_position, Vector2i(4, 7), "B enters C's old stern")
	assert_eq(ships[2].hex_position, Vector2i(4, 5), "C enters A's old stern")
	_assert_no_overlap(ships)


func test_ring_with_a_member_blocked_from_outside_never_overlaps() -> void:
	# D (crew A) contests B's target (4,7) with B (crew G): D always wins (+6), so B stays and keeps its
	# stern on (6,5), under A's bow, which sailed in assuming B would leave. The cycle is broken and the
	# pass run again: A now meets B's stern (6,5), C meets A's kept stern (4,5), and D meets C's kept
	# stern (4,7). Nobody in the ring moves and final footprints never overlap.
	var ships := _make_ring("G")
	var d = _make_ship_state(Vector2i(3, 7), 0, 1, "C", "ship_d", 3, "A")  # bow (3,7), stern (2,7)
	_plot_straight(d, 1)  # bow into (4,7)
	ships.append(d)

	var log = resolver.run(ships, env, _hold_course(["ship_a", "ship_b", "ship_c", "ship_d"]))
	resolver.apply_results(log, ships)

	var expected := {"ship_a": [Vector2i(5, 5), "ship_b"], "ship_c": [Vector2i(4, 6), "ship_a"],
		"ship_d": [Vector2i(3, 7), "ship_c"]}
	for sid in expected:
		var result = log.get_result(sid)
		assert_eq(result.final_hex, expected[sid][0], "%s stays" % sid)
		assert_eq(result.blocked_by, expected[sid][1], "%s meets the stern %s keeps" % [sid, expected[sid][1]])
		assert_eq(_events_of(result, MovementTypes.ResolutionEventType.MOVE).size(), 0,
			"%s's step is not executed" % sid)
	assert_eq(ships[1].hex_position, Vector2i(5, 6), "B stays")
	assert_eq(Occupancy.overlapping_ids(ships), [] as Array[String], "No two ships overlap")


func test_only_the_ring_that_went_wrong_is_broken() -> void:
	# Two rings in one segment: the blocked ring of test_ring_with_a_member_blocked_from_outside_never_overlaps
	# and a free copy of the ring 10 hexes east (E, F, G as A, B, C). Only the blocked ring's cycle is
	# broken in the replay; the free ring still sails round, with no collision.
	var ships := _make_ring("G")
	var d = _make_ship_state(Vector2i(3, 7), 0, 1, "C", "ship_d", 3, "A")
	_plot_straight(d, 1)
	ships.append(d)
	var e = _make_ship_state(Vector2i(15, 5), 0, 1, "C", "ship_e")  # stern (14,5)
	var f = _make_ship_state(Vector2i(15, 6), 2, 1, "C", "ship_f")  # stern (16,5)
	var g = _make_ship_state(Vector2i(14, 6), 4, 1, "C", "ship_g")  # stern (14,7)
	for s in [e, f, g]:
		_plot_straight(s, 1)
		ships.append(s)

	var log = resolver.run(ships, env, _hold_course(["ship_a", "ship_b", "ship_c", "ship_d"]))
	resolver.apply_results(log, ships)

	assert_eq(ships[0].hex_position, Vector2i(5, 5), "The blocked ring stays (A)")
	assert_eq(log.get_result("ship_a").blocked_by, "ship_b")
	assert_eq(e.hex_position, Vector2i(16, 5), "E enters F's old stern")
	assert_eq(f.hex_position, Vector2i(14, 7), "F enters G's old stern")
	assert_eq(g.hex_position, Vector2i(14, 5), "G enters E's old stern")
	for sid in ["ship_e", "ship_f", "ship_g"]:
		var result = log.get_result(sid)
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.COLLISION), "%s: no collision" % sid)
		assert_eq(result.blocked_by, "", "%s is not blocked" % sid)
	assert_eq(Occupancy.overlapping_ids(ships), [] as Array[String], "No two ships overlap")


func test_collision_holds_the_old_stern_of_a_ship_whose_group_has_not_run() -> void:
	# A5: a ship stopped by a collision before its own group runs keeps its old stern at once, so no bow
	# (not even one let in by the cycle fallback) can enter it.
	var a = _make_ship_state(Vector2i(4, 5), 0, 1, "C", "ship_a")
	var b = _make_ship_state(Vector2i(5, 5), 3, 1, "C", "ship_b")  # bow (5,5) W, stern (6,5)
	var p := MovementResolver.ResolutionPass.new()
	p.ship_map = {"ship_a": a, "ship_b": b}
	p.results = {"ship_a": MovementTypes.ShipResolutionResult.new("ship_a"),
		"ship_b": MovementTypes.ShipResolutionResult.new("ship_b")}
	p.current_hexes = {"ship_a": a.hex_position, "ship_b": b.hex_position}
	p.current_facings = {"ship_a": 0, "ship_b": 3}
	p.stopped = {"ship_a": false, "ship_b": false}
	var seg := MovementResolver.Segment.new()
	seg.intended_moves = {"ship_a": {"hex": Vector2i(5, 5), "facing": 0}, "ship_b": {"hex": Vector2i(4, 5), "facing": 3}}
	seg.start_bows = p.current_hexes.duplicate()
	seg.start_facings = p.current_facings.duplicate()

	resolver._apply_collision(p, seg, "ship_a", "ship_b")

	assert_eq(seg.held.get(Vector2i(6, 5), ""), "ship_b", "B's old stern is held by B")
	assert_true(seg.resolved.has("ship_b"), "B's group no longer holds anyone up")


# ===========================================================================
# A turn cancelled after steps ahead
# ===========================================================================

func _assert_stopped_after_two_ahead(ship: ShipState, cause: String, other: String) -> void:
	assert_eq(ship.speed, 2, "Speed is the steps executed")
	assert_true(ship.moved_this_turn, "The ship moved ahead before its turn was cancelled")
	assert_eq(ship.facing, 0, "The turn is cancelled")
	var stop := _stopped_short_of(ship.ship_id)
	assert_not_null(stop, "STOPPED_SHORT is logged")
	if stop:
		assert_eq(stop.data.get("moved", -1), 2)
		assert_eq(stop.data.get("planned", -1), 3)
		assert_eq(stop.data.get("cause", ""), cause)
		assert_eq(stop.target_id, other)


func test_turn_rolled_back_after_steps_ahead_stops_short() -> void:
	# Two ahead, then a turn whose stern swings onto a stopped ship and is never cleared (6.B.4a). Speed 3,
	# maneuverability C (deceleration 3) may stop, so the plot is amended to the two steps ahead.
	env.wind_direction = 3
	var ship = _make_ship_state(Vector2i(2, 5), 0, 3, "C", "ship_d")  # bow (2,5), stern (1,5)
	var blocker = _make_ship_state(Vector2i(4, 4), 0, 0, "C", "blocker")  # bow (4,4), stern (3,4)
	GameState.ship_controller.set_plotted_movement("ship_d", [
		{"hex": {"q": 3, "r": 5}, "facing": 0},
		{"hex": {"q": 4, "r": 5}, "facing": 0},
		{"hex": {"q": 4, "r": 5}, "facing": 1},
	])
	var ships: Array[ShipState] = [ship, blocker]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	assert_eq(ship.hex_position, Vector2i(4, 5))
	assert_eq(_events_of(log.get_result("ship_d"), MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK).size(), 1)
	_assert_stopped_after_two_ahead(ship, "overlap", "blocker")
	_assert_no_overlap(ships)


func test_stern_contest_lost_after_steps_ahead_stops_short() -> void:
	# L (crew G) and W (crew A, always wins) sail 2 ahead and swing their sterns into (4, 4) with no further
	# MPs (6.C.5). L (speed 3, maneuverability C) may stop, so its turn is just cancelled.
	env.wind_direction = 2
	var ship_l = _make_ship_state(Vector2i(2, 5), 0, 3, "C", "ship_l", 3, "G")
	var ship_w = _make_ship_state(Vector2i(6, 3), 3, 3, "C", "ship_w", 3, "A")
	GameState.ship_controller.set_plotted_movement("ship_l", [
		{"hex": {"q": 3, "r": 5}, "facing": 0},
		{"hex": {"q": 4, "r": 5}, "facing": 0},
		{"hex": {"q": 4, "r": 5}, "facing": 1},
	])
	GameState.ship_controller.set_plotted_movement("ship_w", [
		{"hex": {"q": 5, "r": 3}, "facing": 3},
		{"hex": {"q": 4, "r": 3}, "facing": 3},
		{"hex": {"q": 4, "r": 3}, "facing": 4},
	])
	var ships: Array[ShipState] = [ship_l, ship_w]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	assert_eq(ship_l.hex_position, Vector2i(4, 5))
	assert_eq(ship_w.facing, 4, "W wins and turns")
	_assert_stopped_after_two_ahead(ship_l, "stern_contest", "ship_w")
	_assert_no_overlap(ships)


func test_uncleared_sterns_together_overlap_rolls_both_back() -> void:
	# A and B swing their sterns into (4, 5) on segment 0. A has a step ahead to follow, so it is no
	# contest (6.C.1b) but a 6.B overlap; A's step ahead runs into stopped S, so neither stern leaves
	# (4, 5) on segment 1. Both overlaps fail together and both turns are rolled back (6.B.4).
	env.wind_direction = 3
	var ship_a = _make_ship_state(Vector2i(5, 5), 1, 2, "C", "ship_a")  # bow (5,5), stern (5,4)
	var ship_b = _make_ship_state(Vector2i(3, 6), 1, 2, "C", "ship_b")  # bow (3,6), stern (3,5)
	var ship_s = _make_ship_state(Vector2i(6, 5), 1, 0, "C", "ship_s")  # bow (6,5), stern (6,4)
	GameState.ship_controller.set_plotted_movement("ship_a", [
		{"hex": {"q": 5, "r": 5}, "facing": 0},
		{"hex": {"q": 6, "r": 5}, "facing": 0},
	])
	GameState.ship_controller.set_plotted_movement("ship_b", [{"hex": {"q": 3, "r": 6}, "facing": 2}])
	var ships: Array[ShipState] = [ship_a, ship_b, ship_s]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)

	assert_eq(ship_a.facing, 1, "A's turn is rolled back")
	assert_eq(ship_b.facing, 1, "B's turn is rolled back")
	for sid in ["ship_a", "ship_b"]:
		var result = log.get_result(sid)
		var rollbacks = _events_of(result, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
		assert_eq(rollbacks.size(), 1, "%s: one rollback" % sid)
		if rollbacks.size() == 1:
			assert_eq(rollbacks[0].detail, "sterns together")
		assert_false(_has_event(result, MovementTypes.ResolutionEventType.CONTESTED_HEX_ROLL), "%s: no contest" % sid)
		assert_eq(_events_of(result, MovementTypes.ResolutionEventType.MOVE).size(), 0)
	assert_eq(log.get_result("ship_a").blocked_by, "ship_b")
	assert_eq(log.get_result("ship_b").blocked_by, "ship_a")
	_assert_no_overlap(ships)


func test_overlap_kept_because_the_other_ship_stopped_rolls_back() -> void:
	# A turns S on its last MP: its stern swings into (5, 4), B's bow hex at the start ("already
	# occupied"), as B sails ahead and leaves its stern there. B would clear the overlap with its second
	# step, but it runs into stopped S and stays, so the overlap is still there after segment 1 and A's
	# turn is rolled back. B, replayed, still sails one ahead and is stopped by S.
	env.wind_direction = 3
	var ship_a = _make_ship_state(Vector2i(5, 5), 0, 2, "C", "ship_a")  # bow (5,5), stern (4,5)
	var ship_b = _make_ship_state(Vector2i(5, 4), 0, 2, "C", "ship_b")  # bow (5,4), stern (4,4)
	var ship_s = _make_ship_state(Vector2i(7, 4), 1, 0, "C", "ship_s")  # bow (7,4), stern (7,3)
	assert_eq(HexGrid.stern_of(Vector2i(5, 5), 1), Vector2i(5, 4))
	GameState.ship_controller.set_plotted_movement("ship_a", [{"hex": {"q": 5, "r": 5}, "facing": 1}])
	_plot_straight(ship_b, 2)
	var ships: Array[ShipState] = [ship_a, ship_b, ship_s]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result_a = log.get_result("ship_a")
	var result_b = log.get_result("ship_b")

	assert_eq(ship_a.facing, 0, "A's turn is rolled back")
	var rollbacks = _events_of(result_a, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1)
	if rollbacks.size() == 1:
		assert_eq(rollbacks[0].detail, "already occupied")
		assert_eq(rollbacks[0].impulse, 1)
	assert_eq(result_a.blocked_by, "ship_b")
	assert_eq(ship_b.hex_position, Vector2i(6, 4), "B made its first step only")
	assert_eq(result_b.blocked_by, "ship_s")
	assert_true(_has_event(result_b, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
		or _has_event(result_b, MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED), "B meets S")
	_assert_no_overlap(ships)


# ===========================================================================
# Rules edge cases after a rollback (6.B.4, 6.C, 6.D)
# ===========================================================================

func test_contest_drm_counts_the_amended_plot() -> void:
	# A plotted 3 and B 1, but a rollback amended them to 1 and 3: the +1 for more MPs goes to B.
	var state_a = _make_ship_state(Vector2i(5, 5), 0, 3, "C", "ship_a")
	_plot_straight(state_a, 3)
	var state_b = _make_ship_state(Vector2i(6, 7), 3, 3, "C", "ship_b")
	_plot_straight(state_b, 1)
	var ship_map: Dictionary = {"ship_a": state_a, "ship_b": state_b}
	var steps := {"ship_a": [{}], "ship_b": [{}, {}, {}]}
	var ids := ["ship_a", "ship_b"]
	assert_eq(resolver._calculate_contest_drm_relative("ship_a", ids, ship_map), 1, "From the plots: A has more MPs")
	assert_eq(resolver._calculate_contest_drm_relative("ship_a", ids, ship_map, steps), 0)
	assert_eq(resolver._calculate_contest_drm_relative("ship_b", ids, ship_map, steps), 1, "Amended: B has more MPs")


func test_bearing_off_drm_counts_the_amended_plot() -> void:
	# A plotted 5 ahead (+1), but its plot was amended to 2: the bear-off roll takes no DRM.
	var loser = _make_ship_state(Vector2i(4, 5), 0, 3, "C", "ship_a")
	_plot_straight(loser, 5)
	var blocker = _make_ship_state(Vector2i(6, 5), 0, 0, "C", "ship_b")  # stern (5,5), dead ahead of A
	var p := MovementResolver.ResolutionPass.new()
	p.ship_map = {"ship_a": loser, "ship_b": blocker}
	p.results = {"ship_a": MovementTypes.ShipResolutionResult.new("ship_a"),
		"ship_b": MovementTypes.ShipResolutionResult.new("ship_b")}
	p.current_hexes = {"ship_a": loser.hex_position, "ship_b": blocker.hex_position}
	p.current_facings = {"ship_a": 0, "ship_b": 0}
	p.stopped = {"ship_a": false, "ship_b": true}
	p.forward_since_turn = {"ship_a": 10}  # bearing off is legal
	p.steps_by_ship = {"ship_a": loser.plotted_actions.movement.slice(0, 2), "ship_b": []}

	resolver._resolve_collision_or_bearoff(p, MovementResolver.Segment.new(), "ship_a", "ship_b")

	var rolls = _events_of(p.results["ship_a"], MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
	assert_eq(rolls.size(), 1)
	if rolls.size() == 1:
		assert_string_contains(rolls[0].detail, "drm=+0")


func test_rollback_names_every_ship_still_overlapped() -> void:
	# T lies on (4, 5). A and B both swing their sterns into it (A has a step ahead to follow, so no
	# contest); A's step ahead runs into stopped S. After segment 1 A still overlaps both B and T, and its
	# rollback names both.
	env.wind_direction = 3
	var ship_a = _make_ship_state(Vector2i(5, 5), 1, 2, "C", "ship_a")  # bow (5,5), stern (5,4)
	var ship_b = _make_ship_state(Vector2i(3, 6), 1, 2, "C", "ship_b")  # bow (3,6), stern (3,5)
	var ship_s = _make_ship_state(Vector2i(6, 5), 1, 0, "C", "ship_s")  # bow (6,5), stern (6,4)
	var ship_t = _make_ship_state(Vector2i(4, 5), 1, 0, "C", "ship_t")  # bow (4,5), stern (4,4)
	GameState.ship_controller.set_plotted_movement("ship_a", [
		{"hex": {"q": 5, "r": 5}, "facing": 0},
		{"hex": {"q": 6, "r": 5}, "facing": 0},
	])
	GameState.ship_controller.set_plotted_movement("ship_b", [{"hex": {"q": 3, "r": 6}, "facing": 2}])
	var ships: Array[ShipState] = [ship_a, ship_b, ship_s, ship_t]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result_a = log.get_result("ship_a")

	assert_eq(ship_a.facing, 1, "A's turn is rolled back")
	var overlaps = _events_of(result_a, MovementTypes.ResolutionEventType.OVERLAP)
	assert_eq(overlaps.size(), 1)
	if overlaps.size() == 1:
		assert_string_contains(overlaps[0].detail, "ship_b")
		assert_string_contains(overlaps[0].detail, "ship_t")
	var rollbacks = _events_of(result_a, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK)
	assert_eq(rollbacks.size(), 1)
	if rollbacks.size() == 1:
		assert_eq(rollbacks[0].detail, "already occupied")
	_assert_no_overlap(ships)


func test_deceleration_minimum_reads_the_facing_at_the_cut_point() -> void:
	# As the validator does: the MA at the facing where the plot is cut, not at the start-of-turn facing.
	env.wind_direction = 3
	var ship = _make_ship_state(Vector2i(5, 5), 0, 5, "A", "ship_d")  # speed 5, deceleration 2
	assert_eq(resolver._deceleration_minimum(ship), 3, "Start-of-turn facing E: MA > 0")
	assert_eq(resolver._deceleration_minimum(ship, 0), 3)
	assert_eq(resolver._deceleration_minimum(ship, 3), 0, "Heading into the wind (WF=L), MA is 0: it may stop")


func test_rolled_back_ship_run_into_on_the_overlap_segment_keeps_its_rollback() -> void:
	# A's turn on segment 0 overlaps stopped B and is rolled back to nothing (speed 2, C: it may stop).
	# In the final pass C's bow runs into A's kept stern on segment 0, so A is stopped on the overlap
	# segment itself. A still reached that segment in its pre-turn pose: the rollback is logged and is
	# why A stopped short, not C running into it.
	env.wind_direction = 3
	var ship_a = _make_ship_state(Vector2i(5, 5), 0, 2, "C", "ship_a")  # bow (5,5), stern (4,5)
	GameState.ship_controller.set_plotted_movement("ship_a", [{"hex": {"q": 5, "r": 5}, "facing": 1}])
	var ship_b = _make_ship_state(Vector2i(5, 4), 3, 0, "C", "ship_b")  # bow (5,4), stern (6,4)
	var ship_c = _make_ship_state(Vector2i(4, 6), 4, 1, "C", "ship_c")  # bow (4,6) NW, stern (4,7)
	_plot_straight(ship_c, 1)  # into (4,5); speed 1, no step ahead yet: it cannot bear off
	var ships: Array[ShipState] = [ship_a, ship_b, ship_c]

	var log = resolver.run(ships, env)
	resolver.apply_results(log, ships)
	var result_a = log.get_result("ship_a")

	assert_eq(result_a.stopped_at_impulse, 0, "A is stopped on the overlap segment")
	assert_eq(log.get_result("ship_c").collided_with, "ship_a", "C runs into A's kept stern")
	assert_eq(_events_of(result_a, MovementTypes.ResolutionEventType.OVERLAP).size(), 1, "The swing is logged")
	assert_eq(_events_of(result_a, MovementTypes.ResolutionEventType.OVERLAP_ROLLBACK).size(), 1)
	assert_eq(MovementResolver.stop_cause(result_a), {"cause": "overlap", "other": "ship_b"})
	var stop := _stopped_short_of("ship_a")
	assert_not_null(stop)
	if stop:
		assert_eq(stop.data.get("cause", ""), "overlap")
	_assert_no_overlap(ships)


func test_three_sterns_contest_keeps_its_result_in_the_replay() -> void:
	# Three sterns swing into (5, 5) with no further MPs: a contest (6.C.5). S1 (speed 5, maneuverability
	# A) must still use 3 MPs, so when it loses, its plot is amended to steps ahead and the turn is
	# replayed; the contest between the two ships left keeps its first result instead of being rolled
	# again. Over many seeds: exactly one ship turns, and it is the one every loser lost to.
	env.wind_direction = 3
	for seed_value in range(1, 41):
		GameState.ships.clear()
		GameState.turn_log = PhaseEvents.PhaseLog.new()
		rng.seed = seed_value
		resolver = MovementResolver.new(GameState, rng)
		var s1 = _make_ship_state(Vector2i(6, 5), 5, 5, "A", "s1")  # stern (5,6)
		var s2 = _make_ship_state(Vector2i(4, 6), 1, 2, "C", "s2")  # stern (4,5)
		var s3 = _make_ship_state(Vector2i(6, 4), 0, 2, "C", "s3")  # stern (5,4)
		GameState.ship_controller.set_plotted_movement("s1", [{"hex": {"q": 6, "r": 5}, "facing": 0}])
		GameState.ship_controller.set_plotted_movement("s2", [{"hex": {"q": 4, "r": 6}, "facing": 2}])
		GameState.ship_controller.set_plotted_movement("s3", [{"hex": {"q": 6, "r": 4}, "facing": 5}])
		var turned_to := {"s1": 0, "s2": 2, "s3": 5}
		var ships: Array[ShipState] = [s1, s2, s3]

		var log = resolver.run(ships, env)
		resolver.apply_results(log, ships)

		var turned: Array = []
		var lost_to: Dictionary = {}
		for s in ships:
			if s.facing == turned_to[s.ship_id]:
				turned.append(s.ship_id)
			for ev in _events_of(log.get_result(s.ship_id), MovementTypes.ResolutionEventType.STERN_BLOCKED):
				lost_to[ev.detail.trim_prefix("lost stern contest to ")] = true
			var events: Array = log.get_result(s.ship_id).events
			for ev in events:
				assert_eq(events.count(ev), 1, "seed %d: %s's events are logged once" % [seed_value, s.ship_id])
			assert_lte(_events_of(log.get_result(s.ship_id), MovementTypes.ResolutionEventType.STERN_BLOCKED).size(), 1)
		assert_eq(turned.size(), 1, "seed %d: exactly one ship turns" % seed_value)
		if turned.size() == 1:
			assert_eq(lost_to.keys(), turned, "seed %d: every loser lost to the ship that turned" % seed_value)
		_assert_no_overlap(ships)


# ===========================================================================
# Bearing off as the owner's decision (6.D)
# ===========================================================================

## Mover (crew A, maneuver D, speed 7: deceleration 4, minimum 3 MPs) plots three hexes east from
## bow (5,5); a stopped ship holds (7,5), so the mover meets it on segment 1 after one hex.
func _bear_off_setup() -> Array[ShipState]:
	var blocker = _make_ship_state(Vector2i(7, 5), 1, 0, "C", "blocker")  # bow (7,5), stern (7,4)
	var mover = _make_ship_state(Vector2i(5, 5), 0, 7, "D", "mover", 3, "A")
	_plot_straight(mover, 3)
	return [mover, blocker] as Array[ShipState]


func _decide(choice: String, segment: int = 1) -> Dictionary:
	return {"mover": {"choice": choice, "segment": segment}}


func test_prompted_ship_pauses_the_resolution_at_its_potential_collision() -> void:
	var ships := _bear_off_setup()
	var log = resolver.run(ships, env, {}, ["mover"])
	assert_false(log.is_complete(), "6.D.3: the owner decides")
	var situation: MovementTypes.BearOffSituation = log.pending_bear_off
	assert_eq(situation.ship_id, "mover")
	assert_eq(situation.blocker_id, "blocker")
	assert_eq(situation.segment, 1)
	assert_eq(situation.bow, Vector2i(6, 5))
	assert_eq(situation.eligible, ["port", "starboard"] as Array[String], "6.D.2: a first turn is legal either way")
	assert_eq(situation.number, DataManager.get_bearing_off_number("A", "D"))
	assert_eq(situation.drm, 0, "3 MPs plotted: no DRM")
	assert_eq(situation.choices(), ["port", "starboard", "collide"] as Array[String])
	var moves: Array = _events_of(log.get_result("mover"), MovementTypes.ResolutionEventType.MOVE)
	assert_eq(moves.size(), 1, "The step before the potential collision is in the log")


func test_the_log_before_the_decision_repeats_exactly() -> void:
	var ships := _bear_off_setup()
	rng.seed = 7
	var paused = resolver.run(ships, env, {}, ["mover"])
	rng.seed = 7
	var decided = resolver.run(ships, env, _decide("starboard"), ["mover"])
	assert_true(decided.is_complete())
	for sid in ["mover", "blocker"]:
		var before_a: Array = []
		var before_b: Array = []
		for ev in paused.get_result(sid).events:
			if ev.impulse < 1:
				before_a.append(ev.to_dict())
		for ev in decided.get_result(sid).events:
			if ev.impulse < 1:
				before_b.append(ev.to_dict())
		assert_eq(before_b, before_a, "%s: playback can resume at segment 1" % sid)


func test_successful_bear_off_turns_then_meets_the_deceleration_minimum() -> void:
	# 6.D.4: the ship turns the chosen way, then moves ahead only as far as its deceleration requires
	# (speed 7 - 4 = 3 MPs: one ahead, the turn, one more ahead on the new heading).
	var ships := _bear_off_setup()
	var found := false
	for seed_value in range(1, 40):
		rng.seed = seed_value
		var log = resolver.run(ships, env, _decide("starboard"), ["mover"])
		var result = log.get_result("mover")
		var rolls: Array = _events_of(result, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
		if rolls.is_empty() or not rolls[0].success:
			continue
		found = true
		assert_eq(rolls[0].impulse, 1)
		assert_eq(result.final_facing, 1, "Turned to starboard (SE)")
		assert_eq(result.final_hex, Vector2i(6, 6), "Then one hex ahead to meet the deceleration minimum")
		assert_eq(_events_of(result, MovementTypes.ResolutionEventType.MOVE).size(), 3)
		assert_eq(result.collided_with, "", "No collision")
		assert_eq(result.events.find(rolls[0]) < result.events.find(
			_events_of(result, MovementTypes.ResolutionEventType.MOVE)[1]), true, "The roll comes before the turn")
		break
	assert_true(found, "Some seed bears off (A/D needs <= 7)")


func test_failed_bear_off_collides() -> void:
	var ships := _bear_off_setup()
	var found := false
	for seed_value in range(1, 80):
		rng.seed = seed_value
		var log = resolver.run(ships, env, _decide("port"), ["mover"])
		var result = log.get_result("mover")
		var rolls: Array = _events_of(result, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
		if rolls.is_empty() or rolls[0].success:
			continue
		found = true
		assert_eq(result.collided_with, "blocker", "6.E.1: a failed bear-off is a collision")
		assert_eq(result.final_facing, 0)
		break
	assert_true(found, "Some seed fails (d10 8 or 9)")


func test_holding_course_collides_without_a_roll() -> void:
	var ships := _bear_off_setup()
	var log = resolver.run(ships, env, _decide(MovementTypes.BEAR_OFF_COLLIDE), ["mover"])
	var result = log.get_result("mover")
	assert_true(_has_event(result, MovementTypes.ResolutionEventType.BEARING_OFF_DECLINED))
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL), "No roll")
	assert_eq(result.collided_with, "blocker")


func test_a_decision_for_another_segment_is_asked_again() -> void:
	var ships := _bear_off_setup()
	var log = resolver.run(ships, env, _decide("starboard", 0), ["mover"])
	assert_false(log.is_complete(), "The answer was for segment 0; the collision is on segment 1")


func test_a_ship_bears_off_only_once_per_turn() -> void:
	# 6.D.5: after bearing off to starboard, the mover's deceleration step ahead (to (6,6)) meets a
	# second stopped ship: that potential collision is automatic.
	var ships := _bear_off_setup()
	var second = _make_ship_state(Vector2i(6, 6), 0, 0, "C", "second")  # bow (6,6), stern (5,6)
	ships.append(second)
	var found := false
	for seed_value in range(1, 40):
		rng.seed = seed_value
		var log = resolver.run(ships, env, _decide("starboard"), ["mover"])
		var result = log.get_result("mover")
		var rolls: Array = _events_of(result, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL)
		if rolls.is_empty() or not rolls[0].success:
			continue
		found = true
		assert_eq(rolls.size(), 1, "No second attempt")
		assert_eq(result.collided_with, "second", "The second potential collision is automatic")
		var denied: Array = _events_of(result, MovementTypes.ResolutionEventType.BEARING_OFF_PIVOT_DENIED)
		assert_eq(denied.size(), 1)
		assert_eq(denied[0].detail, "already bore off this turn")
		break
	assert_true(found)


func test_unprompted_ships_never_ram() -> void:
	# The AI decides for ships not prompted: it always tries to bear off when it can.
	var ships := _bear_off_setup()
	var log = resolver.run(ships, env)
	assert_true(log.is_complete())
	var result = log.get_result("mover")
	assert_false(_has_event(result, MovementTypes.ResolutionEventType.BEARING_OFF_DECLINED))
	assert_eq(_events_of(result, MovementTypes.ResolutionEventType.BEARING_OFF_ROLL).size(), 1)


func test_ai_bears_off_away_from_the_blocker() -> void:
	var situation := MovementTypes.BearOffSituation.new()
	situation.bow = Vector2i(6, 5)
	situation.facing = 0
	situation.eligible = ["port", "starboard"] as Array[String]
	# Blocker on (7,5) and (7,4): to port (NE) the next hex (7,4) is the blocker; to starboard (SE)
	# the next hex (6,6) is clear.
	assert_eq(StubAI.bear_off_choice(situation, [Vector2i(7, 5), Vector2i(7, 4)]), "starboard")
	situation.eligible = ["port"] as Array[String]
	assert_eq(StubAI.bear_off_choice(situation, [Vector2i(7, 5), Vector2i(7, 4)]), "port", "Never rams")
	situation.eligible = [] as Array[String]
	assert_eq(StubAI.bear_off_choice(situation, [Vector2i(7, 5)]), "collide", "No legal turn")


func test_bear_off_log_text() -> void:
	var ok := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BEAR_OFF, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION, "a",
		{"choice": "starboard", "success": true, "roll": 2, "needed": 5, "drm": 1}, "b")
	assert_eq(ok.to_text({}), "a bears off to starboard to avoid b (rolled 2 +1, needed ≤ 5)")
	var held := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.BEAR_OFF, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION, "a", {"choice": "collide"}, "b")
	assert_eq(held.to_text({}), "a holds course into b")


func test_the_situation_carries_the_other_ships_remaining_plots() -> void:
	# 6.D.3a: the player may see the other ships' plots; only steps from the paused segment on.
	var ships := _bear_off_setup()
	var other = _make_ship_state(Vector2i(5, 8), 0, 2, "C", "other")  # far away, sails two hexes east
	_plot_straight(other, 2)
	ships.append(other)
	var log = resolver.run(ships, env, {}, ["mover"])
	var plots: Dictionary = log.pending_bear_off.other_plots
	assert_eq(plots.get("other"), [Vector2i(7, 8)] as Array[Vector2i], "Its step on segment 1 only")
	assert_false(plots.has("blocker"), "A ship with no plot shows nothing")
	assert_false(plots.has("mover"), "Not the deciding ship itself")
