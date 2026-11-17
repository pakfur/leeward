class_name PlayerState
extends RefCounted
## A player: a seat on a side that commands some of its ships (players/side split).

var id: int = 0
var side: int = 0
var name: String = ""
var is_ai: bool = false


func to_dict() -> Dictionary:
	return {"id": id, "side": side, "name": name, "is_ai": is_ai}


static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.id = int(d.get("id", 0))
	p.side = int(d.get("side", p.id))
	p.name = str(d.get("name", ""))
	p.is_ai = bool(d.get("is_ai", false))
	return p
