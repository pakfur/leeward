# Leeward - Naval Combat Mechanics

## Combat Overview

### Engagement Types
- **Long Range Duel:** Artillery focused
- **Broadside Battle:** Classic ship-to-ship
- **Close Quarters:** Boarding preparation
- **Chase/Escape:** Pursuit mechanics
- **Fleet Action:** Multi-ship engagement

### Combat Phases
1. **Detection Phase:** Spotting and identification
2. **Maneuvering Phase:** Position for advantage
3. **Engagement Phase:** Exchange of fire
4. **Resolution Phase:** Damage and effects

## Wind Mechanics

### Wind System
**Wind Strength:**
- Calm: 0-5 knots (severe movement penalty)
- Light: 6-10 knots (small boats advantage)
- Moderate: 11-20 knots (ideal conditions)
- Strong: 21-30 knots (large ships advantage)
- Gale: 31+ knots (damage risk)

**Points of Sail:**
```
		 Wind Direction
			  ↓
		Into Wind (No Sail)
			/    \
	Close Hauled  Close Hauled
	 (45°)           (45°)
	   /              \
  Beam Reach      Beam Reach
	(90°)           (90°)
	  \              /
   Broad Reach   Broad Reach
	 (135°)        (135°)
		\          /
		 Running
		 (180°)
```

### Speed Modifiers
| Point of Sail | Speed Modifier |
|---------------|----------------|
| Into Wind | 0% (cannot sail) |
| Close Hauled | 60% |
| Beam Reach | 100% |
| Broad Reach | 90% |
| Running | 80% |

## Gunnery System

### Cannon Types
**By Size:**
| Type | Range | Damage | Reload | Special |
|------|-------|---------|---------|---------|
| 6-pounder | Short | Low | Fast | Anti-personnel |
| 12-pounder | Medium | Medium | Medium | Balanced |
| 24-pounder | Long | High | Slow | Ship killer |
| 32-pounder | Long | Very High | Very Slow | Fortress guns |

### Ammunition Types
**Round Shot:**
- Standard damage to hull
- Good range
- Penetration based on caliber

**Chain Shot:**
- Double damage to sails/rigging
- Half damage to hull
- Reduced range (-30%)
- Mobility kill potential

**Grape Shot:**
- Minimal hull damage
- Devastating to crew
- Very short range only
- Boarding preparation

**Heated Shot:**
- Standard damage + fire chance
- Requires special equipment
- Risk to own ship

### Firing Mechanics

#### Range Bands
**Point Blank (0-100m):**
- +30% accuracy
- +20% damage
- Penetration guaranteed

**Short (100-300m):**
- +10% accuracy
- Standard damage
- High penetration

**Medium (300-600m):**
- Standard accuracy
- Standard damage
- Normal penetration

**Long (600-1000m):**
- -20% accuracy
- -10% damage
- Reduced penetration

**Extreme (1000m+):**
- -40% accuracy
- -20% damage
- Minimal penetration

#### Accuracy Calculation
```
Base Accuracy: 60%
+ Gunner skill bonus
+ Captain gunnery bonus
- Range penalty
- Target speed penalty
- Weather penalty
- Damage penalty
= Final Hit Chance
```

### Broadside Mechanics
**Full Broadside:**
- All guns on one side fire
- Maximum damage potential
- Long reload time
- Ship stability affected

**Rolling Broadside:**
- Guns fire in sequence
- Sustained damage
- Continuous pressure
- Better reload management

**Bow/Stern Raking:**
- Firing through length of enemy
- 2x damage multiplier
- Increased critical chance
- Devastating morale impact

## Damage Model

### Hit Locations
**Hull Sections:**
- Bow (15% chance)
- Port/Starboard (35% each)
- Stern (15% chance)

**Critical Components:**
| Component | Hit Chance | Effect |
|-----------|------------|---------|
| Masts | 15% | Speed reduction |
| Rudder | 10% | Maneuver penalty |
| Gun Deck | 20% | Firepower reduction |
| Magazine | 5% | Explosion risk |
| Waterline | 10% | Flooding |

