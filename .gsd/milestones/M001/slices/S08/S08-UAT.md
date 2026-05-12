# S08: StubAI drives plotting protocol for non-player ships — UAT

**Milestone:** M001
**Written:** 2026-05-12T18:49:19.470Z

## S08 UAT: StubAI drives plotting protocol\n\n### Test: AI ships are plotted, player ships are not\n- Load test_basic scenario (1 player ship, 1+ AI ships)\n- Call StubAI.plot_all_ai_ships()\n- **Verify**: AI ships have non-empty plotted_actions.movement; player ship has empty plotted_actions.movement\n\n### Test: AI plots are rule-validated\n- AI ship facing into wind (luffing) should get 0 MA and empty plot\n- AI ship with clear forward path should consume full MA\n- **Verify**: Step count matches MA from movement allowance table\n\n### Test: Sessions cleaned up\n- After plot_all_ai_ships(), no active sessions remain on MovementPlottingController\n\n### Test: AI and player ships resolve together\n- Plot AI ships via StubAI, manually plot player ship\n- Run MovementResolver\n- **Verify**: Both ships have resolution results
