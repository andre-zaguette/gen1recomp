# Gen2 (Crystal) Native Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New Bark Town renders in Crystal's real, ROM-derived colors — ground, buildings, and the player sprite — automatically (no `COLORS` menu interaction), and the palette shifts between morning/day/night to match the host system's real-world clock.

**Architecture:** Resolve Crystal's palette data (tile→group map, per-time-of-day RGB, sprite RGB) entirely from readable `pret/pokecrystal` source text at manifest-build time — mirroring how `fontCharmap` is already resolved from source, not compiled ROM bytes — and embed the fully-resolved result directly in the committed `tools/rom_manifest_crystal.json`. The runtime Lua extractor just forwards it. The engine change is a single, well-factored lever: `src/render/PaletteFX.lua`'s `gbcPack()` (already the one seam all of the existing per-tile-color rendering machinery — `hasWorldTileset`/`worldGroupAt`/`worldGroupColors`/`spriteObp` — goes through for Gen1's "ADVANCED"/RED++ mode) grows a Crystal-aware branch, and `usesGbcPack()` returns true unconditionally for Crystal. Every downstream consumer (`TileRenderer`'s baked atlas, `SpriteRenderer`'s OBP bake, `OverworldController`'s whole-screen shader skip) already keys off exactly those two functions, so no other rendering code changes.

**Tech Stack:** Python 3 (manifest/tooling), Lua 5.1/LuaJIT (runtime extractor + engine), LÖVE2D.

## Global Constraints

- No ROM bytes, and no pokecrystal source *text* beyond what's already established as fair game (charmap-style structural/metadata parsing, not pixel data), are ever committed — only derived, non-copyrightable metadata. This spec's palette data is resolved once from readable pokecrystal source (RGB tables, tile-group maps) at manifest-build time and committed as decimal RGB values in `tools/rom_manifest_crystal.json`, the same category of data `fontCharmap` already sets precedent for.
- `data/generated/*` and `assets/generated/*` are gitignored, written only at import time on the player's machine.
- CI has no ROM: any new automated test must run against hand-built fixture data.
- This plan touches only Gen2 (Crystal)-specific files plus small, precisely-scoped additions to shared files (`src/render/PaletteFX.lua`, `src/core/GameVersion.lua`, `src/core/Game.lua`, `src/world/OverworldController.lua`). The existing Gen1 `COLORS` modes (OG RED/SGB/ADVANCED/etc.) and full test suite must show zero regressions.
- Crystal does not participate in the `COLORS` option. It always renders in its own real color, independent of `PaletteFX.mode`.
- No gameplay effect of time of day (no different encounters, no NPC schedules, no time-gated content) — the clock built here drives palette selection only.
- No cave/indoor Crystal palettes in this slice (no cave or interior map has been extracted yet).

---

### Task 1: `tools/extract_gen2/palettes.py` — resolve Crystal's palette data from source

**Files:**
- Create: `tools/extract_gen2/palettes.py`
- Create: `tools/extract_gen2/test_palettes.py`

**Interfaces:**
- Consumes: `tools/extract/util.py`'s existing `read_asm(path)` and `parse_number(tok)`.
- Produces: `resolve(pokecrystal)` — takes a pokecrystal checkout root path, returns:
  ```python
  {
    "tileGroups": {0: 0, 1: 5, ...},  # tile graphic id (int) -> BG palette group 0-7
    "byTime": {
      "morn": {"groupColors": [[[r,g,b],[r,g,b],[r,g,b],[r,g,b]], ...8 groups],
               "spriteColor": [[r,g,b],[r,g,b],[r,g,b],[r,g,b]]},
      "day":  {...}, "nite": {...},
    },
  }
  ```
  All RGB values already scaled 0-255. Consumed by Task 2.

- [ ] **Step 1: Write the failing test**

Create `tools/extract_gen2/test_palettes.py`:

