# Gen2 Crystal Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sequence the remaining work to take Pokémon Crystal from "opening plays, one route half-built" to a fully playable port on gen1recomp's existing Gen1 engine, without losing track of scope the way ad-hoc map-by-map requests already have once this session.

**Architecture:** Unchanged from what six prior slices (2026-08-03 through 2026-08-05, see `docs/superpowers/plans/`) and this session already established: `tools/make_rom_manifest_crystal.py` reads `roms/pokecrystal` (a real pret/pokecrystal checkout) and a built `.sym` to produce `tools/rom_manifest_crystal.json`; `src/import/RomExtractorGen2.lua` reads real ROM bytes at runtime through that manifest into `data/generated/*.lua` + `assets/generated/**`; hand-ported behavior that can't be extracted mechanically (NPC dialogue, coord_event-shaped triggers, story flags) lives in `data/scripts/crystal_*.lua`, registered from `data/scripts/init.lua` under `GameVersion.isCrystal()`. Every new map/system in this roadmap is another pass through that same pipeline, not a new architecture.

**Tech Stack:** Lua 5.1/LuaJIT (engine + tests), Python 3 + Pillow (manifest generation, `tools/extract_gen2/`), LÖVE 11.x (runtime), pytest (Python-side tests), the project's own `tests/harness.lua` (Lua-side tests via `scripts/test.sh`).

## Global Constraints

- Never commit ROM bytes; the manifest and generated caches carry only metadata/derived assets (established project rule, `AGENT_HANDOFF.md`).
- Keep the Gen1 (Red/Blue/Yellow) pipeline byte-identical in behavior; every shared-file change (this session touched `src/world/Map.lua`, `src/pokemon/Sprites.lua`, `src/battle/BattleState.lua`) must run the **full** `scripts/test.sh` (not `--quick`) before being considered done, and stay backward-compatible for Gen1's data shapes (number, not table, for `grassTile`; `GameVersion.isCrystal()` gates, not version-blind changes).
- Every map/manifest change must be verified by regenerating `tools/rom_manifest_crystal.json` from the real `roms/pokecrystal` checkout and diffing against the committed version — an unexplained diff means something else drifted.
- Any behavior this project adds that the real ROM does not have (this session already added one: the New Bark Town "no POKéMON, go see PROF.ELM" route guard) must be recorded in `docs/new-features.md`, not silently shipped as if it were ROM-faithful.
- Simplifications forced by a missing subsystem (no time-of-day script command, no day-of-week, no clock) get a one-line comment at the simplification site citing the ROM label that was trimmed and why — this session's `data/scripts/crystal_*.lua` files are the reference style.
- New sprites/tilesets always get matte-transparency (`ImageWriter.matteColor0`) applied, and any pret rip under `gfx/**/*.png` gets checked for a multi-frame animation sheet (width×height being a multiple of width×width) before being copied wholesale — two real bugs this session both came from skipping that check.

---

## Roadmap Overview

| # | Milestone | Size | Status |
| - | --------- | ---- | ------ |
| 0 | Close out this session's open bugs | Small | **Next** |
| 1 | New Bark Town loop closure (Route 29 → Route 46 Gate, Cherrygrove City, Mr. Pokémon errand) | Medium | Planned below |
| 2 | Gen2 battle mechanics: Special split (Sp.Atk/Sp.Def), held items | Large | Sequenced, own plan later |
| 3 | Gen2 world/UI systems: day/night wild encounters, Pokégear radio/map, multi-pocket bag UI, breeding/Day Care | Large | Sequenced, own plan later |
| 4 | Early-game music (New Bark Town, Route 29, Cherrygrove, wild battle theme) | Medium | Sequenced, own plan later |
| 5 | Violet City + Sprout Tower + Falkner (first gym) | Large | Sequenced, own plan later |
| 6 | Azalea Town → Goldenrod City (gyms 2-3, Slowpoke Well, Team Rocket intro) | Large | Sequenced, own plan later |
| 7 | Ecruteak → Blackthorn (gyms 4-8, Team Rocket HQ, legendary beasts) | Very large | Sequenced, own plan later |
| 8 | Elite Four + Hall of Fame + credits | Medium | Sequenced, own plan later |
| 9 | Kanto revisit (post-game, gyms 9-16, Red at Mt. Silver) | Very large | Sequenced, own plan later |

