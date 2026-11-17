class_name TurnPhaseController
extends Node
## TurnPhaseController - Server-authoritative turn phase management
## Handles all phase transitions and validates player readiness

signal phase_changed(new_phase: int)
signal turn_changed(turn_number: int)
signal resolution_log_ready(log: MovementTypes.ResolutionLog)
signal fire_declaration_requested()
signal combat_log_ready(log: PhaseEvents.PhaseLog)
signal game_over(result: Dictionary)
## Movement playback reached a potential collision of a prompted player's ship (6.D.3): the player
## answers with player_submit_bear_off.
signal bear_off_decision_requested(situation: MovementTypes.BearOffSituation)
## STATUS_ADJUSTMENT waits for a prompted player's grapple (SoP V.C) or ungrapple (V.D) orders, or
## prize-crew sizes (10.G.6): `step` is "grapple", "ungrapple" or "prize_size", `options` that
## player's choices (see maintenance_options).
## The player answers with player_submit_maintenance_orders.
signal maintenance_orders_requested(player_id: int, step: String, options: Array)

enum GamePhase {
	SETUP,
	ENVIRONMENT,
	PLANNING,
	MOVEMENT_RESOLUTION,
	COMBAT_RESOLUTION,
	DRIFT_CALCULATION,
	STATUS_ADJUSTMENT,
	MORALE_CHECK,
	MESSAGE_DELIVERY,
	POST_COMBAT,
	END_TURN
}

## Steps inside COMBAT_RESOLUTION: orders are declared (hidden, simultaneous), then resolved.
enum CombatStep { NONE, DECLARE, RESOLVE }

## Waiting steps inside STATUS_ADJUSTMENT (Maintenance sub-phases C and D, 8.C): the phase waits in
## GRAPPLE, then in UNGRAPPLE, only while a prompted player has a choice to make; PRIZE (10.G.6, after
## the crew tasks are counted) when a reorganization has ended with more boarders than the minimum.
enum MaintenanceStep { NONE, GRAPPLE, UNGRAPPLE, PRIZE }

var current_phase: GamePhase = GamePhase.SETUP
var current_turn: int = 0
var players_ready: Array[bool] = [false, false]
var is_server: bool = true  # Set to true on server, false on clients
var _pending_resolution_log: MovementTypes.ResolutionLog = null
var combat_step: CombatStep = CombatStep.NONE
var _fire_orders: Array = [[], []]  # per player: Array[GunneryTypes.FireOrder]
var _marine_orders: Array = [[], []]  # per player: Array of {ship_id, target_id} (7.G)
var _fire_ready: Array[bool] = [false, false]
## Players whose ships' bear-off decisions are asked for (6.D.3); everyone else's ships decide by
## StubAI.bear_off_choice. Empty (no prompts) unless the game wires a human player in.
var bear_off_prompt_player_ids: Array[int] = []
## The human players (GameState.start_scenario). Their ships get a default course at planning start.
var human_player_ids: Array[int] = []
## ship_id -> {course: Array (step dicts), crew_auto: bool, boarding: String}: the planning start
## state of every ship of a human player (Cancel / Reset course restore it). Cleared at END_TURN.
var planning_snapshot: Dictionary = {}
## This turn's answers: ship_id -> {choice, segment} (see MovementResolver.run).
var _bear_off_decisions: Dictionary = {}
## Players asked for their grapple and ungrapple orders (8.C); everyone else's ships are ordered by
## StubAI. Empty (no prompts, no pause) unless the game wires a human player in, as for bear-off.
var maintenance_prompt_player_ids: Array[int] = []
## Players the server plays (StubAI): their plan counts as submitted as soon as PLANNING begins.
## Set by GameState.start_scenario; empty in headless tests, which submit for both sides.
var ai_player_ids: Array[int] = []
var maintenance_step: MaintenanceStep = MaintenanceStep.NONE
## Prompted players whose orders for the current maintenance step are still awaited.
var _maintenance_waiting: Array[int] = []
## The current maintenance step's options per prompted player (player_id -> Array) and the orders
## received ([ship_id, other_id] pairs, all players).
var _maintenance_options: Dictionary = {}
var _maintenance_orders: Array = []
## The resolver's RNG state when this g-t's movement resolution first ran: a re-run after a bear-off
## answer starts from it, so the dice before the decision (poor maneuvering, tacking, contests) repeat.
var _resolution_rng_state: int = 0
## Set when END_TURN finds a victory: {"winner", "reason", "points", "turn"}. {} while the game runs.
var game_result: Dictionary = {}

# Reference to game state (authoritative on server)
var game_state: Node = null

func _init(state: Node = null) -> void:
	game_state = state if state else GameState

func start_new_game() -> void:
	"""Initialize a new game - SERVER ONLY"""
	if not is_server:
		push_error("TurnPhaseController: Cannot start game on client")
		return

	current_turn = 1
	game_result = {}
	players_ready = [false, false] as Array[bool]
	combat_step = CombatStep.NONE
	_fire_orders = [[], []]
	_marine_orders = [[], []]
	_fire_ready = [false, false]
	_pending_resolution_log = null
	_bear_off_decisions = {}
	_reset_maintenance()
	current_phase = GamePhase.SETUP  # Start in SETUP so advance_phase() enters ENVIRONMENT

	Trace.trace_log("TurnPhase", "Game started - Turn: %d" % current_turn)
	turn_changed.emit(current_turn)  # listeners (and GameState's mirror) see turn 1 of the new game
	advance_phase()  # This will transition SETUP -> ENVIRONMENT

