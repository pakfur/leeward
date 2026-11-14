class_name GameOverPanel
extends PanelContainer
## GameOverPanel - Modal result card shown over the map when the game ends.
##
## Presentation only: it formats TurnPhaseController.game_result and the final ship list and
## emits back_requested when the player wants to leave. It never touches game state.

signal back_requested()

const PLAYER_ID := 0
const ENEMY_ID := 1
const PANEL_SIZE := Vector2(460, 0)
const TOP_MARGIN := 24.0  # gap above the card: it sits at the upper centre, clear of the ships
const POINTS_NOTE := "Points: full value for each enemy ship struck, part value for sections destroyed."

var _headline_label: Label
var _reason_label: Label
var _turn_label: Label
var _grid: GridContainer
var _points_note_label: Label
var _back_button: Button


# --- Pure presentation helpers (unit tested) ---------------------------------

## "Victory" for a player win (winner 0), "Defeat" for an AI win (1), "Draw" otherwise.
static func headline(winner: int) -> String:
	match winner:
		PLAYER_ID:
			return "Victory"
		ENEMY_ID:
			return "Defeat"
	return "Draw"


## Victory points with one decimal, e.g. "18.5".
static func points_text(points: float) -> String:
	return "%.1f" % points


## "N of M".
static func struck_text(struck: int, total: int) -> String:
	return "%d of %d" % [struck, total]


## {"struck": int, "total": int} for one side's ships.
static func struck_counts(ships: Array, player_id: int) -> Dictionary:
	var struck := 0
	var total := 0
	for ship in ships:
		if ship.player_id != player_id:
			continue
		total += 1
		if ship.is_struck():
			struck += 1
	return {"struck": struck, "total": total}


## Why the game ended, from the player's point of view. `own` and `enemy` are struck_counts().
static func reason_text(reason: String, own: Dictionary, enemy: Dictionary) -> String:
	if reason == "turn limit":
		return "Turn limit reached"
	var own_all: bool = own["struck"] >= own["total"]
	var enemy_all: bool = enemy["struck"] >= enemy["total"]
	if own_all and enemy_all:
		return "Both sides have struck"
	if own_all:
		return "All your ships have struck"
	if enemy_all:
		return "All enemy ships have struck"
	return "The battle is over"


## Every string the panel shows, from a victory result and the final ship list.
static func summary(result: Dictionary, ships: Array) -> Dictionary:
	var own := struck_counts(ships, PLAYER_ID)
	var enemy := struck_counts(ships, ENEMY_ID)
	var points: Dictionary = result.get("points", {})
	return {
		"headline": headline(int(result.get("winner", -1))),
		"reason": reason_text(str(result.get("reason", "")), own, enemy),
		"turn": "Game ended on turn %d" % int(result.get("turn", 0)),
		"player_points": points_text(float(points.get(PLAYER_ID, 0.0))),
		"enemy_points": points_text(float(points.get(ENEMY_ID, 0.0))),
		"player_struck": struck_text(own["struck"], own["total"]),
		"enemy_struck": struck_text(enemy["struck"], enemy["total"]),
		"points_note": POINTS_NOTE,
	}


# --- Panel -------------------------------------------------------------------

func _ready() -> void:
	name = "GameOverPanel"
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = PANEL_SIZE

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_headline_label = Label.new()
	_headline_label.name = "HeadlineLabel"
	_headline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline_label.add_theme_font_size_override("font_size", 40)
	_headline_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	box.add_child(_headline_label)

	_reason_label = Label.new()
	_reason_label.name = "ReasonLabel"
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_reason_label)

	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_turn_label)

	box.add_child(HSeparator.new())

	_grid = GridContainer.new()
	_grid.name = "ResultGrid"
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 24)
	box.add_child(_grid)

	_points_note_label = Label.new()
	_points_note_label.name = "PointsNoteLabel"
	_points_note_label.theme_type_variation = &"SecondaryLabel"
	_points_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_points_note_label.custom_minimum_size = Vector2(PANEL_SIZE.x - 48, 0)
	box.add_child(_points_note_label)

	box.add_child(HSeparator.new())

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "Back to scenarios"
	_back_button.custom_minimum_size = Vector2(0, 40)
	_back_button.pressed.connect(func(): back_requested.emit())
	box.add_child(_back_button)


## Fill the card from the game result and the final ships.
func show_result(result: Dictionary, ships: Array) -> void:
	var text := summary(result, ships)
	_headline_label.text = text["headline"]
	_reason_label.text = text["reason"]
	_turn_label.text = text["turn"]
	_points_note_label.text = text["points_note"]
	for child in _grid.get_children():
		child.queue_free()
		_grid.remove_child(child)
	for cell in ["", "You", "Enemy",
			"Points scored", text["player_points"], text["enemy_points"],
			"Ships struck", text["player_struck"], text["enemy_struck"]]:
		var label := Label.new()
		label.text = cell
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(label)
	visible = true
	_place.call_deferred()  # after the layout has measured the new rows


## Upper centre of the screen at the panel's minimum size, so the final position of the ships
## (usually mid-map) stays visible below it.
func _place() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN + size.y
