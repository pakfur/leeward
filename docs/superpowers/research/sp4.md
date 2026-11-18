# Sub-project 4 — Anchoring: decision inputs

Sources read: rules 13.A–F (pdf p.37–38; p.38 rendered and checked against the scan), 8.A.7, 8.B, 2.B.5 / SoP V.A–B,
5.D.4, 5.D.7, 7.C.12c, 9.B.1b, Scenario Book special rule B, Scenario 7 (Nile), tournament map rules; ship log
`ship-log-blank-1.png` (Crew Task Order Codes); diagrams 25–26.

## 1. Rules summary

**Permission.** Scenario Book V.B: anchoring is *not allowed unless the scenario permits it*. Permissions seen:
"anywhere on the board" (Sc. 7 Nile, Sc. 20 Lissa); tournament games: only on hexes xx01–xx15 of each column (a zone).
**No depth limit for anchoring exists in the rules** — depth matters only for grounding (13.G, sub-project 3).

**Crew tasks (ship log, all 1 CS; checked on the scan):**

| Code | Meaning | g-t's | Rule |
|---|---|---|---|
| PBA | Prepare bow anchor | 2 (CQ A–D) / 3 (E–G) | 13.B.1 |
| PSA | Prepare stern anchor | 6 ± SK | 13.B.1 |
| PBS | Prepare bow springs | 2 × (5 ± SK) | 13.B.2 (OCR "2 x ( + SK)" — log and example settle it: CQ C → 8) |
| PSS | Prepare stern springs | 2 × (6 ± SK) | 13.B.2 (CQ C → 10) |
| A | Anchor | 1 | 13.C.1 |
| AX | Cut anchor (cable) | 1 | 13.F.2 |
| VO / VI | Veer out / veer in | 1 | 13.E.1–2 |
| HS | Handle springs | 1 (each g-t the ship turns) | 13.D.3 |

**Preparation (13.B).** Bow *or* stern, never both (13.B.3); PBS only after/with PBA side, PSS with PSA; cannot PBA twice
before anchoring. Springs may be prepared before or after anchoring; if after, they take effect on completion (13.B.2).
Readied anchors/springs stay ready until used (13.B.4). Each ship may anchor at most twice per scenario (13.A.5, 13.F.2).

**Anchoring (13.C).** One CS plots A; the ship may plot **no MPs** that g-t, else the A plot is erased (13.C.1). Announced in
Movement, takes effect in the Maintenance Phase: after the drift roll (the ship may drift normally that g-t), the anchor
counter goes in the bow hex (PBA) or stern hex (PSA): AB / AS (13.C.2; SoP V.B "Anchoring & Towing" sub-phase).
- Anchored ships may use no MPs until the cable is cut; they veer and "must drift"; springs ships may turn (13.C.3).
- Next g-t: automatic drift exactly 1 hex directly to leeward (13.C.5), so the cable is 1 hex (anchor 1 hex upwind of the
  bow/stern). Thereafter no table drift (Diagram 25 example: "would not drift again unless it veers out").
- Normal anchoring: the ship swings to WF=L (AB) or WF=R (AS), 60° per g-t in the Drift phase, fewest g-t's; if exactly
  opposite (AB at WF=R / AS at WF=L) a d6: 1–3 port, 4–6 starboard; keeps that direction (13.C.4).
- Wind direction change: same Drift sub-phase, turns to keep its WF and drifts so bow (stern) is directly downwind of
  the anchor — oblique drift (13.C.6).

**Springs (13.D).** No swing to the wind: keeps its WF; still lies 1 hex downwind of the anchor (13.D.1). May plot one 60°
turn per g-t; AB pivots on the bow, **AS pivots on the stern** (unique in the rules); grappled/fouled cannot turn (13.D.2).
One CS on HS each turning g-t or no turn (13.D.3). Timing: "like all other movement" → Movement Phase.

**Veering (13.E).** VO: 1 CS, ship drifts 1 more hex downwind in the Drift Phase of that g-t; max 3 VOs in effect (cable
1–4 hexes); not on a g-t it turns. VI: undoes one VO, takes effect in the **Movement Phase**; if a ship blocks it, it does
not happen, no collision; not on a g-t it turns. The cable never obstructs. SoP V.A: a veering ship that hits another
rolls for fouling. WS=0 (13.E.3): may anchor or cut, no drift, no VO, no springs; VI allowed.

**Cutting (13.F).** Only cutting (no weighing). AX: anchor removed in the Anchoring sub-phase of that g-t; movement may
be plotted next g-t; no turn/VI/VO on the AX g-t. 13.F.3 / 5.D.4b: a ship at WF=L at the start of the g-t after the cut is
not in irons that g-t (one free g-t to turn to WF=C, still an MA=0 turn → tacking roll without the +1 irons DRM).

