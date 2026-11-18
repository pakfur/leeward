# Sub-project 6 — Ships and guns: decision inputs

Headline: of the four items, **lower-deck guns are already done**, **medium guns are done in code (no data uses them)**, **class 4 is supported by every chart but has no ship data**, and **chase guns are not in the 1997 rules at all**: they would be a home-made rule. The real work is data (SDC transcription and corvettes) and one design call on chase guns.

## 1. Rules summary

- **1.G.7 Gunnery Area** (OCR'd as "4.G.7", pdf p.6–7). Three gun types: LG, MG, CR, factors **per side**. "Only one ship in the CA Scenario Book has medium guns" (Diomede, scenario special rule V.C: 4 LG + 3 MG, OB shows `4/3m 0 (3:-4)`). The SDC has **no MG column**. `(F:L)` after CR = freeboard : LDGM.
- **Gunnery Factor Calculation table** (gunnery-factor-chart.jpg, p.111; checked against the scan): LG ×1 at 1–15; **MG ×1 at 1–5, ×¾ at 6–10, ×½ at 11–12, — at 13–15**; CR ×2,2,2,1½,1,½ then —. Sum all types, **round up once after adding** (rule 2 on the chart). `gunnery_factor_table.json` matches exactly.
- **3.B.5 / 3.E.1 / 7.F.1–2** Lower-deck guns. Sea < freeboard: nothing. Sea = freeboard: LDGM off the **leeward** broadside BGN, not at WF=L or WF=R. Sea > freeboard: LDGM off **all** gunfire. 3.E.1's "(=3)" is an OCR mangle (a pointer to 7.F.2 only; no effect on behaviour).
- **Class (1.G.2a, glossary, SDC notes)**: 1 = three-deckers, 2 = two-deckers, 3 = frigates and razees, 4 = corvettes. "Only class 1, 2 and 3 ships are included on the SDC; class 4 ships (corvettes) are found in several scenarios." Maneuver type D usual for class 4 (1.G.10); speed types C-f/C-s/C-vs (1.G.11).
- **Class 4 effects already in the rules/charts**: drift class DRM +2 (8.A), marine fire −1 only for the larger class firer (7.G.4), boarding class DRMs (10), prize minimum 1 box (10.G.6), blast MGN 25/10 (8.E.10), crit tables `*_by_class` (rigging #8/#12, hull #4/#5: class 4 loses 0 marines / 0 sailors / 1 crew).
- **Chase guns: no rule.** `grep` of the whole rules book finds no chase/bow/stern gun rule; 7.B.1–3 define four batteries (bow and stern hex × port/starboard), each a 60° beam arc. "Chase" appears only in history text. Earlier Leeward specs ("Milestone 3") listed chase guns as a wish, not a rule.
- **Ship Data Chart** (ship-data-chart.jpg, p.106), per row: rate, year avail., class + maneuver type (C-M), speed type, draft, CH mod, rigging ×4, hull ×4, crew S1–S4 : M, LG, CR, (F : LDGM), cost at A3 B3 C3 C4 C5 D4 D5 E4 E5 ("–" = not purchasable by that navy). **41 rows**:
  - British 16: 100, 98L, 98, 80, 74L, 74c, 74, 64c, 64, 50, 44RZ, 40, 38, 36, 32L, 32.
  - French 13: 120, 110, 80c, 80, 74L, 74c, 74, 50RZ, 44, 40c, 40, 38, 36.
  - Spanish 8: 130, 112, 80L, 80, 74, 64, 40, 34 (all CR 0).
  - American 4: 44, 38, 36, 32.
  - "c" rows share hull/rigging/crew/speed with their plain twin; only guns and cost differ (e.g. Br 74c `16 4 (4:-5)` vs 74 `17 1 (4:-5)`).
  - Speed types on the SDC are only L-f, L-s, F-f, F-s. Freeboard 3–6, LDGM −3 to −8, CH +1 to −2.
  - OCR/scan doubts to settle at transcription against PDF p.106: French 80 speed "L-f•" (stray mark, read L-f); small digits in French 120/110 crew rows.
- **Corvettes (class 4) exist only in scenario OBs**, each with one VP figure, not a CQ/MR cost row. Examples read from the OB scans: Babet 20 `D4 4d C-s 14 −3, 4-4-4-4, 3 3 3 3, 1 2 2 2:2, 2 0 (5:-7), VP 12` (sb-p08); Coureur 14 `D5 4d C-s 12 −4, 2-3-3-3, 2 2 2 2, 1 1 1 2:2, 1 0 (5:-7), VP 6`; Rosalie 20 `D6 4c C-f 14 −3, 4-4-4-4, 3 3 3 3, 1 2 2 2:2, 2 0 (5:-7), VP 10` (sb-p09). Note CH −3/−4, one-box crew sections, MR 6, and a maneuver type c corvette.
- OBs also carry per-ship variants of SDC types (Flora 36 `6 0` vs SDC 36 `6 3`; Africaine "F38" freeboard 5 not 6; F-vs ships like Pomone, Rhin). The SDC is the "free build" source; OBs are per-scenario.

## 2. Current code

- **Lower-deck guns: complete.** `FireRules.lower_deck_closed` / `lower_deck_modifier` (scripts/server/fire_rules.gd:201–217), `FireGeometry.leeward_side` (scripts/core/fire_geometry.gd:28), `GunneryCalculator.preview` modifier `lower_deck_closed` (gunnery_calculator.gd:121, 235), ship card Guns rows (`CrewOverlayText.gun_rows`, crew_overlay_text.gd:191–209). Dismasted −sea state (7.C.12e) in `preview`. feature_diff §5 already lists 7.F.2 as matching. Only gap: tests use 3 ship types, so freeboards 3 and 4 with sea 3–5 are covered only by the 74.
- **Medium guns: complete in code.** `GunneryCalculator.preview` sums `lg/mg/cr × gunnery_multiplier` and `ceili` once (gunnery_calculator.gd:86–89) = chart rule. `Ship.gun_factors` loads `mg` (scripts/state/ship.gd:91–92); `VictoryController.can_move_or_fight` counts it; `ShipCardStatus` draws an MG colour (ship_card_status.gd:97–118). `test_combat_tables.gd:38–42` tests the multipliers. Missing: any ship with mg > 0 and a TGF test (e.g. Diomede at range 6: 4 + 2.25 → 7).
- **Class 4: tables ready, no ships.** `movement_allowance.json` has C/F, C/S, C/VS (and F/VS, L/VS); `speed_change_table`, `turning_table`, `tacking_table`, `bearing_off_table` have maneuver type d; drifting/boarding/fire/crit tables have class 4; `ProceduralShipSpec.CLASS_SCALE` has 4: 0.8 and 2 masts below rate 20 (scripts/view/procedural_ship_spec.gd:24, 63). Nothing in code has run a class 4 ship; one-box crew sections and CH −4 untested.
- **Ship data**: `data/rules/ships.json` = `frigate_38` (Br 38), `frigate_32` (Br 32), `ship_of_line_74` (Br 74); numbers match the SDC. Cruft: `armament` (display-only history, includes fictional `bow_chasers`), `type`, `speed` ("Slow" on an F/F ship), `crew_quality`. `DataManager.load_ship_definitions` (data_manager.gd:295) and a hard-coded fallback copy `_create_default_ships` (data_manager.gd:576–597). `Ship.from_dict` (ship.gd:54–98); `Ship.is_french_gunned` uses `nationality`, but play uses `ShipState.gunnery_navy()`. `Ship.point_value(cq, mr)` falls back to nearest MR, then the lowest cost (ship.gd:186–208), so a one-entry cost dict works for corvettes.
- **No per-scenario ship overrides**: `GameState` builds ships from `ship_type` only (game_state.gd:382). 47 files reference the three ids (21 scenario ships use them).
- **Models**: `assets/models/ships/` is empty; every ship is a procedural model from rating and class (`ProceduralShipSpec.for_ship`, `ProceduralShipBuilder`). Gun decks come from rating (≥90 three, ≥60 two), so a two-decker 44/50 draws one deck (cosmetic).
- **Arcs and chase-gun touch points**: sides are ints 0/1 everywhere: `FireOrder.side`, `battery` full/bow/stern (gunnery_types.gd:10–23), `ShipState.guns_dismounted[2]`, `initial_broadside_fired[2]`, `obscured_penalty(side)`, `FireRules.lower_deck_modifier(side)`, `FireGeometry.bearing_side` / `battery_bears` / `in_battery_arc` / `broadside_hexes`, `rake_type_ships` (ahead/astern = rake zone), `FireRules.MAX_TARGETS`/`declaration_error`/`side_shots`, `GunneryCalculator.eligible_shots`, fire panel rows and `GameController.battery_arc`, `StubAI._side_offers` / `choose_fire_orders` (stub_ai.gd:292–419) and `_bearing_batteries` / `_score_position` (stub_ai.gd:825–853), `PlayerView` FIRE event fields, `DamageController` hull-loss dismount (`section + 1` to both sides, damage_controller.gd:483–490).

## 3. Work breakdown

| # | Component | Files | Size |
|---|---|---|---|
| A | Transcribe SDC rows to `ships.json` (ids, speed type `L-f`→`L/F`, maneuver letter upper-case, nationality, year, costs with "–" omitted); drop cruft fields; trim `_create_default_ships` to a fallback | data/rules/ships.json, data_manager.gd, ship.gd | M (41 rows) or S (~10) |
| B | Ship-data validator (row shape, speed type in movement table, maneuver in tables, class 1–4, freeboard 1–6, LDGM < 0, CH −4..+1, costs keys), hooked into `validate-rule-table` | .claude/skills/validate-rule-table/scripts/ | S |
| C | Class 4 corvette types from OBs (Babet/Rosalie/Coureur-style 20, 18, 14 or generic C-f/C-s/C-vs rows), single VP | ships.json | S |
| D | Per-scenario ship overrides (optional; e.g. `"overrides": {"gun_factors": {...}}` or OB row inline) so Diomede's MG and OB variants work without a type per ship | game_state.gd (ship build), scenario-creator SKILL.md | S–M |
| E | Tests: MG TGF (Diomede), class 4 end-to-end (move with type D/C-s, drift +2, prize min 1, crits by class 4, one-box crew sections), freeboard 3/4/5/6 vs sea, `point_value` for one-entry costs | test/unit/* | M |
| F | Scenario(s) using new types (a mixed squadron with a corvette and a 3-decker; a Diomede MG scenario) | data/scenarios/ | S |
| G | Chase guns (only if user wants them): new arc geometry, order kind, rules for modifiers/targets/initial broadside/dismount/rake interplay, preview, resolver, AI firing + positioning, fire panel row, events, data field per ship | fire_geometry, fire_rules, gunnery_types, gunnery_calculator, gunnery_resolver, stub_ai, fire_declaration_panel, game_controller, ship.gd, ships.json, player_view | L |
| H | Procedural model tweaks: decks from class (class 2 → 2 decks, class 1 → 3) not rate; brig/sloop rig for class 4 | procedural_ship_spec.gd | S |
| I | feature_diff (§2 row 53 → §5; chase guns to §4 if added or §3 "not a rule"), CLAUDE.md ship id list | docs | S |

Without chase guns the sub-project is mostly data + tests: roughly S–M overall. With chase guns, G dominates.

## 4. Decisions needing the user (by importance)

**Q1. Chase guns: build them, and if so how?** There is no 1997 rule; anything built is house rule (§4 of feature_diff).
- (a) **Drop from scope**; record "not in Vol. 1" in feature_diff §3 (like "sinking"). Zero cost; arcs stay as book.
- (b) **Simple chasers**: each ship gets a fixed small factor (e.g. 1 LG per end; 0 for class 4?), a 60° arc dead ahead of the bow hex / astern of the stern hex, fired as a separate "battery" with its own BGN (TGF 1–2 → BGN 3–8 at range 1, out at 8–10), one of the ≤2 targets, no initial-broadside bonus, no rake bonus, not affected by guns dismounted or lower deck. New side value (e.g. `side` 2 = bow chase, 3 = stern chase) or a `battery` kind. Gives pursuit a purpose; touches everything listed in §2 arcs. M–L.
- (c) **Chasers as a re-aim of the broadside**: bow/stern battery may fire into the ahead/astern 60° with the half-broadside modifier and a further penalty. No new data, reuses battery orders, but blurs the rake geometry (the "blind" zones are what make rakes possible) and makes the model less readable.
Trade-off: chase guns weaken the rake zone that the book balances around (a raking ship could be fired back at), and add an order type to UI and AI. Recommend **(a) now**, revisit with 14.A impulse movement / pursuit scenarios in sub-project 7 or after playtests; if the user wants them, (b) with the chaser ≤ 1 factor so rakes stay dominant.

**Q2. How many SDC types to add?**
- (a) All 41 rows. Complete free-build catalogue; M transcription effort with a validator; many near-duplicates ("c" twins), nationality-specific costs.
- (b) Representative ~10–12: one per class/role per navy that differs (Br 100, Br 74, Br 64, Br 50, Br 44RZ, Br 38, Br 32, Fr 120, Fr 80, Fr 74, Fr 40, Sp 112, Am 44). Fast; most variety for fewest rows.
- (c) Just the classes missing (one 3-decker, one 64/50, one corvette).
Recommend **(a)**: transcription is mechanical, a validator catches errors, and PVP/free build later wants the full menu; cost per row is small once the shape is fixed. (b) if the user wants this sub-project short.

**Q3. Where do class 4 corvettes come from?** The SDC has none; only OBs.
- (a) Add a few OB corvettes as types (`corvette_20_c_s` = Babet, `_c_f` = Rosalie, `brig_14` = Coureur), VP as a single cost.
- (b) Invent generic C-f/C-s/C-vs 18/20/22 rows by extrapolating SDC patterns (house data).
- (c) Defer class 4 until historical scenarios.
Recommend **(a)**: book numbers, enough to exercise every class-4 path; record "corvettes from OBs, not SDC" in feature_diff.

**Q4. Per-scenario ship overrides (OB variants)?** Diomede's MG and many OB ships differ from SDC rows; the roadmap excludes historical scenarios.
- (a) No overrides; add Diomede as its own type (`two_decker_44_diomede`) to exercise MG. Simple.
- (b) Allow a scenario ship entry to override any `Ship` field (`gun_factors`, `freeboard`, hp …). Flexible, needed later for historical scenarios; small loader change but adds a validation surface and server-authoritative data that clients must also see.
Recommend **(a)** now with a note; (b) when historical scenarios are scoped.

**Q5. Ship-type ids and naming.** Current ids are generic (`frigate_38`). With 41+ rows, nationality matters (Br 38 ≠ Fr 38 ≠ Am 38).
- (a) Nation-prefixed ids (`br_74`, `br_74c`, `fr_74l`, `sp_112`, `am_44`), keep the three old ids as aliases. (b) Rename everything and update 47 files. (c) Keep old ids, add new ones ad hoc.
Recommend **(a)**: no churn, unambiguous. (Asked because ids appear in scenario JSON authored by the user.)

**Q6. Nationality vs navy for French guns and costs.** A French-built type sailed by the British (Africaine "F38") is common. Code already uses `navy` (scenario) for BGN; SDC costs are per nationality of the *buyer*.
- (a) Keep: type `nationality` = builder, scenario `navy` = user; costs looked up from the type row. (b) Make cost depend on navy.
Recommend (a); free build is out of scope. Low stakes but changes data shape.

**Q7. Any UI in scope?** Back end only as last time, or a ship-type picker / showing class, freeboard and LDGM on the card?
Recommend **back end only**; the card already shows MG and lower-deck state. If chase guns are built, the fire panel needs a row (unavoidable).

**Q8. 3D look of new types.** No model assets exist; all ships are procedural (`ProceduralShipSpec`). Options: (a) accept procedural as is; (b) small tweak so decks follow class (two-decker 44/50 shows two decks) and class 4 gets a brig/ship-sloop rig; (c) commission/import real models (out of scope).
Recommend **(b)**, S-sized, view only. Ask only because the user may want art left alone.

AI expectations: no new AI decisions are needed for MG, class 4 or new types (the AI uses `preview` and table-driven movement). Only chase guns (Q1 b/c) would need `choose_fire_orders` and `_score_position` changes. Not a separate question unless Q1 = build.

## 5. Decisions the builder can make alone

- Lower-deck guns: no change; add freeboard 3/5/6 coverage tests; close the feature_diff row.
- MG: no code change; add a Diomede-style test (range 6: 4 + 3×¾ = 6.25 → TGF 7).
- Speed-type and maneuver mapping: SDC `L-f` → `"L/F"`, `2b` → class 2, maneuverability `"B"`.
- Costs: store only non-"–" cells; `point_value` fallback already handles missing keys; corvettes get one key matching their OB CQ/MR (e.g. `"D4": 12`).
- "c" rows become separate types sharing data (no inheritance mechanism).
- Drop `armament`, `type`, `speed`, `crew_quality` from ships.json (not rules data; `armament` with fictional chasers is misleading); keep `year` (new field, unused) and `draft` (sub-project 3 depth).
- `_create_default_ships` stays as the three-row test fallback.
- Validator in `validate-rule-table` for ships.json; run with the others.
- Verify every transcribed row against PDF p.106 render (skill's swift script) where digits are small.
- `Ship.is_french_gunned` (unused in play, uses nationality) — remove or route to navy.

## 6. Dependencies and risks

- **Sub-project 3 (map/depth)** reads `draft`; transcribe it for all rows now.
- **Sub-project 7 (optional rules)**: 14.E historical gunfire limits and 14.D fatigue touch gunnery; chase guns, if ever built, interact with 14.A impulse movement (pursuit). Another reason to defer chase guns.
- **Sub-project 2 / PlayerView**: new ship fields are public type data; no BOX_FIELDS change unless chase guns add a new event or data per side.
- **Victory**: VP from `point_value(cq, mr)`; French/Spanish types have no A3/B3 cells, so a scenario giving a Spanish ship CQ A falls back to the nearest/lowest cost silently. Consider a scenario validation warning.
- **Class 4 untested paths**: one-box crew sections (sections-firing modifier, morale per section, RO forcing a 1-box section), CH −4 with crit rolls, `MAX_PORTS/MIN_PORTS` model clamps at rate 14. Expect a few small bugs; budget tests.
- **Balance**: corvettes (TGF 1–2) cannot hurt frigates beyond range ~7; fine historically, but AI "engage" will throw them at frigates. Acceptable for now.
- **Data risk**: 41 hand-transcribed rows — mitigated by the validator and a second-pass check against the scan.
