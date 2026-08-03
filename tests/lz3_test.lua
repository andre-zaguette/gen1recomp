-- tests/lz3_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Lz3 = require("src.import.Lz3")

local function bytesToTable(str)
  local out = {}
  for i = 1, #str do out[i] = str:byte(i) end
  return out
end

local function eqBytes(actual, expectedStr, label)
  local expected = bytesToTable(expectedStr)
  eq(#actual, #expected, label .. " length")
  for i = 1, #expected do
    eq(actual[i], expected[i], label .. " byte " .. i)
  end
end

-- cmd=0 (LITERAL), length field = 3-1 = 2 -> header 0x02
eqBytes(Lz3.decompress({ 0x02, 0x41, 0x42, 0x43, 0xFF }), "ABC", "literal")

-- cmd=1 (ITERATE) << 5 = 0x20, length field = 5-1 = 4 -> 0x24
local iterate = Lz3.decompress({ 0x24, 0x99, 0xFF })
eq(#iterate, 5, "iterate length")
for i = 1, 5 do eq(iterate[i], 0x99, "iterate byte " .. i) end

-- cmd=2 (ALTERNATE) << 5 = 0x40, length field = 6-1 = 5 -> 0x45
local alt = Lz3.decompress({ 0x45, 0xAA, 0xBB, 0xFF })
eqBytes(alt, string.char(0xAA, 0xBB, 0xAA, 0xBB, 0xAA, 0xBB), "alternate")

-- cmd=3 (ZERO) << 5 = 0x60, length field = 4-1 = 3 -> 0x63
local zero = Lz3.decompress({ 0x63, 0xFF })
eq(#zero, 4, "zero length")
for i = 1, 4 do eq(zero[i], 0, "zero byte " .. i) end

-- 3 literal bytes "ABC", then REPEAT 3 bytes from offset -3
eqBytes(Lz3.decompress({ 0x02, 0x41, 0x42, 0x43, 0x82, 0x82, 0xFF }),
  "ABCABC", "repeat negative offset")

-- 3 literal bytes "XYZ", then REPEAT 3 bytes from positive offset 0x0000
eqBytes(Lz3.decompress({ 0x02, 0x58, 0x59, 0x5A, 0x82, 0x00, 0x00, 0xFF }),
  "XYZXYZ", "repeat positive offset")

-- 1 literal byte 0xB0, then FLIP 1 byte from offset -1
local flip = Lz3.decompress({ 0x00, 0xB0, 0xA0, 0x80, 0xFF })
eqBytes(flip, string.char(0xB0, 0x0D), "flip")

-- 3 literal bytes "ABC", then REVERSE 3 bytes from offset -1 (src=2, 'C'): reads backward C,B,A
local reverse = Lz3.decompress({ 0x02, 0x41, 0x42, 0x43, 0xC2, 0x80, 0xFF })
eqBytes(reverse, "ABCCBA", "reverse")

-- LZ_LONG: inner cmd=0 (LITERAL), 32 literal bytes
local longHeader = { 0xE0, 0x1F }
for i = 0, 31 do longHeader[#longHeader + 1] = i end
longHeader[#longHeader + 1] = 0xFF
local long = Lz3.decompress(longHeader)
eq(#long, 32, "long command length")
for i = 1, 32 do eq(long[i], i - 1, "long command byte " .. i) end

T.finish("lz3_test")
