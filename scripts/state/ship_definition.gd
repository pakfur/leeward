class_name ShipDefinition
extends RefCounted
## ShipDefinition - Strongly-typed ship definition data from ships.json
## This class represents the static definition of a ship type (e.g., "frigate_38")

# Basic ship information
var name: String = ""
var nationality: String = ""
var rating: int = 0
var ship_class: int = 0  # "class" is a reserved keyword, using "ship_class"
var maneuverability: String = ""
var speed_type: String = ""
var type: String = ""
var speed: String = ""  # Optional: "Fast", "Slow", etc.

# Physical characteristics
var draft: int = 0
var freeboard: int = 0

# Hit points (all arrays have 4 elements for 4 ship sections)
var rigging_hp: Array[int] = [0, 0, 0, 0]
var hull_hp: Array[int] = [0, 0, 0, 0]

# Crew
var crew_count: Array[int] = [0, 0, 0, 0]
var marine_count: int = 0

# Armament - stored as Dictionary for flexibility
var guns: Dictionary = {}

static func from_dict(data: Dictionary) -> ShipDefinition:
	"""Create a ShipDefinition from a Dictionary (parsed from JSON)"""
	var def = ShipDefinition.new()

	# Basic information
	def.name = data.get("name", "Unknown Ship")
	def.nationality = data.get("nationality", "Unknown")
	def.rating = data.get("rating", 0)
	def.ship_class = data.get("class", 0)
	def.maneuverability = data.get("maneuverability", "")
	def.speed_type = data.get("speed_type", "F/F")
	def.type = data.get("type", "")
	def.speed = data.get("speed", "")

	# Physical characteristics
	def.draft = data.get("draft", 0)
	def.freeboard = data.get("freeboard", 0)

	# Hit points - convert from untyped arrays
	var rigging_data = data.get("rigging_hp", [0, 0, 0, 0])
	for i in range(min(4, rigging_data.size())):
		def.rigging_hp[i] = int(rigging_data[i])

	var hull_data = data.get("hull_hp", [0, 0, 0, 0])
	for i in range(min(4, hull_data.size())):
		def.hull_hp[i] = int(hull_data[i])

	# Crew
	var crew_data = data.get("crew_count", [0, 0, 0, 0])
	for i in range(min(4, crew_data.size())):
		def.crew_count[i] = int(crew_data[i])

	def.marine_count = data.get("marine_count", 0)

	# Guns - store as-is (complex nested structure)
	def.guns = data.get("guns", {})

	return def

func to_dict() -> Dictionary:
	"""Convert this ShipDefinition back to a Dictionary"""
	return {
		"name": name,
		"nationality": nationality,
		"rating": rating,
		"class": ship_class,
		"maneuverability": maneuverability,
		"speed_type": speed_type,
		"type": type,
		"speed": speed,
		"draft": draft,
		"freeboard": freeboard,
		"rigging_hp": rigging_hp,
		"hull_hp": hull_hp,
		"crew_count": crew_count,
		"marine_count": marine_count,
		"guns": guns
	}

func get_total_crew() -> int:
	"""Get the total crew count across all sections"""
	var total = 0
	for count in crew_count:
		total += count
	return total

func get_total_rigging_hp() -> int:
	"""Get the total rigging HP across all sections"""
	var total = 0
	for hp in rigging_hp:
		total += hp
	return total

func get_total_hull_hp() -> int:
	"""Get the total hull HP across all sections"""
	var total = 0
	for hp in hull_hp:
		total += hp
	return total

func get_gun_count() -> int:
	"""Get the total number of guns on this ship"""
	var total = 0

	for category in guns.values():
		if category is Dictionary:
			if category.has("count"):
				# Flat gun category (e.g. bow_chasers: {count: 2, size: 9})
				total += category.get("count", 0)
			else:
				# Nested gun category (e.g. long_guns: {main_deck_port: {count: 19}})
				for gun_group in category.values():
					if gun_group is Dictionary and gun_group.has("count"):
						total += gun_group.get("count", 0)

	return total
