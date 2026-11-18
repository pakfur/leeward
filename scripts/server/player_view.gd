class_name PlayerView
extends RefCounted
## PlayerView - limited information (Close Action 14.C): what one player may see of the ships and
## of a turn's events. Pure queries: nothing here changes the game state or the logs.
##
## With limited information on (the default; a scenario's "tournament": true turns it off, 14.C.3)
## a player sees everything about the ships they command and, of every other ship, enemy or
## friendly (14.C.1 "any other player"), only the number of rigging, hull and crew sections lost
## (and whether the marine section is one) in place of the box counts. Guns, critical hits, fires,
## repairs and the rest stay visible (14.C.1d, 14.C.2).
##
## Anchor preparations are hidden the same way (a captain cannot see another ship's ground tackle
## being got ready): anchor_ready, springs_ready and the preparation crew tasks (AnchorRules.PREP_CODES)
## of a ship the reader does not command. The anchor itself (anchor, anchorings_used, cable_cut_turn)
## stays public, as does a CREW_TASK event for any other code. A tow prepared (tow_prepared and the
## PT task and its events) is hidden from every non-commander, teammates too; the tow itself
## (towing_id, towed_by) is public.
##
## Signals and talks are hidden whatever the scenario: a SIGNAL event goes to the sending player's
## side only (by data.from_player, not the event's side stamp: the sending ship may be taken before
## delivery), a TALK event to the two players in that talk.

const Type := PhaseEvents.Type

## The box-count fields of each event type, as "<role>:<path>": role is the ship the field
## describes ("ship_id" or "target_id" of the event, or the name of a data key holding a ship id,
## e.g. "captor_id"), path a data key, dotted for a nested one.
## A field is hidden when the reader does not command that ship. DAMAGE alone gets a replacement
## ({sections_lost, marine_section_lost}, from its sections_emptied); the other types' losses also
## appear as DAMAGE events, so their fields are dropped with nothing in their place.
const BOX_FIELDS := {
	# The gunfire result on the target. BGN, modifiers, MGN, d6 and FGN stay (14.C.1d).
	Type.FIRE: ["target_id:rigging", "target_id:hull", "target_id:crew"],
	# The damaged ship's boxes lost, and what they could be counted from (one d6 per crew box,
	# BCF lost, the emptied section indices). bcf_needed is the enemy's table result: kept.
	Type.DAMAGE: ["ship_id:rigging", "ship_id:hull", "ship_id:crew", "ship_id:sailors_lost",
		"ship_id:marines_lost", "ship_id:crew_rolls", "ship_id:bcf_lost", "ship_id:sections_emptied"],
	# The firer's marine boxes, and the crew boxes the target loses. The column stays, as the
	# BGN does for gunfire (14.C.1d), so the target can check the shot.
	Type.MARINE_FIRE: ["ship_id:boxes", "target_id:crew"],
	# Each side's boxes in the fight, its TBCF (a sum of boxes), boxes lost and the original crew
	# below. Rolls, DRMs, odds, percentages and the BCF each side inflicts stay.
	Type.BOARDING_ROUND: [
		"ship_id:attacker.sailors", "ship_id:attacker.marines", "ship_id:attacker.tbcf",
		"ship_id:attacker.lost_sailors", "ship_id:attacker.lost_marines", "ship_id:attacker.below",
		"target_id:defender.sailors", "target_id:defender.marines", "target_id:defender.tbcf",
		"target_id:defender.lost_sailors", "target_id:defender.lost_marines", "target_id:defender.below"],
	# The outcome: rolls, morale ratings and MCs, no box counts.
	Type.BOARDING_RESULT: [],
	# Hits the blast does to the target (ship_id is the exploding ship).
	Type.BLAST: ["target_id:rigging", "target_id:hull", "target_id:crew"],
	# ship_id is the prize, target_id the captor: the boxes the captor sends, and the prize's new crew.
	Type.PRIZE_CREW: ["target_id:sailors", "target_id:marines", "ship_id:crew_count", "ship_id:marine_count"],
	# Which defending sections face which attacker: section indices, no box counts.
	Type.DEFENCE_SPLIT: [],
	# ship_id is the retaken ship: her crew below and the prize crew she held; the prisoners are
	# the captor's boxes (the boarding ship, target_id, may be another).
	Type.RECAPTURED: ["ship_id:original_boxes", "ship_id:prize_boxes", "captor_id:prisoners"],
	# ship_id is the captor, target_id the prize: the boxes of her original crew below.
	Type.REORGANIZING_ABORTED: ["target_id:original_crew"],
}

