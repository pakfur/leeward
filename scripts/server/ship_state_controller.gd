class_name ShipStateController
extends Node
## ShipStateController - Server-authoritative ship state management
## All ship state mutations must go through this controller

signal ship_state_changed(ship_id: String)

var is_server: bool = true  # Set to true on server, false on clients
var game_state: Node = null

func _init(state: Node = null) -> void:
	game_state = state if state else GameState

## Computed Properties

func get_rigging_quality(ship_id: String) -> int:
	## Rigging level: number of rigging sections that still have boxes (0-4)
	var ship = game_state.get_ship(ship_id)
	if not ship:
		return 4
	return ship.rigging_level()

func get_movement_allowance(ship_id: String, facing: int = -1) -> int:
	var ship = game_state.get_ship(ship_id)
	if not ship:
		return 0

	var wind_dir = game_state.environment.wind_direction if game_state.environment else 0
	var hex_grid = HexGrid.new()
	var wind_facing = hex_grid.get_wind_facing(ship.facing if facing < 0 else facing, wind_dir)

	var rigging_quality = get_rigging_quality(ship_id)
	if rigging_quality == 0:
		return 0  # dismasted: never consult the table

	var spd_type = ship.ship.speed_type if ship.ship else "F/F"
	var wind_speed = game_state.environment.wind_speed if game_state.environment else 2
	if wind_speed <= 0:
		return 0  # calm: the table starts at wind speed 1
	var ma = DataManager.get_movement_allowance(
		spd_type,
		wind_speed,
		wind_facing,
		ship.movement_sail_state(),
		rigging_quality
	)
	# Sheets cut / shrouds severed (rigging #7, #9): -1 MP in every direction and sail state.
	ma = maxi(ma - ship.critical_mp_loss(current_turn()), 0)
	# 5.G: blocked wind, after every other change to MA.
	var ship_facing: int = ship.facing if facing < 0 else facing
	ma = BlockedWind.apply(ma, BlockedWind.is_blocked(ship.hex_position, ship_facing, wind_dir,
			game_state.ships.values(), ship_id))

	Trace.trace_log("ShipState", "MA: %d | wind: %s | facing: %s | speed: %s | sail: %s" % [ma, wind_dir, wind_facing, wind_speed, ship.sail_state])
	return ma

## The g-t being played (0 when the game state has none, as in some test doubles).
func current_turn() -> int:
	var turn = game_state.get("current_turn") if game_state else null
	return int(turn) if turn != null else 0

## Acceleration and deceleration limits this g-t (5.E.4-6): {"accel", "decel"}.
func get_speed_change_limits(ship_id: String) -> Dictionary:
	var ship = game_state.get_ship(ship_id)
	if not ship:
		return {"accel": 0, "decel": 0}
	return speed_change_limits(ship)

## The Speed Change table value, then the 5.E.5 reductions (two rigging sections lost, towing,
## WS 1: -1 each, never below 1), then Braces Cut (accel and decel at most 1, rigging #4), then
## Sheets Cut (accel -1, may reach 0, 5.E.6; rigging #7, from the g-t after it was inflicted).
func speed_change_limits(ship: ShipState) -> Dictionary:
	var maneuverability: String = ship.ship.maneuverability.to_lower() if ship.ship else "b"
	var accel: int = DataManager.get_speed_change("acceleration", maneuverability)
	var decel: int = DataManager.get_speed_change("deceleration", maneuverability)
	var reduction := 0
	if ship.rigging_sections_lost() >= 2:
		reduction += 1
	if ship.towing:
		reduction += 1
	var wind_speed: int = game_state.environment.wind_speed if game_state.get("environment") else 2
	if wind_speed == 1:
		reduction += 1
	if reduction > 0:
		accel = maxi(accel - reduction, 1)
	if ship.has_critical("braces_cut"):
		accel = mini(accel, 1)
		decel = mini(decel, 1)
	if ship.sheets_cut_active(current_turn()):
		accel = maxi(accel - 1, 0)
	return {"accel": accel, "decel": decel}

## Movement and Positioning

