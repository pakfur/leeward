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


## Moves a ship to bow `bow` facing `facing` (ShipStateController.set_ship_position / set_ship_facing),
## for setting up a situation in a running game, e.g. ships alongside for marine fire. Its movement
## plot, made for the old position, is cleared (the ship holds its place this turn). Refused when
## either hex is off the map or held by another ship, or the ship is out of play.
func place_ship(ship_id: String, bow: Vector2i, facing: int) -> String:
	var reason := _refusal()
	if reason != "":
		return reason
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return "no ship %s" % ship_id
	if ship.is_out_of_play():
		return "%s is out of play" % ship_id
	if facing < 0 or facing > 5:
		return "facing must be 0-5"
	var hexes: Array[Vector2i] = [bow, HexGrid.stern_of(bow, facing)]
	var held := Occupancy.build(game_state.get_all_ships(), [ship_id])
	for h in hexes:
		if not Occupancy.in_bounds(h, game_state.active_scenario):
			return "hex %s is off the map" % h
		if held.has(h):
			return "hex %s is held by %s" % [h, held[h]]
	var sc: ShipStateController = game_state.ship_controller
	if not sc.set_ship_position(ship_id, bow) or not sc.set_ship_facing(ship_id, facing):
		return "the server refused to move %s" % ship_id
	sc.set_plotted_movement(ship_id, [])
	Trace.trace_log("DevCommands", "Placed %s at %s facing %d" % [ship_id, bow, facing])
	return ""


## Grapples two adjacent ships at once (ShipStateController.add_grapple, no roll), for setting up a
## boarding in a running game. The link counts for boarding from the next PLANNING (10.A.2:
## linked at the start of the g-t), or at once when `count_now` (GameState.linked_at_plot is
## retaken). Refused unless both ships exist, are in play or struck, and are adjacent.
func grapple_ships(ship_id: String, other_id: String, count_now: bool = false) -> String:
	var reason := _refusal()
	if reason != "":
		return reason
	var a: ShipState = game_state.get_ship(ship_id)
	var b: ShipState = game_state.get_ship(other_id)
	if a == null or b == null or ship_id == other_id:
		return "two different ships are needed"
	if a.is_destroyed() or b.is_destroyed() or a.is_captured() or b.is_captured():
		return "a destroyed ship or a prize cannot be grappled from the Developer UI"
	if not game_state.grappling_controller.adjacent(a, b):
		return "%s and %s are not adjacent" % [ship_id, other_id]
	if not game_state.ship_controller.add_grapple(ship_id, other_id):
		return "the server refused the grapple"
	if count_now:
		game_state.boarding_controller.take_link_snapshot()
	Trace.trace_log("DevCommands", "Grappled %s and %s" % [ship_id, other_id])
	return ""


## Skips to the next phase.
func advance_phase() -> String:
	var reason := _refusal()
	if reason != "":
		return reason
	game_state.phase_controller.advance_phase()
	Trace.trace_log("DevCommands", "Advanced phase")
	return ""
