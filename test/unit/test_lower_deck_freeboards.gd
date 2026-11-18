extends GutTest
## Lower-deck guns at freeboards 3-6 (7.F.2).

var calc: GunneryCalculator
var _saved_ships: Dictionary
var _saved_by_side: Dictionary
var _saved_env: EnvironmentState


func before_each() -> void:
	_saved_ships = GameState.ships.duplicate()
	_saved_by_side = GameState.ships_by_side.duplicate(true)
	_saved_env = GameState.environment
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	_set_sea(1)
	calc = GunneryCalculator.new(GameState)


func after_each() -> void:
	GameState.ships = _saved_ships
	GameState.ships_by_side = _saved_by_side
	GameState.environment = _saved_env


func _set_sea(sea: int) -> void:
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 2
	env.sea_state = sea
	GameState.environment = env


func _make_ship(id: String, type_id: String, side: int, hex: Vector2i, facing: int) -> ShipState:
	var def := DataManager.get_ship_definition(type_id)
	var s := ShipState.new()
	s.ship = def
	s.ship_id = id
	s.hex_position = hex
	s.facing = facing
	s.sail_state = "MS"
	s.crew_quality = "D"
	s.rigging_current_hp = def.rigging_hp.duplicate()
	s.hull_current_hp = def.hull_hp.duplicate()
	s.crew_count = def.crew_count.duplicate()
	s.marine_count = def.marine_count
	s.controller_side = side  # the shared definition stays untouched
	GameState.ships[id] = s
	GameState.ships_by_side[side].append(id)
	return s


func test_every_freeboard_against_every_sea() -> void:
	var cases := [["br_44_diomede", 3, -4], ["br_98l", 3, -3], ["br_74", 4, -5],
			["br_32", 5, -7], ["sp_34", 5, -8], ["br_38", 6, -7]]
	for c in cases:
		var s := _make_ship("s_" + c[0], c[0], 0, Vector2i.ZERO, 1)
		assert_eq(s.ship.freeboard, c[1], "%s freeboard" % c[0])
		assert_eq(s.ship.lower_deck_modifier, c[2], "%s LDGM" % c[0])
		for sea in range(0, 6):
			var starboard_expected: int = c[2] if sea > 0 and sea >= c[1] else 0
			var port_expected: int = c[2] if sea > c[1] else 0
			assert_eq(FireRules.lower_deck_modifier(s, 1, sea, 0), starboard_expected,
					"%s starboard sea %d" % [c[0], sea])
			assert_eq(FireRules.lower_deck_modifier(s, 0, sea, 0), port_expected,
					"%s port sea %d" % [c[0], sea])


func _diomede_order() -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = "diomede"
	order.side = 1
	order.target_id = "target"
	order.ammo = "round"
	order.aim = "low"
	order.battery = "full"
	return order


func _mod(p: GunneryTypes.ShotPreview, name: String) -> int:
	for m in p.modifiers:
		if m["name"] == name:
			return m["value"]
	return 0


func test_diomede_sea_three_preview() -> void:
	_make_ship("diomede", "br_44_diomede", 0, Vector2i.ZERO, 1)
	_make_ship("target", "br_38", 1, Vector2i(-3, 3), 1)
	_set_sea(3)
	var p := calc.preview(_diomede_order())
	assert_true(p.can_fire, p.reason)
	assert_eq(p.range_hexes, 3)
	assert_eq(_mod(p, "lower_deck_closed"), -4)
	_set_sea(2)
	var p2 := calc.preview(_diomede_order())
	assert_true(p2.can_fire, p2.reason)
	for m in p2.modifiers:
		assert_ne(m["name"], "lower_deck_closed")
