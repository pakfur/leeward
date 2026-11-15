extends Control
## FireDeclarationPanel - Context-panel UI for declaring broadside fire during COMBAT_RESOLUTION.
##
## Lists each own ship that has at least one eligible shot; ships without one are listed greyed
## underneath with the reason in plain words. Each broadside (port/starboard) gets
## an always-visible list of target rows (nearest target first, "Hold fire" last; only the ship's
## single best shot is selected by default, the other broadside holds fire), an aim toggle and an
## ammunition toggle, each with the reason when it is locked.
## Each target row names the battery it fires (7.B.1): "Full broadside" (only when both the bow
## and the stern battery bear), "Bow battery" and "Stern battery" (half broadsides), one row per
## battery that bears, in that order. A side may split, bow battery at one target and stern
## battery at another.
## The firing rules themselves (full vs half, target cap, forced aim, ammunition range) live in
## FireRules on the server side; this panel only keeps widget state and text.
## Every change re-queries GunneryCalculator.preview_orders (a pure query) for the ship's whole
## order set, so the numbers and the breakdown are those the resolver will roll (two targets, half
## broadside, initial broadside once per broadside). No popups. The panel never mutates game
## state: pressing the main button only emits the assembled order dictionaries.

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
const BATTERY_LABELS := {
	GunneryTypes.BATTERY_FULL: "Full broadside",
	GunneryTypes.BATTERY_BOW: "Bow battery",
	GunneryTypes.BATTERY_STERN: "Stern battery",
}

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
@onready var scroll: ScrollContainer = %ScrollContainer
@onready var more_below_label: Label = %MoreBelowLabel

const NO_SHOT_COLOR := Color(0.6, 0.62, 0.66)

## ship_id -> {"name": String, "header": Button,
##             "options": {side: {target_id: {battery: ShotPreview}}} (one-target eligible shots),
##             "sides": {side: {"bow", "stern", "want_high", "want_dismantling"}} (target per battery),
##             "defaults": {side: {"bow", "stern"}}, "widgets": {side: Dictionary}}
var _ships: Dictionary = {}
var _ship_order: Array[String] = []
var _focused_ship_id: String = ""
var _group := ButtonGroup.new()
var _building: bool = false
## Order-set key -> preview_orders() result, for this setup(). Game state does not change while the
## panel is open (fire is declared, not resolved), so a set's previews never go stale; _clear()
## empties it. Saves re-previewing every unchosen row's order set on each refresh.
var _preview_cache: Dictionary = {}


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


