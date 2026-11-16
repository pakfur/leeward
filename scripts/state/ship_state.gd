class_name ShipState
extends Resource
## ShipState - Mutable game state for a ship (no visual components)
## This class is serializable and can run on both server and client
## Immutable identity/definition data lives in the Ship reference

## DESTROYED: blown up (hull critical #12). Out of play like a struck ship, and it also never
## drifts, fouls or takes damage; its two hexes stay on the map as a wreck that blocks movement
## and line of sight.
enum Status { ACTIVE, STRUCK, DESTROYED }

const PORT := 0
const STARBOARD := 1
const SAIL_ORDER: Array[String] = ["NS", "FS", "MS", "PS"]
## max_turns_per_gt() when nothing limits turning
const UNLIMITED_TURNS := -1
## Lasting critical-hit effects kept in critical_effects (one-shot results leave no entry).
## crew_disorganized (hull #4) is not an effect: it is a forced RO crew task (is_disorganized).
const CRITICAL_EFFECT_IDS: Array[String] = [
	"signal_halyards_cut", "braces_cut", "lines_jammed", "broadside_obscured",
	"sheets_cut", "shrouds_severed", "rudder_jammed",
]
## rudder_jam_direction() when the rudder is not jammed
const RUDDER_NOT_JAMMED := -2
## 7.C.11: gunfire modifier per obscured broadside entry (Rigging #6, #10)
const OBSCURED_PENALTY := -2
## Crew sections (4.A.3): 0-3 are the sailor sections S1-S4, MARINES the marine section.
const SAILOR_SECTIONS := 4
const MARINES := 4
const SECTION_NAMES: Array[String] = ["S1", "S2", "S3", "S4", "M"]

# Ship reference (immutable identity + type definition)
var ship: Ship = null

# Convenience getters for immutable identity fields
var ship_id: String:
	get: return ship.ship_id if ship else ""
var player_id: int:
	get: return ship.player_id if ship else 0
var ship_name: String:
	get: return ship.ship_name if ship else "Unknown"
var ship_type: String:
	get: return ship.ship_type if ship else ""

# Position and movement (hex-based, deterministic)
@export var hex_position: Vector2i = Vector2i.ZERO
@export var facing: int = 0  # 0-5, hex direction
@export var speed: int = 0  # hexes per turn
@export var immobilized: bool = false  # ship cannot move
@export var tacking: bool = false # user has indicated they are tacking
@export var fouled_with: String = ""  # ship_id of fouled partner, empty if not fouled
@export var collision_this_turn: bool = false  # set during resolution, cleared at turn start
@export var movement_allowance: int = 0 # current turns movement points
@export var min_ma: int = 0 # current ma + any deceleration considerations
@export var max_ma: int = 0 # current speed + acceleration and ma considerations
@export var acceleration: int = 0 # current ships acceleration, negative value indicates deceleration

# Towing
@export var towing: bool = false

# Sail and rigging state
@export var sail_state: String = "MS"  # FS, MS, PS, NS
@export var rigging_current_hp: Array[int] = [0, 0, 0, 0]  # damage per section

# Hull state
@export var hull_current_hp: Array[int] = [0, 0, 0, 0]

# Crew
@export var morale_rating: int = 4  # 2-6 (higher is worse)
@export var crew_count: Array[int] = [0, 0, 0, 0] # boxes in each of the 4 sailor sections
@export var marine_count: int = 0 # number of "marines" 0-12
@export var crew_quality: String = "B" # A=Elite, B=Veteran, C-D=Trained, E=Green, F-G=Demoralized
@export var starting_crew_quality: String = "B" # crew quality when the game began; fixes the ship's victory-point value

# Combat and turn-loop state (mutated only through ShipStateController)
@export var status: Status = Status.ACTIVE
@export var guns_dismounted: Array[int] = [0, 0]  # per side: PORT, STARBOARD
@export var initial_broadside_fired: Array[bool] = [false, false]
@export var moved_this_turn: bool = false
@export var pending_morale_checks: int = 0
@export var morale_triggers_used: Array[String] = []
@export var unfoul_attempts: int = 0

