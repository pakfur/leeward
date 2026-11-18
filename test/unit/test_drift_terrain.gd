extends GutTest
## DriftResolver over the map (map and scenario spec, 8.A.1, 8.A.5, 8.A.6, 13.G.2): aground ships
## never drift and hold their group, a drift into land or too-shallow water runs the ship aground
## where it stands (no rigging loss), a drift off a `none` edge loses the ship, off a crossable
## escape edge escapes it. Wind from the east (direction 0): downwind is west (-1, 0).
## Dice order: drift d10; fouling d10 (only when a ship blocks); depth d6s.

const PHASE := 5

var resolver: DriftResolver
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _old_turn: int


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	_old_turn = GameState.current_turn
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.active_scenario = {}
	GameState.current_turn = 1
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	resolver = DriftResolver.new(GameState)


func after_each() -> void:
	assert_eq(_dice.remaining(), 0, "every scripted die was used")
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _make_ship(id: String, hex: Vector2i, facing: int = 1, side: int = 0) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id,
		"ship_type": "frigate_38", "name": "38-gun Frigate", "nationality": "British",
		"rating": 38, "class": 3, "maneuverability": "C", "speed_type": "F/F", "draft": 16,
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	state.side = side
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
	GameState.ships_by_side[side].append(id)
	return state


func _hexes(list: Array) -> Array:
	var out: Array = []
	for h in list:
		out.append([h.x, h.y])
	return out


func _drifts() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.DRIFT)


