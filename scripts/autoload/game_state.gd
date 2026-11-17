extends Node
## GameState - Manages the overall game state
## This is now a data container. Authority is managed by server controllers.
## On server: Full read/write access via controllers
## On client: Read-only, updated via network sync

signal phase_changed(new_phase: GamePhase)
signal turn_changed(turn_number: int)
@warning_ignore("unused_signal")  # Part of the state API; emitted once multiplayer readiness is wired
signal player_ready(player_id: int)
signal state_synced()  # Emitted when state is synced from server
## A new game has been set up from `scenario` (active_scenario, ships and environment are the new
## game's). Views that depend on the scenario configure themselves here, never in _ready(): the
## game scene's nodes are ready before the game starts and would see the previous game's data.
signal game_started(scenario: Dictionary)

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

var current_phase: GamePhase = GamePhase.SETUP
var current_turn: int = 0
## Mirror of TurnPhaseController.players_ready: player id -> plan submitted.
var players_ready: Dictionary = {0: false, 1: false}
var active_scenario: Dictionary = {}
var selected_scenario: String = ""  # Scenario name selected from menu

# Server-side controllers (only active on server)
var is_server: bool = true  # Set by network manager
var phase_controller: TurnPhaseController = null
var ship_controller: ShipStateController = null
var environment_controller: EnvironmentController = null
var command_validator: CommandValidator = null
var network_sync: NetworkSync = null
var movement_plotting_controller: MovementPlottingController = null
var movement_resolver: MovementResolver = null
var stub_ai: StubAI = null
## Developer UI requests (server only, debug builds only).
var dev_commands: DevCommands = null

# State objects (authoritative on server, read-only on client)
var environment: EnvironmentState = null  # Environmental conditions
var ships: Dictionary = {}  # ship_id -> ShipState
var ships_by_side: Dictionary = {0: [], 1: []}  # side -> Array[ship_id]
var players: Dictionary = {}  # player id (int) -> PlayerState
var groups: Dictionary = {}  # side (int) -> {group name -> Array[String] of ship ids}
var talks: Array = []  # this game's talks between ships (11.B.3), Dictionaries; opened at PLANNING start
var end_offers: Dictionary = {}  # side (int) -> bool: that side offers to end the game by agreement (2.A.1)
var signals: Array[SignalState] = []  # flag signals sent this game (11.A); delivered at MESSAGE_DELIVERY

# Shared seeded RNG — seeded from scenario on game start; all controllers share this instance
var rng: RandomNumberGenerator = null
# All die rolls (d10 is 0-9); built on rng
var dice: Dice = null
var fire_geometry: FireGeometry = null
var gunnery_calculator: GunneryCalculator = null
var damage_controller: DamageController = null
var critical_hit_controller: CriticalHitController = null
var gunnery_resolver: GunneryResolver = null
var marine_fire_resolver: MarineFireResolver = null
var sail_controller: SailController = null
var crew_task_controller: CrewTaskController = null
var fire_controller: FireController = null
var repair_controller: RepairController = null
var drift_resolver: DriftResolver = null
var fouling_controller: FoulingController = null
var grappling_controller: GrapplingController = null
var boarding_controller: BoardingController = null
var morale_controller: MoraleController = null
var victory_controller: VictoryController = null

# Boarding (boarding spec §2.2-2.3; changed only by BoardingController)
## Live and recently finished boarding actions (BoardingAction).
var boarding_actions: Array = []
## Last BoardingAction id given.
var boarding_seq: int = 0
## Ships fouled or grappled to each ship when PLANNING began: ship_id -> Array of ship ids
## ("fouled or grappled at the start of the g-t", 10.A.2).
var linked_at_plot: Dictionary = {}
## Boarding actions at the end of each turn: turn -> Array of BoardingAction dictionaries.
var boarding_history: Dictionary = {}

# Event log for the current turn, and finished logs by turn number
var turn_log: PhaseEvents.PhaseLog = null
var turn_logs: Dictionary = {}  # turn -> PhaseEvents.PhaseLog

# State history tracking (indexed by turn number)
var environment_history: Array[EnvironmentState] = []  # Historical environment states
var ship_history: Dictionary = {}  # ship_id -> Array[ShipState] for historical ship states

# Legacy accessors for backward compatibility
var wind_direction: int:
	get: return environment.wind_direction if environment else 0
var wind_speed: int:
	get: return environment.wind_speed if environment else 2
