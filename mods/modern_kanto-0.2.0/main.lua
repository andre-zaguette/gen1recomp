-- Modern Kanto
--
-- Four changes that each answer the same complaint: Gen 1 decided things by
-- type that later generations decided by move, and shipped a battle system
-- nobody could argue with because nobody could see it.
--
--   SPLIT   physical/special per move, not per type   (Gen 4)
--   TYPES   the four rows Gen 2 corrected              (including the Ghost bug)
--   AI      opponents that read type effectiveness
--   ATLAS   a screen for what lives here and what you still need
--
-- Every one is separately switchable and every one is off-by-default where
-- it changes the balance, because this is a beta and a player should be able
-- to turn a piece off without turning the mod off.
--
-- ------- why everything is in this one file
--
-- 0.1.0 shipped as main.lua plus data/ and lib/, pulled in with
-- `require("data.split")` and friends. It did not work: a mod-relative
-- require does not resolve at runtime, so main.lua threw on its first line
-- and the mod registered NOTHING -- no options, no screen, no patches --
-- while reporting no error at all. modkit validate stayed green throughout,
-- because its harness feeds the mod's files in differently from the way the
-- game does.
--
-- One file has no such question to answer.
--
-- ------- why the split is data and not a hook
--
-- src/battle/Damage.lua decides a move's category like this:
--
--   "the move's own category field wins, then the merged type record's"
--
-- So the per-move answer is already supported; Gen 1 simply never fills the
-- move's own field. Patching `moves` records is therefore the whole of the
-- split -- no damage hook, nothing intercepted, and it composes with any
-- other mod that touches the battle instead of racing it.

-- The Gen 4 physical/special split, expressed as exceptions.
--
-- Gen 1 decides the category from the move's TYPE: every Water move is
-- special because Water is a special type, every Normal move physical. Gen 4
-- moved the decision onto the move itself, which is why Gyarados -- 125
-- Attack, 60 Special -- throws Hydro Pump off the wrong stat in Gen 1.
--
-- The engine already supports the per-move answer: Damage.categoryOf reads
-- "the move's own category field wins, then the merged type record's". So
-- this is data, not a hook -- which is why the split composes with any other
-- mod that touches damage instead of fighting it.
--
-- Only the DIFFERENCES are listed. A move whose Gen 4 category already
-- matches what its Gen 1 type implies needs no entry, and listing it would
-- just be a bigger table to get wrong.
local SPLIT = {
  -- Special types whose move is PHYSICAL in Gen 4. The punches are the
  -- famous ones: Fire Punch off a special stat is why Gen 1 Hitmonchan
  -- cannot use its elemental punches at all.
  physical = {
    "FIRE_PUNCH",     -- Fire
    "ICE_PUNCH",      -- Ice
    "THUNDERPUNCH",   -- Electric
    "CRABHAMMER",     -- Water
    "WATERFALL",      -- Water
    "CLAMP",          -- Water
    "RAZOR_LEAF",     -- Grass
    "VINE_WHIP",      -- Grass
  },

  -- Physical types whose move is SPECIAL in Gen 4.
  special = {
    "GUST",           -- Normal in Gen 1; Flying and special from Gen 2 on
    "SWIFT",          -- Normal
    "TRI_ATTACK",     -- Normal
    "HYPER_BEAM",     -- Normal
    "RAZOR_WIND",     -- Normal
    "SONICBOOM",      -- Normal; fixed damage, but categorised for consistency
    "ACID",           -- Poison
    "SLUDGE",         -- Poison
    "SMOG",           -- Poison
  },
}

