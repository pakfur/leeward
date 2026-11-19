class_name BoardPlanning
extends Node
## Planning on the board, pieces 1 and 2 (spec docs/superpowers/specs/2026-11-18-board-planning-design.md):
## the view-side coordinator GameController owns in PLANNING. It holds the local player's Plan /
## Done checklist, the radial menu of one own ship (her main ring, or her Orders ring), the map
## badges and the chip box of the Move-mode ship, builds the ring items and reads the PLANNING
## keys. View only: it reads state and queries the server (`course_options`,
## `start_of_turn_course`, `order_options`), never mutates either; course, crew and order requests
## go through GameController (`reset_course_requested`, `crew_overlay_requested`, `order_toggled`,
## `rally_requested`, and the course clicks it routes while `move_ship_id()` is set).

signal crew_overlay_requested(ship_id: String)
signal reset_course_requested(ship_id: String)
## Move mode entered for `ship_id`, or left ("").
signal move_mode_changed(ship_id: String)
## A ring opened for `ship_id` (a click, Tab, Space): GameController selects her.
signal ring_opened(ship_id: String)
## An Orders-ring toggle: `order` is "lead", "escape" or "surrender", `on` the state asked for.
signal order_toggled(ship_id: String, order: String, on: bool)
## The Orders ring's Rally (14.B.3: one d10, rolled at once by the server).
signal rally_requested(ship_id: String)

const ICONS := {
	"move": preload("res://assets/ui/radial/move.svg"),
	"crew": preload("res://assets/ui/radial/crew.svg"),
	"reset": preload("res://assets/ui/radial/reset.svg"),
	"done": preload("res://assets/ui/radial/done.svg"),
	"undo": preload("res://assets/ui/radial/undo.svg"),
	"orders": preload("res://assets/ui/radial/orders.svg"),
	"signal": preload("res://assets/ui/radial/signal.svg"),
	"lead": preload("res://assets/ui/radial/lead.svg"),
	"escape": preload("res://assets/ui/radial/escape.svg"),
	"surrender": preload("res://assets/ui/radial/surrender.svg"),
	"rally": preload("res://assets/ui/radial/rally.svg"),
	"back": preload("res://assets/ui/radial/back.svg"),
}
## Which ring is open: the ship's main ring or her Orders ring.
const MAIN := "main"
const ORDERS := "orders"
## The Signal item's greyed reason while the composer is not built yet (and the server has none).
const SIGNAL_OFF := "Signals: coming next"
const RALLY_HINT := "One d10 against her morale rating, rolled at once."
const RESET_OFF := "No course plotted: she sails her default course."
## Fallback wording for a locked ship whose lock carries no reason of its own.
const LOCKED_OFF := "She cannot plot movement this turn."
## How far above her centre on screen (in world units, hex size 1) a ship's badge sits: clear of
## the hull and the selection ring on the water (the speed label goes astern).
const BADGE_LIFT := 1.1

var _checklist := PlanChecklist.new()
var _radial: RadialMenu
var _badges: PlanBadges
var _chips: CourseChips
var _camera: Camera3D = null
var _world_of := Callable()  # ship_id -> Vector3 (her centre on the water) or null
var _safe_rect := Callable()  # -> Rect2 of the map area, clear of the side panel
var _selected := Callable()  # -> String: the selected own ship (Space, Tab's start)
var _planning := false
var _own_ids: Array = []  # the own ships in the checklist, in card order
var _ring_ship := ""
var _ring_kind := MAIN
var _move_ship := ""
## The local player, whose ships these are (the `order_options` query's player).
var player_id := 0


func _init() -> void:
	name = "BoardPlanning"
	_radial = RadialMenu.new()
	_radial.ui_scale = CrewStyle.K  # the crew overlay's scaling of prototype pixels
	_radial.item_chosen.connect(_on_item_chosen)
	_radial.closed.connect(_on_ring_closed)
	_badges = PlanBadges.new()
	_badges.name = "PlanBadges"
	_badges.lift = BADGE_LIFT
	_chips = CourseChips.new()
	_chips.ui_scale = CrewStyle.K
	_chips.done_pressed.connect(_on_chips_done)
	_chips.keep_pressed.connect(leave_move)
	_checklist.changed.connect(_on_checklist_changed)


