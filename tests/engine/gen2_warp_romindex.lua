-- Regression guard for the "warp to ROUTE_29_ROUTE_46_GATE#3 out of range"
-- live-playtest crash (fixed in commit 9370a38, exercised end-to-end by
-- Task 7's own registration of Route 30 -- see
-- docs/superpowers/plans/2026-08-06-gen2-crystal-roadmap.md's Task 7 and
-- .superpowers/sdd/2026-08-06-gen2-crystal-roadmap/progress.md).
--
-- Root cause: RomExtractorCrystal.lua's extractMap() skips (does not append)
-- a warp_event whose destination map isn't registered yet, so a map whose
-- ROM def_warp_events order has an unregistered entry BEFORE a registered
-- one ends up with a compacted `warps` array -- array position no longer
-- equals the ROM's own 1-based warp order. Any OTHER map's warp_event
-- naming "warp N of this map" by ROM order then silently resolves against
-- the wrong (or a missing) array slot via plain positional indexing.
--
-- Fix: each kept warp entry now carries its own ROM-order `romIndex`;
-- Warp.lua's resolve() matches on it when present. Gen1 maps' own
-- extractor (src/import/RomExtractor.lua) never skips a warp and never
-- sets this field, so a Gen1-shaped warps array (dense, no romIndex) must
-- keep resolving by plain position exactly as before -- this test pins
-- both shapes.
--   luajit tests/engine/gen2_warp_romindex.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Warp = require("src.world.Warp")

-- Route29Route46Gate's real shape after two skipped ROM entries (both to
-- the unregistered ROUTE_46): romIndex 1,2 skipped, 3,4 kept and compacted
-- to array positions 1,2.
local compactedData = {
  maps = {
    ROUTE_29_ROUTE_46_GATE = {
      warps = {
        { y = 7, x = 4, destWarp = 1, destMap = "ROUTE_29", romIndex = 3 },
        { y = 7, x = 5, destWarp = 1, destMap = "ROUTE_29", romIndex = 4 },
      },
    },
  },
}

do
  -- Route 29's real warp_event: warp_event 27,1, ROUTE_29_ROUTE_46_GATE, 3
  local destMap, x, y = Warp.destination(
    compactedData, { destMap = "ROUTE_29_ROUTE_46_GATE", destWarp = 3 })
  eq(destMap, "ROUTE_29_ROUTE_46_GATE", "romIndex match: destMap")
  eq(x, 4, "romIndex match: lands on the romIndex=3 entry's x, not array[3] (nil)")
  eq(y, 7, "romIndex match: lands on the romIndex=3 entry's y")
end

do
  local destMap, x, y = Warp.destination(
    compactedData, { destMap = "ROUTE_29_ROUTE_46_GATE", destWarp = 4 })
  eq(destMap, "ROUTE_29_ROUTE_46_GATE", "romIndex match: destWarp=4 destMap")
  eq(x, 5, "romIndex match: destWarp=4 resolves to the romIndex=4 entry")
end

-- Gen1 maps: RomExtractor.lua never skips a warp and never sets romIndex,
-- so a dense array must still resolve by plain position (the pre-fix,
-- and still-correct-for-Gen1, behavior).
local denseData = {
  maps = {
    PALLET_TOWN = {
      warps = {
        { y = 1, x = 1, destWarp = 1, destMap = "PLAYERS_HOUSE_1F" },
        { y = 2, x = 2, destWarp = 1, destMap = "RIVALS_HOUSE" },
      },
    },
  },
}

do
  local destMap, x, y = Warp.destination(
    denseData, { destMap = "PALLET_TOWN", destWarp = 2 })
  eq(destMap, "PALLET_TOWN", "Gen1 positional fallback: destMap")
  eq(x, 2, "Gen1 positional fallback: destWarp=2 resolves to array position 2")
  eq(y, 2, "Gen1 positional fallback: y")
end

do
  -- A genuinely out-of-range destWarp (no romIndex match, no valid array
  -- position) must still fail loudly, not silently land somewhere wrong.
  local ok, err = pcall(Warp.destination,
    compactedData, { destMap = "ROUTE_29_ROUTE_46_GATE", destWarp = 99 })
  check(not ok, "out-of-range destWarp still fails (no false positive fallback)")
  check(err and err:find("out of range") ~= nil,
    "failure is the expected 'out of range' assert, not some other error")
end

T.finish("Gen2 Warp.lua romIndex resolution")
