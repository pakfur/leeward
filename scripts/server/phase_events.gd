class_name PhaseEvents
extends RefCounted
## PhaseEvents - Typed per-turn event log.
##
## Server controllers append events (die rolls, modifiers, outcomes) to
## GameState.turn_log; the UI renders them with PhaseEvent.to_text so every
## roll is traceable by the player.

enum Type {
	FIRE, DAMAGE, GUNS_DISMOUNTED, MORALE_NOTED, MORALE_CHECK, STRIKE,
	DRIFT, FOULED, UNFOUL, SAIL_CHANGE, VICTORY, HOLD_FIRE,
	COLLISION, STOPPED_SHORT, IN_IRONS, WIND,
	TURN_UNDONE,  # a plotted turn rolled back or lost to a stern contest; the ship sailed on ahead instead
	BEAR_OFF,  # a potential collision (6.D): {choice: port/starboard/collide, success, roll, needed, drm}
	CRITICAL_ROLL,  # 7.D.11 after a natural 6: {d6, ch_mod, ch_number, hit}
	CRITICAL_HIT,  # a critical hit or Rigging/Hull Check result (see CriticalHitController)
	CRITICAL_FIXED,  # 8.D.5 fix roll: {result_id, side, roll, modifier, needed, attempt, success}
	CRITICAL_ENDED,  # a lasting critical effect ended without a roll: {result_id, side, reason}
	POOR_MANEUVERING,  # 6.F.3 roll for a plotted turn: {roll, needed, success, outcome}
	FIRE_STARTED,  # a fire breaks out (8.E.1): {fire, fires, cause, mc, result_id | roll, needed | range | from_fire, age}; target_id: its source
	DESTROYED,  # the ship blew up (hull #12) and is out of play: {reason}; target_id: freed fouling partner
	CREW_TASK,  # a crew task other than a sail change: {code, sections, params, state, done, needed, reason}
	FIRE_FOUGHT,  # 8.E.3 firefighting roll: {fire, number, sections, roll, modifier, needed, attempt, success}
	FIRE_UNFOUGHT,  # 8.E.6: a fire nobody fought this g-t: {fire, number, mc}
	FIRE_SPREAD,  # 8.E.4 spread roll from ship_id to target_id: {roll, needed, spreads}
	EXPLOSION_CHECK,  # 8.E.8 a burning hulk rolls to explode: {roll, needed, explodes}
	BLAST,  # 8.E.10 blast from ship_id on target_id: {range, mgn, d6, fgn, rigging, hull, crew}
	DEBRIS,  # 8.E.11 flaming debris from ship_id on target_id: {range, roll | attached, afire}
	REPAIR,  # 8.F.5 a repair completed: {code, kind: rigging/hull/shrouds, section (0-3, rigging/hull), sections}
	MARINE_FIRE,  # 7.G marine fire from ship_id at target_id: {boxes, column, modifiers, modifier, d6, total, crew}
	GRAPPLE,  # 8.C.2 grappling roll by ship_id at target_id: {roll, modifiers, modifier, total, needed, success, in_irons?}
	UNGRAPPLE,  # 8.C.4 ungrappling roll by ship_id from target_id: {roll, modifiers, modifier, total, needed, attempt, success}
	BOARDERS,  # 10.B.6 ship_id forms (FB) or disbands (BD) boarders, public: {sections, task}
	BOARDERS_AWAY,  # 10.C.1 ship_id's boarders go away onto target_id: {sections, action | joins}
	MARINES_DEFEND,  # 10.C.3 ship_id's marines replotted to FB against boarders from target_id: {cancelled_task, done}
	BOARDING_ROUND,  # 10.D one round, ship_id (attacker) onto target_id: {action, round, attacker: {...}, defender: {...}}
	BOARDING_RESULT,  # 10.D.5 the round's outcome: {action, special, side, d10, mr, mcs, result: fight_on/captured/repulsed/driven_off} (no round fought: result captured (+ reason)/surrendered/attackers_lost/target_gone; 10.F: shared_capture + with, captor_id)
	SHIP_CAPTURED,  # 10.E.2 ship_id is taken by target_id: {captor_id, struck_before, action, outcome}
	PRIZE_CREW,  # 10.G.7 a prize crew from target_id goes aboard ship_id: {sailors, marines, cq, mr, crew_count, marine_count}
	RECAPTURED,  # 10.H.4 ship_id is back with its own side: {cause: "rose"|"boarded", original_boxes, prize_boxes, cq, mr} (+ target_id: the boarding ship)
	REORGANIZING_ABORTED,  # 10.G.5 ship_id's boarders reorganizing aboard prize target_id turn to defend her: {sections}
	DEFENCE_SPLIT,  # 10.F.2 ship_id, boarded by several ships, shares out its defenders: {split: [{attacker_id, action, sections}]}
	BEAR_OFF_ORDER,  # 6.D.3c potential collisions on one segment ordered by d10: {order: [{ship_id, rolls}]}; ship_id: the first
	SIGNAL,  # 11.A a flag signal delivered, ship_id = the sending ship: {from_player, address: {kind, name}, words}
	TALK,  # 11.B.3 a word passed between sterns-adjacent ships of one side, ship_id = the speaking ship: {talk_id, from_player, words}
	END_OFFER,  # 2.A.1 a side offers or withdraws an offer to end the game, ship_id empty: {side, offer: bool}
	AGROUND,  # a ship runs or drifts aground: {cause: movement/drift, terrain: land/shallow, hex, depth, draft}
	LEAD_CAST,  # a ship casts the lead: {hex, depth, draft, outcome, side}
	ESCAPE_DECLARED,  # a ship declares it is trying to escape
	ESCAPED,  # a ship escapes: {how: edge|distance|speed, edge | range (-1: no enemy on the map)}
	ARRIVED,  # a reinforcement enters: {hex, facing, sail_state, speed}
	ARRIVAL_DELAYED,  # a reinforcement cannot enter this turn; target_id: the ship in the way
}

## Crew task names for the log (crew_tasks.json codes).
const CREW_TASK_NAMES := {
	"T": "work the braces", "RO": "reorganize", "FF": "fight the fire",
	"RR": "repair rigging", "RH": "repair the hull", "RS": "repair the shrouds",
	"FB": "form boarders", "BR": "stand ready to board", "BA": "board", "BD": "disband the boarders",
	"PBA": "prepare the bow anchor", "PSA": "prepare the stern anchor", "PBS": "prepare bow springs",
	"PSS": "prepare stern springs", "A": "anchor", "AX": "cut the cable", "VO": "veer out",
	"VI": "veer in", "HS": "handle the springs",
}

## The same tasks as gerunds, for "finishes …" / "stops …" lines.
const CREW_TASK_GERUNDS := {
	"T": "working the braces", "RO": "reorganizing", "FF": "fighting the fire",
	"RR": "repairing rigging", "RH": "repairing the hull", "RS": "repairing the shrouds",
	"FB": "forming boarders", "BR": "standing ready to board", "BA": "boarding", "BD": "disbanding the boarders",
	"PBA": "preparing the bow anchor", "PSA": "preparing the stern anchor", "PBS": "preparing bow springs",
	"PSS": "preparing stern springs", "A": "anchoring", "AX": "cutting the cable", "VO": "veering out",
	"VI": "veering in", "HS": "handling the springs",
}

## Why a crew task ended early, in plain words (reasons not listed are shown as given).
const CREW_TASK_REASONS := {
	"abandoned": "given other orders",
	"crew lost": "the section is lost",
	"crew_disorganized": "crew disorganized",
	"action over": "the boarding action is over",
	"boarding": "the prize is taken",
	"captured": "the ship is captured",
	"retaken": "the ship is retaken",
	"destroyed": "the ship has been destroyed",
	"struck": "the ship has struck",
	"escaped": "the ship has escaped",
}