func advance_phase() -> void:
	"""Progress to the next game phase - SERVER ONLY"""
	if not is_server:
		push_error("TurnPhaseController: Cannot advance phase on client")
		return
	if not game_result.is_empty():
		return  # Game over: the phase stays END_TURN
	if maintenance_step != MaintenanceStep.NONE:
		push_warning("TurnPhaseController: STATUS_ADJUSTMENT waits for maintenance orders; advance_phase ignored")
		return

	match current_phase:
		GamePhase.SETUP:
			_enter_environment_phase()
		GamePhase.ENVIRONMENT:
			_enter_planning_phase()
		GamePhase.PLANNING:
			_enter_movement_resolution_phase()
		GamePhase.MOVEMENT_RESOLUTION:
			_enter_combat_resolution_phase()
		GamePhase.COMBAT_RESOLUTION:
			_enter_drift_calculation_phase()
		GamePhase.DRIFT_CALCULATION:
			_enter_status_adjustment_phase()
		GamePhase.STATUS_ADJUSTMENT:
			_enter_morale_check_phase()
		GamePhase.MORALE_CHECK:
			_enter_message_delivery_phase()
		GamePhase.MESSAGE_DELIVERY:
			_enter_post_combat_phase()
		GamePhase.POST_COMBAT:
			push_warning("TurnPhaseController: POST_COMBAT waits for player_end_turn(); advance_phase ignored")
		GamePhase.END_TURN:
			_start_new_turn()

func _enter_environment_phase() -> void:
	"""SERVER ONLY: Enter environment phase and update conditions"""
	current_phase = GamePhase.ENVIRONMENT
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: ENVIRONMENT")

	# Update environment (using controller for RNG management and shader updates)
	if game_state.environment:
		if game_state.environment_controller:
			# Use controller which manages RNG and updates shader
			game_state.environment_controller.tick_environment(game_state.environment, current_turn)
		else:
			push_warning("TurnPhaseController: No environment_controller available for tick")

		Trace.trace_log("TurnPhase", "Environment: Wind %s (%d), Speed %s (%d), Sea %s (%d)" % [
			game_state.environment.get_wind_direction_name(),
			game_state.environment.wind_direction,
			game_state.environment.get_wind_speed_name(),
			game_state.environment.wind_speed,
			game_state.environment.get_sea_state_name(),
			game_state.environment.sea_state
		])

	advance_phase()

func _enter_planning_phase() -> void:
	"""SERVER ONLY: Enter planning phase"""
	current_phase = GamePhase.PLANNING
	players_ready = [false, false]
	Trace.trace_log("TurnPhase", "Phase: PLANNING - Players plot their actions")

	# 10.A.2: boarding needs the two ships fouled or grappled at the start of the g-t.
	if game_state.get("boarding_controller") != null:
		game_state.boarding_controller.take_link_snapshot()
	_store_default_courses()
	if game_state.stub_ai:
		game_state.stub_ai.plot_all_ai_ships()
	for p in ai_player_ids:
		if p >= 0 and p < players_ready.size():
			players_ready[p] = true
	# Announced last: listeners (the view) find the default courses stored and the AI's plan in.
	phase_changed.emit(current_phase)

## Stores 6.G.2's default course for each human ship that can plot and records every human ship's
## planning start state (planning_snapshot).
func _store_default_courses() -> void:
	planning_snapshot = {}
	for ship in game_state.ships.values():
		var s: ShipState = ship
		if not human_player_ids.has(s.player_id):
			continue
		var course: Array = []
		if DefaultCourse.can_plot(s):
			course = DefaultCourse.as_dicts(DefaultCourse.for_ship(game_state, s))
			game_state.ship_controller.set_plotted_movement(s.ship_id, course)
		var orders = s.plotted_actions.get("crew_orders", {})
		planning_snapshot[s.ship_id] = {
			"course": course.duplicate(true),
			"crew_auto": s.crew_auto,
			"boarding": str(orders.get("boarding", "")) if orders is Dictionary else "",
		}


## Read-only: the course the ship had when planning began ([] when none).
func start_of_turn_course(ship_id: String) -> Array:
	var snap: Dictionary = planning_snapshot.get(ship_id, {})
	return (snap.get("course", []) as Array).duplicate(true)


## SERVER ONLY: Cancel. Puts every ship of the player back to its planning start state: course,
## crew plot, sail order, Automatic switch and boarding order. Crew tasks in progress stay.
## Returns "" or the reason it is refused.
func player_reset_planning(player_id: int) -> String:
	var why := _planning_request_error(player_id)
	if why != "":
		return why
	for ship_id in planning_snapshot:
		var ship: ShipState = game_state.get_ship(ship_id)
		if ship == null or ship.player_id != player_id:
			continue
		_restore_snapshot(ship_id, true)
	Trace.trace_log("TurnPhase", "Player %d reset the planning" % player_id)
	return ""


## SERVER ONLY: the card's Reset course: that ship's course back to its planning start course.
func player_reset_course(player_id: int, ship_id: String) -> String:
	var why := _course_request_error(player_id, ship_id)
	if why != "":
		return why
	if not planning_snapshot.has(ship_id):
		return "no planning start course for %s" % ship_id
	_restore_snapshot(ship_id, false)
	return ""


func _restore_snapshot(ship_id: String, with_crew: bool) -> void:
	var snap: Dictionary = planning_snapshot[ship_id]
	var course: Array = (snap["course"] as Array).duplicate(true)
	if not course.is_empty():
		game_state.ship_controller.set_plotted_movement(ship_id, course)
	else:
		game_state.ship_controller.clear_plotted_movement(ship_id)
	if with_crew:
		game_state.ship_controller.clear_crew_plot(ship_id)
		game_state.ship_controller.set_crew_auto(ship_id, snap["crew_auto"])
		game_state.ship_controller.set_crew_orders(ship_id,
				{"sail_target": "", "boarding": snap["boarding"]})


func _planning_request_error(player_id: int) -> String:
	if not is_server:
		push_error("TurnPhaseController: Cannot reset planning on client")
		return "planning is reset on the server only"
	if not game_result.is_empty():
		return "the game is over"
	if current_phase != GamePhase.PLANNING:
		return "planning can be reset in the planning phase only"
	if player_id < 0 or player_id >= players_ready.size():
		return "invalid player %d" % player_id
	if players_ready[player_id]:
		return "this player's plan is already submitted"
	return ""


