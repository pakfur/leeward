extends Control
## FireDeclarationPanel - Context-panel UI for declaring broadside fire during COMBAT_RESOLUTION.
##
## Lists each own ship that has at least one eligible shot. Each broadside (port/starboard) gets
## a target list ("Hold fire" first and selected by default), an aim toggle and an ammunition
## toggle. Every change re-queries GunneryCalculator.preview (a pure query) so the displayed
## modified gunfire numbers and modifier breakdown are always current. The panel never mutates
## game state: pressing Fire only emits the assembled order dictionaries for the controller.

signal fire_pressed(orders: Array)
## A ship row was chosen (the controller draws that ship's arcs).
signal ship_focused(ship_id: String)
## A broadside's target (or toggles) changed for this ship.
signal selection_changed(ship_id: String)

const SIDE_NAMES := ["Port", "Starboard"]
const SEPARATOR := " · "

@onready var ship_list_container: VBoxContainer = %ShipListContainer
@onready var error_label: Label = %ErrorLabel
@onready var fire_button: Button = %FireButton
@onready var instructions_label: Label = %InstructionsLabel

## ship_id -> {"name": String, "header": Button, "shots": {side: Array[ShotPreview]},
##             "sides": {side: {"target_id","aim","ammo"}}, "widgets": {side: Dictionary}}
var _ships: Dictionary = {}
var _ship_order: Array[String] = []
var _focused_ship_id: String = ""
var _group := ButtonGroup.new()
var _building: bool = false


# ============================================================================
# Pure presentation helpers (unit tested)
# ============================================================================

## "<name> — range N · [bow|stern rake] · [initial broadside] · <modified number>"
static func option_text(target_name: String, preview: GunneryTypes.ShotPreview) -> String:
	var parts: Array[String] = ["%s — range %d" % [target_name, preview.range_hexes]]
	if preview.rake != "":
		parts.append("%s rake" % preview.rake)
	if preview.initial_broadside:
		parts.append("initial broadside")
	parts.append(str(preview.mgn))
	return SEPARATOR.join(parts)


## One "name value" line per modifier, e.g. "rake +2".
static func modifier_lines(preview: GunneryTypes.ShotPreview) -> Array[String]:
	var lines: Array[String] = []
	for m in preview.modifiers:
		var key := str(m.get("name", "?"))
		var label: String = PhaseEvents.MODIFIER_LABELS.get(key, key.replace("_", " "))
		lines.append("%s %+d" % [label, int(m.get("value", 0))])
	return lines


static func dismantling_allowed(range_hexes: int) -> bool:
	return range_hexes <= GunneryCalculator.MAX_DISMANTLING_RANGE


## High fire is forced when the range only allows it.
static func effective_aim(wanted_aim: String, high_only: bool) -> String:
	return GunneryTypes.AIM_HIGH if high_only else wanted_aim


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
			w["options"].disabled = true
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
	fire_button.text = "Fire"
	instructions_label.text = "Choose a target for each broadside, or hold fire."


func _add_ship(ship_state: ShipState, shots_by_side: Dictionary) -> void:
	var ship_id := ship_state.ship_id
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	ship_list_container.add_child(box)

	var header := Button.new()
	header.text = ship_state.ship_name
	header.toggle_mode = true
	header.button_group = _group
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.pressed.connect(func(): focus_ship(ship_id))
	box.add_child(header)

	var entry := {"name": ship_state.ship_name, "header": header,
		"shots": shots_by_side, "sides": {}, "widgets": {}}
	_ships[ship_id] = entry
	_ship_order.append(ship_id)

	for side in [ShipState.PORT, ShipState.STARBOARD]:
		if not shots_by_side.has(side):
			continue
		entry["sides"][side] = {"target_id": "", "aim": GunneryTypes.AIM_LOW,
			"ammo": GunneryTypes.AMMO_ROUND}
		entry["widgets"][side] = _build_side(box, ship_id, side, shots_by_side[side])
	box.add_child(HSeparator.new())


func _build_side(parent: VBoxContainer, ship_id: String, side: int, shots: Array) -> Dictionary:
	var label := Label.new()
	label.text = "%s broadside" % SIDE_NAMES[side]
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)

	var options := OptionButton.new()
	options.fit_to_longest_item = false
	options.clip_text = true
	options.add_item("Hold fire")
	options.set_item_metadata(0, "")
	for shot in shots:
		options.add_item(GameState.get_ship(shot.order.target_id).ship_name)
		options.set_item_metadata(options.item_count - 1, shot.order.target_id)
	options.select(0)
	parent.add_child(options)

	var toggles := HBoxContainer.new()
	var high := CheckButton.new()
	high.text = "High fire"
	high.add_theme_font_size_override("font_size", 11)
	var dismantling := CheckButton.new()
	dismantling.text = "Dismantling"
	dismantling.add_theme_font_size_override("font_size", 11)
	toggles.add_child(high)
	toggles.add_child(dismantling)
	parent.add_child(toggles)

	var breakdown := Label.new()
	breakdown.add_theme_font_size_override("font_size", 10)
	breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(breakdown)

	var changed := func(_arg = null): _on_side_changed(ship_id, side)
	options.item_selected.connect(changed)
	high.toggled.connect(changed)
	dismantling.toggled.connect(changed)
	return {"options": options, "high": high, "dismantling": dismantling, "breakdown": breakdown}