-- The four places Gen 1's type chart disagrees with every generation after
-- it. Multipliers are the engine's tenths: 0 immune, 5 half, 20 double, and
-- an absent row means neutral.
--
-- The first is not a design choice anyone defends -- it is a bug. Ghost was
-- meant to be strong against Psychic (the games say so, the anime says so,
-- Sabrina's gym is built as though it were true) and the table shipped with
-- a zero, so Ghost does literally nothing to Psychic. Since Gen 1's only
-- Ghost moves are on Poison-typed Pokemon, which Psychic resists, Psychic
-- ends up with no counterplay at all and eats the entire generation.
--
-- Verified against the decoded chart rather than from memory: the four rows
-- below read 0x, 2x, 2x and absent in the ROM's own data.
local TYPEFIX = {
  { attacker = "GHOST", defender = "PSYCHIC_TYPE", from = 0, to = 20,
    why = "the notorious bug: 0x where 2x was intended" },
  { attacker = "BUG", defender = "POISON", from = 20, to = 5,
    why = "Gen 2 flipped it: Bug is weak to Poison, not strong" },
  { attacker = "POISON", defender = "BUG", from = 20, to = 10,
    why = "Gen 2 made it neutral" },
  { attacker = "ICE", defender = "FIRE", from = 10, to = 5,
    why = "Gen 2 made Fire resist Ice; Gen 1 left it neutral" },
}

return function(mod)
  local Strings = require("src.core.Strings")

  mod.options:define({
    { key = "split", label = "SPLIT", type = "toggle", default = false },
    { key = "types", label = "TYPE CHART", type = "choice", default = "gen1",
      choices = { { "GEN 1", "gen1" }, { "MODERN", "modern" } } },
    { key = "ghost", label = "GHOST FIX", type = "toggle", default = true },
    { key = "ai", label = "SMART AI", type = "toggle", default = false },
    { key = "atlas", label = "ATLAS", type = "toggle", default = true },
  })

  local function opt(key)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok then return nil end
    return value
  end

  -- ------- 1. the physical/special split
  --
  -- Applied at load because a registry patch is a load-time act: the merge
  -- happens once, and a category that changed halfway through a battle would
  -- be worse than either answer. The option is read here and takes effect on
  -- the next launch, which the label says.

  if opt("split") then
    for _, id in ipairs(SPLIT.physical) do
      pcall(function() mod.content.moves:patch(id, { category = "physical" }) end)
    end
    for _, id in ipairs(SPLIT.special) do
      pcall(function() mod.content.moves:patch(id, { category = "special" }) end)
    end
  end

  -- ------- 2. the type chart
  --
  -- GHOST FIX is separate from the rest and on by default, because the
  -- Ghost/Psychic zero is a bug rather than a balance decision -- the other
  -- three rows are Gen 2 rebalancing a working chart, which is a taste.
  --
  -- A row that exists is patched and a missing one registered: Ice/Fire is
  -- absent from the ROM's table entirely (absent means neutral), so there is
  -- nothing there to patch.

  local function setMatchup(attacker, defender, multiplier)
    local id = attacker .. ">" .. defender
    local ok = pcall(function()
      mod.content.type_chart:patch(id, { multiplier = multiplier })
    end)
    if not ok then
      pcall(function()
        mod.content.type_chart:register(id, { multiplier = multiplier })
      end)
    end
  end

  local modernTypes = opt("types") == "modern"
  for _, row in ipairs(TYPEFIX) do
    local isGhostBug = row.attacker == "GHOST" and row.defender == "PSYCHIC_TYPE"
    if (isGhostBug and opt("ghost")) or (not isGhostBug and modernTypes) then
      setMatchup(row.attacker, row.defender, row.to)
    end
  end

-- The type-effectiveness pass, done properly.
--
-- ------- why this patches LAYER_3 instead of adding a layer
--
-- A layer only runs if the trainer's own class lists it (TrainerAI walks the
-- class's `mods` and looks each id up), so registering a brand new id would
-- have produced a record nobody ever calls -- a mod that appears to work,
-- changes nothing, and gives no error. LAYER_3 is the vanilla type pass and
-- every type-aware trainer already references it, so patching it reaches
-- exactly the opponents it should.
--
-- ------- what vanilla gets wrong
--
-- The engine's own comment on LAYER_3:
--
--   "AIGetTypeEffectiveness only reads the FIRST matching TypeEffects row
--    for (move type vs either defender type) -- no dual-type product"
--
-- So against a dual type the AI sees one half of the matchup and stops. A
-- Fire move into Grass/Poison reads 2x and ignores nothing else; a Ground
-- move into a Flying/Ground target may read the 2x and miss that the target
-- is immune. This pass multiplies the rows out, which is what the damage
-- calculation itself does when the move actually lands.
--
-- Scores are golf: LOWER is more encouraged (vanilla writes `score - 1` to
-- encourage and `score + 1` to discourage), and every usable move starts at
-- 10.


local function aiScore(TypeChart, view, def, score)
  if not def then return score end
  -- A status move has no damage to be effective with; vanilla runs this pass
  -- for them too, and nudging them on typing is noise.
  if (def.power or 0) <= 0 then return score end

  local rows = TypeChart.rows(def.type, view.target.curTypes)
  if not rows or #rows == 0 then return score end

  -- tenths, so 10 is neutral: 20 * 5 / 10 = 10, a 2x and a 0.5x cancelling
  local mult = 10
  for _, row in ipairs(rows) do
    mult = mult * row / 10
  end

  if mult == 0 then
    -- Immune. Vanilla has no answer for this at all, which is why a Gen 1
    -- trainer will happily throw Earthquake at a Pidgey until it faints.
    return score + 5
  elseif mult >= 20 then
    return score - 2      -- super effective: harder than vanilla's -1
  elseif mult > 10 then
    return score - 1
  elseif mult < 10 then
    return score + 1
  end
  return score
end

-- Returns the score function to patch onto LAYER_3. TypeChart is required
-- here rather than at file scope so a headless test can hand in its own.
local function aiLayer()
  local TypeChart = require("src.battle.TypeChart")
  return function(view, def, score)
    local ok, result = pcall(aiScore, TypeChart, view, def, score)
    -- A throw inside the AI would take the enemy's turn down with it, so an
    -- unexpected shape just leaves the vanilla score alone.
    if ok then return result end
    return score
  end
end

  -- ------- 3. the AI layer
  --
  -- ai_classes takes three kinds of record; `layer` is a scoring pass over
  -- the moves the opponent is choosing between, which is the smallest useful
  -- one. A `brain` would replace the chooser outright and throw away the
  -- vanilla behaviour this is meant to sit on top of.
  --
  -- Scoring only nudges: it does not pick. Gen 1's own layers still run, so
  -- a trainer keeps its personality and simply stops firing Water Gun at
  -- Gyarados.

  -- LAYER_3 is patched rather than a new id registered: TrainerAI walks the
  -- trainer class's own list of layers, so an id nobody references would be
  -- a record that never runs -- working in appearance, inert in fact.
  if opt("ai") then
    local scoreLayer = aiLayer()
    pcall(function()
      mod.content.ai_classes:patch("LAYER_3", { score = scoreLayer })
    end)
  end

-- The Atlas: what lives where, and what you still need.
--
-- Gen 1 holds a complete encounter table and shows the player none of it.
-- The Pokedex says what a species is once you have met it; nothing says
-- where to go and find the one you have not. This reads the merged
-- `encounters` dataset -- so a mod that adds or edits encounters appears
-- here too -- and marks each species against the dex.
--
-- One area per row, expanded into its species when opened. No search and no
-- sorting: at 8 pixels a glyph a 160-wide screen holds nineteen characters,
-- and a filter box would cost more of them than it earns.


local ROWS = 13          -- list rows that fit between header and footer
local TEXT_X = 4
local TEXT_MAX = 160 - TEXT_X * 2

local function newAtlas(mod, game)
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")

  local function fit(text)
    text = tostring(text or "")
    while #text > 1 and Font.width(text) > TEXT_MAX do
      text = text:sub(1, #text - 1)
    end
    return text
  end

  -- Areas, built once on open. The dataset is a map id -> { grass = {...},
  -- water = {...} }, each holding slots of { level, species }; the same
  -- species appears in several slots, so they are folded to one row with the
  -- level range that species actually spans.
  local function buildAreas()
    local out = {}
    local encounters = game.data and game.data.encounters or {}
    for mapId, groups in pairs(encounters) do
      local seen, list = {}, {}
      for _, group in pairs(groups) do
        for _, slot in ipairs((type(group) == "table" and group.slots) or {}) do
          local id = slot.species
          if id then
            local row = seen[id]
            if row then
              row.low = math.min(row.low, slot.level or 0)
              row.high = math.max(row.high, slot.level or 0)
            else
              row = { species = id, low = slot.level or 0, high = slot.level or 0 }
              seen[id] = row
              list[#list + 1] = row
            end
          end
        end
      end
      if #list > 0 then
        table.sort(list, function(a, b) return a.species < b.species end)
        out[#out + 1] = { map = mapId, species = list }
      end
    end
    table.sort(out, function(a, b) return a.map < b.map end)
    return out
  end

  local self = {
    game = game,
    isOpaque = true,
    areas = buildAreas(),
    area = nil,     -- nil = the area list; otherwise the opened area
    index = 1,
    scroll = 0,
  }

  local function owned(speciesId)
    local dex = game.save and game.save.pokedex
    return dex and dex.owned and dex.owned[speciesId] and true or false
  end

  local function rowCount()
    if self.area then return #self.area.species end
    return #self.areas
  end

  local function clamp()
    local n = math.max(1, rowCount())
    if self.index < 1 then self.index = n end
    if self.index > n then self.index = 1 end
    if self.index <= self.scroll then self.scroll = self.index - 1 end
    if self.index > self.scroll + ROWS then self.scroll = self.index - ROWS end
    if self.scroll < 0 then self.scroll = 0 end
  end

  function self:update()
    local input = game.input
    if input:wasPressed("up") then self.index = self.index - 1; clamp()
    elseif input:wasPressed("down") then self.index = self.index + 1; clamp()
    elseif input:wasPressed("a") then
      if not self.area and self.areas[self.index] then
        self.area, self.index, self.scroll = self.areas[self.index], 1, 0
      end
    elseif input:wasPressed("b") then
      -- B walks back out of an area before it leaves the screen, which is
      -- the behaviour every other nested menu in this game has.
      if self.area then
        self.area, self.index, self.scroll = nil, 1, 0
      else
        game.stack:pop()
      end
    elseif input:wasPressed("start") then
      game.stack:pop()
    end
  end

  -- Areas are counted by how many of their species the player owns, which is
  -- the number the screen exists to answer: not "what is here" but "is there
  -- anything here I still need".
  local function areaProgress(area)
    local have = 0
    for _, row in ipairs(area.species) do
      if owned(row.species) then have = have + 1 end
    end
    return have, #area.species
  end

  function self:draw()
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.setColor(0, 0, 0, 1)

    if self.area then
      local have, total = areaProgress(self.area)
      Font.draw(fit(Strings("%d/%d CAUGHT", have, total)), TEXT_X, 2)
    else
      local areas = #self.areas
      Font.draw(fit(Strings("ATLAS %d AREAS", areas)), TEXT_X, 2)
    end

    local top = 14
    for i = 1, ROWS do
      local n = self.scroll + i
      local y = top + (i - 1) * 9
      local line
      if self.area then
        local row = self.area.species[n]
        if row then
          local mark = owned(row.species) and "*" or "-"
          local level = row.low == row.high and tostring(row.low)
                        or (row.low .. "-" .. row.high)
          line = Strings("%s%s L%s", mark, row.species, level)
        end
      else
        local area = self.areas[n]
        if area then
          local have, total = areaProgress(area)
          line = Strings("%s %d/%d", area.map, have, total)
        end
      end
      if line then
        if n == self.index then Font.draw(">", TEXT_X - 3, y) end
        Font.draw(fit(line), TEXT_X + 6, y)
      end
    end

    Font.draw(fit(Strings("A:OPEN B:BACK")), TEXT_X, 133)
  end

  clamp()
  return self
end

  -- ------- 4. the atlas

  if opt("atlas") then
    local SCREEN = "ModernKantoAtlas"
    mod.content.screens:register(SCREEN, { new = function(game)
      return newAtlas(mod, game)
    end })

    mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
      local out = next(game, items)
      if type(out) ~= "table" then return out end
      return mod.ui.insertBefore(out, "SAVE", {
        label = Strings("ATLAS"),
        onSelect = function() mod.ui.push(game, SCREEN) end,
      })
    end)
  end

  -- ------- the public surface
  --
  -- Exported so another mod can read them, and so the suite can check the
  -- tables and the scoring through the same door the game uses rather than
  -- reaching for a file it hopes is there.
  mod.exports.split = SPLIT
  mod.exports.typefix = TYPEFIX
  mod.exports.aiScore = aiScore
end
