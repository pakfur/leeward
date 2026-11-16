extends GutTest
const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
## Grappling and ungrappling (Close Action 1997, 8.C; boarding spec B3, §6 tests 1-10).
## Grappling table (p.109): d10 <= 2 succeeds; DRMs ± SK, fouled -1, marines not available +1,
## wind speed 4 +1, target did not move -1. Unfouling table for ungrappling: <= 2/3/4 by attempt;
## ± SK, marines not available +1; (ungrappling only) -1 per CQ better than the enemy, friendly -2,
## wind speed 4 -1. SK: A -3, B -2, C -1, D 0, E +1, F +2, G +3.

const PHASE := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT

var grappling: GrapplingController
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState


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
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	GameState.environment = env
	grappling = GrapplingController.new(GameState)


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


## Facing 1 (SE): the stern is the NW neighbour (q, r-1). Ships on (5,5) and (6,5) are alongside.
func _make_ship(id: String, player: int, hex: Vector2i, quality: String = "D", mps: int = 2) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
	})
	state.hex_position = hex
	state.facing = 1
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = quality
	state.mp_used_this_turn = mps
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


func _events(type: PhaseEvents.Type) -> Array:
	return GameState.turn_log.of_type(type)


# --- who may grapple (8.C.1, 8.C.3) ---

func test_three_mps_cannot_grapple() -> void:
	# 8.C.1 example 1: a ship that used 3 MPs cannot grapple, whatever the target did; and it cannot
	# be grappled either (both must have used <= 2).
	_make_ship("a", 0, Vector2i(5, 5), "D", 3)
	_make_ship("b", 1, Vector2i(6, 5), "D", 0)
	assert_eq(grappling.grapple_options("a"), [] as Array[String])
	assert_eq(grappling.grapple_options("b"), [] as Array[String], "the target used 3 MPs")
	assert_string_contains(grappling.grapple_error("a", "b"), "3 MPs")


func test_only_adjacent_ships_may_be_grappled() -> void:
	# 8.C.1: each adjacent ship; orientation does not matter.
	_make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	_make_ship("c", 1, Vector2i(9, 5))
	assert_eq(grappling.grapple_options("a"), ["b"] as Array[String])


func test_cq_f_struck_or_burning_ship_cannot_grapple_but_can_be_grappled() -> void:
	# 8.C.3: burning ships, ships at CQ F or G, and struck ships cannot grapple.
	var a := _make_ship("a", 0, Vector2i(5, 5), "F")
	var b := _make_ship("b", 1, Vector2i(6, 5))
	assert_eq(grappling.grapple_options("a"), [] as Array[String], "CQ F")
	assert_eq(grappling.grapple_options("b"), ["a"] as Array[String], "a CQ F ship can be grappled")
	a.crew_quality = "D"
	a.status = ShipState.Status.STRUCK
	assert_eq(grappling.grapple_options("a"), [] as Array[String], "struck")
	assert_eq(grappling.grapple_options("b"), ["a"] as Array[String], "a struck ship can be grappled")
	a.status = ShipState.Status.ACTIVE
	a.fire_list = [{"seq": 1, "created_turn": 1, "started_turn": 1, "cause": "crit"}] as Array[Dictionary]
	assert_eq(grappling.grapple_options("a"), [] as Array[String], "burning")
	assert_eq(grappling.grapple_options("b"), ["a"] as Array[String], "a burning ship can be grappled")


# --- the grappling roll (8.C.2, Grappling table) ---

func test_cq_b_rolls_4_and_grapples() -> void:
	# §6 test 2: both used 2 MPs, adjacent, CQ B, d10 4: 4 - 2 = 2 <= 2, grappled.
	_make_ship("a", 0, Vector2i(5, 5), "B")
	_make_ship("b", 1, Vector2i(6, 5))
	assert_eq(int(grappling.grapple_chance("a", "b")["needed"]), 4, "needs d10 <= 4")
	_dice.queue([4])
	grappling.resolve_grapples([["a", "b"]], PHASE)
	assert_eq(GameState.get_ship("a").grappled_with, ["b"] as Array[String])
	assert_eq(GameState.get_ship("b").grappled_with, ["a"] as Array[String], "symmetric")
	var ev: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.GRAPPLE)[0]
	assert_eq(ev.data["total"], 2)
	assert_true(ev.data["success"])


