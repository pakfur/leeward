extends GutTest
## Tests for CriticalHitController: the gunfire critical-hit roll (7.D.11), Rigging and Hull
## Checks (7.D.7, 7.D.8a), extra boxes and chaining (7.D.12), the chart's flags and notes
## (diamond, [D], dismasted), stern/bow rakes (7.E.5b, 7.E.6) and crit MCs (9.B.1e).
## Expected values come from the Rigging/Hull Critical Hits charts (p.112-113) and spec §5.

const PORT := 0
const STARBOARD := 1
const PHASE := 4  # COMBAT_RESOLUTION

var crits: CriticalHitController
var a: ShipState
var b: ShipState
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_crits: CriticalHitController
var _old_turn := 0
var _old_env: EnvironmentState


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_crits = GameState.critical_hit_controller
	_old_turn = GameState.current_turn
	_old_env = GameState.environment
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.current_turn = 3
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	crits = CriticalHitController.new(GameState)
	GameState.critical_hit_controller = crits
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	a = _make_ship("a_ship", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_ship", 1, Vector2i(-1, 1), 3, -2)


func after_each() -> void:
	assert_eq(_dice.remaining(), 0, "every scripted roll was used")
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.critical_hit_controller = _old_crits
	GameState.current_turn = _old_turn
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, player: int, hex: Vector2i, facing: int, ch_mod: int = 0,
		ship_class: int = 3) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id,
		"player_id": player,
		"ship_name": id,
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": ship_class,
		"maneuverability": "C",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
		"ch_modifier": ch_mod,
	})
	state.hex_position = hex
	state.facing = facing
	state.sail_state = "MS"
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	state.marine_count = 2
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


## A shot at b_ship from a_ship. engaged_side defaults to starboard.
func _ctx(aim: String = "high", ammo: String = "round", rake: String = "",
		side: int = STARBOARD, d6: int = 6, fgn: int = 40, dismasted: bool = false) -> Dictionary:
	return {
		"source_id": "a_ship", "target_id": "b_ship", "aim": aim, "ammo": ammo, "rake": rake,
		"engaged_side": side, "dismasted_at_start": dismasted, "fgn": fgn, "d6": d6,
	}


## Gunfire crit on b_ship with the CH d6 a hit (1 - 2 = -1 <= 5) and the 2d6 = sum of `two`.
func _crit(two: Array, ctx: Dictionary) -> bool:
	_dice.queue([1])
	_dice.queue(two)
	crits.hold()
	var hit := crits.check_gunfire_crit(ctx, PHASE)
	crits.release(PHASE)
	return hit


func _events(type: PhaseEvents.Type) -> Array[PhaseEvents.PhaseEvent]:
	return GameState.turn_log.of_type(type)


func _crit_events() -> Array[PhaseEvents.PhaseEvent]:
	return _events(PhaseEvents.Type.CRITICAL_HIT)


func _ids(events: Array) -> Array:
	return events.map(func(e): return e.data["result_id"])


# --- 7.D.11 the critical-hit roll ---

func test_row1_natural_six_ch_mod_minus_two_is_a_crit() -> void:
	# Majestic G-T 8: FGN 40 (CH# <= 5), CH d6 6, CH mod -2: 6 - 2 = 4 <= 5.
	_dice.queue([6, 2, 2])  # CH d6, then 2d6 = 4 (rigging: braces cut)
	assert_true(crits.check_gunfire_crit(_ctx(), PHASE))
	var roll := _events(PhaseEvents.Type.CRITICAL_ROLL)
	assert_eq(roll.size(), 1)
	assert_eq(roll[0].data, {"d6": 6, "ch_mod": -2, "ch_number": 5, "hit": true})
	assert_eq(roll[0].ship_id, "b_ship")
	assert_eq(roll[0].target_id, "a_ship")
	assert_eq(_ids(_crit_events()), ["braces_cut"])
	assert_eq(_crit_events()[0].data["source"], "gunfire")
	assert_true(b.has_critical("braces_cut"))


func test_row2_ch_mod_zero_six_misses() -> void:
	b.ship.ch_modifier = 0
	_dice.queue([6])
	assert_false(crits.check_gunfire_crit(_ctx(), PHASE))
	var roll := _events(PhaseEvents.Type.CRITICAL_ROLL)
	assert_eq(roll.size(), 1, "the failed roll is logged")
	assert_false(roll[0].data["hit"])
	assert_eq(_crit_events().size(), 0)


func test_row3_fgn_six_ch_number_zero_still_crits_with_mod() -> void:
	# FGN 1-6: CH# <= 0; CH d6 2 - 2 = 0 <= 0.
	_dice.queue([2, 2, 2])
	assert_true(crits.check_gunfire_crit(_ctx("high", "round", "", STARBOARD, 6, 6), PHASE))
	assert_eq(_events(PhaseEvents.Type.CRITICAL_ROLL)[0].data["ch_number"], 0)


func test_row4_gunnery_five_rolls_nothing() -> void:
	assert_false(crits.check_gunfire_crit(_ctx("high", "round", "", STARBOARD, 5), PHASE))
	assert_eq(_events(PhaseEvents.Type.CRITICAL_ROLL).size(), 0)


func test_struck_target_rolls_no_crit() -> void:
	b.status = ShipState.Status.STRUCK
	assert_false(crits.check_gunfire_crit(_ctx(), PHASE))
	assert_eq(GameState.turn_log.events.size(), 0)


