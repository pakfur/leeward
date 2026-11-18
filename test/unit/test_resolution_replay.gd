extends GutTest
## ResolutionReplay alone, with a stand-in panel: the queue, Next, Resolve all, prompts, draining and
## cancelling. Plus GameController's pure helpers for the replay (filtered->raw log indices, when a
## replay is outlived by the phase).

const GameControllerScript = preload("res://scripts/core/game_controller.gd")
const COMBAT := TurnPhaseController.GamePhase.COMBAT_RESOLUTION
const DRIFT := TurnPhaseController.GamePhase.DRIFT_CALCULATION
const STATUS := TurnPhaseController.GamePhase.STATUS_ADJUSTMENT


class StubPanel extends RefCounted:
	signal next_pressed()
	signal resolve_all_pressed()
	var shown: Array = []  # [index, total, label, instant]
	var answer: Control = null
	var answer_calls: int = 0

	func show_step(_step: ResolutionStep, index: int, total: int, label: String, instant: bool) -> void:
		shown.append([index, total, label, instant])

	func set_answer_section(control: Control) -> void:
		answer_calls += 1
		if answer != null and is_instance_valid(answer) and answer != control:
			answer.free()
		answer = control


var replay: ResolutionReplay
var panel: StubPanel
var _shown: Array[int] = []
var _drained: int = 0
var _finished: int = 0


func before_each() -> void:
	replay = ResolutionReplay.new()
	add_child_autofree(replay)
	panel = StubPanel.new()
	replay.attach_panel(panel)
	_shown.clear()
	_drained = 0
	_finished = 0
	replay.step_shown.connect(func(_s: ResolutionStep, i: int) -> void: _shown.append(i))
	replay.drained.connect(func() -> void: _drained += 1)


func after_each() -> void:
	if panel.answer != null and is_instance_valid(panel.answer):
		panel.answer.free()


func _steps(n: int, phase: int = COMBAT) -> Array[ResolutionStep]:
	var out: Array[ResolutionStep] = []
	for i in n:
		var s := ResolutionStep.new()
		s.kind = "gunfire"
		s.phase = phase
		s.title = "step %d" % i
		out.append(s)
	return out


func _prompt() -> ResolutionStep:
	var s := ResolutionStep.new()
	s.kind = "prompt_maintenance"
	s.phase = STATUS
	s.prompt = {"step": "grapple"}
	return s


func _finish() -> void:
	_finished += 1


func test_next_walks_steps() -> void:
	replay.start("combat", [COMBAT] as Array[int])
	replay.append(_steps(3))
	assert_eq(_shown, [0] as Array[int], "the first step comes up at once")
	assert_eq(panel.shown[0], [0, 3, "Combat", false])
	replay.next()
	replay.next()
	assert_eq(_shown, [0, 1, 2] as Array[int])
	assert_eq(replay.current_index(), 2)
	replay.finish_when_drained(_finish)
	assert_eq(_drained, 0, "the last step stays on screen until Next")
	assert_true(replay.is_running())
	replay.next()
	assert_eq(_drained, 1)
	assert_eq(_finished, 1)
	assert_false(replay.is_running())
	assert_false(replay.resolving)


func test_resolve_all_stops_at_prompt() -> void:
	replay.start("post_combat", [DRIFT, STATUS] as Array[int])
	replay.append(_steps(3, DRIFT))
	var answer := Control.new()
	replay.push_prompt(_prompt(), answer)
	replay.finish_when_drained(_finish)
	replay.resolve_all()
	assert_eq(_shown, [0, 1, 2, 3] as Array[int], "every step up to and including the prompt")
	assert_true(panel.shown[1][3], "resolve all lands the dice instantly")
	assert_eq(panel.answer, answer, "the prompt's controls are up")
	assert_eq(_drained, 0, "the prompt is never skipped")
	replay.next()
	replay.resolve_all()
	assert_eq(replay.current_index(), 3, "Next and Resolve all wait for the answer")
	replay.prompt_answered()
	assert_null(panel.answer, "the answer section goes")
	assert_eq(_drained, 1, "nothing after the prompt: drained")
	assert_eq(_finished, 1)


