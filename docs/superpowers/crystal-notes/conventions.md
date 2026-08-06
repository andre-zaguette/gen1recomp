# Conventions

Patterns confirmed across multiple Crystal maps/objects/sprites this
session — apply these by default on new territory; re-verify only if
something doesn't fit. See [[README]] for how these notes work.

## Object visibility: SET flag = hidden

`object_event`'s trailing field is an `EVENT_*` flag (`macros/scripts/
maps.asm`'s own doc comment: `\<13>: event flag: an EVENT_* constant, or
-1 to always appear`). Confirmed empirically three times this session:

- `ELMSLAB_OFFICER` / `EVENT_COP_IN_ELMS_LAB` — the flag IS in
  `InitializeEventsScript`'s force-set list (`engine/events/
  std_scripts.asm`, run once from the player's bedroom on a new game) →
  hidden from the start, only `clearevent`'d (in `MrPokemonsHouse.asm`,
  after the theft phone call) to reveal him.
- `NEWBARKTOWN_RIVAL` / `EVENT_RIVAL_NEW_BARK_TOWN` — the flag is **not**
  in that force-set list → clear by default → visible from the start,
  only `setevent`'d (same `MrPokemonsHouse.asm` script) to hide him.
- `PLAYERSNEIGHBORSHOUSE_POKEFAN_F` / `EVENT_PLAYERS_NEIGHBORS_HOUSE_
  NEIGHBOR` — IS force-set → hidden from the start (she's the same
  character as `PLAYERSHOUSE1F_POKEFAN_F`, who visits the player's house
  instead until the same errand swaps her back).

**Check `engine/events/std_scripts.asm`'s `InitializeEventsScript` for
every new object's flag before deciding its default `hidden` state** —
don't assume "has a flag" means "hidden"; the polarity depends on whether
that specific flag is force-set at boot.

In gen1recomp: a manifest object entry gets `"hidden": True` in
`tools/make_rom_manifest_crystal.py`'s `START_MAP_CONTENT`, then
`data/scripts/crystal_*.lua` calls `hide_object`/`show_object` at the
point in a script where the ROM would `setevent`/`clearevent` that flag.

## Sign "text" field = the ROM script label, not baked English

Objects and signs both route through `mapScripts.talkScript(mapId,
textConst)` (`OverworldState:showMapText`). For an object, `textConst` is
a `TEXT_*` constant already; for a sign, it used to be literal baked
English (nothing ever routed that through the talk-script system, so
every sign silently failed with "no text for..."). Fixed project-wide:
a sign's manifest `"text"` field is now its own `"script"` label (the
real ROM label, e.g. `"ElmsLabHealingMachine"`), and a `data/scripts/
crystal_*.lua` talk entry keyed by that same label supplies the content.

## Text markers: `\n` / `\v` / `\f`

`src/render/TextBox.lua`'s own doc comment: `\n` = second line (same
page, no wait), `\v` = scroll one line up (waits for input — matches
ROM's `cont` macro), `\f` = page break (waits for A, clears — matches
ROM's `para` macro). `line` → `\n`. A lone first-page `text "..."` with
no `line` after it is just that line alone, no marker needed.

## Palette groups for `START_NPC_SPRITES`

`tools/extract_gen2/palettes.py` supports exactly 8 named groups: `red`,
`blue`, `green`, `brown`, `pink`, `silver`, `tree`, `rock`. Pick the one
matching the sprite's `PAL_NPC_*` value at its most common/canonical
object_event placement (the ROM doesn't guarantee every placement of a
shared sprite uses the same `PAL_NPC_*`, and this project's model is one
palette per sprite file, not per placement — an accepted simplification).

## Pret's `gfx/**/*.png` rips: two things to check before copying wholesale

1. **Multi-frame animation sheet.** Front-sprite pics
   (`gfx/pokemon/*/front.png`) and icons (`gfx/icons/*.png`) are pret's
   own rip of every animation frame stacked vertically — always an exact
   multiple of the image's own width (e.g. cyndaquil front.png is
   40×200 = 5 frames of 40×40). Back sprites (`gfx/pokemon/*/back.png`,
   `gfx/player/*_back.png`) are single-frame already. Check
   `height % width == 0 and height > width` before deciding whether to
   crop to the top `width × width` square (this project has no
   battle-sprite animation player yet, so it always crops to frame 1 —
   bitmask `$00`, the unmodified base pose).
2. **No alpha channel.** These rips are palette-indexed or grayscale PNGs
   with a solid white background, not transparent. Always run
   `ImageWriter.matteColor0` (flood-fills white in from the four edges
   only, so an internal white detail stays opaque) before saving.

## Battle sprite scale: Gen1's back pics are half-resolution, Crystal's aren't

`BattleState.BATTLE_SCALE_DEFAULT.back = 2` exists because Gen1's own
back pics (`redb.png` etc., via `RomExtractor.lua`) are stored — and
extracted — at literal half resolution (`redb.png` is 32×32; `ScaleSpriteByTwo`
doubles it in the real ROM too). Crystal's back pics (pret's own rips)
are already full resolution. `BattleState.BATTLE_SCALE_DEFAULT_CRYSTAL`
exists specifically to override this per `GameVersion.isCrystal()` — any
new per-species or per-image battle-scale need should check this default
first rather than assuming Gen1's 2x is universal.

## Manifest generator gotchas

- `object_event`'s hour-limit fields (h1/h2) are usually `-1, -1`
  ("always"), but can be a named `MORN`/`DAY`/`NITE` constant instead of
  a number for a time-of-day-gated NPC variant. `parse_maps`'s
  `object_event` regex requires **numeric** h1/h2 and silently fails to
  match (not error) any line that isn't — the ROM-byte object count
  (`objectCount`, counted separately, unconditionally) stays correct, but
  that specific object never reaches `START_MAP_CONTENT`'s positional
  matching. Confirmed on `PLAYERS_HOUSE1F_MOM2/3/4` (their `MORN`/`DAY`/
  `NITE` variants never match; only the `-1,-1` "always" copy does).
- Every symbol a Lua-side `self:symbol(name)` call needs (a `MapAttributes`/
  `MapEvents` pair for every registered map, at minimum) must ALSO be
  listed in `tools/make_rom_manifest_crystal.py`'s `REQUIRED_SYMBOLS` —
  registering a map in `MAP_SPECS` alone is not enough; `embed_symbols`
  only copies what `REQUIRED_SYMBOLS` names. Missing this is a hard crash
  at real-ROM-import time (`error: required symbol is missing: X`), not
  something the manifest-diff step catches.
- A warp to a map that isn't registered yet used to be a hard crash
  (`assert`) during real ROM import; `RomExtractorGen2.lua`'s
  `extractMap` now logs a warning and skips that one warp instead, so
  registering a big map doesn't require registering every map it warps
  toward at the same time.
