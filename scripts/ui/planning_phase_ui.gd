extends Control
## PlanningPhaseUI - Main planning interface displayed in context panel during PLANNING phase

signal ship_selected(ship_id: String)
signal end_planning_pressed()
signal crew_overlay_requested(ship_id: String)  ## a card's "Crew & damage" button
signal reset_planning_confirmed()  ## Cancel, confirmed: every order back to the start of the turn
signal card_clicked(ship_id: String)  ## a card was clicked (not set by code): her ring opens on the board

const ShipListItem = preload("res://scenes/ui/ship_list_item.tscn")

@onready var title_label: Label = %TitleLabel
@onready var ship_list_container: VBoxContainer = %ShipListContainer
@onready var still_in_plan_label: Label = %StillInPlanLabel
@onready var instructions_label: Label = %InstructionsLabel
@onready var end_planning_button: Button = %EndPlanningButton
@onready var cancel_button: Button = %CancelButton
@onready var reset_dialog: ConfirmationDialog = %ResetDialog

# Track state
var ship_list_items: Dictionary = {}  # ship_id -> ShipListItem
var selected_ship_id: String = ""
var ship_states: Dictionary = {}  # ship_id -> ShipState (read-only references)
var _checklist: PlanChecklist = null  # board planning's Plan / Done checklist (view state)
var crew_overlay_open: bool = false  # the selected card hides its summary line while the overlay is open

func _ready() -> void:
	end_planning_button.pressed.connect(func(): end_planning_pressed.emit())
	cancel_button.pressed.connect(func(): reset_dialog.popup_centered())
	reset_dialog.confirmed.connect(func(): reset_planning_confirmed.emit())
	instructions_label.text = PlanningText.instructions()

func setup_for_player(player_ships: Array[ShipState]) -> void:
	clear_ships()

	for ship_state in player_ships:
		_add_ship_to_list(ship_state)

	# Select first ship by default
	if not player_ships.is_empty():
		_select_ship(player_ships[0].ship_id)

	refresh_crew_summaries()

## The crew plan changed (crew overlay): the cards follow it.
func refresh_crew_orders() -> void:
	refresh_crew_summaries()

## The status box on every card from the stored crew plan (a read-only query); the cards redraw
## their hull, rigging, crew and guns from the ship too.
func refresh_crew_summaries() -> void:
	for ship_id in ship_list_items:
		var ship: ShipState = ship_states.get(ship_id)
		var item = ship_list_items[ship_id]
		if ship == null or GameState.crew_task_controller == null:
			continue
		item.setup(ship)
		item.set_crew_plan(GameState.crew_task_controller.current_plan(ship_id))

func clear_ships() -> void:
	for child in ship_list_container.get_children():
		child.queue_free()

	ship_list_items.clear()
	selected_ship_id = ""
	ship_states.clear()

func _add_ship_to_list(ship_state: ShipState) -> void:
	var list_item = ShipListItem.instantiate()
	ship_list_container.add_child(list_item)

	# Setup the item with ship data
	list_item.setup(ship_state)

	# Connect signals
	list_item.selected.connect(func(): _on_card_clicked(ship_state.ship_id))
	list_item.crew_pressed.connect(func(): crew_overlay_requested.emit(ship_state.ship_id))
	list_item.pill_pressed.connect(func(): _on_pill_pressed(ship_state.ship_id))

	# Track the item
	ship_list_items[ship_state.ship_id] = list_item

	ship_states[ship_state.ship_id] = ship_state
	list_item.set_plan_state(_checklist.state(ship_state.ship_id) if _checklist != null else "")

func _on_card_clicked(ship_id: String) -> void:
	_on_ship_item_selected(ship_id)
	card_clicked.emit(ship_id)


func _on_ship_item_selected(ship_id: String) -> void:
	_select_ship(ship_id)
	ship_selected.emit(ship_id)

## Make `ship_id` the ship whose orders are shown and tell the controller (as a card click does).
func select_ship(ship_id: String) -> void:
	if ship_list_items.has(ship_id):
		_on_ship_item_selected(ship_id)

func _select_ship(ship_id: String) -> void:
	# Deselect previous
	if selected_ship_id != "" and ship_list_items.has(selected_ship_id):
		ship_list_items[selected_ship_id].set_selected_state(false)

	# Select new
	selected_ship_id = ship_id
	if ship_list_items.has(ship_id):
		ship_list_items[ship_id].set_selected_state(true)
	refresh_crew_summaries()

func update_ship_display(ship_state: ShipState) -> void:
	if ship_list_items.has(ship_state.ship_id):
		ship_list_items[ship_state.ship_id].setup(ship_state)

## Follow board planning's checklist: each card's pill and the footer's "still in Plan" line.
func bind_checklist(checklist: PlanChecklist) -> void:
	if _checklist != null and _checklist.changed.is_connected(_refresh_plan_state):
		_checklist.changed.disconnect(_refresh_plan_state)
	_checklist = checklist
	if _checklist != null:
		_checklist.changed.connect(_refresh_plan_state)
	_refresh_plan_state()


func _refresh_plan_state() -> void:
	for id in ship_list_items:
		ship_list_items[id].set_plan_state(_checklist.state(id) if _checklist != null else "")
	if still_in_plan_label:
		var text := still_in_plan_text(_checklist.plan_count() if _checklist != null else 0)
		still_in_plan_label.text = text
		still_in_plan_label.visible = text != ""


## The footer's note: a ship still in Plan at End Planning sails her stored (default) course.
static func still_in_plan_text(count: int) -> String:
	if count <= 0:
		return ""
	if count == 1:
		return "1 ship is still in Plan: she sails her default course"
	return "%d ships still in Plan sail their default course" % count


## A pill click: Plan <-> Done; a Locked ship stays as she is.
func _on_pill_pressed(ship_id: String) -> void:
	if _checklist == null:
		return
	match _checklist.state(ship_id):
		PlanChecklist.PLAN:
			_checklist.set_done(ship_id, true)
		PlanChecklist.DONE:
			_checklist.set_done(ship_id, false)