var sea_state: int:
	get: return environment.sea_state if environment else 1

func _ready() -> void:
	Trace.trace_log("GameState", "Initialized (server: %s)" % is_server)
	# Initialize server controllers if this is the server
	if is_server:
		_initialize_server_controllers()

func _initialize_server_controllers() -> void:
	"""Initialize server-side controllers - SERVER ONLY"""
	if rng == null:
		rng = RandomNumberGenerator.new()
	dice = Dice.new(rng)
	fire_geometry = FireGeometry.new(HexGrid.new())
	gunnery_calculator = GunneryCalculator.new(self)
	damage_controller = DamageController.new(self)
	critical_hit_controller = CriticalHitController.new(self)
	gunnery_resolver = GunneryResolver.new(self)
	marine_fire_resolver = MarineFireResolver.new(self)
	sail_controller = SailController.new(self)
	crew_task_controller = CrewTaskController.new(self)
	crew_task_controller.register_handler(SailController.CODE, sail_controller)
	crew_task_controller.register_handler(TackCrewHandler.CODE, TackCrewHandler.new(self))
	crew_task_controller.register_handler(ReorganizeHandler.CODE, ReorganizeHandler.new(self))
	fire_controller = FireController.new(self)
	crew_task_controller.register_handler(FireController.CODE, fire_controller)
	repair_controller = RepairController.new(self)
	for code in RepairController.CODES:
		crew_task_controller.register_handler(code, repair_controller)
	drift_resolver = DriftResolver.new(self)
	fouling_controller = FoulingController.new(self)
	grappling_controller = GrapplingController.new(self)
	boarding_controller = BoardingController.new(self)
	for code in BoardingTaskHandler.CODES:
		crew_task_controller.register_handler(code, BoardingTaskHandler.new(self, code))
	morale_controller = MoraleController.new(self)
	victory_controller = VictoryController.new(self)
	turn_log = new_turn_log(1)
	phase_controller = TurnPhaseController.new(self)
	ship_controller = ShipStateController.new(self)
	environment_controller = EnvironmentController.new(self)
	command_validator = CommandValidator.new(self, ship_controller, phase_controller)
	network_sync = NetworkSync.new(self)
	network_sync.is_server = is_server
	movement_plotting_controller = MovementPlottingController.new(self)
	movement_resolver = MovementResolver.new(self)
	stub_ai = StubAI.new(self)
	dev_commands = DevCommands.new(self)

	# Add Node-based controllers to the tree so _ready/_process fire and they're freed on exit
	add_child(phase_controller)
	add_child(ship_controller)
	add_child(environment_controller)
	add_child(command_validator)
	add_child(network_sync)
	add_child(movement_plotting_controller)

	# Connect signals
	phase_controller.phase_changed.connect(_on_server_phase_changed)
	phase_controller.turn_changed.connect(_on_server_turn_changed)

	# Connect movement plotting signals
	movement_plotting_controller.session_submitted.connect(_on_movement_submitted)

	# Connect state change signals to trigger sync
	if is_server:
		phase_changed.connect(_on_state_changed_broadcast)
		turn_changed.connect(_on_state_changed_broadcast)
		if ship_controller:
			ship_controller.ship_state_changed.connect(_on_state_changed_broadcast)

	Trace.trace_log("GameState", "Server controllers initialized")

## SERVER ONLY: starts a scenario game: clears the ships, builds every ship of the scenario (its
## type from ships.json, its navy per ship or per side, 1.G.8), sets which players are human
## by player id (they are asked about bearing off and the maintenance orders; every other player is
## the AI, whose plan is in as soon as PLANNING begins), then start_new_game. The view creates its ship
## views on game_started. Returns false when refused.
func start_scenario(scenario_data: Dictionary, human_player_ids: Array[int]) -> bool:
	if not is_server:
		push_error("GameState: Cannot start a scenario on client")
		return false
	clear_ships()
	var navies: Variant = scenario_data.get("navies", {})
	for ship_data in scenario_data.get("ships", []):
		var ship_state := _scenario_ship(ship_data, navies)
		if ship_state != null:
			add_ship(ship_state)
	if not _build_players(scenario_data, human_player_ids):
		return false
	if phase_controller:
		phase_controller.bear_off_prompt_player_ids = human_player_ids.duplicate()
		phase_controller.human_player_ids = human_player_ids.duplicate()
		phase_controller.maintenance_prompt_player_ids = human_player_ids.duplicate()
		var ai: Array[int] = []
		for id in player_ids():
			if not human_player_ids.has(id):
				ai.append(id)
		phase_controller.ai_player_ids = ai
	start_new_game(scenario_data)
	return true