func test_cq_b_rolls_5_and_misses() -> void:
	_make_ship("a", 0, Vector2i(5, 5), "B")
	_make_ship("b", 1, Vector2i(6, 5))
	_dice.queue([5])
	grappling.resolve_grapples([["a", "b"]], PHASE)
	assert_false(GameState.get_ship("a").is_grappled(), "5 - 2 = 3 > 2")
	assert_false(_events(PhaseEvents.Type.GRAPPLE)[0].data["success"])


func test_fouled_target_still_ws4_drms() -> void:
	# §6 test 3: fouled -1 (the chart wins over 8.C.1's text), target did not move -1, WS 4 +1,
	# CQ B -2; d10 5: 5 - 2 - 1 - 1 + 1 = 2 <= 2, grappled.
	_make_ship("a", 0, Vector2i(5, 5), "B")
	_make_ship("b", 1, Vector2i(6, 5), "D", 0)
	GameState.ship_controller.set_fouled_with("a", "b")
	GameState.ship_controller.set_fouled_with("b", "a")
	GameState.environment.wind_speed = 4
	var chance := grappling.grapple_chance("a", "b")
	assert_eq(int(chance["modifier"]), -3)
	_dice.queue([5])
	grappling.resolve_grapples([["a", "b"]], PHASE)
	assert_true(GameState.get_ship("a").is_grappled_to("b"))
	assert_eq(_events(PhaseEvents.Type.GRAPPLE)[0].data["total"], 2)


func test_marines_not_available_is_plus_one() -> void:
	# Grappling DRM: marines not available +1 (the marines plotted to another task).
	var a := _make_ship("a", 0, Vector2i(5, 5), "D")
	_make_ship("b", 1, Vector2i(6, 5))
	CrewFixtures.give_sail_change(a, "FS", [ShipState.MARINES])
	assert_eq(int(grappling.grapple_chance("a", "b")["modifier"]), 1)


func test_one_grapple_per_pair_second_roll_not_made() -> void:
	# §6 test 5 (8.C.2): both order a grapple on each other; the first (lower ship_id) succeeds,
	# so the second roll is not made.
	_make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	_dice.queue([0, 0])
	grappling.resolve_grapples([["b", "a"], ["a", "b"]], PHASE)
	assert_eq(_dice.remaining(), 1, "only a rolled")
	assert_eq(_events(PhaseEvents.Type.GRAPPLE).size(), 1)
	assert_eq(_events(PhaseEvents.Type.GRAPPLE)[0].ship_id, "a")


func test_failed_first_attempt_lets_the_other_ship_roll() -> void:
	_make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	_dice.queue([9, 1])
	grappling.resolve_grapples([["b", "a"], ["a", "b"]], PHASE)
	assert_true(GameState.get_ship("a").is_grappled_to("b"))
	assert_eq(_events(PhaseEvents.Type.GRAPPLE).size(), 2)


func test_illegal_order_is_dropped_without_a_roll() -> void:
	_make_ship("a", 0, Vector2i(5, 5), "D", 3)
	_make_ship("b", 1, Vector2i(6, 5))
	grappling.resolve_grapples([["a", "b"]], PHASE)
	assert_eq(_events(PhaseEvents.Type.GRAPPLE).size(), 0)
	assert_false(GameState.get_ship("a").is_grappled())


func test_grapple_at_wf_l_puts_ship_in_irons() -> void:
	# 5.D.5: a ship at WF=L that is grappled is in irons (speed 0). Wind from SE (1), facing 1 = WF L.
	GameState.environment.wind_direction = 1
	var a := _make_ship("a", 0, Vector2i(5, 5))
	var b := _make_ship("b", 1, Vector2i(6, 5))
	b.facing = 4  # NW: WF R, not in irons
	b.hex_position = Vector2i(6, 4)  # bow (6,4) beside a's stern (5,4)
	a.speed = 2
	b.speed = 2
	_dice.queue([0])
	grappling.resolve_grapples([["b", "a"]], PHASE)
	assert_true(a.is_grappled_to("b"))
	assert_eq(a.speed, 0, "WF=L: in irons")
	assert_eq(b.speed, 2, "WF=R: unaffected")
	assert_eq(_events(PhaseEvents.Type.GRAPPLE)[0].data["in_irons"], ["a"] as Array[String])


