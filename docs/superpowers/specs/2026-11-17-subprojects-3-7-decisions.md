# Sub-projects 3–7: decisions register

Date: 2026-11-17. The user's answers to the up-front design questions for roadmap sub-projects 3–7
(`2026-11-16-feature-gap-roadmap-design.md`), and the calls left to the builder, recorded before the work
runs unattended. Each sub-project still gets its own design (`docs/superpowers/specs/`) and plan
(`docs/superpowers/plans/`) written from this register; anything a design settles beyond it is marked as
the builder's call there. **U** = the user's answer (binding). **B** = the builder's call (may be revised by
a design if the code shows a better way; any revision is noted in the design and in the run's ledger).

Guiding principles (user, 2026-11-16): playability and fun before fidelity; deviations go in
`feature_diff.md` §4; the end goal is networked 1v1 and team PVP (server-authoritative, every request
validated against the requesting player); the stub AI must play every feature.

## 0. Cross-cutting

- **U — UI scope: view-only minimum.** Draw the new state: land/shallow hex tints with the depth range,
  edge markers, views for arriving ships, anchor marker, tow line and the towed ship following in
  playback, proportional-pace playback, badges (AGROUND, ESCAPING, ANCHORED, TOWING/IN TOW,
  SURRENDERED), combat-log lines. No new input controls: orders go through server requests (and the
  Developer UI's `dev_commands` for manual testing). A later UX pass adds controls.
- **U — Integration: merge and push main** after each sub-project once `make test` is green and the final
  review and SCV audit are clean; the next starts from that main.
- **U — Unattended run.** The user monitors and answers unanticipated questions.
- **B — Order of work:**
  1. Proportional movement (from sub-project 7). It changes how the movement resolver schedules steps,
     and grounding (3) and towing (5) both add per-step resolver rules that should be built and tested
     on the final schedule.
  2. Sub-project 3, map and scenario.
  3. Sub-project 4, anchoring.
  4. Sub-project 5, towing.
  5. Sub-project 6, ships and guns.
  6. The rest of sub-project 7: 14.B, 14.D, 14.E.
- **B — Workflow:** per sub-project, a design, a plan, then subagent-driven execution in a worktree with
  per-task reviews, the whole-branch review and the SCV audit. Rulings go in the ledger and, where they
  touch rules, in `feature_diff.md`.
- **B — Players and victory:** new requests take a `player_id` and check `GameState.commands`.
  `VictoryController` stops hard-coding sides 0/1 while it is touched (sub-project 3).

## 1. Proportional movement (replaces 14.A)

The user's direction: instead of 14.A's impulses, get the same outcome, *faster ships beat slower
ships*. All plotted movement is resolved simultaneously, each ship moving at a pace proportional to its
speed. When two ships plot into the same hex, the faster gets there first, and the slower goes through
collision / bear-off resolution during movement resolution.

- **U — Replaces front-loaded movement in every game** (no option). feature_diff §4: a deliberate
  change; 14.A (and 14.A.7) closed as replaced / not offered.
- **U — Pace = MPs plotted this turn.** Step k (1-based) of an N-step plot (turns count as steps, as for
  speed) happens at time k/N of the turn.
- **U — Gunfire stays after movement.** No impulse fire.
- **U — Exact ties** (equal k/N) use today's simultaneous rules: potential collision / bear-off for both,
  the 6.C stern contest.
- **B — Mechanics:**
  - The resolver's segments become the distinct times k/N over all ships, in increasing order. Times
    are compared exactly as integer cross-products, never floats.
  - On each segment only the ships with a step at that time move.
  - Every existing per-segment rule keeps working per segment: overlap cleared "by the end of the next
    segment" (6.B), 6.C.1b, bear-off pauses, the 6.D.3c order, cycle breaks.
- **B — Fixed schedule:**
  - A ship's schedule comes from its plot as it stands when resolution begins, after poor maneuvering.
  - Steps added later by a rollback or bear-off amendment (the deceleration minimum) take the ship's
    next unused times on its schedule. If none are left, they trail after the last segment in order.
    Replays therefore stay deterministic.
  - A tack at MA 0 (one turn) keeps its pre-movement roll and happens at time 1/1.
- **B — Playback:** each ship glides at its own pace and every ship's move ends together. The total
  playback time per turn is unchanged.
- **B — 6.B.2 overlap window:** "the next segment" now means the next distinct time at which either of
  the two ships moves. Otherwise a slow ship's swinging stern would be judged on a segment in which
  neither ship moves.

## 2. Sub-project 3 — map and scenario

- **U — Typed edges, rectangle board.**
  - The board becomes a true rectangle (offset rows) with N/S/E/W edges.
  - Each edge is `open` (a wall: plots off it are refused, drift stops), `none` (a ship forced off by
    drift, bear-off or collision is destroyed; plotting off it is refused) or `escape` (a ship that has
    declared escape leaves and is saved).
  - **The user's note:** typed boundaries will later carry land and shore lines, ports and other
    natural and man-made obstacles, so build them as a general mechanism, not a special case for the
    four map edges.
- **B — How "general" is built:**
  - One terrain model (`TerrainMap`, pure, in the state layer) holds typed hexes (`land`, shallow areas
    with a base depth and a die) and a typed boundary list.
  - A boundary is a set of hex sides with a type (`open`, `none`, `escape`) and an optional name.
  - The four map edges are just the boundaries a rectangular board generates.
  - Queries ask "what does crossing from hex A to hex B mean", so a coastline or harbour boom can be
    added later as more boundaries or hex types without touching movement code again.
  - Ports and obstacles are not built now.
- **U — Depth random per entry, as the rules:**
  - A shallow area's depth is base + d6, rolled each time a bow enters (13.G.2a: aground when depth
    ≤ draft).
  - The map shows each area's range.
  - Depth rolls in movement come from the resolver's RNG, so re-runs repeat them. This is the accepted
    Dice exception, like 6.D.3c.
  - Drift depth rolls go through `game_state.dice`.
