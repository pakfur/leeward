class_name OptionalRules
extends RefCounted
## The scenario's optional-rules switches (Close Action 14.B voluntary surrender, 14.D fatigue,
## 14.E gunfire limits; the sub-project 7 register, section 6). They live in the scenario's
## `optional_rules` block, every one off when absent: `voluntary_surrender` and `fatigue` are
## bools, `gunfire_limits` is one of GUNFIRE_LIMIT_VALUES. Pure statics; a bad value reads as off.
## `GameState.start_scenario` lays a lobby's override over the block (`merged`) after checking
## it with `errors`.

const KEY := "optional_rules"
const GUNFIRE_LIMIT_VALUES: Array[String] = ["none", "crew", "heel", "both"]
const SWITCHES: Array[String] = ["voluntary_surrender", "fatigue"]


## All three settings, defaults for what is missing or bad.
static func of(scenario: Dictionary) -> Dictionary:
	var block: Variant = scenario.get(KEY, {})
	if not block is Dictionary:
		block = {}
	var out := {"voluntary_surrender": false, "fatigue": false, "gunfire_limits": "none"}
	for name in SWITCHES:
		if block.get(name, false) is bool:
			out[name] = block.get(name, false)
	var limits: Variant = block.get("gunfire_limits", "none")
	if limits is String and GUNFIRE_LIMIT_VALUES.has(limits):
		out["gunfire_limits"] = limits
	return out


static func voluntary_surrender(scenario: Dictionary) -> bool:
	return of(scenario)["voluntary_surrender"]


static func fatigue(scenario: Dictionary) -> bool:
	return of(scenario)["fatigue"]


## The crew-quality gunfire limit (14.E) is on.
static func crew_limit(scenario: Dictionary) -> bool:
	var limits: String = of(scenario)["gunfire_limits"]
	return limits == "crew" or limits == "both"


## The heel gunfire limit (14.E) is on.
static func heel_limit(scenario: Dictionary) -> bool:
	var limits: String = of(scenario)["gunfire_limits"]
	return limits == "heel" or limits == "both"


## A copy of `base` with each key of `override` laid over it.
static func merged(base: Dictionary, override: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in override:
		out[key] = override[key]
	return out


## One message per problem in the scenario's block; empty when there is no block or it is sound.
static func errors(scenario: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not scenario.has(KEY):
		return out
	var block: Variant = scenario[KEY]
	if not block is Dictionary:
		out.append("optional_rules must be an object")
		return out
	for key in block:
		if SWITCHES.has(key):
			if not block[key] is bool:
				out.append("optional_rules.%s must be true or false" % key)
		elif key == "gunfire_limits":
			if not (block[key] is String and GUNFIRE_LIMIT_VALUES.has(block[key])):
				out.append("optional_rules.gunfire_limits must be none, crew, heel or both")
		else:
			out.append("unknown optional rule '%s'" % key)
	return out
