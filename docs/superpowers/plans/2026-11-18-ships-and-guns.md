# Ships and Guns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Leeward all 41 Ship Data Chart types plus four order-of-battle ships (three class-4 corvettes and
brigs, and Diomede with medium guns), a validator for them, tests for medium guns, class 4 and lower-deck guns at
every freeboard, and the house-rule simple chasers (one long-gun factor firing dead ahead and dead astern), played
by the stub AI and drawn by a view-only minimum.

**Architecture:**
- Data: `ships.json` rows keyed by nation-prefixed ids, old ids as aliases resolved in `DataManager` (Task 1).
- Tests only for medium guns, class 4 and lower-deck guns (Task 2).
- Chasers are fire orders on two new arc numbers, `side` 2 (bow chase) and 3 (stern chase), battery `"chase"`:
  pure geometry and declaration rules (Task 3), then the calculator and resolver (Task 4), the AI (Task 5).
- View: fire panel and map arcs (Task 6); ship card, procedural models and deck drawings (Task 7).
- Test scenario and docs (Task 8).

**Size:** 8 tasks, under the ~14 limit. If a split is wanted: Tasks 1–2 (ship data) and Tasks 3–8 (chasers, view,
docs) are each a coherent branch; Task 8's docs would then be split between them.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5, Python 3 (validator). `make test` runs the whole suite. Run
`make import` before `make test` whenever a task adds a `class_name` or any new file; Godot then writes the
`.uid` files, which every commit must include.

**Spec:** `docs/superpowers/specs/2026-11-18-ships-and-guns-design.md`. Executors read it alongside this plan;
section numbers below (§n) are the spec's. Binding requirements:
`docs/superpowers/specs/2026-11-17-subprojects-3-7-decisions.md` §0 and §5. Rules: `docs/rules/close_action.md`
1.G, 7.A.4, 7.B, 7.C, 7.E.2, 7.F; the Ship Data Chart scan `docs/rules/images/ship-data-chart.jpg` (pdf p.106);
the OB scans `docs/rules/images/sb-p08-1.png` (Babet) and `sb-p09-1.png` (Diomede, Coureur, Rosalie). Invoke the
`close-action-rules` skill before game-logic work.

## Global Constraints

- **Directions:** `HexGrid.DIRECTIONS` 0 = E (1, 0), 1 = SE (0, 1), 2 = SW (−1, 1), 3 = W (−1, 0), 4 = NW (0, −1),
  5 = NE (1, −1). `HexGrid.stern_of(bow, f) = bow + DIRECTIONS[(f + 3) % 6]`. Starboard is `facing + 1`/`+ 2`.
- **Arc numbers:** `ShipState.PORT` 0, `ShipState.STARBOARD` 1, `FireGeometry.ARC_AHEAD` 2, `FireGeometry.ARC_ASTERN`
  3. `GunneryTypes.CHASE_BOW` = 2 and `GunneryTypes.CHASE_STERN` = 3 (literals, with a test that they equal the
  FireGeometry values). `GunneryTypes.BATTERY_CHASE` = `"chase"`. The bow chaser fires from the bow hex into
  `ARC_AHEAD` (≤ 30° off the heading, 0.5° tolerance), the stern chaser from the stern hex into `ARC_ASTERN`
  (≥ 150° off the heading), both to range 15.
- **Chaser numbers:** `FireRules.CHASE_GUN_FACTORS = {"lg": 1, "mg": 0, "cr": 0}`, so TGF 1. BGN for TGF 1 by range
  1–7: 3, 2, 2, 1, 1, 0, 0; range 8+ grey (refused "cannot fire at this range with this gunnery factor").
- **Chaser modifiers (spec §4.3):** applied: `crew_quality`, `sections_firing`, `two_targets`, `plain_sail`,
  `wind_speed_4`, `anchored`, `dismasted`, `voluntary_reduction`. Never: `guns_dismounted`, `broadside_obscured`,
  `half_broadside`, `rake`, `initial_broadside`, `lower_deck_closed`, `dismantling_shot` (round shot only).
  `p.rake` is always `""` and `p.initial_broadside` false for a chase shot.
- **Gunnery test fixture** (as `test/unit/test_gunnery_calculator.gd`): wind speed 2, sea 1, firer crew D (+0),
  four sailor sections (±0), sail MS, so with no other modifier `mgn == bgn`. Firer bow (0, 0), facing 0, stern
  (−1, 0).
  - Target dead ahead at range 1: bow (2, 0), facing 0 (hexes (2, 0), (1, 0)); bow chaser BGN 3. The firer is
    also adjacent astern of the target's stern: a broadside there would be a stern rake (7.E.2b).
  - Target dead ahead at range 2: bow (3, 0), facing 0; BGN 2.
  - Target dead astern at range 2: bow (−3, 0), facing 0 (hexes (−3, 0), (−4, 0)); stern chaser BGN 2.
  - Target ahead at range 8: bow (9, 0), facing 0: refused.
- **Ship ids:** the 45 ids of the Task 1 table; aliases `frigate_38` → `br_38`, `frigate_32` → `br_32`,
  `ship_of_line_74` → `br_74`. Scenario ships keep the `ship_type` string they were written with.
- **Dice:** no new dice. With no chase order in a set, every existing resolution and dice order is unchanged.
- **Server authority:** no new request and no new ShipState field. View code (`scripts/ui`, `scripts/view`,
  `scripts/core`, `scripts/commands`) only reads; `test_server_authority.gd` must stay green.
- Use `Trace`, never `print()`.
- `make test` is green at the end of every task. An existing test may change its expected values only where the
  task says so, or (Tasks 4 and 5) where the change is caused by a chaser now being able to fire; each such change
  is listed in the commit message with the reason.
- The PostToolUse hook runs the full `make test` after edits under `scripts/server/`, `scripts/state/`,
  `scripts/core/`, `scripts/autoload/` and `test/unit/`.
- `docs/rules/feature_diff.md`, `CLAUDE.md`, the scenario-creator skill and the validator skill are updated in
  Task 8 only.
- **Commits:** every commit that adds a file also adds its `.uid` (run `make import` first). Plain separate git
  commands from the worktree. End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A transcription slip in `ships.json`** silently skews a type. Pinned by the validator (Task 1 Step 6, its
   broken-copy check), the spot tests of `test_data_manager_ships.gd` and the row-by-row scan check (Task 1 Step 7).
2. **Old scenarios and tests still load** through the aliases and keep their fallback names ("38-gun Frigate 1").
   Pinned by Task 1 `test_aliases_resolve_to_one_definition` and the unchanged
   `test_data_manager_scenarios.gd`.
3. **A chase order reaching a per-side array** (`guns_dismounted`, `initial_broadside_fired`, `obscured_penalty`,
   `lower_deck_modifier`) would crash or read port. Pinned by Task 4
   `test_chaser_ignores_dismounted_obscured_and_lower_deck` and `test_chase_shot_does_not_spend_initial_broadside`.
4. **Nothing changes for broadside-only fire:** dice order and numbers. Pinned by the unchanged
   `test_gunnery_resolver.gd` and Task 4 `test_broadside_sets_resolve_as_before`.
5. **The two-target limit across chasers and broadsides** (7.A.4, 7.C.12g). Pinned by Task 3
   `test_declaration_counts_chasers_as_targets` and Task 4 `test_chaser_at_second_target_takes_two_target_penalty`.

---

### Task 1: The ship types — data, aliases and the validator

**Files:**
- Modify: `data/rules/ships.json` (rewrite), `scripts/state/ship.gd`, `scripts/autoload/data_manager.gd`,
  `test/unit/test_data_manager_ships.gd`.
- Create: `.claude/skills/validate-rule-table/scripts/validate_ships.py`.

**Interfaces (Produces):**
- `ships.json`: one object per id below, keys in this order: `name`, `nationality`, `rating`, `year`, `class`,
  `maneuverability`, `speed_type`, `draft`, `ch_modifier`, `rigging_hp`, `hull_hp`, `crew_count`, `marine_count`,
  `gun_factors` (`{"lg", "mg", "cr"}`), `freeboard`, `lower_deck_modifier`, `point_costs`, then optional
  `aliases`, `armament`. A first key `"_doc"` (a string) says: source (SDC p.106, OBs), the id scheme, that costs
  hold only the chart's filled cells, and that `year` is the SDC's "Year Avail." (1794 for the OB ships). Keep the
  existing `armament` objects on `br_38` (from `frigate_38`) and `br_74` (from `ship_of_line_74`) unchanged.
  `aliases`: `br_38` `["frigate_38"]`, `br_32` `["frigate_32"]`, `br_74` `["ship_of_line_74"]`. Nationality from
  the prefix: `br` British, `fr` French, `sp` Spanish, `am` American. `speed_type` `L-f` → `"L/F"`; C-M `2b` →
  `"class": 2, "maneuverability": "B"`; `ch_modifier` `+1` → `1`. No `type`, `speed`, `crew_quality` keys.
