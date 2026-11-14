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

func load_all(dir: String = "res://data/rules/") -> bool:
	var gf = _load_json(dir + "gunnery_factor_table.json")
	var bgn = _load_json(dir + "basic_gunfire_number_table.json")
	var results = _load_json(dir + "gunfire_results_table.json")
	var mods = _load_json(dir + "gunfire_modifiers.json")
	var crew_loss = _load_json(dir + "crew_loss_table.json")
	var drifting = _load_json(dir + "drifting_table.json")
	var unfouling = _load_json(dir + "unfouling_table.json")
	var crew_quality = _load_json(dir + "crew_quality_table.json")
	for table in [gf, bgn, results, mods, crew_loss, drifting, unfouling, crew_quality]:
		if table == null:
			return false

	_gunnery_factor = gf
	_bgn_rows = bgn["rows"]
	_modifiers = mods
	_crew_loss = crew_loss
	_drifting = drifting
	_unfouling = unfouling
	_crew_quality = crew_quality

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

## name: "two_targets", "plain_sail", "dismantling_shot", "anchored", "wind_speed_4".
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

func skill_modifier(crew_quality: String) -> int:
	var entry = _lookup(_crew_quality, crew_quality, "crew quality")
	return 0 if entry == null else int(entry["sk"])

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
