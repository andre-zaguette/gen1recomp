# Gen2 (Crystal) Font Extraction

Status: approved for planning
Date: 2026-08-03

## Context

The Gen2 (Crystal) extraction skeleton (`2026-08-03-gen2-crystal-extraction-skeleton-design.md`)
proved the import pipeline end-to-end for New Bark Town: the player boots
into the map, walks in all four directions, and collision matches the real
game. That spec deliberately stubbed `data/generated/font.lua` as an empty
table, since its only stated goal was "render a static town and walk in it."

Real-ROM manual verification of that skeleton (and of the interact-button
fixes that followed it) surfaced a visible gap: the title screen and every
menu (Start Menu, etc.) render as blank white space where their labels
should be. This is not missing ROM dialogue — every label involved
("NEW GAME", "OPTION", "EXIT GAME", "POKéDEX", "BADGES", "TIME", ...) is a
hardcoded Lua string, routed through the engine's own `Strings()` function,
not extracted from the ROM. What is actually missing is the font itself:
`src/render/Font.lua` draws every glyph from `data.font`'s glyph sheets and
charmap, and Crystal's `font.lua` is an empty stub, so nothing draws.

This is a small, self-contained gap, distinct from real GBC color (a
separate, much larger spec, deliberately not bundled here — see that
spec's own non-goals) and distinct from ROM dialogue/text extraction (still
out of scope: `data/generated/text.lua` and `text_pointers.lua` stay empty).

## Goal

Extract Crystal's font glyphs and character map from the player's own ROM,
following the exact same architecture the walking skeleton already
established (manifest built ahead of time from a local `pret/pokecrystal`
checkout → runtime extractor reads the player's ROM bytes by address →
generated cache → engine renders it, unchanged). Once this lands, every
Lua-sourced UI string in the game (title screen, Start Menu, etc.) renders
legibly instead of blank.

## Non-goals

- ROM dialogue / script text (`data/generated/text.lua`,
  `text_pointers.lua` stay empty stubs; this is UI chrome only).
- GBC color palettes (separate spec).
- Pokédex-only extra glyphs (feet/inches marks, kana) — Crystal's
  `font_extra.png` equivalent doesn't carry these either; the Gen1 extractor
  patches them in from a separate Pokédex tile symbol that has no Gen2
  counterpart in scope here.
- Any map besides New Bark Town, any data besides font.

## Reference

Same ROM as the walking skeleton: `Pokemon - Crystal Version (USA, Europe)
(Rev 1).gbc`, SHA-1 `f2f52230b536214ef7c9924f483392993e226cfb`. Symbol
addresses come from a local `pret/pokecrystal` checkout + built `.sym` file
(already used to build the existing `tools/rom_manifest_crystal.json`),
never committed; only the derived manifest is.

## Architecture

Confirmed against the local pokecrystal checkout: Crystal's font format is
structurally identical to Gen1's.

- `Font:` (`gfx/font/font.1bpp`) — 128 tiles, 128×64px, 1bpp. Codes
  $80–$FF (`charmap "A", $80` ... `charmap "0", $f6` etc. — both upper/lower
  case and digits live in this one page). Same shape as Gen1's
  `FontGraphics` symbol.
- `FontExtra:` (`gfx/font/font_extra.2bpp`) — 32 tiles, 128×16px, 2bpp.
  Covers exactly codes $60–$7F: box-drawing borders ($79–$7E, matching
  `Font.DEFAULT_BORDER`'s existing codes), quotes, and space ($7F). Unlike
  Gen1 (whose `TextBoxGraphics` + a separate Pokédex-tile patch together
  make up `font_extra.png`), Crystal ships this whole range as one INCBIN
  — simpler, no patch step needed.
- `constants/charmap.asm` — same `charmap "seq", $code` format Gen1's
  parser already reads. Every control/meta token (`<PLAYER>`, `<CONT>`,
  `@`, `#`, ...) has a code below $60 in Crystal's charmap too (verified by
  inspection), so the existing "keep only $60–$FF" range filter excludes
  them all on its own — no per-token exclusion list needs to be ported.

New files, mirroring the pattern the walking skeleton's own architecture
table established:

| New file | Mirrors | Responsibility |
| --- | --- | --- |
| `tools/extract_gen2/font.py` | `tools/extract/font.py` | Parses `constants/charmap.asm` from a local pokecrystal checkout into `{seq, code}` entries |

Existing files, small additions:

