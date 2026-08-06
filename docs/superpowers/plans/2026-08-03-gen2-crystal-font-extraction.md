# Gen2 (Crystal) Font Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract Crystal's font glyphs and character map from the player's own ROM so every hardcoded UI string (title screen, Start Menu, etc.) renders legibly instead of blank white.

**Architecture:** Mirror the existing Gen1 font pipeline exactly — a Python manifest step reads a local `pret/pokecrystal` checkout for symbol addresses and the character map, then a Lua runtime extractor (`RomExtractorGen2`) decodes the two font graphics symbols straight from the player's ROM bytes into the same `data/generated/font.lua` shape `src/render/Font.lua` already consumes for Gen1. Zero engine changes.

**Tech Stack:** Python 3 (manifest/tooling), Lua 5.1/LuaJIT (runtime extractor + engine), LÖVE2D.

## Global Constraints

- No ROM bytes, and no pokecrystal/pokered source text, are ever committed — only derived, non-copyrightable metadata (`tools/rom_manifest_crystal.json`: symbol addresses, byte offsets, code numbers).
- `data/generated/*` and `assets/generated/*` are gitignored, written only at import time on the player's machine.
- CI has no ROM: any new automated test must run against hand-built fixture data, never a real checkout or ROM (see `tests/run_tests.lua`'s existing Gen2 section for the established pattern).
- This plan touches only Gen2 (Crystal)-specific files; the Gen1 font path and full existing test suite must show zero regressions.

---

### Task 1: `tools/extract_gen2/font.py` — charmap parser

**Files:**
- Create: `tools/extract_gen2/font.py`
- Create: `tools/extract_gen2/test_font.py`

**Interfaces:**
- Consumes: `tools/extract/util.py`'s existing `read_asm(path)` (returns a list of `(lineno, text)` with comments stripped) and `parse_number(tok)` (parses `$hex`/`%binary`/decimal RGBDS literals) — both already used by `tools/make_rom_manifest_crystal.py`, unmodified.
- Produces: `parse_charmap(pokecrystal)` — takes a pokecrystal checkout root path (string), returns a list of `{"seq": str, "code": int}` dicts, longest-`seq`-first. Consumed by Task 2.

- [ ] **Step 1: Write the failing test**

Create `tools/extract_gen2/test_font.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tools/extract_gen2/test_font.py -v`
Expected: `ModuleNotFoundError` or `AttributeError` — `extract_gen2.font` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `tools/extract_gen2/font.py`:

```python
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 tools/extract_gen2/test_font.py -v`
Expected: `OK` (2 tests passed).

- [ ] **Step 5: Commit**

```bash
git add tools/extract_gen2/font.py tools/extract_gen2/test_font.py
git commit -m "$(cat <<'EOF'
Add Crystal charmap parser

Mirrors tools/extract/font.py's parse_charmap, scoped to just the
character map (Font/FontExtra symbol decoding is a runtime-extractor
concern, Task 3). Crystal's control tokens all sit below the $60
drawable-range cutoff already used to exclude them, so this drops
Gen1's separate RUNTIME_TOKENS exclusion list entirely.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Wire the charmap + font symbols into the Crystal manifest builder

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py`

**Interfaces:**
- Consumes: `tools/extract_gen2/font.py`'s `parse_charmap` (Task 1).
- Produces: `tools/rom_manifest_crystal.json` gains a top-level `"fontCharmap"` array and two new entries (`"Font"`, `"FontExtra"`) in `"symbols"`. Consumed by Task 3's `RomExtractorGen2:extractFont()` via `self.manifest.fontCharmap` and `self:symbol("Font")` / `self:symbol("FontExtra")`.

- [ ] **Step 1: Add the two symbols and the charmap call**

In `tools/make_rom_manifest_crystal.py`:

Add the import, right after the existing `from rom_data import SymbolTable` line:

```python
from extract_gen2.font import parse_charmap  # noqa: E402
```

Add `"Font"` and `"FontExtra"` to `REQUIRED_SYMBOLS`:

```python
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
```

In `main()`, add `"fontCharmap"` to the `data` dict:

```python
    data = {
        "romSha1": CRYSTAL_SHA1,
        "symbols": embed_symbols(symbols),
        "newBarkTown": parse_new_bark_town(pokecrystal),
        "fontCharmap": parse_charmap(pokecrystal),
    }
```

- [ ] **Step 2: Run it for real against the local pokecrystal checkout and verify the output**

```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal /tmp/pokecrystal \
  --symbols /tmp/pokecrystal/crystal.sym \
  --out tools/rom_manifest_crystal.json
python3 -c "
import json
d = json.load(open('tools/rom_manifest_crystal.json'))
print('Font' in d['symbols'], 'FontExtra' in d['symbols'])
print(len(d['fontCharmap']), 'charmap entries')
print([e for e in d['fontCharmap'] if e['seq'] == 'A'])
"
```

Expected: `True True`; charmap entry count in the low hundreds (Crystal's real `charmap.asm` has ~370 total `charmap` lines, most below the `$60` cutoff — expect on the order of 150-200 surviving entries, not an exact pinned count); the `'A'` lookup prints `[{'seq': 'A', 'code': 128}]` (`0x80 == 128`).

- [ ] **Step 3: Commit**

```bash
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json
git commit -m "$(cat <<'EOF'
Add font symbols and charmap to the Crystal manifest

Font/FontExtra join the existing symbol set (map/tileset/sprite);
fontCharmap is the parsed constants/charmap.asm drawable range. Both
consumed by RomExtractorGen2:extractFont() next.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `RomExtractorGen2:extractFont()` — runtime extraction

**Files:**
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `self:symbol(name)` (existing, returns `{bank, address, name}`), `self.rom:bytes(bank, address, length)` (existing), `ImageWriter.decode1bpp(raw, width, height, transparent)` and `ImageWriter.decode2bpp(raw, width, height, transparent)` (existing, unmodified — `src/import/ImageWriter.lua:20,45`), `self:save(image, relative)` / `self:write(name, value)` (existing), `self.manifest.fontCharmap` (Task 2).
- Produces: `data/generated/font.lua` shaped exactly like Gen1's (`src/render/Font.lua:38` `Font.load(data)` already consumes this: `{source, image, imageExtra, mainBase, extraBase, glyphsPerRow, charmap}`). `RomExtractorGen2:extractFont()` is called from `run()`; no other task depends on its internals.

- [ ] **Step 1: Remove `"font"` from `STUB_MODULES` and bump `STAGE_COUNT`**

In `src/import/RomExtractorGen2.lua`, change:

```lua
local STAGE_COUNT = 3
```
to:
```lua
local STAGE_COUNT = 4
```

Remove `"font"` from the `STUB_MODULES` list, and update the leading
comment's stale count (it says "13" — the 13 modules `Data:load()`
requires beyond the 3 already-real ones, of which `field` gets real
content and the rest are bare stubs; with `font` now also real, that
splits into 2 real + 11 bare stubs, so the comment's count of the
`STUB_MODULES` list itself drops from 12 to 11):

```lua
-- The other 12 modules Data:load()'s MODULES gate requires that this
-- skeleton's scope (New Bark Town's map/tileset/player sprite/font
-- only, see the spec's non-goals) never populates.  `field` gets real
-- boot content (extractField, below); the rest are bare empty tables --
-- confirmed by reading Data:seedDefaults, FieldDefaults.seed,
-- SsAnneLayout.apply and Font.load directly that every one of them
-- tolerates emptiness (Task 10 brief).  Not invented placeholder
-- content: an empty table is the honest "not extracted yet".
local STUB_MODULES = {
  "constants", "text", "text_pointers", "trainer_headers",
  "pokemon", "moves", "items", "type_chart", "trainers", "encounters",
  "battle_anims",
}
```

- [ ] **Step 2: Write `extractFont()`**

Add this function after `extractSprite()` (before `extractTileset()` — position doesn't matter functionally, this keeps the file's stage order matching `run()`'s call order from Step 3 below):

```lua
-- Font: 128 tiles, 128x64px, 1bpp -- codes $80-$FF (both cases + digits,
-- confirmed against constants/charmap.asm during planning). FontExtra: 32
-- tiles, 128x16px, 2bpp -- codes $60-$7F (space, quotes, the box-drawing
-- border glyphs Font.DEFAULT_BORDER already expects at $79-$7E). Unlike
-- Gen1 (whose font_extra.png is TextBoxGraphics plus a separate
-- Pokedex-tile patch), Crystal ships this whole range as one INCBIN, so
-- there is no patch step.
function RomExtractorGen2:extractFont()
  self:beginStage("Font")
  local main = self:symbol("Font")
  local raw = self.rom:bytes(main.bank, main.address, 128 * 8)
  local image = ImageWriter.decode1bpp(raw, 128, 64, true)
  self:save(image, "fonts/font.png")
  self:tick("Font", 1, 2)

  local extra = self:symbol("FontExtra")
  local shaded = ImageWriter.decode2bpp(
    self.rom:bytes(extra.bank, extra.address, 32 * 16), 128, 16)
  local extraImage = ImageWriter.blank(128, 16, 0, 0, 0, 0)
  for y = 0, 15 do
    for x = 0, 127 do
      local r = shaded:getPixel(x, y)
      if r < 0.5 then extraImage:setPixel(x, y, 0, 0, 0, 1) end
    end
  end
  self:save(extraImage, "fonts/font_extra.png")
  self:tick("Font", 2, 2)

  local data = {
    source = "ROM:Font, FontExtra",
    image = "assets/generated/fonts/font.png",
    imageExtra = "assets/generated/fonts/font_extra.png",
    mainBase = 0x80, extraBase = 0x60, glyphsPerRow = 16,
    charmap = self.manifest.fontCharmap,
  }
  self:write("font", data)
  return data
end
```

- [ ] **Step 3: Call it from `run()`**

Change:

```lua
function RomExtractorGen2:run()
  local results = {}
  results.sprites = self:extractSprite()
  results.tilesets = self:extractTileset()
  results.maps = self:extractMap()
  results.field = self:extractField(results.maps.NEW_BARK_TOWN)
  self:extractStubs()
```

to:

```lua
function RomExtractorGen2:run()
  local results = {}
  results.sprites = self:extractSprite()
  results.tilesets = self:extractTileset()
  results.maps = self:extractMap()
  results.font = self:extractFont()
  results.field = self:extractField(results.maps.NEW_BARK_TOWN)
  self:extractStubs()
```

- [ ] **Step 4: Update the file's header comment**

Change the top-of-file comment from:

```lua
-- src/import/RomExtractorGen2.lua
-- Gen2 (Crystal) runtime extractor, scoped to New Bark Town: map, the
-- TILESET_JOHTO tileset, and the player (Chris) overworld sprite.
```

to:

```lua
-- src/import/RomExtractorGen2.lua
-- Gen2 (Crystal) runtime extractor, scoped to New Bark Town: map, the
-- TILESET_JOHTO tileset, the player (Chris) overworld sprite, and the
-- font (glyphs + charmap) used to draw the engine's own hardcoded UI
-- strings (title screen, menus).
```

- [ ] **Step 5: Verify the file loads (syntax check)**

Run: `luajit -e "assert(loadfile('src/import/RomExtractorGen2.lua'))" && echo OK`
Expected: `OK`

- [ ] **Step 6: Run the full quick test suite to confirm no regressions**

Run: `./scripts/test.sh --quick`
Expected: `ALL TIERS PASSED` (same as before this task — this file isn't `require`d by any headless test, so this step is a regression guard on everything else, not a check on this task's own new code; Task 4 and the manual verification in Task 5 cover that).

- [ ] **Step 7: Commit**

```bash
git add src/import/RomExtractorGen2.lua
git commit -m "$(cat <<'EOF'
Extract Crystal's font glyphs and charmap at import time

RomExtractorGen2:extractFont() decodes the Font (1bpp) and FontExtra
(2bpp) ROM symbols into data/generated/font.lua, in exactly the shape
src/render/Font.lua already consumes for Gen1 -- zero engine changes.
font.lua moves out of the empty-stub list (STUB_MODULES) now that it
has real content.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Fixture-backed structural test

**Files:**
- Modify: `tests/run_tests.lua`

**Interfaces:**
- Consumes: `src/render/Font.lua`'s existing `Font.load(data)`, `Font.encode(text)`, `Font.width(text)` (all unmodified — this task proves they already handle Gen2-shaped font data, the same claim Task 7 of the walking skeleton already proved for map data).
- Produces: nothing consumed by a later task; this is a leaf verification.

- [ ] **Step 1: Write the test**

In `tests/run_tests.lua`, add this new `do...end` block immediately after the existing Gen2 map/tileset block (which ends with `check(w ~= nil and w.def.destMap == "ROUTE_29", "New Bark Town fixture warp table intact")` followed by `end`), and before the `-- ---------------------------------------------- the globbed tiers` comment:

```lua
-- Hand-built font data (not ROM-derived), matching the shape
-- RomExtractorGen2:extractFont() produces -- proves Font.lua already
-- consumes Gen2-shaped charmap data correctly, the same "zero engine
-- changes" claim the map/tileset fixture above proves for map data.
-- Reuses the map fixture's own PNG (Font.load never inspects pixel
-- content, only the dimensions love_stub reads from the real PNG
-- header -- see tests/love_stub.lua's pngSize).
do
  local Font = require("src.render.Font")
  local fontData = {
    image = "tests/fixture_data/assets/fix_out.png",
    imageExtra = "tests/fixture_data/assets/fix_out.png",
    mainBase = 0x80, extraBase = 0x60, glyphsPerRow = 16,
    charmap = {
      { seq = "A", code = 0x80 },
      { seq = "B", code = 0x81 },
      { seq = " ", code = 0x7f },
    },
  }
  Font.load({ font = fontData })
  local codes = Font.encode("AB A")
  eq(#codes, 4, "Gen2 font fixture: 'AB A' is 4 glyphs")
  eq(codes[1], 0x80, "Gen2 font fixture: 'A' resolves via charmap")
  eq(codes[2], 0x81, "Gen2 font fixture: 'B' resolves via charmap")
  eq(codes[3], 0x7f, "Gen2 font fixture: space resolves to extra-page code")
  eq(codes[4], 0x80, "Gen2 font fixture: second 'A' resolves via charmap")
  eq(Font.width("AB"), 16, "Gen2 font fixture: two fixed-width glyphs measure 16px")
end
```

- [ ] **Step 2: Run it and verify it passes**

Run: `luajit tests/run_tests.lua 2>&1 | grep -i "gen2 font"`
Expected: 6 lines, each starting `ok` (this proves existing, unmodified `Font.lua` code already handles the shape correctly — there is no "make it pass" implementation step here, matching the walking skeleton's own Task 7 precedent of proving zero-engine-change consumption).

Then run the full suite to confirm nothing else broke:

Run: `./scripts/test.sh --quick`
Expected: `ALL TIERS PASSED`

- [ ] **Step 3: Commit**

```bash
git add tests/run_tests.lua
git commit -m "$(cat <<'EOF'
Add fixture-backed structural test for Gen2-shaped font data

Proves Font.lua already loads and resolves hand-built New Bark
Town-shaped font data (matching RomExtractorGen2.lua's extractFont
output schema) correctly, with no ROM present -- same "zero engine
changes" claim Task 7 already proved for map data, now for font.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Manual real-ROM verification

**Files:** none (verification checklist only; this task produces no commit unless it uncovers a bug in an earlier task, in which case fix that task's file and commit there, then re-run this task from Step 1 — same pattern the walking skeleton's own Task 8/10 followed).

**Interfaces:** N/A.

- [ ] **Step 1: Reimport Crystal with the real ROM**

```bash
love .
```

In the launcher, reimport the Crystal ROM (already-imported versions get a "Reimport" action; see `src/import/LauncherView.lua`'s `imp:reimport(version)`). Expected: import runs through "Player sprite" → "Johto tileset" → "New Bark Town" → "Font" → "Ready" (the new fourth stage from Task 3), no error.

- [ ] **Step 2: Verify the generated font assets**

```bash
python3 -c "
import glob
for p in sorted(glob.glob('*/Library/Application Support/LOVE/pokemon-love2d/crystal/data/generated/font.lua', recursive=True)):
    print(p)
"
```

(If that glob doesn't resolve on your machine, find the save directory LÖVE printed at launch instead — `love.filesystem.getSaveDirectory()`, logged during import.) Confirm `crystal/data/generated/font.lua` exists and is larger than the ~10-byte empty-table stub every other still-stubbed module has, and that `crystal/assets/generated/fonts/font.png` and `font_extra.png` exist.

- [ ] **Step 3: Visual check against spec acceptance criteria 3**

Press Play, reach the title screen. Expected: "NEW GAME" / "OPTION" / "EXIT GAME" (or "CONTINUE" if a save exists) render as legible black-on-white text, not blank space. Start a new game, open the Start Menu (pause menu). Expected: "POKéDEX", "POKéMON"/party-related label, "BAG", the player name field, "SAVE", "OPTION", "EXIT" all render legibly.

- [ ] **Step 4: Confirm no glyph warnings for the strings actually shown**

Watch the terminal `love .` was launched from while doing Step 3. Expected: no `[warn] font: no glyph for ...` lines for any character in the strings just visually confirmed (occasional warnings for characters *not* exercised, e.g. from an unrelated screen, are fine and out of scope here).

- [ ] **Step 5: If everything above passes, update the spec's status**

Edit `docs/superpowers/specs/2026-08-03-gen2-crystal-font-extraction-design.md`'s `Status:` line from `approved for planning` to `verified against real ROM, <today's date>`, and commit:

```bash
git add docs/superpowers/specs/2026-08-03-gen2-crystal-font-extraction-design.md
git commit -m "$(cat <<'EOF'
Mark the Gen2 (Crystal) font extraction verified against real ROM

Title screen and Start Menu render legible text from the extracted
font; no glyph warnings for any string exercised during verification.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```
