# Leeward - Game Rules and Mechanics

## Board and Setup

### Board Layout
- **Grid Type:** Hex grid, Isometric
- **Board Size:** [infinite, lazy loading], zoomable viewport
- **Terrain Types:**
  - [X] Open water
  - [X] Shallow water
  - [X] Islands
  - [X] Ports
  - [X] Reefs/obstacles

### Scenarios
- Scenarios determine initial setup conditions and placement of ships, terrain, weather, sea condition etc
- Scenarios are packaged in a plain folder format, zip file or PCK archive
- Scenarios include settings, assets, custom scripts, images

### Initial Setup (Configurable per Scenarios)
1. Weather
  1.1 Wind direction (1-6 (the face of a hex))
  1.2 Wind direction change: enum: [Oceanic, Costal, None] Used to determine what wind direction change is possible during an encounter
  1.2 Wind Speed at start: [0 (still), 1 (low), 2 (light winds), 3 (average), 4 (strong), 5 (tempest)]
  1.3 Wind Speed Change: [variable, steady]
2. Sea State [0-3]
3. For each ship in the battle set the ship initial setup
  3.1 Sail State per ship: [Furl/D (all sails furled, or ship entirely dismasted), FS (fighting sail), MS (maneuvering sail), or PS (plain sail)]
  3.2 Rating: [rating (First, Second, Third, Fourth, Fifth, Sixth, Unrated), number of long guns) 
  3.3 Ship Name, Ship Nationality
  3.4 Speed (relative to other ships with the same rating): [VS (very slow), S (slow), A (average), F (Fast), VF (Very Fast)]
  3.5 Long Guns [count, canon ball size, location (main deck port or starboard, gun deck, lower deck, chasers, )]
  3.6 Carronades [count, canon ball size, location (port, starboard, fore, aft)]
  3.7 Hull sections [damage rating, damage taken]
  3.8 Rigging [0-10 per spar]
  3.9 Position on map, facing
  3.10 Ship acceleration/deceleration values
4. Crew
  4.1 Crew Sections [count, section number (1-4), type (ordinary, marine, topmen, officers), creq quality (Elite, Veteran, Trained, Green, Lubber), morale (2, 3, 4, 5)]

  

## Turn Structure

### Phase Order

(phases that start with a ++ require player interaction, phases that start with a == must be done server-side if multiplayer)
1. == ENVIRONMENT PHASE
  1.1. Update Wind Direction
  1.2. Update Wind Speed
  1.3. Perform Ship Sail checks to see if ship rigging or sail is damaged.

 2. ++ PLANNING PHASE (Player Interaction Required)
   2.1 For each ship under the players command, allow the user to select a ship and show a UI where the player can plot actions for this turn.
   2.2 Plot actions permit the player to update none, some or all of the following item: (All optional)
     2.2.1 Game calculate movement points (MP) (below) 
     2.2.2: Move ship, using MP. A ship may perform one of three possible actions with each MP. Move forward 1 hex, turn left (port) one hex facing, turn right (starboard) one hex facing. Plot all ship movement steps. Include moving forward and turning. Detailed moving and turning rules are below.
     2.2.2 optional anchoring of ship if allowed
     2.2.3 Plan any towing 
     2.2.4 Allocate casting the lead to measure speed
     2.2.5 Set sail state, including reefing, taking out reefs, striking sails on deck, updating sail plan for light winds, heavy winds, storms
     2.2.6 Plan boarding party preparatlon
     2.2.7 Plan crew reorganization, including reallocating sailors, allocating between sails and gunnery
     2.2.8 Perform repairs, rigging, spars, hull, above and below the waterline. 
     2.2.9 Allocate crew firefighting, reallocating crew to fight any fires
     2.2.10 Gunnery and Marine fire, select targets, select which guns to fire
     2.2.11 send messsages between ships (using flags)
   2.3 Some plotted actions may take multiple turns to complete, and require allocated crew to complete
   2.4 Player submits all plotted actions
   2.5 Player sends and messages (using constrained "flags" system)

