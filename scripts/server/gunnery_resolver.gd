class_name GunneryResolver
extends RefCounted
## GunneryResolver - Resolves all declared fire simultaneously (Close Action 1997, 9.3-9.5).
## Every shot is computed from the state before any damage; then shots are rolled in a
## deterministic order, looked up on the Gunfire Results table and applied.

const SAIL_NS := "NS"
const SAIL_MS := "MS"
const SAIL_PS := "PS"
const RAKE_RANK := {"stern": 0, "bow": 1, "": 2}
const BATTERY_RANK := {"full": 0, "bow": 1, "stern": 2, "chase": 3}

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## Resolve `orders` for `phase`. Orders that cannot fire are skipped (no event, broadside not spent).
##
## Dice order is part of the contract (tests script dice by position). First:
##   0. (14.E, only with gunfire_limits on) one d6 per firing ship that has a qualifying low shot,
##      ascending firer ship_id, before any shot's dice; 4+ fires every such shot of that ship high
## Then for each shot, in resolution order (by target_id, stern rakes, bow rakes, others, then firer ship_id, then side,
## then battery full, bow, stern, chase; the chase sides 2 and 3 sort after the broadsides):
##   1. the gunnery d6 (fgn = mgn + d6)
##   2. one d6 per slashed token, columns in order fs, ms, ps, tokens left to right
##   3. the half-box d6, only when a furled target's rigging is odd
##   4. crew-loss d6s, rolled inside DamageController.apply_hits
##   5. the critical-hit d6, only when the gunnery d6 is a natural 6 (and not dismantling shot
##      aimed low, which causes no hull crits, 7.C.12b), and only if the target has not struck
##   6. on a critical hit, the 2d6 crit roll and the result's own sub-rolls (CriticalHitController)
##   7. the Rigging/Hull Check d6s (and their sub-rolls) for the sections the shot and its crit
##      emptied, in queue order (CriticalHitController.drain)
## A shot with fgn < 1 rolls only the gunnery d6.
func resolve(orders: Array[GunneryTypes.FireOrder], phase: int) -> void:
	if not is_server:
		push_error("GunneryResolver: Cannot resolve gunnery on client")
		return

	# Step 1: capture every shot (and target condition) before any damage is applied.
	# preview_orders applies the two-target modifier (7.C.12g) and gives a split side's
	# initial-broadside bonus to one shot only (7.C.10).
	var shots: Array[Dictionary] = []
	for preview: GunneryTypes.ShotPreview in game_state.gunnery_calculator.preview_orders(orders):
		var order := preview.order
		if not preview.can_fire:
			continue
		var target: ShipState = game_state.get_ship(order.target_id)
		var dismasted: bool = target.is_dismasted()
		shots.append({
			"preview": preview,
			"sail_state": String(target.sail_state).to_upper(),
			"target_dismasted": dismasted,
		})

	# 14.E: the gunfire-limit rolls come before any shot's dice.
	_roll_aim_limits(shots, phase)

	# Step 2: deterministic order.
	shots.sort_custom(_shot_before)

	for shot in shots:
		_resolve_shot(shot, phase)

	# 14.D: each ship that fired counts one firing turn, after all shots (no die).
	var firers: Array[String] = []
	for shot in shots:
		var firer_id: String = shot["preview"].order.ship_id
		if not firers.has(firer_id):
			firers.append(firer_id)
	firers.sort()
	for firer_id in firers:
		game_state.ship_controller.note_gunfire_turn(firer_id)


## 14.E: one d6 per ship with a shot that has aim limits, ascending ship_id; on AIM_FORCED_MIN or
## more each such shot fires high (a copy of its order, so the caller's order is untouched; the
## MGN stays as previewed) and one AIM_FORCED event is logged. No die without such a shot.
func _roll_aim_limits(shots: Array[Dictionary], phase: int) -> void:
	var by_firer: Dictionary = {}  # ship_id -> Array of shot dictionaries
	for shot in shots:
		var preview: GunneryTypes.ShotPreview = shot["preview"]
		if preview.aim_limits.is_empty():
			continue
		var firer_id := preview.order.ship_id
		if not by_firer.has(firer_id):
			by_firer[firer_id] = []
		by_firer[firer_id].append(shot)
	var firers: Array = by_firer.keys()
	firers.sort()
	for firer_id: String in firers:
		var roll: int = game_state.dice.d6()
		var rules: Array[String] = []
		var sides: Array[int] = []
		for shot: Dictionary in by_firer[firer_id]:
			shot["aim_roll"] = roll
			var preview: GunneryTypes.ShotPreview = shot["preview"]
			for rule in preview.aim_limits:
				if not rules.has(rule):
					rules.append(rule)
			if not sides.has(preview.order.side):
				sides.append(preview.order.side)
			if roll >= FireRules.AIM_FORCED_MIN:
				var forced := GunneryTypes.FireOrder.from_dict(preview.order.to_dict())
				forced.aim = GunneryTypes.AIM_HIGH
				preview.order = forced
		if roll < FireRules.AIM_FORCED_MIN:
			continue
		var ordered: Array[String] = []  # "crew" before "heel"
		for rule in ["crew", "heel"]:
			if rules.has(rule):
				ordered.append(rule)
		sides.sort()
		var firer: ShipState = game_state.get_ship(firer_id)
		game_state.turn_log.add(PhaseEvents.Type.AIM_FORCED, phase, firer_id, {
			"roll": roll,
			"rules": ordered,
			"sides": sides,
			"quality": firer.crew_quality,
		})