## Builds players, commanders and groups from the scenario (spec 2). Returns false (after a
## push_error) on a bad roster: a ship under two players, an unknown ship, a player on a side with
## no ships, or two fleet flagships on one side.
func _build_players(scenario_data: Dictionary, human_player_ids: Array[int]) -> bool:
	players.clear()
	groups = {}
	var sides: Array[int] = []
	for ship_id in ships:
		var s: int = ships[ship_id].side
		if not sides.has(s):
			sides.append(s)
	sides.sort()
	var entries: Array = scenario_data.get("players", [])
	if entries.is_empty():
		for s in sides:
			entries.append({"id": s, "side": s, "name": "Side %d" % s})
	var owner_of := {}  # ship id -> player id
	for entry in entries:
		var player := PlayerState.new()
		player.id = int(entry.get("id", 0))
		player.side = int(entry.get("side", player.id))
		player.name = str(entry.get("name", "Player %d" % player.id))
		player.is_ai = not human_player_ids.has(player.id)
		if players.has(player.id):
			push_error("GameState: player %d is listed twice" % player.id)
			return false
		if not sides.has(player.side):
			push_error("GameState: player %d is on side %d, which has no ships" % [player.id, player.side])
			return false
		players[player.id] = player
		for ship_id in entry.get("ships", []):
			var sid := str(ship_id)
			if not ships.has(sid):
				push_error("GameState: player %d lists unknown ship %s" % [player.id, sid])
				return false
			if owner_of.has(sid):
				push_error("GameState: ship %s is listed under two players" % sid)
				return false
			if ships[sid].side != player.side:
				push_error("GameState: ship %s is on side %d, not player %d's side" % [sid, ships[sid].side, player.id])
				return false
			owner_of[sid] = player.id
	for s in sides:
		var lowest := -1
		for pid in players:
			if players[pid].side == s and (lowest < 0 or pid < lowest):
				lowest = pid
		if lowest < 0:
			push_error("GameState: side %d has ships but no player" % s)
			return false
		var fleet_flags := 0
		for ship_id in ships_by_side.get(s, []):
			if ships[ship_id].ship.flag == "fleet":
				fleet_flags += 1
			if not owner_of.has(ship_id):
				owner_of[ship_id] = lowest
		if fleet_flags > 1:
			push_error("GameState: side %d has two fleet flagships" % s)
			return false
	for ship_id in owner_of:
		ship_controller.set_commander(ship_id, owner_of[ship_id])
	var raw_groups: Dictionary = scenario_data.get("groups", {})
	for key in raw_groups:
		var by_name := {}
		for group_name in raw_groups[key]:
			var ids: Array[String] = []
			for ship_id in raw_groups[key][group_name]:
				ids.append(str(ship_id))
			by_name[str(group_name)] = ids
		groups[int(key)] = by_name
	return true


func get_player(id: int) -> PlayerState:
	return players.get(id)


func players_of_side(side: int) -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for id in players:
		if players[id].side == side:
			out.append(players[id])
	out.sort_custom(func(a: PlayerState, b: PlayerState) -> bool: return a.id < b.id)
	return out


## The human who speaks for the side (2.A.1): the human commanding the in-play fleet flagship, else the
## lowest-id human commanding an in-play squadron flagship, else the lowest-id human, else -1.
func senior_human_player(side: int) -> int:
	var humans: Array[int] = []
	for p in players_of_side(side):
		if not p.is_ai:
			humans.append(p.id)
	for flag in ["fleet", "squadron"]:
		for id in humans:
			for s in ships_of_player(id):
				if s.ship != null and s.ship.flag == flag and not s.is_out_of_play():
					return id
	return humans[0] if not humans.is_empty() else -1


func side_of_player(id: int) -> int:
	var p: PlayerState = players.get(id)
	return p.side if p != null else -1


## The player commanding the ship (ShipState.commanding_player), -1 for an unknown id.
func commander_of(ship_id: String) -> int:
	var s: ShipState = ships.get(ship_id)
	return s.commanding_player() if s != null else -1


func commands(player_id: int, ship_id: String) -> bool:
	return player_id >= 0 and commander_of(ship_id) == player_id