Milestones 2-3 were originally sequenced after the first few cities (build the system where the ROM first exercises it), but were moved directly after Milestone 1 on the explicit call that Crystal must play by Gen2's own battle/world rules rather than Gen1's rules with a Crystal skin — see the mid-session architecture discussion this plan's Self-Review section references. Battle-math-affecting mechanics (Milestone 2: the Special split changes every damage calculation from turn one; held items are core to Gen2 battles) come before world/UI systems (Milestone 3) that don't change whether a battle is computed correctly.

Only Milestones 0 and 1 are broken into executable tasks below — writing full task-level detail for Milestone 2 onward now would mean inventing engine/ROM structure this session never actually read, which is exactly the placeholder problem this plan format forbids. Each milestone gets its own `docs/superpowers/plans/YYYY-MM-DD-gen2-crystal-<slice>.md` (and matching spec under `docs/superpowers/specs/`) written with the writing-plans skill once the milestone before it is done, the same way the six existing Crystal plans were each scoped to one slice.

---

## Milestone 0: Close out this session's open bugs

Three items are still open from this session with a concrete lead each; a fourth (battle background) has a fix already applied that needs confirmation.

### Task 1: Confirm the battle-back-sprite scale fix resolved the giant/checkered battle screen

**Files:**
- Already modified: `src/battle/BattleState.lua` (`BATTLE_SCALE_DEFAULT_CRYSTAL`, `resolveBattleScale`)
- No new files for this task — it is a verification task, not a code task.

**Interfaces:**
- Consumes: `BattleState.resolveBattleScale(data, side, path, species)`, already returning `1` for Crystal's `"back"` side (unit-tested this session: Gen1 back=2, Crystal back=1, Crystal front=1, species override still wins).
- Produces: a yes/no answer that gates whether Task 2 (below) is needed at all.

- [ ] **Step 1: Get a fresh Crystal build running**

```bash
cd /Users/andreaugustozaguettefernandes/repos/gen1recomp
LUA=luajit scripts/test.sh 2>&1 | tail -20
```
Expected: `ALL TIERS PASSED` (this only proves the fix didn't regress anything testable headlessly — the visual confirmation needs a real LÖVE run).

- [ ] **Step 2: Trigger a real wild encounter**

Launch `love .`, import the Crystal ROM if the cache is stale, walk into Route 29's grass until a wild battle starts (SENTRET is the common encounter there per this session's testing).

- [ ] **Step 3: Compare against the expected shape**

Expected: the player's back sprite and the enemy's front sprite are each a single, correctly-proportioned Pokémon/trainer image — no giant tiled/checkered pattern filling the screen, no sprite larger than roughly a third of the 160x144 battle area.

- [ ] **Step 4: If still broken, open a systematic-debugging pass**

If the checkered pattern persists, the 2x-scale theory was incomplete — invoke `superpowers:systematic-debugging` fresh rather than re-guessing; do not fold more speculative fixes into this plan. Re-read `src/battle/BattleState.lua`'s `colorMode()` path (line ~4843) and `drawPicsLayer` (line ~5110) with a debug print of `self:colorMode()`'s actual return value and `s`/`eff` in a live session, since this session's investigation never got a definitive "yes, this canvas render is graphically confirmed correct" checkpoint from inside a running LÖVE process.

