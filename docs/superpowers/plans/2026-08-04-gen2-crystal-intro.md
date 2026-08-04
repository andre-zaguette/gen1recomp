# Gen2 (Crystal) New-Game Intro Sequence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pressing NEW GAME on Crystal plays the real intro — Oak's narration with his portrait and a live Wooper demo (sprite + cry), a working boy/girl choice that changes the player's overworld sprite, and player naming — replacing the `NoOpScreen` placeholder, then spawns the named, gendered player in New Bark Town.

**Architecture:** Every piece mirrors an already-proven pattern in this codebase rather than inventing anything new. Crystal's text byte-encoding is confirmed identical to Gen1's (same opcodes, no compression) — the runtime decode logic is ported verbatim from `RomExtractor.lua` into `RomExtractorGen2.lua`. Kris's sprite is a straight symbol-swap of the already-working Chris extraction. Oak's portrait and Wooper's front pic reuse this Gen2 pipeline's own LZ3 decompressor exactly as the tileset extraction already does. Wooper's cry mirrors Gen1's two-level indirection (species → `{cryIndex, pitch, length}` → `{bank, address}`), resolved once at manifest-build time from readable pokecrystal source (matching the font/palette precedent), with only a single 16KB ROM bank dump needed at runtime (not Gen1's three). The new `src/ui/CrystalIntro.lua` screen delegates to `src/ui/OakSpeech.lua`'s existing, unmodified step-runner methods via Lua metatable inheritance, overriding only the parts that are genuinely different (step list, demo beat text key, the new gender-choice step) — `OakSpeech.lua` itself is never touched, so Gen1's intro carries zero regression risk. `src/world/Player.lua` gains one optional trailing parameter so a save's chosen gender can pick Kris's sprite over Chris's, fully backward compatible.

**Tech Stack:** Python 3 (manifest/tooling), Lua 5.1/LuaJIT (runtime extractor + engine), LÖVE2D.

## Global Constraints

- No ROM bytes, and no raw pokecrystal narrative/prose text, are ever committed — only derived, non-copyrightable metadata (symbol addresses, byte offsets, resolved index/pointer tables). This mirrors the `fontCharmap`/palette precedent exactly: the Oak/gender-prompt *text itself* is genuinely extracted from the player's own ROM at *runtime* (never committed), matching every other dialogue string in this project.
- `data/generated/*` and `assets/generated/*` are gitignored, written only at import time on the player's machine.
- CI has no ROM: any new automated test must run against hand-built fixture data.
- This plan touches Gen2-specific files plus small, precisely-scoped additions to two shared files (`src/world/Player.lua`, backward compatible via an optional parameter) and reads (never modifies) `src/ui/OakSpeech.lua`. The existing Gen1 intro flow and full test suite must show zero regressions.
- No rival naming, no starter selection, no Elm's Lab, no Pokémon besides Wooper, no animated front-sprite blending, no Crystal map besides New Bark Town, no general text/dialogue pipeline (only the ~8 named labels this intro needs).

---

### Task 1: `src/world/Player.lua` — save-aware player sprite selection

**Files:**
- Modify: `src/world/Player.lua`
- Modify: `src/world/OverworldController.lua` (the one real call site)

**Interfaces:**
- Produces: `Player.new(data, cx, cy, facing, save)` — `save` is a new, optional 5th parameter. When present and `save.player.gender` equals the alternate-gender sentinel and `field.playerSprites.walkAlt` resolves to a real sprite in `data.sprites`, that sprite is used instead of the default `walk` one. Consumed by Task 8 (the intro's gender step sets `Game.save.player.gender`) and by Task 9's manual verification.

- [ ] **Step 1: Change `Player.new`'s signature and sprite selection**

In `src/world/Player.lua`, change:

```lua
function Player.new(data, cx, cy, facing)
  local self = setmetatable({}, Player)
  self.stepFrames = FieldDefaults.world(data, "stepFrames") or STEP_FRAMES
  self.bikeStepFrames = FieldDefaults.world(data, "bikeStepFrames")
  self.turnFrames = FieldDefaults.world(data, "turnFrames") or TURN_FRAMES
  -- field.playerSprites: which sprite ids the player wears on foot, on the
  -- water and on the bicycle (LoadPlayerSpriteGraphics /
  -- LoadSurfingPlayerSpriteGraphics, home/overworld.asm)
  local walkId = FieldDefaults.fieldValue(data, "playerSprites", "walk")
```

to:

```lua
function Player.new(data, cx, cy, facing, save)
  local self = setmetatable({}, Player)
  self.stepFrames = FieldDefaults.world(data, "stepFrames") or STEP_FRAMES
  self.bikeStepFrames = FieldDefaults.world(data, "bikeStepFrames")
  self.turnFrames = FieldDefaults.world(data, "turnFrames") or TURN_FRAMES
  -- field.playerSprites: which sprite ids the player wears on foot, on the
  -- water and on the bicycle (LoadPlayerSpriteGraphics /
  -- LoadSurfingPlayerSpriteGraphics, home/overworld.asm). walkAlt is a
  -- second, gender-alternate walk sprite (Crystal's Kris, alongside the
  -- default Chris) -- no Gen1 version has ever populated it, and no
  -- existing save has save.player.gender set, so this is a pure addition:
  -- every pre-existing call/save keeps resolving the same walkId it
  -- always has.
  local walkId = FieldDefaults.fieldValue(data, "playerSprites", "walk")
  if save and save.player and save.player.gender == "girl" then
    local altId = FieldDefaults.fieldValue(data, "playerSprites", "walkAlt")
    if altId and data.sprites[altId] then walkId = altId end
  end
```

- [ ] **Step 2: Pass `Game.save` at the one real call site**

In `src/world/OverworldController.lua`, change:

```lua
    self.player = Player.new(Game.data, x, y, facing)
```

to:

```lua
    self.player = Player.new(Game.data, x, y, facing, Game.save)
```

- [ ] **Step 3: Verify both files load**

Run:
```bash
luajit -e "assert(loadfile('src/world/Player.lua'))" && echo OK
luajit -e "assert(loadfile('src/world/OverworldController.lua'))" && echo OK
```
Expected: `OK` twice.

- [ ] **Step 4: Run the full quick test suite to confirm no regressions**

Run: `./scripts/test.sh --quick`
Expected: `ALL TIERS PASSED` (no existing save sets `save.player.gender`, so every existing test's player sprite resolution is byte-for-byte unchanged).

- [ ] **Step 5: Commit**

```bash
git add src/world/Player.lua src/world/OverworldController.lua
git commit -m "$(cat <<'EOF'
Let a save's chosen gender pick an alternate player sprite

Player.new gains an optional trailing save parameter; when present
and save.player.gender is "girl" and field.playerSprites.walkAlt
resolves to a real sprite, that sprite is used instead of the
default walk one. No existing save sets this field and no existing
version populates walkAlt, so every current call/save resolves
exactly as before -- this is scaffolding for the Crystal intro's
boy/girl choice (a later task), not yet reachable from any version.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Extract Kris's sprite

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py`
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `KrisSpriteGFX` — bank `$31`, addr `$7a40` (confirmed against `pokecrystal.sym`). Identical shape to the already-extracted `ChrisSpriteGFX`: `overworld_sprite` macro, 12 tiles, `WALKING_SPRITE`, 2bpp, 384 raw bytes.
- Produces: a second entry, `SPRITE_KRIS`, in `data/generated/sprites.lua`, and `field.playerSprites.walkAlt = "SPRITE_KRIS"` in `data/generated/field.lua`. Consumed by Task 1 (already landed) and Task 8's gender step.

- [ ] **Step 1: Add the symbol**

In `tools/make_rom_manifest_crystal.py`, add `"KrisSpriteGFX"` to `REQUIRED_SYMBOLS`, right after `"ChrisSpriteGFX"`:

```python
REQUIRED_SYMBOLS = (
    "NewBarkTown_MapAttributes",
    "NewBarkTown_MapEvents",
    "TilesetJohtoGFX",
    "TilesetJohtoMeta",
    "TilesetJohtoColl",
    "ChrisSpriteGFX",
    "KrisSpriteGFX",
    "Font",
    "FontExtra",
)
```

- [ ] **Step 2: Regenerate the manifest for real**

```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal /tmp/pokecrystal \
  --symbols /tmp/pokecrystal/pokecrystal.sym \
  --out tools/rom_manifest_crystal.json
python3 -c "
import json
d = json.load(open('tools/rom_manifest_crystal.json'))
print(d['symbols']['KrisSpriteGFX'])
"
```
Expected: a `[bank, address]` pair, `[49, 31296]` (`0x31` = 49, `0x7a40` = 31296).

- [ ] **Step 3: Extend `extractSprite()` to also write Kris**

In `src/import/RomExtractorGen2.lua`, change:

```lua
function RomExtractorGen2:extractSprite()
  self:beginStage("Player sprite")
  local symbol = self:symbol("ChrisSpriteGFX")
  local raw = self.rom:bytes(symbol.bank, symbol.address, 16 * 96 / 4)
  local image = ImageWriter.decode2bpp(raw, 16, 96, true)
  self:save(image, "sprites/chris.png")
  local out = {
    SPRITE_CHRIS = {
      id = "SPRITE_CHRIS", source = "ROM:ChrisSpriteGFX",
      image = "assets/generated/sprites/chris.png",
      frames = 96 / 16, walker = true,
    },
  }
  self:write("sprites", out)
  self:tick("Player sprite", 1, 1)
  return out
end
```

to:

```lua
function RomExtractorGen2:extractSprite()
  self:beginStage("Player sprite")
  local chris = self:symbol("ChrisSpriteGFX")
  local chrisRaw = self.rom:bytes(chris.bank, chris.address, 16 * 96 / 4)
  local chrisImage = ImageWriter.decode2bpp(chrisRaw, 16, 96, true)
  self:save(chrisImage, "sprites/chris.png")

  -- Kris: the girl protagonist, identical sheet shape to Chris (same
  -- overworld_sprite macro, 12 tiles, 2bpp) -- only her default in-ROM
  -- palette differs (PAL_OW_BLUE vs PAL_OW_RED), which this project's own
  -- real-color palette work already resolves independently of the ROM's
  -- own default, so it needs no special handling here.
  local kris = self:symbol("KrisSpriteGFX")
  local krisRaw = self.rom:bytes(kris.bank, kris.address, 16 * 96 / 4)
  local krisImage = ImageWriter.decode2bpp(krisRaw, 16, 96, true)
  self:save(krisImage, "sprites/kris.png")

  local out = {
    SPRITE_CHRIS = {
      id = "SPRITE_CHRIS", source = "ROM:ChrisSpriteGFX",
      image = "assets/generated/sprites/chris.png",
      frames = 96 / 16, walker = true,
    },
    SPRITE_KRIS = {
      id = "SPRITE_KRIS", source = "ROM:KrisSpriteGFX",
      image = "assets/generated/sprites/kris.png",
      frames = 96 / 16, walker = true,
    },
  }
  self:write("sprites", out)
  self:tick("Player sprite", 1, 1)
  return out
end
```

- [ ] **Step 4: Stamp `field.playerSprites.walkAlt`**

In `src/import/RomExtractorGen2.lua`'s `extractField` function, change:

```lua
    playerSprites = { walk = "SPRITE_CHRIS" },
```

to:

```lua
    playerSprites = { walk = "SPRITE_CHRIS", walkAlt = "SPRITE_KRIS" },
```

- [ ] **Step 5: Verify the file loads and run the full quick suite**

```bash
luajit -e "assert(loadfile('src/import/RomExtractorGen2.lua'))" && echo OK
./scripts/test.sh --quick
```
Expected: `OK`, then `ALL TIERS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json src/import/RomExtractorGen2.lua
git commit -m "$(cat <<'EOF'
Extract Kris's overworld sprite

Straight symbol-swap of the already-working Chris extraction --
KrisSpriteGFX has the identical overworld_sprite macro shape (12
tiles, 2bpp, 384 bytes). Stamps field.playerSprites.walkAlt so
Player.lua's new save.player.gender check (previous task) has a real
sprite to resolve.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Port Gen1's text-decode logic and extract the intro's ~8 text labels

**Files:**
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `_OakText1` (`70:5d35`), `_OakText2` (`70:5da4`), `_OakText4` (`70:5de5`), `_OakText5` (`70:5e51`), `_OakText6` (`71:4000`), `_OakText7` (`71:4026`), `_AreYouABoyOrAreYouAGirlText` (`70:4ca3`) — all plain charmap byte runs, terminated by `$50` (`TX_END`), same opcode set as Gen1. Reading these labels *directly* (not through their `OakTextN`-style wrapper labels, which use a `TX_FAR` redirect this scoped extraction doesn't need to support) sidesteps the one Gen2 text-opcode this port doesn't implement.
- Also needed as a menu-choice string (not full-page text): the gender menu's two choices. Confirmed in pokecrystal (`engine/menus/init_gender.asm`) as a plain 2-item menu with literal "Boy"/"Girl" captions defined in source, not built from a `TX_*`-encoded ROM string — hardcode these two English words as plain Lua strings in the step data (Task 8), exactly the way this project already hardcodes menu chrome text (e.g. `Strings("YOUR NAME?")` in `OakSpeech.lua`) rather than round-tripping them through the text-decode pipeline for two words that are never going to need in-ROM extraction.
- Produces: `crystal/data/generated/text.lua` (currently an empty stub — this task gives it its first real content), a flat map `{["_OakText1"] = "...", ...}`, keyed by the exact label string. Consumed by Task 8's `CrystalIntro.lua`.

- [ ] **Step 1: Port `textGlyph`/`decodeTextCommands` from `RomExtractor.lua`**

Read `src/import/RomExtractor.lua`'s `TEXT_GLYPH_OVERRIDES` table, `RomExtractor:textGlyph`, and `RomExtractor:decodeTextCommands` (search for `decodeTextCommands` — they're a contiguous block, currently around line 1402-1454) in full before starting, so the port below matches the real current code exactly, not this plan's paraphrase.

Add to `src/import/RomExtractorGen2.lua` (a new section, e.g. after `extractPalettes`):

```lua
-- Ported from src/import/RomExtractor.lua's textGlyph/decodeTextCommands
-- (Task 10-era "parallel pipeline, not shared abstraction" precedent --
-- see the walking skeleton's own spec for why this project doesn't
-- factor Gen1/Gen2 text decoding through one shared function). Crystal's
-- text opcode set is confirmed byte-identical to Gen1's (same TX_*
-- values, no compression, verified during planning against
-- home/text.asm's PrintText/PlaceNextChar), and reading a label's real
-- string body directly (rather than through its OakTextN-style TX_FAR
-- wrapper) never needs the TX_FAR opcode this port omits.
local TEXT_GLYPH_OVERRIDES = {
  [0x4B] = "{_CONT}", [0x4C] = "{SCROLL}",
  [0x6D] = "{COLON}", [0xF0] = "¥",
}

function RomExtractorGen2:textGlyph(value)
  if TEXT_GLYPH_OVERRIDES[value] then return TEXT_GLYPH_OVERRIDES[value] end
  local glyph = self.manifest.charmap[tostring(value)]
    or ("{BYTE:%02X}"):format(value)
  if glyph:sub(1, 1) == "<" and glyph:sub(-1) == ">" then
    return "{" .. glyph:sub(2, -2) .. "}"
  end
  return glyph
end

function RomExtractorGen2:decodeTextCommands(symbol)
  local address = symbol.address
  local out = {}
  for _ = 1, 4096 do
    local command = self.rom:byte(symbol.bank, address)
    address = address + 1
    if command == 0x50 then
      return table.concat(out)
    elseif command == 0 then
      while true do
        local value = self.rom:byte(symbol.bank, address)
        address = address + 1
        if value == 0x50 or value == 0x57 or value == 0x58 or value == 0x5F then
          return table.concat(out)
        end
        out[#out + 1] = self:textGlyph(value)
      end
    else
      error(("%s: unsupported text command $%02X, this port only reads " ..
        "plain-body labels directly (no TX_FAR)"):format(symbol.name, command))
    end
  end
  error(symbol.name .. ": text command stream is too long")
end
```

Note this port intentionally drops Gen1's `substitutions`/`pending` machinery (dynamic RAM-value insertion, e.g. `<PLAYER>` mid-decode) — the ~7 labels this task reads don't need it (confirm by reading their actual decoded output in Step 3 below: if any of them turns out to contain a `command == 1/2/9` byte, STOP and either add the substitution handling back (mirroring Gen1's exactly) or report back — don't guess).

- [ ] **Step 2: Add the label list and the extraction function**

Add to `src/import/RomExtractorGen2.lua`:

```lua
-- The intro's narration + gender-prompt text. Direct symbol reads (see
-- decodeTextCommands's doc comment above) -- no pointer-table sweep, the
-- same "read exactly what's needed, by name" pattern font/palette
-- extraction already established for Gen2.
local INTRO_TEXT_LABELS = {
  "_OakText1", "_OakText2", "_OakText4", "_OakText5", "_OakText6",
  "_OakText7", "_AreYouABoyOrAreYouAGirlText",
}

function RomExtractorGen2:extractIntroText()
  self:beginStage("Intro text")
  local out = {}
  for index, label in ipairs(INTRO_TEXT_LABELS) do
    out[label] = self:decodeTextCommands(self:symbol(label))
    self:tick("Intro text", index, #INTRO_TEXT_LABELS)
  end
  self:write("text", out)
  return out
end
```

- [ ] **Step 3: Add the symbols to the manifest and regenerate**

In `tools/make_rom_manifest_crystal.py`, add all 7 labels to `REQUIRED_SYMBOLS`:

```python
REQUIRED_SYMBOLS = (
    "NewBarkTown_MapAttributes",
    "NewBarkTown_MapEvents",
    "TilesetJohtoGFX",
    "TilesetJohtoMeta",
    "TilesetJohtoColl",
    "ChrisSpriteGFX",
    "KrisSpriteGFX",
    "Font",
    "FontExtra",
    "_OakText1",
    "_OakText2",
    "_OakText4",
    "_OakText5",
    "_OakText6",
    "_OakText7",
    "_AreYouABoyOrAreYouAGirlText",
)
```

Regenerate:
```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal /tmp/pokecrystal \
  --symbols /tmp/pokecrystal/pokecrystal.sym \
  --out tools/rom_manifest_crystal.json
python3 -c "
import json
d = json.load(open('tools/rom_manifest_crystal.json'))
for l in ['_OakText1','_OakText2','_OakText4','_OakText5','_OakText6','_OakText7','_AreYouABoyOrAreYouAGirlText']:
    print(l, d['symbols'][l])
"
```
Expected: 7 `[bank, address]` pairs, matching (in decimal) `_OakText1`→`[112, 23861]`, `_OakText6`→`[113, 16384]`, etc. (bank `$70`=112, `$71`=113).

- [ ] **Step 4: Wire the extraction into `run()`**

In `src/import/RomExtractorGen2.lua`'s `run()`, add the call (position doesn't matter functionally; put it near `extractFont`/`extractPalettes` for readability):

```lua
  results.text = self:extractIntroText()
```

- [ ] **Step 5: Verify the file loads and run the full quick suite**

```bash
luajit -e "assert(loadfile('src/import/RomExtractorGen2.lua'))" && echo OK
./scripts/test.sh --quick
```
Expected: `OK`, then `ALL TIERS PASSED`.

- [ ] **Step 6: Manual spot-check against the real ROM (not the full Task 9 verification — just this task's own data)**

This is worth doing now, before building the UI on top of unverified text, rather than only at the end:

```bash
love .
```
Reimport Crystal, then check the generated save directory's `crystal/data/generated/text.lua` (path logged at launch) contains all 7 labels with plausible English text, no `{BYTE:XX}` fallback glyphs (which would indicate a charmap gap) and no obviously mis-decoded garbage.

- [ ] **Step 7: Commit**

```bash
git add src/import/RomExtractorGen2.lua tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json
git commit -m "$(cat <<'EOF'
Extract the intro's narration and gender-prompt text

Ports Gen1's proven text-decode opcodes (confirmed byte-identical in
Crystal, no compression) into RomExtractorGen2 rather than sharing
RomExtractor.lua's implementation, matching this project's established
parallel-pipeline architecture. Reads the ~7 named ROM labels the
intro needs directly, bypassing their TX_FAR wrapper labels, so no
pointer-table sweep or dynamic-substitution handling is needed for
this scoped set.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Extract Oak's portrait and Wooper's front sprite

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py`
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `PokemonProfPic` (Oak's trainer portrait, bank `$56` addr `$415e`) and `WooperFrontpic` (bank `$55` addr `$7846`) — both LZ3-compressed, 2bpp, decompressed via this Gen2 pipeline's existing `Lz3.decompress`/`ImageWriter.decode2bpp` exactly as `extractTileset` already does.
- Produces: `assets/generated/trainers/oak.png` + `data/generated/trainers.lua`'s `OPP_PROF_OAK.pic` entry; `assets/generated/pokemon/wooper_front.png` + `data/generated/pokemon.lua`'s `WOOPER.frontPic`-equivalent entry (exact field name to match whatever `src/pokemon/Sprites.lua`'s `.path(data, id, "front", opts)` reads — check that function first, see Step 1). Consumed by Task 8's `CrystalIntro.lua`.

- [ ] **Step 1: Research the exact consumption shape before writing extraction code**

Read `src/pokemon/Sprites.lua`'s `path`/`playerPath` functions (already used by `OakSpeech.lua`'s `resolvePic`, e.g. `require("src.pokemon.Sprites").path(game.data, desc.id, "front", { kind = "oak" })`) to find exactly what `data.pokemon.<SPECIES>` and `data.trainers.<ID>` shape it expects for a front/trainer pic path. Match that shape exactly — do not invent a new one. Also confirm via `engine/gfx/load_pics.asm` (already partially researched: `_GetFrontpic` calls with `c = 7*7`) whether `WooperFrontpic`'s compressed data can be decoded as a single static 56×56 2bpp image directly (the base frame of Gen2's animated-pic format), or whether the animated format's first N bytes need special handling before the plain 2bpp decode applies. If genuinely unclear after reading `engine/gfx/load_pics.asm`'s `_GetFrontpic` (non-animated call path) and `pic_animation.asm`, prefer decoding exactly what `_GetFrontpic`'s own code path does (not `GetAnimatedFrontpic`'s), byte for byte, over guessing.

- [ ] **Step 2: Add both symbols to the manifest and regenerate**

Add `"PokemonProfPic"` and `"WooperFrontpic"` to `REQUIRED_SYMBOLS` in `tools/make_rom_manifest_crystal.py`, then:

```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal /tmp/pokecrystal \
  --symbols /tmp/pokecrystal/pokecrystal.sym \
  --out tools/rom_manifest_crystal.json
```

- [ ] **Step 3: Write the extraction**

Add to `src/import/RomExtractorGen2.lua`, mirroring `extractTileset`'s LZ3+2bpp pattern exactly:

```lua
-- Oak's trainer portrait and Wooper's front sprite, both LZ3-compressed
-- 2bpp pics -- same decompress-then-decode2bpp shape extractTileset
-- already uses for TilesetJohtoGFX. Trainer pics aren't animated in Gen2
-- (only Pokemon pics are), so PokemonProfPic is a plain static decode;
-- WooperFrontpic's exact static-frame handling was confirmed against
-- engine/gfx/load_pics.asm during planning (see this task's own research
-- step) -- adjust the decode here if that research found the animated
-- format needs different handling than a plain decode2bpp call.
function RomExtractorGen2:extractIntroPics()
  self:beginStage("Intro portraits")
  local oak = self:symbol("PokemonProfPic")
  local oakCompressed = self.rom:bytes(oak.bank, oak.address, 0x1000)
  local oakRaw = Lz3.decompress(oakCompressed)
  local oakImage = ImageWriter.decode2bpp(oakRaw, 56, 56)
  self:save(oakImage, "trainers/oak.png")
  self:tick("Intro portraits", 1, 2)

  local wooper = self:symbol("WooperFrontpic")
  local wooperCompressed = self.rom:bytes(wooper.bank, wooper.address, 0x1000)
  local wooperRaw = Lz3.decompress(wooperCompressed)
  local wooperImage = ImageWriter.decode2bpp(wooperRaw, 56, 56)
  self:save(wooperImage, "pokemon/wooper_front.png")
  self:tick("Intro portraits", 2, 2)

  local trainers = { OPP_PROF_OAK = {
    id = "OPP_PROF_OAK", source = "ROM:PokemonProfPic",
    pic = "assets/generated/trainers/oak.png",
  } }
  self:write("trainers", trainers)

  local pokemon = { WOOPER = {
    id = "WOOPER", source = "ROM:WooperFrontpic",
    frontPic = "assets/generated/pokemon/wooper_front.png",
  } }
  self:write("pokemon", pokemon)

  return { trainers = trainers, pokemon = pokemon }
end
```

Adjust the `trainers.OPP_PROF_OAK`/`pokemon.WOOPER` field names (`pic`/`frontPic`) to match exactly what Step 1's research into `src/pokemon/Sprites.lua` found, if it differs from this sketch — this code block is a starting point, not a substitute for that research.

Remove `"trainers"` and `"pokemon"` from `STUB_MODULES` (search for the list near the top of the file) now that both have real content — leaving them in would let `extractStubs()` overwrite this task's work with empty tables.

- [ ] **Step 4: Wire into `run()`**

```lua
  local intro = self:extractIntroPics()
  results.trainers = intro.trainers
  results.pokemon = intro.pokemon
```

- [ ] **Step 5: Verify the file loads and run the full quick suite**

```bash
luajit -e "assert(loadfile('src/import/RomExtractorGen2.lua'))" && echo OK
./scripts/test.sh --quick
```
Expected: `OK`, then `ALL TIERS PASSED`.

- [ ] **Step 6: Manual spot-check**

```bash
love .
```
Reimport, and directly open the generated `assets/generated/trainers/oak.png` and `assets/generated/pokemon/wooper_front.png` files (from the save directory logged at launch) in an image viewer. Expected: recognizable Oak portrait and Wooper sprite, not garbled pixels (a garbled image means the static/animated frame handling from Step 1 needs revisiting).

- [ ] **Step 7: Commit**

```bash
git add src/import/RomExtractorGen2.lua tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json
git commit -m "$(cat <<'EOF'
Extract Oak's portrait and Wooper's front sprite

Both LZ3-compressed 2bpp pics, decoded with this pipeline's existing
decompressor exactly as the tileset extraction already does. First
species/trainer-pic content this Gen2 work has ever produced --
scoped to exactly the one demo species and one portrait the intro
needs, not a general Pokedex/trainer roster.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Extract Wooper's cry

**Files:**
- Create: a small addition to `tools/make_rom_manifest_crystal.py` resolving the two-level cry indirection from readable source
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `PokemonCries` (bank `$3c` addr `$6787`, 6-byte rows: `dw cryIndex, pitch, length`, one row per species in dex order) and the `Cries` pointer table (`audio/cry_pointers.asm`, `dba`-style 3-byte `{bank, address}` entries per `CRY_*` index, with `Cry_Wooper`'s own entry already confirmed) — resolve the `CRY_WOOPER` → `{bank, address}` step once from readable source at manifest-build time (mirroring the palette spec's index-resolution precedent), so the runtime extractor only needs Wooper's own `PokemonCries` row (a direct symbol-relative read) plus the pre-resolved header location.
- Produces: `data/generated/audio.lua`'s `cries.WOOPER = {header = {bank, address}, pitch, length}` (matching Gen1's existing shape exactly, confirmed by reading `src/import/RomExtractor.lua`'s `extractAudio`) and `assets/generated/audio/programs.bin` (a single 16KB dump of ROM bank `$3c`, which happens to contain both `PokemonCries` and `Cry_Wooper`'s own 3-channel program). Consumed by Task 8's `CrystalIntro.lua` via `Sound.playCry(game.data, "WOOPER")` (the existing, unmodified Gen1 cry-playback path).

- [ ] **Step 1: Research and confirm the exact byte layout before writing code**

Read, in the local pokecrystal checkout:
- `data/pokemon/cries.asm` (the `PokemonCries` table: `mon_cry index, pitch, length` per species, `dw` x3 = 6 bytes/row, `table_width MON_CRY_LENGTH`) — confirm Wooper's row position (species dex order; cross-check `constants/pokemon_constants.asm`'s `WOOPER` constant value against how `PokemonCries` is ordered) and that `index` in each row is a `CRY_*` constant name, not a raw pointer.
- `audio/cry_pointers.asm`'s `Cries:` table and its `dba Cry_Wooper` entry, and `constants/cry_constants.asm` (or wherever `CRY_WOOPER`'s numeric value is defined) to get the exact index needed to pick the right `Cries` row.
- Confirm `Cry_Wooper`, `Cry_Wooper_Ch5`, `Cry_Wooper_Ch6`, `Cry_Wooper_Ch8` (the actual 3-channel program) and `PokemonCries` are all within the same ROM bank (`$3c`, per planning research) — if any channel sub-track turns out to live in a different bank, that bank needs dumping too; verify, don't assume.

Also read `src/core/ChipSynth.lua`'s `loadBanks`/`romByte` (confirmed during planning: `data.audio.programFile` + `data.audio.bankOrder`, a list of original ROM bank numbers whose 16KB slices are concatenated in order into the dumped file) and `src/import/RomExtractor.lua`'s `extractAudio` (the `cries[species] = {header, pitch, length}` shape) in full, so this task's output matches that consumption exactly.

- [ ] **Step 2: Resolve the two-level indirection once, from readable source, at manifest-build time**

In `tools/make_rom_manifest_crystal.py`, add a small resolver (structure it as a function, e.g. `resolve_wooper_cry(pokecrystal)`, following this file's existing style) that:
1. Parses `audio/cry_pointers.asm`'s `Cries:` table to find `Cry_Wooper`'s position, and resolves that to a `{bank, address}` pair the same way `parse_tile_groups`/`parse_outdoor_index` in `tools/extract_gen2/palettes.py` already parse `dw`/`db`-style tables from source text (reuse that module's parsing conventions, don't invent new ones) -- OR, more directly, since the symbol table already resolves `Cry_Wooper` (add it to `REQUIRED_SYMBOLS` alongside `PokemonCries`), just use the already-resolved `Cry_Wooper` symbol's `[bank, address]` directly instead of re-deriving it from the pointer table's source text. Prefer this simpler path if `Cry_Wooper` is independently addressable as its own symbol (already confirmed: bank `$3c` addr `$6df6`) -- there's no need to parse the indirection at all if the final target is already a named, resolvable symbol.
2. Parses `data/pokemon/cries.asm`'s `PokemonCries` table for Wooper's row specifically (matching the `mon_cry` macro invocations, `index, pitch, length`), OR, simpler still: since this only needs ONE species' pitch/length pair, just read Wooper's specific `mon_cry` line directly (its position in the table = Wooper's dex-order index, confirm this against `constants/pokemon_constants.asm`).

Given `Cry_Wooper`'s bank:address is already directly resolvable as a plain symbol, Step 2's simplest correct implementation may not need any new Python parsing logic at all beyond reading `pitch`/`length` off Wooper's one `mon_cry` line in `data/pokemon/cries.asm` (a single regex-matched line, not a full table parse) -- prefer the simplest approach that's still correct over building general machinery this scoped feature doesn't need.

Add the resolved `{"cryHeader": {"bank": ..., "address": ...}, "cryPitch": ..., "cryLength": ..., "cryBank": ...}`-shaped (exact key names at the implementer's discretion, matching this file's existing naming style) data to the manifest's `data` dict in `main()`.

- [ ] **Step 3: Regenerate the manifest and verify**

```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal /tmp/pokecrystal \
  --symbols /tmp/pokecrystal/pokecrystal.sym \
  --out tools/rom_manifest_crystal.json
cat tools/rom_manifest_crystal.json | python3 -c "import json,sys; d=json.load(sys.stdin); print({k:v for k,v in d.items() if 'cry' in k.lower()})"
```
Expected: sane, non-zero pitch/length values and a `{bank: 60, address: 28150}` (`0x3c:0x6df6`)-shaped header location.

- [ ] **Step 4: Write the runtime extraction**

Add to `src/import/RomExtractorGen2.lua`:

```lua
-- Wooper's cry: one 16KB dump of ROM bank $3c (which happens to contain
-- both PokemonCries and Cry_Wooper's own 3-channel program -- confirmed
-- during planning), mirroring src/core/ChipSynth.lua's existing
-- programFile/bankOrder consumption exactly. Gen1's equivalent
-- (RomExtractor.lua:extractAudio) dumps three whole banks because it
-- extracts every species' cry plus the full music engine; this only
-- ever needs Wooper's, so one bank suffices. self.rom.data is the raw
-- ROM byte string (Rom.lua's own field); Rom.offset(bank, 0x4000)
-- gives the file offset of that bank's first byte -- the exact same
-- self.rom.data:sub(...) technique RomExtractor.lua:extractAudio
-- already uses for its own (larger) bank dump, not a new API.
function RomExtractorGen2:extractCry()
  self:beginStage("Wooper cry")
  local bank = 0x3c
  local first = Rom.offset(bank, 0x4000) + 1
  local raw = self.rom.data:sub(first, first + 0x3FFF)
  local CacheFs = require("src.import.CacheFs")
  local ok, writeError = CacheFs.write("assets/generated/audio/programs.bin", raw)
  if not ok then error("could not write audio program: " .. tostring(writeError)) end
  local audio = {
    programFile = "assets/generated/audio/programs.bin",
    bankOrder = { bank },
    cries = {
      WOOPER = {
        header = self.manifest.cryHeader,
        pitch = self.manifest.cryPitch,
        length = self.manifest.cryLength,
      },
    },
  }
  self:write("audio", audio)
  self:tick("Wooper cry", 1, 1)
  return audio
end
```

Confirm `Rom` (the module, not just `self.rom` the instance) is already `require`d at the top of `RomExtractorGen2.lua` (it is, for `Rom.new(romData)` in the constructor) so `Rom.offset` is directly callable.

Remove `"audio"` from `OPTIONAL`... no -- `audio` is already optional in `Data.lua` (confirmed during planning, alongside `palettes`/`icons`), so no `Data.lua` changes are needed; just don't leave `"audio"` in `STUB_MODULES` if it's there (check; if Crystal's `STUB_MODULES` list never included `"audio"` at all, since it's optional and simply absent today, there's nothing to remove).

- [ ] **Step 5: Wire into `run()`**

```lua
  results.audio = self:extractCry()
```

- [ ] **Step 6: Verify the file loads and run the full quick suite**

```bash
luajit -e "assert(loadfile('src/import/RomExtractorGen2.lua'))" && echo OK
./scripts/test.sh --quick
```
Expected: `OK`, then `ALL TIERS PASSED`.

- [ ] **Step 7: Manual verification**

```bash
love .
```
Reimport. This task alone has no UI trigger yet (that's Task 8) -- verify instead via a small scratch script or the Lua console (if available) calling `Sound.playCry(Game.data, "WOOPER")` after boot, or defer this check to Task 9's full manual verification once `CrystalIntro.lua` exists to trigger it naturally. If deferring, note that explicitly rather than silently skipping it.

- [ ] **Step 8: Commit**

```bash
git add src/import/RomExtractorGen2.lua tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json
git commit -m "$(cat <<'EOF'
Extract Wooper's cry

Mirrors Gen1's existing cry data shape (header/pitch/length) and
ChipSynth's programFile/bankOrder consumption exactly, so playback
goes through the same, unmodified chip-synth engine. Only one 16KB
ROM bank needs dumping (vs Gen1's three), since this only ever needs
Wooper's cry, not the full music/SFX engine.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `src/ui/CrystalIntro.lua` — the intro screen

**Files:**
- Create: `src/ui/CrystalIntro.lua`

**Interfaces:**
- Consumes: `src/ui/OakSpeech.lua`'s shared instance methods (`say`, `sayText`, `stepText`, `applyPic`, `resolvePic`, `afterReveal`, `revealPic`, `recordAnswer`, `runCry`, `lastPageLines`, `finish`, `update`, `draw`, the `"say"`/`"name"`/`"choice"`/`"pic"`/`"shrink"`/`"fn"` cases of `runStep`) via Lua metatable delegation -- read unmodified, `OakSpeech.lua` itself is never edited by this task. `crystal/data/generated/text.lua` (Task 3), `sprites.lua` (Task 2), `trainers.lua`/`pokemon.lua` (Task 4), `audio.lua` (Task 5).
- Produces: `CrystalIntro.new(game, onDone)` / `CrystalIntro:enter()`, matching the exact `Screens.push`-compatible contract `OakSpeech`/`NoOpScreen` already follow. Consumed by Task 7 (wiring `field.boot.screens.newGame`).

- [ ] **Step 1: Read `OakSpeech.lua` in full before starting**

This task depends entirely on understanding exactly which methods to inherit unchanged and which to override. Read `src/ui/OakSpeech.lua` completely (already read once during planning; re-read now, don't work from memory) before writing any code.

- [ ] **Step 2: Write `CrystalIntro.lua`**

```lua
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
  local demoPath = game.data.pokemon and game.data.pokemon.WOOPER
    and game.data.pokemon.WOOPER.frontPic
  local ok, img = pcall(love.graphics.newImage,
    require("src.render.Assets").resolve(demoPath or ""))
  self.demoPic = ok and img or nil
  self.demoTrueColor = false
  return self
end

function CrystalIntro:runStep(step)
  local kind = step.kind
  if kind == "gender" then
    self:sayText(self:stepText(step), function()
      local Menu = require("src.ui.Menu")
      local items = {
        { label = "BOY", onSelect = function()
          self.game.save.player.gender = "boy"
          self:recordAnswer(step, 1, "BOY", "boy")
          self:advance()
        end },
        { label = "GIRL", onSelect = function()
          self.game.save.player.gender = "girl"
          self:recordAnswer(step, 2, "GIRL", "girl")
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
```

- [ ] **Step 2: Confirm the player's chosen sprite actually applies after naming**

Read how `OakSpeech:finish()` / the surrounding boot flow spawns the actual overworld `Player` instance (trace from `Game.lua`'s `onNewGame` through to wherever `OverworldController.lua:370`'s `Player.new(Game.data, x, y, facing, Game.save)` call — Task 1's own change — actually runs relative to when this screen pops). Confirm `Game.save.player.gender` (set by the "gender" step above) is already assigned by the time `Player.new` runs, so the very first spawn already picks the right sprite (not just sprite changes on the *next* map load). If it's not — if `Player.new` runs once, earlier, before this screen's gender step executes — STOP and report back with what you find; that would mean the gender choice needs to trigger a player-sprite rebuild explicitly (e.g. calling into `OverworldController`'s reload path, similar to how the color plan's `checkTimeOfDay` forces one), which is a real design decision, not a guess to make silently.

- [ ] **Step 3: Verify the file loads**

Run: `luajit -e "assert(loadfile('src/ui/CrystalIntro.lua'))" && echo OK`
Expected: `OK`

- [ ] **Step 4: Run the full quick suite**

Run: `./scripts/test.sh --quick`
Expected: `ALL TIERS PASSED` (this file isn't reachable from any version yet -- Task 7 wires it up -- so this is a pure regression guard).

- [ ] **Step 5: Commit**

```bash
git add src/ui/CrystalIntro.lua
git commit -m "$(cat <<'EOF'
Add CrystalIntro.lua, Crystal's new-game intro screen

Delegates to OakSpeech's shared step-runner mechanics via metatable
inheritance rather than duplicating them -- OakSpeech.lua itself is
untouched, so Gen1's intro carries zero regression risk. Own step
list (gender choice, Oak's narration + Wooper demo, naming, no rival
anything) and a new "gender" step kind OakSpeech has no equivalent
for. Not yet reachable from any version -- wiring is the next task.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Wire the new screen into Crystal's boot flow

**Files:**
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `CrystalIntro.lua` (Task 6, by screen id -- `src/ui/Screens.lua`'s existing convention resolves any unregistered id to `src.ui.<Id>` automatically, confirmed during planning; no registry edit needed).
- Produces: `field.boot.screens.newGame = "CrystalIntro"` in `data/generated/field.lua`, replacing the walking skeleton's `"NoOpScreen"` placeholder.

- [ ] **Step 1: Change the boot screen id**

In `src/import/RomExtractorGen2.lua`'s `extractField`, change:

```lua
      screens = { newGame = "NoOpScreen" },
```

to:

```lua
      screens = { newGame = "CrystalIntro" },
```

- [ ] **Step 2: Verify the file loads and run the full quick suite**

```bash
luajit -e "assert(loadfile('src/import/RomExtractorGen2.lua'))" && echo OK
./scripts/test.sh --quick
```
Expected: `OK`, then `ALL TIERS PASSED`.

- [ ] **Step 3: Commit**

```bash
git add src/import/RomExtractorGen2.lua
git commit -m "$(cat <<'EOF'
Wire CrystalIntro into Crystal's new-game boot flow

field.boot.screens.newGame now points at the real intro (Task 6)
instead of the NoOpScreen placeholder the walking skeleton added
before any text/character-select data existed.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Fixture-backed structural test

**Files:**
- Modify: `tests/run_tests.lua`

**Interfaces:**
- Consumes: `CrystalIntro.lua` (unmodified by this task), `OakSpeech.lua` (unmodified), hand-built fixture data mirroring Tasks 2-5's real output shapes.
- Produces: nothing consumed by a later task; leaf verification.

- [ ] **Step 1: Write the test**

Add a new `do...end` block to `tests/run_tests.lua`'s Gen2 section (after the palette fixture block from the color plan), proving `CrystalIntro`'s step list is well-formed and its overridden `runStep`/`new` behave correctly against hand-built data, without a real ROM. At minimum:

- `CrystalIntro.defaultSteps()` returns a list with a `"gender"`-kind step first, exactly one `"demo"`-kind step, exactly one `"name"`-kind step, and zero steps with `who == "rival"` or any rival-pic/rival-name reference (a direct regression guard for the "no rival naming" non-goal).
- Build a minimal fake `game` (`{ data = { pokemon = { WOOPER = { frontPic = ... } }, text = { ... 7 keys ... }, sprites = {...}, field = {...}, trainers = {...} }, save = { player = {} }, stack = <a fake with :push recording calls> }`) -- reuse whatever fake-game construction pattern the existing `OakSpeech`-adjacent tests in this file (if any) already use; if none exist yet, build the minimal shape `CrystalIntro.new`/`runStep`'s "gender" and "demo" cases actually touch, informed by having read those methods in Task 6.
- Instantiate `CrystalIntro.new(fakeGame, function() ... end)`, drive it through the "gender" step's menu selection (simulate choosing "GIRL"), and assert `fakeGame.save.player.gender == "girl"` afterward -- a direct regression guard for Task 1/6's gender-to-sprite wiring.

Follow this file's established fixture-test conventions exactly (see the font/map/palette blocks above it in the same file): hand-built data only, no ROM, and restore any global state you touch (`GameVersion`, module-level caches) at the end of the block, matching the discipline those earlier blocks already established.

- [ ] **Step 2: Run it and verify it passes**

Run: `luajit tests/run_tests.lua 2>&1 | grep -i "crystal intro"` (or whatever message prefix you used)
Expected: every line starts `ok`.

Then: `./scripts/test.sh --quick` — expect `ALL TIERS PASSED`.

- [ ] **Step 3: Commit**

```bash
git add tests/run_tests.lua
git commit -m "$(cat <<'EOF'
Add fixture-backed structural test for CrystalIntro

Proves the step list has no rival-naming/rival-pic content, has
exactly one gender/demo/name step each, and that choosing a gender
in the fixture actually sets save.player.gender -- a direct
regression guard for the Player.lua sprite-selection wiring.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Manual real-ROM verification

**Files:** none (verification checklist only; this task produces no commit unless it uncovers a bug in an earlier task, in which case fix that task's file and commit there, then re-run this task from Step 1).

**Interfaces:** N/A.

- [ ] **Step 1: Reimport Crystal with the real ROM**

```bash
love .
```
Reimport. Expected: import completes with no error, progress runs through the new "Intro text"/"Intro portraits"/"Wooper cry" stages.

- [ ] **Step 2: Play the intro start to finish**

Press Play, then NEW GAME. Expected, in order: the boy/girl choice appears and is legible; choosing either option proceeds; Oak's portrait appears with legible narration text; the Wooper demo shows Wooper's sprite and plays its cry sound; naming the player works (both the preset list and typing a new name); the closing "ready?" text and shrink-away animation play; the player spawns in New Bark Town.

- [ ] **Step 3: Verify the gender choice actually changed the sprite**

Play through once choosing "GIRL". Expected: the player's overworld sprite in New Bark Town is Kris's, not Chris's. Play through again (a fresh save) choosing "BOY". Expected: Chris's sprite.

- [ ] **Step 4: Verify the chosen name shows up**

Confirm the name entered during naming appears wherever this project already displays the player's name in Crystal (e.g. any status/menu text that reads `save.player.name`, matching how Gen1 already does this).

- [ ] **Step 5: Confirm zero regression to Gen1's intro**

Start a new game on Red, Blue, or Yellow. Expected: Oak's Gen1 intro (welcome, Nidorino demo, player + rival naming, legend text, shrink) behaves exactly as it did before this plan -- no visual, text, or naming differences.

- [ ] **Step 6: If everything above passes, update the spec's status**

Edit `docs/superpowers/specs/2026-08-04-gen2-crystal-intro-design.md`'s `Status:` line from `approved for planning` to `verified against real ROM, <today's date>`, and commit:

```bash
git add docs/superpowers/specs/2026-08-04-gen2-crystal-intro-design.md
git commit -m "$(cat <<'EOF'
Mark the Gen2 (Crystal) new-game intro verified against real ROM

Full intro plays start to finish: gender choice (with the sprite it
picks confirmed to actually apply), Oak's narration and portrait,
the Wooper demo (sprite + cry), naming, and spawn in New Bark Town.
Gen1's own intro confirmed unaffected.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```