const MODIFIER_LABELS := {
	"crew_quality": "crew",
	"sections_firing": "sections firing",
	"guns_dismounted": "guns dismounted",
	"rake": "rake",
	"initial_broadside": "initial broadside",
	"two_targets": "two targets",
	"plain_sail": "plain sail",
	"dismantling_shot": "dismantling shot",
	"wind_speed_4": "wind speed 4",
	"dismasted": "dismasted",
	"lower_deck_closed": "Lower deck guns closed",
	"broadside_obscured": "broadside obscured",
	"voluntary_reduction": "Voluntary reduction",
	# Marine Fire DRMs (7.G.4)
	"grappled_or_fouled": "alongside",
	"cq_e_f": "crew",
	"cq_g": "crew",
	"target_boarders": "target's boarders",
	"larger_class": "larger ship",
	# Grappling and ungrappling DRMs (8.C)
	"skill": "crew",
	"fouled": "fouled",
	"marines_unavailable": "marines busy",
	"ws4": "wind speed 4",
	"target_did_not_move": "target did not move",
	"friendly": "friendly ship",
	"better_crew": "better crew",
}

const SIDE_NAMES := ["port", "starboard"]

## The human player's id (single-player: player 0); VICTORY text is written from their side.
const HUMAN_SIDE := 0

const SAIL_NAMES := {
	"FS": "fighting sail", "MS": "maneuvering sail", "PS": "plain sail", "NS": "no sail",
}

const SAIL_CANCEL_REASONS := {
	"not available": "that sail is not available now",
	"no crew": "not enough crew to work the sails",
	"crew lost": "the crew working the sails were lost",
	"struck": "the ship has struck",
	"dismasted": "the ship is dismasted",
	"lines jammed": "the lines are jammed",
	"destroyed": "the ship has been destroyed",
}

const STRIKE_REASONS := {
	"hull destroyed": "hull destroyed",
	"no crew": "no crew left",
	"morale": "the crew's morale broke",
	"waterline": "not enough crew to man the pumps",
}

## Critical-hit result ids (critical_hits_table.json) in plain words.
const CRITICAL_RESULT_NAMES := {
	"mast_may_fall": "mast may fall",
	"signal_halyards_cut": "signal halyards cut",
	"braces_cut": "braces cut",
	"lines_jammed": "lines jammed",
	"broadside_obscured": "broadside obscured",
	"sheets_cut": "sheets cut",
	"leadership_casualties": "leadership casualties",
	"shrouds_severed": "shrouds severed",
	"yard_shot_away": "yard shot away",
	"stays_cut": "stays cut",
	"mast_falls_on_deck": "mast falls on deck",
	"rudder": "rudder hit",
	"wheel_shot_away": "wheel shot away",
	"crew_disorganized": "crew disorganized",
	"hull_structural_damage": "hull structural damage",
	"rigging_damage": "rigging damage",
	"guns_dismounted": "guns dismounted",
	"minor_explosion": "minor explosion",
	"waterline_damage": "waterline damage",
	"afire_major_explosion": "afire, major explosion",
}

const CRITICAL_NOTES := {
	"not_simulated": "not yet simulated",
	"not_implemented": "not yet implemented",
	"sinking_not_simulated": "sinking not yet simulated",
}

## CRITICAL_FIXED: what the crew fixes, per fixable effect id (broadside_obscured adds the side).
const CRITICAL_FIX_OBJECTS := {
	"broadside_obscured": "broadside obscured",
	"braces_cut": "the cut braces",
	"lines_jammed": "the jammed lines",
	"rudder_jammed": "the jammed rudder",
	"signal_halyards_cut": "the cut signal halyards",
}

## CRITICAL_ENDED reasons
const CRITICAL_END_REASONS := {
	"expired": "repaired",
	"dismasted": "cleared (the ship is dismasted)",
}

const VICTORY_REASONS := {
	"all struck": "every ship of one side has struck",
	"turn limit": "turn limit reached",
	"agreement": "ended by agreement",
}

const ORDINALS := ["first", "second", "third", "fourth", "fifth"]


## "The wind veers to west and freshens to 3 (fresh)", or "The wind holds steady". Directions number
## clockwise (0 = E, 1 = SE ...), so clockwise is veering. Used by the log and the minimap forecast.
static func wind_change_text(from_dir: int, to_dir: int, from_speed: int, to_speed: int, speed_name: String) -> String:
	var parts := PackedStringArray()
	if from_dir != to_dir:
		var steps := (to_dir - from_dir + 6) % 6
		var verb := "veers" if steps < 3 else ("backs" if steps > 3 else "shifts")
		parts.append("%s to %s" % [verb, wind_direction_word(to_dir)])
	if from_speed != to_speed:
		var name_lower := speed_name.to_lower()
		parts.append("%s to %d%s" % ["freshens" if to_speed > from_speed else "eases", to_speed,
			" (%s)" % name_lower if name_lower != "" else ""])
	if parts.is_empty():
		return "The wind holds steady"
	return "The wind " + " and ".join(parts)


## Wind directions by index, as EnvironmentState numbers them (0 = E, 1 = SE ... 5 = NE).
const WIND_DIRECTION_WORDS := ["east", "south-east", "south-west", "west", "north-west", "north-east"]


static func wind_direction_word(direction: int) -> String:
	return WIND_DIRECTION_WORDS[direction] if direction >= 0 and direction < WIND_DIRECTION_WORDS.size() else "?"


## Display label for a gunnery modifier id ("initial_broadside" -> "initial broadside").
static func modifier_label(modifier_id: String) -> String:
	return MODIFIER_LABELS.get(modifier_id, modifier_id.replace("_", " "))


## An edge name in words ("W" -> "west"); other boundary names as given.
static func edge_label(edge_name: String) -> String:
	match edge_name:
		"N":
			return "north"
		"E":
			return "east"
		"S":
			return "south"
		"W":
			return "west"
	return edge_name


## "1 turn" / "2 turns"; `many` defaults to `one` + "s".
static func plural(count: int, one: String, many: String = "") -> String:
	return "%d %s" % [count, one if count == 1 else (many if many != "" else one + "s")]


static func times_text(count: int) -> String:
	match count:
		1:
			return "once"
		2:
			return "twice"
	return "%d times" % count


## "S1, marines" for crew section indices (4 = marines).
static func sections_text(sections: Array) -> String:
	var names := PackedStringArray()
	for s in sections:
		names.append("marines" if int(s) == ShipState.MARINES else ShipState.SECTION_NAMES[clampi(int(s), 0, 4)])
	return ", ".join(names)


## "S3", "S3 and S4", "S1, S2 and the marines": crew sections as the subject of a log line.
static func crew_subject(sections: Array) -> String:
	var names := PackedStringArray()
	for s in sections:
		names.append("the marines" if int(s) == ShipState.MARINES else ShipState.SECTION_NAMES[clampi(int(s), 0, 4)])
	if names.is_empty():
		return "the crew"
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## `one` for a single crew section, else `many` ("begins" / "begin").
static func crew_verb(sections: Array, one: String, many: String) -> String:
	return one if sections.size() <= 1 else many


## "fighting sail (FS)" for a sail-state code; unknown codes are shown as given.
static func sail_name(code: String) -> String:
	var key := code.to_upper()
	return "%s (%s)" % [SAIL_NAMES[key], key] if SAIL_NAMES.has(key) else (code if code != "" else "?")


