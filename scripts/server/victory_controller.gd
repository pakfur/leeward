class_name VictoryController
extends RefCounted
## VictoryController - Close Action 1997 victory points (section 12.1).
## A side scores a fraction of each enemy ship's point value: all of it once the ship has
## struck, been destroyed (hull #12) or been captured (VI.B.2-3), otherwise a share for each rigging, hull and crew section
## that is completely destroyed. The game ends when a side has no ship left in play (every ship
## struck or destroyed), when it has none able to move or fight (2.A.1), or at the scenario's turn limit. Pure queries: nothing here mutates game state.

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
	var value: float = ship.ship.point_value(ship.starting_crew_quality, ship.original_morale_rating())
	if ship.is_out_of_play():
		return value
	var share := 0.0
	for i in range(mini(ship.rigging_current_hp.size(), RIGGING_SHARES.size())):
		if ship.rigging_current_hp[i] <= 0:
			share += RIGGING_SHARES[i]
	for i in range(mini(ship.hull_current_hp.size(), HULL_SHARES.size())):
		if ship.hull_current_hp[i] <= 0:
			share += HULL_SHARES[i]
	# Spec §8 Q4: a section emptied only by detaching a prize crew is not destroyed (the men are
	# alive aboard the prize).
	var crew_share := 0.0
	for i in range(ship.crew_count.size()):
		if ship.crew_count[i] <= 0 and _detached(ship, i) <= 0:
			crew_share += CREW_SECTION_SHARE
	if ship.marine_count <= 0 and _detached(ship, ShipState.MARINES) <= 0:
		crew_share += CREW_SECTION_SHARE
	share += minf(crew_share, CREW_SHARE_CAP)
	return value * share


func check(turn: int) -> Dictionary:
	## {} while the game continues; otherwise
	## {"winner": player id or -1 for a draw, "reason", "points": {0: float, 1: float}, "turn"}.
	var reason := ""
	if _is_defeated(0) or _is_defeated(1):
		reason = "all struck"
	elif _is_unable(0) or _is_unable(1):
		reason = "no ship able to move or fight"
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


static func _detached(ship: ShipState, section: int) -> int:
	return ship.detached_boxes[section] if section < ship.detached_boxes.size() else 0


func _is_defeated(player_id: int) -> bool:
	## A side with no ships at all counts as defeated. Ships it controls only: a prize (CAPTURED)
	## is out of play, so a side holding only prizes is defeated (boarding spec §2.6).
	for ship: ShipState in game_state.get_side_ships(player_id):
		if not ship.is_out_of_play():
			return false
	return true


func can_move_or_fight(ship: ShipState) -> bool:
	## 2.A.1, read as "move OR fight" (user decision 2026-11-16): in play and either still rigged
	## or with a gun factor left on some side. Fouled, grappled and in-irons ships count as able.
	if ship.is_out_of_play():
		return false
	if ship.rigging_level() > 0:
		return true
	var factors: int = 0
	for gun_type: String in ["lg", "mg", "cr"]:
		factors += int(ship.ship.gun_factors.get(gun_type, 0))
	for side in range(2):
		if factors - ship.guns_dismounted[side] > 0:
			return true
	return false


func _is_unable(player_id: int) -> bool:
	for ship: ShipState in game_state.get_side_ships(player_id):
		if can_move_or_fight(ship):
			return false
	return true


func _points_scored(player_id: int) -> float:
	## The enemy's ships by original owner: a ship it lost to capture scores 100 % like a struck one
	## (VI.B.2-3), wherever it now is.
	var total := 0.0
	for ship: ShipState in game_state.get_original_side_ships(1 - player_id):
		total += points_lost(ship)
	return total
