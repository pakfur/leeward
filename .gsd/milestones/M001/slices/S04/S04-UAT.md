# S04: Planning UI fleet workflow: Movement button, plot display, End Planning — UAT

**Milestone:** M001
**Written:** 2026-05-12T16:36:16.607Z

# S04 UAT — Planning UI Fleet Workflow

## Manual Test Plan

1. **Load test_fleet.json** via `make play`
2. **Select each player-0 ship** — verify ship list highlights selected ship
3. **Click Movement** on first ship — verify plotting starts, MA/path display works
4. **Submit movement** — verify ship shows green tint + [OK], End Planning counter increments
5. **Repeat for all player-0 ships** — verify End Planning button enables when all submitted
6. **Re-plot a submitted ship** — click Movement on a green [OK] ship, verify old path clears, fresh plotting starts, counter decrements
7. **Re-submit** — verify counter returns to full, button re-enables
8. **Press End Planning** — verify phase advances to MOVEMENT_RESOLUTION
9. **Check Trace output** — verify no print() calls, all logs use Trace.trace_log()

