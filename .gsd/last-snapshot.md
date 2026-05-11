# GSD context snapshot (2026-05-11T23:46:20.745Z)

## Active context
Active: M001 / S01 / T01 - Add bearing_off_table.json + DataManager wrapper + unit tests

## Top project memories
- [MEM010] (convention) DataManager rule-table loaders share a fixed shape: a `_doc` key inside the JSON (excluded from item counts), `load_X_table(file_path) -> bool` (push_warning + return false on missing file, push_error + return false on parse failure, returns true and prints item count on success), and `get_X(...)` lookups that `assert()` valid params (case-insensitive letter args canonicalized to one case), then push_error and return a zero value (0, 0.0, or {}) on any missing key.
- [MEM001] (architecture) MovementValidator shape Chose: Single MovementValidator class with broken-out private methods and an internal PlottingState snapshot.. Rationale: All rules consult JSON tables; GDScript favors clear procedural code over plugin-style rule engines; debugging interlocking rule failures is easier in one class with explicit method names. Rule-engine of composable rule classes considered and rejected as premature abstraction..
- [MEM002] (architecture) Movement resolver placement Chose: New MovementResolver class under scripts/server/, symmetric with MovementValidator.. Rationale: Clean separation between plotting (legality) and resolution (execution under simultaneity rules). ShipStateController and MovementPlottingController are the wrong concerns. Rejected: extending ShipStateController (bloats one class); method on plotting controller (session manager, not simulator)..
- [MEM003] (architecture) Mid-resolution user input pattern Chose: Async/await on Godot signals for contested-hex surrender and bear-off prompts during resolution.. Rationale: Godot-idiomatic, single execution context, no new mini-protocol. Stub-AI prompt answers injected programmatically so deadlock is impossible in single-machine M001. Rejected: mini-session protocol (too heavy for yes/no); explicit state machine (too verbose)..
- [MEM004] (arc
…[truncated]