```python
# tools/extract_gen2/test_palettes.py
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from extract_gen2 import palettes

# Trimmed stand-ins for the four real pokecrystal source files this
# resolver reads. Shapes match the real files exactly (same macro/directive
# syntax), just far fewer entries.
JOHTO_PALETTE_MAP = """
	tilepal 0, GRAY, RED, GREEN, WATER, YELLOW, BROWN, ROOF, TEXT

rept 16
	db $ff
endr

	tilepal 1, RED, GRAY, GREEN, WATER, YELLOW, BROWN, ROOF, TEXT
"""

ENVIRONMENT_COLORS = """
EnvironmentColorsPointers:
	dw .OutdoorColors ; unused
	dw .OutdoorColors ; TOWN

.OutdoorColors:
	db $00, $01, $02, $28, $04, $05, $06, $07 ; morn
	db $08, $09, $0a, $28, $0c, $0d, $0e, $0f ; day
	db $10, $11, $12, $29, $14, $15, $16, $17 ; nite
	db $18, $19, $1a, $1b, $1c, $1d, $1e, $1f ; dark

.IndoorColors:
	db $20, $21, $22, $23, $24, $25, $26, $07 ; morn
"""

# 8 named rows per time block (gray/red/green/water/yellow/brown/roof/text),
# in that fixed order, matching PAL_BG_* -- plus the two "overworld water"
# rows ($28 morn/day, $29 nite) .OutdoorColors' WATER slot points to instead
# of the plain WATER row.
BG_TILES_PAL = """
; morn
	RGB 01,01,01, 01,01,01, 01,01,01, 01,01,01 ; gray
	RGB 02,02,02, 02,02,02, 02,02,02, 02,02,02 ; red
	RGB 03,03,03, 03,03,03, 03,03,03, 03,03,03 ; green
	RGB 04,04,04, 04,04,04, 04,04,04, 04,04,04 ; water
	RGB 05,05,05, 05,05,05, 05,05,05, 05,05,05 ; yellow
	RGB 06,06,06, 06,06,06, 06,06,06, 06,06,06 ; brown
	RGB 07,07,07, 07,07,07, 07,07,07, 07,07,07 ; roof
	RGB 08,08,08, 08,08,08, 08,08,08, 08,08,08 ; text

; day
	RGB 11,11,11, 11,11,11, 11,11,11, 11,11,11 ; gray
	RGB 12,12,12, 12,12,12, 12,12,12, 12,12,12 ; red
	RGB 13,13,13, 13,13,13, 13,13,13, 13,13,13 ; green
	RGB 14,14,14, 14,14,14, 14,14,14, 14,14,14 ; water
	RGB 15,15,15, 15,15,15, 15,15,15, 15,15,15 ; yellow
	RGB 16,16,16, 16,16,16, 16,16,16, 16,16,16 ; brown
	RGB 17,17,17, 17,17,17, 17,17,17, 17,17,17 ; roof
	RGB 18,18,18, 18,18,18, 18,18,18, 18,18,18 ; text

; nite
	RGB 21,21,21, 21,21,21, 21,21,21, 21,21,21 ; gray
	RGB 22,22,22, 22,22,22, 22,22,22, 22,22,22 ; red
	RGB 23,23,23, 23,23,23, 23,23,23, 23,23,23 ; green
	RGB 24,24,24, 24,24,24, 24,24,24, 24,24,24 ; water
	RGB 25,25,25, 25,25,25, 25,25,25, 25,25,25 ; yellow
	RGB 26,26,26, 26,26,26, 26,26,26, 26,26,26 ; brown
	RGB 27,27,27, 27,27,27, 27,27,27, 27,27,27 ; roof
	RGB 28,28,28, 28,28,28, 28,28,28, 28,28,28 ; text

; dark
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; gray
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; red
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; green
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; water
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; yellow
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; brown
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; roof
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; text

; indoor
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; gray
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; red
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; green
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; water
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; yellow
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; brown
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; roof
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; text

; overworld water
	RGB 31,31,31, 31,31,31, 31,31,31, 31,31,31 ; morn/day
	RGB 09,09,09, 09,09,09, 09,09,09, 09,09,09 ; nite
"""

# 8 named rows per time block (red/blue/green/brown/pink/silver/tree/rock).
# Chris always uses "red" (PAL_OW_RED = row 0 of each time block).
NPC_SPRITES_PAL = """
; morn
	RGB 01,01,01, 01,01,01, 01,01,01, 01,01,01 ; red
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; blue
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; green
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; brown
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; pink
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; silver
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; tree
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; rock

; day
	RGB 11,11,11, 11,11,11, 11,11,11, 11,11,11 ; red
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; blue
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; green
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; brown
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; pink
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; silver
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; tree
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; rock

; nite
	RGB 21,21,21, 21,21,21, 21,21,21, 21,21,21 ; red
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; blue
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; green
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; brown
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; pink
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; silver
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; tree
	RGB 00,00,00, 00,00,00, 00,00,00, 00,00,00 ; rock
"""


def _write_fixture(root):
    def w(rel, content):
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
    w("gfx/tilesets/johto_palette_map.asm", JOHTO_PALETTE_MAP)
    w("data/maps/environment_colors.asm", ENVIRONMENT_COLORS)
    w("gfx/tilesets/bg_tiles.pal", BG_TILES_PAL)
    w("gfx/overworld/npc_sprites.pal", NPC_SPRITES_PAL)


class ResolveTest(unittest.TestCase):
    def test_tile_groups_span_the_vram_bank_gap(self):
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(tmp)
            result = palettes.resolve(tmp)
        # bank-0 block: tile ids 0-7 (one tilepal line, 8 names)
        self.assertEqual(result["tileGroups"][0], 0)  # GRAY
        self.assertEqual(result["tileGroups"][3], 3)  # WATER
        self.assertEqual(result["tileGroups"][7], 7)  # TEXT
        # bank-1 block must start at tile id 128, not 8 -- the $ff-padded
        # gap (tile ids 8-127 in this trimmed fixture, 96-127 in the real
        # table) is never assigned
        self.assertNotIn(8, result["tileGroups"])
        self.assertNotIn(127, result["tileGroups"])
        self.assertEqual(result["tileGroups"][128], 1)  # RED
        self.assertEqual(result["tileGroups"][135], 7)  # TEXT

    def test_outdoor_water_slot_uses_the_special_overworld_water_row(self):
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(tmp)
            result = palettes.resolve(tmp)
        # group 3 (WATER) in .OutdoorColors' morn row is index $28, which
        # points at bg_tiles.pal's "overworld water / morn/day" row (RGB
        # 31,31,31,...), NOT the plain "water" row (RGB 04,04,04,...)
        morn_water = result["byTime"]["morn"]["groupColors"][3]
        self.assertEqual(morn_water[0], [255, 255, 255])  # scale5(31) == 255
        nite_water = result["byTime"]["nite"]["groupColors"][3]
        self.assertEqual(nite_water[0], [74, 74, 74])  # scale5(9) == 74

    def test_scale5_rgb555_to_rgb888(self):
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(tmp)
            result = palettes.resolve(tmp)
        # morn GRAY row: RGB 01,01,01 x4 -> scale5(1) == 8
        self.assertEqual(result["byTime"]["morn"]["groupColors"][0][0], [8, 8, 8])

    def test_sprite_color_is_chris_red_row_per_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(tmp)
            result = palettes.resolve(tmp)
        self.assertEqual(result["byTime"]["morn"]["spriteColor"][0], [8, 8, 8])
        self.assertEqual(result["byTime"]["day"]["spriteColor"][0], [90, 90, 90])
        self.assertEqual(result["byTime"]["nite"]["spriteColor"][0], [173, 173, 173])

    def test_dark_and_indoor_are_not_resolved(self):
        with tempfile.TemporaryDirectory() as tmp:
            _write_fixture(tmp)
            result = palettes.resolve(tmp)
        self.assertEqual(set(result["byTime"].keys()), {"morn", "day", "nite"})


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tools/extract_gen2/test_palettes.py -v`
Expected: `ModuleNotFoundError` — `extract_gen2.palettes` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `tools/extract_gen2/palettes.py`:

```python
"""Crystal BG tile-group + time-of-day RGB palette resolution.

Sources (all read as human-readable pokecrystal source text, never
compiled ROM bytes -- the same category of "structural, byte-identical
to the one canonical ROM this project validates by SHA-1" data
tools/extract_gen2/font.py's fontCharmap already sets precedent for):

  gfx/tilesets/johto_palette_map.asm -- tilepal macro invocations, one
    named BG palette group per tile graphic id. Two blocks: bank-0 tile
    ids (a contiguous run starting at 0), then a 16-byte ($ff) padding
    gap (32 tile ids, unused), then bank-1 tile ids starting at id 128
    (not immediately after the bank-0 block -- confirmed against the
    real ROM's runtime lookup, home/engine/tilesets/map_palettes.asm's
    `byte_offset = tileId >> 1`: 112 bytes total = 224 addressable
    tile-id slots, ids 96-127 land on the padding and are never
    referenced by real map data).

  data/maps/environment_colors.asm's EnvironmentColorsPointers.OutdoorColors
    -- 4 rows (morn/day/nite/dark) x 8 columns (one per BG palette
    group), each an index ($00-$29) into bg_tiles.pal's RGB rows. The
    WATER column's morn/day/nite indices point at bg_tiles.pal's
    trailing "overworld water" rows instead of the plain "water" row --
    this resolver does not special-case that; it just follows whatever
    index is actually there, exactly as the real game does.

  gfx/tilesets/bg_tiles.pal -- 42 RGB555 rows (8 named colors x 5 time/
    environment blocks, plus 2 "overworld water" rows), in the exact
    order EnvironmentColorsPointers.OutdoorColors indexes.

  gfx/overworld/npc_sprites.pal -- RGB555 rows, 8 named colors per time
    block (red/blue/green/brown/pink/silver/tree/rock). Chris always
    wears PAL_OW_RED (row 0 of each time block) -- the only overworld
    sprite this skeleton extracts.

Deliberately resolves only morn/day/nite (this project's Crystal work
has no cave or indoor map extracted yet, so "dark" and "indoor" data --
real, but meaningless without one -- are left unresolved; see the
Gen2 (Crystal) Native Color design spec's non-goals).
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from extract.util import parse_number, read_asm  # noqa: E402

# index 0-7, matches constants/tileset_constants.asm's PAL_BG_* order
PAL_BG_NAMES = ("GRAY", "RED", "GREEN", "WATER", "YELLOW", "BROWN", "ROOF", "TEXT")

# tile ids 0-95 (bank 0) are contiguous from 0; the $ff-padded gap covers
# ids 96-127; bank 1 tile ids resume at 128 (see module docstring)
BANK1_START_ID = 128


def _scale5(v):
    """5-bit (0-31) RGB555 component -> 8-bit (0-255)."""
    return round(v * 255 / 31)


def parse_tile_groups(pokecrystal):
    groups = {}
    tile_id = 0
    seen_bank1 = False
    path = os.path.join(pokecrystal, "gfx/tilesets/johto_palette_map.asm")
    for _, line in read_asm(path):
        m = re.match(r"tilepal\s+(\d+),\s*(.+)$", line.strip())
        if not m:
            continue
        bank = int(m.group(1))
        if bank == 1 and not seen_bank1:
            tile_id = BANK1_START_ID
            seen_bank1 = True
        for name in (n.strip() for n in m.group(2).split(",")):
            groups[tile_id] = PAL_BG_NAMES.index(name)
            tile_id += 1
    return groups


def parse_outdoor_index(pokecrystal):
    """4 rows (morn/day/nite/dark), each 8 ints -- indexes into bg_tiles.pal."""
    path = os.path.join(pokecrystal, "data/maps/environment_colors.asm")
    rows = []
    in_block = False
    for _, line in read_asm(path):
        s = line.strip()
        if s == ".OutdoorColors:":
            in_block = True
            continue
        if not in_block:
            continue
        m = re.match(r"db\s+(.+)$", s)
        if not m:
            break
        rows.append([parse_number(v.strip()) for v in m.group(1).split(",")])
    if len(rows) != 4:
        raise SystemExit(
            f".OutdoorColors: expected 4 rows (morn/day/nite/dark), got {len(rows)}")
    return rows


def _parse_rgb_rows(path):
    rows = []
    for _, line in read_asm(path):
        m = re.match(r"RGB\s+(.+)$", line.strip())
        if not m:
            continue
        nums = [int(v) for v in m.group(1).split(",")]
        rows.append([nums[i:i + 3] for i in range(0, 12, 3)])
    return rows


def resolve(pokecrystal):
    tile_groups = parse_tile_groups(pokecrystal)
    outdoor_index = parse_outdoor_index(pokecrystal)  # [morn, day, nite, dark]
    bg_rows = _parse_rgb_rows(os.path.join(pokecrystal, "gfx/tilesets/bg_tiles.pal"))
    sprite_rows = _parse_rgb_rows(
        os.path.join(pokecrystal, "gfx/overworld/npc_sprites.pal"))

    by_time = {}
    for time_idx, time_name in enumerate(("morn", "day", "nite")):
        group_colors = []
        for group in range(8):
            row = bg_rows[outdoor_index[time_idx][group]]
            group_colors.append([[_scale5(c) for c in color] for color in row])
        sprite_row = sprite_rows[time_idx * 8 + 0]  # PAL_OW_RED = 0
        sprite_color = [[_scale5(c) for c in color] for color in sprite_row]
        by_time[time_name] = {"groupColors": group_colors, "spriteColor": sprite_color}

    return {"tileGroups": tile_groups, "byTime": by_time}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tools/extract_gen2/test_palettes.py -v`
