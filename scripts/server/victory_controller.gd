class_name VictoryController
extends RefCounted
## VictoryController - Close Action 1997 victory points (section 12.1).
## A side scores a fraction of each enemy ship's point value: all of it once the ship has
## struck, otherwise a share for each rigging, hull and crew section that is completely
## destroyed. The game ends when a side has no ship left unstruck, or at the scenario's
## turn limit. Pure queries: nothing here mutates game state.

## Share of a ship's value lost per destroyed section (rigging 1-3, rigging 4, hull 1-3, hull 4)
const RIGGING_SHARES: Array[float] = [0.05, 0.05, 0.05, 0.10]
const HULL_SHARES: Array[float] = [0.10, 0.10, 0.10, 0.10]
const CREW_SECTION_SHARE: float = 0.10
const CREW_SHARE_CAP: float = 0.40

var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


func points_lost(ship: ShipState) -> float:
	## Points the enemy scores for this ship.
	var value: float = ship.ship.point_value(ship.starting_crew_quality, ship.morale_rating)
	if ship.is_struck():
		return value
	var share := 0.0
	for i in range(mini(ship.rigging_current_hp.size(), RIGGING_SHARES.size())):
		if ship.rigging_current_hp[i] <= 0:
			share += RIGGING_SHARES[i]
	for i in range(mini(ship.hull_current_hp.size(), HULL_SHARES.size())):
		if ship.hull_current_hp[i] <= 0:
			share += HULL_SHARES[i]
	var crew_share := 0.0
	for boxes in ship.crew_count:
		if boxes <= 0:
			crew_share += CREW_SECTION_SHARE
	if ship.marine_count <= 0:
		crew_share += CREW_SECTION_SHARE
	share += minf(crew_share, CREW_SHARE_CAP)
	return value * share


func check(turn: int) -> Dictionary:
	## {} while the game continues; otherwise
	## {"winner": player id or -1 for a draw, "reason", "points": {0: float, 1: float}, "turn"}.
	var reason := ""
	if _is_defeated(0) or _is_defeated(1):
		reason = "all struck"
	else:
		var limit: int = int(game_state.active_scenario.get("turn_limit", 0))
		if limit > 0 and turn >= limit:
			reason = "turn limit"
	if reason == "":
		return {}

	var points := {0: _points_scored(0), 1: _points_scored(1)}
	var winner := -1
	if points[0] > points[1]:
		winner = 0
	elif points[1] > points[0]:
		winner = 1
	return {"winner": winner, "reason": reason, "points": points, "turn": turn}


func _is_defeated(player_id: int) -> bool:
	## A side with no ships at all counts as defeated.
	for ship: ShipState in game_state.get_player_ships(player_id):
		if not ship.is_struck():
			return false
	return true


func _points_scored(player_id: int) -> float:
	var total := 0.0
	for ship: ShipState in game_state.get_player_ships(1 - player_id):
		total += points_lost(ship)
	return total
