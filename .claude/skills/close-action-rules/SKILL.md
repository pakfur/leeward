---
name: close-action-rules
description: Use when building, testing, reviewing or fixing Leeward game logic (movement, plotting, turning, tacking, bearing off, collisions, fouling, gunnery, arcs, rakes, damage, drift, weather, wind, sail changes, morale, striking, victory) or when deciding what the correct game behaviour is — "what does the rule say", "is this a bug or a house rule", a test needs an expected value, or a rule section number such as 5.D.1 or 7.E.2 is mentioned. Also use when a change adds, fixes or alters a game feature, because docs/rules/feature_diff.md must then be updated.
---

# Close Action rules: where the authority lives

Leeward implements *Close Action: The Age of Fighting Sail, Vol. 1* (1997). Every game-logic question has one answer, in the 1997 rules book, minus the deliberate changes recorded in `docs/rules/feature_diff.md`. Look the rule up; do not rely on memory or on other rule documents in the repo.

## Sources, in order of authority

| Source | Use it for | Notes |
|---|---|---|
| Chart and table scans (see **Chart map** below) | **Numbers** | Tables are images and are *not* transcribed in the text. Read the image (the Read tool shows images). **Where the text and a chart disagree, the chart wins** (e.g. two targets: text −10, chart −12; collision rigging loss: chart says "ramming ship only"). |
| `docs/rules/close_action.md` | **Procedure and wording** of rules 1–14, examples, explanations, the glossary, and the scenario book | OCR of the scan. Diagrams are inline images: `docs/rules/images/diagram-NN-*.png` (1–26). |
| `docs/CoA_-_Close_Action_the_Age_of_Fighting_Sail_vol_1_1997.pdf` | Settling doubtful OCR | Scan with no text layer. The `<!-- pdf p.N, Rules Book p.M -->` comment before the passage gives the page: `Read` with `pages: "N"`. |
| `docs/rules/feature_diff.md` | **What Leeward deliberately or knowingly does differently**, and what is missing | Read the row for the rule before you call code "wrong". |
| `data/rules/*.json` | What the code actually uses | Transcriptions of the charts. They have been wrong before (tacking and bearing off). If one disagrees with the scan, the scan wins; fix the JSON and run both validators (see CLAUDE.md). |

**Not authoritative — never take rules or numbers from:** `docs/Close-Action-Rules-v6-1.*`, `docs/Close_Action_latest.pdf`, `docs/02-game-rules.md`, `docs/02.1-movement-protocol.md`, `docs/02.2 - contexted-hex-rules.md`, `docs/07-naval-combat-mechanics.md`. They are a later, different edition or home-made design notes. Code comments citing a rule number are hints, not authority.

## Chart map

All in `docs/rules/images/`. Pages are the PDF pages (for `Read` with `pages:`). `docs/*.jpeg` are older scans of some of the same pages (e.g. `docs/combat_tables_1.jpeg` = `boarding-combat-chart.jpg`); either will do.

