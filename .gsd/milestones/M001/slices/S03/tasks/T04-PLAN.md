---
estimated_steps: 1
estimated_files: 2
skills_used: []
---

# T04: Implement luffing, in-irons, fast-tack bonus, and tacking detection

Luffing: if a pivot would make wind_facing=L, allow it but set remaining_ma=0 and mark can_submit=true (movement ends). In-irons: if ship starts turn at wind_facing=L with speed=0, movement is blocked (empty valid_hexes, can_submit=true for no-movement submission). Tacking detection: if ship pivots to L and then pivots again same direction (through L), set session.is_tacking_attempt=true. Fast-tack bonus: if ship is at wind_facing=C and first move is a pivot to wind_facing=B, add +1 to remaining MA (close-hauled to broad reach bonus). Trace all of these.

## Inputs

- `scripts/server/movement_validator.gd`
- `scripts/server/movement_plotting_session.gd`
- `scripts/core/hex_grid.gd`

## Expected Output

- `scripts/server/movement_validator.gd`
- `scripts/server/movement_plotting_session.gd`

## Verification

Fixture: pivot into L ends movement. In-irons ship gets empty moves. Tacking through L sets is_tacking_attempt. C→B first pivot gets +1 MA.
