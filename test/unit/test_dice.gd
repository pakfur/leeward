extends GutTest
## Tests for Dice ranges and seeded determinism.

func _dice(seed_value: int = 1) -> Dice:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Dice.new(rng)

func test_d10_range_is_0_to_9() -> void:
	var dice := _dice()
	var lo := 99
	var hi := -99
	for _i in range(500):
		var v := dice.d10()
		lo = mini(lo, v)
		hi = maxi(hi, v)
	assert_eq(lo, 0)
	assert_eq(hi, 9)

func test_d6_range_is_1_to_6() -> void:
	var dice := _dice()
	var lo := 99
	var hi := -99
	for _i in range(2000):
		var v := dice.d6()
		lo = mini(lo, v)
		hi = maxi(hi, v)
	assert_eq(lo, 1)
	assert_eq(hi, 6)

func test_two_d6_range_is_2_to_12() -> void:
	var dice := _dice()
	var lo := 99
	var hi := -99
	for _i in range(2000):
		var v := dice.two_d6()
		lo = mini(lo, v)
		hi = maxi(hi, v)
	assert_eq(lo, 2)
	assert_eq(hi, 12)

func test_two_d10_range_is_0_to_18() -> void:
	var dice := _dice()
	var lo := 99
	var hi := -99
	for _i in range(2000):
		var v := dice.two_d10()
		lo = mini(lo, v)
		hi = maxi(hi, v)
	assert_eq(lo, 0)
	assert_eq(hi, 18)

func test_same_seed_same_sequence() -> void:
	var a := _dice(7)
	var b := _dice(7)
	for i in range(20):
		assert_eq(a.d10(), b.d10(), "Roll %d must match" % i)