## Every player id, ascending: the roster's, or without one (a game set up without
## start_scenario) the default one player per side: 0, 1 and any other side with ships.
func player_ids() -> Array[int]:
	var out: Array[int] = []
	if not players.is_empty():
		for id in players:
			out.append(int(id))
	else:
		out.assign([0, 1])
		for side in ships_by_side:
			if not out.has(int(side)):
				out.append(int(side))
	out.sort()
	return out


func ships_of_player(id: int) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for ship_id in ships:
		if commander_of(ship_id) == id:
			out.append(ships[ship_id])
	out.sort_custom(func(a: ShipState, b: ShipState) -> bool: return a.ship_id < b.ship_id)
	return out


func in_play_ships_of_player(id: int) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for s in ships_of_player(id):
		if not s.is_out_of_play():
			out.append(s)
	return out


## A ShipState for one scenario ship entry, or null when its type is unknown.
func _scenario_ship(ship_data: Dictionary, navies: Variant) -> ShipState:
	var type_def = DataManager.get_ship_definition(str(ship_data.get("ship_type", "")))
	if type_def == null:
		push_error("Ship definition not found: %s" % ship_data.get("ship_type", ""))
		return null
	var ship_ref := Ship.initialize_from_scenario(ship_data, type_def.to_dict())
	var side := str(int(ship_data.get("side", ship_data.get("player_id", 0))))  # JSON numbers are floats
	if not ship_data.has("navy") and navies is Dictionary and navies.has(side):
		ship_data = ship_data.duplicate()
		ship_data["navy"] = str(navies[side])
	var ship_state := ShipState.new()
	ship_state.initialize_from_scenario(ship_data, ship_ref)
	return ship_state


func start_new_game(scenario_data: Dictionary) -> void:
	"""Initialize a new game with scenario data - SERVER ONLY"""
	if not is_server:
		push_error("GameState: Cannot start game on client")
		return

	active_scenario = scenario_data
	# Mirrors of the phase controller's state start over with the game (the controller's
	# turn_changed / phase_changed keep them in step from here on).
	current_turn = 1
	current_phase = GamePhase.SETUP
	players_ready = {}
	for id in player_ids():
		players_ready[id] = false

	# Seed the shared RNG from scenario (default to 0 if no seed provided)
	var seed_value: int = scenario_data.get("seed", 0)
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	dice = Dice.new(rng)
	turn_log = new_turn_log(1)
	turn_logs.clear()
	boarding_actions = []
	boarding_seq = 0
	signals = []
	talks = []
	end_offers = {}
	linked_at_plot = {}
	boarding_history = {}
	Trace.trace_log("GameState", "RNG seeded", seed_value)

	# Clear any existing state history
	clear_state_history()

	# Initialize environment from scenario
	environment = EnvironmentState.new()
	environment.initialize_from_scenario(scenario_data)

	Trace.trace_log("GameState", "Game started - Turn: 1, Wind: %s (%d), Speed: %s (%d)" % [
		environment.get_wind_direction_name(),
		environment.wind_direction,
		environment.get_wind_speed_name(),
		environment.wind_speed
	])

	for message in placement_errors():
		push_error(message)

	game_started.emit(active_scenario)

	# Start the game via phase controller
	if phase_controller:
		phase_controller.start_new_game()

## Problems with where the ships stand: a hex (bow or stern) off the scenario's map, or two
## footprints sharing a hex. One message each; empty when the placement is valid. Read-only.
func placement_errors() -> Array[String]:
	var errors: Array[String] = []
	var all_ships := get_all_ships()
	for s in all_ships:
		for h in s.occupied_hexes():
			if not Occupancy.in_bounds(h, active_scenario):
				errors.append("GameState: ship '%s' occupies %s, outside map_bounds" % [s.ship_id, h])
	for i in all_ships.size():
		for j in range(i + 1, all_ships.size()):
			var pair: Array[ShipState] = [all_ships[i], all_ships[j]]
			if Occupancy.overlapping_ids(pair).size() > 0:
				errors.append("GameState: ships '%s' and '%s' overlap" % [pair[0].ship_id, pair[1].ship_id])
	return errors


func _on_server_phase_changed(new_phase: int) -> void:
	"""Handle phase change from server controller"""
	current_phase = new_phase as GamePhase
	phase_changed.emit(current_phase)