func _hex_array(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in list:
		out.append(h)
	return out


# --- MapRules.forced_move --------------------------------------------------------

func test_forced_move_priorities() -> void:
	var s := _make_ship("a", Vector2i(5, 5))
	var old := _hex_array([Vector2i(5, 5), Vector2i(5, 4)])
	var shifted := _hex_array([Vector2i(4, 5), Vector2i(4, 4)])
	# A ship in the way and a crossing of an open edge: the edge wins.
	var edge_old := _hex_array([Vector2i(-5, 0), Vector2i(-4, 0)])
	var edge_new := _hex_array([Vector2i(-6, 0), Vector2i(-5, 0)])
	var r := MapRules.forced_move({"map_bounds": {"width": 10, "height": 10}}, s, edge_old, edge_new,
		{Vector2i(-5, 0): "x"}, 1)
	assert_eq(r["result"], "edge")
	assert_eq(r["edge"], "W")
	# Land and a ship: land.
	r = MapRules.forced_move({"terrain": {"land": _hexes([Vector2i(4, 5)])}}, s, old, shifted,
		{Vector2i(4, 4): "x"}, 1)
	assert_eq(r["result"], "land")
	# A ship only: the ship, bow first.
	r = MapRules.forced_move({}, s, old, shifted, {Vector2i(4, 4): "y", Vector2i(4, 5): "x"}, 1)
	assert_eq(r["result"], "ship")
	assert_eq(r["blocker"], "x")
	# Into a shoal: clear, with the bow in shallows.
	r = MapRules.forced_move({"terrain": {"shallow": [
		{"name": "bar", "base": 10, "hexes": _hexes([Vector2i(4, 5)])}]}}, s, old, shifted, {}, 1)
	assert_eq(r["result"], "clear")
	assert_true(r["shallow_bow"])
	# Only the stern in a shoal: no depth die for the bow.
	r = MapRules.forced_move({"terrain": {"shallow": [
		{"name": "bar", "base": 10, "hexes": _hexes([Vector2i(4, 4)])}]}}, s, old, shifted, {}, 1)
	assert_eq(r["result"], "clear")
	assert_false(r["shallow_bow"])
	# Open water.
	r = MapRules.forced_move({}, s, old, shifted, {}, 1)
	assert_eq(r["result"], "clear")
	assert_false(r["shallow_bow"])


# --- aground ships ---------------------------------------------------------------

func test_aground_ship_never_drifts_and_holds_its_group() -> void:
	## The one place that says who never drifts: DriftResolver._holds_group (anchored ships join it).
	var a := _make_ship("a", Vector2i(5, 5))
	var b := _make_ship("b", Vector2i(6, 5))
	a.aground = true
	GameState.ship_controller.set_fouled_with("a", "b")
	GameState.ship_controller.set_fouled_with("b", "a")
	resolver.resolve(PHASE)  # no die is drawn: the queue is empty
	assert_eq(_drifts().size(), 0)
	assert_eq(a.hex_position, Vector2i(5, 5))
	assert_eq(b.hex_position, Vector2i(6, 5))


# --- land and shallows -----------------------------------------------------------

func test_drift_onto_land_runs_aground_without_rigging_loss() -> void:
	GameState.active_scenario = {"terrain": {"land": _hexes([Vector2i(4, 5)])}}
	var a := _make_ship("a", Vector2i(5, 5))
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_true(a.is_aground())
	assert_eq(a.hex_position, Vector2i(5, 5))
	assert_eq(a.rigging_current_hp, [5, 5, 6, 6] as Array[int], "no rigging loss when drifting aground")
	var drift: PhaseEvents.PhaseEvent = _drifts()[0]
	assert_false(drift.data["drifted"])
	assert_eq(drift.data["blocked"], "aground")
	var aground := GameState.turn_log.of_type(PhaseEvents.Type.AGROUND)
	assert_eq(aground.size(), 1)
	assert_eq(aground[0].data["cause"], "drift")
	assert_eq(aground[0].data["terrain"], "land")


func test_drift_into_shallow_rolls_depth_with_dice() -> void:
	GameState.active_scenario = {"terrain": {"shallow": [
		{"name": "bank", "base": 15, "hexes": _hexes([Vector2i(4, 5)])}]}}
	var a := _make_ship("a", Vector2i(5, 5))
	_dice.queue([9, 1])  # depth 16 <= draft 16
	resolver.resolve(PHASE)
	assert_true(a.is_aground())
	assert_eq(a.hex_position, Vector2i(5, 5))
	var aground := GameState.turn_log.of_type(PhaseEvents.Type.AGROUND)
	assert_eq(aground[0].data["terrain"], "shallow")
	assert_eq(aground[0].data["depth"], 16)
	assert_eq(aground[0].data["draft"], 16)
	assert_eq(a.rigging_current_hp, [5, 5, 6, 6] as Array[int])

	GameState.turn_log = PhaseEvents.PhaseLog.new()
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var b := _make_ship("b", Vector2i(5, 5))
	_dice.queue([9, 2])  # depth 17 > draft 16: through
	resolver.resolve(PHASE)
	assert_false(b.is_aground())
	assert_eq(b.hex_position, Vector2i(4, 5))


func test_stern_only_in_shallows_rolls_no_depth() -> void:
	GameState.active_scenario = {"terrain": {"shallow": [
		{"name": "bank", "base": 5, "hexes": _hexes([Vector2i(4, 4)])}]}}
	var a := _make_ship("a", Vector2i(5, 5))
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_false(a.is_aground())
	assert_eq(a.hex_position, Vector2i(4, 5))


# --- edges -----------------------------------------------------------------------

func _edge_scenario(west: String) -> Dictionary:
	return {"map_bounds": {"width": 10, "height": 10}, "terrain": {"edges": {"W": west}}}


func test_drift_off_none_edge_loses_the_ship() -> void:
	GameState.active_scenario = _edge_scenario("none")
	var a := _make_ship("a", Vector2i(-5, 0), 3)  # bow (-5,0), stern (-4,0)
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_true(a.is_destroyed())
	assert_false(a.is_on_map())
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.DESTROYED).size(), 1)


func test_drift_off_escape_edge_escapes_declared_ship() -> void:
	GameState.active_scenario = _edge_scenario("escape")
	GameState.active_scenario["escape"] = {"0": {"from_turn": 1}}
	var a := _make_ship("a", Vector2i(-5, 0), 3)
	a.escape_declared = true
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_true(a.is_escaped())
	var escaped := GameState.turn_log.of_type(PhaseEvents.Type.ESCAPED)
	assert_eq(escaped[0].data["how"], "edge")
	assert_eq(escaped[0].data["edge"], "W")


