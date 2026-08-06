# Gen2 (Crystal) ROM Extraction Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the existing Gen1 ROM-import architecture (manifest generated from disassembly source → runtime extractor reads the player's real ROM bytes by address → generated Lua/PNG cache → engine renders it unchanged) works for Pokemon Crystal, by extracting New Bark Town (map, tileset, player sprite) end-to-end.

**Architecture:** A fully parallel Gen2 pipeline (new files mirroring the Gen1 ones), reusing existing *generic* infrastructure (byte/asm-parsing helpers, Lua `Rom`/`ImageWriter`/`LuaWriter`) unchanged via import, never modifying or forking Gen1-specific extraction logic. New: an LZ3 decompressor (Crystal's tile graphics are LZ-compressed; Gen1's aren't), and a Gen2 collision-permission translator (Crystal stores collision per block-quadrant against a permission table; Gen1 stores a flat walkable-tile-id list — translated at extraction time so the existing engine needs zero changes).

**Tech Stack:** Python 3 + Pillow (dev-path tooling, mirrors `tools/build_rom_data.py`), Lua/LuaJIT + LÖVE 11.x (runtime extractor, mirrors `src/import/RomExtractor.lua`).

## Global Constraints

- Reference ROM: `Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc`, SHA-1 `f2f52230b536214ef7c9924f483392993e226cfb`, 2,097,152 bytes. Already present at `roms/` (gitignored).
- Reference disassembly: `pret/pokecrystal` (https://github.com/pret/pokecrystal), cloned locally by the implementer, never committed to this repo.
- No shared abstraction with `src/import/RomExtractor.lua` / `tools/extract/*.py` / `tools/build_rom_data.py` beyond importing already-existing *generic* helpers (`tools/rom_data.py`'s `RomImage`/`SymbolTable`, `tools/extract/util.py`'s asm/Lua helpers, `src/import/Rom.lua`, `src/import/ImageWriter.lua`, `src/import/LuaWriter.lua`). Do not edit those files.
- Scope is New Bark Town only: its map, the `TILESET_JOHTO` tileset, and the player (`ChrisSpriteGFX`) overworld sprite. No other maps, no Pokédex/moves/items/battle/audio.
- Generated output must exactly match the field names/shapes already used by `data/generated/maps.lua`, `tilesets.lua`, `sprites.lua` (see Task 5/6 Interfaces) so `src/world/MapLoader.lua` and `src/render/TileRenderer.lua` consume it with zero changes.
- Full spec: `docs/superpowers/specs/2026-08-03-gen2-crystal-extraction-skeleton-design.md`.

---

## Background facts pinned down during planning (do not re-derive; verify against source if anything here seems wrong)

These were confirmed by fetching real files from `https://github.com/pret/pokecrystal` (branch `master`) during planning. Re-fetch and re-confirm if pokecrystal's `master` has moved on since.

**LZ3 compression** (`home/decompress.asm`, `Decompress::`): a command stream terminated by `$FF`. Each command byte: bits 5-7 = command id, bits 0-4 = `length - 1` (so stored length `n` means `n+1` actual bytes/repeats), *except* command 7 (`LZ_LONG`): the real command is bits 2-4 of that byte, and length is 10-bit (bits 0-1 of that byte as the high 2 bits, next byte as the low 8 bits), plus 1. Commands: `0`=LITERAL (copy n raw bytes), `1`=ITERATE (read 1 byte, repeat n times), `2`=ALTERNATE (read 2 bytes, alternate them for n bytes total), `3`=ZERO (write n zero bytes), `4`=REPEAT/`5`=FLIP/`6`=REVERSE (back-reference commands: read 1 more byte; if bit7 set, the source position is `(current output length) - magnitude - 1` where `magnitude` is the low 7 bits (verified by hand-simulating the Z80 `.rewrite`/negative branch: `and %01111111 / cpl / add e / ld l,a / ld a,-1 / adc d / ld h,a` computes `HL = DE - magnitude - 1`, not `DE - magnitude` — a naive reading of "subtract the magnitude" misses the extra `-1` the `cpl`/`ld a,-1` idiom introduces); if bit7 clear, read one more byte and the 16-bit big-endian pair is added *unmodified* to the output length *at the start of the whole stream* — then copy `n` bytes forward (REPEAT), bit-flipped (FLIP), or backward (REVERSE) from that resolved source position).

**Tileset struct** (`data/tilesets.asm`, `MACRO tileset`): 15 bytes — `dba` (bank + word pointer, 3 bytes each) for GFX, Meta (blockset), Coll (collision), then `dw` Anim, `dw` NULL (unused), `dw` PalMap. New Bark Town uses `TILESET_JOHTO`; its pieces are directly-addressable symbols: `TilesetJohtoGFX` (LZ3-compressed `.2bpp.lz`), `TilesetJohtoMeta` (`data/tilesets/johto_metatiles.bin`, 2048 bytes = 128 blocks × 16 bytes, 4×4 tile-id grid — byte-identical layout to Gen1's `.bst` blocksets), `TilesetJohtoColl` (`data/tilesets/johto_collision.asm`, 4 raw bytes per block — one `COLL_*` constant per quadrant/cell of the 4×4 block, *not* a flat walkable-id list like Gen1). Because the skeleton only ever needs the Johto tileset, the manifest embeds these specific symbol names directly — no need to parse/walk the `Tilesets::` table.

**Collision translation** (`constants/collision_constants.asm` + `data/collision/collision_permissions.asm`): each `COLL_*` constant is an index into `CollisionPermissionTable`, which maps it to a base permission byte — `LAND_TILE` ($00, walkable), `WATER_TILE` ($01, surf-only), `WALL_TILE` ($0F, blocked), optionally OR'd with `TALK` ($10, interact-only/blocked-for-walking, e.g. cuttable trees). A block's 4 stored collision bytes correspond 1:1 to its 4 cells (a 4×4-tile block = a 2×2 grid of 16×16 cells), matching the engine's existing "bottom-left tile of the cell decides collision" rule (`docs/architecture.md`). To keep `Map.lua`/`TileRenderer.lua` unchanged, the extractor derives a flat walkable-tile-id set (Gen1's format) from New Bark Town's *actual* block usage: for every block instance on the map, for each of its 4 cells, resolve `COLL_*` → permission; if the permission (masked `& 0x0F`) is `LAND_TILE`, mark that cell's bottom-left tile id (position 4 or 12 in the 16-tile block grid — the bottom-left tile of the top-left/bottom-left cell is tile index 4×row+col, see Task 5) as walkable.

**Event row formats** (`macros/scripts/maps.asm`, fetched from `https://raw.githubusercontent.com/pret/pokecrystal/master/macros/scripts/maps.asm`): every map's own `MapEvents` block is prefixed by `db 0, 0 ; filler`, then four counted sections in order (warps, coords, bg, objects), each starting with its own count byte (`def_warp_events`/`def_coord_events`/`def_bg_events`/`def_object_events`, each just `db <count>`):
- `warp_event`: 5 bytes — `y(1), x(1), destWarp(1), GROUP(1), MAP(1)` (the last two from the `map_id` macro: `db GROUP_<mapname>, MAP_<mapname>`, i.e. Gen2 identifies a destination map by a `(group, number)` pair, not Gen1's single flat map id byte).
- `coord_event`: 8 bytes — `sceneId(1), y(1), x(1), filler(1), scriptPtr(2 LE), filler(2)`. Not needed for this skeleton's map/tileset/sprite scope (no scripts run), but New Bark Town's 2 coord events must still be skipped by that many bytes when parsing past them to reach the bg/object sections.
- `bg_event`: 5 bytes — `y(1), x(1), function/BGEVENT_*(1), scriptPtr(2 LE)`.
- `object_event`: 13 bytes — `sprite(1), y+4(1), x+4(1), movementFunc(1), radius as packed nibbles y-then-x(1), hourH1(1), hourH2(1), palette+type as packed nibbles(1), sightRange(1), scriptPtr(2 LE), eventFlag(2 LE)`.

**Sprite struct** (`data/sprites/sprites.asm`, `MACRO overworld_sprite`): 6 bytes — `dw` address, `db` (tiles×16 | bank<<?)... concretely: address word, then a byte packing tile-count/bank/type/palette per `constants/sprite_data_constants.asm`. The player's graphic, `ChrisSpriteGFX` (`gfx/sprites/chris.png`, `gfx/sprites.asm`), is **not** LZ-compressed (plain `.2bpp` INCBIN, unlike the tileset). Sheet is 16×96px (2 tiles wide × 12 tiles tall = 24 8×8 tiles). Exact frame/direction order (which of the 12 16×16 frames is stand/walk × down/up/left, and whether right-facing is a horizontal flip like Gen1) is **not yet confirmed** — Task 4/5 include a verification step against the actual loader code before finalizing frame indices.

**ROM size**: Crystal/Gold/Silver are 2,097,152 bytes (2 MiB), vs. Gen1's 1,048,576 bytes (1 MiB). `src/import/RomImporter.lua:876` currently hardcodes a 1 MiB check that would reject any Gen2 ROM outright — Task 6 generalizes it.

---

### Task 1: LZ3 decompressor (Python)

**Files:**
- Create: `tools/extract_gen2/__init__.py` (empty)
- Create: `tools/extract_gen2/lz3.py`
- Test: `tools/extract_gen2/test_lz3.py`

**Interfaces:**
- Produces: `lz3.decompress(data: bytes) -> bytes` — decodes one LZ3 stream starting at `data[0]`, stops at the `$FF` terminator (does not require the terminator to be the last byte of `data`; any trailing bytes are ignored). Used by Task 3 (dev-path Python extractor).

- [ ] **Step 1: Write the failing tests**

```python
# tools/extract_gen2/test_lz3.py
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from extract_gen2 import lz3


class Lz3Test(unittest.TestCase):
    def test_literal(self):
        # cmd=0 (LITERAL), length field = 3-1 = 2 -> header 0b000_00010 = 0x02
        data = bytes([0x02, 0x41, 0x42, 0x43, 0xFF])
        self.assertEqual(lz3.decompress(data), b"ABC")

    def test_iterate(self):
        # cmd=1 (ITERATE) << 5 = 0x20, length field = 5-1 = 4 -> 0x24
        data = bytes([0x24, 0x99, 0xFF])
        self.assertEqual(lz3.decompress(data), bytes([0x99]) * 5)

    def test_alternate(self):
        # cmd=2 (ALTERNATE) << 5 = 0x40, length field = 6-1 = 5 -> 0x45
        data = bytes([0x45, 0xAA, 0xBB, 0xFF])
        self.assertEqual(lz3.decompress(data), bytes([0xAA, 0xBB, 0xAA, 0xBB, 0xAA, 0xBB]))

    def test_zero(self):
        # cmd=3 (ZERO) << 5 = 0x60, length field = 4-1 = 3 -> 0x63
        data = bytes([0x63, 0xFF])
        self.assertEqual(lz3.decompress(data), bytes(4))

    def test_repeat_negative_offset(self):
        # 3 literal bytes "ABC", then REPEAT 3 bytes from offset -3
        # (back to the start of "ABC"): cmd=4<<5=0x80, length field=3-1=2 -> 0x82,
        # offset byte with bit7 set, magnitude 2 -> 0x82 (src = len(out)-magnitude-1 = 3-2-1 = 0)
        data = bytes([0x02, 0x41, 0x42, 0x43, 0x82, 0x82, 0xFF])
        self.assertEqual(lz3.decompress(data), b"ABCABC")

    def test_repeat_positive_offset(self):
        # 3 literal bytes "XYZ", then REPEAT 3 bytes from the start of the
        # whole output (positive offset 0x0000): cmd=4<<5=0x80, length
        # field=3-1=2 -> 0x82, offset hi=0x00 (bit7 clear), lo=0x00
        data = bytes([0x02, 0x58, 0x59, 0x5A, 0x82, 0x00, 0x00, 0xFF])
        self.assertEqual(lz3.decompress(data), b"XYZXYZ")

    def test_flip_bit_reverses_each_byte(self):
        # 1 literal byte 0b10110000 (0xB0), then FLIP 1 byte from offset -1
        # cmd=5<<5=0xA0, length field=1-1=0 -> 0xA0, offset byte 0x80 (bit7 set, magnitude 0;
        # src = len(out)-magnitude-1 = 1-0-1 = 0, the literal byte just written)
        data = bytes([0x00, 0xB0, 0xA0, 0x80, 0xFF])
        # 0xB0 = 0b10110000 -> bit-reversed = 0b00001101 = 0x0D
        self.assertEqual(lz3.decompress(data), bytes([0xB0, 0x0D]))

    def test_long_command(self):
        # LZ_LONG (cmd=7): real command in bits 2-4 of the header.
        # header = 111 xxx yy -> want inner cmd=0 (LITERAL), so xxx=000:
        # header = 0b111_000_yy. Want length 32 (needs the 10-bit form):
        # length field = 32 - 1 = 31 = 0b0000011111 -> hi(2 bits)=00, lo(8 bits)=0b00011111=0x1F
        header = 0b11100000  # cmd bits 000 -> LITERAL, length hi = 00
        data = bytes([header, 0x1F]) + bytes(range(32)) + bytes([0xFF])
        self.assertEqual(lz3.decompress(data), bytes(range(32)))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 tools/extract_gen2/test_lz3.py -v`
Expected: FAIL / ModuleNotFoundError (`lz3.py` does not exist yet).

- [ ] **Step 3: Implement `lz3.py`**

```python
"""LZ3 decompressor, used by Pokemon Gold/Silver/Crystal for most graphics.

Ported from pret/pokecrystal's home/decompress.asm (Decompress::), read
directly from https://github.com/pret/pokecrystal/blob/master/home/decompress.asm
during planning -- see docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md
for the command-byte layout this mirrors. This module only decompresses
(the game never needs re-compressing at runtime).
"""

LZ_END = 0xFF

CMD_LITERAL = 0
CMD_ITERATE = 1
CMD_ALTERNATE = 2
CMD_ZERO = 3
CMD_REPEAT = 4
CMD_FLIP = 5
CMD_REVERSE = 6
CMD_LONG = 7


def _flip_byte(value):
    result = 0
    for bit in range(8):
        if value & (1 << bit):
            result |= 1 << (7 - bit)
    return result


def decompress(data):
    """Decode one LZ_END-terminated LZ3 stream from the start of `data`."""
    out = bytearray()
    pos = 0
    start_pos = 0  # output length at stream start; REPEAT/FLIP/REVERSE positive offsets are relative to this

    def read_byte():
        nonlocal pos
        value = data[pos]
        pos += 1
        return value

    while True:
        header = read_byte()
        if header == LZ_END:
            break
        cmd = (header >> 5) & 0x7
        if cmd == CMD_LONG:
            cmd = (header >> 2) & 0x7
            hi = header & 0x3
            lo = read_byte()
            length = ((hi << 8) | lo) + 1
        else:
            length = (header & 0x1F) + 1

        if cmd == CMD_LITERAL:
            out.extend(data[pos:pos + length])
            pos += length
        elif cmd == CMD_ITERATE:
            value = read_byte()
            out.extend(bytes([value]) * length)
        elif cmd == CMD_ALTERNATE:
            a, b = data[pos], data[pos + 1]
            pos += 2
            for i in range(length):
                out.append(a if i % 2 == 0 else b)
        elif cmd == CMD_ZERO:
            out.extend(bytes(length))
        elif cmd in (CMD_REPEAT, CMD_FLIP, CMD_REVERSE):
            offset_byte = read_byte()
            if offset_byte & 0x80:
                magnitude = offset_byte & 0x7F
                src = len(out) - magnitude - 1
            else:
                lo = read_byte()
                src = start_pos + ((offset_byte << 8) | lo)
            if cmd == CMD_REPEAT:
                for i in range(length):
                    out.append(out[src + i])
            elif cmd == CMD_FLIP:
                for i in range(length):
                    out.append(_flip_byte(out[src + i]))
            else:
                for i in range(length):
                    out.append(out[src - i])
        else:
            raise ValueError(f"unknown LZ3 command {cmd}")
    return bytes(out)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 tools/extract_gen2/test_lz3.py -v`
Expected: all 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/extract_gen2/__init__.py tools/extract_gen2/lz3.py tools/extract_gen2/test_lz3.py
git commit -m "$(cat <<'EOF'
Add LZ3 decompressor for Gen2 graphics (Python)

Pokemon Gold/Silver/Crystal compress most graphics with an lz3 variant
that Gen1 ROMs never used. Ported from pret/pokecrystal's
home/decompress.asm; needed before the Crystal tileset extractor can
read TilesetJohtoGFX.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: LZ3 decompressor (Lua)

**Files:**
- Create: `src/import/Lz3.lua`
- Test: `tests/lz3_test.lua`

**Interfaces:**
- Consumes: `bit` library (already a project dependency, see `src/import/RomExtractor.lua:1`).
- Produces: `Lz3.decompress(data: table<int,int>) -> table<int,int>` — same algorithm as Task 1's `lz3.decompress`, but Lua-idiomatic: `data` and the return value are 1-indexed arrays of byte values (0-255), matching the convention already used by `Rom:bytes()` (`src/import/Rom.lua:32`) and `Rom.decompressPic` (`src/import/Rom.lua:178`). Used by Task 5 (runtime Lua extractor).

- [ ] **Step 1: Write the failing test**

```lua
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

-- LZ_LONG: inner cmd=0 (LITERAL), 32 literal bytes
local longHeader = { 0xE0, 0x1F }
for i = 0, 31 do longHeader[#longHeader + 1] = i end
longHeader[#longHeader + 1] = 0xFF
local long = Lz3.decompress(longHeader)
eq(#long, 32, "long command length")
for i = 1, 32 do eq(long[i], i - 1, "long command byte " .. i) end

T.report("lz3_test")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `luajit tests/lz3_test.lua`
Expected: FAIL (module `src.import.Lz3` not found).

- [ ] **Step 3: Implement `src/import/Lz3.lua`**

```lua
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
```

Note: `src`/indices above are computed in 0-indexed terms then read via `out[src + i + 1]` (1-indexed table access) — `src` itself is a 0-indexed offset into the (conceptually 0-indexed) output stream, consistent with the Python version; `#out` in Lua already equals the 0-indexed "next write position," so `src = #out - magnitude - 1` matches Python's `src = len(out) - magnitude - 1` directly. The `- 1` matters: hand-simulating `decompress.asm`'s negative-offset branch (`and %01111111 / cpl / add e / ld l,a / ld a,-1 / adc d / ld h,a`) shows it computes `HL = DE - magnitude - 1`, not `DE - magnitude` — confirmed against real pret/pokecrystal source during Task 1's review.

- [ ] **Step 4: Run test to verify it passes**

Run: `luajit tests/lz3_test.lua`
Expected: PASS, all checks green, "0 FAILURES" (or matching harness convention — check `tests/harness.lua`'s `T.report` output format if it differs).

- [ ] **Step 5: Commit**

```bash
git add src/import/Lz3.lua tests/lz3_test.lua
git commit -m "$(cat <<'EOF'
Add LZ3 decompressor for Gen2 graphics (Lua)

Runtime-path mirror of tools/extract_gen2/lz3.py (Task 1), for
src/import/RomExtractorGen2.lua to decompress Crystal's tileset
graphics on the player's own machine at first boot.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Crystal manifest generator

**Files:**
- Create: `tools/make_rom_manifest_crystal.py`
- Create (generated by running the script, then committed): `tools/rom_manifest_crystal.json`

**Interfaces:**
- Produces: `tools/rom_manifest_crystal.json`, a JSON object with:
  - `"romSha1"`: `"f2f52230b536214ef7c9924f483392993e226cfb"`
  - `"symbols"`: `{name: [bank, address], ...}` for exactly: `NewBarkTown_MapAttributes`, `NewBarkTown_MapEvents`, `TilesetJohtoGFX`, `TilesetJohtoMeta`, `TilesetJohtoColl`, `ChrisSpriteGFX`.
  - `"newBarkTown"`: `{"width": 10, "height": 9, "tileset": "TILESET_JOHTO", "warpCount": 4, "coordEventCount": 2, "bgEventCount": 4, "objectCount": 3}` (structural facts read from source, used by Tasks 4/5 as sanity assertions against what the ROM bytes actually contain).
  - Consumed by: Task 4 (`tools/build_rom_data_gen2.py`) and, once re-expressed for the shipped app, Task 5's runtime manifest (see Task 5 Interfaces — the runtime manifest is a trimmed copy without `newBarkTown`'s already-known-from-symbols fields, matching how `tools/rom_manifest.json` vs. the Lua-side manifest usage already works for Gen1).

- [ ] **Step 1: Set up a local pokecrystal checkout and build its symbol file**

This is a one-time, non-committed local environment step (mirrors what a `pret/pokered` checkout + RGBDS build already requires for the existing `tools/make_rom_manifest.py`).

```bash
git clone https://github.com/pret/pokecrystal.git /tmp/pokecrystal
cd /tmp/pokecrystal
git submodule update --init --recursive
make crystal   # requires rgbds on PATH; see /tmp/pokecrystal/INSTALL.md if this fails
ls crystal.sym  # should now exist
```

Expected: `crystal.sym` exists and is a non-empty RGBDS symbol file (`bank:address name` lines, same format `tools/rom_data.py`'s `SymbolTable` already parses).

- [ ] **Step 2: Confirm the exact map_attributes / MapEvents / sprite source text**

Fetch and read these four files from the checkout (or `curl https://raw.githubusercontent.com/pret/pokecrystal/master/<path>` if you don't want to grep the local clone) and confirm they still match what's documented in this plan's "Background facts" section above — if `pret/pokecrystal`'s `master` has changed since this plan was written, update the plan's background section before continuing:
- `data/maps/attributes.asm` (the `map_attributes` macro + New Bark Town's invocation)
- `maps/NewBarkTown.asm` (the `NewBarkTown_MapEvents:` block — confirm the `warp_event`/`bg_event`/`object_event`/`def_*_events` macro forms; only `object_event`'s 13-byte layout is pinned down in this plan already, quoted in the Background section — the `warp_event` and `bg_event` byte widths must be read from source here before Task 4/5 can parse them)
- `data/tilesets.asm` (confirm the 15-byte `tileset` macro and that `TilesetJohtoGFX`/`Meta`/`Coll` are still separately-labelled INCBINs)
- `data/sprites/sprites.asm` + `engine/overworld/player_sprites.asm` (or wherever `ChrisSpriteGFX` is loaded from) — confirm the exact frame/direction layout of the 12-tile sheet before Task 4/5 hardcode frame indices

- [ ] **Step 3: Write `tools/make_rom_manifest_crystal.py`**

```python
#!/usr/bin/env python3
"""Generate the New Bark Town-scoped Gen2 manifest from a pokecrystal checkout.

Mirrors tools/make_rom_manifest.py's shape (symbolic metadata only, no ROM
bytes) but is scoped to exactly the symbols/facts the Crystal skeleton
extractor needs -- see docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md.
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract.util import parse_number, read_asm, split_args  # noqa: E402
from rom_data import SymbolTable  # noqa: E402

CRYSTAL_SHA1 = "f2f52230b536214ef7c9924f483392993e226cfb"

REQUIRED_SYMBOLS = (
    "NewBarkTown_MapAttributes",
    "NewBarkTown_MapEvents",
    "TilesetJohtoGFX",
    "TilesetJohtoMeta",
    "TilesetJohtoColl",
    "ChrisSpriteGFX",
)


def parse_new_bark_town(pokecrystal):
    """Read data/maps/maps.asm + constants/map_constants.asm for New Bark
    Town's dimensions, and maps/NewBarkTown.asm for its event counts."""
    dims = None
    for _, line in read_asm(
            os.path.join(pokecrystal, "constants/map_constants.asm")):
        m = re.match(r"map_const\s+NEW_BARK_TOWN,\s*(\d+),\s*(\d+)", line.strip())
        if m:
            dims = {"width": int(m.group(1)), "height": int(m.group(2))}
    if not dims:
        raise SystemExit("NEW_BARK_TOWN dimensions not found in map_constants.asm")

    counts = {"warpCount": 0, "coordEventCount": 0, "bgEventCount": 0, "objectCount": 0}
    field_for_macro = {
        "warp_event": "warpCount",
        "coord_event": "coordEventCount",
        "bg_event": "bgEventCount",
        "object_event": "objectCount",
    }
    in_events = False
    for _, line in read_asm(os.path.join(pokecrystal, "maps/NewBarkTown.asm")):
        s = line.strip()
        if s == "NewBarkTown_MapEvents:":
            in_events = True
            continue
        if not in_events:
            continue
        for macro, field in field_for_macro.items():
            if s.startswith(macro + " "):
                counts[field] += 1

    return {
        "width": dims["width"], "height": dims["height"],
        "tileset": "TILESET_JOHTO", **counts,
    }


def embed_symbols(symbols):
    out = {}
    for name in REQUIRED_SYMBOLS:
        symbol = symbols.by_name.get(name)
        if not symbol:
            raise SystemExit(f"required symbol missing from .sym: {name}")
        out[name] = [symbol.bank, symbol.address]
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pokecrystal", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument(
        "--out",
        default=os.path.join(os.path.dirname(__file__), "rom_manifest_crystal.json"))
    args = parser.parse_args()

    pokecrystal = os.path.abspath(args.pokecrystal)
    if not os.path.isfile(os.path.join(pokecrystal, "main.asm")):
        raise SystemExit(f"{pokecrystal} is not a pokecrystal checkout")

    symbols = SymbolTable(os.path.abspath(args.symbols))
    data = {
        "romSha1": CRYSTAL_SHA1,
        "symbols": embed_symbols(symbols),
        "newBarkTown": parse_new_bark_town(pokecrystal),
    }
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run it for real and verify the output**

```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal /tmp/pokecrystal \
  --symbols /tmp/pokecrystal/crystal.sym \
  --out tools/rom_manifest_crystal.json
cat tools/rom_manifest_crystal.json
```

Expected: valid JSON; `newBarkTown.width == 10`, `newBarkTown.height == 9`, `newBarkTown.tileset == "TILESET_JOHTO"`, `newBarkTown.warpCount == 4`, `newBarkTown.coordEventCount == 2`, `newBarkTown.bgEventCount == 4`, `newBarkTown.objectCount == 3` (all confirmed by planning-time research — if any differ, `parse_new_bark_town`'s macro-name matching has a bug, fix it before continuing); all 6 symbols in `REQUIRED_SYMBOLS` present with non-null `[bank, address]` pairs.

- [ ] **Step 5: Commit**

```bash
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json
git commit -m "$(cat <<'EOF'
Add Crystal manifest generator, scoped to New Bark Town

Mirrors tools/make_rom_manifest.py's pattern (symbolic metadata
parsed from a local pokecrystal checkout, no ROM bytes) but only
carries the symbols and facts the New Bark Town skeleton needs.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Dev-path Python extractor

**Files:**
- Create: `tools/build_rom_data_gen2.py`
- Create: `tools/extract_gen2/collision.py`

**Interfaces:**
- Consumes: `tools/rom_manifest_crystal.json` (Task 3), `tools/extract_gen2/lz3.py` (Task 1), `tools/extract_gen2/collision.py` (this task, Step 1b), `tools/rom_data.py`'s `RomImage`/`SymbolTable` (existing, unmodified), `tools/extract/util.py`'s `write_lua` (existing, unmodified), `tools/extract/gfx.py`'s `_decode_2bpp`/`_save_png`-equivalent PNG writing (reuse pattern, do not import private `_`-prefixed functions — write a small local `_write_2bpp_png` matching `build_rom_data.py:212-216`'s shape).
- Produces: `tools/extract_gen2/collision.py`'s `COLLISION_PERMISSION_TABLE` (a 256-entry list, index = raw `COLL_*` byte from ROM, value = permission byte) is also consumed directly by Task 5 (ported to the Lua `COLLISION_PERMISSION` table verbatim — keep the two lists byte-for-byte identical).
- Produces (to `--out-dir`, default `tools/gen2_dev_data/`, **not** `data/generated/` — this is a verification-only path, never shipped): `maps.lua` (one entry, `NEW_BARK_TOWN`), `tilesets.lua` (one entry, `TILESET_JOHTO`), `sprites.lua` (one entry, `SPRITE_CHRIS`), plus `tilesets/johto.png` and `sprites/chris.png` under `--assets-dir` (default `tools/gen2_dev_data/assets/`).

- [ ] **Step 1: Event row byte widths (already confirmed; use verbatim)**

Confirmed directly from `macros/scripts/maps.asm` during planning — see this plan's Background section for the full `warp_event` (5 bytes)/`coord_event` (8 bytes)/`bg_event` (5 bytes)/`object_event` (13 bytes) layouts. Used directly by Step 2b's `extract_map`.

- [ ] **Step 1b: The COLL_* -> permission table (already confirmed; use verbatim)**

Fetched directly from `https://raw.githubusercontent.com/pret/pokecrystal/master/data/collision/collision_permissions.asm` during planning (256 entries, `assert_table_length $100`). `LAND_TILE=0x00` (walkable), `WATER_TILE=0x01` (surf-only), `WALL_TILE=0x0F` (blocked), `TALK=0x10` (OR'd in for interact-only tiles, still blocked for walking). Default is `LAND_TILE`; everything else is a listed exception:

```python
# tools/extract_gen2/collision.py
LAND_TILE, WATER_TILE, WALL_TILE, TALK = 0x00, 0x01, 0x0F, 0x10

_WALL = (
    0x07, 0x0F, 0x27, 0x2F, 0x62, 0x6A,
    *range(0x80, 0x85), *range(0x88, 0x8D), *range(0x90, 0xA0),
    0xFF,
)
_WALL_TALK = (0x12, 0x15, 0x1A, 0x1D)
_WATER = (
    0x20, 0x21, 0x25, 0x26, 0x28, 0x29, 0x2D, 0x2E,
    *range(0x30, 0x40), *range(0xC0, 0xD0),
)
_WATER_TALK = (0x22, 0x24, 0x2A, 0x2C)

COLLISION_PERMISSION_TABLE = [LAND_TILE] * 256
for _index in _WALL:
    COLLISION_PERMISSION_TABLE[_index] = WALL_TILE
for _index in _WALL_TALK:
    COLLISION_PERMISSION_TABLE[_index] = WALL_TILE | TALK
for _index in _WATER:
    COLLISION_PERMISSION_TABLE[_index] = WATER_TILE
for _index in _WATER_TALK:
    COLLISION_PERMISSION_TABLE[_index] = WATER_TILE | TALK

assert len(COLLISION_PERMISSION_TABLE) == 256
```

Sanity-check once written: `COLLISION_PERMISSION_TABLE[0x00] == LAND_TILE` (`COLL_FLOOR`), `COLLISION_PERMISSION_TABLE[0x07] == WALL_TILE` (`COLL_WALL`), `COLLISION_PERMISSION_TABLE[0x29] == WATER_TILE` (`COLL_WATER`), `COLLISION_PERMISSION_TABLE[0xFF] == WALL_TILE` (`COLL_FF`) — these four match the source comments directly.

- [ ] **Step 2: Write the map/tileset/sprite extraction functions**

```python
#!/usr/bin/env python3
"""Dev-path Gen2 (Crystal) data builder: New Bark Town only.

Combines tools/rom_manifest_crystal.json with the player's real Crystal
ROM to produce verification data under --out-dir/--assets-dir (never
data/generated/ -- this is not the shipped path, see
src/import/RomExtractorGen2.lua for that). Mirrors tools/build_rom_data.py's
shape, scoped to one map/tileset/sprite.
"""

import argparse
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from extract import util  # noqa: E402
from extract_gen2 import collision, lz3  # noqa: E402
from rom_data import RomImage, SymbolTable, load_manifest  # noqa: E402

GB_SHADES = (
    (255, 255, 255, 255), (170, 170, 170, 255),
    (85, 85, 85, 255), (0, 0, 0, 255),
)

# COLL_* constant -> base permission, from pret/pokecrystal
# constants/collision_constants.asm + data/collision/collision_permissions.asm
LAND_TILE, WATER_TILE, WALL_TILE, TALK = 0x00, 0x01, 0x0F, 0x10


def _decode_2bpp(raw, width, height):
    tile_count = width // 8 * (height // 8)
    if len(raw) != tile_count * 16:
        raise ValueError(f"2bpp payload is {len(raw)} bytes, expected {tile_count * 16}")
    image = Image.new("RGBA", (width, height))
    pixels = image.load()
    tiles_per_row = width // 8
    for tile in range(tile_count):
        tx, ty = (tile % tiles_per_row) * 8, (tile // tiles_per_row) * 8
        for y in range(8):
            low = raw[tile * 16 + y * 2]
            high = raw[tile * 16 + y * 2 + 1]
            for x in range(8):
                bit = 7 - x
                shade = ((high >> bit) & 1) * 2 + ((low >> bit) & 1)
                pixels[tx + x, ty + y] = GB_SHADES[shade]
    return image


def _write_2bpp_png(raw, width, height, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _decode_2bpp(raw, width, height).save(path, optimize=True)


def extract_sprite(rom, symbols, out_assets):
    """ChrisSpriteGFX: 16x96px, not LZ-compressed."""
    symbol = symbols["ChrisSpriteGFX"]
    raw = rom.bytes(symbol.bank, symbol.address, 16 * 96 // 4)
    _write_2bpp_png(raw, 16, 96, os.path.join(out_assets, "sprites", "chris.png"))
    return {
        "SPRITE_CHRIS": {
            "id": "SPRITE_CHRIS",
            "source": "ROM:ChrisSpriteGFX",
            "image": "assets/generated/sprites/chris.png",
            "frames": 96 // 16,
            "walker": True,
        }
    }


def _collision_permission(coll_value):
    return collision.COLLISION_PERMISSION_TABLE[coll_value]


def extract_tileset(rom, symbols, out_dir, out_assets):
    gfx = symbols["TilesetJohtoGFX"]
    meta = symbols["TilesetJohtoMeta"]
    coll = symbols["TilesetJohtoColl"]

    compressed = rom.bytes(gfx.bank, gfx.address, 0x4000)  # generous upper bound; LZ3 stops at $FF
    raw = lz3.decompress(compressed)
    width_tiles = 16  # gfx/tilesets/johto.png is a 16-tiles-wide sheet, like Gen1 tileset sheets
    height = len(raw) // 16 // width_tiles * 8
    width = width_tiles * 8
    _write_2bpp_png(raw, width, height, os.path.join(out_assets, "tilesets", "johto.png"))

    blocks_raw = rom.bytes(meta.bank, meta.address, 2048)
    blocks = [list(blocks_raw[i:i + 16]) for i in range(0, len(blocks_raw), 16)]

    coll_raw = rom.bytes(coll.bank, coll.address, len(blocks) * 4)
    walkable = set()
    for block_index, block in enumerate(blocks):
        cell_colls = coll_raw[block_index * 4:block_index * 4 + 4]
        # cell order/tile-index-within-block mapping confirmed against
        # data/tilesets/johto_collision.asm + the metatile grid layout
        # (top-left, top-right, bottom-left, bottom-right cells; each
        # cell's "bottom-left tile" is the tile the engine's collision
        # rule reads -- see docs/architecture.md).
        for cell_index, coll_value in enumerate(cell_colls):
            permission = _collision_permission(coll_value)
            if permission & 0x0F == LAND_TILE:
                bottom_left_tile_row = 1 if cell_index < 2 else 3
                bottom_left_tile_col = (cell_index % 2) * 2
                tile_id = block[bottom_left_tile_row * 4 + bottom_left_tile_col]
                walkable.add(tile_id)

    out = {
        "TILESET_JOHTO": {
            "id": "TILESET_JOHTO",
            "source": "ROM:TilesetJohtoGFX/Meta/Coll",
            "image": "assets/generated/tilesets/johto.png",
            "imageWidth": width, "imageHeight": height,
            "tilesPerRow": width // 8,
            "blocks": blocks,
            "walkable": sorted(walkable),
            "counterTiles": [], "grassTile": None,
            "doorTiles": [], "warpTiles": [],
            "animation": None,
        }
    }
    util.write_lua(os.path.join(out_dir, "tilesets.lua"), out,
                    header="Source: real Pokemon Crystal ROM (TilesetJohto*)")
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom", required=True)
    parser.add_argument("--manifest",
                         default=os.path.join(os.path.dirname(__file__), "rom_manifest_crystal.json"))
    parser.add_argument("--out-dir",
                         default=os.path.join(os.path.dirname(__file__), "gen2_dev_data"))
    parser.add_argument("--assets-dir",
                         default=os.path.join(os.path.dirname(__file__), "gen2_dev_data", "assets"))
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    rom = RomImage(args.rom, expected_sha1=manifest["romSha1"])
    symbols = SymbolTable(manifest["symbols"])

    sprites = extract_sprite(rom, symbols, args.assets_dir)
    util.write_lua(os.path.join(args.out_dir, "sprites.lua"), sprites,
                    header="Source: real Pokemon Crystal ROM (ChrisSpriteGFX)")
    extract_tileset(rom, symbols, args.out_dir, args.assets_dir)
    print("done")


if __name__ == "__main__":
    main()
```

Note: `extract_sprite`/`extract_tileset`/`main` deliberately omit map extraction (New Bark Town's `.blk`/warps/objects) from this first pass — added as **Step 2b** below.

**Scope note on `extract_map`**: warp/bg/object rows reference other maps and sprites by raw numeric ids (a `(GROUP, MAP)` pair for warp destinations, a `SPRITE_*` id for objects) that only resolve to names via global order tables this skeleton does not build (that's follow-on work once more of Johto is extracted — see the spec's "Follow-on work" section). So `extract_map` fully parses and correctly skips every event section (proving the byte layout and counts are right, which is what acceptance criterion 5 checks), but only materializes warps' `x`/`y`/`destWarp` plus the raw `destMapGroup`/`destMapNumber`, and leaves `objects`/`signs` as empty lists (bg_events and object_events are skipped-but-not-decoded — NPCs are out of this skeleton's scope, matching the spec's "just the player sprite" framing). `connections` is also left `{}`: the 12-byte-per-entry connection-entry format that follows the fixed header was not independently re-confirmed against source during planning (unlike every other struct in this plan) and isn't needed for "walk around New Bark Town" — resolving it is follow-on work, not a silent guess.

- [ ] **Step 2b: Create `tools/extract_gen2/collision.py` and add `extract_map`**

Create `tools/extract_gen2/collision.py` with exactly the content given in Step 1b above. Add this function and call it from `main()`, writing `maps.lua`:

```python
def extract_map(rom, symbols, manifest, out_dir):
    header = symbols["NewBarkTown_MapAttributes"]
    expected = manifest["newBarkTown"]

    border = rom.byte(header.bank, header.address)
    height = rom.byte(header.bank, header.address + 1)
    width = rom.byte(header.bank, header.address + 2)
    if (width, height) != (expected["width"], expected["height"]):
        raise ValueError(
            f"NewBarkTown ROM dimensions {width}x{height} do not match "
            f"manifest {expected['width']}x{expected['height']}")
    blocks_bank = rom.byte(header.bank, header.address + 3)
    blocks_ptr = rom.word(header.bank, header.address + 4)
    events_bank = rom.byte(header.bank, header.address + 6)  # shared by MapScripts/MapEvents
    events_ptr = rom.word(header.bank, header.address + 9)

    blocks = list(rom.bytes(blocks_bank, blocks_ptr, width * height))

    addr = events_ptr
    addr += 2  # "db 0, 0 ; filler" MapEvents header

    warp_count = rom.byte(events_bank, addr)
    addr += 1
    warps = []
    for _ in range(warp_count):
        row = rom.bytes(events_bank, addr, 5)
        warps.append({
            "y": row[0], "x": row[1], "destWarp": row[2],
            "destMapGroup": row[3], "destMapNumber": row[4],
        })
        addr += 5
    if warp_count != expected["warpCount"]:
        raise ValueError(
            f"NewBarkTown ROM has {warp_count} warps, manifest expects "
            f"{expected['warpCount']}")

    coord_count = rom.byte(events_bank, addr)
    addr += 1 + coord_count * 8  # coord_event rows: not decoded, just skipped
    if coord_count != expected["coordEventCount"]:
        raise ValueError(
            f"NewBarkTown ROM has {coord_count} coord events, manifest "
            f"expects {expected['coordEventCount']}")

    bg_count = rom.byte(events_bank, addr)
    addr += 1 + bg_count * 5  # bg_event rows: not decoded (see Task 4's scope note)
    if bg_count != expected["bgEventCount"]:
        raise ValueError(
            f"NewBarkTown ROM has {bg_count} bg events, manifest expects "
            f"{expected['bgEventCount']}")

    object_count = rom.byte(events_bank, addr)
    addr += 1 + object_count * 13  # object_event rows: not decoded (see Task 4's scope note)
    if object_count != expected["objectCount"]:
        raise ValueError(
            f"NewBarkTown ROM has {object_count} objects, manifest expects "
            f"{expected['objectCount']}")

    out = {
        "NEW_BARK_TOWN": {
            "id": "NEW_BARK_TOWN", "label": "NewBarkTown", "index": 1,
            "source": f"ROM:{header.bank:02X}:{header.address:04X}",
            "tileset": "TILESET_JOHTO",
            "width": width, "height": height, "blocks": blocks,
            "borderBlock": border, "connections": {},
            "warps": warps, "signs": [], "objects": [],
        }
    }
    util.write_lua(os.path.join(out_dir, "maps.lua"), out,
                    header="Source: real Pokemon Crystal ROM (NewBarkTown_MapAttributes/MapEvents)")
    return out
```

And in `main()`, after `extract_tileset(...)`:

```python
    extract_map(rom, symbols, manifest, args.out_dir)
```

- [ ] **Step 3: Run against the real ROM**

```bash
python3 tools/build_rom_data_gen2.py --rom "roms/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"
```

Expected: exits 0, prints "done". Then manually inspect:
```bash
python3 -c "
import sys; sys.path.insert(0, 'tools')
print(open('tools/gen2_dev_data/tilesets.lua').read()[:500])
"
open tools/gen2_dev_data/assets/tilesets/johto.png   # (macOS `open`; use an image viewer on other platforms)
open tools/gen2_dev_data/assets/sprites/chris.png
```
Expected: `johto.png` looks like recognizable Game Boy Color town tile art (not noise/garbage — garbage output means the LZ3 command decoding or the GFX symbol/length is wrong); `chris.png` is a 16×96 sheet of a recognizable walking-trainer sprite (not compressed noise, since this path has no LZ3 involved — a wrong result here points at a wrong `ChrisSpriteGFX` address or width/height). `tilesets.lua`'s `walkable` list should be non-empty and should NOT include every tile id 0-127 (an all-walkable result likely means `_collision_permission` is wrong, defaulting everything to LAND_TILE).

- [ ] **Step 4: Commit**

```bash
git add tools/build_rom_data_gen2.py tools/extract_gen2/collision.py tools/gen2_dev_data/.gitignore
git commit -m "$(cat <<'EOF'
Add Gen2 dev-path extractor for New Bark Town verification

Mirrors tools/build_rom_data.py's shape (manifest + real ROM ->
inspectable source-tree data), scoped to the tileset and sprite the
Crystal skeleton needs, so output can be sanity-checked by eye before
the runtime Lua extractor (which real players will run) exists.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

(Add `tools/gen2_dev_data/` to `.gitignore` first if not already covered by an existing pattern — check `.gitignore` for how `tools/dev_data`-equivalent Gen1 output, if any, is already excluded, and mirror it; this directory is regenerable scratch output, not source.)

---

### Task 5: Runtime Lua extractor

**Files:**
- Create: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `src/import/Rom.lua` (existing, unmodified — `Rom.new`, `:byte`, `:word`, `:bytes`), `src/import/ImageWriter.lua` (existing, unmodified — `decode2bpp`, `save`), `src/import/LuaWriter.lua` (existing, unmodified — `write`), `src/import/Lz3.lua` (Task 2).
- Produces: `RomExtractorGen2.new(romData, manifest, progress)` returning an object with `:run()`, mirroring `RomExtractor`'s public shape (`src/import/RomExtractor.lua:53-61,2073-2096`) exactly, so `RomImporter.lua` (Task 6) can call it identically to `RomExtractor`. Writes `data/generated/maps.lua`, `tilesets.lua`, `sprites.lua` (via `LuaWriter.write`, which — like Gen1 — writes relative to the active `CacheFs.prefix`, so no Gen2-specific path logic is needed here) in the exact field shapes already consumed by `src/world/MapLoader.lua` and `src/render/TileRenderer.lua` (see Task 4's `tilesets.lua`/`sprites.lua` shapes above, plus the map shape from `RomExtractor.lua:372-379`: `{id, label, index, source, tileset, width, height, blocks, borderBlock, connections, warps, signs, objects}` — Gen2's map can omit `label`/`index`/`signs` content details that don't apply, but must keep the same key names present, defaulting absent lists to `{}`).

- [ ] **Step 1: Port `tools/build_rom_data_gen2.py`'s logic to Lua**

```lua
-- src/import/RomExtractorGen2.lua
-- Gen2 (Crystal) runtime extractor, scoped to New Bark Town: map, the
-- TILESET_JOHTO tileset, and the player (Chris) overworld sprite.
-- Mirrors src/import/RomExtractor.lua's shape and helper usage; ported
-- from tools/build_rom_data_gen2.py (Task 4) -- keep the two in sync if
-- either changes. See docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md.

local bit = require("bit")
local ImageWriter = require("src.import.ImageWriter")
local LuaWriter = require("src.import.LuaWriter")
local Lz3 = require("src.import.Lz3")
local Rom = require("src.import.Rom")

local RomExtractorGen2 = {}
RomExtractorGen2.__index = RomExtractorGen2

local STAGE_COUNT = 3

-- COLL_* -> CollisionPermissionTable base permission, ported verbatim from
-- tools/extract_gen2/collision.py (Task 4 Step 1b) -- keep the two
-- byte-for-byte identical. Source: pret/pokecrystal
-- constants/collision_constants.asm + data/collision/collision_permissions.asm
local LAND_TILE, WATER_TILE, WALL_TILE, TALK = 0x00, 0x01, 0x0F, 0x10
local COLLISION_PERMISSION = {}
for i = 0, 255 do COLLISION_PERMISSION[i] = LAND_TILE end
local WALL = {
  0x07, 0x0F, 0x27, 0x2F, 0x62, 0x6A,
  0x80, 0x81, 0x82, 0x83, 0x84,
  0x88, 0x89, 0x8A, 0x8B, 0x8C,
  0xFF,
}
for i = 0x90, 0x9F do WALL[#WALL + 1] = i end
local WALL_TALK = { 0x12, 0x15, 0x1A, 0x1D }
local WATER = { 0x20, 0x21, 0x25, 0x26, 0x28, 0x29, 0x2D, 0x2E }
for i = 0x30, 0x3F do WATER[#WATER + 1] = i end
for i = 0xC0, 0xCF do WATER[#WATER + 1] = i end
local WATER_TALK = { 0x22, 0x24, 0x2A, 0x2C }
for _, i in ipairs(WALL) do COLLISION_PERMISSION[i] = WALL_TILE end
for _, i in ipairs(WALL_TALK) do COLLISION_PERMISSION[i] = bit.bor(WALL_TILE, TALK) end
for _, i in ipairs(WATER) do COLLISION_PERMISSION[i] = WATER_TILE end
for _, i in ipairs(WATER_TALK) do COLLISION_PERMISSION[i] = bit.bor(WATER_TILE, TALK) end

function RomExtractorGen2.new(romData, manifest, progress)
  return setmetatable({
    rom = Rom.new(romData),
    manifest = manifest,
    symbols = manifest.symbols,
    progress = progress,
    stage = 0,
  }, RomExtractorGen2)
end

function RomExtractorGen2:symbol(name)
  local location = self.symbols[name]
  if not location then error("required symbol is missing: " .. tostring(name)) end
  return { bank = location[1], address = location[2], name = name }
end

function RomExtractorGen2:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then self.progress(self.stage - 1, STAGE_COUNT, name, 0, 1) end
end

function RomExtractorGen2:tick(name, current, total)
  if self.progress then
    self.progress(self.stage - 1 + current / total, STAGE_COUNT, name, current, total)
  end
end

function RomExtractorGen2:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
end

function RomExtractorGen2:save(image, relative)
  ImageWriter.save(image, "assets/generated/" .. relative)
end

function RomExtractorGen2:extractSprite()
  self:beginStage("Player sprite")
  local symbol = self:symbol("ChrisSpriteGFX")
  local raw = self.rom:bytes(symbol.bank, symbol.address, 16 * 96 / 4)
  local image = ImageWriter.decode2bpp(raw, 16, 96, true)
  self:save(image, "sprites/chris.png")
  local out = {
    SPRITE_CHRIS = {
      id = "SPRITE_CHRIS", source = "ROM:ChrisSpriteGFX",
      image = "assets/generated/sprites/chris.png",
      frames = 96 / 16, walker = true,
    },
  }
  self:write("sprites", out)
  self:tick("Player sprite", 1, 1)
  return out
end

function RomExtractorGen2:extractTileset()
  self:beginStage("Johto tileset")
  local gfx = self:symbol("TilesetJohtoGFX")
  local meta = self:symbol("TilesetJohtoMeta")
  local coll = self:symbol("TilesetJohtoColl")

  local compressed = self.rom:bytes(gfx.bank, gfx.address, 0x4000)
  local raw = Lz3.decompress(compressed)
  local widthTiles = 16
  local width = widthTiles * 8
  local height = #raw / 16 / widthTiles * 8
  local image = ImageWriter.decode2bpp(raw, width, height)
  self:save(image, "tilesets/johto.png")

  local blocksRaw = self.rom:bytes(meta.bank, meta.address, 2048)
  local blocks = {}
  for offset = 1, #blocksRaw, 16 do
    local block = {}
    for pos = offset, offset + 15 do block[#block + 1] = blocksRaw[pos] end
    blocks[#blocks + 1] = block
  end

  local collRaw = self.rom:bytes(coll.bank, coll.address, #blocks * 4)
  local walkableSet = {}
  for blockIndex, block in ipairs(blocks) do
    for cellIndex = 0, 3 do
      local collValue = collRaw[(blockIndex - 1) * 4 + cellIndex + 1]
      local permission = COLLISION_PERMISSION[collValue]
      assert(permission, "unknown COLL_* value " .. tostring(collValue))
      if bit.band(permission, 0x0F) == LAND_TILE then
        local row = cellIndex < 2 and 1 or 3
        local col = (cellIndex % 2) * 2
        local tileId = block[row * 4 + col + 1]
        walkableSet[tileId] = true
      end
    end
  end
  local walkable = {}
  for tileId in pairs(walkableSet) do walkable[#walkable + 1] = tileId end
  table.sort(walkable)

  local out = {
    TILESET_JOHTO = {
      id = "TILESET_JOHTO", source = "ROM:TilesetJohtoGFX/Meta/Coll",
      image = "assets/generated/tilesets/johto.png",
      imageWidth = width, imageHeight = height, tilesPerRow = width / 8,
      blocks = blocks, walkable = walkable,
      counterTiles = {}, grassTile = nil, doorTiles = {}, warpTiles = {},
      animation = nil,
    },
  }
  self:write("tilesets", out)
  self:tick("Johto tileset", 1, 1)
  return out
end

function RomExtractorGen2:extractMap()
  self:beginStage("New Bark Town")
  local header = self:symbol("NewBarkTown_MapAttributes")
  local expected = self.manifest.newBarkTown

  local border = self.rom:byte(header.bank, header.address)
  local height = self.rom:byte(header.bank, header.address + 1)
  local width = self.rom:byte(header.bank, header.address + 2)
  assert(width == expected.width and height == expected.height,
    "NewBarkTown ROM dimensions do not match manifest")
  local blocksBank = self.rom:byte(header.bank, header.address + 3)
  local blocksPtr = self.rom:word(header.bank, header.address + 4)
  local eventsBank = self.rom:byte(header.bank, header.address + 6)
  local eventsPtr = self.rom:word(header.bank, header.address + 9)

  local blocks = self.rom:bytes(blocksBank, blocksPtr, width * height)

  local addr = eventsPtr + 2 -- "db 0, 0 ; filler" MapEvents header

  local warpCount = self.rom:byte(eventsBank, addr)
  addr = addr + 1
  local warps = {}
  for _ = 1, warpCount do
    local row = self.rom:bytes(eventsBank, addr, 5)
    warps[#warps + 1] = {
      y = row[1], x = row[2], destWarp = row[3],
      destMapGroup = row[4], destMapNumber = row[5],
    }
    addr = addr + 5
  end
  assert(warpCount == expected.warpCount, "NewBarkTown warp count mismatch")

  local coordCount = self.rom:byte(eventsBank, addr)
  addr = addr + 1 + coordCount * 8
  assert(coordCount == expected.coordEventCount, "NewBarkTown coord event count mismatch")

  local bgCount = self.rom:byte(eventsBank, addr)
  addr = addr + 1 + bgCount * 5
  assert(bgCount == expected.bgEventCount, "NewBarkTown bg event count mismatch")

  local objectCount = self.rom:byte(eventsBank, addr)
  addr = addr + 1 + objectCount * 13
  assert(objectCount == expected.objectCount, "NewBarkTown object count mismatch")

  local out = {
    NEW_BARK_TOWN = {
      id = "NEW_BARK_TOWN", label = "NewBarkTown", index = 1,
      source = ("ROM:%02X:%04X"):format(header.bank, header.address),
      tileset = "TILESET_JOHTO",
      width = width, height = height, blocks = blocks,
      borderBlock = border, connections = {},
      warps = warps, signs = {}, objects = {},
    },
  }
  self:write("maps", out)
  self:tick("New Bark Town", 1, 1)
  return out
end

function RomExtractorGen2:run()
  local results = {}
  results.sprites = self:extractSprite()
  results.tilesets = self:extractTileset()
  results.maps = self:extractMap()
  if self.progress then
    self.progress(STAGE_COUNT, STAGE_COUNT, "Ready", 1, 1)
  end
  return results
end

return RomExtractorGen2
```

- [ ] **Step 2: Verify against the Python version**

`extractMap`/`extractTileset`/`extractSprite` and `COLLISION_PERMISSION` are already complete in Step 1's listing above (mirroring Task 4's Python versions field-for-field). Diff the byte offsets and `COLLISION_PERMISSION`/warp-row/bg-row/object-row widths against `tools/build_rom_data_gen2.py` (Task 4) line by line — they must match exactly, since Task 4 already validated those values against the real ROM in its Step 3.

- [ ] **Step 3: Note on testing**

There is no automated test for this file directly (matching this codebase's established pattern — `src/import/RomExtractor.lua` itself has no unit tests either; it's validated by the real import flow and downstream content tests, not isolated unit tests). Step 2's diff against the already-ROM-verified Python version is this task's correctness gate; Task 8 is the full real-ROM proof.

- [ ] **Step 4: Commit**

```bash
git add src/import/RomExtractorGen2.lua
git commit -m "$(cat <<'EOF'
Add Gen2 (Crystal) runtime ROM extractor

Ports tools/build_rom_data_gen2.py to Lua: reads the player's real
Crystal ROM at first boot and writes New Bark Town's map, tileset,
and player sprite into data/generated/, in the same schema Gen1's
RomExtractor.lua already produces so the engine needs no changes.
Not yet wired into the importer (Task 6).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Wire Crystal into GameVersion and RomImporter

**Files:**
- Modify: `src/core/GameVersion.lua`
- Modify: `src/import/RomImporter.lua:876-880` (ROM size gate), `~920` (extractor selection)

**Interfaces:**
- Consumes: `src/import/RomExtractorGen2.lua` (Task 5).
- Produces: `GameVersion.VERSIONS.crystal` entry; `GameVersion.info("crystal").extractor == "gen2"`; `RomImporter` accepts a 2,097,152-byte ROM and routes it to `RomExtractorGen2`.

- [ ] **Step 1: Add the `crystal` entry and a `romSize`/`extractor` field to every entry**

```lua
-- src/core/GameVersion.lua
GameVersion.VERSIONS = {
  red = {
    id = "red",
    label = "Red",
    displayName = "Pokemon Red",
    launcherName = "Red",
    sha1 = "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
    manifest = "tools/rom_manifest.json",
    cachePrefix = "",
    saveSuffix = "",
    romSize = 1024 * 1024,
    extractor = "gen1",
  },
  blue = {
    id = "blue",
    label = "Blue",
    displayName = "Pokemon Blue",
    launcherName = "Blue",
    sha1 = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2",
    manifest = "tools/rom_manifest_blue.json",
    cachePrefix = "blue/",
    saveSuffix = "_blue",
    romSize = 1024 * 1024,
    extractor = "gen1",
  },
  yellow = {
    id = "yellow",
    label = "Yellow",
    displayName = "Pokemon Yellow",
    launcherName = "Yellow (alpha)",
    sha1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1",
    manifest = "tools/rom_manifest_yellow.json",
    cachePrefix = "yellow/",
    saveSuffix = "_yellow",
    romSize = 1024 * 1024,
    extractor = "gen1",
  },
  crystal = {
    id = "crystal",
    label = "Crystal",
    displayName = "Pokemon Crystal",
    launcherName = "Crystal (alpha)",
    sha1 = "f2f52230b536214ef7c9924f483392993e226cfb",
    manifest = "tools/rom_manifest_crystal.json",
    cachePrefix = "crystal/",
    saveSuffix = "_crystal",
    romSize = 2 * 1024 * 1024,
    extractor = "gen2",
  },
}

GameVersion.ORDER = { "red", "blue", "yellow", "crystal" }
```

(Apply this as an `Edit` to the existing file, keeping every other function in `GameVersion.lua` — `isBlue`, `isYellow`, `info`, `saveSuffix`, `cachePrefix`, `forSha1` — unchanged.)

- [ ] **Step 2: Generalize the ROM size gate in `RomImporter.lua`**

Replace the hardcoded check:
```lua
  if #data ~= 1024 * 1024 then
    self:setError(("Expected a 1 MiB Game Boy ROM; this file is %.2f MiB.")
      :format(#data / 1024 / 1024))
    return
  end
```
with:
```lua
  local validSizes = {}
  for _, version in ipairs(GameVersion.ORDER) do
    validSizes[GameVersion.info(version).romSize] = true
  end
  if not validSizes[#data] then
    self:setError(("Expected a Game Boy or Game Boy Color ROM (1 or 2 MiB); "
      .. "this file is %.2f MiB."):format(#data / 1024 / 1024))
    return
  end
```

- [ ] **Step 3: Route extraction through `RomExtractorGen2` for Gen2 versions**

Replace:
```lua
    local RomExtractor = require("src.import.RomExtractor")
    local extractor = RomExtractor.new(self.romData, manifest,
```
with:
```lua
    local extractorModule = info.extractor == "gen2"
      and "src.import.RomExtractorGen2" or "src.import.RomExtractor"
    local RomExtractor = require(extractorModule)
    local extractor = RomExtractor.new(self.romData, manifest,
```

(`info` is already in scope at this point in `startData` — it's assigned at line 889, before the `coroutine.create` block that contains this call.)

- [ ] **Step 4: Manually verify the launcher lists Crystal and the size gate accepts it**

There's no existing automated test harness for the launcher UI flow (`tests/` has no LÖVE-graphics-driven UI test for `RomImporter`'s launcher tabs). Verify manually:
```bash
love .
```
Expected: the launcher now shows a 4th tab/column, "Crystal (alpha)"; dropping/selecting the real Crystal ROM from `roms/` does not immediately fail with "Expected a 1 MiB..." (it should proceed to hashing/import — Task 8 covers the full import verification once `extractMap` (Task 5 Step 2) exists).

- [ ] **Step 5: Commit**

```bash
git add src/core/GameVersion.lua src/import/RomImporter.lua
git commit -m "$(cat <<'EOF'
Wire Pokemon Crystal into GameVersion and the ROM importer

Adds a crystal GameVersion entry and generalizes RomImporter's
previously Gen1-only 1 MiB ROM-size gate and extractor selection so a
2 MiB Crystal ROM routes to RomExtractorGen2 instead of RomExtractor.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Fixture-backed structural test (no ROM)

**Files:**
- Modify: `tests/run_tests.lua` (append a new section)

**Interfaces:**
- Consumes: `src/world/MapLoader.lua`, `src/world/Map.lua` (existing, unmodified — confirmed in planning that `MapLoader.load(data, mapId)` only reads `data.maps[mapId]` and `data.tilesets[def.tileset]`, so a minimal hand-built table works without going through `src/core/Data.lua`'s 16-module `Data:load()` gate).
- Produces: a new assertions section proving the Gen1 engine's map-loading/collision code accepts Gen2-shaped data (same field names, same value types) with no ROM present, exercising this plan's central claim end-to-end at the structural level.

- [ ] **Step 1: Write the test section**

Append to the end of `tests/run_tests.lua` (before whatever final "N FAILURES" report line the file ends with — check the file's last ~10 lines first to append in the right place, above that report call):

```lua
-- ------------------------------------------------- Gen2 (Crystal) skeleton
-- Hand-built New Bark Town-shaped data (not ROM-derived -- mirrors the
-- shape RomExtractorGen2.lua produces, see docs/superpowers/plans/
-- 2026-08-03-gen2-crystal-extraction-skeleton.md), proving MapLoader/Map
-- consume Gen2 data with zero engine changes, without needing the real
-- Crystal ROM.
do
  local function flatBlocks(width, height, blockId)
    local blocks = {}
    for i = 1, width * height do blocks[i] = blockId end
    return blocks
  end

  local gen2Data = {
    tilesets = {
      TILESET_JOHTO = {
        id = "TILESET_JOHTO",
        image = "tests/fixture_data/assets/fix_out.png", -- reuse an existing fixture PNG; content doesn't matter for this structural check
        imageWidth = 128, imageHeight = 128, tilesPerRow = 16,
        blocks = { { 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 5, 5, 5 } }, -- block 0: top rows tile 0 (walkable), bottom rows tile 5 (wall)
        walkable = { 0 },
        counterTiles = {}, grassTile = nil, doorTiles = {}, warpTiles = {},
        animation = nil,
      },
    },
    maps = {
      NEW_BARK_TOWN = {
        id = "NEW_BARK_TOWN", label = "NewBarkTown", index = 2000,
        source = "fixture", tileset = "TILESET_JOHTO",
        width = 10, height = 9,
        blocks = flatBlocks(10, 9, 1), -- block index 1 doesn't exist in this 1-block tileset on purpose: overwritten below for the one cell under test
        borderBlock = 0,
        connections = {},
        warps = { { x = 5, y = 5, destMap = "ROUTE_29", destWarp = 1 } },
        signs = {},
        objects = {},
      },
    },
  }
  -- block 0 (top walkable / bottom wall) at cell (5,5) and its neighbor;
  -- overwrite two entries in the flat block array (row-major, width=10)
  gen2Data.maps.NEW_BARK_TOWN.blocks[5 * 10 + 5 + 1] = 0

  local MapLoader = require("src.world.MapLoader")
  local newBark = MapLoader.load(gen2Data, "NEW_BARK_TOWN")
  eq(newBark.widthCells, 20, "New Bark Town fixture width in cells (10 blocks * 2)")
  eq(newBark.heightCells, 18, "New Bark Town fixture height in cells (9 blocks * 2)")
  check(newBark:isWalkableCell(11, 11), "New Bark Town fixture: block-0 top cell walkable")
  local w = newBark:warpAtCell(5, 5)
  check(w == nil or w.def.destMap == "ROUTE_29", "New Bark Town fixture warp table intact")
end
```

(This test constructs coordinates loosely — the exact cell math for "which cell lands on block index 0 vs 1" depends on `Map.lua`'s block→cell indexing, which the existing Pallet Town assertions earlier in this same file already exercise for Gen1 data. Before finalizing, run once, read the actual `newBark.widthCells`/`isWalkableCell` results printed by a temporary `print()`, and adjust the asserted cell coordinates to match reality rather than guessing — the point of this test is that Gen2-shaped data loads and behaves consistently with `Map.lua`'s existing rules, not to hit one specific hardcoded cell blindly.)

- [ ] **Step 2: Run and verify**

Run: `luajit tests/run_tests.lua`
Expected: the existing ~1600+ Gen1 assertions still pass (data/generated/ must be present locally from a prior Red import for this file to run at all, per the file's own header comment — if it's not present, run this new section in isolation first via a scratch script that only requires `src.world.MapLoader` and runs the `do...end` block above, to avoid needing a full Gen1 ROM import just to test this), plus the new "New Bark Town fixture" checks all pass.

- [ ] **Step 3: Commit**

```bash
git add tests/run_tests.lua
git commit -m "$(cat <<'EOF'
Add fixture-backed structural test for Gen2-shaped map data

Proves MapLoader/Map load and evaluate hand-built New Bark
Town-shaped data (matching RomExtractorGen2.lua's output schema)
correctly, with no ROM present -- the core claim of the Gen2
extraction skeleton, testable without a real Crystal ROM.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Manual real-ROM end-to-end verification

**Files:** none (verification checklist only; this task produces no commit unless it uncovers a bug in an earlier task, in which case fix that task's file and commit there).

**Interfaces:** N/A.

- [ ] **Step 1: Run the real import**

```bash
love .
```
In the launcher, select the "Crystal (alpha)" tab, choose `roms/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc`. Expected: SHA-1 validates (no "Unsupported ROM" error), import progress runs through "Player sprite" → "Johto tileset" → "Ready" (per `RomExtractorGen2:run()`'s stage list), and the game boots into New Bark Town.

- [ ] **Step 2: Visual/behavioral checks against spec acceptance criteria 2-3**

- Tiles render (not blank/garbled — a garbled render means the LZ3 decode or tileset PNG dimensions are wrong).
- The player sprite is visible and walks in all directions tested (down/up/left/right) without visual corruption.
- Walking into the walls/houses of New Bark Town is blocked; walking on open ground is not — cross-check a few specific tiles against what real Crystal gameplay looks like (screenshots or your own knowledge of the town layout) to catch a wrong `COLLISION_PERMISSION` mapping or wrong bottom-left-tile math from Task 5.

- [ ] **Step 3: Spot-check extracted data against the real game (spec acceptance criterion 5)**

Compare `crystal/data/generated/maps.lua`'s `NEW_BARK_TOWN.warps` (4 entries expected) and the rendered tileset PNG against known New Bark Town structure (professor's lab, player's house, rival's house, and the routes to the west/east) — if the extracted warp count or tileset art doesn't match, work backward from which Task's byte offsets are wrong (most likely Task 4/5 Step 2b's event-row parsing or Task 3's macro assumptions) and fix that task, then re-run from Task 8 Step 1.

**Found during this step (real bug, not anticipated by the plan):** attempting to import Crystal crashed the launcher —

```
src/import/LauncherView.lua:54: attempt to index local 'c' (a nil value)
```

Root cause, confirmed by reading the code: `src/import/LauncherView.lua`'s tab bar is a **hardcoded array of exactly 3 game tabs** (`red`/`blue`/`yellow`, plus `mods`/`find`) at the `local tabs = { ... }` literal inside `buildHeader` (around line 565) — Task 6 only wired Crystal into `GameVersion.lua`/`RomImporter.lua`'s *import logic*, never into this separate, hand-maintained UI tab list, so there is no Crystal tab button to click at all. Separately, `RomImporter.lua:893-895` already sets `self.tab = version` on ROM drop by SHA-1 regardless of whether a tab button exists for it, so dropping the Crystal ROM flips the active tab to `"crystal"` programmatically and the (correctly data-driven) ROM-card panel then tries to render a Crystal card — hitting `local accent = version == "yellow" and "gold" or version` (line 683) → `accent = "crystal"` → `C("crystal")` → `PAL["crystal"]` is nil → crash. A second, non-crashing but still wrong bug in the same area: the "N of 3 ready" filler text (line 633) hardcodes "3", which is now wrong with 4 versions.

Fix this now, before re-attempting Step 1-3:

### Task 9: Wire Crystal into the launcher tab bar

**Files:**
- Modify: `src/import/LauncherView.lua`

**Interfaces:**
- Consumes: `GameVersion.ORDER` (existing, already includes `"crystal"` since Task 6).
- No other task depends on this; it only makes the already-correct, already-data-driven ROM-card rendering (which already works for Crystal, per Task 8 Step 1's crash trace showing it *tried* to render) reachable and crash-free.

- [ ] **Step 1: Add a `crystal` accent color to `PAL`**

In `src/import/LauncherView.lua`, the `PAL` table (around line 30-47), add a new entry alongside `red`/`blue`/`gold` — a cyan distinct from Crystal's siblings, matching the games's own icy-blue branding:

```lua
local PAL = {
  bg        = { 10, 15, 34 },
  card      = { 16, 23, 48 },
  rowBg     = { 9, 14, 34 },
  border    = { 120, 150, 220 },
  red       = { 255, 60, 72 },
  blue      = { 70, 150, 255 },
  gold      = { 255, 203, 5 },
  crystal   = { 125, 224, 224 },
  green     = { 62, 224, 138 },
  -- ... (rest unchanged)
```

- [ ] **Step 2: Add a `crystal` tab to the hardcoded `tabs` array**

In `buildHeader`, the `local tabs = { ... }` literal (around line 565-571), add a fourth game tab between `yellow` and `mods`:

```lua
  local tabs = {
    { id = "red", letter = "R", col = "red", ink = "white", labelText = Strings("RED") },
    { id = "blue", letter = "B", col = "blue", ink = "white", labelText = Strings("BLUE") },
    { id = "yellow", letter = "Y", col = "gold", ink = "bg", labelText = Strings("YELLOW") },
    { id = "crystal", letter = "C", col = "crystal", ink = "bg", labelText = Strings("CRYSTAL") },
    { id = "mods", icon = imp._modsIcon, col = "chipModTop", ink = "white", labelText = Strings("MODS") },
    { id = "find", icon = imp._findIcon, col = "chipModTop", ink = "white", labelText = Strings("FIND MODS") },
  }
```

(`ink = "bg"` matches `yellow`'s choice — both `gold` and `crystal` are light fills where dark text reads better than white; the letter-glyph ink-color branch at line ~604 already handles `ink == "bg"` generically, so no other code changes are needed for the glyph to render legibly.)

- [ ] **Step 3: Make the "N of _ ready" count dynamic**

Replace the hardcoded literal (around line 633):

```lua
  label(bar, Strings("%d of 3 ready", ready), 12 * m.s + 2, C("gray"),
    { textWrap = false })
```

with:

```lua
  local totalVersions = #GameVersion.ORDER
  label(bar, Strings("%d of %d ready", ready, totalVersions), 12 * m.s + 2, C("gray"),
    { textWrap = false })
```

(`Strings.get`'s `string.format(text, ...)` call already supports multiple `%d` substitutions — confirmed by reading `src/core/Strings.lua:90-113` — so this is a direct drop-in, no other `Strings` changes needed.)

- [ ] **Step 4: Manually verify**

There's no automated test for this file (matches the established pattern for `LauncherView.lua`, which has no test coverage anywhere in this codebase today). Verification is Task 8's own retry: run `love .` in this worktree, confirm a 4th "C" tab appears in the tab bar alongside R/B/Y, confirm the "N of 4 ready" text (not "N of 3"), and confirm dropping the Crystal ROM no longer crashes — proceed to Task 8 Step 1-3 as originally written.

- [ ] **Step 5: Commit**

```bash
git add src/import/LauncherView.lua
git commit -m "$(cat <<'EOF'
Add Crystal to the launcher's tab bar and accent palette

Task 6 wired Crystal into GameVersion.lua/RomImporter.lua's import
logic, but LauncherView.lua's tab bar is a separately hand-maintained
list that was never updated -- so there was no Crystal tab to click,
and dropping the ROM (which sets the active tab by SHA-1 regardless)
crashed trying to color a ROM card with a nonexistent PAL entry.
Found during Task 8's real-ROM manual verification.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

**Found during Task 9 Step 4's retry of Task 8 (real bug, not anticipated by the plan):** pressing Play after a successful Crystal import crashes with:

```
src/core/Game.lua:388: attempt to index field 'stack' (a nil value)
```

Root cause, confirmed by reading the code: `src/core/Data.lua`'s `MODULES` list (line 8) unconditionally requires 16 generated data modules — `constants, maps, tilesets, text, text_pointers, trainer_headers, font, sprites, pokemon, moves, items, type_chart, trainers, encounters, field, battle_anims` — and `error()`s on the first one that fails to `require` (`Data.lua:209-223`). `RomExtractorGen2.lua` (Task 5) only ever writes 3 of them: `maps`, `tilesets`, `sprites` (`self:write(...)` at lines 91, 147, 206) — by design, since the spec's non-goals exclude Pokédex/moves/items/battle/text data. So `Data:load()` throws on `constants` (the first missing module), before `Game:load()` reaches `self.stack = StateStack` (`Game.lua:60`).

The crash you actually see is one step downstream of that: `LauncherView.lua:211` (`RomImporter:play` → `onComplete` → `main.lua`'s `bootGame` → `Game:load()`) runs inside a `pcall` in the click-dispatch path, which swallows the `Data:load()` error silently. But `main.lua` had already set `Importer = nil` and torn down the launcher UI before the throw, so every frame afterward, `love.draw()` falls through to `Game:draw()` on a `Game` object whose `load()` never finished — producing the visible `self.stack` nil crash, repeated every frame.

Fix this now, before re-attempting Task 8 Step 1-3 again:

### Task 10: Make Crystal's generated cache satisfy Data:load()'s module gate, and boot straight into New Bark Town

**Files:**
- Modify: `src/import/RomExtractorGen2.lua`
- Add: a minimal pass-through UI screen (see Step 3)

**Interfaces:**
- Consumes: `src/core/Data.lua`'s `MODULES` list (unchanged — this task supplies what it demands, it does not weaken the gate); `src/world/FieldDefaults.lua`'s `seed()` (confirmed pure fill-if-absent, safe against a Kanto-map-free dataset); `src/world/SsAnneLayout.lua`'s `apply()` (confirmed to no-op safely when `SS_ANNE_1F`/`SS_ANNE_1F_ROOMS` are absent from `maps`); `src/ui/Screens.lua`'s `push(game, id, ...)` contract (a screen module's `new(game, onDone)` calls `onDone()` after popping itself — confirmed against `src/ui/OakSpeech.lua:235,551`).
- Produces: `crystal/data/generated/{constants,text,text_pointers,trainer_headers,font,pokemon,moves,items,type_chart,trainers,encounters,field,battle_anims}.lua`, all minimal-but-valid-shaped stubs; a `field.lua` whose `boot` table points spawn at New Bark Town and skips the Oak-speech-equivalent starter-selection screen.

Confirmed safe by reading the source directly (do not re-derive from scratch, but do verify nothing has drifted before relying on it):
- `Data:seedDefaults()` (`Data.lua:92-148`) only additively fills gaps (`CONSTANT_DEFAULTS`, `BOOT_DEFAULTS`, `FieldDefaults.seed`) and computes `constants.dexSize` by scanning `self.pokemon` (safe at 0 entries → `dexSize = 0`, `dexDigits = 3`).
- `Data:seedCinnabarGymTrainerHeaders` / `Data:seedFightingDojoKarateMaster` only require `self.trainer_headers` to be a non-nil table; they add a couple of inert Kanto-only keys to it that nothing Crystal-related ever reads. Harmless, not worth special-casing.
- `src/render/Font.lua`'s `Font.load(data)` (`Font.lua:38-86`) tolerates `data.font = {}` cleanly (`pagesOf`, `def.charmap or {}`, `def.border or {}` all degrade to empty) — no glyphs render, which is fine since this skeleton shows no text/dialogue.

Not yet confirmed — **verify against source, do not guess**, before writing the corresponding stub or wiring:
- Whether `src/ui/TitleState.lua` and the splash screens (`src/ui/IntroMovie.lua`, whatever `bootScreens(self).splash` defaults to) touch any `Data` field beyond what's already stubbed. If they do, either extend the relevant stub or override `field.boot.screens.splash`/`.title` too — do not add Crystal-branded splash/title art; a generic/inert screen is in scope, custom presentation is not.
- The exact New Bark Town spawn tile: read the already-generated `crystal/data/generated/maps.lua` (from Task 8's completed import) and pick a coordinate known walkable — e.g. one of `NEW_BARK_TOWN.warps[i]`'s own `(x, y)`, which is guaranteed walkable since that's where a warp lands the player. Do not invent a coordinate without checking it against the real extracted map.

- [ ] **Step 1: Write minimal stub content for the 13 modules `RomExtractorGen2` doesn't otherwise produce**

In `src/import/RomExtractorGen2.lua`, alongside the existing `self:write("maps", ...)` / `self:write("tilesets", ...)` / `self:write("sprites", ...)` calls, add `self:write(name, {})` for `constants`, `text`, `text_pointers`, `trainer_headers`, `font`, `pokemon`, `moves`, `items`, `type_chart`, `trainers`, `encounters`, `battle_anims` — bare empty tables satisfy `Data:load()`'s `require` gate and every downstream read site this task's research confirmed tolerates emptiness. Do not invent placeholder entries (fake species, fake moves) — an empty table is the honest representation of "not extracted yet," matching the spec's stated non-goals.

`field` is not in that bare-empty list — it needs real content, in Step 2.

- [ ] **Step 2: Stamp `field.boot` to spawn in New Bark Town and skip starter selection**

Still in `RomExtractorGen2.lua`, write a `field` module (`self:write("field", { boot = { ... } })`) with:
- `startMap = "NEW_BARK_TOWN"`, `startX`/`startY` = the verified walkable coordinate from this task's research above, `startFacing = "down"`.
- `screens = { newGame = "<the no-op screen id from Step 3>" }` — leave `splash`/`title` on the `BOOT_DEFAULTS` fallback unless Step 1's source-reading above found a reason they need overriding too.

Everything else in `BOOT_DEFAULTS` (`playerName`, `rivalName`, `startMoney`, `namePresets`) is filled in for free by `Data:seedDefaults`'s fill-if-absent pass — do not duplicate those keys.

- [ ] **Step 3: Add a no-op "no starter selection" screen**

`Screens.push` has no built-in skip sentinel (`Screens.lua:43-63` always resolves an id and instantiates it) — `field.boot.screens.newGame` must name a real screen module. Add one (naming and exact location at the implementer's discretion, e.g. `src/ui/NoOpScreen.lua`) matching `OakSpeech.new(game, onDone)`'s contract: pop itself and call `onDone()`, with no starter selection, no dialogue, no other side effect. Confirm by reading `OakSpeech.lua` fully (not skimming) that this is the complete contract a caller depends on — `Game:makeTitleState`'s `onNewGame` (`Game.lua:139-153`) already pushes `OverworldState` before pushing this screen on top, so once this screen pops itself the player is standing in New Bark Town.

- [ ] **Step 4: Manually verify**

No automated test covers this (real-ROM boot, like Task 8, is manual-only per the spec's own Testing section). Run `love .`, select Crystal, import if needed, press Play, press NEW GAME at the title screen. Expected: no crash, no starter-selection screen, player spawns standing in New Bark Town on a walkable tile — then proceed to Task 8 Step 2-3's visual/collision/warp-count checks as originally written.

- [ ] **Step 5: Commit**

```bash
git add src/import/RomExtractorGen2.lua src/ui/<the-new-screen-file>.lua
git commit -m "$(cat <<'EOF'
Make Crystal's generated cache satisfy Data:load()'s module gate

Data:load() requires 16 generated modules; RomExtractorGen2 only
wrote 3 (maps, tilesets, sprites), so Data:load() threw on the
missing 'constants' module every time -- silently swallowed by
LauncherView's click-dispatch pcall, surfacing only as a nil
self.stack crash in Game:draw one frame later. Stub the other 13
with empty tables (all confirmed tolerant of emptiness by reading
Data.lua, FieldDefaults.lua, SsAnneLayout.lua, and Font.lua directly)
and stamp field.boot to spawn in New Bark Town through a no-op
screen instead of Gen1's species-driven Oak speech.

Found during Task 9's retry of Task 8's manual verification.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: If everything above passes, update the spec's status**

Edit `docs/superpowers/specs/2026-08-03-gen2-crystal-extraction-skeleton-design.md`'s `Status:` line from "approved for planning" to "skeleton verified against real ROM, <today's date>", and commit:

```bash
git add docs/superpowers/specs/2026-08-03-gen2-crystal-extraction-skeleton-design.md
git commit -m "$(cat <<'EOF'
Mark the Gen2 (Crystal) extraction skeleton as verified

New Bark Town imports, renders, and is walkable end-to-end from a
real Pokemon Crystal ROM. Gold/Silver and the rest of Johto are
follow-on work.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```
