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
