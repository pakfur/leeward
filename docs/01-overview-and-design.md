# Leeward - Game Overview and Design

## Game Concept
**Genre:** Turn-based naval combat board game with RPG and progression elements  
**Setting:** 19th century Age of Sail  
**Platform:** Desktop  

### Core Pillars
- [ ] Strategic turn-based combat
- [ ] Historical authenticity
- [ ] Character/ship progression
- [ ] Tactical depth

## Game Vision
Leeward is a realistic game system that combines tactical naval combat during the Napoleonic era with character progression and advancement. Players engage in a series of naval combat scenarios, testing their seamanship, leadership and tactical skills. The scenarios available to the player depend on their chosen career. Characters may choose between one of three careers, a British Naval career, a British privateer, or a deadly pirate. 

Game play: Leeward is turn based board game, where the player is presented with a hex board where tactical naval combat occurs. Leeward uses a simultaneous movement game turn based system to resolve combat. At the beginning of each game-turn, all players (AI included) plot their actions for that game-turn on virtual ship logs. The plots are then revealed and executed simultaneously. As a ship captain, the player will have four areas of concerns: seamanship, combat, crew management, and ship management. Finally, Lewward includes a rich progression system which will allow players to choose a career and track their progress from leading small ships through leading large naval battles.

### Player Areas of Concerns:
1. Seamanship: To defeat the enemy, you must bring them to battle under conditions that give you an overall edge. In the age of sail, ships were dependent upon the variable winds for movement, tactical initiative generally rested with the side that held the upwind (windward) position from their enemies. Naval tactics were dominated by the struggle for the weather gauge advantage, and seamanship (the ability to maneuver a ship skilfully) was often the decisive factor in naval battles.

2. Combat: There are three possible forms of comabat in Leeward: gun fire, marine fire, and boarding. 
**Gun fire** includes both fore and aft mounted cannons, but the primary power of a warship came the broadside, the massed destructive power of up to 70 side-firing cannon. The purpose of gun fire was to disable the ship by damaging the ships rigging and sails, injure or kill enemy crew or ultimatly to sink an enemy ship.

**Marine fire** includes everything from the firing of muuskets and pistols from the main deck and tops, to lobbing explosive grenados to the enemy ship. Marine fire was primarly used to kill enemy creew or eliminate enemy ship command through use of snipers.

**Boarding** as a form of combat was a high risk manuever where crew would attempt to board the enemys ship and overwhelm the crew with hand-to-hand combat. While boarding was sometimes sucessful, it was a high risk manuever that was usually not successful.

3. Crew management: There are two types of crew in Leeward - sailor crew sections and marine crew sections. Sailor crew sections can perform all crew functions except marine fire - issue orders, fire the guns, set or take in sail, make repairs, anchor, and so forth. Marines can perform all crew functions except firing the ship's guns. Only ships available in the Naval career may use marine crew. Privateer and Pirate careers do not have access to marine crew.

The key statistics about the crew are its **quantity** (the number of crew available to perform sailing, gunnery, marine fire, repair, etc), its **quality**. which can vary from 'Able' to 'Seaman', to 'Lubber', reflecting the state of training. Quality has wide-ranging effects on your ship's gunfire and many other situations. 
Secondary statistics include moral which quantifies how willing the crew are to keep fighting can vary from (High morale to Demoralized). As your ship takes battle casualties crew quantity and morale can be affected.


4. Ship management: The sailing ships of the era were complex machines, which required constant upkeep and repairs to keep in top shape for effective seamanship and combat. The condition of ships rigging and sails, the state of the spars and masts, hull condition, the state of the rudder all affect the ability of the ship to manuever and ultimately the ability of the ship to fight. 
A damaged ship may require valuable crew to be taken away from sailing and gunnery duties and moved into ship repair, reducing the combat effectiveness of the ship. 

### Player Progression

Player progression tracks the players journey through their career. As the player progresses, new, larger ships are available, more challenging scenarios are opened up and the rewards increase. Each career has different incentives, rewards, and scenarios available.

