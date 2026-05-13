---
name: scenario-creator
description: Create new Leeward scenario JSON files with valid ship placements, wind, and map config
disable-model-invocation: true
---

# Scenario Creator

Create a new scenario JSON file in `data/scenarios/`.

## Workflow

1. Ask the user for:
   - Scenario name and description
   - Number of ships per side and ship types (look up valid types from `data/rules/ships.json`)
   - Wind conditions (direction 0-5, speed 1-4)
   - Any special requirements (starting positions, formations, sail states)

2. Read `data/rules/ships.json` to validate ship type IDs.

3. Generate the scenario JSON using this schema:

```json
{
  "name": "Scenario Name",
  "description": "What this scenario tests or demonstrates",
  "seed": 42,
  "wind_direction": 2,
  "wind_speed": 2,
  "wind_speed_change": "steady",
  "wind_direction_change": "none",
  "region": "oceanic",
  "sea_state": 1,
  "map": {
    "map_texture": "res://assets/textures/water_default.png",
    "show_hex": true
  },
  "map_bounds": {
    "width": 100,
    "height": 100
  },
  "minimap_texture": "",
  "ships": []
}
```

Each ship entry:

```json
{
  "id": "unique_ship_id",
  "player_id": 0,
  "ship_type": "frigate_38",
  "position": { "q": 0, "r": 0 },
  "facing": 0,
  "speed": 0,
  "movement_points": 0,
  "acceleration": 0,
  "sail_state": "MS",
  "crew_quality": "Trained",
  "crew_morale": 4
}
```

## Validation Rules

- `ship_type` must exist in `data/rules/ships.json`
- `facing`: 0-5 (0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE)
- `wind_direction`: 0-5 (same as facing)
- `wind_speed`: 1-4
- `sail_state`: one of `FS` (fighting), `MS` (maneuvering), `PS` (plain), `NS` (no sail)
- `crew_quality`: one of `Elite`, `Crack`, `Trained`, `Green`, `Rabble`
- `crew_morale`: 1-6
- `player_id`: integer (0 = player, 1+ = opponents/AI)
- `id` must be unique across all ships in the scenario
- `position` (q, r): axial hex coordinates — avoid overlapping positions
- `sea_state`: 1-4
- `region`: `oceanic`, `coastal`, `harbor`
- `wind_speed_change`: `steady`, `gusting`, `dying`
- `wind_direction_change`: `none`, `veering`, `backing`

## Output

Write the scenario file to `data/scenarios/<name>.json`. Use snake_case for the filename.

After creating the file, remind the user to test it with `make play` (or edit `scenes/main_game.tscn` to point to the new scenario) and verify it loads without errors.