func player_submit_plan(player_id: int) -> bool:
	"""SERVER ONLY: Validate and accept player plan submission"""
	if not is_server:
		push_error("TurnPhaseController: Cannot submit plan on client")
		return false

	if not game_result.is_empty():
		return false

	if current_phase != GamePhase.PLANNING:
		push_error("[Server] Cannot submit plan outside PLANNING phase")
		return false

	if player_id < 0 or player_id >= players_ready.size():
		push_error("[Server] Invalid player_id: %d" % player_id)
		return false

	players_ready[player_id] = true
	Trace.trace_log("TurnPhase", "Player %d submitted plan" % player_id)

	# Check if all players are ready
	if players_ready.all(func(is_ready): return is_ready):
		Trace.trace_log("TurnPhase", "All players ready, advancing phase")
		# End Planning: every crew plot is made legal against its final movement plot.
		if game_state.crew_task_controller:
			game_state.crew_task_controller.finalize_plots()
		advance_phase()

	return true

## SERVER ONLY: the player withdraws a ship's movement plot to plot it again (other plotted
## orders, such as a sail change, are kept). Returns "" or the reason it is refused.
func player_clear_movement(player_id: int, ship_id: String) -> String:
	if not is_server:
		push_error("TurnPhaseController: Cannot clear a movement plot on client")
		return "movement plots are changed on the server only"
	if not game_result.is_empty():
		return "the game is over"
	if current_phase != GamePhase.PLANNING:
		return "movement can only be re-plotted in the planning phase"
	if player_id < 0 or player_id >= players_ready.size():
		return "invalid player %d" % player_id
	if players_ready[player_id]:
		return "this player's plan is already submitted"
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "no ship %s" % ship_id
	if ship.player_id != player_id:
		return "%s is not this player's ship" % ship_id
	game_state.ship_controller.set_plotted_movement(ship_id, [])
	Trace.trace_log("TurnPhase", "Player %d cleared the movement plot of %s" % [player_id, ship_id])
	return ""


## SERVER ONLY: appends one step to the ship's stored course (the always-on course editing). The
## hex must be a valid next move from the course end (validated as the plotting session's
## SELECT_HEX does). A ship with no stored course starts from its position and facing. Stores the
## course; returns "" or the reason it is refused (the course is then unchanged).
func player_extend_course(player_id: int, ship_id: String, hex: Vector2i) -> String:
	var why := _course_request_error(player_id, ship_id)
	if why != "":
		return why
	var ship: ShipState = game_state.get_ship(ship_id)
	var path := stored_course(ship)
	var cur_hex: Vector2i = ship.hex_position if path.is_empty() else path[-1].hex
	var cur_facing: int = ship.facing if path.is_empty() else path[-1].facing
	var validation := MovementValidator.new(game_state).validate_hex_selection(
		ship, cur_hex, cur_facing, hex, path)
	if not validation.is_valid:
		return validation.error_message
	var move_type: MovementTypes.MoveType = validation.metadata.move_type \
			if validation.metadata else MovementTypes.MoveType.NONE
	var resulting_hex: Vector2i = validation.metadata.resulting_hex \
			if validation.metadata else hex
	path.append(MovementTypes.PlotStep.new(resulting_hex, validation.new_facing, move_type))
	game_state.ship_controller.set_plotted_movement(ship_id, DefaultCourse.as_dicts(path))
	return ""


## SERVER ONLY: cuts the ship's stored course back to the steps before `step_index` (0 clears it;
## the size keeps all of it). Stores the result as the player's plot. Returns "" or the reason.
func player_cut_course(player_id: int, ship_id: String, step_index: int) -> String:
	var why := _course_request_error(player_id, ship_id)
	if why != "":
		return why
	var ship: ShipState = game_state.get_ship(ship_id)
	var path := stored_course(ship)
	if step_index < 0 or step_index > path.size():
		return "no step %d in the course of %s" % [step_index, ship_id]
	var kept: Array[MovementTypes.PlotStep] = []
	kept.assign(path.slice(0, step_index))
	game_state.ship_controller.set_plotted_movement(ship_id, DefaultCourse.as_dicts(kept))
	return ""


## Read-only: what the view needs to draw and extend a ship's course: `path` (the stored steps),
## `valid_next` (MovementTypes.ValidNextHexes from the course end), `remaining_ma`, `mp_used` (MPs
## the course spends, turns included), `max_ma` (the most it may spend at the course-end heading),
## `start_max_ma` (the same at the start heading), `is_tacking_attempt`, `rudder_error` ("" or the
## jammed-rudder text: the course is kept, the view warns). {} when the ship cannot plot.
func course_options(ship_id: String) -> Dictionary:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or not DefaultCourse.can_plot(ship):
		return {}
	var path := stored_course(ship)
	var cur_hex: Vector2i = ship.hex_position if path.is_empty() else path[-1].hex
	var cur_facing: int = ship.facing if path.is_empty() else path[-1].facing
	var validator := MovementValidator.new(game_state)
	var moves := validator.calculate_valid_moves(ship, cur_hex, cur_facing, path)
	var empty: Array[MovementTypes.PlotStep] = []
	var at_start := moves if path.is_empty() else \
			validator.calculate_valid_moves(ship, ship.hex_position, ship.facing, empty)
	return {
		"path": path,
		"valid_next": moves.valid_hexes,
		"remaining_ma": moves.remaining_ma,
		"mp_used": moves.mp_spent,
		"max_ma": moves.max_ma,
		"start_max_ma": at_start.max_ma,
		"is_tacking_attempt": moves.is_tacking_attempt,
		"rudder_error": validator.rudder_jam_error(ship, path),
	}


## The steps stored in the ship's plotted movement.
func stored_course(ship: ShipState) -> Array[MovementTypes.PlotStep]:
	var steps: Array[MovementTypes.PlotStep] = []
	for d in ship.plotted_actions.get("movement", []):
		steps.append(MovementTypes.PlotStep.from_dict(d))
	return steps


