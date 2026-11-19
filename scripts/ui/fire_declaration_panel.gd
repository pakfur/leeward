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
## FireRules on the server side; the order logic and the per-ship selection state (default choice,
## row picks, target cap, reductions, the orders sent) are FireOrdersModel's (`model`), shared with
## the board; this panel only keeps widgets and text.
## Every change re-queries GunneryCalculator.preview_orders (a pure query) for the ship's whole
## order set, so the numbers and the breakdown are those the resolver will roll (two targets, half
## broadside, initial broadside once per broadside). No popups. The panel never mutates game
## state: pressing the main button only emits the assembled order dictionaries.
## Chasers (house rule, register §5): after Port and Starboard, a "Bow chaser" and a "Stern chaser"
## block for each chaser that has a target (GunneryCalculator.eligible_shots sides
## GunneryTypes.CHASE_BOW / CHASE_STERN, battery "chase"): rows labelled "Chaser", the aim toggle,
## the reduction stepper and the ammunition toggle locked (round shot only). A chase side keeps its
## target under "bow" (the "stern" key stays ""), so FireRules.limit_targets / battery_targets keep
## the ship within two targets. The default choice is the best broadside row; a ship with no
## broadside row starts on its best chaser row.
## Marine fire (7.G, boarding spec §4.4): each own ship whose marines may fire gets a "Marines" block
## with one row per adjacent enemy (MarineFireResolver.eligible_marine_shots, a pure query) showing
## the Marine Fire column and the chance of a hit, plus "Hold musket fire"; one choice at most (7.G.2).
## The best shot is chosen by default. A ship with a marine shot but no gun shot is still listed, so
## the panel opens. The controller reads get_marine_orders() and sends them with the gun orders in
## the same server request (player_submit_fire_orders).

signal fire_pressed(orders: Array)
## A ship row was chosen (the controller draws that ship's arcs).
signal ship_focused(ship_id: String)
## A broadside's target (or toggles) changed for this ship.
signal selection_changed(ship_id: String)

## Every side a ship may fire from, in panel order: the two broadsides, then the bow and stern chasers.
const ALL_SIDES: Array[int] = FireOrdersModel.ALL_SIDES
const SIDE_NAMES := {
	ShipState.PORT: "Port",
	ShipState.STARBOARD: "Starboard",
	GunneryTypes.CHASE_BOW: "Bow chaser",
	GunneryTypes.CHASE_STERN: "Stern chaser",
}
const CHASE_AMMO_NOTE := "Chasers fire round shot only"
const SEPARATOR := " — "
const HIGH_ONLY_NOTE := "Range %d+: must fire high"
const DISMANTLING_NOTE := "Dismantling shot reaches %d hexes"
const D6_NOTE := "A d6 is added when you fire; higher is better."
const BATTERY_LABELS := {
	GunneryTypes.BATTERY_FULL: "Full broadside",
	GunneryTypes.BATTERY_BOW: "Bow battery",
	GunneryTypes.BATTERY_STERN: "Stern battery",
	GunneryTypes.BATTERY_CHASE: "Chaser",
}

@onready var ship_list_container: VBoxContainer = %ShipListContainer
@onready var error_label: Label = %ErrorLabel
@onready var fire_button: Button = %FireButton
@onready var instructions_label: Label = %InstructionsLabel
@onready var two_target_label: Label = %TwoTargetLabel
@onready var scroll: ScrollContainer = %ScrollContainer
@onready var more_below_label: Label = %MoreBelowLabel

const NO_SHOT_COLOR := Color(0.6, 0.62, 0.66)

## The order logic and selection state (FireOrdersModel); the panel keeps only its widgets.
var model := FireOrdersModel.new()
## ship_id -> {"name": String, "header": Button, "widgets": {side: Dictionary}} for ships with a gun shot.
var _ships: Dictionary = {}
var _focused_ship_id: String = ""
var _group := ButtonGroup.new()
var _building: bool = false
## ship_id -> {"rows": {target_id: Button} ("" = hold row)} for ships whose marines may fire.
var _marines: Dictionary = {}


