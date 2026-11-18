class_name CombatTables
extends RefCounted
## CombatTables - the 1997 Close Action combat charts, loaded from
## data/rules/*.json. Owned by DataManager (DataManager.combat_tables).
## Gunfire result strings are parsed once at load time.
## Validate the JSON after edits:
##   python3 .claude/skills/validate-rule-table/scripts/validate_combat.py

const RESULT_ROWS := 52
const MAX_RANGE := 15
const FRENCH_FIRST_RANGE := 11

var _gunnery_factor: Dictionary = {}
var _bgn_rows: Array = []
var _results: Array = []   # index fgn-1 -> {"ch": int, "low": {col: tokens}, "high": {col: tokens}}
var _modifiers: Dictionary = {}
var _crew_loss: Dictionary = {}
var _drifting: Dictionary = {}
var _unfouling: Dictionary = {}
var _crew_quality: Dictionary = {}
var _critical_hits: Dictionary = {}
var _poor_maneuvering: Dictionary = {}
var _crew_tasks: Dictionary = {}
var _fire: Dictionary = {}
var _boarding: Dictionary = {}
var _grappling: Dictionary = {}
var _marine_fire: Dictionary = {}

func load_all(dir: String = "res://data/rules/") -> bool:
	var gf = _load_json(dir + "gunnery_factor_table.json")
	var bgn = _load_json(dir + "basic_gunfire_number_table.json")
	var results = _load_json(dir + "gunfire_results_table.json")
	var mods = _load_json(dir + "gunfire_modifiers.json")
	var crew_loss = _load_json(dir + "crew_loss_table.json")
	var drifting = _load_json(dir + "drifting_table.json")
	var unfouling = _load_json(dir + "unfouling_table.json")
	var crew_quality = _load_json(dir + "crew_quality_table.json")
	var critical_hits = _load_json(dir + "critical_hits_table.json")
	var poor_maneuvering = _load_json(dir + "poor_maneuvering_table.json")
	var crew_tasks = _load_json(dir + "crew_tasks.json")
	var fire = _load_json(dir + "fire_table.json")
	var boarding = _load_json(dir + "boarding_combat_table.json")
	var grappling = _load_json(dir + "grappling_table.json")
	var marine_fire = _load_json(dir + "marine_fire_table.json")
	for table in [gf, bgn, results, mods, crew_loss, drifting, unfouling, crew_quality,
			critical_hits, poor_maneuvering, crew_tasks, fire, boarding, grappling, marine_fire]:
		if table == null:
			return false

	_gunnery_factor = gf
	_bgn_rows = bgn["rows"]
	_modifiers = mods
	_crew_loss = crew_loss
	_drifting = drifting
	_unfouling = unfouling
	_crew_quality = crew_quality
	_critical_hits = _whole_numbers_to_int(critical_hits)
	_poor_maneuvering = _whole_numbers_to_int(poor_maneuvering)
	_crew_tasks = _whole_numbers_to_int(crew_tasks)
	_fire = _whole_numbers_to_int(fire)
	_boarding = _whole_numbers_to_int(boarding)
	_grappling = _whole_numbers_to_int(grappling)
	_marine_fire = _whole_numbers_to_int(marine_fire)

	_results.clear()
	for row in results["rows"]:
		var parsed := {"ch": int(row["ch"])}
		for aim in ["low", "high"]:
			var columns := {}
			for column in ["fs", "ms", "ps"]:
				columns[column] = _parse_result(String(row[aim][column]))
			parsed[aim] = columns
		_results.append(parsed)
	if _results.size() != RESULT_ROWS:
		push_error("CombatTables: gunfire results has %d rows, expected %d" % [_results.size(), RESULT_ROWS])
		return false

	Trace.trace_log("CombatTables", "Loaded combat tables from %s" % dir)
	return true

func gunnery_multiplier(gun_type: String, range_hexes: int) -> float:
	if range_hexes < 1 or range_hexes > MAX_RANGE:
		return 0.0
	if not _gunnery_factor.has(gun_type):
		push_error("CombatTables: unknown gun type '%s'" % gun_type)
		return 0.0
	return float(_gunnery_factor[gun_type][range_hexes - 1])

## Returns -1 when the ship cannot fire (grey box, out of range, or TGF < 1).
func basic_gunfire_number(tgf: int, range_hexes: int, french: bool) -> int:
	if range_hexes < 1 or range_hexes > MAX_RANGE:
		return -1
	for row in _bgn_rows:
		if tgf >= int(row["tgf_min"]) and tgf <= int(row["tgf_max"]):
			var value = row["bgn"][range_hexes - 1]
			if french and range_hexes >= FRENCH_FIRST_RANGE:
				value = row["french"][range_hexes - FRENCH_FIRST_RANGE]
			return -1 if value == null else int(value)
	return -1

