class_name PlanningText
extends RefCounted
## PlanningText - Pure presentation text for the planning panel: ship cards, the movement
## readout, the instruction line and collision warnings. No scene nodes, no state changes.


## "HMS Lively — 38-gun Frigate": how a ship is first identified in a panel. The type is left out
## when it is unknown or the name already starts with it (a fallback name such as "38-gun Frigate 2").
static func name_and_type(ship: ShipState) -> String:
	var type_name: String = ship.ship.name if ship.ship else ""
	if type_name == "" or ship.ship_name.to_lower().begins_with(type_name.to_lower()):
		return ship.ship_name
	return "%s — %s" % [ship.ship_name, type_name]


## The ship card's detail lines: hull and rigging as boxes per section (as in the status panel),
## the sail by name, and crew quality and morale spelled out.
static func card_lines(ship: ShipState) -> Array[String]:
	var t: Ship = ship.ship
	var no_max: Array[int] = []
	return [
		ShipStatusPanel.box_line("Hull", ship.hull_current_hp, t.hull_hp if t else no_max),
		ShipStatusPanel.box_line("Rigging", ship.rigging_current_hp, t.rigging_hp if t else no_max),
		PlanningSailUi.sail_label(ship.sail_state),
		"Crew quality %s, morale %d" % [ship.crew_quality, ship.morale_rating],
	]


## "Movement: N of M left" — M is the most the ship can spend this turn and stays fixed for the plot.
static func movement_line(remaining: int, maximum: int) -> String:
	return "Movement: %d of %d left" % [remaining, maximum]


## Why the plot's maximum is below the movement-table allowance, "" when it is not.
static func movement_limit_note(table_ma: int, maximum: int, speed_last_turn: int, acceleration: int) -> String:
	if table_ma <= maximum:
		return ""
	return "Limited by acceleration: speed last turn %d, may gain %d (wind and sail allow %d)." % [
		speed_last_turn, acceleration, table_ma]


## One line under the readout when a pivot changed the allowance itself (the movement table gives a
## different number on the new point of sail) instead of only spending its point. `before` and
## `after` are the server's remaining movement either side of the step; `old_code` / `new_code`
## are the wind-facing codes (L, C, B, R) of the heading before and after it. "" otherwise.
static func allowance_change_note(before: int, after: int, old_code: String, new_code: String) -> String:
	if old_code == new_code or after == before - 1 or (before <= 0 and after <= 0):
		return ""
	return "Allowance changed on the new heading (%s → %s)" % [
		ShipIndicatorModel.point_of_sail_label(old_code).to_lower(),
		ShipIndicatorModel.point_of_sail_label(new_code).to_lower()]


## The steering line of the plotting panel (hull #2, #3; 6.F), "" for sound steering.
## `jam` is ShipState.rudder_jam_direction(); `pending_turn` ShipState.pending_turn.
static func steering_note(poor_maneuvering: bool, chance: float, pending_turn: int, jam: int,
		rudder_destroyed: bool) -> String:
	var lines: PackedStringArray = []
	if pending_turn == 0 or pending_turn == 1:
		lines.append("Left-over turn to %s: must be the first move, succeeds without a roll." %
			PhaseEvents.SIDE_NAMES[pending_turn])
	if poor_maneuvering:
		var cause := "Rudder destroyed" if rudder_destroyed else "Wheel shot away"
		lines.append("%s: one 60° turn per game turn, %d%% to turn as plotted (else one hex ahead first)." % [
			cause, int(round(chance * 100.0))])
	if jam == -1:
		lines.append("Rudder jammed amidships: no turns.")
	elif jam == 0 or jam == 1:
		lines.append("Rudder jammed to %s: turns only that way, at least once if moving." %
			PhaseEvents.SIDE_NAMES[jam])
	return "\n".join(lines)


## The tacking note for a turn at MA 0 (5.D.2a): "Tack: 60 % with 2 at the braces (3: 80 %)";
## with a full crew at the braces only the first part.
static func tacking_note(chance: float, sections: int, full_chance: float, full_sections: int = 3) -> String:
	var text := "Tack: %d %% with %d at the braces" % [int(round(chance * 100.0)), sections]
	if sections < full_sections:
		text += " (%d: %d %%)" % [full_sections, int(round(full_chance * 100.0))]
	return text


const IRONS_NOTE := "Head to wind: the ship will be in irons and movement ends here."


## The note under the movement readout: the allowance-change note (may be ""), plus the irons
## warning whenever the plotted heading's wind-facing code is "L" (head to wind).
static func plot_note(allowance_note: String, heading_code: String) -> String:
	if heading_code != "L":
		return allowance_note
	return IRONS_NOTE if allowance_note == "" else allowance_note + "\n" + IRONS_NOTE


## The instruction line under the ship list. `needing`: ships still without orders;
## `unable`: ships that cannot move at all (fouled, struck, dismasted).
static func instructions(needing: int, total: int, unable: int) -> String:
	if needing == 1:
		return "1 ship still needs orders. Select it and press Movement."
	if needing > 1:
		return "%d ships still need orders. Select each and press Movement." % needing
	if total > 0 and unable == total:
		return "No ship can move this turn. Press End Planning."
	return "All ships have orders. Press End Planning."


## Hexes that currently hold another ship (its bow or stern): hex -> that ship's name.
## `hexes` are Vector2i; `ships` are ShipState; the plotting ship itself is ignored.
static func occupied_hexes(hexes: Array, ships: Array, active_ship_id: String) -> Dictionary:
	var by_hex := {}
	for ship in ships:
		if ship.ship_id != active_ship_id:
			for h in ship.occupied_hexes():  # bow and stern
				by_hex[h] = ship.ship_name
	var result := {}
	for hex in hexes:
		if by_hex.has(hex):
			result[hex] = by_hex[hex]
	return result


static func collision_text(ship_name: String) -> String:
	return "Collision risk: %s is here" % ship_name


## A turn whose stern would swing into another ship's hex.
static func swing_collision_text(ship_name: String) -> String:
	return "Stern would swing into %s" % ship_name
