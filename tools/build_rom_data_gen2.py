#!/usr/bin/env python3
"""Dev-path Gen2 (Crystal) data builder: New Bark Town only.

Combines tools/rom_manifest_crystal.json with the player's real Crystal
ROM to produce verification data under --out-dir/--assets-dir (never
data/generated/ -- this is not the shipped path, see
src/import/RomExtractorGen2.lua for that). Mirrors tools/build_rom_data.py's
shape, scoped to one map/tileset/sprite.
"""

import argparse
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract import util  # noqa: E402
from extract_gen2 import collision, lz3  # noqa: E402
from rom_data import RomImage, SymbolTable, load_manifest  # noqa: E402

GB_SHADES = (
    (255, 255, 255, 255), (170, 170, 170, 255),
    (85, 85, 85, 255), (0, 0, 0, 255),
)

# COLL_* constant -> base permission, from pret/pokecrystal
# constants/collision_constants.asm + data/collision/collision_permissions.asm
LAND_TILE, WATER_TILE, WALL_TILE, TALK = 0x00, 0x01, 0x0F, 0x10


def _decode_2bpp(raw, width, height):
    tile_count = width // 8 * (height // 8)
    if len(raw) != tile_count * 16:
        raise ValueError(f"2bpp payload is {len(raw)} bytes, expected {tile_count * 16}")
    image = Image.new("RGBA", (width, height))
    pixels = image.load()
    tiles_per_row = width // 8
    for tile in range(tile_count):
        tx, ty = (tile % tiles_per_row) * 8, (tile // tiles_per_row) * 8
        for y in range(8):
            low = raw[tile * 16 + y * 2]
            high = raw[tile * 16 + y * 2 + 1]
            for x in range(8):
                bit = 7 - x
                shade = ((high >> bit) & 1) * 2 + ((low >> bit) & 1)
                pixels[tx + x, ty + y] = GB_SHADES[shade]
    return image


def _write_2bpp_png(raw, width, height, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _decode_2bpp(raw, width, height).save(path, optimize=True)


def extract_sprite(rom, symbols, out_assets):
    """ChrisSpriteGFX: 16x96px, not LZ-compressed."""
    symbol = symbols["ChrisSpriteGFX"]
    raw = rom.bytes(symbol.bank, symbol.address, 16 * 96 // 4)
    _write_2bpp_png(raw, 16, 96, os.path.join(out_assets, "sprites", "chris.png"))
    return {
        "SPRITE_CHRIS": {
            "id": "SPRITE_CHRIS",
            "source": "ROM:ChrisSpriteGFX",
            "image": "assets/generated/sprites/chris.png",
            "frames": 96 // 16,
            "walker": True,
        }
    }


def _collision_permission(coll_value):
    return collision.COLLISION_PERMISSION_TABLE[coll_value]


def extract_tileset(rom, symbols, out_dir, out_assets):
    gfx = symbols["TilesetJohtoGFX"]
    meta = symbols["TilesetJohtoMeta"]
    coll = symbols["TilesetJohtoColl"]

    compressed = rom.bytes(gfx.bank, gfx.address, 0x4000)  # generous upper bound; LZ3 stops at $FF
    raw = lz3.decompress(compressed)
    width_tiles = 16  # gfx/tilesets/johto.png is a 16-tiles-wide sheet, like Gen1 tileset sheets
    # tile count = len(raw) bytes / 16 bytes-per-2bpp-tile; height = (rows of
    # width_tiles tiles) * 8px. (Brief's original formula had a spurious
    # leading "* 8" that inflated height 8x -- see task-4-report.md.)
    height = len(raw) // 16 // width_tiles * 8
    width = width_tiles * 8
    _write_2bpp_png(raw, width, height, os.path.join(out_assets, "tilesets", "johto.png"))

    blocks_raw = rom.bytes(meta.bank, meta.address, 2048)
    blocks = [list(blocks_raw[i:i + 16]) for i in range(0, len(blocks_raw), 16)]

    coll_raw = rom.bytes(coll.bank, coll.address, len(blocks) * 4)
    walkable = set()
    for block_index, block in enumerate(blocks):
        cell_colls = coll_raw[block_index * 4:block_index * 4 + 4]
        # cell order/tile-index-within-block mapping confirmed against
        # data/tilesets/johto_collision.asm + the metatile grid layout
        # (top-left, top-right, bottom-left, bottom-right cells; each
        # cell's "bottom-left tile" is the tile the engine's collision
        # rule reads -- see docs/architecture.md).
        for cell_index, coll_value in enumerate(cell_colls):
            permission = _collision_permission(coll_value)
            if permission & 0x0F == LAND_TILE:
                bottom_left_tile_row = 1 if cell_index < 2 else 3
                bottom_left_tile_col = (cell_index % 2) * 2
                tile_id = block[bottom_left_tile_row * 4 + bottom_left_tile_col]
                walkable.add(tile_id)

    out = {
        "TILESET_JOHTO": {
            "id": "TILESET_JOHTO",
            "source": "ROM:TilesetJohtoGFX/Meta/Coll",
            "image": "assets/generated/tilesets/johto.png",
            "imageWidth": width, "imageHeight": height,
            "tilesPerRow": width // 8,
            "blocks": blocks,
            "walkable": sorted(walkable),
            "counterTiles": [], "grassTile": None,
            "doorTiles": [], "warpTiles": [],
            "animation": None,
        }
    }
    util.write_lua(os.path.join(out_dir, "tilesets.lua"), out,
                    header="Source: real Pokemon Crystal ROM (TilesetJohto*)")
    return out


def extract_map(rom, symbols, manifest, out_dir):
    header = symbols["NewBarkTown_MapAttributes"]
    expected = manifest["newBarkTown"]

    border = rom.byte(header.bank, header.address)
    height = rom.byte(header.bank, header.address + 1)
    width = rom.byte(header.bank, header.address + 2)
    if (width, height) != (expected["width"], expected["height"]):
        raise ValueError(
            f"NewBarkTown ROM dimensions {width}x{height} do not match "
            f"manifest {expected['width']}x{expected['height']}")
    blocks_bank = rom.byte(header.bank, header.address + 3)
    blocks_ptr = rom.word(header.bank, header.address + 4)
    events_bank = rom.byte(header.bank, header.address + 6)  # shared by MapScripts/MapEvents
    events_ptr = rom.word(header.bank, header.address + 9)

    blocks = list(rom.bytes(blocks_bank, blocks_ptr, width * height))

    addr = events_ptr
    addr += 2  # "db 0, 0 ; filler" MapEvents header

    warp_count = rom.byte(events_bank, addr)
    addr += 1
    warps = []
    for _ in range(warp_count):
        row = rom.bytes(events_bank, addr, 5)
        warps.append({
            "y": row[0], "x": row[1], "destWarp": row[2],
            "destMapGroup": row[3], "destMapNumber": row[4],
        })
        addr += 5
    if warp_count != expected["warpCount"]:
        raise ValueError(
            f"NewBarkTown ROM has {warp_count} warps, manifest expects "
            f"{expected['warpCount']}")

    coord_count = rom.byte(events_bank, addr)
    addr += 1 + coord_count * 8  # coord_event rows: not decoded, just skipped
    if coord_count != expected["coordEventCount"]:
        raise ValueError(
            f"NewBarkTown ROM has {coord_count} coord events, manifest "
            f"expects {expected['coordEventCount']}")

    bg_count = rom.byte(events_bank, addr)
    addr += 1 + bg_count * 5  # bg_event rows: not decoded (see Task 4's scope note)
    if bg_count != expected["bgEventCount"]:
        raise ValueError(
            f"NewBarkTown ROM has {bg_count} bg events, manifest expects "
            f"{expected['bgEventCount']}")

    object_count = rom.byte(events_bank, addr)
    addr += 1 + object_count * 13  # object_event rows: not decoded (see Task 4's scope note)
    if object_count != expected["objectCount"]:
        raise ValueError(
            f"NewBarkTown ROM has {object_count} objects, manifest expects "
            f"{expected['objectCount']}")

    out = {
        "NEW_BARK_TOWN": {
            "id": "NEW_BARK_TOWN", "label": "NewBarkTown", "index": 1,
            "source": f"ROM:{header.bank:02X}:{header.address:04X}",
            "tileset": "TILESET_JOHTO",
            "width": width, "height": height, "blocks": blocks,
            "borderBlock": border, "connections": {},
            "warps": warps, "signs": [], "objects": [],
        }
    }
    util.write_lua(os.path.join(out_dir, "maps.lua"), out,
                    header="Source: real Pokemon Crystal ROM (NewBarkTown_MapAttributes/MapEvents)")
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom", required=True)
    parser.add_argument("--manifest",
                         default=os.path.join(os.path.dirname(__file__), "rom_manifest_crystal.json"))
    parser.add_argument("--out-dir",
                         default=os.path.join(os.path.dirname(__file__), "gen2_dev_data"))
    parser.add_argument("--assets-dir",
                         default=os.path.join(os.path.dirname(__file__), "gen2_dev_data", "assets"))
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    rom = RomImage(args.rom, expected_sha1=manifest["romSha1"])
    symbols = SymbolTable(manifest["symbols"])

    sprites = extract_sprite(rom, symbols, args.assets_dir)
    util.write_lua(os.path.join(args.out_dir, "sprites.lua"), sprites,
                    header="Source: real Pokemon Crystal ROM (ChrisSpriteGFX)")
    extract_tileset(rom, symbols, args.out_dir, args.assets_dir)
    extract_map(rom, symbols, manifest, args.out_dir)
    print("done")


if __name__ == "__main__":
    main()