## `ui_parent`: where the ring, badges and chip box go (null: under this node, as in tests).
## `world_of(ship_id)` gives a ship's centre in the world, `safe_rect()` the map area,
## `selected()` the selected own ship's id.
func setup(ui_parent: Node, camera: Camera3D, world_of: Callable, safe_rect: Callable,
		selected: Callable) -> void:
	_camera = camera
	_world_of = world_of
	_safe_rect = safe_rect
	_selected = selected
	_badges.setup(camera)
	if safe_rect.is_valid():
		_badges.map_rect_provider = safe_rect
		_chips.map_rect_provider = safe_rect
	_chips.setup(camera)
	var parent: Node = ui_parent if ui_parent != null else self
	for c in controls():
		if c.get_parent() == null:
			parent.add_child(c)


## The Controls this node puts over the map (GameController orders them under its overlays).
func controls() -> Array[Control]:
	return [_badges, _chips, _radial] as Array[Control]


func checklist() -> PlanChecklist:
	return _checklist


func radial_menu() -> RadialMenu:
	return _radial


func badges() -> PlanBadges:
	return _badges


func course_chips() -> CourseChips:
	return _chips


func is_planning() -> bool:
	return _planning


## PLANNING begins: every own ship that can plot is in Plan, the others Locked.
func begin_planning(own_ships: Array[ShipState]) -> void:
	close_ring()
	leave_move()
	var ids: Array = []
	for ship in own_ships:
		ids.append(ship.ship_id)
	_planning = true
	_own_ids = ids
	_checklist.begin(ids, _movable(ids))


## PLANNING is over (any phase, a new game, leaving the game): ring, chip box and badges close,
## Move mode is left and the checklist is emptied.
func end_planning() -> void:
	close_ring()
	leave_move()
	_planning = false
	_own_ids = []
	_checklist.clear()
	_badges.clear()


## Re-reads which ships can plot (a rally, a cut cable from the Developer UI): the checklist and
## badges follow, and a Move-mode ship that can no longer plot leaves Move mode.
func refresh() -> void:
	if not _planning:
		return
	var movable := _movable(_ids())
	_checklist.refresh_movable(movable)
	if _move_ship != "" and not movable.get(_move_ship, false):
		leave_move()
	_show_badges()  # a standing order (lead, escape, surrender) given or withdrawn


# --- ring ----------------------------------------------------------------------------------------

## The ring of an own ship: Move, Crew & damage, Orders, Signal, Reset course, then Done (in Plan)
## or Plan again (Done or Locked). Greyed items carry the server's reasons. A surrendered ship
## (14.B, struck) has only what does not need her in play: her Orders ring's Rally.
func ring_items(ship: ShipState) -> Array[RadialItem]:
	if ship.surrendered:
		return orders_items(ship)
	var items: Array[RadialItem] = []
	var block := "" if PlanningSailUi.can_plot_movement(ship) else _block_reason(ship)
	items.append(RadialItem.make("move", "Move", ICONS["move"],
		"Plot her course hex by hex on the map.", block))
	items.append(RadialItem.make("crew", "Crew & damage", ICONS["crew"],
		"Crew, sails, fires, repairs and boarding (C)."))
	items.append(RadialItem.make("orders", "Orders", ICONS["orders"],
		"Lead, escape, surrender, rally."))
	var signal_error := str(_order_options(ship.ship_id).get("signal", {}).get("error", ""))
	items.append(RadialItem.make("signal", "Signal", ICONS["signal"],
		"Send a flag signal to your squadron.", signal_error if signal_error != "" else SIGNAL_OFF))
	items.append(RadialItem.make("reset", "Reset course", ICONS["reset"],
		"Back to her default course.", "" if _has_own_course(ship.ship_id) else RESET_OFF))
	if _checklist.state(ship.ship_id) == PlanChecklist.PLAN:
		items.append(RadialItem.make("done", "Done", ICONS["done"], "Her orders are given."))
	else:
		var off := _block_reason(ship) if _checklist.state(ship.ship_id) == PlanChecklist.LOCKED else ""
		items.append(RadialItem.make("undo", "Plan again", ICONS["undo"], "Back to Plan.", off))
	return items


