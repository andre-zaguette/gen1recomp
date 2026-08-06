# Gen2 (Crystal) Title Screen — Visuals + Title Music Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Crystal is the active version, the title screen shows Crystal's
own logo/Suicune/crystal-ornament art with its real entrance animation, and
`Music_TitleScreen` plays through the existing, unmodified `ChipSynth.lua`
on channels 1/2/4 (pulse/pulse/noise; channel 3, wave, stays silent — see
Non-goals).

**Architecture:** New `RomExtractorGen2:extractTitle()` /
`:extractTitleMusic()` stages read the title graphics/palette/music
directly from the player's own ROM at import time (mirroring every existing
Gen2 extraction stage). A new `src/audio/CrystalMusicTranscoder.lua`
(sibling to the existing `CrystalCryTranscoder.lua`, not a rewrite of it)
decodes Crystal's real music-channel bytecode into the event-table shape
`src/audio/ChipAsm.lua` already assembles via `ChipAsm.song(...)`. A new
`crystalLayout` branch in `src/ui/TitleState.lua`, parallel to the existing
`yellowLayout` branch, draws the entrance wipe and Suicune's frame-swap loop
with ordinary 2D blitting (no shader, no hardware raster emulation — the
spec's own research already ruled that out).

**Tech Stack:** Lua (LuaJIT `bit` library, LÖVE headless test harness),
Python 3 (manifest builder, regex-based source-text resolution).

## Global Constraints

- `src/core/ChipSynth.lua`, `src/core/ChipAudio.lua`, and `src/core/Sound.lua`
  must show **zero diff** from before this plan (same constraint the cry
  transcoder plan enforced — `ChipAsm.song(...)`'s existing vocabulary is
  sufficient; no engine change needed).
- Channel 3 (wave) is out of scope. Nothing in this plan reads
  `Music_TitleScreen_Ch3`, and the assembled song only carries channels
  1/2/4 — `ChipAsm.song()` tolerates a channel list shorter than 4 (it
  just iterates `spec.channels`, see `src/audio/ChipAsm.lua:359-380`).
- No committed ROM bytes. Title graphics/palette/music *content* is read
  from the player's own ROM at import time; only *structural* facts
  (symbol addresses) are resolved from readable pokecrystal source/symbol
  text at manifest-build time — same split every prior Gen2 task uses.
- `docs/superpowers/specs/2026-08-05-gen2-crystal-title-screen-design.md`
  is the approved spec. This plan's own research corrects two of the
  spec's structural assumptions (both called out below and in Task 2/3):
  the "CRYSTAL VERSION" text is baked into `TitleLogoGFX`'s own pixels,
  not a separate ribbon asset like Red/Blue/Yellow have; and full
  per-region GBC palette tinting of the title screen is deferred (see
  Task 2's note) because it would require integrating with `PaletteFX`'s
  existing general tile-group/time-of-day coloring system
  (`src/render/PaletteFX.lua`), which is real, separate design work
  the spec did not scope.

## Research already done (do not re-derive)

All of the following was confirmed directly against the real ROM
(`roms/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc`) and the local
`pret/pokecrystal` checkout (cloned + built with RGBDS 1.0.3, producing
`pokecrystal.sym` — path referenced below as `<pokecrystal>`).

**Symbol addresses** (bank:address, from `<pokecrystal>/pokecrystal.sym`):

```
TitleSuicuneGFX               43:6f46
TitleLogoGFX                  43:7326
TitleCrystalGFX                43:7cee
TitleScreenPalettes            43:7ede
Music_TitleScreen              3a:7808   (header only — not read directly, see Task 4)
Music_TitleScreen_Ch1          3a:7814   (main body, 345 bytes, through 796c)
Music_TitleScreen_Ch1.sub1     3a:796d   (23 bytes, through 7983)
Music_TitleScreen_Ch1.sub1loop1 3a:7971  (label inside sub1, not a separate window)
Music_TitleScreen_Ch2          3a:7984   (main body, 355 bytes, through 7ae6)
Music_TitleScreen_Ch2.sub1     3a:7ae7   (26 bytes, through 7b00)
Music_TitleScreen_Ch2.sub1loop1 3a:7ae7  (same address as sub1 itself — the loop target is sub1's own first byte)
Music_TitleScreen_Ch3          3a:7b01   (wave channel — NOT read by this plan)
Music_TitleScreen_Ch4          3a:7c5c   (main body, 222 bytes, through 7d39)
Music_TitleScreen_Ch4.loop1    3a:7d40   (label inside the main body, byte offset 0xE4/228 from Ch4's start)
Music_TitleScreen_Ch4.sub1     3a:7d77   (10 bytes, through 7d80)
Music_TitleScreen_Ch4.sub2     3a:7d81   (10 bytes, through 7d8a)
Music_TitleScreen_Ch4.sub3     3a:7d8b   (8 bytes, through 7d92)
Music_TitleScreen_Ch4.sub3loop1 3a:7d8b  (same address as sub3 itself)
Music_TitleScreen_Ch4.sub4     3a:7d93   (11 bytes, through 7d9d)
```

(All addresses through the next symbol's start; RGBDS's `.sub1`-style local
labels are stored fully-qualified in the `.sym` file, e.g.
`Music_TitleScreen_Ch1.sub1` — confirmed `tools/rom_data.py`'s
`SymbolTable.__init__` regex (`^([0-9a-fA-F]{2}):([0-9a-fA-F]{4})\s+(\S+)`)
captures the whole dotted token as one name, so these can go straight into
`REQUIRED_SYMBOLS`/`self:symbol(...)` exactly as written above — no special
handling needed for the dot.)

**"CRYSTAL VERSION" is not a separate asset.** Unlike Red/Blue/Yellow
(which have their own version-ribbon PNG), `engine/movie/title.asm` fills
the attribute map for the text's screen row (`hlbgcoord 5, 9 / ld bc, 11`)
as part of the same pass that lays out `TitleLogoGFX`'s own gradient rows —
the text pixels are baked directly into `TitleLogoGFX` (160×64px). This
plan's Task 2 extracts one logo image, not a logo plus a separate ribbon.

**The command byte table is fully verified against real ROM bytes**, not
inferred from the macro source alone. Dumping
`Music_TitleScreen_Ch1` (bank `3a`, address `7814`) gives:

```
da 00 86 e5 77 db 03 e6 00 02 e1 10 12 ef f0 d8 0c a7 dc a0 d5 03 dc a7 d6 80 01 a0 c7 83
```

which matches, byte for byte, hand-decoding
`macros/scripts/audio.asm`'s macro bodies against the channel's actual
source (`audio/music/titlescreen.asm`):

```
tempo 134            -> da 00 86        (tempo_cmd=$DA, bigdw 134)
volume 7, 7           -> e5 77           (volume_cmd=$E5, dn(7,7))
duty_cycle 3          -> db 03           (duty_cycle_cmd=$DB, db 3)
pitch_offset 2        -> e6 00 02        (pitch_offset_cmd=$E6, bigdw 2)
vibrato 16, 1, 2       -> e1 10 12        (vibrato_cmd=$E1, db 16, dn(1,2))
stereo_panning T, F    -> ef f0           (stereo_panning_cmd=$EF, dn(0xF,0x0))
note_type 12, 10, 7    -> d8 0c a7        (note_type_cmd=$D8, db 12, dn(10,7))
volume_envelope 10, 0  -> dc a0           (volume_envelope_cmd=$DC, dn(10,0))
octave 3               -> d5              (octave_cmd=$D0 + 8-3)
rest 4                 -> 03              (= note 0, 4 = dn(0,3))
volume_envelope 10, 7  -> dc a7
octave 2                -> d6              ($D0 + 8-2)
note G_, 1              -> 80              (G_ = FrequencyTable index 8, dn(8,0))
rest 2                  -> 01              (dn(0,1))
note A_, 1               -> a0              (A_ = index 10, dn(10,0))
note B_, 8               -> c7              (B_ = index 12, dn(12,7))
note G_, 4               -> 83              (dn(8,3))
```

Every byte matches exactly — this is a complete, load-bearing confirmation
of the command table below, not a hypothesis.

**Two corrections vs. what a naive byte-copy would assume** (the same
caliber of gotcha `CrystalCryTranscoder`'s own "square_note passthrough is
wrong" note documented — see `src/audio/CrystalCryTranscoder.lua`'s
docstring):

1. **`sound_call`/`sound_loop` are swapped between dialects.** Crystal
   (`macros/scripts/audio.asm`): `sound_loop_cmd = $FD`,
   `sound_call_cmd = $FE`. ChipAsm/Gen1 (`src/audio/ChipAsm.lua`'s
   `E.call`/`E.loop`): `call` emits `$FD`, `loop` emits `$FE`. Confirmed
   against real bytes: `Music_TitleScreen_Ch1.sub1`'s
   `sound_loop 5, .sub1loop1` compiles to `fd 05 71 79` (count 5, target
   address `0x7971` little-endian) — `$FD` here is unambiguously
   Crystal's `sound_loop`, the opposite of what its numeric value means in
   ChipAsm. **Do not byte-copy these two command bytes.**
2. **The note/rest/drum pitch nibble is offset by one, and REST reuses
   pitch 0 on every channel** (not a separate command range).
   `audio/notes.asm`'s `FrequencyTable` is authoritative: index 0 = `__`
   (silence, `dw 0`), index 1 = `C_`, index 2 = `C#`, ... index 12 = `B_`,
   then the table repeats for the next octave. Crystal's `rest` macro is
   literally `note 0, \1` — reusing pitch-nibble 0 as the rest marker,
   confirmed above (`rest 4` → `03` → `dn(0,3)`, and `rest 2` → `01`).
   ChipAsm's own scheme is different: `E.note` uses pitch 0-11 = C..B
   directly, and rest is a **separate** `$C0-$CF` byte range
   (`src/audio/ChipAsm.lua`'s `E.rest`), not pitch-nibble 0. So: a Crystal
   note byte's high nibble `N` decodes to `{rest = length}` when `N == 0`;
   otherwise, on a pulse channel (hw 1/2), `{pitch = N - 1, len = length}`
   (`Cursor:pitch` accepts an explicit numeric `event.pitch` 0-11 directly,
   confirmed in `src/audio/ChipAsm.lua:63-72` — no need to go through note
   names). On the noise channel (hw 4), `N == 0` is still rest (`rest` is
   channel-agnostic in Crystal's own macro set), and `N > 0` decodes to
   `{drum = N, len = length}` — **no** `-1` offset here: because pitch-nibble
   0 is unconditionally rest in Crystal's own dialect, nothing in the real
   data can ever address "drum 0", so there is no off-by-one to correct
   for on the noise channel (unlike the chromatic pitch table, which the
   `FrequencyTable` proves is 1-indexed).

**`note_type` is a 2-3 byte command in Crystal but a 1-2 byte command in
ChipAsm — same semantics, different packing**, exactly the kind of
structural gap `CrystalCryTranscoder` already handles for `square_note`/
`noise_note`. Crystal: `db note_type_cmd($D8); db speed; [dn(volume, fade)
if given]`. ChipAsm's own `E.notetype`: `db 0xD0 + speed` (speed folded
into the command byte itself, one byte), then `db volume*16+fade` for
pulse/wave channels, no second byte for noise (hw==4). Confirmed against
Ch4's real bytes (`drum_speed 12` compiles to `d8 0c` with **no** third
byte, since `drum_speed` calls `note_type` with only one argument —
`macros/scripts/audio.asm`'s `_NARG >= 2` gate skips the volume/fade byte).
Decode into the semantic event `{notetype = {speed, volume, fade}}` (or
just `{speed = ...}` implied 0/0 on noise, since ChipAsm's own emitter
already skips the second byte for `hw == 4`) and let `ChipAsm.lua` re-pack
it in its own scheme.

**`volume_envelope` has no direct ChipAsm event.** It changes volume/fade
without touching the note-length "speed" divider `note_type` also carries.
ChipAsm's vocabulary only exposes volume/fade bundled inside a `notetype`
event (which always re-specifies speed too). The transcoder tracks the
most recently seen `note_type`/`drum_speed` speed value as internal state
(defaulting to `12`, the standard "fresh channel" value used throughout
`audio/music/titlescreen.asm`) and re-emits a full `{notetype = {speed =
<tracked>, volume, fade}}` event whenever a bare `volume_envelope` command
is decoded. This is a semantic-equivalence choice (not a literal 1:1
opcode mapping) — call this out in the module's own comments so a future
reader isn't confused about why `volume_envelope` produces a `notetype`
event.

**Control flow / labels.** `sound_call`/`sound_loop`'s address operand is
a raw absolute ROM address (2-byte little-endian, confirmed above:
`fd 05 71 79` → target `0x7971`), not a channel-relative offset. Three
distinct shapes appear across Ch1/Ch2/Ch4, all of which the transcoder
must resolve via a single `labels: {[address] = name}` map built by
`RomExtractorGen2:extractTitleMusic()` from the manifest's own symbol
addresses (Task 4):
- **External subroutine call** (Ch1's main body: `sound_call .sub1`,
  three times) — target address is `Music_TitleScreen_Ch1.sub1`'s own
  start, decoded into a separate `{bytes=..., baseAddress=...}` window and
  assembled as a named `ChipAsm` subroutine (`spec.subroutines.sub1`).
- **Self-loop where the label is the subroutine's own first byte**
  (Ch1's `.sub1`/`.sub1loop1` are two labels at *different* addresses
  inside `sub1` — `sub1loop1` sits 4 bytes into `sub1`, after one
  `note_type`+`note` pair; Ch2's `.sub1`/`.sub1loop1` are the *same*
  address — the loop covers all of `sub1`; Ch4's `.sub3`/`.sub3loop1` are
  also the same address). The transcoder emits a `{label = name}` marker
  event the instant its running absolute address matches a key in
  `labels`, so both shapes (label mid-subroutine vs. label at the
  subroutine's own start) fall out of the same mechanism with no special
  case.
- **Self-loop inside the main body itself** (Ch4's `.loop1`, at byte
  offset 228 into its own main body, looped back to via
  `sound_loop 6, .loop1` near the end of that same body) — same
  `{label=name}` mechanism, just with `loop1`'s address included in the
  `labels` map passed to the *main body's* `decodeChannel` call rather
  than a subroutine's.

---

### Task 1: Manifest additions — title graphics/palette and music channel/subroutine symbols

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py`
- Modify: `tools/rom_manifest_crystal.json` (regenerated, not hand-edited)

**Interfaces:**
- Produces: new entries in the manifest's `symbols` map — `TitleSuicuneGFX`,
  `TitleLogoGFX`, `TitleCrystalGFX`, `TitleScreenPalettes`,
  `Music_TitleScreen_Ch1`, `Music_TitleScreen_Ch1.sub1`,
  `Music_TitleScreen_Ch1.sub1loop1`, `Music_TitleScreen_Ch2`,
  `Music_TitleScreen_Ch2.sub1`, `Music_TitleScreen_Ch4`,
  `Music_TitleScreen_Ch4.loop1`, `Music_TitleScreen_Ch4.sub1`,
  `Music_TitleScreen_Ch4.sub2`, `Music_TitleScreen_Ch4.sub3`,
  `Music_TitleScreen_Ch4.sub4` (each `[bank, address]`, same shape every
  other symbol already uses). Tasks 2 and 4 read these via
  `self:symbol("TitleLogoGFX")` etc., exactly like every other
  `self:symbol(...)` call already in `RomExtractorGen2.lua`.

Note: `Music_TitleScreen_Ch2.sub1loop1` and `Music_TitleScreen_Ch4.sub3loop1`
are **not** added — both share their subroutine's own start address (see
Research above), so `self:symbol("Music_TitleScreen_Ch2.sub1")`'s address
already covers them; Task 4 builds the `labels` map by hand from the
symbols it does have, not by looking up every dotted variant.

- [ ] **Step 1: Add the new symbols to `REQUIRED_SYMBOLS`**

In `tools/make_rom_manifest_crystal.py`, extend the `REQUIRED_SYMBOLS`
tuple (after the existing `Cry_Wooper_Ch8` entry):

```python
    # Title screen graphics + palette (engine/movie/title.asm). One logo
    # image carries the "CRYSTAL VERSION" text baked into its own pixels
    # -- unlike Red/Blue/Yellow, Crystal has no separate ribbon asset (see
    # docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md's
    # "Research already done" section).
    "TitleSuicuneGFX",
    "TitleLogoGFX",
    "TitleCrystalGFX",
    "TitleScreenPalettes",
    # Music_TitleScreen's pulse (Ch1/Ch2) and noise (Ch4) channels, plus
    # every subroutine they sound_call/sound_loop into. Ch3 (wave) is
    # deliberately absent -- out of scope, see the plan's Non-goals.
    # Addresses confirmed against pokecrystal.sym; see the plan's
    # "Research already done" section for the full byte-level decode this
    # is built from.
    "Music_TitleScreen_Ch1",
    "Music_TitleScreen_Ch1.sub1",
    "Music_TitleScreen_Ch1.sub1loop1",
    "Music_TitleScreen_Ch2",
    "Music_TitleScreen_Ch2.sub1",
    "Music_TitleScreen_Ch4",
    "Music_TitleScreen_Ch4.loop1",
    "Music_TitleScreen_Ch4.sub1",
    "Music_TitleScreen_Ch4.sub2",
    "Music_TitleScreen_Ch4.sub3",
    "Music_TitleScreen_Ch4.sub4",
```

- [ ] **Step 2: Regenerate the manifest**

```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal <path-to-your-pokecrystal-checkout> \
  --symbols <path-to-your-pokecrystal-checkout>/pokecrystal.sym
```

Expected: `wrote tools/rom_manifest_crystal.json`. Confirm the diff adds
exactly the 15 new `symbols` entries above (decimal `[bank, address]` pairs
— e.g. `TitleLogoGFX: [67, 29478]` is the decimal form of `43:7326`) with
**no other lines changed**.

- [ ] **Step 3: Commit**

```bash
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json
git commit -m "gen2: resolve title screen and title music symbols"
```

---

### Task 2: `RomExtractorGen2:extractTitle()` — graphics + palette

**Files:**
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `Lz3.decompress(data)` (existing, `src/import/Lz3.lua:25` —
  takes the raw compressed byte array `self.rom:bytes(...)` returns,
  returns a raw decompressed byte array), `ImageWriter.decode2bpp(raw,
  width, height, transparent)` (existing, `src/import/ImageWriter.lua:20`),
  `self:symbol(name)`, `self.rom:bytes(bank, address, length)`,
  `self.rom:word(bank, address)`, `self:save(image, relative)`,
  `self:write(name, value)` (all existing, same as every other extraction
  method in this file).
- Produces: `RomExtractorGen2:extractTitle()`, called from `:run()`,
  writing into `data/generated/field.lua`'s `title` key — the exact shape
  `src/ui/TitleState.lua:144-162` already reads (`self.title = game.data.field
  and game.data.field.title`). New keys this task adds:
  `title.logo` (path string, `assets/generated/title/logo.png`),
  `title.suicune` (path string, `assets/generated/title/suicune.png` — the
  raw 128×128 sheet; Task 5 slices frames from it at draw time),
  `title.crystalOrnament` (path string,
  `assets/generated/title/crystal.png`), `title.palette` (a `{bg = {...8
  palettes...}, obj = {...8 palettes...}}` table, each palette an array of
  4 `{r,g,b}` 0-255 tables — same shape `RomExtractor.lua:895-937`'s
  `extractPalettes` already produces for Gen1, extracted for completeness
  but **not yet consumed by any draw code** — see the note below).

`extractField` (existing, `RomExtractorGen2.lua:494`) already returns the
`{boot = {...}}` table this writes into `data.field`; this task adds a
sibling `title` key to that same table rather than replacing anything.

**Note on scope (plan correction vs. the spec):** the spec's Architecture
section did not fully resolve how the title's palette gets applied to the
screen. Reading `src/render/PaletteFX.lua` (its `PaletteFX.checkTimeOfDay`,
`gbcPack()`, and tile-group/time-of-day cache invalidation machinery
around lines 895-945) shows Crystal already has a real, general, tile-group
-based GBC coloring system — a materially different mechanism than a flat
16-palette title screen needs (Gen1's own `sgbPalettes` zone approach is
closer in shape, but that's SGB-specific and doesn't apply to a GBC-only
game). Integrating the title screen with `PaletteFX`'s general system is
real, separate design work this plan does not attempt. This task extracts
`title.palette`'s raw bytes because it is cheap and will be needed by
whatever follow-on does that integration, but Task 5's `crystalLayout`
draw code renders the plain decoded PNGs with no additional tinting pass —
same as how Suicune/logo/crystal-ornament are already flat 2bpp/DMG
grayscale-shaded images, consistent with how `extractFont`/`extractIntroPics`
already decode Crystal graphics in this file (no CGB color baked in yet
anywhere in `RomExtractorGen2.lua`).

- [ ] **Step 1: Add `extractTitle`**

Add after `extractCry` (mirrors that method's placement and comment style):

```lua
-- Title screen art (engine/movie/title.asm): the Pokemon logo (with
-- "CRYSTAL VERSION" baked into its own pixels -- Crystal has no separate
-- ribbon asset, unlike Red/Blue/Yellow), the running-Suicune tile sheet,
-- the falling crystal ornament, and the title's 16 GBC palettes (8 BG + 8
-- OBJ). See docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md.
function RomExtractorGen2:extractTitle()
  self:beginStage("Title screen")

  local suicune = self:symbol("TitleSuicuneGFX")
  local suicuneRaw = Lz3.decompress(self.rom:bytes(suicune.bank, suicune.address, 0x1000))
  local suicuneImage = ImageWriter.decode2bpp(suicuneRaw, 128, 128)
  self:save(suicuneImage, "title/suicune.png")
  self:tick("Title screen", 1, 4)

  local logo = self:symbol("TitleLogoGFX")
  local logoRaw = Lz3.decompress(self.rom:bytes(logo.bank, logo.address, 0x1000))
  local logoImage = ImageWriter.decode2bpp(logoRaw, 160, 64)
  self:save(logoImage, "title/logo.png")
  self:tick("Title screen", 2, 4)

  local crystalGfx = self:symbol("TitleCrystalGFX")
  local crystalRaw = Lz3.decompress(self.rom:bytes(crystalGfx.bank, crystalGfx.address, 0x1000))
  local crystalImage = ImageWriter.decode2bpp(crystalRaw, 48, 80)
  self:save(crystalImage, "title/crystal.png")
  self:tick("Title screen", 3, 4)

  -- 16 GBC palettes (8 BG, 8 OBJ), 4 colors each, RGB555 packed 2
  -- bytes/color -- same layout and scale5 conversion RomExtractor.lua's
  -- extractPalettes already uses for Gen1's SuperPalettes/CGBBasePalettes.
  local palTable = self:symbol("TitleScreenPalettes")
  local function scale5(value) return math.floor(value * 255 / 31 + 0.5) end
  local function readPalettes(startIndex, count)
    local out = {}
    for index = 0, count - 1 do
      local colors = {}
      for color = 0, 3 do
        local value = self.rom:word(palTable.bank,
          palTable.address + (startIndex + index) * 8 + color * 2)
        colors[#colors + 1] = {
          scale5(bit.band(value, 0x1F)),
          scale5(bit.band(bit.rshift(value, 5), 0x1F)),
          scale5(bit.band(bit.rshift(value, 10), 0x1F)),
        }
      end
      out[#out + 1] = colors
    end
    return out
  end
  local palette = { bg = readPalettes(0, 8), obj = readPalettes(8, 8) }
  self:tick("Title screen", 4, 4)

  local title = {
    logo = "assets/generated/title/logo.png",
    suicune = "assets/generated/title/suicune.png",
    crystalOrnament = "assets/generated/title/crystal.png",
    palette = palette,
  }
  return title
end
```

- [ ] **Step 2: Wire it into `extractField` / `:run()`**

`extractField` (existing, `RomExtractorGen2.lua:494-...`) builds the
`{boot = {...}}` table this writes as `data.field`. Change its return to
include the new `title` key, and call `extractTitle` from `:run()` before
`extractField` so the result is available to fold in:

```lua
  results.text = self:extractIntroText()
  local title = self:extractTitle()
  results.field = self:extractField(results.maps.NEW_BARK_TOWN, title)
```

And in `extractField`'s signature/body, accept and fold in the new
parameter:

```lua
function RomExtractorGen2:extractField(newBarkTown, title)
  local spawn = assert(newBarkTown.warps[1],
    "NewBarkTown has no warps to derive a walkable spawn tile from")
  local out = {
    boot = {
      startMap = "NEW_BARK_TOWN", startX = spawn.x, startY = spawn.y,
```

(Keep every existing line inside `extractField` exactly as-is; only the
function's own parameter list changes and the returned table gains a
sibling `title = title` key alongside the existing `boot` key — read the
existing function's tail before editing to match its exact closing
brace/return shape.)

- [ ] **Step 3: Bump `STAGE_COUNT`**

```lua
local STAGE_COUNT = 8
```

- [ ] **Step 4: Run the existing Gen2 fixture tests**

```bash
luajit tests/run_tests.lua 2>&1 | tail -40
```

Expected: still green (no existing behavior changed; this task only adds a
new function, a new `:run()` call, and one new parameter threaded through
`extractField`).

- [ ] **Step 5: Commit**

```bash
git add src/import/RomExtractorGen2.lua
git commit -m "gen2: extract Crystal's title screen graphics and palette"
```

---

### Task 3: `CrystalMusicTranscoder` — decode Crystal music bytecode, re-encode via ChipAsm

**Files:**
- Create: `src/audio/CrystalMusicTranscoder.lua`
- Modify: `tests/run_tests.lua` (new fixture block)

**Interfaces:**
- Consumes: `src/audio/ChipAsm.lua`'s existing `ChipAsm.song(spec)` where
  `spec = {channels = {{hw = 1|2|4, program = {...events...}, subroutines
  = {name = {...events...}, ...}}, ...}}` (see `src/audio/ChipAsm.lua:359-
  406`). Event shapes used: `{label = name}`, `{tempo = 0-0xFFFF}`,
  `{duty = 0-3}`, `{notetype = {speed=0-15, volume=0-15, fade=-7..7}}`,
  `{octave = 1-8}`, `{vibrato = {delay, depth, rate}}`, `{pan = 0-255}`,
  `{rest = length}`, `{pitch = 0-11, len = length}`, `{drum = id, len =
  length}`, `{call = name}`, `{loop = {count, to = name}}`, `{ret = true}`
  — all already implemented by `ChipAsm.lua`'s `emitters()`.
- Produces:
  `CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels) ->
  events` and `CrystalMusicTranscoder.buildSong(channels) -> {chip =
  {...}}` (`channels = {{hw = 1|2|4, bytes, baseAddress, subroutines =
  {name = {bytes, baseAddress}, ...}, labels = {[address] = name, ...}},
  ...}`). Task 4 calls `buildSong` with the byte windows and label maps it
  builds from the manifest symbols Task 1 added.

- [ ] **Step 1: Write `src/audio/CrystalMusicTranscoder.lua`**

```lua
-- Translates Pokemon Crystal's real music-engine bytecode
-- (Music_TitleScreen's pulse/noise channels) into the Lua event-table
-- shape src/audio/ChipAsm.lua already knows how to assemble into a
-- Gen1-dialect chip program, then calls ChipAsm.song(...). Sibling to
-- src/audio/CrystalCryTranscoder.lua, not a rewrite of it -- cries and
-- songs use different enough opcode sets (this module's vocabulary is a
-- strict superset: tempo, volume, pitch_offset, vibrato, stereo_panning,
-- note_type, volume_envelope, octave, sound_call/loop/ret, on top of the
-- plain note/duty/duty_cycle_pattern the cry transcoder already covers)
-- that a shared decoder would be premature abstraction -- same "parallel
-- pipeline" precedent the walking skeleton's own spec established. See
-- docs/superpowers/specs/2026-08-05-gen2-crystal-title-screen-design.md
-- and docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md's
-- "Research already done" section for the verified opcode table and the
-- two dialect corrections (sound_call/sound_loop are byte-swapped vs.
-- ChipAsm; the note pitch nibble is offset by one and REST reuses pitch
-- 0 on every channel) this is built from. Channel 3 (wave) is out of
-- scope: this module only handles pulse (hw 1/2) and noise (hw 4).

local bit = require("bit")
local ChipAsm = require("src.audio.ChipAsm")

local CrystalMusicTranscoder = {}

-- packed low nibble -> signed fade, identical to CrystalCryTranscoder's
-- fadeValue / ChipSynth.lua's fadeValue / ChipAsm.lua's Cursor:fade
local function fadeValue(nibble)
  if bit.band(nibble, 8) ~= 0 then return -bit.band(nibble, 7) end
  return nibble
end

-- Decodes one Crystal-dialect music channel program into a ChipAsm event
-- list. `bytes` is a 1-indexed byte array (Rom:bytes(...)'s shape)
-- starting exactly at `baseAddress` (the absolute ROM address of
-- bytes[1]). `hw` is 1/2 (pulse) or 4 (noise) -- never 3 (wave), which
-- this module does not decode. `labels` is an address -> name map: every
-- time the byte currently being read sits at an address present in
-- `labels`, a {label = name} marker is emitted first (covers both
-- self-referential loop points inside this same window and, when
-- decoding a subroutine, the subroutine's own start). Every sound_call/
-- sound_loop target address is looked up in the same map; a missing
-- entry is a hard error rather than a guess, matching
-- CrystalCryTranscoder's "raise on anything unverified" stance. Stops at
-- sound_ret ($FF, Crystal's own value -- shared with ChipAsm's dialect,
-- unlike sound_call/sound_loop); the returned list's last entry is always
-- {ret = true}.
function CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels)
  labels = labels or {}
  local events = {}
  local i = 1
  local lastSpeed = 12 -- audio/music/titlescreen.asm's own fresh-channel default

  local function targetName(low, high)
    local addr = low + high * 0x100
    local name = labels[addr]
    if not name then
      error(("CrystalMusicTranscoder: sound_call/sound_loop target $%04X " ..
        "has no matching entry in the labels map"):format(addr))
    end
    return name
  end

  while true do
    local addr = baseAddress + i - 1
    if labels[addr] then
      events[#events + 1] = { label = labels[addr] }
    end
    local cmd = bytes[i]
    if cmd == nil then
      error("CrystalMusicTranscoder: ran off the end of the byte window " ..
        "before a sound_ret ($FF) terminator")
    elseif cmd == 0xFF then -- sound_ret_cmd (shared value)
      events[#events + 1] = { ret = true }
      return events
    elseif cmd == 0xDA then -- tempo_cmd
      events[#events + 1] = { tempo = bytes[i + 1] * 0x100 + bytes[i + 2] }
      i = i + 3
    elseif cmd == 0xDB then -- duty_cycle_cmd
      events[#events + 1] = { duty = bytes[i + 1] }
      i = i + 2
    elseif cmd == 0xDC then -- volume_envelope_cmd: no direct ChipAsm event,
      -- re-emitted as a notetype carrying the last-known speed (see the
      -- plan's "Research already done" section)
      local packed = bytes[i + 1]
      events[#events + 1] = { notetype = {
        speed = lastSpeed,
        volume = bit.rshift(packed, 4), fade = fadeValue(bit.band(packed, 0x0F)),
      } }
      i = i + 2
    elseif cmd == 0xD8 then -- note_type_cmd (also drum_speed on hw==4)
      local speed = bytes[i + 1]
      lastSpeed = speed
      if hw == 4 then
        events[#events + 1] = { notetype = { speed = speed, volume = 0, fade = 0 } }
        i = i + 2
      else
        local packed = bytes[i + 2]
        events[#events + 1] = { notetype = {
          speed = speed,
          volume = bit.rshift(packed, 4), fade = fadeValue(bit.band(packed, 0x0F)),
        } }
        i = i + 3
      end
    elseif cmd == 0xE1 then -- vibrato_cmd
      local packed = bytes[i + 2]
      events[#events + 1] = { vibrato = {
        delay = bytes[i + 1],
        depth = bit.rshift(packed, 4), rate = bit.band(packed, 0x0F),
      } }
      i = i + 3
    elseif cmd == 0xE3 then -- toggle_noise_cmd: hw==4 only, this song's
      -- one drum-kit-select byte has no ChipAsm equivalent (ChipSynth's
      -- noise channel doesn't model separate drum kits) and carries no
      -- audible effect on its own -- drop it, matching how this
      -- transcoder already drops other structural-only bytes.
      i = i + 2
    elseif cmd == 0xE6 then -- pitch_offset_cmd: no ChipAsm event exists for
      -- this (Gen1's own dialect has no equivalent concept). Verify
      -- during Step 3's real-ROM listening check whether dropping it
      -- (as this does) sounds acceptably close, since Wooper's cry
      -- precedent shows cross-engine pitch scaling sometimes needs
      -- by-ear correction -- if the title theme sounds detectably
      -- mistuned, revisit this rather than silently shipping it.
      i = i + 3
    elseif cmd == 0xEF then -- stereo_panning_cmd
      events[#events + 1] = { pan = bytes[i + 1] }
      i = i + 2
    elseif cmd < 0xD0 then -- plain note/rest/drum record: dn(pitchOrDrum, length-1)
      local pitchOrDrum = bit.rshift(cmd, 4)
      local length = bit.band(cmd, 0x0F) + 1
      if pitchOrDrum == 0 then
        events[#events + 1] = { rest = length }
      elseif hw == 4 then
        events[#events + 1] = { drum = pitchOrDrum, len = length }
      else
        events[#events + 1] = { pitch = pitchOrDrum - 1, len = length }
      end
      i = i + 1
    elseif cmd == 0xFD then -- sound_loop_cmd (Crystal) -> ChipAsm {loop=...}
      local count = bytes[i + 1]
      events[#events + 1] = { loop = { count = count, to = targetName(bytes[i + 2], bytes[i + 3]) } }
      i = i + 4
    elseif cmd == 0xFE then -- sound_call_cmd (Crystal) -> ChipAsm {call=...}
      events[#events + 1] = { call = targetName(bytes[i + 1], bytes[i + 2]) }
      i = i + 3
    else
      error(("CrystalMusicTranscoder: unsupported opcode $%02X at byte %d " ..
        "(address $%04X) -- outside the set Music_TitleScreen's real " ..
        "channels use"):format(cmd, i, addr))
    end
  end
end

-- channels: array of {hw = 1|2|4, bytes, baseAddress, subroutines =
-- {name = {bytes, baseAddress}, ...} or nil, labels = {[address] = name,
-- ...} or nil}. Returns {chip = {blob, channels, engine = 1}}, ready to
-- sit on data.audio.songs[songName] (src/core/Music.lua's own consumer
-- shape -- confirmed against how src/ui/TitleState.lua:203-209's
-- startMusic already gates on data.audio.songs[song] before calling
-- Music.play).
function CrystalMusicTranscoder.buildSong(channels)
  local specs = {}
  for index, channel in ipairs(channels) do
    local subroutines
    if channel.subroutines then
      subroutines = {}
      for name, sub in pairs(channel.subroutines) do
        subroutines[name] = CrystalMusicTranscoder.decodeChannel(
          sub.bytes, channel.hw, sub.baseAddress, channel.labels)
      end
    end
    specs[index] = {
      hw = channel.hw,
      program = CrystalMusicTranscoder.decodeChannel(
        channel.bytes, channel.hw, channel.baseAddress, channel.labels),
      subroutines = subroutines,
    }
  end
  return ChipAsm.song({ channels = specs })
end

return CrystalMusicTranscoder
```

- [ ] **Step 2: Add the fixture test to `tests/run_tests.lua`**

Append after the existing Gen2 cry transcoder fixture block (added by the
prior cry-transcoder plan — search for `-- Gen2 cry transcoder` to find
its end). This fixture uses `Music_TitleScreen_Ch1`'s real, verified-above
opening bytes plus the full, verified `.sub1` bytes, proving the decoder,
the note/rest/pitch-offset-by-one handling, the `note_type`/
`volume_envelope` handling, and the `sound_call`/`sound_loop` label
resolution all work against real data — not hand-invented fixtures.

```lua
-- ------------------------------------------------- Gen2 music transcoder
-- Music_TitleScreen_Ch1's real opening bytes (main body) plus its full
-- .sub1 (docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md's
-- "Research already done" section has the full verified decode this
-- fixture comes from), fed through CrystalMusicTranscoder, proving the
-- decode produces the exact expected ChipAsm events -- including the
-- pitch-nibble-minus-one correction, the note_type/volume_envelope
-- handling, and sound_call/sound_loop label resolution -- with no ROM
-- needed.
do
  local CrystalMusicTranscoder = require("src.audio.CrystalMusicTranscoder")

  -- Music_TitleScreen_Ch1 (bank $3a, address $7814), first 30 bytes --
  -- tempo/volume/duty_cycle/pitch_offset/vibrato/stereo_panning/
  -- note_type/volume_envelope/octave/rest, then five real notes.
  local ch1Bytes = {
    0xDA, 0x00, 0x86,       -- tempo 134
    0xE5, 0x77,             -- volume 7, 7
    0xDB, 0x03,             -- duty_cycle 3
    0xE6, 0x00, 0x02,       -- pitch_offset 2 (dropped, no event emitted)
    0xE1, 0x10, 0x12,       -- vibrato 16, 1, 2
    0xEF, 0xF0,             -- stereo_panning TRUE, FALSE
    0xD8, 0x0C, 0xA7,       -- note_type 12, 10, 7
    0xDC, 0xA0,             -- volume_envelope 10, 0
    0xD5,                   -- octave 3
    0x03,                   -- rest 4
    0xDC, 0xA7,             -- volume_envelope 10, 7
    0xD6,                   -- octave 2
    0x80,                   -- note G_, 1
    0x01,                   -- rest 2
    0xA0,                   -- note A_, 1
    0xC7,                   -- note B_, 8
    0x83,                   -- note G_, 4
    0xFF,                   -- sound_ret (synthetic terminator for this fixture window)
  }
  local ch1BaseAddress = 0x7814

  local events = CrystalMusicTranscoder.decodeChannel(ch1Bytes, 1, ch1BaseAddress, {})
  eq(events[1].tempo, 134, "Music transcoder: tempo decodes to 134")
  eq(events[2].duty, nil, "Music transcoder: volume event has no duty field")
  check(events[3].duty == 3, "Music transcoder: duty_cycle decodes to 3")
  eq(#events, 13, "Music transcoder: pitch_offset is dropped, 17 commands -> 13 events")
  check(events[4].vibrato and events[4].vibrato.delay == 16
    and events[4].vibrato.depth == 1 and events[4].vibrato.rate == 2,
    "Music transcoder: vibrato 16,1,2 decodes correctly")
  eq(events[5].pan, 0xF0, "Music transcoder: stereo_panning packs to 0xF0")
  check(events[6].notetype and events[6].notetype.speed == 12
    and events[6].notetype.volume == 10 and events[6].notetype.fade == 7,
    "Music transcoder: note_type 12,10,7 decodes correctly")
  check(events[7].notetype and events[7].notetype.speed == 12
    and events[7].notetype.volume == 10 and events[7].notetype.fade == 0,
    "Music transcoder: volume_envelope 10,0 reuses the last note_type speed (12)")
  eq(events[8].octave, 3, "Music transcoder: octave 3")
  eq(events[9].rest, 4, "Music transcoder: rest 4")
  check(events[10].notetype.volume == 10 and events[10].notetype.fade == 7,
    "Music transcoder: volume_envelope 10,7")
  eq(events[11].octave, 2, "Music transcoder: octave 2")
  eq(events[12].pitch, 7, "Music transcoder: note G_ decodes to pitch 7 (G, 0-indexed)")
  eq(events[12].len, 1, "Music transcoder: note G_,1 length")
  eq(events[13].ret, true, "Music transcoder: ends with sound_ret")

  -- Music_TitleScreen_Ch1.sub1 (bank $3a, address $796d), full 23 bytes,
  -- including its internal .sub1loop1 label (offset 4, address $7971)
  -- and its sound_loop 5, .sub1loop1 (target $7971).
  local sub1Bytes = {
    0xD8, 0x0C, 0xC3, -- note_type 12, 12, 3
    0x30,             -- note D_, 1
    0x00,             -- rest 1               <- .sub1loop1 label here ($7971)
    0xD6,             -- octave 2
    0x30,             -- note D_, 1
    0xD7,             -- octave 1
    0xA0,             -- note A_, 1
    0xD6,             -- octave 2
    0x30,             -- note D_, 1
    0xFD, 0x05, 0x71, 0x79, -- sound_loop 5, .sub1loop1 ($7971)
    0x00,             -- rest 1
    0x30,             -- note D_, 1
    0xD7,             -- octave 1
    0xA0,             -- note A_, 1
    0xD8, 0x08, 0xB7, -- note_type 8, 11, 7
    0xFF,             -- sound_ret
  }
  local sub1BaseAddress = 0x796D
  local sub1Labels = { [0x7971] = "sub1loop1" }

  local subEvents = CrystalMusicTranscoder.decodeChannel(
    sub1Bytes, 1, sub1BaseAddress, sub1Labels)
  eq(subEvents[1].notetype.speed, 12, "Music transcoder: sub1 opens with note_type 12,12,3")
  eq(subEvents[2].pitch, 2, "Music transcoder: note D_ decodes to pitch 2")
  eq(subEvents[3].rest, 1, "Music transcoder: sub1 rest 1")
  check(subEvents[4].label == "sub1loop1",
    "Music transcoder: sub1loop1 label emitted at address $7971")
  local loopEvent
  for _, event in ipairs(subEvents) do
    if event.loop then loopEvent = event end
  end
  check(loopEvent and loopEvent.loop.count == 5 and loopEvent.loop.to == "sub1loop1",
    "Music transcoder: sound_loop 5, .sub1loop1 resolves to the label by name")
  check(subEvents[#subEvents].ret == true, "Music transcoder: sub1 ends with sound_ret")

  -- buildSong assembles a full channel (main body calling into a labeled
  -- subroutine) through the real, unmodified ChipAsm.song(...).
  local song = CrystalMusicTranscoder.buildSong({
    {
      hw = 1,
      bytes = ch1Bytes,
      baseAddress = ch1BaseAddress,
      subroutines = { sub1 = { bytes = sub1Bytes, baseAddress = sub1BaseAddress } },
      labels = sub1Labels,
    },
  })
  check(song.chip and song.chip.blob ~= nil, "Music transcoder: buildSong produces a chip blob")
  eq(song.chip.channels[1].number, 1, "Music transcoder: buildSong tags hardware channel 1")
end
```

`check`, `eq` are `tests/run_tests.lua`'s existing shared assertion
helpers, the same ones the neighboring Gen2 cry-transcoder block above
uses — no new helper needed.

- [ ] **Step 3: Run the test**

```bash
luajit tests/run_tests.lua 2>&1 | tail -60
```

Expected: all new "Music transcoder: ..." assertions pass, full existing
suite stays green.

- [ ] **Step 4: Commit**

```bash
git add src/audio/CrystalMusicTranscoder.lua tests/run_tests.lua
git commit -m "gen2: add CrystalMusicTranscoder, translating title music bytecode"
```

---

### Task 4: Wire into `RomExtractorGen2:extractTitleMusic()`

**Files:**
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `CrystalMusicTranscoder.buildSong(channels)` (Task 3),
  `self:symbol(name)`, `self.rom:bytes(bank, address, length)`,
  `self:write(name, value)` (all existing).
- Produces: `RomExtractorGen2:extractTitleMusic()`, called from `:run()`,
  extending `data/generated/audio.lua`'s existing `{cries = {...}}` table
  (written by `extractCry`) with a sibling `songs = {Music_TitleScreen =
  {chip = {...}}}` key — the exact shape
  `src/ui/TitleState.lua:203-209`'s `startMusic` already checks
  (`data.audio.songs[song]`) and `src/core/Music.lua`'s `Music.play(data,
  song)` already expects (confirmed by reading `Music.lua`'s existing
  Gen1 song-playing path — it reads `data.audio.songs[name].chip`, same
  field `ChipAsm.song()` produces).

- [ ] **Step 1: Add the `CrystalMusicTranscoder` require**

```lua
local CrystalMusicTranscoder = require("src.audio.CrystalMusicTranscoder")
```

- [ ] **Step 2: Bump `STAGE_COUNT`**

```lua
local STAGE_COUNT = 9
```

- [ ] **Step 3: Add `extractTitleMusic`**

Add after `extractTitle` (Task 2):

```lua
-- Music_TitleScreen's pulse (Ch1/Ch2) and noise (Ch4) channels, translated
-- from Crystal's bytecode dialect via CrystalMusicTranscoder. Channel 3
-- (wave) is not read -- out of scope, see the plan's Non-goals. Generous
-- byte-window sizes (400/400/300 for the three main bodies, 40/40 for
-- Ch1/Ch2's one subroutine each, 20 each for Ch4's four) are comfortably
-- larger than the real verified spans (345/355/222 and 23/26/10/10/8/11
-- respectively) -- decodeChannel stops at sound_ret regardless of extra
-- trailing bytes in the window, same margin convention extractCry already
-- established.
function RomExtractorGen2:extractTitleMusic()
  self:beginStage("Title music")

  local ch1 = self:symbol("Music_TitleScreen_Ch1")
  local ch1Sub1 = self:symbol("Music_TitleScreen_Ch1.sub1")
  local ch1Sub1Loop1 = self:symbol("Music_TitleScreen_Ch1.sub1loop1")
  local ch1Labels = {
    [ch1Sub1.address] = "sub1",
    [ch1Sub1Loop1.address] = "sub1loop1",
  }

  local ch2 = self:symbol("Music_TitleScreen_Ch2")
  local ch2Sub1 = self:symbol("Music_TitleScreen_Ch2.sub1")
  local ch2Labels = { [ch2Sub1.address] = "sub1" }

  local ch4 = self:symbol("Music_TitleScreen_Ch4")
  local ch4Loop1 = self:symbol("Music_TitleScreen_Ch4.loop1")
  local ch4Sub1 = self:symbol("Music_TitleScreen_Ch4.sub1")
  local ch4Sub2 = self:symbol("Music_TitleScreen_Ch4.sub2")
  local ch4Sub3 = self:symbol("Music_TitleScreen_Ch4.sub3")
  local ch4Sub4 = self:symbol("Music_TitleScreen_Ch4.sub4")
  local ch4Labels = {
    [ch4Loop1.address] = "loop1",
    [ch4Sub1.address] = "sub1",
    [ch4Sub2.address] = "sub2",
    [ch4Sub3.address] = "sub3",
    [ch4Sub4.address] = "sub4",
  }

  local song = CrystalMusicTranscoder.buildSong({
    {
      hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 400),
      subroutines = {
        sub1 = { baseAddress = ch1Sub1.address,
                 bytes = self.rom:bytes(ch1Sub1.bank, ch1Sub1.address, 40) },
      },
      labels = ch1Labels,
    },
    {
      hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 400),
      subroutines = {
        sub1 = { baseAddress = ch2Sub1.address,
                 bytes = self.rom:bytes(ch2Sub1.bank, ch2Sub1.address, 40) },
      },
      labels = ch2Labels,
    },
    {
      hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch4Sub1.address,
                 bytes = self.rom:bytes(ch4Sub1.bank, ch4Sub1.address, 20) },
        sub2 = { baseAddress = ch4Sub2.address,
                 bytes = self.rom:bytes(ch4Sub2.bank, ch4Sub2.address, 20) },
        sub3 = { baseAddress = ch4Sub3.address,
                 bytes = self.rom:bytes(ch4Sub3.bank, ch4Sub3.address, 20) },
        sub4 = { baseAddress = ch4Sub4.address,
                 bytes = self.rom:bytes(ch4Sub4.bank, ch4Sub4.address, 20) },
      },
      labels = ch4Labels,
    },
  })

  self:tick("Title music", 1, 1)
  return song
end
```

- [ ] **Step 4: Fold the song into `data.audio` alongside `extractCry`'s cries**

`extractCry` currently writes `data/generated/audio.lua` directly
(`self:write("audio", audio)`). Change `:run()` to build one combined
`audio` table and write it once:

```lua
  local cries = self:extractCry()
  local titleSong = self:extractTitleMusic()
  results.audio = { cries = cries.cries, songs = { Music_TitleScreen = titleSong } }
  self:write("audio", results.audio)
  self:extractStubs()
```

And remove `extractCry`'s own `self:write("audio", audio)` line (and its
now-redundant `return audio` can stay, since Task 4's caller uses the
return value directly instead) — `extractCry` should end with `return
audio` only, no longer writing the file itself; the combined write above
in `:run()` is now the single place `data/generated/audio.lua` gets
written.

- [ ] **Step 5: Run the existing Gen2 fixture tests**

```bash
luajit tests/run_tests.lua 2>&1 | tail -40
```

Expected: still green.

- [ ] **Step 6: Commit**

```bash
git add src/import/RomExtractorGen2.lua
git commit -m "gen2: extract and translate Music_TitleScreen via RomExtractorGen2"
```

---

### Task 5: `TitleState.lua` — `crystalLayout` branch

**Files:**
- Modify: `src/ui/TitleState.lua`

**Interfaces:**
- Consumes: `GameVersion.isCrystal()` (existing, `src/core/GameVersion.lua:91`),
  `self.title.logo` / `self.title.suicune` / `self.title.crystalOrnament`
  (Task 2's new `field.title` keys, read the same way
  `self.logo`/`self.version` already are at `TitleState.lua:148-152`),
  `data.audio.songs.Music_TitleScreen` (Task 4 — already wired for free:
  `startMusic`'s existing default `self.title.music or
  "Music_TitleScreen"` matches the key Task 4 writes, so no change needed
  in `startMusic` itself).
- Produces: a third top-level layout branch, `self.crystalLayout`,
  alongside the existing Red/Blue path and `self.yellowLayout`.

This task has more open-ended visual-tuning work than Tasks 1-4: the
*data* (entrance timing, Suicune's 4-frame table, the falling-crystal
motion) is fully verified against the real ROM (see Research above and
`engine/movie/title.asm`), but the exact pixel offsets for slicing
Suicune's 4 frames out of the single 128×128 sheet Task 2 extracts depend
on where `LoadSuicuneFrame`'s VRAM tile addresses (`vTiles3`/`vTiles5`,
tiles `$80`/`$88`/`$00`/`$08`) land inside that decoded PNG — verify this
visually against the real game during Step 3, adjusting the quad
coordinates below if the initial guess is off, rather than treating them
as exact.

- [ ] **Step 1: Add the `crystalLayout` flag and asset loads**

In `TitleState.new` (`TitleState.lua:138-193`), alongside the existing
`self.yellow`/`self.yellowPikachu`/etc. block:

```lua
  self.crystal = GameVersion.isCrystal()
  self.suicuneSheet = self.crystal and tryImage(imagePath(title.suicune)
    or "assets/generated/title/suicune.png") or nil
  self.crystalOrnament = self.crystal and tryImage(imagePath(title.crystalOrnament)
    or "assets/generated/title/crystal.png") or nil
  self.crystalLayout = self.crystal and self.suicuneSheet ~= nil
  if self.crystalLayout then
    -- title.asm boot: hSCX starts at 112 (off-screen right / logo band's
    -- alternating-line wipe) and the falling crystal ornament starts at
    -- y=-0x22, both animating in over the same ~28-frame entrance (see
    -- TitleScreenEntrance/AnimateTitleCrystal in engine/menus/intro_menu.asm
    -- and engine/movie/title.asm).
    self.entranceSCX = 112
    self.ornamentY = -0x22
    self.phase = "entrance"
    self.suicuneFrame = 1
    self.suicuneFrameTimer = 0
  end
```

(`self.blue`/`self.yellow` already exist above this point; `self.crystal`
follows the same `GameVersion.is*()` pattern.)

- [ ] **Step 2: Entrance animation, Suicune loop, and draw**

Add the update logic to `TitleState:update` (alongside the existing
`if self.yellowLayout then ... return end` branch near the top of that
function, `TitleState.lua:402-419`):

```lua
  if self.crystalLayout then
    if self.phase == "entrance" then
      self.entranceSCX = math.max(0, self.entranceSCX - 4) -- 112 -> 0 over 28 frames
      self.ornamentY = math.min(6, self.ornamentY + 2) -- -0x22 -> 6, +2px/frame
      if self.entranceSCX == 0 and self.ornamentY >= 6 then
        self.phase = "loop"
        self:startMusic()
      end
      return -- input ignored until the entrance lands, matching Yellow's cinematic gate
    end
    self.suicuneFrameTimer = self.suicuneFrameTimer + 1
    if self.suicuneFrameTimer >= 8 then -- SuicuneFrameIterator: one advance every 8 frames
      self.suicuneFrameTimer = 0
      self.suicuneFrame = self.suicuneFrame % 4 + 1
    end
    local input = self.game.input
    if input:wasPressed("start") or input:wasPressed("a") then
      self:openMenu()
    end
    return
  end
```

Add the draw branch to `TitleState:draw` (alongside the existing
`if self.yellowLayout then ... else ... end` split,
`TitleState.lua:466-520`):

```lua
  elseif self.crystalLayout then
    -- TitleScreenEntrance: the logo wipes in from alternating sides per
    -- row-pair (the "interlaced" effect) -- draw the logo in 8px-tall
    -- strips, odd/even strips offset in opposite directions, both
    -- converging on 0 as self.entranceSCX counts down to 0.
    if self.logo then
      local iw, ih = self.logo:getDimensions()
      local stripH = 8
      for y = 0, ih - 1, stripH do
        local dir = ((y / stripH) % 2 == 0) and 1 or -1
        local dx = dir * self.entranceSCX
        love.graphics.draw(self.logo,
          love.graphics.newQuad(0, y, iw, math.min(stripH, ih - y), iw, ih),
          16 + dx, 8 + y)
      end
    end
    if self.crystalOrnament then
      love.graphics.draw(self.crystalOrnament, 56, self.ornamentY)
    end
    if self.phase == "loop" and self.suicuneSheet then
      -- SuicuneFrameIterator's .Frames table selects one of 4 fixed
      -- frames from the decoded 128x128 sheet every 8 frames; verify
      -- these quad offsets against the real game (see this task's own
      -- note above) and adjust if the sheet's internal frame layout
      -- differs from this initial 64x48-per-frame, 2x2-grid guess.
      local frameQuads = {
        love.graphics.newQuad(0, 0, 64, 48, 128, 128),
        love.graphics.newQuad(64, 0, 64, 48, 128, 128),
        love.graphics.newQuad(0, 48, 64, 48, 128, 128),
        love.graphics.newQuad(64, 48, 64, 48, 128, 128),
      }
      love.graphics.draw(self.suicuneSheet, frameQuads[self.suicuneFrame], 48, 96)
    end
```

(This `elseif` sits between the existing `if self.yellowLayout then ...`
block and the trailing `else` that handles Red/Blue — read
`TitleState.lua:466-520`'s current structure first so the new branch
slots in without disturbing the existing two.)

- [ ] **Step 3: `sgbPalettes` guard**

In `TitleState:sgbPalettes` (`TitleState.lua:46-74`), add an early return
before the existing `yellowLayout`/Red-Blue branch — Crystal is GBC-only,
no SGB pack exists for it:

```lua
function TitleState:sgbPalettes(game)
  if self.crystalLayout then return nil end
  local P = require("src.render.PaletteFX")
```

- [ ] **Step 4: Manual verification against the real ROM**

Run the project the same way every prior Gen2 task in this branch
verified real-ROM behavior (reuse whichever concrete launch steps the
skeleton/cry-transcoder plans already established — same running game,
importing `roms/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc`).
Confirm:
- The logo wipes in from alternating sides and the crystal ornament falls
  into place, landing together.
- Suicune's 4 frames cycle visibly and don't look like a jumbled/wrong
  crop (if they do, the quad offsets in Step 2 need adjusting against the
  real 128×128 sheet — inspect
  `<save dir>/crystal/assets/generated/title/suicune.png` directly in an
  image viewer to see the actual frame layout Task 2 decoded).
- `Music_TitleScreen` plays and is audibly recognizable as the real
  title theme (channel 3/wave absent — expect it to sound thinner than
  the real game, that's the documented, accepted gap, not a bug).
- Pressing START or A opens the main menu as it already does for
  Red/Blue/Yellow.

Report what was actually seen/heard, not just "no error" — same
listening-and-looking discipline the cry-transcoder plan's own Task 4
established.

- [ ] **Step 5: Commit**

```bash
git add src/ui/TitleState.lua
git commit -m "gen2: add Crystal's title screen layout (entrance wipe, Suicune loop, music)"
```

---

### Task 6: Full-suite verification and final real-ROM check

There is no separate `tests/fixture_data_gen2/` directory to add to —
confirmed by reading `tests/run_tests.lua` directly: the existing "Gen2
(Crystal) skeleton" section (starting around line 3474) is a series of
inline `do ... end` blocks, each hand-building fixture data in the shape
`RomExtractorGen2.lua` produces and feeding it straight into the real
downstream consumer (`MapLoader.load`, `Font.load`, `PaletteFX`) — proving
those consumers work with Gen2-shaped data, without touching
`RomExtractorGen2` itself or needing the real ROM. The prior cry-transcoder
plan followed the exact same principle: it added a fixture test for
`CrystalCryTranscoder` (Task 3 of this plan already did the equivalent for
`CrystalMusicTranscoder`), but did **not** add a separate fixture test for
`RomExtractorGen2:extractCry()` itself — that task's own verification was
just "run the existing suite, confirm it's still green" (Task 2 Step 5 and
Task 4 Step 5, above, already do exactly this for `extractTitle`/
`extractTitleMusic`). No further fixture task is needed beyond what Tasks
2-5 already include.

**Files:** none (verification only)

**Interfaces:** none new.

- [ ] **Step 1: Re-run the full test suite**

**Files:** none (verification only)

**Interfaces:** none new.

- [ ] **Step 1: Re-run the full test suite**

```bash
scripts/test.sh
```

Expected: 100% green, including every existing Gen1 audio test
(`tests/mod_audio_tests.lua`, `tests/engine/fanfare_music_hold.lua`,
`tests/engine/wave_channel_mix_bug429.lua`,
`tests/engine/quit_thread_shutdown.lua`,
`tests/engine/effect_stereo_bug626.lua`) — proving zero regression to
Gen1's own audio and title screen (spec's Global Constraints).

- [ ] **Step 2: Confirm zero diff on the off-limits files**

```bash
git diff dev...HEAD -- src/core/ChipSynth.lua src/core/ChipAudio.lua src/core/Sound.lua
```

Expected: empty output. If non-empty, stop and investigate before
proceeding.

- [ ] **Step 3: Confirm Red/Blue/Yellow's title screens are unchanged**

Boot Red, Blue, and Yellow in turn (`POKEPORT_VERSION=red` /
`blue` / `yellow`) and confirm each still shows its own existing title
screen exactly as before this plan — Task 5 only added a new `elseif`
branch and one early-return guard, touching no existing Red/Blue/Yellow
code path.

- [ ] **Step 4: Final real-ROM report**

Summarize, in the PR/commit description or a message to the user, what
was actually observed for Crystal's title screen and music (per Task 5
Step 4's checklist) and explicitly flag the two known, documented gaps
this plan leaves open on purpose: channel 3 (wave) is silent, and the
title's own GBC palette (`title.palette`, extracted but unused — see
Task 2's scope note) isn't yet applied to the rendered art.
