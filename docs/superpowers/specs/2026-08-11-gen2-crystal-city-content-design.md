# Gen2 (Crystal) City Content Roadmap

Status: proposed, 2026-08-11
Date: 2026-08-11

## Context

The Crystal port already has a real extraction/import pipeline, ROM-backed
maps, and hand-ported behavior files under `data/scripts/crystal_*.lua`.
What it does **not** have yet is one execution spec that says, city by city:

- what content exists in the decompiled ROM,
- which map files and interiors define that content,
- which scripted events matter for gameplay progression,
- which engine features are required before each city can be called
  faithful.

Without that, the work keeps happening reactively by route or by bug
report, which is fine for one-off fixes but not for city-scale parity.

This spec turns the settlement content of Crystal into a spec-driven
backlog. It is deliberately implementation-oriented: every city entry names
the ROM files to read, the expected player-facing content, the event types
the engine must support, and a concrete "definition of done".

## Goal

Define a city-by-city implementation script for Pokémon Crystal content on
gen1recomp, grounded in `roms/pokecrystal`, that future work can execute in
 slices without re-deriving scope from scratch.

## Non-goals

- Byte-level extraction details for every NPC text pointer. Those remain in
  the per-slice implementation plans and `tools/make_rom_manifest_crystal.py`.
- Route-by-route encounter tables or dungeon room-by-room specs.
- Gold/Silver divergence.
- Rewriting the existing Crystal roadmap. This spec complements
  `docs/superpowers/plans/2026-08-06-gen2-crystal-roadmap.md`; it does not
  replace it.

## Source of truth

For every city spec below, the baseline files are:

- `roms/pokecrystal/data/maps/maps.asm`
- `roms/pokecrystal/constants/map_constants.asm`
- `roms/pokecrystal/data/maps/attributes.asm`
- `roms/pokecrystal/maps/<CityOrInterior>.asm`
- `roms/pokecrystal/constants/event_flags.asm`
- `roms/pokecrystal/engine/events/std_scripts.asm`

Use `maps.asm` for the list of interiors tied to a city/landmark, and the
per-map `.asm` files for the real warps, signs, coord events, callbacks,
objects, gifts, and battles.

## Delivery model

Each city implementation slice should produce:

1. Manifest coverage in `tools/make_rom_manifest_crystal.py`
2. Regenerated `tools/rom_manifest_crystal.json`
3. One or more `data/scripts/crystal_<map>.lua` files
4. Any engine capability needed by that city's events
5. Full regression run with `luajit tests/run_engine.lua`
6. Cache marker bump if old Crystal caches would silently miss the new maps

## Event dependency taxonomy

Before porting a city, classify its events into these buckets:

- `Simple talk/sign/item`: `jumptext*`, `itemball`, hidden items, one-shot gifts
- `Scene / coord event`: rival ambushes, escorts, map-entry cutscenes
- `Trainer battle`: `OBJECTTYPE_TRAINER`, sight checks, rematches, phone flows
- `System unlock`: Flypoint, radio/map card, Magnet Train, bike, Pokégear features
- `Quest state`: Rocket takeover, medicine delivery, machine-part return, GS Ball, etc.
- `Time/day gated`: weekday siblings, day/night visibility, call flags
- `Attached landmark`: tower, lighthouse, cave, port, well, den, forest gate

The first bucket is cheap. The others usually require engine work before the
city can be considered complete.

## Definition of done, globally

A city is "done" only when:

- its outdoor map is reachable from the current progression path,
- all mandatory entry/exit warps for the city loop resolve,
- its mandatory story gates and rival/gym events behave correctly,
- its required interiors exist and are navigable,
- optional NPC flavor may remain partial only if explicitly documented,
- all deliberate simplifications are called out in comments or docs.

---

## Settlement order

This is the recommended city-first implementation order, matching Crystal's
main progression and keeping dependencies local.

1. New Bark Town
2. Cherrygrove City
3. Violet City
4. Azalea Town
5. Goldenrod City
6. Ecruteak City
7. Olivine City
8. Cianwood City
9. Mahogany Town
10. Blackthorn City
11. Pallet Town
12. Viridian City
13. Pewter City
14. Cerulean City
15. Vermilion City
16. Lavender Town
17. Celadon City
18. Saffron City
19. Fuchsia City
20. Cinnabar Island

---

