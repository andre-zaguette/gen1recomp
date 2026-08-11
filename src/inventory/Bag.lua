-- The bag defaults to 20 slots (BAG_ITEM_CAPACITY,
-- constants/menu_constants.asm), but mods may replace that limit through
-- Data.constants.bagSize.  A distinct item id occupies one slot regardless
-- of quantity; badges live in the inventory table but are not bag items.
-- save.bagOrder keeps acquisition order like wBagItems (SELECT can reorder
-- it).

local Bag = {}

local DEFAULT_CAPACITY = 20
local CRYSTAL_CAPACITY = {
  ITEM = 20,
  BALL = 12,
  KEY_ITEM = 25,
}

local function isCrystal()
  return require("src.core.GameVersion").isCrystal()
end

local function itemDef(data, id)
  return data and data.items and data.items[id] or nil
end

function Bag.pocketOf(data, id, def)
  def = def or itemDef(data, id) or {}
  if type(def.pocket) == "string" and def.pocket ~= "" then
    return def.pocket
  end
  if def.machine then return "TM_HM" end
  if def.keyItem then return "KEY_ITEM" end
  if def.ball or require("src.inventory.ItemEffects").isBall(id) then
    return "BALL"
  end
  return "ITEM"
end

-- `data` is injectable for the save editor and headless mod tests.  Normal
-- gameplay may omit it because the loader merges mods into the Data
-- singleton before any item can be added.  The fallback keeps old/stale
-- generated caches and isolated callers at the vanilla limit.
function Bag.capacity(data, pocket)
  data = data or require("src.core.Data")
  if pocket and isCrystal() then
    return CRYSTAL_CAPACITY[pocket] or math.huge
  end
  local configured = data and data.constants and data.constants.bagSize
  if type(configured) == "number" and configured >= 1 then
    return math.floor(configured)
  end
  return DEFAULT_CAPACITY
end

local function isBadge(id)
  return id:find("BADGE", 1, true) ~= nil
end

-- exported so item lists that share save.inventory (e.g. the PC deposit
-- menu) can exclude badges the same way the bag does
Bag.isBadge = isBadge

function Bag.slots(save, data, pocket)
  local n = 0
  for id, qty in pairs(save.inventory) do
    if qty and not isBadge(id)
       and (not pocket or Bag.pocketOf(data, id) == pocket) then
      n = n + 1
    end
  end
  return n
end

-- Acquisition-ordered id list (wBagItems).  Rebuilt sorted once for
-- saves from before the order existed, then maintained incrementally.
function Bag.order(save, data, pocket)
  local order = save.bagOrder
  if not order then
    order = {}
    for id in pairs(save.inventory) do
      if not isBadge(id) then table.insert(order, id) end
    end
    table.sort(order)
    save.bagOrder = order
  end
  -- drop stale ids, append unknown ones (defensive against direct
  -- inventory writes)
  local seen = {}
  for i = #order, 1, -1 do
    local id = order[i]
    if not save.inventory[id] or seen[id] then
      table.remove(order, i)
    else
      seen[id] = true
    end
  end
  for id in pairs(save.inventory) do
    if not isBadge(id) and not seen[id] then table.insert(order, id) end
  end
  if not pocket then return order end
  local filtered = {}
  for _, id in ipairs(order) do
    if Bag.pocketOf(data, id) == pocket then
      filtered[#filtered + 1] = id
    end
  end
  return filtered
end

function Bag.swap(save, idA, idB)
  if not idA or not idB or idA == idB then return end
  local order = Bag.order(save)
  local aIndex, bIndex
  for i, id in ipairs(order) do
    if id == idA and not aIndex then aIndex = i end
    if id == idB and not bIndex then bIndex = i end
  end
  if aIndex and bIndex then
    order[aIndex], order[bIndex] = order[bIndex], order[aIndex]
  end
end

-- Add qty of an item; returns false (and adds nothing) when a new slot
-- is needed and the bag is full, or when the stack would pass 99
-- (AddItemToInventory's per-slot quantity cap).
function Bag.add(save, id, qty, data)
  local inv = save.inventory
  local pocket = Bag.pocketOf(data, id)
  local cap = Bag.capacity(data, pocket)
  if not inv[id] and not isBadge(id)
      and cap < math.huge and Bag.slots(save, data, pocket) >= cap then
    return false
  end
  if pocket == "KEY_ITEM" and isCrystal() then
    local isNew = not inv[id]
    inv[id] = 1
    if isNew and not isBadge(id) then
      table.insert(Bag.order(save), id)
    end
    return true
  end
  if not isBadge(id) and (inv[id] or 0) + (qty or 1) > 99 then
    return false
  end
  local isNew = not inv[id]
  inv[id] = (inv[id] or 0) + (qty or 1)
  if isNew and not isBadge(id) then
    table.insert(Bag.order(save), id)
  end
  return true
end

-- Remove qty (default 1); clears the slot and its order entry at zero.
function Bag.remove(save, id, qty)
  local inv = save.inventory
  inv[id] = (inv[id] or 0) - (qty or 1)
  if inv[id] <= 0 then
    inv[id] = nil
    local order = save.bagOrder
    if order then
      for i, oid in ipairs(order) do
        if oid == id then table.remove(order, i) break end
      end
    end
  end
end

return Bag