# --- hull results, engaged side, rakes ---

func test_row5_hull_nine_dismounts_two_guns_engaged_side_only() -> void:
	assert_true(_crit([4, 5], _ctx("low")))
	assert_eq(b.guns_dismounted, [0, 2] as Array[int])
	var ev := _crit_events()[0]
	assert_eq(ev.data["result_id"], "guns_dismounted")
	assert_eq(ev.data["side"], STARBOARD)
	var guns := _events(PhaseEvents.Type.GUNS_DISMOUNTED)
	assert_eq(guns[0].data, {"amount": 2, "side": STARBOARD})


func test_row6_stern_rake_dismounts_on_both_sides() -> void:
	# 7.E.5b
	_crit([4, 5], _ctx("low", "round", "stern", CriticalHitController.SIDE_BOTH))
	assert_eq(b.guns_dismounted, [2, 2] as Array[int])


func test_bow_rake_side_roll_picks_port() -> void:
	_dice.queue([1])
	_dice.queue([4, 4])
	_dice.queue([2])  # side d6: port
	crits.check_gunfire_crit(_ctx("low", "round", "bow", CriticalHitController.SIDE_RANDOM), PHASE)
	assert_eq(b.guns_dismounted, [1, 0] as Array[int])
	assert_eq(_crit_events()[0].data["side_roll"], 2)


func test_engaged_side_from_relative_bearing() -> void:
	# Spec Q12: a non-rake shot hits the side the firer lies on.
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "a_ship"
	order.target_id = "b_ship"
	order.aim = "low"
	order.ammo = "round"
	var expected: int = GameState.fire_geometry.bearing_side(b.hex_position, b.facing, a.hex_position)
	assert_ne(expected, -1, "fixture: A lies in one of B's broadside arcs")
	assert_eq(crits.shot_context(order, "", false)["engaged_side"], expected)
	assert_eq(crits.shot_context(order, "stern", false)["engaged_side"], CriticalHitController.SIDE_BOTH)
	assert_eq(crits.shot_context(order, "bow", false)["engaged_side"], CriticalHitController.SIDE_RANDOM)


func test_engaged_side_on_centre_line_is_random() -> void:
	# A dead astern of B, on B's keel line, beyond rake range.
	b.hex_position = Vector2i(8, 0)
	b.facing = 0
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "a_ship"
	order.target_id = "b_ship"
	assert_eq(crits.shot_context(order, "", false)["engaged_side"], CriticalHitController.SIDE_RANDOM)


func test_row7_dismantling_aimed_low_rolls_no_crit() -> void:
	# 7.C.12b: dismantling shot causes no hull critical hits.
	assert_false(crits.check_gunfire_crit(_ctx("low", "dismantling"), PHASE))
	assert_eq(GameState.turn_log.events.size(), 0)


func test_row8_dismantling_yard_shot_away_ignored() -> void:
	# Rigging #10 is [D].
	_crit([4, 6], _ctx("high", "dismantling"))
	var ev := _crit_events()[0]
	assert_eq(ev.data["result_id"], "yard_shot_away")
	assert_eq(ev.data["ignored"], "dismantling shot")
	assert_eq(b.rigging_current_hp, [5, 5, 6, 6] as Array[int])
	assert_eq(b.critical_effects.size(), 0)


func test_dismantling_does_not_filter_non_d_results() -> void:
	_crit([2, 2], _ctx("high", "dismantling"))  # braces cut has no [D]
	assert_true(b.has_critical("braces_cut"))


func test_row25_bow_rake_rudder_becomes_one_hull() -> void:
	# 7.E.6: no rudder result from a bow rake; one extra hull hit instead.
	_crit([1, 1], _ctx("low", "round", "bow", CriticalHitController.SIDE_RANDOM))
	assert_eq(b.hull_current_hp, [4, 5, 5, 6] as Array[int])
	assert_false(b.rudder_destroyed)
	assert_false(b.has_critical("rudder_jammed"))
	assert_true(_crit_events()[0].data["converted"])
	assert_eq(_events(PhaseEvents.Type.DAMAGE)[0].data["cause"], "critical")


func test_row26_rudder_destroyed_then_jam_ignored() -> void:
	_dice.queue([1, 1, 1, 2])  # CH d6, 2d6 = 2, rudder d6 2: destroyed
	crits.check_gunfire_crit(_ctx("low"), PHASE)
	assert_true(b.rudder_destroyed)
	_dice.queue([1, 1, 1, 5])  # rudder d6 5: jammed, ignored
	crits.check_gunfire_crit(_ctx("low"), PHASE)
	assert_false(b.has_critical("rudder_jammed"))
	assert_eq(_crit_events()[1].data["ignored"], "rudder already destroyed")


func test_rudder_jammed_records_entry() -> void:
	_dice.queue([1, 1, 1, 4])
	crits.check_gunfire_crit(_ctx("low"), PHASE)
	assert_true(b.has_critical("rudder_jammed"))
	assert_false(b.rudder_destroyed)


func test_rudder_jammed_holds_the_last_step_direction() -> void:
	# Spec Q15: the jam direction is the last step the ship executed (here a starboard turn).
	b.last_step_direction = STARBOARD
	_dice.queue([1, 1, 1, 6])  # rudder d6 6: jammed
	crits.check_gunfire_crit(_ctx("low"), PHASE)
	assert_eq(b.rudder_jam_direction(), STARBOARD)
	assert_eq(_crit_events()[0].data["jam"], STARBOARD)
	assert_string_contains(_crit_events()[0].to_text({}), "rudder jammed to starboard")