## Returns an Array of tokens; each token is an Array of alternatives;
## an alternative is {} (nothing) or {"type": "r"|"h"|"c", "count": int}.
## column is the chart column as printed: "fs", "ms" (+MS increment), "ps" (+PS increment).
func gunfire_result(fgn: int, aim: String, column: String) -> Array:
	if fgn < 1:
		return []
	var row: Dictionary = _results[mini(fgn, RESULT_ROWS) - 1]
	if not row.has(aim) or not row[aim].has(column):
		push_error("CombatTables: unknown gunfire result aim/column '%s'/'%s'" % [aim, column])
		return []
	return row[aim][column].duplicate(true)

func critical_hit_number(fgn: int) -> int:
	if fgn < 1:
		return 0
	return _results[mini(fgn, RESULT_ROWS) - 1]["ch"]

func crew_quality_modifier(crew_quality: String) -> int:
	return int(_lookup(_modifiers["crew_quality"], crew_quality, "crew quality"))

func sections_firing_modifier(sections: int) -> int:
	return int(_lookup(_modifiers["sections_firing"], str(sections), "sections firing"))

## kind is "rake" or "initial_broadside"; 0 beyond range 5.
func range_bonus(kind: String, range_hexes: int) -> int:
	if kind != "rake" and kind != "initial_broadside":
		push_error("CombatTables: unknown range bonus kind '%s'" % kind)
		return 0
	var bonuses: Array = _modifiers[kind]
	if range_hexes < 1 or range_hexes > bonuses.size():
		return 0
	return int(bonuses[range_hexes - 1])

## name: "two_targets", "half_broadside", "plain_sail", "dismantling_shot", "anchored", "wind_speed_4".
func flat_modifier(name: String) -> int:
	if name in ["crew_quality", "sections_firing", "rake", "initial_broadside", "_doc"]:
		push_error("CombatTables: '%s' is not a flat modifier" % name)
		return 0
	return int(_lookup(_modifiers, name, "flat modifier"))

## cause is "gunfire_at_hull" or "other". True = a sailor box is lost, false = a marine box.
func crew_loss_is_sailor(cause: String, d6: int) -> bool:
	var entry = _lookup(_crew_loss, cause, "crew loss cause")
	if entry == null:
		return true
	return d6 <= int(entry["sailor_max"])

## sail_key: "ps", "ms", "fs", "ns" or "dismasted". Returns the minimum d10 roll
## that drifts (0 = automatic), or -1 when the ship never drifts.
func drift_number(sail_key: String, wind_speed: int) -> int:
	var by_wind = _lookup(_drifting, sail_key.to_lower(), "drift sail state")
	if by_wind == null:
		return -1
	if wind_speed < 0 or wind_speed >= by_wind.size():
		push_error("CombatTables: drift wind speed %d out of range" % wind_speed)
		return -1
	var value = by_wind[wind_speed]
	return -1 if value == null else int(value)

func drift_class_drm(ship_class: int) -> int:
	return int(_drifting["class_drm"].get(str(ship_class), 0))

## attempt 1, 2, 3+ (game-turns spent trying). Highest d10 roll that succeeds.
func unfouling_success_max(attempt: int) -> int:
	var table: Array = _unfouling["success_max"]
	return int(table[clampi(attempt, 1, table.size()) - 1])

## The Unfouling table's "Marines not avail.: +1" DRM (All Uses: unfouling, fixing, firefighting).
func marines_unavailable_modifier() -> int:
	return int(_unfouling.get("marines_unavailable", 0))

## Crew Task Order Codes (ship log), data/rules/crew_tasks.json. `code` is a row key
## (SAIL_MAJOR, SAIL_MINOR, T, RO, FF, RR, RH, RS). Deep copy; {} for an unknown code.
func crew_task(code: String) -> Dictionary:
	var row = _lookup(_crew_tasks, code, "crew task")
	return {} if row == null else (row as Dictionary).duplicate(true)

## G-t's the task needs at this crew quality; -1 for an open-ended task (T, FF).
## {ad, eg}: CQ A-D / E-G. {sk_base: n}: max(1, n + SK mod). {fixed: n}.
func task_turns(code: String, crew_quality: String) -> int:
	var row := crew_task(code)
	if row.is_empty():
		return -1
	var turns: Dictionary = row.get("turns", {})
	if turns.has("ad"):
		return int(turns["eg"]) if crew_quality in ["E", "F", "G"] else int(turns["ad"])
	if turns.has("sk_base"):
		return int(turns.get("times", 1)) * maxi(1, int(turns["sk_base"]) + skill_modifier(crew_quality))
	if turns.has("fixed"):
		return int(turns["fixed"])
	return -1

## [min, max] crew sections the task takes; [] for an unknown code.
func task_sections(code: String) -> Array:
	var row := crew_task(code)
	return row.get("sections", [])

