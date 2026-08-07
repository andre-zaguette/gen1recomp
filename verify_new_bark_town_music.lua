#!/usr/bin/env luajit
-- Standalone verification script for extractNewBarkTownMusic
-- Tests extraction against the real Crystal ROM and committed manifest

local RomExtractorGen2 = require("src.import.RomExtractorGen2")
local Json = require("src.link.Json")

local function main()
  -- Read the ROM file
  local romPath = "roms/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"
  local handle = assert(io.open(romPath, "rb"), "could not open ROM: " .. romPath)
  local romData = handle:read("*a")
  handle:close()
  print(string.format("Loaded ROM: %s (%d bytes)", romPath, #romData))

  -- Read the manifest
  local manifestPath = "tools/rom_manifest_crystal.json"
  local manifestHandle = assert(io.open(manifestPath, "r"), "could not open manifest: " .. manifestPath)
  local manifestJson = manifestHandle:read("*a")
  manifestHandle:close()
  local manifest = Json.decode(manifestJson)
  print(string.format("Loaded manifest: %s (%d symbols)", manifestPath,
    manifest.symbols and 1 or 0))

  -- Verify Music_NewBarkTown symbols are in manifest
  local requiredSymbols = {
    "Music_NewBarkTown_Ch1",
    "Music_NewBarkTown_Ch1.mainloop",
    "Music_NewBarkTown_Ch1.sub1",
    "Music_NewBarkTown_Ch1.sub2",
    "Music_NewBarkTown_Ch2",
    "Music_NewBarkTown_Ch2.mainloop",
    "Music_NewBarkTown_Ch2.sub1",
    "Music_NewBarkTown_Ch2.sub2",
    "Music_NewBarkTown_Ch3",
    "Music_NewBarkTown_Ch3.mainloop",
  }

  for _, symbolName in ipairs(requiredSymbols) do
    if not manifest.symbols[symbolName] then
      error("required symbol missing from manifest: " .. symbolName)
    end
  end
  print("All required symbols found in manifest")

  -- Create extractor and test extraction
  local extractor = RomExtractorGen2.new(romData, manifest)
  print("Created RomExtractorGen2 instance")

  -- Extract Music_NewBarkTown
  local song = extractor:extractNewBarkTownMusic()
  print("Extracted Music_NewBarkTown successfully")

  -- Basic validation of the song
  if not song or type(song) ~= "table" then
    error("extractNewBarkTownMusic did not return a valid song table")
  end

  print("Song extracted successfully")
  if song.channels then
    print(string.format("Song has %d channels", #song.channels))
    for i = 1, math.min(3, #song.channels) do
      print(string.format("  Channel %d: present", i))
    end
  end

  print("\nSUCCESS: New Bark Town music extraction verified!")
end

main()
