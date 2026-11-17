extends GutTest
## Tests for GunneryCalculator: shot eligibility and modified gunfire number (pure queries).

const PORT := 0
const STARBOARD := 1

var calc: GunneryCalculator
var firer: ShipState
var target: ShipState


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	calc = GunneryCalculator.new(GameState)
	firer = _make_ship("firer", 0, Vector2i.ZERO, 0)
	target = _make_ship("target", 1, _n(1), 0)


func _n(d: int) -> Vector2i:
	return HexGrid.DIRECTIONS[d]


func _steps(d: int, count: int) -> Vector2i:
	return HexGrid.DIRECTIONS[d] * count


func _make_ship(id: String, player: int, hex: Vector2i, facing: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id,
		"player_id": player,
		"ship_name": id,
		"ship_type": "frigate_38",
		"name": "38-gun Frigate",
		"nationality": "British",
		"rating": 38,
		"class": 3,
		"maneuverability": "C",
		"speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3],
		"marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex
	state.facing = facing
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


func _order(side: int = STARBOARD, ammo: String = "round", aim: String = "low",
		battery: String = "full", target_id: String = "target") -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "firer"
	order.side = side
	order.target_id = target_id
	order.ammo = ammo
	order.aim = aim
	order.battery = battery
	return order


func _battery(battery: String, side: int = STARBOARD, target_id: String = "target") -> GunneryTypes.FireOrder:
	return _order(side, "round", "low", battery, target_id)


func _mod(preview: GunneryTypes.ShotPreview, name: String) -> int:
	for m in preview.modifiers:
		if m["name"] == name:
			return m["value"]
	return 0


func _names(preview: GunneryTypes.ShotPreview) -> Array:
	return preview.modifiers.map(func(m): return m["name"])


# --- basic numbers ---

func test_adjacent_target_numbers() -> void:
	var p := calc.preview(_order())
	assert_true(p.can_fire, p.reason)
	assert_eq(p.range_hexes, 1)
	assert_eq(p.tgf, 14)
	assert_eq(p.bgn, 24)
	assert_eq(p.modifiers, [{"name": "initial_broadside", "value": 4}] as Array[Dictionary])
	assert_true(p.initial_broadside)
	assert_eq(p.mgn, 28)


func test_initial_broadside_already_fired() -> void:
	firer.initial_broadside_fired[STARBOARD] = true
	var p := calc.preview(_order())
	assert_false(p.initial_broadside)
	assert_eq(p.mgn, 24)


func test_crew_quality_b_adds_four() -> void:
	firer.initial_broadside_fired[STARBOARD] = true
	firer.crew_quality = "B"
	assert_eq(calc.preview(_order()).mgn, 28)


func test_sections_firing_penalty() -> void:
	firer.crew_count = [0, 3, 3, 3] as Array[int]
	var p := calc.preview(_order())
	assert_eq(_mod(p, "sections_firing"), -3)


func test_guns_dismounted_penalty() -> void:
	firer.guns_dismounted[STARBOARD] = 3
	assert_eq(_mod(calc.preview(_order()), "guns_dismounted"), -3)


## 7.C.11: -2 per broadside obscured entry on the firing side (Rigging #6; #10 adds one per side).
func test_broadside_obscured_on_firing_side() -> void:
	GameState.ship_controller.add_critical_effect("firer", {"id": "broadside_obscured", "side": STARBOARD})
	var p := calc.preview(_order())
	assert_eq(_mod(p, "broadside_obscured"), -2)
	assert_eq(p.mgn, 26)
	assert_eq(_mod(calc.preview(_order(PORT)), "broadside_obscured"), 0, "the other side is clear")


func test_broadside_obscured_entries_add_up() -> void:
	GameState.ship_controller.add_critical_effect("firer", {"id": "broadside_obscured", "side": STARBOARD})
	GameState.ship_controller.add_critical_effect("firer", {"id": "broadside_obscured", "side": STARBOARD})
	assert_eq(_mod(calc.preview(_order()), "broadside_obscured"), -4)


func test_broadside_obscured_previewed_orders_match_preview() -> void:
	# The resolver rolls preview_orders(); the fire panel shows the same numbers.
	GameState.ship_controller.add_critical_effect("firer", {"id": "broadside_obscured", "side": STARBOARD})
	var previews := calc.preview_orders(_orders([_order()]))
	assert_eq(_mod(previews[0], "broadside_obscured"), -2)
	assert_eq(previews[0].mgn, calc.preview(_order()).mgn)
	assert_eq(PhaseEvents.modifier_label("broadside_obscured"), "broadside obscured")


func test_two_targets_modifier() -> void:
	var p := calc.preview(_order(), true)
	assert_eq(_mod(p, "two_targets"), -12)


func test_plain_sail_modifier() -> void:
	firer.sail_state = "PS"
	assert_eq(_mod(calc.preview(_order()), "plain_sail"), -1)


func test_dismantling_shot() -> void:
	var p := calc.preview(_order(STARBOARD, "dismantling"))
	assert_eq(_mod(p, "dismantling_shot"), 1)


func test_dismantling_out_of_range_cannot_fire() -> void:
	target.hex_position = _steps(1, 8)
	var p := calc.preview(_order(STARBOARD, "dismantling"))
	assert_false(p.can_fire)
	assert_ne(p.reason, "")


func test_wind_speed_four_modifier() -> void:
	GameState.environment.wind_speed = 4
	assert_eq(_mod(calc.preview(_order()), "wind_speed_4"), -1)


func test_dismasted_subtracts_sea_state() -> void:
	firer.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	GameState.environment.sea_state = 2
	assert_eq(_mod(calc.preview(_order()), "dismasted"), -2)


func test_modifier_order() -> void:
	firer.crew_quality = "B"
	firer.sail_state = "PS"
	firer.crew_count = [0, 3, 3, 3] as Array[int]
	firer.guns_dismounted[STARBOARD] = 1
	GameState.ship_controller.add_critical_effect("firer", {"id": "broadside_obscured", "side": STARBOARD})
	GameState.environment.wind_speed = 4
	var p := calc.preview(_order(STARBOARD, "dismantling"), true)
	assert_eq(_names(p), ["crew_quality", "sections_firing", "guns_dismounted", "broadside_obscured",
		"initial_broadside",
		"two_targets", "plain_sail", "dismantling_shot", "wind_speed_4"])


# --- long range ---

func test_long_range_is_high_only() -> void:
	target.hex_position = _steps(1, 10)
	var p := calc.preview(_order(STARBOARD, "round", "high"))
	assert_true(p.can_fire, p.reason)
	assert_true(p.high_only)
	assert_eq(p.tgf, 6)
	assert_eq(p.bgn, 4)
	assert_false(p.initial_broadside)
	assert_eq(_mod(p, "initial_broadside"), 0)


# --- cannot fire ---

func test_target_ahead_is_out_of_arc() -> void:
	target.hex_position = _n(0)
	var p := calc.preview(_order())
	assert_false(p.can_fire)
	assert_string_contains(p.reason, "arc")


func test_wrong_side_is_out_of_arc() -> void:
	var p := calc.preview(_order(PORT))
	assert_false(p.can_fire)
	assert_string_contains(p.reason, "arc")


func test_blocked_line_of_sight() -> void:
	target.hex_position = _steps(1, 3)
	_make_ship("blocker", 1, _steps(1, 1), 0)
	_make_ship("blocker2", 1, _steps(1, 2), 0)
	var p := calc.preview(_order())
	assert_false(p.can_fire)
	assert_string_contains(p.reason, "line of sight")


func test_struck_target_cannot_be_fired_on() -> void:
	target.status = ShipState.Status.STRUCK
	assert_false(calc.preview(_order()).can_fire)


func test_struck_firer_cannot_fire() -> void:
	firer.status = ShipState.Status.STRUCK
	assert_false(calc.preview(_order()).can_fire)


func test_destroyed_target_cannot_be_fired_on() -> void:
	target.status = ShipState.Status.DESTROYED
	var p := calc.preview(_order())
	assert_false(p.can_fire)
	assert_string_contains(p.reason, "destroyed")


func test_destroyed_firer_cannot_fire_and_has_no_eligible_shots() -> void:
	firer.status = ShipState.Status.DESTROYED
	assert_false(calc.preview(_order()).can_fire)
	assert_eq(calc.eligible_shots(firer.ship_id).size(), 0)


func test_same_player_cannot_fire() -> void:
	target.ship.player_id = 0
	assert_false(calc.preview(_order()).can_fire)


# --- rake ---

func test_stern_rake_at_close_range() -> void:
	# Target bow (0,0) facing E, stern (-1,0). Firer bow (-2,0) directly astern, facing SE.
	target.hex_position = Vector2i.ZERO
	target.facing = 0
	firer.hex_position = _steps(3, 2)
	firer.facing = 1
	# Only the bow battery bears (the stern battery's port arc misses the target).
	var p := calc.preview(_battery("bow", PORT))
	assert_true(p.can_fire, p.reason)
	assert_eq(p.rake, "stern")
	assert_eq(_mod(p, "rake"), 4)


func test_no_rake_at_range_six() -> void:
	target.hex_position = Vector2i.ZERO
	target.facing = 0
	# Firer bow (-7,0): six hexes from the target's stern (-1,0).
	firer.hex_position = _steps(3, 7)
	firer.facing = 1
	var p := calc.preview(_battery("bow", PORT))
	assert_true(p.can_fire, p.reason)
	assert_eq(_mod(p, "rake"), 0)
	assert_eq(p.rake, "")


# --- table edges ---

func test_many_dismounted_guns_gives_negative_mgn_but_can_fire() -> void:
	firer.guns_dismounted[STARBOARD] = 40
	var p := calc.preview(_order())
	assert_true(p.can_fire)
	assert_lt(p.mgn, 0)


func test_no_sailor_sections_cannot_fire() -> void:
	firer.crew_count = [0, 0, 0, 0] as Array[int]
	assert_false(calc.preview(_order()).can_fire)


func test_zero_gun_factors_cannot_fire() -> void:
	firer.ship.gun_factors = {"lg": 0, "mg": 0, "cr": 0}
	var p := calc.preview(_order())
	assert_false(p.can_fire)
	assert_eq(p.tgf, 0)


# --- eligible_shots / any_eligible_shot ---

func test_eligible_shots_lists_starboard_target() -> void:
	# Both batteries bear: the full broadside and each battery alone.
	var shots := calc.eligible_shots("firer")
	assert_eq(shots.size(), 3)
	assert_eq(shots.map(func(s): return s.order.battery), ["full", "bow", "stern"])
	for shot in shots:
		assert_eq(shot.order.side, STARBOARD)
		assert_eq(shot.order.target_id, "target")
		assert_eq(shot.order.aim, "low")
	assert_true(calc.any_eligible_shot())


func test_eligible_shots_offer_the_bearing_battery_when_full_cannot_fire() -> void:
	# Target bow (0,3) facing SE, stern (0,2): only the bow battery bears.
	target.hex_position = Vector2i(0, 3)
	target.facing = 1
	var shots := calc.eligible_shots("firer")
	assert_eq(shots.size(), 1)
	assert_eq(shots[0].order.battery, "bow")
	assert_eq(shots[0].batteries, 1)


func test_eligible_shots_use_high_aim_at_long_range() -> void:
	target.hex_position = _steps(1, 10)
	var shots := calc.eligible_shots("firer")
	assert_eq(shots.size(), 3)
	for shot in shots:
		assert_eq(shot.order.aim, "high")


func test_no_eligible_shot_when_out_of_range() -> void:
	target.hex_position = _steps(1, 16)
	assert_eq(calc.eligible_shots("firer").size(), 0)
	assert_false(calc.any_eligible_shot())


# --- validate_orders ---

func test_validate_valid_order() -> void:
	var orders: Array[GunneryTypes.FireOrder] = [_order()]
	assert_eq(calc.validate_orders(0, orders), "")


func test_validate_duplicate_side() -> void:
	var orders: Array[GunneryTypes.FireOrder] = [_order(), _order()]
	assert_ne(calc.validate_orders(0, orders), "")


func test_validate_enemy_ship() -> void:
	var orders: Array[GunneryTypes.FireOrder] = [_order()]
	assert_ne(calc.validate_orders(1, orders), "")


func test_validate_low_aim_at_long_range() -> void:
	target.hex_position = _steps(1, 12)
	var orders: Array[GunneryTypes.FireOrder] = [_order(STARBOARD, "round", "low")]
	assert_ne(calc.validate_orders(0, orders), "")


func test_validate_out_of_arc() -> void:
	var orders: Array[GunneryTypes.FireOrder] = [_order(PORT)]
	assert_ne(calc.validate_orders(0, orders), "")


func test_validate_bad_aim_and_ammo() -> void:
	var orders: Array[GunneryTypes.FireOrder] = [_order(STARBOARD, "round", "sideways")]
	assert_ne(calc.validate_orders(0, orders), "")
	orders = [_order(STARBOARD, "grape", "low")]
	assert_ne(calc.validate_orders(0, orders), "")


# --- two-hex geometry: batteries, LOS exclusions, half broadside ---

func test_full_broadside_has_two_batteries() -> void:
	var p := calc.preview(_order())
	assert_true(p.can_fire, p.reason)
	assert_eq(p.batteries, 2)
	assert_eq(_mod(p, "half_broadside"), 0)


func test_range_uses_closest_hexes() -> void:
	# Target bow (-2,5) facing SE, stern (-2,4). Bow to bow is 5; firer stern to target stern is 4.
	target.hex_position = Vector2i(-2, 5)
	target.facing = 1
	var p := calc.preview(_order())
	assert_true(p.can_fire, p.reason)
	assert_eq(p.range_hexes, 4)


func test_target_own_stern_does_not_block() -> void:
	# Target bow (0,3) facing SE, stern (0,2). The bow battery's LOS to the target's bow runs
	# through the target's own stern hex.
	target.hex_position = Vector2i(0, 3)
	target.facing = 1
	assert_eq(target.stern_hex(), Vector2i(0, 2))
	var p := calc.preview(_battery("bow"))
	assert_true(p.can_fire, p.reason)


# No test that the firer's own hexes do not block its lines of sight (7.B.7): that cannot arise. A
# battery fires only into the 60-120 degree wedge off its bow, and the firer's other hex lies dead
# ahead or astern of it, so no line of sight from either battery ever passes through it. The
# target's own hexes can block, and are excluded: test_target_own_stern_does_not_block.


func test_one_battery_bears_gives_half_broadside() -> void:
	# Target bow (0,3) facing SE, stern (0,2): in the bow battery's arc, outside the stern battery's.
	target.hex_position = Vector2i(0, 3)
	target.facing = 1
	var p := calc.preview(_battery("bow"))
	assert_true(p.can_fire, p.reason)
	assert_eq(p.batteries, 1)
	assert_eq(_mod(p, "half_broadside"), -8)


func test_half_broadside_at_two_targets_takes_only_two_target_modifier() -> void:
	# 7.C.12g: a half broadside fired while firing at two targets takes -12, not -20.
	target.hex_position = Vector2i(0, 3)
	target.facing = 1
	var p := calc.preview(_battery("bow"), true)
	assert_true(p.can_fire, p.reason)
	assert_eq(p.batteries, 1)
	assert_eq(_mod(p, "half_broadside"), 0)
	assert_eq(_mod(p, "two_targets"), -12)


func test_struck_ship_blocks_los_with_both_hexes() -> void:
	target.hex_position = Vector2i(-2, 4)
	assert_eq(calc.preview(_order()).batteries, 2, "setup: full broadside without the hulk")
	# A struck ship whose stern (-1,2) sits on the bow battery's LOS to the target's bow.
	var hulk := _make_ship("hulk", 1, Vector2i(0, 2), 0)
	hulk.status = ShipState.Status.STRUCK
	assert_eq(hulk.stern_hex(), Vector2i(-1, 2))
	assert_eq(calc.preview(_order()).reason, "only the stern battery bears: a full broadside needs both")
	assert_false(calc.preview(_battery("bow")).can_fire, "the hulk blocks the bow battery")
	var p := calc.preview(_battery("stern"))
	assert_true(p.can_fire, p.reason)
	assert_eq(p.batteries, 1)
	assert_eq(_mod(p, "half_broadside"), -8)


func test_destroyed_ship_blocks_los_with_both_hexes() -> void:
	# As the struck hulk above: the wreck's stern (-1,2) blocks the bow battery (spec Q2).
	target.hex_position = Vector2i(-2, 4)
	var wreck := _make_ship("wreck", 1, Vector2i(0, 2), 0)
	wreck.status = ShipState.Status.DESTROYED
	assert_false(calc.preview(_battery("bow")).can_fire, "the wreck blocks the bow battery")
	assert_true(calc.preview(_battery("stern")).can_fire)


# --- battery fire orders (7.B.1, 7.C.12f/g) ---

## Firer bow (0,0) facing E, stern (-1,0). X bow (0,3) facing SE (stern (0,2)) is covered only
## by the starboard bow battery; Y bow (-4,3) facing SW (stern (-3,2)) only by the starboard stern
## battery.
func _place_split_targets() -> void:
	target.hex_position = Vector2i(0, 3)
	target.facing = 1
	var y := _make_ship("y", 1, Vector2i(-4, 3), 2)
	assert_eq(y.stern_hex(), Vector2i(-3, 2))


func _orders(list: Array) -> Array[GunneryTypes.FireOrder]:
	var typed: Array[GunneryTypes.FireOrder] = []
	for o in list:
		typed.append(o)
	return typed


func test_full_requires_both_batteries() -> void:
	target.hex_position = Vector2i(0, 3)
	target.facing = 1
	var p := calc.preview(_battery("full"))
	assert_false(p.can_fire)
	assert_eq(p.reason, "only the bow battery bears: a full broadside needs both")
	assert_false(calc.preview(_battery("stern")).can_fire, "the stern battery does not bear")
	assert_true(calc.preview(_battery("bow")).can_fire)


func test_bow_battery_alone_is_half_broadside() -> void:
	# Abeam target: both batteries bear, but firing only the bow battery is a half broadside.
	var full := calc.preview(_battery("full"))
	var bow := calc.preview(_battery("bow"))
	assert_true(bow.can_fire, bow.reason)
	assert_eq(bow.batteries, 1)
	assert_eq(_mod(bow, "half_broadside"), -8)
	assert_eq(bow.tgf, full.tgf, "gun factors are the full side's")
	assert_eq(bow.mgn, full.mgn - 8)
	var stern := calc.preview(_battery("stern"))
	assert_eq(_mod(stern, "half_broadside"), -8)


func test_split_side_two_targets() -> void:
	# Ruling (7.C.12g): with two targets only the two-target modifier applies, not the -8.
	_place_split_targets()
	var bow := _battery("bow", STARBOARD, "target")
	var stern := _battery("stern", STARBOARD, "y")
	assert_eq(calc.validate_orders(0, _orders([bow, stern])), "")
	assert_eq(GunneryCalculator.target_count("firer", [bow, stern]), 2)
	for order in [bow, stern]:
		var p := calc.preview(order, true)
		assert_true(p.can_fire, p.reason)
		assert_eq(p.batteries, 1)
		assert_eq(_mod(p, "two_targets"), -12)
		assert_eq(_mod(p, "half_broadside"), 0)
	# Fired alone (one target), the same battery shot takes the -8 instead.
	assert_eq(_mod(calc.preview(bow), "half_broadside"), -8)


func test_three_targets_refused() -> void:
	_place_split_targets()
	_make_ship("z", 1, Vector2i(0, -2), 0)
	var orders := _orders([_battery("bow", STARBOARD, "target"), _battery("stern", STARBOARD, "y"),
			_battery("full", PORT, "z")])
	assert_eq(calc.validate_orders(0, orders), "more than two targets")


func test_battery_used_twice_refused() -> void:
	assert_eq(calc.validate_orders(0, _orders([_battery("full"), _battery("bow")])), "battery fired twice")
	assert_eq(calc.validate_orders(0, _orders([_battery("stern"), _battery("stern")])), "battery fired twice")
	assert_eq(calc.validate_orders(0, _orders([_battery("full"), _battery("full")])), "battery fired twice")


func test_both_batteries_at_one_target_must_be_declared_full() -> void:
	var reason := calc.validate_orders(0, _orders([_battery("bow"), _battery("stern")]))
	assert_eq(reason, "ship firer fires both batteries of one side at target: declare a full broadside")


func test_unknown_battery_refused() -> void:
	var order := _battery("middle")
	assert_eq(calc.preview(order).reason, "unknown battery 'middle'")
	assert_eq(calc.validate_orders(0, _orders([order])), "unknown battery 'middle'")


func test_target_count_counts_distinct_targets() -> void:
	var port := _battery("full", PORT, "target")
	var starboard := _battery("full", STARBOARD, "target")
	assert_eq(GunneryCalculator.target_count("firer", [port, starboard]), 1)
	assert_eq(GunneryCalculator.target_count("other", [port, starboard]), 0)


func test_old_orders_default_full() -> void:
	var order := GunneryTypes.FireOrder.from_dict({"ship_id": "firer", "side": 1, "target_id": "target"})
	assert_eq(order.battery, "full")
	var round_trip := GunneryTypes.FireOrder.from_dict(_battery("stern").to_dict())
	assert_eq(round_trip.battery, "stern")


# --- initial broadside once per side (7.C.10) ---

func _ib(p: GunneryTypes.ShotPreview) -> int:
	return _mod(p, "initial_broadside")


func test_split_side_initial_broadside_goes_to_closer_shot() -> void:
	# X (range 2) is only in the starboard bow arc; Y bow (-6,5) facing SW (range 4) only in the
	# stern arc. The stern shot is listed first; the bonus still goes to the closer bow shot.
	target.hex_position = Vector2i(0, 3)
	target.facing = 1
	_make_ship("y", 1, Vector2i(-6, 5), 2)
	var stern := _battery("stern", STARBOARD, "y")
	var bow := _battery("bow", STARBOARD, "target")
	assert_eq(calc.validate_orders(0, _orders([stern, bow])), "")
	var single_stern := calc.preview(stern, true)
	assert_eq(single_stern.range_hexes, 4)
	assert_eq(_ib(single_stern), DataManager.combat_tables.range_bonus("initial_broadside", 4),
			"alone, the stern shot would earn its own bonus")
	var previews := calc.preview_orders(_orders([stern, bow]))
	assert_eq(previews[1].range_hexes, 2)
	assert_eq(_ib(previews[1]), DataManager.combat_tables.range_bonus("initial_broadside", 2))
	assert_true(previews[1].initial_broadside)
	assert_eq(_ib(previews[0]), 0)
	assert_false(previews[0].initial_broadside)
	assert_eq(previews[0].mgn, single_stern.mgn - _ib(single_stern))


func test_split_side_initial_broadside_tie_goes_to_bow() -> void:
	# X and Y both at range 2: equal bonuses, so the bow battery keeps it.
	_place_split_targets()
	var previews := calc.preview_orders(_orders([_battery("stern", STARBOARD, "y"),
			_battery("bow", STARBOARD, "target")]))
	assert_eq(previews[0].range_hexes, previews[1].range_hexes)
	assert_eq(_ib(previews[0]), 0, "stern battery")
	assert_eq(_ib(previews[1]), DataManager.combat_tables.range_bonus("initial_broadside", 2), "bow battery")


func test_each_side_keeps_its_own_initial_broadside() -> void:
	# Port and starboard are separate broadsides: both first-fire shots keep the bonus.
	_make_ship("z", 1, Vector2i(1, -2), 0)
	var previews := calc.preview_orders(_orders([_battery("full", STARBOARD, "target"),
			_battery("full", PORT, "z")]))
	assert_true(previews[0].can_fire, previews[0].reason)
	assert_true(previews[1].can_fire, previews[1].reason)
	assert_true(previews[0].initial_broadside)
	assert_true(previews[1].initial_broadside)
	assert_eq(_mod(previews[0], "two_targets"), -12)


# --- 1.G.8: the navy using the ship sets the BGN at ranges 11-15 ---

func test_bgn_follows_the_navy_using_the_ship() -> void:
	# 1.G.8c, EXAMPLE 2: a British-built ship sailed by the French uses the French BGN at 11-15.
	target.hex_position = _steps(1, 12)
	var british := calc.preview(_order(STARBOARD, "round", "high"))
	assert_true(british.can_fire, british.reason)
	var tables: CombatTables = DataManager.combat_tables
	assert_eq(british.bgn, tables.basic_gunfire_number(british.tgf, british.range_hexes, false), "built and sailed British")
	firer.navy = "French"
	assert_true(firer.is_french_gunned())
	var french := calc.preview(_order(STARBOARD, "round", "high"))
	assert_eq(french.bgn, tables.basic_gunfire_number(french.tgf, french.range_hexes, true), "the French BGN column")
	assert_ne(french.bgn, british.bgn, "the two columns differ here")
	firer.navy = ""
	firer.ship.nationality = "French"
	firer.navy = "British"
	assert_false(firer.is_french_gunned(), "a French-built ship sailed by the British uses the British BGN")


# --- 7.B.10-12: friendly ships make blocking hexes ---
# Firer bow (0,0) facing E, stern (-1,0). A ship at bow (-2,5) facing W, stern (-1,5), is at range 5
# in the starboard arc. The target, bow (-4,8) facing E, stern (-5,8), lies at range 8 beyond it.
# The lines from each battery to the target's hexes miss the ship's own hexes; each battery has one
# that crosses a hex beside the ship at range 5 or more, e.g. (-3,6) on the bow battery's line to
# the target's bow.

func _blocking_fixture(friend_player: int) -> ShipState:
	target.hex_position = Vector2i(-4, 8)
	target.facing = 0
	return _make_ship("friend", friend_player, Vector2i(-2, 5), 3)


func test_preview_names_blocking_friend() -> void:
	# 7.B.10a/c: a friend at medium range blocks the hexes beside it beyond itself; lines of sight
	# through them are blocked.
	var friend := _blocking_fixture(0)
	assert_eq(calc.preview(_order()).reason, "Blocked by friendly ship %s" % friend.ship_name)
	assert_eq(calc.preview(_battery("bow")).reason, "Blocked by friendly ship %s" % friend.ship_name)


func test_struck_friend_still_blocks() -> void:
	# 7.B.10 counts every friendly ship; a struck one is still there.
	var friend := _blocking_fixture(0)
	friend.status = ShipState.Status.STRUCK
	assert_eq(calc.preview(_order()).reason, "Blocked by friendly ship %s" % friend.ship_name)


func test_enemy_ship_makes_no_blocking_hexes() -> void:
	# 7.B.10: only friendly ships make blocking hexes; an enemy blocks just its own hexes (7.B.7).
	_blocking_fixture(1)
	var p := calc.preview(_order())
	assert_true(p.can_fire, p.reason)
	assert_eq(p.range_hexes, 8)