## The `_crew_request_error` checks (phase, submitted plan, owner) plus: the ship must be able to
## plot (not fouled, grappled, struck, dismasted, a prize).
func _course_request_error(player_id: int, ship_id: String) -> String:
	var why := _crew_request_error(player_id, ship_id)
	if why != "":
		return why
	var ship: ShipState = game_state.get_ship(ship_id)
	if not DefaultCourse.can_plot(ship):
		return "%s cannot move" % ship_id
	return ""


## SERVER ONLY: the player's crew plan for one ship (the crew overlay; crew-tasks spec §3.2, §4.4).
## Checks the phase, the player, that the plan is not yet submitted and that the ship is theirs;
## CrewTaskController.plot_crew normalizes and stores it. Returns "" or the reason it is refused.
func player_plot_crew(player_id: int, ship_id: String, plan: Dictionary) -> String:
	var why := _crew_request_error(player_id, ship_id)
	if why != "":
		return why
	return game_state.crew_task_controller.plot_crew(player_id, ship_id, plan)


## SERVER ONLY: the Automatic crew switch for one of the player's ships (spec §3.3). Same checks
## as player_plot_crew. Returns "" or the reason it is refused.
func player_set_crew_auto(player_id: int, ship_id: String, on: bool) -> String:
	var why := _crew_request_error(player_id, ship_id)
	if why != "":
		return why
	return game_state.crew_task_controller.set_auto(player_id, ship_id, on)


## SERVER ONLY: the sail change ordered for one of the player's ships ("" withdraws it), with the
## same checks as player_plot_crew; SailController.plot_sail_change validates the target (5.F.6).
func player_plot_sail_change(player_id: int, ship_id: String, target: String) -> String:
	var why := _crew_request_error(player_id, ship_id)
	if why != "":
		return why
	return game_state.sail_controller.plot_sail_change(player_id, ship_id, target)


func _crew_request_error(player_id: int, ship_id: String) -> String:
	if not is_server:
		push_error("TurnPhaseController: Cannot plot crew on client")
		return "crew orders are given on the server only"
	if not game_result.is_empty():
		return "the game is over"
	if current_phase != GamePhase.PLANNING:
		return "crew orders are given in the planning phase"
	if player_id < 0 or player_id >= players_ready.size():
		return "invalid player %d" % player_id
	if players_ready[player_id]:
		return "this player's plan is already submitted"
	if game_state.crew_task_controller == null:
		return "no crew-task controller"
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "no ship %s" % ship_id
	if ship.player_id != player_id:
		return "%s is not this player's ship" % ship_id
	if ship.is_destroyed():
		return "%s is destroyed" % ship_id
	return ""


func _enter_movement_resolution_phase() -> void:
	"""SERVER ONLY: Enter movement resolution phase.
	Runs the resolver and emits resolution_log_ready. Does NOT auto-advance.
	The view layer plays back the log and calls on_playback_completed() when done."""
	current_phase = GamePhase.MOVEMENT_RESOLUTION
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: MOVEMENT_RESOLUTION")

	# Crew plots become tasks now (SoP III; sail changes start), before movement resolution
	# clears the plots.
	if game_state.crew_task_controller:
		game_state.crew_task_controller.begin_turn_tasks(current_phase)

	_bear_off_decisions = {}
	if game_state.movement_resolver and game_state.environment:
		_resolution_rng_state = game_state.movement_resolver.rng.state
		_run_movement_resolution(0)
	else:
		advance_phase()


## Run the resolver with this turn's bear-off answers and hand the log to the view, which plays it
## from `resume_impulse`. An incomplete log (a prompted ship's potential collision) is played up to
## that segment; the view then calls on_playback_paused().
func _run_movement_resolution(resume_impulse: int) -> void:
	var all_ships = game_state.ships_on_map()  # a wreck removed at END_TURN (8.G.1f) is gone
	game_state.movement_resolver.rng.state = _resolution_rng_state
	@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
	var log = game_state.movement_resolver.run(all_ships, game_state.environment, _bear_off_decisions,
		_bear_off_prompt_ship_ids(all_ships))
	log.resume_impulse = resume_impulse
	_pending_resolution_log = log
	Trace.trace_log("TurnPhase", "MOVEMENT_RESOLUTION resolver done", {"turn": log.turn,
		"ships": log.ship_results.size(), "complete": log.is_complete()})
	resolution_log_ready.emit(log)


func _bear_off_prompt_ship_ids(ships: Array) -> Array:
	var ids: Array = []
	for s in ships:
		if s.player_id in bear_off_prompt_player_ids:
			ids.append(s.ship_id)
	return ids


## The view played an incomplete log up to its potential collision: ask the owner.
func on_playback_paused() -> void:
	if not is_server:
		push_error("TurnPhaseController: Cannot pause playback on client")
		return
	if current_phase != GamePhase.MOVEMENT_RESOLUTION or _pending_resolution_log == null \
			or _pending_resolution_log.is_complete():
		push_error("TurnPhaseController: on_playback_paused with no decision pending")
		return
	bear_off_decision_requested.emit(_pending_resolution_log.pending_bear_off)


## The owner's answer to the pending potential collision (6.D.3): "port", "starboard" or "collide".
## Returns "" when accepted (the resolution runs again and playback resumes at that segment), else
## the reason it was refused.
func player_submit_bear_off(player_id: int, ship_id: String, choice: String) -> String:
	if not is_server:
		push_error("TurnPhaseController: Cannot submit a bear-off decision on client")
		return "bear-off decisions can only be submitted on the server"
	if not game_result.is_empty():
		return "the game is over"
	if current_phase != GamePhase.MOVEMENT_RESOLUTION or _pending_resolution_log == null \
			or _pending_resolution_log.is_complete():
		return "no bear-off decision pending"
	var situation: MovementTypes.BearOffSituation = _pending_resolution_log.pending_bear_off
	if situation.ship_id != ship_id:
		return "the decision pending is for %s" % situation.ship_id
	var ship = game_state.get_ship(ship_id)
	if ship == null or ship.player_id != player_id:
		return "player %d does not command %s" % [player_id, ship_id]
	if not choice in situation.choices():
		return "%s is not a legal choice here" % choice
	_bear_off_decisions[ship_id] = {"choice": choice, "segment": situation.segment}
	Trace.trace_log("TurnPhase", "Bear-off decision", {"ship": ship_id, "choice": choice, "segment": situation.segment})
	_run_movement_resolution(situation.segment)
	return ""


