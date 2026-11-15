extends GutTest
## Blocked wind (Close Action 5.G). Wind from W (direction 3) blows towards E, so the hex
## directly to windward of a hex is its western neighbour.

const WIND_FROM_W := 3


func _ship(id: String, bow: Vector2i, facing: int, sail: String = "FS", rigging: Array[int] = [5, 5, 5, 5]) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({"ship_id": id, "speed_type": "F/F", "maneuverability": "b"})  # ship_id comes from the Ship
	s.hex_position = bow
	s.facing = facing
	s.sail_state = sail
	s.rigging_current_hp = rigging.duplicate()
	return s


func _blocked(target: ShipState, others: Array) -> bool:
	var ships: Array = [target]
	ships.append_array(others)
	return BlockedWind.is_blocked(target.hex_position, target.facing, WIND_FROM_W, ships, target.ship_id)


# --- WF=R: only the one hex directly to windward (5.G.2) -------------------------------------

func test_running_ship_blocked_by_one_ship_astern_to_windward() -> void:
	# Running E: bow (5,5), stern (4,5). Windward of the stern is (3,5); the bow's is its own stern.
	var target := _ship("t", Vector2i(5, 5), 0)
	var blocker := _ship("b", Vector2i(3, 5), 0, "FS")  # bow (3,5), stern (2,5)
	assert_true(_blocked(target, [blocker]), "5.G.2: WF=R needs only the one hex to windward")


func test_running_ship_never_blocks_its_own_wind() -> void:
	var target := _ship("t", Vector2i(5, 5), 0)
	assert_false(_blocked(target, []), "5.G.2: a ship in WF=R never blocks its own wind")


func test_furled_ship_does_not_block() -> void:
	var target := _ship("t", Vector2i(5, 5), 0)
	var blocker := _ship("b", Vector2i(3, 5), 0, "NS")
	assert_false(_blocked(target, [blocker]), "5.G.2: furled ships do not block wind")


func test_dismasted_ship_does_not_block() -> void:
	var target := _ship("t", Vector2i(5, 5), 0)
	var blocker := _ship("b", Vector2i(3, 5), 0, "FS", [0, 0, 0, 0])
	assert_false(_blocked(target, [blocker]), "5.G.2 / Diagram 12: a dismasted ship does not block")


# --- WF=C and WF=B: both hexes directly to windward (5.G.2) ---------------------------------

func test_broad_reach_needs_both_windward_hexes() -> void:
	# Heading NE (5) with wind from W is a broad reach. Bow (5,5), stern (4,6): windward hexes are
	# (4,5) and (3,6).
	var target := _ship("t", Vector2i(5, 5), 5)
	var one := _ship("one", Vector2i(4, 5), 1, "MS")  # bow (4,5), stern (4,4): covers (4,5) only
	assert_false(_blocked(target, [one]), "One of two windward hexes is not enough at WF=B")
	var second := _ship("second", Vector2i(3, 6), 1, "PS")  # bow (3,6), stern (3,5)
	assert_true(_blocked(target, [one, second]), "Both windward hexes held by ships at FS or above")


func test_one_parallel_ship_can_hold_both_windward_hexes() -> void:
	var target := _ship("t", Vector2i(5, 5), 5)  # broad reach, windward (4,5) and (3,6)
	var parallel := _ship("p", Vector2i(4, 5), 5, "FS")  # bow (4,5), stern (3,6)
	assert_true(_blocked(target, [parallel]), "5.G.2: 'another ship or ships'")


func test_close_hauled_needs_both_windward_hexes() -> void:
	# Heading NW (4) with wind from W is close-hauled. Bow (5,5), stern (5,6): windward (4,5), (4,6).
	var target := _ship("t", Vector2i(5, 5), 4)
	var half := _ship("h", Vector2i(4, 5), 0, "FS")  # bow (4,5), stern (3,5)
	assert_false(_blocked(target, [half]))
	var full := _ship("f", Vector2i(4, 5), 4, "FS")  # bow (4,5), stern (4,6)
	assert_true(_blocked(target, [full]))


func test_blocker_must_be_at_fs_or_higher_in_every_windward_hex() -> void:
	# "occupied by another ship or ships, who are all at sail state FS or higher"
	var target := _ship("t", Vector2i(5, 5), 4)  # windward (4,5), (4,6)
	var a := _ship("a", Vector2i(4, 5), 0, "FS")  # bow (4,5), stern (3,5)
	var b := _ship("b", Vector2i(4, 6), 0, "NS")  # bow (4,6), stern (3,6), furled
	assert_false(_blocked(target, [a, b]))


# --- 5.G.3: MA -1, never to 0 ------------------------------------------------------------------

func test_blocked_wind_reduces_ma_by_one_but_never_to_zero() -> void:
	assert_eq(BlockedWind.apply(4, true), 3, "5.G.3: MA reduced by 1")
	assert_eq(BlockedWind.apply(1, true), 1, "5.G.3: never reduced to 0")
	assert_eq(BlockedWind.apply(0, true), 0, "MA 0 stays 0")
	assert_eq(BlockedWind.apply(4, false), 4, "Not blocked: unchanged")


func test_ship_controller_movement_allowance_includes_blocked_wind() -> void:
	DataManager.load_movement_allowance_table()
	var saved_env = GameState.environment
	var saved_ships: Dictionary = GameState.ships.duplicate()
	GameState.ships.clear()
	var env := EnvironmentState.new()
	env.wind_direction = WIND_FROM_W
	env.wind_speed = 3
	GameState.environment = env
	var target := _ship("t", Vector2i(5, 5), 0, "FS")
	GameState.ships["t"] = target
	var free_ma: int = GameState.ship_controller.get_movement_allowance("t")
	var blocker := _ship("b", Vector2i(3, 5), 0, "FS")
	GameState.ships["b"] = blocker
	var blocked_ma: int = GameState.ship_controller.get_movement_allowance("t")
	GameState.ships = saved_ships
	GameState.environment = saved_env
	assert_gt(free_ma, 1, "Fixture: the table MA is above 1")
	assert_eq(blocked_ma, free_ma - 1, "5.G.3: blocked wind costs 1 MA")
