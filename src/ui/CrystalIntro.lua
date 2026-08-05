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

local CrystalIntro = setmetatable({}, { __index = OakSpeechModule })
CrystalIntro.__index = CrystalIntro
CrystalIntro.isOpaque = true
CrystalIntro.letterboxWhite = true

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
  local ok, img = pcall(love.graphics.newImage, Assets.resolve(demoPath or ""))
  self.demoPic = ok and img or nil
  self.demoTrueColor = self.demoPic and demoTrueColor or false
  return self
end

function CrystalIntro:runStep(step)
  local kind = step.kind
  if kind == "gender" then
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
          self:recordAnswer(step, 1, "BOY", "boy")
          refreshPlayerSprite()
          self:advance()
        end },
        { label = "GIRL", onSelect = function()
          self.game.save.player.gender = "girl"
          self:recordAnswer(step, 2, "GIRL", "girl")
          refreshPlayerSprite()
          self:advance()
        end },
      }
      self.game.stack:push(Menu.new(self.game, items, { cancelable = false }))
    end)
  elseif kind == "demo" then
    self.pic = self.demoPic
    self.picFlip = true
    self.picTrueColor = self.demoTrueColor
    self:revealPic("wipe", function()
      Sound.playCry(self.game.data, self.demoSpecies)
      self:say(step.demoTextKey or "_OakText2", function() self:advance() end)
    end)
  else
    OakSpeechModule.runStep(self, step)
  end
end

return CrystalIntro
