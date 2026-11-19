class_name PlanningFooter
extends VBoxContainer
## The fleet panel's footer in PLANNING, view only: the instructions, the "still in Plan" line, End
## Planning and Cancel (Cancel asks first, in the footer's own dialog). Bound to the fleet panel and
## board planning's PlanChecklist, it sets each card's Plan / Done pill and toggles it on a pill
## click. GameController sends the requests on its signals.

signal end_planning_pressed()
signal reset_planning_confirmed()  ## Cancel, confirmed: every order back to the start of the turn

const RESET_TOOLTIP := "Reset every order this turn to how it was at the start of the turn"
const RESET_TEXT := "Reset all orders for this turn? Courses, crew, sail and boarding orders go back to how they were at the start of the turn."

var instructions_label: Label = null
var still_in_plan_label: Label = null
var end_planning_button: Button = null
var cancel_button: Button = null
var reset_dialog: ConfirmationDialog = null

var _fleet: FleetPanel = null
var _checklist: PlanChecklist = null


func _init() -> void:
	name = "PlanningFooter"
	add_theme_constant_override("separation", 8)
	add_child(HSeparator.new())
	instructions_label = _note(PlanningText.instructions())
	instructions_label.name = "InstructionsLabel"
	add_child(instructions_label)
	still_in_plan_label = _note("")
	still_in_plan_label.name = "StillInPlanLabel"
	still_in_plan_label.visible = false
	add_child(still_in_plan_label)
	var row := HBoxContainer.new()
	row.name = "FooterRow"
	row.add_theme_constant_override("separation", 6)
	add_child(row)
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
	add_child(reset_dialog)
	end_planning_button.pressed.connect(_on_end_planning)
	cancel_button.pressed.connect(_on_cancel)
	reset_dialog.confirmed.connect(_on_reset_confirmed)


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
	button.focus_mode = Control.FOCUS_NONE  # Space and Enter stay the game's keys
	return button


## Follow `checklist` on `fleet`'s cards: each pill and the "still in Plan" line. The connections
## are this footer's methods, so they go when the footer is freed (the next phase's footer).
func bind(fleet: FleetPanel, checklist: PlanChecklist) -> void:
	_fleet = fleet
	_checklist = checklist
	fleet.pill_pressed.connect(_on_pill_pressed)
	fleet.cards_changed.connect(refresh)
	if checklist != null:
		checklist.changed.connect(refresh)
	refresh()


## The pills and the "still in Plan" line from the checklist (only while this is the fleet's footer).
func refresh() -> void:
	if _fleet == null or _fleet.footer() != self:
		return
	for id in _fleet.cards:
		_fleet.cards[id].set_plan_state(_checklist.state(id) if _checklist != null else "")
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


func _on_end_planning() -> void:
	end_planning_pressed.emit()


func _on_cancel() -> void:
	reset_dialog.popup_centered()


func _on_reset_confirmed() -> void:
	reset_planning_confirmed.emit()


## A pill click: Plan <-> Done; a Locked ship stays as she is.
func _on_pill_pressed(ship_id: String) -> void:
	if _checklist == null or _fleet == null or _fleet.footer() != self:
		return
	match _checklist.state(ship_id):
		PlanChecklist.PLAN:
			_checklist.set_done(ship_id, true)
		PlanChecklist.DONE:
			_checklist.set_done(ship_id, false)