| Image | PDF p. | Tables on it | JSON transcription |
|---|---|---|---|
| `movement-chart.jpg` | 108 | Movement allowance, turning, speed change (acceleration/deceleration) | `movement_allowance.json`, `turning_table.json`, `speed_change_table.json` |
| `boarding-combat-chart.jpg` | 109 | Boarding combat and skill factors (CQ → SK mod, BCF), grappling, **unfouling**, **collision resolution** (fouling roll, extra rigging lost), **tacking**, **bearing off**, poor maneuvering, **drifting**, **wind speed change**, **wind direction change** | `crew_quality_table.json`, `unfouling_table.json`, `tacking_table.json`, `bearing_off_table.json`, `drifting_table.json` (collision and wind: in code) |
| `gunfire-results-chart.jpg` | 110 | Gunfire results (FGN → damage, CH#), gunfire modifiers (range, rake, initial broadside, two targets …), crew loss | `gunfire_results_table.json`, `gunfire_modifiers.json`, `crew_loss_table.json` |
| `gunnery-factor-chart.jpg` | 111 | Gunnery factor multipliers by range, Basic Gunfire Number | `gunnery_factor_table.json`, `basic_gunfire_number_table.json` |
| `rigging-critical-hits.jpg`, `hull-critical-hits.jpg` | 112–113 | Critical hits (not implemented) | — |
| `ship-data-chart.jpg` | 106 | Ship Data Chart (notes are transcribed under "SHIP DATA CHART (SDC) — NOTES") | `ships.json` |
| `ship-log-sample.png`, `ship-log-blank-*.png` | — | Section boxes, morale-check marks per section | `ships.json`, `damage_controller.gd` |
| `diagram-NN-*.png` | — | Diagrams 1–26, cited by rule text (e.g. 20 = rakes, 23 = drifting) | — |

## Finding a rule

Rule paragraphs start with a bold number, `**7.E.2 Rake Definition.**`, with lettered clauses (`a.`, `b.`) below. Line numbers drift, so search:

```bash
grep -n '^#### 7\.E' docs/rules/close_action.md          # section heading
grep -n '^\*\*7\.E\.2' docs/rules/close_action.md        # one rule paragraph
grep -n -i 'in irons' docs/rules/close_action.md         # by term; also check the GLOSSARY
```

Then read the whole section, including its EXAMPLE and EXPLANATION paragraphs and the diagram it cites. Rules cross-reference each other ("see 6.E"); follow the references. The SEQUENCE OF PLAY summary near the end of the rules book lists the phase order.

**OCR traps.** `<mark>…</mark>` marks low-confidence OCR, and unmarked text can be wrong too: symbols such as `≤`/`≥`, `−` and `+`, and digits are the usual casualties (7.E.2 reads "< 5 hexes" where the rule means ≤ 5). When a number, comparison or sign decides the behaviour, check the scan page before coding or asserting it. The page is in the nearest `<!-- pdf p.N` comment *above* the passage (`grep -n 'pdf p\.' docs/rules/close_action.md`, take the last one before your line); if the passage sits near a page break, read page N+1 too. If the scan settles a mis-read, you may fix the text in `close_action.md`.

## Section map

| Topic | Rules | Main Leeward code |
|---|---|---|
| Sequence of play | 2 | `turn_phase_controller.gd` |
| Weather, wind direction/speed, sea state | 3.B–3.E | `environment_controller.gd` |
| Plotting, crew tasks | 4 | `movement_plotting_*.gd`, `sail_controller.gd` |
| MA, turning, tacking, in irons, speed change, sail state, blocked wind | 5.A–5.G | `movement_validator.gd`, `movement_resolver.gd`, `ship_state.gd` |
| Execution, overlap, contested hexes, bearing off, collisions, fouling, illegal moves | 6.A–6.G | `movement_resolver.gd`, `occupancy.gd` |
| Arcs, LOS, gunfire procedure and modifiers, damage, rakes | 7.A–7.E | `fire_geometry.gd`, `fire_rules.gd`, `gunnery_calculator.gd`, `gunnery_resolver.gd`, `damage_controller.gd` |
| Drift, unfouling (fire, repairs, grappling: not implemented) | 8 | `drift_resolver.gd`, `fouling_controller.gd` |
| Crew quality, morale checks, striking | 9 | `morale_controller.gd` |
| Boarding, signalling, towing, anchoring, optional rules | 10–14 | not implemented (see feature_diff §2) |
| Victory, scenarios | Scenario Book ("Standard Victory Determination") | `victory_controller.gd`, `data/scenarios/` |

## Working on game logic

1. **Before changing behaviour:** find the rule and read the chart behind it. Then search `feature_diff.md` for the rule number (`grep -n '7\.E\.2' docs/rules/feature_diff.md`).
   - Listed under §4 *Deliberate simplifications*, or as a decision in §3 (e.g. struck ships cannot be targeted): that is intended. Do not "fix" it to match the book unless the user asks.
   - Listed as **Missing** / **Differs** / **Partly fixed**: a known gap. Fixing it is fine when it is the task.
   - Not listed: if the code differs from the rule, that is a new finding. Report it; add it to the diff.
2. **Tests:** take expected values from the rule or chart, not from what the code currently returns. Name the rule in the test (`# 7.E.2b: adjacent astern is a rake`). Pin dice with `ScriptedDice`; the charts use d10 = 0–9.
3. **After the change:** update `docs/rules/feature_diff.md` in the same change (next section).

## Keeping feature_diff.md current

Update it whenever a change adds, fixes, partly fixes or alters a rule-governed feature, or when you find a new difference. A change with no rule effect (refactor, UI, presentation) needs no update.

- **Status words** (§1 Type column and the lead word of §3's Leeward column): **Missing**, **Differs**, **Partly fixed**, **Fixed**. For a partial fix, say what now matches *and* what is "**Still different:**" or "**Still missing:**".
- **Where rows go:** §1 headline items (keep the number; mark it **Fixed.** rather than deleting it). §2.1 known missing systems (Milestone 2/3), §2.2 missing and untracked. §3 present in both, but the outcome differs: when fully fixed, set the row to **Fixed** with "Matches.", and add the feature to §5. §4 deliberate simplifications: add one only when the user decides to keep a difference. §5 implemented and matching, with rule numbers. §6 items settled from the scans; remove a **?** when the chart or scan settles it.
- **✔** means the finding was checked against the code. Add it only when you have read the code behind the row.
- **Code column:** name the file and function (`movement_resolver.gd` (`_roll_tacking`)), not line numbers, which go stale. Older rows still carry line numbers; replace them in any row you edit.
- **Header:** set "Compared against" to the commit you checked against (`git rev-parse --short HEAD`), and keep the Legend in step if you add a status.
- **CLAUDE.md:** if the change touches a "Known Limitations" or "Not implemented" item there, update that line too, so the two documents agree.
- Write rows in the existing style: plain sentences, rule numbers in the Rule column, outcome effect stated.

## Common mistakes

| Mistake | Instead |
|---|---|
| Taking a number from rule text, v6-1 docs or memory | Read the chart scan |
| Trusting a `data/rules/*.json` value because tests pass | Spot-check it against the scan when the behaviour is in question |
| "Fixing" a §4 simplification | Leave it; ask the user |
| Asserting the code's current output in a new test | Assert the rule's outcome |
| Acting on an OCR'd `<`, `+` or digit | Check the PDF page first |
| Finishing a rule change without touching feature_diff.md | Update the row, the status word and the header commit |
