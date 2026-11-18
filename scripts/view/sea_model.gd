class_name SeaModel
extends Node
## SeaModel - the one sea shared by the water shader and the ship motion (sea-state spec B).
##
## Presentation only: it is fed the environment (`set_environment`, from OceanView) and never
## writes game state. It owns the sea clock (`sea_time`; the swell phases and the chop clock are
## accumulated per frame, so a speed, wavelength or wind change never jumps them), the long swell (three Gerstner components
## running downwind, sized by sea state), the zoom intensity (0 = flat board, 1 = full swell) from
## the camera distance, and the look values: one preset per sea state from
## `data/ui/sea_presets.json`, loaded whenever the effective sea state changes, plus the globals.
## The developer override (`sea_state_override`) changes the look only, never EnvironmentState.

const PRESETS_PATH := "res://data/ui/sea_presets.json"
## Swell amplitude (world units, all components together) by sea state 0-5.
const SWELL_AMP_BY_SEA := [0.03, 0.06, 0.1, 0.15, 0.22, 0.3]
## Whitecap scale by sea state 0-5, inside the preset's strength.
const WHITECAP_BY_SEA := [1.0, 0.8, 1.0, 1.25, 1.0, 1.6]
## Steady heel in degrees at a beam wind, by wind speed 0-5 (heel to leeward).
const HEEL_BY_WIND := [0.0, 1.5, 3.0, 5.0, 7.0, 9.0]
## Swell components: [angle off downwind (deg), share of amplitude, wavelength factor, phase offset].
const COMPONENTS := [
	[0.0, 0.6, 1.0, 0.0],
	[22.0, 0.3, 0.73, 1.7],
	[-31.0, 0.25, 1.37, 4.1],
]
## Sea state the base chop is always sized for. The presets were tuned with the base chop read
## at the game's sea state, which was 1 in every scenario used, while the override changed the
## preset; so each preset's chop_strength already carries the difference between sea states, and
## the base chop follows the wind speed only.
const CHOP_BASE_SEA := 1
## Gerstner crest sharpening (horizontal displacement share).
const SWELL_Q := 0.8
## Gravity at map scale (1 world unit ~ 26 m): deep-water phase speed c = sqrt(g / k).
const G_MAP := 9.81 / 26.0
## Process before every ShipView (default priority 0): the ships sample the sea after it moves.
const PROCESS_PRIORITY := -10
## Seconds the swell takes to swing round to a new downwind after the wind direction changes.
const DIR_BLEND_SECONDS := 3.0
## The preset fields, in the order of the preset table.
const PRESET_FIELDS := [
	"swell_height_mult", "swell_wavelength", "swell_speed", "swell_shading", "chop_strength",
	"inertia_mult", "heel_mult", "glide_seconds", "whitecap_threshold", "whitecap_strength",
]
const GLOBAL_FIELDS := ["flat_distance", "full_distance", "grid_fade_start", "grid_fade_end", "whitecap_min_sea"]
## World XZ unit vectors of the hex directions (0 = E, clockwise; +Z is south).
const HEX_DIRECTIONS := {
	0: Vector2(1.0, 0.0), 1: Vector2(0.5, 0.866), 2: Vector2(-0.5, 0.866),
	3: Vector2(-1.0, 0.0), 4: Vector2(-0.5, -0.866), 5: Vector2(0.5, -0.866),
}

## Emitted after a sea state's preset has been loaded into the tunable fields.
signal preset_loaded()

static var instance: SeaModel = null
static var _data: Dictionary = {}

# ---- tunables: a preset per sea state (sea_presets.json "presets") ----
var sea_state_override: int = -1    ## -1 = the game's sea state; 0-5 = the look of that sea state
var swell_height_mult: float = 1.0
var swell_wavelength: float = 8.75  ## world units (1 hex = 1.0)
var swell_speed: float = 1.0        ## multiplier on the deep-water phase speed
var swell_shading: float = 0.4      ## normal tilt from the swell when zoomed out (the board stays flat)
var chop_strength: float = 1.0      ## short waves and normal maps
var inertia_mult: float = 1.0       ## ship motion low-pass time constants
var heel_mult: float = 1.0
var glide_seconds: float = 0.8      ## movement playback, seconds per clock unit (one MP of the longest plot)
var whitecap_threshold: float = 0.8 ## crest height (fraction of the swell) where foam starts
var whitecap_strength: float = 1.0  ## × WHITECAP_BY_SEA × zoom
# ---- tunables: globals (sea_presets.json "globals") ----
var flat_distance: float = 20.5     ## camera distance at and beyond which the sea is a flat board
var full_distance: float = 7.5      ## camera distance at and within which the swell is full
var grid_fade_start: float = 0.5    ## intensity where the plain hex grid starts to fade
var grid_fade_end: float = 1.0      ## intensity where it is gone (HexOverlay layers never fade)
var whitecap_min_sea: int = 1       ## no whitecaps below this sea state

