package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Bag = require("src.inventory.Bag")
local BagMenu = require("src.ui.BagMenu")
local GameVersion = require("src.core.GameVersion")
local StartMenu = require("src.ui.StartMenu")

local oldVersion = GameVersion.get()
GameVersion.set("crystal")

local data = {
  items = {
    POTION = { id = "POTION", name = "POTION", pocket = "ITEM", tossable = true },
    ANTIDOTE = { id = "ANTIDOTE", name = "ANTIDOTE", pocket = "ITEM", tossable = true },
    POKE_BALL = { id = "POKE_BALL", name = "POKe BALL", pocket = "BALL", tossable = true },
    GREAT_BALL = { id = "GREAT_BALL", name = "GREAT BALL", pocket = "BALL", tossable = true },
    BICYCLE = { id = "BICYCLE", name = "BICYCLE", pocket = "KEY_ITEM", tossable = false },
    COIN_CASE = { id = "COIN_CASE", name = "COIN CASE", pocket = "KEY_ITEM", tossable = false },
    TM_CUT = {
      id = "TM_CUT", name = "TM01", pocket = "TM_HM", tossable = true,
      machine = { kind = "TM", number = 1, move = "CUT" },
    },
    HM_CUT = {
      id = "HM_CUT", name = "HM01", pocket = "TM_HM", tossable = false,
      machine = { kind = "HM", number = 1, move = "CUT" },
    },
  },
}

local save = {
  inventory = {
    POTION = 2,
    POKE_BALL = 5,
    BICYCLE = 1,
    TM_CUT = 2,
    HM_CUT = 1,
  },
  bagOrder = { "POTION", "POKE_BALL", "BICYCLE", "TM_CUT", "HM_CUT" },
  money = 3000,
  party = {},
  flags = {},
  player = { name = "CRIS" },
}

T.eq(Bag.capacity(data, "ITEM"), 20, "Crystal items pocket keeps the 20-slot cap")
T.eq(Bag.capacity(data, "BALL"), 12, "Crystal balls pocket keeps the 12-slot cap")
T.eq(Bag.capacity(data, "KEY_ITEM"), 25, "Crystal key-item pocket keeps the 25-slot cap")
T.check(Bag.capacity(data, "TM_HM") > 1000, "Crystal TM/HM pocket has no practical slot cap")

local ballOrder = Bag.order(save, data, "BALL")
T.eq(#ballOrder, 1, "BALL pocket filters the bag order")
T.eq(ballOrder[1], "POKE_BALL", "BALL pocket keeps only ball items")

local keyOrder = Bag.order(save, data, "KEY_ITEM")
T.eq(#keyOrder, 1, "KEY ITEM pocket filters the bag order")
T.eq(keyOrder[1], "BICYCLE", "KEY ITEM pocket keeps only key items")

local tmOrder = Bag.order(save, data, "TM_HM")
T.eq(#tmOrder, 2, "TM/HM pocket filters the bag order")
T.eq(tmOrder[1], "TM_CUT", "TM/HM pocket keeps TM entries")
T.eq(tmOrder[2], "HM_CUT", "TM/HM pocket keeps HM entries")

do
  local capSave = { inventory = {}, bagOrder = {} }
  for i = 1, 20 do
    local id = "ITEM_" .. i
    data.items[id] = { id = id, name = id, pocket = "ITEM", tossable = true }
    T.check(Bag.add(capSave, id, 1, data), "Crystal item pocket accepts slot " .. i)
  end
  data.items.ITEM_21 = { id = "ITEM_21", name = "ITEM_21", pocket = "ITEM", tossable = true }
  T.check(not Bag.add(capSave, "ITEM_21", 1, data),
    "Crystal item pocket refuses a 21st distinct item")
  T.check(Bag.add(capSave, "POKE_BALL", 1, data),
    "Crystal balls pocket remains independent from the items pocket")
end

do
  local stack = { top = function() end, pop = function() end, push = function() end }
  local pressed = {}
  local game = {
    data = data,
    save = save,
    stack = stack,
    input = {
      wasPressed = function(_, key) return pressed[key] or false end,
      isDown = function() return false end,
    },
  }
  local menu = BagMenu.new(game, {})
  T.eq(menu.title, "ITEMS", "Crystal bag opens on the items pocket")
  T.eq(menu.items[1].value, "POTION", "Crystal items pocket shows only regular items first")

  pressed = { right = true }
  menu:update(0)
  T.eq(menu.title, "BALLS", "Right switches the Crystal bag to balls")
  T.eq(#menu.items, 1, "BALLS pocket shows only ball entries")
  T.eq(menu.items[1].value, "POKE_BALL", "BALLS pocket filters correctly")

  pressed = { right = true }
  menu:update(0)
  T.eq(menu.title, "KEY ITEMS", "Right switches the Crystal bag to key items")
  T.eq(menu.items[1].value, "BICYCLE", "KEY ITEMS pocket filters correctly")

  pressed = { right = true }
  menu:update(0)
  T.eq(menu.title, "TM/HM", "Right switches the Crystal bag to TM/HM")
  T.eq(#menu.items, 2, "TM/HM pocket shows both TMs and HMs")

  pressed = { left = true }
  menu:update(0)
  T.eq(menu.title, "KEY ITEMS", "Left cycles back to the previous pocket")
end

do
  local game = {
    data = data,
    save = save,
    stack = { push = function() end },
    overworld = nil,
  }
  local menu = StartMenu.new(game)
  T.eq(menu.items[2].label, "PACK", "Crystal start menu says PACK instead of ITEM")
end

GameVersion.set(oldVersion)
T.finish("Gen2 Crystal bag pockets")
