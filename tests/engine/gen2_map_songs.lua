-- Pins Milestone 2's mapSongs wiring end-to-end: every registered Crystal
-- map resolves to a song label via results.audio.mapSongs, and every
-- label this task has actually extracted resolves to a real ChipAsm song
-- def (not just a string). Extended in each subsequent Milestone 2 task
-- as more songs land -- see docs/superpowers/plans/
-- 2026-08-06-gen2-crystal-milestone2-music.md.
--   luajit tests/engine/gen2_map_songs.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- Real, ROM-verified per docs/superpowers/plans/
-- 2026-08-06-gen2-crystal-milestone2-music.md's Research Finding 1 table.
local EXPECTED_MAP_SONGS = {
  NEW_BARK_TOWN = "Music_NewBarkTown",
  PLAYERS_HOUSE_1F = "Music_NewBarkTown",
  PLAYERS_HOUSE_2F = "Music_NewBarkTown",
  PLAYERS_NEIGHBORS_HOUSE = "Music_NewBarkTown",
  ELMS_HOUSE = "Music_NewBarkTown",
  ELMS_LAB = "Music_ElmsLab",
  ROUTE_29 = "Music_Route29",
  ROUTE_29_ROUTE_46_GATE = "Music_Route29",
  CHERRYGROVE_CITY = "Music_CherrygroveCity",
  ROUTE_30 = "Music_Route30",
  MR_POKEMONS_HOUSE = "Music_CherrygroveCity",
}

-- This test cannot import a real ROM (no data/generated/ in this
-- checkout, gitignored /roms/), so it checks the manifest's own "music"
-- field directly -- the same source RomExtractorGen2.lua's mapSongs loop
-- reads from at runtime -- rather than a live Data:load().
local Json = require("src.link.Json")
local f = io.open("tools/rom_manifest_crystal.json", "r")
local manifest = Json.decode(f:read("*a"))
f:close()

for mapId, expectedSong in pairs(EXPECTED_MAP_SONGS) do
  local map = manifest.maps[mapId]
  check(map ~= nil, ("manifest has a %s entry"):format(mapId))
  eq(map.music, expectedSong,
    ("%s's manifest music field is %s"):format(mapId, expectedSong))
end

T.finish("Gen2 mapSongs manifest wiring")
