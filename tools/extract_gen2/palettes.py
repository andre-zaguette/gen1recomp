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
