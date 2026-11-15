extends RefCounted
## Test fixtures for crew tasks (not a test file). Use with
##   const CrewFixtures = preload("res://test/unit/crew_fixtures.gd")
## Fixtures set ShipState fields directly, as other test fixtures do.


## Puts a sail change to `target` in progress on `ship`, worked by `sections` (0-3 sailors,
## 4 = marines), with `done` g-t's completed. With `plotted` the sections count as plotted this
## g-t (they do not serve the guns).
static func give_sail_change(ship: ShipState, target: String, sections: Array, done: int = 0,
		plotted: bool = true) -> Dictionary:
	ship.task_seq += 1
	var task := ShipState.crew_task_from({
		"seq": ship.task_seq, "code": "SAIL", "sections": sections, "done": done, "started_turn": 1,
		"params": {"target": target, "from": ship.sail_state, "row": SailController.cost_row(ship, target)},
		"forced": false, "marines_available": false, "ended": "",
	})
	ship.crew_tasks.append(task)
	if plotted:
		for section in sections:
			if not ship.plotted_sections.has(int(section)):
				ship.plotted_sections.append(int(section))
	return task


## Orders a sail change in the ship's plot (crew_orders.sail_target).
static func order_sail(ship: ShipState, target: String) -> void:
	ship.plotted_actions["crew_orders"] = {"sail_target": target}
