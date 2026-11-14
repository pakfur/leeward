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


func _order(side: int = STARBOARD, ammo: String = "round", aim: String = "low") -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "firer"
	order.side = side
	order.target_id = "target"
	order.ammo = ammo
	order.aim = aim
	return order


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
	GameState.environment.wind_speed = 4
	var p := calc.preview(_order(STARBOARD, "dismantling"), true)
	assert_eq(_names(p), ["crew_quality", "sections_firing", "guns_dismounted", "initial_broadside",
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


func test_same_player_cannot_fire() -> void:
	target.ship.player_id = 0
	assert_false(calc.preview(_order()).can_fire)


# --- rake ---

func test_stern_rake_at_close_range() -> void:
	target.hex_position = Vector2i.ZERO
	target.facing = 0
	firer.hex_position = _n(3)
	firer.facing = 1
	var p := calc.preview(_order(PORT))
	assert_true(p.can_fire, p.reason)
	assert_eq(p.rake, "stern")
	assert_eq(_mod(p, "rake"), 4)


func test_no_rake_at_range_six() -> void:
	target.hex_position = Vector2i.ZERO
	target.facing = 0
	firer.hex_position = _steps(3, 6)
	firer.facing = 1
	var p := calc.preview(_order(PORT))
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
	var shots := calc.eligible_shots("firer")
	assert_eq(shots.size(), 1)
	assert_eq(shots[0].order.side, STARBOARD)
	assert_eq(shots[0].order.target_id, "target")
	assert_eq(shots[0].order.aim, "low")
	assert_true(calc.any_eligible_shot())


func test_eligible_shots_use_high_aim_at_long_range() -> void:
	target.hex_position = _steps(1, 10)
	var shots := calc.eligible_shots("firer")
	assert_eq(shots.size(), 1)
	assert_eq(shots[0].order.aim, "high")


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