3. == MOVEMENT RESOLUTION PHASE
  3.1 For each ship:
  3.2 If the ship is "In Irons" (facing the wind, can't move) then there is a chance the ship can escape. Roll to see if the ship is still In Irons or is stuck.
  3.3 For all other ships that plotted movement (2.2.1) 
    3.2.1 resolve plotted movement
    3.3.2 Resolve contested hexes
    3.3.2 Resolve any ship ramming
  3.4 Update the Map

4. == COMBAT RESOLUTION PHASE
  4.1 Resolve Gunnery and Marine fire for guns plotted in 2.2.10. Visually update the UI for dramatic effect
  4.2 Resolve boarding attacks
  4.3 Resolve any critical hits, "man the pumps"
  4.4 Update the map

5. == DRIFT CALCULATION PHASE 
  5.1 Resolve "drifting" or "fouling" for dismast4ed ships, or rammed ships
  5.2 Update ship position and status

6. == STATUS ADJUSTMENT
  6.1 Resolve exploding ships (based on combat damage 4.1)
  6.2 Resolve sinking ships (based on hull damage from 4.1)
  6.3 Update sail state according to 2.2.5
  6.4 Resolve any repairs started with 2.2.8
  6.5 Resolve any crew reorginization plotted with 2.2.7
  6.6 Resolve any anchors changes with 2.2.2
  6.7 Display current knots if 2.2.4 was cast
  6.8 Resolve any multi-turn plotted actions

7. == MORALE CHECKS
  7.1 Update crew morale state

8. == Message Delivery 
  8.1 Messages from other ships flags (2.5) delivered and displayed 

9. ++ POST COMBAT (Player Interaction Required)
  9.1 UI displays current state fo ships. 
  9.2 Player may take any of the following actions:
  9.3 Grappling/Ungrappling rules. Player can select an adjacent ship and grapple, or ungrapple
  9.4 Unfouling actions. Player may choose to unfoul any fouled ship
  9.5 Fire damage. Player may choose to fight any fires on board

10. ++ Player (or AI) may choose to strike (surrender) one or more ships
  10.1 Player may end turn, strike colors for some or all ships, or accept surrender of enemy ships

11. Player ends the turn. Next turn begins


### Movement Allowance Calculation
Calculate Movement Allowence Points on the Movement Allowance Table. 
Spend 1 Movement Allowance (MA) for 1 Movement Point (MP).

Base Values in the table vary by ship type, rating, speed

Movement Allowance Table

| Wind Facing |     FS     |    MS     |    PS    |
| :---------- |  :-------: | :------:  | -------: |
|   L         |     ##     |    ##     |    ##    |
|   C         |     ##     |    ##     |    ##    |
|   B         |     ##     |    ##     |    ##    |
|   R         |     ##     |    ##     |    ##    |

Sail State:
FS = Fighting Sails
MS = Manuerving Sails
PS = Plain Sails

Wind Facing
L = luffing
C = close hauled
B = broad reach
R = running before the wind

Factors which also affect Movement Allowance:
- Ruder Destroyed
- Ships wheel destroyed
- Rigging Damage
- Wind Speed
- Crew Quality
- Ship Speed (3.4)
- Sail State (3.10)
- Sail Quality

EXAMPLE: A fast frigate (ship speed=F) which is close-hauled (wind facing = C) at maneuvering sail (Sail = MS) in a moderate breeze (Wind SPeed = 3) and has 4 rigging sections remaining has a Movement Allowance of 4. Ignoring no deceleration or acceleration, the frigate could spend from O to 4 MP's in that game-turn. It could not expend more than 4 MP's even if it turns to Wind Facing B (where it would normally have an Movement Allowence of 7).

## Movement Rules

### Basic Movement
- Calculate Movement Allowance (MA)
- Spend MA to make a movement

Action Table

|   Action                    |  MA Cost                         |
| :-------------------------- | -------------------------------: |
|   Move Forward 1 hex        |  1                               |
|   Pivot 1 face to starboard |  1                               |
|   Pivot 1 face to port      |  1                               |
|   Pivot 1 face to starboard |  0 (if MA is 0, 1 time per turn) |
|   Pivot 1 face to port.     |  0 (if MA is 0, 1 time per turn) |


Exceptions: 

- The number of allowed pivots per turn is determined by the ships rating (3.2). See Turning below
- Each pivot to port or starboard will recalculate the maximum Movement Allowence allowed in that wind direction. The spent action points are subtracted from the new Movement Allowence. If the remaining movement allowence is <= 0 then the MA is set to 0.
- If MA = 0, player may pivot 1 time per turn to port or starboard
- If player luffs (pivots into wind facing L) forward direction stops for the turn. (exception: Fast Tack, see Fast Tack below)
- If a player is close hauled (WF = C) and as its first movement pivots to broad reach (WF = B) and has at least 1 movement allowence left, then the player gets 1 additional movement allowance


- **Turning Rules:** 

Turning Table
|   Ship Class                |  Speed       |
| :-------------------------- | -----------: |
|   Move Forward 1 hex        |  1                               |


  1. General Rules:
  1.1 A ships manuverability depends on wether the ship is pivot the _same_ direction or _opposite_ direction compared to the last time it pivoted. 
  1.2 All previous moves are recorded as they play a role in determining future movement options. Recorded moves are _not_ reset at the beginning of a turn.
  1.2 Example movement record: F = move 1 hex forward, P = pivot 1 hex face to port, F = pivot one hex face to starboard. "PFFFPF" (turn to port, move 3 hexes forward, turn to port, move 1 hex forward)

  2. Turning in the same direction:
  2.1 There must be 0-3 "F" movements in the movement record between two turns in the same direction. 



pseudo code
```python

from Move import move
from Board import board


class Ship:
  def __init__(self, rating: Int):
    self.rating = rating
    self.previous_turn = None
    self.forward_hex_moves_since_last_turn = 0


  def turn(self, move, direction) -> int:

    match move.direction:
      case "forward":
        if movement_allowed(move.direction):


```



- **Speed:** [Base movement + modifiers]
- **Turning:** [Turning radius/restrictions]
- **Wind Effects:**
  - Sailing with wind
  - Sailing against wind
  - Tacking mechanics

### Special Maneuvers
- [ ] Full sail
- [ ] Emergency turn
- [ ] Ram
- [ ] Boarding preparation

## Combat System

### Engagement Rules
- **Range Bands:**
  - Long range: [effects]
  - Medium range: [effects]
  - Close range: [effects]
  - Boarding range: [requirements]

### Cannon Combat
- **Firing Arcs:** [Port/Starboard/Bow/Stern]
- **Ammunition Types:**
  - Round shot: [damage/effects]
  - Chain shot: [damage/effects]
  - Grape shot: [damage/effects]

### Damage System
- **Hull Points:** [How calculated]
- **Critical Hits:**
  - Mast damage
  - Rudder damage
  - Crew casualties
  - Fire
  - Magazine explosion

### Boarding Combat
1. **Initiation Requirements**
2. **Crew Combat Resolution**
3. **Capture Conditions**

## Ship Statistics

### Core Attributes
- **Hull:** [Health/armor]
- **Speed:** [Maximum movement]
- **Maneuverability:** [Turn rate]
- **Firepower:** [Number of guns]
- **Crew:** [Size and quality]

### Ship Classes
| Class | Hull | Speed | Guns | Crew | Special |
|-------|------|-------|------|------|---------|
| Sloop | | | | | |
| Frigate | | | | | |
| Ship of the Line | | | | | |

## Resources and Economy

### Resources
- **Gold:** [Uses]
- **Supplies:** [Uses]
- **Ammunition:** [Types and limits]
- **Crew morale:** [Effects]

### Port Actions
- [ ] Repair ship
- [ ] Recruit crew
- [ ] Buy supplies
- [ ] Upgrade ship

## Weather and Environmental Effects

### Wind
- **Wind Direction:** [How it changes]
- **Wind Strength:** [Effects on movement]

### Weather Conditions
- **Clear:** Normal conditions
- **Fog:** [Visibility effects]
- **Storm:** [Movement/combat penalties]
- **Calm:** [No wind effects]

### Environmental Hazards
- Reefs: [Damage effects]
- Shallow water: [Movement restrictions]
- Currents: [Movement modifiers]

## Victory and Defeat

### Scenario Objectives
- Destroy enemy fleet
- Capture specific ships
- Control ports
- Escort missions
- Time-based objectives

### Defeat Conditions
- All ships destroyed
- Flagship captured
- Morale collapse
- Time limit exceeded

## Multiplayer Rules

### Turn Time Limits
[If applicable]

### Simultaneous vs Sequential
[Turn order system]

### Balance Mechanisms
[Fleet points, handicaps, etc.]

## Special Rules

### National Abilities
[Different nations have different bonuses]

### Legendary Captains
[Special character abilities]

### Historical Scenarios
[Special rules for historical battles]