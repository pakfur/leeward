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
	 2.2.1 plot ship movement, include tacking, wearing, beating upwind, sailing downwind etc
	 2.2.2 optional anchoring of ship if allowed
	 2.2.3 Plan any towing 
	 2.2.4 Allocate casting the lead to measure speed
	 2.2.5 Set sail state, including reefing, taking out reefs, striking sails on deck, updating sail plan for light winds, heavy winds, storms
	 2.2.6 Plan boarding party preparatlon
	 2.2.7 Plan crew reorganization, including reallocating sailors, allocating between sails and gunnery
	 2.2.8 Perform repairs, rigging, spars, hull, above and below the waterline. 
	 2.2.9 Allocate crew firefighting, reallocating crew to fight any fires
	 2.2.10 Gunnery and Marine fire, select targets, select which guns to fire, ammunition type, hull or rigging
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


### Movement Allowance (MA) Calculation
The calculated movement allowance (MA) depends on five factors: 
1. Speed Type: 3 types - L (Ship of the Line class), F (Frigate class), or C (Corvette class), each with 1 of 3 modifiers F (Fast), S (Slow), VS (Very Slow).
2. Wind Speed: 0 to 4.
3. Wind Facing: 4 types - L (luffing), C (close hauled), B (broad reach) and R (running before the wind).
4. Sail State: 4 levels - PS (plain sail), MS (Manuerving Sail), FS (fighting sail), NS (sails furled or dismasted)
5. Rigging Damage: Reflects damage. Range from 4 (no damage) to 0 (full damage, unusable)

---
#### Movement Allowance Tables (MA) Sail State / Wind Facing
(partial table, complete table has 9 * 3 * 4 * 3 * 4 = 1728 rows including all combinations of all 5 factors)
MA = 0-4, a dash (-) means that the Sail State is not available due to the Rigging Available value.




This diagram shows the relative wind facing value based on wind direction:
                                 L
Wind Direction:  |             ------
                 v          C /       \ C
                             /         \
                             \         /
                            B \       / B
                               ------
                                 R
*Wind facing diagram*

EXAMPLE: A fast frigate (ship speed=F/F) which is close-hauled (wind facing = C) at maneuvering sail (Sail = MS) in a moderate breeze (Wind SPeed = 3) and has 4 rigging sections remaining has a Movement Allowance of 4. Ignoring no deceleration or acceleration, the frigate could spend from O to 4 MP's in that game-turn. It could not expend more than 4 MP's even if it turns to Wind Facing B (where it would normally have an Movement Allowence of 7).

## Movement Rules

1. Calculate Movement Allowance (MA). This is the theoritical maximum movement allowed
2. Plot Actions spending MA until MA = 0, or movement restrictions are exceeded

Actions: 'F#' - move forward number of hexes, 'P' - pivot left 60 degrees to port, 'S' - pivot right 60 degrees to starboard 

EXAMPLE: A fast frigate (ship speed=F/F) which is close-hauled (wind facing = C) at maneuvering sail (Sail = MS) in a moderate breeze (Wind SPeed = 3) and has 4 rigging sections remaining has a Movement Allowance of 4. The player chooses to move 2 hexes forward, pivot to starboard and then continue forward 1 hex: The plotted course is 'F2 S F1'

*Action Table*

|   Action                    |  MA Cost                         |
| :-------------------------- | -------------------------------: |
|   Move Forward 1 hex        |  1                               |
|   Pivot 1 face to starboard |  1                               |
|   Pivot 1 face to port      |  1                               |
|   Pivot 1 face to starboard |  0 (if MA is 0, 1 time per turn) |
|   Pivot 1 face to port.     |  0 (if MA is 0, 1 time per turn) |


#### Movement Forward Rules:

A ship that does not change direction, may move forward the same number of hexes as the previous turn, accelerate faster, or decelerate. 