func test_drained_fires_once() -> void:
	replay.start("combat", [COMBAT] as Array[int])
	replay.append(_steps(1))
	replay.finish_when_drained(_finish)
	replay.next()
	replay.next()
	replay.resolve_all()
	replay.finish_when_drained(_finish)
	assert_eq(_drained, 1)
	assert_eq(_finished, 1)


func test_finish_with_nothing_shown_drains_at_once() -> void:
	replay.start("post_combat", [DRIFT] as Array[int])
	replay.append(_steps(0))
	replay.finish_when_drained(_finish)
	assert_eq(_drained, 1)
	assert_eq(_shown, [] as Array[int])
	assert_eq(panel.shown.size(), 0, "the panel never drew a step")


func test_append_while_waiting_continues() -> void:
	replay.start("post_combat", [DRIFT, STATUS] as Array[int])
	replay.append(_steps(2, DRIFT))
	replay.resolve_all()
	assert_eq(replay.current_index(), 1)
	assert_eq(_drained, 0, "no finish asked for: the replay waits")
	replay.append(_steps(2, STATUS))
	assert_eq(_shown, [0, 1, 2] as Array[int], "the appended step comes up at once")
	assert_eq(panel.shown[2], [2, 4, "Status", false], "at the normal pace again")
	replay.next()
	replay.finish_when_drained(_finish)
	assert_eq(_drained, 0)
	replay.next()
	assert_eq(_drained, 1)


func test_prompt_pushed_while_waiting_comes_up() -> void:
	replay.start("post_combat", [DRIFT, STATUS] as Array[int])
	replay.append(_steps(1, DRIFT))
	replay.next()
	var answer := Control.new()
	replay.push_prompt(_prompt(), answer)
	assert_eq(replay.current_index(), 1)
	assert_eq(panel.answer, answer)


func test_cancel_emits_nothing() -> void:
	replay.start("post_combat", [DRIFT, STATUS] as Array[int])
	replay.append(_steps(2, DRIFT))
	var queued := Control.new()
	replay.push_prompt(_prompt(), queued)
	replay.finish_when_drained(_finish)
	replay.cancel()
	assert_false(replay.is_running())
	assert_false(replay.resolving)
	assert_false(is_instance_valid(queued), "an answer the panel never took is freed")
	replay.next()
	replay.resolve_all()
	replay.prompt_answered()
	replay.append(_steps(1))
	assert_eq(_drained, 0)
	assert_eq(_finished, 0)
	assert_eq(_shown, [0] as Array[int], "nothing more after the cancel")


func test_drain_callback_may_start_the_next_replay() -> void:
	var restart := func() -> void:
		replay.start("post_combat", [DRIFT] as Array[int])
		replay.append(_steps(1, DRIFT))
	replay.start("combat", [COMBAT] as Array[int])
	replay.append(_steps(1))
	replay.finish_when_drained(restart)
	replay.next()
	assert_true(replay.is_running(), "the new replay survives the old one's drain")
	assert_eq(replay.kind, "post_combat")
	assert_eq(replay.current_index(), 0)


# --- GameController helpers ------------------------------------------------------------------

func _ev(type: PhaseEvents.Type, phase: int, ship: String, target: String = "") -> PhaseEvents.PhaseEvent:
	return PhaseEvents.PhaseEvent.new(type, phase, ship, {}, target)


func test_raw_indices_map_filtered_events_to_the_log() -> void:
	var raw: Array[PhaseEvents.PhaseEvent] = [
		_ev(PhaseEvents.Type.FIRE, COMBAT, "a", "b"),
		_ev(PhaseEvents.Type.SIGNAL, COMBAT, "b"),  # dropped by the filter
		_ev(PhaseEvents.Type.DAMAGE, COMBAT, "b"),
		_ev(PhaseEvents.Type.CREW_TASK, DRIFT, "b"),  # dropped
		_ev(PhaseEvents.Type.DRIFT, DRIFT, "b"),
	]
	var filtered: Array = [raw[0].to_dict(), raw[2].to_dict(), raw[4].to_dict()]
	assert_eq(GameControllerScript.raw_indices(raw, filtered), PackedInt32Array([0, 2, 4]))


