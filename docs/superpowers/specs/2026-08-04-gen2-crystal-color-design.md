# Gen2 (Crystal) Native Color

Status: verified against real ROM, 2026-08-04
Date: 2026-08-04

## Context

The Gen2 (Crystal) walking skeleton (`2026-08-03-gen2-crystal-extraction-skeleton-design.md`) and its font follow-on (`2026-08-03-gen2-crystal-font-extraction-design.md`) got New Bark Town booting, walkable, and legible — but rendered entirely in Game Boy monochrome shading. Crystal is a native Game Boy Color game: every tile and sprite has a real, ROM-defined color, unlike Red/Blue/Yellow, which are monochrome carts this project only *optionally* colorizes through several fan-made reinterpretations (the `COLORS` option: OG RED, SGB, ADVANCED/"RED++", etc. — see `src/render/PaletteFX.lua`).

This spec extracts Crystal's real palette data from the player's own ROM and renders New Bark Town in it, automatically, with no player-facing option to turn it off — there is no "authentic monochrome Crystal" the way there's an authentic monochrome Red, so Crystal does not participate in the `COLORS` menu at all.

Crystal's colors vary by time of day (morning/day/night), a feature this project has never needed before (Gen1 has no day/night). This spec includes that clock — driven by the host system's real-world time, mirroring how a real GBC cartridge's RTC chip tracks real elapsed time — strictly as an input to *which palette is active*. It does not touch gameplay: no time-gated encounters, events, or NPC schedules. Those are explicitly separate, deferred work.

## Goal

New Bark Town renders in Crystal's real, ROM-extracted colors — ground, buildings, and the player sprite — automatically, and the active palette shifts between morning/day/night to match the host system's real-world clock, the same way it would on real hardware.

## Non-goals

- Any map besides New Bark Town (same constraint every Gen2 spec so far has kept).
- Cave/dark palettes (`PALETTE_DARK`, FLASH-gated) and indoor palettes (`wEnvironment == INDOOR`) — both real Crystal mechanics, both meaningless without a cave or interior map extracted, which none is yet. `src/render/PaletteFX.lua`'s existing `darkWorld`/FLASH mechanic (Gen1 Rock Tunnel) is a close analog for a future Crystal cave spec, not touched here.
- Any gameplay effect of time of day (encounter tables, NPC schedules, time-locked events/items). The clock built here drives palette selection only.
- A manual "set your clock" first-boot screen (real Crystal has one for its RTC chip). This project reads the host's real-world time directly instead.
- Extending the `COLORS` option or any of its existing modes (OG RED/SGB/ADVANCED/etc.) to Crystal. Crystal does not use that option; it always renders in its own real color.
- GB (monochrome-compatibility) mode for Crystal.

## Reference

Same ROM and local `pret/pokecrystal` checkout as the walking skeleton and font specs. Three additional ROM symbols, all confirmed present as real, addressable compiled data (not build-time-only PC-side assets) by reading `pokecrystal.sym` and the source directly:

- **`TilesetJohtoPalMap`** — bank `$13`, address `$40e5`, 112 bytes. Nibble-packed: each byte holds two tile IDs' BG palette group (0-7), 48 bytes for VRAM-bank-0 tile IDs, 16 bytes of `$ff` padding, 48 bytes for VRAM-bank-1 tile IDs (`gfx/tileset_palette_maps.asm`, `gfx/tilesets/johto_palette_map.asm`).
- **The `.OutdoorColors` index table** — a local label under `EnvironmentColorsPointers` in `data/maps/environment_colors.asm`; 32 bytes, `[time 0-3][group 0-7]` → an index (`$00`-`$29`) into `TilesetBGPalette` below. Exact linker-visible symbol name to be confirmed against the built `.sym` during planning (RGBDS may expose local labels under a qualified name).
- **`TilesetBGPalette`** — bank `$02`, address `$7319`, 336 bytes (42 rows × 4 colors × 2-byte RGB555 words = 42×8 bytes). The 32 rows `.OutdoorColors` actually indexes into (morn `$00-07`, day `$08-0f`, nite `$10-17`, dark `$18-1f`, water-swap exceptions at `$28-29`) are the "Outdoor" subset this spec extracts; the remaining rows (indoor, other environments) are out of scope. Read directly by the real game's `LoadMapPals` (`engine/gfx/color.asm:1197-1252`), confirming genuine runtime ROM use.
- **`MapObjectPals`** — bank `$02`, address `$7469`, 256 bytes: `[time 0-3][palette-id 0-7][color 0-3]`, RGB555 words. Chris uses palette-id 0 (`PAL_OW_RED`, `constants/sprite_data_constants.asm`). Read directly by `LoadMapPals` (`engine/gfx/color.asm:1257-1260`) into `wOBPals1`.

