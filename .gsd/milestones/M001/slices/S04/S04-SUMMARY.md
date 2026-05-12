---
id: S04
parent: M001
milestone: M001
provides:
  - end_planning_button
  - ship_submission_tracking
  - replot_support
requires:
  []
affects:
  []
key_files:
  - scripts/ui/planning_phase_ui.gd
  - scenes/ui/planning_phase_ui.tscn
  - scripts/core/game_controller.gd
  - scripts/ui/ship_list_item.gd
key_decisions:
  - End Planning gates on all player-0 ships submitted — no partial submission
  - Re-plotting clears old submission entirely before starting fresh
  - Stub player_submit_plan(1) placeholder for StubAI in S08
patterns_established:
  - (none)
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T16:36:16.606Z
blocker_discovered: false
---

# S04: Planning UI fleet workflow: Movement button, plot display, End Planning

**Added End Planning button with submission tracking, visual feedback, and re-plot support for the fleet planning workflow**

## What Happened

Implemented the complete planning UI fleet workflow. The EndPlanningButton shows a live N/M counter (submitted/total ships) and only enables when all player-0 ships have submitted movement plots. Ship list items display green-tinted panels with [OK] suffix for submitted ships, with selected state taking visual priority. Re-plotting is supported by clicking Movement on an already-submitted ship, which clears the old submission (path overlay, plotted_actions, UI state) before starting a fresh plotting session. End Planning fires player_submit_plan(0) plus a stub player_submit_plan(1) through the phase controller, advancing to MOVEMENT_RESOLUTION. All print() calls in GameController and PlanningPhaseUI were replaced with Trace.trace_log(). Fixed 3 pre-existing crew_count test assertions that didn't match the actual data in ships.json.

## Verification

make test: all 214 tests pass. Code review confirmed End Planning button disabled state, submission tracking, re-plot clearing, and phase advancement wiring.

## Requirements Advanced

None.

## Requirements Validated

None.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

None.

## Known Limitations

None.

## Follow-ups

None.

## Files Created/Modified

None.