func test_drift_at_escape_edge_without_declaring_is_blocked() -> void:
	GameState.active_scenario = _edge_scenario("escape")
	GameState.active_scenario["escape"] = {"0": {"from_turn": 1}}
	var a := _make_ship("a", Vector2i(-5, 0), 3)
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_false(a.is_escaped())
	assert_eq(a.hex_position, Vector2i(-5, 0))
	assert_eq(_drifts()[0].data["blocked"], "map edge")


## Ruling 2026-11-17: a ship in a live boarding action cannot drift out of it by an escape edge.
func test_drift_at_escape_edge_in_a_boarding_action_is_blocked() -> void:
	GameState.active_scenario = _edge_scenario("escape")
	GameState.active_scenario["escape"] = {"0": {"from_turn": 1}}
	var a := _make_ship("a", Vector2i(-5, 0), 3)
	a.escape_declared = true
	var action := BoardingAction.new()
	action.attacker_id = "x"
	action.defender_id = "a"
	action.state = BoardingAction.ENGAGED
	var old_actions: Array = GameState.boarding_actions
	GameState.boarding_actions = [action]
	_dice.queue([9])
	resolver.resolve(PHASE)
	GameState.boarding_actions = old_actions
	assert_false(a.is_escaped())
	assert_eq(a.hex_position, Vector2i(-5, 0))
	assert_eq(_drifts()[0].data["blocked"], "map edge")


func test_group_member_lost_off_none_edge_others_drift() -> void:
	# a (bow (-5,0), stern (-4,0)) and b (bow (-3,0), stern (-2,0)) are grappled. a's bow leaves the
	# map by the none edge; b only moves one hex.
	GameState.active_scenario = _edge_scenario("none")
	var a := _make_ship("a", Vector2i(-5, 0), 3)
	var b := _make_ship("b", Vector2i(-3, 0), 3)
	GameState.ship_controller.add_grapple("a", "b")
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_true(a.is_destroyed())
	assert_false(a.is_on_map())
	assert_eq(b.hex_position, Vector2i(-4, 0), "b drifted one hex downwind")
	assert_false(b.is_grappled())
	assert_true(b.is_on_map())


# --- partial drift with terrain (8.A.5) ---------------------------------------------

func _partial_bow_free() -> ShipState:
	# Facing 1: bow (5,5), stern (5,4). The blocker holds (4,4), the stern's downwind hex, so the
	# bow would drift to (4,5) and the ship swing on its stern.
	var drifter := _make_ship("a", Vector2i(5, 5))
	var blocker := _make_ship("b", Vector2i(4, 4), 0, 1)
	blocker.moved_this_turn = true
	return drifter


func test_partial_drift_into_shoal_grounds_in_place() -> void:
	GameState.active_scenario = {"terrain": {"shallow": [
		{"name": "bank", "base": 15, "hexes": _hexes([Vector2i(4, 5)])}]}}
	var a := _partial_bow_free()
	_dice.queue([9, 9, 1])  # drift, fouling (fails), depth 16 <= 16
	resolver.resolve(PHASE)
	assert_true(a.is_aground())
	assert_eq(a.hex_position, Vector2i(5, 5), "aground in place, not pivoted")
	assert_eq(a.facing, 1)
	assert_eq(_drifts()[0].data["blocked"], "aground")
	assert_eq(GameState.turn_log.of_type(PhaseEvents.Type.AGROUND)[0].data["cause"], "drift")


func test_partial_drift_through_deep_enough_shoal_pivots() -> void:
	GameState.active_scenario = {"terrain": {"shallow": [
		{"name": "bank", "base": 15, "hexes": _hexes([Vector2i(4, 5)])}]}}
	var a := _partial_bow_free()
	_dice.queue([9, 9, 2])
	resolver.resolve(PHASE)
	assert_false(a.is_aground())
	assert_eq(a.hex_position, Vector2i(4, 5))
	assert_eq(a.facing, 2)
	assert_eq(_drifts()[0].data["partial"], "bow")


