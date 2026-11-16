class_name StubAI
extends RefCounted
## StubAI - Drives the plotting protocol for non-player ships
## Uses the real MovementPlottingController so all AI plots are rule-validated.
##
## Strategies:
##   "engage"  — steer toward the nearest enemy, presenting a broadside when close (default)
##   "forward" — move straight ahead, consuming all available MA
##   "hold"    — submit immediately with empty path
##
## Fire: each ship fires each broadside at its best-odds target, splitting a side between two
## targets when no full broadside bears (see choose_fire_orders); its marines fire at the adjacent
## enemy with the best modified die (choose_marine_orders).

## A broadside shot at or inside this range scores as a firing position.
const FIRING_RANGE := 5
const FIRING_POSITION_BASE := 1000
## A firing position loses this much per hex of range.
const FIRING_RANGE_WEIGHT := 2
## Added to a firing position's score when its second battery bears too: worth more than one hex of
## range, less than two (two batteries at range r beat one at r or r-1, lose to one at r-2).
const SECOND_BATTERY_BONUS := 3

## Plotting errors for ships that legitimately cannot move; the AI skips them without error.
const LOCKED_ERROR_CODES := ["SHIP_FOULED", "SHIP_GRAPPLED", "SHIP_CAPTURED", "SHIP_STRUCK", "SHIP_DESTROYED", "SHIP_DISMASTED"]

var game_state: Node = null
var _request_counter: int = 0
## When non-empty, forces this strategy for every AI ship (used by tests).
var strategy_override: String = ""


func _init(p_game_state: Node = null) -> void:
	game_state = p_game_state if p_game_state else GameState


func plot_all_ai_ships() -> void:
	assert(game_state.is_server, "StubAI: Must only run on server")
	var controller: MovementPlottingController = game_state.movement_plotting_controller
	if not controller:
		push_error("StubAI: No movement_plotting_controller on game_state")
		return

	var ai_ships := _get_ai_ships()
	Trace.trace_log("StubAI", "plot_all_ai_ships: %d AI ships" % ai_ships.size())

	for ship_state in ai_ships:
		var strategy := _get_strategy(ship_state)
		_plot_ship(ship_state, controller, strategy)
	assign_crew()


## The AI's crew orders (crew-tasks spec §3.3). It gives the orders only (no sail changes today)
## and leaves Automatic on, so CrewAuto places its sections by the same rules as the player's.
func assign_crew() -> void:
	assert(game_state.is_server, "StubAI: Must only run on server")
	var sc: ShipStateController = game_state.ship_controller
	for ship_state in _get_ai_ships():
		if ship_state.is_destroyed():
			continue
		if not ship_state.crew_auto:
			sc.set_crew_auto(ship_state.ship_id, true)
		sc.set_crew_orders(ship_state.ship_id, {"sail_target": "", "boarding": boarding_order(ship_state)})


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
		if other == null or other.player_id == ship_state.player_id:
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
		if other.player_id != ship_state.player_id and not other.is_out_of_play() and other.has_boarders() \
				and grappling != null and grappling.adjacent(ship_state, other):
			return "ready"
	return ""


## Prize-crew sizes (10.G.6; boarding spec §3.6) for the won actions of `player_ids` that offer a
## choice: the minimum, plus one if another enemy ship in play is within 3 hexes of the prize.
## {action_id: size}.
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
				if other.ship_id == prize.ship_id or other.player_id == player_id or other.is_out_of_play():
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
	if enemy == null or enemy.player_id == ship_state.player_id:
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


## Grapple orders (8.C.1) for the ships of `player_ids`, as [ship_id, target_id] pairs: every
## eligible enemy that has struck, or whose crew is at most two thirds of this ship's in boarding
## combat factors (boarding spec §3.6). Never a friendly ship.
func grapple_orders(player_ids: Array[int]) -> Array:
	var grappling: GrapplingController = game_state.grappling_controller
	var orders: Array = []
	for ship_state in _ships_of(player_ids):
		for target_id in grappling.grapple_options(ship_state.ship_id):
			if _wants_grapple(ship_state, game_state.get_ship(target_id)):
				orders.append([ship_state.ship_id, target_id])
	return orders


