class_name StubAI
extends RefCounted
## StubAI - Drives the plotting protocol for non-player ships
## Uses the real MovementPlottingController so all AI plots are rule-validated.
##
## Strategies (a ship's strategy is its standing order, GameState.order_of; strategy_override wins):
##   "engage"    — steer toward the ordered target (engage <ship>) or else the nearest enemy,
##                 presenting a broadside when close (default, and the fallback of every order)
##   "close"     — hold within the ordered range of the nearest enemy: close it from beyond,
##                 fight as engage inside it, never opening the range
##   "follow"    — sail for the hex astern of the leader's stern, never into another ship's hexes
##   "line"      — follow the ship listed before this one in the order's group (GameState.groups);
##                 the first follows the fleet flagship, the flagship engages; no group: the flagship
##   "disengage" — open the range from the nearest enemy
##   "escape"    — a ship whose side may escape this turn, under the scenario's "escape" posture
##                 (`ai`) or a disengage order: declares escape and runs for a permitted escape edge
##   "anchor"    — a ship that wants to anchor (wants_to_anchor: an ANCHOR signal, or drift danger)
##                 holds (an empty plot carried to the deceleration minimum) until she may let go
##   "forward"   — move straight ahead, consuming all available MA (tests)
##   "hold"      — submit immediately with empty path (tests)
## Every course is carried on to the deceleration limit (_meet_deceleration_minimum). Every strategy
## keeps to safe water while it can (_move_safe): no crossing the ship may not make, no land, no hex
## where it may ground. A course of at most 2 steps into shallow water casts the lead (_maybe_cast_lead).
##
## Anchors (anchoring spec §11): the crew's anchor order (anchor_order) rides at anchor, rigs springs
## and hauls to bear (haul_choice), cuts on CUT CABLES or when a signalled move order finds no enemy
## within range; an unanchored ship told ANCHOR, or in drift danger, prepares an anchor and lets go.
##
## Fire: each ship fires each broadside at its best-odds target, splitting a side between two
## targets when no full broadside bears (see choose_fire_orders); a ship ordered to engage a ship
## fires at her first when she can; its marines fire at the adjacent enemy with the best modified
## die (choose_marine_orders).

## A broadside shot at or inside this range scores as a firing position.
const FIRING_RANGE := 5
const FIRING_POSITION_BASE := 1000
## A firing position loses this much per hex of range.
const FIRING_RANGE_WEIGHT := 2
## Added to a firing position's score when its second battery bears too: worth more than one hex of
## range, less than two (two batteries at range r beat one at r or r-1, lose to one at r-2).
const SECOND_BATTERY_BONUS := 3
## Taken off a close position beyond the ordered range: more than any engage score within range 15.
const CLOSE_OUTSIDE_PENALTY := 100
## An escaping ship's score for a bow off the map (across a permitted escape edge).
const ESCAPE_EXIT_SCORE := 10000
## Escape: a heading into the wind (WF "L", in irons, 5.D.5) is worth this many hexes of distance
## to the escape edge less than any other, so the ship never luffs to save a step.
const ESCAPE_LUFF_PENALTY := 50

## Plotting errors for ships that legitimately cannot move; the AI skips them without error.
const LOCKED_ERROR_CODES := ["SHIP_FOULED", "SHIP_GRAPPLED", "SHIP_CAPTURED", "SHIP_STRUCK", "SHIP_DESTROYED", "SHIP_DISMASTED", "SHIP_AGROUND", "SHIP_ANCHORED", "SHIP_OFF_MAP"]
## Submission refusals after which the ship is replotted with a plain course.
const REPLOT_ERROR_CODES := ["RUDDER_JAMMED", "TOO_SLOW", "CANNOT_SUBMIT"]
## The most moves added to reach the deceleration limit (more than any movement allowance).
const MAX_PADDING_STEPS := 20
## Standing orders that send an anchored ship under way when no enemy is within range (spec §11).
const MOVE_ORDERS: Array[String] = ["engage", "close", "follow", "line", "disengage"]
## Drift danger looks this many hexes downwind (spec §11).
const DRIFT_DANGER_HEXES := 4

var game_state: Node = null
var _request_counter: int = 0
## When non-empty, forces this strategy for every AI ship (used by tests).
var strategy_override: String = ""
## Submissions refused during the last plot_all_ai_ships, as {ship_id, error} (diagnostics; a refused
## course is replotted plain).
var refusals: Array = []


func _init(p_game_state: Node = null) -> void:
	game_state = p_game_state if p_game_state else GameState


func plot_all_ai_ships() -> void:
	if not game_state.is_server:
		push_error("StubAI: Must only run on server")
		return
	var controller: MovementPlottingController = game_state.movement_plotting_controller
	if not controller:
		push_error("StubAI: No movement_plotting_controller on game_state")
		return
	refusals = []

	var ai_ships := _get_ai_ships()
	Trace.trace_log("StubAI", "plot_all_ai_ships: %d AI ships" % ai_ships.size())

	for ship_state in ai_ships:
		var strategy := _get_strategy(ship_state)
		_plot_ship(ship_state, controller, strategy)
	assign_crew()


## The AI's crew orders (crew-tasks spec §3.3). It gives the orders only (no sail changes today)
## and leaves Automatic on, so CrewAuto places its sections by the same rules as the player's.
func assign_crew() -> void:
	if not game_state.is_server:
		push_error("StubAI: Must only run on server")
		return
	var sc: ShipStateController = game_state.ship_controller
	for ship_state in _get_ai_ships():
		if ship_state.is_destroyed():
			continue
		if not ship_state.crew_auto:
			sc.set_crew_auto(ship_state.ship_id, true)
		sc.set_crew_orders(ship_state.ship_id, {"sail_target": "", "boarding": boarding_order(ship_state),
			"anchor": anchor_order(ship_state)})


## The AI's anchor order (anchoring spec §11), one of AnchorRules.ORDERS, placed by rule A2c.
## Anchored: "cut" on CUT CABLES, or when a signalled move order finds no enemy in play within
## FireRules.MAX_RANGE, but never while she cannot make way at any heading or her lee is dangerous
## (downwind_danger: cutting would only put her back in drift danger); else "prepare_springs" while
## springs may be prepared; else, with springs, the haul (haul_choice). Not anchored and wanting to
## (wants_to_anchor): "anchor" with an anchor ready, else "prepare_bow" when it may be prepared and
## no anchor is being prepared. Otherwise "".
func anchor_order(ship_state: ShipState) -> String:
	if ship_state.is_out_of_play() or not ship_state.crew_can_act():
		return ""
	if ship_state.is_anchored():
		var signalled := str(ship_state.standing_order.get("order", ""))
		if (signalled == "cut" or (MOVE_ORDERS.has(signalled) and not _enemy_within(ship_state, FireRules.MAX_RANGE))) \
				and _can_make_way(ship_state) and not downwind_danger(ship_state):
			return "cut"
		var springs_code := str(AnchorRules.order_task(ship_state, "prepare_springs")["code"])
		if ship_state.tasks_with("PBS").is_empty() and ship_state.tasks_with("PSS").is_empty() \
				and AnchorRules.refusal(ship_state, springs_code, {}, {}, []) == "":
			return "prepare_springs"
		if ship_state.has_springs():
			return haul_choice(ship_state)
		return ""
	if wants_to_anchor(ship_state):
		if ship_state.anchor_ready != "":
			return "anchor"
		if ship_state.tasks_with("PBA").is_empty() and ship_state.tasks_with("PSA").is_empty() \
				and AnchorRules.refusal(ship_state, "PBA", {}, {}, []) == "":
			return "prepare_bow"
	return ""