## Johto Cities

### New Bark Town

**ROM anchors**

- `maps/NewBarkTown.asm`
- `maps/ElmsLab.asm`
- `maps/PlayersHouse1F.asm`
- `maps/PlayersHouse2F.asm`
- `maps/PlayersNeighborsHouse.asm`
- `maps/ElmsHouse.asm`

**Content**

- Starter town exterior
- Player home, neighbor home, Elm's lab, Elm's house
- First outbound gate toward Route 29
- Intro/start save setup, Mom setup, starter selection, Pokégear bootstrap

**Key ROM events**

- Teacher stops player before receiving a Pokémon
- Flypoint callback
- Mom banking/savings setup
- Elm lab starter choice and Mystery Egg quest start

**Dependencies**

- Scene / coord-event support
- Basic gifts / starter selection / party injection
- House interiors and player bedroom fidelity

**Done when**

- New game flow is fully walkable and starter acquisition is faithful
- Pre-starter route blocking matches Crystal behavior
- Every mandatory intro interior works

### Cherrygrove City

**ROM anchors**

- `maps/CherrygroveCity.asm`
- `maps/CherrygroveMart.asm`
- `maps/CherrygrovePokecenter1F.asm`
- `maps/CherrygroveGymSpeechHouse.asm`
- `maps/GuideGentsHouse.asm`
- `maps/CherrygroveEvolutionSpeechHouse.asm`

**Content**

- First real town hub
- Mart, PokéCenter, Guide Gent house, gym-speech house, evolution-speech house
- Route 30 connection and Route 29 return path

**Key ROM events**

- Guide Gent town tour and Map Card grant
- Rival battle trigger on return trip
- Mystic Water one-time gift
- Early flavor NPCs about Route 30, gyms, evolution

**Dependencies**

- Guided escort / follow scripts for the tour
- Rival scene and battle
- One-shot gifts
- Mart and nurse behavior

**Current port status**

- Outdoor map and core interiors exist
- Flavor NPCs and gifts partially ported
- Guide Gent tour and full rival return scene still belong to the "scene" bucket

**Done when**

- The city loop from Route 29 -> Cherrygrove -> Route 30 -> return trip works
- Mandatory rival/tour content is faithful
- All registered interiors are usable and visually correct

### Violet City

**ROM anchors**

- `maps/VioletCity.asm`
- `maps/VioletMart.asm`
- `maps/VioletGym.asm`
- `maps/EarlsPokemonAcademy.asm`
- `maps/VioletNicknameSpeechHouse.asm`
- `maps/VioletPokecenter1F.asm`
- `maps/VioletKylesHouse.asm`
- `maps/Route31VioletGate.asm`
- Attached landmark: `maps/SproutTower*.asm`

**Content**

- First gym city
- Mart, PokéCenter, Earl's Pokémon Academy, nickname speech house, Kyle's house
- Access to Sprout Tower and Route 32

**Key ROM events**

- Flypoint callback
- Earl/academy tutorial flavor
- Falkner gym progression
- Sprout Tower monk sequence and HM/flash-adjacent progression setup

**Dependencies**

- Trainer battles in gym and tower
- Multi-floor tower support
- City-to-landmark sequencing

**Current port status**

- Route 31 and `Route31VioletGate` are now in scope
- Violet City itself is the next major city slice

**Done when**

- Player can enter Violet, clear Sprout Tower, beat Falkner, and exit toward Route 32

### Azalea Town

**ROM anchors**

- `maps/AzaleaTown.asm`
- `maps/AzaleaPokecenter1F.asm`
- `maps/AzaleaMart.asm`
- `maps/KurtsHouse.asm`
- `maps/AzaleaGym.asm`
- Attached landmarks: `maps/SlowpokeWell*.asm`, `maps/IlexForest*.asm`

**Content**

- Second gym city
- Kurt quest hub
- Slowpoke Well / Team Rocket intro
- Ilex Forest exit hub

**Key ROM events**

- Rival battle on entering town
- Kurt rescue / Slowpoke Well chain
- Gym clear
- GS Ball return scene later in the game

**Dependencies**

- Coord-event rival battle
- Trainer battles and Rocket event flags
- Multi-map quest state
- Later-game return scene support

**Done when**

- Bugsy progression and Slowpoke Well are faithful
- Kurt's early and late quest states resolve correctly

