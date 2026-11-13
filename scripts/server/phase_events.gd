class_name PhaseEvents
extends RefCounted
## PhaseEvents - Typed per-turn event log.
##
## Server controllers append events (die rolls, modifiers, outcomes) to
## GameState.turn_log; the UI renders them with PhaseEvent.to_text so every
## roll is traceable by the player.

enum Type {
	FIRE, DAMAGE, GUNS_DISMOUNTED, MORALE_NOTED, MORALE_CHECK, STRIKE,
	DRIFT, FOULED, UNFOUL, SAIL_CHANGE, VICTORY,
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

	## One readable line. Missing data keys are skipped, never an error.
	func to_text(ship_names: Dictionary) -> String:
		var who := _name(ship_names, ship_id)
		var other := _name(ship_names, target_id)
		match type:
			Type.FIRE:
				return _fire_text(who, other)
			Type.DAMAGE:
				return "%s takes %s" % [who, _damage_summary()]
			Type.GUNS_DISMOUNTED:
				return "%s has %s guns dismounted" % [who, _val("amount")]
			Type.MORALE_NOTED:
				return "%s notes morale trigger %s (count %s)" % [
					who, _val("trigger"), _val("count")]
			Type.MORALE_CHECK:
				var passed := "passed" if data.get("passed", false) else "failed"
				return "%s morale check: roll %s vs rating %s (quality %s): %s" % [
					who, _val("roll"), _val("rating"), _val("quality"), passed]
			Type.STRIKE:
				return "%s strikes (%s)" % [who, _val("reason")]
			Type.DRIFT:
				return _drift_text(who)
			Type.FOULED:
				return "%s is fouled with %s" % [who, other]
			Type.UNFOUL:
				var result := "frees itself" if data.get("success", false) else "stays fouled"
				return "%s tries to unfoul from %s: roll %s %+d, needed %s: %s" % [
					who, other, _val("roll"), int(data.get("modifier", 0)),
					_val("needed"), result]
			Type.SAIL_CHANGE:
				return _sail_text(who)
			Type.VICTORY:
				return "Victory: side %s (%s)" % [_val("winner"), _val("reason")]
		return "%s: event %d" % [who, type]

	func _fire_text(who: String, other: String) -> String:
		var parts := PackedStringArray()
		parts.append("BGN %s" % _val("bgn"))
		for m in data.get("modifiers", []):
			var label: String = PhaseEvents.MODIFIER_LABELS.get(m.get("name", ""),
				str(m.get("name", "?")).replace("_", " "))
			parts.append("%+d %s" % [int(m.get("value", 0)), label])
		var calc := " ".join(parts)
		if data.has("mgn"):
			calc += " = %s" % _val("mgn")
		var side_idx := int(data.get("side", -1))
		var side := ""
		if side_idx >= 0 and side_idx < PhaseEvents.SIDE_NAMES.size():
			side = " " + PhaseEvents.SIDE_NAMES[side_idx]
		var aim := ", %s" % data["aim"] if data.has("aim") else ""
		var ammo := ""
		if data.has("ammo"):
			ammo = ", roundshot" if data["ammo"] == "round" else ", %s" % data["ammo"]
		var text := "%s fires%s at %s, range %s%s%s: %s" % [
			who, side, other, _val("range"), aim, ammo, calc]
		text += ", d6 %s" % _val("d6")
		if data.has("fgn"):
			text += " → %s" % _val("fgn")
		var rake := str(data.get("rake", ""))
		if rake != "":
			text += " (%s rake)" % rake
		text += ": " + _damage_summary()
		return text

	func _damage_summary() -> String:
		var parts := PackedStringArray()
		parts.append("%s rigging" % _val("rigging", "0"))
		parts.append("%s hull" % _val("hull", "0"))
		parts.append("%s crew" % _val("crew", "0"))
		var text := ", ".join(parts)
		if data.has("crew_rolls"):
			text += " (crew rolls %s)" % str(data["crew_rolls"])
		return text

	func _drift_text(who: String) -> String:
		var text := "%s drift check: roll %s, needed %s: " % [who, _val("roll"), _val("needed")]
		var from_hex := _hex_text("from")
		if data.get("drifted", false):
			text += "drifts"
			if from_hex != "" and data.has("to"):
				text += " from %s to %s" % [from_hex, _hex_text("to")]
			return text
		if data.has("blocked"):
			text += "blocked by %s, holds position" % data["blocked"]
		else:
			text += "holds position"
		if from_hex != "":
			text += " at %s" % from_hex
		return text

	## "(q, r)" for a {"q", "r"} dictionary stored under `key`, "" when absent or malformed.
	func _hex_text(key: String) -> String:
		var hex = data.get(key)
		if hex is Dictionary and hex.has("q") and hex.has("r"):
			return "(%d, %d)" % [int(hex["q"]), int(hex["r"])]
		return ""

	func _sail_text(who: String) -> String:
		if data.has("cancelled"):
			return "%s sail change cancelled (%s)" % [who, data["cancelled"]]
		var text := "%s sail change %s → %s" % [who, _val("from"), _val("to")]
		if data.has("turns_left"):
			text += ", %s turns left" % _val("turns_left")
		return text

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
