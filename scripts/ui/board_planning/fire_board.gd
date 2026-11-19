class_name FireBoard
extends RefCounted
## The fire declaration step on the board (board planning piece 3), view state only: a
## FireOrdersModel (the orders and every number, from GunneryCalculator.preview_orders), the fire
## step's Plan / Done checklist, the target mode (one ship's side, or her marines, picking a target)
## and the option box's draft. BoardPlanning shows it (ring, badges, box, arrows); GameController
## draws the arc and the target rings. Nothing here reaches the server: the orders are sent with
## model.order_dicts() / model.marine_orders() (Task 3).
##
## The board starts every ship with no orders (a ship still in Plan holds fire, as the footer says);
## a ship with no shot starts Done with her no-shot reason. While the option box is open its draft
## is applied to the model at once, so the number shown is the whole set's (a second target's −12
## included); Cancel puts the ship's choices back as they were when the box opened.

signal changed()

## The marines in target mode (the gun sides are ShipState.PORT / STARBOARD and the chase sides).
const MARINES := 4
## Ring items for the gun sides, in ring order: [side, item id, label, icon].
const SIDE_ITEMS := [
	[ShipState.PORT, "port", "Port broadside", "port"],
	[ShipState.STARBOARD, "starboard", "Starboard broadside", "starboard"],
	[GunneryTypes.CHASE_BOW, "bowchase", "Bow chaser", "bowchase"],
	[GunneryTypes.CHASE_STERN, "sternchase", "Stern chaser", "sternchase"],
]
const ICONS := {
	"port": preload("res://assets/ui/radial/port.svg"),
	"starboard": preload("res://assets/ui/radial/starboard.svg"),
	"bowchase": preload("res://assets/ui/radial/bowchase.svg"),
	"sternchase": preload("res://assets/ui/radial/sternchase.svg"),
	"marines": preload("res://assets/ui/radial/marines.svg"),
	"hold": preload("res://assets/ui/radial/hold.svg"),
	"done": preload("res://assets/ui/radial/done.svg"),
	"undo": preload("res://assets/ui/radial/undo.svg"),
}
## The muskets' arrow colour (prototype --marine).
const MUSKET_COLOR := Color("#e8d27a")
## Arrows of ships other than the one whose ring or target mode is open.
const DIM_ALPHA := 0.35

var model: FireOrdersModel = null
var checklist := PlanChecklist.new()
var _ids: Array[String] = []
var _names: Dictionary = {}
var _target_ship := ""
var _target_side := -1
## The open option box: {ship_id, side, target_id, snapshot (FireOrdersModel.ship_snapshot)}.
var _box: Dictionary = {}


## The step begins for `listed_ids` (the local player's ships, card order): every order is cleared,
## ships with a shot are in Plan, the rest Done.
func begin(fire_model: FireOrdersModel, listed_ids: Array) -> void:
	end()
	model = fire_model
	_ids.clear()
	for id in listed_ids:
		_ids.append(str(id))
	_names = FireOrdersModel.target_names(GameState.get_all_ships())
	for id in _ids:
		if has_shot(id):
			model.hold_fire(id)  # the board starts with no orders: a ship in Plan holds fire
	var all := {}
	for id in _ids:
		all[id] = true
	checklist.begin(_ids, all)
	for id in _ids:
		if not has_shot(id):
			checklist.set_done(id, true)
	model.changed.connect(_on_model_changed)
	changed.emit()


## The step is over: target mode and the box are dropped (the model is left as it is).
func end() -> void:
	if model != null and model.changed.is_connected(_on_model_changed):
		model.changed.disconnect(_on_model_changed)
	model = null
	_ids.clear()
	_target_ship = ""
	_target_side = -1
	_box = {}
	checklist.clear()


func is_active() -> bool:
	return model != null


func ship_ids() -> Array[String]:
	return _ids.duplicate()


## A gun or a marine shot (FireOrdersModel.ships_with_shots).
func has_shot(ship_id: String) -> bool:
	return model != null and model.ships_with_shots().has(ship_id)


