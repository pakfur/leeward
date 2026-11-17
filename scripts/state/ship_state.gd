class_name ShipState
extends Resource
## ShipState - Mutable game state for a ship (no visual components)
## This class is serializable and can run on both server and client
## Immutable identity/definition data lives in the Ship reference

## DESTROYED: blown up (hull critical #12). Out of play like a struck ship, and it also never
## drifts, fouls or takes damage; its two hexes stay on the map as a wreck that blocks movement
## and line of sight.
## CAPTURED: taken by boarding (10.H; boarding spec §2.5). Out of play for its holder (it never moves,
## fires or keeps a side alive) but, unlike a struck ship, a target for its old side (10.H.1).
enum Status { ACTIVE, STRUCK, DESTROYED, CAPTURED }

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
## Boarding crew-task codes (10.B-10.C): form boarders, boarders ready, boarders away, disband.
const BOARDING_CODES: Array[String] = ["FB", "BR", "BA", "BD"]
## Boarding tasks that put boarders aboard: the public counter (10.B.6), the marine-fire -1, 10.D.7.
const BOARDER_CODES: Array[String] = ["FB", "BR", "BA"]

# Ship reference (immutable identity + type definition)
var ship: Ship = null

# Convenience getters for immutable identity fields
var ship_id: String:
	get: return ship.ship_id if ship else ""
## The side that controls the ship: the captor once it is a prize (controller_side), else the owner.
## Every reader (selection, owner colour, gunnery sides, AI) follows control (boarding spec §2.5).
var side: int:
	get: return controller_side if controller_side >= 0 else (ship.side if ship else 0)
## The side the ship began the game with (Ship.side); victory points go by this (VI.B).
var original_side: int:
	get: return ship.side if ship else 0
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
## Ships grappled to this one (8.C; symmetric, any number; ShipStateController.add_grapple /
## remove_grapple). A pair may be fouled and grappled at once.
@export var grappled_with: Array[String] = []
## Ungrappling attempts this ship has made against each grappled partner: partner id -> count
## (8.C.4, the Unfouling table's g-t column). Dropped when the grapple goes.
@export var ungrapple_attempts: Dictionary = {}
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
## The side controlling the ship when it is not its original owner (a prize, 10.H.1); -1 = the owner.
@export var controller_side: int = -1
## The player commanding the ship (-1 = none yet); set at load, mutated via ShipStateController.set_commander.
@export var commander_id: int = -1
## Prize data while CAPTURED (10.G-H): {"captor_id": String, "original_crew": {"crew_count", "marine_count",
## "crew_quality", "morale_rating"}, "prize_crew_aboard": bool}. While a prize, the live crew fields are
## the prize crew's (empty until it is put aboard). {} otherwise.
@export var prize: Dictionary = {}
## Boxes this ship detached as prize crews, per section (S1-S4, M): emptied sections that only lost
## men to a prize crew do not count as destroyed for victory points (boarding spec §8 Q4).
@export var detached_boxes: Array[int] = [0, 0, 0, 0, 0]
## The navy sailing the ship (1.G.8: its BGN at ranges 11-15); "" = the ship type's nationality.
## From the scenario (per ship "navy", or per side "navies"); a prize takes its captor's.
@export var navy: String = ""
## The morale rating that fixes the ship's point value once a recapture (10.H.4) has set its MR to
## 6; -1 = the live morale rating (or the original crew's while a prize).
@export var value_morale_rating: int = -1
@export var guns_dismounted: Array[int] = [0, 0]  # per side: PORT, STARBOARD
@export var initial_broadside_fired: Array[bool] = [false, false]
@export var moved_this_turn: bool = false
@export var pending_morale_checks: int = 0
@export var morale_triggers_used: Array[String] = []
@export var unfoul_attempts: int = 0
## Taken off the map (8.G.1f "remove ships": an exploded ship at the end of the g-t). The ship stays
## in GameState.ships for logs, history and victory, but no map query sees it (is_on_map()).
@export var removed_from_map: bool = false

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
## The way the ship turned (PORT, STARBOARD) to come to WF=L, -1 when it is not at WF=L or got
## there without turning (wind shift). Turning back the other way is a reverse tack (5.D.3b).
@export var irons_entry_turn: int = -1

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
		# true once a movement plot was stored this turn (even an empty one: hold position); until
		# then the resolver gives the ship its 6.G.2 default course (DefaultCourse)
		"movement_plotted": false,
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

## Taken by boarding (10.H): a prize of the side in controller_side.
func is_captured() -> bool:
	return status == Status.CAPTURED