## The ship wants to anchor (spec §11): not anchored, the scenario allows anchoring at her drop hex,
## fewer than two anchorings used, and an ANCHOR standing order or drift danger.
func wants_to_anchor(ship_state: ShipState) -> bool:
	if ship_state.is_out_of_play() or not ship_state.crew_can_act():
		return false
	if ship_state.is_anchored() or ship_state.anchorings_used >= AnchorRules.MAX_ANCHORINGS:
		return false
	if not AnchorRules.permitted(game_state.active_scenario, AnchorRules.drop_hex(ship_state)):
		return false
	return str(ship_state.standing_order.get("order", "")) == "anchor" or drift_danger(ship_state)


## Drift danger (spec §11): on the map, neither anchored nor aground, unable to make way (dismasted,
## or no movement allowance at her facing), and shifting her footprint downwind one hex at a time,
## up to DRIFT_DANGER_HEXES times, she meets danger (downwind_danger).
func drift_danger(ship_state: ShipState) -> bool:
	if not ship_state.is_on_map() or ship_state.is_anchored() or ship_state.is_aground():
		return false
	if not ship_state.is_dismasted() \
			and game_state.ship_controller.get_movement_allowance(ship_state.ship_id) != 0:
		return false
	return downwind_danger(ship_state)


## The downwind scan of drift danger, whatever the ship's state: shifting her footprint downwind one
## hex at a time, up to DRIFT_DANGER_HEXES times, she meets a `none` crossing (LOST), land or a hex
## that always grounds her bow before any crossing that holds her (BLOCKED, an `open` edge; an
## ESCAPE crossing counts the same, ruling F9). A shift with a LOST crossing is danger even when
## another of its crossings holds.
func downwind_danger(ship_state: ShipState) -> bool:
	var scenario: Dictionary = game_state.active_scenario
	var terrain := TerrainMap.of(scenario)
	var wind_dir: int = game_state.environment.wind_direction if game_state.environment else 0
	var step: Vector2i = HexGrid.DIRECTIONS[AnchorRules.downwind(wind_dir)]
	var hexes := ship_state.occupied_hexes()
	for _i in range(DRIFT_DANGER_HEXES):
		var shifted: Array[Vector2i] = []
		for h in hexes:
			shifted.append(h + step)
		var held := false
		for k in hexes.size():
			var outcome := str(MapRules.crossing_outcome(scenario, ship_state, hexes[k], shifted[k],
				game_state.current_turn)["outcome"])
			if outcome == MapRules.LOST:
				return true
			if outcome == MapRules.BLOCKED or outcome == MapRules.ESCAPE:
				held = true
		if held:
			return false
		for k in shifted.size():
			if not hexes.has(shifted[k]) and terrain.is_land(shifted[k]):
				return true
		if terrain.in_bounds(shifted[0]) and terrain.grounds(shifted[0], ship_state.ship.draft) == "always":
			return true
		hexes = shifted
	return false


## The spring haul of an anchored ship (spec §11): "", "turn_starboard" or "turn_port". Of no turn,
## starboard and port (that order breaks ties), the one whose footprint brings the most batteries of
## one side to bear on her target (the ordered engage target while an enemy in play, else the
## nearest enemy) within FireRules.MAX_RANGE; a turn counts only when the crew may handle the
## springs for it (AnchorRules.refusal "HS") and its swing is clear (AnchorRules.forced_check).
func haul_choice(ship_state: ShipState) -> String:
	var target_id := str(game_state.order_of(ship_state.ship_id).get("target", ""))
	var target: ShipState = game_state.get_ship(target_id) if target_id != "" else null
	if target == null or target.side == ship_state.side or target.is_out_of_play():
		target = _nearest_enemy(ship_state)
	if target == null:
		return ""
	var here := ship_state.occupied_hexes()
	var r: int = game_state.fire_geometry.range_between(here, target.occupied_hexes())
	if r < 0 or r > FireRules.MAX_RANGE:
		return ""
	var occupied := _occupied_except(ship_state, target)
	var friendly := _friendly_footprints(ship_state)
	var ships: Array[ShipState] = []
	ships.assign(game_state.get_all_ships())
	var others := Occupancy.build(ships, [ship_state.ship_id])
	var ctx := CrewRules.context(game_state, ship_state)
	var best := ""
	var best_score := _bearing_batteries(here, ship_state.facing, target.occupied_hexes(), occupied, friendly)
	for choice in [["turn_starboard", 1], ["turn_port", -1]]:
		var side_name := "starboard" if int(choice[1]) > 0 else "port"
		if AnchorRules.refusal(ship_state, "HS", {"turn": side_name}, ctx, []) != "":
			continue
		var turn := AnchorRules.spring_turn(ship_state, int(choice[1]))
		var hexes: Array[Vector2i] = []
		hexes.assign(turn["hexes"])
		if str(AnchorRules.forced_check(game_state.active_scenario, here, hexes, others)["result"]) != "clear":
			continue
		var score := _bearing_batteries(hexes, int(turn["facing"]), target.occupied_hexes(), occupied, friendly)
		if score > best_score:
			best = str(choice[0])
			best_score = score
	return best


## The ship could make way at some heading: not dismasted, and a movement allowance above 0 at
## one facing at least (a bow-anchored ship lies head to wind, MA 0 at her own facing).
func _can_make_way(ship_state: ShipState) -> bool:
	if ship_state.is_dismasted():
		return false
	for f in range(6):
		if game_state.ship_controller.get_movement_allowance(ship_state.ship_id, f) > 0:
			return true
	return false


## An enemy in play on the map lies within `max_range` of the ship (footprint to footprint).
func _enemy_within(ship_state: ShipState, max_range: int) -> bool:
	for other: ShipState in game_state.get_all_ships():
		if other.side == ship_state.side or other.is_out_of_play() or not other.is_on_map():
			continue
		var r: int = game_state.fire_geometry.range_between(ship_state.occupied_hexes(), other.occupied_hexes())
		if r >= 0 and r <= max_range:
			return true
	return false


## The AI's boarding order (boarding spec §3.6), placed by rule A2b: "board:<id>" at an enemy linked
## at the start of the g-t that it would board (struck, or its readied boarders' TBCF against the
## enemy's visible defence gives at least +1 after the class DRM, i.e. 3:2 for an equal class);
## "ready" while linked to an enemy or alongside one that has boarders; else "" (readied sections
## stand down; the spec's two-g-t wait is not kept).
func boarding_order(ship_state: ShipState) -> String:
	if ship_state.is_out_of_play():
		return ""
	var linked: Array = game_state.linked_at_plot.get(ship_state.ship_id, [])
	var readied: Array[int] = []
	for s in range(ShipState.MARINES + 1):
		if ship_state.is_readied(s) and s != BoardingRules.MINIMUM_CREW_SECTION:
			readied.append(s)
	var ids := linked.duplicate()
	ids.sort()
	var any_enemy_linked := false
	for other_id in ids:
		var other: ShipState = game_state.get_ship(str(other_id))
		if other == null or other.side == ship_state.side:
			continue
		any_enemy_linked = true
		if BoardingRules.boardable_error(ship_state, other, linked) != "":
			continue
		if other.is_struck() and not readied.is_empty():
			return "board:%s" % other.ship_id
		if not readied.is_empty() and _odds_favour(ship_state, readied.slice(0, 2), other):
			return "board:%s" % other.ship_id
	if any_enemy_linked:
		return "ready"
	var grappling = game_state.get("grappling_controller")
	for other: ShipState in game_state.get_all_ships():
		if other.side != ship_state.side and not other.is_out_of_play() and other.has_boarders() \
				and grappling != null and grappling.adjacent(ship_state, other):
			return "ready"
	return ""


