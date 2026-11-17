extends GutTest
## 11.A.6-7: signal length by commander and the word-counting rules.


func _ship(flag: String, navy: String) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({"flag": flag, "nationality": navy})
	state.navy = navy
	return state


func test_plain_words_counted_and_upper_cased() -> void:
	var r := SignalText.words("set spacing between ships 2", [] as Array[String])
	assert_eq(r["error"], "")
	assert_eq(r["words"].size(), 5)
	assert_eq(r["words"][0], "SET")


func test_ship_name_is_one_word() -> void:
	var r := SignalText.words("BREAK ENEMY LINE ASTERN PRINCIPE DE ASTURIAS", ["Principe de Asturias"] as Array[String])
	assert_eq(r["error"], "")
	assert_eq(r["words"].size(), 5)


func test_prefix_optional() -> void:
	var names: Array[String] = ["HMS Lively"]
	for text in ["ENGAGE HMS LIVELY .", "ENGAGE LIVELY ."]:
		var r := SignalText.words(text, names)
		assert_eq(r["error"], "", text)
		assert_eq(r["words"].size(), 3, text)
		assert_string_contains(r["words"][1], "LIVELY", text)


func test_punctuation_counts() -> void:
	var r := SignalText.words("CLOSE TO 5 HEXES!", [] as Array[String])
	assert_eq(r["words"].size(), 5)


func test_contraction_and_hyphen_refused() -> void:
	assert_string_contains(SignalText.words("DON'T FIRE", [] as Array[String])["error"], "11.A.7")
	assert_string_contains(SignalText.words("MUSKET-SHOT", [] as Array[String])["error"], "11.A.7")


func test_hyphenated_ship_name_is_one_word() -> void:
	var r := SignalText.words("FOLLOW SAINT-GEORGES", ["Saint-Georges"] as Array[String])
	assert_eq(r["error"], "")
	assert_eq(r["words"].size(), 2)


func test_empty_signal() -> void:
	assert_eq(SignalText.words("  ", [] as Array[String])["error"], "Empty signal")


func test_limits() -> void:
	assert_eq(SignalText.limit(_ship("", "British"), 1805), 3)
	assert_eq(SignalText.limit(_ship("fleet", "French"), 1805), 5)
	assert_eq(SignalText.limit(_ship("fleet", "British"), 1802), 5)
	assert_eq(SignalText.limit(_ship("fleet", "British"), 1803), 7)
	assert_eq(SignalText.limit(_ship("fleet", "British"), 0), 5)
	assert_eq(SignalText.TALK_LIMIT, 5)
