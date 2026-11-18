class_name SignalOrders
extends RefCounted
## Reads a delivered signal's words as a standing order (players-and-sides spec 7). Pure statics.
## Phrases: ENGAGE, ENGAGE/ATTACK <ship>, CLOSE TO <1-15>, FOLLOW FLAGSHIP, FOLLOW <ship>,
## FORM LINE, DISENGAGE, ANCHOR, CUT CABLES / CUT CABLE (anchoring spec §11). Other words are
## ignored (a lone CUT among them).


## ship_ids_by_word: upper-cased one-word ship name (as SignalText.words returns it, and its bare
## name) -> ship id. Returns the orders in the order they appear.
static func parse(words: Array[String], ship_ids_by_word: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while i < words.size():
		var w := words[i]
		var nxt := words[i + 1] if i + 1 < words.size() else ""
		match w:
			"ENGAGE", "ATTACK":
				if ship_ids_by_word.has(nxt):
					out.append({"order": "engage", "target": str(ship_ids_by_word[nxt])})
					i += 2
					continue
				if w == "ENGAGE":
					out.append({"order": "engage"})
			"CLOSE":
				var j := i + 1
				if j < words.size() and words[j] == "TO":
					j += 1
				if j < words.size() and words[j].is_valid_int():
					var n := int(words[j])
					if n >= 1 and n <= 15:
						out.append({"order": "close", "range": n})
						i = j + 1
						continue
			"FOLLOW":
				if nxt == "FLAGSHIP":
					out.append({"order": "follow", "leader": "FLAGSHIP"})
					i += 2
					continue
				if ship_ids_by_word.has(nxt):
					out.append({"order": "follow", "leader": str(ship_ids_by_word[nxt])})
					i += 2
					continue
			"FORM":
				if nxt == "LINE":
					out.append({"order": "line"})
					i += 2
					continue
			"DISENGAGE":
				out.append({"order": "disengage"})
			"ANCHOR":
				out.append({"order": "anchor"})
			"CUT":
				if nxt == "CABLES" or nxt == "CABLE":
					out.append({"order": "cut"})
					i += 2
					continue
		i += 1
	return out
