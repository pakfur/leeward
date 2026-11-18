class_name MoveSchedule
extends RefCounted
## Exact rational step times for proportional movement. Pure: no state, no dice.
##
## A ship plotting N steps takes step j at time (j + 1) / N of the g-t, so every
## ship finishes its plot at time 1. Times are Vector2i(numerator, denominator),
## always compared by cross-multiplication, never as floats. `times` holds the
## distinct step times <= 1 over all ships; a "segment" is an index into it.
## Steps beyond a ship's plot (N + k) fall on trailing segments at times 2, 3, ...

const START := Vector2i(0, 1)  ## pre-movement events
const END := Vector2i(1, 0)  ## the end check after the last segment; greater than every time

var plot_steps: Dictionary = {}  ## ship_id -> N (plot size this run)
var times: Array[Vector2i] = []  ## distinct step times <= 1 over all ships, ascending


func _init(p_plot_steps: Dictionary) -> void:
	plot_steps = p_plot_steps
	for id in plot_steps:
		var n: int = plot_steps[id]
		for j in range(n):
			_insert_time(step_time(j, n))


static func reduce(num: int, den: int) -> Vector2i:
	var a := absi(num)
	var b := absi(den)
	while b != 0:
		var t := a % b
		a = b
		b = t
	if a == 0:
		return Vector2i(num, den)
	@warning_ignore("integer_division")
	return Vector2i(num / a, den / a)


## -1, 0 or 1. A zero denominator (END) is greatest.
static func compare(a: Vector2i, b: Vector2i) -> int:
	if a.y == 0 and b.y == 0:
		return 0
	if a.y == 0:
		return 1
	if b.y == 0:
		return -1
	return signi(a.x * b.y - b.x * a.y)


## Time of step `step` of a plot of `steps`: (step+1)/steps, reduced; steps past the plot at 2, 3, ...
static func step_time(step: int, steps: int) -> Vector2i:
	if step < steps:
		return reduce(step + 1, steps)
	return Vector2i(step - steps + 2, 1)


func _insert_time(t: Vector2i) -> void:
	var i := 0
	while i < times.size():
		var c := compare(times[i], t)
		if c == 0:
			return
		if c > 0:
			break
		i += 1
	times.insert(i, t)


func _n(ship_id: String) -> int:
	return plot_steps.get(ship_id, 0)


func segment_of(ship_id: String, step: int) -> int:
	var n := _n(ship_id)
	if step >= n:
		return times.size() + (step - n)
	return times.find(step_time(step, n))


## The step the ship takes on `segment`, or -1 when it has none there.
func step_at(ship_id: String, segment: int) -> int:
	var n := _n(ship_id)
	if n == 0:
		return -1
	if segment >= times.size():
		return n + (segment - times.size())
	var t := times[segment]
	if (t.x * n) % t.y != 0:
		return -1
	@warning_ignore("integer_division")
	return t.x * n / t.y - 1


## The ship's scheduled steps on segments before `segment`.
func steps_before(ship_id: String, segment: int) -> int:
	var n := _n(ship_id)
	var count := 0
	for j in range(n):
		if segment_of(ship_id, j) < segment:
			count += 1
	return count + maxi(0, segment - times.size())


## ship_id -> Array of steps; the scheduled times plus the most extra steps.
func segment_count(steps_by_ship: Dictionary) -> int:
	var extra := 0
	for id in steps_by_ship:
		extra = maxi(extra, (steps_by_ship[id] as Array).size() - _n(id))
	return times.size() + extra


func time_of(segment: int) -> Vector2i:
	if segment < times.size():
		return times[segment]
	return Vector2i(2 + segment - times.size(), 1)


## First segment after `after` on which any of ship_ids has a step it still holds; else segment_count.
func next_segment(ship_ids: Array, after: int, steps_by_ship: Dictionary) -> int:
	var count := segment_count(steps_by_ship)
	for seg in range(after + 1, count):
		for id in ship_ids:
			var j := step_at(id, seg)
			if j >= 0 and j < (steps_by_ship[id] as Array).size():
				return seg
	return count
