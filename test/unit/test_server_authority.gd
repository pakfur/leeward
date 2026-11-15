extends GutTest
## Server authority over game state (CLAUDE.md "Server Authority"): view-side code
## (scripts/ui, scripts/view, scripts/core) reads state and sends requests that the server
## validates (player_submit_*, player_clear_movement, plot_sail_change(player_id, ...),
## dev_commands.*). It never calls a state mutator or writes a ShipState field itself.
## This test scans the source so a violation fails `make test`.

const VIEW_DIRS := ["res://scripts/ui", "res://scripts/view", "res://scripts/core"]

## [regex, what it catches]
const FORBIDDEN := [
	# read-only queries (get_/is_/can_/has_) are allowed
	["\\bship_controller\\.(?!get_|is_|can_|has_)", "a ShipStateController mutator called from view code"],
	["\\bShipStateController\\b", "ShipStateController used from view code"],
	["\\benvironment_controller\\.set_", "an EnvironmentController mutator called from view code"],
	["\\bphase_controller\\.advance_phase\\(", "phase advanced from view code (use dev_commands)"],
	["\\b(ship|ship_state|ss|state)\\.(hex_position|facing|speed|sail_state|status|crew_count|marine_count|rigging_current_hp|hull_current_hp|crew_quality|plotted_actions|fouled_with|critical_effects|crew_tasks|crew_plots)\\s*(=|\\+=|-=)[^=]",
			"a ShipState field written from view code"],
]


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(d)))
	return out


func test_view_code_never_mutates_game_state() -> void:
	var violations: Array[String] = []
	var checks: Array = []
	for f in FORBIDDEN:
		var re := RegEx.new()
		assert_eq(re.compile(f[0]), OK, "pattern compiles: %s" % f[0])
		checks.append([re, f[1]])
	var scanned := 0
	for dir_path in VIEW_DIRS:
		for path in _gd_files(dir_path):
			scanned += 1
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var line: String = lines[i]
				if line.strip_edges().begins_with("#"):
					continue
				for c in checks:
					if c[0].search(line) != null:
						violations.append("%s:%d %s: %s" % [path, i + 1, c[1], line.strip_edges()])
	assert_gt(scanned, 10, "view code was scanned")
	assert_eq(violations.size(), 0, "view code must not mutate game state:\n" + "\n".join(violations))


func test_dev_commands_refuse_unknown_property() -> void:
	var dc := DevCommands.new(GameState)
	if GameState.ships.is_empty():
		assert_ne(dc.set_ship_property("nope", "facing", 1), "", "an unknown ship is refused")
		return
	var sid: String = GameState.ships.keys()[0]
	assert_ne(dc.set_ship_property(sid, "hull_current_hp", 0), "", "an unlisted property is refused")
