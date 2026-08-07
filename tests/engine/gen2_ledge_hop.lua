-- Regression guard for the Route 29 ledge bug reported via live playtest:
-- "some ledge spots let me pass through from both sides (should be
-- one-way); some spots block the downward jump entirely (should work)."
--
-- Root cause, verified directly against roms/pokecrystal (gitignored, not
-- committed -- see RomExtractorGen2.lua's extractTileset for the derivation):
-- Crystal encodes ledges via COLL_HOP_* collision-permission bytes
-- ($A0-$A7, constants/collision_constants.asm), which this project's
-- extractor previously never recognized at all -- every COLL_HOP_* byte
-- silently fell through to the same default as plain floor (LAND_TILE),
-- making every ledge freely walkable in every direction (symptom 1).
--
-- The first fix attempt keyed the new hop-facing table by the resolved
-- 8x8 GRAPHIC tile id, mirroring how walkable/grass are already tile-id
-- keyed. That is wrong for this specific collision class: re-deriving
-- TILESET_JOHTO's real collision data directly from the ROM found that
-- the same graphic tile id can carry a hop permission in one placed
-- metatile block and plain walkable floor in a completely different
-- block elsewhere in the same tileset -- tile identity is not collision
-- identity once a graphic gets reused. A tile-id-keyed table therefore
-- either wrongly blocks a genuinely-walkable reuse of that graphic
-- elsewhere (symptom 2, "can't pass where I should") or, if the
-- overlap resolves the other way, leaves the real ledge unblocked
-- again (symptom 1 persists). The fix instead keys hopFacing by
-- (block id, quadrant) -- exactly what the real GBC engine's own
-- wPlayerTileCollision byte is keyed by (home/map.asm reads the
-- block's own 4 permission bytes directly, never the tile graphic) --
-- so this test's fixture DELIBERATELY reuses one graphic tile id in
-- both a walkable block and a hop block, the exact shape that broke
-- the first attempt, to prove the block+quadrant keying handles it.
--   luajit tests/engine/gen2_ledge_hop.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Map = require("src.world.Map")

-- Graphic tile id 42 is reused: block 0 (plain floor) uses it in its
-- bottom-left quadrant (cellTile's own sampling position), and block 1
-- (a ledge) uses the SAME id 42 in its bottom-left quadrant too, but
-- that quadrant there is a real COLL_HOP_DOWN.
local FLOOR_BLOCK = { 5, 5, 5, 5, 5, 5, 5, 5, 42, 5, 5, 5, 5, 5, 5, 5 }
local LEDGE_BLOCK = { 5, 5, 5, 5, 5, 5, 5, 5, 42, 5, 5, 5, 5, 5, 5, 5 }

local tilesetDef = {
  id = "TEST_LEDGE_TILESET",
  blocks = { FLOOR_BLOCK, LEDGE_BLOCK }, -- 1-indexed: block id 0 -> slot 1, block id 1 -> slot 2
  walkable = { 5, 42 }, -- both graphic ids are plain floor SOMEWHERE
  -- block id 1 (LEDGE_BLOCK), quadrant 2 (bottom-left, the same quadrant
  -- cellTile always samples) carries a real COLL_HOP_DOWN permission.
  hopFacing = { [1] = { [2] = { down = true } } },
}

local mapDef = {
  id = "TEST_LEDGE_MAP", tileset = "TEST_LEDGE_TILESET",
  -- a 1x2 map: block (0,0) is plain floor, block (0,1) is the ledge
  width = 1, height = 2, blocks = { 0, 1 }, borderBlock = 0,
}

local map = Map.new(mapDef, tilesetDef)

-- Each 32x32px block spans a 2x2 grid of 16x16px cells (Map.new's own
-- widthCells/heightCells = def.width/height * 2), and Map:cellTile
-- always samples the BOTTOM-LEFT 8x8 tile of whichever quadrant a cell
-- falls in. So block row 0 (FLOOR_BLOCK)'s bottom-left quadrant is cell
-- (0,1); block row 1 (LEDGE_BLOCK)'s bottom-left quadrant -- the one
-- this fixture put the COLL_HOP_DOWN permission on -- is cell (0,3).

-- cell (0,1): FLOOR_BLOCK's bottom-left quadrant -- plain floor, no ledge.
check(map:hopFacingAt(0, 1) == nil,
  "the plain-floor cell has no hop-facing entry")
check(map:isWalkableCell(0, 1) == true,
  "the plain-floor cell is walkable")

-- cell (0,3): LEDGE_BLOCK's bottom-left quadrant, the real COLL_HOP_DOWN
-- spot -- SAME graphic tile id (42) as the walkable cell above, but
-- must NOT be freely walkable (symptom 1: the reported "no blocking,
-- passes through both ways" bug).
local hop = map:hopFacingAt(0, 3)
check(hop ~= nil, "the ledge cell has a hop-facing entry")
check(hop.down == true, "the ledge cell allows a downward hop")
check(hop.up == nil and hop.left == nil and hop.right == nil,
  "the ledge cell allows ONLY a downward hop, not every direction")
eq(map:isWalkableCell(0, 3), false,
  "the ledge cell is NOT plainly walkable despite sharing tile id 42 " ..
  "with the walkable floor cell above (symptom 1's exact failure shape: " ..
  "tile-id reuse must not leak walkability across blocks)")

T.finish("Gen2 ledge hop collision (COLL_HOP_* block+quadrant keying)")
