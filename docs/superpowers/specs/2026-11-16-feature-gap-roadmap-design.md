# Closing the Close Action feature gap: roadmap

Date: 2026-11-16. Status: approved by the user 2026-11-16.

## Intent

Close every gap in §2 of `docs/rules/feature_diff.md` ("Features in the board game that Leeward lacks"): all of Volume 1, the optional rules (14) and the Milestone 3 items included. The second aim is to get Leeward ready for multi-user play. The end goal is **networked 1v1 and team PVP**. This round builds what such play needs and makes it testable with AI or scripted players. Networking itself is a later project.

**Guiding principle (user, 2026-11-16).** Closing the gap is a goal; a 100 % faithful port is not. Playability and fun come before fidelity. The 1997 rules are a starting point, and the user expects to deviate from them once the core loop is in place. When a rule is fiddly or a poor fit for a computer game, each sub-project's design proposes a more playable reading and records it in `feature_diff.md` §4 as a deliberate change.

## How the work is split

Seven sub-projects, done in this order. Each one gets its own brainstorm, design (`docs/superpowers/specs/`) and plan (`docs/superpowers/plans/`) when it starts, so that what one teaches can shape the next. Only sub-project 1 is designed now (`2026-11-16-rule-fixes-design.md`).

| # | Sub-project | Rules | Depends on |
|---|---|---|---|
| 1 | Rule fixes | 5.E.8, 5.D.3, 5.D.4c / 3.D.4, 6.C.3 (deliberate change), 6.D.3c, 7.B.10–12, 7.C.14, 2.A.1 (no ship able to move or fight), 10.H.2 (grapple, ungrapple, unfoul), 8.G.1f (exploded ships), the "sinking" and "sail check" rows | — |
| 2 | Players and sides | Separate players from sides, flagships, signalling (ch. 11, 4.A.4, 8.G.1e, signal halyards cut), talking between ships (11.B.3), game end by agreement (2.A.1), limited information (14.C) | 1 |
| 3 | Map and scenario | Map exit and escape (2.B.5g, 8.G.1f), reinforcements (2.B.1, 3.A), depth and land, grounding, casting the lead (13.G), land blocking LOS (7.B.7) | 1 |
| 4 | Anchoring | 13.A–F, 8.B, 8.A.7 veering, 7.C.12c anchored +1, the anchoring exceptions to being in irons (5.D.4a–b, 13.F.3) | 3 |
| 5 | Towing | 12.A, towing DRMs already read by tacking and acceleration, prizes towed (10.H.2) | 1 (3 helps) |
| 6 | Ships and guns | Lower-deck guns and freeboard against sea state (7.F, 3.E.1), medium guns, chase guns, class 4 ships (1.G.7), their ship data from the Ship Data Chart | 1 |
| 7 | Optional rules | 14.A impulse movement (and fire at the end of an impulse), 14.B voluntary surrender and rallying, 14.D fatigue, 14.E historical gunfire limits, each switched on per scenario | 1, 2 for 14.B in team play |

**Why this order.** Sub-project 1 is small, self-contained and clears most of §2.2. Sub-project 2 comes next because nearly every server request takes a `player_id` that today *is* the side (0 or 1); every feature built on the old model before the split is rework later. The map comes before anchoring because anchoring matters near shore. Towing and ships/guns are independent and can swap places. The optional rules come last because they change systems the others build.

## What we found that shapes later sub-projects

- **Signalling only applies to sides with two or more players** (11.A.2). It belongs with the side/player split, not on its own. In 1v1 its only effect is signal halyards cut.
- **There is no multi-user plumbing.** `scripts/server/network_sync.gd` is a stub with no transport. `GameState.start_scenario(scenario, human_player_ids)` takes side numbers as player ids. Sub-project 2 must introduce a player (who gives orders, sees, signals) distinct from a side (who wins, who is friendly), keep every request validated by the server against the requesting player, and leave room for a transport and per-client views later.
- **Limited information (14.C) is a per-player view filter.** It is cheap to design in sub-project 2 and expensive to retrofit after networking.
- **Volume 1 has no sinking rule.** A ship with no hull boxes strikes, and explodes only if burning (8.E.8). The "Sinking" row is closed as "not in the rules" (sub-project 1).
- **"Sail checks after a wind change" is not a rule either.** The `# TODO` in `_enter_environment_phase` is home-made and goes (sub-project 1).
- **Removed ships.** Sub-project 1 adds a single notion of "on the map" for exploded ships; sub-project 3 reuses it for escaped ships.

## Non-goals of this roadmap

- Networking, lobbies, matchmaking, accounts.
- The Scenario Book's historical scenarios, the rating system and tournament rules (outside the rules-book scope of `feature_diff.md`).
- AI strategy beyond what each feature needs to be played against.

## Done

Each sub-project ends with its §2 rows moved to §3/§4/§5 of `feature_diff.md`, `CLAUDE.md` "Known Limitations" in step, `make test` green and the SCV review clean. The roadmap is done when §2 of `feature_diff.md` is empty.
