---
estimated_steps: 1
estimated_files: 3
skills_used: []
---

# T02: Calculate and display tacking probability in Planning UI

In GameController, read is_tacking_attempt from client signals and pass tacking probability (looked up from DataManager.get_tacking_percent) to PlanningPhaseUI. Add a tacking probability label to the plotting controls section of the planning UI. Show 'Tacking: NN%' when is_tacking_attempt is true, hide otherwise. Compute probability from ship's maneuverability and current wind speed.

## Inputs

- `is_tacking_attempt from client signals`
- `DataManager.get_tacking_percent`
- `ship maneuverability from Ship definition`
- `wind_speed from GameState.environment`

## Expected Output

- `Tacking probability label in planning UI`
- `Label shows percentage when tacking, hides otherwise`

## Verification

make test passes; label visible/hidden correctly in manual test
