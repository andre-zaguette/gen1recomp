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
