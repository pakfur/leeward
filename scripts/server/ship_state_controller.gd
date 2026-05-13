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
	var ship = game_state.get_ship(ship_id)
	if not ship or not ship.ship:
		return 4

	var max_hp_array = ship.ship.rigging_hp
	var total_max = 0
	var total_current = 0

	for i in range(4):
		total_max += max_hp_array[i] if i < max_hp_array.size() else 0
		total_current += ship.rigging_current_hp[i]

	if total_max == 0:
		return 4

	var hp_percentage = float(total_current) / float(total_max)

	if hp_percentage >= 0.85:
		return 4
	elif hp_percentage >= 0.60:
		return 3
	elif hp_percentage >= 0.35:
		return 2
	else:
		return 1

func get_movement_allowance(ship_id: String) -> int:
	var ship = game_state.get_ship(ship_id)
	if not ship:
		return 0

	var wind_dir = game_state.environment.wind_direction if game_state.environment else 0
	var hex_grid = HexGrid.new()
	var wind_facing = hex_grid.get_wind_facing(ship.facing, wind_dir)

	var spd_type = ship.ship.speed_type if ship.ship else "F/F"
	var rigging_quality = get_rigging_quality(ship_id)
	var wind_speed = game_state.environment.wind_speed if game_state.environment else 2
	var ma = DataManager.get_movement_allowance(
		spd_type,
		wind_speed,
		wind_facing,
		ship.sail_state,
		rigging_quality
	)

	Trace.trace_log("ShipState", "MA: %d | wind: %s | facing: %s | speed: %s | sail: %s" % [ma, wind_dir, wind_facing, wind_speed, ship.sail_state])
	return ma

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

	ship.clear_plot()
	return true

func clear_turn_flags(ship_id: String) -> bool:
	if not is_server:
		push_error("ShipStateController: Cannot clear turn flags on client")
		return false

	var ship = game_state.get_ship(ship_id)
	if not ship:
		push_error("[Server] Ship not found: %s" % ship_id)
		return false

	ship.clear_turn_flags()
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
