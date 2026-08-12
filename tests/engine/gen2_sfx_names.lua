-- Pins the SFX plan's manifest symbol coverage end-to-end (docs/
-- superpowers/plans/2026-08-08-gen2-crystal-sfx.md, Task 2): every real
-- Sfx_*_ChN symbol RomExtractorCrystal.lua's extractSfx references by
-- literal name must exist in the committed manifest -- the same
-- regression class Milestone 2's Task 4/5 hit twice (a Lua extractor
-- shipped without its matching manifest symbols).
--   luajit tests/engine/gen2_sfx_names.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Json = require("src.link.Json")
local f = io.open("tools/rom_manifest_crystal.json", "r")
local manifest = Json.decode(f:read("*a"))
f:close()

local EXPECTED_SYMBOLS = {
  "Sfx_Bump_Ch5", "Sfx_Cut_Ch8", "Sfx_Wrong_Ch5", "Sfx_Wrong_Ch6",
  "Sfx_BallPoof_Ch5", "Sfx_BallPoof_Ch8", "Sfx_JumpOverLedge_Ch5",
  "Sfx_Transaction_Ch5", "Sfx_Transaction_Ch6", "Sfx_EnterDoor_Ch8",
  "Sfx_KeyItem_Ch5", "Sfx_KeyItem_Ch6", "Sfx_KeyItem_Ch7",
  "Sfx_IntroWhoosh_Ch8",
}

for _, name in ipairs(EXPECTED_SYMBOLS) do
  check(manifest.symbols[name] ~= nil,
    ("manifest has a %s symbol entry"):format(name))
end

-- Runtime chip-def shape can only be checked against a real ROM import
-- (no data/generated/ in this checkout) -- if one exists locally, verify
-- every one of the 9 names resolves to a real chip def; otherwise skip
-- with a clear reason, matching gen2_map_songs.lua's own precedent.
if love.filesystem and love.filesystem.getInfo
   and love.filesystem.getInfo("data/generated/audio.lua") then
  local audio = require("data.generated.audio")
  local EXPECTED_NAMES = {
    "Collision", "Cut", "Denied", "Ball_Poof", "Ledge_Jump",
    "Withdraw_Deposit", "Go_Inside", "Get_Key_Item", "Intro_Whoosh",
  }
  for _, name in ipairs(EXPECTED_NAMES) do
    check(audio.sfx and audio.sfx[name] ~= nil,
      ("%s resolves to a real sfx def when a ROM is imported"):format(name))
  end
else
  print("(skipped: no data/generated/audio.lua in this environment -- " ..
    "runtime sfx-def shape needs a real ROM import to verify)")
end

T.finish("Gen2 SFX manifest symbol coverage")
