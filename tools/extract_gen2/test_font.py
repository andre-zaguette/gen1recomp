# tools/extract_gen2/test_font.py
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from extract_gen2 import font

# A trimmed stand-in for constants/charmap.asm: one low-code control
# token (must be excluded), one bracket-style token that happens to sit
# inside the drawable range (kept -- see font.py's docstring for why),
# space, and a few real letters across both charmap.asm blocks real
# Crystal splits printable characters into ($80-$FF main page,
# $60-$7F extra page).
FIXTURE_CHARMAP = """
; Control characters
\tcharmap "<NULL>",    $00
\tcharmap "<PLAYER>",  $52
\tcharmap "@",         $50

; Actual characters
\tcharmap "<BOLD_A>",  $60 ; unused
\tcharmap " ",         $7f
\tcharmap "A",         $80
\tcharmap "B",         $81
\tcharmap "a",         $a0
"""


class ParseCharmapTest(unittest.TestCase):
    def test_filters_control_tokens_and_keeps_drawable_range(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "constants"))
            with open(os.path.join(tmp, "constants/charmap.asm"), "w") as f:
                f.write(FIXTURE_CHARMAP)
            entries = font.parse_charmap(tmp)

        by_seq = {e["seq"]: e["code"] for e in entries}
        self.assertNotIn("<NULL>", by_seq)
        self.assertNotIn("<PLAYER>", by_seq)
        self.assertNotIn("@", by_seq)
        self.assertEqual(by_seq["<BOLD_A>"], 0x60)
        self.assertEqual(by_seq[" "], 0x7f)
        self.assertEqual(by_seq["A"], 0x80)
        self.assertEqual(by_seq["B"], 0x81)
        self.assertEqual(by_seq["a"], 0xa0)

    def test_sorted_longest_seq_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "constants"))
            with open(os.path.join(tmp, "constants/charmap.asm"), "w") as f:
                f.write(FIXTURE_CHARMAP)
            entries = font.parse_charmap(tmp)

        self.assertEqual(entries[0]["seq"], "<BOLD_A>")


if __name__ == "__main__":
    unittest.main()