func test_rudder_jammed_with_no_step_is_straight() -> void:
	# Spec Q15: with no step at all the rudder jams amidships (-1): no turns.
	_dice.queue([1, 1, 1, 4])
	crits.check_gunfire_crit(_ctx("low"), PHASE)
	assert_eq(b.rudder_jam_direction(), -1)
	assert_string_contains(_crit_events()[0].to_text({}), "rudder jammed amidships")


func test_wheel_shot_away_sets_flag() -> void:
	_crit([1, 2], _ctx("low"))
	assert_true(b.wheel_shot_away)
	assert_true(b.is_poor_maneuvering())


func test_hull_four_crew_disorganized_loses_one_sailor_only() -> void:
	# Spec Q6: only the box loss; disorganization is not simulated.
	_crit([2, 2], _ctx("low"))
	assert_eq(b.crew_count, [2, 3, 3, 3] as Array[int])
	assert_eq(_crit_events()[0].data["note"], "not_simulated")


func test_hull_five_leadership_marine_and_mc() -> void:
	_crit([2, 3], _ctx("low"))
	assert_eq(b.marine_count, 1)
	assert_eq(b.pending_morale_checks, 1)


func test_hull_six_one_hull_box() -> void:
	_crit([3, 3], _ctx("low"))
	assert_eq(b.hull_current_hp, [4, 5, 5, 6] as Array[int])


func test_hull_eight_one_gun() -> void:
	_crit([4, 4], _ctx("low", "round", "", PORT))
	assert_eq(b.guns_dismounted, [1, 0] as Array[int])


func test_hull_ten_minor_explosion_hull_and_guns_no_fire_roll() -> void:
	# Spec Q10: 1H and -2 guns on the engaged broadside; fire roll deferred.
	_crit([5, 5], _ctx("low"))
	assert_eq(b.hull_current_hp, [4, 5, 5, 6] as Array[int])
	assert_eq(b.guns_dismounted, [0, 2] as Array[int])
	assert_eq(b.fires, 0)
	assert_eq(_crit_events()[0].data["note"], "fire_not_simulated")


func test_row18_class_two_pumps_take_three_sailors_lowest_first() -> void:
	# 7.D.12 example: S2 has 2 boxes; both go and one from S3; S2 lost: one MC.
	b.ship.ship_class = 2
	b.crew_count = [0, 2, 3, 3] as Array[int]
	_crit([5, 6], _ctx("low"))
	assert_eq(b.crew_count, [0, 0, 2, 3] as Array[int])
	assert_eq(b.marine_count, 2)
	assert_true(b.morale_triggers_used.has("crew_1"))
	assert_eq(b.pending_morale_checks, 1)


func test_row19_class_three_pumps_take_two_sailors() -> void:
	_crit([5, 6], _ctx("low"))
	assert_eq(b.crew_count, [1, 3, 3, 3] as Array[int])


func test_pumps_without_enough_crew_strike() -> void:
	b.crew_count = [1, 0, 0, 0] as Array[int]
	b.marine_count = 0
	_crit([5, 6], _ctx("low"))
	assert_true(b.is_struck())
	assert_eq(_events(PhaseEvents.Type.STRIKE)[0].data["reason"], "waterline")
	assert_eq(b.total_crew_boxes(), 0)


# --- Hull #12 afire / major explosion (spec Q2, Q14) ---

## Hull #12 on b_ship (class 3 unless changed), then the explosion 2d10 = `explosion`.
func _hull_twelve(explosion: Array, ctx: Dictionary = {}) -> void:
	_dice.queue([1, 6, 6])  # CH d6, then 2d6 = 12
	_dice.queue(explosion)
	crits.hold()
	crits.check_gunfire_crit(ctx if not ctx.is_empty() else _ctx("low"), PHASE)
	crits.release(PHASE)


func test_hull_twelve_afire_hull_guns_both_sides_and_mc() -> void:
	_hull_twelve([5, 5])  # 10 + 0 (CQ D) = 10, not < 3
	assert_eq(b.fires, 1)
	assert_eq(b.hull_current_hp, [4, 5, 5, 6] as Array[int])
	assert_eq(b.guns_dismounted, [2, 2] as Array[int], "-2 on each broadside")
	assert_eq(b.pending_morale_checks, 1)
	assert_eq(b.status, ShipState.Status.ACTIVE)
	var data: Dictionary = _crit_events()[0].data
	assert_eq(data["result_id"], "afire_major_explosion")
	assert_eq(data["side"], CriticalHitController.SIDE_BOTH)
	assert_eq(data["explosion"], {"roll": 10, "modifier": 0, "total": 10, "needed": 3, "explodes": false})
	var fire := _events(PhaseEvents.Type.FIRE_STARTED)
	assert_eq(fire.size(), 1)
	assert_eq(fire[0].data["fires"], 1)
	assert_eq(_events(PhaseEvents.Type.DESTROYED).size(), 0)


func test_hull_twelve_engaged_side_never_rolled() -> void:
	# Both broadsides lose guns, so a bow rake rolls no side d6.
	_hull_twelve([9, 9], _ctx("low", "round", "bow", CriticalHitController.SIDE_RANDOM))
	assert_eq(b.guns_dismounted, [2, 2] as Array[int])


