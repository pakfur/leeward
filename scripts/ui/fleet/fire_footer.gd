class_name FireFooter
extends VBoxContainer
## The fleet panel's footer in the fire declaration step (board planning piece 3), view only: the
## instructions, a line saying how many ships with a shot hold fire, a refusal line and **Fire**,
## whose text says what the orders do (FireText.fire_button_text_with_marines). Bound to the fleet
## panel and the step's FireBoard, it sets the cards' fire pills (FIRE, NO TARGET, "✓ n ORDERS",
## NO FIRE: FireBoard.pill) and toggles Plan / Done on a pill click. The orders themselves are given
## on the board; GameController sends them on fire_pressed.

signal fire_pressed()

const INSTRUCTIONS := "Click a ship (or Tab) for her fire ring, pick a broadside, a chaser or her marines, then a target."

var hold_fire_label: Label = null
var error_label: Label = null
var fire_button: Button = null

var _fleet: FleetPanel = null
var _board: FireBoard = null


func _init() -> void:
	name = "FireFooter"
	add_theme_constant_override("separation", 8)
	add_child(HSeparator.new())
	add_child(_note(INSTRUCTIONS))
	hold_fire_label = _note("")
	hold_fire_label.name = "HoldFireLabel"
	hold_fire_label.visible = false
	add_child(hold_fire_label)
	error_label = _note("")
	error_label.name = "ErrorLabel"
	error_label.add_theme_color_override("font_color", Color(1, 0.4, 0.35, 1))
	error_label.visible = false
	add_child(error_label)
	fire_button = Button.new()
	fire_button.name = "FireButton"
	fire_button.custom_minimum_size = Vector2(0, 44)
	fire_button.focus_mode = Control.FOCUS_NONE  # Space and Enter stay the game's keys
	fire_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long order list wraps, never widens the panel
	fire_button.text = FireText.fire_button_text(0)
	fire_button.pressed.connect(_on_fire)
	add_child(fire_button)


static func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SecondaryLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## The step begins: follow `board` on `fleet`'s cards and select the first ship with a shot (else
## the first card). The connections are this footer's methods, so they go when it is freed.
func bind(fleet: FleetPanel, board: FireBoard) -> void:
	_fleet = fleet
	_board = board
	fleet.pill_pressed.connect(_on_pill_pressed)
	fleet.cards_changed.connect(refresh)
	board.changed.connect(refresh)
	board.checklist.changed.connect(refresh)
	var first := ""
	for id in fleet.cards:
		if board.has_shot(id):
			first = id
			break
	if first == "" and not fleet.cards.is_empty():
		first = fleet.cards.keys()[0]
	fleet.select_ship(first)
	refresh()


## Pills, the hold-fire line and the Fire button from the board's state (only while this is the
## fleet's footer and the step runs).
func refresh() -> void:
	if _fleet == null or _fleet.footer() != self or _board == null or not _board.is_active():
		return
	for id in _fleet.cards:
		var p := _board.pill(id)
		_fleet.cards[id].set_plan_state(card_state(str(p["state"])), card_text(p), _board.no_shot_reason(id))
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


func _on_fire() -> void:
	fire_pressed.emit()


## A pill click: Plan <-> Done (FireBoard.set_done; a ship with no shot stays Done).
func _on_pill_pressed(ship_id: String) -> void:
	if _fleet == null or _fleet.footer() != self or _board == null or not _board.is_active():
		return
	_board.set_done(ship_id, _board.state(ship_id) == PlanChecklist.PLAN)