# ============================================================================
# Pure presentation helpers (unit tested)
# ============================================================================

## "Hermione — 7 marines, column 7-8, alongside −1 — hits on 4 or less (67%)" for a marine-fire
## preview (MarineFireResolver.preview). A shot that cannot hit says so.
static func marine_option_text(target_name: String, preview: Dictionary) -> String:
	var parts: Array[String] = [target_name]
	var head := "%s, column %s" % [PhaseEvents.plural(int(preview.get("boxes", 0)), "marine"),
		str(preview.get("column", ""))]
	for m in preview.get("modifiers", []):
		var v := int(m.get("value", 0))
		head += ", %s %s%d" % [PhaseEvents.modifier_label(str(m.get("name", "?"))), "−" if v < 0 else "+", absi(v)]
	parts.append(head)
	var hit_max := int(preview.get("hit_max", 0))
	if hit_max <= 0:
		parts.append("cannot hit")
	else:
		var odds := "hits on %s (%d%%)" % ["any roll" if hit_max >= 6 else "%d or less" % hit_max,
			int(preview.get("chance", 0))]
		if int(preview.get("most", 0)) > 1:
			odds += ", up to %d boxes" % int(preview["most"])
		parts.append(odds)
	return SEPARATOR.join(parts)


## The main button's text with marine fire: "Fire 1 broadside and muskets", "Fire muskets",
## or fire_button_text_for() alone when no marines fire.
static func fire_button_text_with_marines(orders: Array, marine_count: int) -> String:
	var guns := fire_button_text_for(orders)
	if marine_count <= 0:
		return guns
	if orders.is_empty():
		return "Fire muskets"
	return guns + " and muskets"


## The footer under the ship list, matching the current choice.
static func footer_text(order_count: int, changed: bool) -> String:
	if order_count == 0:
		return "Holding all fire. Pick a target row to fire."
	if changed:
		return "You changed the target. Pick any row to change it again."
	return "Your best shot is chosen; the other broadside holds fire. Pick any row to change it."


## ship_id -> "Topaze — 32-gun Frigate": target rows name each ship with its type.
static func target_names(ships: Array) -> Dictionary:
	return FireOrdersModel.target_names(ships)


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


## "Full broadside", "Bow battery", "Stern battery" or "Chaser".
static func battery_label(battery: String) -> String:
	return str(BATTERY_LABELS.get(battery, battery))


## A side block's title: "Port broadside", "Starboard broadside", "Bow chaser", "Stern chaser".
static func side_title(side: int) -> String:
	var side_name := str(SIDE_NAMES.get(side, side))
	return side_name if GunneryTypes.is_chase_side(side) else "%s broadside" % side_name


## The breakdown line of a side that holds fire.
static func holds_fire_text(side: int) -> String:
	return "This chaser holds fire." if GunneryTypes.is_chase_side(side) else "This broadside holds fire."


## Widget key of a target row ("" is the hold-fire row): FireOrdersModel.row_key.
static func row_key(target_id: String, battery: String) -> String:
	return FireOrdersModel.row_key(target_id, battery)


## A ship's FireOrders for its sides: FireOrdersModel.orders_for_sides.
static func panel_orders(ship_id: String, sides: Dictionary, ranges: Dictionary) -> Array[GunneryTypes.FireOrder]:
	return FireOrdersModel.orders_for_sides(ship_id, sides, ranges)


## What the main button does: "Fire 1 broadside", "Fire 2 half broadsides", "Fire 1 broadside and
## 1 half broadside", "Fire 1 broadside and 1 chaser" or "Hold all fire". A full-broadside order
## counts as a broadside, a bow or stern battery order as a half broadside (a side split between
## two targets is two half broadsides), a "chase" order as a chaser.
static func fire_button_text(full_count: int, half_count: int = 0, chase_count: int = 0) -> String:
	var parts := PackedStringArray()
	if full_count > 0:
		parts.append("%d broadside%s" % [full_count, "" if full_count == 1 else "s"])
	if half_count > 0:
		parts.append("%d half broadside%s" % [half_count, "" if half_count == 1 else "s"])
	if chase_count > 0:
		parts.append("%d chaser%s" % [chase_count, "" if chase_count == 1 else "s"])
	if parts.is_empty():
		return "Hold all fire"
	return "Fire " + " and ".join(parts)


