#!/usr/bin/env python3
"""Generate the New Bark Town-scoped Gen2 manifest from a pokecrystal checkout.

Mirrors tools/make_rom_manifest.py's shape (symbolic metadata only, no ROM
bytes) but is scoped to exactly the symbols/facts the Crystal skeleton
extractor needs -- see docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md.
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract.util import parse_number, read_asm, split_args  # noqa: E402
from rom_data import SymbolTable  # noqa: E402
from extract_gen2.font import parse_charmap  # noqa: E402
from extract_gen2.palettes import resolve as resolve_palettes  # noqa: E402

CRYSTAL_SHA1 = "f2f52230b536214ef7c9924f483392993e226cfb"

REQUIRED_SYMBOLS = (
    "NewBarkTown_MapAttributes",
    "NewBarkTown_MapEvents",
    "TilesetJohtoGFX",
    "TilesetJohtoMeta",
    "TilesetJohtoColl",
    "ChrisSpriteGFX",
    "Font",
    "FontExtra",
)


def parse_new_bark_town(pokecrystal):
    """Read data/maps/maps.asm + constants/map_constants.asm for New Bark
    Town's dimensions, and maps/NewBarkTown.asm for its event counts."""
    dims = None
    for _, line in read_asm(
            os.path.join(pokecrystal, "constants/map_constants.asm")):
        m = re.match(r"map_const\s+NEW_BARK_TOWN,\s*(\d+),\s*(\d+)", line.strip())
        if m:
            dims = {"width": int(m.group(1)), "height": int(m.group(2))}
    if not dims:
        raise SystemExit("NEW_BARK_TOWN dimensions not found in map_constants.asm")

    counts = {"warpCount": 0, "coordEventCount": 0, "bgEventCount": 0, "objectCount": 0}
    field_for_macro = {
        "warp_event": "warpCount",
        "coord_event": "coordEventCount",
        "bg_event": "bgEventCount",
        "object_event": "objectCount",
    }
    in_events = False
    for _, line in read_asm(os.path.join(pokecrystal, "maps/NewBarkTown.asm")):
        s = line.strip()
        if s == "NewBarkTown_MapEvents:":
            in_events = True
            continue
        if not in_events:
            continue
        for macro, field in field_for_macro.items():
            if s.startswith(macro + " "):
                counts[field] += 1

    return {
        "width": dims["width"], "height": dims["height"],
        "tileset": "TILESET_JOHTO", **counts,
    }


def embed_symbols(symbols):
    out = {}
    for name in REQUIRED_SYMBOLS:
        symbol = symbols.by_name.get(name)
        if not symbol:
            raise SystemExit(f"required symbol missing from .sym: {name}")
        out[name] = [symbol.bank, symbol.address]
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pokecrystal", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument(
        "--out",
        default=os.path.join(os.path.dirname(__file__), "rom_manifest_crystal.json"))
    args = parser.parse_args()

    pokecrystal = os.path.abspath(args.pokecrystal)
    if not os.path.isfile(os.path.join(pokecrystal, "main.asm")):
        raise SystemExit(f"{pokecrystal} is not a pokecrystal checkout")

    symbols = SymbolTable(os.path.abspath(args.symbols))
    data = {
        "romSha1": CRYSTAL_SHA1,
        "symbols": embed_symbols(symbols),
        "newBarkTown": parse_new_bark_town(pokecrystal),
        "fontCharmap": parse_charmap(pokecrystal),
        "palettes": resolve_palettes(pokecrystal),
    }
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