func _on_server_turn_changed(turn_number: int) -> void:
	"""Handle turn change from server controller"""
	# Save snapshots of previous turn's state before updating to new turn
	# This happens when advancing from turn N to turn N+1
	if turn_number > 1:  # Don't save for turn 1 (no previous state to save)
		var previous_turn = turn_number - 1
		save_environment_snapshot(previous_turn)
		save_all_ships_snapshot(previous_turn)
		Trace.trace_log("GameState", "Saved state snapshots for turn %d" % previous_turn)

	current_turn = turn_number
	turn_changed.emit(current_turn)

func _on_state_changed_broadcast(_arg = null) -> void:
	"""Broadcast state changes to clients when state changes"""
	if is_server and network_sync:
		# Note: This gets called frequently. In production, you might want to
		# debounce this or use delta syncing for efficiency
		pass  # network_sync.broadcast_state() called automatically via timer


func _on_movement_submitted(_session_id: String, ship_id: String, final_path: Array) -> void:
	"""Handle movement submission from plotting controller
	final_path is Array[MovementTypes.PlotStep]"""
	Trace.trace_log("GameState", "Movement submitted for ship %s (%d hexes)" % [ship_id, final_path.size()])
	# The movement is already applied to ship_state.plotted_actions by the controller
	# Additional handling (e.g., checking if all ships have submitted) can go here


func get_phase_name() -> String:
	"""Get human-readable phase name"""
	return GamePhase.keys()[current_phase]

## Ship Management Functions

func add_ship(ship_state: ShipState) -> bool:
	## Add a ship to the state container. Used by both server (setup) and client (sync).  SCV:ALLOW
	## A ship whose id is already present, or whose footprint (bow or stern hex) shares a hex with
	## another ship's footprint, is rejected (push_error, returns false) and not added.
	if ships.has(ship_state.ship_id):
		push_error("GameState: duplicate ship id '%s' rejected" % ship_state.ship_id)
		return false
	var others: Array[ShipState] = []
	others.assign(ships.values())
	var occupied := Occupancy.build(others)
	for h in ship_state.occupied_hexes():
		if occupied.has(h):
			push_error("GameState: ship '%s' starts on %s, already occupied by '%s'; rejected" % [
				ship_state.ship_id, h, occupied[h]])
			return false
	ships[ship_state.ship_id] = ship_state

	# Track by player
	if not ships_by_side.has(ship_state.side):
		ships_by_side[ship_state.side] = []
	ships_by_side[ship_state.side].append(ship_state.ship_id)

	Trace.trace_log("GameState", "Added ship %s (side %d)" % [ship_state.ship_id, ship_state.side])
	return true

func remove_ship(ship_id: String) -> void:
	## Remove a ship from the state container. Used by both server and client.  SCV:ALLOW
	if not ships.has(ship_id):
		return

	var ship_state = ships[ship_id]
	var side = ship_state.side

	ships.erase(ship_id)

	if ships_by_side.has(side):
		ships_by_side[side].erase(ship_id)

	Trace.trace_log("GameState", "Removed ship %s" % ship_id)

## SERVER: a fresh event log for `turn` whose events record each named ship's controlling side
## when logged (PhaseEvent.sides), so the log can label them as they were then.
func new_turn_log(turn: int) -> PhaseEvents.PhaseLog:
	var fresh: PhaseEvents.PhaseLog = PhaseEvents.PhaseLog.new()
	fresh.turn = turn
	fresh.side_of = side_of
	return fresh

## The side controlling the ship now, -1 for an unknown id.
func side_of(ship_id: String) -> int:
	var ship: ShipState = ships.get(ship_id)
	return ship.side if ship != null else -1

func get_ship(ship_id: String) -> ShipState:
	"""Get ship state by ID"""
	return ships.get(ship_id)

func get_side_ships(side: int) -> Array[ShipState]:
	"""Get all ships of a side"""
	var result: Array[ShipState] = []
	if ships_by_side.has(side):
		for ship_id in ships_by_side[side]:
			if ships.has(ship_id):
				result.append(ships[ship_id])
	return result

## Ships whose original owner is `side`, whoever controls them now (victory points, VI.B).
func get_original_side_ships(side: int) -> Array[ShipState]:
	var result: Array[ShipState] = []
	var ids: Array = ships.keys()
	ids.sort()
	for ship_id in ids:
		if ships[ship_id].original_side == side:
			result.append(ships[ship_id])
	return result