func test_row34_hull_twelve_class_two_roll_one_explodes() -> void:
	# Spec row 34: CQ D, no fires, class 2, 2d10 = 1: 1 < 2, the ship explodes and is destroyed.
	b.ship.ship_class = 2
	_hull_twelve([0, 1])
	assert_true(b.is_destroyed())
	assert_true(b.is_out_of_play())
	assert_true(_crit_events()[0].data["explosion"]["explodes"])
	var destroyed := _events(PhaseEvents.Type.DESTROYED)
	assert_eq(destroyed.size(), 1)
	assert_eq(destroyed[0].data["reason"], "explosion")
	assert_eq(b.pending_morale_checks, 0, "a destroyed ship checks no morale")


func test_hull_twelve_total_equal_to_class_does_not_explode() -> void:
	_hull_twelve([1, 2])  # 3 + 0 = 3, not < 3
	assert_false(b.is_destroyed())


func test_hull_twelve_crew_quality_drm() -> void:
	b.crew_quality = "A"
	_hull_twelve([0, 0])  # 0 + 3 = 3, not < 3
	assert_false(b.is_destroyed())
	assert_eq(_crit_events()[0].data["explosion"]["modifier"], 3)


func test_hull_twelve_poor_crew_explodes() -> void:
	b.crew_quality = "G"
	_hull_twelve([2, 3])  # 5 - 3 = 2 < 3
	assert_true(b.is_destroyed())


func test_hull_twelve_existing_fire_drm_reads_fires_before_increment() -> void:
	b.fires = 1
	_hull_twelve([2, 3])  # 5 - 2 (one fire already) = 3, not < 3; -4 would have exploded
	assert_false(b.is_destroyed())
	assert_eq(_crit_events()[0].data["explosion"]["modifier"], -2)
	assert_eq(b.fires, 2)


func test_hull_twelve_year_1783_drm() -> void:
	var old_scenario: Dictionary = GameState.active_scenario
	GameState.active_scenario = {"year": 1783}
	_hull_twelve([1, 2])  # 3 - 1 = 2 < 3
	GameState.active_scenario = old_scenario
	assert_true(b.is_destroyed())
	assert_eq(_crit_events()[0].data["explosion"]["modifier"], -1)


func test_hull_twelve_year_after_1783_or_absent_no_drm() -> void:
	var old_scenario: Dictionary = GameState.active_scenario
	GameState.active_scenario = {"year": 1784}
	assert_eq(crits.explosion_modifier(b, 0), 0)
	GameState.active_scenario = {}
	assert_eq(crits.explosion_modifier(b, 0), 0)
	GameState.active_scenario = {"year": 1780.0}  # JSON numbers load as floats
	assert_eq(crits.explosion_modifier(b, 0), -1)
	GameState.active_scenario = old_scenario


func test_hull_twelve_dismantling_shot_ignored() -> void:
	# [D]: a dismantling shot aimed low causes no hull crit roll at all (7.C.12b), so nothing.
	_dice.queue([])
	assert_false(crits.check_gunfire_crit(_ctx("low", "dismantling"), PHASE))
	assert_eq(b.fires, 0)


func test_hull_twelve_explosion_frees_fouled_partner() -> void:
	b.ship.ship_class = 2
	GameState.ship_controller.set_fouled_with("a_ship", "b_ship")
	GameState.ship_controller.set_fouled_with("b_ship", "a_ship")
	_hull_twelve([0, 0])
	assert_true(b.is_destroyed())
	assert_eq(a.fouled_with, "")
	assert_eq(b.fouled_with, "")


func test_hull_twelve_checks_queued_by_its_hull_box_skip_the_wreck() -> void:
	# The 1H empties hull section 1; its Hull Check is queued behind the explosion roll and is not
	# rolled once the ship is destroyed.
	b.ship.ship_class = 2
	b.hull_current_hp = [1, 5, 5, 6] as Array[int]
	_hull_twelve([0, 0])
	assert_true(b.is_destroyed())
	assert_eq(_crit_events().size(), 1, "no Hull Check rolled for the wreck")


func test_destroyed_target_rolls_no_crit() -> void:
	b.status = ShipState.Status.DESTROYED
	assert_false(crits.check_gunfire_crit(_ctx(), PHASE))
	assert_eq(_events(PhaseEvents.Type.CRITICAL_ROLL).size(), 0)


func test_destroyed_ship_rolls_no_fixes() -> void:
	GameState.ship_controller.add_critical_effect("b_ship", {"id": "braces_cut"})
	b.status = ShipState.Status.DESTROYED
	crits.resolve_fixes(PHASE)
	assert_eq(_events(PhaseEvents.Type.CRITICAL_FIXED).size(), 0)


# --- rigging results ---

func test_rigging_three_signal_halyards_one_box_at_ms_no_entry() -> void:
	_crit([1, 2], _ctx())
	assert_eq(b.rigging_current_hp, [4, 5, 6, 6] as Array[int])
	assert_eq(b.critical_effects.size(), 0)


func test_rigging_three_signal_halyards_nothing_at_fs() -> void:
	b.sail_state = "FS"
	_crit([1, 2], _ctx())
	assert_eq(b.rigging_current_hp, [5, 5, 6, 6] as Array[int])


func test_rigging_five_lines_jammed_entry() -> void:
	_crit([2, 3], _ctx())
	assert_true(b.has_critical("lines_jammed"))


