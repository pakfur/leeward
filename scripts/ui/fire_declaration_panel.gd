extends Control
## FireDeclarationPanel - Context-panel UI for declaring broadside fire during COMBAT_RESOLUTION.
##
## Lists each own ship that has at least one eligible shot. Each broadside (port/starboard) gets
## an always-visible list of target rows (best target first, "Hold fire" last; only the ship's
## single best shot is selected by default, the other broadside holds fire), an aim toggle and an ammunition toggle, each with the reason when it is locked. Every
## change re-queries GunneryCalculator.preview (a pure query) so the displayed numbers and the
## breakdown are always current. No popups. The panel never mutates game state: pressing the
## main button only emits the assembled order dictionaries for the controller.

signal fire_pressed(orders: Array)
## A ship row was chosen (the controller draws that ship's arcs).
signal ship_focused(ship_id: String)
## A broadside's target (or toggles) changed for this ship.
signal selection_changed(ship_id: String)

const SIDE_NAMES := ["Port", "Starboard"]
const SEPARATOR := " — "
const HIGH_ONLY_NOTE := "Range %d+: must fire high"
const DISMANTLING_NOTE := "Dismantling shot reaches %d hexes"
const D6_NOTE := "A d6 is added when you fire; higher is better."

## Calculator refusal reasons (GunneryCalculator.preview) -> plain words for the "Combat" panel.
const NO_SHOT_ARC := "out of both broadside arcs"
const NO_SHOT_RANGE := "out of range"
const NO_SHOT_LOS := "line of sight blocked"
const NO_SHOT_CREW := "no crew to serve the guns"
const NO_SHOT_STRUCK := "struck"
const NO_SHOT_NO_ENEMY := "no enemy afloat"

@onready var ship_list_container: VBoxContainer = %ShipListContainer
@onready var error_label: Label = %ErrorLabel
@onready var fire_button: Button = %FireButton
@onready var instructions_label: Label = %InstructionsLabel
@onready var two_target_label: Label = %TwoTargetLabel

## ship_id -> {"name": String, "header": Button, "shots": {side: Array[ShotPreview]},
##             "sides": {side: {"target_id","aim","ammo","want_high","want_dismantling"}},
##             "widgets": {side: Dictionary}}
var _ships: Dictionary = {}
var _ship_order: Array[String] = []
var _focused_ship_id: String = ""
var _group := ButtonGroup.new()
var _building: bool = false


# ============================================================================
# Pure presentation helpers (unit tested)
# ============================================================================

## The footer under the ship list, matching the current choice.
static func footer_text(order_count: int, changed: bool) -> String:
	if order_count == 0:
		return "Holding all fire. Pick a target row to fire."
	if changed:
		return "You changed the target. Pick any row to change it again."
	return "Your best shot is chosen; the other broadside holds fire. Pick any row to change it."


## ship_id -> "Topaze — 32-gun Frigate": target rows name each ship with its type.
static func target_names(ships: Array) -> Dictionary:
	var names := {}
	for ship in ships:
		names[ship.ship_id] = PlanningText.name_and_type(ship)
	return names


## "<name> — range N — gunfire M[ — stern rake][ — initial broadside]"
static func option_text(target_name: String, preview: GunneryTypes.ShotPreview) -> String:
	var parts: Array[String] = [target_name, "range %d" % preview.range_hexes, "gunfire %d" % preview.mgn]
	if preview.rake != "":
		parts.append("%s rake" % preview.rake)
	if preview.initial_broadside:
		parts.append("initial broadside")
	return SEPARATOR.join(parts)


