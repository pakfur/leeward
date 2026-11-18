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