## fire_button_text() for a set of orders.
static func fire_button_text_for(orders: Array) -> String:
	var full := 0
	var chase := 0
	for order in orders:
		if order.battery == GunneryTypes.BATTERY_FULL:
			full += 1
		elif order.battery == GunneryTypes.BATTERY_CHASE:
			chase += 1
	return fire_button_text(full, orders.size() - full - chase, chase)


## Radio-style marker so the chosen row is obvious at a glance.
static func row_marker(chosen: bool) -> String:
	return "● " if chosen else "○ "


## Why "High fire" is locked on; else the 14.E chance that a low aim holds (`limits` from the
## previews' aim_limits); "" when the player may choose freely.
static func aim_note(high_only: bool, limits: Array = [], crew_quality: String = "") -> String:
	if high_only:
		return HIGH_ONLY_NOTE % FireRules.HIGH_ONLY_RANGE
	if limits.is_empty():
		return ""
	var parts := PackedStringArray()
	for rule in limits:
		parts.append("crew CQ %s" % crew_quality if str(rule) == "crew" else "firing to windward")
	return "Low aim holds only on a d6 of 1–3 (14.E: %s)" % ", ".join(parts)


## Why "Dismantling" is unavailable, "" when it may be chosen. Says so when the player's choice
## is being replaced by roundshot for this target.
static func dismantling_note(range_hexes: int, want_dismantling: bool) -> String:
	if FireRules.dismantling_allowed(range_hexes):
		return ""
	var note := DISMANTLING_NOTE % FireRules.MAX_DISMANTLING_RANGE
	return note + " — roundshot this time" if want_dismantling else note


## Shown next to the main button while some ship fires both broadsides, e.g.
## "Two targets: −12 on each broadside". `modifier` is the (negative) two-target modifier.
## `with_chaser` (a chaser is one of the two targets) says "shot" instead of "broadside".
static func two_target_note(modifier: int, with_chaser: bool = false) -> String:
	return "Two targets: %s%d on each %s" % ["−" if modifier < 0 else "+", absi(modifier),
		"shot" if with_chaser else "broadside"]


## "HMS Phoebe — no broadside bears: out of range": one ship's no-shot line, in the fire panel and
## in the "Combat" panel alike.
static func no_shot_line(ship_name: String, reason: String) -> String:
	return "%s%sno broadside bears: %s" % [ship_name, SEPARATOR, reason]


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
	model.setup(ship_ids)
	for ship_id in model.gun_ships():
		_add_ship(GameState.get_ship(ship_id))
	for ship_id in model.no_shot_ships():
		_add_no_shot_row(no_shot_line(GameState.get_ship(ship_id).ship_name, model.no_shot_reason(ship_id)))
	for ship_id in model.marine_ships():
		if not model.has_gun_shots(ship_id):
			_add_marine_only_ship(GameState.get_ship(ship_id))
	_building = false
	for ship_id in _ships:
		_refresh_ship(ship_id)
	for ship_id in _marines:
		_refresh_marines(ship_id)
	_update_fire_button()
	var gun_ships := model.gun_ships()
	if not gun_ships.is_empty():
		focus_ship(gun_ships[0])
	return model.ships_with_shots().size()


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
	return model.target_ids(ship_id)


## The single batteries ("bow", "stern") that fire from `side` of a ship; [] while it holds fire.
func get_batteries(ship_id: String, side: int) -> Array[String]:
	return model.batteries(ship_id, side)


## Marine fire orders as {ship_id, target_id} dictionaries, one per ship whose marines fire.
func get_marine_orders() -> Array:
	return model.marine_orders()


## The marine target chosen for a ship ("" while its marines hold fire or it has no block).
func get_marine_target(ship_id: String) -> String:
	return model.marine_target(ship_id)