### Goldenrod City

**ROM anchors**

- `maps/GoldenrodCity.asm`
- `maps/GoldenrodGym.asm`
- `maps/GoldenrodBikeShop.asm`
- `maps/GoldenrodFlowerShop.asm`
- `maps/GoldenrodNameRater.asm`
- `maps/GoldenrodHappinessRater.asm`
- `maps/GoldenrodDeptStore*.asm`
- `maps/GoldenrodGameCorner*.asm`
- `maps/GoldenrodPokecenter1F.asm`
- Attached areas: `GoldenrodUnderground*`, Radio Tower maps, Magnet Train Station

**Content**

- Biggest Johto services hub
- Gym, bike shop, flower shop, happiness rater, name rater
- Department Store, Game Corner, Radio Tower, underground, Magnet Train station

**Key ROM events**

- Flypoint callback
- Whitney gym and SquirtBottle access via Flower Shop
- Radio expansion flavor
- Rocket takeover later
- Move Tutor callback state

**Dependencies**

- Complex service screens
- Department store multi-floor navigation
- Rocket occupation state
- City callback/object state changes

**Done when**

- Whitney unlock path, SquirtBottle, and later Radio Tower occupation all work

### Ecruteak City

**ROM anchors**

- `maps/EcruteakCity.asm`
- `maps/EcruteakTinTowerEntrance.asm`
- `maps/EcruteakPokecenter1F.asm`
- `maps/EcruteakLugiaSpeechHouse.asm`
- `maps/EcruteakMart.asm`
- `maps/EcruteakGym.asm`
- `maps/EcruteakItemfinderHouse.asm`
- Attached landmarks: `maps/BurnedTower*.asm`, `maps/TinTower*.asm`

**Content**

- Ghost/legend lore hub
- Gym, mart, PokéCenter, lore houses, tower entrance
- Burned Tower and Tin Tower progression

**Key ROM events**

- Flypoint callback
- Morty gym unlock path
- Burned Tower rival/Eusine/Suicune chain
- Tower legend exposition

**Dependencies**

- Complex scripted legend scenes
- Multi-floor towers
- Rival + Eusine story state

**Done when**

- Morty path and Burned Tower legend chain are faithful

### Olivine City

**ROM anchors**

- `maps/OlivineCity.asm`
- `maps/OlivineGym.asm`
- `maps/OlivineMart.asm`
- `maps/OlivinePokecenter1F.asm`
- `maps/OlivineCafe.asm`
- `maps/OlivineGoodRodHouse.asm`
- Attached landmarks: `maps/OlivineLighthouse*.asm`, `maps/OlivinePort*.asm`

**Content**

- West-coast city hub
- Gym, mart, PokéCenter, café, Good Rod house
- Lighthouse stack and port

**Key ROM events**

- Flypoint callback
- Rival encounter scene
- Lighthouse / Amphy medicine quest start
- Port and later ship access

**Dependencies**

- Coord-event rival scene
- Multi-floor lighthouse
- Quest chain that reaches Cianwood and returns

**Done when**

- Jasmine medicine quest path works end-to-end

### Cianwood City

**ROM anchors**

- `maps/CianwoodCity.asm`
- `maps/CianwoodGym.asm`
- `maps/CianwoodPokecenter1F.asm`
- `maps/CianwoodPharmacy.asm`
- `maps/CianwoodPhotoStudio.asm`
- `maps/CianwoodLugiaSpeechHouse.asm`
- `maps/PokeSeersHouse.asm`

**Content**

- Island city hub
- Gym, PokéCenter, pharmacy, seer, photo studio, lore house
- Sea route reward point

**Key ROM events**

- Suicune and Eusine scene
- Eusine battle
- HM Fly reward
- Pharmacy medicine for Olivine quest

**Dependencies**

- Legend cutscene support
- Trainer battle with named trainer state
- HM reward flow

**Done when**

- Chuck gym clear, Fly reward, Eusine scene, and medicine return loop all work

### Mahogany Town

**ROM anchors**

- `maps/MahoganyTown.asm`
- `maps/MahoganyGym.asm`
- `maps/MahoganyPokecenter1F.asm`
- `maps/MahoganyMart1F.asm`
- `maps/MahoganyRedGyaradosSpeechHouse.asm`
- Attached landmarks: `Route43*`, `LakeOfRage*`, Rocket Hideout under the mart