## One "name value" line per modifier, e.g. "rake +2".
static func modifier_lines(preview: GunneryTypes.ShotPreview) -> Array[String]:
	var lines: Array[String] = []
	for m in preview.modifiers:
		lines.append("%s %+d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))), int(m.get("value", 0))])
	return lines


## "Base 18, initial broadside +4 = 22. A d6 is added when you fire; higher is better."
static func breakdown_text(preview: GunneryTypes.ShotPreview) -> String:
	var lines := modifier_lines(preview)
	var sum := "Base %d" % preview.bgn
	if not lines.is_empty():
		sum += ", %s = %d" % [", ".join(lines), preview.mgn]
	return "%s. %s" % [sum, D6_NOTE]


## What the main button does: "Fire 1 broadside" / "Fire 2 broadsides" / "Hold all fire".
static func fire_button_text(order_count: int) -> String:
	if order_count <= 0:
		return "Hold all fire"
	return "Fire %d broadside%s" % [order_count, "" if order_count == 1 else "s"]


## Radio-style marker so the chosen row is obvious at a glance.
static func row_marker(chosen: bool) -> String:
	return "● " if chosen else "○ "


static func dismantling_allowed(range_hexes: int) -> bool:
	return range_hexes <= GunneryCalculator.MAX_DISMANTLING_RANGE


## High fire is forced when the range only allows it.
static func effective_aim(wanted_aim: String, high_only: bool) -> String:
	return GunneryTypes.AIM_HIGH if high_only else wanted_aim


## Dismantling only when the player asked for it and the range allows it; roundshot otherwise.
static func effective_ammo(want_dismantling: bool, range_hexes: int) -> String:
	return GunneryTypes.AMMO_DISMANTLING if want_dismantling and dismantling_allowed(range_hexes) \
		else GunneryTypes.AMMO_ROUND


## Why "High fire" is locked on, "" when the player may choose.
static func aim_note(high_only: bool) -> String:
	return HIGH_ONLY_NOTE % GunneryCalculator.HIGH_ONLY_RANGE if high_only else ""


## Why "Dismantling" is unavailable, "" when it may be chosen. Says so when the player's choice
## is being replaced by roundshot for this target.
static func dismantling_note(range_hexes: int, want_dismantling: bool) -> String:
	if dismantling_allowed(range_hexes):
		return ""
	var note := DISMANTLING_NOTE % GunneryCalculator.MAX_DISMANTLING_RANGE
	return note + " — roundshot this time" if want_dismantling else note


## Target rows in display order: highest modified gunfire number first, then nearest, then name.
## Each entry is {"target_id", "mgn", "range", "name"}; returns a sorted copy.
static func rank_targets(entries: Array) -> Array:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return _better_row(x, y))
	return sorted


## Which broadside starts with a target: the one whose best row is the best one-target shot
## (highest modified number, then nearest, then name; port before starboard on a full tie).
## `ranked_by_side` is side -> rank_targets() output. The other broadside starts on hold fire,
## because firing both costs the two-target modifier on each shot. -1 when no side has a row.
static func default_side(ranked_by_side: Dictionary) -> int:
	var best_side := -1
	var best: Dictionary = {}
	var sides := ranked_by_side.keys()
	sides.sort()
	for side in sides:
		var rows: Array = ranked_by_side[side]
		if rows.is_empty():
			continue
		var top: Dictionary = rows[0]
		if best_side < 0 or _better_row(top, best):
			best_side = int(side)
			best = top
	return best_side


static func _better_row(x: Dictionary, y: Dictionary) -> bool:
	if int(x["mgn"]) != int(y["mgn"]):
		return int(x["mgn"]) > int(y["mgn"])
	if int(x["range"]) != int(y["range"]):
		return int(x["range"]) < int(y["range"])
	return str(x["name"]) < str(y["name"])


## Shown next to the main button while some ship fires both broadsides, e.g.
## "Two targets: −12 on each broadside". `modifier` is the (negative) two-target modifier.
static func two_target_note(modifier: int) -> String:
	return "Two targets: %s%d on each broadside" % ["−" if modifier < 0 else "+", absi(modifier)]


## The main reason a ship cannot fire at its nearest enemy, in plain words, from the calculator's
## refusal reasons for each broadside. A reason other than "not in the arc" wins (it means the
## target IS in that broadside's arc). Empty `reasons` means there is no enemy to shoot at.
static func no_shot_reason(reasons: Array) -> String:
	if reasons.is_empty():
		return NO_SHOT_NO_ENEMY
	var chosen := ""
	for r in reasons:
		var text := str(r)
		if not text.contains("arc"):
			chosen = text
			break
	if chosen == "":
		return NO_SHOT_ARC
	if chosen.contains("struck"):
		return NO_SHOT_STRUCK
	if chosen.contains("line of sight"):
		return NO_SHOT_LOS
	if chosen.contains("sailor") or chosen.contains("crew"):
		return NO_SHOT_CREW
	if chosen.contains("range"):
		return NO_SHOT_RANGE
	return chosen