## PlanChecklist.PLAN or DONE ("" for a ship not in the step).
func state(ship_id: String) -> String:
	return checklist.state(ship_id)


## Done (true) or back in Plan; a ship with no shot stays Done.
func set_done(ship_id: String, done: bool) -> void:
	if not done and not has_shot(ship_id):
		return
	checklist.set_done(ship_id, done)


## Her orders: the gun orders plus one for her marines.
func order_count(ship_id: String) -> int:
	if model == null:
		return 0
	return model.ship_orders(ship_id).size() + (1 if model.marine_target(ship_id) != "" else 0)


## The ships with a shot and no order (they hold fire).
func ships_without_orders() -> int:
	var n := 0
	for id in _ids:
		if has_shot(id) and order_count(id) == 0:
			n += 1
	return n


## Why she has no shot ("" when she has one): the guns' reason, or the marines' for a ship with no
## gun at all and no marine shot.
func no_shot_reason(ship_id: String) -> String:
	if model == null or has_shot(ship_id):
		return ""
	return model.no_shot_reason(ship_id)


## Her pill on the map: {state, text} (PlanBadges FIRE / NO TARGET / ORDERS / NO_FIRE).
func pill(ship_id: String) -> Dictionary:
	if not has_shot(ship_id):
		return {"state": PlanBadges.NO_TARGET, "text": ""}
	var n := order_count(ship_id)
	if state(ship_id) == PlanChecklist.PLAN:
		# Still in Plan until Done, but confirmed orders show as a count (they are sent).
		return {"state": PlanBadges.FIRE, "text": "FIRE · %d" % n if n > 0 else ""}
	if n == 0:
		return {"state": PlanBadges.NO_FIRE, "text": ""}
	return {"state": PlanBadges.ORDERS, "text": "✓ %d ORDER%s" % [n, "" if n == 1 else "S"]}


## The fire ring: Port broadside, Starboard broadside, Bow chaser, Stern chaser, Marines, Hold fire
## (Clear orders once she has one), then Done (in Plan) or Change orders. A side with no target is
## greyed with the model's reason; a side with an order is `on`.
func ring_items(ship_id: String) -> Array[RadialItem]:
	var items: Array[RadialItem] = []
	if model == null:
		return items
	var bearing := model.sides_bearing(ship_id)
	for entry in SIDE_ITEMS:
		var side: int = entry[0]
		var on := not model.batteries(ship_id, side).is_empty()
		var n: int = (bearing.get(side, []) as Array).size()
		items.append(RadialItem.make(entry[1], entry[2], ICONS[entry[3]], _side_hint(on, n),
			model.side_reason(ship_id, side), on))
	var marines_on := model.marine_target(ship_id) != ""
	items.append(RadialItem.make("marines", "Marines", ICONS["marines"],
		_side_hint(marines_on, model.marine_targets(ship_id).size()), model.marine_reason(ship_id), marines_on))
	var orders := order_count(ship_id)
	var reason := no_shot_reason(ship_id)
	items.append(RadialItem.make("hold", "Clear orders" if orders > 0 else "Hold fire", ICONS["hold"],
		"Remove her fire orders." if orders > 0 else "She holds her fire this turn.", reason))
	if state(ship_id) == PlanChecklist.PLAN:
		items.append(RadialItem.make("done", "Done", ICONS["done"],
			"Her fire orders are given." if orders > 0 else "Done: she holds her fire."))
	else:
		items.append(RadialItem.make("undo", "Change orders", ICONS["undo"], "Back to choosing.", reason))
	return items


## The ring's subtitle: her orders, or why she has no shot.
func subtitle(ship_id: String) -> String:
	var reason := no_shot_reason(ship_id)
	if reason != "":
		return "No shot: %s" % reason
	var n := order_count(ship_id)
	return "Holds fire" if n == 0 else "%d fire order%s" % [n, "" if n == 1 else "s"]