- The rows (transcribed from the scan for this plan; Step 7 re-checks each against it):

| id | name | rate | year | C-M | ST | D | CH | rigging | hull | crew S1–S4:M | LG/MG/CR | F:LDGM | point_costs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `br_100` | 100-gun Ship of the Line | 100 | 1793 | 1A | L/F | 27 | +1 | 8 8 8 9 | 10 11 11 11 | 8 8 9 9:8 | 24/0/1 | 4:-3 | A3=135 B3=120 C3=108 C4=104 C5=102 D4=96 D5=94 |
| `br_98l` | 98-gun Ship of the Line (large) | 98L | 1797 | 1A | L/F | 26 | +1 | 8 8 8 8 | 10 10 11 11 | 7 8 8 8:7 | 23/0/1 | 3:-3 | A3=128 B3=114 C3=103 C4=99 C5=97 D4=91 D5=89 |
| `br_98` | 98-gun Ship of the Line | 98 | 1793 | 1A | L/S | 25 | 0 | 7 8 8 8 | 10 10 10 11 | 7 7 8 8:7 | 21/0/1 | 4:-4 | A3=118 B3=105 C3=95 C4=91 C5=89 D4=84 D5=82 |
| `br_80` | 80-gun Ship of the Line | 80 | 1794 | 2B | L/F | 24 | 0 | 7 8 8 8 | 10 10 10 10 | 7 7 7 8:7 | 20/0/3 | 4:-4 | A3=124 B3=110 C3=99 C4=96 C5=94 D4=88 D5=86 |
| `br_74l` | 74-gun Ship of the Line (large) | 74L | 1798 | 2B | L/F | 23 | 0 | 7 7 8 8 | 9 9 9 10 | 6 6 7 7:6 | 18/0/4 | 4:-4 | A3=116 B3=103 C3=93 C4=90 C5=88 D4=82 D5=80 |
| `br_74c` | 74-gun Ship of the Line (carronades) | 74c | 1798 | 2B | L/F | 22 | 0 | 7 7 7 7 | 8 8 9 9 | 6 6 6 6:5 | 16/0/4 | 4:-5 | A3=104 B3=93 C3=84 C4=81 C5=79 D4=75 D5=73 |
| `br_74` | 74-gun Ship of the Line | 74 | 1793 | 2B | L/F | 22 | 0 | 7 7 7 7 | 8 8 9 9 | 6 6 6 6:5 | 17/0/1 | 4:-5 | A3=99 B3=88 C3=79 C4=77 C5=75 D4=71 D5=69 |
| `br_64c` | 64-gun Ship of the Line (carronades) | 64c | 1798 | 2B | L/F | 21 | -1 | 6 6 6 7 | 7 7 7 8 | 5 5 5 5:4 | 12/0/3 | 4:-4 | A3=83 B3=74 C3=67 C4=65 C5=63 D4=59 D5=58 |
| `br_64` | 64-gun Ship of the Line | 64 | 1793 | 2B | L/F | 21 | -1 | 6 6 6 7 | 7 7 7 8 | 5 5 5 5:4 | 13/0/1 | 4:-4 | A3=78 B3=70 C3=63 C4=61 C5=59 D4=56 D5=55 |
| `br_50` | 50-gun Two-decker | 50 | 1793 | 2B | L/S | 20 | -1 | 5 5 6 6 | 6 6 6 7 | 3 3 4 4:3 | 9/0/1 | 4:-5 | A3=62 B3=55 C3=50 C4=48 C5=47 D4=44 D5=43 |
| `br_44rz` | 44-gun Razee | 44RZ | 1795 | 3B | F/F | 20 | -1 | 6 6 6 7 | 7 7 7 7 | 3 3 4 4:3 | 7/0/5 | 5:-6 | A3=71 B3=63 C3=57 C4=55 C5=54 D4=51 D5=50 |
| `br_40` | 40-gun Frigate | 40 | 1813 | 3C | F/F | 19 | -2 | 5 6 6 6 | 5 6 6 6 | 3 3 4 4:3 | 8/0/5 | 6:-7 | A3=67 B3=60 C3=54 C4=52 C5=51 D4=48 D5=47 |
| `br_38` | 38-gun Frigate | 38 | 1793 | 3C | F/F | 18 | -2 | 5 5 6 6 | 5 5 5 6 | 3 3 3 3:2 | 6/0/4 | 6:-7 | A3=54 B3=48 C3=43 C4=42 C5=41 D4=38 D5=36 |
| `br_36` | 36-gun Frigate | 36 | 1793 | 3C | F/F | 18 | -2 | 5 5 5 6 | 5 5 5 5 | 2 3 3 3:2 | 6/0/3 | 6:-7 | A3=49 B3=44 C3=40 C4=39 C5=38 D4=35 D5=34 |
| `br_32l` | 32-gun Frigate (large) | 32L | 1794 | 3C | F/S | 17 | -2 | 5 5 5 5 | 4 5 5 5 | 2 2 3 3:2 | 6/0/2 | 6:-7 | A3=46 B3=41 C3=37 C4=36 C5=35 D4=33 D5=32 |
| `br_32` | 32-gun Frigate | 32 | 1793 | 3C | F/S | 16 | -2 | 4 5 5 5 | 4 4 4 5 | 2 2 2 3:2 | 4/0/2 | 5:-7 | A3=37 B3=33 C3=30 C4=29 C5=28 D4=26 D5=25 |
| `fr_120` | 120-gun Ship of the Line | 120 | 1793 | 1A | L/F | 29 | +1 | 9 9 9 9 | 12 12 12 12 | 10 10 11 11:11 | 29/0/1 | 4:-4 | B3=154 C3=133 C4=127 C5=121 D4=111 D5=106 E4=96 E5=89 |
| `fr_110` | 110-gun Ship of the Line | 110 | 1793 | 1A | L/F | 28 | +1 | 8 8 9 9 | 11 11 11 11 | 10 10 10 10:10 | 27/0/1 | 4:-4 | B3=145 C3=125 C4=120 C5=114 D4=104 D5=100 E4=90 E5=84 |
| `fr_80c` | 80-gun Ship of the Line (carronades) | 80c | 1807 | 2A | L/F | 24 | 0 | 8 8 8 8 | 10 10 11 11 | 8 8 8 8:8 | 23/0/3 | 4:-5 | B3=128 C3=110 C4=105 C5=100 D4=92 D5=88 E4=80 E5=74 |
| `fr_80` | 80-gun Ship of the Line | 80 | 1793 | 2A | L/F | 24 | 0 | 8 8 8 8 | 10 10 11 11 | 8 8 8 8:8 | 24/0/1 | 4:-5 | B3=123 C3=106 C4=102 C5=97 D4=89 D5=85 E4=77 E5=71 |
| `fr_74l` | 74-gun Ship of the Line (large) | 74L | 1793 | 2B | L/F | 23 | 0 | 7 7 8 8 | 9 9 10 10 | 6 7 7 7:7 | 21/0/1 | 4:-5 | B3=109 C3=94 C4=90 C5=86 D4=78 D5=75 E4=68 E5=63 |
| `fr_74c` | 74-gun Ship of the Line (carronades) | 74c | 1807 | 2B | L/F | 22 | 0 | 7 7 7 8 | 9 9 9 9 | 6 6 7 7:7 | 18/0/3 | 4:-5 | B3=100 C3=86 C4=83 C5=79 D4=72 D5=69 E4=63 E5=58 |
| `fr_74` | 74-gun Ship of the Line | 74 | 1793 | 2B | L/F | 22 | 0 | 7 7 7 8 | 9 9 9 9 | 6 6 7 7:7 | 19/0/1 | 4:-5 | B3=97 C3=84 C4=80 C5=76 D4=70 D5=67 E4=61 E5=56 |
| `fr_50rz` | 50-gun Razee | 50RZ | 1793 | 3B | F/F | 21 | 0 | 7 7 7 7 | 8 8 8 8 | 4 5 5 5:5 | 14/0/1 | 5:-6 | B3=80 C3=69 C4=66 C5=63 D4=57 D5=55 E4=50 E5=46 |
| `fr_44` | 44-gun Frigate | 44 | 1794 | 3B | F/F | 20 | -1 | 6 7 7 7 | 6 7 7 7 | 4 4 5 5:4 | 10/0/1 | 6:-7 | B3=62 C3=54 C4=52 C5=49 D4=45 D5=43 E4=39 E5=36 |
| `fr_40c` | 40-gun Frigate (carronades) | 40c | 1807 | 3C | F/F | 18 | -2 | 5 5 6 6 | 5 5 5 6 | 3 3 4 4:3 | 6/0/3 | 6:-7 | B3=47 C3=42 C4=40 C5=38 D4=34 D5=33 E4=30 E5=28 |
| `fr_40` | 40-gun Frigate | 40 | 1793 | 3C | F/F | 18 | -2 | 5 5 6 6 | 5 5 5 6 | 3 3 4 4:3 | 7/0/1 | 6:-7 | B3=43 C3=37 C4=36 C5=34 D4=31 D5=30 E4=27 E5=25 |
| `fr_38` | 38-gun Frigate | 38 | 1793 | 3C | F/F | 18 | -2 | 5 5 5 6 | 5 5 5 5 | 3 3 3 4:3 | 6/0/1 | 5:-7 | B3=42 C3=36 C4=35 C5=33 D4=30 D5=29 E4=26 E5=24 |
| `fr_36` | 36-gun Frigate | 36 | 1793 | 3C | F/F | 16 | -2 | 5 5 5 5 | 4 4 5 5 | 2 3 3 3:3 | 4/0/1 | 5:-7 | B3=32 C3=27 C4=26 C5=25 D4=23 D5=22 E4=20 E5=18 |
| `sp_130` | 130-gun Ship of the Line | 130 | 1793 | 1A | L/S | 29 | +1 | 8 8 9 9 | 11 11 12 12 | 10 10 11 11:11 | 28/0/0 | 3:-3 | C3=125 C4=117 C5=110 D4=102 D5=96 E4=86 E5=77 |
| `sp_112` | 112-gun Ship of the Line | 112 | 1793 | 1A | L/S | 28 | +1 | 8 8 9 9 | 11 11 11 12 | 10 10 10 10:10 | 26/0/0 | 4:-3 | C3=118 C4=111 C5=105 D4=97 D5=92 E4=82 E5=73 |
| `sp_80l` | 80-gun Ship of the Line (large) | 80L | 1795 | 2B | L/S | 24 | 0 | 7 8 8 8 | 10 10 10 11 | 7 8 8 8:8 | 22/0/0 | 4:-4 | C3=100 C4=94 C5=89 D4=81 D5=77 E4=68 E5=61 |
| `sp_80` | 80-gun Ship of the Line | 80 | 1793 | 2B | L/S | 23 | 0 | 7 7 8 8 | 9 10 10 10 | 7 7 8 8:7 | 20/0/0 | 4:-5 | C3=94 C4=88 C5=83 D4=76 D5=72 E4=64 E5=57 |
| `sp_74` | 74-gun Ship of the Line | 74 | 1793 | 2B | L/S | 22 | 0 | 7 7 7 7 | 8 9 9 9 | 6 6 7 7:6 | 15/0/0 | 4:-4 | C3=74 C4=70 C5=66 D4=60 D5=57 E4=51 E5=45 |
| `sp_64` | 64-gun Ship of the Line | 64 | 1793 | 2B | L/S | 21 | -1 | 6 6 6 7 | 7 7 7 8 | 5 5 6 6:5 | 12/0/0 | 4:-5 | C3=60 C4=56 C5=53 D4=48 D5=46 E4=40 E5=37 |
| `sp_40` | 40-gun Frigate | 40 | 1793 | 3C | F/S | 18 | -2 | 5 5 6 6 | 5 5 6 6 | 3 3 4 4:3 | 7/0/0 | 6:-7 | C3=38 C4=36 C5=34 D4=31 D5=29 E4=26 E5=23 |
| `sp_34` | 34-gun Frigate | 34 | 1793 | 3C | F/S | 17 | -2 | 5 5 5 5 | 4 5 5 5 | 2 3 3 3:3 | 4/0/0 | 5:-8 | C3=25 C4=23 C5=22 D4=20 D5=19 E4=17 E5=15 |
| `am_44` | 44-gun Frigate | 44 | 1798 | 3B | F/F | 21 | -1 | 7 7 7 7 | 7 8 8 8 | 4 5 5 5:4 | 8/0/6 | 6:-7 | A3=79 B3=73 C3=68 C4=66 C5=65 D4=61 D5=60 |
| `am_38` | 38-gun Frigate | 38 | 1798 | 3C | F/F | 19 | -2 | 6 6 6 6 | 6 6 6 6 | 3 4 4 4:3 | 6/0/4 | 6:-7 | A3=56 B3=52 C3=48 C4=47 C5=46 D4=44 D5=43 |
| `am_36` | 36-gun Frigate | 36 | 1800 | 3C | F/F | 18 | -2 | 5 5 5 6 | 5 5 5 5 | 3 3 3 4:3 | 6/0/3 | 6:-7 | A3=49 B3=45 C3=42 C4=41 C5=40 D4=38 D5=37 |
| `am_32` | 32-gun Frigate | 32 | 1799 | 3C | F/F | 17 | -2 | 5 5 5 5 | 4 5 5 5 | 3 3 3 3:2 | 1/0/8 | 5:-7 | A3=51 B3=47 C3=44 C4=43 C5=42 D4=39 D5=38 |
| `br_44_diomede` | 44-gun Two-decker (Diomede) | 44 | 1794 | 2B | L/S | 19 | -2 | 4 5 5 5 | 5 5 6 6 | 2 3 3 3:2 | 4/3/0 | 3:-4 | D4=27 |
| `fr_20_babet` | 20-gun Corvette (Babet) | 20 | 1794 | 4D | C/S | 14 | -3 | 4 4 4 4 | 3 3 3 3 | 1 2 2 2:2 | 2/0/0 | 5:-7 | D4=12 |
| `fr_20_rosalie` | 20-gun Corvette (Rosalie) | 20 | 1794 | 4C | C/F | 14 | -3 | 4 4 4 4 | 3 3 3 3 | 1 2 2 2:2 | 2/0/0 | 5:-7 | D6=10 |
| `fr_14_coureur` | 14-gun Brig (Coureur) | 14 | 1794 | 4D | C/S | 12 | -4 | 2 3 3 3 | 2 2 2 2 | 1 1 1 2:2 | 1/0/0 | 5:-7 | D5=6 |

