# Sub-project 7 — Optional rules (14.A, 14.B, 14.D, 14.E): decision inputs

Sources read: `docs/rules/close_action.md` ch. 14, checked against the scan (PDF pp. 39–40, Rules Book pp. 36–37, rendered to PNG); `feature_diff.md` §2 row "Optional rules (14)"; roadmap; the code below. 14.C is done (`player_view.gd`, scenario flag `"tournament"`).

## 1. Rules summary

**14.A Impulse movement** (Rules Book p. 36)
- 14.A.1: standard movement is "front-loaded" (a slow ship's MPs are spent in the same early segments as a fast ship's). Book: impulse movement is for very small actions, "emphatically not recommended for fleet actions" (the reason is table look-ups, which a computer removes).
- 14.A.2: 4 impulses per Movement Phase; a ship uses 0–3 MPs per impulse by plotted MPs (turns count as MPs). Table (scan-checked, image `rb-p36-1.png`):

  | MPs | I1 | I2 | I3 | I4 |
  |---|---|---|---|---|
  | 1 | – | – | 1 | – |
  | 2 | – | 1 | – | 1 |
  | 3 | – | 1 | 1 | 1 |
  | 4 | 1 | 1 | 1 | 1 |
  | 5 | 1 | 1 | 2 | 1 |
  | 6 | 1 | 2 | 1 | 2 |
  | 7 | 1 | 2 | 2 | 2 |
  | 8 | 2 | 2 | 2 | 2 |
  | 9 | 2 | 2 | 3 | 2 |
  | 10 | 2 | 3 | 2 | 3 |

  Max MA in `movement_allowance.json` is 10, so the table covers every speed.
- 14.A.3 Plotting unchanged; the plot is followed without deviation except bearing off and collisions. (14.A.3/14.A.4 headings are lost in the OCR; recovered from the scan.)
- 14.A.4 All movement of an impulse finishes before the next; within an impulse movement is front-loaded with the normal rules. Example: A plots 8, B plots 6; impulse 1 A uses 2, B 1 (the book misprints "ship A" for B); both use 1 in segment 1, A its 2nd in segment 2.
- 14.A.5 Overlaps (6.B) allowed if cleared by the end of the Movement Phase. 14.A.6: two ships entering one hex in the same segment of the same impulse → normal ch. 6 rules.
- 14.A.7 Optional gunfire (an option within the option): for "only one or two ships per side", gunfire may be resolved at the end of any impulse. The entire move of both ships is read out at the start of the g-t so players know the best impulse. (a) a ship fires once per g-t; (b) not on consecutive impulses, even across g-t's; reload impulses: CQ A/B 1, C/D 2, E/F/G 3. Example (scan; the OCR says "impulse 4", the scan says 1): Pluton CQ C fires at impulse 2, reloads 3–4, may fire impulse 1 next g-t; at CQ E she could fire only from impulse 2. Formula: next allowed global impulse = last + reload + 1.

**14.B Voluntary surrender** (p. 37)
- 14.B.2: a ship at CQ F or G, **or** with ≥ 5 sections lost (rigging, hull, crew in any combination) may surrender before it is forced to strike. Treated exactly as struck: does nothing but fight fires, may not be fired on, boarding succeeds automatically; once captured it cannot rally.
- 14.B.3 Rally "at any time after it has surrendered": take an MC; pass → moves and fights normally; fail → drops one CQ; may keep trying until it succeeds or strikes from successive failures (fail at G = struck for good, as 9.C).
- 14.B.4 A ship cannot rally twice: a second surrender is permanent.

**14.D Fatigue** (p. 37)
- 14.D.2: after the 5th time a ship has fired her guns in a game, all later fire −1 (booked as an extra "guns dismounted", i.e. −1 on the MGN, all broadsides). 14.D.3: a further −1 every 10 more firings: "g-t's 15, 25, 35". No recovery. Ambiguity: whether the −2 starts on the 15th or the 16th firing (see §5).

