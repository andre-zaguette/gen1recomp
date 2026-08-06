-- Crystal's new-game intro: the boy/girl choice, Oak's narration + Wooper
-- demo, and player naming (engine/menus/intro_menu.asm's NewGame/OakSpeech/
-- InitGender). No rival naming or starter selection -- confirmed during
-- planning that both happen later, as ordinary Elm's Lab map events, not
-- part of this sequence.
--
-- Delegates to OakSpeech's shared step-runner mechanics (text/pic/reveal/
-- naming/shrink handling) via metatable inheritance rather than
-- duplicating them -- OakSpeech.lua itself is never modified, so this
-- carries zero regression risk to Gen1's own intro. Only genuinely
-- different behavior is overridden below: the step list, the "demo"
-- step's text key (Crystal's differs from Gen1's hardcoded one), and a
-- new "gender" step kind this file adds itself (OakSpeech has no such
-- step kind and doesn't need one).

local OakSpeechModule = require("src.ui.OakSpeech")
local Assets = require("src.render.Assets")
local Sprites = require("src.pokemon.Sprites")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local bit = require("bit")

local CrystalIntro = setmetatable({}, { __index = OakSpeechModule })
CrystalIntro.__index = CrystalIntro
CrystalIntro.isOpaque = true
CrystalIntro.letterboxWhite = true

local FALLBACK_TEXT = {
  _OakText1 = Strings.source("Hello! Sorry to\nkeep you waiting!\fWelcome to the\nworld of POKeMON!\fMy name is OAK.\fPeople call me the\nPOKeMON PROF."),
  _OakText2 = Strings.source("This world is in-\nhabited by crea-\ntures that we call\nPOKeMON."),
  _OakText4 = Strings.source("People and POKeMON\nlive together by\fsupporting each\nother.\fSome people play\nwith POKeMON, some\nbattle with them."),
  _OakText5 = Strings.source("But we don't know\neverything about\nPOKeMON yet.\fThere are still\nmany mysteries to\nsolve."),
  _OakText6 = Strings.source("Now, what did you\nsay your name was?"),
  _OakText7 = Strings.source("<PLAYER>, are you\nready?\fYour very own\nPOKeMON story is\nabout to unfold.\fYou'll face fun\ntimes and tough\nchallenges.\fA world of dreams\nand adventures\nwith POKeMON\nawaits! Let's go!"),
  _AreYouABoyOrAreYouAGirlText = Strings.source("Are you a boy?\nOr are you a girl?"),
}

local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

local function tryImageData(path)
  if not path or not love.image then return nil end
  local ok, data = pcall(love.image.newImageData, path)
  return ok and data or nil
end

local function imageFromData(data)
  if not data then return nil end
  local ok, img = pcall(love.graphics.newImage, data)
  return ok and img or nil
end

local function shadeIndex(r)
  if r > 0.83 then return 1 end
  if r > 0.5 then return 2 end
  if r > 0.17 then return 3 end
  return 4
end

local function fileBytes(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function decodeGbcPal(path)
  local raw = fileBytes(path)
  if not raw or #raw < 8 then return nil end
  local colors = {}
  for i = 1, 4 do
    local lo = raw:byte((i - 1) * 2 + 1)
    local hi = raw:byte((i - 1) * 2 + 2)
    local value = lo + hi * 256
    local r = bit.band(value, 0x1F)
    local g = bit.band(bit.rshift(value, 5), 0x1F)
    local b = bit.band(bit.rshift(value, 10), 0x1F)
    colors[i] = {
      math.floor(r * 255 / 31 + 0.5),
      math.floor(g * 255 / 31 + 0.5),
      math.floor(b * 255 / 31 + 0.5),
    }
  end
  return colors
end

local function colorizeImage(path, pal, alphaWhite)
  local data = tryImageData(path)
  if not (data and pal and #pal >= 4) then return tryImage(path) end
  data:mapPixel(function(_, _, r, g, b, a)
    if a == 0 then return r, g, b, a end
    local idx = shadeIndex(r)
    local c = pal[idx]
    local alpha = (alphaWhite and idx == 1) and 0 or a
    return c[1] / 255, c[2] / 255, c[3] / 255, alpha
  end)
  return imageFromData(data)
end

local function firstExisting(...)
  for i = 1, select("#", ...) do
    local path = select(i, ...)
    if path and Assets.exists(path) then return path end
  end
  return select(1, ...)
end

function CrystalIntro.defaultSteps()
  return {
    {
      id = "gender",
      kind = "gender",
      textKey = "_AreYouABoyOrAreYouAGirlText",
    },
    {
      id = "oak_welcome",
      kind = "say",
      textKey = "_OakText1",
      pic = "oak",
      reveal = "fade",
    },
    {
      id = "demo_wooper",
      kind = "demo",
      demoTextKey = "_OakText2",
    },
    {
      id = "oak_4",
      kind = "say",
      textKey = "_OakText4",
      pic = "oak",
    },
    {
      id = "oak_5",
      kind = "say",
      textKey = "_OakText5",
      pic = "oak",
    },
    {
      id = "ask_player_name",
      kind = "say",
      textKey = "_OakText6",
      pic = "player",
    },
    {
      id = "name_player",
      kind = "name",
      who = "player",
      title = Strings("YOUR NAME?"),
      presetsWho = "player",
      presetsFallback = { "CHRIS", "KRIS" },
    },
    {
      id = "ready",
      kind = "say",
      textKey = "_OakText7",
      pic = "player",
    },
    {
      id = "shrink",
      kind = "shrink",
      textKey = "_OakText7",
    },
  }
end

function CrystalIntro.new(game, onDone)
  -- Reuse OakSpeech's constructor for everything version-agnostic (pic
  -- resolution setup, name length, shrink pics, walk sheet), then
  -- override the two things Crystal's ROM data doesn't share with Gen1's:
  -- the demo species/pic (Wooper, not Nidorino/whatever oakGfx defaults
  -- to) and no rival pic at all (Crystal's intro never shows or names a
  -- rival).
  local self = OakSpeechModule.new(game, onDone)
  setmetatable(self, CrystalIntro)
  self.rivalPic = nil
  self.demoSpecies = "WOOPER"
  -- Sprites.path is the same resolver OakSpeech.new itself used two lines
  -- up (for NIDORINO) and the same one resolvePic's "pokemon" branch calls
  -- -- it reads pokemon[species].spriteFront, not .frontPic (confirmed by
  -- reading RomExtractorGen2:extractIntroPics(), which writes
  -- pokemon.WOOPER.spriteFront). Going through this helper rather than
  -- reading the field directly keeps this file agnostic to that shape.
  local demoPath, demoTrueColor = Sprites.path(
    game.data, self.demoSpecies, "front", { kind = "oak" })
  local playerPath = select(1, Sprites.playerPath(
    game.data, "front", { kind = "intro" }))
  local trainers = game.data.trainers or {}
  local walkDef = game.data.sprites and game.data.sprites.SPRITE_CHRIS or nil
  local oakPal = decodeGbcPal("roms/pokecrystal/gfx/trainers/oak.gbcpal")
  local boyPal = decodeGbcPal("roms/pokecrystal/gfx/trainers/red.gbcpal")
  local girlPal = decodeGbcPal("roms/pokecrystal/gfx/trainers/blue.gbcpal")
  local wooperPal = decodeGbcPal("roms/pokecrystal/gfx/pokemon/wooper/front.gbcpal")
  self.demoAnimating = false
  self.demoPic = colorizeImage(demoPath and Assets.resolve(demoPath),
    wooperPal, false)
  if not self.demoPic then
    local ok, img = pcall(love.graphics.newImage, Assets.resolve(demoPath or ""))
    self.demoPic = ok and img or nil
  end
  self.demoTrueColor = self.demoPic and true or demoTrueColor or false
  self.genderBg = nil
  self.oakPic = colorizeImage(firstExisting(
    "roms/pokecrystal/gfx/trainers/oak.png",
    trainers and trainers.OPP_PROF_OAK and trainers.OPP_PROF_OAK.pic), oakPal, false)
    or self.oakPic
  self.oakPicTrueColor = self.oakPic ~= nil
  self.playerBoyPic = colorizeImage(firstExisting(
    "roms/pokecrystal/gfx/player/chris.png", playerPath and Assets.resolve(playerPath)),
    boyPal, false)
    or self.playerPic
  self.playerGirlPic = colorizeImage(firstExisting(
    "roms/pokecrystal/gfx/player/kris.png"),
    girlPal, false)
    or self.playerBoyPic
  self.walkBoySheet = colorizeImage(firstExisting(
    "roms/pokecrystal/gfx/sprites/chris.png", walkDef and walkDef.image),
    boyPal, true)
    or self.walkSheet
  self.walkGirlSheet = colorizeImage(firstExisting(
    "roms/pokecrystal/gfx/sprites/kris.png"),
    girlPal, true)
    or self.walkBoySheet
  self.showGenderChoices = false
  self:setPlayerGenderArt((self.game.save.player and self.game.save.player.gender) or "boy")
  return self
end

function CrystalIntro:setPlayerGenderArt(gender)
  if gender == "girl" then
    self.playerPic = self.playerGirlPic or self.playerBoyPic or self.playerPic
    self.walkSheet = self.walkGirlSheet or self.walkBoySheet or self.walkSheet
  else
    self.playerPic = self.playerBoyPic or self.playerPic
    self.walkSheet = self.walkBoySheet or self.walkSheet
  end
  self.playerTrueColor = self.playerPic ~= nil
  self.walkTrueColor = self.walkSheet ~= nil
end

function CrystalIntro:stepText(step)
  if step.text then return step.text end
  if step.textKey then
    local text = self.game and self.game.data and self.game.data.text
    return (text and text[step.textKey]) or FALLBACK_TEXT[step.textKey] or ""
  end
  return ""
end

function CrystalIntro:buildSteps()
  local steps = CrystalIntro.defaultSteps(self)
  local Runtime = require("src.mods.Runtime")
  local Logger = require("src.core.Logger")
  local hooked = Runtime.call("intro.oak_speech.build",
    function(s) return s end, steps, self)
  if type(hooked) ~= "table" then
    Logger.error("intro.oak_speech.build returned %s; keeping Crystal steps",
                 type(hooked))
    return steps
  end
  return hooked
end

function CrystalIntro:runStep(step)
  local kind = step.kind
  if kind == "gender" then
    self.showGenderChoices = true
    self.bgImage = self.genderBg
    self.pic = nil
    self.picTrueColor = false
    self:sayText(self:stepText(step), function()
      local Menu = require("src.ui.Menu")
      -- Game.lua:onNewGame pushes OverworldState (which constructs
      -- game.overworld.player from whatever save.player.gender held at
      -- that moment -- unset, at boot) BEFORE pushing this intro screen,
      -- so the Player object already exists by the time either choice
      -- below runs, with the wrong/default walk sprite baked in. Refresh
      -- it in place after writing the real gender rather than restructure
      -- that shared, Gen1-critical boot order (see Player:refreshSprite's
      -- own comment for why an in-place field swap is safe here).
      local function refreshPlayerSprite()
        local ow = self.game.overworld
        local p = ow and ow.player
        if p and p.refreshSprite then p:refreshSprite(self.game.data, self.game.save) end
      end
      local items = {
        { label = "BOY", onSelect = function()
          self.game.save.player.gender = "boy"
          self:setPlayerGenderArt("boy")
          self.showGenderChoices = false
          self.bgImage = nil
          self:recordAnswer(step, 1, "BOY", "boy")
          refreshPlayerSprite()
          self:advance()
        end },
        { label = "GIRL", onSelect = function()
          self.game.save.player.gender = "girl"
          self:setPlayerGenderArt("girl")
          self.showGenderChoices = false
          self.bgImage = nil
          self:recordAnswer(step, 2, "GIRL", "girl")
          refreshPlayerSprite()
          self:advance()
        end },
      }
      self.game.stack:push(Menu.new(self.game, items, { cancelable = false }))
    end)
  elseif kind == "demo" then
    self.demoAnimating = true
    self.bgImage = nil
    self.pic = self.demoPic
    self.picFlip = true
    self.picTrueColor = self.demoTrueColor
    self:revealPic("wipe", function()
      Sound.playCry(self.game.data, self.demoSpecies)
      self:sayText(self:stepText({ textKey = step.demoTextKey or "_OakText2" }),
        function() self:advance() end)
    end)
  else
    self.demoAnimating = false
    self.showGenderChoices = false
    self.bgImage = nil
    if kind == "name" then
      local who = step.who or "player"
      local isGirl = self.game.save.player.gender == "girl"
      local presets = isGirl
        and { "KRIS", "AMANDA", "JUANA", "JODI" }
        or { "CHRIS", "MAT", "ALLAN", "JON" }
      require("src.ui.Screens").push(self.game, "NamingScreen", {
        layout = "crystal",
        title = step.title or Strings("YOUR NAME?"),
        presets = presets,
        maxLen = step.maxLen or self.nameLen,
        iconImage = isGirl and self.playerGirlPic or self.playerBoyPic,
        iconTrueColor = true,
        onDone = function(name)
          if who == "rival" then
            self.game.save.player.rival = name
          else
            self.game.save.player.name = name
          end
          self:recordAnswer(step, 1, name, name)
          self:advance()
        end,
      })
    else
      OakSpeechModule.runStep(self, step)
    end
  end
end

function CrystalIntro:drawGenderChoices()
  local PaletteFX = require("src.render.PaletteFX")
  local function drawChoice(img, x, y)
    if not img then return end
    local w, h = img:getDimensions()
    love.graphics.draw(img, x, y)
    PaletteFX.markTrueColor(x, y, w, h)
  end
  drawChoice(self.playerBoyPic, 24, 36)
  drawChoice(self.playerGirlPic, 88, 36)
end

function CrystalIntro:update(dt)
  OakSpeechModule.update(self, dt)
end

function CrystalIntro:draw()
  OakSpeechModule.draw(self)
  if self.showGenderChoices then
    self:drawGenderChoices()
  end
end

return CrystalIntro