- `tools/make_rom_manifest_crystal.py`: add `"Font"` and `"FontExtra"` to
  `REQUIRED_SYMBOLS` (so their ROM bank/address land in the manifest's
  `symbols` table), and call the new `font.parse_charmap()` to add a
  `fontCharmap` field to the output JSON, exactly mirroring
  `tools/make_rom_manifest.py`'s `"fontCharmap": font.parse_charmap(pokered)`.
- `src/import/RomExtractorGen2.lua`: a new `extractFont()` method, called
  from `run()` in place of `font`'s current entry in `STUB_MODULES`.
  Mirrors `RomExtractor:extractFont()`: decode `Font` (1bpp) into a black-
  ink-on-transparent 128×64 PNG, decode `FontExtra` (2bpp, threshold-to-ink)
  into a 128×16 PNG, write both under `assets/generated/fonts/`, and write
  `data/generated/font.lua`:

  ```lua
  {
    source = "ROM:Font, FontExtra",
    image = "assets/generated/fonts/font.png",
    imageExtra = "assets/generated/fonts/font_extra.png",
    mainBase = 0x80, extraBase = 0x60, glyphsPerRow = 16,
    charmap = self.manifest.fontCharmap,
  }
  ```

  This is exactly the shape `src/render/Font.lua` already consumes for
  Gen1 — zero engine changes, same as every other module the walking
  skeleton already extracts.

### Data flow

Unchanged from the walking skeleton, font added to the decode step:

```
local pokecrystal checkout (dev-only, not committed)
        |
        v  tools/make_rom_manifest_crystal.py (+ tools/extract_gen2/font.py)
tools/rom_manifest_crystal.json  (committed; now also carries fontCharmap
                                   and Font/FontExtra symbol addresses)
        |
        v  RomExtractorGen2.lua, at the player's first boot
player's real Crystal ROM ------------+
        |                             |
        v                             v
   SHA-1 validation           decode New Bark Town + font
        |
        v
crystal/data/generated/font.lua + crystal/assets/generated/fonts/*.png
```

### Approaches considered

- **Chosen — mirror Gen1's font extraction exactly**, as above. Same risk
  profile as the walking skeleton itself: the format is already confirmed
  identical, so this is mechanical porting, not new design.
- **Rejected — ship pre-rendered label images instead of extracting the
  ROM font.** Would be faster, but bundles Nintendo-owned glyph art in the
  repo, violating the project's core "only the player's own ROM is ever a
  source of assets" rule.
- **Rejected — bundle real ROM dialogue/text extraction into this same
  slice.** Dialogue is a materially bigger problem (compressed text
  streams, pointer tables, script commands) and was explicitly split out
  during brainstorming to keep this slice small and mechanical.

## Testing

Mirrors the walking skeleton's own testing section and Task 7's precedent
(a hand-built, non-ROM-derived fixture inside `tests/run_tests.lua`, not a
real font asset):

- A new `do...end` block in `tests/run_tests.lua`'s Gen2 section builds a
  `data.font` table by hand (reusing an existing fixture PNG path for
  `image`/`imageExtra`, same trick the map fixture already uses — the
  headless `love_stub` doesn't inspect pixel content) with a small charmap
  covering a few known letters. Loads it via `Font.load`, then asserts
  `Font.encode`/`Font.width`/`Font.draw` resolve those letters to real
  glyph codes (not the space fallback), proving the shape this extractor
  will produce is one `Font.lua` already consumes correctly.
- Real-ROM verification is manual/local only, like the rest of this
  project's Gen2 work: reimport Crystal, confirm the title screen shows
  "NEW GAME"/"OPTION"/"EXIT GAME" and the Start Menu shows its labels,
  and confirm no `[warn] font: no glyph for ...` lines appear in the log
  for any hardcoded UI string exercised during that pass.

## Acceptance criteria

1. `python3 tools/make_rom_manifest_crystal.py --pokecrystal <checkout> --symbols <crystal.sym> --out tools/rom_manifest_crystal.json` runs clean and the output JSON gains `fontCharmap` plus `Font`/`FontExtra` symbol entries.
2. Reimporting Crystal in the launcher generates `crystal/data/generated/font.lua` and `crystal/assets/generated/fonts/{font,font_extra}.png`.
3. The title screen and Start Menu render legible text for every
   hardcoded UI string exercised, with no `no glyph` warnings for them in
   the log.
4. `luajit tests/run_tests.lua` passes the new fixture-backed font case
   with no ROM present.
5. The existing Gen1 font path and full test suite show no regressions
   (this change only touches Gen2-specific files).

## Follow-on work (explicitly out of scope here)

- Real GBC color (separate spec).
- ROM dialogue / script text extraction (`text`, `text_pointers`).
- Pokédex-specific extra glyphs, if a future slice ever extracts Gen2
  Pokédex data.