**14.E Historical gunfire limits** (p. 37; numbers scan-checked)
- 14.E.3: a CQ E/F/G ship wishing to fire low rolls a d6 when it fires; 4+ → must fire high (50 %). Applies to any navy (14.E.2 is only the French rationale).
- 14.E.4 "Alternate Rule": a ship at WF=C or WF=B firing **to windward** and wishing to fire low: d6, 4+ → high. "Alternate" suggests an either/or with 14.E.3. High is always allowed.

## 2. Current code

- **Movement**: `MovementResolver.run` / `_resolve_pass` / `_resolve_impulse` (`scripts/server/movement_resolver.gd`, 2130 lines). "Impulse" in the code is a segment = a ship's i-th plotted step (`ship_steps[impulse]`), i.e. fully front-loaded. ~219 references to impulse/segment carry "index = step index" semantics: `_find_tacking_impulse`, `_all_on_last_step` (6.C.1b), `_deceleration_minimum(...) <= impulse`, rollback `segment`s and `_amended_steps`, `_segment_hex_key`, bear-off `situation.segment`, `resume_impulse`, `max_impulses`. Replays from `rng_start` require earlier segments to stay identical across passes.
- **Playback**: `scripts/view/movement_resolution_playback_controller.gd` groups events by `ev.impulse` and glides stretches between event segments; it already tolerates ships idle in some segments. Bear-off pause = play to `pending_bear_off.segment`, then `TurnPhaseController.on_playback_paused` / `player_submit_bear_off` re-run from `resume_impulse`.
- **Turn cycle**: `TurnPhaseController._enter_movement_resolution_phase` → `on_playback_completed` (apply results) → `_enter_combat_resolution_phase` (boarding `declare`, skip test via `any_eligible_shot`, DECLARE: `fire_declaration_requested`, `StubAI.submit_fire_orders`, `player_submit_fire_orders`) → `_resolve_combat` (marine `prepare`, `gunnery_resolver.resolve`, marine `resolve`, `boarding_controller.resolve`, `combat_log_ready`). One combat step per g-t, on end-of-movement positions.
- **Gunnery**: `GunneryCalculator.preview` reads poses straight from `ShipState` (`occupied_hexes`, `facing`, `_occupied_hexes`, `friendly_ships`); `FireGeometry` itself is pure (hexes + facing in). Modifiers via `_add_modifier`; `guns_dismounted` is `-guns_dismounted[side]` (fatigue slots in beside it). Aim: `FireRules.make_order` / `effective_aim` (forced high at range ≥ 10); `GunneryResolver._resolve_shot` rolls d6s in a documented order (tests script it). `FireGeometry.leeward_side(facing, wind_dir)` exists (used by 7.F.2) — gives "to windward" for 14.E.4. `ShipState.initial_broadside_fired` is the only firing history; no fire count.
- **Morale/strike**: `MoraleController._check` (d10 ≥ MR passes, fail → CQ −1, fail at G → `DamageController.strike`). `DamageController.strike(ship_id, reason, phase)` sets STRUCK, logs STRIKE, cancels all tasks but FF. Callers: morale, fire (`hull destroyed`), crits (`waterline`). STRUCK→ACTIVE never happens today; 85 `is_struck`/`is_out_of_play` uses (15 in view code). `FireController.skill` treats struck as CQ G without changing `crew_quality` (good for a rally).
- **Victory**: `VictoryController.points_lost` (struck = 100 %), `check` ends the game at END_TURN when a side has no ship in play ("all struck") or none able to move or fight.
- **AI**: `StubAI.submit_fire_orders` / `choose_fire_orders` / `choose_marine_orders`; no surrender notion.
- **Switch model**: `PlayerView.limited()` reads `game_state.active_scenario.get("tournament", false)`; `year`, `turn_limit` read the same way. No options UI; no `start_scenario` override.

## 3. Work breakdown

