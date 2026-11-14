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


## Offered hexes that currently hold another ship: hex -> that ship's name.
## `hexes` are Vector2i; `ships` are ShipState; the plotting ship itself is ignored.
static func occupied_hexes(hexes: Array, ships: Array, active_ship_id: String) -> Dictionary:
	var by_hex := {}
	for ship in ships:
		if ship.ship_id != active_ship_id:
			by_hex[ship.hex_position] = ship.ship_name
	var result := {}
	for hex in hexes:
		if by_hex.has(hex):
			result[hex] = by_hex[hex]
	return result


static func collision_text(ship_name: String) -> String:
	return "Collision risk: %s is here" % ship_name