### Damage Types

#### Hull Damage
- Reduces ship HP
- Can cause flooding
- Affects structural integrity
- Repair priority

#### Sail Damage
- Reduces maximum speed
- Affects maneuverability
- Can be quickly repaired
- Weather vulnerability

#### Crew Casualties
- Reduces efficiency
- Affects all actions
- Morale impact
- Cannot be repaired in battle

#### System Damage
**Fire:**
- Spreads each turn
- Damages multiple systems
- Crew panic
- Can be fought

**Flooding:**
- Progressive hull damage
- Speed reduction
- Stability loss
- Pumps required

### Armor and Penetration
**Armor Values:**
- Sloop: 50mm oak
- Frigate: 100mm oak
- Ship of the Line: 150mm oak
- Ironclad: 200mm iron

**Penetration Formula:**
```
Penetration = Cannon Power × (1 - Range Penalty) - Armor Value
If Penetration > 0: Full damage
If Penetration < 0: Reduced/No damage
```

## Boarding Combat

### Boarding Prerequisites
- Adjacent positioning
- Speed matching
- Grappling successful
- Or ram successful

### Boarding Phases
1. **Approach:** Close distance under fire
2. **Grappling:** Hooks and lines
3. **Assault:** Crew combat
4. **Capture:** Control achieved

### Crew Combat
**Combat Power Calculation:**
```
Base Power = Number of Crew
× Marine multiplier (1.5x)
× Morale modifier (0.5x to 1.5x)
× Captain leadership
× Equipment bonus
```

### Boarding Outcomes
- **Victory:** Capture enemy ship
- **Repelled:** Return to ships
- **Stalemate:** Continue next round
- **Defeat:** Ship captured

## Special Maneuvers

### Tactical Actions
**Crossing the T:**
- Position perpendicular to enemy line
- Full broadside vs minimal return
- Requires superior position

**Breaking the Line:**
- Pass through enemy formation
- Rake multiple ships
- High risk, high reward

**Wearing Ship:**
- Emergency 180° turn
- Slower than tacking
- Works in any wind

### Emergency Actions
**Cut the Masts:**
- Voluntary mast destruction
- Instant speed loss
- Improved stability in storm

**Dump Cargo:**
- Increase speed
- Lose valuable resources
- Desperation move

**Scuttle Ship:**
- Deny capture
- Last resort
- Crew evacuation required

## Environmental Combat Factors

### Weather Effects
**Fog:**
- Visibility reduced to 200m
- -30% accuracy
- Surprise attacks possible

**Storm:**
- Movement restricted
- -50% accuracy
- Damage from weather

**Rain:**
- -20% accuracy
- Fire prevention
- Reduced visibility

### Terrain Interaction
**Shallow Water:**
- Large ships restricted
- Grounding risk
- Escape routes limited

**Islands/Rocks:**
- Cover from fire
- Collision danger
- Ambush positions

**Currents:**
- Movement modification
- Predictable patterns
- Tactical advantage

## Combat Resolution

### Victory Conditions
- Enemy surrenders (morale broken)
- Enemy destroyed (0 HP)
- Enemy captured (boarding)
- Enemy retreats (escapes board)

### Surrender Mechanics
**Surrender Factors:**
- Hull below 25%
- Crew below 30%
- Captain killed
- Surrounded

### Post-Combat
**Salvage:**
- Cargo recovery
- Ship repair materials
- Weapon acquisition
- Prisoner ransom

**Repairs:**
- Emergency patches
- Sail replacement
- Crew treatment
- Pump flooding

## Multiplayer Combat Considerations

### Simultaneous Planning
- Both players plan secretly
- Actions resolve simultaneously
- No reaction advantage

### Time Limits
- Turn timer: 2-5 minutes
- Combat timer: 30 seconds per decision
- Overall match: 30-60 minutes

### Balance Mechanics
- Fleet point limits
- Matchmaking by skill
- Symmetric scenarios
- Asymmetric balance