## ShipState.serialize keys replaced for a ship the reader does not command.
const SHIP_BOX_KEYS: Array[String] = ["rigging_current_hp", "hull_current_hp", "crew_count", "marine_count"]
## ShipState.serialize keys dropped for a ship the reader does not command: the boxes sent away as
## a prize crew, and her plan (no captain sees another ship's plot; ruling 2026-11-17).
const SHIP_HIDDEN_KEYS: Array[String] = ["detached_boxes", "plotted_actions", "pending_turn",
	"anchor_ready", "springs_ready", "tow_prepared"]

var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## A preparation task a captain cannot see on another ship: an anchor (PBA, PSA, PBS, PSS) or a tow (PT).
static func _is_prep_code(code: String) -> bool:
	return AnchorRules.PREP_CODES.has(code) or code == "PT"


## Limited information is on unless the scenario is a tournament game (14.C.3).
func limited() -> bool:
	return not bool(game_state.active_scenario.get("tournament", false))


## The ship as `player_id` may see it: the full ShipState.serialize() for a ship they command (or
## with limited information off), else the same with the box counts replaced by
## rigging_sections_lost, hull_sections_lost, crew_sections_lost (sailor sections) and
## marine_section_lost, a prize's crew below (prize.original_crew) given the same way, and
## detached_boxes, plotted_actions and pending_turn dropped (and standing_order and
## escape_declared, for a reader of another side). {} for an unknown ship.
func ship_for(player_id: int, ship_id: String) -> Dictionary:
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null:
		return {}
	var data: Dictionary = ship.serialize()
	if not limited() or game_state.commands(player_id, ship_id):
		return data
	for key in SHIP_BOX_KEYS + SHIP_HIDDEN_KEYS:
		data.erase(key)
	# A signalled order is the side's secret (11.A.4): only players of the ship's side may see it.
	# So is a declared escape: the enemy learns of it at the end of the turn (V.D.2, ESCAPE_DECLARED).
	var reader_side: int = game_state.side_of_player(player_id)
	if reader_side < 0 or reader_side != ship.side:
		data.erase("standing_order")
		data.erase("escape_declared")
	var type: Ship = ship.ship
	data["rigging_sections_lost"] = _lost(ship.rigging_current_hp, type.rigging_hp if type else [])
	data["hull_sections_lost"] = _lost(ship.hull_current_hp, type.hull_hp if type else [])
	data["crew_sections_lost"] = _lost(ship.crew_count, type.crew_count if type else [])
	data["marine_section_lost"] = ship.marine_count <= 0 and (type == null or type.marine_count > 0)
	var visible_tasks: Array = []
	for task in data.get("crew_tasks", []):
		if not _is_prep_code(str(task.get("code", ""))):
			visible_tasks.append(task)
	data["crew_tasks"] = visible_tasks
	var prize: Dictionary = data.get("prize", {})
	if prize.has("original_crew"):
		var below: Dictionary = prize["original_crew"]
		below["crew_sections_lost"] = _lost(below.get("crew_count", []), type.crew_count if type else [])
		below["marine_section_lost"] = int(below.get("marine_count", 0)) <= 0 and (type == null or type.marine_count > 0)
		below.erase("crew_count")
		below.erase("marine_count")
	return data


## Every ship (on the map or not) as `player_id` may see it, by ship id.
func ships_for(player_id: int) -> Array[Dictionary]:
	var ids: Array = game_state.ships.keys()
	ids.sort()
	var out: Array[Dictionary] = []
	for id in ids:
		out.append(ship_for(player_id, str(id)))
	return out