**Other.** 5.D.4a anchored ships are never in irons; 5.D.7 a ship in irons may drop anchor. 7.C.12c anchored (normal
or springs) **+1 to the BGN** (chart and `gunfire_modifiers.json` "anchored": 1 agree). 9.B.1b: raking a dismasted anchored
ship causes an MC (already true in code; the sentence only denies anchored ships the towing exemption). Nile special rules:
French start at normal anchor, anchor in the hex ahead of the bow; solitaire French "sit still and fire".

## 2. Current code

- Nothing anchoring-related exists; `turn_phase_controller.gd:_after_prize_step` has `# TODO: sinking, anchors`.
- `data/rules/gunfire_modifiers.json` already has `"anchored": 1`; `GunneryCalculator.preview` (`gunnery_calculator.gd:~100–120`)
  adds flat modifiers (plain_sail, wind_speed_4…) but never `anchored`.
- Crew tasks: `CrewTaskController` (`register_handler`, `begin_turn_tasks`, `advance_tasks` in STATUS_ADJUSTMENT,
  `after_movement`, `force_task`), handler base `crew_task_handler.gd` (`can_plot`, `turns_required`, `prepare`,
  `on_complete`, `cancel_reason`, `after_movement_reason`), models `tack_crew_handler.gd`, `repair_controller.gd`.
  `CombatTables.task_turns` supports `{ad,eg}`, `{sk_base}`, `{fixed}` — **no `2 × (n ± SK)` form**. `crew_tasks.json` lacks
  all nine anchoring codes. Ordered tasks are `plotted_actions.crew_orders` (`sail_target`, `boarding`) placed by
  `CrewAuto.allocate`; legality in `CrewRules.normalize` / `refusal` / `context` (knows `ma0_turn_plotted`).
- Drift: `DriftResolver.resolve` (eligible = didn't move / collided / linked; group drift 8.A.6, `_first_block`, `_try_foul`,
  map edge blocked; WS 0 → nothing). Called alone in `_enter_drift_calculation_phase`. No anchored-ship notion.
- Irons: `MovementResolver._is_in_irons` (speed 0 and WF=L, except `calm_just_ended`); turns pivot on the bow
  everywhere (validator, resolver overlap/contest logic, `HexGrid.stern_of`).
- Plotting: `MovementValidator` errors (`SHIP_FOULED`, `SHIP_GRAPPLED`, …), `DefaultCourse.for_ship`, deceleration minimum
  `MovementValidator.deceleration_error` (5.E.4) — relevant because A needs a 0-MP plot.
- `StubAI`: strategies engage/close/follow/line/disengage via `_steer`; `assign_crew` keeps Automatic on.
- `PlayerView.ship_for` drops `plotted_actions` for others; `crew_tasks` visibility to check.
- Scenarios: no `anchoring` permission field, no initial-anchor field. `draft` is loaded, never read.

## 3. Work breakdown

| # | Component | Files | Size |
|---|---|---|---|
| 1 | Nine task codes + `{sk_base, times}` turns form; validator update | `crew_tasks.json`, `combat_tables.gd:task_turns`, `validate_combat.py` | S |
| 2 | Anchor state: prep (`""/bow/stern`), springs ready, `anchor {hex, end bow/stern, springs, cable 1–4, swing_dir}`, anchorings used, `cable_cut_turn`; serialize; controller mutators | `ship_state.gd`, `ship_state_controller.gd` | S–M |
| 3 | `AnchorController` (new, `scripts/server/`): handler for PBA/PSA/PBS/PSS/A/AX/VO/VI/HS (one instance, like RepairController); `resolve(phase)` = SoP V.A–B for anchored ships: post-anchoring drift, swing to WF (d6), wind-shift reposition, VO, then place/remove anchors; fouling on blocked moves | new file, `game_state.gd`, `turn_phase_controller.gd` (DRIFT_CALCULATION) | L |
| 4 | Drift integration: anchored ships (and groups containing one) skip the d10 table | `drift_resolver.gd` | S |
| 5 | Movement: anchored ships refuse MPs (`SHIP_ANCHORED`), no default course; springs turn (1 per g-t, HS, AS pivots on stern) through validator/resolver or a pre-resolver step; VI; A plot erased if MPs plotted; never in irons / free g-t after AX | `movement_validator.gd`, `movement_resolver.gd`, `default_course.gd`, `movement_types.gd` | M–L |
| 6 | Crew legality + Automatic: refusals (13.B.3, twice limit, permission zone, VO≤3, VI≤VO, no VO/VI/AX with a turn, HS only with springs and a plotted turn, A needs prep), new order `crew_orders.anchor` (prepare_bow / prepare_stern / springs / anchor / cut / veer_out / veer_in) placed by Auto | `crew_rules.gd`, `crew_auto.gd`, `crew_task_controller.gd` | M |
| 7 | Gunnery +1 `anchored` modifier | `gunnery_calculator.gd` | S |
| 8 | Events (ANCHORED, ANCHOR_SWING, VEERED, CABLE_CUT, ANCHOR_PREPARED…) + log text; `PlayerView` (hide prep state, anchor public) | `phase_events.gd`, `player_view.gd`, combat log text | S |
| 9 | Scenario schema: `anchoring` permission, per-ship initial anchor; test scenario; scenario-creator doc | `game_state.gd`/scenario load, `data/scenarios/`, `.claude/skills/scenario-creator/SKILL.md` | S |
| 10 | StubAI anchoring behaviour (scope per Q4) | `stub_ai.gd`, maybe `signal_orders.gd` | M |
| 11 | Tests (task lengths, swing, oblique drift, veering, springs pivot, irons, +1, AI) | `test/unit/test_anchoring*.gd` | L |
| 12 | Docs: feature_diff rows (anchoring, irons exceptions, crew tasks "still missing"), CLAUDE.md | docs | S |
| 13 | UI (only if in scope, Q5): overlay stations/order picker, map anchor marker + cable, card badge | `scripts/ui/crew_overlay/*`, `ship_view.gd` | M |