- **U — Plots that would certainly run aground are allowed** (as the rules). No server refusal into land
  or certain shallows. *(The stub AI still avoids them.)*
- **U — Aground counts as lost:**
  - Scores 100 % to the enemy and is not "able to move or fight".
  - A scenario flag `aground_counts_lost: false` turns that off.
  - The ship stays on the map, cannot fire its guns, plot or drift, can use marine fire, board and be
    boarded, and can be fired on.
  - Running aground in movement stops the ship and costs rigging as a collision (6.E.3). Drifting
    aground costs none. It never refloats (13.G.3).
- **U — Escape: share + window.**
  - Scenario `escape`: which sides may escape, from which turn, at which edges, and the share of an
    escaped ship's value its side scores.
  - The enemy still scores the escaped ship's damaged sections (VI.B.6).
  - An escaped ship is off the map, out of play and not lost. "All struck" ignores escaped ships
    (VI.A.1c).
  - The D.1 conditions are checked at END_TURN, after the 8.G.1f removal and before the victory check:
    a. off an escape edge; b. ≥ 31 hexes from every enemy; c. 20–30 hexes and the ship's maximum MA at
    its WF is ≥ that of every enemy 20–30 hexes off of the same or larger class.
  - The declaration is a request, `player_declare_escape(player_id, ship_id, on)`, made in PLANNING.
  - The enemy learns of the declaration at the end of that turn (D.4), through an event that
    `PlayerView` releases then.
  - No special-victory vocabulary.
- **B — Escape and the AI:** the AI escapes when the scenario gives its side an escape posture
  (`ai: {"<side>": "escape"}`) or a DISENGAGE signal is in force and escape is permitted. It declares,
  then runs for the escape edge or opens the range.
- **U — Casting the lead is an explicit order.**
  - A per-ship order for the turn, `player_set_cast_lead(player_id, ship_id, on)`, valid only with
    ≤ 2 MPs plotted (checked in `plan_errors`).
  - The depth is learnt just before each hex is entered. A ship that would ground bears off
    automatically, which always succeeds, except Poor Maneuvering, which uses the PM table.
  - **B:** the bear-off goes to the deeper side, with no prompt. The AI casts the lead whenever its
    course enters a shallow hex that may be too shallow, at ≤ 2 MPs, and otherwise steers clear.
