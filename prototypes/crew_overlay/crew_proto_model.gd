extends RefCounted
## Throwaway prototype model for the crew overlay. A faithful port of the state and
## rules in docs/superpowers/prototypes/crew-overlay.html (v15): fake data, no rules
## engine, never reads or writes GameState.

signal message_requested(text: String, kind: String, actions: Array)

const SECTIONS_FIRING := {4: 0, 3: -3, 2: -6, 1: -9}

const SHIPS := {
	"frigate": {
		"name": "HMS Lively", "type": "38-gun frigate", "crew_quality": "D", "sk": 0,
		"crew": {"S1": 3, "S2": 3, "S3": 3, "S4": 3, "M": 2},
		"hull": {"max": [5, 5, 5, 6], "cur": [4, 5, 5, 6]},
		"rig": {"max": [5, 5, 6, 6], "cur": [2, 5, 6, 6]},
		"decks": [
			{"id": "upper", "name": "Upper deck", "note": "Quarterdeck, waist and forecastle", "guns": 4},
			{"id": "gun", "name": "Gun deck", "note": "19 eighteen-pounders a side", "guns": 19},
			{"id": "orlop", "name": "Orlop", "note": "Below the waterline", "guns": 0},
		],
		"gun_decks": ["gun"],
	},
	"sol74": {
		"name": "HMS Superb", "type": "74-gun ship of the line", "crew_quality": "C", "sk": -1,
		"crew": {"S1": 6, "S2": 6, "S3": 6, "S4": 6, "M": 5},
		"hull": {"max": [8, 8, 9, 9], "cur": [6, 8, 9, 9]},
		"rig": {"max": [7, 7, 7, 7], "cur": [3, 7, 7, 7]},
		"decks": [
			{"id": "upper", "name": "Upper deck", "note": "Quarterdeck, waist and forecastle", "guns": 6},
			{"id": "gun_up", "name": "Upper gun deck", "note": "14 eighteen-pounders a side", "guns": 14},
			{"id": "gun_low", "name": "Lower gun deck", "note": "14 thirty-two-pounders a side", "guns": 14},
			{"id": "orlop", "name": "Orlop", "note": "Below the waterline", "guns": 0},
		],
		"gun_decks": ["gun_up", "gun_low"],
	},
}

# Repair turns, 8.F: RR 6 ± SK, RH 10 ± SK, RS 5 ± SK. Rects are landscape deck units (1000 x 360).
const STATIONS := {
	"guns": {"label": "Serve the guns", "code": "", "decks": "gun_decks", "rect": [190, 118, 620, 124], "cap": 4,
		"accepts": "sailor", "is_default": true, "note": "Both broadsides. Unassigned sailors work the guns (4.B.4)."},
	"marine_fire": {"label": "Marine fire", "code": "", "decks": ["upper"], "rect": [78, 70, 170, 96], "cap": 1,
		"accepts": "marine", "is_default": true, "note": "Muskets at the quarterdeck rail."},
	"braces": {"label": "Braces (tacking)", "code": "T", "decks": ["upper"], "rect": [448, 64, 150, 98], "cap": 3, "accepts": "any"},
	"boarders": {"label": "Boarders", "code": "FB", "decks": ["upper"], "rect": [272, 64, 168, 98], "cap": 5, "accepts": "any"},
	"rr": {"label": "Rigging repair", "code": "RR", "decks": ["upper"], "rect": [420, 196, 160, 96], "cap": 1, "accepts": "any"},
	"rs": {"label": "Shroud repair", "code": "RS", "decks": ["upper"], "rect": [272, 196, 140, 96], "cap": 1, "accepts": "any"},
	"sails": {"label": "Sails aloft", "code": "", "decks": ["upper"], "rect": [606, 92, 210, 176], "cap": 2, "accepts": "any"},
	"rh": {"label": "Hull repair", "code": "RH", "decks": ["orlop"], "rect": [330, 118, 300, 124], "cap": 1, "accepts": "any"},
}
## Fire stations sit in this zone under Marine fire (landscape units).
const FIRE_ZONE := [78, 192, 170, 106]

const SAIL_CHANGES := {
	"FS": [{"to": "MS", "cs": 1, "turns": 2}, {"to": "Furl", "cs": 1, "turns": 1}],
	"MS": [{"to": "FS", "cs": 1, "turns": 1}, {"to": "PS", "cs": 2, "turns": 2}],
	"PS": [{"to": "MS", "cs": 2, "turns": 2}],
}

