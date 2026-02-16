extends Control
## ContextPanel - Collapsible left-side panel for context-sensitive UI
## Displays different content based on game state/context

@export var panel_width_percent: float = 0.2  # 20% of screen width
@export var collapsed_width: float = 10.0  # Width when collapsed (narrow strip)
@export var animation_duration: float = 0.3  # Seconds for expand/collapse animation

# UI elements
@onready var panel_container: PanelContainer = $PanelContainer
@onready var title_label: Label = $PanelContainer/VBox/TitleBar/TitleLabel
@onready var toggle_button: Button = $PanelContainer/VBox/TitleBar/ToggleButton
@onready var content_container: Control = $PanelContainer/VBox/ContentContainer

# State
var is_expanded: bool = true
var expanded_width: float = 0.0
var current_width: float = 0.0
var animation_progress: float = 1.0  # 0-1, 1 = animation complete

# Collapsed state UI (shown when panel is collapsed)
var collapsed_button: Button

func _ready() -> void:
	# Calculate initial sizes
	_update_panel_size()

	# Set z-index above minimap, below DevUI
	z_index = 50

	# Set up toggle button
	toggle_button.text = "<<"
	toggle_button.pressed.connect(_on_toggle_pressed)

	# Create collapsed expand button (sticks out from narrow strip)
	_create_collapsed_button()

	# Start expanded
	is_expanded = true
	current_width = expanded_width
	set_deferred("size:x", current_width)
	panel_container.set_deferred("size:x", current_width)

	print("ContextPanel initialized: expanded_width=%f, collapsed_width=%f" % [expanded_width, collapsed_width])

func _create_collapsed_button() -> void:
	"""Create the expand button shown when panel is collapsed"""
	collapsed_button = Button.new()
	collapsed_button.text = ">>"
	collapsed_button.custom_minimum_size = Vector2(40, 40)
	collapsed_button.visible = false
	collapsed_button.pressed.connect(_on_toggle_pressed)
	add_child(collapsed_button)

	# Position will be updated to match toggle button position
	collapsed_button.z_index = 1

func _update_panel_size() -> void:
	"""Update panel size based on screen dimensions"""
	var screen_size = get_viewport_rect().size
	expanded_width = screen_size.x * panel_width_percent

	# Set full height for the control
	set_deferred("size:y", screen_size.y)
	custom_minimum_size.y = screen_size.y

	# Position at left edge
	position = Vector2(0, 0)

func _process(delta: float) -> void:
	"""Animate expand/collapse transition"""
	if animation_progress < 1.0:
		animation_progress = min(1.0, animation_progress + delta / animation_duration)

		# Ease in-out interpolation
		var t = _ease_in_out(animation_progress)

		# Interpolate width
		var start_width = collapsed_width if is_expanded else expanded_width
		var end_width = expanded_width if is_expanded else collapsed_width
		current_width = lerp(start_width, end_width, t)

		# Apply width to both Control and PanelContainer
		size.x = current_width
		panel_container.size.x = current_width
		panel_container.custom_minimum_size.x = current_width

		# Update visibility of elements
		if animation_progress >= 1.0:
			_finish_animation()

func _ease_in_out(t: float) -> float:
	"""Smooth ease-in-out curve"""
	return t * t * (3.0 - 2.0 * t)

func _on_toggle_pressed() -> void:
	"""Toggle between expanded and collapsed states"""
	is_expanded = not is_expanded
	animation_progress = 0.0

	# Start animation
	print("ContextPanel: %s" % ("Expanding" if is_expanded else "Collapsing"))

func _finish_animation() -> void:
	"""Called when animation completes"""
	if is_expanded:
		# Show expanded content
		toggle_button.text = "<<"
		toggle_button.visible = true
		title_label.visible = true
		content_container.visible = true
		collapsed_button.visible = false
		panel_container.visible = true
	else:
		# Show collapsed state - just narrow strip + button
		panel_container.visible = false
		collapsed_button.visible = true

		# Position collapsed button at same Y position as toggle button was
		# Get toggle button's global position before hiding
		var button_y_pos = toggle_button.global_position.y
		collapsed_button.position = Vector2(collapsed_width, button_y_pos)

func set_context_title(title: String) -> void:
	"""Set the title bar text (context-dependent)"""
	title_label.text = title

func set_context_content(content_node: Control) -> void:
	"""Replace the content area with a new context-specific UI"""
	# Clear existing content
	for child in content_container.get_children():
		child.queue_free()

	# Add new content
	if content_node:
		content_container.add_child(content_node)

func get_content_container() -> Control:
	"""Get the container for adding context-specific UI"""
	return content_container
