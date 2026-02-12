GODOT := godot
GUT_CLI := addons/gut/gut_cmdln.gd
TEST_DIR := res://test/

.PHONY: help test test-verbose test-file run play editor import clean version

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- Testing ---

test: ## Run all tests
	$(GODOT) --headless -s $(GUT_CLI) -gdir=$(TEST_DIR) -ginclude_subdirs -gexit

test-verbose: ## Run all tests with verbose output
	$(GODOT) --headless --verbose -s $(GUT_CLI) -gdir=$(TEST_DIR) -ginclude_subdirs -gexit -glog=3

test-file: ## Run a single test file (usage: make test-file F=test/unit/test_data_manager_ships.gd)
	@test -n "$(F)" || (echo "Usage: make test-file F=test/unit/test_foo.gd" && exit 1)
	$(GODOT) --headless -s $(GUT_CLI) -gtest=res://$(F) -gexit

# --- Running ---

run: ## Run the game (starts at splash screen)
	$(GODOT)

play: ## Run directly into gameplay (skip menus)
	$(GODOT) res://scenes/main_game.tscn

editor: ## Open in Godot Editor
	$(GODOT) --editor

# --- Project Management ---

import: ## Rebuild the Godot import cache
	$(GODOT) --headless --import

clean: ## Remove .godot cache (forces full reimport)
	rm -rf .godot/

version: ## Show Godot version
	$(GODOT) --version
