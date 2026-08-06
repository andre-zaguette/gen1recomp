#!/usr/bin/env python3
"""Generate the minimal Crystal-start Gen2 manifest from a pokecrystal checkout.

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
    "PlayersHouse1F_MapAttributes",
    "PlayersHouse1F_MapEvents",
    "PlayersHouse2F_MapAttributes",
    "PlayersHouse2F_MapEvents",
    "ElmsLab_MapAttributes",
    "ElmsLab_MapEvents",
    "PlayersNeighborsHouse_MapAttributes",
    "PlayersNeighborsHouse_MapEvents",
    "ElmsHouse_MapAttributes",
    "ElmsHouse_MapEvents",
    "TilesetJohtoGFX",
    "TilesetJohtoMeta",
    "TilesetJohtoColl",
    "TilesetPlayersHouseGFX",
    "TilesetPlayersHouseMeta",
    "TilesetPlayersHouseColl",
    "TilesetPlayersRoomGFX",
    "TilesetPlayersRoomMeta",
    "TilesetPlayersRoomColl",
    "TilesetLabGFX",
    "TilesetLabMeta",
    "TilesetLabColl",
    "TilesetHouseGFX",
    "TilesetHouseMeta",
    "TilesetHouseColl",
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
    # Title screen graphics + palette (engine/movie/title.asm). One logo
    # image carries the "CRYSTAL VERSION" text baked into its own pixels
    # -- unlike Red/Blue/Yellow, Crystal has no separate ribbon asset (see
    # docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md's
    # "Research already done" section).
    "TitleSuicuneGFX",
    "TitleLogoGFX",
    "TitleCrystalGFX",
    "TitleScreenPalettes",
    # Music_TitleScreen's pulse (Ch1/Ch2) and noise (Ch4) channels, plus
    # every subroutine they sound_call/sound_loop into. Ch3 (wave) is
    # deliberately absent -- out of scope, see the plan's Non-goals.
    # Addresses confirmed against pokecrystal.sym; see the plan's
    # "Research already done" section for the full byte-level decode this
    # is built from.
    "Music_TitleScreen_Ch1",
    "Music_TitleScreen_Ch1.sub1",
    "Music_TitleScreen_Ch1.sub1loop1",
    "Music_TitleScreen_Ch2",
    "Music_TitleScreen_Ch2.sub1",
    # Ch2.sub1 has its own internal loop point, same shape as Ch1.sub1's
    # sub1loop1 (present in REQUIRED_SYMBOLS above) -- confirmed against
    # the real pokecrystal.sym (`3a:7aeb Music_TitleScreen_Ch2.sub1loop1`,
    # 4 bytes into .sub1, right after its note_type+note lead-in) and
    # against the disassembly (audio/music/titlescreen.asm's Ch2 .sub1
    # block: `sound_loop 5, .sub1loop1` targets it). Missing from the
    # original symbol list here was a real gap Task 4 hit: without it,
    # CrystalMusicTranscoder errors decoding Ch2's real ROM bytes with
    # "sound_call/sound_loop target $7AEB has no matching entry in the
    # labels map" the moment it reaches Ch2's own sound_loop instruction.
    "Music_TitleScreen_Ch2.sub1loop1",
    "Music_TitleScreen_Ch4",
    "Music_TitleScreen_Ch4.loop1",
    "Music_TitleScreen_Ch4.sub1",
    "Music_TitleScreen_Ch4.sub2",
    "Music_TitleScreen_Ch4.sub3",
    "Music_TitleScreen_Ch4.sub4",
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


MAP_SPECS = {
    "NEW_BARK_TOWN": {
        "label": "NewBarkTown",
        "asm": "NewBarkTown.asm",
        "tileset": "TILESET_JOHTO",
    },
    "PLAYERS_HOUSE_1F": {
        "label": "PlayersHouse1F",
        "asm": "PlayersHouse1F.asm",
        "tileset": "TILESET_PLAYERS_HOUSE",
    },
    "PLAYERS_HOUSE_2F": {
        "label": "PlayersHouse2F",
        "asm": "PlayersHouse2F.asm",
        "tileset": "TILESET_PLAYERS_ROOM",
    },
    "ELMS_LAB": {
        "label": "ElmsLab",
        "asm": "ElmsLab.asm",
        "tileset": "TILESET_LAB",
    },
    "PLAYERS_NEIGHBORS_HOUSE": {
        "label": "PlayersNeighborsHouse",
        "asm": "PlayersNeighborsHouse.asm",
        "tileset": "TILESET_HOUSE",
    },
    "ELMS_HOUSE": {
        "label": "ElmsHouse",
        "asm": "ElmsHouse.asm",
        "tileset": "TILESET_PLAYERS_HOUSE",
    },
}

START_MAP_CONTENT = {
    "NEW_BARK_TOWN": {
        "signs": [
            {"text": "NEW BARK TOWN\nThe Town Where\nThe Winds of a New\nBeginning Blow"},
            {"text": "{PLAYER}'s House"},
            {"text": "ELM POKéMON LAB"},
            {"text": "ELM'S HOUSE"},
        ],
        "objects": [
            {
                "text": "Wow, your POKéGEAR\nis impressive!\fDid your mom get\nit for you?",
            },
            {
                "text": "Yo, {PLAYER}!\fI hear PROF.ELM\ndiscovered some\vnew POKéMON.",
            },
            {
                "text": "...\fSo this is the\nfamous ELM POKéMON\vLAB...",
            },
        ],
    },
    "PLAYERS_HOUSE_1F": {
        "signs": [
            {"text": "Mom's specialty!\fCINNABAR VOLCANO\nBURGER!"},
            {"text": "The sink is spot-\nless. Mom likes it\nclean."},
            {"text": "Let's see what's\nin the fridge...\fFRESH WATER and\ntasty LEMONADE!"},
            {"text": "There's a movie on\nTV: Stars dot the\fsky as two boys\nride on a train...\fI'd better get\nrolling too!"},
        ],
        "objects": [
            {
                "text": "PROF.ELM is wait-\ning for you.\fHurry up, baby!",
            },
            {
                "text": "Hello, {PLAYER}!\nI'm visiting!\f{PLAYER}, have you\nheard?\fMy daughter is\nadamant about\vbecoming PROF.\nELM's assistant.\fShe really loves\nPOKéMON!",
            },
        ],
    },
    "PLAYERS_HOUSE_2F": {
        "signs": [],
        "objects": [],
    },
    "PLAYERS_NEIGHBORS_HOUSE": {
        "signs": [],
        "objects": [
            {
                "text": "PIKACHU is an\nevolved POKéMON.\fI was amazed by\nPROF.ELM's find-\vings.\fHe's so famous for\nhis research on\vPOKéMON evolution.\f...sigh...\fI wish I could be\na researcher like\nhim...",
            },
            {
                "text": "My daughter is\nadamant about\fbecoming PROF.\nELM's assistant.\fShe really loves\nPOKéMON!\fBut then, so do I!",
            },
        ],
    },
    "ELMS_HOUSE": {
        "signs": [
            {
                "text": "POKéMON. Where do\nthey come from? \fWhere are they\ngoing?\fWhy has no one\never witnessed a\vPOKéMON's birth?\fI want to know! I\nwill dedicate my\vlife to the study\nof POKéMON!\f...\fIt's a part of\nPROF.ELM's re-\vsearch papers.",
            },
        ],
        "objects": [
            {
                "text": "Hi, {PLAYER}! My\nhusband's always\fso busy--I hope\nhe's OK.\fWhen he's caught\nup in his POKéMON\vresearch, he even\nforgets to eat.",
            },
            {
                "text": "When I grow up,\nI'm going to help\nmy dad!\fI'm going to be a\ngreat POKéMON\nprofessor!",
            },
        ],
    },
    "ELMS_LAB": {
        "signs": [
            {"text": "I wonder what this\ndoes?"},
            {"text": "There's an e-mail\nmessage here!"},
            {"text": "PROF.ELM's re-\nsearch journals...\fIt's so complicated..."},
            {"text": "The wrapper is\neasy to tear.\fOpen the package and\neat."},
            {"text": "It's full of all\nsorts of difficult\nbooks."},
            {"text": "It's full of all\nsorts of difficult\nbooks."},
            {"text": "It's full of all\nsorts of difficult\nbooks."},
            {"text": "It's full of all\nsorts of difficult\nbooks."},
        ],
        "objects": [
            {
                "name": "ELMSLAB_ELM",
                "text": "TEXT_ELMSLAB_ELM",
            },
            {
                "name": "ELMSLAB_ELMS_AIDE",
                "text": "TEXT_ELMSLAB_ELMS_AIDE",
            },
            {
                "name": "ELMSLAB_POKE_BALL1",
                "text": "TEXT_ELMSLAB_CYNDAQUIL_POKE_BALL",
            },
            {
                "name": "ELMSLAB_POKE_BALL2",
                "text": "TEXT_ELMSLAB_TOTODILE_POKE_BALL",
            },
            {
                "name": "ELMSLAB_POKE_BALL3",
                "text": "TEXT_ELMSLAB_CHIKORITA_POKE_BALL",
            },
            {
                "name": "ELMSLAB_OFFICER",
                "text": "TEXT_ELMSLAB_OFFICER",
            },
        ],
    },
}

MOVEMENT_MAP = {
    "SPRITEMOVEDATA_WANDER": ("WALK", "ANY_DIR"),
    "SPRITEMOVEDATA_SPINRANDOM_SLOW": ("WALK", "ANY_DIR"),
    "SPRITEMOVEDATA_SPINRANDOM_FAST": ("WALK", "ANY_DIR"),
    "SPRITEMOVEDATA_WALK_UP_DOWN": ("WALK", "UP_DOWN"),
    "SPRITEMOVEDATA_WALK_LEFT_RIGHT": ("WALK", "LEFT_RIGHT"),
    "SPRITEMOVEDATA_STANDING_DOWN": ("STAY", "DOWN"),
    "SPRITEMOVEDATA_STANDING_UP": ("STAY", "UP"),
    "SPRITEMOVEDATA_STANDING_LEFT": ("STAY", "LEFT"),
    "SPRITEMOVEDATA_STANDING_RIGHT": ("STAY", "RIGHT"),
    "SPRITEMOVEDATA_STILL": ("STAY", "NONE"),
}


def parse_map_constants(pokecrystal):
    out = {}
    current_group = 0
    current_number = 0
    path = os.path.join(pokecrystal, "constants/map_constants.asm")
    for _, line in read_asm(path):
        s = line.strip()
        if s.startswith("newgroup"):
            current_group += 1
            current_number = 0
            continue
        if s.startswith("endgroup"):
            current_number = 0
            continue
        m = re.match(r"map_const\s+([A-Z0-9_]+),\s*(\d+),\s*(\d+)", s)
        if not m:
            continue
        current_number += 1
        out[m.group(1)] = {
            "width": int(m.group(2)),
            "height": int(m.group(3)),
            "group": current_group,
            "number": current_number,
        }
    return out


def parse_maps(pokecrystal):
    dims = parse_map_constants(pokecrystal)
    attributes_path = os.path.join(pokecrystal, "data/maps/attributes.asm")
    connection_map = {}
    current = None
    for _, line in read_asm(attributes_path):
        s = line.strip()
        m = re.match(r"map_attributes\s+(\w+),\s+([A-Z0-9_]+),", s)
        if m:
            current = m.group(2)
            connection_map.setdefault(current, {})
            continue
        m = re.match(r"connection\s+(north|south|west|east),\s+(\w+),\s+([A-Z0-9_]+),\s*(-?\d+)", s)
        if m and current:
            connection_map[current][m.group(1)] = {
                "map": m.group(3),
                "offset": int(m.group(4)),
            }
    out = {}
    lookup = {}
    field_for_macro = {
        "warp_event": "warpCount",
        "coord_event": "coordEventCount",
        "bg_event": "bgEventCount",
        "object_event": "objectCount",
    }
    for const_name, spec in MAP_SPECS.items():
        dim = dims.get(const_name)
        if not dim:
            raise SystemExit(f"{const_name} dimensions not found in map_constants.asm")
        counts = {
            "warpCount": 0,
            "coordEventCount": 0,
            "bgEventCount": 0,
            "objectCount": 0,
        }
        in_events = False
        marker = spec["label"] + "_MapEvents:"
        asm_path = os.path.join(pokecrystal, "maps", spec["asm"])
        sign_index = 0
        object_index = 0
        signs = []
        objects = []
        for _, line in read_asm(asm_path):
            s = line.strip()
            if s == marker:
                in_events = True
                continue
            if not in_events:
                continue
            for macro, field in field_for_macro.items():
                if s.startswith(macro + " "):
                    counts[field] += 1
            m = re.match(r"bg_event\s+(-?\d+),\s+(-?\d+),\s+\w+,\s+(\w+)", s)
            if m:
                if sign_index < len(START_MAP_CONTENT[const_name]["signs"]):
                    text = START_MAP_CONTENT[const_name]["signs"][sign_index]["text"]
                    signs.append({
                        "x": int(m.group(1)),
                        "y": int(m.group(2)),
                        "script": m.group(3),
                        "text": text,
                    })
                sign_index += 1
                continue
            m = re.match(
                r"object_event\s+(-?\d+),\s+(-?\d+),\s+([A-Z0-9_]+),\s+([A-Z0-9_]+),\s+"
                r"(-?\d+),\s+(-?\d+),\s+(-?\d+),\s+(-?\d+),\s+([A-Z0-9_]+|\d+),\s+"
                r"([A-Z0-9_]+),\s+(-?\d+),\s+([A-Za-z0-9_]+),\s+([A-Z0-9_]+|-1)",
                s)
            if m:
                if object_index < len(START_MAP_CONTENT[const_name]["objects"]):
                    content = START_MAP_CONTENT[const_name]["objects"][object_index]
                    movement, roam = MOVEMENT_MAP.get(m.group(4), ("STAY", "DOWN"))
                    objects.append({
                        "index": object_index + 1,
                        "name": content.get("name"),
                        "x": int(m.group(1)),
                        "y": int(m.group(2)),
                        "sprite": m.group(3),
                        "movement": movement,
                        "range": roam,
                        "script": m.group(12),
                        "text": content["text"],
                    })
                object_index += 1
                continue
        if sign_index < len(START_MAP_CONTENT[const_name]["signs"]):
            raise SystemExit(
                f"{const_name}: expected {len(START_MAP_CONTENT[const_name]['signs'])} "
                f"sign texts, matched {sign_index}")
        if object_index < len(START_MAP_CONTENT[const_name]["objects"]):
            raise SystemExit(
                f"{const_name}: expected {len(START_MAP_CONTENT[const_name]['objects'])} "
                f"object texts, matched {object_index}")
        out[const_name] = {
            "label": spec["label"],
            "tileset": spec["tileset"],
            "width": dim["width"],
            "height": dim["height"],
            "group": dim["group"],
            "number": dim["number"],
            "connections": connection_map.get(const_name, {}),
            "signs": signs,
            "objects": objects,
            **counts,
        }
        lookup[f"{dim['group']}:{dim['number']}"] = const_name
    return out, lookup


def parse_spawn(pokecrystal):
    path = os.path.join(pokecrystal, "data/maps/spawn_points.asm")
    for _, line in read_asm(path):
        m = re.match(
            r"spawn\s+PLAYERS_HOUSE_2F,\s*(-?\d+),\s*(-?\d+)", line.strip())
        if m:
            return {"map": "PLAYERS_HOUSE_2F", "x": int(m.group(1)), "y": int(m.group(2))}
    raise SystemExit("PLAYERS_HOUSE_2F spawn not found in spawn_points.asm")


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
    maps, map_lookup = parse_maps(pokecrystal)
    data = {
        "romSha1": CRYSTAL_SHA1,
        "symbols": embed_symbols(symbols),
        "maps": maps,
        "mapLookup": map_lookup,
        "spawn": parse_spawn(pokecrystal),
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