## "<name>[ — Bow battery] — range N — gunfire M[ — stern rake][ — initial broadside]"
static func option_text(target_name: String, preview: GunneryTypes.ShotPreview, battery: String = "") -> String:
	var parts: Array[String] = [target_name]
	if battery != "":
		parts.append(battery_label(battery))
	parts.append_array(["range %d" % preview.range_hexes, "gunfire %d" % preview.mgn])
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
## A half broadside leads: "Half broadside −8 on base 18, crew +1 = 11. ..." (only when the
## calculator applied it: with two targets it does not, 7.C.12g).
static func breakdown_text(preview: GunneryTypes.ShotPreview) -> String:
	var half := 0
	var lines: Array[String] = []
	for m in preview.modifiers:
		if str(m.get("name", "")) == "half_broadside":
			half = int(m.get("value", 0))
		else:
			lines.append("%s %+d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))), int(m.get("value", 0))])
	var sum := "Base %d" % preview.bgn
	if half != 0:
		sum = "%s on base %d" % [half_broadside_text(half), preview.bgn]
	if not lines.is_empty():
		sum += ", " + ", ".join(lines)
	if half != 0 or not lines.is_empty():
		sum += " = %d" % preview.mgn
	return "%s. %s" % [sum, D6_NOTE]


## "Half broadside −8" (true minus sign).
static func half_broadside_text(value: int) -> String:
	return "Half broadside %s%d" % ["−" if value < 0 else "+", absi(value)]


## "Full broadside", "Bow battery" or "Stern battery".
static func battery_label(battery: String) -> String:
	return str(BATTERY_LABELS.get(battery, battery))


## The batteries a target can be fired at with from one side, from its eligible previews, in
## GunneryTypes.BATTERIES order: "full" only when both batteries bear, and each single battery
## that bears (each gets its own row, so a side can split or fire a half broadside).
static func battery_options(previews: Array) -> Array[String]:
	var can := {}
	for p: GunneryTypes.ShotPreview in previews:
		if p.can_fire and p.order != null:
			can[p.order.battery] = true
	var options: Array[String] = []
	for battery in GunneryTypes.BATTERIES:
		if can.has(battery):
			options.append(battery)
	return options


## eligible_shots() output grouped as side -> target_id -> battery -> ShotPreview.
static func options_by_target(shots: Array[GunneryTypes.ShotPreview]) -> Dictionary:
	var by_side := {}
	for shot in shots:
		var side := shot.order.side
		if not by_side.has(side):
			by_side[side] = {}
		if not by_side[side].has(shot.order.target_id):
			by_side[side][shot.order.target_id] = {}
		by_side[side][shot.order.target_id][shot.order.battery] = shot
	return by_side


## Widget key of a target row ("" is the hold-fire row).
static func row_key(target_id: String, battery: String) -> String:
	return "" if target_id == "" else "%s|%s" % [target_id, battery]


## Whether the row (target_id, battery) is what the side currently fires.
static func row_chosen(bow: String, stern: String, target_id: String, battery: String) -> bool:
	match battery:
		GunneryTypes.BATTERY_FULL:
			return bow == target_id and stern == target_id
		GunneryTypes.BATTERY_BOW:
			return bow == target_id and stern != target_id
		GunneryTypes.BATTERY_STERN:
			return stern == target_id and bow != target_id
	return false


## Row-click state transition for one side (widget state only; FireRules.side_shots turns it
## into shots). `state` has "bow" and "stern" (target per battery). target_id "" holds fire;
## picking the chosen row again holds what it fires; "full" aims both batteries at the target;
## a single battery aims only that battery, and a full broadside at that target becomes the half.
static func choose_battery(state: Dictionary, target_id: String, battery: String) -> Dictionary:
	var bow: String = str(state.get("bow", ""))
	var stern: String = str(state.get("stern", ""))
	if target_id == "":
		return {"bow": "", "stern": ""}
	var chosen := row_chosen(bow, stern, target_id, battery)
	match battery:
		GunneryTypes.BATTERY_FULL:
			bow = "" if chosen else target_id
			stern = bow
		GunneryTypes.BATTERY_BOW:
			bow = "" if chosen else target_id
			if stern == target_id:
				stern = ""
		GunneryTypes.BATTERY_STERN:
			stern = "" if chosen else target_id
			if bow == target_id:
				bow = ""
	return {"bow": bow, "stern": stern}


## A ship's FireOrders for its sides (side -> {"bow", "stern", "want_high", "want_dismantling"})
## through FireRules (bow+stern at one target = full broadside, forced aim, ammunition range).
## `ranges` is target_id -> range in hexes.
static func panel_orders(ship_id: String, sides: Dictionary, ranges: Dictionary) -> Array[GunneryTypes.FireOrder]:
	var orders: Array[GunneryTypes.FireOrder] = []
	var keys := sides.keys()
	keys.sort()
	for side in keys:
		var state: Dictionary = sides[side]
		for shot: Dictionary in FireRules.side_shots(state["bow"], state["stern"]):
			orders.append(FireRules.make_order(ship_id, int(side), shot["target_id"], shot["battery"],
				bool(state.get("want_high", false)), bool(state.get("want_dismantling", false)),
				int(ranges.get(shot["target_id"], 0))))
	return orders


## What the main button does: "Fire 1 broadside", "Fire 2 half broadsides", "Fire 1 broadside and
## 1 half broadside" or "Hold all fire". A full-broadside order counts as a broadside, a bow or stern
## battery order as a half broadside (a side split between two targets is two half broadsides).
static func fire_button_text(full_count: int, half_count: int = 0) -> String:
	var parts := PackedStringArray()
	if full_count > 0:
		parts.append("%d broadside%s" % [full_count, "" if full_count == 1 else "s"])
	if half_count > 0:
		parts.append("%d half broadside%s" % [half_count, "" if half_count == 1 else "s"])
	if parts.is_empty():
		return "Hold all fire"
	return "Fire " + " and ".join(parts)


## fire_button_text() for a set of orders.
static func fire_button_text_for(orders: Array) -> String:
	var full := 0
	for order in orders:
		if order.battery == GunneryTypes.BATTERY_FULL:
			full += 1
	return fire_button_text(full, orders.size() - full)


## Radio-style marker so the chosen row is obvious at a glance.
static func row_marker(chosen: bool) -> String:
	return "● " if chosen else "○ "


## Why "High fire" is locked on, "" when the player may choose.
static func aim_note(high_only: bool) -> String:
	return HIGH_ONLY_NOTE % FireRules.HIGH_ONLY_RANGE if high_only else ""


## Why "Dismantling" is unavailable, "" when it may be chosen. Says so when the player's choice
## is being replaced by roundshot for this target.
static func dismantling_note(range_hexes: int, want_dismantling: bool) -> String:
	if FireRules.dismantling_allowed(range_hexes):
		return ""
	var note := DISMANTLING_NOTE % FireRules.MAX_DISMANTLING_RANGE
	return note + " — roundshot this time" if want_dismantling else note


## Target rows in display order: highest modified gunfire number first, then nearest, then name.
## Each entry is {"target_id", "mgn", "range", "name"}; returns a sorted copy.
static func rank_targets(entries: Array) -> Array:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return _better_row(x, y))
	return sorted