func test_rigging_six_obscured_side_roll_and_boxes() -> void:
	# PS: 2R; d6 4: starboard.
	b.sail_state = "PS"
	_dice.queue([1, 3, 3, 4])
	crits.check_gunfire_crit(_ctx(), PHASE)
	assert_eq(b.rigging_current_hp, [3, 5, 6, 6] as Array[int])
	assert_eq(b.critical_count("broadside_obscured", STARBOARD), 1)
	assert_eq(b.obscured_penalty(STARBOARD), -2)
	assert_eq(b.obscured_penalty(PORT), 0)


func test_rigging_seven_sheets_cut_expires_after_next_turn_once_per_turn() -> void:
	# Rows 10-11: next g-t only; at most one per ship per g-t.
	_crit([3, 4], _ctx())
	_crit([3, 4], _ctx())
	assert_eq(b.critical_count("sheets_cut"), 1)
	assert_eq(b.critical_effects[0]["expires_after_turn"], 4)
	assert_eq(_crit_events()[1].data["ignored"], "sheets already cut this turn")


func test_rigging_nine_shrouds_box_and_entry() -> void:
	_crit([4, 5], _ctx())
	assert_eq(b.rigging_current_hp, [4, 5, 6, 6] as Array[int])
	assert_true(b.has_critical("shrouds_severed"))


func test_rigging_ten_yard_shot_away_both_sides() -> void:
	_crit([4, 6], _ctx())
	assert_eq(b.rigging_current_hp, [3, 5, 6, 6] as Array[int])  # MS: 2R
	assert_eq(b.obscured_penalty(PORT), -2)
	assert_eq(b.obscured_penalty(STARBOARD), -2)


func test_row20_mast_falls_on_deck_class_three() -> void:
	# Cross out section 1; 2C (marines first: 1 marine, 1 sailor); RC for the section; MC.
	b.marine_count = 1
	_dice.queue([1, 6, 6, 4])  # CH d6, 2d6 = 12, RC d6 4 (lines jammed)
	crits.hold()
	crits.check_gunfire_crit(_ctx(), PHASE)
	crits.release(PHASE)
	assert_eq(b.rigging_current_hp, [0, 5, 6, 6] as Array[int])
	assert_eq(b.marine_count, 0)
	assert_eq(b.crew_count, [2, 3, 3, 3] as Array[int])
	assert_eq(_ids(_crit_events()), ["mast_falls_on_deck", "lines_jammed"])
	assert_eq(_crit_events()[1].data["source"], "rigging_check")
	assert_true(b.morale_triggers_used.has("crew_4"))
	assert_eq(b.pending_morale_checks, 2, "all marines lost + the crit MC")


func test_row21_stays_cut_mast_goes_then_one_more_box() -> void:
	b.speed = 4
	_dice.queue([1, 5, 6, 3, 4])  # CH, 2d6 = 11, d10 3 <= speed 4, RC d6 4
	crits.hold()
	crits.check_gunfire_crit(_ctx(), PHASE)
	crits.release(PHASE)
	assert_eq(b.rigging_current_hp, [0, 4, 6, 6] as Array[int])
	assert_eq(b.pending_morale_checks, 1)
	assert_eq(_ids(_crit_events()), ["stays_cut", "lines_jammed"])


func test_stays_cut_roll_above_speed_only_one_box() -> void:
	b.speed = 2
	_dice.queue([1, 5, 6, 3])
	crits.check_gunfire_crit(_ctx(), PHASE)
	assert_eq(b.rigging_current_hp, [4, 5, 6, 6] as Array[int])
	assert_eq(b.pending_morale_checks, 0)


func test_row22_mast_may_fall_eight_crosses_out_and_chains() -> void:
	# MS +1, one section lost +1, WS 4 +1, d6 5: 8 >= 8.
	GameState.environment.wind_speed = 4
	b.rigging_current_hp = [0, 5, 6, 6] as Array[int]
	_dice.queue([1, 1, 1, 5, 4])  # CH, 2d6 = 2, mast d6 5, RC d6 4
	crits.hold()
	crits.check_gunfire_crit(_ctx(), PHASE)
	crits.release(PHASE)
	assert_eq(b.rigging_current_hp, [0, 0, 6, 6] as Array[int])
	var ev := _crit_events()[0]
	assert_eq(ev.data["modifier"], 3)
	assert_true(ev.data["falls"])
	assert_eq(_ids(_crit_events()), ["mast_may_fall", "lines_jammed"])


func test_mast_may_fall_seven_holds() -> void:
	_dice.queue([1, 1, 1, 5])  # MS +1, WS 2: 6 < 8
	crits.check_gunfire_crit(_ctx(), PHASE)
	assert_eq(b.rigging_current_hp, [5, 5, 6, 6] as Array[int])
	assert_false(_crit_events()[0].data["falls"])


# --- dismasted rules (chart notes) ---

func test_row23_diamond_ignored_when_dismasted_this_phase() -> void:
	# The shot dismasts B; the RC for the last section rolls braces cut (diamond): ignored.
	b.rigging_current_hp = [0, 0, 0, 2] as Array[int]
	_dice.queue([3])  # RC d6 3: braces cut
	GameState.damage_controller.apply_hits("b_ship", 2, 0, 0, "other", PHASE, "a_ship", _ctx())
	assert_true(b.is_dismasted())
	var ev := _crit_events()[0]
	assert_eq(ev.data["result_id"], "braces_cut")
	assert_eq(ev.data["ignored"], "dismasted")
	assert_false(b.has_critical("braces_cut"))