func on_playback_completed() -> void:
	"""Called by the view layer after resolution playback finishes.
	Applies results to state and advances to the next phase."""
	if not is_server:
		push_error("TurnPhaseController: Cannot complete movement playback on client")
		return
	if current_phase != GamePhase.MOVEMENT_RESOLUTION:
		push_error("TurnPhaseController: on_playback_completed called outside MOVEMENT_RESOLUTION")
		return
	if _pending_resolution_log and not _pending_resolution_log.is_complete():
		push_error("TurnPhaseController: on_playback_completed with a bear-off decision pending")
		return
	if _pending_resolution_log:
		var all_ships = game_state.get_all_ships()
		game_state.movement_resolver.apply_results(_pending_resolution_log, all_ships)
		Trace.trace_log("TurnPhase", "MOVEMENT_RESOLUTION results applied", _pending_resolution_log.to_dict())
		# 8.F.3b: a hull repair ends on a ship that moved more than 4 MPs.
		if game_state.crew_task_controller:
			game_state.crew_task_controller.after_movement(current_phase)
		_pending_resolution_log = null
	advance_phase()

func _enter_combat_resolution_phase() -> void:
	"""SERVER ONLY: Enter combat resolution phase.
	Skipped entirely when no ship has a legal gun shot or marine shot (7.G). Otherwise waits in DECLARE for both
	players' fire orders, then resolves them (RESOLVE) and waits for the view to finish
	playback via on_combat_playback_completed()."""
	current_phase = GamePhase.COMBAT_RESOLUTION
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: COMBAT_RESOLUTION")

	# SoP IV.A, 10.C.4a: boarders away are announced first (the defenders' marines replot, struck
	# or undefended ships are taken at once); the boarding is fought after all the fire.
	var boarding = game_state.get("boarding_controller")
	var announced: bool = boarding != null and boarding.declare(current_phase)
	var any_boarding: bool = announced or (boarding != null and boarding.has_actions_to_resolve())
	var calculator = game_state.gunnery_calculator
	var marines = game_state.get("marine_fire_resolver")
	var any_gun: bool = calculator != null and calculator.any_eligible_shot()
	var any_marine: bool = marines != null and marines.any_eligible_marine_shot()
	if not any_gun and not any_marine:
		if any_boarding:
			# Boarding with no fire: no declaration step; RESOLVE runs the boarding alone.
			combat_step = CombatStep.RESOLVE
			boarding.resolve(current_phase)
			Trace.trace_log("TurnPhase", "COMBAT_RESOLUTION: boarding only")
			combat_log_ready.emit(game_state.turn_log)
			return
		combat_step = CombatStep.NONE
		advance_phase()
		return

	combat_step = CombatStep.DECLARE
	_fire_orders = [[], []]
	_marine_orders = [[], []]
	_fire_ready = [false, false]
	fire_declaration_requested.emit()
	if game_state.stub_ai:
		game_state.stub_ai.submit_fire_orders()

func player_submit_fire_orders(player_id: int, orders: Array, marine_orders: Array = []) -> String:
	"""SERVER ONLY: Validate and store a player's fire orders (Array of FireOrder dictionaries) and
	marine fire orders (Array of {ship_id, target_id}, 7.G; MarineFireResolver.validate_orders).
	Returns "" on success, otherwise the reason it was rejected (nothing changes on rejection).
	A later valid submission replaces an earlier one until both players are ready."""
	if not is_server:
		push_error("TurnPhaseController: Cannot submit fire orders on client")
		return "fire orders can only be submitted on the server"
	if not game_result.is_empty():
		return "the game is over"
	if current_phase != GamePhase.COMBAT_RESOLUTION or combat_step != CombatStep.DECLARE:
		return "fire orders are not being accepted now"
	if player_id < 0 or player_id >= _fire_ready.size():
		return "invalid player %d" % player_id

	var typed: Array[GunneryTypes.FireOrder] = []
	for entry in orders:
		if not entry is Dictionary:
			return "malformed fire order"
		typed.append(GunneryTypes.FireOrder.from_dict(entry))

	var reason: String = game_state.gunnery_calculator.validate_orders(player_id, typed)
	if reason != "":
		return reason
	var marines: Array = []
	for entry in marine_orders:
		if not entry is Dictionary:
			return "malformed marine fire order"
		marines.append({"ship_id": str(entry.get("ship_id", "")), "target_id": str(entry.get("target_id", ""))})
	if not marines.is_empty():
		reason = game_state.marine_fire_resolver.validate_orders(player_id, marines)
		if reason != "":
			return reason

	_fire_orders[player_id] = typed
	_marine_orders[player_id] = marines
	_fire_ready[player_id] = true
	Trace.trace_log("TurnPhase", "Player %d declared %d fire orders, %d marine fire orders" % [
		player_id, typed.size(), marines.size()])

	if _fire_ready.all(func(is_ready): return is_ready):
		_resolve_combat()
	return ""

