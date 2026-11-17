class_name BlockedWind
extends RefCounted
## BlockedWind - wind shadow (Close Action 5.G), as pure static functions (no state, no dice).
## - 5.G.2: a ship's wind is blocked when the hexes directly to windward of (and adjacent to) its
##   hexes are all held by other ships at FS or above (not furled, not dismasted). At WF=C or B that
##   is two hexes; at WF=R one (the bow's windward hex is the ship's own stern, and a ship never
##   blocks its own wind).
## - 5.G.3: blocked wind costs 1 MA, applied after every other change, and never brings MA to 0.
## The wind comes from `wind_direction`, so a hex's windward neighbour is in that direction.
## Positions are whatever the caller passes: ShipStateController uses where the ships are; the
## movement validator uses the plotting ship's plotted position against the others' positions.


## True when a ship with this bow and facing has its wind blocked by `ships` (ShipState values;
## `exclude_id`, the ship itself, and ships removed from the map (8.G.1f) are skipped).
static func is_blocked(bow: Vector2i, facing: int, wind_direction: int, ships: Array, exclude_id: String) -> bool:
	var own: Array[Vector2i] = [bow, HexGrid.stern_of(bow, facing)]
	var windward: Array[Vector2i] = []
	for h in own:
		var upwind: Vector2i = h + HexGrid.DIRECTIONS[wind_direction % 6]
		if not upwind in own:
			windward.append(upwind)
	if windward.is_empty():
		return false
	var blockers := {}
	for s in ships:
		var ship_state := s as ShipState
		if ship_state == null or ship_state.ship_id == exclude_id or not ship_state.is_on_map() \
				or not blocks_wind(ship_state):
			continue
		for h in ship_state.occupied_hexes():
			blockers[h] = true
	for h in windward:
		if not blockers.has(h):
			return false
	return true


## A ship at FS or above with rigging left blocks wind; a furled or dismasted one does not (5.G.2).
static func blocks_wind(ship_state: ShipState) -> bool:
	return ship_state.sail_state.to_upper() in ["FS", "MS", "PS"] and not ship_state.is_dismasted()


## The MA after blocked wind (5.G.3): one less, but never below 1 (and 0 stays 0).
static func apply(ma: int, blocked: bool) -> int:
	return ma - 1 if blocked and ma > 1 else ma
