extends GutTest
## Signals become standing orders (players-and-sides spec 7): SignalOrders.parse, delivery applies.

const PHASES := TurnPhaseController.GamePhase

var _names := {"HMS LIVELY": "brit_a2", "LIVELY": "brit_a2", "BUCENTAURE": "fr_a1", "TOPAZE": "fr_a2"}


func before_each() -> void:
	_reset()
	var s := DataManager.load_scenario("test_squadron").duplicate(true)
	assert_true(GameState.start_scenario(s, [0, 1] as Array[int]))


func after_each() -> void:
	_reset()


func _pc() -> TurnPhaseController:
	return GameState.phase_controller


func _reset() -> void:
	var pc := _pc()
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = PHASES.SETUP
	pc.players_ready = {0: false, 1: false}
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()
	GameState.signals.clear()


func _w(text: String) -> Array[String]:
	var out: Array[String] = []
	for p in text.split(" ", false):
		out.append(p)
	return out


func _parse(text: String) -> Array[Dictionary]:
	return SignalOrders.parse(_w(text), _names)


func _deliver(from_player: int, from_ship: String, address: Dictionary, text: String) -> void:
	var sig := SignalState.new()
	sig.turn = GameState.current_turn
	sig.from_player = from_player
	sig.from_ship = from_ship
	sig.address = address
	sig.words = _w(text)
	_pc()._apply_signal_orders(sig)


func _fleet() -> Dictionary:
	return {"kind": "fleet", "name": ""}


func _order(id: String) -> Dictionary:
	return GameState.ships[id].standing_order


func test_parse_table() -> void:
	assert_eq(_parse("ENGAGE"), [{"order": "engage"}] as Array[Dictionary])
	assert_eq(_parse("ENGAGE BUCENTAURE"), [{"order": "engage", "target": "fr_a1"}] as Array[Dictionary])
	assert_eq(_parse("ATTACK TOPAZE"), [{"order": "engage", "target": "fr_a2"}] as Array[Dictionary])
	assert_eq(_parse("CLOSE TO 4"), [{"order": "close", "range": 4}] as Array[Dictionary])
	assert_eq(_parse("CLOSE TO 0"), [] as Array[Dictionary])
	assert_eq(_parse("CLOSE TO 16"), [] as Array[Dictionary])
	assert_eq(_parse("CLOSE TO MANY"), [] as Array[Dictionary])
	assert_eq(_parse("FOLLOW FLAGSHIP"), [{"order": "follow", "leader": "FLAGSHIP"}] as Array[Dictionary])
	assert_eq(_parse("FOLLOW HMS LIVELY".replace("HMS ", "")), [{"order": "follow", "leader": "brit_a2"}] as Array[Dictionary])
	assert_eq(_parse("FORM LINE"), [{"order": "line"}] as Array[Dictionary])
	assert_eq(_parse("DISENGAGE"), [{"order": "disengage"}] as Array[Dictionary])
	assert_eq(_parse("HELLO WORLD"), [] as Array[Dictionary])
	assert_eq(_parse("ENGAGE THEN DISENGAGE").size(), 2)


func test_engage_attack_without_ship_is_plain_engage() -> void:
	assert_eq(_parse("ENGAGE ATTACK"), [{"order": "engage"}] as Array[Dictionary])


func test_last_order_wins() -> void:
	_deliver(0, "brit_a1", _fleet(), "ENGAGE THEN DISENGAGE")
	assert_eq(_order("brit_a2")["order"], "disengage")


func test_fleet_signal_sets_every_ship() -> void:
	_deliver(0, "brit_a1", _fleet(), "CLOSE TO 3")
	for id in ["brit_a1", "brit_a2", "brit_b1"]:
		assert_eq(_order(id), {"order": "close", "range": 3})
	assert_true(_order("fr_a1").is_empty())


func test_group_signal_sets_group_only() -> void:
	_deliver(0, "brit_a1", {"kind": "group", "name": "Van"}, "FORM LINE")
	assert_eq(_order("brit_a2"), {"order": "line", "group": "Van"})
	assert_true(_order("brit_b1").is_empty())
	_deliver(0, "brit_a1", _fleet(), "FORM LINE")
	assert_eq(_order("brit_b1"), {"order": "line", "group": ""})


func test_follow_flagship_resolves_to_flagship_id() -> void:
	_deliver(0, "brit_a1", _fleet(), "FOLLOW FLAGSHIP")
	assert_eq(_order("brit_a2"), {"order": "follow", "leader": "brit_a1"})
	assert_true(_order("brit_a1").is_empty(), "the flagship does not follow itself")


func test_engage_target_must_be_enemy() -> void:
	_deliver(0, "brit_a1", _fleet(), "ENGAGE LIVELY")
	assert_true(_order("brit_b1").is_empty())
	_deliver(0, "brit_a1", _fleet(), "ENGAGE BUCENTAURE")
	assert_eq(_order("brit_b1"), {"order": "engage", "target": "fr_a1"})


func test_follow_must_be_friend() -> void:
	_deliver(0, "brit_a1", _fleet(), "FOLLOW TOPAZE")
	assert_true(_order("brit_b1").is_empty())


func test_out_of_play_ships_skipped() -> void:
	GameState.ships["brit_b1"].status = ShipState.Status.STRUCK
	_deliver(0, "brit_a1", {"kind": "group", "name": "Rear"}, "DISENGAGE")
	assert_true(_order("brit_b1").is_empty())


func test_order_falls_back_when_leader_struck() -> void:
	_deliver(0, "brit_a1", _fleet(), "FOLLOW FLAGSHIP")
	assert_eq(GameState.order_of("brit_a2")["order"], "follow")
	GameState.ships["brit_a1"].status = ShipState.Status.STRUCK
	assert_eq(GameState.order_of("brit_a2")["order"], "engage")


func test_order_falls_back_when_target_struck() -> void:
	_deliver(0, "brit_a1", _fleet(), "ENGAGE BUCENTAURE")
	GameState.ships["fr_a1"].status = ShipState.Status.STRUCK
	assert_eq(GameState.order_of("brit_a2"), {"order": "engage"})


func test_no_order_is_engage() -> void:
	assert_eq(GameState.order_of("brit_a2"), {"order": "engage"})


func test_standing_order_round_trips() -> void:
	_deliver(0, "brit_a1", _fleet(), "CLOSE TO 5")
	var back := ShipState.deserialize(GameState.ships["brit_a2"].serialize())
	assert_eq(back.standing_order, {"order": "close", "range": 5})
