# Rulings made during the unattended run (sub-projects 3–7)

Decisions taken on the user's behalf while executing the plans, beyond the decisions register
(`specs/2026-11-17-subprojects-3-7-decisions.md`). Each says what it costs if wrong. Newest sub-project last.

## Proportional movement (merged 2026-11-17)

1. **Overlap across a bear-off pause.** Under proportional pace a 6.B overlap window can span several segments, so a bear-off prompt can come while an earlier swing is still pending; the re-run with the answer may roll that swing back. Movement still pauses at the decision; the watched swing then swings back like any rolled-back overlap (playback fixed, tested, recorded in design §4 and feature_diff §4). *If wrong:* in a rare case the player answers a bear-off with a stern in a hex that later swings back.
2. **Lost test coverage restored with new tests.** Switching to proportional pace changed what seven overlap tests reached; their new expectations were kept and new equal-pace tests restore "sterns together", the stale cascaded rollback, multi-ship overlap naming and Diagrams 14 D/E. *If wrong:* none.
3. **Playback easing** follows design §6 (ease in on a ship's first glide, ease out on its last, linear between) rather than the plan's "smoothstep on first and last", which would stop a ship after its first step. *If wrong:* a cosmetic change.
4. **Live check:** done once (Task 5, `test_fleet`): slower ships visibly part-way through their glides while faster ones are further on; no errors. *If wrong:* a visual glitch found later.
5. **Process:** the docs-only task was reviewed as part of the whole-branch review; the SCV audit ran once at the end (clean).

Parked minors (not fixed, judged harmless): the playback clock can idle briefly when a special event lies after the last move; `steps_before` is O(N·T) for tiny N; the playback fallback for a log without times is untested.

## Sub-project 3 — map and scenario (merged 2026-11-17)

1. **Inner boundaries are walls only for now.** Typed boundaries are general (map edges and future shore lines), but a boundary inside the map may only be `open`; a scenario giving one `none` or `escape` is rejected as "not supported yet". *If wrong:* a reef line that destroys ships needs a later change.
2. **A ship locked in a live boarding action cannot escape** (plotting, movement and drift treat its escape crossing as blocked); boarding treats a ship off the map as gone. A captor whose boarders are still reorganizing aboard a prize may sail away; the prize is then left without a prize crew and her crew below retakes her. *If wrong:* a boarded ship cannot slip off an escape edge.
3. **An escaped ship's fires go out** and the fire sub-phase skips ships off the map. *If wrong:* none.
4. **AI near shoals is cautious:** it avoids doubtful ("maybe") water as well as certain shallows and casts the lead only when forced into a shoal; when escaping it keeps out of the wind (no luffing headings). *If wrong:* a timid AI near coasts.
5. **Waiting reinforcements take no part in anything** (cannot be fired on, boarded, grappled, blasted; no maintenance prompt; no planning card). An entry hex held by another ship delays the arrival one turn. *If wrong:* none.
6. **Victory with 3+ sides ends when any one side is defeated or unable** (the PVP aims are 1v1 and two-side team games). A side with no ships at all still counts as defeated. *If wrong:* a 3-side scenario ends early.
7. **A Poor Maneuvering failure while casting the lead grounds the ship** even when no bear-off turn would be legal (harsher than the book in a rare case).
8. **Lead bear-off goes to the deeper side, no prompt;** a lead turn undone by an overlap is not offered again (prevents a resolution loop).
9. **Escape speed test (D.1c)** uses each ship's heaviest sail its rigging allows; one shared max-MA helper serves escape and arrival speed.
10. **Process:** the docs-only task was reviewed in the whole-branch review; SCV audit clean.

Parked minors (judged harmless): stronger depth-order test, escape band boundary tests (19/20/30), padding-fallback tiers for the AI, the status-overlay clamp rect after a board resize, `LEFT_MAP.from_hex` is the post-step bow, a turn that would be no better than the present heading ends an escaping AI's plot early.

## Sub-project 4 — anchoring (merged 2026-11-18)

1. **Weighing anchor is not built:** an anchored ship leaves by cutting her cable (13.F.1 covers cutting); the register's "cutting and weighing" was read as cutting. *If wrong:* add a weigh task later.
2. **Manual crews have no overlay control to order anchoring yet** (view-only UI scope): Automatic crew's anchor order and the Developer UI cover it until the UX pass. *If wrong:* manual players cannot anchor by hand yet.
3. **Spring turns and veering in are refused** into a held hex, land or off the map, and for a ship fouled or grappled to another; aground ships take no part. *If wrong:* none.
4. **An anchored bow rolls depth whenever it enters a new hex** (settling, veering out onto her old stern hex), as drift does; a bow that stays put while the ship swings rolls nothing.
5. **Blocked forced moves at anchor** are a blocked drift: a ship in the way gives a fouling roll and the ship stays; land grounds her; an edge holds her; an anchored ship is never moved off the map.
6. **An anchored ship cannot escape and does not count as a pursuer** (like aground). *If wrong:* a ship must cut before escaping.
7. **No starting anchor on a reinforcement** (scenario error). A starting anchor counts as one of the ship's two anchorings.
8. **Anchoring preparation is hidden from every non-commander** (teammates too); the anchor itself is public.
9. **AI:** stays anchored, prepares springs and hauls to bear; cuts only on a signalled move order (or an escape posture) with no enemy in range, and never while it would drift into danger unanchored or cannot make way; emergency anchoring when drifting toward land or a `none` edge (an escape edge is not danger). *If wrong:* an AI ship may stay anchored longer than a human would.
10. **Movement never moves an anchored or aground ship** even if a plot was stored (defence added after the live check found the Developer UI path).
11. **Process:** SCV audit clean (two optional guards added).

Parked minors: none beyond those recorded in feature_diff §4.

## Sub-project 5 — towing (merged 2026-11-18)

1. **Starting a tow is a standing crew order** (`tow: "take:<id>"`), rolled at the start of the Grappling sub-phase with no prompt (no new input control). The order is re-checked only when it changes; one whose target can no longer be towed (unknown, own side's enemy, struck, destroyed, escaped, off the map) lapses with a log line. *If wrong:* a player must re-issue an order after it lapses.
2. **The towed ship takes her tower's speed** and follows in her wake; a turning tow swings differently from Diagram 24 (user decision).
3. **A prize towed off the map stays CAPTURED** (her value is not handed back to her original side).
4. **Who may tow:** friendly ships and friendly prizes, not own-side struck ships; a dismasted ship cannot tow, and a tower that becomes dismasted casts off her tow automatically; anchored ships neither tow nor are towed, and a ship in a tow cannot anchor; a tow parts if either ship grounds. *If wrong:* a dismasted tower can no longer hold a tow.
5. **Blocked tows:** a follow blocked by a third ship, land or the edge undoes the tower's step and trims her plot (no deceleration padding); a collision that stops the tower makes the tow ram her (one collision per ship per segment — a tow already held does not also ram); the towed ship's old stern stays held for the follow segment (spec §5).
6. **A tower held by a fouled or grappled tow cannot plot**; no grapple is offered between a tower and her own tow; a tower does not escape while her tow is fouled, grappled or locked in a boarding action.
7. **Hidden information:** tow preparation, PT tasks and lapsed tow orders are hidden from every non-commander; the tow itself is public.
8. **AI towing:** with no enemy within 8 hexes the nearest AI ship (nearest-first claims, one cripple each) prepares and tows a friendly dismasted ship or prize toward its escape edge or away from the enemy; it approaches by a search that never heads into the wind, up to 2 MPs a g-t (the 8.C limit), gives up a target after 6 g-t's without getting closer (memory reset each game), cuts when an enemy closes within 3 or it cannot make way (with wind). *If wrong:* the AI tows less often than a human would.
9. **The hawser follows the ships through movement playback.**
10. **Process:** SCV audit clean.

Parked minors: a tow rollback that undid a bear-off can name the wrong ship in its STOPPED_SHORT line when land held the tow; `TowRules` reads ship names from the GameState autoload for messages; the per-frame hawser mesh is rebuilt rather than scaled.

## Sub-project 6 — ships and guns (merged 2026-11-18)

1. **Chase guns (house rule, user decision) fire to range 7 only:** a chaser is one long-gun factor (TGF 1) and the BGN chart has no number for TGF 1 beyond range 7, so its 60° arc reaches 15 but it can hit only to 7 (the chart wins). *If wrong:* give chasers more factors.
2. **Chasers take no rake, half-broadside, obscured, lower-deck, dismounted or initial-broadside effects;** sections-firing, two-target −12, anchored +1, plain sail and the other flat modifiers apply; a chaser is one of the ship's ≤ 2 targets; chasers do not count toward "able to move or fight"; the AI fires them only when no broadside bears. A holding chaser's arc is drawn faint.
3. **Ship types:** all 41 SDC rows with nation-prefixed ids (the three old ids are aliases); the class-4 corvettes Babet and Rosalie and the brig Coureur come from the scenario orders of battle (the SDC has none); Diomede is her own type (no per-scenario overrides). The procedural model takes its gun decks from the class (1 → 3, 2 → 2, 3–4 → 1) and class 4 gets a two-masted rig; the crew overlay picks its deck drawing by class.
4. **Removed data fields:** `type`, `speed`, `crew_quality` on the type, `Ship.is_french_gunned` (the navy rule is `ShipState.is_french_gunned`). The three old parser warnings (ship_state.gd, turn_phase_controller.gd) are fixed.
5. **Process:** ship rows checked against the scan three times (pre-flight, implementer, final review); SCV audit clean.

Parked: a tow astern blocking a stern chaser is refused as "no line of sight" rather than "blocked by friendly ship"; the full-game test asserts a FIRE event but not specifically a chase shot.

## Sub-project 7 — optional rules (merged 2026-11-18)

1. **Switches:** a scenario `optional_rules` block (`voluntary_surrender`, `fatigue`, `gunfire_limits`: crew / heel / both), all off by default, with an override passed to `start_scenario`; a malformed block refuses the start.
2. **Surrender (14.B)** takes effect at the end of the turn it is ordered (user decision): she moves per plot, can be fired on, fires no guns or muskets and sends no new boarders, and strikes at MORALE_CHECK before the noted morale checks. The order is hidden from the other side until she strikes; Cancel withdraws it. Eligibility: CQ F/G or ≥ 5 sections lost, prize-crew detached sections not counted. In 1v1 surrendering the last ship concedes (user decision).
3. **Rally:** one MC in planning; a pass returns her to play this turn with her default course (crew_auto kept); a fail lowers CQ, at G she is struck for good; a second surrender is permanent; no surrender in the g-t she rallied; a ship with no hull or no crew left cannot rally (9.C). *If wrong:* rallying is a little more restrictive than the book.
4. **Fatigue (14.D):** counted per firing turn (any battery, chasers included), −1 from the 6th, −2 from the 16th ("g-t 15" read as the 16th), no recovery; public.
5. **Gunfire limits (14.E):** one d6 per firing ship covers both rules when both are on; a low shot forced high on 4+ keeps its previewed number and reads the High column; every navy; not marine fire; the fire panel shows the 50 % chance in its aim note.
6. **AI:** surrenders when eligible and a linked enemy has boarders ready or it faces ≥ 2:1 gun-factor odds within range 3; rallies (before plotting) when no enemy is within 5.
7. **Roadmap closed:** feature_diff §2 is empty; the Scenario Book's scattering, variable reinforcement entry and special victory conditions are recorded as not offered (§4).
8. **Process:** several small task reviews were folded into the whole-branch review; SCV audit clean; the last parser warning in the project was fixed (an annotation must sit on the line, not the function).

## Board planning, piece 1 (radial menu and planning per ship) — 2026-11-18

- First Tab with no ring open opens the selected ship's ring if she is still in Plan, else the next ship in Plan; Shift+Tab goes back. Cost if wrong: one extra key press.
- Footer line: "n ships still in Plan: they sail the course shown" (the earlier wording claimed the default course even for plotted ships). Cost if wrong: wording only.
- A refused End Planning puts the first ship it names into Move mode so the chip box shows the server's reason (the card no longer has a Course block). Cost if wrong: the camera's attention jumps to that ship.
- Move puts a Done ship back in Plan; Esc in Move mode reopens her ring; Reset course leaves Plan/Done as it was; board keys do nothing while the crew overlay is open. Cost if wrong: small habits to relearn.
- Parked: Reset course stays enabled on a ship anchored mid-turn by the Developer UI; a ring opened before a window resize keeps its old clamp; Esc with the Cancel confirmation open closes the ring first; in a game with several humans the ring stays live after you submit (the server refuses the edits) — piece 4.

## Board planning, piece 2 (orders ring and signal composer) — 2026-11-19

- Orders a scenario does not use are hidden (escape with no escape edge for her side; surrender and rally with 14.B off; rally unless surrendered); every other refusal is greyed with the server's reason. Cost if wrong: a player may not learn an order exists in a scenario that lacks it.
- A surrendered ship's ring holds Rally and Crew & damage (read-only overlay). Cost if wrong: one icon.
- An open ring hides its ship's pill and order marks. Cost if wrong: the state is one glance away on the card.
- Any map click closes the signal box; Tab stays in its text field; Enter sends and keeps the field editing. Cost if wrong: small habits.
- The signal box names the sender of a pending signal and warns that a new one (from any ship) replaces it: signals are one per player a turn. A ship is not offered herself as an address. Cost if wrong: none known.