## Target rows in list order: nearest first, then name, then target id (the default choice is
## still the best shot, rank_targets). Each entry has "target_id", "range" and "name"; returns a
## sorted copy. Within a target the rows go Full, Bow, Stern (battery_options).
static func display_order(entries: Array) -> Array:
	var sorted := entries.duplicate()
	sorted.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["range"]) != int(y["range"]):
			return int(x["range"]) < int(y["range"])
		if str(x["name"]) != str(y["name"]):
			return str(x["name"]) < str(y["name"])
		return str(x["target_id"]) < str(y["target_id"]))
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


## "HMS Phoebe — no broadside bears: out of range": one ship's no-shot line, in the fire panel and
## in the "Combat" panel alike.
static func no_shot_line(ship_name: String, reason: String) -> String:
	return "%s%sno broadside bears: %s" % [ship_name, SEPARATOR, reason]


## The nearest enemy afloat (ties by ship id), null when none. Distance on `grid` from the closest
## hex of one footprint to the closest hex of the other.
static func nearest_enemy(ship: ShipState, all_ships: Array, grid: HexGrid) -> ShipState:
	var nearest: ShipState = null
	var best := 1 << 30
	if grid == null:
		return null
	var geometry := FireGeometry.new(grid)
	for other: ShipState in all_ships:
		if other.player_id == ship.player_id or other.is_struck():
			continue
		var d := geometry.range_between(ship.occupied_hexes(), other.occupied_hexes())
		if d < best or (d == best and other.ship_id < nearest.ship_id):
			best = d
			nearest = other
	return nearest


## Why `ship` has no shot, in plain words: its calculator previews (a pure query) of both
## broadsides against its nearest enemy, mapped by no_shot_reason(). `calculator` is a
## GunneryCalculator (anything with preview(order)).
static func ship_no_shot_reason(ship: ShipState, all_ships: Array, calculator, grid: HexGrid) -> String:
	if ship.is_struck():
		return NO_SHOT_STRUCK
	var reasons: Array = []
	var target := nearest_enemy(ship, all_ships, grid)
	if target and calculator:
		for side in [ShipState.PORT, ShipState.STARBOARD]:
			var reason := _no_shot_preview(calculator, ship.ship_id, side, target.ship_id,
				GunneryTypes.BATTERY_FULL)
			# Only one battery bears: its own preview gives the real reason (crew, range...).
			if reason.contains("needs both"):
				for battery in [GunneryTypes.BATTERY_BOW, GunneryTypes.BATTERY_STERN]:
					var single := _no_shot_preview(calculator, ship.ship_id, side, target.ship_id, battery)
					if not single.contains("arc") and not single.contains("line of sight"):
						reason = single
						break
			reasons.append(reason)
	return no_shot_reason(reasons)


