class_name AnchorController
extends CrewTaskHandler
## AnchorController - the crew-task handler of the nine anchoring codes (Close Action 1997,
## 13.B-F, SoP V.A-B; anchoring spec §3-§5). One instance (game_state.anchor_controller) is
## registered for every AnchorRules.CODES code.
##
## - 13.B: preparing an anchor (PBA, PSA) makes it ready at the bow or stern; preparing springs
##   (PBS, PSS) makes them ready for the next anchoring, or rigs them at once on a ship already
##   anchored by that end (13.B.2). A preparation ends when its reason is gone: an anchor task once
##   the ship is anchored, a springs task once its end has no anchor (the cable cut, 13.F).
## - 13.C.1: an anchoring (A) on a g-t the ship moves is erased. The MPs are the ship's actual plot:
##   the stored course, or the default course (6.G.2) when none was stored (actual_steps).
## - Whether a task may start is AnchorRules.refusal, at End Planning (ctx "final").
##
## The anchoring step after drift (SoP V.A-B; spec §4), resolve_anchoring, in DRIFT_CALCULATION:
## - V.A, riding to the anchor: every ship on the map anchored before this g-t, not destroyed and not
##   aground, leeward first (DriftResolver.leeward_first), at wind speed above 0 (13.E.3). The facing
##   takes one 60-degree swing toward her proper facing (13.C.4, 13.C.6; a springs ship turns with the
##   wind and keeps her WF, 13.D.1), cable 0 becomes 1 (13.C.5), a VO begun this g-t adds 1 (13.E.1);
##   the ship moves to the footprint as one forced move (AnchorRules.forced_check). A ship in the way
##   rolls to foul and holds, land grounds her where she stands, the edge holds her (never off the
##   map), a fouled or grappled ship holds. A hold keeps her facing, the 13.C.5 settle (retried next
##   g-t) and a rolled swing direction; a VO is lost.
## - V.B, by ship id: a live A begun this g-t drops the ready anchor (drop, 13.C.2: after drift, so
##   she may have drifted first), a live AX begun this g-t cuts the cable (cut, 13.F.2).
##
## Dice order (game_state.dice; tests script dice by position), V.A per ship in leeward order:
##   1. only when she faces exactly away from her proper facing with no swing direction yet: the
##      swing d6 (1-3 port, 4-6 starboard)
##   2. then either the fouling d10 (DriftResolver.try_foul: a ship in the way, both free of fouling,
##      neither dismasted nor a wreck) or the depth d6 (a clear move whose bow enters a new shoal)
## V.B rolls nothing. At wind speed 0 V.A rolls nothing and moves nothing.

const ENDED_ANCHORED := "anchored"
const ENDED_NO_BOW := "no bow anchor"
const ENDED_NO_STERN := "no stern anchor"

## What holds an anchored ship's forced move (ANCHOR_MOVE `blocked`).
const BLOCKED_SHIP := "ship"
const BLOCKED_LAND := "land"
const BLOCKED_EDGE := "edge"
const BLOCKED_LINKED := "linked"


func _init(p_game_state: Node) -> void:
	super(p_game_state)


## The MPs the ship sails this g-t: its stored course when one was plotted, else its default course
## (6.G.2).
func actual_steps(ship: ShipState) -> int:
	if bool(ship.plotted_actions.get("movement_plotted", false)):
		return (ship.plotted_actions.get("movement", []) as Array).size()
	return DefaultCourse.for_ship(game_state, ship).size()


## The live task with `code` begun this g-t, or {}.
func live_this_turn(ship: ShipState, code: String) -> Dictionary:
	var turn := int(game_state.current_turn)
	for task in ship.tasks_with(code):
		if int(task.get("started_turn", -1)) == turn:
			return task
	return {}


func prepare(ship: ShipState, candidate: Dictionary) -> String:
	var ctx := CrewRules.context(game_state, ship)
	ctx["final"] = true
	ctx["plotted_mps"] = actual_steps(ship)
	var raw = candidate.get("params", {})
	var params: Dictionary = raw if raw is Dictionary else {}
	return AnchorRules.refusal(ship, str(candidate.get("code", "")), params, ctx, [])


func on_complete(ship: ShipState, task: Dictionary, phase: int) -> void:
	super(ship, task, phase)
	var sc: ShipStateController = game_state.ship_controller
	var id := ship.ship_id
	match str(task.get("code", "")):
		"PBA":
			sc.set_anchor_ready(id, "bow")
		"PSA":
			sc.set_anchor_ready(id, "stern")
		"PBS":
			_springs_done(ship, "bow")
		"PSS":
			_springs_done(ship, "stern")