## Plain words for a morale trigger id (hull_1..3, crew_0..3, crew_4, dismasted, raked_dismasted_tN).
static func morale_trigger_text(trigger: String) -> String:
	if trigger == "dismasted":
		return "dismasted"
	if trigger.begins_with("raked_dismasted"):
		return "raked while dismasted"
	if trigger == "crew_4":
		return "all marines lost"
	if trigger.begins_with("crit_"):
		return "critical hit"
	if trigger.begins_with("fire_"):
		return "fire breaks out"
	if trigger.begins_with("boarding_"):
		return "boarders repulsed"
	if trigger.begins_with("unfought_"):
		return "a fire with no one to fight it"
	if trigger.begins_with("hull_") and trigger.substr(5).is_valid_int():
		return "%s hull section lost" % _ordinal(int(trigger.substr(5)) - 1)
	if trigger.begins_with("crew_") and trigger.substr(5).is_valid_int():
		return "%s crew section lost" % _ordinal(int(trigger.substr(5)))
	return "heavy damage"


static func _ordinal(index: int) -> String:
	return ORDINALS[index] if index >= 0 and index < ORDINALS.size() else "a"


## A single logged event. `data` is type-specific (rolls, modifiers, amounts).
class PhaseEvent extends RefCounted:
	var type: Type = Type.FIRE
	var phase: int = 0  # TurnPhaseController.GamePhase value
	var ship_id: String = ""
	var target_id: String = ""
	var data: Dictionary = {}
	## Ship id -> the player controlling it when the event was logged (PhaseLog stamps it, server
	## side), so the log can label sides as they were: a ship captured later keeps her old side here.
	var sides: Dictionary = {}

	func _init(p_type: Type = Type.FIRE, p_phase: int = 0, p_ship_id: String = "",
			p_data: Dictionary = {}, p_target_id: String = "") -> void:
		type = p_type
		phase = p_phase
		ship_id = p_ship_id
		target_id = p_target_id
		data = p_data

	func to_dict() -> Dictionary:
		return {
			"type": type,
			"phase": phase,
			"ship_id": ship_id,
			"target_id": target_id,
			"data": data.duplicate(true),
			"sides": sides.duplicate(),
		}

	## Every ship id the event's text names: ship_id, target_id and the ids kept in its data.
	func ship_ids() -> PackedStringArray:
		var ids := PackedStringArray()
		for id in [ship_id, target_id, str(data.get("captor_id", ""))]:
			if id != "" and not ids.has(id):
				ids.append(id)
		for e in data.get("order", []):
			var id := str((e as Dictionary).get("ship_id", "")) if e is Dictionary else ""
			if id != "" and not ids.has(id):
				ids.append(id)
		for e in data.get("split", []):
			var id := str((e as Dictionary).get("attacker_id", "")) if e is Dictionary else ""
			if id != "" and not ids.has(id):
				ids.append(id)
		return ids

	## The player that controlled `id` when the event was logged, or `fallback` if not recorded.
	func player_when_logged(id: String, fallback: int) -> int:
		return int(sides.get(id, fallback))

	## One readable line in plain English, numbers kept. Missing data keys are skipped, never
	## an error; raw ids, roll arrays and zero amounts are never shown.
	func to_text(ship_names: Dictionary) -> String:
		var who := _name(ship_names, ship_id)
		var other := _name(ship_names, target_id)
		match type:
			Type.FIRE:
				return _fire_text(who, other)
			Type.HOLD_FIRE:
				return "%s holds fire." % who
			Type.DAMAGE:
				return _damage_text(who)
			Type.GUNS_DISMOUNTED:
				var guns := int(data.get("amount", 0))
				var side_idx := int(data.get("side", -1))
				var where := "each broadside"
				if side_idx >= 0 and side_idx < PhaseEvents.SIDE_NAMES.size():
					where = "the %s broadside" % PhaseEvents.SIDE_NAMES[side_idx]
				return "%s has %s dismounted on %s" % [
					who, PhaseEvents.plural(guns, "gun") if data.has("amount") else "guns", where]
			Type.CRITICAL_ROLL:
				return _critical_roll_text(who)
			Type.CRITICAL_HIT:
				return _critical_hit_text(who)
			Type.CRITICAL_FIXED:
				return _critical_fixed_text(who)
			Type.CRITICAL_ENDED:
				var id := str(data.get("result_id", ""))
				var reason := str(data.get("reason", "expired"))
				return "%s: %s %s" % [who, PhaseEvents.CRITICAL_RESULT_NAMES.get(id, id.replace("_", " ")),
					PhaseEvents.CRITICAL_END_REASONS.get(reason, "ended (%s)" % reason)]
			Type.MORALE_NOTED:
				var times := "" if int(data.get("count", 1)) <= 1 else " %s" % PhaseEvents.times_text(int(data["count"]))
				return "%s must check morale%s (%s)" % [who, times,
					PhaseEvents.morale_trigger_text(str(data.get("trigger", "")))]
			Type.MORALE_CHECK:
				return _morale_check_text(who)
			Type.FIRE_STARTED:
				return _fire_started_text(who, other)
			Type.FIRE_FOUGHT:
				return _fire_fought_text(who)
			Type.FIRE_UNFOUGHT:
				return "%s has no crew to fight fire %d" % [who, int(data.get("number", 1))] \
					+ (": morale check" if data.get("mc", false) else "")
			Type.FIRE_SPREAD:
				var roll := int(data.get("roll", 0))
				var needed := int(data.get("needed", 0))
				if data.get("spreads", false):
					return "The fire aboard %s spreads to %s (d10 %d ≤ %d)" % [who, other, roll, needed]
				return "The fire aboard %s does not spread to %s (d10 %d > %d)" % [who, other, roll, needed]
			Type.EXPLOSION_CHECK:
				var verdict := "she explodes!" if data.get("explodes", false) else "she burns on"
				return "Burning hulk %s: explosion roll %s, needs %s or less — %s" % [
					who, _val("roll"), _val("needed"), verdict]
			Type.BLAST:
				var hits := _hits_text(["rigging", "hull", "crew"], {}, "no damage")
				return "The blast from %s strikes %s (range %s: %s + %s = %s): %s" % [
					who, other, _val("range"), _val("mgn"), _val("d6"), _val("fgn"), hits]
			Type.DEBRIS:
				if data.get("attached", false):
					return "Flaming debris from %s falls on %s, fouled alongside: afire" % [who, other]
				var roll := int(data.get("roll", 0))
				var r := int(data.get("range", 0))
				if data.get("afire", false):
					return "Flaming debris from %s sets %s afire (d6 %d, range %d)" % [who, other, roll, r]
				return "Flaming debris from %s falls clear of %s (d6 %d, range %d)" % [who, other, roll, r]
			Type.REPAIR:
				return _repair_text(who)
			Type.MARINE_FIRE:
				return _marine_fire_text(who, other)
			Type.GRAPPLE:
				return _grapple_text(who, other)
			Type.UNGRAPPLE:
				return _ungrapple_text(who, other)
			Type.BOARDERS:
				var secs := PhaseEvents.sections_text(data.get("sections", []))
				if str(data.get("task", "")) == "BD":
					return "%s stands down her boarders (%s)" % [who, secs]
				return "%s forms boarders (%s)" % [who, secs]
			Type.BOARDERS_AWAY:
				if data.get("joins", false):
					return "%s sends more boarders (%s) into the fight on %s" % [who,
						PhaseEvents.sections_text(data.get("sections", [])), other]
				return "%s: boarders away! (%s) onto %s" % [who, PhaseEvents.sections_text(data.get("sections", [])), other]
			Type.MARINES_DEFEND:
				var old := str(data.get("cancelled_task", ""))
				if old == "" or old == "BD":
					return "%s's marines turn out to repel boarders" % who
				return "%s's marines drop their work (%s) to repel boarders" % [who,
					PhaseEvents.CREW_TASK_NAMES.get(old, old.to_lower())]
			Type.BOARDING_ROUND:
				return _boarding_round_text(who, other)
			Type.BOARDING_RESULT:
				return _boarding_result_text(who, other, ship_names)
			Type.SHIP_CAPTURED:
				match str(data.get("outcome", "")):
					"overwhelmed":
						return "%s is overwhelmed by a sixth boarding ship and taken by %s (10.F.2)" % [who, other]
					"undefended":
						return "%s is taken by %s: no one is left to defend her (10.E.2b)" % [who, other]
				# A ship that struck in the fight already has her own line (BOARDING_RESULT, 10.E.2c).
				var struck: bool = data.get("struck_before", false) and str(data.get("outcome", "")) != "struck_in_action"
				return "%s is taken by %s%s" % [who, other, " (she had struck)" if struck else ""]
			Type.DEFENCE_SPLIT:
				var parts := PackedStringArray()
				for e in data.get("split", []):
					var secs: Array = e.get("sections", [])
					parts.append("%s against %s" % [PhaseEvents.sections_text(secs) if not secs.is_empty() else "no one",
						_name(ship_names, str(e.get("attacker_id", "")))])
				return "%s, boarded by %d ships, splits her defence: %s (10.F.2)" % [who, parts.size(), "; ".join(parts)]
			Type.PRIZE_CREW:
				var n := int(data.get("sailors", 0)) + int(data.get("marines", 0))
				return "A prize crew of %d (%s%s) from %s goes aboard %s" % [n, _val("cq"), _val("mr"), other, who]
			Type.RECAPTURED:
				if str(data.get("cause", "")) == "boarded":
					return "%s is retaken by %s: her crew is freed from below (%s%s)" % [who, other, _val("cq"), _val("mr")]
				return "%s's crew rises and retakes the ship: %s below against a prize crew of %s (%s%s)" % [
					who, _val("original_boxes"), _val("prize_boxes"), _val("cq"), _val("mr")]
			Type.REORGANIZING_ABORTED:
				return "%s's boarders stop reorganizing to defend the prize %s (%s)" % [who, other,
					PhaseEvents.sections_text(data.get("sections", []))]
			Type.AGROUND:
				return _aground_text(who)
			Type.LEAD_CAST:
				return _lead_text(who)
			Type.ESCAPE_DECLARED:
				return "%s is trying to escape" % who
			Type.ESCAPED:
				return _escaped_text(who)
			Type.ARRIVED:
				var sail: String = PhaseEvents.SAIL_NAMES.get(str(data.get("sail_state", "")).to_upper(), "")
				return "%s arrives at %s%s" % [who, _hex_text("hex"), " under %s" % sail if sail != "" else ""]
			Type.ARRIVAL_DELAYED:
				return "%s cannot enter: %s holds her entry hex; she will try next turn" % [who, other]
			Type.DESTROYED:
				if str(data.get("reason", "")) == "no_sea_room":
					return "%s leaves the map where there is no sea room and is lost" % who
				var text := "%s explodes and is destroyed" % who
				if target_id != "":
					text += "; %s is no longer fouled with her" % other
				return text
			Type.STRIKE:
				return "%s strikes her colours (%s)" % [who,
					PhaseEvents.STRIKE_REASONS.get(str(data.get("reason", "")), str(data.get("reason", "cause unknown")))]
			Type.DRIFT:
				return _drift_text(who, other)
			Type.FOULED:
				# Collision fouling. A drift that fouls says so on its own DRIFT line.
				return "%s and %s are fouled together" % [who, other]
			Type.COLLISION:
				var at := _hex_text("hex")
				return "%s collides with %s%s" % [who, other, " at " + at if at != "" else ""]
			Type.STOPPED_SHORT:
				return _stopped_short_text(who, other)
			Type.TURN_UNDONE:
				return _turn_cause_text("%s cannot make its plotted turn" % who, other)
			Type.IN_IRONS:
				if data.get("cause", "") == "tack":
					return "%s misses stays and is in irons" % who
				if data.get("cause", "") == "rudder":
					return "%s turns into the wind with no rudder and is in irons" % who
				return "%s is still in irons" % who
			Type.POOR_MANEUVERING:
				return _poor_maneuvering_text(who)
			Type.WIND:
				return _wind_text()
			Type.BEAR_OFF:
				return _bear_off_text(who, other)
			Type.BEAR_OFF_ORDER:
				return _bear_off_order_text(ship_names)
			Type.UNFOUL:
				return _unfoul_text(who, other)
			Type.SAIL_CHANGE:
				return _sail_text(who)
			Type.CREW_TASK:
				return _crew_task_text(who)
			Type.VICTORY:
				return _victory_text()
			Type.SIGNAL:
				return _signal_text(who, ship_names)
			Type.TALK:
				return "%s calls across: %s" % [who, " ".join(data.get("words", []))]
			Type.END_OFFER:
				var side_name := "Side %d" % (int(data.get("side", 0)) + 1)
				return "%s offers to end the game" % side_name if data.get("offer", false) else "%s withdraws its offer to end the game" % side_name
		return "%s: event %d" % [who, type]

	## "X's damaged steering fails the turn (7 > 5) — one hex ahead" (6.F.3), or "answers the helm".
	func _poor_maneuvering_text(who: String) -> String:
		var roll := int(data.get("roll", 0))
		var needed := int(data.get("needed", 0))
		if data.get("success", false):
			return "%s's damaged steering answers the helm (%d ≤ %d)" % [who, roll, needed]
		var text := "%s's damaged steering fails the turn (%d > %d)" % [who, roll, needed]
		match str(data.get("outcome", "")):
			"one hex ahead":
				return text + " — one hex ahead"
			"carried over":
				return text + " — one hex ahead; the turn carries over to next turn"
		return text

	## "HMS Victory signals the fleet: ENGAGE THE ENEMY".
	func _signal_text(who: String, ship_names: Dictionary) -> String:
		var address: Dictionary = data.get("address", {})
		var to := "the fleet"
		match str(address.get("kind", "fleet")):
			"group":
				to = "the %s" % str(address.get("name", ""))
			"ship":
				to = _name(ship_names, str(address.get("name", "")))
		return "%s signals %s: %s" % [who, to, " ".join(data.get("words", []))]

	## "X: critical hit roll 3 -2 = 1 ≤ 4 — critical hit!" or "… 6 +0 = 6 > 4, no critical".
	func _critical_roll_text(who: String) -> String:
		var d6 := int(data.get("d6", 0))
		var mod := int(data.get("ch_mod", 0))
		var needed := int(data.get("ch_number", 0))
		var sum := "%d %+d = %d" % [d6, mod, d6 + mod]
		if data.get("hit", false):
			return "%s: critical hit roll %s ≤ %d — critical hit!" % [who, sum, needed]
		return "%s: critical hit roll %s > %d, no critical" % [who, sum, needed]

	## "X fixes the port broadside obscured (3 -2 = 1 ≤ 2)" or
	## "X fails to fix the jammed lines (7 -2 = 5 > 2)" (8.D.5, Unfouling table).
	func _critical_fixed_text(who: String) -> String:
		var id := str(data.get("result_id", ""))
		var what: String = PhaseEvents.CRITICAL_FIX_OBJECTS.get(id, id.replace("_", " "))
		var side := int(data.get("side", -1))
		if id == "broadside_obscured":
			what = "the %s%s" % [PhaseEvents.SIDE_NAMES[side] + " " if side == 0 or side == 1 else "", what]
		var roll := int(data.get("roll", 0))
		var mod := int(data.get("modifier", 0))
		var needed := int(data.get("needed", 0))
		var sum := "%d %+d = %d" % [roll, mod, roll + mod]
		if data.get("success", false):
			return "%s fixes %s (%s ≤ %d)" % [who, what, sum, needed]
		return "%s fails to fix %s (%s > %d)" % [who, what, sum, needed]

	## "X: hull critical 9 — guns dismounted −2 (port)", "X: rigging check 4 — lines jammed",
	## "X: rigging critical 4 — braces cut (ignored: dismasted)".
	func _critical_hit_text(who: String) -> String:
		var roll := _val("roll")
		var what := ""
		match str(data.get("source", "")):
			"rigging_check":
				what = "rigging check %s" % roll
			"hull_check":
				what = "hull check %s" % roll
			"hull_7":
				what = "rigging critical %s (from hull damage)" % roll
			_:
				what = "%s critical %s" % [str(data.get("table", "")), roll]
		var id := str(data.get("result_id", ""))
		var result: String = PhaseEvents.CRITICAL_RESULT_NAMES.get(id, id.replace("_", " "))
		var side := int(data.get("side", -1))
		var side_text := ""
		if side == 0 or side == 1:
			side_text = PhaseEvents.SIDE_NAMES[side]
		elif side == 2:
			side_text = "both broadsides"
		var sub: Array = data.get("sub_rolls", [])
		match id:
			"rudder":
				if data.get("converted", false):
					result = "rudder hit from ahead — 1 hull box instead"
				elif data.has("rudder"):
					var state := str(data["rudder"])
					if data.has("jam"):
						var jam := int(data["jam"])
						state += " " + ("to " + PhaseEvents.SIDE_NAMES[jam] if jam == 0 or jam == 1 else "amidships")
					result = "rudder %s (d6 %s)" % [state, str(sub[0]) if not sub.is_empty() else "?"]
			"guns_dismounted", "minor_explosion":
				if data.has("guns"):
					result += " −%d" % int(data["guns"])
				if data.has("fire_roll"):
					var fr: Dictionary = data["fire_roll"]
					var total := int(fr["roll"]) + int(fr["modifier"])
					var detail := "d10 %d %+d = %d" % [int(fr["roll"]), int(fr["modifier"]), total]
					if fr.get("afire", false):
						result += " — afire (%s ≥ %d)" % [detail, int(fr["needed"])]
					else:
						result += " — no fire (%s < %d)" % [detail, int(fr["needed"])]
			"afire_major_explosion":
				if data.has("guns"):
					result += " −%d guns" % int(data["guns"])
				if data.has("explosion"):
					var ex: Dictionary = data["explosion"]
					var detail := "2d10 %d %+d = %d" % [int(ex["roll"]),
						int(ex["modifier"]), int(ex["total"])]
					if ex.get("explodes", false):
						result += " — she explodes (%s < class %d)" % [detail, int(ex["needed"])]
					else:
						result += " — no explosion (%s, not below class %d)" % [detail, int(ex["needed"])]
			"broadside_obscured":
				if side_text != "":
					result = "%s broadside obscured" % side_text
					side_text = ""
			"yard_shot_away":
				side_text = ""
				result += " (both broadsides obscured)"
			"mast_may_fall":
				if data.has("needed") and not sub.is_empty():
					var total := int(sub[0]) + int(data.get("modifier", 0))
					result += " — %s (d6 %s %+d = %d, needs %d)" % [
						"the mast falls" if data.get("falls", false) else "it holds",
						str(sub[0]), int(data.get("modifier", 0)), total, int(data["needed"])]
			"stays_cut":
				if data.has("speed") and not sub.is_empty():
					result += " — %s (d10 %s, speed %d)" % [
						"the mast goes" if data.get("falls", false) else "the mast stands",
						str(sub[0]), int(data["speed"])]
			"crew_disorganized":
				var section := int(data.get("section", -1))
				if section >= 0 and section < ShipState.SECTION_NAMES.size():
					result += ": %s must reorganize" % ShipState.SECTION_NAMES[section]
			"waterline_damage":
				if data.has("pumps"):
					result += ", %s to the pumps" % PhaseEvents.plural(int(data["pumps"]), "sailor box", "sailor boxes")
		var text := "%s: %s — %s" % [who, what, result]
		if side_text != "":
			text += " (%s)" % side_text
		if data.has("ignored"):
			text += " (ignored: %s)" % str(data["ignored"])
		if data.has("note"):
			text += " (%s)" % PhaseEvents.CRITICAL_NOTES.get(str(data["note"]), str(data["note"]))
		return text

	## "X bears off to starboard to avoid Y (rolled 2, needed ≤ 5)", "X fails to bear off …", or
	## "X holds course into Y".
	func _bear_off_text(who: String, other: String) -> String:
		var choice := str(data.get("choice", ""))
		if choice == MovementTypes.BEAR_OFF_COLLIDE:
			return "%s holds course into %s" % [who, other]
		var drm := int(data.get("drm", 0))
		var roll_text := "rolled %d%s, needed ≤ %d" % [int(data.get("roll", 0)),
			" %+d" % drm if drm != 0 else "", int(data.get("needed", 0))]
		if data.get("success", false):
			return "%s bears off to %s to avoid %s (%s)" % [who, choice, other, roll_text]
		return "%s fails to bear off to %s (%s)" % [who, choice, roll_text]

	## "Two ships must bear off on the same segment; by d10 Bravo (7) decides first, then Alpha (3)" (6.D.3c).
	func _bear_off_order_text(ship_names: Dictionary) -> String:
		var parts: PackedStringArray = []
		for e in data.get("order", []):
			var rolls: PackedStringArray = []
			for r in (e as Dictionary).get("rolls", []):
				rolls.append(str(int(r)))
			parts.append("%s (%s)" % [_name(ship_names, str(e.get("ship_id", ""))), ", ".join(rolls)])
		if parts.is_empty():
			return "Bearing off order decided by d10"
		var count := "Two" if parts.size() == 2 else str(parts.size())
		var text := "%s ships must bear off on the same segment; by d10 %s decides first" % [count, parts[0]]
		for i in range(1, parts.size()):
			text += ", then %s" % parts[i]
		return text

	func _aground_text(who: String) -> String:
		var how := "drifts" if str(data.get("cause", "")) == "drift" else "runs"
		var on := "land" if str(data.get("terrain", "")) == "land" else "the shoal"
		var text := "%s %s aground on %s at %s" % [who, how, on, _hex_text("hex")]
		if on != "land" and data.has("depth"):
			text += ": %s ft, draws %s ft" % [_val("depth"), _val("draft")]
		return text

	func _lead_text(who: String) -> String:
		var depth := int(data.get("depth", -1))
		var reading := "land" if depth < 0 else "%d ft" % depth
		var text := "%s casts the lead: %s at %s, draws %s ft" % [who, reading, _hex_text("hex"), _val("draft")]
		var outcome := str(data.get("outcome", ""))
		var side := int(data.get("side", -1))
		match outcome:
			"bore_off":
				if side >= 0 and side < PhaseEvents.SIDE_NAMES.size():
					text += ", bears off to %s" % PhaseEvents.SIDE_NAMES[side]
				else:
					text += ", bears off"
			"entered":
				text += ", and holds her course"
			"held":
				text += ", and holds back"
			"pm_failed":
				text += ", but cannot make the turn (poor maneuvering)"
			"":
				pass
			_:
				text += ", %s" % outcome.replace("_", " ")
		return text

	func _escaped_text(who: String) -> String:
		var hexes := PhaseEvents.plural(int(data.get("range", 0)), "hex", "hexes")
		match str(data.get("how", "")):
			"distance":
				if int(data.get("range", -1)) < 0:
					return "%s escapes with no enemy in sight" % who
				return "%s escapes %s from the nearest enemy" % [who, hexes]
			"speed":
				return "%s escapes %s off, and no enemy can catch her" % [who, hexes]
		return "%s escapes off the %s edge" % [who, PhaseEvents.edge_label(str(data.get("edge", "")))]

	## "… stops short of its plotted course", with the cause the resolution recorded, if any.
	func _stopped_short_text(who: String, other: String) -> String:
		var text := "%s stops short of its plotted course" % who
		match str(data.get("cause", "")):
			"map_edge":
				return "%s stops at the edge of the map" % who
			"stern_contest", "stern_blocked", "overlap":
				return _turn_cause_text(text, other)
			"collision":
				if target_id != "":
					return "%s after colliding with %s" % [text, other]
			"lead":
				text += " after casting the lead"
			"bore_off":
				text += " after bearing off"
				if target_id != "":
					text += " — %s was in the way" % other
		return text

	## `text` followed by why a plotted turn was not made: a lost stern contest, a blocked stern or a
	## rolled-back overlap (6.B, 6.C), naming the other ship when it is known.
	func _turn_cause_text(text: String, other: String) -> String:
		if target_id == "":
			return text
		match str(data.get("cause", "")):
			"stern_contest":
				text += " — it lost the contest with %s for the hex its stern was turning into" % other
				if data.has("roll") and data.has("other_roll"):
					text += " (rolled %d against %d)" % [int(data["roll"]), int(data["other_roll"])]
			"stern_blocked":
				text += " — its stern was blocked by %s" % other
			"overlap":
				text += " — its stern swung into %s and had to swing back" % other
		return text

	func _fire_text(who: String, other: String) -> String:
		var side_idx := int(data.get("side", -1))
		var side := ""
		if side_idx >= 0 and side_idx < PhaseEvents.SIDE_NAMES.size():
			side = " " + PhaseEvents.SIDE_NAMES[side_idx]
		# A half broadside names its battery ("starboard bow battery"); a full broadside reads as before.
		var battery := str(data.get("battery", GunneryTypes.BATTERY_FULL))
		if battery == GunneryTypes.BATTERY_BOW or battery == GunneryTypes.BATTERY_STERN:
			side += " %s battery" % battery
		var setup := PackedStringArray()
		if data.has("range"):
			setup.append("range %s" % _val("range"))
		if data.has("aim"):
			setup.append(str(data["aim"]))
		if data.has("ammo"):
			setup.append("roundshot" if data["ammo"] == GunneryTypes.AMMO_ROUND else "dismantling shot")
		var rake := str(data.get("rake", ""))
		if rake != "":
			setup.append("%s rake" % rake)
		var text := "%s fires%s at %s" % [who, side, other]
		if not setup.is_empty():
			text += ", " + ", ".join(setup)

		var calc := PackedStringArray()
		if data.has("bgn"):
			calc.append("base %s" % _val("bgn"))
		var modifiers: Array = data.get("modifiers", [])
		for m in modifiers:
			calc.append("%s %+d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))), int(m.get("value", 0))])
		var sum := ", ".join(calc)
		if data.has("mgn") and not modifiers.is_empty():
			sum += " = %s" % _val("mgn")
		if data.has("d6"):
			sum += ("" if sum == "" else ", ") + "d6 %s" % _val("d6")
		if data.has("fgn"):
			sum += " → %s" % _val("fgn")
		if sum != "":
			text += " — " + sum
		return text + ": " + _hits_text(["rigging", "hull", "crew"], {}, "no damage")

	## "2 rigging, 1 hull" for the non-zero amounts among `keys`; `fallback` when all are zero.
	func _hits_text(keys: Array, units: Dictionary, fallback: String) -> String:
		var parts := PackedStringArray()
		for key in keys:
			var amount := int(data.get(key, 0))
			if amount <= 0:
				continue
			if units.has(key):
				parts.append(PhaseEvents.plural(amount, units[key][0], units[key][1]))
			else:
				parts.append("%d %s" % [amount, key])
		return ", ".join(parts) if not parts.is_empty() else fallback

	func _damage_text(who: String) -> String:
		var units := {
			"rigging": ["rigging box", "rigging boxes"],
			"hull": ["hull box", "hull boxes"],
			"sailors_lost": ["sailor", "sailors"],
			"marines_lost": ["marine", "marines"],
			"crew": ["crew", "crew"],
		}
		var keys: Array = ["rigging", "hull"]
		if data.has("sailors_lost") or data.has("marines_lost"):
			keys.append_array(["sailors_lost", "marines_lost"])
		else:
			keys.append("crew")
		var hits := _hits_text(keys, units, "")
		if hits == "":
			return "%s takes no damage" % who
		if data.get("cause", "") == "fire":
			return "%s loses %s to fire" % [who, hits]
		if data.get("cause", "") == "marine_fire":
			return "%s loses %s to musketry" % [who, hits]
		if data.get("cause", "") == "boarding":
			return "%s loses %s in the boarding (%s BCF needed)" % [who, hits, _val("bcf_needed")]
		return "%s loses %s" % [who, hits]

	## "X's marines fire on Y (7 boxes, column 7-8) — d6 5, alongside −1 → 4: 1 crew box" (7.G).
	func _marine_fire_text(who: String, other: String) -> String:
		var calc := PackedStringArray(["d6 %s" % _val("d6")])
		for m in data.get("modifiers", []):
			calc.append("%s %s%d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))),
				"−" if int(m.get("value", 0)) < 0 else "+", absi(int(m.get("value", 0)))])
		var crew := int(data.get("crew", 0))
		var result := "no effect" if crew <= 0 else PhaseEvents.plural(crew, "crew box", "crew boxes")
		return "%s's marines fire on %s (%s, column %s) — %s → %s: %s" % [who, other,
			PhaseEvents.plural(int(data.get("boxes", 0)), "box", "boxes"), _val("column"),
			", ".join(calc), _val("total"), result]

	## "X throws grapples at Y — d10 2, crew −1 → 1 ≤ 2: grappled" (8.C.2).
	func _grapple_text(who: String, other: String) -> String:
		var success: bool = data.get("success", false)
		var text := "%s throws grapples at %s — %s %s %s: %s" % [who, other, _calc_text(),
			"≤" if success else ">", _val("needed"), "grappled" if success else "they miss"]
		var irons: Array = data.get("in_irons", [])
		if success and not irons.is_empty():
			var names := PackedStringArray()
			for sid in irons:
				names.append(who if sid == ship_id else other)
			text += "; %s %s in irons, head to wind" % [" and ".join(names), "is" if names.size() == 1 else "are"]
		return text

	## "Boarding, X onto Y: 62 v 44; attacker 9 −2 = 7, defender 9 −1 = 8" (10.D.1-3).
	func _boarding_round_text(who: String, other: String) -> String:
		var a: Dictionary = data.get("attacker", {})
		var d: Dictionary = data.get("defender", {})
		var side := func(x: Dictionary) -> String:
			var drm := int(x.get("drm", 0))
			return "%d %s%d = %d" % [int(x.get("roll", 0)), "−" if drm < 0 else "+", absi(drm), int(x.get("total", 0))]
		var round_no := int(data.get("round", 1))
		return "Boarding, %s onto %s%s: %d v %d; attacker %s, defender %s" % [who, other,
			" (round %d)" % round_no if round_no > 1 else "", int(a.get("tbcf", 0)),
			int(d.get("tbcf", 0)), side.call(a), side.call(d)]

	## "X's boarders are repulsed and take 1 MC" / "X's boarders carry Y" / "The fight aboard Y goes on".
	## A capture's taking is the SHIP_CAPTURED line that follows; this line gives the fight's outcome.
	func _boarding_result_text(who: String, other: String, ship_names: Dictionary) -> String:
		var d10 := int(data.get("d10", -1))
		var kind := "capture roll" if str(data.get("special", "")).begins_with("capture") else "repulse roll"
		var roll := " (%s d10 %d %s MR %d)" % [kind, d10, "<" if d10 < int(data.get("mr", 0)) else "≥", int(data.get("mr", 0))] if d10 >= 0 else ""
		match str(data.get("result", "")):
			"captured":
				match str(data.get("reason", "")):
					"struck_in_action":
						return "%s has struck with boarders aboard (10.E.2c)" % other
					"all_defenders_lost":
						return "%s has no defenders left (10.E.2e)" % other
				return "%s's boarders carry %s!%s" % [who, other, roll]
			"shared_capture":
				return "%s's boarders are aboard %s as %s takes her: they reorganize too (10.F)%s" % [who, other,
					_name(ship_names, str(data.get("captor_id", ""))), roll]
			"surrendered":
				return "%s's boarders aboard %s surrender with their ship (10.D.6)" % [who, other]
			"attackers_lost":
				return "%s's boarders are all lost: %s holds" % [who, other]
			"target_gone":
				return "The fight aboard %s ends: she is gone" % other
			"repulsed":
				var mcs := int(data.get("mcs", 0))
				return "%s's boarders are repulsed%s%s" % [who, " and take %s" % PhaseEvents.plural(mcs, "MC") if mcs > 0 else "", roll]
			"driven_off":
				return "%s's boarders are all lost: %s holds" % [who, other]
		var special := str(data.get("special", "none"))
		if special != "none" and d10 >= 0:
			return "The fight aboard %s goes on%s" % [other, roll]
		return "The fight aboard %s goes on" % other

	## "X cuts the grapples to Y — d10 3, crew −2 → 1 ≤ 2 (1st try): free" (8.C.4).
	func _ungrapple_text(who: String, other: String) -> String:
		var success: bool = data.get("success", false)
		var verdict := "cuts the grapples to" if success else "fails to cut the grapples to"
		return "%s %s %s — %s %s %s (try %s)" % [who, verdict, other, _calc_text(),
			"≤" if success else ">", _val("needed"), _val("attempt")]

	## "d10 4, crew −2, fouled −1 → 1" from roll, modifiers and total.
	func _calc_text() -> String:
		var calc := PackedStringArray(["d10 %s" % _val("roll")])
		for m in data.get("modifiers", []):
			calc.append("%s %s%d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))),
				"−" if int(m.get("value", 0)) < 0 else "+", absi(int(m.get("value", 0)))])
		return "%s → %s" % [", ".join(calc), _val("total")]

	func _morale_check_text(who: String) -> String:
		var text := "%s morale check: rolled %s, needed %s" % [who, _val("roll"), _val("rating")]
		if not data.has("passed"):
			return text
		if data["passed"]:
			return text + " — passes"
		text += " — fails"
		if data.get("breaks", false):
			return text + "; the crew will not fight on"
		if data.has("quality"):
			text += "; crew quality drops to %s" % data["quality"]
		return text

	## One line per drift, telling the whole outcome: drifted, held by the roll, or blocked (by the
	## map edge, by the ship in its way — fouling it or not — or by its fouled partner).
	func _drift_text(who: String, other: String) -> String:
		var from_hex := _hex_text("from")
		var at := " at %s" % from_hex if from_hex != "" else ""
		var dice := "rolled %s, needed %s" % [_roll_text(), _val("needed")]
		if data.get("drifted", false) and data.has("partial"):
			return _partial_drift_text(who, other)
		if data.get("drifted", false):
			var text := "%s drifts downwind" % who
			if from_hex != "" and data.has("to"):
				text += " from %s to %s" % [from_hex, _hex_text("to")]
			return text + " (drift roll %s, needed %s)" % [_roll_text(), _val("needed")]
		if not data.has("blocked"):
			return "%s holds position%s (drift roll %s, needed %s)" % [who, at, _roll_text(), _val("needed")]
		match str(data["blocked"]):
			"aground":
				return "%s drifts aground" % who
			"map edge":
				return "%s would drift (%s) but is at the edge of the map and holds position%s" % [who, dice, at]
			"ship":
				if target_id == "":
					return "%s would drift (%s) but another ship is in the way; holds position%s" % [who, dice, at]
				if data.get("fouled", false):
					return "%s drifts onto %s (%s) but cannot pass; the two ships are fouled together" % [
						who, other, dice]
				return "%s would drift onto %s (%s) but is blocked and holds position%s" % [who, other, dice, at]
			"partner":
				var link := str(data.get("link", "fouled"))
				var partner := other if target_id != "" else "its %s partner" % ("grappled" if link == "grappled" else "fouled")
				var how := "fouled alongside"
				if link == "grappled":
					how = "grappled alongside"
				elif link == "group":
					how = "in the same grappled or fouled group"
				return "%s would drift (%s) but is held back by %s, %s, and holds position%s" % [
					who, dice, partner, how, at]
		return "%s would drift (%s) but is blocked and holds position%s" % [who, dice, at]

	## A partial drift (8.A.5): one end slips downwind and the ship swings round on the other.
	func _partial_drift_text(who: String, other: String) -> String:
		var names := ["E", "SE", "SW", "W", "NW", "NE"]
		var facing := int(data.get("facing", -1))
		var text := "%s drifts partly: its %s slips downwind" % [who, str(data["partial"])]
		if facing >= 0 and facing < names.size():
			text += " and it swings to face %s" % names[facing]
		if target_id != "":
			text += ", blocked by %s" % other
		if data.get("fouled", false):
			text += "; the two ships are fouled together"
		return text + " (drift roll %s, needed %s)" % [_roll_text(), _val("needed")]

	func _unfoul_text(who: String, other: String) -> String:
		# Either ship's success frees the pair, so a failure never claims the pair stays fouled.
		var dice := "rolled %s, needed %s or less" % [_roll_text(), _val("needed")]
		if not data.has("success"):
			return "%s tries to cut free of %s: %s" % [who, other, dice]
		if data["success"]:
			return "%s cuts free (%s) — %s and %s are no longer fouled" % [who, dice, who, other]
		return "%s fails to cut free of %s (%s)" % [who, other, dice]

	## "6", or "6 +1" when a modifier applies.
	func _roll_text() -> String:
		var modifier := int(data.get("modifier", 0))
		return _val("roll") if modifier == 0 else "%s %+d" % [_val("roll"), modifier]

	## "(q, r)" for a {"q", "r"} dictionary stored under `key`, "" when absent or malformed.
	func _hex_text(key: String) -> String:
		var hex = data.get(key)
		if hex is Dictionary and hex.has("q") and hex.has("r"):
			return "(%d, %d)" % [int(hex["q"]), int(hex["r"])]
		return ""

	func _sail_text(who: String) -> String:
		var to := str(data.get("to", ""))
		if data.has("cancelled"):
			var reason: String = PhaseEvents.SAIL_CANCEL_REASONS.get(str(data["cancelled"]), str(data["cancelled"]))
			var change := " to %s" % PhaseEvents.sail_name(to) if to != "" else ""
			return "%s: sail change%s cancelled: %s" % [who, change, reason]
		var turns := int(data.get("turns_left", 0))
		if turns <= 0:
			return "%s is now at %s" % [who, PhaseEvents.sail_name(to)]
		return "%s begins changing sail %s → %s (%s)" % [who, _val("from"), _val("to"),
			PhaseEvents.plural(turns, "turn")]

	## "Vengeance catches fire (hull critical)", "...: a second fire breaks out", "... catches fire
	## from Fougueux (d10 2 ≤ 4)".
	func _fire_started_text(who: String, other: String) -> String:
		var fires := int(data.get("fires", 1))
		var head := "%s catches fire" % who if fires <= 1 else "Another fire breaks out aboard %s (%d burning)" % [who, fires]
		var why := ""
		match str(data.get("cause", "")):
			"crit":
				why = "hull critical"
			"spread":
				why = "from %s" % other if target_id != "" else "spread"
				if data.has("roll"):
					why += ", d10 %d ≤ %d" % [int(data["roll"]), int(data.get("needed", 0))]
			"growth":
				why = "the fire grows after %s" % PhaseEvents.plural(int(data.get("age", 5)), "turn")
			"debris":
				why = "flaming debris from %s" % other if target_id != "" else "flaming debris"
		var text := head + (" (%s)" % why if why != "" else "")
		if fires > 1 and why != "":
			text = head.trim_suffix(")") + "; %s)" % why  # one parenthesis: "(2 burning; …)"
		if data.get("mc", false):
			text += ": morale check"
		return text

	## "Vengeance's S2 puts out fire 1 (3 −2 = 1 ≤ 2)" / "... fails to master fire 1 (8 −2 = 6 > 2)" (8.E.3).
	func _fire_fought_text(who: String) -> String:
		var sections: Array = data.get("sections", [])
		var crew := PhaseEvents.crew_subject(sections)
		if data.get("below", false):
			crew = "original crew below"  # 10.H.3
			sections = []
		var roll := int(data.get("roll", 0))
		var modifier := int(data.get("modifier", 0))
		var needed := int(data.get("needed", 0))
		var sum := "%d %s = %d" % [roll, ("%+d" % modifier).replace("-", "−"), roll + modifier] if modifier != 0 else str(roll)
		var number := int(data.get("number", 1))
		if data.get("success", false):
			return "%s's %s %s out fire %d (%s ≤ %d)" % [who, crew, PhaseEvents.crew_verb(sections, "puts", "put"),
				number, sum, needed]
		return "%s's %s %s to master fire %d (%s > %d, %s turn)" % [who, crew,
			PhaseEvents.crew_verb(sections, "fails", "fail"), number, sum, needed,
			PhaseEvents._ordinal(int(data.get("attempt", 1)) - 1)]

	## "Vengeance repairs a rigging box (section 2)", "Vengeance splices the severed shrouds" (8.F.5).
	func _repair_text(who: String) -> String:
		var sections: Array = data.get("sections", [])
		var by := " (%s)" % PhaseEvents.sections_text(sections) if not sections.is_empty() else ""
		match str(data.get("kind", "")):
			"shrouds":
				return "%s splices the severed shrouds%s" % [who, by]
			"rigging", "hull":
				var section := int(data.get("section", -1))
				var where := " in section %d" % (section + 1) if section >= 0 else ""
				return "%s repairs a %s box%s%s" % [who, str(data["kind"]), where, by]
		return "%s completes a repair%s" % [who, by]

	## "Vengeance: S3 begins to repair rigging (4 turns)", "Vengeance: S3 and S4 stop reorganizing: the
	## ship has struck", "Vengeance: S3 finishes repairing rigging".
	func _crew_task_text(who: String) -> String:
		var sections: Array = data.get("sections", [])
		var crew := PhaseEvents.crew_subject(sections)
		var code := str(data.get("code", ""))
		var task: String = PhaseEvents.CREW_TASK_NAMES.get(code, code)
		var doing: String = PhaseEvents.CREW_TASK_GERUNDS.get(code, code)
		if code == "FF" and int((data.get("params", {}) as Dictionary).get("fire", -1)) < 0:
			task = "stand fire watch"
			doing = "standing fire watch"
		var verb := func(one: String, many: String) -> String: return PhaseEvents.crew_verb(sections, one, many)
		var reason_id := str(data.get("reason", data.get("state", "")))
		var reason: String = PhaseEvents.CREW_TASK_REASONS.get(reason_id, reason_id)
		var needed := int(data.get("needed", -1))
		match str(data.get("state", "")):
			"attached":
				return "%s: %s, on fire watch, %s to the new fire at once" % [who, crew, verb.call("turns", "turn")]
			"started":
				var length := " (%s)" % PhaseEvents.plural(needed, "turn") if needed > 0 else ""
				return "%s: %s %s to %s%s" % [who, crew, verb.call("begins", "begin"), task, length]
			"completed":
				return "%s: %s %s %s" % [who, crew, verb.call("finishes", "finish"), doing]
			"refused":
				return "%s: %s cannot %s: %s" % [who, crew, task, reason]
			"reset":
				return "%s: %s's work to %s is lost (%s done): %s" % [who, crew, task,
					PhaseEvents.plural(int(data.get("done", 0)), "turn"), reason]
		return "%s: %s %s %s: %s" % [who, crew, verb.call("stops", "stop"), doing, reason]

	## "The wind veers to west", "The wind freshens to 3 (fresh)", or both in one line.
	func _wind_text() -> String:
		var text := PhaseEvents.wind_change_text(int(data.get("from_direction", 0)),
			int(data.get("to_direction", data.get("from_direction", 0))), int(data.get("from_speed", 0)),
			int(data.get("to_speed", data.get("from_speed", 0))), str(data.get("speed_name", "")))
		if data.get("forecast", false):
			return "Next turn " + text.substr(0, 1).to_lower() + text.substr(1)
		return text

	func _victory_text() -> String:
		var reason: String = PhaseEvents.VICTORY_REASONS.get(str(data.get("reason", "")), str(data.get("reason", "")))
		var suffix := " (%s)" % reason if reason != "" else ""
		if not data.has("winner"):
			return "The battle is over" + suffix
		match int(data["winner"]):
			PhaseEvents.HUMAN_SIDE:
				return "Victory: you" + suffix
			-1:
				return "Draw" + suffix
		return "Victory: the enemy" + suffix

	func _val(key: String, fallback: String = "?") -> String:
		return str(data[key]) if data.has(key) else fallback

	static func _name(ship_names: Dictionary, id: String) -> String:
		if id == "":
			return "?"
		return str(ship_names.get(id, id))


