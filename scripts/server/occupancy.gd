class_name Occupancy
extends RefCounted
## Occupancy - hex -> ship_id maps for two-hex ships (bow + stern). Static, stateless.


## Map every occupied hex (bow and stern) to its ship id. Struck ships are included.
static func build(ships: Array[ShipState], exclude_ids: Array = []) -> Dictionary:
	var result := {}
	for s in ships:
		if s.ship_id in exclude_ids:
			continue
		for h in s.occupied_hexes():
			result[h] = s.ship_id
	return result


## Like build(), but from {ship_id: bow} and {ship_id: facing} dictionaries.
static func from_positions(bows: Dictionary, facings: Dictionary, exclude_ids: Array = []) -> Dictionary:
	var result := {}
	for id in bows:
		if id in exclude_ids:
			continue
		var bow: Vector2i = bows[id]
		result[bow] = id
		result[HexGrid.stern_of(bow, int(facings[id]))] = id
	return result


## Ids of ships whose footprints share at least one hex with another ship.
static func overlapping_ids(ships: Array[ShipState]) -> Array[String]:
	var owner := {}
	var ids: Array[String] = []
	for s in ships:
		for h in s.occupied_hexes():
			if owner.has(h) and owner[h] != s.ship_id:
				for id in [owner[h], s.ship_id]:
					if not ids.has(id):
						ids.append(id)
			else:
				owner[h] = s.ship_id
	return ids