# Critical hits (7.D.11-12; mutated only through ShipStateController)
## Each entry: {"seq": int, "id": String (CRITICAL_EFFECT_IDS), "turn": int,
## "side": int (-1 none; broadside_obscured: PORT/STARBOARD; rudder_jammed: -1 straight,
## 0 port, 1 starboard), "attempts": int (fix rolls so far),
## "expires_after_turn": int (-1 = no expiry)}
@export var critical_effects: Array[Dictionary] = []
@export var critical_seq: int = 0  # next seq; also makes crit morale triggers unique
@export var rudder_destroyed: bool = false  # log box, permanent (hull #2)
@export var wheel_shot_away: bool = false  # log box, permanent (hull #3)
## Fires burning aboard (8.E; mutated only through ShipStateController). Each:
## {"seq": int, "created_turn": int (g-t it broke out), "started_turn": int (first g-t it burns and
## does damage: created_turn for a Combat Phase fire, created_turn + 1 for one made in the Fire &
## Explosions sub-phase, crew-tasks spec 0.3 #5), "cause": "crit"|"spread"|"growth"|"debris"}.
@export var fire_list: Array[Dictionary] = []
@export var fire_seq: int = 0  # last fire seq given; seqs are never reused (morale triggers)
@export var explosion_checks: int = 0  # 8.E.8: explosion rolls made so far (each later one is -1)
## Steering (6.F.4, hull #2): a turn carried over to this g-t's first MP after a failed
## Poor Maneuvering roll (-1 none, PORT, STARBOARD); it succeeds without a roll.
@export var pending_turn: int = -1
## The last step the ship executed (-1 straight or none, PORT, STARBOARD); kept across a g-t
## in which it made no step. Rudder Jammed jams in this direction (spec Q15).
@export var last_step_direction: int = -1

# Crew tasks (4.A.3, 4.B; crew-tasks spec §2.2; mutated only through ShipStateController)
## Automatic crew allocation (spec §3.3): the server places the sections by CrewAuto's rules.
@export var crew_auto: bool = true
## Each: {"seq": int, "code": String ("SAIL", ...), "sections": Array[int], "done": int (g-t's
## completed), "started_turn": int, "params": Dictionary, "forced": bool,
## "marines_available": bool (the task leaves the marines available, 10.B.4-5),
## "ended": String ("" while live, else the reason; kept until the g-t ends)}.
## SAIL params: {"target": "MS", "from": "FS", "row": "SAIL_MINOR"}.
@export var crew_tasks: Array[Dictionary] = []
@export var task_seq: int = 0
## Sections plotted to a task this g-t: they do not serve the guns, even if the task ends early.
@export var plotted_sections: Array[int] = []
## MPs used this g-t: executed steps, turns included (8.F.3b, 8.C.1).
@export var mp_used_this_turn: int = 0
## Sections already checked once (8.F.5, 9.B.2): a repaired section lost again is not checked again.
@export var checked_sections: Dictionary = {"rigging": [false, false, false, false],
		"hull": [false, false, false, false]}

# Plotted actions for this turn. crew_assignments: {section:int -> {"code", "params"}} (absent =
# unplotted); crew_orders: the ship's orders to its crew ({"sail_target": ""}).
var plotted_actions: Dictionary = empty_plot()

static func empty_plot() -> Dictionary:
	return {
		"movement": [],  # Array of movement commands
		"crew_assignments": {},
		"crew_orders": {"sail_target": ""},
		# true once the crew plan was stored this turn; until then the plan is the carry-over
		# defaults (tasks in progress stay, CrewRules.plan_of)
		"crew_plotted": false,
		"gunnery": [],
	}

func _init() -> void:
	# Initialize arrays properly
	if rigging_current_hp.is_empty():
		rigging_current_hp = [0, 0, 0, 0]
	if hull_current_hp.is_empty():
		hull_current_hp = [0, 0, 0, 0]

## Stern hex, derived from the bow (`hex_position`) and facing.
func stern_hex() -> Vector2i:
	return HexGrid.stern_of(hex_position, facing)

## Hexes covered by the ship: [bow, stern].
func occupied_hexes() -> Array[Vector2i]:
	return [hex_position, stern_hex()]

## Hexes the ship covers, for the view (model length): every ship is two hexes, bow and stern
## (see occupied_hexes()).
func get_ship_size() -> int:
	return 2

func is_struck() -> bool:
	return status == Status.STRUCK

func is_destroyed() -> bool:
	return status == Status.DESTROYED

## Struck or destroyed: cannot move, fire, change sail, unfoul, fix or check morale, and is not a
## target. A struck ship still drifts; a destroyed one does not.
func is_out_of_play() -> bool:
	return status != Status.ACTIVE