static func _no_shot_preview(calculator, ship_id: String, side: int, target_id: String, battery: String) -> String:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = side
	order.target_id = target_id
	order.battery = battery
	return str(calculator.preview(order).reason)


## True while part of the list is hidden below the visible area (the "More below" hint shows).
static func more_below(scroll_value: float, page: float, content_height: float) -> bool:
	return scroll_value + page < content_height - 1.0


# ============================================================================
# Setup
# ============================================================================

func _ready() -> void:
	fire_button.pressed.connect(_on_fire_pressed)
	error_label.visible = false
	_style_scrollbar()
	var bar := scroll.get_v_scroll_bar()
	bar.value_changed.connect(func(_v: float): _update_more_below())
	bar.changed.connect(_update_more_below)
	scroll.resized.connect(_update_more_below)


## A scrollbar wide and bright enough to notice: the panel often holds more than fits.
func _style_scrollbar() -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 10
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.08)
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(0.75, 0.8, 0.88, 0.85 if state == "grabber" else 1.0)
		grab.set_corner_radius_all(4)
		bar.add_theme_stylebox_override(state, grab)


func _update_more_below() -> void:
	if not is_instance_valid(scroll) or not more_below_label:
		return
	var bar := scroll.get_v_scroll_bar()
	more_below_label.visible = more_below(bar.value, bar.page, bar.max_value)


## Scroll so `control` (a row of the list) is in view; deferred so a fresh layout is used.
func _reveal(control: Control) -> void:
	if is_instance_valid(control) and is_instance_valid(scroll):
		scroll.ensure_control_visible.call_deferred(control)


## Build rows for the given ships that have eligible shots. Returns how many were listed.
func setup(ship_ids: Array) -> int:
	_clear()
	_building = true
	var calculator: GunneryCalculator = GameState.gunnery_calculator
	var no_shot: Array[ShipState] = []
	for ship_id in ship_ids:
		var ship_state: ShipState = GameState.get_ship(ship_id)
		if ship_state == null:
			continue
		var options := options_by_target(calculator.eligible_shots(ship_id))
		if options.is_empty():
			no_shot.append(ship_state)
			continue
		_add_ship(ship_state, options)
	var grid: HexGrid = GameState.fire_geometry.hex_grid if GameState.fire_geometry else null
	for ship_state in no_shot:
		_add_no_shot_row(no_shot_line(ship_state.ship_name,
			ship_no_shot_reason(ship_state, GameState.get_all_ships(), calculator, grid)))
	_building = false
	for ship_id in _ship_order:
		_refresh_ship(ship_id)
	_update_fire_button()
	if not _ship_order.is_empty():
		focus_ship(_ship_order[0])
	return _ship_order.size()


## The greyed no-shot lines, in list order.
func get_no_shot_lines() -> Array[String]:
	var lines: Array[String] = []
	for child in ship_list_container.get_children():
		if child.has_meta("no_shot") and not child.is_queued_for_deletion():
			lines.append((child as Label).text)
	return lines


func get_focused_ship() -> String:
	return _focused_ship_id


func focus_ship(ship_id: String) -> void:
	if not _ships.has(ship_id):
		return
	_focused_ship_id = ship_id
	var header: Button = _ships[ship_id]["header"]
	header.set_pressed_no_signal(true)
	_reveal(header)
	ship_focused.emit(ship_id)


## Target ship ids currently chosen for a ship, each once (holding batteries omitted).
func get_target_ids(ship_id: String) -> Array[String]:
	var ids: Array[String] = []
	if not _ships.has(ship_id):
		return ids
	for target_id in FireRules.battery_targets(_ships[ship_id]["sides"]):
		ids.append(str(target_id))
	return ids


