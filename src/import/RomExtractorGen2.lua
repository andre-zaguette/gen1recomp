-- src/import/RomExtractorGen2.lua
-- Gen2 (Crystal) runtime extractor, scoped to Crystal's intro/new-game
-- opening: New Bark Town, the player's house 1F/2F, their three tilesets,
-- the player (Chris/Kris) overworld sprites, and the
-- font (glyphs + charmap) used to draw the engine's own hardcoded UI
-- strings (title screen, menus).
-- Mirrors src/import/RomExtractor.lua's shape and helper usage; the
-- sprite/tileset/map extraction was ported from tools/build_rom_data_gen2.py
-- (Task 4) -- keep those three in sync if either changes; extractFont()
-- (below) has no counterpart in that Python dev-tool script. See
-- docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md.

local bit = require("bit")
local ChipAsm = require("src.audio.ChipAsm")
local CrystalCryTranscoder = require("src.audio.CrystalCryTranscoder")
local CrystalMusicTranscoder = require("src.audio.CrystalMusicTranscoder")
local ImageWriter = require("src.import.ImageWriter")
local LuaWriter = require("src.import.LuaWriter")
local Logger = require("src.core.Logger")
local Lz3 = require("src.import.Lz3")
local Rom = require("src.import.Rom")

local RomExtractorGen2 = {}
RomExtractorGen2.__index = RomExtractorGen2

local STAGE_COUNT = 10

