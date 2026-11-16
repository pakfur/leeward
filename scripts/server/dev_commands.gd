class_name DevCommands
extends RefCounted
## DevCommands - server-side entry point for the Developer UI (F12).
##
## The Developer UI is a view: it never calls ShipStateController or EnvironmentController
## mutators itself. It sends these requests, which the server checks (server only, debug builds
## only, known ship and property) before it changes anything. Each returns "" or a reason.

## Ship properties the Developer UI may set, mapped to their ShipStateController mutators.
const SHIP_PROPERTIES := {
	"facing": "set_ship_facing",
	"speed": "set_ship_speed",
	"sail_state": "set_sail_state",
}

var game_state


func _init(p_game_state) -> void:
	game_state = p_game_state


func _refusal() -> String:
	if not game_state.is_server:
		return "developer commands run on the server only"
	if not OS.is_debug_build():
		return "developer commands are disabled in release builds"
	return ""


## Sets one ship property (see SHIP_PROPERTIES) through ShipStateController.
func set_ship_property(ship_id: String, property: String, value: Variant) -> String:
	var reason := _refusal()
	if reason != "":
		return reason
	if game_state.get_ship(ship_id) == null:
		return "no ship %s" % ship_id
	if not SHIP_PROPERTIES.has(property):
		return "no developer command for ship property '%s'" % property
	var ok: bool = game_state.ship_controller.call(SHIP_PROPERTIES[property], ship_id, value)
	if not ok:
		return "the server refused %s.%s = %s" % [ship_id, property, value]
	Trace.trace_log("DevCommands", "Ship %s.%s = %s" % [ship_id, property, value])
	return ""


## Sets one environment property through EnvironmentController.
func set_environment_property(property: String, value: Variant) -> String:
	var reason := _refusal()
	if reason != "":
		return reason
	if not game_state.environment_controller.set_environment_property(property, value):
		return "the server refused Environment.%s = %s" % [property, value]
	Trace.trace_log("DevCommands", "Environment.%s = %s" % [property, value])
	return ""


## Starts a fire aboard the ship (as a hull critical would: FireController.start_fire, with its
## morale check). For trying out fire in a running game.
func start_fire(ship_id: String) -> String:
	var reason := _refusal()
	if reason != "":
		return reason
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "no ship %s" % ship_id
	if ship.is_destroyed():
		return "%s is destroyed" % ship_id
	var seq: int = game_state.fire_controller.start_fire(ship_id, FireController.CAUSE_CRIT,
		game_state.phase_controller.current_phase)
	if seq < 0:
		return "the server refused a fire aboard %s" % ship_id
	Trace.trace_log("DevCommands", "Fire %d started aboard %s" % [seq, ship_id])
	return ""


## Marks out `rigging` rigging and `hull` hull boxes on the ship (DamageController.apply_hits,
## lowest section first, with the usual checks), for trying out repairs in a running game.
func damage_ship(ship_id: String, rigging: int, hull: int) -> String:
	var reason := _refusal()
	if reason != "":
		return reason
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "no ship %s" % ship_id
	if ship.is_out_of_play():
		return "%s is out of play" % ship_id
	if rigging < 0 or hull < 0 or rigging + hull == 0:
		return "nothing to mark out"
	game_state.damage_controller.apply_hits(ship_id, rigging, hull, 0, "other",
		game_state.phase_controller.current_phase)
	Trace.trace_log("DevCommands", "Damaged %s: %d rigging, %d hull" % [ship_id, rigging, hull])
	return ""


## Skips to the next phase.
func advance_phase() -> String:
	var reason := _refusal()
	if reason != "":
		return reason
	game_state.phase_controller.advance_phase()
	Trace.trace_log("DevCommands", "Advanced phase")
	return ""
