-- The bag: lists inventory, uses items via ItemEffects.
-- opts.battle = BattleState when opened mid-battle (balls throwable,
-- using an item consumes the turn).

local ItemEffects = require("src.inventory.ItemEffects")
local ListMenu = require("src.ui.ListMenu")
local TextBox = require("src.render.TextBox")

local BagMenu = {}

local Bag = require("src.inventory.Bag")
local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local CRYSTAL_POCKETS = {
  { id = "ITEM", title = "ITEMS" },
  { id = "BALL", title = "BALLS" },
  { id = "KEY_ITEM", title = "KEY ITEMS" },
  { id = "TM_HM", title = "TM/HM" },
}

local PACK_MENU_PATH = "roms/pokecrystal/gfx/pack/pack_menu.png"
local PACK_PAL_PATH = "roms/pokecrystal/gfx/pack/pack.pal"
local PACK_F_PAL_PATH = "roms/pokecrystal/gfx/pack/pack_f.pal"
local PACK_TILEMAP = {
  { 0x00, 0x04, 0x04, 0x04, 0x01, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x02, 0x05, 0x05, 0x05, 0x03 },
  { 0x00, 0x04, 0x04, 0x04, 0x01, 0x15, 0x16, 0x17, 0x18, 0x19, 0x02, 0x05, 0x05, 0x05, 0x03 },
  { 0x00, 0x04, 0x04, 0x04, 0x01, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x02, 0x05, 0x05, 0x05, 0x03 },
  { 0x00, 0x04, 0x04, 0x04, 0x01, 0x10, 0x11, 0x12, 0x13, 0x14, 0x02, 0x05, 0x05, 0x05, 0x03 },
}

local packMenuQuads
local packPaletteCache = {}

local function scale5to255(v)
  return math.floor(v * 255 / 31 + 0.5)
end

