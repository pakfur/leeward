extends Control
## PlanningPhaseUI - the side panel during PLANNING: a FleetPanel (the own ships' cards) with the
## planning footer in its slot (the instructions, the "still in Plan" line, End Planning and Cancel,
## and Cancel's confirmation). The footer is one Control (`footer`, built by build_footer) so the
## whole-turn side panel can take it; this host keeps the planning API GameController uses.

signal ship_selected(ship_id: String)
signal end_planning_pressed()
signal crew_overlay_requested(ship_id: String)  ## a card's "Crew & damage" button
signal reset_planning_confirmed()  ## Cancel, confirmed: every order back to the start of the turn
signal card_clicked(ship_id: String)  ## a card was clicked (not set by code): her ring opens on the board

const RESET_TOOLTIP := "Reset every order this turn to how it was at the start of the turn"
const RESET_TEXT := "Reset all orders for this turn? Courses, crew, sail and boarding orders go back to how they were at the start of the turn."

var fleet: FleetPanel = null
var footer: VBoxContainer = null
var title_label: Label = null
var still_in_plan_label: Label = null
var instructions_label: Label = null
var end_planning_button: Button = null
var cancel_button: Button = null
var reset_dialog: ConfirmationDialog = null

## ship_id -> ShipListItem (the fleet panel's cards).
var ship_list_items: Dictionary:
	get: return fleet.cards
var selected_ship_id: String:
	get: return fleet.selected_ship_id

var _checklist: PlanChecklist = null  # board planning's Plan / Done checklist (view state)
var crew_overlay_open: bool = false  # the selected card hides its summary line while the overlay is open


func _init() -> void:
	fleet = FleetPanel.new()
	fleet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fleet)
	title_label = fleet.title_label
	fleet.ship_card_pressed.connect(_on_card_clicked)
	fleet.crew_overlay_requested.connect(func(id: String): crew_overlay_requested.emit(id))
	fleet.pill_pressed.connect(_on_pill_pressed)
	fleet.set_footer(build_footer())


## The planning footer: instructions, the "still in Plan" line, End Planning + Cancel (Cancel asks
## first, in the footer's own dialog).
func build_footer() -> VBoxContainer:
	footer = VBoxContainer.new()
	footer.name = "PlanningFooter"
	footer.add_theme_constant_override("separation", 8)
	footer.add_child(HSeparator.new())
	instructions_label = _note(PlanningText.instructions())
	instructions_label.name = "InstructionsLabel"
	footer.add_child(instructions_label)
	still_in_plan_label = _note("")
	still_in_plan_label.name = "StillInPlanLabel"
	still_in_plan_label.visible = false
	footer.add_child(still_in_plan_label)
	var row := HBoxContainer.new()
	row.name = "FooterRow"
	row.add_theme_constant_override("separation", 6)
	footer.add_child(row)
	end_planning_button = _footer_button("EndPlanningButton", "End Planning")
	end_planning_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(end_planning_button)
	cancel_button = _footer_button("CancelButton", "Cancel")
	cancel_button.tooltip_text = RESET_TOOLTIP
	row.add_child(cancel_button)
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.name = "ResetDialog"
	reset_dialog.title = "Reset orders"
	reset_dialog.ok_button_text = "Reset"
	reset_dialog.cancel_button_text = "Keep orders"
	reset_dialog.dialog_text = RESET_TEXT
	footer.add_child(reset_dialog)
	end_planning_button.pressed.connect(func(): end_planning_pressed.emit())
	cancel_button.pressed.connect(func(): reset_dialog.popup_centered())
	reset_dialog.confirmed.connect(func(): reset_planning_confirmed.emit())
	return footer


static func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SecondaryLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func _footer_button(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_NONE
	return button


func setup_for_player(player_ships: Array[ShipState]) -> void:
	fleet.refresh_ships(player_ships)
	# The first ship is selected by default.
	if not player_ships.is_empty():
		fleet.select_ship(player_ships[0].ship_id)
	_refresh_plan_state()


## The crew plan changed (crew overlay): the cards follow it.
func refresh_crew_orders() -> void:
	refresh_crew_summaries()

## The status box on every card from the stored crew plan (a read-only query); the cards redraw
## their hull, rigging, crew and guns from the ship too.
func refresh_crew_summaries() -> void:
	fleet.refresh_cards()

func clear_ships() -> void:
	var none: Array[ShipState] = []
	fleet.refresh_ships(none)


func _on_card_clicked(ship_id: String) -> void:
	ship_selected.emit(ship_id)
	card_clicked.emit(ship_id)


## Make `ship_id` the ship whose orders are shown and tell the controller (as a card click does).
func select_ship(ship_id: String) -> void:
	if ship_list_items.has(ship_id):
		fleet.select_ship(ship_id)
		ship_selected.emit(ship_id)

func update_ship_display(ship_state: ShipState) -> void:
	var item: Control = fleet.card(ship_state.ship_id)
	if item != null:
		item.setup(ship_state)

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


## The footer's note: a ship still in Plan at End Planning sails the course shown.
static func still_in_plan_text(count: int) -> String:
	if count <= 0:
		return ""
	if count == 1:
		return "1 ship is still in Plan: she sails the course shown"
	return "%d ships still in Plan: they sail the course shown" % count


## A pill click: Plan <-> Done; a Locked ship stays as she is.
func _on_pill_pressed(ship_id: String) -> void:
	if _checklist == null:
		return
	match _checklist.state(ship_id):
		PlanChecklist.PLAN:
			_checklist.set_done(ship_id, true)
		PlanChecklist.DONE:
			_checklist.set_done(ship_id, false)