## The single batteries ("bow", "stern") that fire from `side` of a ship; [] while it holds fire.
func get_batteries(ship_id: String, side: int) -> Array[String]:
	var batteries: Array[String] = []
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return batteries
	var state: Dictionary = _ships[ship_id]["sides"][side]
	if state["bow"] != "":
		batteries.append(GunneryTypes.BATTERY_BOW)
	if state["stern"] != "":
		batteries.append(GunneryTypes.BATTERY_STERN)
	return batteries


func get_all_orders() -> Array:
	var orders: Array = []
	for ship_id in _ship_order:
		for order in _orders(ship_id, _ships[ship_id]["sides"]):
			orders.append(order.to_dict())
	return orders


## Pick a broadside's target row (target_id, battery); target_id "" holds fire, battery "" means
## the target's preferred battery (a full broadside when both bear). Picking the chosen row again
## holds what it fires. Same effect as clicking the row.
func select_target(ship_id: String, side: int, target_id: String, battery: String = "") -> void:
	if not _ships.has(ship_id) or not _ships[ship_id]["sides"].has(side):
		return
	if target_id != "":
		var options := _battery_options_for(ship_id, side, target_id)
		if battery == "" and not options.is_empty():
			battery = options[0]
		if not options.has(battery):
			return
	_ships[ship_id]["sides"] = _apply_choice(ship_id, side, target_id, battery)
	_on_side_changed(ship_id, side)
	var row: Button = _ships[ship_id]["widgets"][side]["targets"].get(row_key(target_id, battery))
	if row:
		_reveal(row)


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
	_preview_cache.clear()
	_focused_ship_id = ""
	_group = ButtonGroup.new()
	error_label.visible = false
	fire_button.disabled = false
	fire_button.text = fire_button_text(0)
	instructions_label.text = footer_text(1, false)


func _add_ship(ship_state: ShipState, options: Dictionary) -> void:
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
		"options": options, "sides": {}, "widgets": {}, "defaults": {}}
	_ships[ship_id] = entry
	_ship_order.append(ship_id)

	var names := target_names(GameState.get_all_ships())
	var ranked_by_side := {}
	for side in [ShipState.PORT, ShipState.STARBOARD]:
		if not options.has(side):
			continue
		# Rank by each target's preferred battery (full broadside when both bear), one target.
		var ranked_entries: Array = []
		for target_id: String in options[side]:
			var battery: String = _battery_options_for(ship_id, side, target_id)[0]  # full first
			var shot: GunneryTypes.ShotPreview = options[side][target_id][battery]
			ranked_entries.append({"target_id": target_id, "mgn": shot.mgn, "battery": battery,
				"range": shot.range_hexes, "name": str(names.get(target_id, target_id))})
		ranked_by_side[side] = rank_targets(ranked_entries)
	var firing_side := default_side(ranked_by_side)
	for side in [ShipState.PORT, ShipState.STARBOARD]:
		if not ranked_by_side.has(side):
			continue
		var ranked: Array = ranked_by_side[side]
		var start := {"bow": "", "stern": ""}
		if side == firing_side:
			start = choose_battery(start, str(ranked[0]["target_id"]), str(ranked[0]["battery"]))
		entry["defaults"][side] = start.duplicate()
		entry["sides"][side] = {"bow": start["bow"], "stern": start["stern"],
			"want_high": false, "want_dismantling": false}
		entry["widgets"][side] = _build_side(box, ship_id, side, display_order(ranked))
	box.add_child(HSeparator.new())