func test_non_diamond_applies_when_dismasted_this_phase() -> void:
	b.rigging_current_hp = [0, 0, 0, 2] as Array[int]
	_dice.queue([5])  # RC d6 5: broadside obscured (no diamond); NS now: no boxes
	_dice.queue([1])  # side d6: port
	GameState.damage_controller.apply_hits("b_ship", 2, 0, 0, "other", PHASE, "a_ship", _ctx())
	assert_eq(b.critical_count("broadside_obscured", PORT), 1)


func test_row24_no_rigging_crit_on_ship_dismasted_before_combat() -> void:
	b.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	b.sail_state = "NS"
	_crit([5, 5], _ctx("high", "round", "", STARBOARD, 6, 40, true))
	var ev := _crit_events()[0]
	assert_eq(ev.data["ignored"], "dismasted before this combat phase")
	assert_eq(b.critical_effects.size(), 0)


# --- Rigging and Hull Checks, chaining (7.D.7, 7.D.8a, 7.D.12) ---

func test_row9_hull_section_emptied_hull_check_seven_rolls_rigging() -> void:
	# HC d6 3: hull #7 rigging damage, 2d6 on the Rigging Crit column (4: braces cut).
	_dice.queue([3, 2, 2])
	GameState.damage_controller.apply_hits("b_ship", 0, 5, 0, "other", PHASE, "a_ship", _ctx("low"))
	var events := _crit_events()
	assert_eq(events.map(func(e): return e.data["source"]), ["hull_check", "hull_7"])
	assert_eq(_ids(events), ["rigging_damage", "braces_cut"])
	assert_eq(events[0].data["section"], 0)
	assert_true(b.has_critical("braces_cut"))


func test_hull_check_guns_use_shot_side_and_stern_rake() -> void:
	# HC d6 6: hull #9, -2 guns; stern rake: both sides (7.E.5b), on top of 7.D.8b's -1 each.
	_dice.queue([6])
	GameState.damage_controller.apply_hits("b_ship", 0, 5, 0, "other", PHASE, "a_ship",
			_ctx("low", "round", "stern", CriticalHitController.SIDE_BOTH))
	assert_eq(b.guns_dismounted, [3, 3] as Array[int])


func test_crit_extra_boxes_empty_a_section_and_chain() -> void:
	# Hull #6 (1H) empties hull section 1 (1 box left): HC d6 1 (leadership) follows.
	b.hull_current_hp = [1, 5, 5, 6] as Array[int]
	_dice.queue([1, 3, 3, 1])
	crits.hold()
	crits.check_gunfire_crit(_ctx("low"), PHASE)
	crits.release(PHASE)
	assert_eq(_ids(_crit_events()), ["hull_structural_damage", "leadership_casualties"])
	assert_eq(b.marine_count, 1)


func test_checks_run_fifo_after_the_shot_crit() -> void:
	# Gunfire empties rigging 1 and hull 1 while held; the crit (2d6 = 4) comes first, then
	# the RC and the HC in the order the sections emptied.
	crits.hold()
	GameState.damage_controller.apply_hits("b_ship", 5, 5, 0, "other", PHASE, "a_ship", _ctx("high"))
	assert_eq(crits.pending_checks(), 2)
	_dice.queue([1, 2, 2])  # CH d6, 2d6 = 4 braces cut
	_dice.queue([4])  # RC: lines jammed
	_dice.queue([2])  # HC: 1H
	crits.check_gunfire_crit(_ctx("high"), PHASE)
	crits.release(PHASE)
	assert_eq(_crit_events().map(func(e): return e.data["source"]),
			["gunfire", "rigging_check", "hull_check"])
	assert_eq(b.hull_current_hp, [0, 4, 5, 6] as Array[int])


func test_struck_ship_rolls_no_checks() -> void:
	crits.queue_rigging_check("b_ship", _ctx())
	b.status = ShipState.Status.STRUCK
	crits.drain(PHASE)
	assert_eq(_crit_events().size(), 0)


func test_row35_two_crit_mcs_in_one_turn() -> void:
	# 9.B.1e: each crit MC has its own trigger.
	b.marine_count = 4
	_crit([3, 5], _ctx())  # rigging #8 leadership
	_crit([3, 5], _ctx())
	assert_eq(b.pending_morale_checks, 2)
	var triggers := _events(PhaseEvents.Type.MORALE_NOTED).map(func(e): return e.data["trigger"])
	assert_eq(triggers.size(), 2)
	assert_ne(triggers[0], triggers[1])
	assert_eq(PhaseEvents.morale_trigger_text(triggers[0]), "critical hit")


func test_row36_collision_empties_rigging_section_rolls_check_in_movement() -> void:
	# 7.D.7, 6.E.3: the collision path drains the queue in MOVEMENT_RESOLUTION.
	_dice.queue([4])
	GameState.movement_resolver._apply_rigging_damage("b_ship", 5, GameState.ship_controller)
	var events := _crit_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0].phase, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION)
	assert_eq(events[0].data["source"], "rigging_check")
	assert_true(b.has_critical("lines_jammed"))


# --- 8.D.5 fixing (STATUS_ADJUSTMENT) ---

const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT


func _add(ship_id: String, id: String, side: int = -1) -> int:
	return GameState.ship_controller.add_critical_effect(ship_id, {"id": id, "side": side})


