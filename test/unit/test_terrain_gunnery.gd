extends GutTest
## Terrain and gunnery: land blocks line of sight (7.B.7-9), shallows do not, an aground ship
## holds its guns (13.G.3) but can be fired on and may use its marines.

const STARBOARD := 1

var calc: GunneryCalculator
var firer: ShipState
var target: ShipState
var _saved_scenario: Dictionary


func before_each() -> void:
	_saved_scenario = GameState.active_scenario
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	calc = GunneryCalculator.new(GameState)
	GameState.active_scenario = {}
	firer = _make_ship("firer", 0, Vector2i.ZERO, 0)
	target = _make_ship("target", 1, Vector2i(0, 4), 0)


func after_each() -> void:
	GameState.active_scenario = _saved_scenario


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
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.crew_quality = "D"
	GameState.ships[id] = state
	GameState.ships_by_side[player].append(id)
	return state


func _order() -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "firer"
	order.side = STARBOARD
	order.target_id = "target"
	order.ammo = "round"
	order.aim = "low"
	order.battery = "full"
	return order


## Every hex within 6 of the firer that neither ship holds (so every line between them crosses one).
func _fill() -> Array:
	var out: Array = []
	var held: Array = firer.occupied_hexes() + target.occupied_hexes()
	for q in range(-6, 7):
		for r in range(-6, 7):
			if not held.has(Vector2i(q, r)):
				out.append([q, r])
	return out


func test_baseline_shot_is_accepted() -> void:
	var p := calc.preview(_order())
	assert_true(p.can_fire, p.reason)


func test_land_blocks_gunfire_line_of_sight() -> void:
	GameState.active_scenario = {"terrain": {"land": _fill()}}
	var p := calc.preview(_order())
	assert_false(p.can_fire)
	assert_eq(p.reason, "no line of sight to target")


func test_shallow_does_not_block_line_of_sight() -> void:
	GameState.active_scenario = {"terrain": {"shallow": [{"name": "bar", "base": 10, "hexes": _fill()}]}}
	var p := calc.preview(_order())
	assert_true(p.can_fire, p.reason)


func test_aground_ship_cannot_fire_guns() -> void:
	firer.aground = true
	var p := calc.preview(_order())
	assert_false(p.can_fire)
	assert_string_contains(p.reason, "13.G.3")
	assert_eq(calc.eligible_shots("firer").size(), 0)


func test_aground_ship_can_be_fired_on_and_use_marines() -> void:
	target.aground = true
	var p := calc.preview(_order())
	assert_true(p.can_fire, p.reason)
	target.aground = false
	firer.aground = true
	target.hex_position = Vector2i(0, 1)
	firer.marine_count = 2
	var m := GameState.marine_fire_resolver.preview("firer", "target")
	assert_true(m["can_fire"], str(m["reason"]))
