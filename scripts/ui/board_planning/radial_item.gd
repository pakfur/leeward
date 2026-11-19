class_name RadialItem
extends RefCounted
## One button of a RadialMenu (board planning, view only). `off_reason` greys the item out and is
## shown under the ring when it is hovered; choosing a greyed item does nothing. `on` marks a
## toggled state (drawn with a green rim).

var id: String = ""
var label: String = ""
var icon: Texture2D = null
var hint: String = ""
## "" = enabled; otherwise why the item cannot be chosen now (the server's reason, never re-encoded).
var off_reason: String = ""
var on: bool = false


static func make(item_id: String, item_label: String, item_icon: Texture2D, item_hint := "",
		item_off_reason := "", item_on := false) -> RadialItem:
	var item := RadialItem.new()
	item.id = item_id
	item.label = item_label
	item.icon = item_icon
	item.hint = item_hint
	item.off_reason = item_off_reason
	item.on = item_on
	return item


func is_enabled() -> bool:
	return off_reason == ""
