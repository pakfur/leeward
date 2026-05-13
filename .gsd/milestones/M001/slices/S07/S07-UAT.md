# S07: MovementResolver contested hexes, bear-off, collisions, fouling — UAT

**Milestone:** M001
**Written:** 2026-05-12T18:43:28.400Z

## S07 UAT: Multi-Ship Resolution\n\n### Contested Hex Resolution\n- [x] Two ships moving to same hex triggers contest roll\n- [x] Three-ship contest produces exactly one winner\n- [x] DRM modifiers: crew quality, ship class, MP advantage\n- [x] Contest losers routed to bearing-off resolution\n\n### Bearing Off\n- [x] Probability varies by crew quality and maneuverability (bearing_off_table.json)\n- [x] Pivot denied if insufficient forward hexes since last pivot\n- [x] Successful bearing-off roll allows ship to pivot away\n- [x] Failed roll or denied pivot causes collision\n\n### Collisions\n- [x] Both ships stopped on collision\n- [x] Rigging damage by sail state: FS=2R, MS=4R, PS=6R, NS=0R\n- [x] Moving into stationary ship triggers bearing-off check\n\n### Fouling\n- [x] 50% fouling roll on collision (seeded via GameState.rng)\n- [x] Dismasted ships exempt from fouling\n\n### Verification\n- [x] `make test` — 259/259 pass (0 failures)\n- [x] 11 dedicated multi-ship fixture tests all green