- `Ship`: add `var year: int = 0` (read `"year"`, written by `to_dict`); remove `type`, `speed` (vars,
  `from_dict`, `to_dict`) and `is_french_gunned()`.
- `DataManager`:
  - `var ship_type_aliases: Dictionary = {}` (alias → canonical id); `ship_definitions` holds canonical ids only.
  - `func canonical_ship_type(type_id: String) -> String` (the alias's target, else `type_id`).
  - `get_ship_definition(ship_id)` resolves `canonical_ship_type` first (the warning for an unknown id is kept).
  - `load_ship_definitions` skips keys starting with `_`, records each row's `aliases`, and `push_error`s an alias
    that names an existing id or another alias.
  - `assign_fallback_ship_names` looks the type name up through `get_ship_definition`'s alias resolution (without
    the unknown-id warning for unknown types: check `ship_definitions.has(canonical_ship_type(id))`).
  - `_create_default_ships` holds the same three rows under `br_38`, `br_32`, `br_74`, with their aliases, and the
    names "38-gun Frigate", "32-gun Frigate", "74-gun Ship of the Line" (the 74's old name was
    "74-gun Ship of the Line"; keep it).
- `validate_ships.py` (`python3 .claude/skills/validate-rule-table/scripts/validate_ships.py [--file PATH]
  [--rules-dir DIR]`, default `data/rules/ships.json`; header comment like `validate_combat.py`'s; exit 1 on any
  error, else prints `OK: 45 ship types`). Checks, each error naming the id:
  - `EXPECTED_IDS` = the 45 ids above, exactly (missing or extra is an error); `OB_IDS` = the last four.
  - Allowed keys: the 17 listed above plus `aliases`, `armament`; any other key is an error (catches leftover
    `type`, `speed`, `crew_quality`). `_doc` at top level is allowed.
  - `nationality` matches the id prefix; `name` non-empty; `rating` int 10–140; `year` int 1780–1815; `class`
    int 1–3 for SDC rows, 1–4 for OB rows; `maneuverability` one of `A B C D`; `speed_type` a key of
    `movement_allowance.json`; `draft` int 10–30; `ch_modifier` int −4…+1.
  - `rigging_hp`, `hull_hp`, `crew_count`: four ints ≥ 1, non-decreasing; `marine_count` int ≥ 1.
  - `gun_factors`: exactly `lg`, `mg`, `cr`, ints ≥ 0, sum > 0; `mg` > 0 only on `br_44_diomede`.
  - `freeboard` int 1–6; `lower_deck_modifier` int −8…−1.
  - `point_costs`: SDC rows: keys from `A3 B3 C3 C4 C5 D4 D5 E4 E5`, values ints, strictly decreasing in that
    column order; OB rows: exactly one key matching `^[A-G][2-6]$`, positive int.
  - Twins `br_74c/br_74`, `br_64c/br_64`, `fr_80c/fr_80`, `fr_74c/fr_74`, `fr_40c/fr_40`: equal `class`,
    `maneuverability`, `speed_type`, `draft`, `ch_modifier`, `rigging_hp`, `hull_hp`, `crew_count`,
    `marine_count`, `freeboard`, `lower_deck_modifier`.
  - Aliases: exactly `{"frigate_38": "br_38", "frigate_32": "br_32", "ship_of_line_74": "br_74"}`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_data_manager_ships.gd`:
  - `test_ship_definition_count`: `dm.ship_definitions.size() == 45`.
  - `test_expected_ship_ids_present` becomes: `dm.ship_definitions.has("br_38")`, `has("br_32")`, `has("br_74")`;
    `not has("frigate_38")` (aliases are not keys).
  - `test_aliases_resolve_to_one_definition`: `get_ship_definition("frigate_38") == get_ship_definition("br_38")`
    (same instance); likewise `frigate_32`/`br_32`, `ship_of_line_74`/`br_74`;
    `canonical_ship_type("ship_of_line_74") == "br_74"`; `canonical_ship_type("br_74") == "br_74"`.
  - Keep every existing `frigate_38` / `frigate_32` / `ship_of_line_74` property test (they now pass through the
    alias); delete `test_frigate_38_type` (the field is gone).
  - `test_spot_rows` (one assertion block per row, values from the table):
    - `fr_120`: `crew_count == [10, 10, 11, 11]`, `marine_count == 11`, `gun_factors == {"lg": 29, "mg": 0,
      "cr": 1}`, `not point_costs.has("A3")`, `point_costs["B3"] == 154`, `point_costs["E5"] == 89`;
    - `sp_34`: `lower_deck_modifier == -8`, `freeboard == 5`, `speed_type == "F/S"`;
    - `am_32`: `gun_factors == {"lg": 1, "mg": 0, "cr": 8}`;
    - `br_44_diomede`: `gun_factors["mg"] == 3`, `freeboard == 3`, `point_costs == {"D4": 27}`, `ship_class == 2`;
    - `fr_14_coureur`: `ship_class == 4`, `maneuverability == "D"`, `speed_type == "C/S"`, `crew_count == [1, 1,
      1, 2]`, `ch_modifier == -4`;
    - `fr_20_rosalie`: `point_costs == {"D6": 10}`, `speed_type == "C/F"`, `maneuverability == "C"`;
    - `br_40`: `year == 1813`; `br_100`: `year == 1793`, `ch_modifier == 1`.
  - `test_nationality_matches_prefix`: for every id, `{"br": "British", "fr": "French", "sp": "Spanish", "am":
    "American"}[id.left(2)] == def.nationality`.
  - `test_point_value_of_one_cell_row`: `fr_20_rosalie.point_value("D", 6) == 10.0`;
    `point_value("C", 3) == 10.0` (falls back to the lowest).
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail (45 ≠ 3, unknown ids).
- [ ] **Step 3: Implement** `Ship`, `DataManager` and the new `ships.json` per the Interfaces.
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green, including the unchanged
  `test_data_manager_scenarios.gd` (fallback names "38-gun Frigate 1", "32-gun Frigate 1") and every scenario
  test.
- [ ] **Step 5: Write `validate_ships.py`** per the Interfaces.
- [ ] **Step 6: Run the validators.**
  - `python3 .claude/skills/validate-rule-table/scripts/validate_ships.py` → `OK: 45 ship types`, exit 0.
  - Broken-copy check: copy `data/rules/ships.json` to the scratchpad, change `br_74`'s `hull_hp` to `[8, 9, 8, 9]`
    and `fr_80c`'s `draft` to `25`, run with `--file <copy>`: exit 1, errors naming `br_74` (non-decreasing) and
    `fr_80c` (twin mismatch). Delete the copy.
  - `python3 .claude/skills/validate-rule-table/scripts/validate.py` and `validate_combat.py` still pass.
- [ ] **Step 7: Scan check.** Read `docs/rules/images/ship-data-chart.jpg`, cropping it into bands so the digits
  are large (e.g. Python PIL from the scratchpad, or `swift .claude/skills/close-action-rules/scripts/render_pdf_page.swift
  docs/CoA_-_Close_Action_the_Age_of_Fighting_Sail_vol_1_1997.pdf 106 <scratchpad>/p106.png`), and compare every
  cell of every SDC row in `ships.json` with the scan; then the four OB rows with `sb-p08-1.png` (Babet) and
  `sb-p09-1.png` (Diomede, Coureur, Rosalie). Where the scan and this plan's table differ, the scan wins: fix the
  JSON and say so in the commit message.
- [ ] **Step 8: Commit.**

```bash
git add data/rules/ships.json scripts/state/ship.gd scripts/autoload/data_manager.gd test/unit/test_data_manager_ships.gd .claude/skills/validate-rule-table/scripts/validate_ships.py
git commit -m "feat: all 41 Ship Data Chart types and four OB ships, old ids as aliases, ships.json validator"
```

### Task 2: Medium guns, class 4 and lower-deck guns at every freeboard (tests)

**Files:**
- Create: `test/unit/test_ship_types.gd`, `test/unit/test_lower_deck_freeboards.gd`.
- Modify: only if a test below exposes a bug in a class-4 path; then the smallest fix, named in the commit message.

**Interfaces (Consumes):** Task 1's ids and `DataManager.get_ship_definition`. Build a ship from a definition as:
`var s := ShipState.new(); s.ship = DataManager.get_ship_definition(id)`, then set `ship_id`, side (through
`ships_by_side`), `hex_position`, `facing`, `sail_state = "MS"`, `crew_quality = "D"`, and copy
`rigging_current_hp`, `hull_current_hp`, `crew_count`, `marine_count` from the definition; register it in
`GameState.ships` / `ships_by_side` as `test_gunnery_calculator.gd` does (save and restore what you change).
Environment: wind direction 0, wind speed 2, sea 1 unless stated.

- [ ] **Step 1: Write the tests.**
  - `test_ship_types.gd`:
    - `test_diomede_medium_guns_by_range` (1.G.7, the Gunnery Factor chart): Diomede firer at bow (0, 0), facing 0;
      a `br_38` target of the other side parallel on the starboard beam, bow at `HexGrid.DIRECTIONS[1] * r`,
      facing 0; starboard full broadside, aim high:
      - r 6: `tgf == 7` (4 + 3 × ¾ = 6.25, rounded up once), `bgn == 12`, `can_fire`;
      - r 11: `tgf == 6` (4 + 1.5), `bgn == 3`;
      - r 13: `can_fire == false`, reason contains "cannot fire at this range" (MG out, TGF 4 grey).
    - `test_class_4_movement_tables`: `DataManager.get_movement_allowance("C/S", 2, "B", "ms", 4) == 7`;
      `("C/F", 2, "B", "ps", 4) == 10`; `DataManager.get_speed_change("acceleration", "D") == 3`;
      `("deceleration", "D") == 4`.
    - `test_class_4_table_rows`: `DataManager.combat_tables.drift_class_drm(4) == 2`; `prize_minimum(4) == 1`.
    - `test_one_box_sections_fire`: a `fr_14_coureur` firer (crew `[1, 1, 1, 2]`) with a `br_32` target on her
      starboard beam at range 2; `GameState.ship_controller.remove_crew_box_from(id, 0) == 0` (section emptied);
      `sections_able_to_fire() == 3`; the preview's `sections_firing` modifier is −3; its `tgf == 1`.
    - `test_corvette_point_values`: `fr_20_babet.point_value("D", 4) == 12.0`; `fr_14_coureur.point_value("D", 5)
      == 6.0`.
  - `test_lower_deck_freeboards.gd` (7.F.2), with `FireRules.lower_deck_modifier(ship, side, sea, 0)` on a ship
    facing 1 (wind from 0: WF=C, starboard leeward):
    - `test_every_freeboard_against_every_sea`: for each `[id, freeboard, ldgm]` in `[["br_44_diomede", 3, -4],
      ["br_98l", 3, -3], ["br_74", 4, -5], ["br_32", 5, -7], ["sp_34", 5, -8], ["br_38", 6, -7]]` and sea 0–5:
      starboard is `ldgm` when `sea > 0 and sea >= freeboard`, else 0; port is `ldgm` when `sea > freeboard`,
      else 0. Assert the definition's `freeboard` and `lower_deck_modifier` equal the listed ones first.
    - `test_diomede_sea_three_preview` (Scenario 2 V.D): sea 3, Diomede at bow (0, 0) facing 1 (stern (0, −1)), a
      `br_38` target parallel on her starboard beam at range 3 (bow (−3, 3), facing 1); the starboard full
      broadside preview has modifier `lower_deck_closed` == −4; at sea 2 the same preview has no
      `lower_deck_closed` modifier.
- [ ] **Step 2: Run.** `make import && make test`. Expected: green (no code change is expected). A failing class-4
  test is a bug: find it (invoke `superpowers:systematic-debugging`), fix it minimally, keep the test.
- [ ] **Step 3: Commit.**

```bash
git add test/unit/test_ship_types.gd test/unit/test_ship_types.gd.uid test/unit/test_lower_deck_freeboards.gd test/unit/test_lower_deck_freeboards.gd.uid
git commit -m "test: medium guns (Diomede), class 4 tables and one-box sections, lower-deck guns at every freeboard"
```

### Task 3: Chase arcs and declaration rules (pure)

**Files:**
- Modify: `scripts/core/fire_geometry.gd`, `scripts/server/gunnery_types.gd`, `scripts/server/fire_rules.gd`.
- Test: `test/unit/test_fire_geometry.gd`, `test/unit/test_fire_rules.gd`.

**Interfaces (Produces):**
- `FireGeometry`:
  - `const ARC_AHEAD := 2`, `const ARC_ASTERN := 3`, `const CHASE_HALF_ARC_DEG := 30.0`.
  - `func chase_arc(from_hex: Vector2i, facing: int, to_hex: Vector2i) -> int`: −1 for `from_hex == to_hex`; the
    angle θ as `bearing_side` computes it; `ARC_AHEAD` when θ ≤ 30 + `EPSILON_DEG`, `ARC_ASTERN` when θ ≥ 150 −
    `EPSILON_DEG`, else −1.
  - `in_battery_arc(battery_hex, facing, side, hex)`: for `side` 2 or 3, `chase_arc(...) == side` and within
    `MAX_RANGE`; 0 and 1 as before. `battery_bears`, `blocking_hexes`, `broadside_hexes` reach it unchanged, so
    they accept 2 and 3; update their doc comments ("`side`: a broadside, or `ARC_AHEAD`/`ARC_ASTERN`").
  - `bearing_side`, `rake_type_ships`, `relative_side` unchanged.
- `GunneryTypes`: `const BATTERY_CHASE := "chase"`, `const CHASE_BOW := 2`, `const CHASE_STERN := 3`,
  `const CHASE_SIDES: Array[int] = [CHASE_BOW, CHASE_STERN]`, `static func is_chase_side(side: int) -> bool`,
  `static func is_known_battery(battery: String) -> bool` (`BATTERIES` or `BATTERY_CHASE`). `BATTERIES` is
  unchanged (broadside batteries only). `FireOrder.battery` comment lists `"chase"`.
- `FireRules`:
  - `const CHASE_GUN_FACTORS := {"lg": 1, "mg": 0, "cr": 0}` with a comment: house rule, register §5.
  - `static func chase_mismatch(side: int, battery: String) -> bool`: true when exactly one of
    `GunneryTypes.is_chase_side(side)` and `battery == BATTERY_CHASE` holds.
  - `declaration_error`: `unknown battery` uses `is_known_battery`; then `chase_mismatch` → `"a chaser fires only
    from its own end (side %d, battery %s)"`; the bow/stern "declare a full broadside" check runs only for
    `"bow"`/`"stern"`; "battery fired twice" and "more than two targets" unchanged (they now count chasers).
  - `make_order(...)`: for `battery == BATTERY_CHASE` the ammunition is always round (want_dismantling ignored).
  - `battery_rank`: full 0, bow/stern 1, chase 2.