local function loadPackPals(path)
  local cached = packPaletteCache[path]
  if cached ~= nil then return cached end
  local f = io.open(path, "rb")
  if not f then
    packPaletteCache[path] = false
    return nil
  end
  local text = f:read("*a")
  f:close()
  local pals, cur = {}, {}
  for r, g, b in text:gmatch("RGB%s+(%d+)%s*,%s*(%d+)%s*,%s*(%d+)") do
    cur[#cur + 1] = {
      scale5to255(tonumber(r) or 0),
      scale5to255(tonumber(g) or 0),
      scale5to255(tonumber(b) or 0),
    }
    if #cur == 4 then
      pals[#pals + 1] = cur
      cur = {}
    end
  end
  packPaletteCache[path] = pals
  return pals
end

local function withPackPalette(palette, drawFn)
  local shader = require("src.render.PaletteFX").shader()
  if shader and palette then
    love.graphics.setShader(shader)
    require("src.render.PaletteFX").sendColors(shader, palette)
  end
  drawFn()
  if shader and palette then love.graphics.setShader() end
end

local function packMenuQuad(tile)
  if not love.graphics or not love.graphics.newQuad then return nil end
  if not packMenuQuads then packMenuQuads = {} end
  local q = packMenuQuads[tile]
  if q ~= nil then return q end
  local img = Assets.image(PACK_MENU_PATH)
  local iw, ih = img:getDimensions()
  local cols = math.floor(iw / 8)
  q = love.graphics.newQuad((tile % cols) * 8, math.floor(tile / cols) * 8, 8, 8, iw, ih)
  packMenuQuads[tile] = q
  return q
end

local function drawPackMenuTile(tile, x, y)
  local q = packMenuQuad(tile)
  if q then love.graphics.draw(Assets.image(PACK_MENU_PATH), q, x, y) end
end

-- acquisition order like wBagItems (Bag.order), not alphabetical
local function buildItems(game, pocket)
  local items = {}
  for _, id in ipairs(Bag.order(game.save, game.data, pocket)) do
    local def = game.data.items[id]
    local right
    if (game.save.inventory[id] or 0) > 0
       and Bag.pocketOf(game.data, id, def) ~= "KEY_ITEM"
       and not (def and def.machine and def.machine.kind == "HM") then
      right = "x" .. game.save.inventory[id]
    end
    table.insert(items, {
      value = id,
      label = def and def.name or id,
      right = right,
    })
  end
  return items
end

local function consume(game, id)
  Bag.remove(game.save, id, 1)
end

local function save_name(game)
  return game.save.player.name
end

local function showMessages(game, msgs, onDone)
  if not msgs or #msgs == 0 then
    if onDone then onDone() end
    return
  end
  game.stack:push(TextBox.new(game, table.concat(msgs, "\f"), onDone))
end

-- run the use-flow for an item on a chosen target.  `picker` is the party
-- menu when it was opened with keepOpen (HP medicine only): it is still on
-- the stack, so every exit that prints has to close it afterwards.  For
-- every other item the picker popped itself first and closePicker's identity
-- check makes it a no-op (#252).
local function useOn(game, battle, id, target, list, moveIndex, picker)
  local result, payload, extra = ItemEffects.use(game.data, game.save, id, target,
                                                 battle, moveIndex, game.overworld)
  local function closePicker()
    if picker then picker:close() end
  end

  -- field POKé FLUTE: play the tune, then the no-effect text
  if result == "flute_field" then
    require("src.core.Sound").play(game.data, "Pokeflute")
    showMessages(game, payload)
    return
  end

  -- field POKé FLUTE next to a not-yet-beaten Snorlax: "had effect" text,
  -- then the woke-up/battle sequence (data/scripts/story.lua snorlaxWake)
  if result == "flute_wake" then
    list:close()
    require("src.core.Sound").play(game.data, "Pokeflute")
    showMessages(game, payload, function()
      local ow = game.overworld
      local mod = ow and require("data.scripts.init").get(extra.mapId)
      if ow and mod and mod.snorlaxWake then
        ow.runner:run(mod.snorlaxWake.script, { npc = extra.npc })
      end
    end)
    return
  end

  if result == "consumed_escape" then -- Poké Doll
    consume(game, id)
    list:close()
    showMessages(game, payload, function()
      -- ItemUsePokeDoll sets wEscapedFromBattle and never touches
      -- wBattleResult, so a script that reads the result afterwards sees
      -- 0 -- "defeated". The ghost MAROWAK's script keys on exactly that
      -- (the Poke Doll trick); the flag lets it tell this escape from an
      -- ordinary RUN, which writes $2.
      battle.pokeDollEscape = true
      battle.result = "run"
      battle.afterQueue = "finish"
      battle.phase = "messages"
    end)
    return
  end

  if result == "bicycle" then
    -- StartMenu_Item .useOrTossItem (engine/menus/start_sub_menus.asm):
    -- while BIT_ALWAYS_ON_BIKE of wStatusFlags6 is set -- the Cycling Road,
    -- armed by the forced-bike tiles and cleared by the Route 16/18 gate
    -- scripts -- the BICYCLE refuses with _CannotGetOffHereText and jumps
    -- back to ItemMenuLoop, so the bag stays open and no dismount happens
    -- (#513).  The gate sits ahead of UseItem, before ItemUseBicycle ever
    -- runs, which is why it precedes list:close() here.
    if game.save.forcedBike then
      showMessages(game, { Strings("You can't get off\nhere.") })
      return
    end
    list:close()
    local ow = game.overworld
    local Music = require("src.core.Music")
    -- IsBikeRidingAllowed (home/overworld.asm): the tilesets of
    -- bike_riding_tilesets.asm, plus Route 23 / Indigo Plateau by
    -- map id.  Reads the extracted allowlist when present.
    local function bikeAllowed()
      if not ow then return false end
      local br = game.data.field.bikeRiding
        or { tilesets = { "OVERWORLD", "FOREST", "UNDERGROUND",
                          "SHIP_PORT", "CAVERN" },
             maps = { "ROUTE_23", "INDIGO_PLATEAU" } }
      for _, m in ipairs(br.maps or {}) do
        if ow.map.id == m then return true end
      end
      for _, t in ipairs(br.tilesets or {}) do
        if ow.map.def.tileset == t then return true end
      end
      return false
    end
    if game.save.onBike then
      game.save.onBike = false
      Music.playMap(game.data, ow and ow.map.id, false)
      showMessages(game, { Strings("%s got off\nthe BICYCLE.", save_name(game)) })
    elseif bikeAllowed() then
      game.save.onBike = true
      Music.playMap(game.data, ow.map.id, true)
      showMessages(game, { Strings("%s got on\nthe BICYCLE!", save_name(game)) })
    else
      showMessages(game, { Strings("No cycling\nallowed here.") })
    end
    return
  end

  if result == "fish" then
    list:close()
    local ow = game.overworld
    local p = ow and ow.player
    if ow and p then
      local fx, fy = p:facingCell()
      if ow.map:inBounds(fx, fy) and ow.map:isWaterCell(fx, fy) then
        ow:goFishing(id)
        return
      end
    end
    showMessages(game, { Strings("No good! It's not\neven near water.") })
    return
  end

  if result == "ball" then
    if not battle then
      showMessages(game, { Strings("OAK: %s!\nThis isn't the\ntime to use that!",
                              game.save.player.name) })
      return
    end
    consume(game, id)
    list:close()
    battle:throwBall(id)
    return
  end

  if result == "learn" or result == "learnkept" then
    local moveId = payload
    local mdef = game.data.moves[moveId]
    local function teach()
      -- PIKAHAPPY_USEDTMHM on a successful teach (item_effects.asm:2500)
      local function taught()
        require("src.world.PikachuFollower")
          .modifyHappiness(game.save, "USEDTMHM", target)
      end
      if #target.moves < 4 then
        table.insert(target.moves, { id = moveId, pp = mdef.pp })
        showMessages(game, { Strings("%s learned\n%s!", target.nickname or
          game.data.pokemon[target.species].name, mdef.name) })
        if result == "learn" then consume(game, id) end
        taught()
      else
        require("src.ui.Screens").push(game, "MoveLearnMenu", target, moveId,
          function(learned)
            if learned and result == "learn" then consume(game, id) end
            if learned then taught() end
          end)
      end
    end
    list:close()
    teach()
    return
  end

  -- the TOWN MAP screen (engine/menus/town_map.asm)
  if result == "townmap" then
    local ok = pcall(function()
      require("src.ui.Screens").push(game, "TownMap")
    end)
    if not ok then
      showMessages(game, { Strings("The TOWN MAP is\nunreadable here.") })
    end
    return
  end

  -- ITEMFINDER (engine/items/itemfinder.asm): responds if the current
  -- map still has an unfound hidden item
  if result == "itemfinder" then
    local ow = game.overworld
    local t = game.data.text
    if ow and ow:hasHiddenItemLeft() then
      showMessages(game, { t._ItemfinderFoundItemText
        or Strings("Yes! ITEMFINDER\nindicates there's\nan item nearby.") })
    else
      showMessages(game, { t._ItemfinderFoundNothingText
        or Strings("Nope! ITEMFINDER\nisn't responding.") })
    end
    return
  end

  -- POKé FLUTE in battle: not consumed, but uses the turn
  if result == "flute" then
    list:close()
    require("src.core.Sound").play(game.data, "Pokeflute")
    showMessages(game, payload, function() battle:itemUsed({}) end)
    return
  end

  if result == "escape_rope" then
    -- ItemUseEscapeRope: only inside the dungeon tilesets
    -- (escape_rope_tilesets.asm), never in Agatha's room, and it sets
    -- BIT_ESCAPE_WARP so special_warps.asm warps to wLastBlackoutMap
    -- -- the last Pokémon Center town, same as Dig/Teleport (NOT the
    -- spot you entered the dungeon from)
    local ESCAPE_ROPE_TILESETS = { FOREST = true, CEMETERY = true,
                                   CAVERN = true, FACILITY = true,
                                   INTERIOR = true }
    local ow = game.overworld
    if ow and ESCAPE_ROPE_TILESETS[ow.map.def.tileset]
       and ow.map.id ~= "AGATHAS_ROOM" then
      list:close()
      consume(game, id)
      -- LeaveMapAnim spin-up + SFX_TELEPORT_EXIT_1, a fade, then land OUTSIDE
      -- the last Pokémon Center town door like Fly (#196), via the shared
      -- departure helper -- the same path Dig/Teleport take from the party menu
      ow:beginTeleportOut()
    else
      showMessages(game, { Strings(
        "OAK: %s!\nThis isn't the\ntime to use that!",
        game.save.player.name) })
    end
    return
  end

  if result == "kept" then
    if battle then
        list:close()
        showMessages(game, payload, function()
            battle:itemUsed({})
        end)
    else
        showMessages(game, payload, closePicker)
    end
    return
  end

  if result == "consumed" then
    consume(game, id)
    -- refresh counts in the list
    for i, it in ipairs(list.items) do
      if it.value == id then
        local left = game.save.inventory[id]
        if left then it.right = "x" .. left else table.remove(list.items, i) end
        break
      end
    end
    list.index = math.min(list.index, math.max(1, #list.items))
    if extra and extra.evolveTo then
      list:close()
      local Evolution = require("src.pokemon.Evolution")
      -- item_effects.asm ItemUseEvoStone sets wForceEvolution before
      -- TryEvolvingMon, so a stone evolution's B press is read and
      -- discarded (EvolutionState.lua's cancelable check).  via = "ITEM"
      -- is what makes that non-cancelable here, same as the RARE_CANDY
      -- call below; without it the stone (already consumed above) could
      -- be cancelled out from under the player (#883)
      Evolution.evolve(game, target, extra.evolveTo, nil, "ITEM")
      return
    end
    -- RARE CANDY: after the level text, the stat window, any level-up
    -- moves and a level evolution follow (item_effects.asm .useRareCandy
    -- runs PrintStatsBox, LearnMoveFromLevelUp and TryEvolvingMon)
    if extra and extra.leveledTo and target then
      -- ...but the bag stays open underneath it all: RARE_CANDY is in
      -- pokered's UsableItems_PartyMenu (data/items/use_party.asm), and
      -- .useItem_partyMenu jumps back to StartMenu_Item once UseItem
      -- returns, cursor still on the candy (start_sub_menus.asm) -- so
      -- mashing A burns through a stack of them (#796)
      showMessages(game, payload, function()
        local StatBox = require("src.battle.BattleState").StatBox
        game.stack:push(StatBox.new(game, target, function()
          local Experience = require("src.battle.Experience")
          local def = game.data.pokemon[target.species]
          local moves = Experience.movesLearnedAt(def, extra.leveledTo)
          local i = 0
          local function nextStep()
            i = i + 1
            local moveId = moves[i]
            if not moveId then
              local Evolution = require("src.pokemon.Evolution")
              local evoTo, evo = Evolution.pendingFor(game, target,
                                                     { kind = "levelup" })
              if evoTo then
                Evolution.evolve(game, target, evoTo, nil, evo and evo.method)
              end
              return
            end
            for _, mv in ipairs(target.moves) do
              if mv.id == moveId then return nextStep() end
            end
            local mdef = game.data.moves[moveId]
            if #target.moves < 4 then
              table.insert(target.moves, { id = moveId, pp = mdef.pp })
              local name = target.nickname or def.name
              showMessages(game, { Strings("%s learned\n%s!", name, mdef.name) },
                           nextStep)
            else
              require("src.ui.Screens").push(game, "MoveLearnMenu",
                                             target, moveId, nextStep)
            end
          end
          nextStep()
        end))
      end)
      return
    end
    -- HP medicine: fill the bar in the still-open picker first, then print
    -- and close, the order item_effects.asm .doneHealing runs in
    -- (SFX_HEAL_HP -> UpdateHPBar2 -> RedrawPartyMenu prints the message).
    -- Only a keepOpen picker is still on the stack to animate: every other
    -- item, and every in-battle use, popped it in PartyMenu before onSwitch,
    -- and takes the pop-then-print path below -- which is the path that
    -- spends the battle turn.  #252, #379
    if picker and picker.keepOpen and extra and extra.healedFrom and target then
      picker:animateTo(target, extra.healedFrom, function()
        showMessages(game, payload, closePicker)
      end)
      return
    end
    if battle then
      list:close()
      showMessages(game, payload, function() battle:itemUsed({}) end)
    else
      showMessages(game, payload, closePicker)
    end
    return
  end

  -- .healingItemNoEffect prints over the still-drawn party menu too, so the
  -- refusal closes the picker the same way (#252)
  showMessages(game, payload, closePicker) -- failed
end

local function pickTargetAndUse(game, battle, id, list)
  -- pick a target from the party
  -- the ETHERs and PP UP open the move menu after picking a mon
  -- (ItemUsePPRestore / ItemUsePPUp); the ELIXERs hit every move
  local wantsMove = id == "ETHER" or id == "MAX_ETHER" or id == "PP_UP"
  local def = game.data.items[id]
  local opts = {
    pickOnly = true,
    -- HP medicine animates its bar with the picker still up (#252).  Only
    -- out of battle: the in-battle tail closes the bag list underneath
    -- first, which needs the picker already gone.
    keepOpen = (not battle) and ItemEffects.healsHP(id),
    onSwitch = function(mon, picker)
      if not wantsMove then
        useOn(game, battle, id, mon, list, nil, picker)
        return
      end
      local rows = {}
      for mi, mv in ipairs(mon.moves) do
        local mdef = game.data.moves[mv.id]
        table.insert(rows, {
          value = mi,
          label = mdef and mdef.name or mv.id,
          right = ("%d"):format(mv.pp),
        })
      end
      game.stack:push(ListMenu.new(game, "Which move?", rows, {
        onChoose = function(row, l)
          l:close()
          useOn(game, battle, id, mon, list, row.value)
        end,
      }))
    end,
  }
  -- TM/HM: open the party menu in Gen 1's TM/HM display mode so each mon
  -- shows ABLE / NOT ABLE from its learnset and the prompt reads "Use TM on
  -- which POKeMON?" (engine/items/item_effects.asm ItemUseTMHM ->
  -- party_menu.asm TM/HM type). Stones and other pickOnly items keep the
  -- plain HP layout (Gen 1 shows no ABLE/NOT ABLE for them), so gate
  -- strictly on def.machine. #210
  if def and def.machine then
    opts.tmhm = { move = def.machine.move, kind = def.machine.kind }
  end
  require("src.ui.Screens").push(game, "PartyMenu", opts)
end

local function useItem(game, battle, id, list)
  local def = game.data.items[id]
  -- ItemUseTMHM checks wIsInBattle before BootedUpTMText
  if battle and def and def.machine then
    local _, payload = ItemEffects.use(game.data, game.save, id, nil, battle)
    showMessages(game, payload)
    return
  end
  if ItemEffects.needsTarget(id, def, game.data) and not ItemEffects.isBall(id) then
    -- TMs/HMs boot up and announce their move before the target picker
    -- (ItemUseTMHM: BootedUpTMText / BootedUpHMText + TeachMachineMoveText)
    if def and def.machine then
      local moveDef = game.data.moves[def.machine.move]
      local moveName = moveDef and moveDef.name or def.machine.move
      local booted = def.machine.kind == "HM"
        and "Booted up an HM!" or Strings("Booted up a TM!")
      showMessages(game, { booted, Strings("It contained\n%s!", moveName) },
        function() pickTargetAndUse(game, battle, id, list) end)
      return
    end
    pickTargetAndUse(game, battle, id, list)
  else
    useOn(game, battle, id, nil, list)
  end
end

function BagMenu.new(game, opts)
  opts = opts or {}
  local battle = opts.battle
  local crystal = GameVersion.isCrystal()
  local pocketIndex = math.max(1, math.min(game.save.bagPocketIndex or 1, #CRYSTAL_POCKETS))
  local function currentPocket()
    return crystal and CRYSTAL_POCKETS[pocketIndex] or nil
  end
  local function title()
    local pocket = currentPocket()
    return pocket and pocket.title or "ITEMS"
  end
  local list
  local function refreshItems()
    list.items = buildItems(game, currentPocket() and currentPocket().id or nil)
    list.title = title()
    list.footer = ("¥%d"):format(game.save.money)
    list.index = math.min(list.index, math.max(1, #list.items))
    list.scroll = math.min(list.scroll, math.max(0, #list.items - list.rows))
  end
  list = ListMenu.new(game, title(), buildItems(game, currentPocket() and currentPocket().id or nil), {
    kind = "bag",
    footer = crystal and nil or ("¥%d"):format(game.save.money),
    rows = crystal and 5 or nil,
    -- B returns to the start menu when the bag was opened from it
    onCancel = opts.onCancel,
    -- SELECT reorders items like the original bag (swap_items.asm)
    onSelectKey = function(item, l)
      if not item then return end
      if not l.swapIndex then
        l.swapIndex = l.index
        return
      end
      local from = l.items[l.swapIndex] and l.items[l.swapIndex].value
      local to = l.items[l.index] and l.items[l.index].value
      Bag.swap(game.save, from, to)
      l.swapIndex = nil
      require("src.core.Sound").play(game.data, "Swap")
      refreshItems()
    end,
    onChoose = function(item)
      local id = item.value
      local def = game.data.items[id]
      if list.swapIndex then -- A also completes a pending swap
        local from = list.items[list.swapIndex] and list.items[list.swapIndex].value
        local to = list.items[list.index] and list.items[list.index].value
        Bag.swap(game.save, from, to)
        list.swapIndex = nil
        require("src.core.Sound").play(game.data, "Swap")
        refreshItems()
        return
      end
      if battle then -- no tossing mid-battle
        useItem(game, battle, id, list)
        return
      end
      -- USE / TOSS submenu (the original's item options).
      -- data/text_boxes.asm USE_TOSS_MENU_TEMPLATE: box (13,10)-(19,14),
      -- text at (15,11); start_sub_menus.asm then sets wTopMenuItemY/X to
      -- 11/14 for the cursor.  Menu's own geometry reproduces all of that
      -- from the box alone, so this needs opts rather than a change to the
      -- shared Menu.  The old 12/10/8/6 box was a column too wide and a row
      -- too tall, which left the labels stranded near its top edge (#284).
      local Menu = require("src.ui.Menu")
      game.stack:push(Menu.new(game, {
        { label = Strings("USE"), onSelect = function()
            useItem(game, battle, id, list)
          end },
        { label = Strings("TOSS"), onSelect = function()
            if not def or def.tossable == false then
              showMessages(game, { Strings("That's too impor-\ntant to toss!") })
              return
            end
            local QuantityBox = require("src.ui.QuantityBox")
            game.stack:push(QuantityBox.new(game, {
              max = game.save.inventory[id] or 1,
              onDone = function(qty)
                if not qty then return end
                local ChoiceBox = require("src.ui.ChoiceBox")
                game.stack:push(ChoiceBox.new(game, function(yes)
                  if not yes then return end
                  Bag.remove(game.save, id, qty)
                  refreshItems()
                  showMessages(game, { Strings("Threw away\n%s.", def and def.name or id) })
                end))
              end,
            }))
          end },
      }, { tx = 13, ty = 10, tw = 7, th = 5 }))
    end,
  })
  if crystal then
    local baseUpdate = list.update
    local packPath = game.save.player and game.save.player.gender == "girl"
      and "roms/pokecrystal/gfx/pack/pack_f.png"
      or "roms/pokecrystal/gfx/pack/pack.png"
    local packPals = loadPackPals(
      game.save.player and game.save.player.gender == "girl"
      and PACK_F_PAL_PATH or PACK_PAL_PATH)
    local function pocketLabel(i, pocket)
      if i == pocketIndex then
        return "[" .. pocket.title .. "]"
      end
      return pocket.title
    end
    local function pocketDescription(item)
      if not item then
        return Strings("There's nothing\nhere.")
      end
      local def = game.data.items[item.value] or {}
      if def.machine then
        local move = def.machine.move or ""
        local kind = def.machine.kind or "TM"
        return Strings("%s teaches\n%s.", kind, move)
      end
      local pocket = Bag.pocketOf(game.data, item.value, def)
      if pocket == "KEY_ITEM" then
        return Strings("An important item\nkept in the PACK.")
      elseif pocket == "BALL" then
        return Strings("A BALL pocket\nitem.")
      end
      return Strings("Stored in the\nPACK.")
    end
    local function drawCrystalBag(self)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      withPackPalette(packPals and packPals[1], function()
        for y = 1, 11 do
          for x = 0, 19 do
            drawPackMenuTile(0x24, x * 8, y * 8)
          end
        end
      end)
      withPackPalette(packPals and packPals[2], function()
        for x = 0, 9 do
          drawPackMenuTile(0x28 + x, x * 8, 0)
        end
      end)
      withPackPalette(packPals and packPals[3], function()
        for x = 10, 19 do
          drawPackMenuTile(0x28 + x, x * 8, 0)
        end
      end)
      withPackPalette(packPals and packPals[4], function()
        for y = 2, 10 do
          drawPackMenuTile(0x24, 56, y * 8)
        end
      end)
      withPackPalette(packPals and packPals[5], function()
        local tileRow = PACK_TILEMAP[pocketIndex] or PACK_TILEMAP[1]
        for row = 0, 2 do
          for col = 0, 4 do
            drawPackMenuTile(tileRow[row * 5 + col + 1], col * 8, (7 + row) * 8)
          end
        end
      end)
      love.graphics.rectangle("fill", 40, 8, 120, 88)

      local pack = Assets.image(packPath)
      local quad = nil
      if love.graphics.newQuad then
        quad = love.graphics.newQuad(0, (pocketIndex - 1) * 24, 40, 24, pack:getDimensions())
      end
      if quad then
        withPackPalette(packPals and packPals[6], function()
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(pack, quad, 0, 24)
        end)
      end

      love.graphics.setColor(0, 0, 0, 1)
      local lineY = 16
      for row = 1, self.rows do
        local i = self.scroll + row
        local item = self.items[i]
        if not item then break end
        local y = lineY + (row - 1) * 16
        Font.draw(item.label, 64, y)
        if item.right then
          Font.draw(item.right, 152 - Font.width(item.right), y)
        end
        if i == self.index then
          Font.drawCode((self.swapIndex == i or self.hollowIndex == i)
            and Theme.cursorHollow or Theme.cursor, 56, y)
        end
      end

      Font.drawBox(0, 12, 20, 6)
      local desc = pocketDescription(self.items[self.index])
      local flat = {}
      for _, page in ipairs(require("src.render.TextBox").paginate(desc)) do
        for _, line in ipairs(page) do flat[#flat + 1] = line end
      end
      local y = 112
      for i = math.max(1, #flat - 1), #flat do
        Font.draw(flat[i], 8, y)
        y = y + 16
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    local function switchPocket(delta)
      pocketIndex = ((pocketIndex - 1 + delta) % #CRYSTAL_POCKETS) + 1
      game.save.bagPocketIndex = pocketIndex
      list.swapIndex = nil
      list.index, list.scroll = 1, 0
      refreshItems()
    end
    list.draw = drawCrystalBag
    list.update = function(self, dt)
      local input = self.game.input
      if input:wasPressed("left") then
        switchPocket(-1)
        return
      elseif input:wasPressed("right") then
        switchPocket(1)
        return
      end
      baseUpdate(self, dt)
    end
  end
  return list
end

return BagMenu