# --- ungrappling (8.C.4-6) ---

func test_ungrapple_from_struck_enemy() -> void:
	# §6 test 6 (8.C.4, 8.C.6): CQ B from a struck enemy (CQ G): 5 levels better, -5; 1st attempt,
	# d10 7: 7 - 2 - 5 = 0 <= 2, free.
	var a := _make_ship("a", 0, Vector2i(5, 5), "B")
	var b := _make_ship("b", 1, Vector2i(6, 5), "C")
	GameState.ship_controller.add_grapple("a", "b")
	b.status = ShipState.Status.STRUCK
	assert_eq(int(grappling.ungrapple_chance("a", "b")["modifier"]), -7)
	_dice.queue([7])
	grappling.resolve_ungrapples([["a", "b"]], PHASE)
	assert_false(a.is_grappled())
	assert_false(b.is_grappled())
	var ev: PhaseEvents.PhaseEvent = _events(PhaseEvents.Type.UNGRAPPLE)[0]
	assert_eq(ev.data["total"], 0)
	assert_eq(ev.data["needed"], 2)
	assert_true(ev.data["success"])


func test_ungrapple_from_friendly_ship() -> void:
	# §6 test 7: friendly ships -2; CQ D, d10 4: 4 - 2 = 2 <= 2, free.
	var a := _make_ship("a", 0, Vector2i(5, 5), "D")
	_make_ship("b", 0, Vector2i(6, 5), "D")
	GameState.ship_controller.add_grapple("a", "b")
	_dice.queue([4])
	grappling.resolve_ungrapples([["a", "b"]], PHASE)
	assert_false(a.is_grappled())


func test_ungrapple_ws4_and_marines_busy() -> void:
	# Ungrappling: WS 4 -1 (ungrappling only), marines not available +1 (all uses; 8.C.5).
	var a := _make_ship("a", 0, Vector2i(5, 5), "D")
	_make_ship("b", 1, Vector2i(6, 5), "D")
	GameState.ship_controller.add_grapple("a", "b")
	GameState.environment.wind_speed = 4
	assert_eq(int(grappling.ungrapple_chance("a", "b")["modifier"]), -1)
	CrewFixtures.give_sail_change(a, "FS", [ShipState.MARINES])
	assert_eq(int(grappling.ungrapple_chance("a", "b")["modifier"]), 0)


func test_worse_crew_takes_no_cq_drm() -> void:
	# "Each CQ > enemy: -1": only a better crew gains; a worse one takes nothing.
	_make_ship("a", 0, Vector2i(5, 5), "E")
	_make_ship("b", 1, Vector2i(6, 5), "B")
	GameState.ship_controller.add_grapple("a", "b")
	assert_eq(int(grappling.ungrapple_chance("a", "b")["modifier"]), 1, "SK +1 only")


func test_ungrapple_attempts_grow_easier() -> void:
	# Unfouling table: <= 2, then <= 3, then <= 4, by the roller's attempt against that partner.
	var a := _make_ship("a", 0, Vector2i(5, 5), "D")
	_make_ship("b", 1, Vector2i(6, 5), "D")
	GameState.ship_controller.add_grapple("a", "b")
	_dice.queue([3])
	grappling.resolve_ungrapples([["a", "b"]], PHASE)
	assert_true(a.is_grappled(), "3 > 2")
	assert_eq(int(a.ungrapple_attempts["b"]), 1)
	_dice.queue([3])
	grappling.resolve_ungrapples([["a", "b"]], PHASE)
	assert_false(a.is_grappled(), "second attempt: 3 <= 3")
	assert_true(a.ungrapple_attempts.is_empty(), "attempts dropped with the grapple")


