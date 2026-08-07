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

-- Regression guard for a SECOND, separate bug found via live playtest
-- after the above fix shipped: "it blocks one tile before reaching the
-- ledge, and then it doesn't go down." Root cause: a real Route 29 ledge
-- (TILESET_JOHTO block 75) packs BOTH the hop quadrant AND a WALL
-- quadrant into ONE metatile block -- TL=COLL_HOP_DOWN, BL=WALL, TR/BR
-- =land (re-verified directly against the real ROM: bank/addr from
-- TilesetJohtoMeta/Coll in tools/rom_manifest_crystal.json). Real open
-- ground only resumes one cell past that wall, i.e. 2 cells past the lip
-- itself / 3 cells from the player's pre-hop position -- not the
-- 2-cells-from-start distance Gen1's own ledges use (this fixture's own
-- shape above), which is exactly what OverworldController.lua's
-- checkLedgeHop's "hopDistance" now branches on (2 for a Gen1
-- field.ledges match, 3 for a Gen2 hopFacing match).
--
-- Block layout, one row per metatile block (matching real block 75's
-- own TL/BL split, not two separate blocks):
--   row 0 (id 0): plain floor -- where the player is standing pre-hop.
--   row 1 (id 1): the ledge itself -- TL quadrant (tile 42) is the real
--     COLL_HOP_DOWN spot; BL quadrant (tile 7) is the real WALL quadrant
--     directly below it, exactly like block 75. TR/BR (tile 5) are
--     ordinary land, matching block 75's own non-ledge columns.
--   row 2 (id 2): real open ground, one full block past the ledge.
local function filler16(tl, tr, bl, br)
  local b = {}
  for i = 1, 16 do b[i] = 0 end
  b[5], b[7], b[13], b[15] = tl, tr, bl, br -- the 4 quadrant-representative slots cellTile ever reads
  return b
end
local TALL_FLOOR_BLOCK = filler16(9, 9, 9, 9)
local TALL_LEDGE_BLOCK = filler16(42, 5, 7, 5) -- TL=hop tile, BL=wall, TR/BR=land
local TALL_GROUND_BLOCK = filler16(5, 5, 5, 5)
local tallTilesetDef = {
  id = "TEST_LEDGE_TILESET_TALL",
  blocks = { TALL_FLOOR_BLOCK, TALL_LEDGE_BLOCK, TALL_GROUND_BLOCK },
  walkable = { 9, 5 }, -- tile 7 (the wall quadrant) is deliberately absent
  hopFacing = { [1] = { [0] = { down = true } } }, -- block id 1, quadrant 0 (TL)
}
local tallMapDef = {
  id = "TEST_LEDGE_MAP_TALL", tileset = "TEST_LEDGE_TILESET_TALL",
  width = 1, height = 3, blocks = { 0, 1, 2 }, borderBlock = 0,
}
local tallMap = Map.new(tallMapDef, tallTilesetDef)

-- cy=1: block 0 (floor)'s bottom-left quadrant -- the player's pre-hop
-- standing cell.
check(tallMap:isWalkableCell(0, 1) == true, "the tall fixture's pre-hop cell is walkable floor")
-- cy=2: block 1 (ledge)'s top-left quadrant -- the real hop spot, one
-- cell past the player's start (matches checkLedgeHop's "front" cell).
local lipHop = tallMap:hopFacingAt(0, 2)
check(lipHop ~= nil and lipHop.down == true, "the tall fixture's lip (2 cells past start) allows a downward hop")
-- cy=3: block 1's own bottom-left quadrant -- the WALL directly below
-- the lip, 2 cells past the player's start. This is the OLD
-- hopDistance=2 landing spot, and it must be blocked (the exact real
-- Route 29 bug: hop lands on a wall).
eq(tallMap:isWalkableCell(0, 3), false,
  "2 cells past the lip's start lands on the real wall quadrant -- " ..
  "confirms the old hopDistance=2 landing was broken for this real shape")
-- cy=4: block 2 (ground)'s top-left quadrant, 3 cells past the player's
-- start. This is the FIXED hopDistance=3 landing spot, and it must be
-- walkable.
eq(tallMap:isWalkableCell(0, 4), true,
  "3 cells past the lip's start lands on real open ground -- " ..
  "confirms hopDistance=3 is what checkLedgeHop needs for Gen2 ledges")

T.finish("Gen2 ledge hop collision (COLL_HOP_* block+quadrant keying)")
