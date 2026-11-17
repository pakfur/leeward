class_name ShipMotion
extends RefCounted
## ShipMotion - how a ship rides the shared swell (sea-state spec C). Pure statics, view only.
##
## The swell is sampled at bow, stern and either beam for heave, pitch and roll; ShipView low-passes
## each toward its target with a time constant scaled by the ship's class and the preset's
## inertia_mult, so a 74 answers about 1.45× slower than a frigate. A steady heel to leeward comes
## from the wind (SeaModel.beam_heel_deg) × the sail carried × the beam component of the wind.
## The targets and the low-passed state are the full motion (intensity 1); `rendered` scales the
## low-pass output by the current zoom intensity, so a ship is exactly level at the flat distance
## and fades smoothly while zooming. Roll follows the model's Z rotation: positive = starboard up.

## Base time constants (seconds) for a class 3 ship at inertia_mult 1.
const HEAVE_TAU := 0.5
const PITCH_TAU := 0.8
const ROLL_TAU := 1.1
const HEEL_TAU := 2.5
## Swell samples either side of the keel for the roll (world units).
const ROLL_SAMPLE_HALF := 0.45
## Pitch samples fore and aft of the centre, as a share of the hull length.
const PITCH_SAMPLE_SHARE := 0.45
## Heel by the sail carried, as a share of the beam-wind heel.
const SAIL_HEEL := {"fs": 0.6, "ms": 0.8, "ps": 1.0, "ns": 0.1}
## Slowness by ship class (1 = largest); class 3 is the reference, unlisted classes are 1.
const CLASS_INERTIA := {1: 1.9, 2: 1.45, 3: 1.0, 4: 0.75}


## Sign of the steady heel as a roll: −1 when the leeward side is starboard (starboard down),
## +1 when it is port, 0 head to wind or before it (WF=L/R). `wind_direction` is where the wind
## comes from.
static func heel_sign(facing: int, wind_direction: int) -> float:
	match FireGeometry.leeward_side(facing, wind_direction):
		ShipState.STARBOARD:
			return -1.0
		ShipState.PORT:
			return 1.0
	return 0.0


## Share of the wind on the beam for a ship at `facing` (|sin| of the wind's angle off the bow).
static func beam_component(facing: int, wind_direction: int) -> float:
	var r := posmod(facing - wind_direction, 6)
	return absf(sin(deg_to_rad(r * 60.0)))


## Low-pass time constant (seconds) for a ship of `ship_class`: `base_seconds` × the class factor
## × the preset's inertia_mult.
static func time_constant(ship_class: int, inertia_mult: float, base_seconds: float = 1.0) -> float:
	return base_seconds * float(CLASS_INERTIA.get(ship_class, 1.0)) * inertia_mult


## The steady heel (radians, as a roll) at `facing` with `sail_state` set, at full intensity.
static func steady_heel(sea: SeaModel, facing: int, sail_state: String) -> float:
	if sea == null:
		return 0.0
	var side_sign := heel_sign(facing, sea.wind_direction)
	if side_sign == 0.0:
		return 0.0
	var sail: float = SAIL_HEEL.get(sail_state.to_lower(), 0.0)
	return side_sign * deg_to_rad(sea.beam_heel_deg()) * sail * beam_component(facing, sea.wind_direction)


## Target motion for a ship centred at world XZ `centre` with model yaw `yaw` (radians), the swell
## sampled `reach` fore and aft (ShipView: PITCH_SAMPLE_SHARE × hull length): x heave (world
## units), y pitch (bow up), z roll (starboard up), w heel (radians). Full intensity (scale the
## low-passed result with `rendered`). Zero with no sea model.
static func targets(sea: SeaModel, centre: Vector2, yaw: float, reach: float, sail_state: String) -> Vector4:
	if sea == null:
		return Vector4.ZERO
	var forward := Vector2(-sin(yaw), -cos(yaw))   # the model's −Z (bow) in world XZ
	var starboard := Vector2(cos(yaw), -sin(yaw))  # the model's +X
	var h_bow := sea.swell_height_full(centre + forward * reach)
	var h_stern := sea.swell_height_full(centre - forward * reach)
	var h_stbd := sea.swell_height_full(centre + starboard * ROLL_SAMPLE_HALF)
	var h_port := sea.swell_height_full(centre - starboard * ROLL_SAMPLE_HALF)
	return Vector4(
		(h_bow + h_stern + h_stbd + h_port) * 0.25,
		atan2(h_bow - h_stern, 2.0 * reach),
		atan2(h_stbd - h_port, 2.0 * ROLL_SAMPLE_HALF),
		steady_heel(sea, facing_from_yaw(yaw), sail_state))


## The motion as drawn: the low-passed full-intensity state (heave, pitch, roll, heel) × the zoom
## intensity now. Exactly zero at intensity 0.
static func rendered(state: Vector4, intensity: float) -> Vector4:
	return state * clampf(intensity, 0.0, 1.0)


## The sail that heels a ship: the sail it can actually use (`movement_sail_state`); "" (no heel at
## all) when it is dismasted or destroyed, since NS on a ship with masts still heels a little.
static func heel_sail(ship_state: ShipState) -> String:
	if ship_state.is_destroyed() or ship_state.is_dismasted():
		return ""
	return ship_state.movement_sail_state()


## The hex facing nearest to a model yaw (radians): yaw = −(60·facing + 90)°. Follows the playback's
## turn tween, which turns the model before the state is synced.
static func facing_from_yaw(yaw: float) -> int:
	return posmod(roundi((-rad_to_deg(yaw) - 90.0) / 60.0), 6)


## One step of an exponential low-pass toward `target` with time constant `tau`.
static func low_pass(current: float, target: float, delta: float, tau: float) -> float:
	if tau <= 0.001:
		return target
	return lerpf(current, target, 1.0 - exp(-delta / tau))
