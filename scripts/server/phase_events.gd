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
}

const SIDE_NAMES := ["port", "starboard"]

## The human player's id (single-player: player 0); VICTORY text is written from their side.
const HUMAN_PLAYER := 0

const SAIL_NAMES := {
	"FS": "fighting sail", "MS": "maneuvering sail", "PS": "plain sail", "NS": "no sail",
}

const SAIL_CANCEL_REASONS := {
	"not available": "that sail is not available now",
	"no crew": "not enough crew to work the sails",
	"crew lost": "the crew working the sails were lost",
	"struck": "the ship has struck",
	"dismasted": "the ship is dismasted",
}

const STRIKE_REASONS := {
	"hull destroyed": "hull destroyed",
	"no crew": "no crew left",
	"morale": "the crew's morale broke",
}

const VICTORY_REASONS := {
	"all struck": "every ship of one side has struck",
	"turn limit": "turn limit reached",
}

const ORDINALS := ["first", "second", "third", "fourth", "fifth"]


## Wind directions by index, as EnvironmentState numbers them (0 = E, 1 = SE ... 5 = NE).
const WIND_DIRECTION_WORDS := ["east", "south-east", "south-west", "west", "north-west", "north-east"]


static func wind_direction_word(direction: int) -> String:
	return WIND_DIRECTION_WORDS[direction] if direction >= 0 and direction < WIND_DIRECTION_WORDS.size() else "?"


## Display label for a gunnery modifier id ("initial_broadside" -> "initial broadside").
static func modifier_label(modifier_id: String) -> String:
	return MODIFIER_LABELS.get(modifier_id, modifier_id.replace("_", " "))


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
		}

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
				return "%s has %s dismounted on each broadside" % [
					who, PhaseEvents.plural(guns, "gun") if data.has("amount") else "guns"]
			Type.MORALE_NOTED:
				var times := "" if int(data.get("count", 1)) <= 1 else " %s" % PhaseEvents.times_text(int(data["count"]))
				return "%s must check morale%s (%s)" % [who, times,
					PhaseEvents.morale_trigger_text(str(data.get("trigger", "")))]
			Type.MORALE_CHECK:
				return _morale_check_text(who)
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
			Type.IN_IRONS:
				if data.get("cause", "") == "tack":
					return "%s misses stays and is in irons" % who
				return "%s is still in irons" % who
			Type.WIND:
				return _wind_text()
			Type.UNFOUL:
				return _unfoul_text(who, other)
			Type.SAIL_CHANGE:
				return _sail_text(who)
			Type.VICTORY:
				return _victory_text()
		return "%s: event %d" % [who, type]

	## "… stops short of its plotted course", with the cause the resolution recorded, if any.
	func _stopped_short_text(who: String, other: String) -> String:
		var text := "%s stops short of its plotted course" % who
		match str(data.get("cause", "")):
			"collision":
				if target_id != "":
					return "%s after colliding with %s" % [text, other]
			"bore_off":
				text += " after bearing off"
				if target_id != "":
					text += " — %s was in the way" % other
		return text

	func _fire_text(who: String, other: String) -> String:
		var side_idx := int(data.get("side", -1))
		var side := ""
		if side_idx >= 0 and side_idx < PhaseEvents.SIDE_NAMES.size():
			side = " " + PhaseEvents.SIDE_NAMES[side_idx]
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
		return "%s loses %s" % [who, hits]

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
		if data.get("drifted", false):
			var text := "%s drifts downwind" % who
			if from_hex != "" and data.has("to"):
				text += " from %s to %s" % [from_hex, _hex_text("to")]
			return text + " (drift roll %s, needed %s)" % [_roll_text(), _val("needed")]
		if not data.has("blocked"):
			return "%s holds position%s (drift roll %s, needed %s)" % [who, at, _roll_text(), _val("needed")]
		match str(data["blocked"]):
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
				var partner := other if target_id != "" else "its fouled partner"
				return "%s would drift (%s) but is held back by %s, fouled alongside, and holds position%s" % [
					who, dice, partner, at]
		return "%s would drift (%s) but is blocked and holds position%s" % [who, dice, at]

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

	## "The wind veers to west", "The wind freshens to 3 (fresh)", or both in one line.
	func _wind_text() -> String:
		var parts := PackedStringArray()
		if data.has("from_direction") and data.has("to_direction"):
			var from_dir := int(data["from_direction"])
			var to_dir := int(data["to_direction"])
			if from_dir != to_dir:
				# Directions number clockwise (0 = E, 1 = SE ...): clockwise is veering.
				var steps := (to_dir - from_dir + 6) % 6
				var verb := "veers" if steps < 3 else ("backs" if steps > 3 else "shifts")
				parts.append("%s to %s" % [verb, PhaseEvents.wind_direction_word(to_dir)])
		if data.has("from_speed") and data.has("to_speed"):
			var from_speed := int(data["from_speed"])
			var to_speed := int(data["to_speed"])
			if from_speed != to_speed:
				var speed_name := str(data.get("speed_name", "")).to_lower()
				parts.append("%s to %d%s" % ["freshens" if to_speed > from_speed else "eases", to_speed,
					" (%s)" % speed_name if speed_name != "" else ""])
		if parts.is_empty():
			return "The wind holds steady"
		return "The wind " + " and ".join(parts)

	func _victory_text() -> String:
		var reason: String = PhaseEvents.VICTORY_REASONS.get(str(data.get("reason", "")), str(data.get("reason", "")))
		var suffix := " (%s)" % reason if reason != "" else ""
		if not data.has("winner"):
			return "The battle is over" + suffix
		match int(data["winner"]):
			PhaseEvents.HUMAN_PLAYER:
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

	func add(type: Type, phase: int, ship_id: String, data: Dictionary = {},
			target_id: String = "") -> PhaseEvent:
		var ev := PhaseEvent.new(type, phase, ship_id, data, target_id)
		events.append(ev)
		return ev

	## Like add, but places the event at `index` (clamped to the log), so a cause can be logged
	## ahead of consequences that were recorded while it was being worked out.
	func insert(index: int, type: Type, phase: int, ship_id: String, data: Dictionary = {},
			target_id: String = "") -> PhaseEvent:
		var ev := PhaseEvent.new(type, phase, ship_id, data, target_id)
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