func cancel_reason(ship: ShipState, task: Dictionary) -> String:
	var reason := super(ship, task)
	if reason != "":
		return reason
	match str(task.get("code", "")):
		"PBA", "PSA":
			if ship.is_anchored():
				return ENDED_ANCHORED
		"PBS":
			if not _has_anchor_at(ship, "bow"):
				return ENDED_NO_BOW
		"PSS":
			if not _has_anchor_at(ship, "stern"):
				return ENDED_NO_STERN
	return ""


## 13.B.2: springs rigged at once on a ship anchored by `end`, else ready for the next anchoring.
func _springs_done(ship: ShipState, end: String) -> void:
	var sc: ShipStateController = game_state.ship_controller
	if _anchored_by(ship, end):
		sc.update_anchor(ship.ship_id, {"springs": true})
	else:
		sc.set_springs_ready(ship.ship_id, true)


static func _anchored_by(ship: ShipState, end: String) -> bool:
	return ship.is_anchored() and str(ship.anchor.get("end", "bow")) == end


## An anchor ready or let go at `end`.
static func _has_anchor_at(ship: ShipState, end: String) -> bool:
	return ship.anchor_ready == end or _anchored_by(ship, end)


## SERVER ONLY: the anchoring step after drift (SoP V.A-B), in the order of the file header.
func resolve_anchoring(phase: int) -> void:
	if not is_server:
		push_error("AnchorController: Cannot resolve anchoring on client")
		return
	var env: EnvironmentState = game_state.environment
	var turn := int(game_state.current_turn)
	if env.wind_speed > 0:
		var riding: Array[ShipState] = []
		for ship in game_state.ships_on_map():
			if ship.is_anchored() and not ship.is_destroyed() and not ship.is_aground() \
					and int(ship.anchor.get("turn", 0)) < turn:
				riding.append(ship)
		var order: Array[ShipState] = game_state.drift_resolver.leeward_first(riding,
			AnchorRules.downwind(env.wind_direction))
		for ship in order:
			_ride(ship, phase)
	var ships: Array[ShipState] = game_state.ships_on_map()
	ships.sort_custom(func(a: ShipState, b: ShipState) -> bool: return a.ship_id < b.ship_id)
	for ship in ships:
		if ship.is_destroyed():
			continue
		if not ship.is_anchored() and not live_this_turn(ship, "A").is_empty():
			drop(ship.ship_id, phase)
		elif ship.is_anchored() and not live_this_turn(ship, "AX").is_empty():
			cut(ship.ship_id, phase)


## SERVER ONLY: the ship lets go her ready anchor where she lies (13.C.2), in the anchored end's
## hex, with no cable out yet; logs ANCHORED. False when she is already anchored. With no anchor
## ready (a Developer UI drop) she anchors by the bow.
func drop(ship_id: String, phase: int) -> bool:
	if not is_server:
		push_error("AnchorController: Cannot drop anchor on client")
		return false
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or ship.is_anchored():
		return false
	var end := ship.anchor_ready if ship.anchor_ready != "" else "bow"
	var hex := AnchorRules.drop_hex(ship)
	var springs := ship.springs_ready
	game_state.ship_controller.drop_anchor(ship_id, {"hex": hex, "end": end, "springs": springs,
		"cable": 0, "veered": 0, "swing_dir": 0, "wind_dir": int(game_state.environment.wind_direction),
		"turn": int(game_state.current_turn)})
	game_state.turn_log.add(PhaseEvents.Type.ANCHORED, phase, ship_id,
		{"end": end, "springs": springs, "hex": _hex_dict(hex)})
	Trace.trace_log("Anchor", "Ship %s anchors by the %s at %s" % [ship_id, end, str(hex)])
	return true


## SERVER ONLY: the ship cuts her cable (13.F.2): the anchor is lost and she may plot next g-t;
## logs CABLE_CUT. False when she is not anchored.
func cut(ship_id: String, phase: int) -> bool:
	if not is_server:
		push_error("AnchorController: Cannot cut cable on client")
		return false
	var ship: ShipState = game_state.get_ship(ship_id)
	if ship == null or not ship.is_anchored():
		return false
	var hex: Vector2i = ship.anchor.get("hex", ship.hex_position)
	game_state.ship_controller.cut_cable(ship_id, int(game_state.current_turn))
	game_state.turn_log.add(PhaseEvents.Type.CABLE_CUT, phase, ship_id, {"hex": _hex_dict(hex)})
	Trace.trace_log("Anchor", "Ship %s cuts her cable" % ship_id)
	return true


