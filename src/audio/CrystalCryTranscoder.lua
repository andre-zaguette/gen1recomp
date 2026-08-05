-- Translates Pokemon Crystal's real sound-engine bytecode into the Lua
-- event-table shape src/audio/ChipAsm.lua already knows how to assemble
-- into a Gen1-dialect chip program. Scoped narrowly to the four opcodes
-- Wooper's three real cry channels use (duty_cycle, duty_cycle_pattern, a
-- plain note record, and the terminator) -- see
-- docs/superpowers/specs/2026-08-04-gen2-crystal-cry-transcoder-design.md
-- and docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md's
-- "Research already done" section for the verified opcode table this is
-- built from. Not a general Crystal-dialect decoder: any opcode outside
-- that set is out of scope and raises rather than guessing.

local bit = require("bit")
local ChipAsm = require("src.audio.ChipAsm")

local CrystalCryTranscoder = {}

-- packed low nibble -> signed fade, identical to src/core/ChipSynth.lua's
-- fadeValue and src/audio/ChipAsm.lua's Cursor:fade (bit 3 set means a
-- decay of the low three bits)
local function fadeValue(nibble)
  if bit.band(nibble, 8) ~= 0 then return -bit.band(nibble, 7) end
  return nibble
end

-- Decodes one Crystal-dialect cry channel program into a ChipAsm event
-- list. `bytes` is a 1-indexed array of byte values starting exactly at
-- the channel's first byte (the shape Rom:bytes(...) returns). `noise`
-- selects the noise channel's 3-byte note record (length, packed
-- volume/fade, drum parameter) over the pulse channels' 4-byte record
-- (length, packed volume/fade, 2-byte little-endian frequency register).
-- Stops at the sound_ret ($FF) terminator and returns the event list
-- (its last entry is always {ret = true}).
function CrystalCryTranscoder.decodeChannel(bytes, noise)
  local events = {}
  local i = 1
  while true do
    local cmd = bytes[i]
    if cmd == nil then
      error("CrystalCryTranscoder: ran off the end of the byte window "
        .. "before a sound_ret ($FF) terminator")
    elseif cmd == 0xFF then
      events[#events + 1] = { ret = true }
      return events
    elseif cmd == 0xDB then
      events[#events + 1] = { duty = bytes[i + 1] }
      i = i + 2
    elseif cmd == 0xDE then
      local packed = bytes[i + 1]
      events[#events + 1] = { dutyPattern = {
        bit.band(bit.rshift(packed, 6), 3),
        bit.band(bit.rshift(packed, 4), 3),
        bit.band(bit.rshift(packed, 2), 3),
        bit.band(packed, 3),
      } }
      i = i + 2
    elseif cmd < 0xD0 then
      local len = cmd
      local packed = bytes[i + 1]
      local volume = bit.rshift(packed, 4)
      local fade = fadeValue(bit.band(packed, 0x0F))
      if noise then
        events[#events + 1] = { noiseNote = {
          len = len, volume = volume, fade = fade, parameter = bytes[i + 2],
        } }
        i = i + 3
      else
        local frequency = bytes[i + 2] + bytes[i + 3] * 0x100
        events[#events + 1] = { squareNote = {
          len = len, volume = volume, fade = fade, frequency = frequency,
        } }
        i = i + 4
      end
    else
      error(("CrystalCryTranscoder: unsupported opcode $%02X at byte %d "
        .. "-- outside the set Wooper's real channels use"):format(cmd, i))
    end
  end
end

-- channels: array of {hw = 1-4, bytes = <Rom:bytes(...) array>}, one entry
-- per real Crystal channel. Returns {chip = {blob, channels, engine = 1}},
-- ready to sit directly on a data.audio.cries[SPECIES] entry (as the
-- sibling `chip` field -- see src/core/ChipAudio.lua's newCry: `cry.chip
-- and cry or cry.header`).
function CrystalCryTranscoder.buildCry(channels)
  local specs = {}
  for index, channel in ipairs(channels) do
    specs[index] = {
      hw = channel.hw,
      program = CrystalCryTranscoder.decodeChannel(channel.bytes, channel.hw == 4),
    }
  end
  return ChipAsm.sfx({ channels = specs })
end

return CrystalCryTranscoder
