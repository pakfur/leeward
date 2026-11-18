extends GutTest
## Towing and movement (Close Action 12.A.6-7, 5.D.7; towing spec §2, §5): the tower's 12.A.7 MA
## loss in both MA paths (floored at 0), a towed ship plots nothing, a tower whose tow is fouled or
## grappled is held, a towed ship is never in irons, the tower's +1 tacking DRM, and no anchoring
## while in a tow.
## Wind from the east (direction 0), speed 3. Tower t: bow (5, 5), facing 3 (WF=R), MS, class 3.
## Towed w: bow (7, 5), facing 3, class 2, dismasted unless stated.

const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")

var sc: ShipStateController
var _old_env: EnvironmentState
var _old_scenario: Dictionary
var _old_turn: int


func before_all() -> void:
	DataManager.load_ship_definitions()
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_turning_table()
	DataManager.load_speed_change_table()


func before_each() -> void:
	_old_env = GameState.environment
	_old_scenario = GameState.active_scenario
	_old_turn = GameState.current_turn
	GameState.active_scenario = {"map_bounds": {"width": 40, "height": 30}}
	GameState.current_turn = 5
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var env := EnvironmentState.new()
	env.wind_direction = 0
	env.wind_speed = 3
	env.sea_state = 1
	GameState.environment = env
	sc = GameState.ship_controller


func after_each() -> void:
	GameState.environment = _old_env
	GameState.active_scenario = _old_scenario
	GameState.current_turn = _old_turn
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _ship(id: String, hex: Vector2i, facing: int = 3, ship_class: int = 3, side: int = 0) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({
		"ship_id": id, "side": side, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": ship_class,
		"maneuverability": "C", "speed_type": "F/F", "draft": 16,
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
		"point_costs": DataManager.get_ship_definition("frigate_38").point_costs,
	})
	s.side = side
	s.hex_position = hex
	s.facing = facing
	s.sail_state = "MS"
	s.crew_quality = "C"
	s.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	s.hull_current_hp = [5, 5, 5, 6] as Array[int]
	s.crew_count = [3, 3, 3, 3] as Array[int]
	s.marine_count = 2
	s.crew_auto = false
	GameState.ships[id] = s
	GameState.ships_by_side[side].append(id)
	return s


func _t() -> ShipState:
	return _ship("t", Vector2i(5, 5))


func _w(dismasted: bool = true) -> ShipState:
	var w := _ship("w", Vector2i(7, 5), 3, 2)
	if dismasted:
		w.rigging_current_hp = [0, 0, 0, 0] as Array[int]
	return w


func _resolver() -> MovementResolver:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return MovementResolver.new(GameState, rng)


# --- 12.A.7: the tower's MA loss ------------------------------------------------------

func test_tower_ma_loses_12a7() -> void:
	var t := _t()
	var w := _w()
	var ma0 := sc.get_movement_allowance("t")
	var w_ma0 := sc.get_movement_allowance("w")
	assert_gt(ma0, 3, "precondition: the loss shows")
	assert_true(sc.begin_tow("t", "w"))
	assert_eq(sc.tow_mp_loss(t), 3, "1 + 1 class + 1 dismasted")
	assert_eq(sc.get_movement_allowance("t"), maxi(ma0 - 3, 0))
	assert_eq(sc.tow_mp_loss(w), 0, "the towed ship has no loss of her own")
	assert_eq(sc.get_movement_allowance("w"), w_ma0, "the towed ship's MA unchanged")


func test_validator_ma_matches() -> void:
	var t := _t()
	_w()
	var ma0 := sc.get_movement_allowance("t")
	assert_true(sc.begin_tow("t", "w"))
	var ps := MovementValidator.new(GameState)._build_plotting_state(t, t.hex_position, t.facing,
		[] as Array[MovementTypes.PlotStep])
	assert_eq(ps.base_ma, sc.get_movement_allowance("t"))
	assert_eq(ps.base_ma, maxi(ma0 - 3, 0))


func test_tow_loss_floors_ma_at_zero() -> void:
	GameState.environment.wind_speed = 1
	var t := _ship("t", Vector2i(5, 5), 1)  # WF=C, FS at WS 1: MA 2
	t.sail_state = "FS"
	_w()
	var ma0 := sc.get_movement_allowance("t")
	assert_lt(ma0, 3, "precondition: the loss exceeds the MA")
	assert_gt(ma0, 0)
	assert_true(sc.begin_tow("t", "w"))
	assert_eq(sc.get_movement_allowance("t"), 0, "the controller path floors at 0")
	var ps := MovementValidator.new(GameState)._build_plotting_state(t, t.hex_position, t.facing,
		[] as Array[MovementTypes.PlotStep])
	assert_eq(ps.base_ma, 0, "the validator path floors at 0")