func test_row15_fix_cq_b_first_attempt_four_succeeds() -> void:
	b.crew_quality = "B"  # SK -2
	_add("b_ship", "braces_cut")
	_dice.queue([4])
	crits.resolve_fixes(STATUS)
	assert_false(b.has_critical("braces_cut"))
	var ev := _events(PhaseEvents.Type.CRITICAL_FIXED)
	assert_eq(ev.size(), 1)
	assert_eq(ev[0].ship_id, "b_ship")
	assert_eq(ev[0].data, {"result_id": "braces_cut", "side": -1, "roll": 4, "modifier": -2,
			"needed": 2, "attempt": 1, "success": true})


func test_row15_fix_fails_then_second_attempt_succeeds() -> void:
	b.crew_quality = "B"
	_add("b_ship", "lines_jammed")
	_dice.queue([5])  # 5 - 2 = 3 > 2
	crits.resolve_fixes(STATUS)
	assert_true(b.has_critical("lines_jammed"))
	assert_eq(b.critical_effects[0]["attempts"], 1)
	assert_false(_events(PhaseEvents.Type.CRITICAL_FIXED)[0].data["success"])
	_dice.queue([5])  # attempt 2: 3 <= 3
	crits.resolve_fixes(STATUS)
	assert_false(b.has_critical("lines_jammed"))
	var second := _events(PhaseEvents.Type.CRITICAL_FIXED)[1]
	assert_eq(second.data["needed"], 3)
	assert_eq(second.data["attempt"], 2)
	assert_true(second.data["success"])


func test_fix_third_attempt_needs_four() -> void:
	_add("b_ship", "rudder_jammed")
	b.critical_effects[0]["attempts"] = 2
	_dice.queue([4])  # CQ D: 4 + 0 <= 4
	crits.resolve_fixes(STATUS)
	assert_false(b.has_critical("rudder_jammed"))
	assert_eq(_events(PhaseEvents.Type.CRITICAL_FIXED)[0].data["needed"], 4)


func test_fix_order_ships_by_id_effects_by_seq_each_side_separately() -> void:
	# Yard shot away leaves one obscured entry per side; each is fixed on its own roll.
	_add("b_ship", "broadside_obscured", PORT)
	_add("b_ship", "broadside_obscured", STARBOARD)
	_add("a_ship", "braces_cut")
	_dice.queue([1, 1, 9])  # a: braces fixed; b port fixed; b starboard fails
	crits.resolve_fixes(STATUS)
	var ev := _events(PhaseEvents.Type.CRITICAL_FIXED)
	assert_eq(ev.map(func(e): return [e.ship_id, e.data["result_id"], e.data["side"], e.data["success"]]),
			[["a_ship", "braces_cut", -1, true], ["b_ship", "broadside_obscured", PORT, true],
			["b_ship", "broadside_obscured", STARBOARD, false]])
	assert_eq(b.obscured_penalty(PORT), 0)
	assert_eq(b.obscured_penalty(STARBOARD), -2)


func test_fix_skips_struck_ships_and_unfixable_effects() -> void:
	_add("a_ship", "braces_cut")
	a.status = ShipState.Status.STRUCK
	_add("b_ship", "shrouds_severed")  # repaired by crew tasks, not the Unfouling table
	crits.resolve_fixes(STATUS)
	assert_eq(_events(PhaseEvents.Type.CRITICAL_FIXED).size(), 0)
	assert_true(a.has_critical("braces_cut"))
	assert_true(b.has_critical("shrouds_severed"))


func test_sheets_cut_ends_in_the_next_turns_status_adjustment() -> void:
	# Row 10: inflicted on turn 3, affects turn 4's movement, removed in turn 4's maintenance.
	_crit([3, 4], _ctx())
	crits.resolve_fixes(STATUS)
	assert_true(b.has_critical("sheets_cut"), "kept through turn 3")
	GameState.current_turn = 4
	crits.resolve_fixes(STATUS)
	assert_false(b.has_critical("sheets_cut"))
	var ended := _events(PhaseEvents.Type.CRITICAL_ENDED)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].data, {"result_id": "sheets_cut", "side": -1, "reason": "expired"})


func test_status_adjustment_order_unfoul_fix_sail() -> void:
	var old_phase: int = GameState.phase_controller.current_phase
	a.fouled_with = "b_ship"
	b.fouled_with = "a_ship"
	_add("b_ship", "braces_cut")
	a.sail_change = {"target": "FS", "turns_left": 1, "sections": [3]}
	_dice.queue([9, 9, 1])  # a and b fail to unfoul; b fixes its braces
	GameState.phase_controller._enter_status_adjustment_phase()
	var types: Array = GameState.turn_log.events.map(func(e): return e.type)
	var order := [PhaseEvents.Type.UNFOUL, PhaseEvents.Type.UNFOUL, PhaseEvents.Type.CRITICAL_FIXED,
			PhaseEvents.Type.SAIL_CHANGE]
	assert_eq(types.filter(func(t): return order.has(t)), order)
	assert_false(b.has_critical("braces_cut"))
	GameState.phase_controller.current_phase = old_phase


func test_resolve_fixes_client_refuses() -> void:
	crits.is_server = false
	crits.resolve_fixes(STATUS)
	assert_push_error(1, "client refusal")


# --- Lines Jammed (Rigging #5, 5.F.9c) ---

func test_row16_lines_jammed_cancels_change_in_progress() -> void:
	b.sail_change = {"target": "PS", "turns_left": 2, "sections": [3, 2]}
	_crit([2, 3], _ctx())
	assert_true(b.has_critical("lines_jammed"))
	assert_eq(b.sail_change, {})
	assert_eq(b.sail_state, "MS")
	var sail := _events(PhaseEvents.Type.SAIL_CHANGE)
	assert_eq(sail.size(), 1)
	assert_eq(sail[0].data["cancelled"], "lines jammed")
	assert_eq(sail[0].phase, PHASE)


