extends GutTest
## Medium guns (1.G.7), class 4 tables and one-box sections, from the Ship Data Chart types.

const STARBOARD := 1

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
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	calc = GunneryCalculator.new(GameState)


func after_each() -> void:
	GameState.ships = _saved_ships
	GameState.ships_by_side = _saved_by_side
	GameState.environment = _saved_env


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


func _starboard_high(firer_id: String, target_id: String) -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = firer_id
	order.side = STARBOARD
	order.target_id = target_id
	order.ammo = "round"
	order.aim = "high"
	order.battery = "full"
	return order


func _diomede_preview(r: int) -> GunneryTypes.ShotPreview:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	_make_ship("diomede", "br_44_diomede", 0, Vector2i.ZERO, 0)
	_make_ship("target", "br_38", 1, HexGrid.DIRECTIONS[1] * r, 0)
	return calc.preview(_starboard_high("diomede", "target"))


func test_diomede_medium_guns_by_range() -> void:
	var p6 := _diomede_preview(6)
	assert_true(p6.can_fire, p6.reason)
	assert_eq(p6.tgf, 7)
	assert_eq(p6.bgn, 12)
	var p11 := _diomede_preview(11)
	assert_true(p11.can_fire, p11.reason)
	assert_eq(p11.tgf, 6)
	assert_eq(p11.bgn, 3)
	var p13 := _diomede_preview(13)
	assert_false(p13.can_fire)
	assert_string_contains(p13.reason, "cannot fire at this range")


func test_class_4_movement_tables() -> void:
	assert_eq(DataManager.get_movement_allowance("C/S", 2, "B", "ms", 4), 7)
	assert_eq(DataManager.get_movement_allowance("C/F", 2, "B", "ps", 4), 10)
	assert_eq(DataManager.get_speed_change("acceleration", "D"), 3)
	assert_eq(DataManager.get_speed_change("deceleration", "D"), 4)


func test_class_4_table_rows() -> void:
	assert_eq(DataManager.combat_tables.drift_class_drm(4), 2)
	assert_eq(DataManager.combat_tables.prize_minimum(4), 1)


func test_one_box_sections_fire() -> void:
	var firer := _make_ship("firer", "fr_14_coureur", 0, Vector2i.ZERO, 0)
	_make_ship("target", "br_32", 1, HexGrid.DIRECTIONS[1] * 2, 0)
	assert_eq(GameState.ship_controller.remove_crew_box_from("firer", 0), 0)
	assert_eq(firer.sections_able_to_fire(), 3)
	var p := calc.preview(_starboard_high("firer", "target"))
	assert_true(p.can_fire, p.reason)
	var found := false
	for m in p.modifiers:
		if m["name"] == "sections_firing":
			assert_eq(m["value"], -3)
			found = true
	assert_true(found, "sections_firing modifier present")
	assert_eq(p.tgf, 1)


func test_corvette_point_values() -> void:
	assert_eq(DataManager.get_ship_definition("fr_20_babet").point_value("D", 4), 12.0)
	assert_eq(DataManager.get_ship_definition("fr_14_coureur").point_value("D", 5), 6.0)
