class_name PlayerRoster
extends VBoxContainer
## The "Players" list of the side panel: a row per player with a side colour dot (green for the
## local player's side, red otherwise), the name, an "AI" tag and the player's state at the right.
## Display only; fed by RosterRows.rows.

const STATE_COLOR := Color(0.72, 0.72, 0.72)
const READY_COLOR := Color(0.55, 0.85, 0.55)


func show_rows(rows: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var local_side := -1
	for row in rows:
		if bool(row.get("is_local", false)):
			local_side = int(row.get("side", -1))
	for row in rows:
		add_child(_make_row(row, local_side))


func _make_row(row: Dictionary, local_side: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# ShipView.owner_color: green for the player's side, red for the other.
	var mine: bool = local_side < 0 or int(row.get("side", 0)) == local_side
	dot.color = ShipView.owner_color(ShipView.HUMAN_PLAYER_ID if mine else 1)
	box.add_child(dot)
	var name_label := Label.new()
	name_label.text = String(row.get("name", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(row.get("is_local", false)):
		name_label.theme_type_variation = "StrongLabel"
	box.add_child(name_label)
	if bool(row.get("is_ai", false)):
		var tag := Label.new()
		tag.text = "AI"
		tag.theme_type_variation = "CounterLabel"
		tag.modulate = STATE_COLOR
		box.add_child(tag)
	var state := Label.new()
	var key := String(row.get("state", ""))
	state.text = RosterRows.state_label(key)
	state.modulate = READY_COLOR if key == RosterRows.READY or key == RosterRows.ENDED_TURN else STATE_COLOR
	box.add_child(state)
	return box
