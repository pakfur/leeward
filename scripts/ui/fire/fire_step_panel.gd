class_name FireStepPanel
extends VBoxContainer
## The side panel in the fire declaration step (board planning piece 3), view only: the own ships'
## cards (ShipListItem, as in planning) with their fire pills (FIRE, NO TARGET, "✓ n ORDERS",
## NO FIRE: FireBoard.pill), a line saying how many ships with a shot hold fire, a refusal line and
## **Fire**, whose text says what the orders do (FireText.fire_button_text_with_marines). The orders
## themselves are given on the board (BoardPlanning's fire ring and option box); GameController
## sends them on fire_pressed.

signal fire_pressed()
## A card was clicked: her fire ring opens on the board.
signal card_clicked(ship_id: String)
## A card's Crew & damage button.
signal crew_overlay_requested(ship_id: String)

const ShipListItemScene = preload("res://scenes/ui/ship_list_item.tscn")
const INSTRUCTIONS := "Click a ship (or Tab) for her fire ring, pick a broadside, a chaser or her marines, then a target."

var ship_list: VBoxContainer = null
var hold_fire_label: Label = null
var error_label: Label = null
var fire_button: Button = null
var selected_ship_id := ""

var _items: Dictionary = {}  # ship_id -> ShipListItem
var _board: FireBoard = null


func _init() -> void:
	name = "FireStepPanel"
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Your Fleet"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	ship_list = VBoxContainer.new()
	ship_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_list.add_theme_constant_override("separation", 6)
	scroll.add_child(ship_list)
	add_child(HSeparator.new())
	var instructions := _note(INSTRUCTIONS)
	add_child(instructions)
	hold_fire_label = _note("")
	hold_fire_label.visible = false
	add_child(hold_fire_label)
	error_label = _note("")
	error_label.add_theme_color_override("font_color", Color(1, 0.4, 0.35, 1))
	error_label.visible = false
	add_child(error_label)
	fire_button = Button.new()
	fire_button.name = "FireButton"
	fire_button.custom_minimum_size = Vector2(0, 44)
	fire_button.focus_mode = Control.FOCUS_NONE
	fire_button.text = FireText.fire_button_text(0)
	fire_button.pressed.connect(func(): fire_pressed.emit())
	add_child(fire_button)


static func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SecondaryLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## The step begins: a card per own ship (card order), following `board` (the fire step's state).
## The first ship with a shot is selected.
func setup(ships: Array[ShipState], board: FireBoard) -> void:
	for child in ship_list.get_children():
		child.queue_free()
	_items.clear()
	_board = board
	for ship in ships:
		var card: Control = ShipListItemScene.instantiate()
		ship_list.add_child(card)
		card.setup(ship)
		if GameState.crew_task_controller:
			card.set_crew_plan(GameState.crew_task_controller.current_plan(ship.ship_id))
		var id := ship.ship_id
		card.selected.connect(func(): _on_card_clicked(id))
		card.crew_pressed.connect(func(): crew_overlay_requested.emit(id))
		card.pill_pressed.connect(func(): _on_pill_pressed(id))
		_items[id] = card
	if not board.changed.is_connected(refresh):
		board.changed.connect(refresh)
		board.checklist.changed.connect(refresh)
	var first := ""
	for ship in ships:
		if board.has_shot(ship.ship_id):
			first = ship.ship_id
			break
	if first == "" and not ships.is_empty():
		first = ships[0].ship_id
	select_ship(first)
	refresh()


## The step is over (the panel is freed with the context content): stop following the board.
func _exit_tree() -> void:
	if _board != null and _board.changed.is_connected(refresh):
		_board.changed.disconnect(refresh)
		_board.checklist.changed.disconnect(refresh)


func item(ship_id: String) -> Control:
	return _items.get(ship_id)


## Expands `ship_id`'s card (the others collapse), as in planning.
func select_ship(ship_id: String) -> void:
	if selected_ship_id != "" and _items.has(selected_ship_id):
		_items[selected_ship_id].set_selected_state(false)
	selected_ship_id = ship_id
	if _items.has(ship_id):
		_items[ship_id].set_selected_state(true)


## Pills, the hold-fire line and the Fire button from the board's state.
func refresh() -> void:
	if _board == null or not _board.is_active():
		return
	for id in _items:
		var p := _board.pill(id)
		_items[id].set_plan_state(card_state(str(p["state"])), card_text(p), _board.no_shot_reason(id))
	var text := hold_fire_text(_board.ships_without_orders())
	hold_fire_label.text = text
	hold_fire_label.visible = text != ""
	if not fire_button.disabled:
		fire_button.text = FireText.fire_button_text_with_marines(_board.model.order_dicts(),
			_board.model.marine_orders().size())


## The card pill's checklist look for a fire pill (PlanBadges): FIRE amber (Plan), orders or no fire
## green (Done), NO TARGET outlined (Locked: no shot, nothing to toggle).
static func card_state(fire_state: String) -> String:
	match fire_state:
		PlanBadges.FIRE:
			return PlanChecklist.PLAN
		PlanBadges.NO_TARGET:
			return PlanChecklist.LOCKED
	return PlanChecklist.DONE


## The card pill's words: the map pill's ("✓ 2 ORDERS"), else the badge's state text.
static func card_text(p: Dictionary) -> String:
	var text := str(p.get("text", ""))
	return text if text != "" else str(PlanBadges.PILL_TEXT.get(str(p.get("state", "")), ""))


## The footer's note: a ship with a shot and no order holds fire when Fire is pressed.
static func hold_fire_text(count: int) -> String:
	if count <= 0:
		return ""
	if count == 1:
		return "1 ship has no fire orders: she holds fire"
	return "%d ships have no fire orders: they hold fire" % count


## The server refused the orders: its reason in the footer; the step stays and Fire is live again.
func show_error(reason: String) -> void:
	error_label.text = reason
	error_label.visible = reason != ""
	fire_button.disabled = false
	refresh()


## Fire was pressed: no second press while the server decides.
func set_sending() -> void:
	error_label.visible = false
	fire_button.disabled = true


func _on_card_clicked(ship_id: String) -> void:
	select_ship(ship_id)
	card_clicked.emit(ship_id)


## A pill click: Plan <-> Done (FireBoard.set_done; a ship with no shot stays Done).
func _on_pill_pressed(ship_id: String) -> void:
	if _board == null or not _board.is_active():
		return
	_board.set_done(ship_id, _board.state(ship_id) == PlanChecklist.PLAN)