## Pick the marines' target (7.G.2: one ship); "" holds musket fire. Same effect as clicking the row.
func select_marine_target(ship_id: String, target_id: String) -> void:
	if not model.select_marine_target(ship_id, target_id):
		return
	_refresh_marines(ship_id)
	_update_fire_button()
	error_label.visible = false


func get_all_orders() -> Array:
	return model.order_dicts()


## Pick a broadside's target row (target_id, battery); target_id "" holds fire, battery "" means
## the target's preferred battery (a full broadside when both bear). Picking the chosen row again
## holds what it fires. Same effect as clicking the row.
func select_target(ship_id: String, side: int, target_id: String, battery: String = "") -> void:
	if target_id != "" and battery == "":
		var options := model.battery_options_for(ship_id, side, target_id)
		if not options.is_empty():
			battery = options[0]
	if not model.choose(ship_id, side, target_id, battery):
		return
	_on_side_changed(ship_id, side)
	var row: Button = _ships[ship_id]["widgets"][side]["targets"].get(row_key(target_id, battery))
	if row:
		_reveal(row)


## Ask for high fire / dismantling shot on a broadside. Same effect as pressing the toggles.
func set_want_high(ship_id: String, side: int, on: bool) -> void:
	if model.set_high(ship_id, side, on):
		_on_side_changed(ship_id, side)


func set_want_dismantling(ship_id: String, side: int, on: bool) -> void:
	if model.set_dismantling(ship_id, side, on):
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
	for ship_id in _ships:
		for side in _ships[ship_id]["widgets"]:
			var w: Dictionary = _ships[ship_id]["widgets"][side]
			for button: Button in w["targets"].values():
				button.disabled = true
			w["high"].disabled = true
			w["dismantling"].disabled = true
	for ship_id in _marines:
		for button: Button in (_marines[ship_id]["rows"] as Dictionary).values():
			button.disabled = true


func _clear() -> void:
	for child in ship_list_container.get_children():
		child.queue_free()
	_ships.clear()
	_marines.clear()
	_focused_ship_id = ""
	_group = ButtonGroup.new()
	error_label.visible = false
	fire_button.disabled = false
	fire_button.text = fire_button_text(0)
	instructions_label.text = footer_text(1, false)


func _add_ship(ship_state: ShipState) -> void:
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

	var entry := {"name": ship_state.ship_name, "header": header, "widgets": {}}
	_ships[ship_id] = entry
	for side in model.sides(ship_id):
		entry["widgets"][side] = _build_side(box, ship_id, side, model.targets(ship_id, side))
	if model.has_marines(ship_id):
		_build_marines(box, ship_id)
	box.add_child(HSeparator.new())


## A ship with a marine shot but no gun shot: its name and its Marines block (its no-shot line for
## the guns is listed with the others).
func _add_marine_only_ship(ship_state: ShipState) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	ship_list_container.add_child(box)
	var header := Label.new()
	header.text = PlanningText.name_and_type(ship_state)
	box.add_child(header)
	_build_marines(box, ship_state.ship_id)
	box.add_child(HSeparator.new())


## The "Marines" block: one row per adjacent enemy the marines may fire on, then "Hold musket fire".
func _build_marines(parent: VBoxContainer, ship_id: String) -> void:
	var title := Label.new()
	title.text = "Marines (muskets, adjacent ships only)"
	parent.add_child(title)
	var rows := VBoxContainer.new()
	rows.name = "MarineRows"
	rows.add_theme_constant_override("separation", 2)
	parent.add_child(rows)
	var buttons := {}
	for row: Dictionary in model.marine_targets(ship_id):
		var target_id := str(row["target_id"])
		buttons[target_id] = _marine_row(rows, ship_id, target_id)
	buttons[""] = _marine_row(rows, ship_id, "")
	_marines[ship_id] = {"rows": buttons}


func _marine_row(parent: VBoxContainer, ship_id: String, target_id: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.theme_type_variation = &"SecondaryButton"
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): select_marine_target(ship_id, target_id))
	button.set_meta("marine_target_id", target_id)
	parent.add_child(button)
	return button