## The Orders ring (from `order_options`; items the scenario does not use are left out): Cast the
## lead, Declare escape and Surrender (toggles, `on` when ordered), Rally, then Back. A
## surrendered ship has Rally only.
func orders_items(ship: ShipState) -> Array[RadialItem]:
	var items: Array[RadialItem] = []
	var o := _order_options(ship.ship_id)
	if o.is_empty():
		return items
	var rally: Dictionary = o.get("rally", {})
	var rally_item: RadialItem = null
	if rally.get("shown", false):
		rally_item = RadialItem.make("rally", "Rally", ICONS["rally"], RALLY_HINT,
			str(rally.get("error", "")))
	if ship.surrendered:
		if rally_item != null:
			items.append(rally_item)
		return items  # nothing else is hers to order while she is struck
	var lead: Dictionary = o.get("lead", {})
	var lead_on: bool = lead.get("on", false)
	items.append(RadialItem.make("lead", "Cast the lead: on" if lead_on else "Cast the lead",
		ICONS["lead"], "Sound ahead and bear off shoal water.", str(lead.get("error", "")), lead_on))
	var escape: Dictionary = o.get("escape", {})
	if escape.get("shown", false):
		var esc_on: bool = escape.get("on", false)
		items.append(RadialItem.make("escape", "Escape declared" if esc_on else "Declare escape",
			ICONS["escape"], "Withdraw the declaration." if esc_on else "Leave the map by an escape edge.",
			str(escape.get("error", "")), esc_on))
	var surrender: Dictionary = o.get("surrender", {})
	if surrender.get("shown", false):
		var sur_on: bool = surrender.get("on", false)
		items.append(RadialItem.make("surrender", "Surrender ordered" if sur_on else "Surrender",
			ICONS["surrender"], "Withdraw the order." if sur_on else "She strikes at the morale check.",
			str(surrender.get("error", "")), sur_on))
	if rally_item != null:
		items.append(rally_item)
	items.append(RadialItem.make("back", "Back", ICONS["back"], "Back to her main ring (Esc)."))
	return items


## Opens `ship_id`'s ring (leaving Move mode: a ship is never in Move mode with her ring open).
func open_ring(ship_id: String) -> void:
	var ship := GameState.get_ship(ship_id)
	if ship == null:
		return
	leave_move()
	if _safe_rect.is_valid() and is_inside_tree():
		_radial.set_safe_rect(_safe_rect.call())
	_radial.set_anchor_provider(_screen_point_of.bind(ship_id))
	_ring_kind = MAIN
	_radial.open(ring_items(ship), ship.ship_name, _subtitle(ship))
	_ring_ship = ship_id
	ring_opened.emit(ship_id)


## The open ring's ship's Orders ring, in place (same anchor).
func open_orders() -> void:
	_switch_ring(ORDERS)


## Back from the Orders ring to the main ring, in place.
func back_to_main() -> void:
	_switch_ring(MAIN)


func close_ring() -> void:
	_radial.close()


## The ship whose ring is open, or "".
func ring_ship_id() -> String:
	return _ring_ship if _radial.is_open() else ""


## Which ring is open (MAIN or ORDERS), or "" when none is.
func ring_kind() -> String:
	return _ring_kind if _radial.is_open() else ""


## Re-reads the open ring's items and subtitle in place (an order given, a rally rolled); a note
## in the caption stays.
func refresh_ring() -> void:
	var ship := GameState.get_ship(ring_ship_id())
	if ship != null:
		_radial.refresh_items(_current_items(ship), _subtitle(ship))


## Shows `text` in the open ring's caption (a refusal when `warn`, a rally's result).
func show_note(text: String, warn := false) -> void:
	_radial.show_note(text, warn)