func _resolve_combat() -> void:
	"""SERVER ONLY: Resolve all declared fire simultaneously, then wait for playback.
	Marine fire is simultaneous with gunfire (7.G.5): its shots are taken from the state before any
	gunfire damage, and rolled after all the gunfire dice (boarding spec §3.3)."""
	combat_step = CombatStep.RESOLVE
	var all_orders: Array[GunneryTypes.FireOrder] = []
	for player_orders in _fire_orders:
		all_orders.append_array(player_orders)
	var all_marine: Array = []
	for player_marines in _marine_orders:
		all_marine.append_array(player_marines)
	_log_held_fire(all_orders)
	var marine_shots: Array[Dictionary] = game_state.marine_fire_resolver.prepare(all_marine)
	game_state.gunnery_resolver.resolve(all_orders, GamePhase.COMBAT_RESOLUTION)
	game_state.marine_fire_resolver.resolve(marine_shots, GamePhase.COMBAT_RESOLUTION)
	# 10.C.4: boarding combat after all gunfire and marine fire, on what is left.
	if game_state.get("boarding_controller") != null:
		game_state.boarding_controller.resolve(GamePhase.COMBAT_RESOLUTION)
	Trace.trace_log("TurnPhase", "COMBAT_RESOLUTION resolved", {"orders": all_orders.size(),
		"marine_orders": marine_shots.size()})
	combat_log_ready.emit(game_state.turn_log)

func _log_held_fire(orders: Array[GunneryTypes.FireOrder]) -> void:
	"""SERVER ONLY: Log HOLD_FIRE for every ship (both players, ascending ship_id) that had an
	eligible shot but was given no fire order. Runs before resolution, so eligibility reflects
	the state the orders were declared against."""
	var ordered := {}
	for order in orders:
		ordered[order.ship_id] = true
	var ids: Array = []
	for ship: ShipState in game_state.get_all_ships():
		ids.append(ship.ship_id)
	ids.sort()
	for ship_id: String in ids:
		if ordered.has(ship_id):
			continue
		if game_state.gunnery_calculator.eligible_shots(ship_id).is_empty():
			continue
		game_state.turn_log.add(PhaseEvents.Type.HOLD_FIRE, GamePhase.COMBAT_RESOLUTION, ship_id)

func on_combat_playback_completed() -> void:
	"""Called by the view layer after combat playback finishes. Advances past combat."""
	if not is_server:
		push_error("TurnPhaseController: Cannot complete combat playback on client")
		return
	if current_phase != GamePhase.COMBAT_RESOLUTION or combat_step != CombatStep.RESOLVE:
		push_error("TurnPhaseController: on_combat_playback_completed called outside combat RESOLVE")
		return
	combat_step = CombatStep.NONE
	advance_phase()

func _enter_drift_calculation_phase() -> void:
	"""SERVER ONLY: Enter drift calculation phase"""
	current_phase = GamePhase.DRIFT_CALCULATION
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: DRIFT_CALCULATION")
	game_state.drift_resolver.resolve(GamePhase.DRIFT_CALCULATION)
	advance_phase()

func _enter_status_adjustment_phase() -> void:
	"""SERVER ONLY: Enter status adjustment phase (the Maintenance Phase after drift, SoP V.C-G).
	Grappling, then ungrappling (8.C), each waiting for a prompted player's orders only when that
	player has a choice; then unfouling, fixes, fire and the crew tasks."""
	current_phase = GamePhase.STATUS_ADJUSTMENT
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: STATUS_ADJUSTMENT")
	_reset_maintenance()
	if game_state.get("grappling_controller") == null:
		_finish_status_adjustment()
		return
	_begin_maintenance_step(MaintenanceStep.GRAPPLE)


## Collect the prompted players' options for `step`; wait if any has one, else resolve at once.
func _begin_maintenance_step(step: MaintenanceStep) -> void:
	_maintenance_options = {}
	_maintenance_orders = []
	_maintenance_waiting = []
	for player_id in maintenance_prompt_player_ids:
		var options: Array = maintenance_options(player_id, step)
		if not options.is_empty():
			_maintenance_options[player_id] = options
			_maintenance_waiting.append(player_id)
	if _maintenance_waiting.is_empty():
		_resolve_maintenance_step(step)
		return
	maintenance_step = step
	Trace.trace_log("TurnPhase", "STATUS_ADJUSTMENT waits for %s orders" % _step_name(step),
		{"players": _maintenance_waiting})
	for player_id in _maintenance_waiting.duplicate():
		maintenance_orders_requested.emit(player_id, _step_name(step), _maintenance_options[player_id])


## The choices `player_id` has in `step`: one entry per (own ship, other ship) pair:
## {"ship_id", "target_id", "needed", "modifier", "modifiers", "percent"} (+ "attempt" when
## ungrappling), from GrapplingController's queries. Pure.
func maintenance_options(player_id: int, step: MaintenanceStep) -> Array:
	var out: Array = []
	if step == MaintenanceStep.PRIZE:
		# 10.G.6: prize-crew sizes (BoardingController.prize_size_options; boarding spec §4.3).
		var boarding = game_state.get("boarding_controller")
		return boarding.prize_size_options(player_id) if boarding != null else out
	var grappling = game_state.get("grappling_controller")
	if grappling == null:
		return out
	var own: Array = []
	for ship: ShipState in game_state.get_player_ships(player_id):
		own.append(ship.ship_id)
	own.sort()
	for ship_id in own:
		var others: Array[String] = grappling.grapple_options(ship_id) if step == MaintenanceStep.GRAPPLE \
				else grappling.ungrapple_options(ship_id)
		# 0.4 #7: enemy targets first, then friendly ones.
		var enemies: Array = []
		var friends: Array = []
		for other_id in others:
			var other: ShipState = game_state.get_ship(other_id)
			(friends if other.player_id == player_id else enemies).append(other_id)
		for other_id in enemies + friends:
			var chance: Dictionary = grappling.grapple_chance(ship_id, other_id) if step == MaintenanceStep.GRAPPLE \
					else grappling.ungrapple_chance(ship_id, other_id)
			var entry := {"ship_id": ship_id, "target_id": other_id}
			entry.merge(chance)
			out.append(entry)
	return out