func test_row17_lines_jammed_cleared_when_dismasted() -> void:
	_add("b_ship", "lines_jammed")
	_add("b_ship", "braces_cut")
	b.rigging_current_hp = [0, 0, 0, 1] as Array[int]
	_dice.queue([6])  # RC d6 6: sheets cut, ignored (diamond, dismasted)
	GameState.damage_controller.apply_hits("b_ship", 1, 0, 0, "other", PHASE, "a_ship", _ctx())
	assert_true(b.is_dismasted())
	assert_false(b.has_critical("lines_jammed"))
	assert_true(b.has_critical("braces_cut"), "only lines jammed is fixed by dismasting")
	var ended := _events(PhaseEvents.Type.CRITICAL_ENDED)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].data, {"result_id": "lines_jammed", "side": -1, "reason": "dismasted"})


func test_fix_log_texts() -> void:
	var names := {"b_ship": "Vengeance"}
	var fixed := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_FIXED, STATUS, "b_ship",
			{"result_id": "broadside_obscured", "side": PORT, "roll": 3, "modifier": -2, "needed": 2,
			"success": true})
	assert_eq(fixed.to_text(names), "Vengeance fixes the port broadside obscured (3 -2 = 1 ≤ 2)")
	var failed := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_FIXED, STATUS, "b_ship",
			{"result_id": "lines_jammed", "side": -1, "roll": 7, "modifier": -2, "needed": 2,
			"success": false})
	assert_eq(failed.to_text(names), "Vengeance fails to fix the jammed lines (7 -2 = 5 > 2)")
	var expired := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_ENDED, STATUS, "b_ship",
			{"result_id": "sheets_cut", "reason": "expired"})
	assert_eq(expired.to_text(names), "Vengeance: sheets cut repaired")
	var dismasted := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_ENDED, PHASE, "b_ship",
			{"result_id": "lines_jammed", "reason": "dismasted"})
	assert_eq(dismasted.to_text(names), "Vengeance: lines jammed cleared (the ship is dismasted)")


# --- gunnery resolver hook ---

func test_resolver_rolls_ch_after_damage_and_logs_ch_number() -> void:
	# A fires starboard at B (fixture of test_gunnery_resolver): FGN 34 (CH# 4) with a six.
	b.ship.ch_modifier = 0
	var values: Array = []
	values.resize(60)
	values.fill(6)
	_dice.queue(values)
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "a_ship"
	order.side = STARBOARD
	order.target_id = "b_ship"
	order.ammo = "round"
	order.aim = "low"
	order.battery = "full"
	var orders: Array[GunneryTypes.FireOrder] = [order]
	GunneryResolver.new(GameState).resolve(orders, PHASE)
	var fire := _events(PhaseEvents.Type.FIRE)[0]
	assert_eq(fire.data["ch_number"], DataManager.combat_tables.critical_hit_number(fire.data["fgn"]))
	var types: Array = GameState.turn_log.events.map(func(e): return e.type)
	assert_lt(types.find(PhaseEvents.Type.DAMAGE), types.find(PhaseEvents.Type.CRITICAL_ROLL))
	_dice._queue.clear()


# --- log text ---

func test_log_texts() -> void:
	var names := {"b_ship": "Vengeance"}
	var roll := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_ROLL, PHASE, "b_ship",
			{"d6": 3, "ch_mod": -2, "ch_number": 4, "hit": true})
	assert_eq(roll.to_text(names), "Vengeance: critical hit roll 3 -2 = 1 ≤ 4 — critical hit!")
	var miss := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_ROLL, PHASE, "b_ship",
			{"d6": 6, "ch_mod": 0, "ch_number": 4, "hit": false})
	assert_eq(miss.to_text(names), "Vengeance: critical hit roll 6 +0 = 6 > 4, no critical")
	var guns := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_HIT, PHASE, "b_ship",
			{"source": "gunfire", "table": "hull", "roll": 9, "result_id": "guns_dismounted",
			"side": PORT, "guns": 2, "sub_rolls": []})
	assert_eq(guns.to_text(names), "Vengeance: hull critical 9 — guns dismounted −2 (port)")
	var check := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_HIT, PHASE, "b_ship",
			{"source": "rigging_check", "roll": 4, "result_id": "lines_jammed", "side": -1})
	assert_eq(check.to_text(names), "Vengeance: rigging check 4 — lines jammed")
	var ignored := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CRITICAL_HIT, PHASE, "b_ship",
			{"source": "gunfire", "table": "rigging", "roll": 4, "result_id": "braces_cut",
			"side": -1, "ignored": "dismasted"})
	assert_eq(ignored.to_text(names), "Vengeance: rigging critical 4 — braces cut (ignored: dismasted)")
	var one_side := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.GUNS_DISMOUNTED, PHASE, "b_ship",
			{"amount": 2, "side": STARBOARD})
	assert_eq(one_side.to_text(names), "Vengeance has 2 guns dismounted on the starboard broadside")


func test_client_refuses() -> void:
	crits.is_server = false
	assert_false(crits.check_gunfire_crit(_ctx(), PHASE))
	crits.drain(PHASE)
	assert_push_error(2, "client refusals")
