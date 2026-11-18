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
  "turn_limit": 30,
  "year": 1798,
  "ships": []
}
```

Optional fields: `turn_limit` (integer, game ends at that turn; omit for no limit) and `year`
(integer, the battle's year; when present and ≤ 1783 a hull critical #12 explosion roll takes −1,
Hull Critical Hits table; omit it and no year DRM applies). Also optional: `navies`, the navy each
side sails under, `{"0": "British", "1": "French"}` (1.G.8: French BGN at ranges 11–15), or `navy` on
one ship; without them a ship uses its type's `nationality`.
Also optional: `tournament` (bool, default false): a tournament game (14.C.3) shows every player
the full box counts of every ship; otherwise each player sees only the sections lost of ships
they do not command (limited information, 14.C.1, `PlayerView`).

Players (optional; spec `docs/superpowers/specs/2026-11-17-players-and-sides-design.md`): without them each
side is one player whose id is the side number.

```json
"players": [
  {"id": 0, "side": 0, "name": "Hood", "ships": ["lively", "boreas"]},
  {"id": 1, "side": 0, "name": "Pellew", "ships": ["indef"]},
  {"id": 2, "side": 1, "name": "French"}
],
"groups": { "0": { "van": ["lively"], "rear": ["boreas", "indef"] } }
```

- `players[]`: `id` (unique), `side` (must have ships), `name`, `ships` (ids the player commands, all on that
  side; a ship listed under no player belongs to the side's lowest-id player). Humans are chosen at game start
  (`start_scenario`), the rest are AI.
- `groups`: keyed by side number, then group name to ship ids; a signal may be addressed to a group (11.A.2).
- Ship `flag`: `"fleet"` (at most one per side) or `"squadron"`; the flagship is what FOLLOW FLAGSHIP and the
  end-by-agreement vote read.
- Ship `side` is the owning side (the older `player_id` key is still read).

Each ship entry:

```json
{
  "id": "unique_ship_id",
  "side": 0,
  "ship_type": "frigate_38",
  "position": { "q": 0, "r": 0 },
  "facing": 0,
  "speed": 0,
  "movement_points": 0,
  "acceleration": 0,
  "sail_state": "MS",
  "crew_quality": "Trained",
  "crew_morale": 4,
  "flag": ""
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
- `flag`: optional, `fleet`, `squadron` or empty
- `side`: integer (0 = the human side, 1+ = opponents/AI); the older key `player_id` is still read as an alias
- `id` must be unique across all ships in the scenario
- `position` (q, r): axial hex coordinates of the ship's **bow**. Every ship holds two hexes: the stern
  is derived, the neighbour against the facing (`stern = bow + DIRECTIONS[(facing + 3) % 6]`, i.e.
  `HexGrid.stern_of(bow, facing)`; facing 0/E puts the stern at q−1). No two footprints (bow or
  stern) may share a hex — `GameState.add_ship` refuses an overlapping ship — and both hexes must lie
  inside `map_bounds` and on water (not land)
- `sea_state`: 0-5 (0 calm, 1 slight, 2 moderate, 3 rough, 4 very rough, 5 high; clamped on load)
- `region`: `oceanic`, `coastal`, `harbor`
- `wind_speed_change`: `steady`, `gusting`, `dying`
- `wind_direction_change`: `none`, `veering`, `backing`

## Map and terrain (spec `docs/superpowers/specs/2026-11-17-map-and-scenario-design.md`)

`map_bounds` `{"width": W, "height": H}` is a rectangle of H rows of W hexes in **odd-r offset**
(pointy-top, odd rows shifted half a hex right), centred on the origin: columns `-W/2 .. -W/2+W-1`,
rows `-H/2 .. -H/2+H-1` (integer division). Axial (q, r) from offset (col, row):
`q = col - (row - (row & 1)) / 2`, `r = row` (`TerrainMap.offset_to_axial`). Without `map_bounds` the board is
unbounded. Every `[q, r]` below is axial.

```json
"terrain": {
  "edges": { "N": "open", "E": "none", "S": "open", "W": "escape" },
  "land": [[-3, 11], [-2, 11]],
  "shallow": [ { "name": "A", "base": 15, "hexes": [[-4, 10], [-3, 10]] } ],
  "boundaries": []
},
"escape": { "1": { "from_turn": 1, "edges": ["W"], "share": 0.5 } },
"aground_counts_lost": true,
"ai": { "1": "escape" }
```

- `terrain.edges`: kind of each map edge, default `open`. `open` is a wall (a plot cannot cross it, a
  drift stops at it); `none` means a ship that leaves the map is lost (no sea room, III.C); `escape` lets a
  side that may escape (below) leave and be scored as escaped.
- `terrain.land`: land hexes (impassable; block line of sight, 7.B.7-9).
- `terrain.shallow`: areas of shoal water; each hex has depth `base + 1d6`, rolled when a ship first enters
  it; a ship whose `draft` exceeds the depth runs aground (13.G). A hex is in at most one area and is not land.
- `terrain.boundaries`: extra lines `{"name", "kind", "sides": [[[q,r],[q,r]], ...]}` (each side is two
  neighbouring hexes). Only `open` is supported for these for now; do not use `none` or `escape` off the map edge.
- `escape`: keyed by side. `from_turn` (default 1), `edges` (names of escape boundaries the side may use; empty =
  all), `share` (the fraction of an escaped ship's point value its own side scores, VI.B.6; default 0). A ship may leave only after the player declares escape
  (`player_declare_escape`), and then escapes at the end of a turn by distance or speed from its pursuers (V.D).
- `aground_counts_lost`: default `true`; an aground ship scores as lost (13.G.3). `false` scores it as in play.
- `ai`: keyed by side; `"escape"` makes that side's stub AI run for a permitted escape edge. Absent = the
  standing order decides (default engage).
- Ship `arrives` (integer turn, default 1): a reinforcement waits off the map and enters on the start of that
  turn at its `position` and `facing`, at its `sail_state` (**default `PS`**, not `MS`), at the speed of its
  movement allowance there (2.B.1, 3.A). A held entry is put back a turn.

Terrain checks (`TerrainMap.errors`, all start `Terrain:`, `start_scenario` refuses a scenario that has any):
unknown edge name or kind, land or shallow hex off the map, a hex both land and shallow, a hex in two shallow
areas, a negative shallow `base`, boundary side hexes that are not neighbours. `GameState.placement_errors()`
adds: a ship hex (bow or stern, including a waiting reinforcement's entry footprint) off the map or on land, and
overlapping ships. Keep ships clear of land, off the map edge, and avoid starting them in shallows.

## Anchoring (spec `docs/superpowers/specs/2026-11-17-anchoring-design.md`)

```json
"anchoring": true,
"ships": [ { "id": "fr1", "...": "...", "anchor": {"end": "bow", "springs": true, "cable": 1} } ]
```

- `anchoring`: where ships may anchor (Scenario Book V.B). Absent or `false` = nowhere (default), `true` =
  anywhere, or a zone `{"rows": [first, last], "areas": ["shoal name", ...]}`: odd-r offset rows (inclusive)
  and/or named `terrain.shallow` areas. Checked at the hex the anchor would drop in.
- Ship `anchor` (optional): the ship starts at anchor. `end` (`"bow"` or `"stern"`, required); `springs`
  (default `false`); `cable` 1-4 (default 1); `hex` `[q, r]` (default: `cable` hexes upwind of the anchored end).
  It counts as one of the ship's two anchorings (13.A.5). Give the ship her proper facing (bow into the wind for a
  bow anchor, stern into the wind for a stern anchor; otherwise she swings to it on the first g-t). The
  `anchoring` permission is not checked for a starting anchor.

Anchoring checks (`AnchorRules.scenario_errors`, all start `Anchoring: `, reported by `placement_errors`; a
bad ship entry is skipped, nothing is anchored): `anchoring` not true, false or a zone; a zone with neither
`rows` nor `areas`; `rows` not `[first, last]`; `areas` not a list or naming an unknown area; a ship `anchor`
that is not an object or whose `end` is not bow or stern; `cable` outside 1-4; an explicit `hex` off the map.
The anchor hex itself is not checked against land. See `data/scenarios/test_anchorage.json`.

## Output

Write the scenario file to `data/scenarios/<name>.json`. Use snake_case for the filename.

After creating the file, remind the user to test it with `make play` (or edit `scenes/main_game.tscn` to point to the new scenario) and verify it loads without errors.