**Content**

- Small town with hidden Rocket base
- Gym, PokéCenter, suspicious mart, Red Gyarados speech house

**Key ROM events**

- RageCandyBar roadblock scene
- Red Gyarados / Lake of Rage lead-in
- Rocket Hideout reveal and cleanup
- Pryce gym

**Dependencies**

- Coord-event roadblock
- Hidden-base reveal
- Team Rocket mid-game quest state

**Done when**

- Lake of Rage -> Rocket Hideout -> Pryce sequence works faithfully

### Blackthorn City

**ROM anchors**

- `maps/BlackthornCity.asm`
- `maps/BlackthornGym1F.asm`
- `maps/BlackthornGym2F.asm`
- `maps/BlackthornMart.asm`
- `maps/BlackthornPokecenter1F.asm`
- `maps/BlackthornDragonSpeechHouse.asm`
- `maps/BlackthornEmysHouse.asm`
- `maps/MoveDeletersHouse.asm`
- Attached landmarks: `maps/DragonsDen*.asm`, `DarkCaveBlackthornEntrance`, Ice Path exit

**Content**

- Final Johto city
- Two-floor gym, PokéCenter, mart, Move Deleter, lore houses
- Dragon's Den access

**Key ROM events**

- Flypoint callback
- Santos weekday callback and Spell Tag gift
- Clair gym challenge
- Dragon's Den test and Rising Badge resolution

**Dependencies**

- Weekday/time gating
- Multi-floor gym puzzle
- Post-gym test scene in separate landmark

**Done when**

- Clair -> Dragon's Den -> badge resolution path is faithful

---

## Kanto Cities

These cities open after the Indigo Plateau transition. Their specs can be
implemented later, but the content categories are still defined now so the
postgame does not become ad-hoc.

### Pallet Town

**ROM anchors**

- `maps/PalletTown.asm`
- `maps/RedsHouse1F.asm`
- `maps/RedsHouse2F.asm`
- `maps/BluesHouse.asm`
- `maps/OaksLab.asm`

**Content**

- Postgame anchor town
- Oak's Lab, Red's house, Blue's house

**Key ROM events**

- Flypoint callback
- Kanto starting anchor and Oak lab services

**Dependencies**

- Mostly simple interiors and Oak lab systems

### Viridian City

**ROM anchors**

- `maps/ViridianCity.asm`
- `maps/ViridianGym.asm`
- `maps/ViridianMart.asm`
- `maps/ViridianPokecenter1F.asm`
- `maps/ViridianNicknameSpeechHouse.asm`

**Content**

- Blue's gym city
- Mart, PokéCenter, gym, nickname house

**Key ROM events**

- Flypoint callback
- Dream Eater gift
- Final Kanto gym availability

**Dependencies**

- Gym unlock after Cinnabar/Blue state

### Pewter City

**ROM anchors**

- `maps/PewterCity.asm`
- `maps/PewterGym.asm`
- `maps/PewterMart.asm`
- `maps/PewterPokecenter1F.asm`
- `maps/PewterNidoranSpeechHouse.asm`
- `maps/PewterSnoozeSpeechHouse.asm`

**Content**

- Brock gym city
- Mart, PokéCenter, two speech houses

**Key ROM events**

- Flypoint callback
- Silver Wing gift

**Dependencies**

- One-shot gift flow

### Cerulean City

**ROM anchors**

- `maps/CeruleanCity.asm`
- `maps/CeruleanGym.asm`
- `maps/CeruleanMart.asm`
- `maps/CeruleanPokecenter1F.asm`
- `maps/CeruleanPoliceStation.asm`
- `maps/CeruleanGymBadgeSpeechHouse.asm`
- `maps/CeruleanTradeSpeechHouse.asm`

**Content**

- Misty gym city
- Mart, PokéCenter, police station, two speech houses

**Key ROM events**

- Flypoint callback
- Gym access with Kanto postgame quest state

**Dependencies**

- Kanto quest-state integration

### Vermilion City

**ROM anchors**

- `maps/VermilionCity.asm`
- `maps/VermilionGym.asm`
- `maps/VermilionMart.asm`
- `maps/VermilionPokecenter1F.asm`
- `maps/VermilionFishingSpeechHouse.asm`
- `maps/VermilionMagnetTrainSpeechHouse.asm`
- `maps/VermilionDiglettsCaveSpeechHouse.asm`
- `maps/VermilionPort*.asm`