# ---- derived ----
var sea_time: float = 0.0
var chop_time: float = 0.0          ## the chop's clock: ∫ dt / chop_time_scale (the shader's chop time)
var intensity: float = 0.0          ## 0..1, from the camera distance
var camera_distance: float = 0.0  ## starts at flat_distance: no camera yet means a flat sea
var wind_direction: int = 0         ## where the wind comes from (hex direction)
var wind_speed: int = 2
var game_sea_state: int = 1
## The ocean ShaderMaterial the model drives (set by GameController); null = no shader to feed.
var material: ShaderMaterial = null

var _swell: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]  # dir.x, dir.y, full amp, wavelength
var _phase: Vector3 = Vector3.ZERO      # what the shader gets: accumulated phase + offset
var _phase_acc: Vector3 = Vector3.ZERO  # ∫ k·c dt per component, kept in [0, TAU)
var _dir_angle: float = 0.0  # the swell's downwind angle now (blends toward the wind's)
var _dir_from: float = 0.0
var _dir_to: float = 0.0
var _dir_t: float = 1.0      # 0..1 through the blend; 1 = settled
var _dir_set: bool = false   # false until the first environment: that one snaps
var _preset_sea: int = -1  # the sea state whose preset was last loaded
var _pushed_uniforms: Dictionary = {}  # shader_uniforms() as last sent to the material


func _init() -> void:
	# Run before the ship views (priority 0) so they ride this frame's water, not last frame's.
	process_priority = PROCESS_PRIORITY
	_apply_globals()
	camera_distance = flat_distance
	apply_preset_if_changed()
	_snap_direction()
	recompute()


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and "camera_distance" in cam:
		camera_distance = cam.camera_distance
	intensity = intensity_for(camera_distance, flat_distance, full_distance)
	apply_preset_if_changed()
	advance(delta)
	_push_to_shader()


## Move the sea on by `delta` seconds: the clock, the chop clock, each swell component's phase at
## its present speed (so changing the speed or wavelength changes the rate, not the phase) and the
## swell direction's blend toward the wind; then recompute.
func advance(delta: float) -> void:
	sea_time += delta
	chop_time += delta / chop_time_scale()
	if _dir_t < 1.0:
		_dir_t = minf(1.0, _dir_t + delta / DIR_BLEND_SECONDS)
		_dir_angle = _dir_from + angle_difference(_dir_from, _dir_to) * smoothstep(0.0, 1.0, _dir_t)
	for i in range(_swell.size()):
		_phase_acc[i] = fposmod(_phase_acc[i] + phase_speed(i) * delta, TAU)
	recompute()


## Phase speed k·c (radians per second) of swell component `i` at the present wavelength and speed.
func phase_speed(i: int) -> float:
	var length: float = maxf(swell_wavelength * COMPONENTS[i][2], 0.1)
	var k := TAU / length
	return k * sqrt(G_MAP / k) * swell_speed


## World XZ direction the swell runs now: downwind, or on its way there after a wind shift.
func swell_direction() -> Vector2:
	return Vector2.from_angle(_dir_angle)


## The chop clock's divisor: shorter, faster chop in a stronger wind (CHOP_BASE_SEA).
func chop_time_scale() -> float:
	return clampf(3.5 - wind_speed * 0.25 - CHOP_BASE_SEA * 0.15, 1.5, 3.5)


## The game's wind and sea, as OceanView reads them from the environment.
func set_environment(p_wind_direction: int, p_wind_speed: int, p_sea_state: int) -> void:
	wind_direction = p_wind_direction
	wind_speed = p_wind_speed
	game_sea_state = p_sea_state
	var target := downwind().angle()
	if not _dir_set:
		_dir_set = true
		_snap_direction()
	elif not is_equal_approx(angle_difference(_dir_to, target), 0.0):
		_dir_from = _dir_angle
		_dir_to = target
		_dir_t = 0.0
	apply_preset_if_changed()
	recompute()