- **B — Reinforcements:**
  - A scenario ship may carry `arrives: n` (and optionally a sail state; the default is PS).
  - It exists from the start but is not on the map and not out of play.
  - It is placed at the start of turn n's ENVIRONMENT phase. Its last speed is its PS maximum at that
    WF/WS, so the deceleration limit applies (2.B.1, 3.A).
  - If its entry hex is occupied, it waits a turn and that is logged.
  - Victory and defeat checks count it as alive. AI, signals and orders skip it until it arrives.
  - The view makes its ship view when it arrives.
  - Variable entry rolls (Scenario 12) are left out and recorded in feature_diff.
- **B — Land blocks LOS** (7.B.7–9), through the existing blocking-set path of
  `FireGeometry.has_line_of_sight`. Shallow water does not block it, and land does not block wind.
- **B — Scattering (V.C)** is out of scope; recorded in feature_diff.

## 3. Sub-project 4 — anchoring

- **U — Springs: full cost, simple turn.**
  - Preparing springs takes 2 × (5 ± SK) turns at the bow and 2 × (6 ± SK) at the stern.
  - Hauling (HS) takes the cost listed in the rules.
  - Spring turns are applied in a short step at the start of MOVEMENT_RESOLUTION, before other ships
    move. A turn is refused (logged) if the hex it swings into is held.
  - The ship fires on the new bearing that same turn.
- **U — A ship must slow to a stop first.** Anchoring needs a 0-MP plot, and the deceleration limit
  stands.
- **B — Scope: all in.** That covers bow and stern anchoring, veering out and in, the swing with its
  d6 direction, the two-anchorings limit, cutting and weighing, the anchored +1 gunfire modifier
  (7.C.12c), and the in-irons exceptions (5.D.4a–b, 13.F.3).
- **B — Where:** a scenario field `anchoring`: `false` (the default, as the rules), `true`, or a zone
  of hex rows or a terrain area. There is no depth limit (the rules have none).
- **B — AI:**
  - Ships that start anchored stay, prepare springs and haul to bear on the best target.
  - They cut the cable when a standing order says move and no enemy is in range.
  - Signals ANCHOR and CUT CABLES are added to `SignalOrders`.
  - Emergency anchoring when drifting toward land or a `none` edge.
- **B — Blocked forced moves** (a swing, the 13.C.5 drift, the 13.C.6 reposition, veering out into a
  held hex) are treated as a blocked drift: a fouling roll, and the ship stays put.
- **B — Mechanics:**
  - A new `AnchorController` handles the nine task codes.
  - The anchor effects run in DRIFT_CALCULATION right after drift.
  - An anchored ship (or a group containing one) never rolls on the drift table.
  - The anchor state is public; preparation progress is hidden by `PlayerView`.
  - A scenario ship may start with `anchor: {...}`.

## 4. Sub-project 5 — towing

- **U — The towed ship follows in the wake.** On each step the tower makes, the towed ship's bow takes
  the hex the tower's stern just left, pointing at the tower. This is a deliberate change for a turning
  tow, recorded in §4.
- **U — Starting a tow is faithful:**
  - Prepare to Tow takes 5 ± SK turns.
  - The tower's stern must be directly ahead of the tow's bow.
  - Then a grapple roll at ≤ 2 with the towing −1, under every 8.C limit, including both ships using
    ≤ 2 MPs that turn.
  - Cut Tow takes 1 turn.
- **B — Blocked tows:**
  - When the tower is stopped by a collision, the towed ship rams it (automatic collision, rigging loss,
    fouling roll, tow kept).
  - A follow move into a hex held by a third ship undoes the tower's step, like an overlap rollback.
  - No momentum is invented for the towed ship.
- **B — What may be towed:** friendly ships and friendly prizes (10.H.2), but not own-side struck ships,
  which have surrendered.