## Order dictionaries (FireOrder.to_dict()) for one ship, in side order. Sides on hold fire
## (empty target_id) produce no order. `sides` is side -> {"target_id", "aim", "ammo"}.
static func build_orders(ship_id: String, sides: Dictionary) -> Array:
	var orders: Array = []
	var keys := sides.keys()
	keys.sort()
	for side in keys:
		var s: Dictionary = sides[side]
		if str(s.get("target_id", "")) == "":
			continue
		var order := GunneryTypes.FireOrder.new()
		order.ship_id = ship_id
		order.side = int(side)
		order.target_id = str(s["target_id"])
		order.aim = str(s.get("aim", GunneryTypes.AIM_LOW))
		order.ammo = str(s.get("ammo", GunneryTypes.AMMO_ROUND))
		orders.append(order.to_dict())
	return orders


# ============================================================================
# Setup
# ============================================================================

func _ready() -> void:
	fire_button.pressed.connect(_on_fire_pressed)
	error_label.visible = false


## Build rows for the given ships that have eligible shots. Returns how many were listed.
func setup(ship_ids: Array) -> int:
	_clear()
	_building = true
	var calculator: GunneryCalculator = GameState.gunnery_calculator
	for ship_id in ship_ids:
		var ship_state: ShipState = GameState.get_ship(ship_id)
		if ship_state == null:
			continue
		var shots_by_side := {}
		for shot in calculator.eligible_shots(ship_id):
			var side := shot.order.side
			if not shots_by_side.has(side):
				shots_by_side[side] = []
			shots_by_side[side].append(shot)
		if shots_by_side.is_empty():
			continue
		_add_ship(ship_state, shots_by_side)
	_building = false
	for ship_id in _ship_order:
		_refresh_ship(ship_id)
	_update_fire_button()
	if not _ship_order.is_empty():
		focus_ship(_ship_order[0])
	return _ship_order.size()


func get_focused_ship() -> String:
	return _focused_ship_id


func focus_ship(ship_id: String) -> void:
	if not _ships.has(ship_id):
		return
	_focused_ship_id = ship_id
	var header: Button = _ships[ship_id]["header"]
	header.set_pressed_no_signal(true)
	ship_focused.emit(ship_id)


## Target ship ids currently chosen for a ship (hold-fire sides omitted).
func get_target_ids(ship_id: String) -> Array[String]:
	var ids: Array[String] = []
	if not _ships.has(ship_id):
		return ids
	for side in _ships[ship_id]["sides"]:
		var target_id: String = _ships[ship_id]["sides"][side]["target_id"]
		if target_id != "":
			ids.append(target_id)
	return ids


func get_all_orders() -> Array:
	var orders: Array = []
	for ship_id in _ship_order:
		orders.append_array(build_orders(ship_id, _ships[ship_id]["sides"]))
	return orders


## Choose a broadside's target ("" holds fire). Same effect as clicking that row.
func select_target(ship_id: String, side: int, target_id: String) -> void:
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return
	_ships[ship_id]["sides"][side]["target_id"] = target_id
	_on_side_changed(ship_id, side)


## Ask for high fire / dismantling shot on a broadside. Same effect as pressing the toggles.
func set_want_high(ship_id: String, side: int, on: bool) -> void:
	if _ships.has(ship_id) and _ships[ship_id]["sides"].has(side):
		_ships[ship_id]["sides"][side]["want_high"] = on
		_on_side_changed(ship_id, side)


func set_want_dismantling(ship_id: String, side: int, on: bool) -> void:
	if _ships.has(ship_id) and _ships[ship_id]["sides"].has(side):
		_ships[ship_id]["sides"][side]["want_dismantling"] = on
		_on_side_changed(ship_id, side)


func show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = message != ""
	fire_button.disabled = false


## After the server accepted the orders: lock the panel while combat resolves.
func show_submitted() -> void:
	error_label.visible = false
	fire_button.disabled = true
	fire_button.text = "Orders submitted"
	instructions_label.text = "Resolving combat..."
	for ship_id in _ship_order:
		for side in _ships[ship_id]["widgets"]:
			var w: Dictionary = _ships[ship_id]["widgets"][side]
			for button: Button in w["targets"].values():
				button.disabled = true
			w["high"].disabled = true
			w["dismantling"].disabled = true


func _clear() -> void:
	for child in ship_list_container.get_children():
		child.queue_free()
	_ships.clear()
	_ship_order.clear()
	_focused_ship_id = ""
	_group = ButtonGroup.new()
	error_label.visible = false
	fire_button.disabled = false
	fire_button.text = fire_button_text(0)
	instructions_label.text = footer_text(1, false)