func test_ungrapple_dice_order_lower_id_first_partner_only_if_it_failed() -> void:
	# Dice order (§3.3): the lower id rolls first; the partner only if that failed.
	var a := _make_ship("a", 0, Vector2i(5, 5), "D")
	_make_ship("b", 1, Vector2i(6, 5), "D")
	GameState.ship_controller.add_grapple("a", "b")
	_dice.queue([1, 1])
	grappling.resolve_ungrapples([["b", "a"], ["a", "b"]], PHASE)
	assert_false(a.is_grappled())
	assert_eq(_dice.remaining(), 1, "b did not roll")
	assert_eq(_events(PhaseEvents.Type.UNGRAPPLE)[0].ship_id, "a")
	GameState.ship_controller.add_grapple("a", "b")
	_dice._queue.clear()  # b's unused die from the first case
	_dice.queue([9, 0])
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	grappling.resolve_ungrapples([["b", "a"], ["a", "b"]], PHASE)
	assert_false(a.is_grappled(), "a failed, b cut free")
	assert_eq(_events(PhaseEvents.Type.UNGRAPPLE).size(), 2)


func test_struck_ship_cannot_ungrapple() -> void:
	var a := _make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	GameState.ship_controller.add_grapple("a", "b")
	a.status = ShipState.Status.STRUCK
	assert_eq(grappling.ungrapple_options("a"), [] as Array[String])
	assert_eq(grappling.ungrapple_options("b"), ["a"] as Array[String])


func test_boarding_lock_and_engaged_marines_are_stubbed_until_b4() -> void:
	# 8.C.5 / 8.D.4: no boarding action exists before boarding spec B4.
	var a := _make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	assert_false(grappling.locked_in_boarding("a", "b"))
	assert_false(grappling.marines_in_boarding(a))


# --- consequences ---

func test_grappled_ship_refuses_movement_plot() -> void:
	# §6 test 10 (8.C.7): a grappled ship plots movement: refused, SHIP_GRAPPLED.
	_make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	GameState.ship_controller.add_grapple("a", "b")
	var response = GameState.movement_plotting_controller.handle_start_plotting(0, "a", "req-1")
	assert_true(response is MovementTypes.PlottingErrorResponse)
	assert_eq(response.error_code, "SHIP_GRAPPLED")


func test_grappled_ship_ignores_a_stored_plot() -> void:
	# 8.C.7: a plot left over is ignored by the resolver (defence behind the plotting check).
	var a := _make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	GameState.ship_controller.add_grapple("a", "b")
	a.plotted_actions.movement = [{"hex": {"q": 5, "r": 6}, "facing": 1}]
	assert_eq(GameState.movement_resolver._get_plotted_steps(a), [])


func test_destroyed_ship_releases_its_grapples() -> void:
	var a := _make_ship("a", 0, Vector2i(5, 5))
	var b := _make_ship("b", 1, Vector2i(6, 5))
	GameState.ship_controller.add_grapple("a", "b")
	GameState.damage_controller.destroy("a", "test", PHASE)
	assert_false(a.is_grappled())
	assert_false(b.is_grappled())


func test_linked_ids_and_serialization() -> void:
	var a := _make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	_make_ship("c", 1, Vector2i(4, 6))
	GameState.ship_controller.add_grapple("a", "c")
	GameState.ship_controller.add_grapple("a", "b")
	GameState.ship_controller.set_fouled_with("a", "b")
	GameState.ship_controller.set_ungrapple_attempts("a", "c", 2)
	assert_eq(a.linked_ids(), ["b", "c"] as Array[String], "fouled and grappled to b counts once")
	var copy := ShipState.deserialize(a.serialize())
	assert_eq(copy.grappled_with, ["b", "c"] as Array[String])
	assert_eq(int(copy.ungrapple_attempts["c"]), 2)


func test_marine_fire_alongside_drm_reads_grapples() -> void:
	# Marine Fire DRM: firing ship grappled or fouled to the target -1 (7.G.4).
	var a := _make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	assert_false(MarineFireResolver.linked(a, "b"))
	GameState.ship_controller.add_grapple("a", "b")
	assert_true(MarineFireResolver.linked(a, "b"))


func test_client_does_not_mutate() -> void:
	_make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(6, 5))
	grappling.is_server = false
	grappling.resolve_grapples([["a", "b"]], PHASE)
	assert_push_error("Cannot resolve grappling on client")
	grappling.resolve_ungrapples([["a", "b"]], PHASE)
	assert_push_error("Cannot resolve ungrappling on client")
	assert_false(GameState.get_ship("a").is_grappled())
	GameState.ship_controller.is_server = false
	assert_false(GameState.ship_controller.add_grapple("a", "b"))
	assert_push_error("Cannot add a grapple on client")
	GameState.ship_controller.is_server = true


