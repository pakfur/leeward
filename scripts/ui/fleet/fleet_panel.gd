class_name FleetPanel
extends VBoxContainer
## The side panel for the whole turn (board planning piece 4), view only: **Players** (the roster,
## PlayerRoster, fed RosterRows.rows; hidden while it has no rows), **Your ships** (a ShipListItem
## card per own ship, scrolling; the selected card is expanded, the others are one row) and a
## footer slot pinned at the bottom that the phase fills (End Planning + Cancel, Fire, End Turn).
## Cards are kept by ship id: refresh_ships adds, updates, reorders and removes them, so a prize
## taken joins and a ship lost leaves without rebuilding the rest. The panel never asks the server
## for anything; the phase's owner reads the signals and sets the pills (ShipListItem.set_plan_state).

## A card was clicked (not a selection made by code): the card is selected first.
signal ship_card_pressed(ship_id: String)
## A card's Crew & damage button.
signal crew_overlay_requested(ship_id: String)
## A card's Plan / Done pill (a Locked pill emits nothing: the button is disabled).
signal pill_pressed(ship_id: String)
## refresh_ships added, redrew or removed cards: the footer sets the pills of new cards.
signal cards_changed()

const ShipListItemScene = preload("res://scenes/ui/ship_list_item.tscn")
const TITLE := "Your Fleet"
const PLAYERS_HEADER := "Players"
const SHIPS_HEADER := "Your ships"

var title_label: Label = null
var players_header: Label = null
var ships_header: Label = null  # shown with the Players section (alone it would repeat the title)
var roster: PlayerRoster = null
var ship_list: VBoxContainer = null
var footer_slot: VBoxContainer = null
var cards: Dictionary = {}  # ship_id -> ShipListItem, in card order
var selected_ship_id := ""
var local_player_id := 0

var _footer: Control = null


func _init() -> void:
	name = "FleetPanel"
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.theme_type_variation = &"HeaderLabel"
	title_label.text = TITLE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label)
	add_child(HSeparator.new())
	players_header = _header(PLAYERS_HEADER)
	players_header.name = "PlayersHeader"
	players_header.visible = false
	add_child(players_header)
	roster = PlayerRoster.new()
	roster.name = "PlayerRoster"
	roster.visible = false
	add_child(roster)
	ships_header = _header(SHIPS_HEADER)
	ships_header.name = "ShipsHeader"
	ships_header.visible = false
	add_child(ships_header)
	var scroll := ScrollContainer.new()
	scroll.name = "ShipScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	ship_list = VBoxContainer.new()
	ship_list.name = "ShipList"
	ship_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_list.add_theme_constant_override("separation", 6)
	scroll.add_child(ship_list)
	footer_slot = VBoxContainer.new()
	footer_slot.name = "FooterSlot"
	footer_slot.add_theme_constant_override("separation", 8)
	add_child(footer_slot)


static func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"StrongLabel"
	return label


## A new game for `local_player_id`: no cards, no roster rows (the footer is the phase's).
func setup(player_id: int) -> void:
	local_player_id = player_id
	refresh_roster([])
	var none: Array[ShipState] = []
	refresh_ships(none)


## The Players section from RosterRows.rows; no rows hides it (and the Your ships header, which
## would then sit right under the Your Fleet title).
func refresh_roster(rows: Array) -> void:
	roster.show_rows(rows)
	roster.visible = not rows.is_empty()
	players_header.visible = roster.visible
	ships_header.visible = roster.visible


## One card per ship, in this order: a new ship gets a card, a known one is redrawn from `ships`
## (and her crew plan), a card whose ship is not listed leaves. A selected card that leaves takes
## the selection with it; with none selected the first card is.
func refresh_ships(ships: Array[ShipState]) -> void:
	var wanted := {}
	for ship in ships:
		wanted[ship.ship_id] = true
	for id in cards.keys():
		if not wanted.has(id):
			var gone: Control = cards[id]
			cards.erase(id)
			ship_list.remove_child(gone)
			gone.queue_free()
			if selected_ship_id == id:
				selected_ship_id = ""
	var ordered := {}
	for ship in ships:
		var item: Control = cards.get(ship.ship_id)
		if item == null:
			item = _make_card(ship.ship_id)
		ordered[ship.ship_id] = item
		ship_list.move_child(item, ordered.size() - 1)
		_draw_card(item, ship)
	cards = ordered
	if selected_ship_id == "" and not ships.is_empty():
		_mark_selected(ships[0].ship_id)  # every card was just drawn
	cards_changed.emit()


## Redraws every card from her ship and crew plan (a crew order, a reset, a request's result).
func refresh_cards() -> void:
	for id in cards:
		var item: Control = cards[id]
		if item.ship_state != null:
			_draw_card(item, item.ship_state)


func card(ship_id: String) -> Control:
	return cards.get(ship_id)


## Expands `ship_id`'s card and collapses the others, and redraws the cards (as the planning panel
## did on every selection); emits nothing (a click emits ship_card_pressed).
func select_ship(ship_id: String) -> void:
	_mark_selected(ship_id)
	refresh_cards()


## Expands `ship_id`'s card (none for an unknown id) and collapses the others, with no redraw.
func _mark_selected(ship_id: String) -> void:
	if selected_ship_id != "" and cards.has(selected_ship_id):
		cards[selected_ship_id].set_selected_state(false)
	selected_ship_id = ship_id if cards.has(ship_id) else ""
	if selected_ship_id != "":
		cards[selected_ship_id].set_selected_state(true)


## Puts `control` in the footer slot; the previous footer is freed. `null` clears the slot.
func set_footer(control: Control) -> void:
	if control == _footer:
		return
	if _footer != null and is_instance_valid(_footer):
		footer_slot.remove_child(_footer)
		_footer.queue_free()
	_footer = control
	if _footer != null:
		if _footer.get_parent() != null:
			_footer.get_parent().remove_child(_footer)
		footer_slot.add_child(_footer)


func footer() -> Control:
	return _footer


func _make_card(ship_id: String) -> Control:
	var item: Control = ShipListItemScene.instantiate()
	ship_list.add_child(item)
	item.selected.connect(func(): _on_card_clicked(ship_id))
	item.crew_pressed.connect(func(): crew_overlay_requested.emit(ship_id))
	item.pill_pressed.connect(func(): pill_pressed.emit(ship_id))
	return item


func _draw_card(item: Control, ship: ShipState) -> void:
	item.setup(ship)
	if GameState.crew_task_controller != null:
		item.set_crew_plan(GameState.crew_task_controller.current_plan(ship.ship_id))


func _on_card_clicked(ship_id: String) -> void:
	select_ship(ship_id)
	ship_card_pressed.emit(ship_id)