## SERVER ONLY: a prompted player's orders for the maintenance step now waiting:
## {"grapple": [[ship_id, target_id], ...]} in GRAPPLE, {"ungrapple": [[ship_id, partner_id], ...]}
## in UNGRAPPLE (an empty list orders nothing). Each pair must be one of the player's options.
## Returns "" when accepted (once every prompted player has answered, the step is rolled and the
## phase goes on), else the reason it was refused (nothing changes).
func player_submit_maintenance_orders(player_id: int, orders: Dictionary) -> String:
	if not is_server:
		push_error("TurnPhaseController: Cannot submit maintenance orders on client")
		return "maintenance orders can only be submitted on the server"
	if not game_result.is_empty():
		return "the game is over"
	if current_phase != GamePhase.STATUS_ADJUSTMENT or maintenance_step == MaintenanceStep.NONE:
		return "no maintenance orders are being asked for"
	if not _maintenance_waiting.has(player_id):
		return "no maintenance orders are awaited from player %d" % player_id
	var key := _step_name(maintenance_step)
	for k in orders:
		if str(k) != key:
			return "only %s orders are given now" % key
	if maintenance_step == MaintenanceStep.PRIZE:
		return _submit_prize_sizes(player_id, orders.get(key, {}))
	var pairs = GrapplingController.parse_pairs(orders.get(key, []))
	if pairs == null:
		return "malformed %s orders" % key
	var legal := {}
	for option in _maintenance_options.get(player_id, []):
		legal["%s|%s" % [option["ship_id"], option["target_id"]]] = true
	for pair in pairs:
		var ship: ShipState = game_state.get_ship(pair[0])
		if ship == null:
			return "no ship %s" % pair[0]
		if ship.player_id != player_id:
			return "%s is not this player's ship" % pair[0]
		if not legal.has("%s|%s" % [pair[0], pair[1]]):
			var grappling: GrapplingController = game_state.grappling_controller
			var why: String = grappling.grapple_error(pair[0], pair[1]) if maintenance_step == MaintenanceStep.GRAPPLE \
					else grappling.ungrapple_error(pair[0], pair[1])
			return why if why != "" else "%s cannot %s %s now" % [pair[0], key, pair[1]]
	_maintenance_orders.append_array(pairs)
	_maintenance_waiting.erase(player_id)
	Trace.trace_log("TurnPhase", "Player %d gave %d %s orders" % [player_id, pairs.size(), key])
	if _maintenance_waiting.is_empty():
		var step := maintenance_step
		maintenance_step = MaintenanceStep.NONE
		_resolve_maintenance_step(step)
	return ""


## {"prize_size": {action_id: size}} from a prompted player (10.G.6): each must be one of the
## player's options and from the minimum to the surviving boarders; an action not named keeps the
## minimum. All or nothing: nothing is recorded on a refusal.
func _submit_prize_sizes(player_id: int, sizes: Variant) -> String:
	if not sizes is Dictionary:
		return "malformed prize_size orders"
	var options := {}
	for option in _maintenance_options.get(player_id, []):
		options[int(option["action_id"])] = option
	var parsed := {}
	for k in sizes:
		var key := str(k)
		if not key.is_valid_int() or not (typeof(sizes[k]) == TYPE_INT or typeof(sizes[k]) == TYPE_FLOAT):
			return "malformed prize_size orders"
		if not options.has(int(key)):
			return "no prize crew of action %s is to be chosen by player %d" % [key, player_id]
		var n := int(sizes[k])
		var option: Dictionary = options[int(key)]
		if n < int(option["minimum"]) or n > int(option["maximum"]):
			return "the prize crew must be %d to %d boxes (10.G.6)" % [int(option["minimum"]), int(option["maximum"])]
		parsed[int(key)] = n
	for action_id in parsed:
		var why: String = game_state.boarding_controller.set_prize_size(action_id, parsed[action_id])
		if why != "":
			return why
	_maintenance_waiting.erase(player_id)
	Trace.trace_log("TurnPhase", "Player %d chose %d prize-crew sizes" % [player_id, parsed.size()])
	if _maintenance_waiting.is_empty():
		maintenance_step = MaintenanceStep.NONE
		_resolve_maintenance_step(MaintenanceStep.PRIZE)
	return ""


## Roll `step` with the prompted players' orders plus StubAI's for every other player's ships, then
## move on: ungrappling after grappling, the rest of the phase after ungrappling.
func _resolve_maintenance_step(step: MaintenanceStep) -> void:
	if step == MaintenanceStep.PRIZE:
		_maintenance_orders = []
		_maintenance_options = {}
		if game_state.stub_ai:
			var boarding: BoardingController = game_state.boarding_controller
			var sizes: Dictionary = game_state.stub_ai.prize_sizes(_ai_players())
			for action_id in sizes:
				boarding.set_prize_size(int(action_id), int(sizes[action_id]))
		_after_prize_step()
		return
	var orders: Array = _maintenance_orders.duplicate()
	if game_state.stub_ai:
		var ai_players := _ai_players()
		orders.append_array(game_state.stub_ai.grapple_orders(ai_players) if step == MaintenanceStep.GRAPPLE
				else game_state.stub_ai.ungrapple_orders(ai_players))
	_maintenance_orders = []
	_maintenance_options = {}
	if step == MaintenanceStep.GRAPPLE:
		game_state.grappling_controller.resolve_grapples(orders, current_phase)
		_begin_maintenance_step(MaintenanceStep.UNGRAPPLE)
	else:
		game_state.grappling_controller.resolve_ungrapples(orders, current_phase)
		_finish_status_adjustment()


## Players StubAI answers for (not prompted).
func _ai_players() -> Array[int]:
	var ai_players: Array[int] = []
	for p in game_state.ships_by_player.keys():
		if not maintenance_prompt_player_ids.has(int(p)):
			ai_players.append(int(p))
	return ai_players


