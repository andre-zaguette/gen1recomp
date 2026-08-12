-- Regression guard for Crystal SFX header parsing in
-- RomExtractorCrystal.lua: local and absolute sound_loop/sound_call targets
-- from roms/pokecrystal/audio/sfx.asm must be registered in the labels
-- map, or extractSfx will skip real Crystal effects at import time.
--   luajit tests/engine/gen2_crystal_sfx_header_parse.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local RomExtractorCrystal = require("src.import.RomExtractorCrystal")

local headers = RomExtractorCrystal._parseCrystalSfxHeaders()

local function has(headerName, channelIndex, labelName, which)
  local header = headers[headerName]
  check(header ~= nil, ("header %s exists"):format(headerName))
  local channel = header and header.channels[channelIndex]
  check(channel ~= nil, ("%s channel %d exists"):format(headerName, channelIndex))
  local bucket = channel and channel[which] or nil
  check(bucket and bucket[labelName] == true,
    ("%s channel %d records %s target %s"):format(
      headerName, channelIndex, which, labelName))
end

-- Local loop target inside the same channel.
has("Supersonic", 1, "Sfx_Supersonic_Ch5.loop", "labels")

-- Absolute self-loop target written with the full channel symbol.
has("Surf", 1, "Sfx_Surf_Ch5", "labels")
has("Protect", 2, "Sfx_Protect_Ch8", "labels")

-- Local loop target on a toggle_sfx / music-mode SFX channel.
has("Protect", 1, "Sfx_Protect_Ch5.loop1", "labels")
has("Moonlight", 1, "Sfx_Moonlight_Ch5.loop1", "labels")
has("Encore", 1, "Sfx_Encore_Ch5.loop1", "labels")

T.finish("Gen2 Crystal SFX header parsing")