## Ordered list of events for one turn.
class PhaseLog extends RefCounted:
	var turn: int = 0
	var events: Array[PhaseEvent] = []
	## ship id -> controlling player id (-1 unknown). GameState sets it on the logs it makes, so each
	## event records the sides as they are when it is logged (PhaseEvent.sides).
	var side_of: Callable

	func add(type: Type, phase: int, ship_id: String, data: Dictionary = {},
			target_id: String = "") -> PhaseEvent:
		var ev := PhaseEvent.new(type, phase, ship_id, data, target_id)
		_stamp(ev)
		events.append(ev)
		return ev

	## Takes an event out of the log (a result superseded before anything was shown).
	func remove(ev: PhaseEvent) -> void:
		events.erase(ev)

	func _stamp(ev: PhaseEvent) -> void:
		if not side_of.is_valid():
			return
		for id in ev.ship_ids():
			var side: int = side_of.call(id)
			if side >= 0:
				ev.sides[id] = side

	## Like add, but places the event at `index` (clamped to the log), so a cause can be logged
	## ahead of consequences that were recorded while it was being worked out.
	func insert(index: int, type: Type, phase: int, ship_id: String, data: Dictionary = {},
			target_id: String = "") -> PhaseEvent:
		var ev := PhaseEvent.new(type, phase, ship_id, data, target_id)
		_stamp(ev)
		events.insert(clampi(index, 0, events.size()), ev)
		return ev

	func of_type(type: Type) -> Array[PhaseEvent]:
		var result: Array[PhaseEvent] = []
		for ev in events:
			if ev.type == type:
				result.append(ev)
		return result

	func to_dict() -> Dictionary:
		var list: Array = []
		for ev in events:
			list.append(ev.to_dict())
		return {"turn": turn, "events": list}