## SERVER ONLY: hands a ship to `side` (a prize, 10.H.1; through ShipStateController) and
## re-indexes ships_by_side. Returns false when refused.
func transfer_control(ship_id: String, side: int) -> bool:
	if not is_server:
		push_error("GameState: Cannot transfer control on client")
		return false
	var ship: ShipState = ships.get(ship_id)
	if ship == null:
		return false
	var before := ship.side
	if not ship_controller.set_controller_side(ship_id, -1 if side == ship.original_side else side):
		return false
	if ships_by_side.has(before):
		ships_by_side[before].erase(ship_id)
	if not ships_by_side.has(side):
		ships_by_side[side] = []
	if not ships_by_side[side].has(ship_id):
		ships_by_side[side].append(ship_id)
	Trace.trace_log("GameState", "Ship %s now controlled by side %d" % [ship_id, side])
	return true

func get_all_ships() -> Array[ShipState]:
	"""Get all ships in game"""
	var result: Array[ShipState] = []
	for ship_state in ships.values():
		result.append(ship_state)
	return result

## Ships still on the map (ShipState.is_on_map(): not removed by 8.G.1f), for map queries such
## as the movement resolver's ship list. Read-only.
func ships_on_map() -> Array[ShipState]:
	var result: Array[ShipState] = []
	for ship_state in ships.values():
		if ship_state.is_on_map():
			result.append(ship_state)
	return result

func clear_ships() -> void:
	"""Clear all ships (for new game)"""
	if not is_server:
		push_error("GameState: Cannot clear ships on client")
		return
	ships.clear()
	ships_by_side.clear()
	players.clear()
	groups = {}

## State History Management

func save_environment_snapshot(turn_number: int) -> void:
	"""Save a snapshot of the current environment state for the given turn"""
	if not is_server:
		push_error("GameState: Cannot save an environment snapshot on client")
		return
	if not environment:
		push_warning("GameState: Cannot save environment snapshot - environment is null")
		return

	# Create deep copy of current environment state
	var snapshot = environment.duplicate(true)

	# Ensure array has space for this turn
	while environment_history.size() <= turn_number:
		environment_history.append(null)

	environment_history[turn_number] = snapshot
	Trace.trace_log("GameState", "Saved environment snapshot for turn %d" % turn_number)

func get_environment_at_turn(turn_number: int) -> EnvironmentState:
	"""Get environment state from a specific turn (returns null if not found)"""
	if turn_number >= 0 and turn_number < environment_history.size():
		return environment_history[turn_number]
	return null

func get_previous_environment(turns_ago: int = 1) -> EnvironmentState:
	"""Get environment from N turns ago relative to current turn"""
	var target_turn = current_turn - turns_ago
	return get_environment_at_turn(target_turn)

func save_ship_snapshot(ship_id: String, turn_number: int) -> void:
	"""Save a snapshot of a specific ship's state for the given turn"""
	if not is_server:
		push_error("GameState: Cannot save a ship snapshot on client")
		return
	if not ships.has(ship_id):
		push_warning("GameState: Cannot save ship snapshot - ship %s not found" % ship_id)
		return

	var ship = ships[ship_id]

	# Create deep copy of ship state
	var snapshot = ship.duplicate(true)

	# Initialize ship history array if needed
	if not ship_history.has(ship_id):
		ship_history[ship_id] = []

	var history = ship_history[ship_id]

	# Ensure array has space for this turn
	while history.size() <= turn_number:
		history.append(null)

	history[turn_number] = snapshot
	Trace.trace_log("GameState", "Saved ship %s snapshot for turn %d" % [ship_id, turn_number])

func save_all_ships_snapshot(turn_number: int) -> void:
	"""Save snapshots of all ships for the given turn"""
	if not is_server:
		push_error("GameState: Cannot save ship snapshots on client")
		return
	for ship_id in ships.keys():
		save_ship_snapshot(ship_id, turn_number)

func get_ship_at_turn(ship_id: String, turn_number: int) -> ShipState:
	"""Get a ship's state from a specific turn (returns null if not found)"""
	if not ship_history.has(ship_id):
		return null

	var history = ship_history[ship_id]
	if turn_number >= 0 and turn_number < history.size():
		return history[turn_number]
	return null

func get_previous_ship_state(ship_id: String, turns_ago: int = 1) -> ShipState:
	"""Get a ship's state from N turns ago relative to current turn"""
	var target_turn = current_turn - turns_ago
	return get_ship_at_turn(ship_id, target_turn)