var open := true
var ship_key := "frigate"
var deck := "upper"
var turn := 7
var sail := "FS"
var tacking := false
var shrouds_severed := false
var wheel := false
var obscured := false
var s2_gone := false
var rigging_damaged := true
var hull_damaged := true
var fires: Array = [{"id": 1, "started": 6}]
var assignments: Dictionary = {}  # section -> station id or "ff:<fireId>"
var progress: Dictionary = {}  # section -> {task, done}
var auto: Dictionary = {}  # section -> true when filled in automatically
var sail_target := "MS"
var selected := ""
var pending: Dictionary = {}  # {sec, target} awaiting progress-loss confirmation
var next_fire_id := 2


func ship() -> Dictionary:
	return SHIPS[ship_key]


func sections() -> Array:
	var out: Array = []
	for id in ship()["crew"].keys():
		if id == "S2" and s2_gone:
			continue
		out.append(id)
	return out


static func is_marine(id: String) -> bool:
	return id == "M"


static func section_num(id: String) -> int:
	return 99 if is_marine(id) else int(id.substr(1))


func assigned(sec: String) -> String:
	return assignments.get(sec, "")


func defaults() -> void:
	assignments = {}
	progress = {}
	auto = {}
	for id in sections():
		assignments[id] = "marine_fire" if is_marine(id) else "guns"
	assignments["S3"] = "rr"
	progress["S3"] = {"task": "rr", "done": 2}
	auto_fire()


## A fire nobody fights gets the lowest free sailor section, marked "auto" (8.E.2 must be fought).
func auto_fire() -> void:
	for f in fires:
		var key := "ff:%d" % f["id"]
		if assignments.values().has(key):
			continue
		var free: Array = sections().filter(func(id): return not is_marine(id) and assigned(id) == "guns")
		free.sort_custom(func(a, b): return section_num(a) < section_num(b))
		if not free.is_empty():
			assignments[free[0]] = key
			auto[free[0]] = true


# ---------------- station rules ----------------

func station_visible(st: String) -> bool:
	match st:
		"braces": return tacking
		"rr": return rigging_damaged
		"rs": return shrouds_severed
		"rh": return hull_damaged
	return true


func station_disabled_reason(st: String) -> String:
	if st == "rr" and sail != "FS":
		return "Rigging can be repaired only at fighting sail, furled or dismasted (8.F.3a). You carry %s." % sail
	return ""


func station_decks(st: String) -> Array:
	var d = STATIONS[st]["decks"]
	return ship()["gun_decks"] if d is String else d


func occupants(target: String) -> Array:
	return sections().filter(func(id): return assigned(id) == target)


func capacity(target: String) -> int:
	if target.begins_with("ff:"):
		return 1
	if target == "sails":
		var ch := current_sail_change()
		return ch["cs"] if not ch.is_empty() else 2
	return STATIONS[target]["cap"]


func current_sail_change() -> Dictionary:
	var opts: Array = SAIL_CHANGES.get(sail, [])
	for c in opts:
		if c["to"] == sail_target:
			return c
	return opts[0] if not opts.is_empty() else {}


func fire_index(target: String) -> int:
	for i in fires.size():
		if "ff:%d" % fires[i]["id"] == target:
			return i
	return -1


func task_name(target: String) -> String:
	if target == "":
		return "Unassigned"
	if target.begins_with("ff:"):
		return "Fighting fire " + target.substr(3)
	if target == "sails":
		var ch := current_sail_change()
		return "Sail change to " + ch["to"] if not ch.is_empty() else "Sails"
	return STATIONS[target]["label"]


func task_turns(target: String) -> int:
	var sk: int = ship()["sk"]
	match target:
		"rr": return 6 + sk
		"rh": return 10 + sk
		"rs": return 5 + sk
		"sails":
			var ch := current_sail_change()
			return ch["turns"] if not ch.is_empty() else 1
	return 0


## Why `sec` cannot go to `target`, or "" when it can.
func refusal(sec: String, target: String) -> String:
	if target.begins_with("ff:"):
		var occ_f: Array = occupants(target).filter(func(x): return x != sec)
		if not occ_f.is_empty():
			return "Fire %s already has %s fighting it. One section per fire (8.E.2)." % [target.substr(3), occ_f[0]]
		return ""
	var st: Dictionary = STATIONS[target]
	if not station_visible(target):
		return st["label"] + " is not available now."
	var why := station_disabled_reason(target)
	if why != "":
		return why
	if st["accepts"] == "sailor" and is_marine(sec):
		return "Only sailor sections serve the guns. Marines fire muskets instead."
	if st["accepts"] == "marine" and not is_marine(sec):
		return "Only the marine section gives marine fire."
	var occ: Array = occupants(target).filter(func(x): return x != sec)
	var cap := capacity(target)
	if occ.size() >= cap:
		return "%s is full (%d section%s)." % [st["label"], cap, "s" if cap > 1 else ""]
	if target == "boarders" and not is_marine(sec):
		# Sections busy fighting a fire (mandatory, 8.E.2) are skipped; open question for the spec.
		var lower: Array = sections().filter(func(id): return not is_marine(id) and section_num(id) < section_num(sec) \
				and assigned(id) != "boarders" and not assigned(id).begins_with("ff:"))
		if not lower.is_empty():
			return "Boarders come from the lowest-numbered sailor sections first: send %s before %s (4.B.1)." % [lower[0], sec]
	return ""


