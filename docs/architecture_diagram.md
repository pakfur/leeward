# Leeward - Server-Authoritative Architecture

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          GAME STATE (Autoload)                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ State Data (Read-only on clients, Authoritative on server)     │ │
│  │  • environment: EnvironmentState                               │ │
│  │  • ships: Dictionary<ship_id, ShipState>                       │ │
│  │  • current_phase, current_turn, players_ready                  │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ Server Controllers (Only active on server, is_server = true)   │ │
│  │  • phase_controller: TurnPhaseController                       │ │
│  │  • ship_controller: ShipStateController                        │ │
│  │  • command_validator: CommandValidator                         │ │
│  │  • network_sync: NetworkSync                                   │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## Server-Side Flow

```
┌──────────────┐
│   Player     │
│   Input      │
└──────┬───────┘
	   │
	   ▼
┌──────────────┐
│ MoveCommand  │ ────┐
└──────────────┘     │
					 │
	   ┌─────────────▼─────────────┐
	   │   CommandValidator        │
	   │  • validate_command()     │
	   │  • check turn, player,    │
	   │    phase, MA              │
	   └────────────┬──────────────┘
					│ Valid?
					▼
	   ┌────────────────────────────┐
	   │  ShipStateController       │
	   │  • set_plotted_movement()  │
	   │  • Updates ShipState       │
	   └────────────┬───────────────┘
					│
					▼
	   ┌────────────────────────────┐
	   │  TurnPhaseController       │
	   │  • advance_phase()         │
	   │  • tick_environment()      │
	   │  • resolve_movement()      │
	   └────────────┬───────────────┘
					│
					▼
	   ┌────────────────────────────┐
	   │    NetworkSync             │
	   │  • broadcast_state()       │
	   │  • Sends to all clients    │
	   └────────────────────────────┘
```

## Client-Side Flow

```
	   ┌────────────────────────────┐
	   │    NetworkSync             │
	   │  • receive_state_update()  │
	   │  • Receives from server    │
	   └────────────┬───────────────┘
					│
					▼
	   ┌────────────────────────────┐
	   │      GameState             │
	   │  • sync_from_server()      │
	   │  • Update local state      │
	   │  • Emit state_synced       │
	   └────────────┬───────────────┘
					│
					▼
	   ┌────────────────────────────┐
	   │   GameController           │
	   │  • _sync_all_views()       │
	   └────────────┬───────────────┘
					│
					▼
	   ┌────────────────────────────┐
	   │     ShipView (Visual)      │
	   │  • sync_to_state()         │
	   │  • Update 3D position      │
	   │  • Update rotation         │
	   └────────────────────────────┘
```

## Data Flow: Command Submission

### Server Mode (Single-player or Server)
```
UI (PlanningPanel)
	│
	▼
MoveCommand.execute()
	│
	▼
CommandValidator.execute_command()
	│
	├─→ validate_command()
	│   ├─ Check turn number
	│   ├─ Check player ownership
	│   ├─ Check phase (PLANNING only)
	│   └─ Validate movement allowance
	│
	▼ (if valid)
ShipStateController.set_plotted_movement()
	│
	▼
ShipState.plotted_actions["movement"] = commands
	│
	▼
ship_state_changed signal → NetworkSync broadcasts
```

### Client Mode (Future multiplayer)
```
UI (PlanningPanel)
	│
	▼
MoveCommand created
	│
	▼
NetworkSync.send_command_to_server()
	│
	▼
[Network Transport Layer]
	│
	▼
Server receives via NetworkSync.receive_command()
	│
	└─→ (Same as server flow above)
```

## Phase Lifecycle

```
TurnPhaseController (Server)
	│
	├─→ SETUP
	│   └─→ Initialize game state
	│
	├─→ ENVIRONMENT
	│   ├─→ environment.tick_environment(turn)
	│   ├─→ Update wind, sea state
	│   └─→ Auto-advance
	│
	├─→ PLANNING
	│   ├─→ Players submit commands
	│   ├─→ Wait for all players_ready
	│   └─→ Advance when all ready
	│
	├─→ MOVEMENT_RESOLUTION
	│   ├─→ ship_controller.resolve_all_movement()
	│   └─→ Apply plotted movements
	│
	├─→ COMBAT_RESOLUTION (TODO)
	├─→ DRIFT_CALCULATION (TODO)
	├─→ STATUS_ADJUSTMENT (TODO)
	├─→ MORALE_CHECK (TODO)
	├─→ MESSAGE_DELIVERY (TODO)
	│
	├─→ POST_COMBAT
	│   └─→ Manual advance or timeout
	│
	└─→ END_TURN
		└─→ Loop back to ENVIRONMENT (next turn)
```

## File Organization

```
scripts/
├── autoload/
│   ├── game_state.gd          # Central state + controllers
│   └── data_manager.gd        # Static game data
│
├── server/                     # NEW: Server-authoritative logic
│   ├── turn_phase_controller.gd
│   ├── ship_state_controller.gd
│   ├── command_validator.gd
│   └── network_sync.gd
│
├── state/                      # Pure data classes
│   ├── ship_state.gd
│   └── environment_state.gd
│
├── view/                       # Presentation layer
│   └── ship_view.gd
│
├── commands/                   # Command pattern
│   ├── game_command.gd
│   └── move_command.gd
│
├── core/
│   ├── game_controller.gd     # View management
│   └── hex_grid.gd
│
└── ui/
	├── planning_panel.gd      # Player input
	└── ship_status_panel.gd  # Ship info display
```

## Key Principles

1. **Server Authority**: All state mutations happen server-side via controllers
2. **Command Pattern**: Player actions are commands validated before execution
3. **State Separation**: Pure data (ShipState) vs presentation (ShipView)
4. **One-Way Sync**: Server → Clients (clients never write to server state directly)
5. **Deterministic**: Same inputs = same outputs (important for replay/rollback)

## Security Model

```
❌ BLOCKED: Client cannot...
   • Modify ship position directly
   • Change environment state
   • Advance phases
   • Exceed movement allowance
   • Act out of turn
   • Control opponent ships

✅ ALLOWED: Client can...
   • Submit commands (validated server-side)
   • View all state (read-only)
   • Request full sync
   • Display UI
```

## Future Extensions

- **Replay System**: Save command stream, replay on server
- **Client Prediction**: Optimistic updates with server reconciliation
- **Delta Sync**: Only send state changes, not full state
- **Spectator Mode**: Read-only client connections
- **AI Players**: Server-side AI submits commands like human players