## Prize-crew sizes (10.G.6; boarding spec §3.6) for the won actions of the players `player_ids`
## that offer a choice: the minimum, plus one if another enemy ship in play is within 3 hexes of
## the prize. {action_id: size}.
func prize_sizes(player_ids: Array[int]) -> Dictionary:
	var out := {}
	var boarding = game_state.get("boarding_controller")
	if boarding == null:
		return out
	for player_id in player_ids:
		for option in boarding.prize_size_options(player_id):
			var prize: ShipState = game_state.get_ship(str(option["prize_id"]))
			var size := int(option["minimum"])
			for other: ShipState in game_state.get_all_ships():
				# The prize is under her captor's side: an enemy is a ship of another side.
				if other.ship_id == prize.ship_id or other.side == prize.side or other.is_out_of_play():
					continue
				var r: int = game_state.fire_geometry.range_between(prize.occupied_hexes(), other.occupied_hexes())
				if r >= 0 and r <= 3:
					size += 1
					break
			out[int(option["action_id"])] = mini(size, int(option["maximum"]))
	return out


## The odds of `sections` of the ship against the enemy's visible defence (its boarders and marines)
## give at least +1 after the class DRM (boarding spec §3.6).
func _odds_favour(ship_state: ShipState, sections: Array, enemy: ShipState) -> bool:
	var boarding: BoardingController = game_state.boarding_controller
	var p := boarding.preview(ship_state.ship_id, enemy.ship_id, sections)
	return int(p["tbcf"]) > 0 and int(p["drm"]) >= 1


## Whether the ship would board `enemy` with what it would send (the marines and its lowest sailor
## section): an enemy that has struck, or odds of at least +1 after the class DRM (boarding spec §3.6).
func would_board(ship_state: ShipState, enemy: ShipState) -> bool:
	if enemy == null or enemy.side == ship_state.side:
		return false
	if enemy.is_struck():
		return true
	var goers: Array = []
	if ship_state.section_alive(ShipState.MARINES):
		goers.append(ShipState.MARINES)
	for k in range(BoardingRules.MINIMUM_CREW_SECTION):
		if ship_state.section_alive(k):
			goers.append(k)
			break
	return _odds_favour(ship_state, goers, enemy)


## Grapple orders (8.C.1) for the ships of `sides`, as [ship_id, target_id] pairs: every
## eligible enemy that has struck, or whose crew is at most two thirds of this ship's in boarding
## combat factors (boarding spec §3.6). Never a friendly ship.
func grapple_orders(player_ids: Array[int]) -> Array:
	var grappling: GrapplingController = game_state.grappling_controller
	var orders: Array = []
	for ship_state in _ships_of(player_ids):
		if ship_state.is_captured():
			continue  # a prize never grapples (it may, 10.H.2, but the AI does not)
		for target_id in grappling.grapple_options(ship_state.ship_id):
			if _wants_grapple(ship_state, game_state.get_ship(target_id)):
				orders.append([ship_state.ship_id, target_id])
	return orders


## Ungrapple orders (8.C.4) for the ships of the players `player_ids`: every grapple to a ship it
## would neither board nor grapple (a friendly ship, or an enemy it would not take on).
func ungrapple_orders(player_ids: Array[int]) -> Array:
	var grappling: GrapplingController = game_state.grappling_controller
	var orders: Array = []
	for ship_state in _ships_of(player_ids):
		for partner_id in grappling.ungrapple_options(ship_state.ship_id):
			var partner: ShipState = game_state.get_ship(partner_id)
			# Spec §9: a prize never grapples and cuts every grapple it may.
			# Boarding spec §3.6: keep a grapple to an enemy it would board or grapple; never cut
			# loose from a struck enemy; cut every other (friends included).
			if partner != null and not ship_state.is_captured() and partner.side != ship_state.side \
					and (partner.is_struck() or would_board(ship_state, partner) or _wants_grapple(ship_state, partner)):
				continue
			orders.append([ship_state.ship_id, partner_id])
	return orders


## The AI's grappling rule (boarding spec §3.6): an enemy that has struck, or whose crew's boarding
## combat factors are at most two thirds of this ship's.
func _wants_grapple(ship_state: ShipState, other: ShipState) -> bool:
	if other == null or other.side == ship_state.side:
		return false
	if other.is_struck():
		return true
	return crew_strength(other) * 3 <= crew_strength(ship_state) * 2


## A ship's whole crew in boarding combat factors (10.D.1 BCFs at its current CQ).
static func crew_strength(ship_state: ShipState) -> int:
	var tables: CombatTables = DataManager.combat_tables
	var sailors := 0
	for boxes in ship_state.crew_count:
		sailors += int(boxes)
	return sailors * tables.bcf(ship_state.crew_quality, false) \
		+ ship_state.marine_count * tables.bcf(ship_state.crew_quality, true)


## The ships commanded by the players `player_ids`, by ship_id.
func _ships_of(player_ids: Array[int]) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for ship_state in game_state.get_all_ships():
		if player_ids.has(game_state.commander_of(ship_state.ship_id)):
			out.append(ship_state)
	out.sort_custom(func(a: ShipState, b: ShipState) -> bool: return a.ship_id < b.ship_id)
	return out


## A potential collision (6.D) for a ship the AI decides for. It always tries to bear off when a turn
## is legal (it never rams on purpose) and turns the way whose new bow lies farther from the ship in
## its way; on a tie, starboard. Deterministic, no dice.
static func bear_off_choice(situation: MovementTypes.BearOffSituation, blocker_hexes: Array) -> String:
	if situation.eligible.is_empty():
		return MovementTypes.BEAR_OFF_COLLIDE
	var best: String = situation.eligible[0]
	var best_distance: int = -1
	for choice in [MovementTypes.BEAR_OFF_STARBOARD, MovementTypes.BEAR_OFF_PORT]:
		if not choice in situation.eligible:
			continue
		var facing: int = (situation.facing + 1) % 6 if choice == MovementTypes.BEAR_OFF_STARBOARD \
				else (situation.facing + 5) % 6
		var ahead: Vector2i = situation.bow + HexGrid.DIRECTIONS[facing]
		var distance: int = 1 << 30
		for h in blocker_hexes:
			distance = mini(distance, _axial_distance(ahead, h))
		if distance > best_distance:
			best_distance = distance
			best = choice
	return best


static func _axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	@warning_ignore("integer_division")
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


## Declare fire for every AI player, each for the ships it commands.
func submit_fire_orders() -> void:
	if not game_state.is_server:
		push_error("StubAI: Must only run on server")
		return
	for player_id in ai_player_ids():
		var reason: String = game_state.phase_controller.player_submit_fire_orders(player_id,
			choose_fire_orders(player_id), choose_marine_orders(player_id))
		if reason != "":
			push_error("StubAI: fire orders rejected: %s" % reason)