## Returns true when the assignment happened (false on refusal or pending confirmation).
func assign(sec: String, target: String, confirmed := false) -> bool:
	if assigned(sec) == target:
		return false
	var why := refusal(sec, target)
	if why != "":
		selected = ""
		message_requested.emit(why, "bad", [])
		return false
	var prog: Dictionary = progress.get(sec, {})
	if not prog.is_empty() and prog["done"] > 0 and prog["task"] != target and not confirmed:
		pending = {"sec": sec, "target": target}
		message_requested.emit("%s has %d of %d turns on %s. Moving it loses them (4.A.3)." % [
				sec, prog["done"], task_turns(prog["task"]), task_name(prog["task"]).to_lower()], "warn",
				[{"label": "Move anyway", "primary": true, "id": "confirm_move"}, {"label": "Keep it there", "id": "cancel_move"}])
		return false
	if not prog.is_empty() and prog["task"] != target:
		progress.erase(sec)
	# An unfought fire left behind is filled again before submit (shown as "auto").
	assignments[sec] = target
	auto.erase(sec)
	if task_turns(target) > 0 and not progress.has(sec):
		progress[sec] = {"task": target, "done": 0}
	selected = ""
	message_requested.emit("", "clear", [])
	return true


func confirm_pending() -> void:
	var p := pending
	pending = {}
	if not p.is_empty():
		assign(p["sec"], p["target"], true)


func menu_targets() -> Array:
	var out: Array = []
	for f in fires:
		out.append("ff:%d" % f["id"])
	for st in STATIONS.keys():
		if station_visible(st):
			out.append(st)
	return out


func guns_crew() -> int:
	return sections().filter(func(id): return not is_marine(id) and assigned(id) == "guns").size()


# ---------------- prototype controls ----------------

func reset_defaults() -> void:
	defaults()
	assignments["S3"] = "guns"
	progress.erase("S3")
	auto_fire()


func set_ship(key: String) -> void:
	ship_key = key
	deck = "upper"
	defaults()


func set_sail(s: String) -> void:
	sail = s
	sail_target = SAIL_CHANGES[sail][0]["to"]
	for sec in occupants("rr"):
		if station_disabled_reason("rr") != "":
			assignments[sec] = "guns"
			progress.erase(sec)
			message_requested.emit("%s left rigging repair: it is not possible at %s (8.F.3a). Its progress is lost." % [sec, sail], "bad", [])


func set_sail_target(t: String) -> void:
	sail_target = t
	var occ := occupants("sails")
	for i in range(capacity("sails"), occ.size()):
		assignments[occ[i]] = "marine_fire" if is_marine(occ[i]) else "guns"


func set_tacking(on: bool) -> void:
	tacking = on
	if not on:
		for sec in occupants("braces"):
			assignments[sec] = "guns"


func set_shrouds(on: bool) -> void:
	shrouds_severed = on
	if not on:
		for sec in occupants("rs"):
			assignments[sec] = "guns"


func set_s2_gone(on: bool) -> void:
	s2_gone = on
	if on:
		var t := assigned("S2")
		assignments.erase("S2")
		progress.erase("S2")
		auto.erase("S2")
		auto_fire()
		message_requested.emit("S2 was wiped out. Its task (%s) is abandoned (4.B.3).%s" % [task_name(t).to_lower(),
				" The next free section was sent to the fire." if t.begins_with("ff:") else ""], "bad", [])
	else:
		assignments["S2"] = "guns"
		auto_fire()


func add_fire() -> void:
	fires.append({"id": next_fire_id, "started": turn})
	next_fire_id += 1
	auto_fire()


func remove_fire() -> void:
	if fires.is_empty():
		return
	var f: Dictionary = fires.pop_back()
	for sec in occupants("ff:%d" % f["id"]):
		assignments[sec] = "guns"
		auto.erase(sec)


func next_turn() -> void:
	turn += 1
	var done: Array = []
	for sec in progress.keys():
		var p: Dictionary = progress[sec]
		if assigned(sec) != p["task"]:
			continue
		p["done"] += 1
		if p["done"] >= task_turns(p["task"]):
			done.append("%s finished %s" % [sec, task_name(p["task"]).to_lower()])
			assignments[sec] = "guns"
			progress.erase(sec)
	auto.clear()
	message_requested.emit("Turn %d. Tasks in progress carried over%s." % [turn, ("; " + "; ".join(done)) if not done.is_empty() else ""], "warn", [])