func set_ship_position(ship_id: String, hex_position: Vector2i) -> bool:
	"""SERVER ONLY: Set ship position"""
	if not is_server:
		push_error("ShipStateController: Cannot modify ship position on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship.hex_position = hex_position
	ship_state_changed.emit(ship_id)
	Trace.trace_log("ShipState", "Ship %s moved to %s" % [ship_id, hex_position])
	return true

func set_ship_facing(ship_id: String, facing: int) -> bool:
	"""SERVER ONLY: Set ship facing"""
	if not is_server:
		push_error("ShipStateController: Cannot modify ship facing on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship.facing = facing % 6
	ship_state_changed.emit(ship_id)
	Trace.trace_log("ShipState", "Ship %s facing changed to %d" % [ship_id, ship.facing])
	return true

func set_ship_speed(ship_id: String, speed: int) -> bool:
	"""SERVER ONLY: Set ship speed"""
	if not is_server:
		push_error("ShipStateController: Cannot modify ship speed on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship.speed = speed
	ship_state_changed.emit(ship_id)
	return true

## Sail and Rigging

func set_sail_state(ship_id: String, sail_state: String) -> bool:
	"""SERVER ONLY: Set ship sail state"""
	if not is_server:
		push_error("ShipStateController: Cannot modify sail state on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	var valid_states = ["FS", "MS", "PS", "NS"]
	if not sail_state in valid_states:
		push_error("[Server] Invalid sail state: %s" % sail_state)
		return false

	ship.sail_state = sail_state
	ship_state_changed.emit(ship_id)
	Trace.trace_log("ShipState", "Ship %s sail state: %s" % [ship_id, sail_state])
	return true

func apply_rigging_damage(ship_id: String, section: int, damage: int) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot apply damage on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	if section < 0 or section >= ship.rigging_current_hp.size():
		push_error("[Server] Invalid rigging section: %d" % section)
		return false

	ship.rigging_current_hp[section] = max(0, ship.rigging_current_hp[section] - damage)
	ship_state_changed.emit(ship_id)
	return true

## Hull Damage

func apply_hull_damage(ship_id: String, section: int, damage: int) -> bool:
	"""SERVER ONLY: Apply hull damage"""
	if not is_server:
		push_error("ShipStateController: Cannot apply damage on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	if section < 0 or section >= ship.hull_current_hp.size():
		push_error("[Server] Invalid hull section: %d" % section)
		return false

	ship.hull_current_hp[section] = max(0, ship.hull_current_hp[section] - damage)
	ship_state_changed.emit(ship_id)
	var max_hp = ship.ship.hull_hp[section] if ship.ship else 0
	Trace.trace_log("ShipState", "Ship %s hull section %d: %d/%d HP" % [
		ship_id, section, ship.hull_current_hp[section], max_hp
	])
	return true

func repair_hull(ship_id: String, section: int, repair_amount: int) -> bool:
	"""SERVER ONLY: Repair hull damage"""
	if not is_server:
		push_error("ShipStateController: Cannot repair on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	if section < 0 or section >= ship.hull_current_hp.size():
		push_error("[Server] Invalid hull section: %d" % section)
		return false

	var max_hp = ship.ship.hull_hp[section] if ship.ship else 0
	ship.hull_current_hp[section] = min(max_hp, ship.hull_current_hp[section] + repair_amount)
	ship_state_changed.emit(ship_id)
	return true

## Crew Management

func set_morale_rating(ship_id: String, morale: int) -> bool:
	"""SERVER ONLY: Set crew morale rating"""
	if not is_server:
		push_error("ShipStateController: Cannot modify morale on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.morale_rating = clampi(morale, 2, 6)
	ship_state_changed.emit(ship_id)
	return true

func set_crew_quality(ship_id: String, quality: String) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify crew quality on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.crew_quality = quality
	ship_state_changed.emit(ship_id)
	return true

func remove_crew_box(ship_id: String, marine: bool) -> int:
	"""SERVER ONLY: Remove one crew box. Takes the preferred type, else the other.
	Returns the sailor section emptied (0-3), 4 if marines emptied, -1 otherwise."""
	if not is_server:
		push_error("ShipStateController: Cannot modify crew on client")
		return -1
	var ship = _server_ship(ship_id)
	if not ship:
		return -1
	var emptied := -1
	var section: int = _first_sailor_section(ship)
	var take_marine: bool = ship.marine_count > 0 and (marine or section == -1)
	if take_marine:
		ship.marine_count -= 1
		if ship.marine_count == 0:
			emptied = 4
	else:
		if section != -1:
			ship.crew_count[section] -= 1
			if ship.crew_count[section] == 0:
				emptied = section
	ship_state_changed.emit(ship_id)
	return emptied

func _first_sailor_section(ship: ShipState) -> int:
	for i in range(ship.crew_count.size()):
		if ship.crew_count[i] > 0:
			return i
	return -1

func note_morale_check(ship_id: String, trigger: String, count: int = 1) -> bool:
	"""SERVER ONLY: Queue morale checks for a trigger. False if the trigger was already used."""
	if not is_server:
		push_error("ShipStateController: Cannot modify morale checks on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	if ship.morale_triggers_used.has(trigger):
		return false
	ship.morale_triggers_used.append(trigger)
	ship.pending_morale_checks += count
	ship_state_changed.emit(ship_id)
	return true

func clear_pending_morale_checks(ship_id: String) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify morale checks on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.pending_morale_checks = 0
	ship_state_changed.emit(ship_id)
	return true

## Combat and turn-loop state

func set_status(ship_id: String, status: ShipState.Status) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify status on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.status = status
	ship_state_changed.emit(ship_id)
	return true

func add_guns_dismounted(ship_id: String, amount: int, side: int = -1) -> bool:
	"""SERVER ONLY: Add dismounted guns to one side (PORT/STARBOARD), or both sides when side is -1"""
	if not is_server:
		push_error("ShipStateController: Cannot modify guns on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	for s in [ShipState.PORT, ShipState.STARBOARD]:
		if side == -1 or side == s:
			ship.guns_dismounted[s] += amount
	ship_state_changed.emit(ship_id)
	return true

func set_initial_broadside_fired(ship_id: String, side: int) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify broadside on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	if side != ShipState.PORT and side != ShipState.STARBOARD:
		push_error("[Server] Invalid side: %d" % side)
		return false
	ship.initial_broadside_fired[side] = true
	ship_state_changed.emit(ship_id)
	return true

## --- Crew tasks (4.A.3, 4.B; crew-tasks spec §2.2) ---

func set_crew_auto(ship_id: String, on: bool) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify crew_auto on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.crew_auto = on
	ship_state_changed.emit(ship_id)
	return true

## The plotted crew sections: {section:int -> {"code": String, "params": Dictionary}}.
func set_crew_assignments(ship_id: String, assignments: Dictionary) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot plot crew on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	var copy := {}
	for section in assignments:
		copy[int(section)] = (assignments[section] as Dictionary).duplicate(true)
	ship.plotted_actions["crew_assignments"] = copy
	ship_state_changed.emit(ship_id)
	return true

## The ship's crew orders this turn ({"sail_target": ""}); keys not given keep their value.
func set_crew_orders(ship_id: String, orders: Dictionary) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot plot crew orders on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	var current = ship.plotted_actions.get("crew_orders", {})
	var merged: Dictionary = (current as Dictionary).duplicate(true) if current is Dictionary else {}
	merged.merge(orders.duplicate(true), true)
	ship.plotted_actions["crew_orders"] = merged
	ship_state_changed.emit(ship_id)
	return true

## Adds a crew task ({code, sections, params, forced, marines_available}; seq, done, started_turn
## and ended are filled in). Returns its seq, or -1.
func add_task(ship_id: String, task: Dictionary) -> int:
	if not is_server:
		push_error("ShipStateController: Cannot add crew task on client")
		return -1
	var ship = _server_ship(ship_id)
	if not ship:
		return -1
	ship.task_seq += 1
	var entry := ShipState.crew_task_from(task)
	entry["seq"] = ship.task_seq
	entry["done"] = int(task.get("done", 0))
	entry["started_turn"] = int(task.get("started_turn", current_turn()))
	entry["ended"] = ""
	ship.crew_tasks.append(entry)
	ship_state_changed.emit(ship_id)
	return ship.task_seq

## Merges `fields` into the task with this seq (seq itself is kept).
func update_task(ship_id: String, seq: int, fields: Dictionary) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify crew task on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	for task in ship.crew_tasks:
		if int(task["seq"]) == seq:
			for key in fields:
				if key != "seq":
					task[key] = fields[key].duplicate(true) if (fields[key] is Dictionary or fields[key] is Array) else fields[key]
			ship_state_changed.emit(ship_id)
			return true
	push_error("[Server] No crew task %d on %s" % [seq, ship_id])
	return false

## Ends the task: it stays, with `ended` = reason, until the g-t ends (clear_turn_flags).
func end_task(ship_id: String, seq: int, reason: String) -> bool:
	return update_task(ship_id, seq, {"ended": reason if reason != "" else "ended"})

func set_plotted_sections(ship_id: String, sections: Array) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify plotted sections on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.plotted_sections = ShipState._int_array(sections)
	ship_state_changed.emit(ship_id)
	return true

## 8.F.5, 9.B.2: kind "rigging" or "hull", section 0-3.
func mark_section_checked(ship_id: String, kind: String, section: int) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify checked sections on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship or not ship.checked_sections.has(kind):
		return false
	ship.checked_sections[kind][section] = true
	ship_state_changed.emit(ship_id)
	return true

func set_mp_used(ship_id: String, mps: int) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify mp_used_this_turn on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.mp_used_this_turn = mps
	ship_state_changed.emit(ship_id)
	return true

func set_moved_this_turn(ship_id: String, moved: bool) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify moved_this_turn on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.moved_this_turn = moved
	ship_state_changed.emit(ship_id)
	return true

func set_unfoul_attempts(ship_id: String, attempts: int) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify unfoul attempts on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.unfoul_attempts = attempts
	ship_state_changed.emit(ship_id)
	return true

## Critical hits (7.D.11-12)

## Adds a lasting critical effect and returns its seq, or -1 if refused.
## effect needs "id" (ShipState.CRITICAL_EFFECT_IDS); "side", "turn" and
## "expires_after_turn" are optional. seq and attempts are set here.
func add_critical_effect(ship_id: String, effect: Dictionary) -> int:
	if not is_server:
		push_error("ShipStateController: Cannot add critical effect on client")
		return -1
	var ship = _server_ship(ship_id)
	if not ship:
		return -1
	var id := str(effect.get("id", ""))
	if not ShipState.CRITICAL_EFFECT_IDS.has(id):
		push_error("[Server] unknown critical effect '%s'" % id)
		return -1
	var seq: int = ship.critical_seq
	ship.critical_effects.append({
		"seq": seq,
		"id": id,
		"turn": int(effect.get("turn", game_state.current_turn)),
		"side": int(effect.get("side", -1)),
		"attempts": 0,
		"expires_after_turn": int(effect.get("expires_after_turn", -1)),
	})
	ship.critical_seq = seq + 1
	ship_state_changed.emit(ship_id)
	return seq

## Merges changes into the effect with this seq; "seq" and "id" cannot change.
func update_critical_effect(ship_id: String, seq: int, changes: Dictionary) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot update critical effect on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	var index := _critical_index(ship, seq)
	if index == -1:
		return false
	for key in changes:
		if key != "seq" and key != "id":
			ship.critical_effects[index][key] = changes[key]
	ship_state_changed.emit(ship_id)
	return true

func remove_critical_effect(ship_id: String, seq: int) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot remove critical effect on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	var index := _critical_index(ship, seq)
	if index == -1:
		return false
	ship.critical_effects.remove_at(index)
	ship_state_changed.emit(ship_id)
	return true

func _critical_index(ship: ShipState, seq: int) -> int:
	for i in range(ship.critical_effects.size()):
		if int(ship.critical_effects[i].get("seq", -1)) == seq:
			return i
	push_error("[Server] %s has no critical effect with seq %d" % [ship.ship_id, seq])
	return -1

## Takes the next critical seq (shared with add_critical_effect), e.g. for a unique
## morale trigger (9.B.1e). Returns -1 if refused.
func next_critical_seq(ship_id: String) -> int:
	if not is_server:
		push_error("ShipStateController: Cannot take critical seq on client")
		return -1
	var ship = _server_ship(ship_id)
	if not ship:
		return -1
	var seq: int = ship.critical_seq
	ship.critical_seq = seq + 1
	ship_state_changed.emit(ship_id)
	return seq

## 6.F.4: the turn carried over to the first MP of the next g-t (-1 none, PORT, STARBOARD).
func set_pending_turn(ship_id: String, direction: int) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify pending turn on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.pending_turn = direction
	ship_state_changed.emit(ship_id)
	return true

## The direction of the last step the ship executed (-1 straight, PORT, STARBOARD; spec Q15).
func set_last_step_direction(ship_id: String, direction: int) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify last step on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.last_step_direction = direction
	ship_state_changed.emit(ship_id)
	return true

func set_rudder_destroyed(ship_id: String, destroyed: bool) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify rudder on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.rudder_destroyed = destroyed
	ship_state_changed.emit(ship_id)
	return true

func set_wheel_shot_away(ship_id: String, shot_away: bool) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify wheel on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.wheel_shot_away = shot_away
	ship_state_changed.emit(ship_id)
	return true

## Adds one fire (stored only until 8.E exists).
func add_fire(ship_id: String) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify fires on client")
		return false
	var ship = _server_ship(ship_id)
	if not ship:
		return false
	ship.fires += 1
	ship_state_changed.emit(ship_id)
	return true

## Crosses out the current rigging section (the lowest-numbered one with boxes left;
## rigging #2, #11, #12). Returns its index, or -1 if the ship is already dismasted.
func cross_out_rigging_section(ship_id: String) -> int:
	if not is_server:
		push_error("ShipStateController: Cannot cross out rigging on client")
		return -1
	var ship = _server_ship(ship_id)
	if not ship:
		return -1
	for section in range(ship.rigging_current_hp.size()):
		if ship.rigging_current_hp[section] > 0:
			ship.rigging_current_hp[section] = 0
			ship_state_changed.emit(ship_id)
			Trace.trace_log("ShipState", "Ship %s rigging section %d crossed out" % [ship_id, section])
			return section
	return -1

func _server_ship(ship_id: String) -> ShipState:
	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
	return ship

## Plotted Actions

func set_immobilized(ship_id: String, immobilized: bool) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify immobilized on client")
		return false
	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false
	ship.immobilized = immobilized
	ship_state_changed.emit(ship_id)
	return true

func set_collision_this_turn(ship_id: String, collision: bool) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify collision on client")
		return false
	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false
	ship.collision_this_turn = collision
	ship_state_changed.emit(ship_id)
	return true

func set_fouled_with(ship_id: String, fouled_with: String) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot modify fouled_with on client")
		return false
	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false
	ship.fouled_with = fouled_with
	ship.unfoul_attempts = 0
	ship_state_changed.emit(ship_id)
	return true

func set_plotted_movement(ship_id: String, movement_commands: Array) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot plot movement on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship.plotted_actions["movement"] = movement_commands
	Trace.trace_log("ShipState", "Ship %s plotted movement: %s" % [ship_id, movement_commands])
	return true

func clear_plotted_actions(ship_id: String) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot clear plot on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship._clear_plot()
	return true

func clear_turn_flags(ship_id: String) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot clear turn flags on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship._clear_turn_flags()
	ship.plotted_sections.clear()
	ship.mp_used_this_turn = 0
	var live: Array[Dictionary] = []
	for task in ship.crew_tasks:
		if task.get("ended", "") == "":
			live.append(task)
	ship.crew_tasks = live
	ship_state_changed.emit(ship_id)
	return true

## Movement Resolution

func resolve_movement(ship_id: String) -> bool:
	"""SERVER ONLY: Resolve plotted movement for a ship"""
	if not is_server:
		push_error("ShipStateController: Cannot resolve movement on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	var movement = ship.plotted_actions.get("movement", [])
	if movement.is_empty():
		Trace.trace_log("ShipState", "Ship %s has no plotted movement" % ship_id)
		return true

	# TODO: Implement actual movement resolution
	# For now, just log the movement
	Trace.trace_log("ShipState", "Resolving movement for %s: %s" % [ship.ship_name, movement])

	# Movement logic will be implemented later with hex grid calculations
	# This would involve:
	# 1. Parse movement commands (F2, P, S, etc.)
	# 2. Calculate new position and facing
	# 3. Check for collisions
	# 4. Apply movement
	# 5. Update ship position and facing

	ship_state_changed.emit(ship_id)
	return true

func resolve_all_movement() -> void:
	"""SERVER ONLY: Resolve movement for all ships"""
	if not is_server:
		push_error("ShipStateController: Cannot resolve movement on client")
		return

	Trace.trace_log("ShipState", "Resolving movement for all ships")
	for ship_id in game_state.ships.keys():
		resolve_movement(ship_id)
