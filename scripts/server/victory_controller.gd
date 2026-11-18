class_name VictoryController
extends RefCounted
## VictoryController - Close Action 1997 victory points (section 12.1, Scenario Book VI).
## Sides are the distinct original sides of the ships, any number of them. A side scores, for every
## ship whose original side is another side, the whole value once the ship is lost (struck, destroyed
## (hull #12) or captured, VI.B.2-3, or aground while the scenario's `aground_counts_lost`, default
## true), otherwise a share for each rigging, hull and crew section completely destroyed (an escaped
## ship included, VI.B.6); plus the scenario's escape share of each of its own ships that escaped
## (VI.B.6). A reinforcement still awaiting arrival yields nothing and keeps its side alive.
## The game ends by agreement, when a side has no ship it controls in play and not lost nor waiting
## (VI.A.1c: every ship struck, destroyed, captured, escaped or aground), when it has none able to move
## or fight (2.A.1), or at the scenario's turn limit. Pure queries: nothing here mutates game state.

## Share of a ship's value lost per destroyed section (rigging 1-3, rigging 4, hull 1-3, hull 4)
const RIGGING_SHARES: Array[float] = [0.05, 0.05, 0.05, 0.10]
const HULL_SHARES: Array[float] = [0.10, 0.10, 0.10, 0.10]
const CREW_SECTION_SHARE: float = 0.10
const CREW_SHARE_CAP: float = 0.40

var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


func _value(ship: ShipState) -> float:
	return ship.ship.point_value(ship.starting_crew_quality, ship.original_morale_rating())


func is_lost(ship: ShipState) -> bool:
	## Struck, destroyed or captured (VI.B.2-3), or aground while `aground_counts_lost` (default
	## true). An escaped ship and a waiting reinforcement are not lost.
	if ship.is_struck() or ship.is_destroyed() or ship.is_captured():
		return true
	return ship.is_aground() and bool(game_state.active_scenario.get("aground_counts_lost", true))


func escape_points(ship: ShipState) -> float:
	## VI.B.6: the scenario's escape share of an escaped ship's value, scored by its own original side.
	if not ship.is_escaped():
		return 0.0
	return MapRules.share(game_state.active_scenario, ship.original_side) * _value(ship)


func points_lost(ship: ShipState) -> float:
	## Points the other sides score for this ship: none while it awaits arrival, all of it when lost,
	## else the destroyed sections' shares (an escaped ship still yields them, VI.B.6).
	if ship.is_awaiting_arrival():
		return 0.0
	var value: float = _value(ship)
	if is_lost(ship):
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
	## {"winner": side or -1 for a tie at the top, "reason", "points": {side: float} for every side,
	## "turn"}.
	var sides := _sides()
	var reason := ""
	if _all_agree():
		reason = "agreement"
	elif sides.any(_is_defeated):
		reason = "all struck"
	elif sides.any(_is_unable):
		reason = "no ship able to move or fight"
	else:
		var limit: int = int(game_state.active_scenario.get("turn_limit", 0))
		if limit > 0 and turn >= limit:
			reason = "turn limit"
	if reason == "":
		return {}

	var points := {}
	var best := -INF
	var winner := -1
	for side in sides:
		points[side] = _points_scored(side)
		if points[side] > best:
			best = points[side]
			winner = side
		elif points[side] == best:
			winner = -1
	return {"winner": winner, "reason": reason, "points": points, "turn": turn}


func _sides() -> Array[int]:
	## The distinct original sides of every ship, ascending; [0, 1] when there are no ships. The sides
	## GameState.ships_by_side lists are included, so a side left with no ship at all still counts
	## (and is defeated).
	var sides: Array[int] = []
	for side in game_state.ships_by_side.keys():
		if not sides.has(int(side)):
			sides.append(int(side))
	for ship: ShipState in game_state.ships.values():
		if not sides.has(ship.original_side):
			sides.append(ship.original_side)
	if sides.is_empty():
		sides = [0, 1]
	sides.sort()
	return sides


func _all_agree() -> bool:
	## 2.A.1: every side present has offered. A side with no human never does (offers come only
	## from a side's senior human).
	var sides: Array[int] = []
	for id in game_state.players:
		var side: int = game_state.players[id].side
		if not sides.has(side):
			sides.append(side)
	if sides.is_empty():
		return false
	for side in sides:
		if not game_state.end_offers.get(side, false):
			return false
	return true


static func _detached(ship: ShipState, section: int) -> int:
	return ship.detached_boxes[section] if section < ship.detached_boxes.size() else 0


func _is_defeated(side: int) -> bool:
	## VI.A.1c: no ship the side controls is in play and not lost, or awaiting arrival. A side with no
	## ships at all counts as defeated. Escaped ships do not keep it alive, and a side holding only
	## prizes (out of play) is defeated (boarding spec §2.6).
	for ship: ShipState in game_state.get_side_ships(side):
		if ship.is_awaiting_arrival() or (not ship.is_out_of_play() and not is_lost(ship)):
			return false
	return true


func can_move_or_fight(ship: ShipState) -> bool:
	## 2.A.1, read as "move OR fight" (user decision 2026-11-16): in play and either still rigged
	## or with a gun factor left on some side. Fouled, grappled and in-irons ships count as able; a
	## reinforcement awaiting arrival does too, an escaped or aground ship does not.
	if ship.is_awaiting_arrival():
		return true
	if ship.is_out_of_play() or ship.is_aground():
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


func _is_unable(side: int) -> bool:
	for ship: ShipState in game_state.get_side_ships(side):
		if can_move_or_fight(ship):
			return false
	return true


func _points_scored(side: int) -> float:
	## Every other side's ships by original owner: a ship it lost to capture scores 100 % like a
	## struck one (VI.B.2-3), wherever it now is; plus the side's own escape points (VI.B.6).
	var total := 0.0
	var ids: Array = game_state.ships.keys()
	ids.sort()
	for ship_id in ids:
		var ship: ShipState = game_state.ships[ship_id]
		if ship.original_side == side:
			total += escape_points(ship)
		else:
			total += points_lost(ship)
	return total