## A greyed, unclickable line for an own ship with no shot this turn.
func _add_no_shot_row(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.set_meta("no_shot", true)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = &"SecondaryLabel"
	label.add_theme_color_override("font_color", NO_SHOT_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ship_list_container.add_child(label)


func _build_side(parent: VBoxContainer, ship_id: String, side: int, rows_in_order: Array) -> Dictionary:
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
	var targets := {}
	for row in rows_in_order:
		var target_id := str(row["target_id"])
		for battery in _battery_options_for(ship_id, side, target_id):
			targets[row_key(target_id, battery)] = _target_row(rows, ship_id, side, target_id, battery)
	targets[""] = _target_row(rows, ship_id, side, "", "")

	var breakdown := Label.new()
	breakdown.theme_type_variation = &"SecondaryLabel"
	breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(breakdown)

	var high := _toggle_row(parent, "High fire")
	var dismantling := _toggle_row(parent, "Dismantling")
	high["button"].toggled.connect(func(on: bool): set_want_high(ship_id, side, on))
	dismantling["button"].toggled.connect(func(on: bool): set_want_dismantling(ship_id, side, on))
	return {"targets": targets, "rows": rows_in_order, "high": high["button"], "high_note": high["note"],
		"dismantling": dismantling["button"], "dismantling_note": dismantling["note"],
		"breakdown": breakdown}


## A target row. Not in a ButtonGroup: on a split side two rows (bow and stern) are chosen.
func _target_row(parent: VBoxContainer, ship_id: String, side: int, target_id: String,
		battery: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.theme_type_variation = &"SecondaryButton"
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): select_target(ship_id, side, target_id, battery))
	button.set_meta("target_id", target_id)
	button.set_meta("battery", battery)
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
# Order assembly (read-only: options from eligible_shots, numbers from preview_orders)
# ============================================================================

## battery_options() for one side and target of a ship.
func _battery_options_for(ship_id: String, side: int, target_id: String) -> Array[String]:
	var by_target: Dictionary = _ships[ship_id]["options"].get(side, {})
	return battery_options((by_target.get(target_id, {}) as Dictionary).values())


## The ship's sides after picking row (target_id, battery) on `side`: choose_battery, then the
## target cap (FireRules.limit_targets). A copy.
func _apply_choice(ship_id: String, side: int, target_id: String, battery: String) -> Dictionary:
	var sides: Dictionary = _ships[ship_id]["sides"].duplicate(true)
	var chosen := choose_battery(sides[side], target_id, battery)
	sides[side]["bow"] = chosen["bow"]
	sides[side]["stern"] = chosen["stern"]
	return FireRules.limit_targets(sides, side)


## The ship's FireOrders for `sides` (panel_orders with each target's range).
func _orders(ship_id: String, sides: Dictionary) -> Array[GunneryTypes.FireOrder]:
	var ranges := {}
	for side in _ships[ship_id]["options"]:
		for target_id in _ships[ship_id]["options"][side]:
			for p: GunneryTypes.ShotPreview in _ships[ship_id]["options"][side][target_id].values():
				ranges[target_id] = p.range_hexes
	return panel_orders(ship_id, sides, ranges)


## Previews of a ship's whole order set as they will resolve (GunneryCalculator.preview_orders),
## computed once per order set (_preview_cache).
func _preview_sides(ship_id: String, sides: Dictionary) -> Array[GunneryTypes.ShotPreview]:
	var orders := _orders(ship_id, sides)
	var key := JSON.stringify(orders.map(func(o: GunneryTypes.FireOrder) -> Dictionary: return o.to_dict()))
	if not _preview_cache.has(key):
		_preview_cache[key] = GameState.gunnery_calculator.preview_orders(orders)
	return _preview_cache[key]


static func _find_preview(previews: Array[GunneryTypes.ShotPreview], side: int, target_id: String,
		battery: String) -> GunneryTypes.ShotPreview:
	for p in previews:
		if p.order.side == side and p.order.target_id == target_id and p.order.battery == battery:
			return p
	return null


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
		var orders := get_all_orders()
		fire_button.text = fire_button_text_for(orders)
		instructions_label.text = footer_text(orders.size(), targets_changed())
	if two_target_label:
		two_target_label.text = two_target_note(DataManager.combat_tables.flat_modifier("two_targets")) \
			if DataManager.combat_tables else ""
		two_target_label.visible = any_ship_fires_both()


## True once the player picked a target (or hold fire) other than the one chosen for them.
func targets_changed() -> bool:
	for ship_id in _ship_order:
		var entry: Dictionary = _ships[ship_id]
		for side in entry["sides"]:
			var default: Dictionary = entry["defaults"].get(side, {"bow": "", "stern": ""})
			for key in ["bow", "stern"]:
				if entry["sides"][side][key] != default[key]:
					return true
	return false


## True while some listed ship names two different targets (the two-target modifier applies).
func any_ship_fires_both() -> bool:
	for ship_id in _ship_order:
		if get_target_ids(ship_id).size() > 1:
			return true
	return false


## Re-query previews for the ship's order set and refresh rows, toggles, notes and breakdowns.
## Chosen rows show the preview of the current order set; any other row shows the order set
## that picking it would give. The player's wishes (want_high, want_dismantling) are kept apart
## from what the orders will be, so a forced high aim or a roundshot fallback never sticks.
func _refresh_ship(ship_id: String) -> void:
	var entry: Dictionary = _ships[ship_id]
	var sides: Dictionary = entry["sides"]
	var names := target_names(GameState.get_all_ships())
	var current := _preview_sides(ship_id, sides)
	for side in sides:
		var state: Dictionary = sides[side]
		var widgets: Dictionary = entry["widgets"][side]
		for key: String in widgets["targets"]:
			var button: Button = widgets["targets"][key]
			if key == "":
				var holding: bool = state["bow"] == "" and state["stern"] == ""
				button.set_pressed_no_signal(holding)
				button.text = row_marker(holding) + "Hold fire"
				continue
			var target_id: String = button.get_meta("target_id")
			var battery: String = button.get_meta("battery")
			var chosen := row_chosen(state["bow"], state["stern"], target_id, battery)
			var previews := current if chosen else _preview_sides(ship_id, _apply_choice(ship_id, side, target_id, battery))
			var p := _find_preview(previews, side, target_id, battery)
			var target_name := str(names.get(target_id, target_id))
			var text := option_text(target_name, p, battery) if p and p.can_fire \
				else "%s%s%s" % [target_name, SEPARATOR, p.reason if p else "cannot fire"]
			button.set_pressed_no_signal(chosen)
			button.text = row_marker(chosen) + text

		var high: CheckButton = widgets["high"]
		var dismantling: CheckButton = widgets["dismantling"]
		var breakdown: Label = widgets["breakdown"]
		var side_previews: Array[GunneryTypes.ShotPreview] = []
		for p in current:
			if p.order.side == side:
				side_previews.append(p)
		if side_previews.is_empty():
			high.disabled = true
			high.set_pressed_no_signal(state["want_high"])
			dismantling.disabled = true
			dismantling.set_pressed_no_signal(state["want_dismantling"])
			widgets["high_note"].text = ""
			widgets["dismantling_note"].text = ""
			breakdown.text = "This broadside holds fire."
			continue

		var all_high_only := true
		var any_high_only := false
		var all_high := true
		var any_dismantling := false
		var any_dismantling_allowed := false
		var max_range := 0
		var lines: Array[String] = []
		for p in side_previews:
			all_high_only = all_high_only and p.high_only
			any_high_only = any_high_only or p.high_only
			all_high = all_high and p.order.aim == GunneryTypes.AIM_HIGH
			any_dismantling = any_dismantling or p.order.ammo == GunneryTypes.AMMO_DISMANTLING
			any_dismantling_allowed = any_dismantling_allowed or FireRules.dismantling_allowed(p.range_hexes)
			max_range = maxi(max_range, p.range_hexes)
			var prefix := "%s: " % battery_label(p.order.battery) if side_previews.size() > 1 else ""
			lines.append(prefix + breakdown_text(p))
		high.disabled = all_high_only
		high.set_pressed_no_signal(all_high)
		widgets["high_note"].text = aim_note(any_high_only)
		dismantling.disabled = not any_dismantling_allowed
		dismantling.set_pressed_no_signal(any_dismantling)
		widgets["dismantling_note"].text = dismantling_note(max_range, state["want_dismantling"])
		breakdown.text = "\n".join(lines)


func _on_fire_pressed() -> void:
	fire_pressed.emit(get_all_orders())
