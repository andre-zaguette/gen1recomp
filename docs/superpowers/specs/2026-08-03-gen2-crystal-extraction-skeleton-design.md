# Gen2 (Crystal) ROM Extraction Pipeline — Walking Skeleton

Status: approved for planning
Date: 2026-08-03

## Context

gen1recomp is a native LÖVE2D reimplementation of Pokemon Red/Blue/Yellow. The
engine never emulates the Game Boy or transpiles assembly: a Lua importer
validates the player's own ROM by SHA-1, decodes game data tables and
graphics out of the ROM using bundled address/name metadata (`tools/rom_manifest*.json`,
generated ahead of time from a local `pret/pokered` checkout), and writes a
private generated cache (`data/generated/*.lua`, `assets/generated/**`) that
the rest of the engine runs against. See `docs/architecture.md`.

The long-term goal is to extend this project to Pokemon Gold, Silver, and
Crystal (Gen 2, full Johto + Kanto). That goal decomposes into several
largely-independent subprojects: the ROM extraction pipeline, the extended
data model (new types, held items, breeding, the Sp.Atk/Sp.Def stat split),
Johto-scale world/encounter mechanics (day/night, fishing, rock smash,
headbutt, radio), a Gen2 battle ruleset, and GBC-specific asset/audio
support. This spec covers only the first, and only a thin end-to-end slice
of it.