func test_raw_indices_unmatched_tail_points_past_the_log() -> void:
	var raw: Array[PhaseEvents.PhaseEvent] = [_ev(PhaseEvents.Type.FIRE, COMBAT, "a", "b")]
	var filtered: Array = [raw[0].to_dict(), _ev(PhaseEvents.Type.DRIFT, DRIFT, "x").to_dict()]
	assert_eq(GameControllerScript.raw_indices(raw, filtered), PackedInt32Array([0, 1]))


func test_replay_outlived_by_phase() -> void:
	var P := TurnPhaseController.GamePhase
	var post: Array[int] = [P.DRIFT_CALCULATION, P.STATUS_ADJUSTMENT, P.MORALE_CHECK, P.MESSAGE_DELIVERY]
	assert_false(GameControllerScript.replay_outlived("post_combat", post, P.MORALE_CHECK))
	assert_false(GameControllerScript.replay_outlived("post_combat", post, P.POST_COMBAT),
		"the post-combat replay runs on in POST_COMBAT")
	assert_true(GameControllerScript.replay_outlived("post_combat", post, P.END_TURN))
	assert_true(GameControllerScript.replay_outlived("post_combat", post, P.PLANNING))
	var combat: Array[int] = [P.COMBAT_RESOLUTION]
	assert_false(GameControllerScript.replay_outlived("combat", combat, P.COMBAT_RESOLUTION))
	assert_true(GameControllerScript.replay_outlived("combat", combat, P.DRIFT_CALCULATION))
	assert_true(GameControllerScript.replay_outlived("combat", combat, P.PLANNING))


func test_raw_indices_tell_apart_events_of_one_ship_by_their_data() -> void:
	var prep := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CREW_TASK, COMBAT, "b", {"code": "PBA"})
	var sail := PhaseEvents.PhaseEvent.new(PhaseEvents.Type.CREW_TASK, COMBAT, "b", {"code": "SAIL"})
	var raw: Array[PhaseEvents.PhaseEvent] = [prep, sail]
	assert_eq(GameControllerScript.raw_indices(raw, [sail.to_dict()]), PackedInt32Array([1]),
		"the hidden preparation is skipped, not matched")


func test_step_frame_distance() -> void:
	assert_eq(GameControllerScript.step_frame_distance(1.0, 13.0, 60.0, 1000.0, Vector2(1000, 800)), 13.0,
		"a lone ship: the close framing")
	var far := GameControllerScript.step_frame_distance(60.0, 13.0, 60.0, 1000.0, Vector2(1000, 800))
	assert_gt(far, 13.0, "a distant target pulls the camera back")


# --- GameController: combat playback through the replay ---------------------------------------

class StubContextPanel extends Control:
	var contents: Array = []

	func set_context_title(_t: String) -> void:
		pass

	func set_context_content(node: Control) -> void:
		contents.append(node)
		if node.get_parent() == null:
			add_child(node)


func _with_combat_log(events: Array[PhaseEvents.PhaseEvent]) -> PhaseEvents.PhaseLog:
	var combat_log := PhaseEvents.PhaseLog.new()
	combat_log.turn = 9999  # never a stored turn: events_for reads this log
	combat_log.events = events
	return combat_log


func _combat_controller(ctx: StubContextPanel) -> Node:
	var gc: Node = GameControllerScript.new()  # not in the tree: _ready (scene set-up) does not run
	autofree(gc)
	gc.context_panel = ctx
	return gc


func _run_combat(combat_log: PhaseEvents.PhaseLog, body: Callable) -> void:
	var pc := GameState.phase_controller
	var old_log := GameState.turn_log
	var old_phase := pc.current_phase
	GameState.turn_log = combat_log
	pc.current_phase = TurnPhaseController.GamePhase.COMBAT_RESOLUTION
	pc.combat_step = TurnPhaseController.CombatStep.RESOLVE
	body.call(pc)
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.current_phase = old_phase
	GameState.turn_log = old_log


