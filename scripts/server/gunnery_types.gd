class_name GunneryTypes
extends RefCounted
## GunneryTypes - plain data classes shared by the gunnery calculator, resolver, AI and UI.

const AIM_LOW := "low"
const AIM_HIGH := "high"
const AMMO_ROUND := "round"
const AMMO_DISMANTLING := "dismantling"


## One broadside fired by one ship at one target.
class FireOrder extends RefCounted:
	var ship_id: String = ""
	var side: int = 0
	var target_id: String = ""
	var aim: String = "low"      # "low" | "high"
	var ammo: String = "round"   # "round" | "dismantling"

	static func from_dict(d: Dictionary) -> FireOrder:
		var order := FireOrder.new()
		order.ship_id = String(d.get("ship_id", ""))
		order.side = int(d.get("side", 0))
		order.target_id = String(d.get("target_id", ""))
		order.aim = String(d.get("aim", "low"))
		order.ammo = String(d.get("ammo", "round"))
		return order

	func to_dict() -> Dictionary:
		return {
			"ship_id": ship_id,
			"side": side,
			"target_id": target_id,
			"aim": aim,
			"ammo": ammo,
		}


## What a FireOrder would do, without rolling anything.
class ShotPreview extends RefCounted:
	var order: FireOrder = null
	var can_fire: bool = false
	var reason: String = ""            # set when can_fire is false
	var range_hexes: int = 0
	var rake: String = ""              # "", "bow" or "stern"
	var initial_broadside: bool = false
	var high_only: bool = false
	var tgf: int = 0
	var bgn: int = 0
	var modifiers: Array[Dictionary] = []   # [{"name": String, "value": int}], zero values omitted
	var mgn: int = 0