func _add_ship(ship_state: ShipState, shots_by_side: Dictionary) -> void:
	var ship_id := ship_state.ship_id
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	ship_list_container.add_child(box)

	var header := Button.new()
	header.text = PlanningText.name_and_type(ship_state)
	header.toggle_mode = true
	header.button_group = _group
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.pressed.connect(func(): focus_ship(ship_id))
	box.add_child(header)

	var entry := {"name": ship_state.ship_name, "header": header,
		"shots": shots_by_side, "sides": {}, "widgets": {}, "defaults": {}}
	_ships[ship_id] = entry
	_ship_order.append(ship_id)

	var names := target_names(GameState.get_all_ships())
	var ranked_by_side := {}
	for side in [ShipState.PORT, ShipState.STARBOARD]:
		if not shots_by_side.has(side):
			continue
		# Rank with the defaults the server would preview (low unless forced, roundshot, one target).
		var ranked_entries: Array = []
		for shot: GunneryTypes.ShotPreview in shots_by_side[side]:
			var target_id := shot.order.target_id
			ranked_entries.append({"target_id": target_id, "mgn": shot.mgn,
				"range": shot.range_hexes, "name": str(names.get(target_id, target_id))})
		ranked_by_side[side] = rank_targets(ranked_entries)
	var firing_side := default_side(ranked_by_side)
	for side in [ShipState.PORT, ShipState.STARBOARD]:
		if not ranked_by_side.has(side):
			continue
		var ranked: Array = ranked_by_side[side]
		var start_target: String = str(ranked[0]["target_id"]) if side == firing_side else ""
		entry["defaults"][side] = start_target
		entry["sides"][side] = {"target_id": start_target, "aim": GunneryTypes.AIM_LOW,
			"ammo": GunneryTypes.AMMO_ROUND, "want_high": false, "want_dismantling": false}
		entry["widgets"][side] = _build_side(box, ship_id, side, ranked)
	box.add_child(HSeparator.new())


func _build_side(parent: VBoxContainer, ship_id: String, side: int, ranked: Array) -> Dictionary:
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 6)
	var swatch := ColorRect.new()
	swatch.name = "ArcSwatch"
	swatch.color = BroadsideColors.color(side)  # the same constant draws this side's arc on the map
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(swatch)
	var label := Label.new()
	label.text = "%s broadside" % SIDE_NAMES[side]
	title.add_child(label)
	parent.add_child(title)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	parent.add_child(rows)
	var group := ButtonGroup.new()
	var targets := {}
	for row in ranked:
		targets[str(row["target_id"])] = _target_row(rows, group, ship_id, side, str(row["target_id"]))
	targets[""] = _target_row(rows, group, ship_id, side, "")

	var breakdown := Label.new()
	breakdown.theme_type_variation = &"SecondaryLabel"
	breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(breakdown)

	var high := _toggle_row(parent, "High fire")
	var dismantling := _toggle_row(parent, "Dismantling")
	high["button"].toggled.connect(func(on: bool): set_want_high(ship_id, side, on))
	dismantling["button"].toggled.connect(func(on: bool): set_want_dismantling(ship_id, side, on))
	return {"targets": targets, "rows": ranked, "high": high["button"], "high_note": high["note"],
		"dismantling": dismantling["button"], "dismantling_note": dismantling["note"],
		"breakdown": breakdown}


func _target_row(parent: VBoxContainer, group: ButtonGroup, ship_id: String, side: int,
		target_id: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.theme_type_variation = &"SecondaryButton"
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): select_target(ship_id, side, target_id))
	parent.add_child(button)
	return button


func _toggle_row(parent: VBoxContainer, text: String) -> Dictionary:
	var row := HBoxContainer.new()
	var button := CheckButton.new()
	button.text = text
	button.theme_type_variation = &"SecondaryCheckButton"
	button.focus_mode = Control.FOCUS_NONE
	row.add_child(button)
	var note := Label.new()
	note.theme_type_variation = &"SecondaryLabel"
	note.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.custom_minimum_size = Vector2(80, 0)
	row.add_child(note)
	parent.add_child(row)
	return {"button": button, "note": note}


# ============================================================================
# Reacting to changes
# ============================================================================

func _on_side_changed(ship_id: String, _side: int) -> void:
	if _building:
		return
	_refresh_ship(ship_id)
	_update_fire_button()
	error_label.visible = false
	selection_changed.emit(ship_id)


