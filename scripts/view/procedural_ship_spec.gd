class_name ProceduralShipSpec
extends RefCounted
## ProceduralShipSpec - The shape of a placeholder ship model, worked out from its ship data
## (presentation only). ProceduralShipBuilder turns a spec into meshes.
##
## Model space: the bow points along -Z, +Y is up, the waterline is y = 0, units are hex sizes.

## Sail and mast tiers, lowest first: courses on the lower masts, topsails, topgallants.
const TIER_COURSE := 1
const TIER_TOPSAIL := 2
const TIER_TOPGALLANT := 3
const TIERS: Array[int] = [TIER_COURSE, TIER_TOPSAIL, TIER_TOPGALLANT]

## Sails set at each sail state while every mast is standing.
const SAILS_BY_STATE := {
	"PS": [TIER_COURSE, TIER_TOPSAIL, TIER_TOPGALLANT],
	"MS": [TIER_COURSE, TIER_TOPSAIL],
	"FS": [TIER_TOPSAIL],
	"NS": [],
}

## Hull length per hex of footprint, before the class scale.
const LENGTH_PER_HEX := 1.3
const CLASS_SCALE := {1: 1.0, 2: 1.0, 3: 0.92, 4: 0.8}
const MIN_PORTS := 6
const MAX_PORTS := 14
## Height of each mast tier (lower, top, topgallant) as a fraction of hull length, main mast.
const TIER_HEIGHT_FACTORS: Array[float] = [0.42, 0.32, 0.24]
## Mast heights relative to the main mast: fore, main, mizzen (or fore, main for two masts).
const MAST_SCALE_3: Array[float] = [0.95, 1.0, 0.8]
const MAST_SCALE_2: Array[float] = [0.95, 1.0]
## Mast positions along the hull as a fraction of its length (bow is negative).
const MAST_Z_3: Array[float] = [-0.3, -0.02, 0.28]
const MAST_Z_2: Array[float] = [-0.2, 0.12]

var masts: int = 3
var gun_decks: int = 1
var ports_per_side: int = MAX_PORTS
var length: float = LENGTH_PER_HEX
var beam: float = 0.34
## Freeboard: hull height above the waterline.
var hull_height: float = 0.3
## Hull depth below the waterline.
var draft: float = 0.15
## Z position of each mast, fore first.
var mast_z: Array[float] = []
## Height of each tier of each mast: mast_tier_heights[mast][tier - 1].
var mast_tier_heights: Array = []


## Shape for a ship occupying `hexes` hexes. A null ship gives a frigate.
static func for_ship(ship: Ship, hexes: int) -> ProceduralShipSpec:
	var spec := ProceduralShipSpec.new()
	var rating: int = ship.rating if ship else 38
	var ship_class: int = ship.ship_class if ship else 3

	if rating >= 90:
		spec.gun_decks = 3
	elif rating >= 60:
		spec.gun_decks = 2
	else:
		spec.gun_decks = 1
	spec.masts = 2 if rating < 20 else 3
	spec.ports_per_side = clampi(ceili(rating / (2.0 * spec.gun_decks)), MIN_PORTS, MAX_PORTS)

	spec.length = LENGTH_PER_HEX * hexes * float(CLASS_SCALE.get(ship_class, 1.0))
	spec.beam = spec.length * (0.30 if spec.gun_decks >= 2 else 0.26)
	spec.hull_height = spec.length * (0.12 + 0.07 * spec.gun_decks)
	spec.draft = spec.length * 0.11

	var positions: Array[float] = MAST_Z_3 if spec.masts == 3 else MAST_Z_2
	var scales: Array[float] = MAST_SCALE_3 if spec.masts == 3 else MAST_SCALE_2
	for i in range(spec.masts):
		spec.mast_z.append(positions[i] * spec.length)
		var heights: Array[float] = []
		for factor in TIER_HEIGHT_FACTORS:
			heights.append(factor * spec.length * scales[i])
		spec.mast_tier_heights.append(heights)
	return spec


## How many mast tiers still stand at a rigging level (0-4): topgallants go first, then
## topmasts; a dismasted ship (level 0) keeps only stumps.
static func mast_tiers(rigging_level: int) -> int:
	if rigging_level >= 4:
		return 3
	if rigging_level >= 2:
		return 2
	if rigging_level >= 1:
		return 1
	return 0


## Sail tiers set for a sail state at a rigging level. Sails need their mast; at fighting sail
## with only the lower masts standing, the courses are set instead of the topsails.
static func sail_tiers(sail_state: String, rigging_level: int) -> Array[int]:
	var standing := mast_tiers(rigging_level)
	var wanted: Array = SAILS_BY_STATE.get(sail_state.to_upper(), [])
	var tiers: Array[int] = []
	for tier in wanted:
		if tier <= standing:
			tiers.append(tier)
	if tiers.is_empty() and not wanted.is_empty() and standing >= TIER_COURSE:
		tiers.append(TIER_COURSE)
	return tiers


## Index of the main (tallest) mast.
func main_mast() -> int:
	return 1


## Height of the main masthead above the waterline, with every mast standing.
func masthead_y() -> float:
	var total := hull_height
	for h in mast_tier_heights[main_mast()]:
		total += h
	return total


## Top of the main mast that is still standing at a rigging level: the masthead with every
## mast up, lower down as tiers go, and the stump top when dismasted.
func standing_masthead_y(rigging_level: int) -> float:
	var standing := mast_tiers(rigging_level)
	if standing == 0:
		return hull_height + stump_height(main_mast())
	return tier_base_y(main_mast(), standing + 1)


## Height of the stump left when a mast is shot away.
func stump_height(mast: int) -> float:
	return mast_tier_heights[mast][0] * 0.25


## Bottom of a mast tier above the waterline (tier 1 starts at the deck).
func tier_base_y(mast: int, tier: int) -> float:
	var y := hull_height
	for i in range(tier - 1):
		y += mast_tier_heights[mast][i]
	return y
