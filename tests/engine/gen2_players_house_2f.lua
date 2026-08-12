-- Regression guard for the "missing bed in PLAYERS_HOUSE_2F" investigation
-- (Task 2, docs/superpowers/plans/2026-08-06-gen2-crystal-roadmap.md). No ROM:
-- roms/pokecrystal is gitignored (see .gitignore's "/roms/" entry), so this
-- pins the exact real-ROM byte values re-verified directly against that
-- checkout this session, the same way gen2_crystal_intro.lua's fixed-strings
-- pattern avoids a ROM dependency for a UI-logic fixture.
--
-- What was actually verified this session (do not trust the numbers in the
-- plan doc's Step 4a without re-checking -- they do not match the real ROM,
-- see the report):
--   * roms/pokecrystal/maps/PlayersHouse2F.blk (4x3 blocks) decodes to
--     [4,1,3,2, 5,6,5,5, 5,5,7,5] -- block 7 sits at grid row 2, col 2.
--   * roms/pokecrystal/data/tilesets/players_room_metatiles.bin's block 7
--     (bytes 112-127) is [16,17,17,18, 32,33,33,34, 48,49,49,50, 1,1,1,1],
--     NOT [16,16,133,134,129,130,131,132,145,146,147,148,161,162,163,164]
--     as an earlier session's (unverified) finding claimed -- every one of
--     block 7's real tile ids is < 96, so it renders from
--     TilesetPlayersRoomGFX's own 96-tile 2bpp image with no VRAM
--     bank-select trickery in play (see the report's LoadTilesetGFX read).
--   * Rendering those 16 tile ids against roms/pokecrystal's own
--     gfx/tilesets/players_room.png (pret's pre-decoded rip, cropped 8x8 per
--     tile at 16 tiles/row) produces an unmistakable bed sprite (mattress
--     block + two corner legs), confirmed visually this session.
--   * src/import/Lz3.lua run against the real
--     gfx/tilesets/players_room.2bpp.lz byte-for-byte reproduces the real
--     gfx/tilesets/players_room.2bpp (0 mismatches over 1536 bytes),
--     ruling out a decompressor bug for this tileset.
--
-- This test exercises src/world/Map.lua's OWN block/tile resolution (the
-- same :blockAt/:tileAt math src/render/TileRenderer.lua's :ensureWindow
-- uses to pick a quad) against those real, re-verified numbers, so a future
-- change to that math would be caught here instead of only showing up as a
-- silent missing/wrong sprite in a live LÖVE session.
--   luajit tests/engine/gen2_players_house_2f.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Map = require("src.world.Map")

-- Real PlayersHouse2F.blk grid, width=4 height=3 (RomExtractorCrystal.lua's
-- extractMap reads this straight from ROM bytes, no manifest round trip).
local BLOCKS = { 4, 1, 3, 2, 5, 6, 5, 5, 5, 5, 7, 5 }

-- Real TilesetPlayersRoomMeta block 7 (the bed), re-verified this session
-- directly against roms/pokecrystal -- see the header comment above.
local BED_BLOCK = { 16, 17, 17, 18, 32, 33, 33, 34, 48, 49, 49, 50, 1, 1, 1, 1 }

-- The other referenced blocks (0-6) are irrelevant to this check: fill with
-- a placeholder tile id so Map:tileAt has something non-nil to return if a
-- future edit to this test widens its coverage.
local function placeholderBlock() return { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } end

local tilesetDef = {
  id = "TILESET_PLAYERS_ROOM",
  blocks = {
    placeholderBlock(), placeholderBlock(), placeholderBlock(), placeholderBlock(),
    placeholderBlock(), placeholderBlock(), placeholderBlock(),
    BED_BLOCK, -- index 8 = 1-indexed slot for block id 7
  },
  walkable = {},
}

local mapDef = {
  id = "PLAYERS_HOUSE_2F", tileset = "TILESET_PLAYERS_ROOM",
  width = 4, height = 3, blocks = BLOCKS, borderBlock = 0,
}

local map = Map.new(mapDef, tilesetDef)

eq(map:blockAt(2, 2), 7,
  "PLAYERS_HOUSE_2F: block grid row 2, col 2 (bottom row, 3rd column) is block 7, the bed")

-- Block (bx=2, by=2) covers 8px tiles tx in [8,11], ty in [8,11]
-- (Map:tileAt(tx,ty) -> block[(ty%4)*4 + (tx%4) + 1], the same indexing
-- TileRenderer:ensureWindow uses for its quad lookup).
local expectedTiles = {
  { tx = 8,  ty = 8,  tile = 16 },
  { tx = 9,  ty = 8,  tile = 17 },
  { tx = 10, ty = 8,  tile = 17 },
  { tx = 11, ty = 8,  tile = 18 },
  { tx = 8,  ty = 9,  tile = 32 },
  { tx = 8,  ty = 10, tile = 48 },
  { tx = 11, ty = 10, tile = 50 },
  { tx = 8,  ty = 11, tile = 1 },
  { tx = 11, ty = 11, tile = 1 },
}
for _, e in ipairs(expectedTiles) do
  eq(map:tileAt(e.tx, e.ty), e.tile,
    ("PLAYERS_HOUSE_2F bed: tile (%d,%d) resolves to the bed's real tile id %d")
      :format(e.tx, e.ty, e.tile))
end

check(map:tileAt(8, 8) ~= nil,
  "PLAYERS_HOUSE_2F bed: the bed's top-left tile is not nil (would draw nothing, " ..
  "the exact shape of the originally reported bug)")

T.finish("Gen2 PLAYERS_HOUSE_2F bed")