func _update_fire_button() -> void:
	if fire_button.text != "Orders submitted":
		var order_count := get_all_orders().size()
		fire_button.text = fire_button_text(order_count)
		instructions_label.text = footer_text(order_count, targets_changed())
	if two_target_label:
		two_target_label.text = two_target_note(DataManager.combat_tables.flat_modifier("two_targets")) \
			if DataManager.combat_tables else ""
		two_target_label.visible = any_ship_fires_both()


## True once the player picked a target (or hold fire) other than the one chosen for them.
func targets_changed() -> bool:
	for ship_id in _ship_order:
		var entry: Dictionary = _ships[ship_id]
		for side in entry["sides"]:
			if entry["sides"][side]["target_id"] != entry["defaults"].get(side, ""):
				return true
	return false


## True while some listed ship has a target on both broadsides.
func any_ship_fires_both() -> bool:
	for ship_id in _ship_order:
		if get_target_ids(ship_id).size() > 1:
			return true
	return false


## Re-query previews for every broadside of a ship and refresh rows, toggles, notes and breakdowns.
## The player's wishes (want_high, want_dismantling) are kept apart from what the order will
## actually be, so a forced high aim or a roundshot fallback never sticks to another target.
func _refresh_ship(ship_id: String) -> void:
	var entry: Dictionary = _ships[ship_id]
	var sides: Dictionary = entry["sides"]
	var names := target_names(GameState.get_all_ships())
	for side in sides:
		var state: Dictionary = sides[side]
		var widgets: Dictionary = entry["widgets"][side]
		# Firing both broadsides costs the two-target modifier on each shot.
		var two_targets := false
		for other_side in sides:
			if other_side != side and sides[other_side]["target_id"] != "":
				two_targets = true

		for target_id: String in widgets["targets"]:
			var button: Button = widgets["targets"][target_id]
			var chosen: bool = target_id == state["target_id"]
			button.set_pressed_no_signal(chosen)
			var text := "Hold fire"
			if target_id != "":
				var row_preview := _preview_for(ship_id, side, target_id, state["want_dismantling"], two_targets)
				text = option_text(str(names.get(target_id, target_id)), row_preview)
			button.text = row_marker(chosen) + text

		var holding: bool = state["target_id"] == ""
		var high: CheckButton = widgets["high"]
		var dismantling: CheckButton = widgets["dismantling"]
		var breakdown: Label = widgets["breakdown"]
		if holding:
			state["aim"] = GunneryTypes.AIM_LOW
			state["ammo"] = GunneryTypes.AMMO_ROUND
			high.disabled = true
			high.set_pressed_no_signal(state["want_high"])
			dismantling.disabled = true
			dismantling.set_pressed_no_signal(state["want_dismantling"])
			widgets["high_note"].text = ""
			widgets["dismantling_note"].text = ""
			breakdown.text = "This broadside holds fire."
			continue

		var p := _preview_for(ship_id, side, state["target_id"], state["want_dismantling"], two_targets)
		state["ammo"] = effective_ammo(state["want_dismantling"], p.range_hexes)
		var wanted_aim := GunneryTypes.AIM_HIGH if state["want_high"] else GunneryTypes.AIM_LOW
		state["aim"] = effective_aim(wanted_aim, p.high_only)
		high.disabled = p.high_only
		high.set_pressed_no_signal(state["aim"] == GunneryTypes.AIM_HIGH)
		widgets["high_note"].text = aim_note(p.high_only)
		dismantling.disabled = not dismantling_allowed(p.range_hexes)
		dismantling.set_pressed_no_signal(state["ammo"] == GunneryTypes.AMMO_DISMANTLING)
		widgets["dismantling_note"].text = dismantling_note(p.range_hexes, state["want_dismantling"])
		breakdown.text = breakdown_text(p)


## Preview a shot with the ammunition the order would actually carry at that target's range.
func _preview_for(ship_id: String, side: int, target_id: String, want_dismantling: bool,
		two_targets: bool) -> GunneryTypes.ShotPreview:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = side
	order.target_id = target_id
	order.ammo = GunneryTypes.AMMO_ROUND
	var p: GunneryTypes.ShotPreview = GameState.gunnery_calculator.preview(order, two_targets)
	if want_dismantling and dismantling_allowed(p.range_hexes):
		order.ammo = GunneryTypes.AMMO_DISMANTLING
		p = GameState.gunnery_calculator.preview(order, two_targets)
	return p


func _on_fire_pressed() -> void:
	fire_pressed.emit(get_all_orders())
