class_name BroadsideColors
extends RefCounted
## BroadsideColors - The one colour per broadside (port, starboard). The fire panel's swatch and
## the fire arc drawn on the map both come from here, so they cannot disagree. The arc draws an
## opaque rim in exactly this colour around a faint fill of the same hue.

const PORT := Color(0.98, 0.55, 0.1)  # orange
const STARBOARD := Color(0.25, 0.9, 0.4)  # green
const FILL_ALPHA := 0.3


## The opaque colour for a side (ShipState.PORT / ShipState.STARBOARD).
static func color(side: int) -> Color:
	return STARBOARD if side == ShipState.STARBOARD else PORT


## The translucent fill drawn inside the arc's rim.
static func fill(side: int) -> Color:
	var c := color(side)
	return Color(c.r, c.g, c.b, FILL_ALPHA)
