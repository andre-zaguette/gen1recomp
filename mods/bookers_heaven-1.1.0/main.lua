-- palletreplace: Pallet Town gains an east wing, and its fourth warp drops
-- into BOOKER'S HEAVEN -- a room you enter through a trash can, where reading
-- the other trash can gets you jumped by a level 80 RATICATE called BOOKER.
--
--
-- The two maps are exported from Tiled (maps/*.lua); the room's own
-- scripting lives here, and the east-wing gate scene (OAK turning you
-- back until you own a POKéMON) in scripts/oak_gate.lua.

-- Applied in order: the new map registers before the patch that warps into
-- it, and the gate scene last -- it hooks the map the patch just widened.
local FILES = {
  "maps/BOOKERS_HEAVEN.lua",
  "maps/PALLET_TOWN.lua",
  "scripts/oak_gate.lua",
}

local TRASH_TEXT = "TEXT_BOOKERSHEAVEN_TRASH"
local WHISPER_TEXT = "TEXT_BOOKERSHEAVEN_WHISPER"
local BATTLE_CMD = "palletreplace:booker_battle"

-- BOOKER himself.  A wild mon's moves come from Pokemon.movesAtLevel, so the
-- move list has to be written over after the mon is built.
local BOOKER = {
  species = "RATICATE",
  level = 80,
  nickname = "BOOKER",
  moves = { "EMBER", "FLY" },
}

return function(mod)
  -- ------- the two maps

  for _, relative in ipairs(FILES) do
    local source = mod:read(relative)
    if not source then
      mod.log:error("%s missing from %s -- reinstall the mod", relative, mod.path)
    else
      local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. relative)
      if not chunk then
        mod.log:error("%s did not compile: %s", relative, tostring(compileErr))
      else
        local ok, apply = pcall(chunk)
        if not ok or type(apply) ~= "function" then
          mod.log:error("%s must return function(mod): %s", relative, tostring(apply))
        else
          apply(mod)
        end
      end
    end
  end

  -- ------- text
  -- \n starts the second line and \f is a page break; TextBox soft-wraps at
  -- 18 columns on top of that.  {PLAYER} is expanded by TextBox itself, so
  -- the whisper needs no substitution table.

  mod.content.text:register(TRASH_TEXT,
    "You weren't\nsupposed to be here!")

  mod.content.text:register(WHISPER_TEXT,
    "Someone whispers,\n\"This is BOOKER'S\fHEAVEN, not\n{PLAYER}'s heaven.\"")

  -- ------- the battle
  -- A mod command runs inside the script coroutine exactly like an engine
  -- one, so it may push a state and yield until it closes -- the same shape
  -- as Commands.start_battle.

  mod.content.commands:register(BATTLE_CMD, {
    -- illegal in a parallel script: it takes over the screen
    foreground = true,
    fn = function(ctx)
      local BattleState = require("src.battle.BattleState")
      local Pokemon = require("src.pokemon.Pokemon")
      local Strings = require("src.core.Strings")
      local game, runner = ctx.game, ctx.runner

      local battle = BattleState.newWild(game, BOOKER.species, BOOKER.level)

      -- Rebuild the enemy so the nickname and the move list are the ones
      -- authored here.  makeBattler derives name, curMoves, curStats and the
      -- sprite together, so going through it keeps them consistent -- setting
      -- mon.moves alone would leave battler.curMoves pointing at the old list.
      local mon = Pokemon.new(game.data, BOOKER.species, BOOKER.level)
      mon.nickname = BOOKER.nickname
      mon.moves = {}
      for _, moveId in ipairs(BOOKER.moves) do
        local moveDef = game.data.moves[moveId]
        if not moveDef then
          mod.log:warn("BOOKER: unknown move %s (skipped)", moveId)
        else
          mon.moves[#mon.moves + 1] = { id = moveId, pp = moveDef.pp or 0 }
        end
      end
      battle.enemy = BattleState.makeBattler(game.data, mon, false)
      -- newWild built this from the pre-rename battler
      battle.introText = Strings("Wild %s\nappeared!", battle.enemy.name)

      battle.onFinish = function(result)
        ctx.lastBattleResult = result
        ctx.lastCheck = result == "win"
        if ctx.overworld then ctx.overworld:afterBattle(result, battle) end
        runner:resume()
      end
      game.stack:push(battle)
      runner:yield()
    end,
  })

  -- ------- the room's script

  mod.content.map_scripts:register("BOOKERS_HEAVEN", {
    -- Reading trash can 
    -- (OverworldController.lua:2827).
    talk = {
      [TRASH_TEXT] = {
        { "show_text", TRASH_TEXT },
        { BATTLE_CMD },
      },
    },

    -- onEnter can be reached mid-warp, while the warp command's own runner is
    -- still suspended; starting a script there would trip ScriptRunner:run's
    -- assert.  queueScript is the engine's own answer -- it drains one script
    -- per idle frame once the world settles.
    onEnter = function(_game, overworld)
      overworld:queueScript({
        { "show_text", WHISPER_TEXT },
      })
    end,
  })
end
