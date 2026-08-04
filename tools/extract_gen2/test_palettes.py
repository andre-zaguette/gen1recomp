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
