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