- [ ] **Step 1: Write the failing tests.**
  - `test_fire_geometry.gd`:
    - `test_chase_arc_ahead_and_astern`: from (0, 0) facing 0: (1, 0), (2, 0), (2, −1), (1, 1) → `ARC_AHEAD`
      ((2, −1) and (1, 1) lie at 30°, the boundary); (1, −1), (0, 1) (60°) → −1; (3, −2) (≈ 40.9°) → −1;
      (−1, 0), (−2, 1) (150°) → `ARC_ASTERN`; (−1, −1) (120°) → −1; (0, 0) → −1.
    - `test_chase_arc_turns_with_facing`: for every facing f, `chase_arc((0,0), f, DIRECTIONS[f])` is `ARC_AHEAD`
      and `chase_arc((0,0), f, DIRECTIONS[(f + 3) % 6])` is `ARC_ASTERN`.
    - `test_in_battery_arc_for_chase_arcs`: `in_battery_arc((0,0), 0, 2, (15, 0))` true, `(16, 0)` false;
      `in_battery_arc((0,0), 0, 2, (0, 1))` false; `bearing_side((0,0), 0, (2, 0)) == -1` (unchanged).
    - `test_battery_bears_for_chaser_needs_line_of_sight`: target hexes `[(3, 0), (2, 0)]`, `occupied = {(1, 0):
      "x"}`: `battery_bears((0,0), 0, 2, target, occupied)` false; with `{}` true.
    - `test_chase_arc_hexes`: `broadside_hexes((0,0), 0, 2, 2)` is exactly `[(1, 0), (2, −1), (2, 0), (1, 1)]` in
      any order; `broadside_hexes((0,0), 0, 3, 1) == [(−1, 0)]`.
    - `test_chase_constants_agree`: `GunneryTypes.CHASE_BOW == FireGeometry.ARC_AHEAD`,
      `GunneryTypes.CHASE_STERN == FireGeometry.ARC_ASTERN`.
  - `test_fire_rules.gd` (orders built with `FireRules.make_order`):
    - `test_chase_mismatch_is_a_declaration_error`: side 2 with battery `"bow"`, and side 0 with battery
      `"chase"`, each alone → error containing "own end"; side 2 `"chase"` → `""`; battery `"bogus"` →
      "unknown battery".
    - `test_each_chaser_fires_once`: two side-2 chase orders at different targets → "battery fired twice"; one
      side-2 and one side-3 order → `""`.
    - `test_declaration_counts_chasers_as_targets`: starboard full at A, port full at B, side-2 chase at C →
      "more than two targets"; chase at A instead → `""`.
    - `test_make_order_chaser_fires_round_shot`: `make_order("s", 2, "t", "chase", false, true, 3).ammo ==
      "round"`; aim forced high at range 10.
    - `test_battery_rank_of_chaser`: `battery_rank("chase") == 2`, full 0, bow 1.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run and confirm everything passes.** `make test`.