- **B — Speed and handling:** the 12.A.7 MA loss, the tacking +1 for the tower, and 5.E.5 acceleration
  through the existing `towing` readers. Drift as one group (8.A.6). On hull critical #6, a 1 on a d6
  cuts the tow. The 9.B.1b exception applies.
- **B — Escape:** a towed ship escapes with its tower and scores as escaped.
- **B — AI:** with no enemy within 8 hexes, it prepares and tows its nearest friendly dismasted ship or
  prize toward its side's escape edge (or away from the enemy). It cuts the tow when an enemy closes
  within 3 hexes.
- **B — Mechanics:** the tow is set up in the GRAPPLE maintenance step. It is cut automatically when
  either ship strikes, is destroyed or is taken.

## 5. Sub-project 6 — ships and guns

- **U — Chase guns: simple chasers** (house rule, recorded in §4):
  - 1 long-gun factor per end on every ship.
  - A 60° arc dead ahead of the bow hex and dead astern of the stern hex, to range 15 as long guns.
  - Round shot only, no initial-broadside or rake bonus, and no lower-deck or guns-dismounted effect.
  - A chase battery is one of the ship's ≤ 2 targets.
  - The AI uses it when no broadside bears.
  - Under the view-only scope, the fire panel lists the chaser rows (that is drawing an existing
    control's rows, not a new control).
- **U — All 41 Ship Data Chart types:**
  - Nation-prefixed ids (`br_74`, `fr_80`, `sp_112`, `am_44`, …); the three old ids are kept as
    aliases.
  - Also three class-4 corvettes and brigs from the scenario orders of battle (the chart has none), and
    Diomede (two-decker 44, the only ship with medium guns).
  - Transcribed with a validator, and every row is checked against the scan (PDF p.106).
- **U — No per-scenario overrides** of type data yet. Odd ships become their own types.
- **U — Small procedural-model tweak:** deck count from gun decks, and a brig or sloop rig for class 4
  (view only).
- **B — Lower-deck guns (7.F, 3.E.1) are already done.** Only tests for the other freeboards are added
  and the row is closed. Medium guns are already in the code; a Diomede test covers them.
- **B — Costs:** a type's `nationality` is its builder; the scenario `navy` is its user. Costs are read
  from the type row, and only the filled cells are stored.

## 6. Sub-project 7 — remaining optional rules (each a scenario switch)

- **B — Switches:**
  - A scenario `optional_rules` block: `voluntary_surrender`, `fatigue`, `gunfire_limits`
    (`"crew"`/`"heel"`/`"both"`), all off by default.
  - `start_scenario` takes an override (future lobby settings, tests).
  - Proportional movement is not a switch (§1).
- **U — 14.B surrender takes effect at the end of the turn it is ordered:**
  - It is ordered in PLANNING (`player_surrender`).
  - The ship moves per its plot and may be fired on that turn. It does not fire.
  - It strikes at MORALE_CHECK.
  - A rally is ordered in PLANNING and rolled at once: one MC. A pass means it plots this turn; a fail
    lowers CQ, and a fail at G strikes it for good.
  - A second surrender is permanent.
- **U — In 1v1, surrendering the last ship concedes:** it counts as struck for "all struck".
- **B — Eligibility (14.B.2):** CQ F or G, or ≥ 5 sections lost. Sections detached as a prize crew do
  not count.
- **B — AI surrender:** an AI ship surrenders when eligible and either an enemy with readied boarders
  is linked to it, or it faces ≥ 2:1 odds within range 3. It rallies when no enemy is within 5 hexes.
- **B — 14.D fatigue as written:**
  - −1 from the 6th firing turn, −2 from the 16th, and so on, with no recovery.
  - A firing turn is a turn in which any battery fired.
  - It is shown as the `fatigue` modifier.
- **B — 14.E:** when both rules are on, one d6 covers both. A low aim is forced high on a 4+ if either
  condition holds (a CQ E/F/G crew, or firing to windward at WF C/B). It applies to every navy and not
  to marine fire.
- **B — State and events:**
  - Surrender state and the fatigue count are public.
  - New events: SURRENDER, RALLY, AIM_FORCED.
  - None of them count boxes, so `PlayerView.BOX_FIELDS` is unchanged.
