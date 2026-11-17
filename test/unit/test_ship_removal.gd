extends GutTest
## Exploded ships leave the map at the end of the g-t (Close Action 8.G.1f "remove ships"; user
## decision 2026-11-16: not at once). Until END_TURN the wreck blocks as before; afterwards no map
## query sees it, but it stays in GameState.ships and still counts as lost for victory.

const PHASES := TurnPhaseController.GamePhase
const WIND_FROM_W := 3

var pc: TurnPhaseController
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_logs: Dictionary
var _old_env: EnvironmentState
var _old_scenario: Dictionary


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_speed_change_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_turning_table()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_logs = GameState.turn_logs
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	GameState.dice = Dice.new(GameState.rng)
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.turn_logs = {}
	GameState.active_scenario = {}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	env.wind_direction = WIND_FROM_W
	GameState.environment = env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	pc.game_result = {}
	pc.combat_step = TurnPhaseController.CombatStep.NONE


func after_each() -> void:
	pc.game_result = {}
	pc.current_phase = PHASES.SETUP
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.turn_logs = _old_logs
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _make_ship(id: String, player: int, bow: Vector2i, facing: int = 3) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 10, "mg": 0, "cr": 0},
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	state.hex_position = bow
	state.facing = facing
	state.speed = 1
	state.sail_state = "FS"
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	var hull: Array[int] = [5, 5, 5, 6]
	state.hull_current_hp = hull
	var crew: Array[int] = [3, 3, 3, 3]
	state.crew_count = crew
	state.marine_count = 2
	state.crew_quality = "D"
	state.starting_crew_quality = "D"
	state.morale_rating = 4
	GameState.ships[state.ship_id] = state
	GameState.ships_by_player[player].append(state.ship_id)
	return state


func _end_turn(turn: int = 1) -> void:
	pc.current_turn = turn
	GameState.current_turn = turn
	GameState.turn_log.turn = turn
	pc.current_phase = PHASES.POST_COMBAT
	assert_true(pc.player_end_turn(0), "End Turn accepted in POST_COMBAT")


func test_wreck_blocks_until_end_turn_then_is_removed() -> void:
	# 8.G.1f: ships are removed in the end-of-turn step; until then the wreck holds its hexes.
	_make_ship("a", 0, Vector2i(0, 0))
	_make_ship("b", 1, Vector2i(10, 0))
	var wreck := _make_ship("w", 1, Vector2i(5, 3))
	GameState.damage_controller.destroy("w", "test", PHASES.COMBAT_RESOLUTION)
	assert_true(wreck.is_destroyed())
	assert_true(wreck.is_on_map(), "8.G.1f: still on the map until the end of the g-t")
	var before := Occupancy.build(GameState.get_all_ships())
	assert_eq(before.get(wreck.hex_position, ""), "w", "the wreck's bow hex blocks mid-turn")
	assert_eq(before.get(wreck.stern_hex(), ""), "w", "the wreck's stern hex blocks mid-turn")
	_end_turn(1)
	assert_false(wreck.is_on_map(), "8.G.1f: removed at the end of the g-t")
	var after := Occupancy.build(GameState.get_all_ships())
	assert_false(after.has(wreck.hex_position), "a removed wreck holds no hex")
	assert_false(after.has(wreck.stern_hex()), "a removed wreck holds no hex")
	assert_true(GameState.ships.has("w"), "the ship stays in GameState.ships (logs, history)")
	assert_false(GameState.ships_on_map().has(wreck), "ships_on_map() leaves it out")
	assert_eq(GameState.ships_on_map().size(), 2)


