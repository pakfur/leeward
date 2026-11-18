# Ships and guns: design

Date: 2026-11-18. Roadmap sub-project 6 of the sub-projects 3–7 run
(`2026-11-17-subprojects-3-7-decisions.md` §0 and §5, both binding). Status: draft written for the unattended
run. **U** marks the user's binding answers from the register; **B** the builder's calls, the register's or new
ones made here. A new or refined call is tagged **B (new)** or **B (refined)**, with its reason beside it.
Research memo: `docs/superpowers/research/sp6.md` (checked against the code at `a1dbfd8`, after towing).
Rules: `docs/rules/close_action.md` 1.G.2–1.G.11, 3.B.5, 3.E.1, 7.A.4, 7.B, 7.C, 7.E.2, 7.F.1–2, the SDC notes
(pdf p.107), Scenario 2 special rule V.C (Diomede) and the orders of battle of Scenarios 1 and 2
(`docs/rules/images/sb-p08-1.png`, `sb-p09-1.png`); charts: the Ship Data Chart
(`docs/rules/images/ship-data-chart.jpg`, pdf p.106), the Gunnery Factor and BGN charts (p.111).

## Intent

Leeward has three ship types, all British, and every ship fights only on her beams. This sub-project gives it
the whole Ship Data Chart (41 types of four navies), four odd ships from the orders of battle (three class-4
corvettes and brigs, and Diomede, the one ship with medium guns), and a simple house rule for chase guns so a
pursuit has something to shoot with. Lower-deck guns and medium guns are already in the code; they get the
tests the new ships make possible.

## Goals

1. **All 41 SDC types** (U) in `data/rules/ships.json`, with nation-prefixed ids (`br_74`, `fr_80c`, `sp_112`,
   `am_44`, …). The three old ids `frigate_38`, `frigate_32`, `ship_of_line_74` keep working as aliases of
   `br_38`, `br_32`, `br_74` (U). Every row is transcribed from the scan and checked against it (U).
2. **Four odd ships as their own types** (U: no per-scenario overrides): `fr_20_babet`, `fr_20_rosalie`,
   `fr_14_coureur` (class 4) and `br_44_diomede` (4 LG + 3 MG factors).
3. **A validator** for `ships.json` (U), run with the two existing rule-table validators.
4. **Costs** (U/B): `nationality` is the builder; the scenario `navy` is the user; costs are read from the type
   row, and only the chart's filled cells are stored.
5. **Lower-deck guns** (B, register): no code change; tests for freeboards 3, 4, 5 and 6 against sea states 0–5.
   **Medium guns** (B, register): no code change; a Diomede test pins the chart's arithmetic.
6. **Class 4** works end to end: movement (speed types C/F and C/S, maneuver type D), one-box crew sections,
   drift +2, prize minimum 1, the procedural model.
7. **Simple chasers** (U, house rule): one long-gun factor at each end of every ship, firing dead ahead from the
   bow hex and dead astern from the stern hex, with every interaction settled in §4.
8. **The stub AI** fires its chasers when no broadside bears (U).
9. **View-only minimum** (U): the fire panel lists chaser rows; the map draws their arcs; the ship card lists the
   chasers in its Guns rows; procedural models take their deck count from the gun decks and class 4 ships get a
   two-masted rig; the crew overlay picks a two-decker's deck drawing by class.
10. **Docs**: `feature_diff.md`, `CLAUDE.md`, the scenario-creator skill and the validator skill.

## Non-goals

- Per-scenario overrides of type data (U). OB variants of SDC types (Flora's 36 at `6 0`, Africaine's freeboard
  5, F-vs ships such as Pomone) are not modelled; a scenario uses the nearest type.
- Free-build purchasing, the tournament speed alterations under the SDC, and any ship-type picker (U: no new
  input controls). `year` is stored for a later free-build screen and read by nothing.
- Imported 3D models (U: a small procedural tweak only).
- Chasers in the book's sense of impulse fire or fire during movement (gunfire stays after movement, register §1).

## Design

### 1. Ship types (U; B where marked)

**Ids.** `<nation>_<rate><variant>`: nation `br`, `fr`, `sp`, `am`; rate the SDC number; variant the SDC's
suffix lower-cased (`l` large, `c` carronade-armed, `rz` razee). The OB ships add their name:
`br_44_diomede`, `fr_20_babet`, `fr_20_rosalie`, `fr_14_coureur`. 45 types in all.