static func _side_hint(on: bool, target_count: int) -> String:
	if on:
		return "Ordered. Pick again to change it."
	return "%d target%s." % [target_count, " bears" if target_count == 1 else "s bear"]


# --- target mode ---------------------------------------------------------------------------------

## Picking a target for one side of a ship (or MARINES). False when that side has no target.
func enter_target(ship_id: String, side: int) -> bool:
	if model == null:
		return false
	var ok := model.has_marines(ship_id) if side == MARINES else model.sides(ship_id).has(side)
	if not ok:
		return false
	if box_open():
		cancel_box()
	_target_ship = ship_id
	_target_side = side
	changed.emit()
	return true


## Leaves target mode (an open box is cancelled first).
func leave_target() -> void:
	if _target_ship == "":
		return
	if box_open():
		_restore_box()
	_target_ship = ""
	_target_side = -1
	changed.emit()


func target_ship() -> String:
	return _target_ship


## The side in target mode (MARINES for the marines), -1 outside it.
func target_side() -> int:
	return _target_side


## The targets of the side in target mode, nearest first: {target_id, name, range}.
func targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if model == null or _target_ship == "":
		return out
	if _target_side == MARINES:
		for row in model.marine_targets(_target_ship):
			var p: Dictionary = row["preview"]
			out.append({"target_id": row["target_id"], "name": _name(row["target_id"]),
				"range": int(p.get("range", 1))})
		return out
	for row in model.targets(_target_ship, _target_side):
		out.append({"target_id": row["target_id"], "name": row["name"], "range": int(row["range"])})
	return out


func is_target(target_id: String) -> bool:
	for t in targets():
		if t["target_id"] == target_id:
			return true
	return false


## Opens the option box on a target of the side in target mode; its draft goes into the model at
## once (the side fires at it, with her preferred battery unless it fires at it already). False for
## a ship that is not a target. A box open on another target is put back first.
func pick(target_id: String) -> bool:
	if not is_target(target_id):
		return false
	if box_open():
		_restore_box()
	_box = {"ship_id": _target_ship, "side": _target_side, "target_id": target_id,
		"snapshot": model.ship_snapshot(_target_ship)}
	if _target_side == MARINES:
		if model.marine_target(_target_ship) != target_id:
			model.select_marine_target(_target_ship, target_id)
	elif box_battery() == "":
		model.choose(_target_ship, _target_side, target_id, "")
	changed.emit()
	return true


func box_open() -> bool:
	return not _box.is_empty()


## {ship_id, side, target_id} of the open box ({} when closed).
func box_order() -> Dictionary:
	if _box.is_empty():
		return {}
	return {"ship_id": _box["ship_id"], "side": _box["side"], "target_id": _box["target_id"]}


## The battery the box's side fires at its target with ("full", "bow", "stern", "chase"), "" none.
func box_battery() -> String:
	if _box.is_empty() or int(_box["side"]) == MARINES:
		return ""
	var ship_id: String = _box["ship_id"]
	var side: int = _box["side"]
	var target_id: String = _box["target_id"]
	var st := model.side_state(ship_id, side)
	if st.is_empty():
		return ""
	for battery in model.battery_options_for(ship_id, side, target_id):
		if FireOrdersModel.row_chosen(st["bow"], st["stern"], target_id, battery):
			return battery
	return ""


## The box's battery chip.
func set_box_battery(battery: String) -> void:
	if _box.is_empty() or int(_box["side"]) == MARINES or battery == box_battery():
		return
	model.choose(_box["ship_id"], _box["side"], _box["target_id"], battery)


## The box's Low / High chips (FireRules may still force high: the box shows what the order is).
func set_box_high(on: bool) -> void:
	if not _box.is_empty() and int(_box["side"]) != MARINES:
		model.set_high(_box["ship_id"], _box["side"], on)