**Content**

- Port and Magnet Train city
- Gym, mart, PokéCenter, port, rail access

**Key ROM events**

- Flypoint callback
- Snorlax battle
- HP Up gift

**Dependencies**

- Static encounter battle
- Rail/port travel systems

### Lavender Town

**ROM anchors**

- `maps/LavenderTown.asm`
- `maps/LavenderMart.asm`
- `maps/LavenderPokecenter1F.asm`
- `maps/LavenderSpeechHouse.asm`
- `maps/LavenderNameRater.asm`

**Content**

- Radio tower town
- Mart, PokéCenter, speech house, name rater

**Key ROM events**

- Flypoint callback
- Kanto radio exposition

**Dependencies**

- Radio system for full fidelity

### Celadon City

**ROM anchors**

- `maps/CeladonCity.asm`
- `maps/CeladonGym.asm`
- `maps/CeladonDeptStore*.asm`
- `maps/CeladonGameCorner*.asm`
- `maps/CeladonMansion*.asm`
- `maps/CeladonCafe.asm`
- `maps/CeladonPokecenter1F.asm`

**Content**

- Large commerce city
- Gym, Department Store, Game Corner, Mansion, Café, PokéCenter

**Key ROM events**

- Flypoint callback
- Erika gym
- High-density service content

**Dependencies**

- Multi-floor building support
- Prize/game systems if full parity is desired

### Saffron City

**ROM anchors**

- `maps/SaffronCity.asm`
- `maps/SaffronGym.asm`
- `maps/SaffronMart.asm`
- `maps/SaffronPokecenter1F.asm`
- `maps/SaffronMagnetTrainStation.asm`
- `maps/MrPsychicsHouse.asm`
- `maps/SilphCo1F.asm`

**Content**

- Sabrina city
- Gym, mart, PokéCenter, Magnet Train station, Mr. Psychic, Silph

**Key ROM events**

- Flypoint callback
- Magnet Train and Kanto city hub state

**Dependencies**

- Train travel system
- Gift / optional side services

### Fuchsia City

**ROM anchors**

- `maps/FuchsiaCity.asm`
- `maps/FuchsiaGym.asm`
- `maps/FuchsiaMart.asm`
- `maps/FuchsiaPokecenter1F.asm`
- `maps/BillsOlderSistersHouse.asm`
- `maps/SafariZoneFuchsiaGateBeta.asm`

**Content**

- Janine gym city
- Mart, PokéCenter, gym, Safari Zone gate remnant

**Key ROM events**

- Flypoint callback
- Janine gym

**Dependencies**

- Mostly gym + city services

### Cinnabar Island

**ROM anchors**

- `maps/CinnabarIsland.asm`
- `maps/CinnabarPokecenter1F.asm`
- Linked gym landmark: `maps/SeafoamGym.asm`

**Content**

- Ruined island hub
- PokéCenter and Seafoam redirect

**Key ROM events**

- Flypoint callback
- Blue/Viridian gym availability state

**Dependencies**

- Post-disaster city presentation
- Kanto quest-state callback

---

## Recommended implementation slices

Use these SDD slices rather than porting "one random building":

1. `Violet City + Sprout Tower + Route 32 gate`
2. `Azalea Town + Slowpoke Well + Kurt loop`
3. `Goldenrod City services + Whitney + SquirtBottle`
4. `Ecruteak City + Burned Tower + Morty`
5. `Olivine City + Lighthouse`
6. `Cianwood City + Chuck + Eusine/Suicune scene`
7. `Mahogany Town + Lake of Rage + Rocket Hideout`
8. `Blackthorn City + Clair + Dragon's Den`
9. `Kanto city hubs in badge order`

Each slice should spawn its own implementation plan under
`docs/superpowers/plans/` and reference this file as the city-content
baseline.

## Current extracted coverage snapshot

As of 2026-08-11, the Crystal port has meaningful early coverage for:

- New Bark Town and its intro interiors
- Route 29 / Route 29 Route 46 Gate
- Cherrygrove City and its currently registered interiors
- Route 30 and Route 30 Berry House
- Route 31 and Route 31 Violet Gate

Everything from Violet City onward should treat this document as the
content contract and the per-slice plan as the execution document.
