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


## Puts `count` sections at the braces this g-t (a live T task, as begin_turn_tasks makes for a
## turn at MA 0): M, S4, S3 in worker order. The Tacking roll then has the crew-section DRM
## +2 x (3 - count) (5.D.2a). count 0 removes the T task.
static func give_tack_crew(ship: ShipState, count: int = 3) -> void:
	for k in range(ship.crew_tasks.size() - 1, -1, -1):
		if ship.crew_tasks[k].get("code", "") == "T":
			ship.crew_tasks.remove_at(k)
	if count <= 0:
		return
	var sections: Array = [ShipState.MARINES, 3, 2].slice(0, count)
	ship.task_seq += 1
	ship.crew_tasks.append(ShipState.crew_task_from({
		"seq": ship.task_seq, "code": "T", "sections": sections, "done": 0, "started_turn": 1,
		"params": {}, "forced": false, "marines_available": false, "ended": "",
	}))
	for section in sections:
		if not ship.plotted_sections.has(int(section)):
			ship.plotted_sections.append(int(section))


## Makes a rigging repair legal (8.F.3, 8.F.3a): `boxes` rigging boxes marked out of section 1
## and the ship at fighting sail.
static func allow_rigging_repair(ship: ShipState, boxes: int = 1) -> void:
	ship.sail_state = "FS"
	ship.rigging_current_hp[0] = maxi(0, ship.rigging_current_hp[0] - boxes)


## Marks out `boxes` hull boxes of section 1 (8.F.3: hull repair becomes legal).
static func allow_hull_repair(ship: ShipState, boxes: int = 1) -> void:
	ship.hull_current_hp[0] = maxi(0, ship.hull_current_hp[0] - boxes)