func test_no_steps_still_completes_combat() -> void:
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	var combat_log := _with_combat_log([_ev(PhaseEvents.Type.HOLD_FIRE, COMBAT, "a")])
	_run_combat(combat_log, func(pc: TurnPhaseController) -> void:
		gc._on_combat_log_ready(combat_log)
		assert_ne(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION,
			"on_combat_playback_completed reached the server")
		assert_false(gc._combat_playback_active)
		assert_eq(ctx.contents.size(), 0, "the panel never opens")
		assert_false(gc._replay_running()))


func test_combat_steps_hold_the_server_until_the_last_next() -> void:
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	var combat_log := _with_combat_log([
		_ev(PhaseEvents.Type.FIRE, COMBAT, "a", "b"),
		_ev(PhaseEvents.Type.MORALE_CHECK, COMBAT, "b"),
	])
	_run_combat(combat_log, func(pc: TurnPhaseController) -> void:
		gc._on_combat_log_ready(combat_log)
		assert_eq(ctx.contents.size(), 1, "the resolution panel is in the side panel")
		assert_true(ctx.contents[0] is ResolutionPanel)
		assert_true(gc._replay_running())
		assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION, "held")
		gc.resolution_replay.next()
		assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION, "still held")
		gc.resolution_replay.next()
		assert_ne(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION, "released once")
		assert_false(gc._replay_running()))


func test_leaving_mid_replay_reports_nothing() -> void:
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	gc.back_to_scenarios_requested.connect(func() -> void: pass)
	var combat_log := _with_combat_log([_ev(PhaseEvents.Type.FIRE, COMBAT, "a", "b")])
	_run_combat(combat_log, func(pc: TurnPhaseController) -> void:
		gc._on_combat_log_ready(combat_log)
		gc._leave_game()
		gc.resolution_replay.next()
		gc._skip_combat_playback()
		assert_eq(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION,
			"no completion after leaving")
		assert_false(gc._replay_running()))


func test_reset_mid_combat_replay_lets_the_next_combat_play() -> void:
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	var combat_log := _with_combat_log([_ev(PhaseEvents.Type.FIRE, COMBAT, "a", "b")])
	_run_combat(combat_log, func(pc: TurnPhaseController) -> void:
		gc._on_combat_log_ready(combat_log)
		assert_true(gc._replay_running())
		gc._on_game_started({})  # Developer UI reset mid-replay
		assert_false(gc._combat_playback_active, "the dropped replay does not hold the next combat")
		assert_false(gc._replay_running())
		gc._on_combat_log_ready(combat_log)
		assert_true(gc._replay_running(), "the next combat plays")
		gc.resolution_replay.next()
		assert_ne(pc.current_phase, TurnPhaseController.GamePhase.COMBAT_RESOLUTION, "and completes"))


func test_outlived_combat_replay_clears_the_playback_flag() -> void:
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	var combat_log := _with_combat_log([_ev(PhaseEvents.Type.FIRE, COMBAT, "a", "b")])
	_run_combat(combat_log, func(_pc: TurnPhaseController) -> void:
		gc._on_combat_log_ready(combat_log)
		gc._on_phase_changed(TurnPhaseController.GamePhase.END_TURN)
		assert_false(gc._replay_running(), "outlived: dropped")
		assert_false(gc._combat_playback_active))


# --- GameController: a ship lost off the map in drift (Review Focus 4) ------------------------

func _map_ship(id: String, side: int, hex: Vector2i) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": side, "ship_name": id, "ship_type": "frigate_38",
		"name": "38-gun Frigate", "nationality": "British", "rating": 38, "class": 3,
		"maneuverability": "C", "speed_type": "F/F", "rigging_hp": [5, 5, 6, 6],
		"hull_hp": [5, 5, 5, 6], "crew_count": [3, 3, 3, 3], "marine_count": 2,
		"gun_factors": {"lg": 6, "mg": 0, "cr": 4},
	})
	state.hex_position = hex
	var rigging: Array[int] = [5, 5, 6, 6]
	state.rigging_current_hp = rigging
	GameState.ships[id] = state
	GameState.ships_by_side[side].append(id)
	return state


func _drift(ship: String, roll: int, hex: Vector2i) -> PhaseEvents.PhaseEvent:
	return PhaseEvents.PhaseEvent.new(PhaseEvents.Type.DRIFT, DRIFT, ship,
		{"roll": roll, "needed": 5, "modifier": 0, "drifted": true, "from": {"q": hex.x, "r": hex.y}})