If accelerating: The number of hexes a ship can move forward is determined by the calculated MA, the ships acceleration and the number of hexes the ship moved forward the previous turn.

If decelerating: The number of hexes a ship can move forward is determined by the ships deceleration and the number of hexes the ship moved forward the previous turn. 

If the ship is accelerating:
  The number of hexes a ship may move forward in a single turn is calculated as: hexes = MIN(MA, ship acceleration value + hexes moved forward last turn)
If the ship is decelerating:
  The number of hexes a ship may move forward in a single turn is calculated as: hexes = MAX(MA, ABS(ship deceleration value - hexes moved forward last turn))
If the ship is maintaing the same speed:
  The number of hexes a ship may move forward in a single turn is calculated as: hexes = MAX(MA, ABS(ship deceleration value - hexes moved forward last turn))


#### Pivot Rules:

Pivoting facing L (luffing): A vessel that turns and faces L immediately ends its movement.

Ships have a level of maneuverability ranging from “A” (not very maneuverable) to “D” (very maneuverable).

A ship can make a maximum of 2 pivots per turn. After turning, a ship must move straight ahead a certain number of hexes before it can turn again. this number will depend on the ship's maneuverability, its speed, and whether the turn is made in the same direction as the previous turn. A ship can never make two turns consecutive. Exception: see tacking rules.

Vessels poivot by pivoting their bow, meaning the stern moves and the bow remains in
the hex where it was. 
	Exception: Anchoring with turnbuckles at the stern.



**Tacking Rules**

A ship that pivots its heading to L (luffing) may make an additional turn in the same direction on the same turn only, this maanuever is TACKING. Two consecutive pivots in the same direction may ONLY happen if the first pivot heading is L.  The two pivots are recorded during the PLANNING PHASE. The success or failure is determined during the MOVEMENT phase. The TACKING table is consulted during the MOVEMENT RESOLUTION phase to determine if the TACK was successful.

**TACKING Table**
Ships Manuever Rating (A-D) vs Wind Speed (1-4). The chance to sucessfully tack, cross reference the ships Manueverablity Rating vs current Wind Speed.

|                       | Wind Speed |     |     |     |
| Ships Manuever Rating | 1          | 2   | 3   | 4   |
| --------------------- | ---------- | --- | --- | --- |
|  A                    |  20%       | 40% | 60% | 50% |
|  B                    |  30%       | 50% | 70% | 60% |
|  C                    |  50%       | 70% | 80% | 70% |
|  D                    |  70%       | 80% | 90% | 80% |

If a ship is unsuccessful with the TACKING check, then the ship is immobilized and further movement is not possible this turn. The ship is facing L and immobilized. COMBAT RESOLUTION and MAINTENANCE phases may continue as normal. 

Also: 

- The number of allowed pivots per turn is determined by the ships rating (3.2). See Turning rules for details
- Each pivot to port or starboard will recalculate the maximum Movement Allowence allowed in that wind direction. The spent action points are subtracted from the new Movement Allowence. If the remaining movement allowence is <= 0 then the MA is set to 0.
- If MA = 0, player may pivot 1 time per turn to port or starboard
- If player luffs (pivots into wind facing L) forward direction stops for the turn. (exception: Fast Tack, see Fast Tack below)
- If a player is close hauled (WF = C) and as its first movement pivots to broad reach (WF = B) and has at least 1 movement allowence left, then the player gets 1 additional movement allowance


## Combat System
Gunnery is planned during the PLANNING PHASE
Combat is resolved during the COMBAT PHASE



### Engagement Rules
- **Range Bands:**
  - Long range: [15 hexes]
  - Medium range: [9 hexes]
  - Close range: [3 hexes]
  - Marine (small arms) range: [3 hexes]
  - Boarding range: [requirements]

