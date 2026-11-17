class_name SeaModel
extends Node
## SeaModel - the one sea shared by the water shader and the ship motion (sea-state spec B).
##
## Presentation only: it is fed the environment (`set_environment`, from OceanView) and never
## writes game state. It owns the sea clock (`sea_time`), the long swell (three Gerstner components
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
## Gerstner crest sharpening (horizontal displacement share).
const SWELL_Q := 0.8
## Gravity at map scale (1 world unit ~ 26 m): deep-water phase speed c = sqrt(g / k).
const G_MAP := 9.81 / 26.0
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
var glide_seconds: float = 0.8      ## movement playback, seconds per segment
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
var intensity: float = 0.0          ## 0..1, from the camera distance
var camera_distance: float = 0.0
var wind_direction: int = 0         ## where the wind comes from (hex direction)
var wind_speed: int = 2
var game_sea_state: int = 1
## The ocean ShaderMaterial the model drives (set by GameController); null = no shader to feed.
var material: ShaderMaterial = null

var _swell: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]  # dir.x, dir.y, full amp, wavelength
var _phase: Vector3 = Vector3.ZERO
var _preset_sea: int = -1  # the sea state whose preset was last loaded


func _init() -> void:
	_apply_globals()
	apply_preset_if_changed()
	recompute()


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	sea_time += delta
	var cam := get_viewport().get_camera_3d()
	if cam != null and "camera_distance" in cam:
		camera_distance = cam.camera_distance
	intensity = intensity_for(camera_distance, flat_distance, full_distance)
	apply_preset_if_changed()
	recompute()
	_push_to_shader()


## The game's wind and sea, as OceanView reads them from the environment.
func set_environment(p_wind_direction: int, p_wind_speed: int, p_sea_state: int) -> void:
	wind_direction = p_wind_direction
	wind_speed = p_wind_speed
	game_sea_state = p_sea_state
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
	var shift := Vector2.ZERO
	for i in range(_swell.size()):
		shift += _component_shift(i, p)
	var q := p - shift * intensity
	var h := 0.0
	for i in range(_swell.size()):
		h += _component_height(i, q)
	return h * intensity


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


## Swell components from the sea state, the preset and the wind, and their phases at sea_time.
func recompute() -> void:
	var amp: float = SWELL_AMP_BY_SEA[effective_sea_state()] * swell_height_mult
	var dw := downwind()
	for i in range(COMPONENTS.size()):
		var c: Array = COMPONENTS[i]
		var dir := dw.rotated(deg_to_rad(c[0]))
		var length: float = maxf(swell_wavelength * c[2], 0.1)
		_swell[i] = Vector4(dir.x, dir.y, amp * c[1], length)
		var k := TAU / length
		var speed := sqrt(G_MAP / k) * swell_speed
		_phase[i] = k * speed * sea_time + c[3]


## Feed the ocean shader. The current shader still draws its own waves (wave_1..wave_8 on TIME),
## sized here from the wind and the effective sea state; the swell uniforms come with the shader
## that draws the swell.
func _push_to_shader() -> void:
	if material == null:
		return
	var sea := effective_sea_state()
	var wind_vec := downwind()
	var base_amplitude := 0.05 + wind_speed * 0.03 + sea * 0.05
	var base_frequency := 1.0 - sea * 0.15
	var dir_3 := wind_vec.rotated(deg_to_rad(30.0))
	var dir_5 := wind_vec.rotated(deg_to_rad(-45.0))
	material.set_shader_parameter("wave_1", Vector4(wind_vec.x * 2.0, wind_vec.y * 2.0, base_amplitude * 0.2, base_frequency * 0.8))
	material.set_shader_parameter("wave_3", Vector4(dir_3.x * 1.5, dir_3.y * 1.5, base_amplitude * 0.15, base_frequency * 0.6))
	material.set_shader_parameter("wave_5", Vector4(dir_5.x * 1.2, dir_5.y * 1.2, base_amplitude * 0.1, base_frequency * 1.2))
	material.set_shader_parameter("wave_7", Vector4(wind_vec.x, wind_vec.y, base_amplitude * 0.18, base_frequency * 1.5))
	material.set_shader_parameter("wave_2", Vector4(-0.3, -0.2, base_amplitude * 0.02, 0.5))
	material.set_shader_parameter("wave_4", Vector4(0.2, -0.4, base_amplitude * 0.08, 0.4))
	material.set_shader_parameter("wave_6", Vector4(0.8, 0.3, base_amplitude * 0.03, 0.4))
	material.set_shader_parameter("wave_8", Vector4(-0.3, 0.5, base_amplitude * 0.12, 0.6))
	material.set_shader_parameter("time_factor", clampf(3.5 - wind_speed * 0.25 - sea * 0.15, 1.5, 3.5))
	material.set_shader_parameter("noise_amp", 0.05 + sea * 0.03)


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