func _refresh_marines(ship_id: String) -> void:
	var entry: Dictionary = _marines[ship_id]
	var names := target_names(GameState.get_all_ships())
	var by_target := {}
	for row: Dictionary in model.marine_targets(ship_id):
		by_target[str(row["target_id"])] = row["preview"]
	var target := model.marine_target(ship_id)
	for target_id: String in entry["rows"]:
		var button: Button = entry["rows"][target_id]
		var chosen := target == target_id
		button.set_pressed_no_signal(chosen)
		if target_id == "":
			button.text = row_marker(chosen) + "Hold musket fire"
		else:
			button.text = row_marker(chosen) + marine_option_text(str(names.get(target_id, target_id)),
				by_target.get(target_id, {}))


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


## One side block; `targets` is FireOrdersModel.targets (nearest first), one row per battery that bears.
func _build_side(parent: VBoxContainer, ship_id: String, side: int, targets: Array[Dictionary]) -> Dictionary:
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 6)
	var swatch := ColorRect.new()
	swatch.name = "ArcSwatch"
	swatch.color = BroadsideColors.color(side)  # the same constant draws this side's arc on the map
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(swatch)
	var label := Label.new()
	label.text = side_title(side)
	title.add_child(label)
	parent.add_child(title)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	parent.add_child(rows)
	var target_rows := {}
	var steppers := {}
	for row in targets:
		var target_id := str(row["target_id"])
		for battery: String in row["batteries"]:
			var key := row_key(target_id, battery)
			target_rows[key] = _target_row(rows, ship_id, side, target_id, battery)
			steppers[key] = _reduction_stepper(rows, ship_id, side, target_id, battery)
	target_rows[""] = _target_row(rows, ship_id, side, "", "")

	var breakdown := Label.new()
	breakdown.theme_type_variation = &"SecondaryLabel"
	breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(breakdown)

	var high := _toggle_row(parent, "High fire")
	var dismantling := _toggle_row(parent, "Dismantling")
	high["button"].toggled.connect(func(on: bool): set_want_high(ship_id, side, on))
	dismantling["button"].toggled.connect(func(on: bool): set_want_dismantling(ship_id, side, on))
	if GunneryTypes.is_chase_side(side):
		# A chaser fires round shot only (house rule, register §5): no ammunition choice.
		dismantling["button"].disabled = true
		dismantling["note"].text = CHASE_AMMO_NOTE
	return {"targets": target_rows, "steppers": steppers, "rows": targets, "high": high["button"],
		"high_note": high["note"], "dismantling": dismantling["button"],
		"dismantling_note": dismantling["note"], "breakdown": breakdown}


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


## The "Reduce fire" stepper of a chosen row (7.C.14): - and + buttons around the value. Shown
## only while the row is chosen; it sends the new reduction through set_reduction.
func _reduction_stepper(parent: VBoxContainer, ship_id: String, side: int, target_id: String,
		battery: String) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.visible = false
	var label := Label.new()
	label.text = "Reduce fire"
	label.theme_type_variation = &"SecondaryLabel"
	box.add_child(label)
	var minus := Button.new()
	minus.text = "-"
	minus.theme_type_variation = &"SecondaryButton"
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(func(): step_reduction(ship_id, side, target_id, battery, -1))
	box.add_child(minus)
	var value := Label.new()
	value.theme_type_variation = &"CounterLabel"
	value.custom_minimum_size = Vector2(24, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value)
	var plus := Button.new()
	plus.text = "+"
	plus.theme_type_variation = &"SecondaryButton"
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(func(): step_reduction(ship_id, side, target_id, battery, 1))
	box.add_child(plus)
	parent.add_child(box)
	return {"box": box, "value": value, "minus": minus}