1. Naval Officer Career
  1.1 Progression: Lieutenant -> Commander (AKA Master and Commander) -> Post Captain -> Commodore (role) -> Admiral
  	1.1.1 
  1.2 Progression Currency: Naval officers rely on patronage and influence to get better ships, desirable stations, promotions. Fiat currency can be earned as well, but that is often spent on repairing the ship, and on supplies and crew. 
  	1.2.1 Naval officers select a patron at the start of their career. A patron can use their influence to give access to better naval ships, posting stations, supplies, crew.
  	1.2.2 Completing missions rewards currency to the player, and influence to the patron
  	1.2.3 The more influence a player genmerates for the patron, the more rewards they can get.
  	1.2.4 Spending a patrons influence reduces the influence available to the patron
  1.3 Mission focus: Missions are focused on military support. Convoy duty, SHore bombardments, Snatching up merchants, 1:1 tactical battles with similar ships, multi-ship engagements, Commodore duty managing multiple ships, fleet actions with line of battle ships
  	1.3.1 Rewards: Influence primary objective. Some financial rewards but less than other careers.

 2. Privateer
 	2.1 Progression: Players can start as a privateer career in one of two paths:
 		2.1.1. They earn a Letter of marque after aquiring the Commander rank in the Navy, leave the navy and become a privateer self funded.
 		2.1.2. Start as a private citizen, in debt to investors who fund the ship costs and take most of the profits until player can buy out the investors.
 		2.1.3. Privateers have protection from warships from the country who issued the letter of marque.
 		2.1.4. Privateers can use naval docks and naval stores from their country, at an increased price compared to a naval ship.
 	2.2 Progression Currency: Privateers focus on aquiring currency, through capturing merchants or capturing ans selling miliitary vessels. Purchasing or buying outright what they need. Sometimes from shady sellers.
 		2.2.1 If a player has investors then they can draw down from the investors money for upgrades, repairs etc. But must pay it back
 		2.2.2 A player can buy out investors and self-fund
	2.3 Completing missions rewards currency to the player

3. Pirates
	3.1 Progression: Players can start as a pirate career in one of two paths:
 		3.1.1. They desert after aquiring the Commander rank in the Navy, leave the navy and become a pirate self funded.
 		3.2.2. The start out as a new Pirate with limited starting funds, small ship and crew.
 		3.1.3. Pirates have no protection from warships from any country.
 		3.1.4. Pirates can only use secret ports for refitting, supplies and repairs and upgrades.
 	3.2 Progression Currency: Pirates focus on aquiring currency, through capturing merchants or capturing ans selling miliitary vessels. Purchasing or buying outright what they need. Sometimes from shady sellers.
 		3.2.1 If a player has investors then they can draw down from the investors money for upgrades, repairs etc. But must pay it back
 		3.2.2 A player can buy out investors and self-fund
	3.3 Completing missions rewards currency to the player
		3.3.1. Pirates get the most bonuses from selling supplies of any career track.


## Target Audience
- Military enthusiasts
- Historical simulation fans
- Board game players

## Core Gameplay Loop
Represents gameplay during tactical naval combat

1. ENVIRONMENT PHASE
2. PLAN PHASE (Player Interaction Required)
3. MOVEMENT RESOLUTION PHASE
4. COMBAT RESOLUTION PHASE
5. DRIFT CALCULATION PHASE
6. SHIP/CREW STATUS UPDATE PHASE
9. END OF TURN DISPLAY AND UPDATES PHASE
10. END OF TURN


## Victory Conditions
- [ ] Primary win condition
	- all opposing ships have struck their colors, sank, or been destroyed, burnt or fled

- [ ] Secondary objectives
	- NA

- [ ] Fail states
	- all players ships have struck, sank, been destroyed, burt or fled

## Game Modes
### Campaign Mode
[Description of single-player campaign]
TBD

### Skirmish Mode
- player selects from available mnissions based on career and rank, or progression
- game places the ships in starting position on hex map 
- combat begins following the game loop per turn until win or fail conditions met 

### Multiplayer
[If applicable, describe multiplayer modes]
TBD

## Setting and Narrative

### Historical Period
[Specific era, notable events, technological level]
Napoleonic era, 1790-1814 time period. 

### Geographic Setting
[Regions, important locations, map scope]
- Regions will include geographic regions associated with British sea battles between 1790 and 1814

### Narrative Framework
[How story is delivered, main narrative arc]
TBD

## Art Direction

### Visual Style
[Art style, influences, mood]
- Board game style
- 19th century nautical style for all maps, dialogs and UI elements
- Simple 3d Models
- Isometric Hex Map


### Color Palette
[Primary and secondary colors, meaning]
- Browns, greens, yellows, natural colors, muted colors for major UI elements

### UI Theme
[Naval/nautical themed elements]

## Audio Direction

### Music Style
[Period-appropriate music, combat themes]

### Sound Effects
- Ship sounds (creaking, sails, etc.)
- Combat sounds (cannons, impacts)
- Environmental (ocean, weather)
- UI feedback sounds

## Unique Selling Points
TBD

## Scope and Constraints

### Must Have (MVP)
- [X] Core Game loop
- [X] Mission selection

### Should Have
- [X] Career selection
- [X] Different missions per Career

### Nice to Have
- [X] Support for Game Server Authortative State update and Multiplayer
- [X] Login, Matchmaking, Game stats
- [X] RPG elements
- [X] Career Progression

## Success Metrics
TBD