Crystal's own time-of-day boundaries (`engine/rtc/rtc.asm`, `constants/misc_constants.asm`): morning 4:00-9:59, day 10:00-17:59, night 18:00-3:59.

## Architecture

New file, mirroring the established Gen2 tooling pattern:

| New file | Mirrors | Responsibility |
| --- | --- | --- |
| `tools/extract_gen2/palettes.py` | `tools/extract_gen2/font.py` | Reads the four symbols above (`TilesetJohtoPalMap`, the Outdoor index table, `TilesetBGPalette`, `MapObjectPals`) via a local pokecrystal checkout during manifest generation, resolves the two-step ROM indirection (tile → group → indexed row → RGB) into a flat, already-resolved shape so the runtime extractor and engine never need to know about the index table at all — only pre-resolved `{tileGroups, groupColors[timeOfDay][group], spriteColors[timeOfDay]}`. |

Existing files, small additions:

- `tools/make_rom_manifest_crystal.py`: add the new symbol names to `REQUIRED_SYMBOLS` and a `palettes` field to the manifest, calling `palettes.py`'s resolver — same pattern as the font spec's `fontCharmap` addition.
- `src/import/RomExtractorGen2.lua`: a new `extractPalettes()` method, reading the same four ROM regions at runtime from the player's ROM bytes (mirroring `extractFont()`'s shape) and writing `crystal/data/generated/palettes.lua`.
- `src/render/PaletteFX.lua`: two additions.
  - A time-of-day reader (`os.date` against the host's real-world clock, bucketed using Crystal's own morn/day/nite boundaries above) — new capability; nothing in this engine currently reads wall-clock time (confirmed by search).
  - A resolver that, given a Crystal map's tileset and the current time bucket, looks up `Game.data.palettes` (the new extracted data) — structurally parallel to the existing Gen1 `worldGroupAt`/`worldGroupColors`/`spriteObp` functions (`PaletteFX.lua:541-692`) that already back the "ADVANCED"/RED++ per-tile rendering path, but reading Crystal's own extracted data instead of the static, offline-built `data/palettes_gbc.lua` pack, and keyed by time bucket in addition to tileset/tile.