## Ungrapple orders (8.C.4) for the ships of `player_ids`: every grapple to a ship it would neither
## board nor grapple (a friendly ship, or an enemy it would not take on).
func ungrapple_orders(player_ids: Array[int]) -> Array:
	var grappling: GrapplingController = game_state.grappling_controller
	var orders: Array = []
	for ship_state in _ships_of(player_ids):
		for partner_id in grappling.ungrapple_options(ship_state.ship_id):
			var partner: ShipState = game_state.get_ship(partner_id)
			# Boarding spec §3.6: keep a grapple to an enemy it would board or grapple; never cut
			# loose from a struck enemy; cut every other (friends included).
			if partner != null and partner.player_id != ship_state.player_id \
					and (partner.is_struck() or would_board(ship_state, partner) or _wants_grapple(ship_state, partner)):
				continue
			orders.append([ship_state.ship_id, partner_id])
	return orders


## The AI's grappling rule (boarding spec §3.6): an enemy that has struck, or whose crew's boarding
## combat factors are at most two thirds of this ship's.
func _wants_grapple(ship_state: ShipState, other: ShipState) -> bool:
	if other == null or other.player_id == ship_state.player_id:
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


func _ships_of(player_ids: Array[int]) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for ship_state in game_state.get_all_ships():
		if player_ids.has(ship_state.player_id):
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


## Declare fire for the AI side (player 1).
func submit_fire_orders() -> void:
	assert(game_state.is_server, "StubAI: Must only run on server")
	var reason: String = game_state.phase_controller.player_submit_fire_orders(1, choose_fire_orders(),
		choose_marine_orders())
	if reason != "":
		push_error("StubAI: fire orders rejected: %s" % reason)


## FireOrder dictionaries for every AI ship; roundshot. Each side offers: hold; its best shot (the
## highest-mgn full broadside, ties nearest then target_id, or when no full broadside bears the best
## single battery); and, when no full broadside bears and its bow and stern batteries' best targets
## differ, a split side (bow at one, stern at the other, 7.B.1). Of the combinations of the two
## sides' offers that name at most two targets (7.A.4) and, when they name two, leave every shot
## mgn >= 1 under the two-target penalty, the ship fires the one with the most shots, then the
## highest total mgn (FireRules + preview_orders), then the nearest, then by target_id.
func choose_fire_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var calculator: GunneryCalculator = game_state.gunnery_calculator
	for ship_state in _get_ai_ships():
		var shots := calculator.eligible_shots(ship_state.ship_id)
		var offers: Array = []
		for side in GunneryCalculator.SIDES:
			offers.append(_side_offers(shots, side))
		var best: Dictionary = {}
		for port_offer in offers[0]:
			for starboard_offer in offers[1]:
				var orders: Array[GunneryTypes.FireOrder] = []
				orders.append_array(port_offer)
				orders.append_array(starboard_offer)
				var candidate := _evaluate_orders(calculator, orders)
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
func choose_marine_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var marines: MarineFireResolver = game_state.get("marine_fire_resolver")
	if marines == null:
		return result
	for ship_state in _get_ai_ships():
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


## The order sets one side may fire: [] (hold), its best shot, and the split side when it has one.
func _side_offers(shots: Array[GunneryTypes.ShotPreview], side: int) -> Array:
	var offers: Array = [[] as Array[GunneryTypes.FireOrder]]
	var best: GunneryTypes.ShotPreview = null
	var best_by_battery := {}
	for shot in shots:
		if shot.order.side != side:
			continue
		# A full broadside before any half broadside (FireRules.battery_rank), then mgn.
		if best == null or _preferred(shot, best):
			best = shot
		var battery := shot.order.battery
		if not best_by_battery.has(battery) or _shot_beats(shot, best_by_battery[battery]):
			best_by_battery[battery] = shot
	if best == null:
		return offers
	offers.append([best.order] as Array[GunneryTypes.FireOrder])
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


func _get_ai_ships() -> Array[ShipState]:
	var result: Array[ShipState] = []
	for ship_state in game_state.get_all_ships():
		if ship_state.player_id != 0:
			result.append(ship_state)
	return result


func _get_strategy(_ship_state: ShipState) -> String:
	if strategy_override != "":
		return strategy_override
	return "engage"