## Turn `turn`'s events (the finished log, or the current one) as PhaseEvent.to_dict()s that
## `player_id` may see: SIGNAL only for the sender's side, TALK only for the talkers, and box
## fields (BOX_FIELDS) of ships the reader does not command hidden while limited() is on.
func events_for(player_id: int, turn: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var events_log: PhaseEvents.PhaseLog = _log_of(turn)
	if events_log == null:
		return out
	var limit := limited()
	for ev in events_log.events:
		if ev.type == Type.SIGNAL and not _same_side(player_id, int(ev.data.get("from_player", -1))):
			continue
		if ev.type == Type.TALK and not _in_talk(player_id, str(ev.data.get("talk_id", ""))):
			continue
		if limit and ev.type == Type.CREW_TASK and _is_prep_code(str(ev.data.get("code", ""))) \
				and not game_state.commands(player_id, ev.ship_id):
			continue
		# A lapsed tow order is the tower's plot (no roll was made): hidden like her preparation.
		if limit and ev.type == Type.TOW_BEGUN and ev.data.has("lapsed") \
				and not game_state.commands(player_id, ev.ship_id):
			continue
		var d: Dictionary = ev.to_dict()
		if limit:
			_hide_boxes(player_id, ev, d)
		out.append(d)
	return out


func _log_of(turn: int) -> PhaseEvents.PhaseLog:
	if game_state.turn_logs.has(turn):
		return game_state.turn_logs[turn]
	var current: PhaseEvents.PhaseLog = game_state.turn_log
	return current if current != null and current.turn == turn else null


func _same_side(player_id: int, other_id: int) -> bool:
	var side: int = game_state.side_of_player(player_id)
	return side >= 0 and side == game_state.side_of_player(other_id)


func _in_talk(player_id: int, talk_id: String) -> bool:
	for t in game_state.talks:
		if str(t.get("id", "")) == talk_id:
			return int(t.get("first_player", -1)) == player_id or int(t.get("second_player", -1)) == player_id
	return false


## Removes from `d` (an event dict) the box fields of ships `player_id` does not command.
func _hide_boxes(player_id: int, ev: PhaseEvents.PhaseEvent, d: Dictionary) -> void:
	var fields: Array = BOX_FIELDS.get(ev.type, [])
	if fields.is_empty():
		return
	var data: Dictionary = d["data"]
	var hidden := false
	for spec in fields:
		var parts: PackedStringArray = str(spec).split(":", true, 1)
		var ship_id := _role_ship(ev, parts[0])
		if ship_id == "" or game_state.commands(player_id, ship_id):
			continue
		_erase_path(data, parts[1])
		hidden = true
	if hidden and ev.type == Type.DAMAGE:
		var emptied: Dictionary = ev.data.get("sections_emptied", {})
		var n := 0
		for kind in ["rigging", "hull", "crew"]:
			n += (emptied.get(kind, []) as Array).size()
		data["sections_lost"] = n
		data["marine_section_lost"] = (emptied.get("crew", []) as Array).has(ShipState.MARINES)


## The ship id a BOX_FIELDS role names on `ev`.
static func _role_ship(ev: PhaseEvents.PhaseEvent, role: String) -> String:
	match role:
		"ship_id":
			return ev.ship_id
		"target_id":
			return ev.target_id
	return str(ev.data.get(role, ""))


static func _erase_path(data: Dictionary, path: String) -> void:
	var keys := path.split(".")
	var at: Variant = data
	for i in keys.size() - 1:
		if not (at is Dictionary) or not (at as Dictionary).has(keys[i]):
			return
		at = at[keys[i]]
	if at is Dictionary:
		(at as Dictionary).erase(keys[keys.size() - 1])


## Sections with no boxes left among those the ship type has (a section with 0 boxes in the
## ship's definition is never counted).
static func _lost(current: Array, maximum: Array) -> int:
	var lost := 0
	for i in current.size():
		var section_max: int = int(maximum[i]) if i < maximum.size() else 1
		if section_max > 0 and int(current[i]) <= 0:
			lost += 1
	return lost