func test_ship_lost_in_drift_keeps_her_view_until_her_drift_step() -> void:
	var P := TurnPhaseController.GamePhase
	var pc := GameState.phase_controller
	var old_ships := GameState.ships.duplicate()
	var old_by_side := GameState.ships_by_side.duplicate(true)
	var old_log := GameState.turn_log
	var old_phase := pc.current_phase
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var keeper := _map_ship("keeper", 0, Vector2i(0, 0))
	var lost := _map_ship("lost", 1, Vector2i(20, 0))
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	for id in ["keeper", "lost"]:
		var view := Node3D.new()
		autofree(view)
		gc.ship_views[id] = view
	GameState.turn_log = _with_combat_log([_drift("keeper", 3, keeper.hex_position),
		_drift("lost", 7, lost.hex_position)])

	gc._on_phase_changed(P.DRIFT_CALCULATION)  # the state before drift is recorded
	lost.removed_from_map = true  # drift carries her off a `none` edge (III.C)
	for phase in [P.STATUS_ADJUSTMENT, P.MORALE_CHECK, P.MESSAGE_DELIVERY]:
		gc._on_phase_changed(phase)
	pc.current_phase = P.POST_COMBAT
	gc._on_phase_changed(P.POST_COMBAT)

	assert_true(gc._replay_running(), "the post-combat replay is on the keeper's drift step")
	assert_eq(gc.resolution_replay.current_index(), 0)
	assert_true(gc.ship_views.has("lost"), "her view stays while the replay shows her afloat")
	gc.resolution_replay.next()
	assert_false(gc.ship_views.has("lost"), "her drift step shown: the view leaves")
	gc.resolution_replay.next()
	assert_false(gc._replay_running())

	pc.current_phase = old_phase
	GameState.turn_log = old_log
	GameState.ships = old_ships
	GameState.ships_by_side = old_by_side


# --- GameController: prompts as steps (Task 6) ---------------------------------------------

const GRAPPLE_OPTIONS := [{"ship_id": "a", "target_id": "b", "needed": 2, "percent": 30}]


func _answer_panel(gc: Node, panel_name: String) -> Node:
	return gc.resolution_panel.find_child(panel_name, true, false)


func test_refusal_keeps_prompt() -> void:
	var old_log := GameState.turn_log
	GameState.turn_log = _with_combat_log([])
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	gc._on_maintenance_orders_requested(0, "grapple", GRAPPLE_OPTIONS)
	assert_true(gc._replay_running(), "the prompt opens the post-combat replay")
	assert_eq(gc.resolution_replay.kind, "post_combat")
	var prompt: ResolutionStep = gc.resolution_replay.current_step()
	assert_eq(prompt.kind, "prompt_maintenance")
	var panel: MaintenanceOrdersPanel = _answer_panel(gc, "MaintenanceOrdersPanel")
	assert_not_null(panel, "the orders are the step's answer section")
	# Not in STATUS_ADJUSTMENT: the server refuses.
	panel.get_node("DoneButton").emit_signal("pressed")
	assert_ne(panel.error_text(), "", "the reason shows on the step")
	assert_eq(gc.resolution_replay.current_step(), prompt, "the replay stays on the prompt")
	assert_true(gc._replay_running())
	gc._cancel_resolution_replay()
	GameState.turn_log = old_log


func test_bear_off_prompt_is_a_replay_of_its_own() -> void:
	var pc := GameState.phase_controller
	var old_phase := pc.current_phase
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	var situation := MovementTypes.BearOffSituation.new()
	situation.ship_id = "a"
	situation.blocker_id = "b"
	situation.eligible.assign(["port"])
	situation.number = 5
	situation.chance = 0.5
	gc._on_bear_off_decision_requested(0, situation)
	assert_true(gc._replay_running())
	assert_eq(gc.resolution_replay.kind, "bear_off")
	var prompt: ResolutionStep = gc.resolution_replay.current_step()
	assert_eq(prompt.kind, "prompt_bear_off")
	assert_false(gc.display_states.active(), "movement playback keeps the ship views")
	var panel: BearOffPanel = _answer_panel(gc, "BearOffPanel")
	assert_not_null(panel)
	panel.get_node("Choice_collide").emit_signal("pressed")
	assert_ne(panel.error_text(), "", "no decision pending: refused, shown on the step")
	assert_eq(gc.resolution_replay.current_step(), prompt)
	pc.current_phase = TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION
	gc._prompt_answered(prompt)  # as after an accepted choice
	assert_false(gc._replay_running(), "answered: the bear-off replay is over")
	assert_eq((ctx.contents.back() as Node).name, "MovementPanel", "the side panel shows movement again")
	pc.current_phase = old_phase