- [ ] **Step 5: Commit.**

```bash
git add scripts/core/fire_geometry.gd scripts/server/gunnery_types.gd scripts/server/fire_rules.gd test/unit/test_fire_geometry.gd test/unit/test_fire_rules.gd
git commit -m "feat: chase arcs ahead and astern, chase orders in the declaration rules (house rule)"
```

### Task 4: Chasers fire — calculator, resolver, events

**Files:**
- Modify: `scripts/server/gunnery_calculator.gd`, `scripts/server/gunnery_resolver.gd`,
  `scripts/server/phase_events.gd`.
- Test: `test/unit/test_gunnery_calculator.gd`, `test/unit/test_gunnery_resolver.gd`,
  `test/unit/test_phase_events.gd`, `test/unit/test_player_view.gd` (the existing PlayerView test file; find it
  with `grep -l "events_for" test/unit`), `test/unit/test_victory_controller.gd` (find with
  `grep -l can_move_or_fight test/unit`).
- Existing tests that will need adjusting (spec §4.5 "Adjacent ships"): `test/unit/test_marine_fire.gd`
  (`test_orientation_does_not_matter`, `test_combat_not_skipped_for_a_marine_shot_alone`),
  `test/unit/test_boarding.gd` (`test_combat_runs_boarding_alone_with_no_shot`), and any other the full run shows.