## The sea state the look follows: the developer override if set, else the game's (0-5).
func effective_sea_state() -> int:
	var sea := sea_state_override if sea_state_override >= 0 else game_sea_state
	return clampi(sea, 0, EnvironmentState.SEA_STATE_MAX)


## 0 at distance ≥ flat_distance, 1 at ≤ full_distance, smoothstep between.
static func intensity_for(distance: float, p_flat_distance: float, p_full_distance: float) -> float:
	var span := p_flat_distance - p_full_distance
	if absf(span) < 0.001:
		return 1.0 if distance <= p_full_distance else 0.0
	var t := clampf((p_flat_distance - distance) / span, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The plain hex grid: 1 up to intensity grid_fade_start, 0 at grid_fade_end, linear between.
func grid_opacity() -> float:
	if grid_fade_end <= grid_fade_start:
		return 1.0 if intensity < grid_fade_start else 0.0
	return 1.0 - clampf((intensity - grid_fade_start) / (grid_fade_end - grid_fade_start), 0.0, 1.0)


## World XZ vector the wind blows toward (wind_direction is where it comes from).
func downwind() -> Vector2:
	return -HEX_DIRECTIONS.get(wind_direction, Vector2(1.0, 0.0))


## Steady heel (degrees, before intensity) at a beam wind for this wind speed.
func beam_heel_deg() -> float:
	return HEEL_BY_WIND[clampi(wind_speed, 0, HEEL_BY_WIND.size() - 1)] * heel_mult


## Swell height (× intensity) of the surface at world XZ `p`, as the shader draws it: one
## fixed-point step undoes the Gerstner horizontal shift.
func swell_height(p: Vector2) -> float:
	return swell_height_scaled(p, intensity)


## Swell height of the full swell (intensity 1) at world XZ `p`: what a ship rides before its
## motion is scaled by the zoom (ShipMotion.rendered).
func swell_height_full(p: Vector2) -> float:
	return swell_height_scaled(p, 1.0)


## Swell height at world XZ `p` with the swell scaled by `k` (shift and height).
func swell_height_scaled(p: Vector2, k: float) -> float:
	var shift := Vector2.ZERO
	for i in range(_swell.size()):
		shift += _component_shift(i, p)
	var q := p - shift * k
	var h := 0.0
	for i in range(_swell.size()):
		h += _component_height(i, q)
	return h * k


## Gerstner displacement (× intensity) of the surface point at rest at world XZ `p`:
## x/z the horizontal shift, y the height.
func swell_displacement(p: Vector2) -> Vector3:
	var shift := Vector2.ZERO
	var h := 0.0
	for i in range(_swell.size()):
		shift += _component_shift(i, p)
		h += _component_height(i, p)
	return Vector3(shift.x, h, shift.y) * intensity


## The preset for sea state `sea` (clamped 0-5), from sea_presets.json.
func preset(sea: int) -> Dictionary:
	var presets: Dictionary = _presets_data().get("presets", {})
	var key := str(clampi(sea, 0, EnvironmentState.SEA_STATE_MAX))
	if not presets.has(key):
		push_error("SeaModel: no preset for sea state %s in %s" % [key, PRESETS_PATH])
		return {}
	return (presets[key] as Dictionary).duplicate()


## Every tunable, the override and the effective sea state.
func settings() -> Dictionary:
	var out := {"sea_state_override": sea_state_override}
	for key: String in PRESET_FIELDS + GLOBAL_FIELDS:
		out[key] = get(key)
	out["effective_sea_state"] = effective_sea_state()
	return out


## Log the live values in the sea_presets.json format (the effective sea state's preset line and
## the globals), ready to paste back into the file.
func print_values() -> void:
	var entry := {}
	for key: String in PRESET_FIELDS:
		entry[key] = get(key)
	var globals := {}
	for key: String in GLOBAL_FIELDS:
		globals[key] = get(key)
	Trace.trace_log("Sea", "\"%d\": %s" % [effective_sea_state(), JSON.stringify(entry, "", false)], settings())
	Trace.trace_log("Sea", "\"globals\": %s" % JSON.stringify(globals, "", false))


## Load the effective sea state's preset when it changes (the game's weather or the override);
## live edits to the fields hold until the next change.
func apply_preset_if_changed() -> void:
	var sea := effective_sea_state()
	if sea == _preset_sea:
		return
	var values := preset(sea)
	if values.is_empty():
		return
	_preset_sea = sea
	for key: String in PRESET_FIELDS:
		if values.has(key):
			set(key, float(values[key]))
	preset_loaded.emit()


## Swell components from the sea state, the preset and the (blended) swell direction, and their
## phases: the accumulated phase plus each component's offset.
func recompute() -> void:
	var amp: float = SWELL_AMP_BY_SEA[effective_sea_state()] * swell_height_mult
	var dw := swell_direction()
	for i in range(COMPONENTS.size()):
		var c: Array = COMPONENTS[i]
		var dir := dw.rotated(deg_to_rad(c[0]))
		var length: float = maxf(swell_wavelength * c[2], 0.1)
		_swell[i] = Vector4(dir.x, dir.y, amp * c[1], length)
		_phase[i] = _phase_acc[i] + c[3]


## Point the swell straight downwind with no blend (the first environment of a game).
func _snap_direction() -> void:
	_dir_angle = downwind().angle()
	_dir_from = _dir_angle
	_dir_to = _dir_angle
	_dir_t = 1.0


## Feed the ocean shader: the clock, the swell phases, the zoom intensity and the grid opacity
## every frame; the rest (`shader_uniforms`) only when it differs from what was last sent.
func _push_to_shader() -> void:
	if material == null:
		return
	material.set_shader_parameter("sea_time", sea_time)
	material.set_shader_parameter("chop_time", chop_time)
	material.set_shader_parameter("swell_phase", _phase)
	material.set_shader_parameter("zoom_intensity", intensity)
	material.set_shader_parameter("grid_opacity", grid_opacity())
	var uniforms := shader_uniforms()
	if uniforms == _pushed_uniforms:
		return
	for key: String in uniforms:
		material.set_shader_parameter(key, uniforms[key])
	_pushed_uniforms = uniforms


## The ocean shader's uniforms that change only with the wind, the sea state or the tuning.
## Chop (surface detail, not ridden by ships) grows with the wind (CHOP_BASE_SEA); whitecaps need
## whitecap_min_sea and take WHITECAP_BY_SEA inside the preset strength.
func shader_uniforms() -> Dictionary:
	var sea := effective_sea_state()
	var amp_total := 0.0
	for s in _swell:
		amp_total += s.z
	return {
		"wind_dir": swell_direction(),
		"swell_1": _swell[0], "swell_2": _swell[1], "swell_3": _swell[2],
		"swell_q": SWELL_Q,
		"swell_amp_total": amp_total,
		"swell_shading": swell_shading,
		"chop_strength": chop_strength,
		"chop_amplitude": 0.05 + wind_speed * 0.03 + CHOP_BASE_SEA * 0.05,
		"chop_wavelength": 1.0 - CHOP_BASE_SEA * 0.15,
		"chop_noise": 0.05 + CHOP_BASE_SEA * 0.03,
		"whitecap_threshold": whitecap_threshold,
		"whitecap_strength": whitecap_strength,
		"whitecap_sea_factor": 0.0 if sea < whitecap_min_sea else float(WHITECAP_BY_SEA[sea]),
	}


func _component_shift(i: int, p: Vector2) -> Vector2:
	var s := _swell[i]
	if s.z <= 0.0:
		return Vector2.ZERO
	var d := Vector2(s.x, s.y)
	var f := TAU / s.w * d.dot(p) - _phase[i]
	return d * (SWELL_Q * s.z * cos(f))


func _component_height(i: int, p: Vector2) -> float:
	var s := _swell[i]
	if s.z <= 0.0:
		return 0.0
	return s.z * sin(TAU / s.w * Vector2(s.x, s.y).dot(p) - _phase[i])


func _apply_globals() -> void:
	var globals: Dictionary = _presets_data().get("globals", {})
	flat_distance = float(globals.get("flat_distance", flat_distance))
	full_distance = float(globals.get("full_distance", full_distance))
	grid_fade_start = float(globals.get("grid_fade_start", grid_fade_start))
	grid_fade_end = float(globals.get("grid_fade_end", grid_fade_end))
	whitecap_min_sea = int(globals.get("whitecap_min_sea", whitecap_min_sea))


static func _presets_data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PRESETS_PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("SeaModel: cannot read %s" % PRESETS_PATH)
	return _data
