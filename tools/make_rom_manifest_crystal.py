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
    "Route29_MapAttributes",
    "Route29_MapEvents",
    "Route29Route46Gate_MapAttributes",
    "Route29Route46Gate_MapEvents",
    "CherrygroveCity_MapAttributes",
    "CherrygroveCity_MapEvents",
    "CherrygroveMart_MapAttributes",
    "CherrygroveMart_MapEvents",
    "CherrygrovePokecenter1F_MapAttributes",
    "CherrygrovePokecenter1F_MapEvents",
    "CherrygroveGymSpeechHouse_MapAttributes",
    "CherrygroveGymSpeechHouse_MapEvents",
    "GuideGentsHouse_MapAttributes",
    "GuideGentsHouse_MapEvents",
    "CherrygroveEvolutionSpeechHouse_MapAttributes",
    "CherrygroveEvolutionSpeechHouse_MapEvents",
    "MrPokemonsHouse_MapAttributes",
    "MrPokemonsHouse_MapEvents",
    # Route 30 -- data/maps/maps.asm: `map Route30, TILESET_JOHTO, ROUTE,
    # ...` (same TILESET_JOHTO already required below, no new tileset
    # symbols needed). Registering this map is what makes
    # CherrygroveCity's own `connection north, Route30, ROUTE_30, 5` and
    # MrPokemonsHouse's `warp_event ..., ROUTE_30, 2` incoming warps
    # resolve for real instead of silently skipping.
    "Route30_MapAttributes",
    "Route30_MapEvents",
    "Route30BerryHouse_MapAttributes",
    "Route30BerryHouse_MapEvents",
    "Route31_MapAttributes",
    "Route31_MapEvents",
    "Route31VioletGate_MapAttributes",
    "Route31VioletGate_MapEvents",
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
    "TilesetMartGFX",
    "TilesetMartMeta",
    "TilesetMartColl",
    "TilesetPokecenterGFX",
    "TilesetPokecenterMeta",
    "TilesetPokecenterColl",
    # data/maps/maps.asm: `map Route29Route46Gate, TILESET_GATE, GATE, ...`
    # -- this map's real tileset (id 8 in constants/tileset_constants.asm).
    "TilesetGateGFX",
    "TilesetGateMeta",
    "TilesetGateColl",
    # MrPokemonsHouse's tileset (data/maps/maps.asm: `map MrPokemonsHouse,
    # TILESET_FACILITY, INDOOR, ...`) -- data/maps/attributes.asm's own
    # `map_attributes MrPokemonsHouse, MR_POKEMONS_HOUSE, $00` third field
    # is the border block, not the tileset id, same caveat already
    # documented for Route29Route46Gate/CherrygroveCity above.
    "TilesetFacilityGFX",
    "TilesetFacilityMeta",
    "TilesetFacilityColl",
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
    # Music_TitleScreen's pulse (Ch1/Ch2), wave (Ch3), and noise (Ch4)
    # channels, plus every subroutine they sound_call/sound_loop into.
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
    # Ch3 (wave, hw=3) -- confirmed against pokecrystal.sym (`3a:7b01
    # Music_TitleScreen_Ch3`, no .subN/.mainloop children) and against
    # the real disassembly (audio/music/titlescreen.asm:580-894): a flat,
    # single-block channel with no sound_call/sound_loop of its own,
    # ending in a real sound_ret ($FF). Previously omitted from this list
    # on the false premise that Music_TitleScreen had no Ch3 at all --
    # it does; it just never loops, unlike every other song's Ch3.
    "Music_TitleScreen_Ch3",
    "Music_TitleScreen_Ch4",
    "Music_TitleScreen_Ch4.loop1",
    "Music_TitleScreen_Ch4.sub1",
    "Music_TitleScreen_Ch4.sub2",
    "Music_TitleScreen_Ch4.sub3",
    "Music_TitleScreen_Ch4.sub4",
    # Music_ElmsLab's four channels -- all four hardware channels
    # (pulse 1/2, wave, noise), each with only its own .mainloop label and
    # no sub-labels (confirmed against pokecrystal.sym: 3a:604c
    # Music_ElmsLab_Ch1, 3a:6075 .mainloop; 3a:6128 Ch2, 3a:614f
    # .mainloop; 3a:61fd Ch3, 3a:6216 .mainloop; 3a:62b1 Ch4, 3a:62b9
    # .mainloop). The first song to exercise Ch3 (wave, hw=3) decoding --
    # see docs/superpowers/plans/2026-08-06-gen2-crystal-milestone2-music.md's
    # Task 1 (wave-channel support) and Task 2 (this extraction).
    "Music_ElmsLab_Ch1",
    "Music_ElmsLab_Ch1.mainloop",
    "Music_ElmsLab_Ch2",
    "Music_ElmsLab_Ch2.mainloop",
    "Music_ElmsLab_Ch3",
    "Music_ElmsLab_Ch3.mainloop",
    "Music_ElmsLab_Ch4",
    "Music_ElmsLab_Ch4.mainloop",
    # Music_Route29's four channels -- Ch1/Ch3/Ch4 are .mainloop-only; Ch2
    # has one extra .sub1 (confirmed against pokecrystal.sym: 3c:4392 Ch1,
    # 3c:43a5 .mainloop; 3c:444d Ch2, 3c:4458 .mainloop, 3c:44de .sub1;
    # 3c:44fb Ch3, 3c:4504 .mainloop; 3c:45a9 Ch4, 3c:45b0 .mainloop).
    # These were originally committed by hand-patching the JSON manifest
    # directly (Task 4's fix round) without updating this generator --
    # restored here after a later regeneration silently dropped them.
    "Music_Route29",
    "Music_Route29_Ch1",
    "Music_Route29_Ch1.mainloop",
    "Music_Route29_Ch2",
    "Music_Route29_Ch2.mainloop",
    "Music_Route29_Ch2.sub1",
    "Music_Route29_Ch3",
    "Music_Route29_Ch3.mainloop",
    "Music_Route29_Ch4",
    "Music_Route29_Ch4.mainloop",
    # Music_CherrygroveCity's four channels, all .mainloop-only (confirmed
    # against pokecrystal.sym: 3d:5b0f Ch1, 3d:5b26 .mainloop; 3d:5b74 Ch2,
    # 3d:5b87 .mainloop; 3d:5bd8 Ch3, 3d:5be4 .mainloop; 3d:5c48 Ch4,
    # 3d:5c4d .mainloop). Same "hand-patched JSON, never added here"
    # history as Music_Route29 above -- restored together.
    "Music_CherrygroveCity",
    "Music_CherrygroveCity_Ch1",
    "Music_CherrygroveCity_Ch1.mainloop",
    "Music_CherrygroveCity_Ch2",
    "Music_CherrygroveCity_Ch2.mainloop",
    "Music_CherrygroveCity_Ch3",
    "Music_CherrygroveCity_Ch3.mainloop",
    "Music_CherrygroveCity_Ch4",
    "Music_CherrygroveCity_Ch4.mainloop",
    # Music_NewBarkTown's three channels (no Channel 4) -- Ch1 and Ch2 each
    # have two subroutines (.sub1, .sub2); Ch3 is .mainloop-only. Confirmed
    # against pokecrystal.sym: 3a:72dd Music_NewBarkTown_Ch1, 3a:72eb
    # .mainloop, 3a:7349 .sub1, 3a:737c .sub2; 3a:738d Ch2, 3a:7396
    # .mainloop, 3a:73bf .sub1, 3a:73f2 .sub2; 3a:7400 Ch3, 3a:7408
    # .mainloop. Notably absent: Music_NewBarkTown_Ch4 (not an extraction
    # gap; the real ROM song genuinely only uses 3 of the 4 hardware
    # channels). The most-used song in this milestone (5 maps resolve to it).
    "Music_NewBarkTown_Ch1",
    "Music_NewBarkTown_Ch1.mainloop",
    "Music_NewBarkTown_Ch1.sub1",
    "Music_NewBarkTown_Ch1.sub2",
    "Music_NewBarkTown_Ch2",
    "Music_NewBarkTown_Ch2.mainloop",
    "Music_NewBarkTown_Ch2.sub1",
    "Music_NewBarkTown_Ch2.sub2",
    "Music_NewBarkTown_Ch3",
    "Music_NewBarkTown_Ch3.mainloop",
    # Music_Route30's four channels -- Ch1/Ch2/Ch3 are .mainloop-only; Ch4
    # has five subroutines (.sub1 through .sub5, the most of any song in this
    # milestone). Confirmed against pokecrystal.sym: 3b:7c0d Music_Route30_Ch1,
    # 3b:7c2e .mainloop; 3b:7cda Ch2, 3b:7cf6 .mainloop; 3b:7d5f Ch3,
    # 3b:7d79 .mainloop; 3b:7e7a Ch4, 3b:7e84 .mainloop, 3b:7eb8 .sub1,
    # 3b:7ec1 .sub2, 3b:7ecd .sub3, 3b:7ed7 .sub4, 3b:7ee1 .sub5.
    "Music_Route30",
    "Music_Route30_Ch1",
    "Music_Route30_Ch1.mainloop",
    "Music_Route30_Ch2",
    "Music_Route30_Ch2.mainloop",
    "Music_Route30_Ch3",
    "Music_Route30_Ch3.mainloop",
    "Music_Route30_Ch4",
    "Music_Route30_Ch4.mainloop",
    "Music_Route30_Ch4.sub1",
    "Music_Route30_Ch4.sub2",
    "Music_Route30_Ch4.sub3",
    "Music_Route30_Ch4.sub4",
    "Music_Route30_Ch4.sub5",
    # SFX plan (docs/superpowers/plans/2026-08-08-gen2-crystal-sfx.md):
    # the 14 real Sfx_*_ChN channel symbols behind this project's own
    # Collision/Cut/Denied/Ball_Poof/Ledge_Jump/Withdraw_Deposit/
    # Go_Inside/Get_Key_Item/Intro_Whoosh names -- see the plan's
    # "Research already done" section for the name->constant mapping.
    "Sfx_Bump_Ch5",             # 3c:5d6f -- Collision
    "Sfx_Cut_Ch8",              # 3c:60c3 -- Cut
    "Sfx_Wrong_Ch5",            # 3c:5f05 -- Denied
    "Sfx_Wrong_Ch6",            # 3c:5f1c -- Denied
    "Sfx_BallPoof_Ch5",         # 3c:5ff4 -- Ball_Poof
    "Sfx_BallPoof_Ch8",         # 3c:5fff -- Ball_Poof
    "Sfx_JumpOverLedge_Ch5",    # 3c:5ebc -- Ledge_Jump
    "Sfx_Transaction_Ch5",      # 3c:5d55 -- Withdraw_Deposit
    "Sfx_Transaction_Ch6",      # 3c:5d60 -- Withdraw_Deposit
    "Sfx_EnterDoor_Ch8",        # 3c:5d08 -- Go_Inside
    "Sfx_KeyItem_Ch5",          # 3c:4b92 -- Get_Key_Item
    "Sfx_KeyItem_Ch6",          # 3c:4ba8 -- Get_Key_Item
    "Sfx_KeyItem_Ch7",          # 3c:4bb8 -- Get_Key_Item (Ch8 deliberately
                                # excluded -- see the plan's "Research
                                # already done" section)
    "Sfx_IntroWhoosh_Ch8",      # 3c:656c -- Intro_Whoosh
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
        "music": "Music_NewBarkTown",  # maps.asm:494, MUSIC_NEW_BARK_TOWN
    },
    "PLAYERS_HOUSE_1F": {
        "label": "PlayersHouse1F",
        "asm": "PlayersHouse1F.asm",
        "tileset": "TILESET_PLAYERS_HOUSE",
        "music": "Music_NewBarkTown",  # maps.asm:496, MUSIC_NEW_BARK_TOWN
    },
    "PLAYERS_HOUSE_2F": {
        "label": "PlayersHouse2F",
        "asm": "PlayersHouse2F.asm",
        "tileset": "TILESET_PLAYERS_ROOM",
        "music": "Music_NewBarkTown",  # maps.asm:497, MUSIC_NEW_BARK_TOWN
    },
    "ELMS_LAB": {
        "label": "ElmsLab",
        "asm": "ElmsLab.asm",
        "tileset": "TILESET_LAB",
        "music": "Music_ElmsLab",  # maps.asm:495, MUSIC_PROF_ELM
    },
    "PLAYERS_NEIGHBORS_HOUSE": {
        "label": "PlayersNeighborsHouse",
        "asm": "PlayersNeighborsHouse.asm",
        "tileset": "TILESET_HOUSE",
        "music": "Music_NewBarkTown",  # maps.asm:498, MUSIC_NEW_BARK_TOWN
    },
    "ELMS_HOUSE": {
        "label": "ElmsHouse",
        "asm": "ElmsHouse.asm",
        "tileset": "TILESET_PLAYERS_HOUSE",
        "music": "Music_NewBarkTown",  # maps.asm:499, MUSIC_NEW_BARK_TOWN
    },
    "ROUTE_29": {
        "label": "Route29",
        "asm": "Route29.asm",
        # data/maps/attributes.asm: `map_attributes Route29, ROUTE_29, $05`
        # -- same tileset id as NewBarkTown's own `$05`.
        "tileset": "TILESET_JOHTO",
        "music": "Music_Route29",  # maps.asm:493, MUSIC_ROUTE_29
    },
    "ROUTE_29_ROUTE_46_GATE": {
        "label": "Route29Route46Gate",
        "asm": "Route29Route46Gate.asm",
        # data/maps/maps.asm line 503: `map Route29Route46Gate, TILESET_GATE,
        # GATE, ...`. attributes.asm's `map_attributes` third field ($00) is
        # the border block, not the tileset id -- the real tileset comes from
        # the `map` macro's 2nd field in maps.asm.
        "tileset": "TILESET_GATE",
        "music": "Music_Route29",  # maps.asm:503, MUSIC_ROUTE_29
    },
    "CHERRYGROVE_CITY": {
        "label": "CherrygroveCity",
        "asm": "CherrygroveCity.asm",
        # data/maps/maps.asm: `map CherrygroveCity, TILESET_JOHTO, TOWN, ...`
        # -- same tileset as NewBarkTown/Route29 (already required below).
        # attributes.asm's own `map_attributes CherrygroveCity,
        # CHERRYGROVE_CITY, $35` third field is the border block, not the
        # tileset id, same caveat as Route29Route46Gate above.
        "tileset": "TILESET_JOHTO",
        "music": "Music_CherrygroveCity",  # maps.asm:529, MUSIC_CHERRYGROVE_CITY
    },
    "CHERRYGROVE_MART": {
        "label": "CherrygroveMart",
        "asm": "CherrygroveMart.asm",
        "tileset": "TILESET_MART",
        "music": "Music_CherrygroveCity",  # maps.asm:530, MUSIC_CHERRYGROVE_CITY
    },
    "CHERRYGROVE_POKECENTER_1F": {
        "label": "CherrygrovePokecenter1F",
        "asm": "CherrygrovePokecenter1F.asm",
        "tileset": "TILESET_POKECENTER",
        "music": "Music_PokemonCenter",  # maps.asm:531, MUSIC_POKEMON_CENTER
    },
    "CHERRYGROVE_GYM_SPEECH_HOUSE": {
        "label": "CherrygroveGymSpeechHouse",
        "asm": "CherrygroveGymSpeechHouse.asm",
        "tileset": "TILESET_HOUSE",
        "music": "Music_CherrygroveCity",  # maps.asm:532, MUSIC_CHERRYGROVE_CITY
    },
    "GUIDE_GENTS_HOUSE": {
        "label": "GuideGentsHouse",
        "asm": "GuideGentsHouse.asm",
        "tileset": "TILESET_HOUSE",
        "music": "Music_CherrygroveCity",  # maps.asm:533, MUSIC_CHERRYGROVE_CITY
    },
    "CHERRYGROVE_EVOLUTION_SPEECH_HOUSE": {
        "label": "CherrygroveEvolutionSpeechHouse",
        "asm": "CherrygroveEvolutionSpeechHouse.asm",
        "tileset": "TILESET_HOUSE",
        "music": "Music_CherrygroveCity",  # maps.asm:534, MUSIC_CHERRYGROVE_CITY
    },
    "MR_POKEMONS_HOUSE": {
        "label": "MrPokemonsHouse",
        "asm": "MrPokemonsHouse.asm",
        # data/maps/maps.asm: `map MrPokemonsHouse, TILESET_FACILITY,
        # INDOOR, LANDMARK_ROUTE_30, MUSIC_CHERRYGROVE_CITY, FALSE,
        # PALETTE_DAY, FISHGROUP_SHORE` -- 2nd field is the real tileset id
        # (`map` macro), NOT attributes.asm's `map_attributes` 3rd field
        # (border block, $00 here) -- the exact caveat Route29Route46Gate's
        # own registration task got wrong the first time.
        "tileset": "TILESET_FACILITY",
        "music": "Music_CherrygroveCity",  # maps.asm:536, MUSIC_CHERRYGROVE_CITY
    },
    "ROUTE_30": {
        "label": "Route30",
        "asm": "Route30.asm",
        # data/maps/maps.asm line 527: `map Route30, TILESET_JOHTO, ROUTE,
        # LANDMARK_ROUTE_30, MUSIC_ROUTE_30, FALSE, PALETTE_AUTO,
        # FISHGROUP_POND` -- 2nd field is the real tileset id (`map`
        # macro), same TILESET_JOHTO as NewBarkTown/Route29/CherrygroveCity
        # (already required above). data/maps/attributes.asm's own
        # `map_attributes Route30, ROUTE_30, $05` third field is the
        # border block, not the tileset id -- the exact caveat
        # Route29Route46Gate's own registration task got wrong the first
        # time, re-confirmed correctly here via maps.asm directly.
        "tileset": "TILESET_JOHTO",
        "music": "Music_Route30",  # maps.asm:527, MUSIC_ROUTE_30
    },
    "ROUTE_30_BERRY_HOUSE": {
        "label": "Route30BerryHouse",
        "asm": "Route30BerryHouse.asm",
        "tileset": "TILESET_HOUSE",
        "music": "Music_CherrygroveCity",  # maps.asm:535, MUSIC_CHERRYGROVE_CITY
    },
    "ROUTE_31": {
        "label": "Route31",
        "asm": "Route31.asm",
        "tileset": "TILESET_JOHTO",
        "music": "Music_Route30",  # maps.asm:528, MUSIC_ROUTE_30
    },
    "ROUTE_31_VIOLET_GATE": {
        "label": "Route31VioletGate",
        "asm": "Route31VioletGate.asm",
        "tileset": "TILESET_GATE",
        "music": "Music_Route30",  # maps.asm:537, MUSIC_ROUTE_30
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
                "name": "NEWBARKTOWN_TEACHER",
                "text": "TEXT_NEWBARKTOWN_TEACHER",
            },
            {
                "name": "NEWBARKTOWN_FISHER",
                "text": "TEXT_NEWBARKTOWN_FISHER",
            },
            {
                # ROM: object_event's trailing flag is
                # EVENT_RIVAL_NEW_BARK_TOWN. Unlike ELMSLAB_OFFICER's flag,
                # this one is NOT in InitializeEventsScript's force-set
                # list, so a fresh save reads it clear -- visible, by the
                # same SET=hidden convention -- from the very start of the
                # game. MrPokemonsHouse.asm's errand-return script (setevent
                # EVENT_RIVAL_NEW_BARK_TOWN, not built in this project) is
                # what later hides him here once he crosses paths with the
                # player elsewhere instead, so for now he simply never
                # leaves.
                "name": "NEWBARKTOWN_RIVAL",
                "text": "TEXT_NEWBARKTOWN_RIVAL",
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
                # ROM: object_event 7,4, h1/h2 -1/-1 ("always"), flag
                # EVENT_PLAYERS_HOUSE_MOM_1. The one Mom instance this
                # project renders. Two more ROM object_events place a
                # second Mom sprite for MORN/DAY/NITE (flag
                # EVENT_PLAYERS_HOUSE_MOM_2) -- parse_maps's object_event
                # regex requires numeric hour fields and does not match
                # those (h2 is a MORN/DAY/NITE constant there, not a
                # number), so they never reach this content list at all.
                # This project has no per-object time-of-day gate anyway
                # (unlike PaletteFX.timeOfDay(), which only rebakes
                # colors), so nothing is lost by that gap for now.
                "name": "PLAYERSHOUSE1F_MOM1",
                "text": "TEXT_PLAYERSHOUSE1F_MOM1",
            },
            {
                # ROM: object_event's flag is EVENT_PLAYERS_HOUSE_1F_NEIGHBOR,
                # which InitializeEventsScript does NOT force-set (unlike
                # ELMSLAB_OFFICER/NEWBARKTOWN_RIVAL/
                # PLAYERSNEIGHBORSHOUSE_POKEFAN_F below), so on a fresh
                # save it reads clear -- visible by the same SET=hidden
                # convention -- confirmed by MrPokemonsHouse.asm pairing
                # `setevent EVENT_PLAYERS_HOUSE_1F_NEIGHBOR` with
                # `clearevent EVENT_PLAYERS_NEIGHBORS_HOUSE_NEIGHBOR`: it's
                # the same neighbor lady, visiting here until that errand
                # (not built yet), then home in
                # PLAYERSNEIGHBORSHOUSE_POKEFAN_F's own house instead.
                "name": "PLAYERSHOUSE1F_POKEFAN_F",
                "text": "TEXT_PLAYERSHOUSE1F_POKEFAN_F",
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
                "name": "PLAYERSNEIGHBORSHOUSE_COOLTRAINER_F",
                "text": "TEXT_PLAYERSNEIGHBORSHOUSE_COOLTRAINER_F",
            },
            {
                # ROM: flag EVENT_PLAYERS_NEIGHBORS_HOUSE_NEIGHBOR IS in
                # InitializeEventsScript's force-set list (SET=hidden), so
                # she starts absent from her own house -- she's the
                # PLAYERSHOUSE1F_POKEFAN_F visiting the player's house
                # instead, until an errand (not built yet) swaps her back.
                "name": "PLAYERSNEIGHBORSHOUSE_POKEFAN_F",
                "text": "TEXT_PLAYERSNEIGHBORSHOUSE_POKEFAN_F",
                "hidden": True,
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
                "name": "ELMSHOUSE_ELMS_WIFE",
                "text": "TEXT_ELMSHOUSE_ELMS_WIFE",
            },
            {
                "name": "ELMSHOUSE_ELMS_SON",
                "text": "TEXT_ELMSHOUSE_ELMS_SON",
            },
        ],
    },
    "ELMS_LAB": {
        # "text" here is just documentation of the ROM source now (see the
        # bg_event loop below: a sign's real "text" is its own "script"
        # label, the same fix objects already got) -- this list only needs
        # to be as long as ElmsLab.asm's real bg_event count (16) so every
        # one of them survives into the manifest, in the same order as
        # ElmsLab_MapEvents' def_bg_events.
        "signs": [
            {"text": "ElmsLabHealingMachine: I wonder what this\\ndoes?"},
            {"text": "ElmsLabBookshelf (6,1): It's full of\\ndifficult books."},
            {"text": "ElmsLabBookshelf (7,1)"},
            {"text": "ElmsLabBookshelf (8,1)"},
            {"text": "ElmsLabBookshelf (9,1)"},
            {"text": "ElmsLabTravelTip1: Press START to\\nopen the MENU."},
            {"text": "ElmsLabTravelTip2: Record your trip\\nwith SAVE!"},
            {"text": "ElmsLabTravelTip3: Open your PACK..."},
            {"text": "ElmsLabTravelTip4: Check your POKéMON moves..."},
            {"text": "ElmsLabBookshelf (6,7)"},
            {"text": "ElmsLabBookshelf (7,7)"},
            {"text": "ElmsLabBookshelf (8,7)"},
            {"text": "ElmsLabBookshelf (9,7)"},
            {"text": "ElmsLabTrashcan: The wrapper from\\nthe snack PROF.ELM..."},
            {"text": "ElmsLabWindow: The window's open."},
            {"text": "ElmsLabPC: OBSERVATIONS ON\\nPOKéMON EVOLUTION"},
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
                # ROM: object_event's trailing flag is EVENT_COP_IN_ELMS_LAB,
                # which InitializeEventsScript (engine/events/std_scripts.asm,
                # run once from the player's bedroom on a new game) sets
                # before the player ever reaches the lab -- and a set flag
                # hides the object (macros/scripts/maps.asm's object_event
                # doc: "-1 to always appear", confirmed against
                # MrPokemonsHouse.asm's `clearevent EVENT_COP_IN_ELMS_LAB`,
                # which is what makes him visible, after the rival-theft
                # phone call). That reveal path (Mr. Pokémon's house, the
                # theft phone call) doesn't exist in this project yet, so
                # for now the officer just stays hidden rather than always
                # showing with no trigger at all.
                "hidden": True,
            },
        ],
    },
    "ROUTE_29": {
        "signs": [
            {"text": "Route29Sign1"},
            {"text": "Route29Sign2"},
        ],
        "objects": [
            {
                # ROM: CatchingTutorialDudeScript's own gate,
                # EVENT_GAVE_MYSTERY_EGG_TO_ELM, is part of the mystery-egg
                # chain this project hasn't built, so the only branch that
                # can ever be reached right now (CatchingTutorialBoxFullText)
                # is the only one ported.
                "name": "ROUTE29_COOLTRAINER_M1",
                "text": "TEXT_ROUTE29_COOLTRAINER_M1",
            },
            {
                "name": "ROUTE29_YOUNGSTER",
                "text": "TEXT_ROUTE29_YOUNGSTER",
            },
            {
                "name": "ROUTE29_TEACHER1",
                "text": "TEXT_ROUTE29_TEACHER1",
            },
            {
                # ROM: Route29FruitTree (`fruittree FRUITTREE_ROUTE_29`) --
                # the once-a-day shake-for-an-item mechanic doesn't exist in
                # this project, so this stays hidden rather than standing
                # there doing nothing on interact.
                "name": "ROUTE29_FRUIT_TREE",
                "text": "ROUTE29_FRUIT_TREE",
                "hidden": True,
            },
            {
                "name": "ROUTE29_FISHER",
                "text": "TEXT_ROUTE29_FISHER",
            },
            {
                # ROM: Route29CooltrainerMScript branches on checktime
                # DAY/NITE, both leading to a "waiting for POKéMON" line --
                # no time-of-day script command exists yet (same gap noted
                # elsewhere, e.g. crystal_players_house_1f.lua), so this
                # always shows the DAY branch's text.
                "name": "ROUTE29_COOLTRAINER_M2",
                "text": "TEXT_ROUTE29_COOLTRAINER_M2",
            },
            {
                # ROM: TuscanyScript -- gated on VAR_WEEKDAY == TUESDAY
                # (Route29TuscanyCallback also disappears her every other
                # day), the same day-of-week gap as above. Stays hidden
                # rather than showing every day of the week.
                "name": "ROUTE29_TUSCANY",
                "text": "ROUTE29_TUSCANY",
                "hidden": True,
            },
            {
                # ROM: Route29Potion (`itemball POTION`). Its own trailing
                # flag, EVENT_ROUTE_29_POTION, is not in
                # InitializeEventsScript's force-set list, so it starts
                # clear -- visible -- and the talk script sets it after
                # pickup to hide the ball for good, the same SET=hidden
                # convention as every other flagged object in this file.
                "name": "ROUTE29_POKE_BALL",
                "text": "TEXT_ROUTE29_POTION",
            },
        ],
    },
    "ROUTE_29_ROUTE_46_GATE": {
        "signs": [],
        "objects": [
            {
                "name": "ROUTE29ROUTE46GATE_OFFICER",
                "text": "TEXT_ROUTE29ROUTE46GATE_OFFICER",
            },
            {
                "name": "ROUTE29ROUTE46GATE_YOUNGSTER",
                "text": "TEXT_ROUTE29ROUTE46GATE_YOUNGSTER",
            },
        ],
    },
    "CHERRYGROVE_CITY": {
        "signs": [
            {"text": "CherrygroveCitySign"},
            {"text": "GuideGentsHouseSign"},
            # jumpstd MartSignScript / PokecenterSignScript -- the
            # generic std_text.asm sign text shared by every town's
            # mart/pokecenter sign, not map-specific flavor text.
            {"text": "CherrygroveCityMartSign"},
            {"text": "CherrygroveCityPokecenterSign"},
        ],
        "objects": [
            {
                # ROM: CherrygroveCityGuideGent (object_const_def order:
                # CHERRYGROVECITY_GRAMPS). A `yesorno`-gated guided tour:
                # `follow`+multi-stop `applymovement` walks the player
                # around town narrating the PokéCenter/Mart/Route 30/sea,
                # then `verbosegiveitem`-equivalents a MAP CARD into the
                # player's PokéGear and sets the engine flag ENGINE_MAP_CARD.
                # None of the systems this depends on exist here: no
                # PokéGear/Town Map item system at all (checked -- no
                # "MAP_CARD" or PokéGear-map reference anywhere in src/,
                # unlike ENGINE_POKEGEAR itself which crystal_players_
                # house_1f.lua already sets), and no "one NPC leads, player
                # follows" scripted-walk primitive (src/script/Commands.lua
                # has move_npc/move_npc_to/walk_npc/move_player, but nothing
                # shaped like the ROM's `follow` opcode). Stays hidden
                # rather than faking a tour that can't pay off with a real
                # map card. His trailing flag, EVENT_GUIDE_GENT_IN_HIS_HOUSE,
                # is irrelevant here since "hidden" overrides ROM flag state
                # entirely, same convention as ROUTE29_FRUIT_TREE/TUSCANY.
                "name": "CHERRYGROVECITY_GRAMPS",
                "text": "CHERRYGROVECITY_GRAMPS",
                "hidden": True,
            },
            {
                # ROM: SPRITE_RIVAL, object index CHERRYGROVECITY_RIVAL,
                # triggered by CherrygroveRivalSceneNorth/South
                # (def_coord_events at 33,6 / 33,7), both gated on
                # `SCENE_CHERRYGROVECITY_MEET_RIVAL` (set elsewhere by
                # MrPokemonsHouse.asm's errand-return script, which this
                # project hasn't built) and EVENT_RIVAL_CHERRYGROVE_CITY.
                # This engine has no scene-state mechanism at all (see
                # crystal_elms_lab.lua's onEnter/onStep comments -- same gap
                # noted there) and no coord_event mechanism either. Even if
                # both existed, the actual rival fight needs real Crystal
                # RIVAL1 trainer party data keyed to which starter the
                # player chose vs. which the rival counter-picked
                # (RIVAL1_1_TOTODILE/_CHIKORITA/_CYNDAQUIL) -- src/script/
                # Commands.lua's rival_battle is Gen1/Yellow-shaped only
                # (checks GameVersion.isYellow(), falls back to Gen1's
                # EVENT_CHOSE_SQUIRTLE/BULBASAUR offsets and RBY trainer
                # tables otherwise -- no isCrystal() branch and no Crystal
                # rival-party data exists to feed one). Stays hidden.
                "name": "CHERRYGROVECITY_RIVAL",
                "text": "CHERRYGROVECITY_RIVAL",
                "hidden": True,
            },
            {
                # ROM: CherrygroveTeacherScript. Both branches (checkflag
                # ENGINE_MAP_CARD) are ported even though only the "no map
                # card" one is currently reachable -- ENGINE_MAP_CARD is
                # only ever set by the Guide Gent above, which stays
                # hidden -- same "port both branches even though one is
                # dead for now" precedent as ROUTE29_COOLTRAINER_M1's
                # sibling entries.
                "name": "CHERRYGROVECITY_TEACHER",
                "text": "TEXT_CHERRYGROVECITY_TEACHER",
            },
            {
                # ROM: CherrygroveYoungsterScript, checkflag ENGINE_POKEDEX
                # -- not yet set anywhere in this project's Crystal flow
                # (only Gen1's EVENT_GOT_POKEDEX exists), so only the "no
                # pokedex" branch is currently reachable; both ported.
                "name": "CHERRYGROVECITY_YOUNGSTER",
                "text": "TEXT_CHERRYGROVECITY_YOUNGSTER",
            },
            {
                # ROM: MysticWaterGuy. Straightforward one-time item gift
                # (MYSTIC_WATER) gated on EVENT_GOT_MYSTIC_WATER_IN_
                # CHERRYGROVE, same give_item/set_flag shape as Route 29's
                # Potion ball -- no unbuilt system involved.
                "name": "CHERRYGROVECITY_FISHER",
                "text": "TEXT_CHERRYGROVECITY_FISHER",
            },
        ],
    },
    "CHERRYGROVE_MART": {
        "signs": [],
        "objects": [
            {
                "name": "CHERRYGROVEMART_CLERK",
                "text": "TEXT_CHERRYGROVEMART_CLERK",
            },
            {
                "name": "CHERRYGROVEMART_COOLTRAINER_M",
                "text": "TEXT_CHERRYGROVEMART_COOLTRAINER_M",
            },
            {
                "name": "CHERRYGROVEMART_YOUNGSTER",
                "text": "TEXT_CHERRYGROVEMART_YOUNGSTER",
            },
        ],
    },
    "CHERRYGROVE_POKECENTER_1F": {
        "signs": [],
        "objects": [
            {
                "name": "CHERRYGROVEPOKECENTER1F_NURSE",
                "text": "TEXT_CHERRYGROVEPOKECENTER1F_NURSE",
            },
            {
                "name": "CHERRYGROVEPOKECENTER1F_FISHER",
                "text": "TEXT_CHERRYGROVEPOKECENTER1F_FISHER",
            },
            {
                "name": "CHERRYGROVEPOKECENTER1F_GENTLEMAN",
                "text": "TEXT_CHERRYGROVEPOKECENTER1F_GENTLEMAN",
            },
            {
                "name": "CHERRYGROVEPOKECENTER1F_TEACHER",
                "text": "TEXT_CHERRYGROVEPOKECENTER1F_TEACHER",
            },
        ],
    },
    "CHERRYGROVE_GYM_SPEECH_HOUSE": {
        "signs": [
            {"text": "CherrygroveGymSpeechHouseBookshelf"},
            {"text": "CherrygroveGymSpeechHouseBookshelf"},
        ],
        "objects": [
            {
                "name": "CHERRYGROVEGYMSPEECHHOUSE_POKEFAN_M",
                "text": "TEXT_CHERRYGROVEGYMSPEECHHOUSE_POKEFAN_M",
            },
            {
                "name": "CHERRYGROVEGYMSPEECHHOUSE_BUG_CATCHER",
                "text": "TEXT_CHERRYGROVEGYMSPEECHHOUSE_BUG_CATCHER",
            },
        ],
    },
    "GUIDE_GENTS_HOUSE": {
        "signs": [
            {"text": "GuideGentsHouseBookshelf"},
            {"text": "GuideGentsHouseBookshelf"},
        ],
        "objects": [
            {
                "name": "GUIDEGENTSHOUSE_GRAMPS",
                "text": "TEXT_GUIDEGENTSHOUSE_GRAMPS",
            },
        ],
    },
    "CHERRYGROVE_EVOLUTION_SPEECH_HOUSE": {
        "signs": [
            {"text": "CherrygroveEvolutionSpeechHouseBookshelf"},
            {"text": "CherrygroveEvolutionSpeechHouseBookshelf"},
        ],
        "objects": [
            {
                "name": "CHERRYGROVEEVOLUTIONSPEECHHOUSE_LASS",
                "text": "TEXT_CHERRYGROVEEVOLUTIONSPEECHHOUSE_LASS",
            },
            {
                "name": "CHERRYGROVEEVOLUTIONSPEECHHOUSE_YOUNGSTER",
                "text": "TEXT_CHERRYGROVEEVOLUTIONSPEECHHOUSE_YOUNGSTER",
            },
        ],
    },
    "MR_POKEMONS_HOUSE": {
        # Sign "text" values below are pure documentation (see the bg_event
        # loop's own comment above ElmsLab's entry) -- only the count (5,
        # matching MrPokemonsHouse_MapEvents' real def_bg_events) matters.
        "signs": [
            {"text": "MrPokemonsHouse_ForeignMagazines (0,1): It's packed with\\nforeign magazines."},
            {"text": "MrPokemonsHouse_ForeignMagazines (1,1)"},
            {"text": "MrPokemonsHouse_BrokenComputer (6,1): It's a big com-\\nputer. Hmm. It's broken."},
            {"text": "MrPokemonsHouse_BrokenComputer (7,1)"},
            {"text": "MrPokemonsHouse_StrangeCoins (6,4): A whole pile of\\nstrange coins!"},
        ],
        "objects": [
            {
                # ROM: MrPokemonsHouse_MrPokemonScript. Trailing object_event
                # flag is -1 ("always appear") -- Mr. Pokémon is visible
                # from the moment the map loads, for the whole game.
                "name": "MRPOKEMONSHOUSE_GENTLEMAN",
                "text": "TEXT_MRPOKEMONSHOUSE_GENTLEMAN",
            },
            {
                # ROM: object_event's trailing flag is
                # EVENT_MR_POKEMONS_HOUSE_OAK, which is never setevent'd or
                # clearevent'd anywhere else in the whole disassembly
                # (confirmed: the only other hit is its own `const` line in
                # constants/event_flags.asm) and is NOT in
                # InitializeEventsScript's force-set list either -- so it
                # reads clear on every save, meaning OAK (SPRITE_OAK, object
                # index 2 per MrPokemonsHouse.asm's object_const_def) is
                # visible from the very start too, same as the Gentleman.
                # This matches the real game: PROF.OAK is standing in this
                # room together with MR.POKéMON before the player ever
                # arrives -- the errand-completion script
                # (MrPokemonsHouse_OakScript) walks him over, gives the
                # PokéDex, heals the party, then `disappear`s him for good;
                # his own object flag is never touched by any of that (the
                # ROM hides him with the same explicit-disappear mechanism
                # this project's hide_object already models, not a flag
                # read), so he stays a plain always-visible object here too
                # until data/scripts/crystal_mr_pokemons_house.lua's
                # completion script calls hide_object on him directly.
                "name": "MRPOKEMONSHOUSE_OAK",
                "text": "TEXT_MRPOKEMONSHOUSE_OAK",
            },
        ],
    },
    "ROUTE_30": {
        "signs": [
            {"text": "Route30Sign"},
            {"text": "MrPokemonsHouseDirectionsSign"},
            {"text": "MrPokemonsHouseSign"},
            {"text": "Route30TrainerTips"},
            # BGEVENT_ITEM, not BGEVENT_READ -- a hidden-item bg_event, not
            # a real sign. parse_maps's bg_event loop below doesn't
            # distinguish the two (it only counts/labels bg_events
            # generically), so this still needs a slot here to keep
            # bgEventCount's real ROM count (5) accurate; see
            # crystal_route30.lua for how it's actually scripted
            # (give_item + set_flag, same shape as Route 29's Potion ball,
            # not a plain show_text sign).
            {"text": "Route30HiddenPotion"},
        ],
        "objects": [
            {
                # ROM: YoungsterJoey_ImportantBattleScript, object_const_def
                # name ROUTE30_YOUNGSTER1. Its trailing object_event flag is
                # EVENT_ROUTE_30_BATTLE, only ever setevent'd by
                # ElmsLab.asm's (unbuilt) errand-completion scene -- this is
                # NOT one of the brief's stated "5 blocked objects" (it's
                # OBJECTTYPE_SCRIPT, not OBJECTTYPE_TRAINER, and never calls
                # `startbattle`), but reading its script body confirms it's
                # purely a scripted, non-interactive "watch Joey and Mikey's
                # Rattata fight" cutscene (applymovement + playsound only)
                # gated on the same unbuilt scene-state flag as
                # CHERRYGROVECITY_RIVAL. Stays hidden alongside its two
                # MONSTER companions below rather than standing there inert
                # (this project has no per-object ROM-flag visibility gate
                # at all -- see CHERRYGROVECITY_GRAMPS/_RIVAL precedent --
                # so leaving this unhidden would make it a normal always
                # -visible NPC with no working interaction).
                "name": "ROUTE30_YOUNGSTER1",
                "text": "ROUTE30_YOUNGSTER1",
                "hidden": True,
            },
            {
                # ROM: TrainerYoungsterJoey. Real OBJECTTYPE_TRAINER --
                # blocked on both gaps confirmed this session: no
                # OBJECTTYPE_TRAINER sight-triggered auto-battle wiring in
                # src/world/OverworldController.lua, and no Gen2
                # trainer-party data extracted at all (RomExtractorGen2.lua
                # has no trainer/party table). Not attempting either as
                # part of this task -- future work once the ROM first needs
                # it, per this plan's own sequencing principle.
                "name": "ROUTE30_YOUNGSTER2",
                "text": "ROUTE30_YOUNGSTER2",
                "hidden": True,
            },
            {
                # ROM: TrainerYoungsterMikey. Same trainer-battle gap.
                "name": "ROUTE30_YOUNGSTER3",
                "text": "ROUTE30_YOUNGSTER3",
                "hidden": True,
            },
            {
                # ROM: TrainerBugCatcherDon. Same trainer-battle gap.
                "name": "ROUTE30_BUG_CATCHER",
                "text": "ROUTE30_BUG_CATCHER",
                "hidden": True,
            },
            {
                # ROM: Route30YoungsterScript. OBJECTTYPE_SCRIPT, not a
                # trainer -- `faceplayer`/`opentext`/checkevent
                # EVENT_GAVE_MYSTERY_EGG_TO_ELM/writetext/closetext. That
                # flag is never set anywhere in this project (the mystery-
                # egg-to-Elm handoff hasn't been built -- same gap Task 5
                # confirmed for Route 29's own catch tutorial), so only the
                # "directions to Mr. Pokémon's house" branch is currently
                # reachable; both branches ported anyway, matching the
                # ROUTE29_COOLTRAINER_M1/CHERRYGROVECITY_TEACHER precedent
                # of porting dead branches too.
                "name": "ROUTE30_YOUNGSTER4",
                "text": "TEXT_ROUTE30_YOUNGSTER",
            },
            {
                # ROM: ObjectEvent (SPRITE_MONSTER, a Rattata stand-in),
                # one of YoungsterJoey_ImportantBattleScript's pair --
                # EVENT_ROUTE_30_BATTLE-gated, same unbuilt scene-state gap
                # as ROUTE30_YOUNGSTER1 above. This is the brief's own
                # explicitly-anticipated deferral.
                "name": "ROUTE30_MONSTER1",
                "text": "ROUTE30_MONSTER1",
                "hidden": True,
            },
            {
                # ROM: ObjectEvent, the second SPRITE_MONSTER of the pair.
                "name": "ROUTE30_MONSTER2",
                "text": "ROUTE30_MONSTER2",
                "hidden": True,
            },
            {
                # ROM: Route30FruitTree1 (`fruittree FRUITTREE_ROUTE_30_1`)
                # -- same "no shake-a-tree mechanic exists" gap
                # crystal_route29.lua's ROUTE29_FRUIT_TREE already
                # documented; matching that precedent rather than inventing
                # new fruit-tree behavior here.
                "name": "ROUTE30_FRUIT_TREE1",
                "text": "ROUTE30_FRUIT_TREE1",
                "hidden": True,
            },
            {
                # ROM: Route30FruitTree2 (`fruittree FRUITTREE_ROUTE_30_2`).
                # Same gap as ROUTE30_FRUIT_TREE1.
                "name": "ROUTE30_FRUIT_TREE2",
                "text": "ROUTE30_FRUIT_TREE2",
                "hidden": True,
            },
            {
                # ROM: Route30CooltrainerFScript -- `jumptextfaceplayer`,
                # no unbuilt system involved.
                "name": "ROUTE30_COOLTRAINER_F",
                "text": "TEXT_ROUTE30_COOLTRAINER_F",
            },
            {
                # ROM: Route30Antidote (`itemball ANTIDOTE`). Trailing flag
                # EVENT_ROUTE_30_ANTIDOTE is not in InitializeEventsScript's
                # force-set list, so it starts clear -- visible -- same
                # give_item/set_flag shape as Route 29's Potion ball.
                "name": "ROUTE30_POKE_BALL",
                "text": "TEXT_ROUTE30_ANTIDOTE",
            },
        ],
    },
    "ROUTE_30_BERRY_HOUSE": {
        "signs": [
            {"text": "Route30BerryHouseBookshelf"},
            {"text": "Route30BerryHouseBookshelf"},
        ],
        "objects": [
            {
                "name": "ROUTE30BERRYHOUSE_POKEFAN_M",
                "text": "TEXT_ROUTE30BERRYHOUSE_POKEFAN_M",
            },
        ],
    },
    "ROUTE_31": {
        "signs": [
            {"text": "Route31Sign"},
            {"text": "DarkCaveSign"},
        ],
        "objects": [
            {
                "name": "ROUTE31_FISHER",
                "text": "TEXT_ROUTE31_FISHER",
            },
            {
                "name": "ROUTE31_YOUNGSTER",
                "text": "TEXT_ROUTE31_YOUNGSTER",
            },
            {
                "name": "ROUTE31_BUG_CATCHER",
                "text": "ROUTE31_BUG_CATCHER",
                "hidden": True,
            },
            {
                "name": "ROUTE31_COOLTRAINER_M",
                "text": "TEXT_ROUTE31_COOLTRAINER_M",
            },
            {
                "name": "ROUTE31_FRUIT_TREE",
                "text": "ROUTE31_FRUIT_TREE",
                "hidden": True,
            },
            {
                "name": "ROUTE31_POKE_BALL1",
                "text": "TEXT_ROUTE31_POTION",
            },
            {
                "name": "ROUTE31_POKE_BALL2",
                "text": "TEXT_ROUTE31_POKE_BALL",
            },
        ],
    },
    "ROUTE_31_VIOLET_GATE": {
        "signs": [],
        "objects": [
            {
                "name": "ROUTE31VIOLETGATE_OFFICER",
                "text": "TEXT_ROUTE31VIOLETGATE_OFFICER",
            },
            {
                "name": "ROUTE31VIOLETGATE_COOLTRAINER_F",
                "text": "TEXT_ROUTE31VIOLETGATE_COOLTRAINER_F",
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
                    # "text" used to be the sign's baked English literal,
                    # but nothing ever routed that through the talk-script
                    # system (mapScripts.talkScript keys off this field,
                    # same as an object's TEXT_* constant -- see
                    # OverworldState:showMapText's callers), so every sign
                    # in every Crystal map silently fell through to "no
                    # text for ...".  The sign's own ROM script label
                    # (already captured below as "script", e.g.
                    # "ElmsLabHealingMachine") is a stable, already-unique
                    # key with no need to invent a TEXT_* name -- reuse it
                    # here too, matching what an object's "text" already
                    # points at.
                    signs.append({
                        "x": int(m.group(1)),
                        "y": int(m.group(2)),
                        "script": m.group(3),
                        "text": m.group(3),
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
                    obj = {
                        "index": object_index + 1,
                        "name": content.get("name"),
                        "x": int(m.group(1)),
                        "y": int(m.group(2)),
                        "sprite": m.group(3),
                        "movement": movement,
                        "range": roam,
                        "script": m.group(12),
                        "text": content["text"],
                    }
                    if content.get("hidden"):
                        obj["hidden"] = True
                    objects.append(obj)
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
            "music": spec["music"],
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
