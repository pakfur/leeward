# Sea state: lower-deck guns and a heavier sea (design)

Date: 2026-11-16. Status: approved by the user 2026-11-16 (builder check done). Comes before roadmap sub-project 2 (user's choice); it takes the 7.F / 3.E.1 piece out of sub-project 6 (ships and guns).

## Intent

Two things, one subject:

1. **Rules.** Implement lower-deck guns against sea state (7.F, 3.E.1): when the sea is as high as a ship's freeboard her leeward lower-deck guns are shut, and above it all of them. The ship data already carries `freeboard` and `lower_deck_modifier` (checked against the Ship Data Chart: 38 = 6 / −7, 32 = 5 / −7, 74 = 4 / −5), but nothing reads them, and Leeward's sea state (0–3) cannot reach a freeboard of 4.
2. **Look and feel.** Today the ships "bob around like a tiny toy in a bathtub", the sea has no weight or roughness even zoomed in, and ships move with too little weight. The user wants weight and height in the sea up close, balanced against the board having to read as a game board zoomed out. Whitecaps are wanted from sea state 1 up because they show the wind direction at a glance.

The look was settled in a throwaway spike (`spike/sea-motion`, worktree `.claude/worktrees/sea-spike`, commits f4a6dff, 6e1cacb, b365fed) that the user tuned with live sliders. This design turns it into production code with the user's values.

## Goals

- Sea state runs **0–5**: 1–5 as in the rules (3.B.5), plus 0 = calm (a deliberate extension, no rule effect). Scenarios use the full scale.
- 7.F.2 applies the lower-deck gunfire modifier (LDGM) to the BGN: sea state = freeboard → the leeward broadside only (not at WF=L or WF=R); sea state > freeboard → all gunfire. Previews, the resolver, the AI and the fire panel all agree.
- One sea model drives the water and the ships, so ships ride the swell the player sees.
- Three zoom bands, blended smoothly: zoomed out a flat board (waves only as shading and texture, ships level); mid zoom gentle rocking and barely visible water movement; zoomed in the full swell with heavy, realistic motion.
- The plain hex grid fades out as you zoom in; course, arc, move and target hexes stay visible and clickable at every zoom.
- Whitecaps from sea state 1, streaked downwind, stronger with sea state.
- Ship moves play as one continuous glide with gentle acceleration, slower in heavy seas.
- The tuning values stay editable for later tuning, in a developer tool, not in player UI.

## Non-goals

- Changing game movement. Zoom and sea look are presentation only: drift, leeway, every hex move and every rule are unaffected by zoom.
- Changing sea state during a scenario (it never changes, 3.B.5).
- Sinking, capsizing or any other heavy-weather rule beyond 7.F and the existing dismasted −sea-state modifier (7.C.12e).
- Weather particles (spray, rain), wakes, sound.

## Anti-goals

- **A board you can't read zoomed out.** At the "flat" distance the water must be still enough that hexes, highlights and ships read exactly as now.
- **Ships out of step with the water.** A ship rising on a crest the water doesn't show, or a different clock, is the bug the spike fixed; don't reintroduce it.
- **Highlights hidden by the sea.** The grid may fade; move/course/arc/target hexes never.
- **Server authority weakened.** All the sea look is view code that only reads state. The rule part is server-side in the gunnery calculator.

## Approaches

**One sea model with a zoom intensity (chosen).** Wave settings derived once from wind and sea state feed both the water shader and the ship motion on one clock; a 0–1 intensity from the camera distance scales swell height and ship motion. Coherent; costs reworking shader and ship motion together.

**Two sea materials crossfaded by zoom** — a flat board sea and a separate full ocean blended in between. Rejected: two shaders to keep in step, a blend that can look layered, and the ships still need one motion model.

**Ship motion invented separately from the waves** — per-ship roll and pitch rhythms, sea tuned apart. Rejected: ships wouldn't match the visible swell, which defeats the sense of weight.

The user chose the first and asked for a spike; the spike's structure is the starting point.

## Design

### A. Rules: sea state scale and lower-deck guns

1. **Scale.** `EnvironmentState.sea_state` is 0–5 (validated/clamped on load; default 1). Names: 0 calm, 1 slight, 2 moderate, 3 rough, 4 very rough, 5 high (*builder's call:* exact words; keep `wind_speed_name`'s style). `GameState.sea_state`, the developer UI editor (today 0–3) and the scenario-creator skill (`.claude/skills/scenario-creator/SKILL.md`) follow the new range.
2. **Scenarios** ("update the scenarios to the full scale", user). The three test scenarios keep `sea_state: 1`. *Planner's call:* add one scenario, `data/scenarios/test_heavy_weather.json`, with sea state 4, wind 3, the 74 against the two frigates, so the lower-deck rule (74 freeboard 4: leeward guns shut) and the rough-sea look can be seen and tested. Existing scenario outcomes and tests are untouched.
3. **7.F.2 in the gunnery calculator.** In `GunneryCalculator.preview()`, beside the dismasted modifier: let `fb = firer.ship.freeboard`, `ldgm = firer.ship.lower_deck_modifier` (negative), `sea = environment.sea_state`.
   - `sea < fb` (and always at sea 0): nothing.
   - `sea == fb`: if the firer's WF is C or B and the firing side is the **leeward** side, add modifier `lower_deck_closed` = `ldgm`. WF=L or R: nothing.
   - `sea > fb`: add `lower_deck_closed` = `ldgm` to every shot.
   - The modifier applies to the BGN like the others (it is a "BGN gunfire modifier", SDC note "L"), for full and half broadsides alike.
   - **Leeward side:** the side away from the wind (3.B.2). In Leeward `wind_direction` is the direction the wind comes **from** (`HexGrid.get_wind_facing` gives L when facing == wind_direction; drift goes to `(wind_direction + 3) % 6`). So with `r = (facing − wind_direction + 6) % 6`: r = 1 or 2 → leeward is STARBOARD; r = 4 or 5 → PORT; r = 0 or 3 (WF=L or R) → none (−1). Put this in one pure helper (e.g. `FireGeometry.leeward_side(facing, wind_direction) -> int`) with tests for all six facings.
   - Label in `PhaseEvents.MODIFIER_LABELS`: `lower_deck_closed` → "Lower deck guns closed".
4. **Display.** The fire panel's breakdown already lists modifiers. The selected ship card's Guns readout (`CrewOverlayText.gun_rows` / `guns_readout`) notes a shut lower deck per side ("lower deck closed: sea 4") so the player sees it before firing (*builder's call:* exact copy).
5. **feature_diff.md:** the §2.1 "Lower-deck guns, freeboard vs. sea state" row → §5; a §4 entry for sea state 0 (calm) as an extension; CLAUDE.md's Scenarios and Known Limitations lines updated.

### B. The sea model (view)

Production version of the spike's `scripts/view/sea_model.gd` (read it; it is the reference implementation). Presentation only, never writes state.

1. **One clock.** The model owns `sea_time`, advances it in `_process`, and pushes it to the shader as a uniform every frame; ship motion samples the same function at the same time. The old `scripts/core/wave_calculator.gd` copy of the wave settings goes (or becomes a thin wrapper over the model); nothing keeps a second set of wave numbers.
2. **Swell.** Three Gerstner components running downwind with the spike's spread and shares (`COMPONENTS`: 0°/0.6/×1.0, +22°/0.3/×0.73, −31°/0.25/×1.37; crest sharpening `SWELL_Q` 0.8), deep-water phase speed at map scale (`G_MAP` = 9.81/26), amplitude = base amplitude by sea state (`SWELL_AMP_BY_SEA` = 0.03, 0.06, 0.1, 0.15, 0.22, 0.3 for 0–5) × the preset's `swell_height_mult` × zoom intensity. Short chop and the two normal maps stay as surface detail at every zoom, scaled by `chop_strength`. The water mesh is fine enough for the swell (the spike's 384×384 subdivision; *builder's call* if a camera-centred patch is cheaper for the same look).
3. **Zoom intensity.** 0 at camera distance ≥ `flat_distance` (20.5), 1 at ≤ `full_distance` (7.5), smooth in between (the spike's curve). It scales swell vertex height, ship heave/pitch/roll/heel and whitecaps (whitecaps keep 15 % zoomed out as faint texture). `swell_shading` (0.4) tilts the normals with the swell when zoomed out so the board reads as sea without moving.
4. **Grid fade.** The shader's plain hex grid has opacity 1 up to intensity `grid_fade_start` (0.5) and 0 at `grid_fade_end` (1.0). `HexOverlay` layers (course, arc, move, target, blocked) are unaffected.
5. **Whitecaps.** Foam on swell crests above `whitecap_threshold` (fraction of crest height) plus breaking chop, streaked downwind; strength = preset `whitecap_strength` × `WHITECAP_BY_SEA` (1.0, 0.8, 1.0, 1.25, 1.0, 1.6 for 0–5) × zoom factor; none below `whitecap_min_sea` (1).
6. **Presets.** One preset per sea state, the user's final tuning (2026-11-16), stored as data in `data/ui/sea_presets.json` (presentation data, like `deck_layouts.json`), keyed "0"–"5":

| Sea | swell_height_mult | swell_wavelength | swell_speed | swell_shading | chop_strength | inertia_mult | heel_mult | glide_seconds | whitecap_threshold | whitecap_strength |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0.5 | 13.75 | 2.55 | 0.4 | 1.85 | 1.05 | 1.05 | 0.8 | 0.55 | 0.0 |
| 1 | 0.9 | 8.75 | 0.6 | 0.4 | 2.55 | 1.1 | 1.5 | 0.8 | 0.8 | 1.1 |
| 2 | 0.9 | 8.75 | 0.6 | 0.4 | 2.55 | 1.1 | 1.5 | 0.8 | 0.8 | 1.1 |
| 3 | 0.75 | 5.5 | 0.6 | 0.4 | 2.55 | 1.5 | 1.5 | 0.8 | 0.8 | 1.2 |
| 4 | 1.6 | 11.75 | 1.2 | 0.4 | 1.9 | 1.9 | 1.5 | 1.5 | 0.55 | 1.8 |
| 5 | 1.2 | 9.5 | 2.2 | 0.4 | 2.45 | 2.4 | 1.5 | 1.5 | 0.55 | 2.6 |

   This table is authoritative: the spike's committed `PRESET_*` constants are older round-1 values. Global: `flat_distance` 20.5, `full_distance` 7.5, `grid_fade_start` 0.5, `grid_fade_end` 1.0, `whitecap_min_sea` 1. The user tuned these **with** `SWELL_AMP_BY_SEA` and `WHITECAP_BY_SEA` in place, so both tables are part of the look and must be kept as they are.
7. **Developer tuning.** The spike's F9 panel becomes a "Sea" section of the existing Developer UI (F12; debug builds only): the same sliders, the live camera distance and intensity, a sea-state override (for viewing only: it changes the look, never `EnvironmentState`), and "Print values" logging through `Trace` in the preset format. The spike's autoshot script is dropped.

### C. Ship motion (view)

1. Each `ShipView` samples the swell at bow, stern and both beams (the spike's method) for heave, pitch and roll, low-passed with time constants scaled by ship class/size × the preset's `inertia_mult`, so a 74 answers about 1.4–1.5× slower than a frigate.
2. Steady heel to leeward by wind speed (`HEEL_BY_WIND` = 0, 1.5, 3, 5, 7, 9 degrees at a beam wind for WS 0–5) × sail carried × `heel_mult`, scaled by the beam component of the wind (none head to wind or before it).
3. All motion × zoom intensity: ships sit level at the flat distance.
4. Wrecks keep their sink and fade (8.G.1f work), on top of the swell.

### D. Movement playback (view)

1. Each ship's whole move is one continuous glide with gentle acceleration and deceleration, `glide_seconds` per segment from the current sea state's preset (0.8 s calm to rough, 1.5 s at 4–5). Final positions, the order of events, event pauses and the bear-off pause/resume behave as today.
2. **Ships stand on the event hexes.** The spike stretches each ship's whole move over one track, so at a segment with an event (collision, contested hex, overlap rollback, bear-off pause) ships can be short of or past the hexes involved. *Planner's call (builder check):* split each ship's glide at every segment that has an event; within each stretch the ship accelerates and decelerates, arriving **exactly** on its resolved pose for that segment when the pause starts, then accelerates away after it. Stretches without events stay one continuous glide. This also fixes the spike's "stops dead" edge (the stop is now an arrival). The bear-off resume restarts from the paused segment's poses. Tests assert the pose at every event segment, not only the final pose.
3. *Planner's call:* `HexOverlay` highlights stay flat at their current height, drawn over everything, and clicks keep picking on the flat map plane, even when the swell moves under them zoomed in (the user saw this in the spike).

## Testing

- Rules: GUT tests for the 7.F.2 cases (sea < fb, = fb leeward and windward at WF=C and B, = fb at WF=L/R, > fb both sides, sea 0), the leeward helper for all facings, sea-state load/clamp 0–5, the new scenario loads with valid placements. Expected values from 7.F.2 and the SDC.
- View: unit tests for the pure parts (zoom intensity curve, preset loading from JSON, grid opacity, leeward heel sign, glide timing keeps final poses); a server-authority test pass; a live check in the running game at the flat, mid and full distances at sea 1 and sea 5 (`game_get_errors` = 0).
- `make test` green; the SCV review at the end.

## Left to the builder

File layout within `scripts/view/`, shader structure, the camera-patch vs subdivision choice, exact copy for sea-state names and the Guns readout note, the event-pause easing time.

## Questions

None open. Planner's calls to check: the new heavy-weather scenario (A2); presets stored in `data/ui/sea_presets.json` (B6); the tuning panel moved into the F12 Developer UI (B7); ships arrive exactly on event hexes, the glide split at event segments (D2); highlights stay flat over the swell (D3); sea 1 and 2 share your "1, 2" values.