func _plot_ship(ship_state: ShipState, controller: MovementPlottingController, strategy: String) -> void:
	var ship_id := ship_state.ship_id
	var player_id := ship_state.player_id

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
		"forward":
			version = _strategy_forward(ship_state, controller, session_id, version, started)
		"hold":
			pass

	var submit_response := controller.handle_submit_movement(session_id, version, _next_request_id())

	if submit_response is MovementTypes.PlottingErrorResponse \
			and (submit_response as MovementTypes.PlottingErrorResponse).error_code == "RUDDER_JAMMED":
		# The course found never turned the way the jammed rudder holds (hull #2): stay put instead.
		Trace.trace_log("StubAI", "rudder jammed, holding position", {"ship_id": ship_id})
		controller.handle_cancel_plotting(session_id, _next_request_id())
		var restart := controller.handle_start_plotting(player_id, ship_id, _next_request_id())
		if restart is MovementTypes.PlottingStartedResponse:
			var again := restart as MovementTypes.PlottingStartedResponse
			submit_response = controller.handle_submit_movement(again.session_id, again.session_version,
				_next_request_id())

	if submit_response is MovementTypes.PlottingErrorResponse:
		var err := submit_response as MovementTypes.PlottingErrorResponse
		push_error("StubAI: submit failed for %s: %s" % [ship_id, err.message])
		Trace.trace_log("StubAI", "submit FAILED", {"ship_id": ship_id, "error": err.error_code})
		return

	Trace.trace_log("StubAI", "plotted ship", {
		"ship_id": ship_id,
		"strategy": strategy,
		"steps": ship_state.plotted_actions.get("movement", []).size()
	})


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
	var enemy := _nearest_enemy(ship_state)
	if enemy == null:
		return version  # nothing to engage: submit the session with an empty path

	var ships: Array[ShipState] = []
	ships.assign(game_state.get_all_ships())
	# Footprints of everyone else: a turn may not swing the stern into one (the resolver would
	# cancel it), and lines of sight pass the firer and the enemy but not the rest.
	var others := Occupancy.build(ships, [ship_state.ship_id])
	var occupied := Occupancy.build(ships, [ship_state.ship_id, enemy.ship_id])

	var current_hex := ship_state.hex_position
	var current_facing := ship_state.facing
	var current_valid := started.valid_next_hexes
	var current_version := version
	var can_submit := started.can_submit

	while current_valid and current_valid.has_any_moves():
		var stay_score := _score_position(current_hex, current_facing, enemy, occupied)
		var best: MovementTypes.ValidMove = null
		var best_score := 0
		for move in current_valid.get_all_valid_moves():
			if _stern_blocked(move, current_hex, others):
				continue
			var move_score := _score_position(move.metadata.resulting_hex, move.metadata.resulting_facing, enemy, occupied)
			if best == null or _option_beats(move, move_score, best, best_score, current_facing):
				best = move
				best_score = move_score
		if best == null:
			break
		# An engaged ship holds position unless an option is strictly better; otherwise it keeps
		# way on and works round toward the enemy, even through a lower-scoring step.
		if can_submit and stay_score > 0 and best_score <= stay_score:
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
		if other.player_id == ship_state.player_id or other.is_out_of_play():
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
func _score_position(bow: Vector2i, facing: int, enemy: ShipState, occupied: Dictionary) -> int:
	var geometry: FireGeometry = game_state.fire_geometry
	var firer_hexes: Array[Vector2i] = [bow, HexGrid.stern_of(bow, facing)]
	var enemy_hexes := enemy.occupied_hexes()
	var range_hexes := geometry.range_between(firer_hexes, enemy_hexes)
	if range_hexes <= FIRING_RANGE:
		var batteries := 0
		for side in GunneryCalculator.SIDES:
			var bearing := 0
			for battery in firer_hexes:
				if geometry.battery_bears(battery, facing, side, enemy_hexes, occupied):
					bearing += 1
			batteries = maxi(batteries, bearing)
		if batteries > 0:
			return FIRING_POSITION_BASE - FIRING_RANGE_WEIGHT * range_hexes \
					+ SECOND_BATTERY_BONUS * (batteries - 1)
	var enemy_bow := enemy.hex_position
	var bow_hexes: Array[Vector2i] = [bow]
	var distance := geometry.range_between(bow_hexes, enemy_hexes)
	var misalignment := 0
	if bow != enemy_bow:
		var toward := geometry.hex_grid.get_facing_direction(bow.x, bow.y, enemy_bow.x, enemy_bow.y)
		var steps := absi(facing - toward) % 6
		misalignment = mini(steps, 6 - steps)
	return -(2 * distance + misalignment)


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
