class_name SignalText
extends RefCounted
## Signal and talk message rules (Close Action 11.A.6-7). Pure statics, no state.

const PREFIXES := ["HMS", "USS"]
const PUNCTUATION := ".,;:!?()\""
## Longest talk message, in words (a captain's talk is limited like a flagship's signal).
const TALK_LIMIT := 5

const _OPEN := "@n"  # lower case, so it cannot clash with the upper-cased text
const _CLOSE := "@"


## Splits a message into words: {"words": Array[String], "error": String}. A ship name, with or
## without a prefix such as HMS, is one word; each punctuation mark is one word.
static func words(text: String, ship_names: Array[String]) -> Dictionary:
	var out: Array[String] = []
	var work := text.to_upper()
	# Ship names first (longest first), so a name's own hyphens or dots stay inside it.
	var names: Array[String] = []
	for n in ship_names:
		var up := n.strip_edges().to_upper()
		if up != "":
			names.append(up)
	names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var found: Array[String] = []
	for up in names:
		var bare := _without_prefix(up)
		var re := RegEx.new()
		var pattern := "(?<![A-Z0-9])(?:(?:[A-Z]+\\.|HMS|USS)\\s+)?" + _escape(bare).replace("\\ ", "\\s+") + "(?![A-Z0-9])"
		if re.compile(pattern) != OK:
			continue
		var m := re.search(work)
		while m != null:
			var token := _OPEN + str(found.size()) + _CLOSE
			found.append(m.get_string().strip_edges())
			work = work.substr(0, m.get_start()) + " " + token + " " + work.substr(m.get_end())
			m = re.search(work)
	for ch in PUNCTUATION:
		work = work.replace(ch, " " + ch + " ")
	for part in work.split(" ", false):
		var piece := part.strip_edges()
		if piece == "":
			continue
		if piece.begins_with(_OPEN):
			out.append(found[int(piece.substr(_OPEN.length(), piece.length() - _OPEN.length() - _CLOSE.length()))])
			continue
		for sub in piece.split("\t", false):
			if sub.contains("'") or sub.contains("-"):
				return {"words": [] as Array[String], "error": "%s: contractions and hyphenated words are not allowed (11.A.7)" % sub}
			out.append(sub)
	if out.is_empty():
		return {"words": out, "error": "Empty signal"}
	return {"words": out, "error": ""}


## Most words a ship's commander may signal (11.A.6): a captain 3, a flagship 5, a British
## flagship from 1803 7. A year of 0 means no year.
static func limit(ship: ShipState, year: int) -> int:
	if not ship.is_flagship():
		return 3
	if ship.gunnery_navy() == "British" and year >= 1803:
		return 7
	return 5


static func _without_prefix(name_upper: String) -> String:
	var parts := name_upper.split(" ", false)
	if parts.size() > 1 and (parts[0].ends_with(".") or PREFIXES.has(parts[0])):
		return " ".join(parts.slice(1))
	return name_upper


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		if "\\.^$|?*+()[]{}-".contains(ch):
			out += "\\" + ch
		elif ch == " ":
			out += "\\ "
		else:
			out += ch
	return out