Expected: `OK` (5 tests passed).

- [ ] **Step 5: Commit**

```bash
git add tools/extract_gen2/palettes.py tools/extract_gen2/test_palettes.py
git commit -m "$(cat <<'EOF'
Add Crystal palette resolver

Resolves tile-graphic-id -> BG palette group, and per-time-of-day
(morn/day/nite) RGB colors for both terrain and Chris's sprite,
entirely from readable pokecrystal source text (tilepal macro
invocations, the OutdoorColors index table, bg_tiles.pal/
npc_sprites.pal RGB rows) -- the same "structural data, byte-identical
to the one canonical ROM this project already SHA-1-validates"
category tools/extract_gen2/font.py's fontCharmap already established,
not a raw ROM-byte read. No cave/indoor data resolved (out of scope:
no such map extracted yet).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Wire palette resolution into the Crystal manifest builder

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py`

**Interfaces:**
- Consumes: `tools/extract_gen2/palettes.py`'s `resolve` (Task 1).
- Produces: `tools/rom_manifest_crystal.json` gains a top-level `"palettes"` field (Task 1's exact resolved shape). Consumed by Task 3's `RomExtractorGen2:extractPalettes()` via `self.manifest.palettes`.

- [ ] **Step 1: Add the import and the manifest field**

In `tools/make_rom_manifest_crystal.py`, add the import after the existing `from extract_gen2.font import parse_charmap` line:

```python
from extract_gen2.palettes import resolve as resolve_palettes  # noqa: E402
```

In `main()`, add `"palettes"` to the `data` dict:

```python
    data = {
        "romSha1": CRYSTAL_SHA1,
        "symbols": embed_symbols(symbols),
        "newBarkTown": parse_new_bark_town(pokecrystal),
        "fontCharmap": parse_charmap(pokecrystal),
        "palettes": resolve_palettes(pokecrystal),
    }
```

No `REQUIRED_SYMBOLS` changes -- this data is resolved from source text, not ROM bytes, so it needs no bank:address symbols at all.

- [ ] **Step 2: Run it for real against the local pokecrystal checkout and verify the output**

```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal /tmp/pokecrystal \
  --symbols /tmp/pokecrystal/pokecrystal.sym \
  --out tools/rom_manifest_crystal.json
python3 -c "
import json
d = json.load(open('tools/rom_manifest_crystal.json'))
p = d['palettes']
print(sorted(p['byTime'].keys()))
print(len(p['tileGroups']), 'tile group entries')
print(min(p['tileGroups']), max(p['tileGroups']))
print(p['byTime']['morn']['groupColors'][3][0])  # WATER group, color 0
print(p['byTime']['morn']['spriteColor'][0])
"
```

Expected: `['day', 'morn', 'nite']`; a tile-group count matching what New Bark Town's tileset actually uses (in the low hundreds -- 96 bank-0 ids + up to 96 bank-1 ids, so up to 192, matching this project's own already-extracted `tools/gen2_dev_data/tilesets.lua`'s confirmed 0-191 range from an earlier task); min `0`, max `223` (or lower if the real table happens not to fill every bank-1 slot -- if `max` is unexpectedly below `128`, something is wrong with the bank-1 detection and must be fixed before continuing); the WATER morn color should visibly differ from a plain "water" RGB555 row's naive scale (since `.OutdoorColors` redirects it to the special "overworld water" row -- eyeball that it's a bright, saturated blue-white, not the murkier plain water tone nearby rows show); the sprite color should be a plausible skin/cap-red-ish RGB triple, not `[0,0,0]` or an error.

- [ ] **Step 3: Commit**

```bash
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json
git commit -m "$(cat <<'EOF'
Add resolved palette data to the Crystal manifest

palettes field carries fully-resolved (index indirection already
applied) morn/day/nite RGB for every BG tile group and Chris's
sprite, straight from tools/extract_gen2/palettes.py.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `RomExtractorGen2:extractPalettes()` — forward the resolved data at import time

**Files:**
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `self.manifest.palettes` (Task 2).
- Produces: `data/generated/palettes.lua`, loaded as `Game.data.palettes` (already an *optional* module in `src/core/Data.lua`'s `OPTIONAL` list -- `{"audio", "palettes", "icons"}` -- so no `Data.lua` changes are needed at all; a missing/absent `palettes.lua` already degrades gracefully with a warning, exactly like it does for Gen1 today). Consumed by Task 4's `PaletteFX.gbcPack()`.

- [ ] **Step 1: Write `extractPalettes()` and call it from `run()`**

Add this function to `src/import/RomExtractorGen2.lua`, after `extractFont()`:

```lua
-- Fully resolved by tools/extract_gen2/palettes.py at manifest-build time
-- (see that file's docstring for why this is source-derived rather than a
-- ROM-byte read, unlike every other extractX here) -- nothing left to
-- decode, just forward it into the generated cache under the same
-- "palettes" name Data.lua already treats as optional for Gen1.
function RomExtractorGen2:extractPalettes()
  local data = self.manifest.palettes
  self:write("palettes", data)
  return data
end
```

In `run()`, add the call between `extractFont()` and `extractField()`:

```lua
function RomExtractorGen2:run()
  local results = {}
  results.sprites = self:extractSprite()
  results.tilesets = self:extractTileset()
  results.maps = self:extractMap()
  results.font = self:extractFont()
  results.palettes = self:extractPalettes()
  results.field = self:extractField(results.maps.NEW_BARK_TOWN)
  self:extractStubs()
```

- [ ] **Step 2: Verify the file loads**

Run: `luajit -e "assert(loadfile('src/import/RomExtractorGen2.lua'))" && echo OK`
Expected: `OK`

- [ ] **Step 3: Run the full quick test suite to confirm no regressions**

Run: `./scripts/test.sh --quick`
Expected: `ALL TIERS PASSED`

- [ ] **Step 4: Commit**

```bash
git add src/import/RomExtractorGen2.lua
git commit -m "$(cat <<'EOF'
Write Crystal's resolved palette data at import time

extractPalettes() forwards the manifest's already-resolved
morn/day/nite palette data into data/generated/palettes.lua --
Data.lua already treats "palettes" as an optional generated module
(the same slot Gen1's own ROM-derived SuperPalettes/OG-boot-palette
data uses), so no engine loader changes are needed here.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Render Crystal in real color, unconditionally

**Files:**
- Modify: `src/core/GameVersion.lua`
- Modify: `src/render/PaletteFX.lua`
- Modify: `src/core/Game.lua`

**Interfaces:**
- Consumes: `Game.data.palettes` (Task 3's shape), the existing `PaletteFX.gbcPack()` / `usesGbcPack()` / `hasWorldTileset()` / `worldGroupAt()` / `worldGroupColors()` / `spriteObp()` functions (all unmodified in body except `gbcPack`/`usesGbcPack`/`spriteObp` themselves, per this task).
- Produces: `GameVersion.isCrystal()` (new). `PaletteFX.setData(data)`, `PaletteFX.timeOfDay(hour)` (new, both consumed again by Task 5).

- [ ] **Step 1: Add `GameVersion.isCrystal()`**

In `src/core/GameVersion.lua`, right after the existing `isYellow` function:

```lua
function GameVersion.isYellow()
  return GameVersion.current == "yellow"
end

function GameVersion.isCrystal()
  return GameVersion.current == "crystal"
end
```

- [ ] **Step 2: Give `PaletteFX` a live reference to `Game.data`**

In `src/render/PaletteFX.lua`, near the other module-level locals (`local shader`, `local gbcPack`, `local yellowPack`), add:

```lua
-- Crystal's real-color pack reads live, per-session ROM-extracted data
-- (unlike RED++'s static committed pack below, which is fully self-
-- contained), so it needs a reference to the current Game.data -- set
-- once at boot (src/core/Game.lua, alongside Font.load(Data)).
local activeData = false
local crystalPackCache, crystalPackBucket

function PaletteFX.setData(data)
  activeData = data
  crystalPackCache, crystalPackBucket = nil, nil
end
```

- [ ] **Step 3: Add `PaletteFX.timeOfDay(hour)`**

Add this function anywhere in `src/render/PaletteFX.lua` above `gbcPack` (e.g. right after `PaletteFX.setData`):

```lua
-- Crystal's own morn/day/nite boundaries (engine/rtc/rtc.asm,
-- constants/misc_constants.asm: MORN_HOUR=4, DAY_HOUR=10, NITE_HOUR=18).
-- hour is an optional 0-23 override (tests pass one directly, matching
-- this project's existing os.time()-injection convention -- see
-- src/mods/ModIndex.lua's `now = now or os.time()`); omitted, this reads
-- the host's real-world clock, mirroring how a real GBC cartridge's RTC
-- (battery-backed, free-running on real elapsed time) works, not a
-- simulated or saved in-game clock.
function PaletteFX.timeOfDay(hour)
  hour = hour or os.date("*t").hour
  if hour >= 4 and hour < 10 then return "morn" end
  if hour >= 10 and hour < 18 then return "day" end
  return "nite"
end
```

- [ ] **Step 4: Make `gbcPack()` Crystal-aware**

Change:

```lua
-- Red++ / pokered-gbc SuperPalette pack (committed; optional if absent).
function PaletteFX.gbcPack()
  if gbcPack == nil then
    local ok, pack = pcall(require, "data.palettes_gbc")
    gbcPack = ok and pack or false
  end
  return gbcPack or nil
end
```

to:

```lua
-- Red++ / pokered-gbc SuperPalette pack (committed; optional if absent) --
-- OR, for Crystal, the player's own ROM-extracted real color data,
-- resolved to the current (or test-injected) time-of-day bucket.  Every
-- consumer of this function (hasWorldTileset/worldGroupAt/
-- worldGroupColors/spriteObp below) reads whatever shape it returns
-- without caring which branch produced it -- Crystal's pack just needs
-- the same {world = {tileGroups, groupColors, roofGroup, spriteAssignment,
-- spritePalettes}} shape RED++'s does.
--
-- bucket is an optional override (tests pass one directly); omitted,
-- reads PaletteFX.timeOfDay()'s real-clock bucket.  Cached per bucket so
-- repeated calls within one frame (many tiles share this) don't rebuild
-- the wrapper table -- setData/checkTimeOfDay clear the cache when it's
-- actually stale.
function PaletteFX.gbcPack(bucket)
  if GameVersion.isCrystal() then
    local paletteData = activeData and activeData.palettes
    if not paletteData then return nil end
    bucket = bucket or PaletteFX.timeOfDay()
    if crystalPackCache and crystalPackBucket == bucket then
      return crystalPackCache
    end
    local byTime = paletteData.byTime[bucket] or paletteData.byTime.day
    crystalPackCache = { world = {
      tileGroups = { TILESET_JOHTO = paletteData.tileGroups },
      groupColors = { TILESET_JOHTO = byTime.groupColors },
      -- Crystal has no Gen1-style route/town roof-recolor exception; an
      -- empty (not nil) table makes worldGroupColors' `w.roofGroup[tileset]`
      -- index resolve to nil safely instead of erroring on a missing table.
      roofGroup = {},
      -- Chris is the only overworld sprite this skeleton extracts, always
      -- resolving to spritePalettes' one entry (see spriteObp's
      -- ChrisSpriteGFX case, Step 5 below).
      spriteAssignment = { [0] = 0 },
      spritePalettes = { [0] = byTime.spriteColor },
    } }
    crystalPackBucket = bucket
    return crystalPackCache
  end
  if gbcPack == nil then
    local ok, pack = pcall(require, "data.palettes_gbc")
    gbcPack = ok and pack or false
  end
  return gbcPack or nil
end
```

- [ ] **Step 5: Make `usesGbcPack()` return true unconditionally for Crystal**

Change:

```lua
function PaletteFX.usesGbcPack(mode)
  mode = mode or PaletteFX.mode
  return mode == "redpp"
end
```

to:

```lua
function PaletteFX.usesGbcPack(mode)
  mode = mode or PaletteFX.mode
  return mode == "redpp" or GameVersion.isCrystal()
end
```

This single change is what activates Crystal's real color everywhere: `TileRenderer.lua:475`'s baked-atlas gate, `SpriteRenderer.lua`'s three OBP-bake call sites, and `OverworldController.lua`'s `sgbWorldZones`/whole-screen-shader-skip logic (`OverworldController.lua:640,4468`) all already key off `PaletteFX.usesGbcPack()` with no other change needed.

- [ ] **Step 6: Let `spriteObp` resolve Chris's sprite**

In `PaletteFX.spriteObp`, change:

```lua
  if not idx and (src:find("RedBikeSprite", 1, true)
                  or src:find("SurfingPikachuSprite", 1, true)) then
    idx = 0
  end
```

to:

```lua
  if not idx and (src:find("RedBikeSprite", 1, true)
                  or src:find("SurfingPikachuSprite", 1, true)
                  or src:find("ChrisSpriteGFX", 1, true)) then
    idx = 0
  end
```

`RomExtractorGen2.lua`'s Chris sprite entry sets `source = "ROM:ChrisSpriteGFX"` (no bracketed index), so without this it would never resolve a palette and Chris would stay in DMG shades while the ground around him renders in real color.

- [ ] **Step 7: Wire `PaletteFX.setData` into game boot**

In `src/core/Game.lua`, change:

```lua
  require("src.render.Font").load(Data)
```

to:

```lua
  require("src.render.Font").load(Data)
  require("src.render.PaletteFX").setData(Data)
```

- [ ] **Step 8: Verify the files load**

Run:
```bash
luajit -e "assert(loadfile('src/core/GameVersion.lua'))" && echo OK
luajit -e "assert(loadfile('src/render/PaletteFX.lua'))" && echo OK
luajit -e "assert(loadfile('src/core/Game.lua'))" && echo OK
```
Expected: `OK` three times.

- [ ] **Step 9: Run the full quick test suite to confirm no regressions**

Run: `./scripts/test.sh --quick`
Expected: `ALL TIERS PASSED` (this task changes shared files used by every version's rendering path -- this is the most important regression check in the whole plan; if anything fails, do not proceed to Task 5 until it's green again).

- [ ] **Step 10: Commit**

```bash
git add src/core/GameVersion.lua src/render/PaletteFX.lua src/core/Game.lua
git commit -m "$(cat <<'EOF'
Render Crystal in real color, unconditionally

PaletteFX.gbcPack() -- already the single seam hasWorldTileset/
worldGroupAt/worldGroupColors/spriteObp all read through for Gen1's
ADVANCED/RED++ mode -- grows a Crystal branch that builds the same
{world = {...}} shape from the player's own ROM-extracted palette
data (Task 3) instead of requiring the static committed RED++ pack.
usesGbcPack() now returns true unconditionally for Crystal, which is
the only gate TileRenderer's baked atlas, SpriteRenderer's OBP bake,
and OverworldController's whole-screen-shader skip all already key
off -- so no other rendering file needs to change. spriteObp gains a
ChrisSpriteGFX case (Crystal's sprite source has no bracketed index,
unlike Gen1's SpriteSheetPointerTable entries) so the player sprite
resolves a palette too, not just terrain.

Time of day is read from the host's real-world clock (PaletteFX.
timeOfDay), matching how a real GBC cartridge's RTC works, but this
task only resolves it once per gbcPack() cache miss -- live switching
while already in-game is Task 5.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Live time-of-day switching

**Files:**
- Modify: `src/render/PaletteFX.lua`
- Modify: `src/world/OverworldController.lua`

**Interfaces:**
- Consumes: `PaletteFX.timeOfDay()` (Task 4), the same `MapLoader.invalidateAll()` / `Game.overworld:reloadMap(mapId, reason)` / `SpriteRenderer.invalidate()` / `BattleState.invalidate()` calls `PaletteFX.setMode()` already uses for a `COLORS` change (`PaletteFX.lua:766-781`, read but not modified).
- Produces: `PaletteFX.checkTimeOfDay()`, called once per frame from `OverworldState:update()`.

- [ ] **Step 1: Add `PaletteFX.checkTimeOfDay()`**

Add this function to `src/render/PaletteFX.lua`, right after `PaletteFX.setMode` (so it sits next to the exact mechanism it reuses):

```lua
-- Crystal only: detects a real-world morn/day/nite boundary crossing
-- while already in-game, and forces the same invalidate-and-reload
-- setMode already does for a COLORS change, so the visible palette
-- updates without restarting.  Cheap to call every frame -- os.date is
-- the only work done once the bucket hasn't changed; the (comparatively
-- expensive) atlas rebake only happens on an actual crossing.
local lastCrystalBucket
function PaletteFX.checkTimeOfDay()
  if not GameVersion.isCrystal() then return end
  local bucket = PaletteFX.timeOfDay()
  if lastCrystalBucket == nil then
    lastCrystalBucket = bucket
    return
  end
  if bucket == lastCrystalBucket then return end
  lastCrystalBucket = bucket
  crystalPackCache, crystalPackBucket = nil, nil
  pcall(function() require("src.battle.BattleState").invalidate() end)
  pcall(function() require("src.render.SpriteRenderer").invalidate() end)
  pcall(function()
    require("src.world.MapLoader").invalidateAll()
    local Game = require("src.core.Game")
    if Game.overworld and Game.overworld.map and Game.overworld.reloadMap then
      Game.overworld:reloadMap(Game.overworld.map.id, "timeOfDay")
    end
  end)
end
```

- [ ] **Step 2: Call it from the overworld update loop**

In `src/world/OverworldController.lua`, change:

```lua
function OverworldState:update(dt)
  -- deferred cutscene launch (see queueScript): run a queued script only
```

to:

```lua
function OverworldState:update(dt)
  PaletteFX.checkTimeOfDay()
  -- deferred cutscene launch (see queueScript): run a queued script only
```

- [ ] **Step 3: Verify the files load**

Run:
```bash
luajit -e "assert(loadfile('src/render/PaletteFX.lua'))" && echo OK
luajit -e "assert(loadfile('src/world/OverworldController.lua'))" && echo OK
```
Expected: `OK` twice.

- [ ] **Step 4: Run the full quick test suite to confirm no regressions**

Run: `./scripts/test.sh --quick`
Expected: `ALL TIERS PASSED`

- [ ] **Step 5: Commit**

```bash
git add src/render/PaletteFX.lua src/world/OverworldController.lua
git commit -m "$(cat <<'EOF'
Switch Crystal's palette live when the real-world time-of-day changes

checkTimeOfDay(), called once per overworld update, is a no-op for
every non-Crystal version and a cheap os.date comparison the rest of
the time -- it only pays for an atlas rebake on an actual morn/day/
nite boundary crossing, reusing the exact invalidate-and-reload path
setMode() already uses for a COLORS option change.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Fixture-backed structural test

**Files:**
- Modify: `tests/run_tests.lua`

**Interfaces:**
- Consumes: `GameVersion.set`/`GameVersion.isCrystal` (Task 4), `PaletteFX.setData`/`gbcPack`/`hasWorldTileset`/`worldGroupAt`/`worldGroupColors`/`spriteObp`/`timeOfDay` (Tasks 1-5, all unmodified in this task -- this proves the existing/newly-added functions already handle Gen2-shaped palette data correctly, the same "zero further engine changes" claim Task 7 (map) and the font plan's Task 4 already proved for their own data).
- Produces: nothing consumed by a later task; this is a leaf verification.

- [ ] **Step 1: Write the test**

In `tests/run_tests.lua`, add this new `do...end` block immediately after the Gen2 font fixture block (the one added by the font plan, which ends with `eq(Font.width("AB"), 16, ...)` followed by the `Font.load(Data)` restore line and `end`), and before the `-- ---------------------------------------------- the globbed tiers` comment:

```lua
-- Hand-built Crystal-shaped palette data (not ROM-derived), matching the
-- shape tools/extract_gen2/palettes.py resolves and
-- RomExtractorGen2:extractPalettes() forwards unchanged -- proves
-- PaletteFX's gbcPack()/hasWorldTileset()/worldGroupAt()/
-- worldGroupColors()/spriteObp() (all unmodified by this test) already
-- resolve Gen2-shaped, time-of-day-bucketed data correctly, the same
-- "zero further engine changes" claim the map/font fixtures above prove
-- for their own data. Switches GameVersion to "crystal" and back, and
-- clears PaletteFX's data reference afterward, so nothing here leaks into
-- later checks in this file (see the font fixture block's own Font.load
-- restore for the established precedent this follows).
do
  local GameVersion = require("src.core.GameVersion")
  local PaletteFX = require("src.render.PaletteFX")
  GameVersion.set("crystal")

  local fakeTileGroups = { [0] = 2, [1] = 3 } -- tile 0 -> group 2, tile 1 -> group 3
  local function flatColors(n)
    -- one distinguishable {r,g,b}x4 per group, group N's color 0 = {N,N,N}
    local out = {}
    for g = 0, 7 do out[g + 1] = { { g, g, g }, { g, g, g }, { g, g, g }, { g, g, g } } end
    return out
  end
  local fakePaletteData = {
    tileGroups = fakeTileGroups,
    byTime = {
      morn = { groupColors = flatColors(), spriteColor = { { 40, 40, 40 }, { 40, 40, 40 }, { 40, 40, 40 }, { 40, 40, 40 } } },
      day  = { groupColors = flatColors(), spriteColor = { { 50, 50, 50 }, { 50, 50, 50 }, { 50, 50, 50 }, { 50, 50, 50 } } },
      nite = { groupColors = flatColors(), spriteColor = { { 60, 60, 60 }, { 60, 60, 60 }, { 60, 60, 60 }, { 60, 60, 60 } } },
    },
  }
  PaletteFX.setData({ palettes = fakePaletteData })

  check(PaletteFX.hasWorldTileset("TILESET_JOHTO"),
    "Gen2 palette fixture: TILESET_JOHTO resolves as a known world tileset")
  check(not PaletteFX.hasWorldTileset("TILESET_KANTO"),
    "Gen2 palette fixture: an unrelated tileset does not")

  eq(PaletteFX.worldGroupAt("TILESET_JOHTO", "NEW_BARK_TOWN", 0), 2,
    "Gen2 palette fixture: tile 0 resolves to its extracted group")
  eq(PaletteFX.worldGroupAt("TILESET_JOHTO", "NEW_BARK_TOWN", 1), 3,
    "Gen2 palette fixture: tile 1 resolves to its extracted group")

  -- explicit bucket override (this repo's established os.time()-injection
  -- testability convention -- see PaletteFX.timeOfDay's own doc comment)
  local morn = PaletteFX.gbcPack("morn")
  eq(morn.world.groupColors.TILESET_JOHTO[3][1], { 2, 2, 2 },
    "Gen2 palette fixture: morn bucket resolves group 2's color")
  local nite = PaletteFX.gbcPack("nite")
  local colors, group = PaletteFX.spriteObp({ source = "ROM:ChrisSpriteGFX" }, "seed")
  eq(group, 0, "Gen2 palette fixture: Chris resolves to sprite group 0")
  eq(colors[1], { 60, 60, 60 },
    "Gen2 palette fixture: Chris's sprite color follows the current (nite) bucket")
  eq(nite.world.groupColors.TILESET_JOHTO[4][1], { 3, 3, 3 },
    "Gen2 palette fixture: nite bucket resolves group 3's color, independent of morn's cache")

  -- morn/day/nite hour-boundary math (engine/rtc/rtc.asm: 4/10/18)
  eq(PaletteFX.timeOfDay(3), "nite", "Gen2 palette fixture: hour 3 is nite")
  eq(PaletteFX.timeOfDay(4), "morn", "Gen2 palette fixture: hour 4 is morn")
  eq(PaletteFX.timeOfDay(9), "morn", "Gen2 palette fixture: hour 9 is still morn")
  eq(PaletteFX.timeOfDay(10), "day", "Gen2 palette fixture: hour 10 is day")
  eq(PaletteFX.timeOfDay(17), "day", "Gen2 palette fixture: hour 17 is still day")
  eq(PaletteFX.timeOfDay(18), "nite", "Gen2 palette fixture: hour 18 is nite")

  PaletteFX.setData(nil)
  GameVersion.set("red")
end
```

- [ ] **Step 2: Run it and verify it passes**

Run: `luajit tests/run_tests.lua 2>&1 | grep -i "gen2 palette"`
Expected: 12 lines, each starting `ok` (like the font fixture before it, this proves existing/already-added `PaletteFX` code handles the shape correctly -- there is no red phase here, matching the established precedent).

Then run the full suite to confirm nothing else broke and that `GameVersion.set("red")`/`PaletteFX.setData(nil)` actually restored state cleanly for whatever runs afterward in the same process:

Run: `./scripts/test.sh --quick`
Expected: `ALL TIERS PASSED`

- [ ] **Step 3: Commit**

```bash
git add tests/run_tests.lua
git commit -m "$(cat <<'EOF'
Add fixture-backed structural test for Gen2 palette data

Proves PaletteFX's gbcPack/hasWorldTileset/worldGroupAt/
worldGroupColors/spriteObp -- none modified by this test -- already
resolve hand-built, Gen2-shaped, time-of-day-bucketed palette data
correctly, with no ROM present. Restores GameVersion and PaletteFX's
data reference to their pre-test state at the end, so nothing here
leaks into later checks in this file.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Manual real-ROM verification

**Files:** none (verification checklist only; this task produces no commit unless it uncovers a bug in an earlier task, in which case fix that task's file and commit there, then re-run this task from Step 1).

**Interfaces:** N/A.

- [ ] **Step 1: Reimport Crystal with the real ROM**

```bash
love .
```

Reimport the Crystal ROM (already-imported versions get a "Reimport" action). Expected: import completes with no error.

- [ ] **Step 2: Verify the generated palette data**

Find the save directory LÖVE logged at launch (`love.filesystem.getSaveDirectory()`), and confirm `crystal/data/generated/palettes.lua` exists there and is larger than the ~10-byte empty-table stub every still-unextracted module has (`tileGroups`/`byTime` should make it a few hundred lines at least).

- [ ] **Step 3: Verify New Bark Town renders in real color, automatically**

Press Play, reach New Bark Town. Expected: grass is green, roofs/buildings show real color (not grayscale), water (if any tile is visible) is blue, and this is true without ever opening the Options menu or touching `COLORS` -- confirm by checking whichever `COLORS` value the save/options already has set (any value, including one of the DMG-novelty modes) has no effect on Crystal's own rendering.

- [ ] **Step 4: Verify the player sprite is colored too**

Confirm Chris's sprite shows real color (skin tone, cap, clothing), not a grayscale DMG-shaded sheet, consistent with the surrounding terrain.

- [ ] **Step 5: Verify live time-of-day switching**

Change the host system's clock to a different time-of-day bucket than whatever it currently is (e.g. if it's currently daytime, set the system clock to 22:00 for "nite", or 06:00 for "morn") while the game is running and the player is standing in New Bark Town. Expected: within roughly a second (the next `OverworldState:update()` tick), the rendered palette visibly shifts to match the new bucket, with no crash and no need to restart the game or reload the map manually. Set the system clock back to the correct time afterward.

- [ ] **Step 6: Confirm zero regressions to Gen1's `COLORS` modes**

Switch to Red, Blue, or Yellow, and cycle through the `COLORS` option (OG RED, SGB, ADVANCED, etc.) in the Options menu. Expected: every mode still looks and behaves exactly as it did before this plan (ADVANCED/RED++ in particular, since it shares the most machinery with this change).

- [ ] **Step 7: If everything above passes, update the spec's status**

Edit `docs/superpowers/specs/2026-08-04-gen2-crystal-color-design.md`'s `Status:` line from `approved for planning` to `verified against real ROM, <today's date>`, and commit:

```bash
git add docs/superpowers/specs/2026-08-04-gen2-crystal-color-design.md
git commit -m "$(cat <<'EOF'
Mark the Gen2 (Crystal) native color feature verified against real ROM

New Bark Town renders in real color automatically (terrain and
player sprite), independent of the COLORS option; the palette
switches live when the host system's clock crosses a morn/day/nite
boundary; Gen1's COLORS modes show no regression.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```
