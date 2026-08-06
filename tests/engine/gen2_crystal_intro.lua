-- CrystalIntro's step list and its "gender" step (Task 8 of
-- docs/superpowers/plans/2026-08-04-gen2-crystal-intro.md). No ROM: the step
-- list is a hand-built Lua table already (defaultSteps() needs nothing from
-- game.data), and the gender step is driven against a minimal fake game
-- shaped after what CrystalIntro.new/runStep actually touch (read from
-- src/ui/CrystalIntro.lua and src/ui/OakSpeech.lua before writing this).
--
-- This is a UI/screen-logic fixture, not a pure-data-shape one, so it
-- follows the tests/engine convention that menu_click_bug570.lua and
-- ask_yesno_overlap.lua already established (fake game + stack, T harness)
-- rather than tests/run_tests.lua's Gen2 section, whose existing blocks
-- (font/palette/gbc-atlas-cache) are all pure data-shape fixtures over a
-- real extractor/consumer pair. gen2_cry_transcoder.lua and
-- gen2_music_transcoder.lua already set the "gen2_*.lua under tests/engine/"
-- precedent for newer Gen2 work, auto-discovered by run_engine.lua's
-- directory glob.
--   luajit tests/engine/gen2_crystal_intro.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local CrystalIntro = require("src.ui.CrystalIntro")

-- ------------------------------------------------------------ step list

local steps = CrystalIntro.defaultSteps()

eq(steps[1].kind, "gender",
  "CrystalIntro steps: gender is the first step (InitGender runs before "
  .. "Oak's narration in the ROM)")

local demoCount, nameCount = 0, 0
for _, step in ipairs(steps) do
  if step.kind == "demo" then demoCount = demoCount + 1 end
  if step.kind == "name" then nameCount = nameCount + 1 end
  -- direct regression guard for the "no rival naming" non-goal: Crystal's
  -- NewGame/OakSpeech/InitGender sequence never shows or names a rival
  -- (rival naming happens later, as an ordinary Elm's Lab map event)
  check(step.who ~= "rival",
    "CrystalIntro steps: no step is addressed to a rival (id=" .. tostring(step.id) .. ")")
  check(step.presetsWho ~= "rival",
    "CrystalIntro steps: no step pulls rival name presets (id=" .. tostring(step.id) .. ")")
  check(step.pic ~= "rival",
    "CrystalIntro steps: no step shows the rival pic shorthand (id=" .. tostring(step.id) .. ")")
  check(not (type(step.pic) == "table" and step.pic.id == "OPP_RIVAL1"),
    "CrystalIntro steps: no step resolves the rival trainer pic (id=" .. tostring(step.id) .. ")")
end
eq(demoCount, 1, "CrystalIntro steps: exactly one demo-kind step (Wooper's show-off)")
eq(nameCount, 1, "CrystalIntro steps: exactly one name-kind step (the player only)")

-- ------------------------------------------------------- gender step

-- Minimal fake game: only the fields CrystalIntro.new (via OakSpeech.new)
-- and the "gender" runStep branch actually read. OakSpeech.new tolerates a
-- missing game.data.trainers/.field/.constants/.sprites (all guarded with
-- `... or {}`/`and` short-circuits), and Sprites.path/playerPath fall back
-- cleanly when game.data.pokemon is absent -- so this only needs to supply
-- what CrystalIntro's own demoSpecies override (WOOPER) and the gender
-- step's text actually resolve.
local pushed = {}
local fakeGame = {
  data = {
    pokemon = { WOOPER = { spriteFront = "fake/wooper_front.png" } },
    text = {
      _AreYouABoyOrAreYouAGirlText = "Are you a boy?\nOr are you a girl?",
      _OakText1 = "Hello there!",
      _OakText2 = "Wooper!",
      _OakText4 = "Welcome to the\nworld of POKEMON!",
      _OakText5 = "This world is\ninhabited by POKEMON!",
      _OakText6 = "First, what is\nyour name?",
      _OakText7 = "Your very own\nlegend is about to unfold!",
    },
    sprites = {},
    field = {},
    trainers = {},
  },
  save = { player = {} },
  stack = {
    push = function(_, state) pushed[#pushed + 1] = state end,
  },
}

local intro = CrystalIntro.new(fakeGame, function() end)
check(intro ~= nil, "CrystalIntro.new: constructs against the minimal fake game")
eq(intro.demoSpecies, "WOOPER", "CrystalIntro.new: overrides demoSpecies to WOOPER")
check(intro.rivalPic == nil, "CrystalIntro.new: no rival pic is ever loaded")

-- Stand in for the real TextBox flow (already covered by OakSpeech's own
-- tests): the gender step's real behavior is in the Menu items' onSelect
-- closures, not in how the prompt text gets displayed, so skip straight to
-- them by having sayText call its `next` callback immediately, the same as
-- a TextBox that has finished typing and been dismissed.
intro.sayText = function(_, _text, next) next() end

local genderStep = steps[1]
intro:runStep(genderStep)

eq(#pushed, 1, "CrystalIntro gender step: pushes exactly one state (the BOY/GIRL menu)")
local menu = pushed[1]
check(menu ~= nil and menu.items ~= nil, "CrystalIntro gender step: the pushed state is a Menu with items")

local labels = {}
for i, item in ipairs(menu.items) do labels[i] = item.label end
T.same(labels, { "BOY", "GIRL" }, "CrystalIntro gender step: menu offers BOY then GIRL")

-- simulate choosing GIRL
local girlItem
for _, item in ipairs(menu.items) do
  if item.label == "GIRL" then girlItem = item end
end
check(girlItem ~= nil, "CrystalIntro gender step: a GIRL item exists to select")
girlItem.onSelect()

eq(fakeGame.save.player.gender, "girl",
  "CrystalIntro gender step: choosing GIRL sets save.player.gender "
  .. "(regression guard for Player.lua sprite-selection wiring)")

T.finish("Gen2 Crystal intro")