func is_dismasted() -> bool:
	return rigging_level() == 0

func rigging_level() -> int:
	## Number of rigging sections with at least one box remaining (0-4)
	var level := 0
	for hp in rigging_current_hp:
		if hp > 0:
			level += 1
	return level

func max_sail_state() -> String:
	## Heaviest sail the remaining rigging can carry: 4 sections PS, 3 MS, 2-1 FS, 0 NS
	match rigging_level():
		4: return "PS"
		3: return "MS"
		0: return "NS"
		_: return "FS"

func movement_sail_state() -> String:
	## Sail state the movement table is read at: the lower of carried and max sail.
	## A ship carrying more sail than its rigging allows keeps sail_state unchanged.
	var carried := SAIL_ORDER.find(sail_state.to_upper())
	var limit := SAIL_ORDER.find(max_sail_state())
	return SAIL_ORDER[mini(carried, limit)] if carried >= 0 else "NS"

func total_crew_boxes() -> int:
	var total := marine_count
	for boxes in crew_count:
		total += boxes
	return total

func sections_able_to_fire() -> int:
	## Sailor sections that still have boxes and are not plotted to a task this g-t (4.B.4)
	var able := 0
	for i in range(mini(crew_count.size(), SAILOR_SECTIONS)):
		if crew_count[i] > 0 and not plotted_sections.has(i):
			able += 1
	return able

## Boxes left in crew section i (0-3 sailors, MARINES).
func section_boxes(i: int) -> int:
	if i == MARINES:
		return marine_count
	return crew_count[i] if i >= 0 and i < crew_count.size() else 0

func section_alive(i: int) -> bool:
	return section_boxes(i) > 0

## The live task (ended == "") section i is working on, or {}.
func task_of(i: int) -> Dictionary:
	for task in crew_tasks:
		if task.get("ended", "") == "" and (task.get("sections", []) as Array).has(i):
			return task
	return {}

