-- Shiny Pokemon: Gen2 DV shinies with recolored pics and a one-shot
-- sparkle intro (battle + 2D overworld) with SFX. Compatible with Wilds
-- of Kanto + PokéPC Followers (optional).

return function(mod)
  local Stats = require("src.pokemon.Stats")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local PaletteFX = require("src.render.PaletteFX")
  local Sprites = require("src.pokemon.Sprites")
  local Assets = require("src.render.Assets")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local Sound = require("src.core.Sound")
  local Game = require("src.core.Game")
  local Font = require("src.render.Font")
  local PartyMenu = require("src.ui.PartyMenu")
  local SummaryMenu = require("src.ui.SummaryMenu")

  local MOD_ID = "SHINY_POKEMON"
  local INTRO_SECONDS = 1.35
  -- Overworld shinies replay the sparkle burst on this cadence (seconds).
  local OW_SPARKLE_INTERVAL = 2.8
  local SHINY_SFX = "Dex_Page_Added"
  -- Amortize ImageData sheet bakes so map enter + voxel rebuild stay smooth.
  local OW_BAKES_PER_FRAME = 1
  local owBakeQueue = {}
  local owBakeJobs = {} -- key -> job still in queue
  local owMapSfxPlayed = false
  local owSfxLastAt = 0
  local OW_SFX_DEBOUNCE = 0.6

  local RATE_DENOM = {
    off = nil,
    gen2 = 8192,
    modern = 4096,
    common = 1024,
    frequent = 512,
    often = 100,
    high = 10,
    always = 0,
  }

  local SHINY_ATK = { 2, 3, 6, 7, 10, 11, 14, 15 }

  local function readOpt(key, default)
    local ok, got = pcall(mod.options.get, mod.options, key)
    if ok and got ~= nil then return got end
    return default
  end

  local cache = {}
  local function opt(key, default)
    if cache[key] ~= nil then return cache[key] end
    cache[key] = readOpt(key, default)
    return cache[key]
  end

  local function enabled()
    return opt("enabled", true) and true or false
  end

  local function rateKey()
    local raw = opt("shiny_rate", "modern")
    if raw == true or raw == 1 then return "always" end
    local key = tostring(raw or "modern"):lower()
    -- Accept labels / aliases from older saves or UI quirks.
    if key == "always" or key == "100%" or key:find("100", 1, true)
       or key:find("always", 1, true) then
      return "always"
    end
    if RATE_DENOM[key] ~= nil or key == "off" then return key end
    return "modern"
  end

  local function rateAlways()
    return rateKey() == "always"
  end

  local function sparklesOn()
    return opt("sparkles", true) and true or false
  end

  local function recolorOn()
    return opt("recolor", true) and true or false
  end

  local function debugOwOn()
    return opt("debug_ow", true) and true or false
  end

  -- Counters for the DEBUG OW overlay / log file.
  local dbg = {
    bakeOk = 0, bakeFail = 0, lastBakeErr = "",
    assetsHits = 0, resolveHits = 0, redrawHits = 0,
    lastPath = "", wrapMake = false, version = "1.0.1",
  }

  -- Official Gen 2 Crystal shiny mid-colors (pret/pokecrystal shiny.pal).
  local OFFICIAL_SHINY = {}
  do
    local src = mod:read("shiny_palettes.lua")
    if type(src) == "string" and src ~= "" then
      local loader = loadstring or load
      local chunk = loader(src, "@shiny_palettes.lua")
      if chunk then
        local ok, t = pcall(chunk)
        if ok and type(t) == "table" then OFFICIAL_SHINY = t end
      end
    end
    -- Common id aliases used by Gen1 data / follower filenames.
    if OFFICIAL_SHINY.FARFETCHD then
      OFFICIAL_SHINY.FARFETCH_D = OFFICIAL_SHINY.FARFETCHD
    end
    if OFFICIAL_SHINY.MR_MIME then
      OFFICIAL_SHINY.MR__MIME = OFFICIAL_SHINY.MR_MIME
    end
  end

  local function officialPair(species)
    if not species then return nil end
    local key = tostring(species):upper():gsub("[^%w_]", "_")
    local pair = OFFICIAL_SHINY[key] or OFFICIAL_SHINY[tostring(species)]
    if type(pair) ~= "table" or type(pair[1]) ~= "table" or type(pair[2]) ~= "table" then
      return nil
    end
    return pair[1], pair[2]
  end

  local function speciesFromPath(path, fallback)
    if type(path) == "string" then
      local sp = path:match("follower_([%w_]+)%.png")
      if sp then return sp end
    end
    return fallback
  end

  mod.options:define({
    {
      key = "enabled", type = "toggle", label = "SHINY POKEMON",
      default = true,
      help = "Roll shinies, recolor pics, and play the shiny intro.",
    },
    {
      key = "shiny_rate", type = "choice", label = "SHINY RATE",
      default = "modern",
      choices = {
        { "OFF", "off" },
        { "1/8192 (Gen 2)", "gen2" },
        { "1/4096 (Modern)", "modern" },
        { "1/1024", "common" },
        { "1/512", "frequent" },
        { "1/100", "often" },
        { "1/10", "high" },
        { "100% (Always)", "always" },
      },
      help = "Chance a newly created wild Pokemon is shiny.",
    },
    {
      key = "recolor", type = "toggle", label = "SHINY COLORS",
      default = true,
      help = "Apply official Gen 2 shiny colors (Crystal palettes) to battle and overworld art.",
    },
    {
      key = "sparkles", type = "toggle", label = "SHINY INTRO",
      default = true,
      help = "One-shot sparkle when a shiny appears (battle plays SFX; party follower is visual-only).",
    },
    {
      key = "debug_ow", type = "toggle", label = "DEBUG OW",
      default = false,
      help = "On-screen OW diagnostics + neon-green force recolor. Leave OFF for normal shiny colors.",
    },
  })

  mod.events:on("mod.options_changed", function(payload)
    if payload and payload.mod == mod.id then cache = {} end
  end)

  local function now()
    if love and love.timer and love.timer.getTime then
      return love.timer.getTime()
    end
    return os.clock()
  end

  local function rngFn(rng)
    if type(rng) == "function" then return rng end
    if love and love.math and love.math.random then return love.math.random end
    return math.random
  end

  local function makeShinyDVs(rng)
    rng = rngFn(rng)
    local atk = SHINY_ATK[rng(#SHINY_ATK)]
    local dvs = {
      attack = atk,
      defense = 10,
      speed = 10,
      special = 10,
    }
    dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
           + (dvs.speed % 2) * 2 + (dvs.special % 2)
    return dvs
  end

  local function rollShiny(rng)
    if not enabled() then return false end
    local key = rateKey()
    if key == "off" then return false end
    if key == "always" then return true end
    local denom = RATE_DENOM[key]
    if denom == nil then return false end
    if denom <= 1 then return true end
    rng = rngFn(rng)
    -- love.math.random(n) / math.random(n) => 1..n
    local roll = rng(denom)
    return roll == 1
  end

  local function isShinyMon(mon)
    if not mon then return false end
    if mon.shiny then return true end
    return Stats.isShiny(mon.dvs)
  end

  local function applyShinyToMon(mon, data, dvs)
    if not mon then return mon end
    mon.dvs = dvs
    mon.shiny = true
    local def = data and data.pokemon and data.pokemon[mon.species]
    if def and def.baseStats then
      mon.stats = Stats.calc(def, mon.level or 1, dvs, mon.statExp)
      mon.hp = mon.stats.hp
    end
    return mon
  end

  -- OW contact battles set this before queueScript; Pokemon.new consumes it.
  -- Shape: nil | { dvs = table } | { none = true }
  -- Never use a bare `false` sentinel — a stuck false forced every later
  -- wild to be non-shiny and looked like "100% rate broken".
  local pendingWild = nil
  local wildRollActive = false

  local function clearPendingWild()
    pendingWild = nil
  end

  local origNew = Pokemon.new
  function Pokemon.new(data, species, level, rng)
    local mon = origNew(data, species, level, rng)
    local pending = pendingWild
    if pending ~= nil then
      pendingWild = nil
      if pending.dvs then
        return applyShinyToMon(mon, data, pending.dvs)
      end
      -- pending.none: this OW wild was rolled non-shiny. Still honor 100%.
      if rateAlways() then
        return applyShinyToMon(mon, data, makeShinyDVs(rng))
      end
      mon.shiny = false
      return mon
    end
    if wildRollActive and rollShiny(rng) then
      return applyShinyToMon(mon, data, makeShinyDVs(rng))
    end
    if Stats.isShiny(mon.dvs) then
      mon.shiny = true
    end
    return mon
  end

  local origNewWild = BattleState.newWild
  function BattleState.newWild(game, species, level, opts)
    wildRollActive = true
    local ok, result = pcall(origNewWild, game, species, level, opts)
    wildRollActive = false
    if not ok then
      clearPendingWild()
      error(result, 0)
    end
    -- Belt-and-suspenders: 100% must win even if an earlier pending.none
    -- or a missed wrap left a non-shiny enemy.
    if result and result.enemy and result.enemy.mon and enabled() and rateAlways()
       and not isShinyMon(result.enemy.mon) then
      applyShinyToMon(result.enemy.mon, game.data, makeShinyDVs())
      result.enemy._shinySpriteApplied = false
      result.enemy.shiny = true
    end
    clearPendingWild()
    return result
  end

  -- ------- color bake

  local function clampByte(n)
    if n < 0 then return 0 end
    if n > 255 then return 255 end
    return math.floor(n + 0.5)
  end

  local function rgbToHsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local h, s, v = 0, 0, max
    local d = max - min
    if max ~= 0 then s = d / max end
    if d ~= 0 then
      if max == r then
        h = (g - b) / d + (g < b and 6 or 0)
      elseif max == g then
        h = (b - r) / d + 2
      else
        h = (r - g) / d + 4
      end
      h = h / 6
    end
    return h, s, v
  end

  local function hsvToRgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local r, g, b
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return clampByte(r * 255), clampByte(g * 255), clampByte(b * 255)
  end

  local function shiftColor(col, hueShift, satBoost)
    local r = col[1] or col.r or 0
    local g = col[2] or col.g or 0
    local b = col[3] or col.b or 0
    local h, s, v = rgbToHsv(r, g, b)
    if s < 0.08 and v > 0.92 then
      return { r, g, b }
    end
    -- Soft push for battle palette remaps (4-shade sheets).
    if s < 0.18 then
      h = (h + (hueShift or 0.5)) % 1
      s = math.min(0.55, s + 0.25)
      v = math.min(1, v * 1.03)
    else
      h = (h + (hueShift or 0.5)) % 1
      s = math.min(1, s * (satBoost or 1.35) + 0.08)
    end
    local nr, ng, nb = hsvToRgb(h, s, v)
    return { nr, ng, nb }
  end

  -- Truecolor OW follower sheets: preserve outlines / shadows; only rotate
  -- chromatic pixels. The old path forced sat=0.7 on darks → neon green sludge.
  local function shiftColorOw(col, hueShift, satBoost)
    local r = col[1] or col.r or 0
    local g = col[2] or col.g or 0
    local b = col[3] or col.b or 0
    local h, s, v = rgbToHsv(r, g, b)
    if v < 0.14 or s < 0.14 then
      return { r, g, b }
    end
    if s < 0.08 and v > 0.92 then
      return { r, g, b }
    end
    h = (h + (hueShift or 0.20)) % 1
    s = math.min(0.95, s * (satBoost or 1.2) + 0.04)
    v = math.min(1, v * 1.03)
    local nr, ng, nb = hsvToRgb(h, s, v)
    return { nr, ng, nb }
  end

  local function shinyPaletteColors(baseColors, species)
    local light, dark = officialPair(species)
    if light and dark then
      local black = { 48, 40, 32 }
      if type(baseColors) == "table" and type(baseColors[4]) == "table" then
        black = {
          baseColors[4][1] or 0,
          baseColors[4][2] or 0,
          baseColors[4][3] or 0,
        }
      end
      return {
        { 255, 255, 255 },
        { light[1], light[2], light[3] },
        { dark[1], dark[2], dark[3] },
        black,
      }
    end
    if type(baseColors) ~= "table" then
      return {
        { 255, 255, 255 },
        { 255, 214, 64 },
        { 232, 120, 32 },
        { 48, 40, 32 },
      }
    end
    local out = {}
    for i = 1, 4 do
      local c = baseColors[i] or { 0, 0, 0 }
      if i == 1 then
        out[i] = { c[1] or 255, c[2] or 255, c[3] or 255 }
      else
        out[i] = shiftColor(c, 0.5, 1.45)
      end
    end
    return out
  end

  local shinyImageCache = {}

  local function bakeShadedImage(path, colors, cacheKey)
    if shinyImageCache[cacheKey] then return shinyImageCache[cacheKey] end
    if not (love and love.image and love.image.newImageData) then
      return Assets.image(path)
    end
    local ok, imgOrErr = pcall(function()
      local id = Assets.imageData(path)
      local c = colors
      id:mapPixel(function(_, _, r, g, b, a)
        if a == 0 then return r, g, b, a end
        if r > 0.92 and g > 0.92 and b > 0.92 then return 1, 1, 1, 0 end
        local col = r > 0.83 and c[1] or r > 0.5 and c[2]
                    or r > 0.17 and c[3] or c[4]
        return col[1] / 255, col[2] / 255, col[3] / 255, a
      end)
      local img = love.graphics.newImage(id)
      if img.setFilter then img:setFilter("nearest", "nearest") end
      return img
    end)
    if not ok or not imgOrErr then return nil end
    shinyImageCache[cacheKey] = imgOrErr
    return imgOrErr
  end

  -- Truecolor sheets: classify opaque body pixels by luma into light/dark
  -- mids and paint with official Crystal shiny RGB. Outlines stay black.
  local function bakeOfficialImage(path, species, cacheKey)
    local light, dark = officialPair(species)
    if not light then return nil end
    local neon = debugOwOn()
    cacheKey = tostring(cacheKey) .. ":official:" .. tostring(species)
      .. (neon and ":neon" or "")
    if shinyImageCache[cacheKey] then return shinyImageCache[cacheKey] end
    if not (love and love.image and love.image.newImageData) then
      dbg.bakeFail = dbg.bakeFail + 1
      dbg.lastBakeErr = "no ImageData"
      return nil
    end
    local ok, imgOrErr = pcall(function()
      local id = Assets.imageData(path)
      local byte = false
      local iw, ih = id:getWidth(), id:getHeight()
      for y = 0, math.min(ih - 1, 15) do
        for x = 0, math.min(iw - 1, 15) do
          local pr, pg, pb, pa = id:getPixel(x, y)
          if pr > 1 or pg > 1 or pb > 1 or (pa and pa > 1) then
            byte = true
            break
          end
        end
        if byte then break end
      end
      -- First pass: median luma of chromatic body pixels for light/dark split.
      local lumas = {}
      id:mapPixel(function(_, _, r, g, b, a)
        local transparent = (byte and a < 1) or ((not byte) and a < 0.001)
        if transparent then return r, g, b, a end
        local R = byte and (r / 255) or r
        local G = byte and (g / 255) or g
        local B = byte and (b / 255) or b
        if R < 0.08 and G < 0.08 and B < 0.08 then return r, g, b, a end
        if R > 0.92 and G > 0.92 and B > 0.92 then return r, g, b, a end
        lumas[#lumas + 1] = 0.299 * R + 0.587 * G + 0.114 * B
        return r, g, b, a
      end)
      table.sort(lumas)
      local split = 0.55
      if #lumas > 0 then
        split = lumas[math.max(1, math.floor(#lumas * 0.55))]
      end
      id:mapPixel(function(_, _, r, g, b, a)
        if (byte and a < 1) or ((not byte) and a < 0.001) then
          return r, g, b, a
        end
        local R = byte and (r / 255) or r
        local G = byte and (g / 255) or g
        local B = byte and (b / 255) or b
        -- Opaque black outline / shadow.
        if R < 0.08 and G < 0.08 and B < 0.08 then
          return r, g, b, a
        end
        if neon then
          if byte then return 40, 255, 40, a end
          return 0.15, 1.0, 0.15, a
        end
        -- Near-white highlights stay white.
        if R > 0.92 and G > 0.92 and B > 0.92 then
          if byte then return 255, 255, 255, a end
          return 1, 1, 1, a
        end
        local luma = 0.299 * R + 0.587 * G + 0.114 * B
        local col = luma >= split and light or dark
        if byte then
          return col[1], col[2], col[3], a
        end
        return col[1] / 255, col[2] / 255, col[3] / 255, a
      end)
      local img = love.graphics.newImage(id)
      if img.setFilter then img:setFilter("nearest", "nearest") end
      return img
    end)
    if not ok or not imgOrErr then
      dbg.bakeFail = dbg.bakeFail + 1
      dbg.lastBakeErr = tostring(imgOrErr)
      dbg.lastPath = tostring(path)
      return nil
    end
    dbg.bakeOk = dbg.bakeOk + 1
    dbg.lastPath = tostring(path)
    shinyImageCache[cacheKey] = imgOrErr
    return imgOrErr
  end

  local function bakeHueShiftImage(path, cacheKey, hue, sat)
    local neon = debugOwOn()
    -- :huev7 = never touch alpha. Follower sheets use opaque black OUTLINES
    -- (a=255,rgb=0); keying those to clear punched holes in every sprite.
    cacheKey = tostring(cacheKey) .. (neon and ":neon" or ":huev7")
    if shinyImageCache[cacheKey] then return shinyImageCache[cacheKey] end
    if not (love and love.image and love.image.newImageData) then
      dbg.bakeFail = dbg.bakeFail + 1
      dbg.lastBakeErr = "no ImageData"
      return nil
    end
    -- ~180° reads as classic shiny on many Gen1 browns/purples (gold/green).
    hue = hue or 0.50
    sat = sat or 1.15
    local ok, imgOrErr = pcall(function()
      local id = Assets.imageData(path)
      local byte = false
      local iw, ih = id:getWidth(), id:getHeight()
      for y = 0, math.min(ih - 1, 15) do
        for x = 0, math.min(iw - 1, 15) do
          local pr, pg, pb, pa = id:getPixel(x, y)
          if pr > 1 or pg > 1 or pb > 1 or (pa and pa > 1) then
            byte = true
            break
          end
        end
        if byte then break end
      end
      id:mapPixel(function(_, _, r, g, b, a)
        -- Alpha is sacred: copy through unchanged. Background is already a=0
        -- in follower PNGs; opaque black is the outline, not the matte.
        if (byte and a < 1) or ((not byte) and a < 0.001) then
          return r, g, b, a
        end

        local R = byte and (r / 255) or r
        local G = byte and (g / 255) or g
        local B = byte and (b / 255) or b

        if neon then
          -- Keep true black outlines; fill only chromatic pixels.
          if R < 0.004 and G < 0.004 and B < 0.004 then
            return r, g, b, a
          end
          if byte then return 40, 255, 40, a end
          return 0.15, 1.0, 0.15, a
        end

        local h, s, v = rgbToHsv(R * 255, G * 255, B * 255)
        -- Black / near-black outlines and flat shadows: leave RGB alone.
        if s < 0.08 or v < 0.06 then
          return r, g, b, a
        end
        h = (h + hue) % 1
        s = math.min(1, s * sat)
        v = math.min(1, v * 1.02)
        local nr, ng, nb = hsvToRgb(h, s, v)
        if byte then
          return nr, ng, nb, a
        end
        return nr / 255, ng / 255, nb / 255, a
      end)
      local img = love.graphics.newImage(id)
      if img.setFilter then img:setFilter("nearest", "nearest") end
      return img
    end)
    if not ok or not imgOrErr then
      dbg.bakeFail = dbg.bakeFail + 1
      dbg.lastBakeErr = tostring(imgOrErr)
      dbg.lastPath = tostring(path)
      return nil
    end
    dbg.bakeOk = dbg.bakeOk + 1
    dbg.lastPath = tostring(path)
    shinyImageCache[cacheKey] = imgOrErr
    return imgOrErr
  end

  local function pathLooksGrayscaleSheet(path)
    -- Wilds battle-front bakes and vanilla OW sheets are 4-shade gray.
    if type(path) ~= "string" then return true end
    if path:find("follower_", 1, true) then return false end
    if path:find("overworld_wild_spawns%-cache") then return true end
    return not path:find("trueColor", 1, true)
  end

  local SHINY_CACHE = "shiny_pokemon-cache"

  -- Short stable fingerprint so follower sheets and gray bakes never share
  -- a species-only cache file (that was wiping shiny recolor on OW spawns).
  local function pathFingerprint(path)
    local h = 2166136261
    for i = 1, #path do
      h = (h * 16777619 + path:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
  end

  local function isShinyCachePath(path)
    return type(path) == "string" and path:find(SHINY_CACHE, 1, true) ~= nil
  end

  local function bakeSheetToCache(path, species, kind)
    if type(path) ~= "string" or path == "" then return nil end
    if isShinyCachePath(path) then return path end
    local safe = (tostring(species) .. "_" .. tostring(kind) .. "_"
                  .. pathFingerprint(path)):gsub("[^%w_%-]", "_")
    local rel = SHINY_CACHE .. "/" .. safe .. ".png"
    if love and love.filesystem and love.filesystem.getInfo
       and love.filesystem.getInfo(rel) then
      return rel
    end
    if not (love and love.image and love.filesystem) then return nil end
    local ok, relOrErr = pcall(function()
      local id = Assets.imageData(path)
      if pathLooksGrayscaleSheet(path) then
        local data = Game and Game.data
        local colors = shinyPaletteColors(
          data and PaletteFX.monPal(data, species), species)
        id:mapPixel(function(_, _, r, g, b, a)
          if a == 0 then return r, g, b, a end
          if r > 0.92 and g > 0.92 and b > 0.92 then return 1, 1, 1, 0 end
          local col = r > 0.83 and colors[1] or r > 0.5 and colors[2]
                      or r > 0.17 and colors[3] or colors[4]
          return col[1] / 255, col[2] / 255, col[3] / 255, a
        end)
      else
        -- Prefer official remap; fall back to mild hue if species unknown.
        local light, dark = officialPair(species)
        if light and dark then
          local lumas = {}
          local iw, ih = id:getWidth(), id:getHeight()
          for y = 0, ih - 1 do
            for x = 0, iw - 1 do
              local r, g, b, a = id:getPixel(x, y)
              if a >= 0.05 then
                local R, G, B = r, g, b
                if R > 1 or G > 1 or B > 1 then R, G, B = R / 255, G / 255, B / 255 end
                if not (R < 0.08 and G < 0.08 and B < 0.08)
                   and not (R > 0.92 and G > 0.92 and B > 0.92) then
                  lumas[#lumas + 1] = 0.299 * R + 0.587 * G + 0.114 * B
                end
              end
            end
          end
          table.sort(lumas)
          local split = (#lumas > 0)
            and lumas[math.max(1, math.floor(#lumas * 0.55))] or 0.55
          id:mapPixel(function(_, _, r, g, b, a)
            if a < 0.05 then return r, g, b, a end
            local byte = r > 1 or g > 1 or b > 1
            local R = byte and (r / 255) or r
            local G = byte and (g / 255) or g
            local B = byte and (b / 255) or b
            if R < 0.08 and G < 0.08 and B < 0.08 then return r, g, b, a end
            if R > 0.92 and G > 0.92 and B > 0.92 then return r, g, b, 0 end
            local luma = 0.299 * R + 0.587 * G + 0.114 * B
            local col = luma >= split and light or dark
            return col[1] / 255, col[2] / 255, col[3] / 255, a
          end)
        else
          id:mapPixel(function(_, _, r, g, b, a)
            if a < 0.05 then return r, g, b, a end
            if r > 0.92 and g > 0.92 and b > 0.92 then return r, g, b, 0 end
            local shifted = shiftColor({
              clampByte(r * 255), clampByte(g * 255), clampByte(b * 255),
            }, 0.55, 1.4)
            return (shifted[1] or 0) / 255, (shifted[2] or 0) / 255,
                   (shifted[3] or 0) / 255, a
          end)
        end
      end
      pcall(love.filesystem.createDirectory, SHINY_CACHE)
      local fileData = id:encode("png")
      if not fileData then return nil end
      local wrote = love.filesystem.write(rel, fileData:getString())
      if not wrote then return nil end
      return rel
    end)
    if ok and type(relOrErr) == "string" then return relOrErr end
    return nil
  end

  -- In-memory shiny Image for a source sheet (used every OW draw).
  local function shinyOwImage(path, species)
    if type(path) ~= "string" or path == "" then return nil end
    if isShinyCachePath(path) then
      local ok, img = pcall(Assets.image, path)
      return ok and img or nil
    end
    species = species or speciesFromPath(path)
    local key = "owimg:v6:" .. tostring(species) .. ":" .. path
    if pathLooksGrayscaleSheet(path) then
      return bakeShadedImage(path, shinyPaletteColors(
        Game and Game.data and PaletteFX.monPal(Game.data, species), species), key)
    end
    return bakeOfficialImage(path, species, key)
      or bakeHueShiftImage(path, key, 0.50, 1.15)
  end

  local function bakeFollowerSheet(path, species, cacheKey)
    species = species or speciesFromPath(path)
    return bakeOfficialImage(path, species, cacheKey)
      or bakeHueShiftImage(path, cacheKey, 0.50, 1.15)
  end

  -- ------- Nuclear OW path: recolor at the image source
  -- PokéPCFollowers and SpriteRenderer both go through Assets.image /
  -- SpriteRenderer sheets. Decorating makeEntity alone was losing to those
  -- caches, so at 100% rate we bake follower sheets here instead.

  local origAssetsImage = Assets.image
  local imageSourcePath = setmetatable({}, { __mode = "k" })
  local bakingAssets = false

  local function pathIsFollowerSheet(path)
    return type(path) == "string" and path:find("follower_", 1, true) ~= nil
  end

  -- Never force-bake every follower sheet. 100% rate / DEBUG only affect
  -- wild OW entities via decorateOwEntity. Party trailers must stay
  -- per-mon (pokepcShiny) or one shiny tints the whole pack.
  local function shouldForceOwShinySheet(_path)
    return false
  end

  function Assets.image(path)
    local img = origAssetsImage(path)
    if img and type(path) == "string" then
      imageSourcePath[img] = path
    end
    return img
  end

  local origSpriteNew = SpriteRenderer.new
  function SpriteRenderer.new(spriteDef, seed)
    local self = origSpriteNew(spriteDef, seed)
    local path = spriteDef and spriteDef.image
    if self and self.image and type(path) == "string" then
      imageSourcePath[self.image] = path
    end
    return self
  end

  local installResolveWrap -- defined after follower helpers

  local origMarkSpriteRedraw = PaletteFX.markSpriteRedraw
  function PaletteFX.markSpriteRedraw(image, quad, x, y, sx, colors, keyed)
    return origMarkSpriteRedraw(image, quad, x, y, sx, colors, keyed)
  end

  local function bustOwImageCaches()
    -- Clear bake memo so rate toggles take effect immediately.
    for k in pairs(shinyImageCache) do shinyImageCache[k] = nil end
    pcall(function()
      if SpriteRenderer.invalidate then SpriteRenderer.invalidate() end
    end)
    pcall(function()
      if Assets.invalidate then Assets.invalidate() end
    end)
  end

  -- Drop stale non-shiny sheets cached before this wrap installed.
  bustOwImageCaches()

  mod.events:on("mod.options_changed", function(payload)
    if payload and payload.mod == mod.id then
      cache = {}
      bustOwImageCaches()
    end
  end)

  local function shinyBattleSprite(data, mon, isPlayer)
    local side = isPlayer and "back" or "front"
    local path, tc = Sprites.path(data, mon.species, side, {
      mon = mon, kind = "battle",
    })
    if not path then return nil end
    local key = "battle:" .. tostring(mon.species) .. ":" .. side
    if tc then
      return bakeOfficialImage(path, mon.species, key .. ":tc")
        or bakeHueShiftImage(path, key .. ":tc")
    end
    local base = PaletteFX.monPal(data, mon.species)
    local colors = shinyPaletteColors(base, mon.species)
    local pname = PaletteFX.monPalName(data, mon.species) or "MEWMON"
    return bakeShadedImage(path, colors, key .. ":" .. tostring(pname))
  end

  -- BattleState.makeBattler is a LOCAL inside BattleState.lua; wrapping the
  -- exported alias does not reach newWild/newTrainer/switches. Recolor on
  -- draw / battle.started instead.
  local function ensureShinyBattler(battle, battler)
    if not enabled() or not battler or not battler.mon then return end
    if not isShinyMon(battler.mon) then return end
    battler.mon.shiny = true
    battler.shiny = true
    if not recolorOn() then
      battler._shinySpriteApplied = true
      return
    end
    -- Retry until bake succeeds (first frame can race Dramatic Shape).
    if battler._shinySpriteApplied and battler.sprite then return end
    local data = battle and battle.data or (Game and Game.data)
    if not data then return end
    local img = shinyBattleSprite(data, battler.mon, battler.isPlayer == true)
    if img then
      battler.sprite = img
      battler._shinySpriteApplied = true
    end
  end

  local function syncBattleShinies(battle)
    if not battle then return end
    ensureShinyBattler(battle, battle.enemy)
    ensureShinyBattler(battle, battle.player)
  end

  -- Forward decls: snapped-HUD stars call these after they are defined below.
  local drawNameSparkle, nameSparkleX, hudNameX

  -- Dramatic Shape captures drawPicsLayer before we wrap it; re-sync inside
  -- its texture / HUD snap path so voxel battles keep shiny colors + stars.
  local function dramaticOverworldBattle()
    local ds = mod:find("DRAMATIC_SHAPE")
    if not (ds and ds.exports and ds.exports.lib and ds.exports.lib.require) then
      return nil
    end
    local ok, OB = pcall(ds.exports.lib.require, "OverworldBattle")
    return ok and OB or nil
  end

  local function drawSnappedNameStars(battle, shot)
    if not (battle and shot and love and love.graphics) then return end
    local OB = dramaticOverworldBattle()
    if not (OB and OB.snapRects and OB.hudLive) then return end
    local slide = (battle.introSlide or 0) * 4
    local enemyLive, playerLive = OB.hudLive(battle, slide)
    local _, bandX = OB.snapRects(shot)
    local s = shot.scale or 1
    local g = love.graphics
    local prevCanvas = g.getCanvas()
    local okDraw = pcall(function()
      g.setCanvas(shot.canvas)
      g.setColor(1, 1, 1, 1)
      local function starAt(gbX, gbY, side)
        local bx = bandX and bandX[side] or 0
        local x = bx + gbX * s
        local y = (shot.ly or 0) + gbY * s
        -- Scale the 8x8 mark with the snapped HUD.
        local prev = { g.getColor() }
        g.push()
        g.translate(x, y)
        g.scale(s, s)
        drawNameSparkle(0, 0)
        g.pop()
        g.setColor(prev[1] or 1, prev[2] or 1, prev[3] or 1, prev[4] or 1)
      end
      if enemyLive and battle.enemy and battle.enemy.mon
         and isShinyMon(battle.enemy.mon) then
        local name = battle.enemy.name or ""
        starAt(nameSparkleX(name, hudNameX(1, name)), 0, "enemy")
      end
      local hidePlayer = battle.safari or battle.demo
      if playerLive and not hidePlayer and battle.player and battle.player.mon
         and isShinyMon(battle.player.mon) then
        local name = battle.player.name or ""
        starAt(nameSparkleX(name, hudNameX(10, name)), 56, "player")
      end
    end)
    if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
    if not okDraw then return end
  end

  local function installDramaticShapeShinyHooks()
    local OB = dramaticOverworldBattle()
    if OB and not OB._shinyHooks then
      if type(OB.sideTexture) == "function" then
        local origSide = OB.sideTexture
        function OB.sideTexture(battle, side)
          syncBattleShinies(battle)
          return origSide(battle, side)
        end
      end
      if type(OB.snapHUDs) == "function" then
        local origSnap = OB.snapHUDs
        function OB.snapHUDs(battle, shot)
          local result = origSnap(battle, shot)
          if result and enabled() then
            pcall(drawSnappedNameStars, battle, shot)
          end
          return result
        end
      end
      OB._shinyHooks = true
    end

    -- Battle HUD hooks only here. OW sparkles install via drawFx (below) —
    -- endOverlay canvas-pixel draws were invisible / unreliable in voxel.
  end

  -- ------- one-shot intro FX (battle + overworld)

  local intros = {}

  local function playShinySfx(data)
    data = data or (Game and Game.data)
    if not data then return end
    local ok = pcall(Sound.play, data, SHINY_SFX)
    if not ok then
      pcall(Sound.play, data, "Get_Item1")
    end
    owSfxLastAt = now()
  end

  -- One soft chirp per map for first OW shiny sighting (not from draw loop).
  local function playOwShinySightingSfx(data)
    if owMapSfxPlayed then return end
    local t = now()
    if (t - owSfxLastAt) < OW_SFX_DEBOUNCE then
      owMapSfxPlayed = true
      return
    end
    owMapSfxPlayed = true
    playShinySfx(data)
  end

  -- opts.silent = true: sparkles only (OW / followers — no SFX).
  -- opts.loop = true: restart the sparkle burst every OW_SPARKLE_INTERVAL
  -- (SFX only on the first burst when not silent; loops are visual-only).
  local function beginIntro(key, data, opts)
    if not key or not sparklesOn() or not enabled() then return end
    opts = opts or {}
    local fx = intros[key]
    local t = now()
    if fx then
      if opts.loop then
        local interval = opts.interval or OW_SPARKLE_INTERVAL
        local elapsed = t - (fx.t0 or 0)
        if elapsed >= interval or (elapsed >= (fx.dur or INTRO_SECONDS)
            and elapsed >= interval * 0.85) then
          fx.t0 = t
          fx.dur = INTRO_SECONDS
          fx.loop = true
        end
      end
      return
    end
    intros[key] = {
      t0 = t,
      dur = INTRO_SECONDS,
      loop = opts.loop and true or false,
    }
    if not opts.silent then
      playShinySfx(data)
    end
  end

  local function introActive(key)
    local fx = key and intros[key]
    if not fx or not fx.t0 then return false, 0 end
    local elapsed = now() - fx.t0
    local dur = fx.dur or INTRO_SECONDS
    if elapsed >= dur then
      return false, 1
    end
    return true, elapsed / dur
  end

  -- True when Dramatic Shape voxel pipeline is on (billboards use project()).
  local function voxelOwActive()
    local ok, Pipelines = pcall(require, "src.render.Pipelines")
    if not ok or not Pipelines or type(Pipelines.level) ~= "function" then
      return false
    end
    local lvl = Pipelines.level("voxel")
    if type(lvl) == "number" then return lvl > 0 end
    return lvl and lvl ~= "off" and lvl ~= false
  end

  -- Wait until the battle intro slide / send-out grow finishes.
  local function battleReadyForShinyIntro(battle, isEnemy)
    if not battle then return false end
    if (battle.introSlide or 0) > 0 then return false end
    if isEnemy then
      if battle.showEnemyTrainer or battle.enemySendingOut then return false end
      if battle.growInScale and battle:growInScale(battle.enemy) then return false end
    else
      if battle.showPlayerBack or battle.sendingOut then return false end
      if battle.growInScale and battle:growInScale(battle.player) then return false end
    end
    return true
  end

  -- Persistent ★-style mark next to shiny names (battle / party / summary).
  function drawNameSparkle(x, y)
    if not (love and love.graphics) then return end
    local prev = { love.graphics.getColor() }
    love.graphics.setColor(0, 0, 0, 1)
    local cx, cy = x + 3, y + 3
    love.graphics.rectangle("fill", cx, y, 2, 8)
    love.graphics.rectangle("fill", x, cy, 8, 2)
    love.graphics.rectangle("fill", cx - 1, cy - 1, 4, 4)
    love.graphics.setColor(1, 1, 0.35, 1)
    love.graphics.rectangle("fill", cx, cy, 2, 2)
    love.graphics.setColor(prev[1] or 1, prev[2] or 1, prev[3] or 1, prev[4] or 1)
  end

  function nameSparkleX(name, baseX)
    local w = 0
    if Font and Font.width then
      w = Font.width(name or "")
    elseif type(name) == "string" then
      w = #name * 8
    end
    return baseX + w + 2
  end

  function hudNameX(tx, name)
    local n = 0
    if Font and Font.split then
      n = #Font.split(name or "")
    else
      n = #(name or "")
    end
    return tx * 8 + (n <= 2 and 16 or n <= 4 and 8 or 0)
  end

  local function drawIntroSparkles(key, anchorX, anchorY, seed, scale)
    local active, progress = introActive(key)
    if not active then return false end
    if not (love and love.graphics) then return true end
    scale = scale or 1
    local fade = 1
    if progress > 0.65 then
      fade = 1 - (progress - 0.65) / 0.35
    end
    local burst = math.min(1, progress / 0.18)
    local n = 8
    for i = 1, n do
      local ang = (i / n) * math.pi * 2 + (seed or 0) * 0.2
      local rad = (4 + progress * 14 + (i % 3) * 2) * scale
      local x = anchorX + math.cos(ang) * rad * burst
      local y = anchorY + math.sin(ang * 1.05) * rad * 0.75 * burst - 2 * scale
      local size = math.max(2, math.floor((2.5 - progress) * scale + 0.5))
      -- Opaque yellow — alpha sparkles vanish under some present passes.
      love.graphics.setColor(1, 1, 0.35, 1)
      love.graphics.rectangle("fill", math.floor(x), math.floor(y), size, size)
      if fade > 0.55 then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", math.floor(x) - 1, math.floor(y), 1, size)
      end
    end
    if progress < 0.4 then
      local s = math.max(3, math.floor(3 * scale + 0.5))
      love.graphics.setColor(1, 1, 0.7, 1)
      love.graphics.rectangle("fill",
        math.floor(anchorX) - math.floor(s / 2),
        math.floor(anchorY) - math.floor(s / 2), s, s)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return true
  end

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle or not enabled() then return end
    -- Recolor only — sparkle intro waits until slide-in / send-out finishes.
    syncBattleShinies(battle)
  end)

  local origDrawPics = BattleState.drawPicsLayer
  function BattleState:drawPicsLayer(...)
    syncBattleShinies(self)
    return origDrawPics(self, ...)
  end

  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    if not (enabled() and battle) then return end
    installDramaticShapeShinyHooks()
    syncBattleShinies(battle)

    -- With Dramatic Shape, HUDs are snapped to window edges; stars are drawn
    -- onto that world composite (snapHUDs wrap). Skip the centered GB overlay.
    local snappedHud = battle.dramaticShapeShot ~= nil
    local slide = (battle.introSlide or 0) * 4
    if not snappedHud
       and battle.enemy and battle.enemy.mon and isShinyMon(battle.enemy.mon)
       and not battle.showEnemyTrainer and not battle.enemySendingOut
       and not (battle.growInScale and battle:growInScale(battle.enemy))
       and slide == 0 and not battle.introBalls
       and not battle.enemy.fainted then
      local name = battle.enemy.name or ""
      drawNameSparkle(nameSparkleX(name, hudNameX(1, name)), 0)
    end
    local hidePlayer = battle.safari or battle.demo
    if not snappedHud
       and battle.player and battle.player.mon and isShinyMon(battle.player.mon)
       and not hidePlayer and not battle.showPlayerBack and not battle.sendingOut
       and not (battle.growInScale and battle:growInScale(battle.player))
       and slide == 0 then
      local name = battle.player.name or ""
      drawNameSparkle(nameSparkleX(name, hudNameX(10, name)), 56)
    end

    local function side(battler, isEnemy)
      if not battler or not battler.mon or not isShinyMon(battler.mon) then return end
      if not battleReadyForShinyIntro(battle, isEnemy) then return end
      if not sparklesOn() then return end
      local key = "battle:" .. tostring(battle)
        .. (isEnemy and ":enemy:" or ":player:")
        .. tostring(battler.mon.species)
      beginIntro(key, battle.game and battle.game.data or battle.data)
      local ax, ay = 120, 32
      if not isEnemy then ax, ay = 40, 88 end
      if battle.wide or (battle.wideLayout and battle:wideLayout()) then
        ax = isEnemy and 200 or 60
        ay = isEnemy and 40 or 100
      end
      drawIntroSparkles(key, ax, ay, (battler.mon.level or 1) + (isEnemy and 3 or 7), 1.25)
    end
    side(battle.enemy, true)
    side(battle.player, false)
  end)

  -- ------- Wilds of Kanto + follower compatibility

  local function markOwShiny(entity, record, dvs)
    if not entity then return end
    entity.shiny = true
    entity.shinyDVs = dvs
    if record then
      record.shiny = true
      record.shinyDVs = dvs
    end
  end

  local function owSourcePath(entity)
    local def = entity and entity.sprite and entity.sprite.def
    local path = def and def.image
    if type(path) ~= "string" then return nil end
    if isShinyCachePath(path) then
      return entity._shinySourcePath or path
    end
    return path
  end

  local function owBakeKey(path, species)
    return tostring(species or "?") .. "|" .. tostring(path)
  end

  -- Assign a ready Image onto the entity (hot path only reads _shinyOwImage).
  local function assignOwShinyImage(entity, img, path)
    if not (entity and img) then return false end
    entity._shinyOwImage = img
    entity._shinySourcePath = path or entity._shinySourcePath
    entity._shinyRecolored = true
    entity._shinyQuadCache = nil
    if entity.sprite and entity.sprite.def then
      entity.sprite.image = img
      entity.sprite.def.trueColor = true
      entity.sprite.def.shiny = true
    end
    return true
  end

  local function peekCachedOwImage(path, species)
    if type(path) ~= "string" then return nil end
    -- Hit in-memory bake cache without doing ImageData work.
    species = species or speciesFromPath(path)
    local keyBase = "owimg:v6:" .. tostring(species) .. ":" .. path
    local neon = debugOwOn()
    local officialKey = tostring(keyBase) .. ":official:" .. tostring(species)
      .. (neon and ":neon" or "")
    if shinyImageCache[officialKey] then return shinyImageCache[officialKey] end
    local hueKey = tostring(keyBase) .. (neon and ":neon" or ":huev7")
    if shinyImageCache[hueKey] then return shinyImageCache[hueKey] end
    return nil
  end

  local function finishOwBakeJob(job, img)
    if not job then return end
    owBakeJobs[job.key] = nil
    for _, entity in ipairs(job.waiters or {}) do
      if entity and entity.shiny then
        if img then
          assignOwShinyImage(entity, img, job.path)
        else
          entity._shinyBakeFailed = true
        end
      end
    end
  end

  local function enqueueOwBake(entity, path, species)
    if not (entity and type(path) == "string") then return end
    species = species or entity.species
    entity._shinySourcePath = path
    local cached = peekCachedOwImage(path, species)
    if cached then
      assignOwShinyImage(entity, cached, path)
      return
    end
    -- Prior-session disk cache only (do not write here — that is ImageData work).
    if love and love.filesystem and love.filesystem.getInfo then
      local safe = (tostring(species) .. "_ow_v6_" .. pathFingerprint(path))
        :gsub("[^%w_%-]", "_")
      local disk = SHINY_CACHE .. "/" .. safe .. ".png"
      if love.filesystem.getInfo(disk) then
        local ok, img = pcall(Assets.image, disk)
        if ok and img then
          assignOwShinyImage(entity, img, path)
          return
        end
      end
    end
    local key = owBakeKey(path, species)
    local job = owBakeJobs[key]
    if job then
      job.waiters[#job.waiters + 1] = entity
      return
    end
    job = { key = key, path = path, species = species, waiters = { entity } }
    owBakeJobs[key] = job
    owBakeQueue[#owBakeQueue + 1] = job
  end

  local bakePumpAt = 0
  local function pumpOwBakeQueue()
    local n = 0
    while n < OW_BAKES_PER_FRAME and #owBakeQueue > 0 do
      local job = table.remove(owBakeQueue, 1)
      if job and owBakeJobs[job.key] == job then
        -- One ImageData bake per job; memory cache reused for duplicate species.
        local img = shinyOwImage(job.path, job.species)
        finishOwBakeJob(job, img)
        n = n + 1
      end
    end
  end

  -- Pump even when the player stands still (world.stepped only fires on move).
  local function maybePumpOwBakes()
    if #owBakeQueue == 0 then return end
    local t = now()
    if (t - bakePumpAt) < 0.012 then return end
    bakePumpAt = t
    pumpOwBakeQueue()
  end

  -- Sync recolor only when image is already ready (no ImageData on hot path).
  local function applyOwRecolor(entity, species)
    if not (recolorOn() and entity and entity.sprite and entity.sprite.def) then
      return false
    end
    local path = owSourcePath(entity)
    if type(path) ~= "string" then return false end
    if entity._shinyOwImage and entity._shinySourcePath == path then
      return true
    end
    enqueueOwBake(entity, path, species or entity.species)
    return entity._shinyOwImage ~= nil
  end

  local function owFrameIndex(facing, walkPhase)
    local STAND = SpriteRenderer.STAND
    local WALK = SpriteRenderer.WALK
    facing = facing or "down"
    if walkPhase == 1 and WALK[facing] ~= nil then
      return WALK[facing]
    end
    return STAND[facing] or 0
  end

  local function blitOwTrueColor(img, quad, x, y, flip)
    if not (img and quad and love and love.graphics) then return false end
    local drawX = flip and (x + 16) or x
    local sx = flip and -1 or 1
    if PaletteFX.spriteRedrawPassActive and PaletteFX.spriteRedrawPassActive() then
      origMarkSpriteRedraw(img, quad, drawX, y, sx, nil, false)
    else
      if PaletteFX.markTrueColor then
        PaletteFX.markTrueColor(x, y, 16, 16)
      end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, quad, drawX, y, 0, sx, 1)
    end
    return true
  end

  local function owQuadFor(entity, sprite, img, frame)
    entity._shinyQuadCache = entity._shinyQuadCache or {}
    local hit = entity._shinyQuadCache[frame]
    if hit then return hit end
    local quad = sprite and sprite.frames and sprite.frames[frame]
    if not quad and img and love and love.graphics and love.graphics.newQuad then
      local iw, ih = img:getDimensions()
      quad = love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih)
    end
    entity._shinyQuadCache[frame] = quad
    return quad
  end

  -- Hot path: blit cached _shinyOwImage only (never bake here).
  local function drawOwShinySprite(entity, camX, camY)
    local img = entity._shinyOwImage
    if not img then return false end
    local sprite, px, py, facing, phase, stepFlip = entity:pose()
    if not sprite then return false end
    local x = math.floor((px or 0) - (camX or 0))
    local y = math.floor((py or 0) - (camY or 0)) - 4
    local frame = owFrameIndex(facing, phase)
    local quad = owQuadFor(entity, sprite, img, frame)
    if not quad then return false end
    local flip = (facing == "right")
      or (stepFlip and (facing == "up" or facing == "down"))
    return blitOwTrueColor(img, quad, x, y, flip)
  end

  local function wrapOwDraw(entity)
    if entity._shinyDrawWrapped then return end
    entity._shinyDrawWrapped = true
    local origDraw = entity.draw

    function entity:draw(camX, camY)
      maybePumpOwBakes()
      if not (enabled() and self.shiny
         and not self.hiddenEncounter and self.visibleSprite) then
        if origDraw then origDraw(self, camX, camY) end
        return
      end
      if recolorOn() and self._shinyOwImage then
        if not drawOwShinySprite(self, camX, camY) then
          if origDraw then origDraw(self, camX, camY) end
        end
      else
        -- Bake still queued / recolor off: stock draw this frame.
        if origDraw then origDraw(self, camX, camY) end
      end
      -- 2D sparkles only; voxel uses projected drawFx (same art, correct pos).
      if sparklesOn() and not voxelOwActive() then
        local key = "ow:" .. tostring(self.spawnId or self.id or self)
        beginIntro(key, nil, {
          silent = true, loop = true, interval = OW_SPARKLE_INTERVAL,
        })
        if introActive(key) then
          local ax = math.floor((self.px or 0) - (camX or 0)) + 8
          local ay = math.floor((self.py or 0) - (camY or 0))
          if PaletteFX.markTrueColor then
            PaletteFX.markTrueColor(ax - 12, ay - 12, 24, 28)
          end
          drawIntroSparkles(key, ax, ay, (self.level or 1) + 5, 0.95)
        end
      end
    end
  end

  local function decorateOwEntity(entity, record)
    if not entity or not enabled() or not record then return end
    if record.hiddenEncounter then return end
    local dvs = record.shinyDVs
    local isShiny = record.shiny
    if rateAlways() then
      isShiny = true
      dvs = dvs or makeShinyDVs()
      record.shiny = true
      record.shinyDVs = dvs
    elseif dvs == nil and isShiny == nil then
      if rollShiny() then
        dvs = makeShinyDVs()
        isShiny = true
      else
        isShiny = false
        dvs = nil
      end
      record.shiny = isShiny
      record.shinyDVs = dvs
    end
    if isShiny then
      dvs = dvs or makeShinyDVs()
      record.shinyDVs = dvs
      markOwShiny(entity, record, dvs)
      if entity.sprite and entity.sprite.def then
        entity.sprite.def.trueColor = true
        entity.sprite.def.shiny = true
      end
      if recolorOn() then
        local path = owSourcePath(entity)
        if type(path) == "string" then
          enqueueOwBake(entity, path, record.species or entity.species)
        end
      end
      wrapOwDraw(entity)
      if sparklesOn() then
        pcall(playOwShinySightingSfx, Game and Game.data)
      end
    end
  end

  local function wrapWilds()
    local wilds = mod:find("overworld_wild_spawns")
    if not wilds or not wilds.exports then return end
    local render = wilds.exports.render
    local logic = wilds.exports.logic

    -- Always re-seat as the outermost makeEntity wrapper so WildFollowerSprites
    -- (or anything else) cannot replace the sheet after our recolor runs.
    if render and render.makeEntity then
      local current = render.makeEntity
      if render._shinyMakeFn ~= current then
        local inner = current
        local function shinyMakeEntity(self, game, record)
          local entity = inner(self, game, record)
          -- Never throw out of makeEntity: Wilds treats errors as fatal and
          -- restores vanilla random encounters for the whole map.
          if entity and record then
            local ok, err = pcall(decorateOwEntity, entity, record)
            if not ok then
              mod.log:warn("shiny OW decorate failed: %s", tostring(err))
            end
          end
          return entity
        end
        render.makeEntity = shinyMakeEntity
        render._shinyMakeFn = shinyMakeEntity
      end
    end

    if logic and logic._startBattle and not logic._shinyWrapped then
      local origStart = logic._startBattle
      function logic:_startBattle(record)
        if record then
          if record.shiny and record.shinyDVs then
            pendingWild = { dvs = record.shinyDVs }
          elseif rateAlways() then
            pendingWild = { dvs = makeShinyDVs() }
            record.shiny = true
            record.shinyDVs = pendingWild.dvs
          else
            pendingWild = { none = true }
          end
        end
        local ok, result = pcall(origStart, self, record)
        if not ok then
          clearPendingWild()
          error(result, 0)
        end
        return result
      end
      logic._shinyWrapped = true
    end
  end

  local function activeFollowerMon(game)
    game = game or Game
    if not game or not game.save or not game.save.party then return nil end
    local party = game.save.party
    local idx = game.save.followerPartyIndex
    if idx and party[idx] and (party[idx].hp or 0) > 0 then
      return party[idx]
    end
    for _, m in ipairs(party) do
      if (m.hp or 0) > 0 then return m end
    end
    return party[1]
  end

  local function followerRoot()
    local def = mod.content.sprites:get("SPRITE_PIKACHU")
    local img = def and def.image
    if type(img) == "string" then
      return img:match("^(.-)/assets/sprites/")
    end
    local guesses = {
      "mods/PokePCFollowers-main",
      "mods/PokePCFollowers_VoxelMerge",
      "mods/PokePCFollowers",
    }
    for _, root in ipairs(guesses) do
      local probe = root .. "/assets/sprites/follower_CHARMANDER.png"
      if love and love.filesystem and love.filesystem.getInfo
         and love.filesystem.getInfo(probe) then
        return root
      end
    end
    return nil
  end

  local function followerSheetPath(species)
    local root = followerRoot()
    if not root or not species then return nil end
    return root .. "/assets/sprites/follower_" .. tostring(species) .. ".png"
  end

  -- Dramatic Shape textures from resolveImage; PokéPC overrides it for
  -- SPRITE_PIKACHU. Re-seat as outermost so both see shiny sheets.
  function installResolveWrap()
    if SpriteRenderer._shinyResolve == SpriteRenderer.resolveImage then return end
    local inner = SpriteRenderer.resolveImage
    local function shinyResolve(self, ...)
      if not (enabled() and recolorOn()) then
        return inner(self, ...)
      end
      local path = self and self.def and self.def.image
      local id = self and self.def and self.def.id
      local def = self and self.def

      -- Wild OW shinies (per-entity def.shiny) and 100%/DEBUG force.
      if type(id) == "string" and id:find("OW_WILD", 1, true)
         and pathIsFollowerSheet(path)
         and (rateAlways() or debugOwOn() or (def and def.shiny)) then
        dbg.resolveHits = dbg.resolveHits + 1
        local sp = speciesFromPath(path)
        local shiny = bakeFollowerSheet(path, sp,
          "resolve:wild:" .. tostring(sp) .. ":" .. tostring(path))
        if shiny then return shiny end
      end

      -- Party / trailer: only when this sprite is marked shiny.
      if (id == "SPRITE_POKEPC_MON" or id == "SPRITE_PLAYER_POKEMON"
          or id == "SPRITE_PIKACHU") and def and def.pokepcShiny
         and pathIsFollowerSheet(path) then
        local sp = speciesFromPath(path)
        if id == "SPRITE_PIKACHU" or id == "SPRITE_PLAYER_POKEMON" then
          local mon = activeFollowerMon(Game)
          sp = (mon and mon.species) or sp
        end
        local shiny = bakeFollowerSheet(path, sp,
          "resolve:party:" .. tostring(sp) .. ":S")
        if shiny then return shiny end
      end

      return inner(self, ...)
    end
    SpriteRenderer.resolveImage = shinyResolve
    SpriteRenderer._shinyResolve = shinyResolve
  end
  installResolveWrap()

  local function clearOwIntros()
    local drop = {}
    for k in pairs(intros) do
      if type(k) == "string"
         and (k:sub(1, 9) == "follower:" or k:sub(1, 3) == "ow:"
              or k:sub(1, 8) == "trailer:") then
        drop[#drop + 1] = k
      end
    end
    for i = 1, #drop do intros[drop[i]] = nil end
  end

  -- Looping OW sparkles for party leader / pack trailers (2D + callers).
  local function drawOwFollowerSparkles(key, ax, ay, seed, scale)
    if not (enabled() and sparklesOn() and key) then return false end
    beginIntro(key, Game and Game.data, {
      silent = true, loop = true, interval = OW_SPARKLE_INTERVAL,
    })
    if not introActive(key) then return false end
    if PaletteFX.markTrueColor then
      PaletteFX.markTrueColor((ax or 0) - 12, (ay or 0) - 12, 24, 28)
    end
    drawIntroSparkles(key, ax, ay, seed or 11, scale or 0.95)
    return true
  end

  -- Own SPRITE_PIKACHU / trailer draws so PokéPCFollowers cannot paint the
  -- stock sheet after us. Re-seated on game.ready / map.entered.
  local function installSpriteDrawWrap()
    if SpriteRenderer._shinyOwDraw == SpriteRenderer.draw then return end
    local inner = SpriteRenderer.draw
    local function shinySpriteDraw(self, px, py, camX, camY, facing, walkPhase,
                                   stepFlip, topHalf)
      local id = self.def and self.def.id
      local isFollower = id == "SPRITE_PIKACHU" or id == "SPRITE_PLAYER_POKEMON"
        or id == "SPRITE_POKEPC_MON"
      if enabled() and isFollower then
        local shinyFollow = self.def and self.def.pokepcShiny and true or false
        local species = self.def and self.def.image
          and self.def.image:match("follower_([%w_]+)%.png")
        local sparkleKey
        if id == "SPRITE_POKEPC_MON" then
          -- Pack trailer: per-sprite pokepcShiny only.
          species = species or "CHARMANDER"
          sparkleKey = "trailer:" .. tostring(self.id or species)
        else
          local mon = activeFollowerMon(Game)
          if mon and Stats.isShiny(mon.dvs) then mon.shiny = true end
          -- Per-mon only — never rateAlways (that made the whole pack shiny).
          shinyFollow = (mon and isShinyMon(mon)) or shinyFollow
          species = (mon and mon.species) or species or "PIKACHU"
          sparkleKey = "follower:" .. tostring(species)
        end
        local path = followerSheetPath(species)
          or (self.def and self.def.image)
        local img
        if shinyFollow and recolorOn() and type(path) == "string" then
          img = bakeFollowerSheet(path, species,
            "follower:v6:" .. tostring(species) .. (shinyFollow and ":S" or ""))
        end
        if not img and type(path) == "string" then
          -- Use unwrapped loader so we never recurse through Assets.image wrap.
          local ok, loaded = pcall(origAssetsImage, path)
          img = ok and loaded or nil
        end
        if img then
          local x = math.floor(px - (camX or 0))
          local y = math.floor(py - (camY or 0)) - 4
          local STAND = SpriteRenderer.STAND
          local WALK = SpriteRenderer.WALK
          local frame = ((walkPhase == 1) and WALK or STAND)[facing or "down"] or 0
          local quad = self.frames and self.frames[frame]
          if not quad and love and love.graphics and love.graphics.newQuad then
            local iw, ih = img:getDimensions()
            quad = love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih)
          end
          if quad then
            local flip = (facing == "right")
              or (stepFlip and (facing == "up" or facing == "down"))
            blitOwTrueColor(img, quad, x, y, flip)
            if shinyFollow then
              drawOwFollowerSparkles(sparkleKey, x + 8, y + 4, 11, 0.95)
            end
            return
          end
        end
      end

      if topHalf ~= nil then
        return inner(self, px, py, camX, camY, facing, walkPhase, stepFlip, topHalf)
      end
      return inner(self, px, py, camX, camY, facing, walkPhase, stepFlip)
    end
    SpriteRenderer.draw = shinySpriteDraw
    SpriteRenderer._shinyOwDraw = shinySpriteDraw
  end

  local function syncAllWildEntities()
    local wilds = mod:find("overworld_wild_spawns")
    local logic = wilds and wilds.exports and wilds.exports.logic
    local entities = logic and logic.entities
    if type(entities) ~= "table" then return end
    for _, entity in pairs(entities) do
      if entity and entity.overworldWildSpawn and not entity.hiddenEncounter then
        local record = {
          shiny = entity.shiny,
          shinyDVs = entity.shinyDVs,
          species = entity.species,
          hiddenEncounter = false,
        }
        pcall(decorateOwEntity, entity, record)
      end
    end
  end

  local function writeDebugLog(extra)
    if not (love and love.filesystem and love.filesystem.write) then return end
    local wilds = mod:find("overworld_wild_spawns")
    local nEnt, nShiny, nWrapped = 0, 0, 0
    local entities = wilds and wilds.exports and wilds.exports.logic
      and wilds.exports.logic.entities
    if type(entities) == "table" then
      for _, e in pairs(entities) do
        if e and e.overworldWildSpawn then
          nEnt = nEnt + 1
          if e.shiny then nShiny = nShiny + 1 end
          if e._shinyDrawWrapped then nWrapped = nWrapped + 1 end
        end
      end
    end
    local lines = {
      "SHINY_POKEMON debug " .. dbg.version,
      "enabled=" .. tostring(enabled()) .. " rate=" .. tostring(rateKey())
        .. " recolor=" .. tostring(recolorOn())
        .. " debug_ow=" .. tostring(debugOwOn()),
      "raw shiny_rate=" .. tostring(readOpt("shiny_rate", "<default>")),
      "bakeOk=" .. dbg.bakeOk .. " bakeFail=" .. dbg.bakeFail
        .. " err=" .. tostring(dbg.lastBakeErr),
      "assetsHits=" .. dbg.assetsHits
        .. " resolveHits=" .. dbg.resolveHits
        .. " redrawHits=" .. dbg.redrawHits,
      "lastPath=" .. tostring(dbg.lastPath),
      "wildsEntities=" .. nEnt .. " shiny=" .. nShiny
        .. " drawWrapped=" .. nWrapped,
      "wildsMod=" .. tostring(wilds and wilds.version),
      "followers=" .. tostring(mod:find("PokePCFollowers_VoxelMerge") and "yes" or "no"),
      "wildFollower=" .. tostring(mod:find("WILDS_FOLLOWER_SPRITES") and "yes" or "no"),
      "makeWrapped=" .. tostring(dbg.wrapMake),
      "saveDir mods path note: live mods load from love save dir",
      tostring(extra or ""),
    }
    pcall(love.filesystem.write, "shiny_pokemon_debug.log",
          table.concat(lines, "\n") .. "\n")
  end

  local function drawDebugOverlay()
    if not debugOwOn() or not (love and love.graphics and love.graphics.print) then
      return
    end
    local prev = { love.graphics.getColor() }
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, 0, 160, 54)
    love.graphics.setColor(0.2, 1, 0.2, 1)
    love.graphics.print(string.format(
      "SHINY DBG %s r=%s\nbake %d/%d res %d\npath %s",
      dbg.version, rateKey(), dbg.bakeOk, dbg.bakeFail, dbg.resolveHits,
      tostring(dbg.lastPath):sub(-28)), 2, 2)
    love.graphics.setColor(prev[1] or 1, prev[2] or 1, prev[3] or 1, prev[4] or 1)
  end

  -- Draw debug text in the UI pass so the zone shader cannot eat it.
  pcall(function()
    mod.hooks:wrap("render.letterbox", function(next, ctx)
      next(ctx)
      -- Drawn in the window letterbox (before the GB canvas blit). Top-left
      -- of the window stays readable even when the playfield is centered.
      pcall(drawDebugOverlay)
    end)
  end)

  -- Voxel sparkles: projected world-pixel path (same as dust/heal FX).
  -- Replacing ctx.fx.* alone does nothing; drawFx closes over locals.
  local drewVoxelSparkles = false

  local function collectShinySparkleTargets(ow)
    local out = {}
    if not ow then return out end
    local wilds = mod:find("overworld_wild_spawns")
    local ents = wilds and wilds.exports and wilds.exports.logic
      and wilds.exports.logic.entities
    if type(ents) == "table" then
      for _, e in pairs(ents) do
        if e and e.shiny and not e.hiddenEncounter
           and (e.visibleSprite ~= false) then
          out[#out + 1] = {
            wx = (e.px or 0) + 8, wy = (e.py or 0) + 6,
            key = "ow:" .. tostring(e.spawnId or e.id or e),
            seed = (e.level or 1) + 5,
          }
        end
      end
    end
    local player = ow.player
    if player and player._pokepcAsPokemon then
      local mon = activeFollowerMon(Game)
      if mon and isShinyMon(mon) then
        out[#out + 1] = {
          wx = (player.px or 0) + 8, wy = (player.py or 0) + 6,
          key = "follower:" .. tostring(mon.species), seed = 11,
        }
      end
    end
    for _, e in ipairs(ow.entities or {}) do
      if e and (e.pikachuFollower or e.pokepcTrailer) and e.pokepcShiny then
        out[#out + 1] = {
          wx = (e.px or 0) + 8, wy = (e.py or 0) + 6,
          key = "trailer:" .. tostring(e.pokepcTrailerId or e.id or e),
          seed = 9,
        }
      end
    end
    return out
  end

  local function drawSparklesProjected(project, scale, cam, targets)
    if not (project and cam and targets) then return false end
    scale = scale or 1
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
    local any = false
    for _, t in ipairs(targets) do
      beginIntro(t.key, Game and Game.data, {
        silent = true, loop = true, interval = OW_SPARKLE_INTERVAL,
      })
      if introActive(t.key) then
        local sx, sy = project(t.wx, t.wy)
        if sx then
          local fx, fy = t.wx - cam.x, t.wy - cam.y
          love.graphics.push()
          love.graphics.scale(scale, scale)
          love.graphics.translate(sx / scale - fx, sy / scale - fy)
          drawIntroSparkles(t.key, fx, fy, t.seed or 7, 1.5)
          love.graphics.pop()
          any = true
        end
      end
    end
    return any
  end

  local function installVoxelSparkleDrawFx()
    local Pipelines = require("src.render.Pipelines")
    if Pipelines._shinySparkleDrawFx then return end
    local origPipe = Pipelines.drawWorld
    Pipelines._shinySparkleOrigDrawWorld = origPipe
    function Pipelines.drawWorld(id, ctx)
      if ctx and ctx.drawFx and ctx.state then
        local origDrawFx = ctx.drawFx
        local st = ctx.state
        local cam = ctx.cam or (st and st.camera)
        ctx.drawFx = function(project, scale)
          maybePumpOwBakes()
          origDrawFx(project, scale)
          drewVoxelSparkles = false
          if not (enabled() and sparklesOn() and project and cam) then return end
          local ok, any = pcall(function()
            return drawSparklesProjected(project, scale, cam,
              collectShinySparkleTargets(st))
          end)
          drewVoxelSparkles = ok and any or false
        end
      end
      return origPipe(id, ctx)
    end
    Pipelines._shinySparkleDrawFx = true
  end

  local function installVoxelSparkleEndOverlay()
    local Zoom = require("src.render.Zoom")
    local function bind(V3)
      if type(V3) ~= "table" or type(V3.endOverlay) ~= "function" then
        return false
      end
      if V3._shinySparkleEndWrapped then return true end
      local origEnd = V3.endOverlay
      V3._shinySparkleOrigEnd = origEnd
      function V3.endOverlay()
        pcall(function()
          if drewVoxelSparkles then return end
          if not (enabled() and sparklesOn() and type(V3.project) == "function") then
            return
          end
          local ow = Game and Game.overworld
          local cam = ow and ow.camera
          if not cam then return end
          local fit = Game.renderer and Game.renderer.fitScale
            and Game.renderer:fitScale() or 1
          local scale = Zoom.scale and Zoom.scale(fit) or fit or 1
          local function project(wx, wy)
            return V3.project(wx, 0, wy)
          end
          drawSparklesProjected(project, scale, cam,
            collectShinySparkleTargets(ow))
        end)
        drewVoxelSparkles = false
        return origEnd()
      end
      V3._shinySparkleEndWrapped = "1.4.6"
      return true
    end
    local function tryBind()
      for _, id in ipairs({ "DRAMATIC_SHAPE", "DRAMATIC_SHAPE_SEAMLESS" }) do
        local ds = mod:find(id)
        local lib = ds and ds.exports and ds.exports.lib
        if lib and type(lib.require) == "function" then
          local ok, V3 = pcall(lib.require, "Voxel3D")
          if ok and bind(V3) then return true end
        end
      end
      return false
    end
    tryBind()
    return tryBind
  end

  local rebindSparkleEnd = installVoxelSparkleEndOverlay()

  wrapWilds()
  installSpriteDrawWrap()
  installResolveWrap()
  installVoxelSparkleDrawFx()
  mod.events:on("game.ready", function()
    wrapWilds()
    installSpriteDrawWrap()
    installResolveWrap()
    installDramaticShapeShinyHooks()
    installVoxelSparkleDrawFx()
    if rebindSparkleEnd then rebindSparkleEnd() end
    bustOwImageCaches()
    dbg.wrapMake = true
    writeDebugLog("game.ready")
  end)

  mod.events:on("map.entered", function()
    clearPendingWild()
    clearOwIntros()
    owMapSfxPlayed = false
    -- Drop in-flight bakes for the previous map; keep shinyImageCache warm.
    owBakeQueue = {}
    owBakeJobs = {}
    wrapWilds()
    installSpriteDrawWrap()
    installResolveWrap()
    installDramaticShapeShinyHooks()
    installVoxelSparkleDrawFx()
    if rebindSparkleEnd then rebindSparkleEnd() end
    syncAllWildEntities()
    writeDebugLog("map.entered")
  end)

  mod.events:on("world.stepped", function()
    pcall(pumpOwBakeQueue)
    if not enabled() then return end
    if not rateAlways() then return end
    local wilds = mod:find("overworld_wild_spawns")
    local entities = wilds and wilds.exports and wilds.exports.logic
      and wilds.exports.logic.entities
    if type(entities) ~= "table" then return end
    for _, entity in pairs(entities) do
      if entity and entity.overworldWildSpawn and not entity.hiddenEncounter
         and not entity._shinyDrawWrapped then
        pcall(decorateOwEntity, entity, {
          shiny = entity.shiny,
          shinyDVs = entity.shinyDVs,
          species = entity.species,
          hiddenEncounter = false,
        })
      end
    end
  end)

  -- Persist shiny flag on catch / any party mon that already has shiny DVs.
  mod.events:on("pokemon.caught", function(ev)
    local mon = ev and (ev.mon or ev.pokemon)
    if mon and Stats.isShiny(mon.dvs) then mon.shiny = true end
  end)

  -- Party list: sparkle beside shiny nicknames / species names.
  local origPartyDraw = PartyMenu.draw
  function PartyMenu:draw(...)
    origPartyDraw(self, ...)
    if not enabled() or not self.game then return end
    local party = self.game.save and self.game.save.party
    if not party then return end
    for i, mon in ipairs(party) do
      if Stats.isShiny(mon.dvs) then mon.shiny = true end
      if isShinyMon(mon) then
        local def = self.game.data.pokemon[mon.species]
        local name = mon.nickname or (def and def.name) or "?"
        local y = PartyMenu.entryY(i)
        drawNameSparkle(nameSparkleX(name, 24), y)
      end
    end
  end

  -- Summary / stats screen: shiny front pic + name sparkle.
  local origSummaryNew = SummaryMenu.new
  function SummaryMenu.new(game, mon, ...)
    local self = origSummaryNew(game, mon, ...)
    if enabled() and mon and isShinyMon(mon) then
      mon.shiny = true
      if recolorOn() and game and game.data then
        local img = shinyBattleSprite(game.data, mon, false)
        if img then
          self.sprite = img
          self.spriteTrueColor = true
        end
      end
    end
    return self
  end

  local origSummaryDraw = SummaryMenu.draw
  function SummaryMenu:draw(...)
    origSummaryDraw(self, ...)
    if not enabled() or not self.mon or not isShinyMon(self.mon) then return end
    local def = self.game and self.game.data and self.game.data.pokemon[self.mon.species]
    local name = self.mon.nickname or (def and def.name) or "?"
    drawNameSparkle(nameSparkleX(name, 72), 8)
  end

  -- OPTIONS submenu so shiny settings appear under pause OPTIONS (OPEN).
  local SHINY_SCREEN = "ShinyPokemonOptions"
  local RATE_ORDER = {
    "off", "gen2", "modern", "common", "frequent", "often", "high", "always",
  }
  local RATE_LABEL = {
    off = "OFF", gen2 = "1/8192", modern = "1/4096", common = "1/1024",
    frequent = "1/512", often = "1/100", high = "1/10", always = "100%",
  }

  local function setOpt(key, value, game)
    cache[key] = value
    pcall(function() mod.options:set(key, value) end)
    if game and game.save then
      game.save.options = game.save.options or {}
      game.save.options.modOptions = game.save.options.modOptions or {}
      game.save.options.modOptions[mod.id] =
        game.save.options.modOptions[mod.id] or {}
      game.save.options.modOptions[mod.id][key] = value
    end
    if game and game.mods then
      game.mods.modOptions = game.mods.modOptions or {}
      game.mods.modOptions[mod.id] = game.mods.modOptions[mod.id] or {}
      game.mods.modOptions[mod.id][key] = value
    end
    if game and game.writeOptions then pcall(game.writeOptions, game) end
  end

  local function makeShinyScreen(game)
    local OptionRows = require("src.ui.OptionRows")
    local rows = {
      {
        label = "SHINY",
        value = function() return enabled() and "ON" or "OFF" end,
        step = function(g) setOpt("enabled", not enabled(), g) end,
      },
      {
        label = "SHINY RATE",
        value = function() return RATE_LABEL[rateKey()] or "1/4096" end,
        step = function(g)
          local cur = rateKey()
          local idx = 3
          for i, k in ipairs(RATE_ORDER) do
            if k == cur then idx = i break end
          end
          idx = (idx % #RATE_ORDER) + 1
          setOpt("shiny_rate", RATE_ORDER[idx], g)
        end,
      },
      {
        label = "SHINY COLORS",
        value = function() return recolorOn() and "ON" or "OFF" end,
        step = function(g) setOpt("recolor", not recolorOn(), g) end,
      },
      {
        label = "SHINY INTRO",
        value = function() return sparklesOn() and "ON" or "OFF" end,
        step = function(g) setOpt("sparkles", not sparklesOn(), g) end,
      },
      {
        label = "DEBUG OW",
        value = function() return debugOwOn() and "ON" or "OFF" end,
        step = function(g) setOpt("debug_ow", not debugOwOn(), g) end,
      },
    }
    local screen = {
      game = game, rows = rows, index = 1, scroll = 0, isOpaque = true,
    }
    function screen:sgbPalettes(g)
      return require("src.render.PaletteFX").wholeNamed(g.data, "MEWMON")
    end
    function screen:update()
      local input = self.game.input
      if input:wasPressed("up") then
        self.index = (self.index - 2) % #self.rows + 1
      elseif input:wasPressed("down") then
        self.index = self.index % #self.rows + 1
      elseif input:wasPressed("left") or input:wasPressed("right")
          or input:wasPressed("a") then
        local row = self.rows[self.index]
        if row and row.step then row.step(self.game) end
      elseif input:wasPressed("b") then
        self.game.stack:pop()
      end
      self.scroll = OptionRows.clampScroll(
        self.index, self.scroll, #self.rows, nil)
    end
    function screen:draw()
      OptionRows.draw(self.game, self.rows, self.index, self.scroll,
                      "A/◀▶:CHANGE B:DONE")
    end
    return screen
  end

  mod.content.screens:register(SHINY_SCREEN, { new = makeShinyScreen })

  mod.events:once("mods.loaded", function()
    local ManagerState = require("src.mods.ManagerState")
    local routes = rawget(ManagerState, "__modOptionScreenRoutes")
    if not routes then
      routes = {}
      local openOptions = ManagerState.openOptions
      ManagerState.openOptions = function(self, manifest)
        local screenId = manifest and routes[manifest.id]
        if screenId then
          return require("src.ui.Screens").push(self.game, screenId)
        end
        return openOptions(self, manifest)
      end
      ManagerState.__modOptionScreenRoutes = routes
    end
    routes[mod.id] = SHINY_SCREEN
  end)

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    local row = {
      id = "shiny_pokemon_open",
      label = "SHINY POKEMON",
      value = function() return "OPEN" end,
      activate = function(g)
        require("src.ui.Screens").push(g, SHINY_SCREEN)
      end,
    }
    if mod.ui and type(mod.ui.insertBefore) == "function" then
      return mod.ui.insertBefore(out, "MODS", row)
    end
    out[#out + 1] = row
    return out
  end)

  mod.exports.version = "1.0.1"
  -- Install voxel sparkle / DS hooks once locals above are all bound.
  installDramaticShapeShinyHooks()
  mod.exports.isShiny = Stats.isShiny
  mod.exports.makeShinyDVs = makeShinyDVs
  mod.exports.rollShiny = rollShiny
  mod.exports.onWildEntity = decorateOwEntity
  mod.exports.bustOwImageCaches = bustOwImageCaches
  mod.exports.writeDebugLog = writeDebugLog
  mod.exports.drawOwFollowerSparkles = drawOwFollowerSparkles
  mod.exports.pumpOwBakeQueue = pumpOwBakeQueue
  mod.exports.bakeFollowerOwSheet = function(path, species)
    if not enabled() or not recolorOn() then return nil end
    if type(path) ~= "string" then return nil end
    species = species or speciesFromPath(path)
    return bakeFollowerSheet(path, species,
      "export:party:" .. tostring(species) .. ":" .. path)
  end

  writeDebugLog("mod-load")
  mod.log:info("%s 1.0.1 ready (rate=%s) — OW bake queue + voxel sparkle split",
               MOD_ID, rateKey())
end