- [ ] **Step 5: Commit (only if Step 4 wasn't needed, or once its follow-up fix is verified too)**

```bash
git add src/battle/BattleState.lua
git commit -m "$(cat <<'EOF'
fix: Crystal battle back sprites no longer double-scaled

Gen1's own back pics (redb.png etc.) are stored at literal half
resolution and need the 2x default to look right; Crystal's pret rips
(chris_back.png, kris_back.png, every Pokemon's own back.png) are
already full resolution, so the same default drew them roughly 4x
larger than intended. BATTLE_SCALE_DEFAULT is now version-gated.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

### Task 2: Root-cause the missing bed in PLAYERS_HOUSE_2F

**Files:**
- Investigate: `src/import/RomExtractorGen2.lua` (`extractMap`, `extractTileset`)
- Investigate: `src/world/MapLoader.lua`, `src/render/TileRenderer.lua` (whichever actually draws a loaded map's blocks — not yet confirmed which)
- Likely fix location: one of the two above, TBD by the investigation itself (this is why this task is scoped as diagnosis-first, per this session's own finding that the raw ROM source data is correct)

**Interfaces:**
- Consumes: `tools/rom_manifest_crystal.json`'s `maps.PLAYERS_HOUSE_2F` entry (width=4, height=3 blocks, `.blk` grid `[[4,1,3,2],[5,6,5,5],[5,5,7,5]]` — block `7` at grid row 2, col 2 is the bed, confirmed by rendering `data/tilesets/players_room_metatiles.bin` block 7 directly against `gfx/tilesets/players_room.png` this session).
- Produces: either a fixed `extractMap`/`extractTileset`/renderer, or a confirmed non-finding that reopens the investigation with a different hypothesis.

- [ ] **Step 1: Reproduce the exact block/tile math gen1recomp's own extractor would compute**

```bash
cd /Users/andreaugustozaguettefernandes/repos/gen1recomp
source .venv/bin/activate
python3 -c "
with open('roms/pokecrystal/maps/PlayersHouse2F.blk','rb') as f:
    data = f.read()
width = 4
for y in range(len(data)//width):
    print(y, list(data[y*width:(y+1)*width]))
"
```
Expected: `0 [4, 1, 3, 2]`, `1 [5, 6, 5, 5]`, `2 [5, 5, 7, 5]` (already confirmed this session — this step is the baseline the next steps compare against).

- [ ] **Step 2: Confirm the manifest's committed map data matches**

```bash
python3 -c "
import json
d = json.load(open('tools/rom_manifest_crystal.json'))
m = d['maps']['PLAYERS_HOUSE_2F']
print('width', m['width'], 'height', m['height'])
print('blocks', m.get('blocks'))
"
```
Expected: if `blocks` is present in the manifest and matches `[4,1,3,2,5,6,5,5,5,5,7,5]`, the bug is NOT in the Python manifest generator — move to Step 3. If `blocks` is absent from the manifest entirely (this session found `RomExtractorGen2:extractMap()` reads block bytes directly from ROM at runtime, not from the manifest), skip to Step 3 directly.

- [ ] **Step 3: Add a temporary debug print in the real extractor and run a real import**

In `src/import/RomExtractorGen2.lua`'s `extractMap()`, temporarily add after the `blocks` read for `PLAYERS_HOUSE_2F`:
```lua
if mapId == "PLAYERS_HOUSE_2F" then
  print("PLAYERS_HOUSE_2F blocks:", table.concat(blocks, ","))
end
```
Run a real Crystal ROM import (`love .`, reimport), read the console output, compare against Step 1's `[4,1,3,2,5,6,5,5,5,5,7,5]`. Remove the debug print once the comparison is made, regardless of outcome (this project treats stray debug prints as script noise that fails CI, per `tests/engine/gate_*` conventions already in the test suite).

- [ ] **Step 4a (if Step 3 matches): the bug is in rendering, not extraction**

Find where `TILESET_PLAYERS_ROOM`'s blocks get drawn (grep `src/render` and `src/world` for `blocks\[` and `tileset.blocks`), and check whether block `7`'s four tiles (`meta[7*16:(7+1)*16]` = the bed's tile IDs, re-derived directly from `players_room_metatiles.bin` and verified in `tests/engine/gen2_players_house_2f.lua` as `[16, 17, 17, 18, 32, 33, 33, 34, 48, 49, 49, 50, 1, 1, 1, 1]` — the earlier session's cited numbers above were wrong; every real tile ID here is < 96, consistent with this tileset's 96-tile bank) are being looked up against the CORRECT tileset image (`assets/generated/tilesets/players_room.png`) at the map-render call site, not a stale/wrong tileset reference left over from whichever map the player was on before entering PLAYERS_HOUSE_2F.

- [ ] **Step 4b (if Step 3 does not match): the bug is in extraction**

Check `TilesetPlayersRoomMeta`'s bank/address resolution (`self:symbol("TilesetPlayersRoomMeta")`) and the byte count read (`self.rom:bytes(meta.bank, meta.address, 2048)`) against the `.sym` file directly:
```bash
grep -i "PlayersRoomMeta\|PlayersHouse2F" roms/pokecrystal/pokecrystal.sym
```
A wrong bank/address here would misread every block for this tileset, not just the bed specifically — if other furniture (the console/shelves at blocks 4,1,3,2) render correctly in-game already, this branch is unlikely, but confirm rather than assume.

- [ ] **Step 5: Apply the fix found in Step 4a or 4b, write a targeted regression check**

Once the actual cause is known, add a check to `tests/engine/gen2_crystal_intro.lua` or a new small `tests/engine/gen2_players_house_2f.lua` (following the existing `tests/engine/gen2_*.lua` naming) asserting the specific thing that was wrong (e.g., "block 7's tile IDs resolve against `TILESET_PLAYERS_ROOM`'s image, not the previous map's").

- [ ] **Step 6: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
```
Expected: `ALL TIERS PASSED`. Then commit with a message naming the actual root cause found in Step 4.

### Task 3: Root-cause the missing "R" row on the naming screen

**Files:**
- Investigate: `src/import/RomExtractorGen2.lua` (`extractFont`, `self.manifest.fontCharmap`)
- Investigate: `tools/make_rom_manifest_crystal.py` (`parse_charmap`, wherever `fontCharmap` gets built)
- Investigate: `src/ui/NamingScreen.lua` (already modified this repo cycle per `git status` at session start — check whether Crystal's naming screen reuses Gen1's letter-grid layout assumptions)

**Interfaces:**
- Consumes: `data/generated/font.lua`'s `charmap` field, `assets/generated/fonts/font.png`/`font_extra.png`.
- Produces: either a corrected charmap/font extraction, or a corrected `NamingScreen.lua` grid-to-glyph mapping.

- [ ] **Step 1: Decode the real Crystal font tile sheet directly from ROM source, independent of the extractor**

Crystal's font is at symbol `Font` (128 tiles, 128x64px, 1bpp, codes $80-$FF per `RomExtractorGen2.lua`'s own doc comment on `extractFont`). Confirm which glyph indices Gen1's naming-screen letter grid expects for the R-row specifically:
```bash
grep -n "NAME_.*_ROW\|letterGrid\|ROW.*R\b" src/ui/NamingScreen.lua | head -20
```

- [ ] **Step 2: Compare against Crystal's real charmap**

```bash
grep -n "\"R\"\|'R'" roms/pokecrystal/constants/charmap.asm
```
Expected: find the exact byte value Crystal's ROM uses for uppercase R, and confirm it falls inside the `$80-$FF` range `extractFont` assumes, at the position the 1bpp `128x64` sheet (16 glyphs per row per `RomExtractorGen2.lua`'s `glyphsPerRow = 16` field) would place it.

- [ ] **Step 3: Check whether the gap is in the extracted charmap or in NamingScreen's own row layout**

If Crystal's charmap byte for "R" doesn't land where `NamingScreen.lua`'s row-grid expects a Gen1-shaped charmap to put it (Gen1 and Gen2 do not necessarily share identical glyph ordering — this needs the direct ROM comparison from Step 2, not an assumption), the fix is either a charmap remap table in `extractFont`, or a Crystal-specific row layout in `NamingScreen.lua` gated on `GameVersion.isCrystal()` (matching the version-gate pattern already used throughout this session, e.g. `BattleState.BATTLE_SCALE_DEFAULT_CRYSTAL`).

- [ ] **Step 4: Apply the fix, add a regression check**

Add an assertion to whatever `tests/engine/gen2_*.lua` covers font/charmap already (check for one first with `grep -rl "fontCharmap\|charmap" tests/engine/`), or create `tests/engine/gen2_naming_screen_font.lua` asserting every letter A-Z (and whatever the naming screen's other rows are — lowercase, symbols) resolves to a non-nil glyph.

- [ ] **Step 5: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
```
Expected: `ALL TIERS PASSED`. Commit with the specific root cause named (charmap gap vs. row-layout mismatch — whichever Step 3 found).

---

## Milestone 1: New Bark Town loop closure

Closes the loop this session left open: Route 29's gate to Route 46 currently silently no-ops (this session's own `RomExtractorGen2.lua` fix logs a warning and skips it rather than crashing), and the story's very next beat — Mr. Pokémon's errand, which is what actually reveals `EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON`, hides the New Bark Town rival, and unlocks Route 29's catch tutorial — has no map at all yet.

### Task 4: Register Route29Route46Gate as a minimal map

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py` (`MAP_SPECS`, `REQUIRED_SYMBOLS`, `START_MAP_CONTENT`)
- Modify: `tools/rom_manifest_crystal.json` (regenerated, not hand-edited)
- Create: `data/scripts/crystal_route29_route46_gate.lua`
- Modify: `data/scripts/init.lua` (register the new map's talk table)

**Interfaces:**
- Consumes: the exact pattern `ROUTE_29`'s own registration used this session (`MAP_SPECS["ROUTE_29"]`, `REQUIRED_SYMBOLS` needing `Route29_MapAttributes`/`Route29_MapEvents`, `START_MAP_CONTENT["ROUTE_29"]`'s sign/object list shape).
- Produces: a map the Route 29 → north warp can resolve, removing the `Logger.warn("%s: skipping warp to unregistered map %d:%d", ...)` this session's `RomExtractorGen2.lua` fix currently logs for it.

- [ ] **Step 1: Read the real map source**

```bash
cat roms/pokecrystal/maps/Route29Route46Gate.asm
grep -n "map_const ROUTE_29_ROUTE_46_GATE" roms/pokecrystal/constants/map_constants.asm
grep -n "Route29Route46Gate" roms/pokecrystal/data/maps/attributes.asm
```
This session already read the first ~20 lines: two NPCs (`ROUTE29ROUTE46GATE_OFFICER`, `ROUTE29ROUTE46GATE_YOUNGSTER`), both simple `jumptextfaceplayer` scripts, tileset id `$00` (shared with `FightingDojo`/`SaffronGym`/`SaffronMart` per the attributes.asm dump this session captured — none of those are registered either, so this needs its own tileset entry, not a reused `TILESET_*` constant; confirm the real tileset name via the `.asm`'s own `TilesetXGFX`/`Meta`/`Coll` symbol names, the same way `TILESET_LAB`/`TILESET_HOUSE` were identified for earlier maps).

- [ ] **Step 2: Add the map + tileset to MAP_SPECS and REQUIRED_SYMBOLS**

Follow `tools/make_rom_manifest_crystal.py`'s existing `"ROUTE_29"` entry as the template. Add `Route29Route46Gate_MapAttributes` and `Route29Route46Gate_MapEvents` to `REQUIRED_SYMBOLS` (this session's Route 29 work hit exactly this omission as a real crash — `error: required symbol is missing: Route29_MapAttributes` — do not repeat it here).

- [ ] **Step 3: Add sign/object content**

Read `Route29Route46GateOfficerText`/`Route29Route46GateYoungsterText` from the `.asm` file (both simple `jumptextfaceplayer`, no branching, matching this session's `TEXT_ROUTE29_YOUNGSTER`/`TEXT_ROUTE29_TEACHER1` style exactly) and add both objects to `START_MAP_CONTENT["ROUTE_29_ROUTE_46_GATE"]`.

- [ ] **Step 4: Regenerate and diff the manifest**

```bash
source .venv/bin/activate
python3 tools/make_rom_manifest_crystal.py --pokecrystal roms/pokecrystal --symbols roms/pokecrystal/pokecrystal.sym --out /tmp/manifest_gate.json
diff tools/rom_manifest_crystal.json /tmp/manifest_gate.json
```
Expected: only the new map's entry and the two new `REQUIRED_SYMBOLS` additions appear in the diff — nothing about any already-registered map changes.

- [ ] **Step 5: Apply, write the talk script, register it**

```bash
cp /tmp/manifest_gate.json tools/rom_manifest_crystal.json
```
Write `data/scripts/crystal_route29_route46_gate.lua` with `TEXT_ROUTE29ROUTE46GATE_OFFICER`/`TEXT_ROUTE29ROUTE46GATE_YOUNGSTER` talk entries (real text from Step 1), and add `MapScripts.attachBase("ROUTE_29_ROUTE_46_GATE", require("data.scripts.crystal_route29_route46_gate"))` to `data/scripts/init.lua`'s `GameVersion.isCrystal()` block.

- [ ] **Step 6: Validate the warp no longer gets skipped**

In `src/import/RomExtractorGen2.lua`'s `extractMap()`, the warp-skip `Logger.warn` this session added should no longer fire for Route 29's warp once `ROUTE_29_ROUTE_46_GATE` resolves through `mapLookup`. Confirm with the same isolated-script pattern used throughout this session:
```lua
-- package.path setup, love_stub, GameVersion.set("crystal") --
local mapScripts = require("data.scripts.init")
local script = mapScripts.talkScript("ROUTE_29_ROUTE_46_GATE", "TEXT_ROUTE29ROUTE46GATE_OFFICER")
assert(script, "missing talk script")
```

- [ ] **Step 7: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json data/scripts/crystal_route29_route46_gate.lua data/scripts/init.lua src/import/RomExtractorGen2.lua
git commit -m "$(cat <<'EOF'
feat: register Route29Route46Gate, closing Route 29's north warp

Route 29's warp into this gate silently no-op'd since this session's
warp-tolerance fix (RomExtractorGen2.lua logs and skips a warp to an
unregistered map rather than crashing the whole import). Registering
the gate as a minimal two-NPC map lets the warp resolve for real.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

### Task 5: Register Cherrygrove City

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py` (`MAP_SPECS`, `REQUIRED_SYMBOLS`, `START_MAP_CONTENT`)
- Modify: `tools/rom_manifest_crystal.json` (regenerated)
- Create: `data/scripts/crystal_cherrygrove_city.lua`
- Modify: `data/scripts/init.lua`

**Interfaces:**
- Consumes: the same registration pattern as Task 4 and this session's `ROUTE_29` work.
- Produces: the map Route 29's west connection (`{"west": {"map": "CHERRYGROVE_CITY", "offset": 0}}`, already present in the committed manifest's `ROUTE_29.connections` from this session's regeneration) resolves to, and the entry point for the Mr. Pokémon errand in Task 3.

- [ ] **Step 1: Read the real map source and its scale**

```bash
cat roms/pokecrystal/maps/CherrygroveCity.asm | head -80
grep -n "map_const CHERRYGROVE_CITY" roms/pokecrystal/constants/map_constants.asm
grep -n "CherrygroveCity" roms/pokecrystal/data/maps/attributes.asm
```
Cherrygrove is a full town (multiple buildings, a Poké Mart-equivalent, an old man who teaches the run-toggle, a Pokémon Center-equivalent healing point) — expect this to be noticeably larger than Route 29's object/sign count. Do not assume it fits the same "6 NPCs + 2 signs" shape; count what the `.asm` actually has via the same `def_object_events`/`def_bg_events`/`def_warp_events` grep this session used repeatedly:
```bash
grep -n "def_warp_events\|def_coord_events\|def_bg_events\|def_object_events\|^\tobject_event\|^\twarp_event\|^\tcoord_event\|^\tbg_event" roms/pokecrystal/maps/CherrygroveCity.asm
```

- [ ] **Step 2: Scope which NPCs/buildings are in-bounds for this task**

Given this session's own established scoping pattern (defer anything gated on story content not yet built — the Mystery Egg chain, day-of-week NPCs, scenes needing an unimplemented system), triage every object found in Step 1 into "port now" vs. "hidden, documented why" the same way `ROUTE_29`'s `ROUTE29_FRUIT_TREE`/`ROUTE29_TUSCANY` were handled this session. Do not silently drop anything — every object needs a `START_MAP_CONTENT` entry (hidden or not) so `objectCount` stays accurate.

- [ ] **Step 3: Register the map, connections, tileset**

Cherrygrove is an outdoor town map — check whether it shares `TILESET_JOHTO` (like New Bark Town and Route 29 both did) via its `map_attributes` tileset id, following Task 4 Step 1's grep pattern.

- [ ] **Step 4: Regenerate, diff, apply**

```bash
source .venv/bin/activate
python3 tools/make_rom_manifest_crystal.py --pokecrystal roms/pokecrystal --symbols roms/pokecrystal/pokecrystal.sym --out /tmp/manifest_cherrygrove.json
diff tools/rom_manifest_crystal.json /tmp/manifest_cherrygrove.json
cp /tmp/manifest_cherrygrove.json tools/rom_manifest_crystal.json
```
Expected: only Cherrygrove's own entry and any new `REQUIRED_SYMBOLS` in the diff.

- [ ] **Step 5: Write the talk script(s), register**

Follow this session's `data/scripts/crystal_route29.lua` structure (one file per map, `talk` table keyed by `TEXT_*` constants for objects and by ROM script label for signs). If Cherrygrove turns out to need its own `onStep`/`onEnter` hook (e.g. a coord_event-shaped "welcome to Cherrygrove" tutorial popup — check for `SCENE_CHERRYGROVECITY_MEET_RIVAL`, already referenced this session from `MrPokemonsHouse.asm`'s `setmapscene CHERRYGROVE_CITY, SCENE_CHERRYGROVECITY_MEET_RIVAL`), use the same `onStep` proximity-trigger pattern this session built for Elm and Mom rather than a coord_event mechanism this engine doesn't have.

- [ ] **Step 6: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
```
Expected: `ALL TIERS PASSED`.

### Task 6: Mr. Pokémon's House + the errand chain

This is the task that actually closes the loop: it is what sets `EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON`, hides `NEWBARKTOWN_RIVAL` (currently permanently visible in New Bark Town per this session's explicit, documented simplification in `docs/new-features.md`), reveals `ELMSLAB_OFFICER` (currently permanently hidden, also documented this session), and unlocks Route 29's catch tutorial (`SCENE_ROUTE29_CATCH_TUTORIAL`, currently unreachable per `data/scripts/crystal_route29.lua`'s own comment).

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py` (register `MrPokemonsHouse` as a map)
- Create: `data/scripts/crystal_mr_pokemons_house.lua`
- Modify: `data/scripts/crystal_new_bark_town.lua` (remove the "stays put" simplification comment and wire the real hide-on-errand-return behavior)
- Modify: `data/scripts/crystal_elms_lab.lua` (wire `ELMSLAB_OFFICER`'s reveal)
- Modify: `data/scripts/crystal_route29.lua` (unlock the catch tutorial coord_events — this needs the `onStep` proximity pattern, not a real coord_event mechanism)

**Interfaces:**
- Consumes: `roms/pokecrystal/maps/MrPokemonsHouse.asm` (already read in part this session — the errand-return script sets `EVENT_RIVAL_NEW_BARK_TOWN`, `EVENT_PLAYERS_HOUSE_1F_NEIGHBOR`, clears `EVENT_PLAYERS_NEIGHBORS_HOUSE_NEIGHBOR`, `EVENT_COP_IN_ELMS_LAB`, specialphonecalls `SPECIALCALL_ROBBED`, and branches on which starter the player chose to decide which of the two remaining Poké Balls "the rival stole").
- Produces: `EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON` set (already checked for by `ElmsLabWindow`'s hidden second branch, ported this session but permanently unreachable), the New Bark Town rival hidden, the officer visible, Route 29's catch tutorial live.

- [ ] **Step 1: Read the full errand chain**

```bash
cat roms/pokecrystal/maps/MrPokemonsHouse.asm
```
This session already read lines ~100-135 of this file (the theft/errand-return script) while investigating the officer and rival flags — re-read the whole file now, since the earlier read was scoped to answering "why is this flag set here" rather than "what does this whole map need."

- [ ] **Step 2: Register the map**

Same pattern as Tasks 4-5. Mr. Pokémon's house is a single small building (Mr. Pokémon himself, likely one or two other NPCs) — expect a size closer to `ElmsHouse` than to Cherrygrove.

- [ ] **Step 3: Wire the errand-completion script**

This is the one script in this whole milestone that sets multiple flags across multiple maps in one go — write it as a single `data/scripts/crystal_mr_pokemons_house.lua` talk entry (matching how `crystal_elms_lab.lua`'s `starterBall` already sets `EVENT_GOT_A_POKEMON_FROM_ELM` plus three other flags in one script), following `set_flag`/`clear_flag` commands already proven this session.

- [ ] **Step 4: Remove the New Bark Town rival's "stays put" simplification**

`data/scripts/crystal_new_bark_town.lua` currently has a comment: *"This project has no trigger to make him vanish yet... so for now he just stays put."* Once Task 3's errand script sets `EVENT_RIVAL_NEW_BARK_TOWN`, wire `hide_object("NEW_BARK_TOWN", "NEWBARKTOWN_RIVAL")` into that same script (the object is not `hidden` in the manifest per this session's fix — confirm `hide_object`/`show_object` still work symmetrically on an object that started visible, the same commands already proven on `ELMSLAB_POKE_BALL1/2/3` this session).

- [ ] **Step 5: Wire the officer's reveal**

`data/scripts/crystal_elms_lab.lua`'s `ELMSLAB_OFFICER` is currently `hidden: true` in the manifest with no reveal trigger (documented this session as a known gap). Add `show_object("ELMS_LAB", "ELMSLAB_OFFICER")` to Task 3's errand script, matching the ROM's `clearevent EVENT_COP_IN_ELMS_LAB` timing.

- [ ] **Step 6: Unlock Route 29's catch tutorial**

`data/scripts/crystal_route29.lua`'s `TEXT_ROUTE29_COOLTRAINER_M1` currently only reaches `CatchingTutorialBoxFullText` because `EVENT_GAVE_MYSTERY_EGG_TO_ELM` (a *later* flag than this milestone sets) gates the real tutorial branch. Re-check `CatchingTutorialDudeScript`'s exact gate (`roms/pokecrystal/maps/Route29.asm` lines ~105-137, already read this session) — if the real gate really is `EVENT_GAVE_MYSTERY_EGG_TO_ELM` rather than something this milestone's errand script sets, the catch tutorial stays out of scope for Milestone 1 and belongs in whichever future milestone hands the Mystery Egg to Elm; do not force it in early.

- [ ] **Step 7: Regenerate manifest, run full suite, commit**

```bash
source .venv/bin/activate
python3 tools/make_rom_manifest_crystal.py --pokecrystal roms/pokecrystal --symbols roms/pokecrystal/pokecrystal.sym --out /tmp/manifest_mrpokemon.json
diff tools/rom_manifest_crystal.json /tmp/manifest_mrpokemon.json
cp /tmp/manifest_mrpokemon.json tools/rom_manifest_crystal.json
LUA=luajit scripts/test.sh 2>&1 | tail -20
```
Expected: `ALL TIERS PASSED`. Update `docs/new-features.md`'s New Bark Town route-guard entry (this session's own addition) if the guard's behavior needs adjusting now that the rival can genuinely disappear — re-read it fresh rather than assuming the old wording still applies.

---

## Milestones 2-9: sequencing notes only

Each of these gets its own `docs/superpowers/plans/YYYY-MM-DD-gen2-crystal-<slice>.md`, written with this same skill, once the milestone before it is done. Notes here are the *why this order* reasoning, not task breakdowns — writing task-level detail now would mean inventing ROM structure nobody has read yet.

- **Milestone 2 (early-game music)** comes right after Milestone 1 rather than being deferred to the end, because every map from here on adds another silent room, and the title-screen transcoder work (`src/audio/CrystalMusicTranscoder.lua`, `docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md`) is the only proven reference for how much work one song takes in this codebase — worth doing while that reference is fresh, on a small map set (2-3 songs), before the map count makes the backlog feel unbounded.
- **Milestone 3 (Violet City, first gym)** is the natural next story beat after Cherrygrove/Mr. Pokémon, and is the first place this project needs a working gym-badge/gym-leader battle flow for Crystal specifically (check whether Gen1's existing gym-battle plumbing in `src/battle/` is version-generic already or Red/Blue/Yellow-specific before assuming it's reusable as-is).
- **Milestone 4 (Gen2 systems, wave 1)** is scoped to day/night + Pokégear + bag pockets specifically because Violet City onward starts featuring NPCs and encounters that check time-of-day (this session hit this gap repeatedly as a *simplification*, e.g. `crystal_route29.lua`'s Cooltrainer M2 always showing the DAY line) — worth promoting from "simplified" to "real" once enough maps depend on it that the simplification debt compounds.
- **Milestones 5-7** are the rest of the Johto gym run in ROM order; no new engine systems expected beyond what Milestones 2 and 4 already built, just more of the same map/NPC/dialogue work at Route 29 → Cherrygrove scale.
- **Milestone 6 (Gen2 systems, wave 2)** is placed after Azalea/Goldenrod specifically because Goldenrod's Day Care is the ROM's own first real breeding location — the same "build the system where the ROM first needs it" ordering as Milestone 4.
- **Milestone 8 (Elite Four)** needs Gen1's existing Elite-Four-equivalent battle flow confirmed version-generic (same open question as Milestone 3's gym flow) before it can be scoped in detail.
- **Milestone 9 (Kanto revisit)** is explicitly last: it is Crystal's own post-game, gated behind beating the Elite Four in the ROM itself, and doubles the region size again (8 more gyms). Do not pull any Kanto work earlier just because Gen1's Kanto tilesets/maps already exist in this codebase — Crystal's Kanto is a different game state (badges reset to its own set, NPC dialogue differs, Red's Mt. Silver encounter is Crystal-exclusive content), not a reuse of Gen1's own Kanto extraction.

---

## Self-Review

**Spec coverage:** the user's request was "run Crystal with all its functions working" plus "document a milestone plan" (chosen over ad-hoc continuation or story-critical-path-only). This plan covers: the four concrete asks the user made in the same turn (world map completion, per-map music, Gen2-only systems, main story) as Milestones 1-3/5/7-9 and 4/6 respectively, sequenced by ROM story order with justifications; the two open bugs from this session (Task 2/3 of Milestone 0) and the one unconfirmed fix (Task 1 of Milestone 0) are captured so they don't get lost under the new roadmap.

**Placeholder scan:** Milestone 0 and Milestone 1's tasks each have real commands, real file paths, and real ROM facts already gathered this session (block IDs, symbol names, flag names, script names) — no step says "add appropriate handling" or defers to a future task without naming what that future task is. Milestones 2-9 are deliberately NOT task-broken, and say so explicitly, rather than faking task structure over unread ROM content.

**Type consistency:** `GameVersion.isCrystal()` is the one gating pattern used throughout (Milestone 0 Task 3's font fix, Milestone 1's map registrations, the Global Constraints section) — matches this session's actual `BattleState.BATTLE_SCALE_DEFAULT_CRYSTAL` / `Sprites.playerPath`'s `opts.gender` precedent rather than inventing a new gating convention.
