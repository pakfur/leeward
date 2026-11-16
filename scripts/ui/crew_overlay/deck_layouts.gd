class_name CrewDeckLayouts
extends RefCounted
## CrewDeckLayouts - reads data/ui/deck_layouts.json (crew-tasks spec §2.3): which decks a ship
## type draws and where each station sits. Presentation only; the rules engine never reads it.

const PATH := "res://data/ui/deck_layouts.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("CrewDeckLayouts: cannot read %s" % PATH)
			_data = {"ship_types": {}, "layouts": {}, "stations": {}}
	return _data


## {"decks": [...], "gun_decks": [...]} for a ship type id (ships.json key).
static func layout_for(ship_type: String) -> Dictionary:
	var d := data()
	var key: String = d.get("ship_types", {}).get(ship_type, d.get("default_layout", "frigate"))
	return d.get("layouts", {}).get(key, {"decks": [], "gun_decks": []})


## The deck ids a station is drawn on in this layout ([] if the station has no place).
static func station_decks(layout: Dictionary, station_id: String) -> Array:
	var st: Dictionary = data().get("stations", {}).get(station_id, {})
	var decks = st.get("decks", [])
	if decks is String and decks == "gun_decks":
		return (layout.get("gun_decks", []) as Array).duplicate()
	return (decks as Array).duplicate() if decks is Array else []


## The station's landscape rect [x, y, w, h] in deck units, or [].
static func station_rect(station_id: String) -> Array:
	return (data().get("stations", {}).get(station_id, {}).get("rect", []) as Array).duplicate()
