# Crystal Shiny Battle Sprites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make shiny Crystal Pokémon actually look different in battle — front and back battle pics recolor to the species' real shiny palette whenever `Stats.isShiny(mon.dvs)` is true, using real ROM shiny palette data.

**Architecture:** `src/import/RomExtractorGen2.lua`'s existing per-species sprite extraction already rips `front.png`/`back.png` as true-color, already-normal-palette-composited PNGs — this plan adds a second pass, per species, that decodes the real ROM's normal palette (binary `front.gbcpal`) and shiny palette (text `shiny.pal`), builds a 2-color remap table, and writes a `_front_shiny.png`/`_back_shiny.png` alongside the existing files. `src/pokemon/Sprites.lua`'s `Sprites.path` — the single sanctioned resolution point every battle pic and the summary screen already call through, with the live mon already passed as `opts.mon` — picks the shiny variant when the mon is shiny and one exists, falling back to the normal sprite otherwise. No battle code changes: `BattleState.lua`'s `makeBattler` and `SummaryMenu.lua` already pass `opts.mon` through today.

**Tech Stack:** Lua (LÖVE2D, `love.image` for pixel work), the existing `ImageWriter`/`RomExtractorGen2` extraction pipeline (unchanged elsewhere).

## Global Constraints

- No ROM bytes may ever be committed (`.gitignore`'s `/roms/` entry) — only derived PNG assets under `assets/generated/pokemon/` (already gitignored the same way existing sprite output is) and Lua code.
- `GameVersion.isCrystal()` gates all Gen1/Gen2 divergence — this plan is Crystal-only (Gen1/Yellow have no shiny mechanic at all) and does not touch `src/import/RomExtractor.lua`, `tools/make_rom_manifest.py`, or `tools/make_yellow_manifest.py`.
- This feature needs no `tools/rom_manifest_crystal.json` changes — species sprite paths are already derived purely from `frontStem` (parsed from `base_stats.asm`'s own `INCBIN` line, already read directly by `RomExtractorGen2:parseCrystalSpecies`), not from a ROM bank:address symbol lookup. Do not add manifest entries for this.
- Full test suite (`LUA=luajit scripts/test.sh`) must report all tests passed before every commit.
- A species missing `shiny.pal` (uncommon dex entries) must gracefully keep only its normal sprite — never error, never crash extraction. This mirrors `Music.play`'s existing graceful no-op on an unextracted song (see the SFX and Milestone 2 plans) — a missing shiny variant is a silent, safe absence, not a failure.
- `love.image`-backed pixel work (`ImageWriter.remapColors`, reading real `front.png`/`shiny.pal`/`front.gbcpal` files) cannot be unit-tested headlessly — this project's test stub (`tests/love_stub.lua`) has no `love.image` at all. Test the pure decode/mapping logic (byte and text parsing, the resulting color-remap table) exhaustively with real ROM-derived byte fixtures; the pixel-level remap itself is verified by a real ROM import + visual check (Task 2's own verification step), the same boundary Milestone 2 and the SFX plan already drew between what's headlessly testable and what needs a real `love.image` run.

## Research already done

**Real shiny palette data exists per species in the ROM.** `roms/pokecrystal/gfx/pokemon/<species>/shiny.pal` exists for 251 species (`find gfx/pokemon -iname shiny.pal | wc -l` → 252, one being Unown's own separate per-letter set) — plain pret source text, exactly 2 lines of `RGB r, g, b` (0-31 GBC component scale each). Totodile's is:
```
	RGB 18, 26, 15
	RGB 14, 09, 28
```

**The existing sprite extraction (`RomExtractorGen2:parseCrystalSpecies`, `src/import/RomExtractorGen2.lua`, current lines ~543-592) already reads `front.png`/`back.png` directly from `roms/pokecrystal/gfx/pokemon/<frontStem>/`** — these are pret's own pre-rendered, ALREADY-color-composited true-color PNGs (not raw indexed 2bpp tile data), matted for transparency via the existing `ImageWriter.matteColor0`, saved to `assets/generated/pokemon/<frontStem>_front.png` / `_back.png`, with every species' `def.trueColor = true`. A shiny variant therefore needs a **pixel color remap** on top of the already-extracted PNG — swap the 2 non-fixed colors — not a fresh raw-tile decode.

**The exact GBC palette byte format, hand-decoded and independently cross-verified against a known-good text/binary pair.** Every species also carries a binary `front.gbcpal` (checked identical to `normal.gbcpal` for every species checked) — 4 colors × 2 bytes each, little-endian, standard Game Boy Color BGR555 packing:
```
value = byte[0] + byte[1] * 256
R (0-31) = value & 0x1F
G (0-31) = (value >> 5) & 0x1F
B (0-31) = (value >> 10) & 0x1F
```
0-31 → 0-255: `round(v * 255 / 31)` — the exact scaling `tools/extract/palettes.py`'s own pre-existing `_scale5` helper already uses for Gen1's GBC-enhanced palettes (same GBC hardware format, a Crystal-side file instead of a Gen1-side one).

Verified this decode formula is exactly right against `roms/pokecrystal/gfx/pokemon/unown/normal.pal` — the one species with a checked-in **text** normal palette (`RGB 15, 15, 16` / `RGB 07, 07, 08`) alongside its binary `normal.gbcpal` (`ff7f ef41 e720 0000`). Hand-decoding the binary's middle two colors with the formula above gives exactly `(15,15,16)` and `(7,7,8)` — a byte-for-byte match to the text file. **Color 0 is always white (31,31,31) and color 3 is always black (0,0,0)** across every species (the standard Game Boy monster-sprite convention — confirmed in both Unown's and Totodile's binaries: `ff7f ... 0000`); only colors 1 and 2 (the two lines `shiny.pal`/`normal.pal` give) ever differ, per species and per shiny variant.

**Worked, byte-verified fixture (Totodile), used directly in Task 1's test:**
```
front.gbcpal bytes: FF 7F 2C 6A 3C 11 00 00
  color0 = FF,7F -> value 0x7FFF -> (31,31,31) -> white, fixed
  color1 = 2C,6A -> value 0x6A2C -> (12,17,26) 0-31 -> (99,140,214) 0-255  (blue body)
  color2 = 3C,11 -> value 0x113C -> (28,9,4)   0-31 -> (230,74,33) 0-255  (orange crest)
  color3 = 00,00 -> value 0x0000 -> (0,0,0)    -> black, fixed

shiny.pal text: "RGB 18, 26, 15" / "RGB 14, 09, 28"
  shinyColor1 = (18,26,15) 0-31 -> (148,214,123) 0-255  (replaces the blue)
  shinyColor2 = (14,9,28)  0-31 -> (115,74,230)  0-255  (replaces the orange)
```

**The exact, already-existing hook point that needs zero changes to `BattleState.lua`.** `src/pokemon/Sprites.lua`'s `Sprites.path(data, species, side, opts)` is the sole sanctioned resolution point for every battle pic in the codebase (its own header comment: "every battle pic and party icon load goes through pokemon.sprite") and `opts.mon` — documented as "the live mon when available (per-instance skins)" — is already passed with the real mon object at both call sites that matter:
- `src/battle/BattleState.lua:462-467`, `makeBattler`: `Sprites.path(data, mon.species, isPlayer and "back" or "front", { mon = mon, kind = "battle" })`.
- `src/ui/SummaryMenu.lua:46`, `Sprites.path(game.data, mon.species, "front", { mon = mon, kind = "summary" })` — this call site needs **no task of its own**; it already passes `opts.mon`, so it automatically picks up the shiny sprite for free once `Sprites.path` itself is fixed in Task 2.

`src/pokemon/Stats.lua` (home of the pre-existing `Stats.isShiny(dvs)`) is not required by `src/pokemon/Sprites.lua` today; Task 2 adds that require.

**Explicit non-goals for this plan** (confirmed with the user): party-menu icon shininess — `Sprites.iconPath` is a separate, simpler function that does not take `opts.mon` today; left as a follow-up, no task detail invented for it here.

## File Structure

- `src/import/ImageWriter.lua` — gains `ImageWriter.remapColors(image, mapping)`, a generic pixel-level color-swap utility (sibling to the existing `matteColor0`), operating on a `love.image.ImageData`.
- `src/import/RomExtractorGen2.lua` — `parseCrystalSpecies`'s existing per-species loop gains: reading `shiny.pal` (text) and `front.gbcpal` (binary) per species, decoding both into a 2-entry color-remap table, calling `ImageWriter.remapColors` on the already-extracted front/back `ImageData` before it's matted+saved, and writing `_front_shiny.png`/`_back_shiny.png` (+ `def.spriteFrontShiny`/`def.spriteBackShiny`) only when `shiny.pal` exists for that species.
- `src/pokemon/Sprites.lua` — `Sprites.path` gains a `Stats.isShiny(opts.mon.dvs)` check that substitutes the shiny path when available, before the existing mod-hook step.
- `tests/engine/gen2_shiny_palette.lua` (new, Task 1) — pins the GBC palette byte/text decode and the resulting remap table against the Totodile fixture above, ROM-free.
- `tests/gen2_sprites_shiny_test.lua` (new, Task 2) — pins `Sprites.path`'s shiny-selection logic (species with/without a shiny variant, mon shiny/not-shiny, mod-hook ordering) against a fake `data` table, no `love.image` needed since this only exercises path selection, not pixel work.

## Task 1: GBC palette decode + `ImageWriter.remapColors`

**Files:**
- Modify: `src/import/ImageWriter.lua` (`remapColors`)
- Modify: `src/import/RomExtractorGen2.lua` (new local helpers `decodeGbcPalette`, `parseShinyPal`, `shinyRemapTable` — no wiring into the extraction loop yet, that's Task 2)
- Test: `tests/engine/gen2_shiny_palette.lua` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `ImageWriter.remapColors(image, mapping)` — `image` a `love.image.ImageData`, `mapping` an array of `{from = {r,g,b}, to = {r,g,b}}` pairs with components in the 0-1 float range `getPixel`/`setPixel` already use elsewhere in this file; returns `image` (mutated in place, matching `matteColor0`'s own return-the-mutated-image convention). A pixel matches `from` when every component is within `1/512` of it (tolerance against any rounding difference between this project's own decode and pret's own PNG rendering — see Global Constraints). `decodeGbcPalette(bytes)` (local to `RomExtractorGen2.lua`) takes an 8-byte raw string (a `front.gbcpal`/`normal.gbcpal`'s contents) and returns 4 `{r,g,b}` triples in the 0-255 int range. `parseShinyPal(text)` takes a `shiny.pal`'s raw text and returns exactly 2 `{r,g,b}` triples (0-255 int range) in file order. `shinyRemapTable(normalBytes, shinyText)` combines both into the array shape `ImageWriter.remapColors` consumes directly (0-1 float range, colors 0/3 never included since they never change).

- [ ] **Step 1: Write the failing test**

Create `tests/engine/gen2_shiny_palette.lua`:

```lua
-- Pins the GBC shiny-palette decode this project's Crystal sprite
-- extraction needs (docs/superpowers/plans/
-- 2026-08-10-gen2-crystal-shiny-sprites.md, Task 1) against real,
-- hand-verified ROM bytes -- see the plan's "Research already done"
-- section for the full derivation, including the independent
-- cross-check against roms/pokecrystal/gfx/pokemon/unown/normal.pal
-- (the one species with a checked-in TEXT normal palette) that
-- confirmed this exact byte formula.
--   luajit tests/engine/gen2_shiny_palette.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local RomExtractorGen2 = require("src.import.RomExtractorGen2")

-- Real front.gbcpal bytes for Totodile (roms/pokecrystal/gfx/pokemon/
-- totodile/front.gbcpal, gitignored, not committed -- see the plan).
local totodileGbcPal = string.char(
  0xFF, 0x7F, 0x2C, 0x6A, 0x3C, 0x11, 0x00, 0x00)

local colors = RomExtractorGen2._decodeGbcPalette(totodileGbcPal)
eq(#colors, 4, "decodeGbcPalette returns 4 colors")
eq(colors[1][1], 31, "color0 R is white (31)")
eq(colors[1][2], 31, "color0 G is white (31)")
eq(colors[1][3], 31, "color0 B is white (31)")
eq(colors[2][1], 12, "color1 R (0-31 scale)")
eq(colors[2][2], 17, "color1 G (0-31 scale)")
eq(colors[2][3], 26, "color1 B (0-31 scale)")
eq(colors[3][1], 28, "color2 R (0-31 scale)")
eq(colors[3][2], 9, "color2 G (0-31 scale)")
eq(colors[3][3], 4, "color2 B (0-31 scale)")
eq(colors[4][1], 0, "color3 R is black (0)")
eq(colors[4][2], 0, "color3 G is black (0)")
eq(colors[4][3], 0, "color3 B is black (0)")

-- Real shiny.pal text for Totodile (roms/pokecrystal/gfx/pokemon/
-- totodile/shiny.pal).
local totodileShinyPal = "\tRGB 18, 26, 15\n\tRGB 14, 09, 28\n"
local shiny = RomExtractorGen2._parseShinyPal(totodileShinyPal)
eq(#shiny, 2, "parseShinyPal returns exactly 2 colors")
eq(shiny[1][1], 18, "shiny color1 R (0-31 scale)")
eq(shiny[1][2], 26, "shiny color1 G (0-31 scale)")
eq(shiny[1][3], 15, "shiny color1 B (0-31 scale)")
eq(shiny[2][1], 14, "shiny color2 R (0-31 scale)")
eq(shiny[2][2], 9, "shiny color2 G (0-31 scale)")
eq(shiny[2][3], 28, "shiny color2 B (0-31 scale)")

-- The combined remap table ImageWriter.remapColors consumes directly:
-- 0-255 (0-31 scale converted via round(v * 255 / 31)) -> 0-1 float.
local mapping = RomExtractorGen2._shinyRemapTable(totodileGbcPal, totodileShinyPal)
eq(#mapping, 2, "shinyRemapTable has exactly 2 entries (colors 0/3 never remap)")

local function approx(a, b, msg)
  check(math.abs(a - b) < 1 / 512, msg .. (" (got %.4f, want %.4f)"):format(a, b))
end

-- color1: normal (12,17,26)/31 -> shiny (18,26,15)/31, both 0-1 float
approx(mapping[1].from[1], 99 / 255, "mapping[1].from R")
approx(mapping[1].from[2], 140 / 255, "mapping[1].from G")
approx(mapping[1].from[3], 214 / 255, "mapping[1].from B")
approx(mapping[1].to[1], 148 / 255, "mapping[1].to R")
approx(mapping[1].to[2], 214 / 255, "mapping[1].to G")
approx(mapping[1].to[3], 123 / 255, "mapping[1].to B")

-- color2: normal (28,9,4)/31 -> shiny (14,9,28)/31
approx(mapping[2].from[1], 230 / 255, "mapping[2].from R")
approx(mapping[2].from[2], 74 / 255, "mapping[2].from G")
approx(mapping[2].from[3], 33 / 255, "mapping[2].from B")
approx(mapping[2].to[1], 115 / 255, "mapping[2].to R")
approx(mapping[2].to[2], 74 / 255, "mapping[2].to G")
approx(mapping[2].to[3], 230 / 255, "mapping[2].to B")

-- ImageWriter.remapColors itself needs a real love.image.ImageData, which
-- this project's headless stub does not provide -- guarded the same way
-- other Gen2 tests handle a real-ROM-only check (see gen2_map_songs.lua),
-- skip with a clear reason rather than silently asserting nothing.
if love.image and love.image.newImageData then
  local ImageWriter = require("src.import.ImageWriter")
  local image = love.image.newImageData(2, 1)
  image:setPixel(0, 0, mapping[1].from[1], mapping[1].from[2], mapping[1].from[3], 1)
  image:setPixel(1, 0, 0, 0, 0, 1) -- black, must stay untouched
  ImageWriter.remapColors(image, mapping)
  local r, g, b, a = image:getPixel(0, 0)
  approx(r, mapping[1].to[1], "remapColors swaps a matching pixel's R")
  approx(g, mapping[1].to[2], "remapColors swaps a matching pixel's G")
  approx(b, mapping[1].to[3], "remapColors swaps a matching pixel's B")
  eq(a, 1, "remapColors leaves alpha untouched")
  local br, bg, bb = image:getPixel(1, 0)
  eq(br, 0, "remapColors leaves a non-matching (black) pixel's R untouched")
  eq(bg, 0, "remapColors leaves a non-matching (black) pixel's G untouched")
  eq(bb, 0, "remapColors leaves a non-matching (black) pixel's B untouched")
else
  print("(skipped: no love.image in this environment -- ImageWriter.remapColors " ..
    "needs a real love.image.ImageData to verify)")
end

T.finish("Gen2 Crystal shiny palette decode + ImageWriter.remapColors")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `luajit tests/engine/gen2_shiny_palette.lua`
Expected: FAIL — `RomExtractorGen2._decodeGbcPalette`/`_parseShinyPal`/`_shinyRemapTable` don't exist yet, `ImageWriter.remapColors` doesn't exist yet.

- [ ] **Step 3: Implement `ImageWriter.remapColors`**

In `src/import/ImageWriter.lua`, add after `matteColor0`:

```lua
-- Swaps every pixel matching one of mapping's `from` colors (within a
-- small tolerance -- rounding differences between this project's own GBC
-- palette decode and however the source PNG was itself rendered) to its
-- `to` color, leaving alpha and every non-matching pixel untouched.
-- mapping: array of { from = {r,g,b}, to = {r,g,b} }, components 0-1
-- (getPixel/setPixel's own range). Mutates and returns image, matching
-- matteColor0's own convention.
local COLOR_TOLERANCE = 1 / 512

local function colorMatches(r, g, b, target)
  return math.abs(r - target[1]) < COLOR_TOLERANCE
    and math.abs(g - target[2]) < COLOR_TOLERANCE
    and math.abs(b - target[3]) < COLOR_TOLERANCE
end

function ImageWriter.remapColors(image, mapping)
  local width, height = image:getDimensions()
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local r, g, b, a = image:getPixel(x, y)
      for _, entry in ipairs(mapping) do
        if colorMatches(r, g, b, entry.from) then
          image:setPixel(x, y, entry.to[1], entry.to[2], entry.to[3], a)
          break
        end
      end
    end
  end
  return image
end
```

- [ ] **Step 4: Implement the GBC palette decode helpers**

In `src/import/RomExtractorGen2.lua`, add near `readTextFile`/`fileExists` (current lines ~225-243):

```lua
-- Decodes a raw 8-byte GBC sprite palette (front.gbcpal/normal.gbcpal --
-- 4 colors x 2 bytes, little-endian BGR555) into 4 {r,g,b} triples on the
-- hardware's own 0-31 scale. Verified byte-for-byte against
-- roms/pokecrystal/gfx/pokemon/unown/normal.pal, the one species with a
-- checked-in TEXT normal palette to cross-check against -- see the
-- plan's "Research already done" section.
function RomExtractorGen2._decodeGbcPalette(bytes)
  assert(#bytes == 8, "GBC palette must be exactly 8 bytes (4 colors)")
  local colors = {}
  for i = 0, 3 do
    local lo, hi = bytes:byte(i * 2 + 1, i * 2 + 2)
    local value = lo + hi * 256
    colors[i + 1] = {
      bit.band(value, 0x1F),
      bit.band(bit.rshift(value, 5), 0x1F),
      bit.band(bit.rshift(value, 10), 0x1F),
    }
  end
  return colors
end

-- Decodes a shiny.pal's real pret source text (exactly 2 "RGB r, g, b"
-- lines, 0-31 scale, colors 1 and 2 -- colors 0/3 are always white/black
-- and never appear in this file) into 2 {r,g,b} triples on the same
-- 0-31 scale decodeGbcPalette uses.
function RomExtractorGen2._parseShinyPal(text)
  local colors = {}
  for r, g, b in text:gmatch("RGB%s+(%d+)%s*,%s*(%d+)%s*,%s*(%d+)") do
    colors[#colors + 1] = { tonumber(r), tonumber(g), tonumber(b) }
  end
  assert(#colors == 2, ("shiny.pal must have exactly 2 RGB lines, got %d"):format(#colors))
  return colors
end

-- 0-31 (GBC hardware scale) -> 0-1 float (getPixel/setPixel's own range).
local function scale5to1(v)
  return math.floor(v * 255 / 31 + 0.5) / 255
end

-- Combines a species' real normal + shiny palettes into the mapping
-- ImageWriter.remapColors consumes directly: only colors 1 and 2 ever
-- change (0/3 are always white/black, fixed across every species and
-- every shiny variant -- see the plan's "Research already done" section).
function RomExtractorGen2._shinyRemapTable(normalGbcPalBytes, shinyPalText)
  local normal = RomExtractorGen2._decodeGbcPalette(normalGbcPalBytes)
  local shiny = RomExtractorGen2._parseShinyPal(shinyPalText)
  local mapping = {}
  for i = 1, 2 do
    mapping[i] = {
      from = { scale5to1(normal[i + 1][1]), scale5to1(normal[i + 1][2]), scale5to1(normal[i + 1][3]) },
      to = { scale5to1(shiny[i][1]), scale5to1(shiny[i][2]), scale5to1(shiny[i][3]) },
    }
  end
  return mapping
end
```

`bit` is already required at the top of `RomExtractorGen2.lua` (used elsewhere in this file for collision-permission bitmasks) — confirm the existing `local bit = require("bit")` line is present; do not add a second one.

- [ ] **Step 5: Run test to verify it passes**

Run: `luajit tests/engine/gen2_shiny_palette.lua`
Expected: PASS, all checks green (the `love.image` block runs and passes if `luajit` in this environment has `love.image` available standalone, or prints the skip message otherwise — either is a pass).

- [ ] **Step 6: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add src/import/ImageWriter.lua src/import/RomExtractorGen2.lua tests/engine/gen2_shiny_palette.lua
git commit -m "feat: decode Crystal's real shiny sprite palettes

Every species' shiny.pal (real pret ROM source, 0-31 GBC scale) and
front.gbcpal/normal.gbcpal (binary, same scale, BGR555-packed) can now
be decoded into a 2-color remap table (colors 0/3 are always
white/black, fixed across every species) via
RomExtractorGen2._shinyRemapTable, feeding a new generic
ImageWriter.remapColors pixel utility. Byte-verified against Totodile's
real palettes and independently cross-checked against Unown's own
checked-in text normal.pal. No wiring into extraction yet (Task 2).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: Extract shiny sprites and wire `Sprites.path`

**Files:**
- Modify: `src/import/RomExtractorGen2.lua` (`parseCrystalSpecies`'s per-species loop)
- Modify: `src/pokemon/Sprites.lua` (`Sprites.path`)
- Test: `tests/gen2_sprites_shiny_test.lua` (new)

**Interfaces:**
- Consumes: `ImageWriter.remapColors`, `RomExtractorGen2._shinyRemapTable` (Task 1).
- Produces: `def.spriteFrontShiny` / `def.spriteBackShiny` (string paths, or `nil` when the species has no `shiny.pal`) on every Crystal `data.pokemon[species]` entry; `Sprites.path(data, species, side, opts)` picks the shiny path when `opts.mon` is shiny and one exists for that side, otherwise unchanged behavior.

- [ ] **Step 1: Write the failing test**

Create `tests/gen2_sprites_shiny_test.lua`:

```lua
-- Pins Sprites.path's shiny-sprite selection (docs/superpowers/plans/
-- 2026-08-10-gen2-crystal-shiny-sprites.md, Task 2) against a fake data
-- table -- no love.image needed, this only exercises path selection.
--   luajit tests/gen2_sprites_shiny_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

love = love or require("tests.love_stub")
local Sprites = require("src.pokemon.Sprites")

local data = {
  pokemon = {
    TOTODILE = {
      spriteFront = "assets/generated/pokemon/totodile_front.png",
      spriteBack = "assets/generated/pokemon/totodile_back.png",
      spriteFrontShiny = "assets/generated/pokemon/totodile_front_shiny.png",
      spriteBackShiny = "assets/generated/pokemon/totodile_back_shiny.png",
      trueColor = true,
    },
    -- a species with no shiny.pal in the real ROM -- must gracefully
    -- keep the normal sprite, not error.
    UNOWN = {
      spriteFront = "assets/generated/pokemon/unown_front.png",
      spriteBack = "assets/generated/pokemon/unown_back.png",
      trueColor = true,
    },
  },
}

-- shiny DVs: DEF/SPD/SPC = 10, ATK in the even-high set (Stats.isShiny)
local shinyMon = { species = "TOTODILE", dvs = { attack = 15, defense = 10, speed = 10, special = 10 } }
local plainMon = { species = "TOTODILE", dvs = { attack = 8, defense = 10, speed = 10, special = 10 } }

local path = Sprites.path(data, "TOTODILE", "front", { mon = shinyMon, kind = "battle" })
eq(path, "assets/generated/pokemon/totodile_front_shiny.png", "a shiny mon resolves the shiny front sprite")

path = Sprites.path(data, "TOTODILE", "back", { mon = shinyMon, kind = "battle" })
eq(path, "assets/generated/pokemon/totodile_back_shiny.png", "a shiny mon resolves the shiny back sprite")

path = Sprites.path(data, "TOTODILE", "front", { mon = plainMon, kind = "battle" })
eq(path, "assets/generated/pokemon/totodile_front.png", "a non-shiny mon resolves the normal front sprite")

path = Sprites.path(data, "TOTODILE", "front", {})
eq(path, "assets/generated/pokemon/totodile_front.png", "no mon in opts resolves the normal sprite (e.g. dex/menu views)")

local shinyUnown = { species = "UNOWN", dvs = { attack = 15, defense = 10, speed = 10, special = 10 } }
path = Sprites.path(data, "UNOWN", "front", { mon = shinyUnown, kind = "battle" })
eq(path, "assets/generated/pokemon/unown_front.png",
  "a species with no shiny variant gracefully falls back to its normal sprite, even when the mon is shiny")

if failed > 0 then
  print(("FAILED: %d passed, %d failed"):format(passed, failed))
  os.exit(1)
else
  print(("ALL TESTS PASSED (%d checks)"):format(passed))
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `luajit tests/gen2_sprites_shiny_test.lua`
Expected: FAIL — `Sprites.path` does not check shininess yet, every call returns the normal sprite path.

- [ ] **Step 3: Wire shiny extraction into `parseCrystalSpecies`**

In `src/import/RomExtractorGen2.lua`, inside the per-species loop (current lines ~543-592), immediately after the existing `backSource`/`fileExists(backSource)` block that saves `_back.png` and before the `out[species] = { ... }` table construction, add:

```lua
    local shinyPalSource = "roms/pokecrystal/gfx/pokemon/" .. frontStem .. "/shiny.pal"
    local normalGbcPalSource = "roms/pokecrystal/gfx/pokemon/" .. frontStem .. "/front.gbcpal"
    local spriteFrontShiny, spriteBackShiny
    if fileExists(shinyPalSource) and fileExists(normalGbcPalSource)
        and fileExists(frontSource) then
      local mapping = RomExtractorGen2._shinyRemapTable(
        readTextFile(normalGbcPalSource), readTextFile(shinyPalSource))
      -- re-derive the same cropped/matted front image the normal path
      -- already built above, then remap it -- kept as a fresh decode
      -- rather than threading the earlier local through, so this block
      -- reads standalone against the same source files.
      local full = love.image.newImageData(frontSource)
      local size = full:getWidth()
      local frame = ImageWriter.blank(size, size, 0, 0, 0, 0)
      ImageWriter.blit(frame, full, 0, 0, 0, 0, size, size)
      local shinyFront = ImageWriter.remapColors(ImageWriter.matteColor0(frame), mapping)
      self:save(shinyFront, "pokemon/" .. frontStem .. "_front_shiny.png")
      spriteFrontShiny = "assets/generated/pokemon/" .. frontStem .. "_front_shiny.png"
      if fileExists(backSource) then
        local shinyBack = ImageWriter.remapColors(
          ImageWriter.matteColor0(love.image.newImageData(backSource)), mapping)
        self:save(shinyBack, "pokemon/" .. frontStem .. "_back_shiny.png")
        spriteBackShiny = "assets/generated/pokemon/" .. frontStem .. "_back_shiny.png"
      end
    end
```

Then add the two new fields to the existing `out[species] = { ... }` table (alongside `spriteFront`/`spriteBack`):

```lua
      spriteFrontShiny = spriteFrontShiny,
      spriteBackShiny = spriteBackShiny,
```

- [ ] **Step 4: Wire the shiny check into `Sprites.path`**

In `src/pokemon/Sprites.lua`, add the `Stats` require alongside the existing `Runtime`/`FieldDefaults` requires:

```lua
local Stats = require("src.pokemon.Stats")
```

Then update `Sprites.path` (its current body, before the `Runtime.wantsHook` mod-hook block):

```lua
function Sprites.path(data, species, side, opts)
  opts = opts or {}
  local def = data and data.pokemon and data.pokemon[species]
  if not def then return nil, false end
  local path = side == "back" and def.spriteBack or def.spriteFront
  if opts.mon and opts.mon.dvs and Stats.isShiny(opts.mon.dvs) then
    local shinyPath = side == "back" and def.spriteBackShiny or def.spriteFrontShiny
    if shinyPath then path = shinyPath end
  end
  local ctx = {
    species = species,
    side = side == "back" and "back" or "front",
    kind = opts.kind or "battle",
    mon = opts.mon,
    trueColor = def.trueColor and true or false,
    data = data,
  }
  if path and Runtime.wantsHook("pokemon.sprite") then
    local hooked = Runtime.call("pokemon.sprite", samePath, path, ctx)
    if type(hooked) == "string" and hooked ~= "" then path = hooked end
  end
  return path, ctx.trueColor and true or false
end
```

(The mod-hook step is unchanged and still runs last, so a mod can still override the resolved path — shiny or not — exactly as it could before this task.)

- [ ] **Step 5: Run the test, then the full suite, then commit**

```bash
luajit tests/gen2_sprites_shiny_test.lua
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add src/import/RomExtractorGen2.lua src/pokemon/Sprites.lua tests/gen2_sprites_shiny_test.lua
git commit -m "feat: extract and apply Crystal shiny battle sprites

Every Crystal species with a real shiny.pal now gets a color-remapped
_front_shiny.png/_back_shiny.png alongside its normal sprite.
Sprites.path -- the one seam every battle pic and the summary screen
already resolve through, with the live mon already passed as opts.mon
-- picks the shiny variant whenever Stats.isShiny(mon.dvs) is true and
one exists, falling back to the normal sprite otherwise (species with
no shiny.pal, or opts.mon absent). No changes needed in BattleState.lua
or SummaryMenu.lua -- both already pass opts.mon through.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Real ROM verification (required — this is the only way to confirm the pixel-level remap, which cannot be unit-tested headlessly per this plan's Global Constraints)**

Import a Crystal ROM in a real `love .` run (or reuse an already-imported save), open the save editor on a save with a Totodile in the party, use the Shiny checkbox added earlier this session (`tools/save-editor/panels/MonEditor.lua`) to mark it shiny, save, then start a wild or trainer battle with that Totodile out and visually confirm its battle sprite is recolored (blue body → green, orange crest → purple, per this plan's own worked Totodile fixture). Also confirm a non-shiny party mon's sprite is unchanged, and that a species without a real `shiny.pal` (if one is reachable in the current save) still shows its normal sprite without error when marked shiny via the editor.

---

## Self-Review

**Spec coverage:** the user's two asks — (1) can a Pokémon be marked shiny in the save editor before starting the game, (2) does that shininess actually show up as a different sprite in battle — are both covered: (1) already shipped this session (commit `77cb112`, out of this plan's own scope), (2) is this plan's Task 1 (real palette decode) + Task 2 (extraction + wiring), landing on the exact real ROM shiny palette data the user pointed at ("pega do rom decompilado").

**Placeholder scan:** every task has real byte values (hand-derived and independently cross-checked against a second, unrelated species' checked-in text palette), real file paths (verified to exist in the real ROM checkout), and real commit messages. The one thing this plan cannot verify headlessly (the actual pixel remap against a real PNG) is called out explicitly as Task 2's own required verification step, not silently skipped — matching this project's own "real ROM verification discipline" precedent from the SFX and Milestone 2 plans.

**Type consistency:** `RomExtractorGen2._decodeGbcPalette`/`_parseShinyPal`/`_shinyRemapTable` (Task 1) are consumed exactly as defined by Task 2's extraction code; `ImageWriter.remapColors(image, mapping)`'s `mapping` shape (`{from={r,g,b}, to={r,g,b}}`, 0-1 floats) is produced by `_shinyRemapTable` and consumed unchanged by both `remapColors` itself and Task 1's own test. `def.spriteFrontShiny`/`spriteBackShiny` (Task 2, Step 3) are read by exactly the field names `Sprites.path` checks (Task 2, Step 4) — no naming drift.
