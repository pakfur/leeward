class_name ShipStateController
extends Node
## ShipStateController - Server-authoritative ship state management
## All ship state mutations must go through this controller

signal ship_state_changed(ship_id: String)

var is_server: bool = true  # Set to true on server, false on clients
var game_state: Node = null

func _init(state: Node = null) -> void:
	game_state = state if state else GameState

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
	"""SERVER ONLY: Apply rigging damage"""
	if not is_server:
		push_error("ShipStateController: Cannot apply damage on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	if section < 0 or section >= ship.rigging_damage.size():
		push_error("[Server] Invalid rigging section: %d" % section)
		return false

	ship.rigging_damage[section] += damage
	_recalculate_rigging_quality(ship)
	ship_state_changed.emit(ship_id)
	return true

func _recalculate_rigging_quality(ship: ShipState) -> void:
	"""Recalculate rigging quality based on damage"""
	var intact_sails = 0
	for damage in ship.rigging_damage:
		if damage > 0:
			intact_sails += 1

	# The number of sails with > 0 damage
	ship.rigging_quality = intact_sails

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
	Trace.trace_log("ShipState", "Ship %s hull section %d: %d/%d HP" % [
		ship_id, section, ship.hull_current_hp[section], ship.hull_max_hp[section]
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

	var max_hp = ship.hull_max_hp[section]
	ship.hull_current_hp[section] = min(max_hp, ship.hull_current_hp[section] + repair_amount)
	ship_state_changed.emit(ship_id)
	return true

## Crew Management

func set_crew_count(ship_id: String, count: int) -> bool:
	"""SERVER ONLY: Set crew count"""
	if not is_server:
		push_error("ShipStateController: Cannot modify crew on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship.crew_count = max(0, count)
	ship_state_changed.emit(ship_id)
	return true

func set_crew_morale(ship_id: String, morale: int) -> bool:
	"""SERVER ONLY: Set crew morale"""
	if not is_server:
		push_error("ShipStateController: Cannot modify morale on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship.crew_morale = clamp(morale, 2, 5)
	ship_state_changed.emit(ship_id)
	return true

## Plotted Actions

func set_plotted_movement(ship_id: String, movement_commands: Array[String]) -> bool:
	"""SERVER ONLY: Set plotted movement commands"""
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
	"""SERVER ONLY: Clear all plotted actions for a ship"""
	if not is_server:
		push_error("ShipStateController: Cannot clear plot on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship.clear_plot()
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
