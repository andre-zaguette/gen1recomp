"""Crystal font character map extraction.

Source: constants/charmap.asm. Codes $00-$5F are control/RAM-substitution
tokens (<PLAYER>, <CONT>, @, #, ...) -- every one of them has a code below
$60 in Crystal's own charmap.asm (confirmed by inspection during
planning), so the range check below excludes them all with no per-token
list to keep in sync, unlike tools/extract/font.py's Gen1 RUNTIME_TOKENS.

A handful of bracket-style tokens ($60-$71: <BOLD_A>..<BOLD_M>, <PO>,
<KE>, ...) do fall inside the $60-$FF drawable range and are kept -- this
is harmless rather than wrong: no plain English UI string this project
draws will ever contain their literal "<...>" text, so they can never
match during Font.split, and excluding them would require exactly the
kind of per-token list this function avoids.

Paired at the manifest-build step with the Font/FontExtra ROM symbols --
see docs/superpowers/specs/2026-08-03-gen2-crystal-font-extraction-design.md.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from extract.util import parse_number, read_asm  # noqa: E402


def parse_charmap(pokecrystal):
    """charmap.asm entries for the drawable range ($60-$FF)."""
    entries = []
    seen = set()
    path = os.path.join(pokecrystal, "constants/charmap.asm")
    for _, line in read_asm(path):
        m = re.match(r'charmap\s+"((?:[^"\\]|\\.)*)",\s*(\$\w+)', line.strip())
        if not m:
            continue
        seq = m.group(1).replace('\\"', '"')
        code = parse_number(m.group(2))
        if seq in seen:
            continue
        seen.add(seq)
        if 0x60 <= code <= 0xFF:
            entries.append({"seq": seq, "code": code})
    # longest-first so a greedy matcher (Font.split) picks multi-char
    # sequences before any single-char prefix of them
    entries.sort(key=lambda e: (-len(e["seq"]), e["seq"]))
    return entries
