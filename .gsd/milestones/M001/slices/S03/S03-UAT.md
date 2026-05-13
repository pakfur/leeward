# S03: MovementValidator real rules (single-ship, no contests) — UAT

**Milestone:** M001
**Written:** 2026-05-12T16:24:33.324Z

## UAT: S03 — MovementValidator real rules\n\n### Checks\n\n- [ ] PlotStep.move_type is populated (FORWARD/PORT/STARBOARD)\n- [ ] MA exhaustion: ship with MA=N can make exactly N forward moves\n- [ ] Pivot caps: max 2 pivots/turn, no consecutive pivots\n- [ ] Turning table: min-forward hexes enforced between pivots\n- [ ] Luffing: pivot into wind_facing=L ends movement immediately\n- [ ] In-irons: speed 0 + facing L → no moves, can submit empty\n- [ ] Free pivot at MA=0 costs 0\n- [ ] Fast-tack bonus: C→B first pivot gives +1 MA\n- [ ] Speed range: MA capped by accel/decel from speed_change_table\n- [ ] MA recalculates on pivot (new facing → new wind_facing → new MA)\n- [ ] Trace logs on every rule-block\n- [ ] All 211 tests pass via `make test`