**Names** (B (new): the display name feeds `assign_fallback_ship_names`, so it keeps the old style and the three
old names stay exactly as they are): `"<rate>-gun <kind>"`, kind "Ship of the Line" for classes 1–2, "Frigate"
for class 3, "Razee" for an RZ, "Two-decker" for the British 50 and Diomede, "Corvette"/"Brig" for class 4;
suffixes " (large)" and " (carronades)"; the OB ships add their name in brackets ("20-gun Corvette (Babet)"). The
full list is in the plan's Task 1 table.

**Fields per row** (all from the chart; a row is the JSON object keyed by its id):

| Field | From | Notes |
|---|---|---|
| `name`, `nationality` | — / the chart's section | British, French, Spanish, American |
| `rating`, `year` | Rate, Year Avail. | `year` new (OB ships: 1794, the scenario year) |
| `class`, `maneuverability` | C-M | maneuver letter upper-cased (`2b` → class 2, `"B"`) |
| `speed_type` | Speed Type | `L-f` → `"L/F"`, `C-s` → `"C/S"` |
| `draft`, `ch_modifier` | D, CH | |
| `rigging_hp`, `hull_hp` | RIGGING, HULL | four sections |
| `crew_count`, `marine_count` | CREW S1–S4 : M | |
| `gun_factors` | LG, (MG), CR | `{"lg", "mg", "cr"}` per side; `mg` is 3 for Diomede only |
| `freeboard`, `lower_deck_modifier` | (F : L) | |
| `point_costs` | Cost columns A3 … E5 | only the filled cells; an OB ship has one key, its CQ+MR → VP |
| `aliases` | — | optional list; `br_38`, `br_32`, `br_74` carry the old ids |
| `armament` | — | kept on `br_38` and `br_74` only (the crew overlay's deck notes read it) |

Dropped from the data: `type`, `speed`, `crew_quality` (not rules data, read by nothing in play), and with them
`Ship.type` and `Ship.speed`. `Ship.is_french_gunned` (unused in play, reads the builder) is removed:
`ShipState.is_french_gunned()` (the user's navy, 1.G.8) is the one rule. **B (new):** the research memo's call,
confirmed: one rule, no dead fields.

**Aliases (U).** `DataManager` keeps `ship_definitions` keyed by canonical id only (45 entries) and a separate
`ship_type_aliases` (alias → canonical) read from the rows' `aliases`. `get_ship_definition` and
`assign_fallback_ship_names` resolve an alias first. A scenario's `ship_type` string is stored on the ship as
written (`Ship.ship_type`, `ShipState.ship_type`), so the 21 scenario ships and the crew overlay's
`deck_layouts.json` keys keep working unchanged. Keys of `ships.json` that start with `_` (a `_doc` entry) are
skipped. The hard-coded fallback `_create_default_ships` holds `br_38`, `br_32`, `br_74` with the same aliases.

**Costs (U/B).** `Ship.point_value(cq, mr)` already falls back to the same CQ at the nearest MR, then to the
lowest cost; a one-key OB row works unchanged. A scenario that gives a Spanish ship CQ A therefore scores her at
her lowest cost; that is recorded, not warned about (**B (new)**: scenarios are hand-written, and a warning would
fire on every OB corvette with a CQ other than her own).

**Navy.** The type's `nationality` is the builder; `ShipState.gunnery_navy()` is the scenario's per-ship or
per-side `navy`, else the builder. A `fr_` type therefore fires French BGNs at 11–15 unless a scenario says
otherwise (1.G.8, already built).

**Validator (U).** `.claude/skills/validate-rule-table/scripts/validate_ships.py`, pure Python, exit 1 on any
error, checks the exact id list, each field's type and range, the speed type against `movement_allowance.json`,
sections non-decreasing from 1 to 4 (true of every row on the chart), costs strictly falling along
A3 → E5, cost keys from the chart's nine columns (OB rows: one `[A-G][2-6]` key), the `c` twins sharing every
field but guns, costs and year, the alias map, and no unknown keys. It catches the slips a transcription makes;
the second pass against the scan (U) catches the rest.

### 2. Medium guns and class 4 (B, register)

No rules code changes. `GunneryCalculator.preview` already sums `lg/mg/cr × multiplier` and rounds up once
(chart rule 2). Diomede at range 6: 4 + 3 × ¾ = 6.25 → TGF 7 → BGN 12; at 11: 4 + 1.5 → 6 → BGN 3; at 13 the MG
are out (—) and TGF 4 has no BGN: she cannot fire. Class 4 is already in every chart and table
(`movement_allowance.json` C/F, C/S, C/VS; maneuver type d; drift +2; prize minimum 1; blast; crits by class).
Tests pin these with the real types (plan Task 2). If a test finds a class-4 path broken (one-box sections, CH −4),
the fix belongs in that task.

### 3. Lower-deck guns (B, register)

Already built (7.F.2, `FireRules.lower_deck_closed` / `lower_deck_modifier`). The new types give freeboards 3
(Diomede, `br_98l`, `sp_130`), 4, 5 and 6. A data-driven test runs every freeboard against sea 0–5, both
broadsides, WF=C: below the freeboard nothing; equal, the leeward broadside only; above, both. Diomede at sea 3
(Scenario 2 V.D's alternate sea state) loses her leeward lower deck, −4.

### 4. Chase guns (U, house rule)

#### 4.1 Geometry

Two new arcs, numbered after the broadsides so one int names any arc:

| Arc | Value | Fires from | Covers |
|---|---|---|---|
| `ShipState.PORT` | 0 | bow or stern hex | 60°–120° off the bow, port (unchanged) |
| `ShipState.STARBOARD` | 1 | bow or stern hex | 60°–120° off the bow, starboard (unchanged) |
| `FireGeometry.ARC_AHEAD` | 2 | the bow hex | within 30° of the heading (0°–30°) |
| `FireGeometry.ARC_ASTERN` | 3 | the stern hex | within 30° of the stern (150°–180°) |

Angles are measured as `bearing_side` measures them, with the same 0.5° tolerance, so the boundary hexes (30°,
150°) are in, as the broadside's 60° and 120° hexes are. The wedges 30°–60° and 120°–150° stay blind; at range 1
and 2 every hex lies on a multiple of 30°, so the first blind hexes are at range 3.

`FireGeometry.chase_arc(from_hex, facing, to_hex) -> int` returns `ARC_AHEAD`, `ARC_ASTERN` or −1. The arc
helpers take the arc in their `side` parameter: `in_battery_arc`, `battery_bears`, `blocking_hexes` and
`broadside_hexes` treat 2 and 3 through `chase_arc` and 0 and 1 as before. So line of sight (7.B.7–9) and
friendly blocking hexes (7.B.10–12: a friend in the chaser's arc makes blocking hexes for it) apply to chasers
unchanged. `bearing_side` itself is unchanged.

The reach: the arc runs to range 15, as for long guns (U). **B (new), a reading:** a chaser is one long-gun factor,
TGF 1, and the BGN chart has numbers for TGF 1 only to range 7 (3, 2, 2, 1, 1, 0, 0); beyond 7 its box is grey.
The calculator refuses such a shot as it refuses any grey box ("cannot fire at this range with this gunnery
factor"). The arc drawn on the map still runs to 15. No BGN is invented.

#### 4.2 Orders

A chase order is a `FireOrder` with `side` = `GunneryTypes.CHASE_BOW` (2) or `CHASE_STERN` (3) and `battery` =
`GunneryTypes.BATTERY_CHASE` (`"chase"`). **B (new):** a side value rather than a battery value, because the
per-side arrays (`guns_dismounted[2]`, `initial_broadside_fired[2]`, `obscured_penalty(side)`) would silently read
port if a chase order carried side 0, while side 2 can only reach them through a guarded branch. A chase side with
another battery, or the chase battery on a broadside side, is a declaration error. Each chaser fires at most
once; `FireRules.declaration_error`'s "battery fired twice" key (`ship:side:battery`) covers it unchanged.

#### 4.3 The shot

`GunneryCalculator.preview` takes a chase order through the same steps as a battery, with these differences:

| Item | Chasers | Why |
|---|---|---|
| Gun factors | `FireRules.CHASE_GUN_FACTORS` = `{"lg": 1, "mg": 0, "cr": 0}` on every ship | U. A constant, not a type field (**B (new)**: U says every ship; a field invites variation nobody asked for) |
| Ammunition | round shot only; a dismantling order is refused ("chasers fire round shot only"); `FireRules.make_order` forces round | U |
| Aim | low or high; high only from range 10 as usual | the rule for all gunfire |
| Batteries | one (`batteries` = 1) | |
| Half broadside −8 | not applied | **B (new)**: a chaser is not half of anything; its TGF already says it is small |
| Two targets −12 | applied when the ship's orders name two targets, to every shot, chaser included | U: a chase battery is one of the ≤ 2 targets (7.A.4), so 7.C.12g follows |
| Initial broadside | never: no bonus, and firing a chaser does not spend a broadside's | U |
| Rake | never: `rake` is `""` | U: no rake bonus. **B (new)**: the whole rake effect goes (no stern-rake crew doubling, no raked-while-dismasted MC); a one-factor gun does not rake |
| Guns dismounted | not applied; hull-section losses never dismount a chaser | U |
| Broadside obscured −2 (7.C.11) | not applied | **B (new)**: rigging #6/#10 obscure a broadside; a chaser fires over the bow or stern |
| Lower deck closed | not applied | U |
| Crew quality, sections firing | applied; a ship with no sailor section at the guns cannot fire her chasers | **B (new)**: the chasers are served from the same crew |
| Plain sail, wind speed 4, anchored +1, dismasted −sea, voluntary reduction | applied | ship-wide modifiers (the anchored +1 is sub-project 4's) |
| French BGN at 11–15 | as for the ship (moot: TGF 1 is grey there) | 1.G.8 |
| Refusals (struck, prize, aground, same side, destroyed) | as for broadsides | |

Arc refusal: "target is not in the bow chaser's arc" / "stern chaser's arc" (the fire panel's no-shot mapping
keys on "arc").

`eligible_shots(ship_id)` adds, after the broadside previews, one preview per target per chase side that can
fire. `any_eligible_shot`, `validate_orders` and `preview_orders` need no other change: `preview_orders` keys the
initial-broadside holder by `ship:side`, and a chase shot never claims it.

#### 4.4 Resolution and events

`GunneryResolver` resolves chase shots like any shot (dice order unchanged: by target, rake rank, firer, side,
then battery, where `"chase"` ranks after `"stern"`; chase sides 2 and 3 sort after the broadsides). It does not
call `set_initial_broadside_fired` for a chase shot, and `ShipStateController.set_initial_broadside_fired` refuses
any side but 0 and 1. The critical-hit context's engaged side is the firer's relative side, as for any non-rake
shot. The FIRE event carries `side` 2/3 and `battery` `"chase"`; its text reads "HMS X fires bow chaser at Y, range
3, low, roundshot — …". `PlayerView.BOX_FIELDS` is unchanged: FIRE already hides the target's hits from other
readers whatever the battery.

#### 4.5 Interactions settled

- **Rakes (7.E.2).** The rake geometry is unchanged: a ship in the target's chase arc still rakes it with her
  broadside, and the raked ship may answer with a one-factor chaser (the trade-off the register accepted).
- **Two-target limit.** A chaser at a third target is refused ("more than two targets"); a chaser at the same
  target as a broadside costs nothing; at a second target, −12 on every shot.
- **Hold fire.** A ship whose only shot is a chaser and that does not fire logs HOLD_FIRE, as any ship with an
  eligible shot does. Combat is declared when any chaser bears (more declare steps than before: an enemy dead
  ahead within 7 now gives a shot).
- **Adjacent ships.** With chasers every adjacent enemy lies in some arc of the firer (all its neighbours are at
  0°, 60°, 120° or 180° from a battery hex). Tests that relied on "no gun bears" for an adjacent pair must now
  silence the guns another way (every sailor section on a task).
- **Victory (2.A.1).** `VictoryController.can_move_or_fight` keeps counting only the ship's own gun factors:
  **B (new)** a dismasted ship whose broadsides are all dismounted is out of the fight even though her chasers
  never dismount; otherwise no such ship could ever count as unable.
- **Sub-project 7 (later).** 14.D fatigue counts a "firing turn" when any battery fired: a chaser shot is gunfire
  and should count (noted for that design). 14.E's forced-high roll applies to chasers like any gunfire.

### 5. Stub AI (U; B refined)

`StubAI.choose_fire_orders`: the broadside choice is unchanged. When a ship has no broadside offer at all (no
broadside shot is eligible), its candidates are the chase offers: `_side_offers(shots, CHASE_BOW)` ×
`_side_offers(shots, CHASE_STERN)` (each: hold, its best chase shot, its best shot at an ordered target),
judged by `_evaluate_orders` and `_candidate_beats` as the broadsides are (two targets need every shot at mgn ≥ 1;
then the ordered target, most shots, highest total mgn, nearest, target id). **B (refined):** no mgn floor for a
lone chase shot, as for a lone broadside: the register says the AI uses its chasers when no broadside bears.
Positioning (`_score_position`) is unchanged (**B (new)**: a one-factor gun is not worth steering for; valuing
it would point AI ships bow-on into their enemies' rake zones).

### 6. View (U: view-only minimum)

- **Fire panel.** Per ship, after Port and Starboard, a "Bow chaser" and a "Stern chaser" block when that chaser
  has a target: target rows labelled "Chaser", Hold fire, the aim toggle, the reduction stepper, and the
  ammunition toggle locked with the note "Chasers fire round shot only". The chase state uses the existing
  `{"bow", "stern"}` shape with the target under `"bow"` for either chaser, so `FireRules.limit_targets` and
  `battery_targets` keep the ship within two targets unchanged; `panel_orders` turns a chase side's shot into a
  `BATTERY_CHASE` order. The default choice stays the ship's best broadside; a ship with no broadside row starts
  with its best chaser row (as the AI). The main button counts chasers: "Fire 1 broadside and 1 chaser".
- **Arcs on the map.** `GameController._refresh_fire_overlay` also draws the chase arcs, from the bow hex for 2
  and the stern hex for 3, in a chase colour (`BroadsideColors.CHASE`, used for both chasers).
- **Ship card.** `CrewOverlayText.gun_rows` adds two rows, "Bow chase" and "Stern chase", each one long-gun
  segment and status "ready" (never dismounted, no lower deck). The Guns readout's caption says the sections-firing
  modifier applies "on both broadsides and the chasers".
- **Models.** `ProceduralShipSpec.for_ship`: gun decks from class (1 → 3, 2 → 2, 3 and 4 → 1) instead of rating,
  so a 50 or Diomede draws two decks; class 4 has two masts (a brig rig), every other class three. Null ship
  stays a frigate.
- **Crew overlay deck drawing.** `CrewDeckLayouts.layout_for(ship_type, ship_class)`: the type's entry in
  `deck_layouts.json` `ship_types`, else a new `classes` map (`"1"`, `"2"` → `sol74`), else the default
  (frigate). Presentation only.

### 7. Scenario and docs

A test scenario `test_ships_and_guns.json` (British `br_100`, `br_44_diomede`, `br_38` against French `fr_80`,
`fr_20_babet`, `fr_14_coureur`, sea state 3) plays a whole AI game in a test. Docs as Goal 10.

### 8. Server authority and determinism

No new request, no new state, no new dice: chasers are new orders through `player_submit_fire_orders`, checked by
`validate_orders` against the requesting player. With no chaser fired, the dice order and every existing
resolution are unchanged. The view code only reads (`test_server_authority.gd` stays green).

### 9. Builder's calls, collected

| Call | Kind | Reason |
|---|---|---|
| Type names keep the old style; the three old names unchanged | B (new) | fallback ship names and existing tests |
| Drop `type`, `speed`, `crew_quality` and `Ship.is_french_gunned` | B (new) | not rules data; one navy rule |
| Keep `armament` on `br_38` and `br_74` | B (new) | the crew overlay's deck notes read it |
| OB ships' `year` = 1794 | B (new) | the OBs give none; the scenario year |
| No warning for a CQ/MR missing from a cost row | B (new) | OB corvettes have one cell; fallback documented |
| Chase arcs as sides 2 and 3 | B (new) | per-side arrays cannot be read by mistake |
| Chaser reach limited to 7 by the BGN chart | B (new), reading | the chart's TGF-1 row; no invented numbers |
| No half-broadside −8 on a chaser | B (new) | a chaser is its own battery |
| No rake effect at all from a chaser | B (new) | U's "no rake bonus" extended to the crew doubling and MC |
| No broadside-obscured on a chaser | B (new) | 7.C.11 obscures a broadside |
| Chasers need a sailor section at the guns; sections-firing applies | B (new) | same crew |
| Chasers do not count for "able to fight" | B (new) | keeps 2.A.1 reachable |
| AI: chasers only with no broadside offer, no mgn floor; positioning unchanged | B (refined/new) | register; rake zones |
| Fire panel default: best broadside, else best chaser | B (new) | mirrors the AI |
| Deck drawing by class | B (new) | a 64 or 50 is a two-decker |
| Register entries changed | — | none |
