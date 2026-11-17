extends GutTest
## Tests for GunneryResolver: simultaneous fire, table lookup, adjustments and logging.

const PORT := 0
const STARBOARD := 1
const PHASE := 4
## B's bow when it faces SE: its stern (0,1) has A's bow (0,0) directly astern.
const STERN_RAKE_B_HEX := Vector2i(0, 2)

var resolver: GunneryResolver
var a: ShipState
var b: ShipState
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _dice: ScriptedDice


func before_each() -> void:
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	_setup_ships()
	resolver = GunneryResolver.new(GameState)


func after_each() -> void:
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


## Default: B's bow (-1,1) facing W, stern (0,1), abeam of A (bow (0,0) facing E, stern (-1,0)),
## so each ship's starboard broadside bears on the other with both batteries.
func _setup_ships(b_facing: int = 3, b_hex: Vector2i = Vector2i(-1, 1)) -> void:
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	a = _make_ship("a_ship", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_ship", 1, b_hex, b_facing)


func _make_ship(id: String, player: int, hex: Vector2i, facing: int,
		gun_factors: Dictionary = {"lg": 6, "mg": 0, "cr": 4}, quality: String = "D") -> ShipState:
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
		"gun_factors": gun_factors,
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
	state.crew_quality = quality
	GameState.ships[id] = state
	GameState.ships_by_player[player].append(id)
	return state


func _order(ship_id: String, target_id: String, ammo: String = "round",
		aim: String = "low", battery: String = "full", side: int = STARBOARD) -> GunneryTypes.FireOrder:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = side
	order.target_id = target_id
	order.ammo = ammo
	order.aim = aim
	order.battery = battery
	return order


func _fire(orders: Array) -> void:
	var typed: Array[GunneryTypes.FireOrder] = []
	for o in orders:
		typed.append(o)
	resolver.resolve(typed, PHASE)


func _sixes(count: int = 200) -> void:
	var values: Array = []
	values.resize(count)
	values.fill(6)
	_dice.queue(values)


func _fire_events() -> Array:
	return GameState.turn_log.events.filter(func(e): return e.type == PhaseEvents.Type.FIRE)


func _fire_event_for(ship_id: String) -> PhaseEvents.PhaseEvent:
	for e in _fire_events():
		if e.ship_id == ship_id:
			return e
	return null


## Counts of rigging/hull/crew from table columns, resolving slashed tokens with a roll of 6
## (second alternative), which is what _sixes() scripts.
func _table_amounts(fgn: int, aim: String, columns: Array) -> Dictionary:
	var out := {"r": 0, "h": 0, "c": 0}
	for column in columns:
		for token in DataManager.combat_tables.gunfire_result(fgn, aim, column):
			var alt: Dictionary = token[token.size() - 1]
			if alt.has("type"):
				out[alt["type"]] += int(alt["count"])
	return out


func _has_slash(fgn: int, aim: String, columns: Array) -> bool:
	for column in columns:
		for token in DataManager.combat_tables.gunfire_result(fgn, aim, column):
			if token.size() > 1:
				return true
	return false


## A gunnery d6 whose result row (low aim, given columns) has no slashed token and the wanted
## rigging parity (0 even, 1 odd), for a shot at base mgn `mgn`.
func _d6_with_rigging_parity(mgn: int, columns: Array, parity: int) -> int:
	for d6 in range(1, 7):
		if _has_slash(mgn + d6, "low", columns):
			continue
		if _table_amounts(mgn + d6, "low", columns)["r"] % 2 == parity:
			return d6
	return 0


# --- tests ---

func test_simultaneous_fire_uses_pre_fire_state() -> void:
	_sixes()
	_fire([_order("a_ship", "b_ship"), _order("b_ship", "a_ship")])
	var ev := _fire_event_for("b_ship")
	assert_not_null(ev)
	assert_eq(ev.data["mgn"], 28)
	assert_eq(ev.data["fgn"], 34)
	assert_eq(_fire_events().size(), 2)


func test_fire_line_precedes_its_damage_line() -> void:
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	var types: Array = GameState.turn_log.events.map(func(e): return e.type)
	var damage_at := types.find(PhaseEvents.Type.DAMAGE)
	assert_gt(damage_at, -1, "the broadside does damage")
	assert_lt(types.find(PhaseEvents.Type.FIRE), damage_at)


func test_initial_broadside_spent_after_firing() -> void:
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	assert_true(a.initial_broadside_fired[STARBOARD])
	assert_false(a.initial_broadside_fired[PORT])
	assert_false(b.initial_broadside_fired[STARBOARD])


func test_target_sail_state_adds_columns() -> void:
	var rigging := {}
	for sail in ["FS", "MS", "PS"]:
		_setup_ships()
		b.sail_state = sail
		_dice = ScriptedDice.new()
		GameState.dice = _dice
		_sixes()
		_fire([_order("a_ship", "b_ship")])
		rigging[sail] = _fire_event_for("a_ship").data["rigging"]
	var fgn := 34
	assert_eq(rigging["FS"], _table_amounts(fgn, "low", ["fs"])["r"])
	assert_eq(rigging["MS"], _table_amounts(fgn, "low", ["fs", "ms"])["r"])
	assert_eq(rigging["PS"], _table_amounts(fgn, "low", ["fs", "ms", "ps"])["r"])
	assert_true(rigging["PS"] >= rigging["MS"])
	assert_true(rigging["MS"] >= rigging["FS"])
	assert_true(rigging["PS"] > rigging["FS"], "columns should add something at fgn 34")


func test_dismantling_shot_ignores_hull() -> void:
	_sixes()
	_fire([_order("a_ship", "b_ship", "dismantling")])
	var ev := _fire_event_for("a_ship")
	assert_eq(ev.data["hull"], 0)
	assert_eq(ev.data["rigging"], _table_amounts(ev.data["fgn"], "low", ["fs", "ms"])["r"])
	assert_eq(b.hull_current_hp, [5, 5, 5, 6] as Array[int])


func test_stern_rake_doubles_crew() -> void:
	_setup_ships(1, STERN_RAKE_B_HEX)  # B faces SE, A's bow sits directly astern of B's stern
	_sixes()
	_fire([_order("a_ship", "b_ship", "round", "low", "bow")])  # only A's bow battery bears
	var ev := _fire_event_for("a_ship")
	assert_eq(ev.data["rake"], "stern")
	var expected := _table_amounts(ev.data["fgn"], "low", ["fs", "ms"])
	assert_eq(ev.data["crew"], expected["c"] * 2)
	assert_eq(ev.data["hull"], expected["h"])


func test_bow_rake_does_not_double_crew() -> void:
	_setup_ships(4)  # B faces NW, A's stern is dead ahead of B's bow
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	var ev := _fire_event_for("a_ship")
	assert_eq(ev.data["rake"], "bow")
	assert_eq(ev.data["crew"], _table_amounts(ev.data["fgn"], "low", ["fs", "ms"])["c"])


func test_dismasted_target_takes_no_rigging() -> void:
	b.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	b.sail_state = "NS"
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	var ev := _fire_event_for("a_ship")
	assert_eq(ev.data["rigging"], 0)
	assert_eq(ev.data["hull"], _table_amounts(ev.data["fgn"], "low", ["fs"])["h"])


func test_raked_dismasted_target_notes_morale() -> void:
	_setup_ships(1, STERN_RAKE_B_HEX)
	b.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	b.sail_state = "NS"
	_sixes()
	_fire([_order("a_ship", "b_ship", "round", "low", "bow")])
	var turn: int = GameState.phase_controller.current_turn
	var trigger := "raked_dismasted_t%d" % turn
	var noted := GameState.turn_log.events.filter(func(e):
		return e.type == PhaseEvents.Type.MORALE_NOTED and e.data.get("trigger") == trigger)
	assert_eq(noted.size(), 1)


func test_furled_target_halves_rigging() -> void:
	var odd_d6 := _d6_with_rigging_parity(28, ["fs"], 1)
	assert_ne(odd_d6, 0, "need a slash-free row with odd rigging")
	var base: int = _table_amounts(28 + odd_d6, "low", ["fs"])["r"]
	for case in [[3, base / 2 + 1], [4, base / 2]]:
		_setup_ships()
		b.sail_state = "NS"
		_dice = ScriptedDice.new()
		GameState.dice = _dice
		_dice.queue([odd_d6, case[0]])
		_sixes()
		_fire([_order("a_ship", "b_ship")])
		assert_eq(_fire_event_for("a_ship").data["rigging"], case[1], "half-box roll %d" % case[0])


func test_furled_target_even_rigging_needs_no_roll() -> void:
	var even_d6 := _d6_with_rigging_parity(28, ["fs"], 0)
	assert_ne(even_d6, 0)
	var base: int = _table_amounts(28 + even_d6, "low", ["fs"])["r"]
	b.sail_state = "NS"
	_dice.queue([even_d6, 3, 6, 6, 6, 6])  # the 3 would be a crew roll, not a half-box roll
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	assert_eq(_fire_event_for("a_ship").data["rigging"], base / 2)


func test_fgn_below_one_no_damage_but_broadside_spent() -> void:
	a.guns_dismounted[STARBOARD] = 40
	_dice.queue([1])
	_fire([_order("a_ship", "b_ship")])
	var ev := _fire_event_for("a_ship")
	assert_not_null(ev)
	assert_true(ev.data["fgn"] < 1)
	assert_eq(ev.data["rigging"], 0)
	assert_eq(ev.data["hull"], 0)
	assert_eq(ev.data["crew"], 0)
	assert_true(a.initial_broadside_fired[STARBOARD])
	assert_eq(GameState.turn_log.events.filter(func(e): return e.type == PhaseEvents.Type.DAMAGE).size(), 0)
	assert_eq(b.hull_current_hp, [5, 5, 5, 6] as Array[int])


func test_fgn_above_52_uses_last_row() -> void:
	# B's bow (-1,2) facing SE, stern (-1,1): range 1, a stern rake on which both of A's starboard
	# batteries bear. A heavy broadside, crew A and a dismantling shot give mgn 47; a six makes 53.
	_setup_ships(1, Vector2i(-1, 2))
	a.ship.gun_factors = {"lg": 30, "mg": 0, "cr": 10}
	a.crew_quality = "A"
	_sixes()
	_fire([_order("a_ship", "b_ship", "dismantling")])
	var ev := _fire_event_for("a_ship")
	assert_eq(ev.data["rake"], "stern")
	assert_eq(ev.data["battery"], "full")
	assert_eq(ev.data["range"], 1)
	assert_true(ev.data["fgn"] > 52, "fgn %d should exceed 52" % ev.data["fgn"])
	var expected := _table_amounts(52, "low", ["fs", "ms"])
	assert_eq(ev.data["hull"], 0)
	assert_eq(ev.data["crew"], expected["c"] * 2)
	assert_eq(ev.data["rigging"], expected["r"])


func test_can_fire_false_orders_are_skipped() -> void:
	var order := _order("a_ship", "b_ship")
	order.side = PORT
	_sixes()
	_fire([order])
	assert_eq(_fire_events().size(), 0)
	assert_false(a.initial_broadside_fired[PORT])


func test_same_seed_same_log() -> void:
	var logs: Array = []
	for i in range(2):
		_setup_ships()
		GameState.dice = Dice.new(_seeded_rng(99))
		_fire([_order("a_ship", "b_ship"), _order("b_ship", "a_ship")])
		logs.append(GameState.turn_log.to_dict())
	assert_eq(logs[0], logs[1])
	assert_true(logs[0]["events"].size() >= 2)


func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- battery fire orders (7.B.1, 7.C.12f/g) ---

func test_split_side_fires_each_battery_with_two_target_modifier() -> void:
	# A's starboard bow battery covers only B (bow (0,3) facing SE); its stern battery only C.
	_setup_ships(1, Vector2i(0, 3))
	_make_ship("c_ship", 1, Vector2i(-4, 3), 2)
	_sixes()
	_fire([_order("a_ship", "c_ship", "round", "low", "stern"),
			_order("a_ship", "b_ship", "round", "low", "bow")])
	var events := _fire_events()
	assert_eq(events.size(), 2)
	assert_eq(events.map(func(e): return e.target_id), ["b_ship", "c_ship"])
	assert_eq(events.map(func(e): return e.data["battery"]), ["bow", "stern"])
	for e in events:
		var names: Array = e.data["modifiers"].map(func(m): return m["name"])
		assert_true(names.has("two_targets"), str(names))
		assert_false(names.has("half_broadside"), "two targets: only the two-target modifier")
	assert_true(a.initial_broadside_fired[STARBOARD])


func test_both_sides_at_one_target_are_one_target() -> void:
	# Port and starboard both naming B passes FireRules.declaration_error (bow and stern of one side at
	# one target does not), but validate_orders refuses the set, since port cannot bear: no ship can lie
	# in both broadside arcs of another. The resolver skips the port order. Pins target_count
	# de-duplication: one target named twice is still one target, so no -12.
	_sixes()
	_fire([_order("a_ship", "b_ship", "round", "low", "full", PORT),
			_order("a_ship", "b_ship", "round", "low", "full", STARBOARD)])
	var events := _fire_events()
	assert_eq(events.size(), 1, "Only the starboard broadside bears")
	for e in events:
		assert_eq(e.data["battery"], "full")
		var names: Array = e.data["modifiers"].map(func(m): return m["name"])
		assert_false(names.has("two_targets"), "one target: no two-target modifier")
		assert_false(names.has("half_broadside"))


func test_fire_event_records_full_battery() -> void:
	_sixes()
	_fire([_order("a_ship", "b_ship")])
	assert_eq(_fire_event_for("a_ship").data["battery"], "full")


func test_split_first_fire_earns_initial_broadside_once() -> void:
	# B (range 2) only in A's starboard bow arc, C (range 4) only in its stern arc.
	_setup_ships(1, Vector2i(0, 3))
	_make_ship("c_ship", 1, Vector2i(-6, 5), 2)
	_sixes()
	_fire([_order("a_ship", "c_ship", "round", "low", "stern"),
			_order("a_ship", "b_ship", "round", "low", "bow")])
	var ib := {}
	for e in _fire_events():
		ib[e.target_id] = 0
		for m in e.data["modifiers"]:
			if m["name"] == "initial_broadside":
				ib[e.target_id] = m["value"]
	assert_eq(ib, {"b_ship": DataManager.combat_tables.range_bonus("initial_broadside", 2), "c_ship": 0})
	assert_true(a.initial_broadside_fired[STARBOARD])


func test_reduction_below_one_does_no_damage_and_no_crit() -> void:
	# 7.C.14: an FGN below 1 has no result; a natural 6 then rolls no critical hit either.
	var order := _order("a_ship", "b_ship")
	order.mgn_reduction = 60
	_dice.queue([6])
	_fire([order])
	var ev := _fire_event_for("a_ship")
	assert_true(ev.data["fgn"] < 1)
	assert_eq(ev.data["rigging"] + ev.data["hull"] + ev.data["crew"], 0)
	assert_true(ev.data["modifiers"].any(func(m): return m["name"] == "Voluntary reduction"))
	assert_eq(GameState.turn_log.events.filter(func(e): return e.type == PhaseEvents.Type.CRITICAL_ROLL).size(), 0)