# ============================================================================
# Reacting to changes
# ============================================================================

func _on_side_changed(ship_id: String, side: int) -> void:
	if _building:
		return
	var entry: Dictionary = _ships[ship_id]
	var widgets: Dictionary = entry["widgets"][side]
	var selected: int = widgets["options"].selected
	entry["sides"][side]["target_id"] = str(widgets["options"].get_item_metadata(selected))
	entry["sides"][side]["ammo"] = GunneryTypes.AMMO_DISMANTLING if widgets["dismantling"].button_pressed \
		else GunneryTypes.AMMO_ROUND
	entry["sides"][side]["aim"] = GunneryTypes.AIM_HIGH if widgets["high"].button_pressed \
		else GunneryTypes.AIM_LOW
	_refresh_ship(ship_id)
	error_label.visible = false
	selection_changed.emit(ship_id)


## Re-query previews for every broadside of a ship and refresh texts, toggles and breakdowns.
func _refresh_ship(ship_id: String) -> void:
	var entry: Dictionary = _ships[ship_id]
	var sides: Dictionary = entry["sides"]
	for side in sides:
		var state: Dictionary = sides[side]
		var widgets: Dictionary = entry["widgets"][side]
		var options: OptionButton = widgets["options"]
		# Splitting fire across both broadsides costs the two-target modifier on each shot.
		var two_targets := false
		for other_side in sides:
			if other_side != side and sides[other_side]["target_id"] != "":
				two_targets = true

		# Selected shot first, so the toggles reflect its range before item texts are built.
		var selected_preview: GunneryTypes.ShotPreview = null
		if state["target_id"] != "":
			selected_preview = _preview_for(ship_id, side, state["target_id"], state["ammo"], two_targets)
			if state["ammo"] == GunneryTypes.AMMO_DISMANTLING and not dismantling_allowed(selected_preview.range_hexes):
				state["ammo"] = GunneryTypes.AMMO_ROUND
				selected_preview = _preview_for(ship_id, side, state["target_id"], state["ammo"], two_targets)

		for i in range(1, options.item_count):
			var target_id: String = options.get_item_metadata(i)
			var p := _preview_for(ship_id, side, target_id, state["ammo"], two_targets)
			options.set_item_text(i, option_text(GameState.get_ship(target_id).ship_name, p))

		var holding := selected_preview == null
		var high: CheckButton = widgets["high"]
		var dismantling: CheckButton = widgets["dismantling"]
		high.disabled = holding or selected_preview.high_only
		high.set_pressed_no_signal(not holding and
			effective_aim(state["aim"], selected_preview.high_only) == GunneryTypes.AIM_HIGH)
		if not holding:
			state["aim"] = effective_aim(state["aim"], selected_preview.high_only)
		dismantling.disabled = holding or not dismantling_allowed(selected_preview.range_hexes)
		dismantling.set_pressed_no_signal(not holding and state["ammo"] == GunneryTypes.AMMO_DISMANTLING)

		var breakdown: Label = widgets["breakdown"]
		if holding:
			breakdown.text = ""
		else:
			var lines := modifier_lines(selected_preview)
			breakdown.text = "Basic %d, modified %d\n%s" % [selected_preview.bgn, selected_preview.mgn,
				"\n".join(lines)] if not lines.is_empty() else \
				"Basic %d, modified %d" % [selected_preview.bgn, selected_preview.mgn]


## Preview a shot; if the requested ammunition cannot fire (dismantling beyond range 7),
## fall back to roundshot so the row still shows a number.
func _preview_for(ship_id: String, side: int, target_id: String, ammo: String,
		two_targets: bool) -> GunneryTypes.ShotPreview:
	var order := GunneryTypes.FireOrder.new()
	order.ship_id = ship_id
	order.side = side
	order.target_id = target_id
	order.ammo = ammo
	var p: GunneryTypes.ShotPreview = GameState.gunnery_calculator.preview(order, two_targets)
	if not p.can_fire and ammo == GunneryTypes.AMMO_DISMANTLING:
		order.ammo = GunneryTypes.AMMO_ROUND
		p = GameState.gunnery_calculator.preview(order, two_targets)
	return p


func _on_fire_pressed() -> void:
	fire_pressed.emit(get_all_orders())