## V.A for one ship: swing, settle and veer out, then the forced move (or the hold).
func _ride(ship: ShipState, phase: int) -> void:
	var id := ship.ship_id
	var anchor := ship.anchor
	var wind_dir := int(game_state.environment.wind_direction)
	var end := str(anchor.get("end", "bow"))
	var laid_wind := int(anchor.get("wind_dir", wind_dir))
	var old_facing := ship.facing
	var swing_dir := int(anchor.get("swing_dir", 0))
	var roll := -1
	var causes: Array = []

	# 1. Facing.
	var facing := old_facing
	if ship.has_springs():
		# 13.D.1: the facing turns with the wind, the shorter way, so the WF is kept.
		facing = posmod(old_facing + ((wind_dir - laid_wind + 9) % 6) - 3, 6)
	else:
		var proper := AnchorRules.proper_facing(end, wind_dir)
		if AnchorRules.needs_swing_roll(old_facing, proper, swing_dir):
			roll = game_state.dice.d6()
		var step := AnchorRules.swing_step(old_facing, proper, swing_dir, roll)
		facing = int(step["facing"])
		swing_dir = int(step["swing_dir"])
		if facing != old_facing:
			causes.append("swing")

	# 2. Cable.
	var old_cable := int(anchor.get("cable", 0))
	var cable := old_cable
	var veered := int(anchor.get("veered", 0))
	if cable == 0:
		cable = 1
		causes.append("settle")
	if not live_this_turn(ship, "VO").is_empty():
		cable += 1
		veered += 1
		causes.append("veer_out")
	if wind_dir != laid_wind:
		causes.append("wind")

	# 3. Position.
	var sc: ShipStateController = game_state.ship_controller
	var old_hexes: Array[Vector2i] = ship.occupied_hexes()
	var new_hexes := AnchorRules.footprint(anchor.get("hex", ship.hex_position), end, cable, facing,
		wind_dir)
	if new_hexes == old_hexes:
		sc.update_anchor(id, {"cable": cable, "veered": veered, "swing_dir": swing_dir,
			"wind_dir": wind_dir})
		return
	if causes.is_empty():
		causes.append("settle")  # a 13.C.5 drift held last g-t, tried again

	var blocked := ""
	var blocker_id := ""
	var fouled: Variant = null
	var grounding := {}
	if ship.is_linked():
		blocked = BLOCKED_LINKED
	else:
		var others := Occupancy.build(game_state.ships_on_map(), [id])
		var check := AnchorRules.forced_check(game_state.active_scenario, old_hexes, new_hexes, others)
		match str(check["result"]):
			"clear":
				if check["shallow_bow"]:
					var area := TerrainMap.of(game_state.active_scenario).area_at(new_hexes[0])
					var depth: int = (area.base if area != null else 0) + game_state.dice.d6()
					if depth <= ship.ship.draft:
						blocked = BLOCKED_LAND
						grounding = _ground_data(ship, "shallow", new_hexes[0], depth)
			"ship":
				blocked = BLOCKED_SHIP
				blocker_id = str(check["blocker"])
				var blocker: ShipState = game_state.get_ship(blocker_id)
				if blocker != null:
					fouled = game_state.drift_resolver.try_foul(ship, blocker)
			"land":
				blocked = BLOCKED_LAND
				grounding = _ground_data(ship, "land", _first_land(new_hexes), -1)
			_:
				blocked = BLOCKED_EDGE

	game_state.turn_log.add(PhaseEvents.Type.ANCHOR_MOVE, phase, id, {
		"causes": causes, "from_facing": old_facing, "to_facing": facing, "roll": roll,
		"from": _hex_dict(old_hexes[0]), "to": _hex_dict(new_hexes[0]), "cable": cable,
		"blocked": blocked, "fouled": fouled,
	}, blocker_id)

	if blocked == "":
		sc.set_ship_position(id, new_hexes[0])
		sc.set_ship_facing(id, facing)
		sc.update_anchor(id, {"cable": cable, "veered": veered, "swing_dir": swing_dir,
			"wind_dir": wind_dir})
		return
	# The hold: facing, veered and wind_dir unchanged; the settle stands (retried next g-t), a VO
	# is lost, a rolled swing direction is kept.
	sc.update_anchor(id, {"cable": 1 if old_cable == 0 else old_cable, "swing_dir": swing_dir})
	if not grounding.is_empty():
		game_state.map_controller.ground(id, grounding, phase)


## The first of `hexes` that is land (the bow when none is).
func _first_land(hexes: Array[Vector2i]) -> Vector2i:
	var terrain := TerrainMap.of(game_state.active_scenario)
	for hex in hexes:
		if terrain.is_land(hex):
			return hex
	return hexes[0]


## AGROUND data for an anchored ship's forced move (`depth` -1 for land).
static func _ground_data(ship: ShipState, terrain: String, hex: Vector2i, depth: int) -> Dictionary:
	return {"cause": "anchor", "terrain": terrain, "hex": _hex_dict(hex), "depth": depth,
		"draft": ship.ship.draft}


static func _hex_dict(hex: Vector2i) -> Dictionary:
	return {"q": hex.x, "r": hex.y}