## Change a chosen row's voluntary reduction by `delta` (clamped at 0) and re-preview the ship.
func step_reduction(ship_id: String, side: int, target_id: String, battery: String, delta: int) -> void:
	var n := model.reduction(ship_id, side, target_id, battery) + delta
	if model.set_reduction(ship_id, side, target_id, battery, n):
		_on_side_changed(ship_id, side)


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
		var orders := get_all_orders()
		var marine_orders := get_marine_orders()
		fire_button.text = fire_button_text_with_marines(orders, marine_orders.size())
		instructions_label.text = footer_text(orders.size() + marine_orders.size(), targets_changed())
	if two_target_label:
		two_target_label.text = two_target_note(DataManager.combat_tables.flat_modifier("two_targets"),
			any_two_target_chaser()) \
			if DataManager.combat_tables else ""
		two_target_label.visible = any_ship_fires_both()


## True once the player picked a target (or hold fire) other than the one chosen for them.
func targets_changed() -> bool:
	return model.targets_changed()


## True while some listed ship names two different targets (the two-target modifier applies).
func any_ship_fires_both() -> bool:
	return model.any_ship_fires_both()


## True while a ship naming two targets fires a chaser at one of them.
func any_two_target_chaser() -> bool:
	return model.any_two_target_chaser()


## Re-query previews for the ship's order set and refresh rows, toggles, notes and breakdowns.
## Chosen rows show the preview of the current order set; any other row shows the order set
## that picking it would give. The player's wishes (want_high, want_dismantling) are kept apart
## from what the orders will be, so a forced high aim or a roundshot fallback never sticks.
func _refresh_ship(ship_id: String) -> void:
	var entry: Dictionary = _ships[ship_id]
	var names := target_names(GameState.get_all_ships())
	var current := model.previews(ship_id)
	var firer: ShipState = GameState.get_ship(ship_id)
	var crew_quality := firer.crew_quality if firer else ""
	for side in model.sides(ship_id):
		var state := model.side_state(ship_id, side)
		var widgets: Dictionary = entry["widgets"][side]
		var chase := GunneryTypes.is_chase_side(int(side))
		for key: String in widgets["targets"]:
			var button: Button = widgets["targets"][key]
			if key == "":
				var holding: bool = state["bow"] == "" and state["stern"] == ""
				button.set_pressed_no_signal(holding)
				button.text = row_marker(holding) + "Hold fire"
				continue
			var target_id: String = button.get_meta("target_id")
			var battery: String = button.get_meta("battery")
			var chosen := FireOrdersModel.row_chosen(state["bow"], state["stern"], target_id, battery)
			var previews := current if chosen else model.previews_if_chosen(ship_id, side, target_id, battery)
			var p := FireOrdersModel.find_preview(previews, side, target_id, battery)
			var target_name := str(names.get(target_id, target_id))
			var text := option_text(target_name, p, battery) if p and p.can_fire \
				else "%s%s%s" % [target_name, SEPARATOR, p.reason if p else "cannot fire"]
			button.set_pressed_no_signal(chosen)
			button.text = row_marker(chosen) + text
			var stepper: Dictionary = widgets["steppers"][key]
			stepper["box"].visible = chosen
			var n := FireOrdersModel.reduction_of(state, target_id, battery)
			stepper["value"].text = str(n)
			stepper["minus"].disabled = n <= 0

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
			widgets["dismantling_note"].text = CHASE_AMMO_NOTE if chase else ""
			breakdown.text = holds_fire_text(side)
			continue

		var all_high_only := true
		var any_high_only := false
		var all_high := true
		var any_dismantling := false
		var any_dismantling_allowed := false
		var max_range := 0
		var aim_limits: Array[String] = []  # 14.E, the union over the side's shots
		var lines: Array[String] = []
		for p in side_previews:
			for rule in p.aim_limits:
				if not aim_limits.has(rule):
					aim_limits.append(rule)
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
		widgets["high_note"].text = aim_note(any_high_only, aim_limits, crew_quality)
		dismantling.disabled = chase or not any_dismantling_allowed
		dismantling.set_pressed_no_signal(any_dismantling)
		widgets["dismantling_note"].text = CHASE_AMMO_NOTE if chase \
			else dismantling_note(max_range, state["want_dismantling"])
		breakdown.text = "\n".join(lines)


func _on_fire_pressed() -> void:
	fire_pressed.emit(get_all_orders())
