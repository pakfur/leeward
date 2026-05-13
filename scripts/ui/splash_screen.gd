extends Control
## SplashScreen - Main menu with Play and Quit options

signal play_requested()
signal quit_requested()

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton
@onready var quit_dialog: ConfirmationDialog = %QuitDialog

func _ready() -> void:
	# Connect button signals
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_dialog.confirmed.connect(_on_quit_confirmed)

func _on_play_pressed() -> void:
	Trace.trace_log("UI", "Play button pressed")
	play_requested.emit()

func _on_quit_pressed() -> void:
	Trace.trace_log("UI", "Quit button pressed - showing confirmation")
	quit_dialog.popup_centered()

func _on_quit_confirmed() -> void:
	Trace.trace_log("UI", "Quit confirmed")
	get_tree().quit()