| # | Component | Files | Size |
|---|---|---|---|
| A | Option switches: `OptionalRules` static reader over `active_scenario.optional_rules` (+ `start_scenario` override dict for tests/lobby), scenario-creator skill schema | new `scripts/server/optional_rules.gd`, `game_state.gd`, skill doc | S |
| B | 14.D fatigue: `ShipState.gunfire_count` (serialize), increment once per g-t a ship fires any battery (`GunneryResolver`), `fatigue` modifier in `preview`, AI unaffected | `ship_state.gd`, `ship_state_controller.gd`, `gunnery_resolver.gd`, `gunnery_calculator.gd` | S |
| C | 14.E limits: one d6 per firing ship with a low order that qualifies, rolled before its shots (dice-order contract updated), aim forced high, `AIM_FORCED` in the FIRE event; preview carries "low: 50 %" note; windward test via `leeward_side` + wind facing | `gunnery_resolver.gd`, `fire_rules.gd`, `gunnery_types.gd`, `phase_events.gd` | S |
| D | 14.B surrender/rally: `player_surrender` / `player_rally` requests (validated: option on, commander, eligibility, phase), `ShipState.surrenders` (0/1/2) + `surrendered` flag, `DamageController.strike(..., "surrender")`, new `ShipStateController` un-strike path (ACTIVE, crew auto plan, default course), rally MC through `MoraleController`, events SURRENDER / RALLY, `PlayerView` (public), victory unchanged, AI policy | `turn_phase_controller.gd`, `damage_controller.gd`, `morale_controller.gd`, `ship_state*.gd`, `stub_ai.gd`, `phase_events.gd`, `test_server_authority.gd` | M |
| E | 14.A movement: impulse schedule (table → global segment = 3·(impulse−1) + slot, 12 segments), resolver iterates global segments and maps to step index per ship; every step-index assumption audited (tacking, 6.C.1b, deceleration minimum, rollbacks, contests, bear-off segments, poor-maneuvering, cycle breaks); playback unchanged but longer (maybe skip empty segments) | `movement_resolver.gd`, `movement_types.gd`, new `impulse_table.json` + `DataManager`, playback controller (small) | **L, high risk** — the resolver is the most intricate file; every recent movement bug lived in the rollback/replay logic |
| F | 14.A.7 fire at end of impulse (reduced form, see Q2): resolver records poses at the end of each impulse (`log.impulse_poses[k]`); `FireOrder.impulse`; pose override threaded through `GunneryCalculator.preview`/`eligible_shots`/`validate_orders`/`friendly_ships`/`_occupied_hexes`; reload state `ShipState.last_fire_impulse` (global) + once per g-t; `_resolve_combat` resolves gunfire impulse by impulse (damage applied between), marine fire and boarding after; HOLD_FIRE across impulses; AI picks best (impulse, shot); fire panel would need an impulse picker and ghost poses (UI) | `turn_phase_controller.gd`, `gunnery_*.gd`, `fire_rules.gd`, `movement_resolver.gd`, `stub_ai.gd`, view later | **L** (back-end M–L; UI L) |
| G | Full interleave (movement playback paused at each impulse for a declaration round): new phase sub-steps, apply partial movement results, struck-mid-move handling, bear-off pause inside an impulse, 4 declaration round trips per g-t in PVP | everything in E+F plus phase machine, playback, `apply_results` | **XL** — not recommended |
| H | Docs/tests: feature_diff §2 → §3/§4/§5, CLAUDE.md, GUT tests per rule with ScriptedDice, a 1v1 impulse scenario | docs, `test/unit/` | M |

Honest view of 14.A: E alone changes only who reaches a contested hex first; its value is invisible unless the playback shows ships moving at proportional speed (which it would, nicely). E+F is the version that changes play (no sailing past without a shot). Both touch the resolver/turn cycle that sub-projects 3 (grounding, casting the lead bears off mid-move) and 5 (towed pairs) will also change.

## 4. Decisions needing the user (by importance)