func test_removed_ship_no_longer_blocks_los() -> void:
	# 7.B.4 (LOS blocked by a ship) no longer applies once 8.G.1f has removed the wreck.
	var firer := _make_ship("a", 0, Vector2i(0, 0))
	var target := _make_ship("b", 1, Vector2i(6, 0))
	var wreck := _make_ship("w", 1, Vector2i(3, 0))  # bow (3,0), stern (4,0): across the line
	var geometry: FireGeometry = GameState.fire_geometry
	var occupied := Occupancy.build(GameState.get_all_ships(), [firer.ship_id, target.ship_id])
	assert_false(geometry.has_line_of_sight(firer.hex_position, target.hex_position, occupied),
		"a wreck on the map blocks the line")
	GameState.ship_controller.set_status("w", ShipState.Status.DESTROYED)
	GameState.ship_controller.remove_from_map("w")
	occupied = Occupancy.build(GameState.get_all_ships(), [firer.ship_id, target.ship_id])
	assert_true(geometry.has_line_of_sight(firer.hex_position, target.hex_position, occupied),
		"8.G.1f: a removed wreck no longer blocks")
	assert_false(wreck.is_on_map())


func test_removed_ship_no_longer_blocks_wind() -> void:
	# 5.G.2: running E with the wind from W, the one hex to windward of the stern (3,5) is held.
	var target := _make_ship("t", 0, Vector2i(5, 5), 0)   # bow (5,5), stern (4,5)
	var blocker := _make_ship("w", 1, Vector2i(3, 5), 0)  # bow (3,5) at FS
	var ships: Array = GameState.ships.values()
	assert_true(BlockedWind.is_blocked(target.hex_position, target.facing, WIND_FROM_W, ships, "t"),
		"5.G.2: blocked by the ship to windward")
	GameState.ship_controller.remove_from_map("w")
	assert_false(blocker.is_on_map())
	assert_false(BlockedWind.is_blocked(target.hex_position, target.facing, WIND_FROM_W, ships, "t"),
		"8.G.1f: a ship removed from the map blocks no wind")


func test_removed_ship_still_counts_as_lost_for_victory() -> void:
	# 8.G.1f removes the ship from the map only; 12.1: a destroyed ship is lost at full value.
	_make_ship("a", 0, Vector2i(0, 0))
	var wreck := _make_ship("w", 1, Vector2i(5, 3))
	GameState.damage_controller.destroy("w", "test", PHASES.COMBAT_RESOLUTION)
	_end_turn(2)
	assert_false(wreck.is_on_map(), "removed before the victory check")
	assert_false(pc.game_result.is_empty(), "side 1 has no ship left in play")
	assert_eq(pc.game_result["winner"], 0)
	assert_eq(pc.game_result["points"][0], 38.0, "the removed ship is scored lost at full value")


func test_removed_from_map_round_trips() -> void:
	var ship := _make_ship("w", 1, Vector2i(5, 3))
	assert_true(ship.is_on_map(), "a new ship is on the map")
	assert_true(ShipState.deserialize(ship.serialize()).is_on_map())
	GameState.ship_controller.remove_from_map("w")
	var data := ship.serialize()
	assert_true(data["removed_from_map"])
	assert_false(ShipState.deserialize(data).is_on_map())
	data.erase("removed_from_map")
	assert_true(ShipState.deserialize(data).is_on_map(), "old saves load with the ship on the map")


func test_struck_ship_is_not_removed() -> void:
	# 8.G.1f removes exploded ships here (escaped ones come with sub-project 3); a struck ship stays.
	_make_ship("a", 0, Vector2i(0, 0))
	_make_ship("b", 1, Vector2i(10, 0))
	var struck := _make_ship("s", 1, Vector2i(5, 3))
	GameState.ship_controller.set_status("s", ShipState.Status.STRUCK)
	_end_turn(1)
	assert_true(struck.is_on_map(), "a struck ship stays on the map and keeps blocking")
	assert_eq(Occupancy.build(GameState.get_all_ships()).get(struck.hex_position, ""), "s")


func test_remove_from_map_refused_on_client() -> void:
	var ship := _make_ship("w", 1, Vector2i(5, 3))
	GameState.ship_controller.is_server = false
	GameState.ship_controller.remove_from_map("w")
	GameState.ship_controller.is_server = true
	assert_push_error("Cannot remove a ship from the map on client")
	assert_true(ship.is_on_map())