## Fires and explosions (8.E), data/rules/fire_table.json: spread_number, growth_turns,
## explode_max, debris_radius, debris_never. 0 for an unknown name.
func fire_rule(name: String) -> int:
	var value = _lookup(_fire, name, "fire rule")
	return 0 if value == null or not (value is int or value is float) else int(value)

## 8.E.10 blast table: the MGN for a ship of `ship_class` (1-4) exploding at `range_hexes`;
## -1 beyond range 2 (no blast) or for an unknown class.
func blast_mgn(ship_class: int, range_hexes: int) -> int:
	var rows: Dictionary = _fire.get("blast_mgn", {})
	var row = rows.get(str(ship_class))
	if row == null or range_hexes < 1 or range_hexes > (row as Array).size():
		return -1
	return int(row[range_hexes - 1])

## Boarding Combat Factor of one crew box (Skill Factors, p.109): BCF S or M by crew quality.
## 0 (with an error) for an unknown crew quality.
func bcf(crew_quality: String, marine: bool) -> int:
	var entry = _lookup(_crew_quality, crew_quality, "crew quality")
	return 0 if entry == null else int(entry["bcf_marine" if marine else "bcf_sailor"])


## Boarding Combat table row (2d6, p.109) for a modified roll, clamped to <= 4 / >= 12:
## {"dr", "pct", "attacker", "defender"} (see boarding_combat_table.json for the result codes).
func boarding_row(dr: int) -> Dictionary:
	var rows: Dictionary = _boarding["rows"]
	var copy: Dictionary = (rows[str(clampi(dr, 4, 12))] as Dictionary).duplicate(true)
	copy["dr"] = clampi(dr, 4, 12)
	return copy


## BCF lost for `pct` % of the roller's TBCF, rounded to the nearest whole BCF, halves up (10.D.4,
## spec 0.4 #1). Integer arithmetic only.
static func boarding_loss_bcf(pct: int, roller_tbcf: int) -> int:
	@warning_ignore("integer_division")
	return (pct * roller_tbcf * 2 + 100) / 200


## TBCF odds DRM (10.D.2) for a side with `friendly` TBCF against `enemy`: the ratio F:E rounded
## down to the next lower listed ratio (1:4 ... 4:1; 1:1 = 0); below 1:4 is the 1:4 DRM. Compared
## as f * den >= e * num, no floats.
func odds_drm(friendly: int, enemy: int) -> int:
	var ladder: Array = _boarding["odds_drm"]
	var drm: int = int(ladder[0][2])
	for step in ladder:
		if friendly * int(step[1]) >= enemy * int(step[0]):
			drm = int(step[2])
	return drm


## The attacker's Other DRMs (p.109): the defending ship's class (1 -3, 2 -2, 3 -1, 4 none), plus
## -1 per class the defender is larger (lower class #), +1 per class it is smaller.
func boarding_class_drm(defender_class: int, attacker_class: int) -> int:
	var table: Dictionary = _boarding["class_drm"]
	var drm := int(table.get(str(defender_class), 0))
	var diff := defender_class - attacker_class
	if diff < 0:
		drm += int(table["per_class_larger"]) * -diff
	elif diff > 0:
		drm += int(table["per_class_smaller"]) * diff
	return drm


## Prize crew minimum in boxes by the prize's class (10.G.7); 0 for an unknown class.
func prize_minimum(ship_class: int) -> int:
	return int((_boarding["prize_minimum"] as Dictionary).get(str(ship_class), 0))


## Grappling (d10, p.109): the highest modified roll that succeeds.
func grapple_success_max() -> int:
	return int(_grappling["success_max"])


## A Grappling DRM: "fouled", "towing", "marines_unavailable", "ws4", "target_did_not_move".
func grapple_drm(name: String) -> int:
	var value = _lookup(_grappling["drm"], name, "grappling DRM")
	return 0 if value == null else int(value)


## An Unfouling "Ungrappling Only" DRM: "per_cq_better" (per CQ level better than the enemy),
## "friendly", "ws4".
func ungrapple_drm(name: String) -> int:
	var value = _lookup(_unfouling.get("ungrapple_drm", {}), name, "ungrappling DRM")
	return 0 if value == null else int(value)


## Marine Fire (d6, p.110): crew boxes the target loses for a modified roll `dr` (<= 1 and 6+ are
## the end rows) fired by `boxes` marine boxes (0 boxes: 0).
func marine_fire_result(dr: int, boxes: int) -> int:
	var column := marine_fire_column(boxes)
	if column < 0:
		return 0
	var row: Array = _marine_fire["rows"][str(clampi(dr, 1, 6))]
	return int(row[column])