`pret/pokecrystal` is the official Crystal disassembly; `pret/pokegold`
builds both Gold and Silver from one source tree (mirroring how
`pret/pokered` already builds this project's Red and Blue). Gold/Silver
support is deferred to a follow-on spec once this skeleton proves the
pattern works for Crystal; it should mostly reuse this pipeline's shape.

## Goal

Prove that the existing Gen1 import architecture (manifest generated from
disassembly source → runtime extractor reads the player's real ROM bytes by
address → generated Lua/PNG cache → engine renders it) works unchanged in
shape for a Gen2 game, by extracting the minimum needed to walk around
**New Bark Town** in Pokemon Crystal: the map itself, its tileset, and the
player overworld sprite.

This is a walking skeleton, not a feature. It deliberately does not cover
the Pokédex, moves, items, battle, audio, or any other map. Success is
proving the pipeline end-to-end on one small, real map — not coverage
breadth.

## Non-goals

- Gold and Silver support (follow-on spec; expected to mostly reuse this
  pipeline once proven).
- Any map besides New Bark Town.
- Species/move/item/Pokédex data, battle data, audio programs.
- Day/night cycle, breeding, held items, new types — none of this is needed
  to render a static town and walk in it.
- Refactoring `src/import/RomExtractor.lua` or `tools/extract/*` to share
  primitives with the new Gen2 code. If real duplication becomes obvious
  once the Crystal map/tileset/sprite formats are seen, that is a separate,
  later refactor — not part of this slice.

## Reference ROM

`Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc`, SHA-1
`f2f52230b536214ef7c9924f483392993e226cfb` (2,097,152 bytes / 128 banks).
Already present locally at `roms/`, which is gitignored — never committed.
Symbol/address metadata comes from a local build of `pret/pokecrystal`
(cloned and built with RGBDS to produce a `.sym` file), never committed
either; only the derived `tools/rom_manifest_crystal.json` (names/addresses/
enums, no ROM bytes) is committed, exactly like the existing
`tools/rom_manifest*.json` files.

## Architecture

Approach: a fully parallel Gen2 pipeline, not a shared-primitives
refactor of the Gen1 one (see "Approaches considered" below).

New files, each mirroring an existing Gen1 counterpart, scoped to only the
three assets in play:

| New file | Mirrors | Responsibility |
| --- | --- | --- |
| `tools/make_rom_manifest_crystal.py` | `tools/make_rom_manifest.py` | Parses a local `pokecrystal` checkout + built `.sym` → `tools/rom_manifest_crystal.json` |
| `tools/extract_gen2/maps.py` | `tools/extract/maps.py` | New Bark Town's map header/block/warp layout, Crystal's table format |
| `tools/extract_gen2/tilesets.py` | `tools/extract/tilesets.py` | The tileset New Bark Town uses |
| `tools/extract_gen2/sprites.py` | `tools/extract/sprites.py` | Player overworld walk sheet |
| `tools/build_rom_data_gen2.py` | `tools/build_rom_data.py` | Dev-path: manifest + real ROM → source-tree data, for inspection/verification only |
| `src/import/RomExtractorGen2.lua` | `src/import/RomExtractor.lua` | Runtime extractor: manifest + player's ROM bytes → generated cache, at first boot |
| `tests/fixture_data_gen2/` | `tests/fixture_data/` | Synthetic (non-ROM-derived) dataset in the Crystal schema shape, so CI can test without the real ROM |

Existing files, small additions:

- `src/core/GameVersion.lua`: new `crystal` entry —
  `sha1 = "f2f52230b536214ef7c9924f483392993e226cfb"`,
  `manifest = "tools/rom_manifest_crystal.json"`,
  `cachePrefix = "crystal/"`, `saveSuffix = "_crystal"` — plus a new
  `extractor` field (`"gen2"` for this entry; existing Red/Blue/Yellow
  entries implicitly `"gen1"`) so the importer can route to the right
  extractor module.
- `src/import/RomImporter.lua`: a small branch on `version.extractor` to
  call `RomExtractor` vs `RomExtractorGen2`.

Everything downstream of the generated cache — `MapLoader.lua`,
`TileRenderer.lua`, `SpriteRenderer.lua`, `Camera.lua`, and presentation
features like Tilt (the "voxel" perspective mode), Zoom, and GBC FX — reads
`data/generated/*` and needs zero Gen2-specific changes, *as long as the new
extractor emits the same schema shape the engine already consumes*. This
skeleton's real deliverable is exactly that: proving the Crystal-derived
data fits the existing schema.

### Data flow

```
local pokecrystal checkout (dev-only, not committed)
        |
        v  tools/make_rom_manifest_crystal.py
tools/rom_manifest_crystal.json  (committed)
        |
        v  RomExtractorGen2.lua, at the player's first boot
player's real Crystal ROM ------------+
        |                             |
        v                             v
   SHA-1 validation           decode New Bark Town
                               (map header, tileset, player sprite)
        |
        v
crystal/data/generated/*.lua + crystal/assets/generated/**/*.png
```

### Approaches considered

- **Chosen — parallel pipeline, no shared abstraction yet.** Zero risk to
  the working Gen1 pipeline; Gen2's table formats are different enough
  (map headers, GBC palettes, possibly different graphics compression)
  that guessing a shared abstraction now would likely be wrong. Revisit
  once real overlap is visible.
- **Rejected — extract shared Game Boy primitives first.** Cleaner long
  term, but requires touching working Gen1 extraction code before
  delivering anything new, based on assumptions about Crystal's format
  that aren't yet verified.
- **Rejected — copy-paste `RomExtractor.lua` with no convergence plan.**
  Fastest start, guaranteed long-term drift between two large files doing
  similar things.

## Testing

Mirrors the existing tiered suite (`.github/workflows/ci.yml`):

- `tests/fixture_data_gen2/` is a small, hand-built, non-ROM-derived
  dataset in the Crystal schema shape (map/tileset/sprite for a stand-in
  "New Bark Town"), analogous to `tests/fixture_data/`. CI and any
  contributor without the ROM can run structural tests against it.
- A `luajit tests/run_tests.lua`-style case loads the fixture map and
  asserts basic invariants: dimensions, at least one known walkable and
  one known blocked cell, tileset PNG present and readable.
- Real-ROM verification is manual/local only (the developer's machine has
  the actual Crystal ROM in `roms/`): run the full import, confirm New
  Bark Town renders and the player sprite walks, and spot-check the
  extracted map against the real game.

## Acceptance criteria

1. `python3 tools/make_rom_manifest_crystal.py --pokecrystal <checkout> --symbols <crystal.sym> --out tools/rom_manifest_crystal.json` runs clean.
2. Selecting Crystal in the launcher with the real ROM present passes SHA-1
   validation and generates New Bark Town's map, tileset, and player sprite
   under `crystal/data/generated/` and `crystal/assets/generated/`.
3. The game boots into New Bark Town, tiles render correctly, collision/
   walkability matches the real game, and the player sprite walks.
4. `luajit tests/run_tests.lua` passes the new fixture-backed Gen2 case
   with no ROM present.
5. Manual verification against the real ROM confirms New Bark Town matches
   the source game structurally and visually.

## Follow-on work (explicitly out of scope here)

- Gold/Silver extraction (reusing this pipeline's shape against
  `pret/pokegold`).
- Remaining Johto + Kanto maps, full Pokédex/moves/items, battle data,
  audio.
- Gen2 data model additions (types, held items, breeding, Sp.Atk/Sp.Def
  split) and the Gen2 battle ruleset.
- Day/night and the new encounter mechanics (fishing, rock smash,
  headbutt, radio).
- Any shared-primitives refactor between the Gen1 and Gen2 extractors, if
  it turns out to be warranted.