func clear_state_history() -> void:
	"""Clear all historical state data (for new game)"""
	if not is_server:
		push_error("GameState: Cannot clear the state history on client")
		return
	environment_history.clear()
	ship_history.clear()
	Trace.trace_log("GameState", "Cleared all state history")

## State Serialization (for save/load and multiplayer)

func serialize_full_state() -> Dictionary:
	"""Serialize entire game state for network transmission or save/load"""
	var ship_states = []
	for ship_id in ships.keys():
		ship_states.append(ships[ship_id].serialize())

	# Serialize environment history
	var env_history = []
	for env_state in environment_history:
		if env_state:
			env_history.append(env_state.serialize())
		else:
			env_history.append(null)

	# Serialize ship history
	var ships_history = {}
	for ship_id in ship_history.keys():
		var history_array = []
		for ship_state in ship_history[ship_id]:
			if ship_state:
				history_array.append(ship_state.serialize())
			else:
				history_array.append(null)
		ships_history[ship_id] = history_array

	var actions: Array = []
	for action in boarding_actions:
		actions.append(action.to_dict())
	return {
		"turn": current_turn,
		"phase": current_phase,
		"boarding_actions": actions,
		"boarding_seq": boarding_seq,
		"linked_at_plot": linked_at_plot.duplicate(true),
		"environment": environment.serialize() if environment else {},
		"ships": ship_states,
		"environment_history": env_history,
		"ship_history": ships_history
	}

func deserialize_full_state(data: Dictionary) -> void:
	"""Load full game state from network or save file"""
	if not is_server:
		push_error("GameState: Cannot load a full state on client")
		return
	current_turn = data.get("turn", 1)
	current_phase = data.get("phase", GamePhase.SETUP) as GamePhase

	# Load environment
	if data.has("environment"):
		environment = EnvironmentState.deserialize(data.environment)
	else:
		environment = EnvironmentState.new()

	boarding_actions = []
	for action_data in data.get("boarding_actions", []):
		boarding_actions.append(BoardingAction.from_dict(action_data))
	boarding_seq = int(data.get("boarding_seq", 0))
	linked_at_plot = (data.get("linked_at_plot", {}) as Dictionary).duplicate(true)

	# Load ships
	clear_ships()
	for ship_data in data.get("ships", []):
		var ship_state = ShipState.deserialize(ship_data)
		add_ship(ship_state)

	# Load environment history
	environment_history.clear()
	if data.has("environment_history"):
		for env_data in data.environment_history:
			if env_data:
				environment_history.append(EnvironmentState.deserialize(env_data))
			else:
				environment_history.append(null)

	# Load ship history
	ship_history.clear()
	if data.has("ship_history"):
		for ship_id in data.ship_history.keys():
			var history_array: Array[ShipState] = []
			for ship_data in data.ship_history[ship_id]:
				if ship_data:
					history_array.append(ShipState.deserialize(ship_data))
				else:
					history_array.append(null)
			ship_history[ship_id] = history_array

	Trace.trace_log("GameState", "Loaded state for turn %d, phase %s, %d ships, %d turns of history" % [
		current_turn,
		get_phase_name(),
		ships.size(),
		environment_history.size()
	])

## State Synchronization (for multiplayer)

