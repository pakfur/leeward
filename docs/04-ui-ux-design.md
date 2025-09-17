# Leeward - UI/UX Design Documentation

## UI Overview

### Visual Hierarchy
1. **Primary:** Game board and ships
2. **Secondary:** Action panels and controls
3. **Tertiary:** Resources and status information

### Screen Layout
```
┌─────────────────────────────────────┐
│ Top Bar (Resources, Turn, Menu)     │
├──────┬──────────────────────┬───────┤
│      │                      │       │
│ Left │   Game Board View    │ Right │
│Panel │   (Ships & Water)    │ Panel │
│      │                      │       │
├──────┴──────────────────────┴───────┤
│ Bottom Panel (Actions/Ship Details) │
└─────────────────────────────────────┘
```

## Main Game HUD

### Top Bar
- **Resources Display**
  - Gold: [Icon + Number]
  - Supplies: [Icon + Number]
  - Ammunition: [Icon + Number]
- **Turn Information**
  - Current turn number
  - Active phase indicator
  - Wind direction/strength
- **Menu Buttons**
  - Settings
  - Save/Load
  - Help
  - Exit

### Left Panel (Fleet Overview)
- Ship list with health bars
- Quick ship selection
- Formation controls
- Fleet morale indicator

### Right Panel (Context Sensitive)
- **During Planning:** Available actions
- **During Combat:** Weapon controls
- **Enemy Selected:** Enemy ship details
- **Port View:** Port services

### Bottom Panel
- **Ship Details Tab**
  - Hull integrity
  - Crew status
  - Speed indicator
  - Ammunition count
- **Action Queue Tab**
  - Planned movements
  - Queued actions
- **Combat Log Tab**
  - Recent events
  - Damage reports

## Game Board Interface

### Ship Representation
- Ship model/sprite
- Health indicator
- Movement range overlay
- Firing arc indicators
- Status effect icons

### Board Overlays
- **Movement Grid:** Shows possible moves
- **Firing Ranges:** Red/yellow/green zones
- **Wind Indicator:** Animated arrows
- **Fog of War:** Visibility limits

### Selection and Highlighting
- Selected ship: Bright outline
- Targeted enemy: Red outline
- Allied ships: Blue markers
- Neutral/terrain: Gray

## Control Schemes

### Mouse Controls
- **Left Click:** Select/confirm
- **Right Click:** Cancel/deselect
- **Middle Mouse:** Pan camera
- **Scroll Wheel:** Zoom in/out
- **Hover:** Show tooltips

### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| Space | End turn |
| Tab | Cycle ships |
| Q/E | Rotate camera |
| W/A/S/D | Pan camera |
| 1-9 | Quick actions |
| Esc | Menu/Cancel |

### Touch Controls (if applicable)
- Tap: Select
- Double tap: Confirm
- Pinch: Zoom
- Drag: Pan/Move

## Menu Systems

### Main Menu
- New Game
- Continue
- Load Game
- Settings
- Credits
- Exit

### In-Game Menu
- Resume
- Save Game
- Load Game
- Settings
- Surrender
- Main Menu

### Settings Menu
- **Graphics**
  - Resolution
  - Quality presets
  - Effects toggles
- **Audio**
  - Master volume
  - Music volume
  - SFX volume
- **Gameplay**
  - Difficulty
  - Turn timer
  - UI scale
- **Controls**
  - Key bindings
  - Mouse sensitivity

## Ship Management Interface

### Ship Detail Screen
- 3D ship preview
- Component health display
- Crew distribution
- Upgrade slots
- Statistics comparison

### Upgrade Interface
- Available upgrades grid
- Cost and requirements
- Before/after stats
- Confirm/cancel buttons

## Combat Interface

### Targeting System
- Arc of fire visualization
- Hit probability display
- Estimated damage
- Ammunition selector

### Damage Feedback
- Floating damage numbers
- Screen shake on hits
- Particle effects
- Sound feedback

### Boarding Interface
- Crew strength bars
- Action selection
- Outcome probability
- Retreat option

## Port/Harbor Interface

### Port Menu
- Repair dock
- Shipyard
- Tavern (crew)
- Market
- Admiralty

### Trading Interface
- Item grid
- Buy/sell prices
- Cargo capacity
- Transaction summary

## Feedback Systems

### Visual Feedback
- Button hover states
- Click animations
- Transition effects
- Loading indicators

### Audio Feedback
- UI click sounds
- Hover sounds
- Confirmation chimes
- Error buzzes

### Haptic Feedback (if applicable)
- Action confirmation
- Damage received
- Critical events

## Accessibility Features

### Visual Accessibility
- Colorblind modes
- UI scaling options
- High contrast mode
- Text size adjustment

### Audio Accessibility
- Subtitles
- Visual sound indicators
- Screen reader support

### Control Accessibility
- Remappable controls
- Hold-to-press options
- Reduced motion mode

## UI Flow Diagrams

### Turn Flow
```
Select Ship → Choose Action → Confirm → Execute → Next Ship
```

### Combat Flow
```
Enter Combat → Select Weapon → Choose Target → Roll Dice → Apply Damage
```

## Responsive Design

### Different Resolutions
- Minimum: 1280x720
- Standard: 1920x1080
- 4K: 3840x2160

### Aspect Ratios
- 16:9 (standard)
- 16:10 support
- 21:9 ultrawide support

## Onboarding and Tutorials

### First Time User Experience
1. Animated intro
2. Basic controls tutorial
3. First battle guidance
4. UI element introduction
5. Advanced tactics hints

### Help System
- Contextual tooltips
- Tutorial replay
- Rules reference
- Strategy guide

## Polish and Juice

### Animations
- Ship movement smoothing
- Wave effects
- Sail billowing
- Explosion effects

### Transitions
- Scene transitions
- Menu animations
- Camera movements

### Particle Effects
- Water splashes
- Cannon smoke
- Wood splinters
- Fire effects