# --- StubAI (boarding spec §3.6) ---

func test_ai_grapples_struck_or_weaker_enemies_only() -> void:
	var ai := _make_ship("ai", 1, Vector2i(5, 5), "B")
	var weak := _make_ship("p_weak", 0, Vector2i(6, 5), "E")
	var friend := _make_ship("ai_friend", 1, Vector2i(4, 6), "B")
	# B: 12 sailors x 7 + 2 marines x 9 = 102; E: 12 x 4 + 2 x 6 = 60 <= 2/3 of 102.
	assert_eq(StubAI.crew_strength(ai), 102)
	assert_eq(GameState.stub_ai.grapple_orders([1] as Array[int]), [["ai", "p_weak"]])
	weak.crew_quality = "B"
	assert_eq(GameState.stub_ai.grapple_orders([1] as Array[int]), [], "an equal crew is left alone")
	weak.status = ShipState.Status.STRUCK
	assert_eq(GameState.stub_ai.grapple_orders([1] as Array[int]), [["ai", "p_weak"]], "a struck enemy")
	assert_false(friend.is_grappled(), "never a friendly ship")


func test_ai_cuts_grapples_it_does_not_want() -> void:
	_make_ship("ai", 1, Vector2i(5, 5), "B")
	var enemy := _make_ship("p", 0, Vector2i(6, 5), "B")
	_make_ship("ai_friend", 1, Vector2i(4, 6), "B")
	GameState.ship_controller.add_grapple("ai", "p")
	GameState.ship_controller.add_grapple("ai", "ai_friend")
	# Boarding spec §3.6 (B4): it keeps a grapple to an enemy it would board: M + S1 (2 x 9 + 3 x 7 =
	# 39) against the enemy's marines (18) is 2:1 +2, class 3 defender -1 => +1.
	assert_eq(GameState.stub_ai.ungrapple_orders([1] as Array[int]), [["ai", "ai_friend"], ["ai_friend", "ai"]])
	enemy.crew_quality = "A"
	enemy.marine_count = 6
	# Now 39 v 6 x 10 = 60: 1:2 -2, -1 => -3, and the enemy is no weaker: it cuts.
	assert_eq(GameState.stub_ai.ungrapple_orders([1] as Array[int]),
		[["ai", "ai_friend"], ["ai", "p"], ["ai_friend", "ai"]])
	enemy.status = ShipState.Status.STRUCK
	assert_eq(GameState.stub_ai.ungrapple_orders([1] as Array[int]), [["ai", "ai_friend"], ["ai_friend", "ai"]],
		"never from a struck enemy")


# --- 5.D.5, the collision half ---

func _moved_result(sid: String, from: Vector2i, to: Vector2i, facing: int, collided_with: String) -> MovementTypes.ResolutionLog:
	var log := MovementTypes.ResolutionLog.new(1)
	var result := MovementTypes.ShipResolutionResult.new(sid)
	var ev := MovementTypes.ResolutionEvent.new(sid, 0, MovementTypes.ResolutionEventType.MOVE)
	ev.from_hex = from
	ev.to_hex = to
	ev.facing = facing
	result.events.append(ev)
	result.final_hex = to
	result.final_facing = facing
	result.collided_with = collided_with
	log.add_result(result)
	return log


func test_collision_at_wf_l_puts_ship_in_irons() -> void:
	# 5.D.5: a ship at WF=L in a collision is in irons: stopped (speed 0) although it moved ahead.
	GameState.environment.wind_direction = 1
	var a := _make_ship("a", 0, Vector2i(5, 5))
	_make_ship("b", 1, Vector2i(9, 9))
	var ships: Array[ShipState] = [a]
	GameState.movement_resolver.apply_results(_moved_result("a", Vector2i(5, 4), Vector2i(5, 5), 1, "b"), ships)
	assert_eq(a.speed, 0, "WF=L and collided: in irons")
	GameState.environment.wind_direction = 0  # facing 1 is now close-hauled
	GameState.movement_resolver.apply_results(_moved_result("a", Vector2i(5, 4), Vector2i(5, 5), 1, "b"), ships)
	assert_eq(a.speed, 1, "not at WF=L: speed is the MPs used")