### Cannon Combat
- **Firing Arcs:** [each ship has 4 batterys: Port/Starboard/Bow/Stern, ships may optionally have Marine (small arms) fire]
- **Line Of Sight**: 
  - Each battery (Port/Starboard/Bow/Stern) has an independent LOS calculation. 
  - A battery must have unobstructed LOS within a 60 degree arc to the target ship
  - A ship can have 2 targets. Each battery can target a different ship
  - Marine fire can target any ship in range.
- **Ammunition Types:**
  - Round shot: [damage/effects]
  - Chain shot: [damage/effects]
  - Grape shot: [damage/effects]

### Damage System [TODO]
- **Hull Points:** [How calculated]
- **Critical Hits:**
  - Mast damage
  - Rudder damage
  - Crew casualties
  - Fire
  - Magazine explosion

### Boarding Combat [TODO]
1. **Initiation Requirements**
2. **Crew Combat Resolution**
3. **Capture Conditions**

## Ship Statistics

### Core Attributes
- **Nationality:** [Ship nationality]
- **Rating:** [Number of guns, size] 100,98,80,74,64,50,44,40,38,36,32,28,24,14
- **Class:** [Rating class] 1, 2, 3, 4
- **Manuverability:** [Ship manuverability] a,b,c,d
- **Type:** [Ship type] SOL3 (Ship of the Line (3 decks)), SOL (ship of the line (2 decks)), 2D (2 deck ship), Rz (Razee), HF (Heavy Frigate), Frigate (Frigate), Corvette (Corvette class)
- **Draft:** [Ship draft] Draft, in feet
- **Freeboard:** [Freeboard] Height, in feet, of the height of the lower deck guns above the waterline
- **Rigging:** [Ships rigging] a ship has between 1-4 Rigging sections, one per mast + bowsprit
  - Rigging:Damage: [Damage to Rigging]
  - Rigging:Sail Quality: [Sail quality] 1-3
- **Hull Critical Hit Bonus:** [Ship Hull Critical Damage Modifier] from -4 to +2 (the value that is added to critical hit checks)
- **Hull Health:** [Ship hull hit points] A ship has 3 to 4 hull sections. Each section has a hit point value (from 0 - 10) that represents the max damage that hull section can take
- **Hull Damage Taken:** [Ship hull damage taken] One damage-taken per Hull health entry. Records the current number of hit points remaining for the hull section
- **Crew:** [Crew number and composition depends on ship class and type/ Each crew member is tracked independently. Not every ship has every role]
  - Role: Admiral, Commodore, Post Captain, Commander, Master, Lieutenant, Surgeon, Boatswain, Carpenter, Gunner, Midshipman, Chaplain, Quartermaster, Master at Arms, Sailmaker, Seamen (Landsman), Seamen (Ordinary Seaman), Seamen (Able Seaman), Seamen (Topmen), Marine, Sergeant 
  - Status: Healthy, Injured, Sick, Dead
  - Assigned: Current assigned task
  - Station: Current assigned station
- **Guns:** [Includes canon, carronades, swivel guns]
  - Type: Canon, Carronade, Swivel Gun
  - Canon Ball: Weight (in pounds) 1/2, 3/4, 1, 4, 8, 12, 18, 32, 42
  - Side: Port, Starboard, Bow, Stern
  - Deck: Gun Deck, Lower Deck, Main Deck



## Resources and Economy

### Resources [TODO]
- **Gold:** [Uses]
- **Supplies:** [Uses]
- **Ammunition:** [Types and limits]
- **Crew morale:** [Effects]

### Port Actions [TODO]
- [ ] Repair ship
- [ ] Recruit crew
- [ ] Buy supplies
- [ ] Upgrade ship

## Weather and Environmental Effects [TODO]

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
Simultaneous, turn based

### Balance Mechanisms
[Fleet points, handicaps, etc.]

## Special Rules

### National Abilities
[Different nations have different bonuses]

### Legendary Captains
[Special character abilities]

### Historical Scenarios
[Special rules for historical battles]
