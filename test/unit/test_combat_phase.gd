extends GutTest
## Tests for the two-step COMBAT_RESOLUTION phase (DECLARE then RESOLVE) in TurnPhaseController.
## Drives the real GameState phase controller; entry into combat is triggered by finishing
## MOVEMENT_RESOLUTION playback with no pending movement log.

const PORT := 0
const STARBOARD := 1

var pc: TurnPhaseController
var a: ShipState
var b: ShipState
var _dice: ScriptedDice
var _old_dice: Dice
var _old_log: PhaseEvents.PhaseLog
var _old_env: EnvironmentState
var _declare_signals: int = 0
var _log_signals: int = 0


func before_all() -> void:
	DataManager.load_ship_definitions()


func before_each() -> void:
	pc = GameState.phase_controller
	_old_dice = GameState.dice
	_old_log = GameState.turn_log
	_old_env = GameState.environment
	_dice = ScriptedDice.new()
	GameState.dice = _dice
	_dice.queue(_sixes())
	GameState.turn_log = PhaseEvents.PhaseLog.new()
	var env := EnvironmentState.new()
	env.wind_speed = 2
	env.sea_state = 1
	GameState.environment = env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}
	_declare_signals = 0
	_log_signals = 0
	pc.fire_declaration_requested.connect(_on_declare)
	pc.combat_log_ready.connect(_on_log)
	pc.combat_step = TurnPhaseController.CombatStep.NONE


func after_each() -> void:
	pc.fire_declaration_requested.disconnect(_on_declare)
	pc.combat_log_ready.disconnect(_on_log)
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.current_phase = TurnPhaseController.GamePhase.SETUP
	GameState.dice = _old_dice
	GameState.turn_log = _old_log
	GameState.environment = _old_env
	GameState.ships.clear()
	GameState.ships_by_player = {0: [], 1: []}


func _on_declare() -> void:
	_declare_signals += 1


func _on_log(_log: PhaseEvents.PhaseLog) -> void:
	_log_signals += 1


func _sixes(count: int = 200) -> Array:
	var values: Array = []
	values.resize(count)
	values.fill(6)
	return values


func _make_ship(id: String, player: int, hex: Vector2i, facing: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
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
	GameState.ships_by_player[player].append(id)
	return state


## a (player 0) at the origin facing east; b (player 1) adjacent to its starboard side.
func _setup_adjacent() -> void:
	a = _make_ship("a_ship", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_ship", 1, HexGrid.DIRECTIONS[1], 3)


func _setup_far_apart() -> void:
	a = _make_ship("a_ship", 0, Vector2i.ZERO, 0)
	b = _make_ship("b_ship", 1, Vector2i(40, 0), 3)


func _enter_combat() -> void:
	pc.current_phase = TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
	pc.on_playback_completed()


func _order(side: int = STARBOARD) -> Dictionary:
	return {"ship_id": "a_ship", "side": side, "target_id": "b_ship", "aim": "low", "ammo": "round"}


func _boxes(s: ShipState) -> int:
	var total := s.total_crew_boxes()
	for h in s.hull_current_hp:
		total += h
	for r in s.rigging_current_hp:
		total += r
	return total


func _fire_events() -> Array:
	return GameState.turn_log.of_type(PhaseEvents.Type.FIRE)


func test_combat_skipped_when_no_targets() -> void:
	_setup_far_apart()
	_enter_combat()
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT,
		"combat passes without waiting when nobody has a target")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.NONE)
	assert_eq(_declare_signals, 0, "no declaration request when skipped")
	assert_eq(_log_signals, 0, "no combat log when skipped")


func test_combat_waits_for_orders_when_in_range() -> void:
	_setup_adjacent()
	_enter_combat()
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION)
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE)
	assert_eq(_declare_signals, 1, "declaration requested exactly once")


func test_invalid_orders_rejected_and_phase_waits() -> void:
	_setup_adjacent()
	_enter_combat()
	var before := _boxes(b)
	var reason := pc.player_submit_fire_orders(0, [_order(PORT)])
	assert_ne(reason, "", "out-of-arc order is rejected with a reason")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE, "still waiting")
	assert_eq(_boxes(b), before, "target undamaged")
	reason = pc.player_submit_fire_orders(0, [_order(STARBOARD)])
	assert_eq(reason, "", "valid submission then succeeds")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.RESOLVE)


func test_malformed_orders_rejected() -> void:
	_setup_adjacent()
	_enter_combat()
	assert_ne(pc.player_submit_fire_orders(0, ["not a dictionary"]), "")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE)


func test_empty_orders_allowed() -> void:
	_setup_adjacent()
	_enter_combat()
	assert_eq(pc.player_submit_fire_orders(0, []), "")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.RESOLVE, "AI already ready, so resolves")
	assert_eq(_fire_events().size(), 0, "no FIRE events")
	assert_eq(_log_signals, 1, "log emitted, waiting for playback")
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION)


func test_resolve_then_playback_advances() -> void:
	_setup_adjacent()
	_enter_combat()
	var before := _boxes(b)
	assert_eq(pc.player_submit_fire_orders(0, [_order()]), "")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.RESOLVE)
	assert_lt(_boxes(b), before, "target lost boxes")
	assert_eq(_fire_events().size(), 1)
	pc.on_combat_playback_completed()
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.NONE)
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.POST_COMBAT)


func test_resubmission_replaces_earlier_orders_until_resolved() -> void:
	_setup_adjacent()
	# Hold the AI back so player 0 can submit twice while still in DECLARE.
	pc.current_phase = TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
	var saved_ai := GameState.stub_ai
	GameState.stub_ai = null
	pc.on_playback_completed()
	GameState.stub_ai = saved_ai
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE)
	assert_eq(pc.player_submit_fire_orders(0, [_order()]), "")
	assert_eq(pc.player_submit_fire_orders(0, []), "", "later valid submission replaces earlier")
	assert_ne(pc.player_submit_fire_orders(0, [_order(PORT)]), "", "invalid one is refused")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE, "player 1 not ready yet")
	assert_eq(pc.player_submit_fire_orders(1, []), "")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.RESOLVE)
	assert_eq(_fire_events().size(), 0, "the replacing empty list was used")


func test_submit_outside_declare_rejected() -> void:
	_setup_adjacent()
	assert_ne(pc.player_submit_fire_orders(0, [_order()]), "", "not in combat phase")
	_enter_combat()
	assert_ne(pc.player_submit_fire_orders(5, []), "", "bad player id")
	pc.player_submit_fire_orders(0, [])
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.RESOLVE)
	assert_ne(pc.player_submit_fire_orders(0, []), "", "RESOLVE step is not DECLARE")


func test_combat_playback_outside_resolve_is_ignored() -> void:
	_setup_adjacent()
	_enter_combat()
	pc.on_combat_playback_completed()
	assert_push_error("called outside combat RESOLVE")
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE)
	assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION)


func test_serialize_includes_combat_step() -> void:
	_setup_adjacent()
	_enter_combat()
	var data := pc.serialize_phase_state()
	assert_eq(data["combat_step"], TurnPhaseController.CombatStep.DECLARE)
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.apply_phase_state(data)
	assert_eq(pc.combat_step, TurnPhaseController.CombatStep.DECLARE)