## The Marine Fire column index (0 = 1-2 boxes ... 5 = 11+) for `boxes`; -1 for no boxes.
func marine_fire_column(boxes: int) -> int:
	if boxes < 1:
		return -1
	var columns: Array = _marine_fire["columns"]
	for i in columns.size():
		var top = columns[i][1]
		if top == null or boxes <= int(top):
			return i
	return columns.size() - 1


## The Marine Fire column heading for `boxes`: "1-2" ... "11+"; "" for no boxes.
func marine_fire_column_label(boxes: int) -> String:
	var i := marine_fire_column(boxes)
	if i < 0:
		return ""
	var column: Array = _marine_fire["columns"][i]
	return "%d+" % int(column[0]) if column[1] == null else "%d-%d" % [int(column[0]), int(column[1])]


## A Marine Fire DRM: "grappled_or_fouled", "cq_e_f", "cq_g", "target_boarders", "larger_class",
## "optional_range_2".
func marine_fire_drm(name: String) -> int:
	var value = _lookup(_marine_fire["drm"], name, "marine fire DRM")
	return 0 if value == null else int(value)


func skill_modifier(crew_quality: String) -> int:
	var entry = _lookup(_crew_quality, crew_quality, "crew quality")
	return 0 if entry == null else int(entry["sk"])

## Critical hits (Rigging p.112, Hull p.113). Each accessor returns a deep copy of
## the chart row plus "crit" (its 2d6 row number), or {} for a roll off the chart.
## check: the RC/HC column, d6 1-6. crit: the 2d6 "Crit" column, 2-12.
func rigging_check(d6: int) -> Dictionary:
	return _critical_check("rigging", d6)

func rigging_crit(roll_2d6: int) -> Dictionary:
	return _critical_row("rigging", roll_2d6)

func hull_check(d6: int) -> Dictionary:
	return _critical_check("hull", d6)

func hull_crit(roll_2d6: int) -> Dictionary:
	return _critical_row("hull", roll_2d6)

## Poor Maneuvering (6.F.3): the highest d10 roll (0-9) that succeeds before DRMs.
## -1 (with an error) for an unknown crew quality or maneuver type.
func poor_maneuvering_number(crew_quality: String, maneuverability: String) -> int:
	var row = _poor_maneuvering.get(crew_quality.to_upper())
	var type := maneuverability.to_lower()
	if crew_quality.to_upper() == "_DOC" or not row is Dictionary or not row.has(type):
		push_error("CombatTables: unknown poor maneuvering crew quality/type '%s'/'%s'" % [
			crew_quality, maneuverability])
		return -1
	return int(row[type])

func _critical_check(table: String, d6: int) -> Dictionary:
	var crit = _critical_hits[table]["check"].get(str(d6))
	if crit == null:
		push_error("CombatTables: %s critical check roll %d is off the chart" % [table, d6])
		return {}
	return _critical_row(table, int(crit))

func _critical_row(table: String, roll_2d6: int) -> Dictionary:
	var row = _critical_hits[table]["crit"].get(str(roll_2d6))
	if row == null:
		push_error("CombatTables: %s critical roll %d is off the chart" % [table, roll_2d6])
		return {}
	var copy: Dictionary = (row as Dictionary).duplicate(true)
	copy["crit"] = roll_2d6
	return copy

## JSON numbers load as floats; chart rows hold only whole numbers.
func _whole_numbers_to_int(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _whole_numbers_to_int(value[key])
		return out
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_whole_numbers_to_int(item))
		return items
	if value is float and is_equal_approx(value, roundf(value)):
		return int(value)
	return value

func _lookup(table: Dictionary, key: String, what: String) -> Variant:
	if not table.has(key):
		push_error("CombatTables: unknown %s '%s'" % [what, key])
		return null
	return table[key]

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("CombatTables: table not found: %s" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("CombatTables: failed to parse %s: %s" % [path, json.get_error_message()])
		return null
	if not json.data is Dictionary:
		push_error("CombatTables: %s must be a JSON object" % path)
		return null
	return json.data

## "r/h-c/." -> [[{r,1},{h,1}], [{c,1},{}]]; "" -> [].
func _parse_result(text: String) -> Array:
	var tokens: Array = []
	if text == "":
		return tokens
	for token_text in text.split("-"):
		var alternatives: Array = []
		for alt_text in token_text.split("/"):
			alternatives.append(_parse_alternative(alt_text, text))
		tokens.append(alternatives)
	return tokens

func _parse_alternative(alt_text: String, whole: String) -> Dictionary:
	if alt_text == ".":
		return {}
	var kind := alt_text.right(1)
	var count_text := alt_text.left(alt_text.length() - 1)
	if not kind in ["r", "h", "c"] or (count_text != "" and not count_text.is_valid_int()):
		push_error("CombatTables: bad gunfire result '%s' in '%s'" % [alt_text, whole])
		return {}
	return {"type": kind, "count": 1 if count_text == "" else count_text.to_int()}