## SoP V.E-G after grappling and ungrappling; then, when a reorganization has ended with more
## boarders than the minimum prize crew, the prize-crew size prompt (MaintenanceStep.PRIZE, 10.G.6);
## then the prize crews go aboard and the next phase.
func _finish_status_adjustment() -> void:
	if game_state.fouling_controller:
		game_state.fouling_controller.resolve_unfouling(current_phase)
	if game_state.critical_hit_controller:
		game_state.critical_hit_controller.resolve_fixes(current_phase)
	# SoP V.F: the Fire & Explosions sub-phase (firefighting, damage, growth and spread,
	# explosions, unfought fires).
	if game_state.get("fire_controller") != null:
		game_state.fire_controller.resolve(current_phase)
	# SoP V.G: crew tasks counted, completed (repairs recorded, 8.F.5; RO completed; sail changes
	# take effect, 5.F.8) or cancelled.
	if game_state.crew_task_controller:
		game_state.crew_task_controller.advance_tasks(current_phase)
	if game_state.get("boarding_controller") == null:
		_after_prize_step()
		return
	_begin_maintenance_step(MaintenanceStep.PRIZE)


func _after_prize_step() -> void:
	# 10.G.7: prize crews of actions whose boarders finished reorganizing go aboard.
	if game_state.get("boarding_controller") != null:
		game_state.boarding_controller.advance_reorganizing(current_phase)
	# TODO: sinking, anchors
	advance_phase()


func _reset_maintenance() -> void:
	maintenance_step = MaintenanceStep.NONE
	_maintenance_waiting = []
	_maintenance_options = {}
	_maintenance_orders = []


static func _step_name(step: MaintenanceStep) -> String:
	match step:
		MaintenanceStep.GRAPPLE:
			return "grapple"
		MaintenanceStep.PRIZE:
			return "prize_size"
	return "ungrapple"

func _enter_morale_check_phase() -> void:
	"""SERVER ONLY: Enter morale check phase"""
	current_phase = GamePhase.MORALE_CHECK
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: MORALE_CHECK")
	if game_state.morale_controller:
		game_state.morale_controller.resolve_checks(current_phase)
	advance_phase()

func _enter_message_delivery_phase() -> void:
	"""SERVER ONLY: Enter message delivery phase"""
	current_phase = GamePhase.MESSAGE_DELIVERY
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: MESSAGE_DELIVERY")
	# TODO: Deliver flag messages
	advance_phase()

func _enter_post_combat_phase() -> void:
	"""SERVER ONLY: Enter post combat phase and wait for the player's End Turn"""
	current_phase = GamePhase.POST_COMBAT
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: POST_COMBAT - waiting for End Turn")

func player_end_turn(player_id: int) -> bool:
	"""SERVER ONLY: The human player ends the turn. Only valid in POST_COMBAT; the AI needs no call."""
	if not is_server:
		push_error("TurnPhaseController: Cannot end turn on client")
		return false
	if not game_result.is_empty() or current_phase != GamePhase.POST_COMBAT:
		return false
	if player_id != 0:
		return false
	Trace.trace_log("TurnPhase", "Player %d ended the turn" % player_id)
	_enter_end_turn_phase()
	return true

func _enter_end_turn_phase() -> void:
	"""SERVER ONLY: Enter end turn phase - stop with a result, or roll over to the next turn"""
	current_phase = GamePhase.END_TURN
	phase_changed.emit(current_phase)
	Trace.trace_log("TurnPhase", "Phase: END_TURN")
	planning_snapshot = {}

	# 8.G.1f: remove ships. An exploded ship has blocked the map all g-t; now it leaves it.
	for ship: ShipState in game_state.get_all_ships():
		if ship.is_destroyed() and ship.is_on_map():
			game_state.ship_controller.remove_from_map(ship.ship_id)

	var result: Dictionary = game_state.victory_controller.check(current_turn)
	if result.is_empty():
		_start_new_turn()
		return

	game_result = result
	game_state.turn_log.add(PhaseEvents.Type.VICTORY, current_phase, "",
			{"winner": result["winner"], "reason": result["reason"]})
	game_state.turn_logs[current_turn] = game_state.turn_log
	Trace.trace_log("TurnPhase", "Game over", result)
	game_over.emit(result)

func _start_new_turn() -> void:
	"""SERVER ONLY: Start a new turn"""
	if game_state.get("boarding_controller") != null:
		game_state.boarding_controller.end_of_turn(current_turn)
	for ship: ShipState in game_state.get_all_ships():
		game_state.ship_controller.clear_turn_flags(ship.ship_id)
	game_state.turn_logs[current_turn] = game_state.turn_log
	current_turn += 1
	game_state.turn_log = game_state.new_turn_log(current_turn)
	turn_changed.emit(current_turn)
	Trace.trace_log("TurnPhase", "=== Turn %d ===" % current_turn)
	# 10.H.4: at the start of the g-t, a prize crew below the minimum may lose the ship.
	if game_state.get("boarding_controller") != null:
		game_state.boarding_controller.start_of_turn(GamePhase.ENVIRONMENT)
	# Directly enter environment phase (we're already inside advance_phase() call chain)
	_enter_environment_phase()

func get_phase_name() -> String:
	"""Get human-readable phase name"""
	return GamePhase.keys()[current_phase]

func serialize_phase_state() -> Dictionary:
	"""Serialize phase state for network sync"""
	return {
		"current_phase": current_phase,
		"current_turn": current_turn,
		"players_ready": players_ready,
		"combat_step": combat_step,
		"maintenance_step": maintenance_step
	}

func apply_phase_state(data: Dictionary) -> void:
	"""Apply phase state from server (CLIENT ONLY)"""
	if is_server:
		push_error("TurnPhaseController: apply_phase_state is for clients")
		return
	current_phase = data.get("current_phase", GamePhase.SETUP)
	current_turn = data.get("current_turn", 0)
	players_ready = data.get("players_ready", [false, false])
	combat_step = data.get("combat_step", CombatStep.NONE)
	maintenance_step = data.get("maintenance_step", MaintenanceStep.NONE)

	# Emit signals so UI can update
	phase_changed.emit(current_phase)