func test_partial_drift_stern_free_in_shoal_rolls_no_depth() -> void:
	# Facing 4: bow (5,5), stern (5,6). The blocker holds (4,5); the stern would slip to (4,6).
	GameState.active_scenario = {"terrain": {"shallow": [
		{"name": "bank", "base": 0, "hexes": _hexes([Vector2i(4, 6)])}]}}
	var a := _make_ship("a", Vector2i(5, 5), 4)
	var blocker := _make_ship("b", Vector2i(4, 5), 0, 1)
	blocker.moved_this_turn = true
	_dice.queue([9, 9])  # drift, fouling (fails); no depth die for a stern
	resolver.resolve(PHASE)
	assert_false(a.is_aground())
	assert_eq(a.stern_hex(), Vector2i(4, 6))
	assert_eq(a.facing, 5)


# --- groups ----------------------------------------------------------------------

func test_group_member_on_land_grounds_and_holds_the_group() -> void:
	GameState.active_scenario = {"terrain": {"land": _hexes([Vector2i(4, 5)])}}
	var a := _make_ship("a", Vector2i(5, 5))
	var b := _make_ship("b", Vector2i(6, 5))
	GameState.ship_controller.add_grapple("a", "b")
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_true(a.is_aground())
	assert_false(b.is_aground())
	assert_eq(a.hex_position, Vector2i(5, 5))
	assert_eq(b.hex_position, Vector2i(6, 5))
	var by_ship := {}
	for ev in _drifts():
		by_ship[ev.ship_id] = ev
	assert_eq(by_ship["a"].data["blocked"], "aground")
	assert_eq(by_ship["b"].data["blocked"], "partner")


func test_group_depth_dice_are_drawn_in_group_order() -> void:
	# a's bow enters (4,5), b's bow enters (5,5): both shoals of base 15 (draft 16).
	GameState.active_scenario = {"terrain": {"shallow": [
		{"name": "bank", "base": 15, "hexes": _hexes([Vector2i(4, 5), Vector2i(5, 5)])}]}}
	var a := _make_ship("a", Vector2i(5, 5))
	var b := _make_ship("b", Vector2i(6, 5))
	GameState.ship_controller.add_grapple("a", "b")
	_dice.queue([9, 2, 1])  # drift; a: depth 17 (clear); b: depth 16 (aground)
	resolver.resolve(PHASE)
	assert_false(a.is_aground())
	assert_true(b.is_aground())
	assert_eq(a.hex_position, Vector2i(5, 5), "the group stays")
	assert_eq(b.hex_position, Vector2i(6, 5))
	var grounded := GameState.turn_log.of_type(PhaseEvents.Type.AGROUND)
	assert_eq(grounded.size(), 1)
	assert_eq(grounded[0].ship_id, "b")
	assert_eq(grounded[0].data["depth"], 16)


func test_group_member_escapes_off_permitted_edge_others_drift() -> void:
	GameState.active_scenario = _edge_scenario("escape")
	GameState.active_scenario["escape"] = {"0": {"from_turn": 1}}
	var a := _make_ship("a", Vector2i(-5, 0), 3)
	var b := _make_ship("b", Vector2i(-3, 0), 3)
	a.escape_declared = true
	GameState.ship_controller.add_grapple("a", "b")
	_dice.queue([9])
	resolver.resolve(PHASE)
	assert_true(a.is_escaped())
	assert_eq(b.hex_position, Vector2i(-4, 0))
	assert_false(b.is_grappled())
	assert_true(b.is_on_map())


func test_land_under_the_free_end_grounds_instead_of_pivoting() -> void:
	# Land outranks the blocking ship in forced_move, so the ship runs aground and nothing pivots.
	GameState.active_scenario = {"terrain": {"land": _hexes([Vector2i(4, 5)])}}
	var a := _partial_bow_free()
	_dice.queue([9])  # no fouling roll: no ship is the block
	resolver.resolve(PHASE)
	assert_true(a.is_aground())
	assert_eq(a.hex_position, Vector2i(5, 5))
	assert_eq(a.facing, 1)