## The box's Round / Dismantling chips.
func set_box_dismantling(on: bool) -> void:
	if not _box.is_empty() and int(_box["side"]) != MARINES:
		model.set_dismantling(_box["ship_id"], _box["side"], on)


## The box's voluntary reduction stepper (7.C.14, clamped at 0 by the model).
func step_box_reduction(delta: int) -> void:
	var battery := box_battery()
	if battery == "":
		return
	var n := model.reduction(_box["ship_id"], _box["side"], _box["target_id"], battery) + delta
	model.set_reduction(_box["ship_id"], _box["side"], _box["target_id"], battery, n)


## ✓ Order: the draft stays; the box and target mode close. Returns the ship's id ("" no box).
func confirm_box() -> String:
	if _box.is_empty():
		return ""
	var ship_id: String = _box["ship_id"]
	_box = {}
	_target_ship = ""
	_target_side = -1
	changed.emit()
	return ship_id


## Cancel: the ship's choices go back to what they were when the box opened; target mode stays.
func cancel_box() -> void:
	if _box.is_empty():
		return
	_restore_box()
	changed.emit()


func _restore_box() -> void:
	var box := _box
	_box = {}
	model.restore_ship(box["ship_id"], box["snapshot"])


## What the option box shows, from the model (every number from order_previews, every wording from
## FireText). Guns: {kind "guns", title, batteries [{id, label, on}], high,
## low_off, aim_note, dismantling, dismantling_off, dismantling_note, reduction, number, can_fire,
## breakdown, modifiers, two_target}; marines: {kind "marines", title, text}. {} when closed.
func box_content() -> Dictionary:
	if _box.is_empty():
		return {}
	var ship_id: String = _box["ship_id"]
	var side: int = _box["side"]
	var target_id: String = _box["target_id"]
	var ship := GameState.get_ship(ship_id)
	var ship_name := ship.ship_name if ship else ship_id
	var target := GameState.get_ship(target_id)
	var target_name := target.ship_name if target else target_id
	if side == MARINES:
		var mp := _marine_preview(ship_id, target_id)
		return {"kind": "marines", "title": "%s → %s · range %d" % [ship_name, target_name, int(mp.get("range", 1))],
			"text": FireText.marine_option_text(_name(target_id), mp)}
	var battery := box_battery()
	var p: GunneryTypes.ShotPreview = model.order_previews().get(
		FireOrdersModel.order_key(ship_id, side, target_id, battery))
	var range_hexes := _target_range(ship_id, side, target_id)
	var chase := GunneryTypes.is_chase_side(side)
	var options := model.battery_options_for(ship_id, side, target_id)
	var chips: Array[Dictionary] = []
	if options.size() > 1 or (not options.is_empty() and options[0] not in [GunneryTypes.BATTERY_FULL, GunneryTypes.BATTERY_CHASE]):
		for b in options:
			chips.append({"id": b, "label": FireText.battery_label(b), "on": b == battery})
	var st := model.side_state(ship_id, side)
	var high_only := p != null and p.high_only
	var limits: Array = p.aim_limits if p else []
	var lines: Array[String] = FireText.modifier_lines(p) if p else ([] as Array[String])
	var out := {"kind": "guns", "title": "%s → %s · range %d" % [ship_name, target_name, range_hexes],
		"batteries": chips,
		"high": p != null and p.order.aim == GunneryTypes.AIM_HIGH,
		"low_off": high_only,
		"aim_note": FireText.aim_note(high_only, limits, ship.crew_quality if ship else ""),
		"dismantling": p != null and p.order.ammo == GunneryTypes.AMMO_DISMANTLING,
		"dismantling_off": chase or not FireRules.dismantling_allowed(range_hexes),
		"dismantling_note": FireText.CHASE_AMMO_NOTE if chase
			else FireText.dismantling_note(range_hexes, bool(st.get("want_dismantling", false))),
		"reduction": model.reduction(ship_id, side, target_id, battery) if battery != "" else 0,
		"number": p.mgn if p else 0,
		"can_fire": p != null and p.can_fire,
		"breakdown": FireText.breakdown_text(p) if p and p.can_fire else (p.reason if p else ""),
		"modifiers": lines,
		"two_target": ""}
	if model.target_ids(ship_id).size() > 1 and DataManager.combat_tables:
		var with_chaser := false
		for o in model.ship_orders(ship_id):
			with_chaser = with_chaser or o.battery == GunneryTypes.BATTERY_CHASE
		out["two_target"] = FireText.two_target_note(DataManager.combat_tables.flat_modifier("two_targets"),
			with_chaser)
	return out