func sync_from_server(state_data: Dictionary) -> void:
	"""Apply full state update from server - CLIENT ONLY"""
	if is_server:
		push_error("GameState: Cannot sync from server on server")
		return

	# Update phase state
	current_turn = state_data.get("turn", 1)
	current_phase = state_data.get("phase", GamePhase.SETUP) as GamePhase
	players_ready = TurnPhaseController.readiness_from(state_data.get("players_ready", {}))

	# Update environment
	if state_data.has("environment"):
		if environment:
			# Update existing environment
			var env_data = state_data.environment
			environment.wind_direction = env_data.get("wind_direction", 0)
			environment.wind_speed = env_data.get("wind_speed", 2)
			environment.wind_speed_change = env_data.get("wind_speed_change", "steady")
			environment.wind_direction_change = env_data.get("wind_direction_change", "none")
			environment.sea_state = EnvironmentState.clamp_sea_state(int(env_data.get("sea_state", 1)))
			environment.visibility = env_data.get("visibility", "clear")
			environment.time_of_day = env_data.get("time_of_day", "day")
			environment.precipitation = env_data.get("precipitation", "none")
		else:
			environment = EnvironmentState.deserialize(state_data.environment)

	# Update ships
	var ship_ids_to_remove = []
	for ship_id in ships.keys():
		var found = false
		for ship_data in state_data.get("ships", []):
			if ship_data.get("ship_id") == ship_id:
				found = true
				break
		if not found:
			ship_ids_to_remove.append(ship_id)

	# Remove ships that no longer exist
	for ship_id in ship_ids_to_remove:
		remove_ship(ship_id)

	# Update or add ships
	for ship_data in state_data.get("ships", []):
		var ship_id = ship_data.get("ship_id")
		if ships.has(ship_id):
			# Update existing ship
			_update_ship_from_data(ships[ship_id], ship_data)
		else:
			# Add new ship
			var ship_state = ShipState.deserialize(ship_data)
			add_ship(ship_state)

	# Emit sync signal
	state_synced.emit()
	Trace.trace_log("GameState", "State synced from server: Turn %d, Phase %s, %d ships" % [
		current_turn,
		get_phase_name(),
		ships.size()
	])

func _update_ship_from_data(ship: ShipState, data: Dictionary) -> void:
	## CLIENT ONLY: Apply serialized ship data from server sync.  SCV:ALLOW
	## Callers (sync_from_server, NetworkSync._apply_delta_changes) are guarded against server-side use.
	var pos = data.get("position", {"q": ship.hex_position.x, "r": ship.hex_position.y})
	ship.hex_position = Vector2i(pos.q, pos.r)
	ship.facing = data.get("facing", ship.facing)
	ship.speed = data.get("speed", ship.speed)
	ship.sail_state = data.get("sail_state", ship.sail_state)
	var rigging_hp_data = data.get("rigging_current_hp", null)
	if rigging_hp_data != null:
		ship.rigging_current_hp.clear()
		for hp in rigging_hp_data:
			ship.rigging_current_hp.append(int(hp))
	ship.hull_current_hp = data.get("hull_current_hp", ship.hull_current_hp)
	if data.has("crew_count"):
		ship.crew_count = ShipState._int_array(data["crew_count"])
	ship.marine_count = data.get("marine_count", ship.marine_count)
	ship.crew_quality = data.get("crew_quality", ship.crew_quality)
	ship.morale_rating = int(data.get("morale_rating", ship.morale_rating))
	ship.status = int(data.get("status", ship.status)) as ShipState.Status
	ship.controller_side = int(data.get("controller_side", data.get("controller_id", ship.controller_side)))
	if data.has("prize"):
		ship.prize = ShipState.prize_from(data["prize"])
	if data.has("detached_boxes"):
		ship.detached_boxes = ShipState._int_array(data["detached_boxes"])
	if data.has("guns_dismounted"):
		ship.guns_dismounted = ShipState._int_array(data["guns_dismounted"])
	if data.has("initial_broadside_fired"):
		ship.initial_broadside_fired.clear()
		for fired in data["initial_broadside_fired"]:
			ship.initial_broadside_fired.append(bool(fired))
	ship.crew_auto = bool(data.get("crew_auto", ship.crew_auto))
	if data.has("crew_tasks"):
		ship.crew_tasks.clear()
		for task in data["crew_tasks"]:
			ship.crew_tasks.append(ShipState.crew_task_from(task))
	ship.task_seq = int(data.get("task_seq", ship.task_seq))
	if data.has("plotted_sections"):
		ship.plotted_sections = ShipState._int_array(data["plotted_sections"])
	ship.mp_used_this_turn = int(data.get("mp_used_this_turn", ship.mp_used_this_turn))
	if data.has("checked_sections"):
		ship.checked_sections = (data["checked_sections"] as Dictionary).duplicate(true)
	ship.moved_this_turn = data.get("moved_this_turn", ship.moved_this_turn)
	ship.pending_morale_checks = int(data.get("pending_morale_checks", ship.pending_morale_checks))
	if data.has("morale_triggers_used"):
		ship.morale_triggers_used.clear()
		for trigger in data["morale_triggers_used"]:
			ship.morale_triggers_used.append(str(trigger))
	ship.unfoul_attempts = int(data.get("unfoul_attempts", ship.unfoul_attempts))
	if data.has("plotted_actions"):
		ship.plotted_actions = ShipState.plot_from(data["plotted_actions"])
