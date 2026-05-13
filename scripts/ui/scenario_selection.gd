extends Control
## ScenarioSelection - Select a scenario to play

signal scenario_selected(scenario_name: String)
signal back_requested()

@onready var scenario_list: ItemList = %ScenarioList
@onready var description_label: Label = %DescriptionLabel
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton

var scenarios: Array[Dictionary] = []
var scenario_files: Array[String] = []

func _ready() -> void:
	# Connect signals
	scenario_list.item_selected.connect(_on_scenario_selected)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Load scenarios
	_load_scenarios()

	# Disable start button until scenario selected
	start_button.disabled = true

func _load_scenarios() -> void:
	"""Load all scenario files from data/scenarios directory"""
	var scenarios_path = "res://data/scenarios/"
	var dir = DirAccess.open(scenarios_path)

	if not dir:
		push_error("Failed to open scenarios directory: " + scenarios_path)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path = scenarios_path + file_name
			var scenario = _load_scenario_file(full_path)

			if scenario:
				scenarios.append(scenario)
				scenario_files.append(file_name.get_basename())

				# Add to list
				var display_name = scenario.get("name", file_name.get_basename())
				scenario_list.add_item(display_name)

		file_name = dir.get_next()

	dir.list_dir_end()

	Trace.trace_log("UI", "Loaded %d scenarios" % scenarios.size())

func _load_scenario_file(path: String) -> Dictionary:
	"""Load a single scenario JSON file"""
	if not FileAccess.file_exists(path):
		push_error("Scenario file not found: " + path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open scenario file: " + path)
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)

	if error != OK:
		push_error("Failed to parse scenario JSON: " + path + " Error: " + json.get_error_message())
		return {}

	return json.data

func _on_scenario_selected(index: int) -> void:
	"""Handle scenario selection from list"""
	if index < 0 or index >= scenarios.size():
		return

	var scenario = scenarios[index]

	# Update description
	var description = scenario.get("description", "No description available")
	description_label.text = description

	# Enable start button
	start_button.disabled = false

func _on_start_pressed() -> void:
	"""Start selected scenario"""
	var selected_index = scenario_list.get_selected_items()

	if selected_index.is_empty():
		return

	var index = selected_index[0]
	var scenario_name = scenario_files[index]

	Trace.trace_log("UI", "Starting scenario: " + scenario_name)
	scenario_selected.emit(scenario_name)

func _on_back_pressed() -> void:
	"""Return to main menu"""
	back_requested.emit()
