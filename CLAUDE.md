# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Godot 4.4 game project named "Leeward" using the Forward Plus renderer.

## Common Development Commands

### Running the Project
```bash
# Open the project in Godot Editor
godot --editor

# Run the project directly
godot

# Run a specific scene
godot res://path/to/scene.tscn
```

### Debugging
```bash
# Run with verbose output
godot --verbose

# Run with debug collision shapes visible
godot --debug-collisions
```

### Export and Build
```bash
# Export for specific platform (requires export templates)
godot --export-release "Windows Desktop" builds/windows/game.exe
godot --export-release "macOS" builds/macos/game.app
godot --export-release "Linux" builds/linux/game.x86_64
```

## Project Structure

- **res://** - Root resource path in Godot (maps to project root)
- **.godot/** - Auto-generated folder containing imported assets and cache (gitignored)
- **project.godot** - Main project configuration file

## Godot-Specific Development Notes

### File Types
- **.gd** - GDScript source files
- **.tscn** - Scene files (text-based)
- **.tres** - Resource files (text-based)
- **.import** - Import configuration for assets

### Common Patterns
- Scenes are typically organized by feature or game area
- Scripts extend Node classes and are attached to scenes
- Resources are shared data containers
- Autoload/Singletons are configured in Project Settings

### Script Structure
GDScript files typically follow this structure:
```gdscript
extends [NodeType]

# Signals
signal example_signal(parameter)

# Constants and enums
const CONSTANT_VALUE = 10

# Export variables (shown in Inspector)
@export var exposed_variable = 0

# Regular variables
var internal_variable = 0

# Built-in callbacks
func _ready():
	pass

func _process(delta):
	pass

# Custom methods
func custom_method():
	pass
```