## Live tasks with this code, in seq order.
func tasks_with(code: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task in crew_tasks:
		if task.get("ended", "") == "" and task.get("code", "") == code:
			result.append(task)
	return result

func task_by_seq(seq: int) -> Dictionary:
	for task in crew_tasks:
		if int(task.get("seq", -1)) == seq:
			return task
	return {}

## Section i is in a reorganization forced by Crew Disorganized (hull #4).
func is_disorganized(i: int) -> bool:
	var task := task_of(i)
	return task.get("code", "") == "RO" and (task.get("params", {}) as Dictionary).get("reason", "") == "crew_disorganized"

## The marines are plotted this g-t to a task that takes them away (any task but FB, BR, BD).
## A wiped-out marine section is not "busy" (spec §9 Q5): it gives no "marines not available" DRM.
func marines_busy() -> bool:
	if not plotted_sections.has(MARINES):
		return false
	for k in range(crew_tasks.size() - 1, -1, -1):
		var task: Dictionary = crew_tasks[k]
		if (task.get("sections", []) as Array).has(MARINES):
			return not bool(task.get("marines_available", false))
	return true

## The marines have boxes and are not busy (4.B.4b, 8.C.5).
func marines_available() -> bool:
	return section_alive(MARINES) and not marines_busy()

func fire_count() -> int:
	return fire_list.size()

func is_burning() -> bool:
	return not fire_list.is_empty()

## Seqs of the fires burning, in seq order.
func fire_seqs() -> Array[int]:
	var seqs: Array[int] = []
	for fire in fire_list:
		seqs.append(int(fire.get("seq", -1)))
	seqs.sort()
	return seqs

func fire_by_seq(seq: int) -> Dictionary:
	for fire in fire_list:
		if int(fire.get("seq", -1)) == seq:
			return fire
	return {}

## G-t's the fire has burned on g-t `turn`, counting its first (8.E.5); 0 before it starts.
func fire_age(seq: int, turn: int) -> int:
	var fire := fire_by_seq(seq)
	if fire.is_empty():
		return 0
	return maxi(0, turn - int(fire.get("started_turn", turn)) + 1)

## The live FF task fighting fire `seq`, or {}.
func fire_task(seq: int) -> Dictionary:
	for task in crew_tasks:
		if task.get("ended", "") == "" and task.get("code", "") == "FF" \
				and int((task.get("params", {}) as Dictionary).get("fire", -1)) == seq:
			return task
	return {}

## Sections at the braces (the live T task), 0-3.
func tack_sections() -> int:
	var tasks := tasks_with("T")
	return 0 if tasks.is_empty() else (tasks[0].get("sections", []) as Array).size()

## Boxes marked out of "rigging" or "hull" since the start.
func missing_boxes(kind: String) -> int:
	var start: Array = []
	var now: Array = rigging_current_hp if kind == "rigging" else hull_current_hp
	if ship:
		start = ship.rigging_hp if kind == "rigging" else ship.hull_hp
	var missing := 0
	for i in range(mini(start.size(), now.size())):
		missing += maxi(0, int(start[i]) - int(now[i]))
	return missing

## G-t's the task needs at the current crew quality (9.A.2: recomputed every g-t); -1 open-ended.
func task_turns_required(task: Dictionary) -> int:
	var params: Dictionary = task.get("params", {})
	var row: String = params.get("row", task.get("code", ""))
	if row == "SAIL":  # no row recorded: MS<->PS is the major change (ship log)
		row = "SAIL_MAJOR" if sail_state.to_upper() == "PS" or params.get("target", "") == "PS" else "SAIL_MINOR"
	return DataManager.combat_tables.task_turns(row, crew_quality)

## The sail change in progress in the old shape, for the views: {} or
## {"target": String, "turns_left": int, "sections": Array[int]}.
func sail_change_info() -> Dictionary:
	var tasks := tasks_with("SAIL")
	if tasks.is_empty():
		return {}
	var task: Dictionary = tasks[0]
	return {
		"target": (task.get("params", {}) as Dictionary).get("target", ""),
		"turns_left": maxi(0, task_turns_required(task) - int(task.get("done", 0))),
		"sections": (task.get("sections", []) as Array).duplicate(),
	}

func has_sail_change() -> bool:
	return not tasks_with("SAIL").is_empty()

## The sail state ordered this turn (plotted_actions crew_orders), or "".
func ordered_sail_target() -> String:
	var orders = plotted_actions.get("crew_orders", {})
	return str(orders.get("sail_target", "")) if orders is Dictionary else ""

func has_critical(id: String) -> bool:
	return critical_count(id) > 0

## Entries with this id; side -1 counts every side.
func critical_count(id: String, side: int = -1) -> int:
	var count := 0
	for effect in critical_effects:
		if effect.get("id") == id and (side == -1 or int(effect.get("side", -1)) == side):
			count += 1
	return count

## 7.C.11: -2 per broadside_obscured entry on that side (yard shot away adds one per side).
func obscured_penalty(side: int) -> int:
	return OBSCURED_PENALTY * critical_count("broadside_obscured", side)

## Sheets cut (rigging #7) acts on the g-t after the one it was inflicted on (`turn` is the
## current g-t; -1 counts every entry).
func sheets_cut_active(turn: int = -1) -> bool:
	for effect in critical_effects:
		if effect.get("id") == "sheets_cut" and (turn < 0 or int(effect.get("turn", -1)) < turn):
			return true
	return false

## MPs lost in every direction and sail state on g-t `turn`: sheets cut (at most one,
## rigging #7, see sheets_cut_active) plus each shrouds severed (rigging #9).
func critical_mp_loss(turn: int = -1) -> int:
	return (1 if sheets_cut_active(turn) else 0) + critical_count("shrouds_severed")

## Rigging sections with no boxes left (5.E.5, Tacking DRM).
func rigging_sections_lost() -> int:
	var lost := 0
	var max_hp: Array = ship.rigging_hp if ship else []
	for i in range(rigging_current_hp.size()):
		var section_max: int = int(max_hp[i]) if i < max_hp.size() else 1
		if section_max > 0 and rigging_current_hp[i] <= 0:
			lost += 1
	return lost

## Rudder Jammed direction (hull #2): RUDDER_NOT_JAMMED when not jammed (or the rudder is
## destroyed, which cancels it), else the entry's side: -1 straight (no turns), PORT or STARBOARD.
func rudder_jam_direction() -> int:
	if rudder_destroyed:
		return RUDDER_NOT_JAMMED
	for effect in critical_effects:
		if effect.get("id") == "rudder_jammed":
			return int(effect.get("side", -1))
	return RUDDER_NOT_JAMMED

## Rudder destroyed (hull #2) or wheel shot away (hull #3): Poor Maneuvering rule (6.F).
func is_poor_maneuvering() -> bool:
	return rudder_destroyed or wheel_shot_away

## 60-degree turns allowed per g-t: 1 when poor maneuvering, else UNLIMITED_TURNS.
func max_turns_per_gt() -> int:
	return 1 if is_poor_maneuvering() else UNLIMITED_TURNS

func serialize() -> Dictionary:
	"""Serialize state for network transmission or save/load"""
	var data = {
		"ship": ship.to_dict() if ship else {},
		"position": {"q": hex_position.x, "r": hex_position.y},
		"facing": facing,
		"speed": speed,
		"immobilized": immobilized,
		"tacking": tacking,
		"fouled_with": fouled_with,
		"collision_this_turn": collision_this_turn,
		"movement_allowance": movement_allowance,
		"min_ma": min_ma,
		"max_ma": max_ma,
		"towing": towing,
		"acceleration": acceleration,
		"sail_state": sail_state,
		"rigging_current_hp": rigging_current_hp,
		"hull_current_hp": hull_current_hp,
		"morale_rating": morale_rating,
		"crew_quality": crew_quality,
		"starting_crew_quality": starting_crew_quality,
		"crew_count": crew_count,
		"marine_count": marine_count,
		"status": int(status),
		"guns_dismounted": guns_dismounted,
		"initial_broadside_fired": initial_broadside_fired,
		"crew_auto": crew_auto,
		"crew_tasks": crew_tasks.duplicate(true),
		"task_seq": task_seq,
		"plotted_sections": plotted_sections.duplicate(),
		"mp_used_this_turn": mp_used_this_turn,
		"checked_sections": checked_sections.duplicate(true),
		"moved_this_turn": moved_this_turn,
		"pending_morale_checks": pending_morale_checks,
		"morale_triggers_used": morale_triggers_used,
		"unfoul_attempts": unfoul_attempts,
		"critical_effects": critical_effects.duplicate(true),
		"critical_seq": critical_seq,
		"rudder_destroyed": rudder_destroyed,
		"wheel_shot_away": wheel_shot_away,
		"fire_list": fire_list.duplicate(true),
		"fire_seq": fire_seq,
		"explosion_checks": explosion_checks,
		"pending_turn": pending_turn,
		"last_step_direction": last_step_direction,
		"plotted_actions": plotted_actions.duplicate(true)
	}
	return data

static func deserialize(data: Dictionary) -> ShipState:
	"""Deserialize state from network or save file"""
	var state = ShipState.new()

	# Reconstruct Ship from serialized data
	var ship_data = data.get("ship", {})
	if not ship_data.is_empty():
		state.ship = Ship.from_dict(ship_data)
	else:
		push_error("Missing 'ship' key during ShipState deserialization")

	var pos = data.get("position", {"q": 0, "r": 0})
	state.hex_position = Vector2i(pos.q, pos.r)

	state.facing = data.get("facing", 0)
	state.speed = data.get("speed", 0)
	state.movement_allowance = data.get("movement_allowance", 0)
	state.immobilized = data.get("immobilized", false)
	state.tacking = data.get("tacking", false)
	state.fouled_with = data.get("fouled_with", "")
	state.collision_this_turn = data.get("collision_this_turn", false)
	state.min_ma = int(data.get("min_ma", 0))
	state.max_ma = int(data.get("max_ma", 0))
	state.towing = bool(data.get("towing", false))
	state.acceleration = data.get("acceleration", 0)
	state.sail_state = data.get("sail_state", "MS")

	# Load rigging HP
	var rigging_hp_data = data.get("rigging_current_hp", [0, 0, 0, 0])
	state.rigging_current_hp.clear()
	for hp in rigging_hp_data:
		state.rigging_current_hp.append(int(hp))

	# Load hull HP
	var hull_hp_data = data.get("hull_current_hp", [0, 0, 0, 0])
	state.hull_current_hp.clear()
	for hp in hull_hp_data:
		state.hull_current_hp.append(int(hp))

	state.morale_rating = int(data.get("morale_rating", data.get("crew_morale", 4)))
	state.crew_quality = data.get("crew_quality", "B")
	state.starting_crew_quality = data.get("starting_crew_quality", state.crew_quality)
	var crew_count_data = data.get("crew_count", [0, 0, 0, 0])
	state.crew_count.clear()
	for ct in crew_count_data:
		state.crew_count.append(int(ct))
	state.marine_count = data.get("marine_count", 0)
	state.status = int(data.get("status", Status.ACTIVE)) as Status
	state.guns_dismounted = _int_array(data.get("guns_dismounted", [0, 0]))
	state.initial_broadside_fired.clear()
	for fired in data.get("initial_broadside_fired", [false, false]):
		state.initial_broadside_fired.append(bool(fired))
	state.crew_auto = bool(data.get("crew_auto", true))
	state.crew_tasks.clear()
	for task in data.get("crew_tasks", []):
		state.crew_tasks.append(crew_task_from(task))
	state.task_seq = int(data.get("task_seq", 0))
	state.plotted_sections = _int_array(data.get("plotted_sections", []))
	state.mp_used_this_turn = int(data.get("mp_used_this_turn", 0))
	var checked: Dictionary = data.get("checked_sections", {})
	for kind in ["rigging", "hull"]:
		if checked.has(kind):
			var flags: Array = []
			for flag in checked[kind]:
				flags.append(bool(flag))
			state.checked_sections[kind] = flags
	# Saves from before crew tasks: a sail change in progress becomes a SAIL task.
	var old_change: Dictionary = data.get("sail_change", {})
	if not old_change.is_empty() and state.tasks_with("SAIL").is_empty():
		state.crew_tasks.append(_sail_task_from_old(state, old_change))
	state.moved_this_turn = data.get("moved_this_turn", false)
	state.pending_morale_checks = int(data.get("pending_morale_checks", 0))
	state.morale_triggers_used.clear()
	for trigger in data.get("morale_triggers_used", []):
		state.morale_triggers_used.append(str(trigger))
	state.unfoul_attempts = int(data.get("unfoul_attempts", 0))
	state.critical_effects.clear()
	for effect in data.get("critical_effects", []):
		state.critical_effects.append(_critical_effect_from(effect))
	state.critical_seq = int(data.get("critical_seq", 0))
	state.rudder_destroyed = bool(data.get("rudder_destroyed", false))
	state.wheel_shot_away = bool(data.get("wheel_shot_away", false))
	state.fire_list.clear()
	for fire in data.get("fire_list", []):
		state.fire_list.append(_fire_from(fire))
	state.fire_seq = int(data.get("fire_seq", 0))
	# Saves from before fire was simulated: "fires": n becomes n fires burning since g-t 0.
	if not data.has("fire_list"):
		for i in range(int(data.get("fires", 0))):
			state.fire_seq += 1  # SCV:ALLOW deserialization builds a fresh state
			state.fire_list.append({"seq": state.fire_seq, "created_turn": 0, "started_turn": 0, "cause": "crit"})
	state.explosion_checks = int(data.get("explosion_checks", 0))
	state.pending_turn = int(data.get("pending_turn", -1))
	state.last_step_direction = int(data.get("last_step_direction", -1))
	
	state.plotted_actions = plot_from(data.get("plotted_actions", {}))

	return state

## A plot dictionary from serialized data: crew_assignments keys back to int (JSON gives
## strings), an old "sail_change" order moved into crew_orders, missing keys filled in.
static func plot_from(data: Dictionary) -> Dictionary:
	var plot := empty_plot()
	for key in data:
		if key in ["sail_change", "boarding", "repairs"]:
			continue
		plot[key] = data[key].duplicate(true) if (data[key] is Dictionary or data[key] is Array) else data[key]
	var assignments := {}
	for section in plot.get("crew_assignments", {}):
		assignments[int(section)] = (plot["crew_assignments"][section] as Dictionary).duplicate(true)
	plot["crew_assignments"] = assignments
	if not plot.get("crew_orders") is Dictionary:
		plot["crew_orders"] = {"sail_target": ""}
	if not plot["crew_orders"].has("sail_target"):
		plot["crew_orders"]["sail_target"] = ""
	if str(data.get("sail_change", "")) != "" and plot["crew_orders"]["sail_target"] == "":
		plot["crew_orders"]["sail_target"] = str(data["sail_change"])
	return plot

## Copy of a serialized crew task with its numeric fields as ints.
static func crew_task_from(task: Dictionary) -> Dictionary:
	var copy := task.duplicate(true)
	for key in ["seq", "done", "started_turn"]:
		copy[key] = int(copy.get(key, 0))
	copy["sections"] = _int_array(copy.get("sections", []))
	copy["params"] = copy.get("params", {})
	copy["forced"] = bool(copy.get("forced", false))
	copy["marines_available"] = bool(copy.get("marines_available", false))
	copy["ended"] = str(copy.get("ended", ""))
	return copy

## An old-format sail_change {target, turns_left, sections} as a SAIL task (done is inferred from
## turns_left at the ship's crew quality).
static func _sail_task_from_old(state: ShipState, change: Dictionary) -> Dictionary:
	var target := str(change.get("target", ""))
	var major := state.sail_state.to_upper() == "PS" or target == "PS"
	var row := "SAIL_MAJOR" if major else "SAIL_MINOR"
	var needed: int = DataManager.combat_tables.task_turns(row, state.crew_quality)
	state.task_seq += 1  # SCV:ALLOW deserialization builds a fresh state
	return crew_task_from({
		"seq": state.task_seq, "code": "SAIL", "sections": change.get("sections", []),
		"done": maxi(0, needed - int(change.get("turns_left", needed))), "started_turn": 0,
		"params": {"target": target, "from": state.sail_state, "row": row},
		"forced": false, "marines_available": false, "ended": "",
	})

## Copy of a serialized fire with its numeric fields as ints.
static func _fire_from(fire: Dictionary) -> Dictionary:
	var copy := fire.duplicate(true)
	for key in ["seq", "created_turn", "started_turn"]:
		copy[key] = int(copy.get(key, 0))
	copy["cause"] = str(copy.get("cause", "crit"))
	return copy

## Copy of a serialized effect with its numeric fields as ints (JSON round trips give floats).
static func _critical_effect_from(effect: Dictionary) -> Dictionary:
	var copy := effect.duplicate(true)
	for key in ["seq", "turn", "side", "attempts", "expires_after_turn"]:
		if copy.has(key):
			copy[key] = int(copy[key])
	return copy

static func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for v in values:
		result.append(int(v))
	return result

func initialize_from_scenario(data: Dictionary, ship_ref: Ship) -> void:
	## One-time setup during game init. Not a runtime mutation.  SCV:ALLOW
	ship = ship_ref

	# Position and movement
	hex_position = Vector2i(data.get("position", {}).get("q", 0), data.get("position", {}).get("r", 0))
	facing = data.get("facing", 0)
	speed = data.get("speed", data.get("current_speed", 0))  # Support both "speed" and legacy "current_speed"
	movement_allowance = data.get("movement_allowance", 0)
	acceleration = data.get("acceleration", 0)

	# Sail state
	sail_state = data.get("sail_state", "MS")

	# Rigging HP - from scenario or copy from ship definition
	var rigging_hp_scenario = data.get("rigging_current_hp", null)
	rigging_current_hp.clear()
	if rigging_hp_scenario != null:
		for hp in rigging_hp_scenario:
			rigging_current_hp.append(int(hp))
	elif ship_ref:
		for hp in ship_ref.rigging_hp:
			rigging_current_hp.append(hp)
	else:
		rigging_current_hp = [0, 0, 0, 0]

	# Hull HP - from scenario or copy from ship definition
	var hull_hp_scenario = data.get("hull_current_hp", null)
	hull_current_hp.clear()
	if hull_hp_scenario != null:
		for hp in hull_hp_scenario:
			hull_current_hp.append(int(hp))
	elif ship_ref:
		for hp in ship_ref.hull_hp:
			hull_current_hp.append(hp)
	else:
		hull_current_hp = [0, 0, 0, 0]

	# Crew - counts come from the ship definition; quality and morale from the scenario
	morale_rating = int(data.get("morale_rating", data.get("crew_morale", 4)))
	crew_quality = DataManager._normalize_crew_quality(str(data.get("crew_quality", "B")))
	starting_crew_quality = crew_quality
	crew_count.clear()
	marine_count = 0
	if ship_ref:
		for boxes in ship_ref.crew_count:
			crew_count.append(boxes)
		marine_count = ship_ref.marine_count
	else:
		crew_count = [0, 0, 0, 0]

	Trace.trace_log("ShipState", "Initialized: %s (%s) at %s facing %d, speed %d" % [ship_name, ship_type, hex_position, facing, speed])

func _clear_turn_flags() -> void:
	collision_this_turn = false

func _clear_plot() -> void:
	plotted_actions = empty_plot()
