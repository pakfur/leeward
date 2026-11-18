extends GutTest
## The view of a tow (towing spec §13): the towed ship posed by TOW_FOLLOW and glided at her tower's
## pace, TOW_HELD played as a special event, the hawser from the tower's stern to the tow's bow, the
## TOWING / IN TOW badges and the read-only Tow station of the crew overlay.
## Tower t: bow (5, 5), facing 3, stern (6, 5). Towed w: bow (7, 5), facing 3, stern (8, 5).


var sc: ShipStateController
var grid: HexGrid


func before_all() -> void:
	DataManager.load_movement_allowance_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_turning_table()


func before_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	sc = autofree(ShipStateController.new(GameState))
	grid = HexGrid.new()


func after_each() -> void:
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}


func _ship(id: String, hex: Vector2i, facing: int = 3, side: int = 0) -> ShipState:
	var s := ShipState.new()
	s.ship = Ship.from_dict({
		"ship_id": id, "side": side, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F",
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6],
		"crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	s.hex_position = hex
	s.facing = facing
	s.sail_state = "FS"
	s.crew_quality = "C"
	s.crew_auto = false
	s.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	s.hull_current_hp = [5, 5, 5, 6] as Array[int]
	s.crew_count = [3, 3, 3, 3] as Array[int]
	s.marine_count = 2
	GameState.ships[id] = s
	GameState.ships_by_side[side].append(id)
	return s


func _pair() -> Array:
	var t := _ship("t", Vector2i(5, 5))
	var w := _ship("w", Vector2i(7, 5))
	assert_true(sc.begin_tow("t", "w"))
	return [t, w]


## One step west on `impulse` for the ship at (`bow`, facing 3), as `type`.
func _step(ship_id: String, impulse: int, bow: Vector2i,
		type: MovementTypes.ResolutionEventType) -> MovementTypes.ResolutionEvent:
	var ev := MovementTypes.ResolutionEvent.new(ship_id, impulse, type)
	ev.from_hex = bow
	ev.from_facing = 3
	ev.to_hex = bow + HexGrid.DIRECTIONS[3]
	ev.facing = 3
	return ev


## ============================================================================
## Playback
## ============================================================================

func test_posed_includes_tow_follow() -> void:
	var log := MovementTypes.ResolutionLog.new(1)
	var move := _step("t", 0, Vector2i(5, 5), MovementTypes.ResolutionEventType.MOVE)
	var follow := _step("w", 0, Vector2i(7, 5), MovementTypes.ResolutionEventType.TOW_FOLLOW)
	var posed: Array = MovementResolutionPlaybackController._posed_in([move, follow], log, {})
	assert_eq(posed.size(), 2)
	assert_true(posed.has(move))
	assert_true(posed.has(follow))
	assert_eq(MovementResolutionPlaybackController._special_events([move, follow], []), [])


func test_tow_held_is_special() -> void:
	var held := MovementTypes.ResolutionEvent.new("t", 1, MovementTypes.ResolutionEventType.TOW_HELD)
	held.detail = "her tow could not follow"
	assert_eq(MovementResolutionPlaybackController._special_events([held], []), [held])


func test_plot_steps_for_tow_is_her_towers() -> void:
	var log := MovementTypes.ResolutionLog.new(1)
	log.plot_steps = {"t": 2, "x": 4}
	log.towed_by = {"w": "t"}
	assert_eq(MovementResolutionPlaybackController.plot_steps_for(log, "t"), 2)
	assert_eq(MovementResolutionPlaybackController.plot_steps_for(log, "w"), 2, "the tow glides at her tower's pace")
	assert_eq(MovementResolutionPlaybackController.plot_steps_for(log, "x"), 4)
	assert_eq(MovementResolutionPlaybackController.plot_steps_for(log, "nobody"), 0)


func test_tow_glides_at_tower_pace() -> void:
	var log := MovementTypes.ResolutionLog.new(1)
	log.plot_steps = {"t": 2, "x": 4}
	log.towed_by = {"w": "t"}
	log.longest_plot = 4
	var clocks: Array = [1.0, 2.0, 3.0, 4.0]
	var t_events: Array = [_step("t", 1, Vector2i(5, 5), MovementTypes.ResolutionEventType.MOVE),
		_step("t", 3, Vector2i(4, 5), MovementTypes.ResolutionEventType.MOVE)]
	var w_events: Array = [_step("w", 1, Vector2i(7, 5), MovementTypes.ResolutionEventType.TOW_FOLLOW),
		_step("w", 3, Vector2i(6, 5), MovementTypes.ResolutionEventType.TOW_FOLLOW)]
	var t_track := MovementResolutionPlaybackController.track_for(t_events, grid, -270.0, clocks, log.longest_plot,
		MovementResolutionPlaybackController.plot_steps_for(log, "t"))
	var w_track := MovementResolutionPlaybackController.track_for(w_events, grid, -270.0, clocks, log.longest_plot,
		MovementResolutionPlaybackController.plot_steps_for(log, "w"))
	assert_eq(t_track.spans, [[0.0, 2.0], [2.0, 4.0]])
	assert_eq(w_track.spans, t_track.spans)
	var own_pace := MovementResolutionPlaybackController.track_for(w_events, grid, -270.0, clocks, log.longest_plot, 0)
	assert_ne(own_pace.spans, t_track.spans, "without the tower's count she would jump a unit a step")


## ============================================================================
## Tow line
## ============================================================================

func test_tow_line_segments() -> void:
	var pair := _pair()
	var segs: Array = TowLines.segments(pair, grid)
	assert_eq(segs.size(), 1)
	var from := grid.axial_to_world(6, 5)
	var to := grid.axial_to_world(7, 5)
	assert_almost_eq(segs[0][0].x, from.x, 0.0001)
	assert_almost_eq(segs[0][0].z, from.z, 0.0001)
	assert_almost_eq(segs[0][1].x, to.x, 0.0001)
	assert_almost_eq(segs[0][1].z, to.z, 0.0001)
	assert_almost_eq(segs[0][0].y, GrappleLines.ROPE_HEIGHT, 0.0001)
	assert_almost_eq(segs[0][1].y, GrappleLines.ROPE_HEIGHT, 0.0001)


func test_no_tow_no_line() -> void:
	var a := _ship("t", Vector2i(5, 5))
	var b := _ship("w", Vector2i(7, 5))
	assert_eq(TowLines.segments([a, b], grid), [])


func test_tow_off_map_no_line() -> void:
	var pair := _pair()
	(pair[1] as ShipState).removed_from_map = true
	assert_eq(TowLines.segments(pair, grid), [])


## ============================================================================
## Badges
## ============================================================================

func test_badges() -> void:
	var pair := _pair()
	var t: ShipState = pair[0]
	var w: ShipState = pair[1]
	assert_eq(PlanningSailUi.status_badge(t), "TOWING")
	assert_true(PlanningSailUi.can_plot_movement(t))
	assert_eq(PlanningSailUi.status_badge(w), "IN TOW")
	assert_false(PlanningSailUi.can_plot_movement(w))
	assert_string_contains(PlanningSailUi.movement_block_reason(w), "12.A.6")


func test_held_tower_cannot_plot() -> void:
	var pair := _pair()
	var t: ShipState = pair[0]
	var w: ShipState = pair[1]
	var enemy := _ship("e", Vector2i(8, 6), 3, 1)
	sc.add_grapple("w", "e")
	assert_true(w.is_linked())
	assert_eq(PlanningSailUi.status_badge(t), "TOWING")
	assert_false(PlanningSailUi.can_plot_movement(t), "her tow is grappled: she is held (8.C.7)")
	assert_string_contains(PlanningSailUi.movement_block_reason(t), "8.C.7")
	assert_not_null(enemy)


func test_other_badges_win() -> void:
	var pair := _pair()
	var t: ShipState = pair[0]
	var w: ShipState = pair[1]
	t.anchor = {"hex": t.hex_position, "end": "bow", "springs": false, "cable": 0, "veered": 0,
		"swing_dir": 0, "wind_dir": 0, "turn": 1}
	assert_eq(PlanningSailUi.status_badge(t), "ANCHORED")
	w.status = ShipState.Status.CAPTURED
	assert_eq(PlanningSailUi.status_badge(w), "PRIZE")


## ============================================================================
## Tow station
## ============================================================================

func _tow_station(ship: ShipState) -> Dictionary:
	var ctx := CrewRules.context(GameState, ship)
	for st in CrewRules.stations(ship, {"assignments": {}, "orders": {}}, ctx):
		if st["id"] == TowRules.STATION:
			return st
	return {}


func test_tow_station() -> void:
	var pair := _pair()
	var t: ShipState = pair[0]
	var w: ShipState = pair[1]
	var st := _tow_station(t)
	assert_false(st.is_empty(), "a towing ship has the Tow station")
	assert_eq(st["label"], "Tow")
	assert_eq(st["accepts"], "none")
	assert_eq(st["note"], "Towing %s" % w.ship_name)
	assert_eq(st["disabled_reason"], CrewRules.TOW_REFUSAL)
	assert_eq(_tow_station(w)["note"], "In tow of %s" % t.ship_name)
	var ctx := CrewRules.context(GameState, t)
	assert_eq(CrewRules.refusal(t, {"assignments": {}, "orders": {}}, ctx, 2, TowRules.STATION),
		CrewRules.TOW_REFUSAL)


func test_no_tow_no_station() -> void:
	var a := _ship("a", Vector2i(5, 5))
	assert_true(_tow_station(a).is_empty())
	sc.set_tow_prepared("a", true)
	assert_eq(_tow_station(a)["note"], "Ready to pass a tow")