func test_no_tow_no_loss() -> void:
	var t := _t()
	assert_eq(sc.tow_mp_loss(t), 0)


# --- 12.A.6: the towed ship does not plot; a fouled tow holds the tower -------------

func test_towed_cannot_plot() -> void:
	_t()
	var w := _w(false)
	w.speed = 3
	assert_true(DefaultCourse.can_plot(w), "precondition: she could plot before the tow")
	assert_true(sc.begin_tow("t", "w"))
	assert_false(DefaultCourse.can_plot(w))
	assert_eq(DefaultCourse.for_ship(GameState, w).size(), 0)
	var resp = GameState.movement_plotting_controller.handle_start_plotting(0, "w", "r1")
	assert_true(resp is MovementTypes.PlottingErrorResponse)
	assert_eq(resp.error_code, "SHIP_TOWED")


func test_tower_held_by_fouled_tow() -> void:
	var t := _t()
	_w()
	_ship("x", Vector2i(7, 6), 3, 3)
	t.speed = 3
	assert_true(sc.begin_tow("t", "w"))
	assert_false(DefaultCourse.tow_held(GameState, t), "a free tow does not hold her")
	assert_gt(DefaultCourse.for_ship(GameState, t).size(), 0, "precondition: a default course")
	sc.set_fouled_with("w", "x")
	sc.set_fouled_with("x", "w")
	assert_true(DefaultCourse.tow_held(GameState, t))
	var resp = GameState.movement_plotting_controller.handle_start_plotting(0, "t", "r2")
	assert_true(resp is MovementTypes.PlottingErrorResponse)
	assert_eq(resp.error_code, "TOW_HELD")
	assert_eq(DefaultCourse.for_ship(GameState, t).size(), 0)
	var stored := [MovementTypes.PlotStep.new(Vector2i(4, 5), 3, MovementTypes.MoveType.FORWARD).to_dict()]
	sc.set_plotted_movement("t", stored)
	assert_eq(_resolver()._get_plotted_steps(t).size(), 0, "a stored course is not executed")


func test_tower_held_by_grappled_tow() -> void:
	var t := _t()
	_w()
	_ship("x", Vector2i(7, 6), 3, 3)
	assert_true(sc.begin_tow("t", "w"))
	sc.add_grapple("w", "x")
	assert_true(DefaultCourse.tow_held(GameState, t))
	assert_false(DefaultCourse.tow_held(GameState, GameState.get_ship("w")), "only the tower is held")


# --- 5.D.7: towed ships are out of irons -----------------------------------------------

func test_towed_never_in_irons() -> void:
	_t()
	var w := _ship("w", Vector2i(7, 5), 0, 2)  # facing 0 into a wind from 0: WF=L
	w.speed = 0
	assert_false(IronsRules.excused(w, GameState.environment, GameState.current_turn),
		"precondition: in irons before the tow")
	assert_true(sc.begin_tow("t", "w"))
	assert_true(IronsRules.excused(w, GameState.environment, GameState.current_turn))
	var resolver := _resolver()
	assert_false(resolver._is_in_irons(w, GameState.environment))
	var ships: Array[ShipState] = [w]
	var result: MovementTypes.ShipResolutionResult = resolver.run(ships, GameState.environment).get_result("w")
	var irons := result.events.filter(func(ev): \
		return ev.event_type == MovementTypes.ResolutionEventType.IMMOBILIZED)
	assert_eq(irons.size(), 0)
	assert_false(result.immobilized)


func test_tower_tacking_drm_towing() -> void:
	var t := _t()
	var twin := _ship("twin", Vector2i(5, 9))
	_w()
	assert_true(sc.begin_tow("t", "w"))
	var resolver := _resolver()
	assert_eq(resolver._calculate_tacking_drm(t), resolver._calculate_tacking_drm(twin) + 1)


# --- no anchoring in a tow (ruling) ----------------------------------------------------

func test_no_anchoring_in_a_tow() -> void:
	var t := _t()
	var w := _w(false)
	t.anchor_ready = "bow"
	w.anchor_ready = "bow"
	var ctx := {"wind_speed": 3, "anchoring_here": true}
	assert_eq(AnchorRules.refusal(t, "A", {}, ctx, []), "", "precondition: she may anchor")
	assert_true(sc.begin_tow("t", "w"))
	assert_string_contains(AnchorRules.refusal(t, "A", {}, ctx, []), "cannot anchor")
	assert_string_contains(AnchorRules.refusal(w, "A", {}, ctx, []), "cannot anchor")