**Interfaces:**
- Consumes: Task 3's constants, `chase_arc`, `FireRules.CHASE_GUN_FACTORS`, `chase_mismatch`.
- Produces:
  - `GunneryCalculator.preview(order, two_targets, initial_broadside_allowed)` accepts sides 0–3. For a chase
    order (spec §4.3):
    - `order.side` outside 0–3 → "invalid broadside"; `chase_mismatch` → "a chaser fires only from its own end";
      `order.ammo == "dismantling"` → "chasers fire round shot only";
    - battery hexes: `[bow]` for `CHASE_BOW`, `[stern]` for `CHASE_STERN`;
    - arc refusal "target is not in the bow chaser's arc" / "…stern chaser's arc";
    - LOS and friendly blocking hexes through `battery_blocking_hexes(battery_hex, firer, order.side, friends)` as
      for a battery;
    - TGF from `FireRules.CHASE_GUN_FACTORS`; `p.batteries = 1`;
    - modifiers per Global Constraints; `p.rake = ""`, `p.initial_broadside = false`.
  - `GunneryCalculator.eligible_shots(ship_id)`: after the broadside loop, for each target and each side in
    `GunneryTypes.CHASE_SIDES`, a chase-battery preview that can fire (aim high when `high_only`).
  - `GunneryResolver`: `BATTERY_RANK` gains `"chase": 3`; `_resolve_shot` calls `set_initial_broadside_fired`
    only when `not GunneryTypes.is_chase_side(order.side)`.
  - `PhaseEvents.CHASE_NAMES := {2: "bow chaser", 3: "stern chaser"}`; `_fire_text` names a chase side with it
    ("HMS A fires bow chaser at B, range 2, low, roundshot — …") and adds no " battery" word for `"chase"`.