- `src/render/TileRenderer.lua` / `src/render/SpriteRenderer.lua`: the existing per-tile-palette baked-atlas draw path (`TileRenderer.lua:412-465`'s `getGbcAtlas`, `SpriteRenderer.lua:106-158`) is currently gated on `PaletteFX.usesGbcPack()` (the player has `COLORS` set to `ADVANCED`). Add a second, independent gate — "this map has Crystal's own native color data available" — that activates the same baked-atlas mechanism unconditionally, bypassing the `COLORS` check entirely for Crystal. The atlas cache key gains the current time-of-day bucket, so a bucket change invalidates and rebuilds the baked atlas; recomputing the current bucket is cheap (a plain `os.date` call) and safe to do every time the cache is consulted, so no separate polling/timer infrastructure is needed — only the (comparatively expensive) rebake is gated behind an actual bucket change.

### Data flow

```
local pokecrystal checkout (dev-only, not committed)
        |
        v  tools/make_rom_manifest_crystal.py (+ tools/extract_gen2/palettes.py)
tools/rom_manifest_crystal.json  (committed; now also carries the resolved
                                   palettes table and the new symbol addresses)
        |
        v  RomExtractorGen2.lua, at the player's first boot
player's real Crystal ROM ------------+
        |                             |
        v                             v
   SHA-1 validation           decode New Bark Town + font + palettes
        |
        v
crystal/data/generated/palettes.lua
        |
        v  every frame the baked atlas cache is consulted
PaletteFX.lua's time-of-day reader (os.date, real-world clock)
        |
        v
TileRenderer/SpriteRenderer's existing per-tile baked-atlas path,
now Crystal-aware and unconditional
```

### Approaches considered

- **Chosen — extract Crystal's real palette data from the player's ROM, feed it through a lightly-extended version of the engine's existing per-tile-palette rendering path.** Keeps this project's core rule (the player's own ROM is the only asset source) and reuses the one piece of rendering machinery already shaped for real per-tile color, avoiding a second, parallel rendering system.
- **Rejected — mirror Gen1's "ADVANCED"/RED++ approach exactly** (an offline, curated dataset built once from a separate `pokered-gbc` disassembly project and committed directly to the repo, never touching the player's actual ROM). Would work, but Crystal's real color data is genuinely present in the player's own cartridge — routing around it to use a hand-curated substitute would be a regression in fidelity, not a shortcut.
- **Rejected — build a full in-game day/night clock (elapsed playtime, savable, settable via a first-boot clock screen) instead of reading the host's real-world time.** Closer to how some other games implement day/night, but further from how *this specific game* actually works (a real Crystal cartridge's RTC tracks real elapsed time), and adds save-state and UI surface this slice doesn't need.

## Testing

- `tools/extract_gen2/test_palettes.py`: unit tests for the two-step index resolution (tile → group → indexed row → RGB), against a small hand-built fixture mirroring the real tables' shapes — no real pokecrystal checkout needed, matching `tools/extract_gen2/test_font.py`'s precedent.
- A new fixture-backed block in `tests/run_tests.lua`'s Gen2 section: hand-built `data.palettes` proving `PaletteFX`'s Crystal-aware resolver picks the right group/color for a given tile id and time bucket, and that switching the (test-injected) time bucket changes the resolved color — no ROM, no real clock read needed for this part (the bucket is passed in directly, not read from `os.date`, so the test is deterministic).
- Real-ROM manual verification (as with every prior Gen2 spec): reimport, confirm New Bark Town renders in real color without touching the `COLORS` option, and confirm changing the host system's clock across a morn/day/nite boundary changes the rendered palette without restarting the game.

## Acceptance criteria

1. `tools/make_rom_manifest_crystal.py` runs clean and the output JSON gains a resolved `palettes` field plus the new symbol entries.
2. Reimporting Crystal generates `crystal/data/generated/palettes.lua`.
3. New Bark Town renders in real, non-grayscale color automatically — no `COLORS` menu interaction required, and Crystal is unaffected by whatever `COLORS` value is currently set.
4. Changing the host system's clock across a morn/day/nite boundary changes the rendered palette without restarting the game.
5. `luajit tests/run_tests.lua` passes the new fixture-backed Gen2 palette case with no ROM present.
6. The existing Gen1 `COLORS` modes (OG RED/SGB/ADVANCED/etc.) and full test suite show zero regressions.

## Follow-on work (explicitly out of scope here)

- Cave ("dark"/FLASH-gated) and indoor Crystal palettes, once a cave or interior map is ever extracted.
- Any gameplay effect of time of day (encounters, NPC schedules, time-locked content).
- Extending real-color rendering to Gold/Silver, once those get their own extraction pipeline.