# --- arrows --------------------------------------------------------------------------------------

## One arrow per order (gun and marine), from the firing battery to the target: {ship_id, side
## (MARINES for muskets), target_id, from, to (world points on `grid`), color, text, dim}. `focus`
## (the ring's or target mode's ship) keeps her arrows bright and dims the others; "" dims none.
func arrows(grid: HexGrid, focus: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if model == null or grid == null:
		return out
	var previews := model.order_previews()
	for ship_id in _ids:
		var ship := GameState.get_ship(ship_id)
		if ship == null:
			continue
		var dim := focus != "" and focus != ship_id
		for order in model.ship_orders(ship_id):
			var target := GameState.get_ship(order.target_id)
			if target == null:
				continue
			var p: GunneryTypes.ShotPreview = previews.get(
				FireOrdersModel.order_key(ship_id, order.side, order.target_id, order.battery))
			var text := "%s · %d" % [order.aim, p.mgn] if p else order.aim
			out.append({"ship_id": ship_id, "side": order.side, "target_id": order.target_id,
				"from": _battery_world(grid, ship, order.side, order.battery),
				"to": grid.ship_center_world(target.hex_position, target.facing),
				"color": BroadsideColors.color(order.side), "text": text, "dim": dim})
		var marine_target := model.marine_target(ship_id)
		var mt := GameState.get_ship(marine_target)
		if mt != null:
			var mp := _marine_preview(ship_id, marine_target)
			out.append({"ship_id": ship_id, "side": MARINES, "target_id": marine_target,
				"from": grid.ship_center_world(ship.hex_position, ship.facing),
				"to": grid.ship_center_world(mt.hex_position, mt.facing),
				"color": MUSKET_COLOR, "text": "muskets · %d%%" % int(mp.get("chance", 0)), "dim": dim})
	return out


## In target mode, a "range n" label under each target: {target_id, world, text}.
func range_labels(grid: HexGrid) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if grid == null:
		return out
	for t in targets():
		var ship := GameState.get_ship(t["target_id"])
		if ship != null:
			out.append({"target_id": t["target_id"], "world": grid.ship_center_world(ship.hex_position, ship.facing),
				"text": "range %d" % int(t["range"])})
	return out


static func _battery_world(grid: HexGrid, ship: ShipState, side: int, battery: String) -> Vector3:
	var hexes := ship.occupied_hexes()
	var hex: Vector2i
	if GunneryTypes.is_chase_side(side):
		hex = hexes[1] if side == GunneryTypes.CHASE_STERN else hexes[0]
	elif battery == GunneryTypes.BATTERY_BOW:
		hex = hexes[0]
	elif battery == GunneryTypes.BATTERY_STERN:
		hex = hexes[1]
	else:
		return grid.ship_center_world(ship.hex_position, ship.facing)
	return grid.axial_to_world(hex.x, hex.y)


func _marine_preview(ship_id: String, target_id: String) -> Dictionary:
	for row in model.marine_targets(ship_id):
		if row["target_id"] == target_id:
			return row["preview"]
	return {}


func _target_range(ship_id: String, side: int, target_id: String) -> int:
	for row in model.targets(ship_id, side):
		if row["target_id"] == target_id:
			return int(row["range"])
	return 0


func _name(ship_id: String) -> String:
	return str(_names.get(ship_id, ship_id))


func _on_model_changed() -> void:
	changed.emit()