**Q1. Is 14.A worth building, and in what form?**
- (a) Skip 14.A entirely; record as "not offered" in §4. Zero risk; loses the only rule here that changes tactics.
- (b) Impulse movement only (E). L-cost resolver change for a subtle effect.
- (c) E + 14.A.7 in reduced form (F): movement resolved and played in full as now; then one simultaneous declaration where each ship picks its impulse; gunfire resolved impulse by impulse on the recorded poses. Matches 14.A.7's "entire move read out at the start" and 14.A.3's "plot followed without deviation"; bear-off pause untouched.
- (d) Full interleave (G). Most faithful feel, XL, 4 PVP round trips per g-t.
- Recommend **(c)**, built last and behind its own flag, after sub-projects 3 and 5 land. Optionally (c′): F without E (impulse fire over standard front-loaded segments, 4 slices of 3 segments) — cheaper but ill-defined; not recommended.

**Q2. Impulse fire: one declaration or one per impulse?** (only if Q1 = c/d)
- (a) One declaration per g-t carrying an impulse per ship; later-impulse shots of a ship struck/dismounted earlier are void or weakened. One PVP round trip; no reacting to earlier results.
- (b) Four declaration rounds (only impulses where someone can fire). Lets players react; 4× waiting in PVP.
- Recommend (a).

**Q3. When may a ship surrender, and when does it take effect?** (the PVP exploit: surrender just before a broadside, rally after)
- (a) Request in PLANNING; takes effect at once (visible; no movement, cannot be fired on this g-t). Faithful ("may not be fired upon"), but dodges this g-t's fire.
- (b) Request in PLANNING; colours struck at MORALE_CHECK of that g-t (moves per plot and can be fired on this g-t, does not fire). No dodge; simultaneous for both players.
- (c) Request also in fire DECLARE, effective at end of combat.
- Recommend (b). Rally: request in PLANNING, MC rolled at once, a passed ship plots this g-t.

**Q4. Surrender in 1v1 = conceding?** A surrendered ship counts as struck, so a side whose ships are all surrendered loses at END_TURN before it can rally (2.A.1).
- (a) Faithful: yes, and rally only matters with several ships per side.
- (b) A voluntarily surrendered ship that may still rally does not count for "all struck"/"unable to move or fight" until it is captured, permanently struck, or the turn limit.
- Recommend (a), and treat surrender of the last ship as the 1v1 "concede" (pairs with 2.A.1 end by agreement).

**Q5. Switch granularity and who sets it.**
- (a) Scenario JSON block `"optional_rules": {"impulse_movement", "impulse_fire", "voluntary_surrender", "fatigue", "gunfire_limits": "crew"|"heel"|"both"|none}`, defaults off.
- (b) Same plus an override passed to `start_scenario` (future lobby/match settings, tests).
- (c) A preset ("historical") instead of flags.
- Recommend (b), back-end only. Also: enforce 14.A.7's "one or two ships per side" (refuse/warn), or trust the scenario? Recommend trust the scenario, warn in the log.

**Q6. 14.E: alternatives or combinable?** (a) scenario chooses crew rule or heel rule; (b) both may be on, one d6 covers both (forced high if either condition holds and the roll is 4+); (c) both on, separate rolls (low only ~25 %). Recommend (b) when both set.

**Q7. AI behaviour for surrender.** The stub AI must rally at least (it can be left surrendered only by the forced rules).
- (a) AI never surrenders voluntarily; never needs to rally.
- (b) AI surrenders when eligible and an enemy with readied boarders is linked or it faces ≥ 2:1 odds within range 3; rallies in PLANNING when no enemy within 5 hexes.
- Recommend (b) simple heuristic — otherwise the feature is untestable against the AI.

