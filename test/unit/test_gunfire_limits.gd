extends GutTest
## 14.E historical gunfire limits (optional): a low aim is forced high on a d6 of 4+ when the crew
## is CQ E, F or G ("crew") or the ship fires to windward at WF C/B ("heel"); one d6 per firing
## ship covers both, rolled before any shot's dice.

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
	GameState.active_scenario = {"optional_rules": {"gunfire_limits": "crew"}}
	_setup_ships()
	resolver = GunneryResolver.new(GameState)


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.active_scenario = _old_scenario
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


## A's bow (0,0) facing E; B abeam of it (starboard), facing W, so B's starboard bears on A.
## Wind from 3 (A at WF R: no leeward side) unless a test sets it.
func _setup_ships(wind_direction: int = 3) -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.wind_direction = wind_direction
	env.sea_state = 1
	GameState.environment = env
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	a = _make_ship("a_ship", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_ship", 1, Vector2i(-1, 1), 3)


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


func _order(ship_id: String, target_id: String, aim: String = "low") -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = STARBOARD
	order.target_id = target_id
	order.ammo = "round"
	order.aim = aim
	order.battery = "full"
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


func _events(type: int) -> Array[PhaseEvents.PhaseEvent]:
	var out: Array[PhaseEvents.PhaseEvent] = []
	for e in GameState.turn_log.events:
		if e.type == type:
			out.append(e)
	return out


func _fire_of(ship_id: String) -> PhaseEvents.PhaseEvent:
	for e in _events(PhaseEvents.Type.FIRE):
		if e.ship_id == ship_id:
			return e
	return null


func test_fires_to_windward() -> void:
	assert_true(FireRules.fires_to_windward(0, 1, STARBOARD), "WF C, port leeward")
	assert_true(FireRules.fires_to_windward(0, 2, STARBOARD), "WF B")
	assert_false(FireRules.fires_to_windward(0, 5, STARBOARD), "starboard leeward")
	assert_false(FireRules.fires_to_windward(0, 0, STARBOARD), "WF L")
	assert_false(FireRules.fires_to_windward(0, 3, STARBOARD), "WF R")
	assert_false(FireRules.fires_to_windward(0, 1, GunneryTypes.CHASE_BOW), "a chaser")


func test_aim_limits() -> void:
	assert_eq(FireRules.aim_limits("low", false, "E", 1, 0, 0, true, false), ["crew"])
	assert_eq(FireRules.aim_limits("low", false, "D", 1, 0, 0, true, false), [])
	assert_eq(FireRules.aim_limits("low", false, "G", 1, 0, 0, true, false), ["crew"])
	assert_eq(FireRules.aim_limits("low", false, "D", 1, 0, 1, false, true), ["heel"])
	assert_eq(FireRules.aim_limits("low", false, "F", 1, 0, 1, true, true), ["crew", "heel"])
	assert_eq(FireRules.aim_limits("high", false, "G", 1, 0, 1, true, true), [])
	assert_eq(FireRules.aim_limits("low", true, "G", 1, 0, 1, true, true), [], "range 10+")
	assert_eq(FireRules.aim_limits("low", false, "G", 2, 0, 1, false, true), [], "a chaser")


func test_preview_carries_aim_limits() -> void:
	a.crew_quality = "E"
	var calc: GunneryCalculator = GameState.gunnery_calculator
	var p := calc.preview(_order("a_ship", "b_ship"))
	assert_true(p.can_fire)
	assert_eq(p.aim_limits, ["crew"])
	assert_eq(calc.preview(_order("a_ship", "b_ship", "high")).aim_limits, [])
	GameState.active_scenario = {}
	assert_eq(calc.preview(_order("a_ship", "b_ship")).aim_limits, [])


func test_forced_high_on_four() -> void:
	a.crew_quality = "E"
	_dice.queue([4])
	_sixes()
	var order := _order("a_ship", "b_ship")
	_fire([order])
	var fire := _fire_of("a_ship")
	assert_not_null(fire)
	assert_eq(fire.data["aim"], "high")
	assert_eq(fire.data["aim_ordered"], "low")
	assert_eq(fire.data["aim_roll"], 4)
	var forced := _events(PhaseEvents.Type.AIM_FORCED)
	assert_eq(forced.size(), 1)
	assert_eq(forced[0].ship_id, "a_ship")
	assert_eq(forced[0].data["roll"], 4)
	assert_eq(forced[0].data["rules"], ["crew"])
	assert_eq(forced[0].data["sides"], [1])
	assert_eq(forced[0].data["quality"], "E")
	assert_lt(GameState.turn_log.events.find(forced[0]), GameState.turn_log.events.find(fire),
			"logged before the shot")
	assert_eq(order.aim, "low", "the caller's order is not changed")


func test_low_holds_on_three() -> void:
	a.crew_quality = "E"
	_dice.queue([3])
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	var fire := _fire_of("a_ship")
	assert_eq(fire.data["aim"], "low")
	assert_eq(fire.data["aim_roll"], 3)
	assert_eq(_events(PhaseEvents.Type.AIM_FORCED).size(), 0)


func test_forced_high_keeps_mgn() -> void:
	a.crew_quality = "E"
	var expected := GameState.gunnery_calculator.preview(_order("a_ship", "b_ship"))
	_dice.queue([6])
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	assert_eq(_fire_of("a_ship").data["mgn"], expected.mgn)


func test_one_roll_covers_both_rules() -> void:
	GameState.active_scenario = {"optional_rules": {"gunfire_limits": "both"}}
	_setup_ships(1)
	a.crew_quality = "F"
	_dice.queue([5, 2])
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	var forced := _events(PhaseEvents.Type.AIM_FORCED)
	assert_eq(forced.size(), 1)
	assert_eq(forced[0].data["rules"], ["crew", "heel"])
	assert_eq(_fire_of("a_ship").data["d6"], 2, "one aim d6, then the gunnery d6")


func test_rolls_in_firer_order() -> void:
	a.crew_quality = "E"
	b.crew_quality = "E"
	_dice.queue([4, 1])
	_sixes()
	_fire([_order("b_ship", "a_ship"), _order("a_ship", "b_ship")])
	assert_eq(_fire_of("a_ship").data["aim_roll"], 4)
	assert_eq(_fire_of("a_ship").data["aim"], "high")
	assert_eq(_fire_of("b_ship").data["aim_roll"], 1)
	assert_eq(_fire_of("b_ship").data["aim"], "low")

	_setup_ships()
	a.crew_quality = "E"
	b.crew_quality = "E"
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	_dice.queue([1, 4])
	_sixes()
	_fire([_order("b_ship", "a_ship"), _order("a_ship", "b_ship")])
	assert_eq(_fire_of("a_ship").data["aim_roll"], 1)
	assert_eq(_fire_of("a_ship").data["aim"], "low")
	assert_eq(_fire_of("b_ship").data["aim_roll"], 4)
	assert_eq(_fire_of("b_ship").data["aim"], "high")


func test_no_aim_roll_when_off() -> void:
	GameState.active_scenario = {}
	a.crew_quality = "G"
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	var fire := _fire_of("a_ship")
	assert_false(fire.data.has("aim_roll"))
	assert_eq(fire.data["d6"], 6, "the first die is the gunnery die")


func test_aim_forced_text() -> void:
	var log := PhaseEvents.PhaseLog.new()
	var ev := log.add(PhaseEvents.Type.AIM_FORCED, PHASE, "a_ship",
			{"roll": 5, "rules": ["crew", "heel"], "sides": [1], "quality": "E"})
	var text := ev.to_text({"a_ship": "HMS A"})
	assert_string_contains(text, "cannot hold their aim low")
	assert_string_contains(text, "rolled 5")
	assert_string_contains(text, "crew CQ E, firing to windward")
