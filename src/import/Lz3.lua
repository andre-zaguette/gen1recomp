-- LZ3 decompressor, used by Pokemon Gold/Silver/Crystal for most graphics.
-- Lua mirror of tools/extract_gen2/lz3.py -- see that file's docstring and
-- docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md for
-- the command-byte layout this implements (ported from pret/pokecrystal's
-- home/decompress.asm). Only decompresses; the game never needs recompressing.

local bit = require("bit")

local Lz3 = {}

local LZ_END = 0xFF
local CMD_LITERAL, CMD_ITERATE, CMD_ALTERNATE, CMD_ZERO = 0, 1, 2, 3
local CMD_REPEAT, CMD_FLIP, CMD_REVERSE, CMD_LONG = 4, 5, 6, 7

local function flipByte(value)
  local result = 0
  for i = 0, 7 do
    if bit.band(value, bit.lshift(1, i)) ~= 0 then
      result = bit.bor(result, bit.lshift(1, 7 - i))
    end
  end
  return result
end

function Lz3.decompress(data)
  local out = {}
  local pos = 1
  local startLen = 0 -- output length at stream start (1-indexed arrays: #out)

  local function readByte()
    local value = data[pos]
    pos = pos + 1
    return value
  end

  while true do
    local header = readByte()
    if header == LZ_END then break end
    local cmd = bit.band(bit.rshift(header, 5), 0x7)
    local length
    if cmd == CMD_LONG then
      cmd = bit.band(bit.rshift(header, 2), 0x7)
      local hi = bit.band(header, 0x3)
      local lo = readByte()
      length = bit.bor(bit.lshift(hi, 8), lo) + 1
    else
      length = bit.band(header, 0x1F) + 1
    end

    if cmd == CMD_LITERAL then
      for _ = 1, length do out[#out + 1] = readByte() end
    elseif cmd == CMD_ITERATE then
      local value = readByte()
      for _ = 1, length do out[#out + 1] = value end
    elseif cmd == CMD_ALTERNATE then
      local a, b = data[pos], data[pos + 1]
      pos = pos + 2
      for i = 1, length do
        out[#out + 1] = (i % 2 == 1) and a or b
      end
    elseif cmd == CMD_ZERO then
      for _ = 1, length do out[#out + 1] = 0 end
    elseif cmd == CMD_REPEAT or cmd == CMD_FLIP or cmd == CMD_REVERSE then
      local offsetByte = readByte()
      local src
      if bit.band(offsetByte, 0x80) ~= 0 then
        local magnitude = bit.band(offsetByte, 0x7F)
        src = #out - magnitude - 1
      else
        local lo = readByte()
        src = startLen + bit.bor(bit.lshift(offsetByte, 8), lo)
      end
      for i = 0, length - 1 do
        if cmd == CMD_REPEAT then
          out[#out + 1] = out[src + i + 1]
        elseif cmd == CMD_FLIP then
          out[#out + 1] = flipByte(out[src + i + 1])
        else
          out[#out + 1] = out[src - i + 1]
        end
      end
    else
      error("unknown LZ3 command " .. tostring(cmd))
    end
  end
  return out
end

return Lz3
