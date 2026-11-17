class_name GunneryTypes
extends RefCounted
## GunneryTypes - plain data classes shared by the gunnery calculator, resolver, AI and UI.

const AIM_LOW := "low"
const AIM_HIGH := "high"
const AMMO_ROUND := "round"
const AMMO_DISMANTLING := "dismantling"
## Which batteries of the side fire (7.B.1): both at one target, or one as a half broadside.
const BATTERY_FULL := "full"
const BATTERY_BOW := "bow"
const BATTERY_STERN := "stern"
const BATTERIES: Array[String] = [BATTERY_FULL, BATTERY_BOW, BATTERY_STERN]


## One side's bow battery, stern battery or both (full broadside) fired by one ship at one target.
class FireOrder extends RefCounted:
	var ship_id: String = ""
	var side: int = 0
	var target_id: String = ""
	var aim: String = "low"      # "low" | "high"
	var ammo: String = "round"   # "round" | "dismantling"
	var battery: String = "full" # "full" | "bow" | "stern"
	## Voluntary reduction of the MGN (7.C.14), 0 or more; applied as a modifier by the calculator.
	var mgn_reduction: int = 0

	static func from_dict(d: Dictionary) -> FireOrder:
		var order := FireOrder.new()
		order.ship_id = String(d.get("ship_id", ""))
		order.side = int(d.get("side", 0))
		order.target_id = String(d.get("target_id", ""))
		order.aim = String(d.get("aim", "low"))
		order.ammo = String(d.get("ammo", "round"))
		order.battery = String(d.get("battery", BATTERY_FULL))
		order.mgn_reduction = int(d.get("mgn_reduction", 0))
		return order

	func to_dict() -> Dictionary:
		return {
			"ship_id": ship_id,
			"side": side,
			"target_id": target_id,
			"aim": aim,
			"ammo": ammo,
			"battery": battery,
			"mgn_reduction": mgn_reduction,
		}


## What a FireOrder would do, without rolling anything.
class ShotPreview extends RefCounted:
	var order: FireOrder = null
	var can_fire: bool = false
	var reason: String = ""            # set when can_fire is false
	var range_hexes: int = 0           # closest firer hex to closest target hex (7.C.4)
	var batteries: int = 0             # batteries firing: 2 full broadside, 1 half broadside
	var rake: String = ""              # "", "bow" or "stern"
	var initial_broadside: bool = false
	var high_only: bool = false
	var tgf: int = 0
	var bgn: int = 0
	var modifiers: Array[Dictionary] = []   # [{"name": String, "value": int}], zero values omitted
	var mgn: int = 0
