extends GutTest
## 14.D fatigue (optional): a ship's firing turns are counted (public), and from the 6th the
## gunfire number drops by 1, from the 16th by 2, and so on; chasers take it too.

const STARBOARD := 1
const PHASE := 4

var resolver: GunneryResolver
var a: ShipState
var b: ShipState
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_scenario: Dictionary
var _dice: ScriptedDice


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_scenario = GameState.active_scenario
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.active_scenario = {"optional_rules": {"fatigue": true}}
	_setup_ships()
	resolver = GunneryResolver.new(GameState)


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.active_scenario = _old_scenario
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


## A's bow (0,0) facing E; B abeam of it (starboard) unless moved.
func _setup_ships(b_facing: int = 3, b_hex: Vector2i = Vector2i(-1, 1)) -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	a = _make_ship("a_ship", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_ship", 1, b_hex, b_facing)


func _make_ship(id: String, player: int, hex: Vector2i, facing: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6], "crew_count": [3, 3, 3, 3],
		"marine_count": 2, "gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex
	state.facing = facing
	state.sail_state = "MS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.marine_count = 2
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_side[player].append(id)
	return state


func _order(ship_id: String, target_id: String, battery: String = "full",
		side: int = STARBOARD) -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = side
	order.target_id = target_id
	order.ammo = "round"
	order.aim = "low"
	order.battery = battery
	return order


func _fire(orders: Array) -> void:
	var typed: Array[GunneryTypes.FireOrder] = []
	for o in orders:
		typed.append(o)
	resolver.resolve(typed, PHASE)


func _sixes() -> void:
	var values: Array = []
	values.resize(200)
	values.fill(6)
	_dice.queue(values)


func _fatigue_of(p: GunneryTypes.ShotPreview) -> Variant:
	for m in p.modifiers:
		if m["name"] == "fatigue":
			return m["value"]
	return null


func _preview() -> GunneryTypes.ShotPreview:
	return GameState.gunnery_calculator.preview(_order("a_ship", "b_ship"))


func test_fatigue_penalty_steps() -> void:
	assert_eq(FireRules.fatigue_penalty(0), 0)
	assert_eq(FireRules.fatigue_penalty(4), 0)
	assert_eq(FireRules.fatigue_penalty(5), 1)
	assert_eq(FireRules.fatigue_penalty(14), 1)
	assert_eq(FireRules.fatigue_penalty(15), 2)
	assert_eq(FireRules.fatigue_penalty(24), 2)
	assert_eq(FireRules.fatigue_penalty(25), 3)


func test_preview_takes_fatigue() -> void:
	a.gunfire_turns = 4
	var p4 := _preview()
	assert_null(_fatigue_of(p4))
	a.gunfire_turns = 5
	var p5 := _preview()
	assert_eq(_fatigue_of(p5), -1)
	assert_eq(p5.mgn, p4.mgn - 1)
	a.gunfire_turns = 15
	assert_eq(_fatigue_of(_preview()), -2)


func test_no_fatigue_modifier_when_off() -> void:
	GameState.active_scenario = {}
	a.gunfire_turns = 20
	assert_null(_fatigue_of(_preview()))


func test_chaser_takes_fatigue() -> void:
	_setup_ships(0, Vector2i(3, 0))
	a.gunfire_turns = 5
	var p := GameState.gunnery_calculator.preview(
			_order("a_ship", "b_ship", GunneryTypes.BATTERY_CHASE, GunneryTypes.CHASE_BOW))
	assert_true(p.can_fire)
	assert_eq(_fatigue_of(p), -1)


func test_resolve_counts_one_turn_per_firing_ship() -> void:
	_sixes()
	var orders := [_order("a_ship", "b_ship"), _order("b_ship", "a_ship")]
	_fire(orders)
	assert_eq(a.gunfire_turns, 1)
	assert_eq(b.gunfire_turns, 1)
	_fire(orders)
	assert_eq(a.gunfire_turns, 2)
	assert_eq(b.gunfire_turns, 2)


func test_two_shots_count_once() -> void:
	var c := _make_ship("c_ship", 1, Vector2i(3, 0), 0)
	assert_not_null(c)
	_sixes()
	_fire([
		_order("a_ship", "b_ship"),
		_order("a_ship", "c_ship", GunneryTypes.BATTERY_CHASE, GunneryTypes.CHASE_BOW),
	])
	assert_eq(a.gunfire_turns, 1)


func test_count_runs_with_the_switch_off() -> void:
	GameState.active_scenario = {}
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	assert_eq(a.gunfire_turns, 1)


func test_fire_event_mgn_includes_fatigue() -> void:
	a.gunfire_turns = 5
	var expected := _preview()
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	var ev: PhaseEvents.PhaseEvent = null
	for e in GameState.turn_log.events:
		if e.type == PhaseEvents.Type.FIRE and e.ship_id == "a_ship":
			ev = e
	assert_not_null(ev)
	assert_eq(ev.data["mgn"], expected.mgn)
	assert_true(ev.data["modifiers"].any(
			func(m): return m["name"] == "fatigue" and m["value"] == -1))


func test_gunfire_turns_serialized() -> void:
	a.gunfire_turns = 7
	assert_eq(ShipState.deserialize(a.serialize()).gunfire_turns, 7)


func test_chaser_only_turn_counts() -> void:
	_setup_ships(0, Vector2i(3, 0))
	_sixes()
	_fire([_order("a_ship", "b_ship", GunneryTypes.BATTERY_CHASE, GunneryTypes.CHASE_BOW)])
	assert_eq(a.gunfire_turns, 1, "a turn of chaser fire alone counts")
