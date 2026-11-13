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

enum Mode { NONE, PROGRESS, ORDERED, CHOOSE }


static func sail_name(code: String) -> String:
	var upper := code.to_upper()
	return "%s (%s)" % [SAIL_NAMES.get(upper, upper), upper]


static func plural(count: int, noun: String) -> String:
	return "%d %s%s" % [count, noun, "" if count == 1 else "s"]


static func target_button_text(target: String, cost: Dictionary) -> String:
	return "→ %s (%s, %s)" % [target, plural(cost.get("turns", 0), "turn"), plural(cost.get("sections", 0), "section")]


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
	## Returns {mode, current, text, hint, buttons: [{target, text}], can_cancel}.
	## `targets` is SailController.available_targets; `costs` maps target -> change_cost dict.
	var row := {
		"mode": Mode.NONE,
		"current": sail_name(ship.sail_state),
		"text": "",
		"hint": "",
		"buttons": [],
		"can_cancel": false,
	}
	if ship.is_struck():
		return row
	if not ship.sail_change.is_empty():
		row["mode"] = Mode.PROGRESS
		row["text"] = "Changing to %s — %s left" % [
			ship.sail_change.get("target", "?"),
			plural(ship.sail_change.get("turns_left", 0), "turn")]
		row["hint"] = HINT
		return row
	var ordered: String = ship.plotted_actions.get("sail_change", "")
	if ordered != "":
		row["mode"] = Mode.ORDERED
		row["text"] = "Ordered: → %s" % ordered
		row["can_cancel"] = true
		row["hint"] = HINT
		return row
	if targets.is_empty():
		return row
	row["mode"] = Mode.CHOOSE
	for target in targets:
		row["buttons"].append({"target": target, "text": target_button_text(target, costs.get(target, {}))})
	row["hint"] = HINT
	return row