- [ ] **Step 1: Write the failing tests** (geometry and modifiers from Global Constraints).
  - `test_gunnery_calculator.gd`:
    - `test_bow_chaser_dead_ahead`: target at range 1 ahead; side-2 chase order: `can_fire`, `tgf == 1`,
      `bgn == 3`, `mgn == 3`, `batteries == 1`, `rake == ""`, no `rake`, `initial_broadside` or `half_broadside`
      modifier (the same geometry with a broadside would be a stern rake).
    - `test_stern_chaser_dead_astern`: target at range 2 astern; side-3 order: `bgn == 2`; a side-2 order at it →
      reason contains "bow chaser's arc".
    - `test_chaser_reach_ends_at_seven`: ahead at range 8 → `can_fire == false`, reason contains "cannot fire at
      this range"; ahead at range 2 → `bgn == 2`.
    - `test_chaser_refuses_dismantling_and_mismatch`: side 2 with ammo `"dismantling"` → "round shot only";
      side 2 battery `"bow"` → "own end"; side 5 → "invalid broadside".
    - `test_chaser_ignores_dismounted_obscured_and_lower_deck`: firer `guns_dismounted = [9, 9]`, a
      `broadside_obscured` critical effect on both sides (as the existing obscured test sets one), `freeboard 3`,
      `lower_deck_modifier -5`, sea 5: the chase preview has none of `guns_dismounted`, `broadside_obscured`,
      `lower_deck_closed`, and `mgn == 3` at range 1 ahead.
    - `test_chaser_takes_ship_wide_modifiers`: crew B → `crew_quality` +4; one sailor section plotted
      (`plotted_sections = [0]`) → `sections_firing` −3; all four plotted → reason "no sailor sections able to
      fire"; `sail_state = "PS"` → `plain_sail` present.
    - `test_chaser_blocked_by_ship_between`: target ahead at range 2 with a third ship's hex on (1, 0) (a ship of
      either side at bow (1, 0) facing 2) → `can_fire == false`.
    - `test_eligible_shots_include_chasers`: target ahead at range 2 only: `eligible_shots("firer")` has exactly
      one shot, side 2, battery `"chase"`; with the existing starboard target (`_n(1)`) also present, the
      broadside shots come first and the chase shot is still listed.
    - `test_chaser_at_second_target_takes_two_target_penalty`: orders `[starboard full at "target", side-2 chase at
      "ahead"]` through `preview_orders`: both carry `two_targets` −12; chase alone at "ahead" → no `two_targets`.
  - `test_gunnery_resolver.gd` (its fixture and `ScriptedDice`):
    - `test_chase_shot_does_not_spend_initial_broadside`: resolve one side-2 chase order (d6 queued); afterwards
      `initial_broadside_fired == [false, false]`; one FIRE event with `data.side == 2`, `data.battery ==
      "chase"`, `data.rake == ""`.
    - `test_broadside_sets_resolve_as_before`: an existing two-shot broadside set gives the same events and dice
      consumption as before this task (assert the FIRE events' `fgn` and the dice left, copying an existing
      test's set and expectations).
  - `test_phase_events.gd`: `test_fire_text_names_the_chaser`: a FIRE event with `{"side": 2, "battery": "chase",
    "range": 2, "aim": "low", "ammo": "round", "bgn": 2, "modifiers": [], "mgn": 2, "d6": 3, "fgn": 5}` reads
    containing "fires bow chaser at" and not "battery"; side 3 → "stern chaser".
  - PlayerView test file: `test_chase_fire_hides_target_hits`: with limited information on, a side-2 FIRE event
    against a ship the reader does not command has no `rigging`, `hull`, `crew` in `events_for`.
  - Victory test file: `test_chasers_do_not_keep_a_ship_in_the_fight`: a dismasted ship (`rigging_current_hp` all
    0) with `guns_dismounted` equal to her gun factor total on both sides → `can_move_or_fight == false`.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run the whole suite and adjust only what chasers changed.** `make test`. For each failure:
  - a test that needs "no gun shot" between adjacent ships (the three named above): keep its geometry and
    silence the guns by putting every sailor section of both ships on a task (`plotted_sections = [0, 1, 2, 3]`
    set directly on the fixture ships, or the fixture's own task helper), and change the "no broadside bears"
    message to "no gun bears (every section busy)". `test_orientation_does_not_matter` asserts instead that
    `eligible_shots("a_ship")` holds only a chase shot (side 2).
  - a test whose ships now get a chase shot and whose scripted dice or HOLD_FIRE lines shift: give it the extra
    die or line, keeping its intent.
  - anything else is a bug in this task: fix the code, not the test.
  Name each adjusted test and the reason in the commit message.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/gunnery_calculator.gd scripts/server/gunnery_resolver.gd scripts/server/phase_events.gd test/unit/
git commit -m "feat: chasers fire - one long-gun factor ahead and astern, no rake or broadside effects (house rule)"
```

### Task 5: The stub AI fires its chasers

**Files:**
- Modify: `scripts/server/stub_ai.gd` (`choose_fire_orders` and its doc comment).
- Test: `test/unit/test_stub_ai.gd`.

**Interfaces:**
- Consumes: Task 4's chase shots in `eligible_shots`.
- Produces: `choose_fire_orders(player_id := -1) -> Array[Dictionary]` unchanged in signature. After the
  port × starboard loop, when `best.is_empty()`, the same loop runs over `_side_offers(shots, CHASE_BOW,
  ordered)` × `_side_offers(shots, CHASE_STERN, ordered)` with `_evaluate_orders` and `_candidate_beats` (spec §5).
  `_score_position` and `_bearing_batteries` unchanged.

- [ ] **Step 1: Write the failing tests** (the file's fixture: AI ship `"ai1"` of player 1 at (0, 0), facing 0,
  crew B, so a chaser's `mgn` is its BGN + 4):
  - `test_ai_fires_bow_chaser_when_no_broadside_bears`: enemy `"ahead"` (player 0) at bow (3, 0), facing 0 (range
    2): exactly one order, `side == 2`, `battery == "chase"`, `target_id == "ahead"`, `aim == "low"`,
    `ammo == "round"`.
  - `test_ai_prefers_broadside_to_chaser`: the same plus an enemy on the starboard beam at range 2
    (`_starboard_hex(Vector2i.ZERO, 0, 2)`, facing 0): one order, `side == ShipState.STARBOARD`; no order has
    `battery == "chase"`.
  - `test_ai_picks_one_chaser_between_two_targets`: enemies `"ahead"` (bow (3, 0), facing 0) and `"astern"` (bow
    (−3, 0), facing 0), both at range 2: one order (two targets at −12 leave mgn < 1), side 2 at `"ahead"` (equal
    mgn and range; `"ahead" < "astern"`).
  - `test_ai_fires_stern_chaser`: only `"astern"`: one order, side 3.
  - `test_submitted_chase_orders_validate`: `GameState.gunnery_calculator.validate_orders(1, _typed(orders)) ==
    ""` for the first test's orders.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the whole suite.** `make test`. AI and whole-game tests whose AI ships now fire a chaser
  (extra FIRE events, dice) are adjusted as in Task 4 Step 4, keeping their intent; list them in the commit
  message.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/stub_ai.gd test/unit/
git commit -m "feat: the stub AI fires its chasers when no broadside bears"
```

### Task 6: Fire panel chaser rows and arcs on the map (view)

**Files:**
- Modify: `scripts/ui/fire_declaration_panel.gd`, `scripts/core/game_controller.gd` (`_refresh_fire_overlay`,
  `battery_arc`), `scripts/view/broadside_colors.gd`.
- Test: `test/unit/test_fire_declaration_panel.gd`.

**Interfaces (Produces)** (spec §6; statics unless stated):
- `const ALL_SIDES: Array[int] = [ShipState.PORT, ShipState.STARBOARD, GunneryTypes.CHASE_BOW,
  GunneryTypes.CHASE_STERN]`; `SIDE_NAMES` becomes a Dictionary `{0: "Port", 1: "Starboard", 2: "Bow chaser",
  3: "Stern chaser"}` (update every reader); `BATTERY_LABELS["chase"] = "Chaser"`;
  `const CHASE_AMMO_NOTE := "Chasers fire round shot only"`.
- Chase side state: `{"bow": target_id_or_empty, "stern": "", "want_high", "want_dismantling": false,
  "reductions"}`; the chaser's target is always under `"bow"`.
- `battery_options(previews)`: broadside batteries in `BATTERIES` order, then `"chase"`.
- `row_chosen(bow, stern, target_id, "chase")`: `bow == target_id`.
- `choose_battery(state, target_id, "chase")`: toggles `"bow"` between `target_id` and `""`; `"stern"` stays `""`.
- `panel_orders(ship_id, sides, ranges)`: for a chase side the shot from `side_shots(state["bow"], "")` is made
  with battery `GunneryTypes.BATTERY_CHASE` through `FireRules.make_order` (round shot).
- `default_side(ranked_by_side) -> int`: the best broadside side as now; a chase side only when no broadside side
  has a row.
- `fire_button_text(full_count: int, half_count: int = 0, chase_count: int = 0) -> String`: parts "%d
  broadside(s)", "%d half broadside(s)", "%d chaser(s)" joined with " and "; `fire_button_text_for(orders)`
  counts `"chase"` orders as chasers.
- The panel builds and refreshes `ALL_SIDES` (`_add_ship`, `_refresh_ship`, `get_all_orders` paths); a chase
  block has no ammunition choice (the toggle disabled, its note `CHASE_AMMO_NOTE`), and its breakdown line for a
  holding chaser reads "This chaser holds fire.".
- `GameController.battery_arc(geometry, ship_state, side, batteries)`: for a chase side the battery hex is the
  bow for `CHASE_BOW` and the stern for `CHASE_STERN`, whatever `batteries` holds. `_refresh_fire_overlay` loops
  `FirePanel.ALL_SIDES` (or the same four values).
- `BroadsideColors.CHASE := Color(0.35, 0.7, 1.0)`; `color(side)` returns it for 2 and 3.

- [ ] **Step 1: Write the failing tests** in `test_fire_declaration_panel.gd` (static functions; build
  `ShotPreview`s as the file's `_preview` helper does, setting `order.side` and `order.battery`):
  - `test_options_group_chasers_by_side`: chase previews for side 2 at "a" and side 3 at "b" → `options_by_target`
    keys include 2 and 3; `battery_options` of a target with a full, a bow and a chase preview →
    `["full", "bow", "chase"]`.
  - `test_choose_and_row_chosen_for_chaser`: `choose_battery({"bow": "", "stern": ""}, "a", "chase") == {"bow":
    "a", "stern": ""}`; again → `{"bow": "", "stern": ""}`; `row_chosen("a", "", "a", "chase")` true.
  - `test_panel_orders_for_chasers`: sides `{1: {"bow": "x", "stern": "x", …}, 2: {"bow": "y", "stern": "",
    "want_dismantling": true, …}}`, ranges `{"x": 3, "y": 2}` → two orders: side 1 `"full"`, side 2 `"chase"` with
    ammo `"round"`.
  - `test_default_side_prefers_broadside`: `{2: [row mgn 9], 1: [row mgn 3]}` → 1; `{3: [row mgn 2]}` → 3.
  - `test_fire_button_counts_chasers`: `fire_button_text(1, 0, 1) == "Fire 1 broadside and 1 chaser"`;
    `fire_button_text(0, 0, 2) == "Fire 2 chasers"`; `fire_button_text(0) == "Hold all fire"`.
  - `test_chase_arc_drawn_from_its_end`: `GameController.battery_arc(FireGeometry.new(HexGrid.new()), ship at bow
    (0, 0) facing 0, GunneryTypes.CHASE_STERN, ["bow"])` contains (−2, 0) and not (1, 0); with `CHASE_BOW` it
    contains (2, 0) and not (−2, 0); neither contains the ship's own hexes.
  - `test_chase_colour`: `BroadsideColors.color(2) == BroadsideColors.CHASE`, `color(3)` too, `color(1)` stays
    `STARBOARD`.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** `make test` green (existing panel tests unchanged except where `SIDE_NAMES` indexing moved
  to the dictionary). Then a live check with the godot-mcp tools (CLAUDE.md "Tooling"): `make play` scenario with
  an enemy dead ahead (Developer UI or `test_basic`), open the fire panel in COMBAT_RESOLUTION, confirm the
  "Bow chaser" block, its arc on the map and `game_get_errors` returning zero.
- [ ] **Step 5: Commit.**

```bash
git add scripts/ui/fire_declaration_panel.gd scripts/core/game_controller.gd scripts/view/broadside_colors.gd test/unit/test_fire_declaration_panel.gd
git commit -m "feat: fire panel chaser rows and chase arcs on the map"
```

### Task 7: Ship card chasers, procedural models and deck drawings (view)

**Files:**
- Modify: `scripts/ui/crew_overlay/crew_overlay_text.gd` (`gun_rows`, `guns_readout`),
  `scripts/ui/ship_card_status.gd` (chase row tooltip), `scripts/view/procedural_ship_spec.gd`,
  `scripts/ui/crew_overlay/deck_layouts.gd`, `scripts/ui/crew_overlay/crew_overlay.gd`,
  `scripts/ui/crew_overlay/crew_overlay_footer.gd`, `data/ui/deck_layouts.json`.
- Test: `test/unit/test_crew_overlay.gd`, `test/unit/test_procedural_ship.gd`.

**Interfaces (Produces):**
- `CrewOverlayText.gun_rows(ship, env)` returns four rows: Port, Starboard as now, then `{"side": "Bow chase",
  "lg": 1, "mg": 0, "cr": 0, "dismounted": 0, "lower_deck": 0, "status": "ready"}` and the same with "Stern chase"
  (factors from `FireRules.CHASE_GUN_FACTORS`).
- `guns_readout`'s `why` text: "Gunfire modifier for sections firing, on both broadsides and the chasers."; the no-
  section text: "No sailor section is left at the guns: no gun can fire."
- `ship_card_status.gd`: a chase row's tooltip "%s: 1 long gun factor (house rule: never dismounted, lower deck
  immaterial)".
- `ProceduralShipSpec.for_ship`: `gun_decks` = `{1: 3, 2: 2, 3: 1, 4: 1}[class]` (unknown class: 1); `masts` = 2
  for class 4, else 3; `ports_per_side` formula unchanged.
- `CrewDeckLayouts.layout_for(ship_type: String, ship_class: int = 0) -> Dictionary`: the `ship_types` entry, else
  `classes[str(ship_class)]`, else `default_layout`. `deck_layouts.json` gains `"classes": {"1": "sol74", "2":
  "sol74"}` and a `_doc` sentence for it. Both callers pass `ship.ship.ship_class` (0 when `ship.ship` is null).

- [ ] **Step 1: Write the failing tests.**
  - `test_crew_overlay.gd`: `test_gun_rows_per_side_with_dismounted_guns` now expects `rows.size() == 4`;
    new `test_gun_rows_list_the_chasers`: with `guns_dismounted = [9, 9]` and a shut lower deck (sea 5,
    freeboard 4), rows 2 and 3 are exactly the chase dictionaries above; update the existing `why` assertion to
    the new text.
  - `test_procedural_ship.gd`: `test_small_ship_has_two_masts` now `_ship(18, 4)` → 2 and `_ship(20, 4)` → 2
    (class, not rating); new `test_decks_follow_class`: `_ship(50, 2).gun_decks == 2`, `_ship(44, 2) == 2`,
    `_ship(44, 3) == 1`, `_ship(100, 1) == 3`, `_ship(20, 4) == 1`, and `_ship(20, 3).masts == 3`.
  - `test_crew_overlay.gd` (or the file that tests `CrewDeckLayouts`): `layout_for("br_64", 2)` is the sol74
    layout (compare with `layout_for("ship_of_line_74")`); `layout_for("fr_38", 3)` the frigate layout;
    `layout_for("frigate_38", 0)` unchanged.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** `make test` green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/ui/crew_overlay/crew_overlay_text.gd scripts/ui/ship_card_status.gd scripts/view/procedural_ship_spec.gd scripts/ui/crew_overlay/deck_layouts.gd scripts/ui/crew_overlay/crew_overlay.gd scripts/ui/crew_overlay/crew_overlay_footer.gd data/ui/deck_layouts.json test/unit/test_crew_overlay.gd test/unit/test_procedural_ship.gd
git commit -m "feat: chasers on the ship card, deck count and brig rig by class, deck drawings by class"
```

### Task 8: Test scenario and the docs

**Files:**
- Create: `data/scenarios/test_ships_and_guns.json`, `test/unit/test_ships_and_guns_scenario.gd`.
- Modify: `docs/rules/feature_diff.md`, `CLAUDE.md`, `.claude/skills/scenario-creator/SKILL.md`,
  `.claude/skills/validate-rule-table/SKILL.md`.

**Interfaces:**
- **`test_ships_and_guns.json`** (schema: `.claude/skills/scenario-creator/SKILL.md`): 40 × 30 board, all edges
  open; wind from the north-west (direction 4), speed 2, steady (so ships facing 0 have their starboard to
  leeward and ships facing 3 their port; none is head to wind); `sea_state` 3; `turn_limit` 15; `navies`
  `{"0": "British", "1": "French"}`.
  - Side 0: `br_100` "HMS Royal Sovereign" bow (12, 14) f0 MS; `br_44_diomede` "HMS Diomede" bow (12, 18) f0 MS;
    `br_38` "HMS Arethusa" bow (12, 10) f0 MS. All CQ C, MR 4.
  - Side 1: `fr_80` "Tonnant" bow (26, 14) f3 MS; `fr_20_babet` "Babet" bow (17, 10) f0 MS (hexes (17, 10),
    (16, 10): range 4 dead ahead of Arethusa's bow, so Arethusa's bow chaser and Babet's stern chaser bear at the
    start); `fr_14_coureur` "Coureur" bow (26, 18) f3 MS.
    All CQ D, MR 4 (Coureur MR 5).
  - No overlaps; everything in bounds.

- [ ] **Step 1: Write the failing tests** in `test_ships_and_guns_scenario.gd` (whole-loop driving as
  `test_battle_to_victory.gd` / `test_towing_scenario.gd`, every player AI):
  - `test_scenario_places_cleanly`: `placement_errors().is_empty()`; for Diomede,
    `FireRules.lower_deck_modifier(diomede, ShipState.STARBOARD, 3, 4) == -4` and the port value is 0 (sea =
    freeboard 3: the leeward lower deck only); `gunnery_calculator.eligible_shots` of Arethusa holds a side-2 shot
    at Babet, and Babet's holds a side-3 shot at Arethusa.
  - `test_scenario_plays_to_the_end_cleanly`: play to game over or 15 turns with no `push_error`; at least one FIRE
    event in the run has `battery == "chase"`, or document in the test (with the turn logs) why none was fired and
    assert what the run shows.
  - The existing `test_every_scenario_places_cleanly` covers the new file.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Write the scenario file.** Run `make test` green.
- [ ] **Step 4: Update `.claude/skills/scenario-creator/SKILL.md`:** the `ship_type` list (the 45 ids, grouped by
  navy, with their names), that `frigate_38`, `frigate_32`, `ship_of_line_74` are aliases of `br_38`, `br_32`,
  `br_74`, that a type's nationality is its builder and `navy`/`navies` its user (French BGNs at 11–15 follow the
  user), that a scenario ship's `id` (e.g. `br_74` in the towing example) is a ship id, not a type, and that a
  CQ/MR missing from the type's costs scores at the nearest MR, else the lowest cost.
- [ ] **Step 5: Update `.claude/skills/validate-rule-table/SKILL.md`:** `validate_ships.py` (what it checks, how to
  run it, that ships.json rows are checked against the SDC scan p.106 and the OB scans).
- [ ] **Step 6: Update `docs/rules/feature_diff.md`** (invoke `close-action-rules` for the conventions):
  - Header "Compared against": add this sub-project with `git rev-parse --short HEAD`.
  - §2.1: remove the "Medium guns, chase guns, class 4 ships | 1.G.7" row.
  - §5 rows ✔ (code locations): the Ship Data Chart (all 41 types, 1.G.1–11: `data/rules/ships.json`,
    `validate_ships.py`); medium guns (1.G.7, Gunnery Factor chart: `gunnery_calculator.gd` (`preview`),
    `br_44_diomede`); class 4 (1.G.2a, 1.G.10–11: three OB corvettes and brigs); add to the existing lower-deck row
    that every freeboard 3–6 is covered (`test_lower_deck_freeboards.gd`).
  - §4 bullets:
    - **Simple chasers (house rule, register §5, U)**: one long-gun factor at each end of every ship; arcs ±30°
      dead ahead of the bow hex and astern of the stern hex to range 15, reach limited to 7 by the BGN chart's
      TGF-1 row; round shot only; no initial broadside, rake (no bonus, no crew doubling, no raked MC), half
      broadside, broadside obscured, guns dismounted or lower deck; crew quality, sections firing, two targets,
      plain sail, WS 4, anchored, dismasted and reduction apply; one of the ≤ 2 targets; never dismounted and not
      counted for "able to fight" (2.A.1); the rake geometry is unchanged; the AI fires them only when no broadside
      bears (`fire_geometry.gd` (`chase_arc`), `fire_rules.gd`, `gunnery_calculator.gd`, `stub_ai.gd`).
    - **Ship types, not per-scenario data**: OB ships that differ from their SDC type are not modelled (Flora's
      `6 0`, Africaine's freeboard 5, F-vs ships); odd ships are their own types (Diomede, Babet, Rosalie,
      Coureur; year 1794); the SDC tournament speed changes are not offered.
    - **Costs** by the builder's row; a missing CQ/MR cell scores at the nearest MR, else the lowest cost.
- [ ] **Step 7: Update `CLAUDE.md`:**
  - **Ship Definitions**: replace the three-id sentence with the 45 nation-prefixed ids (scheme, the four OB ids),
    the aliases (`DataManager.ship_type_aliases`, `canonical_ship_type`; scenario `ship_type` kept as written), the
    `year` field, `type`/`speed`/`crew_quality` gone, `armament` only on `br_38`/`br_74`, and "Validate after
    edits: `validate_ships.py`" next to the other validators; "Run all three validators" in Combat Tables.
  - **Sides, Arcs and Rake**: a **Chasers** bullet: `FireGeometry.ARC_AHEAD`/`ARC_ASTERN` (2, 3), `chase_arc`,
    `GunneryTypes.CHASE_BOW`/`CHASE_STERN`/`BATTERY_CHASE`, `FireRules.CHASE_GUN_FACTORS`, what applies and what
    does not (spec §4.3), the fire panel's chaser blocks and `BroadsideColors.CHASE`.
  - **Server Objects**: `gunnery_calculator` (`eligible_shots` lists chase shots) and `stub_ai` (chasers when no
    broadside bears).
  - **Crew Overlay / Planning Panel**: Guns rows list the chasers; `CrewDeckLayouts.layout_for(type, class)`.
  - **Known Limitations**: remove "chase guns, medium guns, class 4 ships" from the Milestone 3 list (anchoring is
    already in; keep what remains true).
- [ ] **Step 8: Run and confirm everything passes.** `make test`; all three validators. Then run the
  `scv-reviewer` agent (CLAUDE.md "SCV Audit") and fix what it finds.
- [ ] **Step 9: Commit.**

```bash
git add data/scenarios/test_ships_and_guns.json test/unit/test_ships_and_guns_scenario.gd test/unit/test_ships_and_guns_scenario.gd.uid .claude/skills/scenario-creator/SKILL.md .claude/skills/validate-rule-table/SKILL.md docs/rules/feature_diff.md CLAUDE.md
git commit -m "docs: ships-and-guns scenario, ship ids and chasers in CLAUDE.md, feature_diff and the skills"
```