func test_maintenance_prompts_join_the_post_combat_replay() -> void:
	var P := TurnPhaseController.GamePhase
	var pc := GameState.phase_controller
	var old_ships := GameState.ships.duplicate()
	var old_by_side := GameState.ships_by_side.duplicate(true)
	var old_log := GameState.turn_log
	var old_phase := pc.current_phase
	GameState.ships.clear()
	GameState.ships_by_side = {0: [], 1: []}
	var a := _map_ship("a", 0, Vector2i(0, 0))
	_map_ship("b", 1, Vector2i(1, 0))
	var ctx := StubContextPanel.new()
	add_child_autofree(ctx)
	var gc := _combat_controller(ctx)
	for id in ["a", "b"]:
		var view := Node3D.new()  # a stand-in: no new ShipView is made off the scene
		autofree(view)
		gc.ship_views[id] = view
	var turn_log := _with_combat_log([_drift("a", 3, a.hex_position)])
	GameState.turn_log = turn_log
	gc._on_phase_changed(P.DRIFT_CALCULATION)
	gc._on_phase_changed(P.STATUS_ADJUSTMENT)

	gc._on_maintenance_orders_requested(0, "grapple", GRAPPLE_OPTIONS)
	var replay: ResolutionReplay = gc.resolution_replay
	assert_eq(replay.current_step().kind, "drift", "the drift already resolved comes first")
	assert_eq(replay.steps().size(), 2)
	replay.next()
	var first: ResolutionStep = replay.current_step()
	assert_eq(first.kind, "prompt_maintenance")
	replay.next()
	assert_eq(replay.current_step(), first, "Next does not pass a prompt")

	# Accepted: the server rolls the grapple and asks for the ungrapple orders, before the answer
	# is taken off the step.
	turn_log.events.append(PhaseEvents.PhaseEvent.new(PhaseEvents.Type.GRAPPLE, STATUS, "a",
		{"roll": 1, "needed": 2, "total": 1, "success": true}, "b"))
	gc._on_maintenance_orders_requested(0, "ungrapple", GRAPPLE_OPTIONS)
	assert_eq(replay.current_step(), first, "still on the first prompt")
	gc._prompt_answered(first)
	assert_eq(replay.current_step().kind, "grapple", "the roll, then")
	replay.next()
	var second: ResolutionStep = replay.current_step()
	assert_eq(second.kind, "prompt_maintenance")
	assert_eq(second.prompt.get("step"), "ungrapple", "the second prompt, in the same replay")

	turn_log.events.append(PhaseEvents.PhaseEvent.new(PhaseEvents.Type.MORALE_CHECK, P.MORALE_CHECK, "b",
		{"roll": 7, "rating": 4, "passed": true}))
	gc._prompt_answered(second)
	gc._on_phase_changed(P.MORALE_CHECK)
	gc._on_phase_changed(P.MESSAGE_DELIVERY)
	pc.current_phase = P.POST_COMBAT
	gc._on_phase_changed(P.POST_COMBAT)
	assert_true(gc._replay_running(), "POST_COMBAT continues the running replay")
	assert_eq(replay.current_index(), 4, "not restarted")
	assert_eq(replay.current_step().kind, "morale")
	assert_null(gc.end_turn_panel, "End Turn waits for the replay")
	replay.next()
	assert_false(gc._replay_running())
	assert_not_null(gc.end_turn_panel, "End Turn after the last step")

	gc._clear_end_turn_ui()
	pc.current_phase = old_phase
	GameState.turn_log = old_log
	GameState.ships = old_ships
	GameState.ships_by_side = old_by_side