## May be fired on (gunfire and marine fire): in play, or a prize, which its old side may fire on
## (10.H.1). Struck and destroyed ships are not targets (feature_diff §4).
func is_targetable() -> bool:
	return status == Status.ACTIVE or status == Status.CAPTURED

## May be boarded (10.A.2-3, 10.G.5): in play, struck or a prize, and not on fire.
func can_be_boarded() -> bool:
	return (status == Status.ACTIVE or status == Status.STRUCK or status == Status.CAPTURED) \
		and not is_burning()

## The morale rating that fixes the ship's point value (VI.B): the original crew's while a prize,
## the one before a recapture after it (value_morale_rating), else the current one.
func original_morale_rating() -> int:
	if value_morale_rating >= 0:
		return value_morale_rating
	var crew: Dictionary = prize.get("original_crew", {})
	return int(crew.get("morale_rating", morale_rating))

## A prize whose prize crew is aboard (10.G.7).
func has_prize_crew() -> bool:
	return is_captured() and bool(prize.get("prize_crew_aboard", false))

## The live crew may be plotted to tasks: a ship in play, or a prize with its prize crew aboard
## (which may plot only boarding and repairs, 10.H.2).
func crew_can_act() -> bool:
	return status == Status.ACTIVE or has_prize_crew()

## Boxes of the prize's original crew locked below (10.H.3); 0 when not a prize.
func original_crew_boxes() -> int:
	var crew: Dictionary = prize.get("original_crew", {})
	var total := int(crew.get("marine_count", 0))
	for b in crew.get("crew_count", []):
		total += int(b)
	return total

## The original crew's sections below with boxes (S1-S4, M), each able to fight one fire (10.H.3).
func original_crew_sections() -> int:
	var crew: Dictionary = prize.get("original_crew", {})
	var n := 1 if int(crew.get("marine_count", 0)) > 0 else 0
	for b in crew.get("crew_count", []):
		if int(b) > 0:
			n += 1
	return n

## The navy whose BGN the ship uses at ranges 11-15 (1.G.8: the navy using the ship).
func gunnery_navy() -> String:
	if navy != "":
		return navy
	return ship.nationality if ship else ""

## 1.G.8: French BGN values at ranges 11-15 when the French navy sails the ship.
func is_french_gunned() -> bool:
	return gunnery_navy() == "French"

## On the map: holds its two hexes, blocks movement, drift, line of sight and wind. False once
## ShipStateController.remove_from_map has taken it off (8.G.1f).
func is_on_map() -> bool:
	return not removed_from_map

## The player commanding the ship: commander_id, or, for a ship given no commander (a game set up
## without a roster, as headless tests do), its side's default player, whose id is the side number
## (spec 2: without "players", one player per side).
func commanding_player() -> int:
	return commander_id if commander_id >= 0 else side


## Carries a fleet or squadron flag and is still in play.
func is_flagship() -> bool:
	return ship != null and ship.flag != "" and not is_out_of_play()


func is_fleet_flagship() -> bool:
	return ship != null and ship.flag == "fleet" and not is_out_of_play()


## Struck or destroyed: cannot move, fire, change sail, unfoul, fix or check morale, and is not a
## target. A struck ship still drifts; a destroyed one does not.
func is_out_of_play() -> bool:
	return status != Status.ACTIVE

## May try to grapple, ungrapple or unfoul (8.C, 8.D): a ship in play, or a prize with her prize crew
## aboard (10.H.2). A struck, destroyed or crewless captured ship may not.
func can_handle_lines() -> bool:
	return status == Status.ACTIVE or has_prize_crew()

## Grappled to at least one ship (8.C.7: cannot move or turn).
func is_grappled() -> bool:
	return not grappled_with.is_empty()

func is_grappled_to(other_id: String) -> bool:
	return grappled_with.has(other_id)

## Ships fouled or grappled to this one, sorted, each once (8.A.6 groups, 10.A.2 boarding links).
func linked_ids() -> Array[String]:
	var ids: Array[String] = []
	if fouled_with != "":
		ids.append(fouled_with)
	for other_id in grappled_with:
		if not ids.has(other_id):
			ids.append(other_id)
	ids.sort()
	return ids

## Fouled or grappled to another ship.
func is_linked() -> bool:
	return fouled_with != "" or is_grappled()

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

## The live boarding task (FB, BR, BA, BD) section i is on, or {}.
func boarding_task(i: int) -> Dictionary:
	var task := task_of(i)
	return task if BOARDING_CODES.has(str(task.get("code", ""))) else {}

