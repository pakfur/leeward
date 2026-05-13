---
name: gen-test
description: Generate a GUT test file for a GDScript source file, matching project test patterns
disable-model-invocation: true
---

# GUT Test Generator

Generate a GUT test file for a given GDScript source file.

## Usage

The user provides a script path (e.g., `scripts/server/ship_state_controller.gd`). Generate a matching test file at `test/unit/test_<name>.gd`.

## Workflow

1. Read the target script to understand its class, methods, dependencies, and constructor/init requirements.
2. Read 1-2 existing test files from `test/unit/` to match the project's style (good examples: `test_movement_validator.gd`, `test_data_manager_ships.gd`).
3. Generate the test file following the patterns below.
4. Run `make test-file F=test/unit/test_<name>.gd` to verify it compiles and passes.

## Test File Pattern

```gdscript
extends GutTest
## Tests for <ClassName> — <brief description>.

# Declare test fixtures
var instance: ClassName

func before_each() -> void:
    # Set up fresh instance for each test
    instance = ClassName.new()

func after_each() -> void:
    # Clean up
    if instance:
        instance.free()

# --- Section Name ---

func test_descriptive_name() -> void:
    # Arrange
    var input = ...
    # Act
    var result = instance.method(input)
    # Assert
    assert_eq(result, expected, "Explanation of what's being verified")
```

## Key Conventions

- File name: `test/unit/test_<script_name>.gd` (e.g., `test_ship_state_controller.gd`)
- Class extends `GutTest`
- All test methods prefixed with `test_`
- Use `before_each()` for per-test setup (preferred) or `before_all()` for expensive one-time setup
- Use `after_each()` to free any created nodes/objects
- Group related tests with `# --- Section Name ---` comments
- Use descriptive assertion messages as the last argument
- Autoload singletons (`DataManager`, `GameState`, `Trace`) are available directly by name
- For server controllers that need `GameState`, create a mock (see `test_movement_validator.gd` for the `MockGameState` pattern)
- For testing scripts that check `is_server`, the test environment defaults to server mode
- Assert methods: `assert_eq`, `assert_ne`, `assert_true`, `assert_false`, `assert_null`, `assert_not_null`, `assert_gt`, `assert_lt`, `assert_has`, `assert_almost_eq`
- For expected errors: `assert_engine_error("expected message")`
- Use `Trace` (not `print()`) for any debug output in test helpers

## What to Test

- Public methods (skip private `_` prefixed methods unless they have complex logic)
- Edge cases: null/empty inputs, boundary values, invalid arguments
- For server controllers: verify `is_server` guard exists, test state mutations
- For data lookups: test valid keys, missing keys, boundary values
- For state objects: test serialization round-trips if `to_dict()`/`from_dict()` exist

## Output

Write the test file, then run it to verify it passes. Fix any compilation or assertion errors before reporting completion.
