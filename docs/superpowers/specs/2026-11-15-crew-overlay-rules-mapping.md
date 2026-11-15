# Crew overlay: rules → stations mapping

**Status:** step 1 of the crew-overlay plan (rules mapping → HTML prototype → Godot prototype → full spec on Fable 5.2 → implementation). These are the constraints the prototype has to respect. They are not the full spec.

**Prototype:** approved 2026-11-15 at version 15: `docs/superpowers/prototypes/crew-overlay.html` (published as the "Leeward Crew Overlay" artifact). Where its layout differs from §3–§5 below, the prototype wins: a bow-up enlarged deck; a fixed deck list in ship order; fire stations on the upper deck under Marine fire; and, in the left panel, the roster, the Guns readout, a collapsible DAMAGE (N) section and hull/rigging bars.

**Sources:** `docs/rules/close_action.md` 4.A.3, 4.B, 5.D.2a, 8.D.5, 8.E, 8.F, 10.B; the ship log's Crew Task Order Codes (`docs/rules/images/ship-log-*.png`); `2026-11-15-crew-tasks-fire-repairs-design.md` §1.1, the task table, which this file does not repeat.

## 1. The core idea

- **A token is a crew section (CS).** A ship has five: S1–S4 (sailors) and M (marines), as on the ship log. A token shows its section's boxes left, e.g. "S2 · 3/3". An emptied section's token is gone.
- **A station is exactly one task code.** Placing a token on a station plots that task for that section. Where a token sits on the deck has no other meaning.
- **Decks are presentation.** The rules engine never sees decks or positions, only `{section → task}`. Ship types differ only in which decks are drawn and where the stations sit.

## 2. Rules the overlay must enforce or show

| Rule | Overlay behaviour |
|---|---|
| 4.B.2 one task per CS | A token is on one station at a time; moving it is a reassignment. |
| 4.B.1 any CS, any task, except boarding | Boarding stations accept the **lowest-numbered** sailor sections first; the station refuses S3 while S1 is free, and says so. **Open question:** the prototype skips a lower section that is fighting a fire (a mandatory task, 8.E.2). The rule's example assumes all sections are free. |
| 4.A.3 same CS for every g-t of a task; stopping loses progress | A token on a task in progress shows its progress ("RR 2/4"). Dragging it away warns: "S3 has 2 of 4 turns on rigging repair; moving it loses them." |
| 4.B.3 an eliminated CS loses its progress | The token disappears; the task shows "abandoned". |
| 4.B.4 unplotted sailors serve the guns; unplotted marines may fire | **Serve the guns** is the default station (the gun deck, both broadsides). It shows the sections-firing modifier live: "Guns: 2 sailor sections (−6)". An unassigned M is "marine fire". |
| 5.D.2a tacking crew | The **T (braces)** station appears only when a turn at MA 0 is plotted. Up to 3 CS, showing the chance per CS count (+2 DRM per CS short of 3). |
| 8.E.2 every fire must be fought by one CS | One **FF** slot per fire (FF1, FF2…). An unfought fire shows red: "unfought fire: morale check each turn" (8.E.6). An empty FF slot may be filled with no fire burning (the HINT). |
| 8.F.3a rigging repair only at FS / furled / dismasted | The **RR** station is greyed out with the reason when the ship carries MS or PS. |
| 8.F.3b hull repair only if ≤ 4 MPs moved | **RH** is allowed, with a warning: "cancelled if the ship moves more than 4". The server decides after movement. |
| 8.F.3 repair only after damage of that type | RR / RH / RS are hidden until there is something to repair. RS appears with Shrouds Severed. |
| 8.F.4 one CS per repair type | Each repair station holds one token. |
| Sail change (5.F) | The **Sails (aloft)** station takes 1 or 2 CS, per the change chosen; the target sail is picked on the station. |
| 10.B boarders (boarding spec) | **Form / ready boarders** at the waist. Marines and sailors, lowest sailor sections first. |
| Critical effects (8.D.5 fixes need no CS) | Markers only, at their place: wheel, rudder, mast (braces / lines / sheets / shrouds), obscured broadside. The fix roll is automatic in maintenance, so there is no token slot. |
| Fire has no location in the rules | Fires appear as **incident cards** in a "Fires" strip, not at a place on the deck. A flame on the deck drawing is decoration only. |

## 3. Station → deck placement (frigate; a 74 adds a second gun deck)

| Station | Task code(s) | Deck |
|---|---|---|
| Sails (aloft) | PS/MS/FS/Furl changes | Upper deck, at the masts |
| Braces | T | Upper deck, quarterdeck |
| Rigging repair | RR | Upper deck, at the masts |
| Shroud repair | RS | Upper deck, chains |
| Boarders | FB / BR (BA / BD) | Upper deck, waist / gangways |
| Serve the guns (default) | none (unplotted) | Gun deck(s); also the upper-deck carronades |
| Fire parties | FF1, FF2 … | Fires strip (on every deck) |
| Hull repair | RH | Orlop / hold (carpenter's walk) |
| Marine fire (default for M) | none (unplotted) | Upper deck, poop / quarterdeck rail |

Not drawn yet: anchoring and towing (Milestone 3), and RO, which shows on the token itself (a "disorganized" face) once crew disorganized is implemented.

## 4. Defaults and carry-over

- Tasks in progress stay where they are from turn to turn.
- New fires get the lowest free sailor section automatically, marked "auto"; the player may change it.
- Everything else defaults to Serve the guns (sailors) and Marine fire (M).
- So the overlay is for **changes**; the planning panel keeps a one-line summary ("S1 sails · S2 FF1 · S3 S4 guns · M fire").

## 5. Prototype scope (HTML)

One frigate and one 74, as a stacked cutaway (all decks visible, selected deck enlarged), five tokens, the stations above, drag, click-then-click, and right-click assignment, the fire strip, crit markers, the gun-modifier readout, the warnings in §2, a small tactical inset, and the planning-panel summary. Fake data; no rules engine.
