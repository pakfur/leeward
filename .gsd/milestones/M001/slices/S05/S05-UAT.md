# S05: Tacking attempt detection and live probability UX — UAT

**Milestone:** M001
**Written:** 2026-05-12T16:44:27.453Z

# S05 UAT — Tacking Attempt Detection and Live Probability UX

## Manual Test Plan

1. **Load test_fleet.json** via `make play`, wind from W
2. **Select a player ship** facing NE (broad reach relative to wind)
3. **Click Movement** and start plotting
4. **Pivot port twice** with a forward in between — second pivot should face into wind (luffing)
5. **Verify tacking label appears** — gold text showing "Tacking: NN% success" in plotting controls
6. **Verify probability is correct** — matches tacking_table.json for ship's maneuverability + current wind speed
7. **Undo past the second pivot** — verify tacking label disappears
8. **Re-plot the tacking path** — verify label reappears
9. **Cancel plotting** — verify label disappears
10. **Plot a non-tacking path** (forward only or pivots that don't hit luffing) — verify label never appears

