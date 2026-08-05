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
    "KrisSpriteGFX",
    "Font",
    "FontExtra",
    "_OakText1",
    "_OakText2",
    "_OakText4",
    "_OakText5",
    "_OakText6",
    "_OakText7",
    "_AreYouABoyOrAreYouAGirlText",
    "PokemonProfPic",
    "WooperFrontpic",
    # Wooper's three real cry channel programs (pulse 1, pulse 2, noise).
    # Read directly by name rather than via Cry_Wooper's own header table
    # (a 3-byte-per-channel {channel_number, address} list) -- confirmed
    # against the real .sym file: Cry_Wooper_Ch5 3c:722e, Cry_Wooper_Ch6
    # 3c:7249, Cry_Wooper_Ch8 3c:7264 (all bank $3c). See
    # docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md's
    # "Research already done" section for the fully-verified byte decode.
    "Cry_Wooper_Ch5",
    "Cry_Wooper_Ch6",
    "Cry_Wooper_Ch8",
)

# Runtime ROM text decoder (RomExtractorGen2:textGlyph/decodeTextCommands)
# overrides for a handful of charmap.asm tokens -- mirrors
# tools/make_rom_manifest.py's charmap()/tools/extract/text.py's
# EXPANSIONS for Gen1, trimmed to the tokens that actually exist in
# Crystal's own constants/charmap.asm. <LINE>/<PARA>/<CONT>/<NEXT> become
# the literal \n/\f/\v control chars src/render/TextBox.lua's markup
# already expects (see its own doc comment), matching Gen1's generated
# text.lua convention exactly (tests/fixture_data/text.lua uses raw \n
# for line breaks, not a "{LINE}" tag). Tokens with no entry here fall
# through to decodeTextCommands's generic "<TOKEN>" -> "{TOKEN}" bracket
# conversion.
TEXT_CHARMAP_EXPANSIONS = {
    "#": "POKé",
    "<PKMN>": "POKéMON",
    "<PC>": "PC",
    "<TM>": "TM",
    "<TRAINER>": "TRAINER",
    "<ROCKET>": "ROCKET",
    "<……>": "……",
    "<LV>": "{LV}",
    "<PLAYER>": "{PLAYER}",
    "<RIVAL>": "{RIVAL}",
    "<TARGET>": "{TARGET}",
    "<USER>": "{USER}",
    "<ID>": "{ID}",
    "<PARA>": "\f",
    "<LINE>": "\n",
    "<CONT>": "\v",
    "<NEXT>": "\n",
    "<DONE>": "",
    "<PROMPT>": "",
    "<NULL>": "",
    "@": "",
    "<DOT>": ".",
}


def text_charmap(pokecrystal):
    """Full $00-$FF constants/charmap.asm entries, keyed by decimal code
    string, for the runtime ROM text decoder. Decode direction (code ->
    displayable string) -- unlike extract_gen2.font.parse_charmap's
    render-direction ($60-$FF only) list used for Font.split. charmap.asm
    repeats several codes for a later Japanese-text counterpart (e.g. $54
    is both English "#" and "<POKEMON>"), so this keeps first-occurrence-
    wins, same as Gen1's charmap()."""
    out = {}
    path = os.path.join(pokecrystal, "constants/charmap.asm")
    for _, line in read_asm(path):
        m = re.match(
            r'charmap\s+"((?:[^"\\]|\\.)*)",\s*(\$[0-9a-fA-F]+)', line.strip())
        if not m:
            continue
        value = int(m.group(2)[1:], 16)
        if str(value) in out:
            continue
        seq = m.group(1).replace('\\"', '"')
        out[str(value)] = TEXT_CHARMAP_EXPANSIONS.get(seq, seq)
    return out


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


def resolve_wooper_cry(pokecrystal):
    """Wooper's row in data/pokemon/cries.asm's PokemonCries table:
    `mon_cry CRY_WOOPER, 147, 175 ; WOOPER`. `mon_cry`'s macro body is
    `dw \\1, \\2, \\3` (three 16-bit words = 6 bytes/row, confirmed by
    reading the macro definition at the top of cries.asm) -- NOT Gen1's
    one-byte pitch/length (src/import/RomExtractor.lua's extractAudio
    reads a 3-byte-per-row table there). Both fields can be negative
    (e.g. QUAGSIRE's row is `CRY_WOOPER, -198, 320`), so this reads them
    as plain signed decimal literals straight off the source line --
    exactly the value the assembler would encode as `dw`, no byte
    packing/unpacking needed since this never touches raw ROM bytes.

    Every row carries its species name as a trailing comment
    (`; WOOPER`), an unambiguous single-match anchor for the one species
    this skeleton's intro needs (confirmed exactly one `; WOOPER$` line
    in the file). extract/util.py's read_asm strips `;` comments before
    a caller ever sees a line, which would remove that anchor, so this
    reads the raw file text directly instead.
    """
    path = os.path.join(pokecrystal, "data/pokemon/cries.asm")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(
        r"mon_cry\s+CRY_\w+,\s*(-?\d+),\s*(-?\d+)\s*;\s*WOOPER\s*$",
        text, re.MULTILINE)
    if not m:
        raise SystemExit("WOOPER row not found in data/pokemon/cries.asm")
    return {"pitch": int(m.group(1)), "length": int(m.group(2))}


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
    wooper_cry = resolve_wooper_cry(pokecrystal)
    data = {
        "romSha1": CRYSTAL_SHA1,
        "symbols": embed_symbols(symbols),
        "newBarkTown": parse_new_bark_town(pokecrystal),
        "fontCharmap": parse_charmap(pokecrystal),
        "charmap": text_charmap(pokecrystal),
        "palettes": resolve_palettes(pokecrystal),
        "cryPitch": wooper_cry["pitch"],
        "cryLength": wooper_cry["length"],
    }
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