-- The other 11 modules Data:load()'s MODULES gate requires that this
-- skeleton's scope (Crystal intro/start maps/tilesets/player sprite/font
-- only, see the spec's non-goals) never populates.  `field` gets real
-- boot content (extractField, below); `text` gets real boot content too
-- (extractIntroText, above -- the intro's ~8 narration/prompt labels);
-- the rest are bare empty tables -- confirmed by reading Data:seedDefaults,
-- FieldDefaults.seed, SsAnneLayout.apply and Font.load directly that every
-- one of them tolerates emptiness (Task 10 brief).  Not invented
-- placeholder content: an empty table is the honest "not extracted yet".
local STUB_MODULES = {
  "constants", "text_pointers", "trainer_headers",
}

-- COLL_* -> CollisionPermissionTable base permission, ported verbatim from
-- tools/extract_gen2/collision.py (Task 4 Step 1b) -- keep the two
-- byte-for-byte identical. Source: pret/pokecrystal
-- constants/collision_constants.asm + data/collision/collision_permissions.asm
local LAND_TILE, WATER_TILE, WALL_TILE, TALK = 0x00, 0x01, 0x0F, 0x10
-- Not a pokecrystal COLL_* base value -- an extra flag bit this project
-- adds on the LAND_TILE base, the same way TALK flags a WALL/WATER tile.
-- constants/collision_constants.asm's COLL_LONG_GRASS ($14) and
-- COLL_TALL_GRASS ($18) are the two real wild-encounter grass values; both
-- stay walkable (bits 0-3 are still LAND_TILE) once flagged, matching
-- src/world/Map.lua's isGrassCell needing "walkable AND grass" together.
local GRASS = 0x20
-- Not a pokecrystal COLL_* base value either -- a third internal base
-- (alongside LAND_TILE/WATER_TILE/WALL_TILE) for the COLL_HOP_* range
-- ($A0-$A7, constants/collision_constants.asm's HI_NYBBLE_LEDGES): a hop
-- tile is NOT unconditionally walkable (must not join walkableSet below)
-- but is also not a plain WALL_TILE -- it's a direction-gated exception,
-- see src/world/OverworldController.lua's checkLedgeHop and Map.lua's
-- hopFacing lookup, which grant the crossing only when the player's
-- facing matches this tile's own allowed direction(s).
local HOP_TILE = 0x02
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
local GRASS_TILES = { 0x14, 0x18 }
-- constants/collision_constants.asm: COLL_HOP_RIGHT $A0, COLL_HOP_LEFT
-- $A1, COLL_HOP_UP $A2 (unused by any real tileset), COLL_HOP_DOWN $A3,
-- COLL_HOP_DOWN_RIGHT $A4, COLL_HOP_DOWN_LEFT $A5, COLL_HOP_UP_RIGHT $A6
-- (unused), COLL_HOP_UP_LEFT $A7 (unused). Facing sets below match
-- engine/overworld/player_movement.asm's own `.ledge_table` bitmask
-- exactly (`.TryJump`: the target tile's collision nybble selects a row
-- of that table, ANDed against the player's current facing -- a facing
-- bit set in the row is a permitted hop direction).
local HOP_FACINGS = {
  [0xA0] = { right = true },
  [0xA1] = { left = true },
  [0xA2] = { up = true },
  [0xA3] = { down = true },
  [0xA4] = { right = true, down = true },
  [0xA5] = { down = true, left = true },
  [0xA6] = { up = true, right = true },
  [0xA7] = { up = true, left = true },
}
for i in pairs(HOP_FACINGS) do COLLISION_PERMISSION[i] = HOP_TILE end
for _, i in ipairs(WALL) do COLLISION_PERMISSION[i] = WALL_TILE end
for _, i in ipairs(WALL_TALK) do COLLISION_PERMISSION[i] = bit.bor(WALL_TILE, TALK) end
for _, i in ipairs(WATER) do COLLISION_PERMISSION[i] = WATER_TILE end
for _, i in ipairs(WATER_TALK) do COLLISION_PERMISSION[i] = bit.bor(WATER_TILE, TALK) end
for _, i in ipairs(GRASS_TILES) do COLLISION_PERMISSION[i] = bit.bor(LAND_TILE, GRASS) end

function RomExtractorGen2.new(romData, manifest, progress)
  return setmetatable({
    rom = Rom.new(romData),
    manifest = manifest,
    symbols = manifest.symbols,
    symCache = {},
    skippedWarps = {},
    progress = progress,
    stage = 0,
  }, RomExtractorGen2)
end

local function parseSymLine(line)
  local bankHex, addrHex, label = line:match("^(%x+):(%x+)%s+(.+)$")
  if not bankHex then return nil end
  return {
    bank = tonumber(bankHex, 16),
    address = tonumber(addrHex, 16),
    name = label,
  }
end

local function hwFromSfxChannel(channel)
  return ({ [5] = 1, [6] = 2, [7] = 3, [8] = 4 })[channel]
end

local function crystalSfxKey(constant)
  local stem = constant and constant:match("^SFX_(.+)$")
  return stem
end

local function crystalSfxHeaderName(key)
  if not key then return nil end
  if key:match("^[A-Z0-9_]+$") then
    local out = {}
    for part in key:gmatch("[A-Z0-9]+") do
      out[#out + 1] = part:sub(1, 1) .. part:sub(2):lower()
    end
    return table.concat(out)
  end
  return key
end

local function parseCrystalSfxHeaders()
  local handle = assert(io.open("roms/pokecrystal/audio/sfx.asm", "rb"))
  local text = handle:read("*a")
  handle:close()
  local headers = {}
  local current
  local channelsBySymbol = {}
  local activeChannel
  local function localLabelName(symbol, label)
    return symbol .. label
  end
  local function addChannelTarget(spec, target, isSubroutine)
    if not (spec and target) then return end
    local full = target:sub(1, 1) == "."
      and localLabelName(spec.symbol, target) or target
    spec.labels[full] = true
    if isSubroutine then spec.subroutines[full] = true end
  end
  for line in text:gmatch("[^\r\n]+") do
    local label = line:match("^(Sfx_[A-Za-z0-9_]+):$")
    local channelLabel = label and channelsBySymbol[label] or nil
    if label and not label:match("_Ch%d+$") then
      current = label:match("^Sfx_(.+)$")
      headers[current] = headers[current] or { channels = {} }
      activeChannel = nil
    elseif channelLabel then
      activeChannel = channelLabel
    end
    if activeChannel then
      local localLabel = line:match("^%s*(%.[A-Za-z0-9_]+):$")
      if localLabel then
        addChannelTarget(activeChannel, localLabel, false)
      else
        local opcode, args = line:match("^%s*(sound_[a-z_]+)%s+(.-)%s*$")
        if opcode == "sound_call" then
          addChannelTarget(activeChannel, args:match("([%.A-Za-z0-9_]+)%s*$"), true)
        elseif opcode == "sound_loop" then
          addChannelTarget(activeChannel, args:match(",%s*([%.A-Za-z0-9_]+)%s*$")
            or args:match("([%.A-Za-z0-9_]+)%s*$"), false)
        elseif opcode == "sound_jump" then
          addChannelTarget(activeChannel, args:match("([%.A-Za-z0-9_]+)%s*$"), false)
        elseif opcode == "sound_ret" then
          activeChannel = nil
        end
      end
    end
    if current then
      local hwChannel, sym = line:match("^%s*channel%s+(%d+),%s*(Sfx_[A-Za-z0-9_]+)")
      if hwChannel and sym then
        local spec = {
          hw = assert(hwFromSfxChannel(tonumber(hwChannel)),
                      "unsupported Crystal SFX channel " .. tostring(hwChannel)),
          symbol = sym,
          labels = { [sym] = true },
          subroutines = {},
        }
        headers[current].channels[#headers[current].channels + 1] = spec
        channelsBySymbol[sym] = spec
      end
    end
  end
  return headers
end

RomExtractorGen2._parseCrystalSfxHeaders = parseCrystalSfxHeaders

local function parseCrystalMoveAnimMeta()
  local handle = assert(io.open("roms/pokecrystal/data/moves/animations.asm", "rb"))
  local text = handle:read("*a")
  handle:close()
  local out = {}
  local current, lines = nil, nil
  local function flush()
    if not current then return end
    local entry = { effect = "SE_DELAY_ANIMATION_10" }
    for _, row in ipairs(lines) do
      local pitch, tempo, sfx = row:match("anim_sound%s+(%d+),%s*(%d+),%s*(SFX_[A-Z0-9_]+)")
      if pitch and tempo and sfx and not entry.sound then
        entry.sound = crystalSfxKey(sfx)
        entry.pitch = tonumber(pitch)
        entry.tempo = tonumber(tempo)
      end
      if row:match("BATTLE_BG_EFFECT_FLASH") then
        entry.effect = "SE_DARK_SCREEN_FLASH"
      elseif row:match("BATTLE_BG_EFFECT_SHAKE_SCREEN")
          or row:match("BATTLE_BG_EFFECT_ROCK_THROW")
          or row:match("BATTLE_BG_EFFECT_BODY_SLAM")
          or row:match("BATTLE_BG_EFFECT_TACKLE") then
        entry.effect = "SE_SHAKE_SCREEN"
      end
    end
    out[current] = entry
  end
  for line in text:gmatch("[^\r\n]+") do
    local label = line:match("^(BattleAnim_[A-Za-z0-9_]+):$")
    if label then
      flush()
      current = label:gsub("^BattleAnim_", ""):upper()
      lines = {}
    elseif current then
      lines[#lines + 1] = line
    end
  end
  flush()
  return out
end

function RomExtractorGen2:symbol(name)
  local location = self.symbols[name]
  if location then
    return { bank = location[1], address = location[2], name = name }
  end
  local cached = self.symCache[name]
  if cached then return cached end
  local symPath = "roms/pokecrystal/pokecrystal.sym"
  local handle = io.open(symPath, "rb")
  if handle then
    for line in handle:lines() do
      local parsed = parseSymLine(line)
      if parsed and parsed.name == name then
        handle:close()
        self.symCache[name] = parsed
        return parsed
      end
    end
    handle:close()
  end
  error("required symbol is missing: " .. tostring(name))
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

local START_NPC_SPRITES = {
  SPRITE_RIVAL = { file = "rival.png", frames = 6, walker = true, palette = "red" },
  SPRITE_TEACHER = { file = "teacher.png", frames = 6, walker = true, palette = "red" },
  SPRITE_FISHER = { file = "fisher.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_MOM = { file = "mom.png", frames = 6, walker = true, palette = "red" },
  SPRITE_GRAMPS = { file = "gramps.png", frames = 6, walker = true, palette = "brown" },
  SPRITE_POKEFAN_F = { file = "pokefan_f.png", frames = 6, walker = true, palette = "brown" },
  SPRITE_POKEFAN_M = { file = "pokefan_m.png", frames = 6, walker = true, palette = "brown" },
  SPRITE_COOLTRAINER_F = { file = "cooltrainer_f.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_BUG_CATCHER = { file = "bug_catcher.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_ELM = { file = "elm.png", frames = 6, walker = true, palette = "brown" },
  SPRITE_SCIENTIST = { file = "scientist.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_OFFICER = { file = "officer.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_NURSE = { file = "nurse.png", frames = 6, walker = false, palette = "red" },
  SPRITE_CLERK = { file = "clerk.png", frames = 6, walker = true, palette = "green" },
  SPRITE_POKE_BALL = { file = "poke_ball.png", frames = 1, walker = false, palette = "red" },
  SPRITE_COOLTRAINER_M = { file = "cooltrainer_m.png", frames = 6, walker = true, palette = "red" },
  SPRITE_YOUNGSTER = { file = "youngster.png", frames = 6, walker = true, palette = "green" },
  SPRITE_LASS = { file = "lass.png", frames = 6, walker = true, palette = "red" },
  SPRITE_SUPER_NERD = { file = "super_nerd.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_FISHING_GURU = { file = "fishing_guru.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_GYM_GUIDE = { file = "gym_guide.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_GAMEBOY_KID = { file = "gameboy_kid.png", frames = 6, walker = false, palette = "green" },
  SPRITE_FRUIT_TREE = { file = "fruit_tree.png", frames = 1, walker = false, palette = "tree" },
  SPRITE_MONSTER = { file = "monster.png", frames = 1, walker = false, palette = "red" },
  -- Mr. Pokémon's House's own two always-visible objects (object_event
  -- trailing flag -1 / a never-set flag -- both read visible-by-default,
  -- confirmed this session's Task 6). Both crashed a live playtest
  -- ("unknown sprite SPRITE_GENTLEMAN", src/world/NPC.lua:28) since
  -- neither was in this table -- Task 6's own report wrongly generalized
  -- the "a HIDDEN object's missing sprite never crashes" precedent
  -- (true for Cherrygrove's SPRITE_GRAMPS) to these two, which are not
  -- hidden. Palettes are each sprite's own ROM default (not a per-object
  -- override -- MrPokemonsHouse.asm's object_events pass literal `0`,
  -- i.e. "use the sprite's own default", per data/sprites/sprites.asm's
  -- own `overworld_sprite GentlemanSpriteGFX, ..., PAL_OW_BLUE` /
  -- `OakSpriteGFX, ..., PAL_OW_BROWN`).
  SPRITE_GENTLEMAN = { file = "gentleman.png", frames = 6, walker = true, palette = "blue" },
  SPRITE_OAK = { file = "oak.png", frames = 6, walker = true, palette = "brown" },
}

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

  -- The player's own battle back pic (field.playerPics, Sprites.playerPath)
  -- -- separate from the overworld walk sheets above. gfx/player/*_back.png
  -- are pret's own single-frame rips (48x48, no animation sheet to crop,
  -- unlike the Pokémon front sprites), same matte-needed shape as those:
  -- palette-indexed, no alpha channel.
  self:save(ImageWriter.matteColor0(
    love.image.newImageData("roms/pokecrystal/gfx/player/chris_back.png")),
    "battle/chris_back.png")
  self:save(ImageWriter.matteColor0(
    love.image.newImageData("roms/pokecrystal/gfx/player/kris_back.png")),
    "battle/kris_back.png")

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
  for spriteId, spec in pairs(START_NPC_SPRITES) do
    local sourcePath = "roms/pokecrystal/gfx/sprites/" .. spec.file
    self:save(love.image.newImageData(sourcePath), "sprites/" .. spec.file)
    out[spriteId] = {
      id = spriteId,
      source = "decomp:" .. sourcePath,
      paletteSource = "CRYSTAL_OW:" .. spec.palette,
      image = "assets/generated/sprites/" .. spec.file,
      frames = spec.frames,
      walker = spec.walker,
    }
  end
  self:write("sprites", out)
  self:tick("Player sprite", 1, 1)
  return out
end

local function readTextFile(path)
  local handle = assert(io.open(path, "rb"), "could not read " .. tostring(path))
  local text = handle:read("*a")
  handle:close()
  return text
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseRgbPalFile(path)
  local colors = {}
  for line in readTextFile(path):gmatch("[^\r\n]+") do
    local r, g, b = line:match("RGB%s+(%d+),%s*(%d+),%s*(%d+)")
    if r then
      colors[#colors + 1] = {
        math.floor(tonumber(r) * 255 / 31 + 0.5),
        math.floor(tonumber(g) * 255 / 31 + 0.5),
        math.floor(tonumber(b) * 255 / 31 + 0.5),
      }
    end
  end
  return colors
end

local function fileExists(path)
  local handle = io.open(path, "rb")
  if handle then
    handle:close()
    return true
  end
  return false
end

-- Decodes a raw 8-byte GBC sprite palette (front.gbcpal/normal.gbcpal --
-- 4 colors x 2 bytes, little-endian BGR555) into 4 {r,g,b} triples on the
-- hardware's own 0-31 scale. Verified byte-for-byte against
-- roms/pokecrystal/gfx/pokemon/unown/normal.pal, the one species with a
-- checked-in TEXT normal palette to cross-check against -- see the
-- plan's "Research already done" section.
function RomExtractorGen2._decodeGbcPalette(bytes)
  assert(#bytes == 8, "GBC palette must be exactly 8 bytes (4 colors)")
  local colors = {}
  for i = 0, 3 do
    local lo, hi = bytes:byte(i * 2 + 1, i * 2 + 2)
    local value = lo + hi * 256
    colors[i + 1] = {
      bit.band(value, 0x1F),
      bit.band(bit.rshift(value, 5), 0x1F),
      bit.band(bit.rshift(value, 10), 0x1F),
    }
  end
  return colors
end

-- Decodes a shiny.pal's real pret source text (exactly 2 "RGB r, g, b"
-- lines, 0-31 scale, colors 1 and 2 -- colors 0/3 are always white/black
-- and never appear in this file) into 2 {r,g,b} triples on the same
-- 0-31 scale decodeGbcPalette uses.
function RomExtractorGen2._parseShinyPal(text)
  local colors = {}
  for r, g, b in text:gmatch("RGB%s+(%d+)%s*,%s*(%d+)%s*,%s*(%d+)") do
    colors[#colors + 1] = { tonumber(r), tonumber(g), tonumber(b) }
  end
  assert(#colors == 2, ("shiny.pal must have exactly 2 RGB lines, got %d"):format(#colors))
  return colors
end

-- 0-31 (GBC hardware scale) -> 0-1 float (getPixel/setPixel's own range).
local function scale5to1(v)
  return math.floor(v * 255 / 31 + 0.5) / 255
end

-- Combines a species' real normal + shiny palettes into the mapping
-- ImageWriter.remapColors consumes directly: only colors 1 and 2 ever
-- change (0/3 are always white/black, fixed across every species and
-- every shiny variant -- see the plan's "Research already done" section).
function RomExtractorGen2._shinyRemapTable(normalGbcPalBytes, shinyPalText)
  local normal = RomExtractorGen2._decodeGbcPalette(normalGbcPalBytes)
  local shiny = RomExtractorGen2._parseShinyPal(shinyPalText)
  local mapping = {}
  for i = 1, 2 do
    mapping[i] = {
      from = { scale5to1(normal[i + 1][1]), scale5to1(normal[i + 1][2]), scale5to1(normal[i + 1][3]) },
      to = { scale5to1(shiny[i][1]), scale5to1(shiny[i][2]), scale5to1(shiny[i][3]) },
    }
  end
  return mapping
end

local function splitCsv(text)
  local out = {}
  for part in text:gmatch("[^,]+") do
    out[#out + 1] = trim(part)
  end
  return out
end

local function uniqueTypes(a, b)
  if a == b then return { a } end
  return { a, b }
end

local function crystalPercentToByte(value)
  return math.floor((tonumber(value) or 0) * 0xFF / 100)
end

local function crystalBucket(percent)
  if percent >= 100 then return 256 end
  return math.floor(percent * 256 / 100)
end

local function crystalDisplayText(text)
  text = trim(text or "")
  text = text:gsub("#", "POKe")
  return text
end

local SPECIAL_LABELS = {
  FARFETCH_D = "FarfetchD",
  HO_OH = "HoOh",
  MR__MIME = "MrMime",
  NIDORAN_F = "NidoranF",
  NIDORAN_M = "NidoranM",
  PORYGON2 = "Porygon2",
}

local function speciesLabelFromId(id)
  if SPECIAL_LABELS[id] then return SPECIAL_LABELS[id] end
  local out = {}
  for part in id:gmatch("[A-Z0-9]+") do
    if part:match("^%d+$") then
      out[#out + 1] = part
    else
      out[#out + 1] = part:sub(1, 1) .. part:sub(2):lower()
    end
  end
  return table.concat(out)
end

local CRYSTAL_EFFECT_MAP = {
  EFFECT_ACCURACY_DOWN = "ACCURACY_DOWN1_EFFECT",
  EFFECT_ACCURACY_DOWN_HIT = "NO_ADDITIONAL_EFFECT",
  EFFECT_ALL_UP_HIT = "NO_ADDITIONAL_EFFECT",
  EFFECT_ALWAYS_HIT = "SWIFT_EFFECT",
  EFFECT_ATTACK_DOWN = "ATTACK_DOWN1_EFFECT",
  EFFECT_ATTACK_DOWN_2 = "ATTACK_DOWN1_EFFECT",
  EFFECT_ATTACK_DOWN_HIT = "ATTACK_DOWN_SIDE_EFFECT",
  EFFECT_ATTACK_UP = "ATTACK_UP1_EFFECT",
  EFFECT_ATTACK_UP_2 = "ATTACK_UP2_EFFECT",
  EFFECT_ATTACK_UP_HIT = "NO_ADDITIONAL_EFFECT",
  EFFECT_ATTRACT = "NO_ADDITIONAL_EFFECT",
  EFFECT_BATON_PASS = "NO_ADDITIONAL_EFFECT",
  EFFECT_BEAT_UP = "NO_ADDITIONAL_EFFECT",
  EFFECT_BELLY_DRUM = "NO_ADDITIONAL_EFFECT",
  EFFECT_BIDE = "BIDE_EFFECT",
  EFFECT_BURN_HIT = "BURN_SIDE_EFFECT1",
  EFFECT_CONFUSE = "CONFUSION_EFFECT",
  EFFECT_CONFUSE_HIT = "CONFUSION_SIDE_EFFECT",
  EFFECT_CONVERSION = "CONVERSION_EFFECT",
  EFFECT_CONVERSION2 = "NO_ADDITIONAL_EFFECT",
  EFFECT_COUNTER = "NO_ADDITIONAL_EFFECT",
  EFFECT_CURSE = "NO_ADDITIONAL_EFFECT",
  EFFECT_DEFENSE_CURL = "DEFENSE_UP1_EFFECT",
  EFFECT_DEFENSE_DOWN = "DEFENSE_DOWN1_EFFECT",
  EFFECT_DEFENSE_DOWN_2 = "DEFENSE_DOWN2_EFFECT",
  EFFECT_DEFENSE_DOWN_HIT = "DEFENSE_DOWN_SIDE_EFFECT",
  EFFECT_DEFENSE_UP = "DEFENSE_UP1_EFFECT",
  EFFECT_DEFENSE_UP_2 = "DEFENSE_UP2_EFFECT",
  EFFECT_DEFENSE_UP_HIT = "NO_ADDITIONAL_EFFECT",
  EFFECT_DESTINY_BOND = "NO_ADDITIONAL_EFFECT",
  EFFECT_DISABLE = "DISABLE_EFFECT",
  EFFECT_DOUBLE_HIT = "ATTACK_TWICE_EFFECT",
  EFFECT_DREAM_EATER = "DREAM_EATER_EFFECT",
  EFFECT_EARTHQUAKE = "NO_ADDITIONAL_EFFECT",
  EFFECT_ENCORE = "NO_ADDITIONAL_EFFECT",
  EFFECT_ENDURE = "NO_ADDITIONAL_EFFECT",
  EFFECT_EVASION_DOWN = "NO_ADDITIONAL_EFFECT",
  EFFECT_EVASION_UP = "EVASION_UP1_EFFECT",
  EFFECT_FALSE_SWIPE = "NO_ADDITIONAL_EFFECT",
  EFFECT_FLAME_WHEEL = "BURN_SIDE_EFFECT1",
  EFFECT_FLINCH_HIT = "FLINCH_SIDE_EFFECT1",
  EFFECT_FLY = "FLY_EFFECT",
  EFFECT_FOCUS_ENERGY = "FOCUS_ENERGY_EFFECT",
  EFFECT_FORCE_SWITCH = "SWITCH_AND_TELEPORT_EFFECT",
  EFFECT_FORESIGHT = "NO_ADDITIONAL_EFFECT",
  EFFECT_FREEZE_HIT = "FREEZE_SIDE_EFFECT1",
  EFFECT_FRUSTRATION = "NO_ADDITIONAL_EFFECT",
  EFFECT_FURY_CUTTER = "NO_ADDITIONAL_EFFECT",
  EFFECT_FUTURE_SIGHT = "NO_ADDITIONAL_EFFECT",
  EFFECT_GUST = "NO_ADDITIONAL_EFFECT",
  EFFECT_HEAL = "HEAL_EFFECT",
  EFFECT_HEAL_BELL = "NO_ADDITIONAL_EFFECT",
  EFFECT_HIDDEN_POWER = "NO_ADDITIONAL_EFFECT",
  EFFECT_HYPER_BEAM = "HYPER_BEAM_EFFECT",
  EFFECT_JUMP_KICK = "JUMP_KICK_EFFECT",
  EFFECT_LEECH_HIT = "DRAIN_HP_EFFECT",
  EFFECT_LEECH_SEED = "LEECH_SEED_EFFECT",
  EFFECT_LEVEL_DAMAGE = "SPECIAL_DAMAGE_EFFECT",
  EFFECT_LIGHT_SCREEN = "LIGHT_SCREEN_EFFECT",
  EFFECT_LOCK_ON = "NO_ADDITIONAL_EFFECT",
  EFFECT_MAGNITUDE = "NO_ADDITIONAL_EFFECT",
  EFFECT_MEAN_LOOK = "NO_ADDITIONAL_EFFECT",
  EFFECT_METRONOME = "METRONOME_EFFECT",
  EFFECT_MIMIC = "MIMIC_EFFECT",
  EFFECT_MIRROR_COAT = "NO_ADDITIONAL_EFFECT",
  EFFECT_MIRROR_MOVE = "MIRROR_MOVE_EFFECT",
  EFFECT_MIST = "MIST_EFFECT",
  EFFECT_MOONLIGHT = "HEAL_EFFECT",
  EFFECT_MORNING_SUN = "HEAL_EFFECT",
  EFFECT_MULTI_HIT = "TWO_TO_FIVE_ATTACKS_EFFECT",
  EFFECT_NIGHTMARE = "NO_ADDITIONAL_EFFECT",
  EFFECT_NORMAL_HIT = "NO_ADDITIONAL_EFFECT",
  EFFECT_OHKO = "OHKO_EFFECT",
  EFFECT_PAIN_SPLIT = "NO_ADDITIONAL_EFFECT",
  EFFECT_PARALYZE = "PARALYZE_EFFECT",
  EFFECT_PARALYZE_HIT = "PARALYZE_SIDE_EFFECT1",
  EFFECT_PAY_DAY = "PAY_DAY_EFFECT",
  EFFECT_PERISH_SONG = "NO_ADDITIONAL_EFFECT",
  EFFECT_POISON = "POISON_EFFECT",
  EFFECT_POISON_HIT = "POISON_SIDE_EFFECT1",
  EFFECT_POISON_MULTI_HIT = "TWINEEDLE_EFFECT",
  EFFECT_PRESENT = "NO_ADDITIONAL_EFFECT",
  EFFECT_PRIORITY_HIT = "NO_ADDITIONAL_EFFECT",
  EFFECT_PROTECT = "NO_ADDITIONAL_EFFECT",
  EFFECT_PSYCH_UP = "NO_ADDITIONAL_EFFECT",
  EFFECT_PSYWAVE = "SPECIAL_DAMAGE_EFFECT",
  EFFECT_PURSUIT = "NO_ADDITIONAL_EFFECT",
  EFFECT_RAGE = "RAGE_EFFECT",
  EFFECT_RAIN_DANCE = "NO_ADDITIONAL_EFFECT",
  EFFECT_RAMPAGE = "THRASH_PETAL_DANCE_EFFECT",
  EFFECT_RAPID_SPIN = "NO_ADDITIONAL_EFFECT",
  EFFECT_RAZOR_WIND = "CHARGE_EFFECT",
  EFFECT_RECOIL_HIT = "RECOIL_EFFECT",
  EFFECT_REFLECT = "REFLECT_EFFECT",
  EFFECT_RESET_STATS = "HAZE_EFFECT",
  EFFECT_RETURN = "NO_ADDITIONAL_EFFECT",
  EFFECT_REVERSAL = "NO_ADDITIONAL_EFFECT",
  EFFECT_ROLLOUT = "NO_ADDITIONAL_EFFECT",
  EFFECT_SACRED_FIRE = "BURN_SIDE_EFFECT2",
  EFFECT_SAFEGUARD = "NO_ADDITIONAL_EFFECT",
  EFFECT_SANDSTORM = "NO_ADDITIONAL_EFFECT",
  EFFECT_SELFDESTRUCT = "EXPLODE_EFFECT",
  EFFECT_SKETCH = "NO_ADDITIONAL_EFFECT",
  EFFECT_SKULL_BASH = "CHARGE_EFFECT",
  EFFECT_SKY_ATTACK = "CHARGE_EFFECT",
  EFFECT_SLEEP = "SLEEP_EFFECT",
  EFFECT_SLEEP_TALK = "NO_ADDITIONAL_EFFECT",
  EFFECT_SNORE = "NO_ADDITIONAL_EFFECT",
  EFFECT_SOLARBEAM = "CHARGE_EFFECT",
  EFFECT_SPEED_DOWN = "SPEED_DOWN1_EFFECT",
  EFFECT_SPEED_DOWN_2 = "NO_ADDITIONAL_EFFECT",
  EFFECT_SPEED_DOWN_HIT = "SPEED_DOWN_SIDE_EFFECT",
  EFFECT_SPEED_UP_2 = "SPEED_UP2_EFFECT",
  EFFECT_SPIKES = "NO_ADDITIONAL_EFFECT",
  EFFECT_SPITE = "NO_ADDITIONAL_EFFECT",
  EFFECT_SPLASH = "SPLASH_EFFECT",
  EFFECT_SP_ATK_UP = "SPECIAL_UP1_EFFECT",
  EFFECT_SP_DEF_DOWN_HIT = "SPECIAL_DOWN_SIDE_EFFECT",
  EFFECT_SP_DEF_UP_2 = "SPECIAL_UP2_EFFECT",
  EFFECT_STATIC_DAMAGE = "SPECIAL_DAMAGE_EFFECT",
  EFFECT_STOMP = "FLINCH_SIDE_EFFECT1",
  EFFECT_SUBSTITUTE = "SUBSTITUTE_EFFECT",
  EFFECT_SUNNY_DAY = "NO_ADDITIONAL_EFFECT",
  EFFECT_SUPER_FANG = "SUPER_FANG_EFFECT",
  EFFECT_SWAGGER = "CONFUSION_EFFECT",
  EFFECT_SYNTHESIS = "HEAL_EFFECT",
  EFFECT_TELEPORT = "SWITCH_AND_TELEPORT_EFFECT",
  EFFECT_THIEF = "NO_ADDITIONAL_EFFECT",
  EFFECT_THUNDER = "PARALYZE_SIDE_EFFECT2",
  EFFECT_TOXIC = "POISON_EFFECT",
  EFFECT_TRANSFORM = "TRANSFORM_EFFECT",
  EFFECT_TRAP_TARGET = "TRAPPING_EFFECT",
  EFFECT_TRIPLE_KICK = "NO_ADDITIONAL_EFFECT",
  EFFECT_TRI_ATTACK = "NO_ADDITIONAL_EFFECT",
  EFFECT_TWISTER = "FLINCH_SIDE_EFFECT1",
}

local FIXED_DAMAGE_MOVES = {
  SONICBOOM = 20,
  DRAGON_RAGE = 40,
  SEISMIC_TOSS = "level",
  NIGHT_SHADE = "level",
  PSYWAVE = "half_level_rand",
}

function RomExtractorGen2:parseCrystalMoves()
  local path = "roms/pokecrystal/data/moves/moves.asm"
  local out = {}
  local index = 0
  local animMeta = parseCrystalMoveAnimMeta()
  for line in readTextFile(path):gmatch("[^\r\n]+") do
    local id, effect, power, moveType, accuracy, pp, chance =
      line:match("^%s*move%s+([A-Z0-9_]+),%s*(EFFECT_[A-Z0-9_]+),%s*(-?%d+),%s*([A-Z0-9_]+),%s*(%d+),%s*(%d+),%s*(%d+)")
    if id then
      index = index + 1
      out[id] = {
        id = id,
        index = index,
        name = id:gsub("_", " "),
        type = moveType,
        power = tonumber(power),
        accuracy = tonumber(accuracy),
        pp = tonumber(pp),
        effect = CRYSTAL_EFFECT_MAP[effect] or "NO_ADDITIONAL_EFFECT",
        effectChance = tonumber(chance),
        originalEffect = effect,
      }
      local anim = animMeta[id]
      if anim and anim.sound then
        out[id].anim = {
          sound = anim.sound,
          pitch = anim.pitch or 0,
          tempo = anim.tempo or 0x80,
        }
        if anim.effect == "SE_SHAKE_SCREEN" then out[id].anim.shake = true end
        if anim.effect == "SE_DARK_SCREEN_FLASH" then out[id].anim.flash = true end
      end
      if FIXED_DAMAGE_MOVES[id] ~= nil then
        out[id].fixedDamage = FIXED_DAMAGE_MOVES[id]
      end
    end
  end
  return out
end

function RomExtractorGen2:extractBattleAnimations(moves)
  self:beginStage("Battle animations")
  local moveAnims = {}
  local animMeta = parseCrystalMoveAnimMeta()
  for moveId in pairs(moves or {}) do
    local meta = animMeta[moveId]
    local row = { effect = (meta and meta.effect) or "SE_DELAY_ANIMATION_10" }
    if meta and meta.sound then row.sound = moveId end
    moveAnims[moveId] = {
      source = "decomp:roms/pokecrystal/data/moves/animations.asm",
      seq = { row },
    }
  end
  for _, name in ipairs({
    "POOF_ANIM", "HIDEPIC_ANIM", "SHOWPIC_ANIM",
    "TOSS_ANIM", "GREATTOSS_ANIM", "ULTRATOSS_ANIM",
    "SHAKE_ANIM", "BLOCKBALL_ANIM",
    "SLP_ANIM", "SLP_PLAYER_ANIM", "CONF_ANIM", "CONF_PLAYER_ANIM",
    "XSTATITEM_ANIM", "XSTATITEM_DUPLICATE_ANIM",
    "TELEPORT", "DIG", "FLY",
  }) do
    if not moveAnims[name] then
      moveAnims[name] = {
        source = "Crystal fallback battle anim",
        seq = { { effect = "SE_DELAY_ANIMATION_10" } },
      }
    end
  end
  local out = {
    tilesheets = {},
    baseCoords = {},
    frameBlocks = {},
    subanims = {},
    moveAnims = moveAnims,
  }
  self:write("battle_anims", out)
  self:tick("Battle animations", 1, 1)
  return out
end

function RomExtractorGen2:parseCrystalLearnsets()
  local byLabel = {}
  local out = {}
  for _, species in ipairs(self.crystalSpeciesOrder or {}) do
    byLabel[speciesLabelFromId(species)] = species
  end
  local current, inMoves = nil, false
  for line in readTextFile("roms/pokecrystal/data/pokemon/evos_attacks.asm"):gmatch("[^\r\n]+") do
    local label = line:match("^([A-Za-z0-9_]+)EvosAttacks:$")
    if label then
      current = byLabel[label]
      inMoves = false
      if current then out[current] = {} end
    elseif current then
      if line:match("^%s*db%s+0%s*;%s*no more evolutions") then
        inMoves = true
      elseif line:match("^%s*db%s+0%s*;%s*no more level%-up moves") then
        current, inMoves = nil, false
      elseif inMoves then
        local level, move = line:match("^%s*db%s+(%d+),%s*([A-Z0-9_]+)")
        if level and move then
          out[current][#out[current] + 1] = { level = tonumber(level), move = move }
        end
      end
    end
  end
  return out
end

function RomExtractorGen2:parseCrystalSpecies(moves)
  local order = {}
  for include in readTextFile("roms/pokecrystal/data/pokemon/base_stats.asm"):gmatch('INCLUDE%s+"data/pokemon/base_stats/([^"]+)"') do
    local filePath = "roms/pokecrystal/data/pokemon/base_stats/" .. include
    local text = readTextFile(filePath)
    local species, dex = text:match("^%s*db%s+([A-Z0-9_]+)%s*;%s*(%d+)")
    local hp, atk, def, spd, sat = text:match("db%s+(%d+),%s*(%d+),%s*(%d+),%s*(%d+),%s*(%d+),%s*(%d+)")
    local type1, type2 = text:match("db%s+([A-Z0-9_]+),%s*([A-Z0-9_]+)%s*;%s*type")
    local catchRate = text:match("db%s+(%-?%d+)%s*;%s*catch rate")
    local baseExp = text:match("db%s+(%-?%d+)%s*;%s*base exp")
    local frontStem = text:match('INCBIN%s+"gfx/pokemon/([^"]+)/front%.dimensions"')
    local growthRate = text:match("db%s+(GROWTH_[A-Z0-9_]+)%s*;%s*growth rate")
    assert(species and dex and hp and atk and def and spd and sat
      and type1 and type2 and catchRate and growthRate and frontStem,
      "could not parse Crystal species file " .. include)
    order[#order + 1] = species
  end
  self.crystalSpeciesOrder = order
  local learnsets = self:parseCrystalLearnsets()
  local out = {}
  for include in readTextFile("roms/pokecrystal/data/pokemon/base_stats.asm"):gmatch('INCLUDE%s+"data/pokemon/base_stats/([^"]+)"') do
    local filePath = "roms/pokecrystal/data/pokemon/base_stats/" .. include
    local text = readTextFile(filePath)
    local species, dex = text:match("^%s*db%s+([A-Z0-9_]+)%s*;%s*(%d+)")
    local hp, atk, def, spd, sat = text:match("db%s+(%d+),%s*(%d+),%s*(%d+),%s*(%d+),%s*(%d+),%s*(%d+)")
    local type1, type2 = text:match("db%s+([A-Z0-9_]+),%s*([A-Z0-9_]+)%s*;%s*type")
    local catchRate = text:match("db%s+(%-?%d+)%s*;%s*catch rate")
    local baseExp = text:match("db%s+(%-?%d+)%s*;%s*base exp")
    local frontStem = text:match('INCBIN%s+"gfx/pokemon/([^"]+)/front%.dimensions"')
    local growthRate = text:match("db%s+(GROWTH_[A-Z0-9_]+)%s*;%s*growth rate")
    local learnset = learnsets[species] or {}
    local level1Moves = {}
    for _, entry in ipairs(learnset) do
      if entry.level == 1 then
        local duplicate = false
        for _, existing in ipairs(level1Moves) do
          if existing == entry.move then
            duplicate = true
            break
          end
        end
        if not duplicate then level1Moves[#level1Moves + 1] = entry.move end
      end
    end
    local frontSource = "roms/pokecrystal/gfx/pokemon/" .. frontStem .. "/front.png"
    local backSource = "roms/pokecrystal/gfx/pokemon/" .. frontStem .. "/back.png"
    if fileExists(frontSource) then
      -- gfx/pokemon/*/front.png is pret's own rip of every animation frame
      -- stacked vertically (front.animated.tilemap/bitmask.asm/frames.asm
      -- describe a tile-substitution animation, not simple cels), always
      -- an exact multiple of the sprite's own width tall -- e.g.
      -- cyndaquil is 40x200 (5 frames), snorlax 56x336 (6 frames).  This
      -- project has no battle-sprite animation player yet (Gen1's own
      -- pics are single-frame), so drawing the whole sheet stacked every
      -- copy of the sprite on screen.  Crop to the top width x width
      -- square -- frame 1, bitmask $00, i.e. the unmodified base pose --
      -- until real animation playback exists.
      local full = love.image.newImageData(frontSource)
      local size = full:getWidth()
      local frame = ImageWriter.blank(size, size, 0, 0, 0, 0)
      ImageWriter.blit(frame, full, 0, 0, 0, 0, size, size)
      -- pret's front.png/back.png are palette-indexed PNGs with no alpha
      -- channel -- solid white behind the pose, not transparent -- so
      -- matte it the same way RomExtractor.lua already does for every
      -- Gen1 pic (flood-fills white in from the four edges only, so it
      -- cannot eat a legitimately white patch fully inside the sprite).
      self:save(ImageWriter.matteColor0(frame), "pokemon/" .. frontStem .. "_front.png")
    end
    if fileExists(backSource) then
      self:save(ImageWriter.matteColor0(love.image.newImageData(backSource)),
        "pokemon/" .. frontStem .. "_back.png")
    end
    local shinyPalSource = "roms/pokecrystal/gfx/pokemon/" .. frontStem .. "/shiny.pal"
    local normalGbcPalSource = "roms/pokecrystal/gfx/pokemon/" .. frontStem .. "/front.gbcpal"
    local spriteFrontShiny, spriteBackShiny
    if fileExists(shinyPalSource) and fileExists(normalGbcPalSource)
        and fileExists(frontSource) then
      local mapping = RomExtractorGen2._shinyRemapTable(
        readTextFile(normalGbcPalSource), readTextFile(shinyPalSource))
      -- re-derive the same cropped/matted front image the normal path
      -- already built above, then remap it -- kept as a fresh decode
      -- rather than threading the earlier local through, so this block
      -- reads standalone against the same source files.
      local full = love.image.newImageData(frontSource)
      local size = full:getWidth()
      local frame = ImageWriter.blank(size, size, 0, 0, 0, 0)
      ImageWriter.blit(frame, full, 0, 0, 0, 0, size, size)
      local shinyFront = ImageWriter.remapColors(ImageWriter.matteColor0(frame), mapping)
      self:save(shinyFront, "pokemon/" .. frontStem .. "_front_shiny.png")
      spriteFrontShiny = "assets/generated/pokemon/" .. frontStem .. "_front_shiny.png"
      if fileExists(backSource) then
        local shinyBack = ImageWriter.remapColors(
          ImageWriter.matteColor0(love.image.newImageData(backSource)), mapping)
        self:save(shinyBack, "pokemon/" .. frontStem .. "_back_shiny.png")
        spriteBackShiny = "assets/generated/pokemon/" .. frontStem .. "_back_shiny.png"
      end
    end
    out[species] = {
      id = species,
      index = tonumber(dex),
      dex = tonumber(dex),
      name = species:gsub("_", " "),
      source = "decomp:" .. filePath,
      types = uniqueTypes(type1, type2),
      baseStats = {
        hp = tonumber(hp), attack = tonumber(atk), defense = tonumber(def),
        speed = tonumber(spd), special = tonumber(sat),
      },
      catchRate = tonumber(catchRate),
      baseExp = tonumber(baseExp),
      growthRate = growthRate:gsub("^GROWTH_", ""),
      learnset = learnset,
      level1Moves = level1Moves,
      spriteFront = fileExists(frontSource)
        and ("assets/generated/pokemon/" .. frontStem .. "_front.png") or nil,
      spriteBack = fileExists(backSource)
        and ("assets/generated/pokemon/" .. frontStem .. "_back.png") or nil,
      spriteFrontShiny = spriteFrontShiny,
      spriteBackShiny = spriteBackShiny,
      trueColor = true,
    }
  end
  return out
end

-- Party-menu icons (Data.icons, consumed by PartyMenu.lua's drawIcon /
-- src.pokemon.Sprites.iconPath). Same shape as Gen1's own icons table
-- (RomExtractor.lua:extractIcons): byDex[dex] names a shared shape, icons[
-- name] is that shape's image path -- Crystal reuses the mechanism as-is,
-- it just fills it from data/pokemon/menu_icons.asm's ICON_* column instead
-- of decoding MonPartyData nybbles from ROM bytes.
function RomExtractorGen2:extractIcons(pokemon)
  self:beginStage("Party icons")
  local entries = {}
  for line in readTextFile("roms/pokecrystal/data/pokemon/menu_icons.asm"):gmatch("[^\r\n]+") do
    local shape, species = line:match("db%s+ICON_([A-Z0-9_]+)%s*;%s*([A-Z0-9_]+)")
    if shape and species then entries[#entries + 1] = { shape = shape, species = species } end
  end
  local byDex, shapesSeen = {}, {}
  for index, entry in ipairs(entries) do
    local def = pokemon[entry.species]
    if def and def.dex then
      byDex[def.dex] = entry.shape
      shapesSeen[entry.shape] = true
    end
    self:tick("Party icons", index, #entries)
  end
  local icons = {}
  for shape in pairs(shapesSeen) do
    -- gfx/icons/<shape>.png is pret's own rip, 16x32: two 16x16
    -- animation frames (the party-menu wiggle) stacked vertically, same
    -- shape as the front-sprite sheets above -- crop to the top frame
    -- and matte its white background the same way, for the same reason
    -- (no icon animation player exists yet).
    local sourcePath = "roms/pokecrystal/gfx/icons/" .. shape:lower() .. ".png"
    if fileExists(sourcePath) then
      local full = love.image.newImageData(sourcePath)
      local size = full:getWidth()
      local frame = ImageWriter.blank(size, size, 0, 0, 0, 0)
      ImageWriter.blit(frame, full, 0, 0, 0, 0, size, size)
      self:save(ImageWriter.matteColor0(frame), "icons/" .. shape:lower() .. ".png")
      icons[shape] = "assets/generated/icons/" .. shape:lower() .. ".png"
    end
  end
  local data = { source = "ROM:MonMenuIcons", byDex = byDex, icons = icons }
  self:write("icons", data)
  return data
end

function RomExtractorGen2:parseCrystalTypeChart()
  local types = {
    NORMAL = { name = "NORMAL", category = "physical" },
    FIGHTING = { name = "FIGHTING", category = "physical" },
    FLYING = { name = "FLYING", category = "physical" },
    POISON = { name = "POISON", category = "physical" },
    GROUND = { name = "GROUND", category = "physical" },
    ROCK = { name = "ROCK", category = "physical" },
    BUG = { name = "BUG", category = "physical" },
    GHOST = { name = "GHOST", category = "physical" },
    STEEL = { name = "STEEL", category = "physical" },
    FIRE = { name = "FIRE", category = "special" },
    WATER = { name = "WATER", category = "special" },
    GRASS = { name = "GRASS", category = "special" },
    ELECTRIC = { name = "ELECTRIC", category = "special" },
    PSYCHIC_TYPE = { name = "PSYCHIC", category = "special" },
    ICE = { name = "ICE", category = "special" },
    DRAGON = { name = "DRAGON", category = "special" },
    DARK = { name = "DARK", category = "special" },
    CURSE_TYPE = { name = "CURSE", category = "physical" },
  }
  local multiplierByName = {
    SUPER_EFFECTIVE = 20,
    NOT_VERY_EFFECTIVE = 5,
    NO_EFFECT = 0,
  }
  local matchups = {}
  for line in readTextFile("roms/pokecrystal/data/types/type_matchups.asm"):gmatch("[^\r\n]+") do
    local attacker, defender, multName =
      line:match("^%s*db%s+([A-Z0-9_]+),%s*([A-Z0-9_]+),%s*([A-Z_]+)")
    if attacker and defender and multiplierByName[multName] ~= nil then
      matchups[#matchups + 1] = {
        attacker = attacker,
        defender = defender,
        multiplier = multiplierByName[multName],
      }
    end
  end
  return { types = types, matchups = matchups }
end

function RomExtractorGen2:parseCrystalItems()
  local constantsText = readTextFile("roms/pokecrystal/constants/item_constants.asm")
  local namesText = readTextFile("roms/pokecrystal/data/items/names.asm")
  local attrsText = readTextFile("roms/pokecrystal/data/items/attributes.asm")

  local ids = {}
  local baseIndex = 0
  local inTmhm = false
  local hmNumber = 0
  local tmNumber = 0
  for line in constantsText:gmatch("[^\r\n]+") do
    if line:find("^DEF NUM_ITEMS EQU") then
      inTmhm = true
    elseif line:find("^DEF NUM_HMS EQU") then
      -- keep parsing, HMs already handled by add_hm
    elseif line:find("^DEF MT01 EQU") then
      break
    end
    local constId = line:match("^const%s+([A-Z0-9_]+)")
    if constId and constId ~= "NO_ITEM" then
      if not inTmhm then
        baseIndex = baseIndex + 1
        ids[#ids + 1] = { id = constId, index = baseIndex, machine = nil }
      else
        ids[#ids + 1] = { id = constId, machine = nil }
      end
    end
    local tmMove = line:match("^add_tm%s+([A-Z0-9_]+)")
    if tmMove then
      tmNumber = tmNumber + 1
      ids[#ids + 1] = {
        id = "TM_" .. tmMove,
        machine = { kind = "TM", number = tmNumber, move = tmMove },
      }
    end
    local hmMove = line:match("^add_hm%s+([A-Z0-9_]+)")
    if hmMove then
      hmNumber = hmNumber + 1
      ids[#ids + 1] = {
        id = "HM_" .. hmMove,
        machine = { kind = "HM", number = hmNumber, move = hmMove },
      }
    end
  end

  local names = {}
  for rawName in namesText:gmatch('li%s+"([^"]+)"') do
    names[#names + 1] = crystalDisplayText(rawName)
  end

  local attrs = {}
  local pendingId
  for line in attrsText:gmatch("[^\r\n]+") do
    local label = line:match("^;%s*([A-Z0-9_]+)")
    if label then pendingId = trim(label) end
    local price, heldEffect, param, property, pocket, fieldMenu, battleMenu =
      line:match("^%s*item_attribute%s+([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,%s]+)")
    if price and pendingId then
      attrs[pendingId] = {
        price = trim(price),
        heldEffect = trim(heldEffect),
        param = trim(param),
        property = trim(property),
        pocket = trim(pocket),
        fieldMenu = trim(fieldMenu),
        battleMenu = trim(battleMenu),
      }
      pendingId = nil
    end
  end

  local out = {}
  for i, meta in ipairs(ids) do
    local attr = attrs[meta.id] or {}
    local priceText = attr.price or "0"
    if priceText:sub(1, 1) == "$" then
      priceText = tostring(tonumber(priceText:sub(2), 16) or 0)
    end
    local pocket = trim(attr.pocket or
      (meta.machine and "TM_HM" or "ITEM"))
    local keyItem = pocket == "KEY_ITEM"
    out[meta.id] = {
      id = meta.id,
      index = meta.index,
      name = crystalDisplayText(names[i] or meta.id),
      price = tonumber(priceText) or 0,
      source = "decomp:data/items/{names,attributes}.asm",
      machine = meta.machine,
      pocket = pocket,
      keyItem = keyItem or nil,
      tossable = not (attr.property and attr.property:find("CANT_TOSS", 1, true)),
    }
  end
  return out
end

function RomExtractorGen2:parseCrystalEncounters()
  local out = {}
  local grassBuckets = {
    crystalBucket(30), crystalBucket(60), crystalBucket(80),
    crystalBucket(90), crystalBucket(95), crystalBucket(99), 256,
  }
  local waterBuckets = {
    crystalBucket(60), crystalBucket(90), 256,
  }

  local function parseGrassFile(path)
    local current
    local phase
    local slotIndex = 0
    for line in readTextFile(path):gmatch("[^\r\n]+") do
      local mapId = line:match("^%s*def_grass_wildmons%s+([A-Z0-9_]+)")
      if mapId then
        current = { id = trim(mapId) }
        phase = nil
        slotIndex = 0
      elseif current then
        local morn, day, nite =
          line:match("^%s*db%s+(%d+)%s+percent,%s*(%d+)%s+percent,%s*(%d+)%s+percent")
        if morn then
          current.grass = {
            rate = crystalPercentToByte(day),
            slots = {},
            buckets = grassBuckets,
          }
        elseif line:find("^%s*;%s*day") then
          phase = "day"
          slotIndex = 0
        elseif line:find("^%s*;%s*morn") or line:find("^%s*;%s*nite") then
          phase = nil
        elseif line:find("^%s*end_grass_wildmons") then
          if current.grass and #current.grass.slots > 0 then
            out[current.id] = {
              source = "decomp:" .. path,
              grass = current.grass,
            }
          end
          current = nil
          phase = nil
        elseif phase == "day" then
          local level, species = line:match("^%s*db%s+(%d+),%s*([A-Z0-9_]+)")
          if level and species and slotIndex < 7 then
            slotIndex = slotIndex + 1
            current.grass.slots[#current.grass.slots + 1] = {
              level = tonumber(level),
              species = trim(species),
            }
          end
        end
      end
    end
  end

  local function parseWaterFile(path)
    local current
    for line in readTextFile(path):gmatch("[^\r\n]+") do
      local mapId = line:match("^%s*def_water_wildmons%s+([A-Z0-9_]+)")
      if mapId then
        current = {
          id = trim(mapId),
          water = { rate = 0, slots = {}, buckets = waterBuckets },
        }
      elseif current then
        local rate = line:match("^%s*db%s+(%d+)%s+percent")
        if rate then
          current.water.rate = crystalPercentToByte(rate)
        elseif line:find("^%s*end_water_wildmons") then
          if #current.water.slots > 0 then
            out[current.id] = out[current.id] or { source = "decomp:" .. path }
            out[current.id].water = current.water
          end
          current = nil
        else
          local level, species = line:match("^%s*db%s+(%d+),%s*([A-Z0-9_]+)")
          if level and species and #current.water.slots < 3 then
            current.water.slots[#current.water.slots + 1] = {
              level = tonumber(level),
              species = trim(species),
            }
          end
        end
      end
    end
  end

  parseGrassFile("roms/pokecrystal/data/wild/johto_grass.asm")
  parseGrassFile("roms/pokecrystal/data/wild/kanto_grass.asm")
  parseWaterFile("roms/pokecrystal/data/wild/johto_water.asm")
  parseWaterFile("roms/pokecrystal/data/wild/kanto_water.asm")
  return out
end

local TILESET_SPECS = {
  TILESET_JOHTO = {
    gfx = "TilesetJohtoGFX", meta = "TilesetJohtoMeta", coll = "TilesetJohtoColl",
    image = "johto.png", source = "ROM:TilesetJohtoGFX/Meta/Coll",
  },
  TILESET_PLAYERS_HOUSE = {
    gfx = "TilesetPlayersHouseGFX", meta = "TilesetPlayersHouseMeta",
    coll = "TilesetPlayersHouseColl", image = "players_house.png",
    source = "ROM:TilesetPlayersHouseGFX/Meta/Coll",
  },
  TILESET_PLAYERS_ROOM = {
    gfx = "TilesetPlayersRoomGFX", meta = "TilesetPlayersRoomMeta",
    coll = "TilesetPlayersRoomColl", image = "players_room.png",
    source = "ROM:TilesetPlayersRoomGFX/Meta/Coll",
  },
  TILESET_LAB = {
    gfx = "TilesetLabGFX", meta = "TilesetLabMeta",
    coll = "TilesetLabColl", image = "lab.png",
    source = "ROM:TilesetLabGFX/Meta/Coll",
  },
  TILESET_HOUSE = {
    gfx = "TilesetHouseGFX", meta = "TilesetHouseMeta",
    coll = "TilesetHouseColl", image = "house.png",
    source = "ROM:TilesetHouseGFX/Meta/Coll",
  },
  -- Route29Route46Gate's tileset (data/maps/maps.asm: `map
  -- Route29Route46Gate, TILESET_GATE, GATE, ...`).
  TILESET_GATE = {
    gfx = "TilesetGateGFX", meta = "TilesetGateMeta",
    coll = "TilesetGateColl", image = "gate.png",
    source = "ROM:TilesetGateGFX/Meta/Coll",
  },
  -- MrPokemonsHouse's tileset (data/maps/maps.asm: `map MrPokemonsHouse,
  -- TILESET_FACILITY, INDOOR, ...`).
  TILESET_FACILITY = {
    gfx = "TilesetFacilityGFX", meta = "TilesetFacilityMeta",
    coll = "TilesetFacilityColl", image = "facility.png",
    source = "ROM:TilesetFacilityGFX/Meta/Coll",
  },
  TILESET_MART = {
    gfx = "TilesetMartGFX", meta = "TilesetMartMeta",
    coll = "TilesetMartColl", image = "mart.png",
    source = "ROM:TilesetMartGFX/Meta/Coll",
  },
  TILESET_POKECENTER = {
    gfx = "TilesetPokecenterGFX", meta = "TilesetPokecenterMeta",
    coll = "TilesetPokecenterColl", image = "pokecenter.png",
    source = "ROM:TilesetPokecenterGFX/Meta/Coll",
  },
}

local function decodeBlocks(raw)
  local blocks = {}
  for offset = 1, #raw, 16 do
    local block = {}
    for pos = offset, offset + 15 do block[#block + 1] = raw[pos] end
    blocks[#blocks + 1] = block
  end
  return blocks
end

function RomExtractorGen2:extractTileset()
  self:beginStage("Crystal start tilesets")
  local out = {}
  local total, index = 0, 0
  for _ in pairs(TILESET_SPECS) do total = total + 1 end
  for id, spec in pairs(TILESET_SPECS) do
    local gfx = self:symbol(spec.gfx)
    local meta = self:symbol(spec.meta)
    local coll = self:symbol(spec.coll)

    local compressed = self.rom:bytes(gfx.bank, gfx.address, 0x4000)
    local raw = Lz3.decompress(compressed)
    local widthTiles = 16
    local width = widthTiles * 8
    local height = #raw / 16 / widthTiles * 8
    local image = ImageWriter.decode2bpp(raw, width, height)
    self:save(image, "tilesets/" .. spec.image)

    local blocks = decodeBlocks(self.rom:bytes(meta.bank, meta.address, 2048))
    local collRaw = self.rom:bytes(coll.bank, coll.address, #blocks * 4)
    local walkableSet, grassSet, hopSet = {}, {}, {}
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
          if bit.band(permission, GRASS) == GRASS then grassSet[tileId] = true end
        elseif bit.band(permission, 0x0F) == HOP_TILE then
          -- Keyed by (blockIndex, cellIndex/quadrant), NOT by the
          -- resolved 8x8 graphic tile id the walkable/grass branches use
          -- above -- verified against the real ROM (TILESET_JOHTO) that
          -- the same graphic tile id can carry a hop permission in one
          -- placed block and plain walkable floor in another (tile
          -- identity is not collision identity once a graphic gets
          -- reused across metatiles). Block+quadrant is exactly what the
          -- real engine's own wPlayerTileCollision byte is keyed by too
          -- (home/map.asm's collision lookup reads the block's own 4
          -- permission bytes directly, never the tile graphic). Keyed by
          -- the 0-based block id (blockIndex - 1) to match Map:blockAt's
          -- own 0-based convention (Map.lua indexes tileset.blocks with
          -- blockId + 1, the same +1 this file's decodeBlocks output
          -- already expects).
          local blockId = blockIndex - 1
          hopSet[blockId] = hopSet[blockId] or {}
          hopSet[blockId][cellIndex] = HOP_FACINGS[collValue]
        end
      end
    end
    local walkable = {}
    for tileId in pairs(walkableSet) do walkable[#walkable + 1] = tileId end
    table.sort(walkable)
    -- src/world/Map.lua's isGrassCell accepts either a single number
    -- (Gen1's tilesets, one grass tile each) or a set table like this one
    -- (Gen2 tilesets can have more than one, e.g. long vs. tall grass) --
    -- nil, same as Gen1, when a tileset has no grass tile at all (indoor
    -- tilesets).
    local grassTile = next(grassSet) and grassSet or nil
    -- block id -> quadrant (0-3) -> {up=,down=,left=,right=} allowed
    -- hop-facing set (see HOP_FACINGS above); nil when this tileset has
    -- no ledges at all (indoor tilesets, and any outdoor tileset that
    -- just doesn't use COLL_HOP_* -- not every route has ledges).
    local hopFacing = next(hopSet) and hopSet or nil

    out[id] = {
      id = id, source = spec.source,
      image = "assets/generated/tilesets/" .. spec.image,
      imageWidth = width, imageHeight = height, tilesPerRow = width / 8,
      blocks = blocks, walkable = walkable,
      counterTiles = {}, grassTile = grassTile, doorTiles = {}, warpTiles = {},
      hopFacing = hopFacing,
      animation = nil,
    }
    index = index + 1
    self:tick("Crystal start tilesets", index, total)
  end
  self:write("tilesets", out)
  return out
end

-- Ported verbatim from src/import/Rom.lua's (private, unexported)
-- transposePicTiles -- Gen1's Pokemon-pic decompressor has its own copy for
-- the same reason: Pokemon/trainer PIC tile data (unlike tileset gfx) is
-- stored column-major in ROM, so decode2bpp's row-major tile walk needs the
-- width x width tile grid transposed first. Confirmed empirically during
-- planning: decoding PokemonProfPic's raw LZ3 output straight through
-- decode2bpp the same way extractTileset does (no transpose) produced a
-- diagonally-scrambled portrait, not Oak; adding this fixed it and produced
-- a recognizable portrait. Operates on a 1-indexed flat byte array in place.
local function transposePicTiles(data, width)
  local tileCount = width * width
  for index = 0, tileCount - 1 do
    local other = (index * width + math.floor(index / width)) % tileCount
    if index < other then
      for offset = 1, 16 do
        local left = index * 16 + offset
        local right = other * 16 + offset
        data[left], data[right] = data[right], data[left]
      end
    end
  end
end

-- Oak's trainer portrait and Wooper's front sprite, both LZ3-compressed
-- 2bpp pics -- same decompress-then-decode2bpp shape extractTileset already
-- uses for TilesetJohtoGFX, plus the transpose step above that PIC data
-- (unlike tileset gfx) needs.
--
-- PokemonProfPic decompresses to exactly 49 tiles (784 bytes, confirmed
-- against the real ROM during planning) -- trainer pics always fill the
-- full 7x7/56x56 box and aren't animated in Gen2 (only Pokemon pics are,
-- confirmed by reading engine/gfx/load_pics.asm's GetTrainerPic, which
-- decompresses straight into the display buffer with no dimension lookup
-- or padding step, unlike _GetFrontpic below), so it's a plain
-- transpose+decode after decompression.
--
-- WooperFrontpic decompresses to 34 tiles (544 bytes, confirmed against the
-- real ROM) -- more than a static sprite needs. Gen2 Pokemon frontpics
-- support two-frame animation (pokecrystal's engine/gfx/pic_animation.asm),
-- and WooperFrontpic's compressed data is pointed at by
-- data/pokemon/pic_pointers.asm the same way for both the animated and
-- non-animated call paths -- there's no separate "static-only" symbol.
-- Reading engine/gfx/load_pics.asm's _GetFrontpic (the non-animated path
-- GetMonFrontpic uses) shows it decompresses that same blob but only ever
-- copies out wBasePicSize's b*b tiles (via PadFrontpic) -- b = 5 for
-- Wooper, confirmed against gfx/pokemon/wooper/front.dimensions in the
-- pokecrystal source (single byte $55, i.e. 5x5). The trailing 9 tiles are
-- delta/blend tiles only pic_animation.asm's frame table
-- (gfx/pokemon/wooper/frames.asm) references, via GetAnimatedFrontpic's
-- separate GetAnimatedEnemyFrontpic call that _GetFrontpic's own
-- (non-animated) path never makes. So a plain static decode slices to the
-- first 25 tiles (400 bytes, 40x40px) before transposing/decoding, matching
-- what _GetFrontpic itself renders for a non-animated frontpic request.
function RomExtractorGen2:extractIntroPics()
  self:beginStage("Intro portraits")
  local oakWidth = 7
  local oak = self:symbol("PokemonProfPic")
  local oakCompressed = self.rom:bytes(oak.bank, oak.address, 0x1000)
  local oakRaw = Lz3.decompress(oakCompressed)
  assert(#oakRaw == oakWidth * oakWidth * 16,
    "PokemonProfPic: unexpected decompressed size " .. #oakRaw)
  transposePicTiles(oakRaw, oakWidth)
  local oakImage = ImageWriter.decode2bpp(oakRaw, oakWidth * 8, oakWidth * 8)
  self:save(oakImage, "trainers/oak.png")
  self:tick("Intro portraits", 1, 2)

  local wooperWidth = 5
  local wooper = self:symbol("WooperFrontpic")
  local wooperCompressed = self.rom:bytes(wooper.bank, wooper.address, 0x1000)
  local wooperDecompressed = Lz3.decompress(wooperCompressed)
  assert(#wooperDecompressed >= wooperWidth * wooperWidth * 16,
    "WooperFrontpic: decompressed data shorter than its base frame")
  local wooperRaw = {}
  for i = 1, wooperWidth * wooperWidth * 16 do
    wooperRaw[i] = wooperDecompressed[i]
  end
  transposePicTiles(wooperRaw, wooperWidth)
  local wooperImage =
    ImageWriter.decode2bpp(wooperRaw, wooperWidth * 8, wooperWidth * 8)
  self:save(wooperImage, "pokemon/wooper_front.png")
  self:tick("Intro portraits", 2, 2)

  local trainers = { OPP_PROF_OAK = {
    id = "OPP_PROF_OAK", source = "ROM:PokemonProfPic",
    pic = "assets/generated/trainers/oak.png",
  } }
  self:write("trainers", trainers)

  local moves = self:parseCrystalMoves()
  local pokemon = self:parseCrystalSpecies(moves)
  local typeChart = self:parseCrystalTypeChart()
  local items = self:parseCrystalItems()
  local encounters = self:parseCrystalEncounters()
  pokemon.WOOPER = pokemon.WOOPER or {}
  pokemon.WOOPER.id = "WOOPER"
  pokemon.WOOPER.source = "ROM:WooperFrontpic"
  pokemon.WOOPER.spriteFront = "assets/generated/pokemon/wooper_front.png"
  pokemon.WOOPER.trueColor = true
  local icons = self:extractIcons(pokemon)
  self:write("pokemon", pokemon)
  self:write("moves", moves)
  self:write("type_chart", typeChart)
  self:write("items", items)
  self:write("encounters", encounters)

  return {
    trainers = trainers,
    pokemon = pokemon,
    moves = moves,
    typeChart = typeChart,
    items = items,
    encounters = encounters,
    icons = icons,
  }
end

local function mapCellTile(mapDef, tilesetDef, cx, cy)
  local tx, ty = cx * 2, cy * 2 + 1
  local bx, by = math.floor(tx / 4), math.floor(ty / 4)
  local blockId
  if bx < 0 or by < 0 or bx >= mapDef.width or by >= mapDef.height then
    blockId = mapDef.borderBlock
  else
    blockId = mapDef.blocks[by * mapDef.width + bx + 1]
  end
  local block = tilesetDef.blocks[(blockId or 0) + 1]
  return block and block[(ty % 4) * 4 + (tx % 4) + 1] or nil
end

function RomExtractorGen2:extractMap()
  self:beginStage("Crystal start maps")
  local manifestMaps = self.manifest.maps or {}
  local out = {}
  local total, index = 0, 0
  for _ in pairs(manifestMaps) do total = total + 1 end
  for mapId, expected in pairs(manifestMaps) do
    local header = self:symbol(expected.label .. "_MapAttributes")
    local border = self.rom:byte(header.bank, header.address)
    local height = self.rom:byte(header.bank, header.address + 1)
    local width = self.rom:byte(header.bank, header.address + 2)
    assert(width == expected.width and height == expected.height,
      mapId .. " ROM dimensions do not match manifest")
    local blocksBank = self.rom:byte(header.bank, header.address + 3)
    local blocksPtr = self.rom:word(header.bank, header.address + 4)
    local eventsBank = self.rom:byte(header.bank, header.address + 6)
    local eventsPtr = self.rom:word(header.bank, header.address + 9)
    local blocks = self.rom:bytes(blocksBank, blocksPtr, width * height)

    local addr = eventsPtr + 2
    local warpCount = self.rom:byte(eventsBank, addr)
    addr = addr + 1
    local warps = {}
    for romIndex = 1, warpCount do
      local row = self.rom:bytes(eventsBank, addr, 5)
      local destMap = self.manifest.mapLookup[row[4] .. ":" .. row[5]]
      if destMap then
        -- romIndex is this entry's 1-based position in the ROM's own
        -- def_warp_events order -- NOT necessarily #warps+1: skipping an
        -- earlier entry (below) compacts this array, so another map's
        -- warp_event pointing at "warp N of this map" by ROM order would
        -- silently resolve to the wrong (or a missing) entry once N no
        -- longer matches this array's own position. Warp.lua's resolve()
        -- matches on romIndex first for exactly this reason.
        warps[#warps + 1] = {
          x = row[1], y = row[2], destWarp = row[3], destMap = destMap,
          romIndex = romIndex,
        }
      else
        -- A warp into a map this slice doesn't extract yet (e.g. Route
        -- 29's gate to Route 46) -- skip it rather than failing the whole
        -- import; the tile just sits inert until that destination map is
        -- registered too. Not asserted: unlike a dimension/count mismatch,
        -- this is an expected, incremental-coverage gap, not a sign the
        -- ROM read something wrong.
        local skipped = self.skippedWarps[mapId] or {}
        self.skippedWarps[mapId] = skipped
        local key = ("%d:%d"):format(row[4], row[5])
        skipped[key] = (skipped[key] or 0) + 1
      end
      addr = addr + 5
    end
    assert(warpCount == expected.warpCount, mapId .. " warp count mismatch")

    local coordCount = self.rom:byte(eventsBank, addr)
    addr = addr + 1 + coordCount * 8
    assert(coordCount == expected.coordEventCount, mapId .. " coord event count mismatch")

    local bgCount = self.rom:byte(eventsBank, addr)
    addr = addr + 1 + bgCount * 5
    assert(bgCount == expected.bgEventCount, mapId .. " bg event count mismatch")

    local objectCount = self.rom:byte(eventsBank, addr)
    addr = addr + 1 + objectCount * 13
    assert(objectCount == expected.objectCount, mapId .. " object count mismatch")

    local signs = expected.signs or {}
    local objects = expected.objects or {}

    out[mapId] = {
      id = mapId, label = expected.label,
      index = expected.group * 100 + expected.number,
      source = ("ROM:%02X:%04X"):format(header.bank, header.address),
      tileset = expected.tileset,
      width = width, height = height, blocks = blocks,
      borderBlock = border, connections = expected.connections or {},
      warps = warps, signs = signs, objects = objects,
      outdoor = mapId == "NEW_BARK_TOWN",
    }
    index = index + 1
    self:tick("Crystal start maps", index, total)
  end
  self:write("maps", out)
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
  self:save(love.image.newImageData("roms/pokecrystal/gfx/font/font_battle_extra.png"),
    "battle/font_battle_extra.png")
  self:save(love.image.newImageData("roms/pokecrystal/gfx/battle/enemy_hp_bar_border.png"),
    "battle/battle_hud_1.png")
  self:save(love.image.newImageData("roms/pokecrystal/gfx/battle/hp_exp_bar_border.png"),
    "battle/battle_hud_2.png")
  self:save(love.image.newImageData("roms/pokecrystal/gfx/battle/hp_exp_bar_border.png"),
    "battle/battle_hud_3.png")
  self:save(love.image.newImageData("roms/pokecrystal/gfx/battle/balls.png"),
    "battle/balls.png")
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
  for tilesetId, groups in pairs(data.tileGroups or {}) do
    if type(groups) == "table" then
      tileGroups[tilesetId] = {}
      for tileId, group in pairs(groups) do
        tileGroups[tilesetId][tonumber(tileId)] = group
      end
    else
      -- Back-compat with the older one-tileset Crystal cache shape.
      tileGroups[tonumber(tilesetId)] = groups
    end
  end
  local hpBar = parseRgbPalFile("roms/pokecrystal/gfx/battle/hp_bar.pal")
  local expBar = parseRgbPalFile("roms/pokecrystal/gfx/battle/exp_bar.pal")
  local out = {
    tileGroups = tileGroups,
    byTime = data.byTime,
    battle = {
      GREENBAR = { hpBar[1], hpBar[2] },
      YELLOWBAR = { hpBar[3], hpBar[4] },
      REDBAR = { hpBar[5], hpBar[6] },
      EXPBAR = { expBar[1], expBar[2] },
    },
  }
  self:write("palettes", out)
  return out
end

local function extractCrystalSong(self, title, channels)
  self:beginStage(title)
  local compiled = {}
  for _, ch in ipairs(channels) do
    local sym = self:symbol(ch.symbol)
    local mainSize = math.max(ch.size or 0, 2048)
    local spec = {
      hw = ch.hw,
      baseAddress = sym.address,
      bytes = self.rom:bytes(sym.bank, sym.address, mainSize),
    }
    if ch.labels then
      local labels = {}
      for _, labelName in ipairs(ch.labels) do
        local label = self:symbol(labelName)
        labels[label.address] = labelName:match("%.([^.]+)$") or labelName
      end
      spec.labels = labels
    end
    if ch.subroutines then
      spec.subroutines = {}
      spec.labels = spec.labels or {}
      local subSize = math.max(ch.subSize or 0, 256)
      for _, subName in ipairs(ch.subroutines) do
        local sub = self:symbol(subName)
        local short = subName:match("%.([^.]+)$") or subName
        spec.subroutines[short] = {
          baseAddress = sub.address,
          bytes = self.rom:bytes(sub.bank, sub.address, subSize),
        }
        spec.labels[sub.address] = short
      end
    end
    compiled[#compiled + 1] = spec
  end
  local song = CrystalMusicTranscoder.buildSong(compiled)
  self:tick(title, 1, 1)
  return song
end

local function decodeCrystalSegment(self, spec, isSfx)
  local sym = self:symbol(spec.symbol)
  local labels = {}
  for _, labelName in ipairs(spec.labels or {}) do
    local label = self:symbol(labelName)
    labels[label.address] = labelName:match("%.([^.]+)$") or labelName
  end
  return CrystalMusicTranscoder.decodeChannel(
    self.rom:bytes(sym.bank, sym.address, spec.size),
    spec.hw, sym.address, labels, isSfx)
end

local function concatEvents(...)
  local out = {}
  for i = 1, select("#", ...) do
    local events = select(i, ...)
    for _, event in ipairs(events or {}) do
      out[#out + 1] = event
    end
  end
  return out
end

local function extractCrystalWildNightSong(self)
  self:beginStage("Johto wild battle night music")

  local ch1Prelude = decodeCrystalSegment(self, {
    hw = 1, symbol = "Music_JohtoWildBattleNight_Ch1", size = 64,
    labels = { "Music_JohtoWildBattle_Ch1.body" },
  })
  local ch1Body = decodeCrystalSegment(self, {
    hw = 1, symbol = "Music_JohtoWildBattle_Ch1.body", size = 512,
    labels = { "Music_JohtoWildBattle_Ch1.body", "Music_JohtoWildBattle_Ch1.mainloop" },
  })

  local ch2Prelude = decodeCrystalSegment(self, {
    hw = 2, symbol = "Music_JohtoWildBattleNight_Ch2", size = 96,
    labels = { "Music_JohtoWildBattle_Ch2.body", "Music_JohtoWildBattle_Ch2.sub1" },
  })
  local ch2Body = decodeCrystalSegment(self, {
    hw = 2, symbol = "Music_JohtoWildBattle_Ch2.body", size = 512,
    labels = { "Music_JohtoWildBattle_Ch2.body", "Music_JohtoWildBattle_Ch2.mainloop" },
  })
  local ch2Sub1 = decodeCrystalSegment(self, {
    hw = 2, symbol = "Music_JohtoWildBattle_Ch2.sub1", size = 96,
    labels = { "Music_JohtoWildBattle_Ch2.sub1" },
  })

  local ch3Prelude = decodeCrystalSegment(self, {
    hw = 3, symbol = "Music_JohtoWildBattleNight_Ch3", size = 64,
    labels = { "Music_JohtoWildBattle_Ch3.body" },
  })
  local ch3Body = decodeCrystalSegment(self, {
    hw = 3, symbol = "Music_JohtoWildBattle_Ch3.body", size = 512,
    labels = {
      "Music_JohtoWildBattle_Ch3.body", "Music_JohtoWildBattle_Ch3.loop1",
      "Music_JohtoWildBattle_Ch3.loop2", "Music_JohtoWildBattle_Ch3.mainloop",
      "Music_JohtoWildBattle_Ch3.loop3", "Music_JohtoWildBattle_Ch3.loop4",
      "Music_JohtoWildBattle_Ch3.loop5", "Music_JohtoWildBattle_Ch3.loop6",
      "Music_JohtoWildBattle_Ch3.loop7", "Music_JohtoWildBattle_Ch3.loop8",
      "Music_JohtoWildBattle_Ch3.loop9", "Music_JohtoWildBattle_Ch3.loop10",
      "Music_JohtoWildBattle_Ch3.sub1", "Music_JohtoWildBattle_Ch3.sub1loop1",
    },
  })
  local ch3Sub1 = decodeCrystalSegment(self, {
    hw = 3, symbol = "Music_JohtoWildBattle_Ch3.sub1", size = 48,
    labels = {
      "Music_JohtoWildBattle_Ch3.sub1", "Music_JohtoWildBattle_Ch3.sub1loop1",
    },
  })

  local song = ChipAsm.song({
    channels = {
      { hw = 1, program = concatEvents(ch1Prelude, ch1Body) },
      {
        hw = 2,
        program = concatEvents(ch2Prelude, ch2Body),
        subroutines = { sub1 = ch2Sub1 },
      },
      {
        hw = 3,
        program = concatEvents(ch3Prelude, ch3Body),
        subroutines = { sub1 = ch3Sub1 },
      },
    },
  })
  self:tick("Johto wild battle night music", 1, 1)
  return song
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
  -- Crystal's OakText3 is only a prompt/control beat between OakText2 and
  -- OakText4, not player-visible copy. Older manifests do not carry the
  -- symbol, so do not require it just to import the intro text set.
  local oakText3 = self.symbols and rawget(self.symbols, "_OakText3")
  if oakText3 then
    out._OakText3 = self:decodeTextCommands(self:symbol("_OakText3"))
  end
  self:write("text", out)
  return out
end

function RomExtractorGen2:extractField(title)
  local spawn = assert(self.manifest.spawn, "Crystal spawn data missing from manifest")
  local out = {
    title = title,
    boot = {
      startMap = spawn.map, startX = spawn.x, startY = spawn.y,
      startFacing = "down",
      -- skip the Oak-speech-equivalent starter-selection screen (out of
      -- scope, no species data extracted); splash/title stay on the
      -- BOOT_DEFAULTS fallback (Game.lua's bootScreens(self).X or
      -- <default> reads), confirmed to need no Crystal-specific data.
      screens = { newGame = "CrystalIntro" },
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
    -- Sprites.playerPath (src/pokemon/Sprites.lua) reads field.playerPics
    -- .back for the battle back pic (BattleState.lua:1435, unguarded on the
    -- very first wild encounter) -- FieldDefaults.FIELD's default there is
    -- Gen1's "assets/generated/battle/redb.png", which extractSprite
    -- (above) never writes into Crystal's cache, so it crashed getImage
    -- the moment a wild battle actually started (grass encounters were
    -- unreachable before the grassTile fix, so nothing hit this path
    -- until now). backAlt is this project's own addition (see
    -- Sprites.playerPath's gender check), the same "Alt" naming
    -- playerSprites.walkAlt above already established for Kris.
    playerPics = {
      back = "assets/generated/battle/chris_back.png",
      backAlt = "assets/generated/battle/kris_back.png",
    },
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

function RomExtractorGen2:stampWarpTiles(tilesets, maps)
  local perTileset = {}
  for mapId, mapDef in pairs(maps) do
    local bucket = perTileset[mapDef.tileset] or {}
    perTileset[mapDef.tileset] = bucket
    local tileset = assert(tilesets[mapDef.tileset],
      "missing tileset for " .. tostring(mapId))
    for _, warp in ipairs(mapDef.warps or {}) do
      local tileId = mapCellTile(mapDef, tileset, warp.x, warp.y)
      if tileId ~= nil then bucket[tileId] = true end
    end
  end
  for tilesetId, tileSet in pairs(perTileset) do
    local list = {}
    for tileId in pairs(tileSet) do list[#list + 1] = tileId end
    table.sort(list)
    tilesets[tilesetId].warpTiles = list
  end
  self:write("tilesets", tilesets)
end

-- Wooper's cry: Cry_Wooper_Ch5/_Ch6/_Ch8's three real channel programs
-- (ROM bank $3c) translated from Crystal's opcode dialect into Gen1's via
-- CrystalCryTranscoder, then assembled into a self-contained chip blob by
-- src/audio/ChipAsm.lua -- the same pseudo-bank-0 mechanism mod-authored
-- ChipAsm songs/sfx already use, so no ROM bank dump or wave-sample table
-- is needed (Engine.new only reads WaveSamples when a header lacks a
-- `chip` field; ours always has one). See
-- docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md.
function RomExtractorGen2:extractCry()
  self:beginStage("Wooper cry")
  local ch5 = self:symbol("Cry_Wooper_Ch5")
  local ch6 = self:symbol("Cry_Wooper_Ch6")
  local ch8 = self:symbol("Cry_Wooper_Ch8")
  local cry = CrystalCryTranscoder.buildCry({
    { hw = 1, bytes = self.rom:bytes(ch5.bank, ch5.address, 40) },
    { hw = 2, bytes = self.rom:bytes(ch6.bank, ch6.address, 40) },
    { hw = 4, bytes = self.rom:bytes(ch8.bank, ch8.address, 20) },
  })
  -- These feed into Gen1-engine conventions elsewhere (ChipSynth.lua's
  -- bit.band(register + frequencyOffset, 0x7FF) and frameTicks = 0x80 +
  -- cryLength), which were designed around Gen1's own byte-range
  -- semantics, not Crystal's. Wooper's values (147/175) happen to land in
  -- range and were confirmed correct by a human listening to the real
  -- rendered output -- this cross-engine scaling is verified for Wooper
  -- specifically, not structurally guaranteed for any future species. A
  -- future species with very different pitch/length values should
  -- re-verify by ear, not assume the scaling holds.
  cry.pitch = self.manifest.cryPitch
  cry.length = self.manifest.cryLength
  local audio = { cries = { WOOPER = cry } }
  self:tick("Wooper cry", 1, 1)
  return audio
end

-- Title screen art (engine/movie/title.asm): the Pokemon logo (with
-- "CRYSTAL VERSION" baked into its own pixels -- Crystal has no separate
-- ribbon asset, unlike Red/Blue/Yellow), the running-Suicune tile sheet,
-- the falling crystal ornament, and the title's 16 GBC palettes (8 BG + 8
-- OBJ). See docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md.
function RomExtractorGen2:extractTitle()
  self:beginStage("Title screen")

  local suicune = self:symbol("TitleSuicuneGFX")
  local suicuneRaw = Lz3.decompress(self.rom:bytes(suicune.bank, suicune.address, 0x1000))
  local suicuneImage = ImageWriter.decode2bpp(suicuneRaw, 128, 128)
  self:save(suicuneImage, "title/suicune.png")
  self:tick("Title screen", 1, 4)

  local logo = self:symbol("TitleLogoGFX")
  local logoRaw = Lz3.decompress(self.rom:bytes(logo.bank, logo.address, 0x1000))
  -- The real compressed data only encodes 156 of the logo's 160 tiles (20x8):
  -- the bottom-right 4 tiles are genuinely blank background, and the
  -- compressor never bothered emitting trailing all-zero tiles. On real
  -- hardware VRAM is cleared before Decompress runs, so those tile slots
  -- read back as zero, i.e. shade 0 / white -- matching the real logo's
  -- blank corner there. Pad to the full 160-tile rectangle the same way.
  local logoExpectedLength = 160 * 64 * 2 / 8
  for index = #logoRaw + 1, logoExpectedLength do logoRaw[index] = 0 end
  -- Real hardware draws the crystal ornament as an OAM sprite with the
  -- BG-priority bit set (title.asm InitializeBackground: `ld a, 0 |
  -- OAM_PRIO`), which means the sprite is hidden behind the background's
  -- ink (color 1-3) but shows through the background's blank/color-0
  -- pixels. Decoding the logo with transparent=true makes its shade-0
  -- pixels alpha=0, reproducing that "see-through" blank-area behavior so
  -- the crystal drawn behind it (TitleState's crystalLayout branch) peeks
  -- through the gaps instead of being fully hidden by an opaque logo.
  local logoImage = ImageWriter.decode2bpp(logoRaw, 160, 64, true)
  self:save(logoImage, "title/logo.png")
  self:tick("Title screen", 2, 4)

  local crystalGfx = self:symbol("TitleCrystalGFX")
  local crystalRaw = Lz3.decompress(self.rom:bytes(crystalGfx.bank, crystalGfx.address, 0x1000))
  -- gfx/title/crystal.2bpp is built with pokecrystal's own `tools/gfx
  -- --interleave` (Makefile: "gfx/title/crystal.2bpp: tools/gfx +=
  -- --interleave --png=$<") -- unlike the logo/Suicune sheets, which are
  -- plain raster tile order. --interleave (tools/gfx.c's interleave())
  -- pairs up consecutive tile-ROWS and alternates their tiles
  -- column-by-column: stream position t's source (row, col) is
  -- row = 2*floor(t/12) + (t%12 odd and 1 or 0), col = (t%12) // 2 for a
  -- 48px-wide (6-tile) image. Confirmed against the real decompressed
  -- bytes (byte-for-byte identical to the pret/pokecrystal checkout's own
  -- pre-interleave gfx/title/crystal.2bpp build artifact) and against
  -- tools/gfx.c's interleave() transform directly: without undoing this,
  -- ImageWriter.decode2bpp's plain-raster assumption renders a scrambled
  -- checkerboard instead of the crystal shard.
  local function deinterleaveTiles(raw, widthTiles)
    local out = {}
    local numTiles = #raw / 16
    local pairWidth = widthTiles * 2
    for t = 0, numTiles - 1 do
      local pair = math.floor(t / pairWidth)
      local rem = t % pairWidth
      local row, col
      if rem % 2 == 0 then
        row, col = pair * 2, rem / 2
      else
        row, col = pair * 2 + 1, (rem - 1) / 2
      end
      local destTile = row * widthTiles + col
      for byteIndex = 1, 16 do
        out[destTile * 16 + byteIndex] = raw[t * 16 + byteIndex]
      end
    end
    return out
  end
  crystalRaw = deinterleaveTiles(crystalRaw, 48 / 8)
  local crystalImage = ImageWriter.decode2bpp(crystalRaw, 48, 80)
  self:save(crystalImage, "title/crystal.png")
  self:tick("Title screen", 3, 4)

  -- 16 GBC palettes (8 BG, 8 OBJ), 4 colors each, RGB555 packed 2
  -- bytes/color -- same layout and scale5 conversion RomExtractor.lua's
  -- extractPalettes already uses for Gen1's SuperPalettes/CGBBasePalettes.
  local palTable = self:symbol("TitleScreenPalettes")
  local function scale5(value) return math.floor(value * 255 / 31 + 0.5) end
  local function readPalettes(startIndex, count)
    local out = {}
    for index = 0, count - 1 do
      local colors = {}
      for color = 0, 3 do
        local value = self.rom:word(palTable.bank,
          palTable.address + (startIndex + index) * 8 + color * 2)
        colors[#colors + 1] = {
          scale5(bit.band(value, 0x1F)),
          scale5(bit.band(bit.rshift(value, 5), 0x1F)),
          scale5(bit.band(bit.rshift(value, 10), 0x1F)),
        }
      end
      out[#out + 1] = colors
    end
    return out
  end
  local palette = { bg = readPalettes(0, 8), obj = readPalettes(8, 8) }
  self:tick("Title screen", 4, 4)

  local title = {
    logo = "assets/generated/title/logo.png",
    suicune = "assets/generated/title/suicune.png",
    crystalOrnament = "assets/generated/title/crystal.png",
    palette = palette,
  }
  return title
end

-- Music_TitleScreen's pulse (Ch1/Ch2), wave (Ch3), and noise (Ch4)
-- channels, translated from Crystal's bytecode dialect via
-- CrystalMusicTranscoder. Channel 3 has no sub-labels and no sound_loop
-- of its own -- pokecrystal.sym lists only Music_TitleScreen_Ch3 itself
-- (3a:7b01, no .subN/.mainloop children), and its real body
-- (roms/pokecrystal/audio/music/titlescreen.asm:580-894) plays once and
-- ends in a real sound_ret ($FF), unlike every other song this milestone
-- extracted where Ch3 loops via a .mainloop label. Generous byte-window
-- sizes (400/400/400/300 for the four main bodies, 40/40 for Ch1/Ch2's
-- one subroutine each, 20 each for Ch4's four) are comfortably larger
-- than the real verified spans (345/355/347/222 and 23/26/10/10/8/11
-- respectively) -- decodeChannel stops at sound_ret regardless of extra
-- trailing bytes in the window, same margin convention extractCry already
-- established.
function RomExtractorGen2:extractTitleMusic()
  self:beginStage("Title music")

  local ch1 = self:symbol("Music_TitleScreen_Ch1")
  local ch1Sub1 = self:symbol("Music_TitleScreen_Ch1.sub1")
  local ch1Sub1Loop1 = self:symbol("Music_TitleScreen_Ch1.sub1loop1")
  local ch1Labels = {
    [ch1Sub1.address] = "sub1",
    [ch1Sub1Loop1.address] = "sub1loop1",
  }

  local ch2 = self:symbol("Music_TitleScreen_Ch2")
  local ch2Sub1 = self:symbol("Music_TitleScreen_Ch2.sub1")
  local ch2Sub1Loop1 = self:symbol("Music_TitleScreen_Ch2.sub1loop1")
  local ch2Labels = {
    [ch2Sub1.address] = "sub1",
    [ch2Sub1Loop1.address] = "sub1loop1",
  }

  local ch3 = self:symbol("Music_TitleScreen_Ch3")

  local ch4 = self:symbol("Music_TitleScreen_Ch4")
  local ch4Loop1 = self:symbol("Music_TitleScreen_Ch4.loop1")
  local ch4Sub1 = self:symbol("Music_TitleScreen_Ch4.sub1")
  local ch4Sub2 = self:symbol("Music_TitleScreen_Ch4.sub2")
  local ch4Sub3 = self:symbol("Music_TitleScreen_Ch4.sub3")
  local ch4Sub4 = self:symbol("Music_TitleScreen_Ch4.sub4")
  local ch4Labels = {
    [ch4Loop1.address] = "loop1",
    [ch4Sub1.address] = "sub1",
    [ch4Sub2.address] = "sub2",
    [ch4Sub3.address] = "sub3",
    [ch4Sub4.address] = "sub4",
  }

  local song = CrystalMusicTranscoder.buildSong({
    {
      hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 400),
      subroutines = {
        sub1 = { baseAddress = ch1Sub1.address,
                 bytes = self.rom:bytes(ch1Sub1.bank, ch1Sub1.address, 40) },
      },
      labels = ch1Labels,
    },
    {
      hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 400),
      subroutines = {
        sub1 = { baseAddress = ch2Sub1.address,
                 bytes = self.rom:bytes(ch2Sub1.bank, ch2Sub1.address, 40) },
      },
      labels = ch2Labels,
    },
    {
      hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 400),
    },
    {
      hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch4Sub1.address,
                 bytes = self.rom:bytes(ch4Sub1.bank, ch4Sub1.address, 20) },
        sub2 = { baseAddress = ch4Sub2.address,
                 bytes = self.rom:bytes(ch4Sub2.bank, ch4Sub2.address, 20) },
        sub3 = { baseAddress = ch4Sub3.address,
                 bytes = self.rom:bytes(ch4Sub3.bank, ch4Sub3.address, 20) },
        sub4 = { baseAddress = ch4Sub4.address,
                 bytes = self.rom:bytes(ch4Sub4.bank, ch4Sub4.address, 20) },
      },
      labels = ch4Labels,
    },
  })

  self:tick("Title music", 1, 1)
  return song
end

-- Music_ElmsLab's four channels, all shaped identically to
-- Music_TitleScreen's own extraction: read a generous byte window per
-- channel (decodeChannel stops at sound_ret regardless of extra trailing
-- bytes), no subroutines on any channel (per pokecrystal.sym: every
-- channel here has only its own .mainloop, no .subN labels -- see the
-- plan's "Research already done" section).
function RomExtractorGen2:extractElmsLabMusic()
  self:beginStage("Elm's Lab music")

  local ch1 = self:symbol("Music_ElmsLab_Ch1")
  local ch1Loop = self:symbol("Music_ElmsLab_Ch1.mainloop")
  local ch2 = self:symbol("Music_ElmsLab_Ch2")
  local ch2Loop = self:symbol("Music_ElmsLab_Ch2.mainloop")
  local ch3 = self:symbol("Music_ElmsLab_Ch3")
  local ch3Loop = self:symbol("Music_ElmsLab_Ch3.mainloop")
  local ch4 = self:symbol("Music_ElmsLab_Ch4")
  local ch4Loop = self:symbol("Music_ElmsLab_Ch4.mainloop")

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      labels = { [ch1Loop.address] = "mainloop" } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      labels = { [ch2Loop.address] = "mainloop" } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
    { hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      labels = { [ch4Loop.address] = "mainloop" } },
  })

  self:tick("Elm's Lab music", 1, 1)
  return song
end

-- Music_CherrygroveCity: same shape as Music_ElmsLab -- four channels,
-- each with only its own .mainloop, no sub-labels (pokecrystal.sym).
function RomExtractorGen2:extractCherrygroveCityMusic()
  self:beginStage("Cherrygrove City music")

  local ch1 = self:symbol("Music_CherrygroveCity_Ch1")
  local ch1Loop = self:symbol("Music_CherrygroveCity_Ch1.mainloop")
  local ch2 = self:symbol("Music_CherrygroveCity_Ch2")
  local ch2Loop = self:symbol("Music_CherrygroveCity_Ch2.mainloop")
  local ch3 = self:symbol("Music_CherrygroveCity_Ch3")
  local ch3Loop = self:symbol("Music_CherrygroveCity_Ch3.mainloop")
  local ch4 = self:symbol("Music_CherrygroveCity_Ch4")
  local ch4Loop = self:symbol("Music_CherrygroveCity_Ch4.mainloop")

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      labels = { [ch1Loop.address] = "mainloop" } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      labels = { [ch2Loop.address] = "mainloop" } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
    { hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      labels = { [ch4Loop.address] = "mainloop" } },
  })

  self:tick("Cherrygrove City music", 1, 1)
  return song
end

-- Music_Route29: Ch1/Ch3/Ch4 are .mainloop-only; Ch2 has one extra
-- .sub1 (pokecrystal.sym) -- a flat, top-level sound_call/sound_loop
-- target, not nested inside another subroutine's own window.
function RomExtractorGen2:extractRoute29Music()
  self:beginStage("Route 29 music")

  local ch1 = self:symbol("Music_Route29_Ch1")
  local ch1Loop = self:symbol("Music_Route29_Ch1.mainloop")
  local ch2 = self:symbol("Music_Route29_Ch2")
  local ch2Loop = self:symbol("Music_Route29_Ch2.mainloop")
  local ch2Sub1 = self:symbol("Music_Route29_Ch2.sub1")
  local ch3 = self:symbol("Music_Route29_Ch3")
  local ch3Loop = self:symbol("Music_Route29_Ch3.mainloop")
  local ch4 = self:symbol("Music_Route29_Ch4")
  local ch4Loop = self:symbol("Music_Route29_Ch4.mainloop")

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      labels = { [ch1Loop.address] = "mainloop" } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch2Sub1.address,
                 bytes = self.rom:bytes(ch2Sub1.bank, ch2Sub1.address, 60) },
      },
      labels = { [ch2Loop.address] = "mainloop", [ch2Sub1.address] = "sub1" } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
    { hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      labels = { [ch4Loop.address] = "mainloop" } },
  })

  self:tick("Route 29 music", 1, 1)
  return song
end

-- Music_NewBarkTown: Ch1 and Ch2 each have two extra subroutines
-- (.sub1, .sub2); Ch3 is .mainloop-only. This song has NO Channel 4 --
-- confirmed by the absence of Music_NewBarkTown_Ch4 in pokecrystal.sym,
-- not an omission (buildSong accepts any number of channels).
function RomExtractorGen2:extractNewBarkTownMusic()
  self:beginStage("New Bark Town music")

  local ch1 = self:symbol("Music_NewBarkTown_Ch1")
  local ch1Loop = self:symbol("Music_NewBarkTown_Ch1.mainloop")
  local ch1Sub1 = self:symbol("Music_NewBarkTown_Ch1.sub1")
  local ch1Sub2 = self:symbol("Music_NewBarkTown_Ch1.sub2")
  local ch2 = self:symbol("Music_NewBarkTown_Ch2")
  local ch2Loop = self:symbol("Music_NewBarkTown_Ch2.mainloop")
  local ch2Sub1 = self:symbol("Music_NewBarkTown_Ch2.sub1")
  local ch2Sub2 = self:symbol("Music_NewBarkTown_Ch2.sub2")
  local ch3 = self:symbol("Music_NewBarkTown_Ch3")
  local ch3Loop = self:symbol("Music_NewBarkTown_Ch3.mainloop")

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch1Sub1.address,
                 bytes = self.rom:bytes(ch1Sub1.bank, ch1Sub1.address, 60) },
        sub2 = { baseAddress = ch1Sub2.address,
                 bytes = self.rom:bytes(ch1Sub2.bank, ch1Sub2.address, 60) },
      },
      labels = {
        [ch1Loop.address] = "mainloop",
        [ch1Sub1.address] = "sub1", [ch1Sub2.address] = "sub2",
      } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch2Sub1.address,
                 bytes = self.rom:bytes(ch2Sub1.bank, ch2Sub1.address, 60) },
        sub2 = { baseAddress = ch2Sub2.address,
                 bytes = self.rom:bytes(ch2Sub2.bank, ch2Sub2.address, 60) },
      },
      labels = {
        [ch2Loop.address] = "mainloop",
        [ch2Sub1.address] = "sub1", [ch2Sub2.address] = "sub2",
      } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
  })

  self:tick("New Bark Town music", 1, 1)
  return song
end

function RomExtractorGen2:extractRoute30Music()
  self:beginStage("Route 30 music")

  local ch1 = self:symbol("Music_Route30_Ch1")
  local ch1Loop = self:symbol("Music_Route30_Ch1.mainloop")
  local ch2 = self:symbol("Music_Route30_Ch2")
  local ch2Loop = self:symbol("Music_Route30_Ch2.mainloop")
  local ch3 = self:symbol("Music_Route30_Ch3")
  local ch3Loop = self:symbol("Music_Route30_Ch3.mainloop")
  local ch4 = self:symbol("Music_Route30_Ch4")
  local ch4Loop = self:symbol("Music_Route30_Ch4.mainloop")
  local ch4Sub1 = self:symbol("Music_Route30_Ch4.sub1")
  local ch4Sub2 = self:symbol("Music_Route30_Ch4.sub2")
  local ch4Sub3 = self:symbol("Music_Route30_Ch4.sub3")
  local ch4Sub4 = self:symbol("Music_Route30_Ch4.sub4")
  local ch4Sub5 = self:symbol("Music_Route30_Ch4.sub5")
  local ch4Labels = {
    [ch4Loop.address] = "mainloop",
    [ch4Sub1.address] = "sub1", [ch4Sub2.address] = "sub2",
    [ch4Sub3.address] = "sub3", [ch4Sub4.address] = "sub4",
    [ch4Sub5.address] = "sub5",
  }

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      labels = { [ch1Loop.address] = "mainloop" } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      labels = { [ch2Loop.address] = "mainloop" } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
    { hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch4Sub1.address,
                 bytes = self.rom:bytes(ch4Sub1.bank, ch4Sub1.address, 30) },
        sub2 = { baseAddress = ch4Sub2.address,
                 bytes = self.rom:bytes(ch4Sub2.bank, ch4Sub2.address, 30) },
        sub3 = { baseAddress = ch4Sub3.address,
                 bytes = self.rom:bytes(ch4Sub3.bank, ch4Sub3.address, 30) },
        sub4 = { baseAddress = ch4Sub4.address,
                 bytes = self.rom:bytes(ch4Sub4.bank, ch4Sub4.address, 30) },
        sub5 = { baseAddress = ch4Sub5.address,
                 bytes = self.rom:bytes(ch4Sub5.bank, ch4Sub5.address, 30) },
      },
      labels = ch4Labels },
  })

  self:tick("Route 30 music", 1, 1)
  return song
end

function RomExtractorGen2:extractBattleMusic()
  return {
    wild = extractCrystalSong(self, "Johto wild battle music", {
      { hw = 1, symbol = "Music_JohtoWildBattle_Ch1", size = 320,
        labels = { "Music_JohtoWildBattle_Ch1.body", "Music_JohtoWildBattle_Ch1.mainloop" } },
      { hw = 2, symbol = "Music_JohtoWildBattle_Ch2", size = 320,
        labels = { "Music_JohtoWildBattle_Ch2.body", "Music_JohtoWildBattle_Ch2.mainloop" },
        subroutines = { "Music_JohtoWildBattle_Ch2.sub1" }, subSize = 80 },
      { hw = 3, symbol = "Music_JohtoWildBattle_Ch3", size = 320,
        labels = {
          "Music_JohtoWildBattle_Ch3.body", "Music_JohtoWildBattle_Ch3.loop1",
          "Music_JohtoWildBattle_Ch3.loop2", "Music_JohtoWildBattle_Ch3.mainloop",
          "Music_JohtoWildBattle_Ch3.loop3", "Music_JohtoWildBattle_Ch3.loop4",
          "Music_JohtoWildBattle_Ch3.loop5", "Music_JohtoWildBattle_Ch3.loop6",
          "Music_JohtoWildBattle_Ch3.loop7", "Music_JohtoWildBattle_Ch3.loop8",
          "Music_JohtoWildBattle_Ch3.loop9", "Music_JohtoWildBattle_Ch3.loop10",
        },
        subroutines = { "Music_JohtoWildBattle_Ch3.sub1", "Music_JohtoWildBattle_Ch3.sub1loop1" },
        subSize = 48 },
    }),
    wildNight = extractCrystalWildNightSong(self),
    trainer = extractCrystalSong(self, "Johto trainer battle music", {
      { hw = 1, symbol = "Music_JohtoTrainerBattle_Ch1", size = 520,
        labels = { "Music_JohtoTrainerBattle_Ch1.mainloop", "Music_JohtoTrainerBattle_Ch1.loop1" },
        subroutines = { "Music_JohtoTrainerBattle_Ch1.sub1" }, subSize = 96 },
      { hw = 2, symbol = "Music_JohtoTrainerBattle_Ch2", size = 560,
        labels = {
          "Music_JohtoTrainerBattle_Ch2.mainloop", "Music_JohtoTrainerBattle_Ch2.loop1",
          "Music_JohtoTrainerBattle_Ch2.loop2", "Music_JohtoTrainerBattle_Ch2.loop3",
        },
        subroutines = {
          "Music_JohtoTrainerBattle_Ch2.sub1", "Music_JohtoTrainerBattle_Ch2.sub2",
          "Music_JohtoTrainerBattle_Ch2.sub3", "Music_JohtoTrainerBattle_Ch2.sub4",
          "Music_JohtoTrainerBattle_Ch2.sub5",
        }, subSize = 96 },
      { hw = 3, symbol = "Music_JohtoTrainerBattle_Ch3", size = 720,
        labels = {
          "Music_JohtoTrainerBattle_Ch3.loop1", "Music_JohtoTrainerBattle_Ch3.mainloop",
          "Music_JohtoTrainerBattle_Ch3.loop2", "Music_JohtoTrainerBattle_Ch3.loop3",
          "Music_JohtoTrainerBattle_Ch3.loop4", "Music_JohtoTrainerBattle_Ch3.loop5",
          "Music_JohtoTrainerBattle_Ch3.loop6", "Music_JohtoTrainerBattle_Ch3.loop7",
          "Music_JohtoTrainerBattle_Ch3.loop8", "Music_JohtoTrainerBattle_Ch3.loop9",
          "Music_JohtoTrainerBattle_Ch3.loop10", "Music_JohtoTrainerBattle_Ch3.loop11",
        },
        subroutines = {
          "Music_JohtoTrainerBattle_Ch3.sub1", "Music_JohtoTrainerBattle_Ch3.sub2",
          "Music_JohtoTrainerBattle_Ch3.sub3", "Music_JohtoTrainerBattle_Ch3.sub4",
          "Music_JohtoTrainerBattle_Ch3.sub4loop1", "Music_JohtoTrainerBattle_Ch3.sub5",
          "Music_JohtoTrainerBattle_Ch3.sub5loop1", "Music_JohtoTrainerBattle_Ch3.sub6",
          "Music_JohtoTrainerBattle_Ch3.sub6loop1", "Music_JohtoTrainerBattle_Ch3.sub7",
        }, subSize = 80 },
    }),
    gym = extractCrystalSong(self, "Johto gym battle music", {
      { hw = 1, symbol = "Music_JohtoGymBattle_Ch1", size = 400,
        labels = { "Music_JohtoGymBattle_Ch1.loop1", "Music_JohtoGymBattle_Ch1.loop2", "Music_JohtoGymBattle_Ch1.mainloop" } },
      { hw = 2, symbol = "Music_JohtoGymBattle_Ch2", size = 400,
        labels = { "Music_JohtoGymBattle_Ch2.loop1", "Music_JohtoGymBattle_Ch2.loop2", "Music_JohtoGymBattle_Ch2.mainloop" } },
      { hw = 3, symbol = "Music_JohtoGymBattle_Ch3", size = 520,
        labels = { "Music_JohtoGymBattle_Ch3.mainloop" },
        subroutines = {
          "Music_JohtoGymBattle_Ch3.sub1", "Music_JohtoGymBattle_Ch3.sub2",
          "Music_JohtoGymBattle_Ch3.sub2loop1", "Music_JohtoGymBattle_Ch3.sub3",
          "Music_JohtoGymBattle_Ch3.sub3loop1", "Music_JohtoGymBattle_Ch3.sub4",
          "Music_JohtoGymBattle_Ch3.sub4loop1", "Music_JohtoGymBattle_Ch3.sub5",
          "Music_JohtoGymBattle_Ch3.sub6", "Music_JohtoGymBattle_Ch3.sub7",
          "Music_JohtoGymBattle_Ch3.sub8", "Music_JohtoGymBattle_Ch3.sub9",
          "Music_JohtoGymBattle_Ch3.sub9loop1", "Music_JohtoGymBattle_Ch3.sub10",
          "Music_JohtoGymBattle_Ch3.sub10loop1", "Music_JohtoGymBattle_Ch3.sub11",
        }, subSize = 48 },
    }),
    final = extractCrystalSong(self, "Champion battle music", {
      { hw = 1, symbol = "Music_ChampionBattle_Ch1", size = 520,
        labels = {
          "Music_ChampionBattle_Ch1.loop1", "Music_ChampionBattle_Ch1.loop2",
          "Music_ChampionBattle_Ch1.loop3", "Music_ChampionBattle_Ch1.mainloop",
          "Music_ChampionBattle_Ch1.loop4", "Music_ChampionBattle_Ch1.loop5",
          "Music_ChampionBattle_Ch1.loop6",
        },
        subroutines = {
          "Music_ChampionBattle_Ch1.sub1", "Music_ChampionBattle_Ch1.sub2",
          "Music_ChampionBattle_Ch1.sub3", "Music_ChampionBattle_Ch1.sub4",
          "Music_ChampionBattle_Ch1.sub5", "Music_ChampionBattle_Ch1.sub6",
        }, subSize = 80 },
      { hw = 2, symbol = "Music_ChampionBattle_Ch2", size = 400,
        labels = { "Music_ChampionBattle_Ch2.mainloop", "Music_ChampionBattle_Ch2.loop1" },
        subroutines = {
          "Music_ChampionBattle_Ch2.sub1", "Music_ChampionBattle_Ch2.sub2",
          "Music_ChampionBattle_Ch2.sub3",
        }, subSize = 80 },
      { hw = 3, symbol = "Music_ChampionBattle_Ch3", size = 520,
        labels = {
          "Music_ChampionBattle_Ch3.loop1", "Music_ChampionBattle_Ch3.loop2",
          "Music_ChampionBattle_Ch3.mainloop", "Music_ChampionBattle_Ch3.loop3",
          "Music_ChampionBattle_Ch3.loop4", "Music_ChampionBattle_Ch3.loop5",
          "Music_ChampionBattle_Ch3.loop6", "Music_ChampionBattle_Ch3.loop7",
          "Music_ChampionBattle_Ch3.loop8", "Music_ChampionBattle_Ch3.loop9",
          "Music_ChampionBattle_Ch3.loop10", "Music_ChampionBattle_Ch3.loop11",
          "Music_ChampionBattle_Ch3.loop12",
        },
        subroutines = {
          "Music_ChampionBattle_Ch3.sub1", "Music_ChampionBattle_Ch3.sub1loop1",
          "Music_ChampionBattle_Ch3.sub2", "Music_ChampionBattle_Ch3.sub3",
          "Music_ChampionBattle_Ch3.sub4",
        }, subSize = 64 },
    }),
    wildWin = extractCrystalSong(self, "Wild victory music", {
      { hw = 1, symbol = "Music_WildPokemonVictory_Ch1", size = 160,
        labels = { "Music_WildPokemonVictory_Ch1.body", "Music_WildPokemonVictory_Ch1.mainloop" },
        subroutines = { "Music_WildPokemonVictory_Ch1.sub1" }, subSize = 48 },
      { hw = 2, symbol = "Music_WildPokemonVictory_Ch2", size = 160,
        labels = { "Music_WildPokemonVictory_Ch2.body", "Music_WildPokemonVictory_Ch2.mainloop" },
        subroutines = { "Music_WildPokemonVictory_Ch2.sub1" }, subSize = 48 },
      { hw = 3, symbol = "Music_WildPokemonVictory_Ch3", size = 160,
        labels = { "Music_WildPokemonVictory_Ch3.body", "Music_WildPokemonVictory_Ch3.mainloop" },
        subroutines = { "Music_WildPokemonVictory_Ch3.sub1" }, subSize = 48 },
    }),
    trainerWin = extractCrystalSong(self, "Trainer victory music", {
      { hw = 1, symbol = "Music_TrainerVictory_Ch1", size = 180,
        labels = { "Music_TrainerVictory_Ch1.loop1", "Music_TrainerVictory_Ch1.mainloop",
          "Music_TrainerVictory_Ch1.loop2", "Music_TrainerVictory_Ch1.loop3" },
        subroutines = { "Music_TrainerVictory_Ch1.sub1" }, subSize = 48 },
      { hw = 2, symbol = "Music_TrainerVictory_Ch2", size = 160,
        labels = { "Music_TrainerVictory_Ch2.loop1", "Music_TrainerVictory_Ch2.mainloop" },
        subroutines = { "Music_TrainerVictory_Ch2.sub1" }, subSize = 48 },
      { hw = 3, symbol = "Music_TrainerVictory_Ch3", size = 160,
        labels = { "Music_TrainerVictory_Ch3.loop1", "Music_TrainerVictory_Ch3.mainloop" },
        subroutines = { "Music_TrainerVictory_Ch3.sub1" }, subSize = 48 },
    }),
    gymWin = extractCrystalSong(self, "Gym victory music", {
      { hw = 1, symbol = "Music_GymLeaderVictory_Ch1", size = 220,
        labels = { "Music_GymLeaderVictory_Ch1.loop1", "Music_GymLeaderVictory_Ch1.mainloop" },
        subroutines = { "Music_GymLeaderVictory_Ch1.sub1", "Music_GymLeaderVictory_Ch1.sub2" },
        subSize = 64 },
      { hw = 2, symbol = "Music_GymLeaderVictory_Ch2", size = 180,
        labels = { "Music_GymLeaderVictory_Ch2.mainloop" },
        subroutines = { "Music_GymLeaderVictory_Ch2.sub1", "Music_GymLeaderVictory_Ch2.sub2" },
        subSize = 48 },
      { hw = 3, symbol = "Music_GymLeaderVictory_Ch3", size = 220,
        labels = { "Music_GymLeaderVictory_Ch3.loop1", "Music_GymLeaderVictory_Ch3.mainloop" },
        subroutines = { "Music_GymLeaderVictory_Ch3.sub1" }, subSize = 96 },
      { hw = 4, symbol = "Music_GymLeaderVictory_Ch4", size = 120,
        labels = { "Music_GymLeaderVictory_Ch4.mainloop", "Music_GymLeaderVictory_Ch4.loop1" },
        subroutines = { "Music_GymLeaderVictory_Ch4.sub1", "Music_GymLeaderVictory_Ch4.sub1loop1" },
        subSize = 48 },
    }),
  }
end

-- The first batch of Crystal SFX: the 9 names this project's own code
-- already calls by name (Sound.play/Sound.startLoop call sites across
-- src/ and data/scripts/), mapped to their real Crystal SFX_* constants
-- -- see the plan's "Research already done" section for each mapping's
-- verification. None of these channel bodies use sound_call/sound_loop
-- (confirmed against their real bytes), so no subroutines/labels table
-- is needed -- unlike every one of Milestone 2's music songs, which all
-- loop forever.
function RomExtractorGen2:extractSfx()
  self:beginStage("Sound effects")
  local headers = parseCrystalSfxHeaders()
  local sfx = {}

  local function ch(symbolName, hw, size)
    local sym = self:symbol(symbolName)
    return { hw = hw, baseAddress = sym.address,
      bytes = self.rom:bytes(sym.bank, sym.address, size or 128) }
  end

  local function buildByHeader(headerName)
    local header = headers[headerName]
    assert(header and #header.channels > 0,
      "missing Crystal SFX header " .. tostring(headerName))
    local channels = {}
    for _, spec in ipairs(header.channels) do
      local labels = {}
      for labelName in pairs(spec.labels or {}) do
        local sym = self:symbol(labelName)
        labels[sym.address] = labelName
      end
      local subroutines
      if next(spec.subroutines or {}) then
        subroutines = {}
        for labelName in pairs(spec.subroutines) do
          local sym = self:symbol(labelName)
          subroutines[labelName] = {
            baseAddress = sym.address,
            bytes = self.rom:bytes(sym.bank, sym.address, 128),
          }
        end
      end
      local channel = ch(spec.symbol, spec.hw, 128)
      channel.labels = labels
      channel.subroutines = subroutines
      channels[#channels + 1] = channel
    end
    return CrystalMusicTranscoder.buildSfx(channels)
  end

  local function tryAdd(targetKey, headerName)
    local ok, built = pcall(buildByHeader, headerName)
    if ok and built then
      sfx[targetKey] = built
      return true
    end
    Logger.warn("Crystal SFX %s skipped: %s", tostring(targetKey), tostring(built))
    return false
  end

  for targetKey, headerName in pairs({
    Collision = "Bump",
    Cut = "Cut",
    Denied = "Wrong",
    Ball_Poof = "BallPoof",
    Ledge_Jump = "JumpOverLedge",
    Withdraw_Deposit = "Transaction",
    Go_Inside = "EnterDoor",
    Go_Outside = "ExitBuilding",
    Get_Key_Item = "KeyItem",
    Intro_Whoosh = "IntroWhoosh",
    Faint_Fall = "Faint",
    Press_AB = "PushButton",
    Tink = "SwitchPockets",
    Trade_Machine = "GiveTrademon",
    Heal_HP = "Potion",
    Get_Item2 = "Item",
    Safari_Zone_PA = "Call",
    Shooting_Star = "TitleScreenEntrance",
    Slots_New_Spin = "SlotMachineStart",
    Slots_Stop_Wheel = "StopSlot",
    Slots_Reward = "GetCoinFromSlots",
    Shrink = "WarpTo",
  }) do
    tryAdd(targetKey, headerName)
  end

  local seen = {}
  for _, move in pairs(self:parseCrystalMoves()) do
    local anim = move.anim
    local key = anim and anim.sound
    if key and not seen[key] then
      seen[key] = true
      tryAdd(key, crystalSfxHeaderName(key))
    end
  end

  self:tick("Sound effects", 1, 1)
  return sfx
end

function RomExtractorGen2:extractStubs()
  for _, name in ipairs(STUB_MODULES) do
    self:write(name, {})
  end
  -- Cache-generation marker for Crystal's expanded start-area extraction.
  self:write("crystal_start_marker_v6", { version = 6 })
end

function RomExtractorGen2:run()
  local results = {}
  results.sprites = self:extractSprite()
  results.tilesets = self:extractTileset()
  local intro = self:extractIntroPics()
  results.trainers = intro.trainers
  results.pokemon = intro.pokemon
  results.moves = intro.moves
  results.battle_anims = self:extractBattleAnimations(results.moves)
  results.type_chart = intro.typeChart
  results.items = intro.items
  results.encounters = intro.encounters
  results.maps = self:extractMap()
  self:stampWarpTiles(results.tilesets, results.maps)
  results.font = self:extractFont()
  results.palettes = self:extractPalettes()
  results.text = self:extractIntroText()
  local title = self:extractTitle()
  results.field = self:extractField(title)
  local cries = self:extractCry()
  local titleSong = self:extractTitleMusic()
  local elmsLabSong = self:extractElmsLabMusic()
  local cherrygroveCitySong = self:extractCherrygroveCityMusic()
  local route29Song = self:extractRoute29Music()
  local newBarkTownSong = self:extractNewBarkTownMusic()
  local route30Song = self:extractRoute30Music()
  local battleMusic = self:extractBattleMusic()
  local sfx = self:extractSfx()
  local mapSongs = {}
  for mapId, expected in pairs(self.manifest.maps) do
    if expected.music then mapSongs[mapId] = expected.music end
  end
  local songs = {
    Music_TitleScreen = titleSong,
    Music_ElmsLab = elmsLabSong,
    Music_CherrygroveCity = cherrygroveCitySong,
    Music_Route29 = route29Song,
    Music_NewBarkTown = newBarkTownSong,
    Music_Route30 = route30Song,
    Music_JohtoWildBattle = battleMusic.wild,
    Music_JohtoWildBattleNight = battleMusic.wildNight,
    Music_JohtoTrainerBattle = battleMusic.trainer,
    Music_JohtoGymBattle = battleMusic.gym,
    Music_ChampionBattle = battleMusic.final,
    Music_WildPokemonVictory = battleMusic.wildWin,
    Music_TrainerVictory = battleMusic.trainerWin,
    Music_GymLeaderVictory = battleMusic.gymWin,
  }
  results.audio = {
    cries = cries.cries,
    songs = songs,
    battle = {
      wild = "Music_JohtoWildBattle",
      wildNight = "Music_JohtoWildBattleNight",
      trainer = "Music_JohtoTrainerBattle",
      gym = "Music_JohtoGymBattle",
      final = "Music_ChampionBattle",
      wildWin = "Music_WildPokemonVictory",
      trainerWin = "Music_TrainerVictory",
      gymWin = "Music_GymLeaderVictory",
    },
    mapSongs = mapSongs,
    sfx = sfx,
  }
  self:write("audio", results.audio)
  self:extractStubs()
  for mapId, rows in pairs(self.skippedWarps) do
    local parts = {}
    for key, count in pairs(rows) do
      parts[#parts + 1] = count > 1 and (key .. " x" .. count) or key
    end
    table.sort(parts)
    Logger.info("%s: skipped warps to unregistered maps (%s)",
      mapId, table.concat(parts, ", "))
  end
  if self.progress then
    self.progress(STAGE_COUNT, STAGE_COUNT, "Ready", 1, 1)
  end
  return results
end

return RomExtractorGen2
