extends PanelContainer
## GameInfoPanel - Displays turn counter and phase information

@onready var turn_label: Label = %TurnLabel
@onready var phase_label: Label = %PhaseLabel
@onready var wind_speed_label: Label = %WindSpeedLabel

func _ready() -> void:
	GameState.turn_changed.connect(_on_turn_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	_update_display()

func _update_display() -> void:
	if turn_label:
		turn_label.text = "Turn: %d" % GameState.current_turn

	if phase_label:
		var phase_name = GameState.get_phase_name()
		phase_label.text = "Phase: %s" % phase_name.replace("_", " ")

	if wind_speed_label:
		var wind_speed_names = ["Calm", "Light", "Moderate", "Strong", "Gale", "Storm"]
		var speed_name = wind_speed_names[GameState.wind_speed] if GameState.wind_speed < wind_speed_names.size() else "Unknown"
		wind_speed_label.text = "Wind: %s" % speed_name

func _on_turn_changed(_turn: int) -> void:
	_update_display()

func _on_phase_changed(_phase) -> void:
	_update_display()
