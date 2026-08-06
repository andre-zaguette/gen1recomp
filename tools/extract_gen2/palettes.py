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

Deliberately resolves only morn/day/nite. The minimal Crystal import
uses both outdoor and indoor environments, so the relevant tilesets are
split between those two environment tables.
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

TILESET_FILES = {
    "TILESET_JOHTO": ("gfx/tilesets/johto_palette_map.asm", "outdoor"),
    "TILESET_PLAYERS_HOUSE": ("gfx/tilesets/players_house_palette_map.asm", "indoor"),
    "TILESET_PLAYERS_ROOM": ("gfx/tilesets/players_room_palette_map.asm", "indoor"),
    "TILESET_LAB": ("gfx/tilesets/lab_palette_map.asm", "indoor"),
    "TILESET_HOUSE": ("gfx/tilesets/house_palette_map.asm", "indoor"),
}


def _scale5(v):
    """5-bit (0-31) RGB555 component -> 8-bit (0-255)."""
    return round(v * 255 / 31)


def parse_palette_map(path):
    groups = {}
    tile_id = 0
    seen_bank1 = False
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


def parse_environment_index(pokecrystal):
    """Named 4-row (morn/day/nite/dark) x 8-col environment index tables."""
    path = os.path.join(pokecrystal, "data/maps/environment_colors.asm")
    rows = {}
    current = None
    for _, line in read_asm(path):
        s = line.strip()
        block = re.match(r"\.(\w+Colors):$", s)
        if block:
            current = block.group(1)
            rows[current] = []
            continue
        if current is None:
            continue
        m = re.match(r"db\s+(.+)$", s)
        if not m:
            current = None
            continue
        rows[current].append([parse_number(v.strip()) for v in m.group(1).split(",")])
    for name in ("OutdoorColors", "IndoorColors"):
        if len(rows.get(name, [])) != 4:
            raise SystemExit(
                f".{name}: expected 4 rows (morn/day/nite/dark), got {len(rows.get(name, []))}")
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
    tile_groups = {}
    environment_for_tileset = {}
    for tileset, spec in TILESET_FILES.items():
      relpath, environment = spec
      tile_groups[tileset] = parse_palette_map(os.path.join(pokecrystal, relpath))
      environment_for_tileset[tileset] = environment
    environment_index = parse_environment_index(pokecrystal)
    bg_rows = _parse_rgb_rows(os.path.join(pokecrystal, "gfx/tilesets/bg_tiles.pal"))
    sprite_rows = _parse_rgb_rows(
        os.path.join(pokecrystal, "gfx/overworld/npc_sprites.pal"))

    by_time = {}
    for time_idx, time_name in enumerate(("morn", "day", "nite")):
        group_colors = {}
        for tileset, environment in environment_for_tileset.items():
            index_rows = environment_index["OutdoorColors" if environment == "outdoor"
                                           else "IndoorColors"]
            groups = []
            for group in range(8):
                row = bg_rows[index_rows[time_idx][group]]
                groups.append([[_scale5(c) for c in color] for color in row])
            group_colors[tileset] = groups
        sprite_colors = {}
        for palette_idx, palette_name in enumerate(
                ("red", "blue", "green", "brown", "pink", "silver", "tree", "rock")):
            sprite_row = sprite_rows[time_idx * 8 + palette_idx]
            sprite_colors[palette_name] = [[_scale5(c) for c in color] for color in sprite_row]
        by_time[time_name] = {
            "groupColors": group_colors,
            "spriteColor": sprite_colors["red"],
            "spriteColors": sprite_colors,
        }

    return {"tileGroups": tile_groups, "byTime": by_time}