func _shot_before(x: Dictionary, y: Dictionary) -> bool:
	var px: GunneryTypes.ShotPreview = x["preview"]
	var py: GunneryTypes.ShotPreview = y["preview"]
	var ox := px.order
	var oy := py.order
	if ox.target_id != oy.target_id:
		return ox.target_id < oy.target_id
	if RAKE_RANK[px.rake] != RAKE_RANK[py.rake]:
		return RAKE_RANK[px.rake] < RAKE_RANK[py.rake]
	if ox.ship_id != oy.ship_id:
		return ox.ship_id < oy.ship_id
	if ox.side != oy.side:
		return ox.side < oy.side
	return BATTERY_RANK.get(ox.battery, 3) < BATTERY_RANK.get(oy.battery, 3)


func _resolve_shot(shot: Dictionary, phase: int) -> void:
	var preview: GunneryTypes.ShotPreview = shot["preview"]
	var order := preview.order
	var sail_state: String = shot["sail_state"]
	var target_dismasted: bool = shot["target_dismasted"]

	# A chaser never spends a broadside's initial-broadside bonus (house rule, register §5).
	if not GunneryTypes.is_chase_side(order.side):
		game_state.ship_controller.set_initial_broadside_fired(order.ship_id, order.side)

	var d6: int = game_state.dice.d6()
	var fgn := preview.mgn + d6
	var rigging := 0
	var rigging_hit := false
	var hull := 0
	var crew := 0
	if fgn >= 1:
		var columns: Array[String] = ["fs"]
		if sail_state == SAIL_MS or sail_state == SAIL_PS:
			columns.append("ms")
		if sail_state == SAIL_PS:
			columns.append("ps")
		var totals := {"r": 0, "h": 0, "c": 0}
		for column in columns:
			for token in DataManager.combat_tables.gunfire_result(fgn, order.aim, column):
				var alternative: Dictionary = token[0]
				if token.size() > 1:
					alternative = token[0] if game_state.dice.d6() <= 3 else token[1]
				if alternative.has("type"):
					totals[alternative["type"]] += int(alternative["count"])
		rigging = totals["r"]
		rigging_hit = rigging > 0
		hull = totals["h"]
		crew = totals["c"]

		var furled: bool = sail_state == SAIL_NS and not target_dismasted
		if furled:
			@warning_ignore("integer_division")
			var half := rigging / 2
			if rigging % 2 == 1 and game_state.dice.d6() <= 3:
				half += 1
			rigging = half
		if target_dismasted:
			rigging = 0
		if order.ammo == GunneryTypes.AMMO_DISMANTLING:
			hull = 0
		if preview.rake == "stern":
			crew *= 2

	var fire_data := {
		"side": order.side,
		"battery": order.battery,
		"range": preview.range_hexes,
		"aim": order.aim,
		"ammo": order.ammo,
		"bgn": preview.bgn,
		"modifiers": preview.modifiers.duplicate(true),
		"mgn": preview.mgn,
		"d6": d6,
		"fgn": fgn,
		"rake": preview.rake,
		"rigging": rigging,
		"hull": hull,
		"crew": crew,
		"ch_number": DataManager.combat_tables.critical_hit_number(fgn),
	}
	if shot.has("aim_roll"):
		fire_data["aim_ordered"] = GunneryTypes.AIM_LOW
		fire_data["aim_roll"] = shot["aim_roll"]
	game_state.turn_log.add(PhaseEvents.Type.FIRE, phase, order.ship_id, fire_data, order.target_id)
	if fgn < 1:
		return

	var crits: CriticalHitController = game_state.critical_hit_controller
	var ctx := crits.shot_context(order, preview.rake, target_dismasted)
	ctx["fgn"] = fgn
	ctx["d6"] = d6
	# Hold the check queue: the shot's own crit (7.D.11) is rolled before the Rigging/Hull
	# Checks its damage caused; release() then drains them.
	crits.hold()
	var hull_fire := order.ammo == GunneryTypes.AMMO_ROUND and order.aim == GunneryTypes.AIM_LOW
	var cause := "gunfire_at_hull" if hull_fire else "other"
	cause = BoardingRules.crew_loss_cause(game_state.get_ship(order.target_id), cause)  # 10.D.7
	game_state.damage_controller.apply_hits(order.target_id, rigging, hull, crew, cause, phase,
			order.ship_id, ctx)
	if target_dismasted and rigging_hit:
		# 8.F.6: the r marks nothing on a dismasted ship but cancels its rigging repairs.
		game_state.damage_controller.rigging_hit_while_dismasted(order.target_id, phase)

	if preview.rake != "" and target_dismasted and not _rigged_tower_holds(order.target_id):
		var turn: int = game_state.phase_controller.current_turn
		var trigger := "raked_dismasted_t%d" % turn
		if game_state.ship_controller.note_morale_check(order.target_id, trigger):
			game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, order.target_id,
					{"trigger": trigger, "count": 1})

	crits.check_gunfire_crit(ctx, phase)
	crits.release(phase)


## 9.B.1b: a dismasted ship raked while in tow takes no MC unless her tower is dismasted too.
func _rigged_tower_holds(target_id: String) -> bool:
	var target: ShipState = game_state.get_ship(target_id)
	if target == null or not target.is_towed():
		return false
	var tower: ShipState = game_state.get_ship(target.towed_by)
	return tower != null and not tower.is_dismasted()