**Q8. Fatigue as written, or a playable variant?** As written it is a permanent creeping −1/−2 that no one sees. Options: (a) as written; (b) as written plus shown on the ship card later; (c) recovery (−1 removed after N g-t's without firing) as a §4 deviation. Recommend (a) now (UI in the UX pass).

**Q9. UI in scope?** Previous sub-project was back-end only. 14.A.7 has no usable human flow without an impulse picker with ghost poses; surrender/rally need two buttons. Options: (a) back-end + AI + tests only; (b) also minimal buttons (Surrender/Rally on the card, impulse dropdown in the fire panel). Recommend (a), but if Q1 = c, ship F's back-end and leave `impulse_fire` unplayable by humans until UX — or defer F to the UX pass.

## 5. Decisions the builder can make alone

- Impulse schedule from the plot's MP count after poor-maneuvering, fixed for every pass; steps added by rollbacks/bear-offs (deceleration minimum) fill the ship's remaining slots, then trail after impulse 4 in segment order — keeps replays deterministic.
- Global segment index = 3·(impulse−1) + slot; empty segments skipped in `max_impulses`/playback timing.
- A tack at MA 0 (one turn, 1 MP) keeps its pre-movement roll; the turn executes in its scheduled slot (impulse 3).
- 6.C.1b "no further MPs" = last plotted step overall, not within the impulse.
- 14.A.7: all batteries of a ship fire on the same impulse (once per g-t, 14.A.7a); marine fire and boarding stay at the end of movement; reload uses CQ at the time of the shot that starts it; reload carries across g-t's via a global impulse counter; a ship that did not fire last g-t is always loaded.
- 14.A.7 poses: a ship fouled/collided/stopped mid-move keeps its pose from then on; a ship struck at an earlier impulse cannot fire later (it is out of play) but keeps moving per plot (14.A.3).
- Fatigue counts g-t's in which any battery fired (not shots or targets); penalty = 0 if prior firings < 5, else 1 + floor((prior − 5)/10) (so −1 from the 6th firing, −2 from the 16th; "after" read consistently). Shown as modifier `fatigue`, not merged into `guns_dismounted`.
- 14.E: one d6 per ship per g-t, rolled just before its first shot in resolution order, only if it has a qualifying low order; applies to every navy; "to windward" = firing side ≠ `leeward_side`; WF from the ship's current facing; not marine fire.
- 14.B eligibility: sections lost = emptied rigging + hull + sailor sections + marine section, excluding sections emptied by detaching a prize crew (as victory does); ships already struck, captured, destroyed or prizes cannot surrender; the commander requests (team play), not the senior player.
- Rally = one normal MC (d10 ≥ MR); fail lowers CQ; fail at G = permanent strike (reason "morale"); rally only from a voluntary surrender; after a rally a second surrender is permanent; a rallied ship re-enters with Automatic crew plan and its default course; grapples/fouling kept.
- Victory: surrendered = struck (100 %) while surrendered; a rallied ship scores by sections again.
- Limited information: surrender state is public (flags were visible); fatigue count public (guns data, 14.C.1d).
- Events: SURRENDER, RALLY (with roll), GUNFIRE_AIM_FORCED (or a field on FIRE), FATIGUE noted in the FIRE modifiers; none count boxes, so no `BOX_FIELDS` change.

## 6. Dependencies and risks

- **Sub-project 3** (grounding, casting the lead bear-off, map exit mid-move) and **5** (towing: towed pair moves as one, towing DRMs) both edit `MovementResolver`. Building 14.A before them means re-auditing every new step-index assumption; build 14.A last.
- **Sub-project 6** (chase guns, medium guns, class 4): chase guns add arcs to `GunneryCalculator.preview`; the 14.A.7 pose override must cover them. Lower-deck/leeward helpers are shared with 14.E.4.
- **Sub-project 2** (done): requests take `player_id`; surrender/rally must use `commands(player_id, ship_id)`; AI per player.
- **Resolver risk**: rollback/replay determinism (`rng_start`, `settled_contests`, cycle breaks) is fragile; 14.A must be a pure re-indexing with the flag off producing byte-identical logs (golden-log tests on existing scenarios).
- **Un-striking** is new: audit the 85 `is_struck`/`is_out_of_play` sites for state cached at strike time (crew tasks cancelled, boarding actions ended as "defender struck", AI target lists, `linked_at_plot`, view wreck/flag visuals — 15 view sites).
- **PVP**: 14.A.7 and 14.B add hidden-information and timing questions (Q2, Q3); keep all new orders simultaneous and server-validated.
- **Dice-order contracts** in `GunneryResolver` change with 14.E; tests that script dice by position stay valid only with the option off.
