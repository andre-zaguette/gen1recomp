-- src/import/RomExtractorGen2.lua
-- Gen2 (Crystal) runtime extractor, scoped to New Bark Town: map, the
-- TILESET_JOHTO tileset, the player (Chris) overworld sprite, and the
-- font (glyphs + charmap) used to draw the engine's own hardcoded UI
-- strings (title screen, menus).
-- Mirrors src/import/RomExtractor.lua's shape and helper usage; the
-- sprite/tileset/map extraction was ported from tools/build_rom_data_gen2.py
-- (Task 4) -- keep those three in sync if either changes; extractFont()
-- (below) has no counterpart in that Python dev-tool script. See
-- docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md.

local bit = require("bit")
local ImageWriter = require("src.import.ImageWriter")
local LuaWriter = require("src.import.LuaWriter")
local Lz3 = require("src.import.Lz3")
local Rom = require("src.import.Rom")

local RomExtractorGen2 = {}
RomExtractorGen2.__index = RomExtractorGen2

local STAGE_COUNT = 5

-- The other 11 modules Data:load()'s MODULES gate requires that this
-- skeleton's scope (New Bark Town's map/tileset/player sprite/font
-- only, see the spec's non-goals) never populates.  `field` gets real
-- boot content (extractField, below); `text` gets real boot content too
-- (extractIntroText, above -- the intro's ~8 narration/prompt labels);
-- the rest are bare empty tables -- confirmed by reading Data:seedDefaults,
-- FieldDefaults.seed, SsAnneLayout.apply and Font.load directly that every
-- one of them tolerates emptiness (Task 10 brief).  Not invented
-- placeholder content: an empty table is the honest "not extracted yet".
local STUB_MODULES = {
  "constants", "text_pointers", "trainer_headers",
  "pokemon", "moves", "items", "type_chart", "trainers", "encounters",
  "battle_anims",
}

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
  local chris = self:symbol("ChrisSpriteGFX")
  local chrisRaw = self.rom:bytes(chris.bank, chris.address, 16 * 96 / 4)
  local chrisImage = ImageWriter.decode2bpp(chrisRaw, 16, 96, true)
  self:save(chrisImage, "sprites/chris.png")

  -- Kris: the girl protagonist, identical sheet shape to Chris (same
  -- overworld_sprite macro, 12 tiles, 2bpp) -- only her default in-ROM
  -- palette differs (PAL_OW_BLUE vs PAL_OW_RED), which this project's own
  -- real-color palette work already resolves independently of the ROM's
  -- own default, so it needs no special handling here.
  local kris = self:symbol("KrisSpriteGFX")
  local krisRaw = self.rom:bytes(kris.bank, kris.address, 16 * 96 / 4)
  local krisImage = ImageWriter.decode2bpp(krisRaw, 16, 96, true)
  self:save(krisImage, "sprites/kris.png")

  local out = {
    SPRITE_CHRIS = {
      id = "SPRITE_CHRIS", source = "ROM:ChrisSpriteGFX",
      image = "assets/generated/sprites/chris.png",
      frames = 96 / 16, walker = true,
    },
    SPRITE_KRIS = {
      id = "SPRITE_KRIS", source = "ROM:KrisSpriteGFX",
      image = "assets/generated/sprites/kris.png",
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

-- Font: 128 tiles, 128x64px, 1bpp -- codes $80-$FF (both cases + digits,
-- confirmed against constants/charmap.asm during planning). FontExtra: 32
-- tiles, 128x16px, 2bpp -- codes $60-$7F (space, quotes, the box-drawing
-- border glyphs Font.DEFAULT_BORDER already expects at $79-$7E). Unlike
-- Gen1 (whose font_extra.png is TextBoxGraphics plus a separate
-- Pokedex-tile patch), Crystal ships this whole range as one INCBIN, so
-- there is no patch step.
function RomExtractorGen2:extractFont()
  self:beginStage("Font")
  local main = self:symbol("Font")
  local raw = self.rom:bytes(main.bank, main.address, 128 * 8)
  local image = ImageWriter.decode1bpp(raw, 128, 64, true)
  self:save(image, "fonts/font.png")
  self:tick("Font", 1, 2)

  local extra = self:symbol("FontExtra")
  local shaded = ImageWriter.decode2bpp(
    self.rom:bytes(extra.bank, extra.address, 32 * 16), 128, 16)
  local extraImage = ImageWriter.blank(128, 16, 0, 0, 0, 0)
  for y = 0, 15 do
    for x = 0, 127 do
      local r = shaded:getPixel(x, y)
      if r < 0.5 then extraImage:setPixel(x, y, 0, 0, 0, 1) end
    end
  end
  self:save(extraImage, "fonts/font_extra.png")
  self:tick("Font", 2, 2)

  local data = {
    source = "ROM:Font, FontExtra",
    image = "assets/generated/fonts/font.png",
    imageExtra = "assets/generated/fonts/font_extra.png",
    mainBase = 0x80, extraBase = 0x60, glyphsPerRow = 16,
    charmap = self.manifest.fontCharmap,
  }
  self:write("font", data)
  return data
end

-- Fully resolved by tools/extract_gen2/palettes.py at manifest-build time
-- (see that file's docstring for why this is source-derived rather than a
-- ROM-byte read, unlike every other extractX here) -- nothing left to
-- decode, just forward it into the generated cache under the same
-- "palettes" name Data.lua already treats as optional for Gen1.
--
-- tileGroups crosses a JSON boundary (Python dict with int keys ->
-- tools/rom_manifest_crystal.json -> JSON always stringifies object keys
-- -> src/link/Json.lua does not convert them back), so
-- self.manifest.palettes.tileGroups arrives keyed by STRING tile ids
-- ("59" = 5, ...).  PaletteFX.worldGroupAt indexes it with a numeric tile
-- id (groups[tileId]), which always misses against a string key, so every
-- tile silently fell back to the group-7 TEXT default.  Re-key to numbers
-- once here, at import time, rather than on every render-time lookup.
-- byTime's groupColors/spriteColor are real 1-indexed Lua arrays (not
-- JSON-object-keyed), so they do not have this problem and pass through
-- untouched.
function RomExtractorGen2:extractPalettes()
  local data = self.manifest.palettes
  local tileGroups = {}
  for tileId, group in pairs(data.tileGroups) do
    tileGroups[tonumber(tileId)] = group
  end
  local out = { tileGroups = tileGroups, byTime = data.byTime }
  self:write("palettes", out)
  return out
end

-- Ported from src/import/RomExtractor.lua's textGlyph/decodeTextCommands
-- (Task 10-era "parallel pipeline, not shared abstraction" precedent --
-- see the walking skeleton's own spec for why this project doesn't
-- factor Gen1/Gen2 text decoding through one shared function). Crystal's
-- text opcode set is confirmed byte-identical to Gen1's (same TX_*
-- values, no compression, verified during planning against
-- home/text.asm's PrintText/PlaceNextChar), and reading a label's real
-- string body directly (rather than through its OakTextN-style TX_FAR
-- wrapper) never needs the TX_FAR opcode this port omits.
local TEXT_GLYPH_OVERRIDES = {
  [0x4B] = "{_CONT}", [0x4C] = "{SCROLL}",
  [0x6D] = "{COLON}", [0xF0] = "¥",
}

function RomExtractorGen2:textGlyph(value)
  if TEXT_GLYPH_OVERRIDES[value] then return TEXT_GLYPH_OVERRIDES[value] end
  local glyph = self.manifest.charmap[tostring(value)]
    or ("{BYTE:%02X}"):format(value)
  if glyph:sub(1, 1) == "<" and glyph:sub(-1) == ">" then
    return "{" .. glyph:sub(2, -2) .. "}"
  end
  return glyph
end

function RomExtractorGen2:decodeTextCommands(symbol)
  local address = symbol.address
  local out = {}
  for _ = 1, 4096 do
    local command = self.rom:byte(symbol.bank, address)
    address = address + 1
    if command == 0x50 then
      return table.concat(out)
    elseif command == 0 then
      while true do
        local value = self.rom:byte(symbol.bank, address)
        address = address + 1
        if value == 0x50 or value == 0x57 or value == 0x58 or value == 0x5F then
          return table.concat(out)
        end
        out[#out + 1] = self:textGlyph(value)
      end
    else
      error(("%s: unsupported text command $%02X, this port only reads " ..
        "plain-body labels directly (no TX_FAR)"):format(symbol.name, command))
    end
  end
  error(symbol.name .. ": text command stream is too long")
end

-- The intro's narration + gender-prompt text. Direct symbol reads (see
-- decodeTextCommands's doc comment above) -- no pointer-table sweep, the
-- same "read exactly what's needed, by name" pattern font/palette
-- extraction already established for Gen2.
local INTRO_TEXT_LABELS = {
  "_OakText1", "_OakText2", "_OakText4", "_OakText5", "_OakText6",
  "_OakText7", "_AreYouABoyOrAreYouAGirlText",
}

function RomExtractorGen2:extractIntroText()
  self:beginStage("Intro text")
  local out = {}
  for index, label in ipairs(INTRO_TEXT_LABELS) do
    out[label] = self:decodeTextCommands(self:symbol(label))
    self:tick("Intro text", index, #INTRO_TEXT_LABELS)
  end
  self:write("text", out)
  return out
end

-- field.boot spawns straight into New Bark Town instead of Gen1's
-- REDS_HOUSE_2F / Oak-speech opening: this skeleton has no starter roster
-- or dialogue text (spec non-goals), so NEW GAME has nowhere to run that
-- scene and must land the player standing somewhere walkable instead.
--
-- The spawn tile is newBarkTown.warps[1]'s own (x, y) rather than a
-- hand-picked literal: this sandbox has neither a love binary nor an
-- already-generated crystal/data/generated/maps.lua to check a guessed
-- coordinate against (Task 10 brief), but a warp tile is walkable by
-- construction -- it is a door/edge tile the ROM's own MapEvents table
-- names, and the player has to be able to walk onto it to trigger it, so
-- COLLISION_PERMISSION never marks one a wall.  Deriving the coordinate
-- from the map this extractor just decoded is verified against the real
-- ROM on every import, which a hardcoded guess could not be here.
function RomExtractorGen2:extractField(newBarkTown)
  local spawn = assert(newBarkTown.warps[1],
    "NewBarkTown has no warps to derive a walkable spawn tile from")
  local out = {
    boot = {
      startMap = "NEW_BARK_TOWN", startX = spawn.x, startY = spawn.y,
      startFacing = "down",
      -- skip the Oak-speech-equivalent starter-selection screen (out of
      -- scope, no species data extracted); splash/title stay on the
      -- BOOT_DEFAULTS fallback (Game.lua's bootScreens(self).X or
      -- <default> reads), confirmed to need no Crystal-specific data.
      screens = { newGame = "NoOpScreen" },
    },
    -- These three data.field.* keys are read with no nil-guard on the
    -- boot -> walk path (unlike everything FieldDefaults.FIELD already
    -- covers, which is all defensively guarded) -- confirmed by reading
    -- every data.field.<key> access site in src/world, src/render and
    -- src/ui directly, not by inspection of this list alone:
    --   * flyWarps: OverworldController.lua:341, `if
    --     Game.data.field.flyWarps[mapId] then` inside setMap, which
    --     runs on every map load including the very first one
    --     (OverworldState:enter -> setMap(..., {via="boot"})) -- this is
    --     the crash the human partner hit (self.stack traced through to
    --     setMap/onNewGame).
    --   * waterTilesets: OverworldController.lua:2263's
    --     `ipairs(Game.data.field.waterTilesets)` inside
    --     tilesetHasWater(), called from setMap's boot-only surf-state
    --     restore (line ~397) on every fresh save (a new save's
    --     save.player carries no `surfing` key yet) -- the very next
    --     unguarded read after flyWarps in the same boot call.
    --   * ledges: OverworldController.lua:1275's
    --     `ipairs(Game.data.field.ledges)` inside checkLedgeHop(),
    --     called from handleInput on the second press of any held
    --     direction (once facing it and not already moving) -- hit by
    --     the first deliberate step the player takes.
    -- Empty tables are the correct "not extracted" value at each read
    -- site (dictionary keyed by map id, and two flat lists respectively)
    -- -- verified by reading each guarded sibling call site (e.g.
    -- OverworldController.lua:3838's `(Game.data.field.flyWarps or
    -- {})[out.id]`) that already treats absence the same way.
    flyWarps = {},
    waterTilesets = {},
    ledges = {},
    -- checkForcedMovement (OverworldController.lua:3506) reads
    -- Game.data.field.forcedMovement.tiles unguarded (`fm.tiles[mapId]`,
    -- indexed before its own `or {}`) on every setMap, including boot.
    -- FieldDefaults.FIELD.forcedMovement only carries `clearMaps` (Route
    -- 16/18 gate cleanup, unrelated) -- it was never meant to double as a
    -- `tiles` fallback, since every real Gen1 extraction always stamps
    -- its own `tiles`. Crystal doesn't, so FieldDefaults.seed's fill()
    -- deep-copied the incomplete default in wholesale, leaving `.tiles`
    -- permanently nil. Stub `tiles = {}` here so fill() merges it
    -- in alongside the inherited (harmless, no Crystal map matches it)
    -- `clearMaps` default instead of leaving the key out entirely.
    forcedMovement = { tiles = {} },
    -- Player.new:46 reads field.playerSprites.walk unguarded (unlike
    -- surf/bike/surfPikachu, each gated behind `data.sprites[id] and`) to
    -- build the player's on-foot SpriteRenderer -- FieldDefaults.FIELD's
    -- default there is Gen1's "SPRITE_RED", which extractSprite (above)
    -- never writes into Crystal's sprites table (only "SPRITE_CHRIS" is),
    -- so it resolved to a nil spriteDef and crashed
    -- SpriteRenderer.new:85 on the very first setMap. surf/bike/fly stay
    -- on the Gen1 defaults deliberately: this skeleton extracts no sprite
    -- for them, so their guards correctly no-op instead of crashing.
    playerSprites = { walk = "SPRITE_CHRIS", walkAlt = "SPRITE_KRIS" },
    -- tryCardKeyDoor (OverworldController.lua:2002-2005) reads
    -- Game.data.field.cardKeyDoors.maps unguarded (`ipairs(ck.maps)`) on
    -- every interact-button press, on any map -- unlike closedDoors/
    -- skipMaps (both read safely through FieldDefaults.fieldValue's
    -- per-leaf fallback elsewhere in this file), .maps/.doorTiles/
    -- .openBlock/.silphCo11F only ever exist in a real Gen1 extraction
    -- (data/events/card_key_maps.asm et al, Silph Co-only) and were never
    -- added to FieldDefaults.FIELD.cardKeyDoors, which only carries
    -- closedDoors/skipMaps. Crystal doesn't stamp cardKeyDoors at all, so
    -- fill() deep-copied that incomplete default in, leaving .maps
    -- permanently nil and crashing the very first interact press anywhere
    -- in the game. maps = {} alone is enough: the onList loop finds no
    -- match and returns false before touching doorTiles/openBlock/
    -- silphCo11F, which stay correctly unreachable (Crystal has no Silph
    -- Co, and its own equivalent is out of this skeleton's scope).
    cardKeyDoors = { maps = {} },
    -- tryHiddenObject (OverworldController.lua:1839), reached from the same
    -- interact() chain as tryCardKeyDoor, reads three more
    -- Game.data.field.hiddenExtras.* keys unguarded (`ipairs(extras.X[mapId])`,
    -- indexed before their own `or {}`): pcTiles (1919), benchGuys (1947),
    -- gymStatues (1961). FieldDefaults.FIELD.hiddenExtras only carries
    -- printTrash/trashCans (both read safely elsewhere, `extras.printTrash
    -- and ...`) -- pcTiles/benchGuys/gymStatues have no default at all, so
    -- with Crystal never stamping hiddenExtras, fill() deep-copied the
    -- incomplete default in and left all three permanently nil. Empty
    -- tables here merge in alongside the inherited printTrash/trashCans,
    -- same shape as every other stub above.
    hiddenExtras = { pcTiles = {}, benchGuys = {}, gymStatues = {} },
  }
  self:write("field", out)
  return out
end

function RomExtractorGen2:extractStubs()
  for _, name in ipairs(STUB_MODULES) do
    self:write(name, {})
  end
end

function RomExtractorGen2:run()
  local results = {}
  results.sprites = self:extractSprite()
  results.tilesets = self:extractTileset()
  results.maps = self:extractMap()
  results.font = self:extractFont()
  results.palettes = self:extractPalettes()
  results.text = self:extractIntroText()
  results.field = self:extractField(results.maps.NEW_BARK_TOWN)
  self:extractStubs()
  if self.progress then
    self.progress(STAGE_COUNT, STAGE_COUNT, "Ready", 1, 1)
  end
  return results
end

return RomExtractorGen2
