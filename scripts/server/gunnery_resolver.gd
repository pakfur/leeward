class_name GunneryResolver
extends RefCounted
## GunneryResolver - Resolves all declared fire simultaneously (Close Action 1997, 9.3-9.5).
## Every shot is computed from the state before any damage; then shots are rolled in a
## deterministic order, looked up on the Gunfire Results table and applied.

const SAIL_NS := "NS"
const SAIL_MS := "MS"
const SAIL_PS := "PS"
const RAKE_RANK := {"stern": 0, "bow": 1, "": 2}

var is_server: bool = true
var game_state: Node = null


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## Resolve `orders` for `phase`. Orders that cannot fire are skipped (no event, broadside not spent).
##
## Dice order is part of the contract (tests script dice by position). For each shot, in
## resolution order (by target_id, stern rakes, bow rakes, others, then firer ship_id, then side):
##   1. the gunnery d6 (fgn = mgn + d6)
##   2. one d6 per slashed token, columns in order fs, ms, ps, tokens left to right
##   3. the half-box d6, only when a furled target's rigging is odd
##   4. crew-loss d6s, rolled inside DamageController.apply_hits
## A shot with fgn < 1 rolls only the gunnery d6.
func resolve(orders: Array[GunneryTypes.FireOrder], phase: int) -> void:
	if not is_server:
		push_error("GunneryResolver: Cannot resolve gunnery on client")
		return

	# Step 1: capture every shot (and target condition) before any damage is applied.
	var shots_per_ship := {}
	for order in orders:
		shots_per_ship[order.ship_id] = int(shots_per_ship.get(order.ship_id, 0)) + 1
	var shots: Array[Dictionary] = []
	for order in orders:
		var preview: GunneryTypes.ShotPreview = game_state.gunnery_calculator.preview(
				order, shots_per_ship[order.ship_id] > 1)
		if not preview.can_fire:
			continue
		var target: ShipState = game_state.get_ship(order.target_id)
		var dismasted: bool = target.is_dismasted()
		shots.append({
			"preview": preview,
			"sail_state": String(target.sail_state).to_upper(),
			"target_dismasted": dismasted,
		})

	# Step 2: deterministic order.
	shots.sort_custom(_shot_before)

	for shot in shots:
		_resolve_shot(shot, phase)


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
	return ox.side < oy.side


func _resolve_shot(shot: Dictionary, phase: int) -> void:
	var preview: GunneryTypes.ShotPreview = shot["preview"]
	var order := preview.order
	var sail_state: String = shot["sail_state"]
	var target_dismasted: bool = shot["target_dismasted"]

	game_state.ship_controller.set_initial_broadside_fired(order.ship_id, order.side)

	var d6: int = game_state.dice.d6()
	var fgn := preview.mgn + d6
	var rigging := 0
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
		hull = totals["h"]
		crew = totals["c"]

		var furled: bool = sail_state == SAIL_NS and not target_dismasted
		if furled:
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

	game_state.turn_log.add(PhaseEvents.Type.FIRE, phase, order.ship_id, {
		"side": order.side,
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
	}, order.target_id)
	if fgn < 1:
		return

	var hull_fire := order.ammo == GunneryTypes.AMMO_ROUND and order.aim == GunneryTypes.AIM_LOW
	var cause := "gunfire_at_hull" if hull_fire else "other"
	game_state.damage_controller.apply_hits(order.target_id, rigging, hull, crew, cause, phase,
			order.ship_id)

	if preview.rake != "" and target_dismasted:
		var turn: int = game_state.phase_controller.current_turn
		var trigger := "raked_dismasted_t%d" % turn
		if game_state.ship_controller.note_morale_check(order.target_id, trigger):
			game_state.turn_log.add(PhaseEvents.Type.MORALE_NOTED, phase, order.target_id,
					{"trigger": trigger, "count": 1})
