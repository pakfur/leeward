class_name IronsRules
extends RefCounted
## IronsRules - pure statics for the exceptions to being in irons (Close Action 5.D.4), shared by
## the movement resolver and the planning note.


## True when `ship` cannot be in irons on `turn`, whatever her wind facing: anchored (5.D.4a), in
## tow (5.D.7), in the g-t after she cut her cable (5.D.4b, 13.F.3), or in the g-t after the wind
## rose from a calm (3.D.4, 5.D.4c; `environment` may be null).
static func excused(ship: ShipState, environment: EnvironmentState, turn: int) -> bool:
	if ship.is_anchored() or ship.is_towed():
		return true
	if ship.cable_cut_turn >= 0 and ship.cable_cut_turn == turn - 1:
		return true
	return environment != null and environment.calm_just_ended(turn)
