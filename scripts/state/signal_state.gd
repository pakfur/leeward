class_name SignalState
extends RefCounted
## A flag signal (Close Action 11.A): sent in PLANNING, delivered at MESSAGE_DELIVERY, read by the
## whole side (11.A.4). Plain data; the server builds and changes it (TurnPhaseController).

var turn: int = 0
var from_player: int = -1
var from_ship: String = ""
## {"kind": "fleet"|"group"|"ship", "name": String}; for a ship, name is the ship id.
var address: Dictionary = {"kind": "fleet", "name": ""}
var words: Array[String] = []
var delivered: bool = false


func to_dict() -> Dictionary:
	return {
		"turn": turn,
		"from_player": from_player,
		"from_ship": from_ship,
		"address": address.duplicate(),
		"words": words.duplicate(),
		"delivered": delivered,
	}


static func from_dict(data: Dictionary) -> SignalState:
	var s := SignalState.new()
	s.turn = int(data.get("turn", 0))
	s.from_player = int(data.get("from_player", -1))
	s.from_ship = str(data.get("from_ship", ""))
	var a = data.get("address", {})
	s.address = {"kind": str(a.get("kind", "fleet")), "name": str(a.get("name", ""))} if a is Dictionary else {"kind": "fleet", "name": ""}
	for w in data.get("words", []):
		s.words.append(str(w))
	s.delivered = bool(data.get("delivered", false))
	return s