## Section i is readied (10.B.3): it formed boarders on an earlier g-t and is now BR.
func is_readied(i: int) -> bool:
	return str(boarding_task(i).get("code", "")) == "BR"

## The boarding action section i is engaged in (10.E.1), or -1.
func boarding_action_of(i: int) -> int:
	var task := boarding_task(i)
	return int((task.get("params", {}) as Dictionary).get("action", -1)) if not task.is_empty() else -1

## The ship has boarders preparing or prepared: a live FB, BR or BA task (10.B.6; the public
## counter, the marine-fire -1, 10.D.7).
func has_boarders() -> bool:
	for code in BOARDER_CODES:
		if not tasks_with(code).is_empty():
			return true
	return false

## Sections on a boarding task aimed at, or engaged with, `enemy_id`, in section order.
func boarding_sections(enemy_id: String) -> Array[int]:
	var out: Array[int] = []
	for i in range(MARINES + 1):
		var params: Dictionary = boarding_task(i).get("params", {})
		if str(params.get("target", "")) == enemy_id or str(params.get("enemy", "")) == enemy_id:
			out.append(i)
	return out

## The marines are fighting in a boarding action, as attackers (BA) or engaged (8.C.5).
func marines_in_boarding() -> bool:
	var task := boarding_task(MARINES)
	return str(task.get("code", "")) == "BA" or boarding_action_of(MARINES) >= 0

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
	if row == "SAIL":  # no row recorded: the sail controller's choice (MS<->PS is the major change)
		row = SailController.cost_row(self, str(params.get("target", "")))
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
		"grappled_with": grappled_with.duplicate(),
		"ungrapple_attempts": ungrapple_attempts.duplicate(),
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
		"controller_side": controller_side,
		"commander_id": commander_id,
		"prize": prize.duplicate(true),
		"detached_boxes": detached_boxes.duplicate(),
		"navy": navy,
		"value_morale_rating": value_morale_rating,
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
		"removed_from_map": removed_from_map,
		"critical_effects": critical_effects.duplicate(true),
		"critical_seq": critical_seq,
		"rudder_destroyed": rudder_destroyed,
		"wheel_shot_away": wheel_shot_away,
		"fire_list": fire_list.duplicate(true),
		"fire_seq": fire_seq,
		"explosion_checks": explosion_checks,
		"pending_turn": pending_turn,
		"last_step_direction": last_step_direction,
		"irons_entry_turn": irons_entry_turn,
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
	state.grappled_with.clear()
	for other_id in data.get("grappled_with", []):
		state.grappled_with.append(str(other_id))
	state.ungrapple_attempts = {}
	var attempts: Dictionary = data.get("ungrapple_attempts", {})
	for other_id in attempts:
		state.ungrapple_attempts[str(other_id)] = int(attempts[other_id])
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
	state.controller_side = int(data.get("controller_side", data.get("controller_id", -1)))
	state.commander_id = int(data.get("commander_id", -1))
	state.prize = prize_from(data.get("prize", {}))
	state.detached_boxes = _int_array(data.get("detached_boxes", [0, 0, 0, 0, 0]))
	state.navy = str(data.get("navy", ""))
	state.value_morale_rating = int(data.get("value_morale_rating", -1))
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
	state.removed_from_map = bool(data.get("removed_from_map", false))
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
	state.irons_entry_turn = int(data.get("irons_entry_turn", -1))
	
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

## Copy of serialized prize data with its numbers as ints (JSON gives floats).
static func prize_from(data: Variant) -> Dictionary:
	if not data is Dictionary or (data as Dictionary).is_empty():
		return {}
	var copy: Dictionary = (data as Dictionary).duplicate(true)
	copy["captor_id"] = str(copy.get("captor_id", ""))
	copy["prize_crew_aboard"] = bool(copy.get("prize_crew_aboard", false))
	var crew: Dictionary = copy.get("original_crew", {})
	copy["original_crew"] = {
		"crew_count": _int_array(crew.get("crew_count", [0, 0, 0, 0])),
		"marine_count": int(crew.get("marine_count", 0)),
		"crew_quality": str(crew.get("crew_quality", "G")),
		"morale_rating": int(crew.get("morale_rating", 6)),
	}
	return copy

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
	navy = str(data.get("navy", ""))  # 1.G.8; GameController fills in the side's "navies" entry
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

## The standing boarding order (crew_orders.boarding): "", "ready", "board:<ship_id>" or "stand_down".
func boarding_order() -> String:
	var orders = plotted_actions.get("crew_orders", {})
	return str(orders.get("boarding", "")) if orders is Dictionary else ""
