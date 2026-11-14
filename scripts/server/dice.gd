class_name Dice
extends RefCounted
## Dice - All game die rolls, drawn from a shared seeded RNG.
## d10 is 0-9 (as on the 1997 charts), so 2d10 is 0-18.

var _rng: RandomNumberGenerator

func _init(p_rng: RandomNumberGenerator) -> void:
	_rng = p_rng

func d6() -> int:
	return _rng.randi_range(1, 6)

func d10() -> int:
	return _rng.randi_range(0, 9)

func two_d6() -> int:
	return d6() + d6()

func two_d10() -> int:
	return d10() + d10()