## The caption of a rally, from MoraleController.rally's RALLY event data (roll, rating, passed,
## quality | breaks). Pure.
static func rally_caption(data: Dictionary) -> String:
	var head := "Rally: d10 %d against %d — " % [int(data.get("roll", 0)), int(data.get("rating", 0))]
	if data.get("passed", false):
		return head + "she is back in play"
	if data.get("breaks", false):
		return head + "failed: she has struck for good"
	return head + "failed: crew quality now %s" % str(data.get("quality", ""))


# --- Move mode -----------------------------------------------------------------------------------

## Today's hex-by-hex course plotting for `ship_id` only. Refused for a ship that cannot plot.
func enter_move(ship_id: String) -> void:
	var ship := GameState.get_ship(ship_id)
	if ship == null or not PlanningSailUi.can_plot_movement(ship):
		return
	close_ring()
	if _move_ship == ship_id:
		return
	_move_ship = ship_id
	_checklist.set_done(ship_id, false)  # plotting her again puts her back in Plan
	move_mode_changed.emit(ship_id)


func leave_move() -> void:
	if _move_ship == "":
		return
	_move_ship = ""
	_chips.hide_chips()
	move_mode_changed.emit("")


func move_ship_id() -> String:
	return _move_ship


## The Move-mode ship's course readout (GameController._course_info) at her course end.
func show_course(info: Dictionary, world_end: Variant) -> void:
	if _move_ship == "":
		return
	_chips.show_course(info, world_end)


# --- keys ----------------------------------------------------------------------------------------

## Tab (Shift+Tab: backward), Space, Enter and Esc while planning; true when the key was taken.
func handle_key(keycode: int, backward := false) -> bool:
	if not _planning:
		return false
	match keycode:
		KEY_TAB:
			var after := _move_ship if _move_ship != "" else ring_ship_id()
			var next := ""
			if after == "":
				# The first Tab starts at the selected ship: her own ring when she is in Plan.
				after = _selected_id()
				if _checklist.state(after) == PlanChecklist.PLAN:
					next = after
			if next == "":
				next = _checklist.prev_in_plan(after) if backward else _checklist.next_in_plan(after)
			if next != "":
				leave_move()
				open_ring(next)
			return true
		KEY_SPACE:
			var id := _selected_id()
			if _checklist.state(id) == "":
				return false
			if ring_ship_id() != id:
				open_ring(id)
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if _move_ship != "":
				_on_chips_done()
				return true
			if ring_ship_id() != "":
				var id := ring_ship_id()
				close_ring()
				_checklist.set_done(id, true)
				return true
			return false
		KEY_ESCAPE:
			if _move_ship != "":
				var id := _move_ship
				leave_move()
				open_ring(id)
				return true
			var ring_ship := GameState.get_ship(ring_ship_id())
			if ring_kind() == ORDERS and ring_ship != null and not ring_ship.surrendered:
				back_to_main()
				return true
			if _radial.is_open():
				close_ring()
				return true
			return false
	return false


# --- internals -----------------------------------------------------------------------------------

func _on_item_chosen(item_id: String) -> void:
	var id := _ring_ship
	# A clicked ring button takes focus; let Space / Enter reach the board again.
	if is_inside_tree():
		get_viewport().gui_release_focus()
	match item_id:
		"move":
			enter_move(id)
		"crew":
			close_ring()
			leave_move()
			crew_overlay_requested.emit(id)
		"reset":
			close_ring()
			reset_course_requested.emit(id)
		"done":
			close_ring()
			leave_move()
			_checklist.set_done(id, true)
		"undo":
			close_ring()
			leave_move()
			_checklist.set_done(id, false)
		"orders":
			open_orders()
		"back":
			back_to_main()
		"lead", "escape", "surrender":
			var now: bool = _order_options(id).get(item_id, {}).get("on", false)
			order_toggled.emit(id, item_id, not now)
		"rally":
			rally_requested.emit(id)
		# "signal": the composer comes with piece 2's Task 3.


