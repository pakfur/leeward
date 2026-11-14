class_name PlanningSailUi
extends RefCounted
## PlanningSailUi - Pure presentation logic for the planning sail row and ship status badges.
## No scene nodes and no state changes: given a ShipState it says what text and controls to show.

const SAIL_NAMES := {
	"NS": "Furled",
	"FS": "Fighting sail",
	"MS": "Manoeuvring sail",
	"PS": "Plain sail",
}

const HINT := "Sections changing sail cannot serve the guns."
const CHOOSE_TEXT := "No change ordered. Choose one, or keep this sail."
const ORDERED_TEXT := "Ordered: %s. Press it again to cancel."

enum Mode { NONE, PROGRESS, ORDERED, CHOOSE }


## The sail's name alone ("Fighting sail"); unknown codes pass through.
static func sail_label(code: String) -> String:
	var upper := code.to_upper()
	return SAIL_NAMES.get(upper, upper)


static func sail_name(code: String) -> String:
	return sail_label(code)


static func plural(count: int, noun: String) -> String:
	return "%d %s%s" % [count, noun, "" if count == 1 else "s"]


## "Fighting sail — 1 turn, 1 section"
static func target_button_text(target: String, cost: Dictionary) -> String:
	return "%s — %s, %s" % [sail_label(target), plural(cost.get("turns", 0), "turn"), plural(cost.get("sections", 0), "section")]


static func status_badge(ship: ShipState) -> String:
	if ship.is_struck():
		return "STRUCK"
	if ship.is_dismasted():
		return "DISMASTED"
	if ship.fouled_with != "":
		return "FOULED"
	return ""


static func can_plot_movement(ship: ShipState) -> bool:
	return status_badge(ship) == ""


static func movement_block_reason(ship: ShipState) -> String:
	match status_badge(ship):
		"STRUCK": return "Ship has struck its colours and cannot move."
		"DISMASTED": return "Ship is dismasted and cannot move."
		"FOULED": return "Ship is fouled with %s and cannot move until it breaks free." % ship.fouled_with
	return ""


static func sail_row(ship: ShipState, targets: Array, costs: Dictionary) -> Dictionary:
	## Returns {mode, current, text, hint, buttons: [{target, text, pressed}]}.
	## `targets` is SailController.available_targets; `costs` maps target -> change_cost dict.
	## The choices keep their place once one is ordered: the ordered one is shown pressed and
	## pressing it again cancels the order (the status text says so).
	var row := {
		"mode": Mode.NONE,
		"current": sail_label(ship.sail_state),
		"text": "",
		"hint": "",
		"buttons": [],
	}
	if ship.is_struck():
		return row
	if not ship.sail_change.is_empty():
		row["mode"] = Mode.PROGRESS
		row["text"] = "Changing to %s — %s left" % [
			sail_label(ship.sail_change.get("target", "?")),
			plural(ship.sail_change.get("turns_left", 0), "turn")]
		row["hint"] = HINT
		return row
	var ordered: String = ship.plotted_actions.get("sail_change", "")
	if targets.is_empty() and ordered == "":
		return row
	var choices: Array = targets.duplicate()
	if ordered != "" and not choices.has(ordered):
		choices.append(ordered)
	row["mode"] = Mode.ORDERED if ordered != "" else Mode.CHOOSE
	row["text"] = ORDERED_TEXT % sail_label(ordered) if ordered != "" else CHOOSE_TEXT
	for target in choices:
		row["buttons"].append({"target": target, "text": target_button_text(target, costs.get(target, {})),
			"pressed": target == ordered})
	row["hint"] = HINT
	return row