## 4. Decisions needing the user (by importance)

**Q1. How faithful should springs be?** Springs are the reason to anchor in a fight (a pivoting battery).
- A. Full: PBS/PSS tasks (8–10 g-t's at CQ C), HS each turning g-t, AS pivots on the stern, turn in the Movement Phase
  inside the resolver (new pivot through overlap/contest code). Most faithful; the stern pivot touches the hairiest code.
- B. Full rules, simpler execution: same tasks and HS cost, but spring turns are applied in a short step at the start of
  MOVEMENT_RESOLUTION before other ships move, refused (no collision, no contest) if the swung hex is held. Fires on the
  new bearing the same g-t, as in the book. Deviation only in rare hex contests.
- C. Simplify the prep: springs come free with the anchor (no PBS/PSS), turn as B. Faster to play; loses the long
  decision "prepare springs or not".
- D. Drop springs (normal anchoring only). Anchoring becomes almost useless in combat.
Recommend **B**: keeps every player-facing cost and the timing, avoids a second pivot model in the resolver.

**Q2. Scope cuts.** Which parts ship now? Candidates: (a) veering VO/VI, (b) anchoring by the stern (PSA/PSS, WF=R
swing, stern pivot), (c) the d6 swing direction and "fewest g-t's" swing (vs snapping to the final WF), (d) the
two-anchorings limit. Options: all in / cut (a) / cut (a)+(b). Recommend **all in**: with a derived "anchor hex + cable
length + end" geometry, veering and stern anchoring are small; cutting them saves little and AS+springs is the
historical Nile/Algeciras play.

**Q3. Where may ships anchor, and what does sub-project 3 owe?** Rules: only where the scenario permits; no depth limit.
- A. Scenario field `anchoring`: `false` (default) / `true` / list of hex rows or a zone; no depth check.
- B. A + a house depth limit (e.g. no anchoring in "deep" hexes) from SP3 depth data. More "realistic", not in the rules.
- C. Always allowed everywhere (playability; anchoring becomes a standard option in PVP).
Recommend **A**, with SP3 exposing a per-hex zone/flag query so a zone can be drawn on its map; default off, as the book.

**Q4. AI behaviour.**
- A. Minimal: AI never starts anchoring; AI ships that start anchored stay, prepare springs if allowed, turn (HS) to bear
  on the best target, never cut (Nile solitaire rule: "sit still and fire").
- B. A + cut the cable when ordered to engage/close/follow and no enemy is in range, or when a standing order says
  move (and signals ANCHOR / CUT CABLES added to `SignalOrders`).
- C. B + the AI anchors on its own: emergency anchoring when dismasted/drifting toward land (needs SP3), or holding a
  defensive position.
Recommend **B** now, emergency anchoring (C) once SP3 land exists. "The AI must play every feature" argues against A.

**Q5. Is any UI in scope?** Without crew-overlay stations a human cannot plot A/PBA/HS… in game (only tests/dev commands).
- A. Back end only (as sub-project 2); dev command to anchor/cut.
- B. Back end + minimal: anchoring stations/orders in the crew overlay, an anchor marker on the map, an ANCHORED badge.
- C. Full UX pass (cable lines, swing preview, springs turn on the map).
Recommend **B**, or A if the UX sub-project is planned soon; anchoring is mostly invisible otherwise.

**Q6. Anchoring needs a 0-MP plot, but the deceleration minimum (5.E.4) stops a fast ship from plotting 0.**
- A. Faithful: slow to a stop first (2–3 g-t's from full speed), then A.
- B. Plotting A waives the deceleration minimum (dropping anchor as a brake — the Nile approach, "brought up").
Recommend **A** (it is the rule and gives the decision weight); B only if playtests find anchoring under fire unusable.

**Q7. What blocks an anchored ship's forced moves?** Swing, 13.C.5 drift, 13.C.6 oblique reposition (can be several
hexes at cable 4) and VO may run into a ship. Rules only say "roll for fouling" (SoP V.A).
- A. Treat as drift: blocked → fouling roll, ship stays put (swing/reposition retried next g-t).
- B. Move along the path and stop at the first block (partial reposition, cable effectively shorter).
Recommend **A** (matches 8.A drift code, simple). Ask because it decides how anchored lines of battle jam.

## 5. Decisions the builder can make alone

- Geometry: store anchor hex, end (bow/stern), cable (1 + VOs); the ship's target bow/stern hex = anchor + downwind ×
  cable. Diagram 25 and 13.C.6 are both reproduced by this.
- New `AnchorController` registered as handler for all nine codes; anchor effects run in DRIFT_CALCULATION right after
  `drift_resolver.resolve` (V.A then V.B), not in `advance_tasks` (which is later, STATUS_ADJUSTMENT). Prep tasks
  complete through the normal `advance_tasks`.
- Anchored ship (or a fouled/grappled group containing one) never rolls the drift table; the anchor holds the group.
- The g-t of dropping anchor: normal d10 drift first, then the anchor is placed (13.C.2); the auto drift is next g-t.
- +1 BGN when an anchor is on the map at the combat step: not for an A plotted this g-t, yes on the AX g-t.
- AX ship: free of irons in the g-t after (`cable_cut_turn`), still an MA-0 turn with the tacking roll, no +1 irons DRM.
- VI timing: apply at the start of MOVEMENT_RESOLUTION with the spring turns (same step as Q1-B); blocked → erased.
- WS 0: no swing/drift/VO/HS; VI and A/AX allowed (13.E.3); deferred 13.C.5 drift happens when the wind returns.
- Struck/destroyed/captured anchored ships stay anchored; struck crews and prize crews cannot plot anchoring tasks
  (10.H.2); a destroyed ship's anchor is removed with it.
- Task lengths recomputed from current CQ each g-t (9.A.2), minimum 1; `{sk_base: 5, times: 2}` = 2 × max(1, 5+SK).
- Anchor counter and anchored state public; preparation progress hidden by `PlayerView` (log is secret).
- Scenario fields: `"anchoring": true|false|{"rows": [1,15]}` (per Q3) and per-ship `"anchor": {"end": "bow",
  "springs": false, "cable": 1}` placed one hex upwind of the bow (Nile).
- Sail state is unaffected by anchoring (players may furl to save rigging, 13.A.1); no forced sail change.
- Events and combat-log wording; dev command `dev_commands.anchor_ship` for testing.

## 6. Cross-sub-project dependencies and risks

- **SP3 (map):** needs (a) a per-hex query for the anchoring zone (Q3) — not depth; (b) land/shallows as blockers for
  anchored-ship moves and grounding when a swing/veer/reposition enters them (13.G.2: drifting aground costs no rigging);
  (c) the existing "map edge blocks drift" rule kept for anchored moves. Agree a shared "forced move" helper so drift,
  veering and grounding use one block/foul/aground check.
- **SP5 (towing):** shares SoP V.B sub-phase and tasks (PT/TX), 5.D.7 "towed out of irons", 9.B.1b towing exemption.
  Put the anchoring step in a function towing can join.
- **Movement resolver risk:** any spring turn inside the resolver (Q1-A) touches overlap/contest/rollback replay logic;
  Q1-B isolates it. Anchored ships must also be immovable obstacles in bear-off/collision code (speed 0, no plot).
- **Crew engine risk:** A/AX/VO/VI/HS take effect mid-turn (drift/movement), not at `advance_tasks`; the handler hooks
  need a "takes effect in phase X" path without breaking task bookkeeping (cancelled-if-MPs-plotted at `finalize_plots`).
- **Server authority:** all orders through `player_plot_crew` (crew_orders) and the springs turn through
  `player_extend_course`; `test_server_authority.gd` must cover new ShipState fields (`anchor`, prep) as view-forbidden.
- **Deceleration (Q6):** if A is chosen, the AI must plan stops ahead (StubAI `_meet_deceleration_minimum` works the
  other way); adds AI work in Q4-C.