## FireOrder dictionaries for every AI ship; roundshot. Each side offers: hold; its best shot (the
## highest-mgn full broadside, ties nearest then target_id, or when no full broadside bears the best
## single battery); and, when no full broadside bears and its bow and stern batteries' best targets
## differ, a split side (bow at one, stern at the other, 7.B.1). Of the combinations of the two
## sides' offers that name at most two targets (7.A.4) and, when they name two, leave every shot
## mgn >= 1 under the two-target penalty, the ship fires the one with the most shots, then the
## highest total mgn (FireRules + preview_orders), then the nearest, then by target_id. A ship
## ordered to engage a ship (spec 7) puts a combination that fires at her before all of these; its
## sides offer their best shot at her too.
func choose_fire_orders(player_id: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var calculator: GunneryCalculator = game_state.gunnery_calculator
	for ship_state in _get_ai_ships(player_id):
		var shots := calculator.eligible_shots(ship_state.ship_id)
		var ordered := str(game_state.order_of(ship_state.ship_id).get("target", ""))
		var offers: Array = []
		for side in GunneryCalculator.SIDES:
			offers.append(_side_offers(shots, side, ordered))
		var best: Dictionary = {}
		for port_offer in offers[0]:
			for starboard_offer in offers[1]:
				var orders: Array[GunneryTypes.FireOrder] = []
				orders.append_array(port_offer)
				orders.append_array(starboard_offer)
				var candidate := _evaluate_orders(calculator, orders)
				if not candidate.is_empty():
					candidate["ordered"] = ordered != "" and ordered in candidate["targets"].split(",")
				if not candidate.is_empty() and (best.is_empty() or _candidate_beats(candidate, best)):
					best = candidate
		if not best.is_empty():
			for order in best["orders"]:
				result.append(order.to_dict())
	return result


## Marine fire orders ({ship_id, target_id}) for every AI ship whose marines may fire (7.G, boarding
## spec §3.6): the adjacent enemy with the best modified die (lowest DRM total); ties: one that has
## boarders preparing or prepared, then the lower ship_id. A shot that cannot mark out a box on any
## roll is not fired.
func choose_marine_orders(player_id: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var marines: MarineFireResolver = game_state.get("marine_fire_resolver")
	if marines == null:
		return result
	for ship_state in _get_ai_ships(player_id):
		var best: Dictionary = {}
		for shot in marines.eligible_marine_shots(ship_state.ship_id):
			if int(shot["hit_max"]) <= 0:
				continue
			if best.is_empty() or _marine_shot_beats(shot, best):
				best = shot
		if not best.is_empty():
			result.append({"ship_id": ship_state.ship_id, "target_id": str(best["target_id"])})
	return result


func _marine_shot_beats(a: Dictionary, b: Dictionary) -> bool:
	if int(a["modifier"]) != int(b["modifier"]):
		return int(a["modifier"]) < int(b["modifier"])
	var boarders_a := MarineFireResolver.has_boarders(game_state.get_ship(str(a["target_id"])))
	var boarders_b := MarineFireResolver.has_boarders(game_state.get_ship(str(b["target_id"])))
	if boarders_a != boarders_b:
		return boarders_a
	return str(a["target_id"]) < str(b["target_id"])


## The order sets one side may fire: [] (hold), its best shot, the split side when it has one, and
## its best shot at the `ordered` target when that is not already the best shot.
func _side_offers(shots: Array[GunneryTypes.ShotPreview], side: int, ordered: String = "") -> Array:
	var offers: Array = [[] as Array[GunneryTypes.FireOrder]]
	var best: GunneryTypes.ShotPreview = null
	var best_ordered: GunneryTypes.ShotPreview = null
	var best_by_battery := {}
	for shot in shots:
		if shot.order.side != side:
			continue
		# A full broadside before any half broadside (FireRules.battery_rank), then mgn.
		if best == null or _preferred(shot, best):
			best = shot
		if ordered != "" and shot.order.target_id == ordered \
				and (best_ordered == null or _preferred(shot, best_ordered)):
			best_ordered = shot
		var battery := shot.order.battery
		if not best_by_battery.has(battery) or _shot_beats(shot, best_by_battery[battery]):
			best_by_battery[battery] = shot
	if best == null:
		return offers
	offers.append([best.order] as Array[GunneryTypes.FireOrder])
	if best_ordered != null and best_ordered != best:
		offers.append([best_ordered.order] as Array[GunneryTypes.FireOrder])
	if best.order.battery == GunneryTypes.BATTERY_FULL:
		return offers
	var bow: GunneryTypes.ShotPreview = best_by_battery.get(GunneryTypes.BATTERY_BOW)
	var stern: GunneryTypes.ShotPreview = best_by_battery.get(GunneryTypes.BATTERY_STERN)
	if bow != null and stern != null and bow.order.target_id != stern.order.target_id:
		offers.append([bow.order, stern.order] as Array[GunneryTypes.FireOrder])
	return offers


## {orders, shots, mgn, range, targets} for a legal, worthwhile order set, else {}.
func _evaluate_orders(calculator: GunneryCalculator, orders: Array[GunneryTypes.FireOrder]) -> Dictionary:
	if orders.is_empty() or FireRules.declaration_error(orders) != "":
		return {}
	var two_targets := FireRules.target_count(orders[0].ship_id, orders) > 1
	var total_mgn := 0
	var nearest := FireRules.MAX_RANGE + 1
	var targets: Array[String] = []
	for p in calculator.preview_orders(orders):
		if not p.can_fire or (two_targets and p.mgn < 1):
			return {}
		total_mgn += p.mgn
		nearest = mini(nearest, p.range_hexes)
		targets.append(p.order.target_id)
	return {"orders": orders, "shots": orders.size(), "mgn": total_mgn, "range": nearest,
		"targets": ",".join(targets)}


func _candidate_beats(a: Dictionary, b: Dictionary) -> bool:
	if a.get("ordered", false) != b.get("ordered", false):
		return a.get("ordered", false)
	for key in ["shots", "mgn"]:
		if a[key] != b[key]:
			return a[key] > b[key]
	if a["range"] != b["range"]:
		return a["range"] < b["range"]
	return a["targets"] < b["targets"]


func _preferred(a: GunneryTypes.ShotPreview, b: GunneryTypes.ShotPreview) -> bool:
	var rank_a := FireRules.battery_rank(a.order.battery)
	var rank_b := FireRules.battery_rank(b.order.battery)
	if rank_a != rank_b:
		return rank_a < rank_b
	return _shot_beats(a, b)


func _shot_beats(a: GunneryTypes.ShotPreview, b: GunneryTypes.ShotPreview) -> bool:
	if a.mgn != b.mgn:
		return a.mgn > b.mgn
	if a.range_hexes != b.range_hexes:
		return a.range_hexes < b.range_hexes
	return a.order.target_id < b.order.target_id


## The players the stub plays, ascending: the roster's AI players (PlayerState.is_ai); in a game
## set up without a roster (headless), every player but player 0.
func ai_player_ids() -> Array[int]:
	var out: Array[int] = []
	for id in game_state.player_ids():
		var player = game_state.get_player(id)
		if (player.is_ai if player != null else id != 0):
			out.append(id)
	return out


## The ships of the AI players (or of the one AI player `player_id`, when given).
func _get_ai_ships(player_id: int = -1) -> Array[ShipState]:
	var ai := ai_player_ids() if player_id < 0 else ([player_id] as Array[int])
	var result: Array[ShipState] = []
	for ship_state in game_state.get_all_ships():
		if ai.has(game_state.commander_of(ship_state.ship_id)):
			result.append(ship_state)
	return result


## The ship's strategy: strategy_override when set (tests), else "escape" under an escape posture
## (_escape_posture), else "anchor" when she wants to anchor (wants_to_anchor), else its standing
## order's (spec 7).
func _get_strategy(ship_state: ShipState) -> String:
	if strategy_override != "":
		return strategy_override
	if _escape_posture(ship_state):
		return "escape"
	if wants_to_anchor(ship_state):
		return "anchor"
	var order := str(game_state.order_of(ship_state.ship_id).get("order", "engage"))
	# CUT CABLES under way, or ANCHOR where she may not anchor, is engage (spec §11).
	if order == "cut" or order == "anchor":
		return "engage"
	return order


## The ship escapes (map and scenario spec §12): its side may declare escape this turn, and the
## scenario's `ai` posture for its side is "escape" or its standing order is disengage.
func _escape_posture(ship_state: ShipState) -> bool:
	var scenario: Dictionary = game_state.active_scenario
	if not MapRules.may_declare(scenario, ship_state.side, game_state.current_turn):
		return false
	var postures = scenario.get("ai", {})
	if postures is Dictionary and str(postures.get(str(ship_state.side), "")) == "escape":
		return true
	return str(game_state.order_of(ship_state.ship_id).get("order", "")) == "disengage"


func _plot_ship(ship_state: ShipState, controller: MovementPlottingController, strategy: String) -> void:
	var ship_id := ship_state.ship_id
	var player_id: int = game_state.commander_of(ship_id)

	# An escaping ship declares before plotting, so the validator offers the escape edge (V.D). A
	# ship that cannot move declares nothing; the AI never withdraws a declaration.
	if strategy == "escape" and not ship_state.escape_declared and DefaultCourse.can_plot(ship_state):
		var refused: String = game_state.phase_controller.player_declare_escape(player_id, ship_id, true)
		if refused != "":
			Trace.trace_log("StubAI", "escape declaration refused", {"ship_id": ship_id, "reason": refused})

	var start_response := controller.handle_start_plotting(player_id, ship_id, _next_request_id())

	if start_response is MovementTypes.PlottingErrorResponse:
		var err := start_response as MovementTypes.PlottingErrorResponse
		if err.error_code in LOCKED_ERROR_CODES:
			Trace.trace_log("StubAI", "ship cannot move, skipped", {"ship_id": ship_id, "reason": err.error_code})
			return
		push_error("StubAI: start_plotting failed for %s: %s" % [ship_id, err.message])
		Trace.trace_log("StubAI", "start_plotting FAILED", {"ship_id": ship_id, "error": err.error_code})
		return

	var started := start_response as MovementTypes.PlottingStartedResponse
	var session_id := started.session_id
	var version := started.session_version

	match strategy:
		"engage":
			version = _strategy_engage(ship_state, controller, session_id, version, started)
		"close":
			version = _strategy_close(ship_state, controller, session_id, version, started)
		"follow":
			version = _strategy_follow(ship_state, controller, session_id, version, started)
		"line":
			version = _strategy_line(ship_state, controller, session_id, version, started)
		"disengage":
			version = _strategy_disengage(ship_state, controller, session_id, version, started)
		"escape":
			version = _strategy_escape(ship_state, controller, session_id, version, started)
		"forward":
			version = _strategy_forward(ship_state, controller, session_id, version, started)
		"hold", "anchor":
			pass

	# 5.E.4: a course that stops short of the deceleration limit is carried on until it meets it.
	# A ship keeping station on a leader pads with moves that stay out of the other ships' hexes.
	# Every ship pads with safe moves (_move_safe) while it has one.
	var avoid := {}
	if strategy in ["follow", "line"]:
		var ships: Array[ShipState] = []
		ships.assign(game_state.get_all_ships())
		avoid = Occupancy.build(ships, [ship_id])
	version = _meet_deceleration_minimum(ship_id, controller, session_id, version, avoid)
	var submit_response := controller.handle_submit_movement(session_id, version, _next_request_id())
	if submit_response is MovementTypes.PlottingErrorResponse:
		refusals.append({"ship_id": ship_id,
			"error": (submit_response as MovementTypes.PlottingErrorResponse).error_code})

	if submit_response is MovementTypes.PlottingErrorResponse \
			and (submit_response as MovementTypes.PlottingErrorResponse).error_code in REPLOT_ERROR_CODES:
		# The course found cannot be submitted (a jammed rudder it never turned for, hull #2): start
		# again with a plain course, straight ahead to the deceleration limit.
		Trace.trace_log("StubAI", "course refused, replotting", {"ship_id": ship_id,
			"error": (submit_response as MovementTypes.PlottingErrorResponse).error_code})
		controller.handle_cancel_plotting(session_id, _next_request_id())
		var restart := controller.handle_start_plotting(player_id, ship_id, _next_request_id())
		if restart is MovementTypes.PlottingStartedResponse:
			var again := restart as MovementTypes.PlottingStartedResponse
			var again_version := _meet_deceleration_minimum(ship_id, controller, again.session_id,
				again.session_version)
			submit_response = controller.handle_submit_movement(again.session_id, again_version,
				_next_request_id())
			if submit_response is MovementTypes.PlottingErrorResponse:
				# Nothing legal to submit: leave the ship unplotted (its default course, 6.G.2).
				Trace.trace_log("StubAI", "no legal course, left unplotted", {"ship_id": ship_id})
				controller.handle_cancel_plotting(again.session_id, _next_request_id())
				return

	if submit_response is MovementTypes.PlottingErrorResponse:
		var err := submit_response as MovementTypes.PlottingErrorResponse
		push_error("StubAI: submit failed for %s: %s" % [ship_id, err.message])
		Trace.trace_log("StubAI", "submit FAILED", {"ship_id": ship_id, "error": err.error_code})
		return

	_maybe_cast_lead(ship_state)
	Trace.trace_log("StubAI", "plotted ship", {
		"ship_id": ship_id,
		"strategy": strategy,
		"steps": ship_state.plotted_actions.get("movement", []).size()
	})


## Extends the session's course with moves ahead (else the first move offered) while it cannot be
## submitted for being short of the deceleration limit (5.E.4). It first takes a move ahead, then
## any move, that is safe (_move_safe) and keeps bow and stern out of `avoid` (hex -> ship id), and
## only when there is none the plain choice. Returns the session version.
func _meet_deceleration_minimum(ship_id: String, controller: MovementPlottingController,
		session_id: String, version: int, avoid: Dictionary = {}) -> int:
	var validator := MovementValidator.new(game_state)
	var ship: ShipState = game_state.get_ship(ship_id)
	for _i in range(MAX_PADDING_STEPS):
		var session := controller.get_session_for_ship(ship_id)
		if session == null or validator.deceleration_shortfall(ship, session.plotted_path) <= 0:
			break
		var valid := session.valid_next_hexes
		if valid == null or not valid.has_any_moves():
			break
		var move: MovementTypes.ValidMove = valid.forward[0] if not valid.forward.is_empty() \
				else valid.get_all_valid_moves()[0]
		var here := ship.hex_position
		if not session.plotted_path.is_empty():
			here = session.plotted_path[session.plotted_path.size() - 1].hex
		var clear := _clear_move(ship, valid.forward, here, avoid)
		if clear == null:
			clear = _clear_move(ship, valid.get_all_valid_moves(), here, avoid)
		if clear != null:
			move = clear
		var response := controller.handle_select_hex(session_id, version, move.hex, _next_request_id())
		if response is MovementTypes.PlottingErrorResponse:
			break
		version = (response as MovementTypes.HexSelectedResponse).session_version
	return version


func _strategy_forward(
	_ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	var current_valid := started.valid_next_hexes
	var current_version := version

	while current_valid and not current_valid.forward.is_empty():
		var forward_move: MovementTypes.ValidMove = current_valid.forward[0]
		var target_hex := forward_move.hex

		var response := controller.handle_select_hex(session_id, current_version, target_hex, _next_request_id())

		if response is MovementTypes.PlottingErrorResponse:
			break

		var selected := response as MovementTypes.HexSelectedResponse
		current_version = selected.session_version
		current_valid = selected.valid_next_hexes

	return current_version


func _strategy_engage(
	ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	var enemy := _engage_enemy(ship_state)
	if enemy == null:
		return version  # nothing to engage: submit the session with an empty path
	var occupied := _occupied_except(ship_state, enemy)
	var friendly := _friendly_footprints(ship_state)
	var score := func(bow: Vector2i, facing: int) -> int:
		return _score_position(bow, facing, enemy, occupied, friendly)
	return _steer(ship_state, controller, session_id, version, started, score, true, false)


## Hold within the ordered range n of the nearest enemy (spec 7, _score_close): beyond n, close it;
## within n, fight as engage does, never opening the range past where it started.
func _strategy_close(
	ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	var enemy := _nearest_enemy(ship_state)
	if enemy == null:
		return version
	var want := clampi(int(game_state.order_of(ship_state.ship_id).get("range", FIRING_RANGE)), 1,
		FireRules.MAX_RANGE)
	var start_range: int = game_state.fire_geometry.range_between(ship_state.occupied_hexes(),
		enemy.occupied_hexes())
	var limit := mini(want, start_range)
	var occupied := _occupied_except(ship_state, enemy)
	var friendly := _friendly_footprints(ship_state)
	var score := func(bow: Vector2i, facing: int) -> int:
		return _score_close(bow, facing, enemy, limit, occupied, friendly)
	return _steer(ship_state, controller, session_id, version, started, score, true, false)


## Sails for the hex astern of the leader's stern (_score_follow), never putting bow or stern into
## another ship's hexes. No leader in play: engage.
func _strategy_follow(
	ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	var leader_id := str(game_state.order_of(ship_state.ship_id).get("leader", ""))
	return _follow_leader(ship_state, leader_id, controller, session_id, version, started)


## Follows the ship before this one in the order's group (_line_leader); the first ship and a ship
## with no group follow the fleet flagship; the flagship (or a line with no flagship) engages.
func _strategy_line(
	ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	return _follow_leader(ship_state, _line_leader(ship_state), controller, session_id, version, started)


## Opens the range from the nearest enemy with every move it has (_score_disengage).
func _strategy_disengage(
	ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	var enemy := _nearest_enemy(ship_state)
	if enemy == null:
		return version
	var score := func(bow: Vector2i, facing: int) -> int:
		return _score_disengage(bow, facing, enemy)
	return _steer(ship_state, controller, session_id, version, started, score, false, false)


## Runs for the nearest permitted escape edge (_score_escape), using every move it has.
func _strategy_escape(
	ship_state: ShipState,
	controller: MovementPlottingController,
	session_id: String,
	version: int,
	started: MovementTypes.PlottingStartedResponse
) -> int:
	var score := func(bow: Vector2i, facing: int) -> int:
		return _score_escape(bow, facing, ship_state)
	return _steer(ship_state, controller, session_id, version, started, score, false, false, true)


func _follow_leader(ship_state: ShipState, leader_id: String, controller: MovementPlottingController,
		session_id: String, version: int, started: MovementTypes.PlottingStartedResponse) -> int:
	var leader: ShipState = game_state.get_ship(leader_id) if leader_id != "" else null
	if leader == null or leader == ship_state or leader.is_out_of_play() or not leader.is_on_map():
		return _strategy_engage(ship_state, controller, session_id, version, started)
	var score := func(bow: Vector2i, facing: int) -> int:
		return _score_follow(bow, facing, leader)
	return _steer(ship_state, controller, session_id, version, started, score, true, true)


## The ship a "line" order follows: the nearest ship in play listed before this one in the order's
## group of its side (GameState.groups); else the side's fleet flagship; "" for the flagship itself
## or when the side has none (the ship then engages).
func _line_leader(ship_state: ShipState) -> String:
	var group := str(game_state.order_of(ship_state.ship_id).get("group", ""))
	var members: Array = game_state.groups.get(ship_state.side, {}).get(group, []) if group != "" else []
	var index := members.find(ship_state.ship_id)
	for i in range(index - 1, -1, -1):
		var other: ShipState = game_state.get_ship(str(members[i]))
		if other != null and not other.is_out_of_play() and other.is_on_map():
			return other.ship_id
	if ship_state.is_fleet_flagship():
		return ""
	for other in game_state.get_all_ships():
		if other.side == ship_state.side and other.is_fleet_flagship() and other.is_on_map():
			return other.ship_id
	return ""


## The enemy an engaging ship steers for: the ordered target (engage <ship>) while she is an enemy
## in play on the map, else the nearest enemy.
func _engage_enemy(ship_state: ShipState) -> ShipState:
	var target_id := str(game_state.order_of(ship_state.ship_id).get("target", ""))
	var target: ShipState = game_state.get_ship(target_id) if target_id != "" else null
	if target != null and target.side != ship_state.side and not target.is_out_of_play() \
			and target.is_on_map():
		return target
	return _nearest_enemy(ship_state)


## Every footprint but the firer's and the enemy's (lines of sight pass those two).
func _occupied_except(ship_state: ShipState, enemy: ShipState) -> Dictionary:
	var ships: Array[ShipState] = []
	ships.assign(game_state.get_all_ships())
	var occupied := Occupancy.build(ships, [ship_state.ship_id, enemy.ship_id])
	for hex in TerrainMap.of(game_state.active_scenario).land:
		occupied[hex] = "land"
	return occupied


## Friendly footprints make blocking hexes (7.B.10), as in GunneryCalculator.preview.
func _friendly_footprints(ship_state: ShipState) -> Array:
	var friendly: Array = []
	for friend in game_state.gunnery_calculator.friendly_ships(ship_state):
		friendly.append(friend.occupied_hexes())
	return friendly


## Greedy course through the session: each step takes the valid move with the best `score`
## (Callable(bow, facing) -> int; ties by _option_beats), skipping turns that swing the stern into
## another ship's hexes and, with `avoid_bows`, moves that put the bow into one. With `hold`, a ship
## whose position scores > 0 stops once no option is strictly better; otherwise it keeps way on,
## even through a lower-scoring step, until it has no move left. It never takes an unsafe move
## (_move_safe: a forbidden crossing, land, or a hex where it may ground); with none safe it stops.
## Returns the session version.
func _steer(ship_state: ShipState, controller: MovementPlottingController, session_id: String,
		version: int, started: MovementTypes.PlottingStartedResponse, score: Callable, hold: bool,
		avoid_bows: bool, hold_turns: bool = false) -> int:
	var ships: Array[ShipState] = []
	ships.assign(game_state.get_all_ships())
	# Footprints of everyone else: a turn may not swing the stern into one (the resolver would
	# cancel it).
	var others := Occupancy.build(ships, [ship_state.ship_id])

	var current_hex := ship_state.hex_position
	var current_facing := ship_state.facing
	var current_valid := started.valid_next_hexes
	var current_version := version
	var can_submit := started.can_submit

	while current_valid and current_valid.has_any_moves():
		var stay_score: int = score.call(current_hex, current_facing)
		var best: MovementTypes.ValidMove = null
		var best_score := 0
		for move in current_valid.get_all_valid_moves():
			if _stern_blocked(move, current_hex, others):
				continue
			if avoid_bows and others.has(move.metadata.resulting_hex):
				continue
			if not _move_safe(ship_state, move):
				continue
			var move_score: int = score.call(move.metadata.resulting_hex, move.metadata.resulting_facing)
			if best == null or _option_beats(move, move_score, best, best_score, current_facing):
				best = move
				best_score = move_score
		if best == null:
			break
		# An engaged ship holds position unless an option is strictly better; otherwise it keeps
		# way on and works round toward the enemy, even through a lower-scoring step.
		if hold and can_submit and stay_score > 0 and best_score <= stay_score:
			break
		# `hold_turns`: a turn (the bow stays put) is made only when it scores strictly better than
		# the present heading, so left-over MPs are never spent turning into the wind.
		if hold_turns and can_submit and best.metadata.resulting_hex == current_hex \
				and best_score <= stay_score:
			break

		var response := controller.handle_select_hex(session_id, current_version, best.hex, _next_request_id())
		if response is MovementTypes.PlottingErrorResponse:
			break
		var selected := response as MovementTypes.HexSelectedResponse
		current_version = selected.session_version
		current_valid = selected.valid_next_hexes
		can_submit = selected.can_submit
		current_hex = best.metadata.resulting_hex
		current_facing = best.metadata.resulting_facing

	return current_version


## Nearest unstruck ship of another player, closest hex to closest hex (both footprints); ties by
## ship_id. Null when there is none.
func _nearest_enemy(ship_state: ShipState) -> ShipState:
	var nearest: ShipState = null
	var nearest_distance := 0
	for other in game_state.get_all_ships():
		if other.side == ship_state.side or other.is_out_of_play():
			continue
		var distance: int = game_state.fire_geometry.range_between(ship_state.occupied_hexes(), other.occupied_hexes())
		if nearest == null or distance < nearest_distance \
				or (distance == nearest_distance and other.ship_id < nearest.ship_id):
			nearest = other
			nearest_distance = distance
	return nearest


## True when `move` is a turn whose swung stern would land in a hex in `others`.
func _stern_blocked(move: MovementTypes.ValidMove, current_hex: Vector2i, others: Dictionary) -> bool:
	var meta := move.metadata
	if meta.resulting_hex != current_hex:
		return false
	return others.has(HexGrid.stern_of(meta.resulting_hex, meta.resulting_facing))


## Score the firer with its bow at `bow` pointing `facing`. `occupied` holds every other footprint
## except the enemy's. Engaged (a battery bears on the enemy footprint within range <= 5):
## 1000 - 2 * range, plus 3 when both batteries of a side bear, always > 0. Otherwise
## -(2 * distance + misalignment), where distance runs from the firer's bow to the closest hex of the
## enemy footprint and misalignment is the number of 60 degree steps between the facing and the
## direction from the bow toward the enemy's bow. The bow leads: counting the firer's stern too would
## score a ship pointing away (stern one hex nearer) as high as one pointing at the enemy.
## `friendly` holds the footprints of the firer's friends, whose blocking hexes (7.B.10) cut lines
## of sight as in GunneryCalculator.preview.
func _score_position(bow: Vector2i, facing: int, enemy: ShipState, occupied: Dictionary,
		friendly: Array = []) -> int:
	var geometry: FireGeometry = game_state.fire_geometry
	var firer_hexes: Array[Vector2i] = [bow, HexGrid.stern_of(bow, facing)]
	var enemy_hexes := enemy.occupied_hexes()
	var range_hexes := geometry.range_between(firer_hexes, enemy_hexes)
	if range_hexes <= FIRING_RANGE:
		var batteries := _bearing_batteries(firer_hexes, facing, enemy_hexes, occupied, friendly)
		if batteries > 0:
			return FIRING_POSITION_BASE - FIRING_RANGE_WEIGHT * range_hexes \
					+ SECOND_BATTERY_BONUS * (batteries - 1)
	var bow_hexes: Array[Vector2i] = [bow]
	var distance := geometry.range_between(bow_hexes, enemy_hexes)
	return -(2 * distance + _misalignment(bow, facing, enemy.hex_position))


## The most batteries of one side that bear on `enemy_hexes` (0-2).
func _bearing_batteries(firer_hexes: Array[Vector2i], facing: int, enemy_hexes: Array[Vector2i],
		occupied: Dictionary, friendly: Array) -> int:
	var geometry: FireGeometry = game_state.fire_geometry
	var batteries := 0
	for side in GunneryCalculator.SIDES:
		var bearing := 0
		for battery in firer_hexes:
			var blocking := geometry.blocking_hexes(battery, facing, side, firer_hexes, friendly)
			if geometry.battery_bears(battery, facing, side, enemy_hexes, occupied, blocking):
				bearing += 1
		batteries = maxi(batteries, bearing)
	return batteries


## 60 degree steps between `facing` and the direction from `bow` toward `hex` (0 when on it).
func _misalignment(bow: Vector2i, facing: int, hex: Vector2i) -> int:
	if bow == hex:
		return 0
	var toward: int = game_state.fire_geometry.hex_grid.get_facing_direction(bow.x, bow.y, hex.x, hex.y)
	return _turn_steps(facing, toward)


static func _turn_steps(a: int, b: int) -> int:
	var steps := absi(a - b) % 6
	return mini(steps, 6 - steps)


## Close (spec 7): within `limit` (the ordered range, or the starting range when nearer; closest
## hexes) a position scores as engage does (_score_position). Beyond it, -(2 * bow distance +
## misalignment toward the enemy's bow) - CLOSE_OUTSIDE_PENALTY, below every position within it, so
## the ship closes from beyond the range and never opens it once inside.
func _score_close(bow: Vector2i, facing: int, enemy: ShipState, limit: int, occupied: Dictionary,
		friendly: Array) -> int:
	var firer_hexes: Array[Vector2i] = [bow, HexGrid.stern_of(bow, facing)]
	var range_hexes: int = game_state.fire_geometry.range_between(firer_hexes, enemy.occupied_hexes())
	if range_hexes <= limit:
		return _score_position(bow, facing, enemy, occupied, friendly)
	# The bow leads, as in _score_position: a stern swung toward her does not count as closing.
	var bow_hexes: Array[Vector2i] = [bow]
	var distance: int = game_state.fire_geometry.range_between(bow_hexes, enemy.occupied_hexes())
	return -(2 * distance + _misalignment(bow, facing, enemy.hex_position)) - CLOSE_OUTSIDE_PENALTY


## Disengage (spec 7): 2 * range (closest hexes) less the misalignment from the bearing away from
## the enemy's bow. Never "on station": the ship uses every move it has.
func _score_disengage(bow: Vector2i, facing: int, enemy: ShipState) -> int:
	var firer_hexes: Array[Vector2i] = [bow, HexGrid.stern_of(bow, facing)]
	var range_hexes: int = game_state.fire_geometry.range_between(firer_hexes, enemy.occupied_hexes())
	var off_away := 3 - _misalignment(bow, facing, enemy.hex_position)
	return 2 * range_hexes - off_away


## Follow (spec 7): the follower's bow on the hex astern of the leader's stern is on station,
## 1000 less the steps between the two facings, always > 0. Otherwise -(2 * hex distance to that
## hex + misalignment toward it).
func _score_follow(bow: Vector2i, facing: int, leader: ShipState) -> int:
	var wake: Vector2i = leader.stern_hex() + HexGrid.DIRECTIONS[(leader.facing + 3) % 6]
	if bow == wake:
		return FIRING_POSITION_BASE - _turn_steps(facing, leader.facing)
	return -(2 * _axial_distance(bow, wake) + _misalignment(bow, facing, wake))


## Escape (map and scenario spec §12): a bow off the map (it has left across an escape edge) scores
## ESCAPE_EXIT_SCORE; with escape boundaries the side may use, minus ten times the bow's distance to
## the nearest of them, and ten times ESCAPE_LUFF_PENALTY less for a heading into the wind; with
## none, the disengage score against the nearest enemy (0 with no enemy).
func _score_escape(bow: Vector2i, facing: int, ship_state: ShipState) -> int:
	var terrain := TerrainMap.of(game_state.active_scenario)
	if not terrain.in_bounds(bow):
		return ESCAPE_EXIT_SCORE
	var nearest := -1
	for boundary_name in _escape_boundaries(ship_state):
		var d := terrain.distance_to_boundary(bow, boundary_name)
		if d >= 0 and (nearest < 0 or d < nearest):
			nearest = d
	if nearest >= 0:
		var luff := 0
		if game_state.environment != null \
				and HexGrid.new().get_wind_facing(facing, game_state.environment.wind_direction) == "L":
			luff = 10 * ESCAPE_LUFF_PENALTY
		return -10 * nearest - luff
	var enemy := _nearest_enemy(ship_state)
	return _score_disengage(bow, facing, enemy) if enemy != null else 0


## The names of the escape boundaries the ship's side is permitted (MapRules.permission: its
## `edges`, or every escape boundary when none are listed).
func _escape_boundaries(ship_state: ShipState) -> Array[String]:
	var out: Array[String] = []
	var permission := MapRules.permission(game_state.active_scenario, ship_state.side)
	if permission.is_empty():
		return out
	var edges: Array = permission["edges"]
	for b in TerrainMap.of(game_state.active_scenario).boundaries:
		if b.kind == TerrainMap.ESCAPE and (edges.is_empty() or edges.has(b.name)):
			out.append(b.name)
	return out


## The first of `moves` that is safe (_move_safe) and keeps bow and stern out of `avoid`, from a
## ship whose bow is at `here`; null when none does.
func _clear_move(ship_state: ShipState, moves: Array, here: Vector2i,
		avoid: Dictionary) -> MovementTypes.ValidMove:
	for move: MovementTypes.ValidMove in moves:
		if avoid.has(move.metadata.resulting_hex) or _stern_blocked(move, here, avoid):
			continue
		if not _move_safe(ship_state, move):
			continue
		return move
	return null


## True when `move`, from the ship's current pose in its plotting session (its position when it has
## no session or path), keeps to safe water: the hex side it crosses (the bow's on a move ahead, the
## stern's on a turn) is clear or an escape the ship may make (MapRules.crossing_outcome); neither the
## new bow nor the new stern is land; and a new bow on the map never grounds at the ship's draft.
func _move_safe(ship_state: ShipState, move: MovementTypes.ValidMove) -> bool:
	var scenario: Dictionary = game_state.active_scenario
	var terrain := TerrainMap.of(scenario)
	var pose_bow := ship_state.hex_position
	var pose_facing := ship_state.facing
	var session: MovementPlottingSession = null
	if game_state.movement_plotting_controller != null:
		session = game_state.movement_plotting_controller.get_session_for_ship(ship_state.ship_id)
	if session != null and not session.plotted_path.is_empty():
		var last: MovementTypes.PlotStep = session.plotted_path[session.plotted_path.size() - 1]
		pose_bow = last.hex
		pose_facing = last.facing
	var bow := move.metadata.resulting_hex
	var stern := HexGrid.stern_of(bow, move.metadata.resulting_facing)
	var from := pose_bow
	var to := bow
	if bow == pose_bow:  # a turn: the bow pivots, the stern swings (5.C.2)
		from = HexGrid.stern_of(pose_bow, pose_facing)
		to = stern
	var outcome: String = MapRules.crossing_outcome(scenario, ship_state, from, to,
		game_state.current_turn, MapController.escape_locked(game_state, ship_state.ship_id))["outcome"]
	if outcome != MapRules.CLEAR and outcome != MapRules.ESCAPE:
		return false
	if terrain.is_land(bow) or terrain.is_land(stern):
		return false
	return not terrain.in_bounds(bow) or terrain.grounds(bow, ship_state.ship.draft) == "never"


## After a successful submit: a course of at most 2 steps with a step ahead whose bow may or will
## ground casts the lead (13.G.4), through the player's own request.
func _maybe_cast_lead(ship_state: ShipState) -> void:
	var steps: Array = ship_state.plotted_actions.get("movement", [])
	if steps.is_empty() or steps.size() > 2:
		return
	var terrain := TerrainMap.of(game_state.active_scenario)
	var prev := ship_state.hex_position
	var doubtful := false
	for step in steps:
		var hex := Vector2i(int(step["hex"]["q"]), int(step["hex"]["r"]))
		if hex != prev and terrain.grounds(hex, ship_state.ship.draft) != "never":
			doubtful = true
		prev = hex
	if not doubtful:
		return
	var player_id: int = game_state.commander_of(ship_state.ship_id)
	var refused: String = game_state.phase_controller.player_set_cast_lead(player_id,
		ship_state.ship_id, true)
	if refused != "":
		Trace.trace_log("StubAI", "cast lead refused", {"ship_id": ship_state.ship_id, "reason": refused})


## Higher score wins; ties keep the current facing, then lowest q, then lowest r.
func _option_beats(
	a: MovementTypes.ValidMove, a_score: int, b: MovementTypes.ValidMove, b_score: int, current_facing: int
) -> bool:
	if a_score != b_score:
		return a_score > b_score
	var a_keeps := a.metadata.resulting_facing == current_facing
	var b_keeps := b.metadata.resulting_facing == current_facing
	if a_keeps != b_keeps:
		return a_keeps
	if a.hex.x != b.hex.x:
		return a.hex.x < b.hex.x
	return a.hex.y < b.hex.y


func _next_request_id() -> String:
	_request_counter += 1
	return "stub_ai_%d" % _request_counter