func _on_ring_closed() -> void:
	_ring_ship = ""
	_ring_kind = MAIN


func _switch_ring(kind: String) -> void:
	var ship := GameState.get_ship(ring_ship_id())
	if ship == null:
		return
	_ring_kind = kind
	_radial.open(_current_items(ship), ship.ship_name, _subtitle(ship))


func _current_items(ship: ShipState) -> Array[RadialItem]:
	return orders_items(ship) if _ring_kind == ORDERS else ring_items(ship)


func _on_chips_done() -> void:
	var id := _move_ship
	leave_move()
	_checklist.set_done(id, true)


func _on_checklist_changed() -> void:
	_show_badges()
	var id := ring_ship_id()
	if id != "":
		var ship := GameState.get_ship(id)
		if ship != null:
			_radial.refresh_items(_current_items(ship), _subtitle(ship))  # Done / Plan again follows, in place


func _show_badges() -> void:
	var entries := {}
	for id in _ids():
		var st := _checklist.state(id)
		var world: Variant = _world_of.call(id) if _world_of.is_valid() else null
		if st == "" or not (world is Vector3):
			continue
		var ship := GameState.get_ship(id)
		if ship != null and ship.surrendered:
			st = PlanBadges.SURRENDERED
		entries[id] = {"world": world, "state": st, "marks": _standing_marks(ship)}
	if entries.is_empty():
		_badges.clear()
	else:
		_badges.show_for(entries)


## The standing orders shown beside her pill (PlanBadges marks), read from her state.
func _standing_marks(ship: ShipState) -> Array[String]:
	var marks: Array[String] = []
	if ship == null:
		return marks
	if ship.casts_lead():
		marks.append(PlanBadges.MARK_LEAD)
	if ship.escape_declared:
		marks.append(PlanBadges.MARK_ESCAPE)
	if ship.surrender_ordered:
		marks.append(PlanBadges.MARK_SURRENDER)
	return marks


func _screen_point_of(ship_id: String) -> Variant:
	if _camera == null or not _world_of.is_valid():
		return null
	var world: Variant = _world_of.call(ship_id)
	if not (world is Vector3) or _camera.is_position_behind(world):
		return null
	return _camera.unproject_position(world)


func _subtitle(ship: ShipState) -> String:
	if not PlanningSailUi.can_plot_movement(ship):
		var badge := PlanningSailUi.status_badge(ship)
		return badge.capitalize() if badge != "" else "Cannot move"
	var options: Dictionary = _course_options(ship.ship_id)
	var course := "course %d MP" % int(options.get("mp_used", 0)) if _has_own_course(ship.ship_id) \
		else "default course"
	return "Speed %d · %s" % [ship.speed, course]


## A course of her own: the stored course differs from the one stored at the planning start.
func _has_own_course(ship_id: String) -> bool:
	var path: Array = _course_options(ship_id).get("path", [])
	var start: Array = []
	if GameState.phase_controller:
		start = GameState.phase_controller.start_of_turn_course(ship_id)  # read-only query
	if path.size() != start.size():
		return true
	for i in path.size():
		var s := MovementTypes.PlotStep.from_dict(start[i])
		if s.hex != path[i].hex or s.facing != path[i].facing:
			return true
	return false


func _order_options(ship_id: String) -> Dictionary:
	if GameState.phase_controller == null:
		return {}
	return GameState.phase_controller.order_options(player_id, ship_id)  # read-only query


func _course_options(ship_id: String) -> Dictionary:
	if GameState.phase_controller == null:
		return {}
	return GameState.phase_controller.course_options(ship_id)  # read-only query


func _block_reason(ship: ShipState) -> String:
	var why := PlanningSailUi.movement_block_reason(ship)
	return why if why != "" else LOCKED_OFF


func _movable(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		var ship := GameState.get_ship(str(id))
		out[str(id)] = ship != null and PlanningSailUi.can_plot_movement(ship)
	return out


func _ids() -> Array:
	return _own_ids


func _selected_id() -> String:
	return str(_selected.call()) if _selected.is_valid() else ""
