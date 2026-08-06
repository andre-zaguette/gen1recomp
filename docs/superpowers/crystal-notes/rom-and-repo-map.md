# Where things live

Quick pointers, not full documentation — grep from here rather than
re-discovering the file each time. See [[README]] for scope.

## In `roms/pokecrystal` (the ROM source)

| Looking for... | File |
|---|---|
| A map's connections (seamless edges) | `data/maps/attributes.asm` — NOT the per-map `.asm` |
| A map's warps/coords/signs/objects | `maps/<MapName>.asm`'s `def_warp_events` / `def_coord_events` / `def_bg_events` / `def_object_events` |
| A map's block grid | `maps/<MapName>.blk` (raw bytes, `width × height` from `map_const`) |
| A map's dimensions/group/number | `constants/map_constants.asm` (`map_const NAME, width, height`) |
| A tileset's tile-to-graphic layout | `data/tilesets/<name>_metatiles.bin` (64 blocks × 16 bytes = 4×4 tile IDs each) + `gfx/tilesets/<name>.png` (the tile atlas, 16 tiles/row) |
| A tileset's collision permissions | `data/tilesets/<name>_collision.asm`, values from `constants/collision_constants.asm` (`COLL_*`) |
| Whether an event flag is set by default on a new save | `engine/events/std_scripts.asm`'s `InitializeEventsScript` |
| Every event flag's name/index | `constants/event_flags.asm` |
| A species → menu-icon shape | `data/pokemon/menu_icons.asm` (`db ICON_X ; SPECIES`), shapes listed in `constants/icon_constants.asm`, art at `gfx/icons/<shape>.png` |
| A glyph's byte value | `constants/charmap.asm` |
| A sprite's overworld graphic | `gfx/sprites/<name>.png` (16×96 = 6 walk frames) or `gfx/player/<name>.png` |
| A sprite's battle back pic | `gfx/player/<name>_back.png` (single frame, see [[conventions]]) |
| A Pokémon's battle pics | `gfx/pokemon/<species>/front.png` (multi-frame, see [[conventions]]), `.../back.png` (single frame) |

## In this repo (the port)

| Looking for... | File |
|---|---|
| Which maps/tilesets/symbols get extracted | `tools/make_rom_manifest_crystal.py` — `MAP_SPECS` (map→label/asm/tileset), `REQUIRED_SYMBOLS` (every `self:symbol()` name the Lua side will ask for), `START_MAP_CONTENT` (per-map signs/objects, positionally matched against what the ROM regex finds) |
| The generated manifest itself | `tools/rom_manifest_crystal.json` — regenerate with `python3 tools/make_rom_manifest_crystal.py --pokecrystal roms/pokecrystal --symbols roms/pokecrystal/pokecrystal.sym --out <tmp>`, always diff before committing |
| Real-ROM-byte extraction at runtime | `src/import/RomExtractorGen2.lua` — one `extractX` method per data category (`extractMap`, `extractTileset`, `extractSprite`, `extractIcons`, `parseCrystalSpecies`, ...) |
| A specific map's NPC dialogue / signs / onEnter / onStep hooks | `data/scripts/crystal_<map_slug>.lua`, one file per map, registered in `data/scripts/init.lua` inside `if GameVersion.isCrystal() then ... end` |
| The script command vocabulary (`show_text`, `give_item`, `hide_object`, `move_player`, ...) | `src/script/Commands.lua` |
| Shared rendering code Gen1 and Gen2 both hit (version-gate here, don't fork) | `src/world/Map.lua` (`isGrassCell`), `src/pokemon/Sprites.lua` (`playerPath`), `src/battle/BattleState.lua` (`resolveBattleScale`) — each already has a `GameVersion.isCrystal()` branch or Crystal-specific default table, follow that pattern for the next one |
| Deliberate non-ROM-faithful additions | `docs/new-features.md` — every one added this session is logged there (Gen2 types in the shared type chart, the New Bark Town no-starter route guard) |
| The milestone roadmap / current task | `docs/superpowers/plans/2026-08-06-gen2-crystal-roadmap.md` |
