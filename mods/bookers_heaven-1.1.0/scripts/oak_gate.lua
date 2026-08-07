-- The east-wing gate scene.
--
-- Pallet Town's fence is opened at block row 2 (cells y = 4 and y = 5) so
-- the player can walk east into the new wing and on to BOOKER'S HEAVEN.
-- Step through that gap with an empty party and OAK comes tearing up
-- behind you, tells you off, marches you back out, and bolts.
--
-- Shaped after PalletTownOakWalksToPlayerScript (pret/pokered
-- scripts/PalletTown.asm) and its port in data/scripts/story2.lua: an
-- onStep hook that returns true to consume the step, a Music_MeetProfOak
-- sting, an emote hold for the "!" bubble, then chained scriptMoves.
-- Nothing here uses ScriptRunner rows, for the same reason story2 does
-- not: onStep can fire while another runner is suspended.

-- The vanilla map is 10 blocks (20 cells) wide, so cells 0..19 are the
-- old town and x >= 20 is the wing this mod bolted on.  Cell 18/19 is the
-- opened fence square itself -- still town, so the scene only fires once
-- a foot actually lands past it.
local WING_X = 20

-- Where the player is put back down: two cells west of the fence gap, far
-- enough that the scene cannot immediately re-arm on the next step east.
local SAFE_X = 17

-- The corridor rows.  Everything else in the wing is unreachable without
-- passing through these, so gating them gates the whole wing, and the
-- walk-back is always a straight line west along walkable ground.
local GATE_ROWS = { [4] = true, [5] = true }

-- Oak retreats to the open middle of town (block row 3 spans y = 6..7,
-- cells x = 2..17) and vanishes there.
local FLEE_Y = 7
local FLEE_X = 9

local SCOLD_TEXT = "TEXT_PALLETTOWN_OAK_GATE"
local PARTING_TEXT = "TEXT_PALLETTOWN_OAK_GATE_BYE"

local SCOLD_FALLBACK =
  "OAK: Hey! Hey!\nDon't go in there!"
  .. "\fWhat the heck do\nyou think you're"
  .. "\fdoing, {PLAYER}?"
  .. "\fYou don't even\nhave a POKéMON!"
  .. "\fCome on, out you\ngo!"

local PARTING_FALLBACK =
  "OAK: Stay out of\nthere, you hear?"
  .. "\fI... uh...\nI have to go!"

return function(mod)
  mod.content.text:register(SCOLD_TEXT, SCOLD_FALLBACK)
  mod.content.text:register(PARTING_TEXT, PARTING_FALLBACK)

  mod.content.map_scripts:register("PALLET_TOWN", {
    -- Ahead of the base contribution either way (mods outrank base at
    -- equal priority), and onStep is first-truthy-consumes, so returning
    -- false leaves the vanilla Oak intro at y == 1 untouched.
    onStep = function(game, ow, x, y)
      if x < WING_X or not GATE_ROWS[y] then return false end
      -- Only heading east.  Walking back out of the wing already ends
      -- where the scene would put you, so re-firing there is noise.
      if ow.player.facing ~= "right" then return false end
      if #game.save.party > 0 then return false end

      local TextBox = require("src.render.TextBox")
      local Commands = require("src.script.Commands")
      local Music = require("src.core.Music")
      local t = game.data.text
      local ctx = { save = game.save, game = game, overworld = ow }

      -- Freeze on this frame.  update() bails early while ow.emote is
      -- set, so no input frame can sneak in between here and the first
      -- scriptMove (the same trap story2.lua's comment at the `scripted`
      -- recheck describes).
      local function hold(frames, npc, cb)
        ow.emote = { frames = frames, npc = npc, onDone = cb }
      end

      ow.player.facing = "left"
      Music.play(game.data, "Music_MeetProfOak")

      -- Oak comes up two cells behind and closes to one, so he is never
      -- spawned on top of the player however deep into the wing they got.
      Commands.show_object(ctx, "PALLET_TOWN", "PALLETTOWN_OAK_GATE")
      Commands.place_npc(ctx, 4, x - 2, y, "right")
      local oak = ow:npcByIndex(4)

      -- Oak's exit: down to the open row, west across town, gone.  The
      -- map theme only comes back once he is hidden, like the escort's
      -- PlayDefaultMusic at the end of the lab walk-in.
      local function flee()
        local function vanish()
          Commands.hide_object(ctx, "PALLET_TOWN", "PALLETTOWN_OAK_GATE")
          Music.playMap(game.data, "PALLET_TOWN")
        end
        if not oak then return vanish() end
        ow:scriptMove(oak, "down", FLEE_Y - oak.cellY, function()
          ow:scriptMove(oak, "left", oak.cellX - FLEE_X, vanish)
        end)
      end

      -- Oak leads, the player follows one cell behind, one tile per beat
      -- (PalletMovementScript_WalkToLab's lockstep, minus the RLE).
      local function marchOut()
        local remaining = x - SAFE_X
        local function tick()
          if remaining <= 0 then
            game.stack:push(TextBox.new(game,
              t[PARTING_TEXT] or PARTING_FALLBACK, flee))
            return
          end
          remaining = remaining - 1
          if oak then ow:scriptMove(oak, "left", 1) end
          ow:scriptMove(ow.player, "left", 1, tick)
        end
        tick()
      end

      -- "!" over Oak, then he steps into the player's face and talks.
      hold(30, oak, function()
        local function scold()
          game.stack:push(TextBox.new(game,
            t[SCOLD_TEXT] or SCOLD_FALLBACK, marchOut))
        end
        if oak then
          ow:scriptMove(oak, "right", 1, scold)
        else
          scold()
        end
      end)
      return true
    end,
  })
end
