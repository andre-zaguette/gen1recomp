# Gen2 (Crystal) Cry Bytecode Transcoder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wooper's cry (Cry_Wooper's three real Crystal-dialect channel
programs) plays audibly through the existing, unmodified `src/core/ChipSynth.lua`
by translating its bytecode into Gen1's opcode dialect once, at import time,
against the player's own ROM.

**Architecture:** A new pure Lua module, `src/audio/CrystalCryTranscoder.lua`,
decodes Crystal's real channel bytes into the same friendly Lua event-table
shape `src/audio/ChipAsm.lua` (the existing Gen1-dialect authoring DSL used
today for mod-authored ChipAsm songs/sfx) already consumes, then calls
`ChipAsm.sfx(...)` to produce a self-contained `{chip = {blob, channels,
engine}}` program — mounted by `ChipSynth.lua`'s existing pseudo-bank-0
mechanism, the same one mod-authored ChipAsm already uses. `ChipSynth.lua`,
`ChipAudio.lua`, and `Sound.lua` are not modified at all; this plan only adds
a new module plus one new `RomExtractorGen2` extraction stage.

**Tech Stack:** Lua (LuaJIT `bit` library, LÖVE headless test harness),
Python 3 (manifest builder, regex-based source-text resolution).

## Global Constraints

- `src/core/ChipSynth.lua`, `src/core/ChipAudio.lua`, and `src/core/Sound.lua`
  must show **zero diff** from before this plan (spec's Non-goals and
  Acceptance Criterion 3). Every task in this plan only adds new files or
  extends `RomExtractorGen2.lua`/`tools/make_rom_manifest_crystal.py`.
- This plan translates **only** Wooper's three real cry channels
  (`Cry_Wooper_Ch5`/`_Ch6`/`_Ch8`, ROM bank `$3c`). No general Crystal audio
  support, no other species, no music, no other SFX (spec's Non-goals).
- No committed ROM bytes. Wooper's cry *content* (the channel programs) is
  read from the player's own ROM at import time by `RomExtractorGen2.lua`,
  mirroring every other Gen2 content extractor in this codebase (font
  glyphs, portrait/sprite pixels, palettes). Only *structural* facts
  (symbol names/addresses, pitch, length) are resolved from readable
  pokecrystal source text at manifest-build time, mirroring font's
  charmap and the intro's text-label resolution.
- `docs/superpowers/specs/2026-08-04-gen2-crystal-cry-transcoder-design.md`
  is the approved spec. Where this plan's own research (below) sharpens or
  corrects a speculative detail from that spec, the plan's version is
  authoritative — each such correction is called out explicitly in the task
  it affects.

## Research already done (do not re-derive)

This plan's own research phase fully decoded Wooper's three real channels
against the real ROM (`roms/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc`,
symbols confirmed in `/private/tmp/pokecrystal/pokecrystal.sym`:
`Cry_Wooper_Ch5` `3c:722e`, `Cry_Wooper_Ch6` `3c:7249`, `Cry_Wooper_Ch8`
`3c:7264`) and cross-checked every opcode against pokecrystal's own
`macros/scripts/audio.asm` (Crystal's real command table) and
`src/core/ChipSynth.lua`'s actual dispatch (Gen1's real command table, read
directly, not inferred). Two corrections to the spec's own speculative
claims fell out of this:

1. **The spec's "plain notes are byte-compatible, pure passthrough" hope is
   wrong.** `ChipSynth.lua`'s SFX/cry note format lives at command range
   `$20-$2F` (`elseif self.sfx and command >= 0x20 and command < 0x30`,
   `src/core/ChipSynth.lua:439`): the low nibble of the *command byte itself*
   carries `length - 1`. Crystal's `square_note`/`noise_note` macros
   (`macros/scripts/audio.asm:27-45`) emit the **plain, un-offset** length as
   its own byte (`db \1`), with no `$20` added. Confirmed against Wooper's
   real bytes: `square_note 2, 9, -1, 1816` really does compile to `02 99 18
   07` (length byte `02`, not `22`). The transcoder does not passthrough
   these bytes; it decodes each Crystal note record into a `{squareNote =
   {len, volume, fade, frequency}}` / `{noiseNote = {len, volume, fade,
   parameter}}` event and lets `ChipAsm.lua`'s existing `E.squareNote` /
   `E.noiseNote` emitters (`src/audio/ChipAsm.lua:199-215`) apply the
   `$20` + `length - 1` packing Gen1 actually expects. Everything else
   (the packed volume/fade nibble byte, the raw little-endian frequency
   word, the noise parameter byte) *is* byte-identical between the two
   dialects — confirmed both by hand-decoding against `audio.asm`'s macro
   bodies and independently by `ChipAsm.lua`'s own pre-existing encoder
   logic agreeing byte-for-byte.
2. **Wooper's three real channels use exactly four opcodes**: `duty_cycle`
   (Crystal `$DB` -> Gen1 `$EC`, 1 param byte, direct passthrough),
   `duty_cycle_pattern` (Crystal `$DE` -> Gen1 `$FC`, 1 packed param byte,
   direct passthrough — confirmed both macros pack the same 4 fields into
   the same bit positions), a plain note record as described above, and
   `sound_ret` (`$FF` in both dialects — this one command byte value is
   genuinely shared). No loop, call, octave, note_type, or SFX-priority
   opcodes appear anywhere in the real data, so this plan implements
   nothing else. `CrystalCryTranscoder.decodeChannel` (Task 2) errors
   loudly on any other opcode rather than guessing at unverified behavior.

Full verified byte-level decode (channel bytes, in order, with the ROM
window each channel needs):

**`Cry_Wooper_Ch5`** (`3c:722e`, hardware channel 1 = pulse 1), 27 bytes:
```
db 02                      -- duty_cycle(2)
02 99 18 07                -- square_note(len=2,  vol=9,  fade=-1, freq=1816)
04 ab 22 07                -- square_note(len=4,  vol=10, fade=-3, freq=1826)
08 ab 34 07                -- square_note(len=8,  vol=10, fade=-3, freq=1844)
04 d6 16 07                -- square_note(len=4,  vol=13, fade=6,  freq=1814)
08 d1 12 07                -- square_note(len=8,  vol=13, fade=1,  freq=1810)
08 00 00 00                -- square_note(len=8,  vol=0,  fade=0,  freq=0)
ff                         -- sound_ret
```

**`Cry_Wooper_Ch6`** (`3c:7249`, hardware channel 2 = pulse 2), 27 bytes:
```
de 07                      -- duty_cycle_pattern(0,0,1,3)  [0x07 = 00 00 01 11]
02 b9 38 07                -- square_note(len=2,  vol=11, fade=-1, freq=1848)
04 cb 42 07                -- square_note(len=4,  vol=12, fade=-3, freq=1858)
08 cb 54 07                -- square_note(len=8,  vol=12, fade=-3, freq=1876)
04 f6 36 07                -- square_note(len=4,  vol=15, fade=6,  freq=1846)
08 f1 32 07                -- square_note(len=8,  vol=15, fade=1,  freq=1842)
08 00 00 00                -- square_note(len=8,  vol=0,  fade=0,  freq=0)
ff                         -- sound_ret
```

**`Cry_Wooper_Ch8`** (`3c:7264`, hardware channel 4 = noise), 16 bytes:
```
02 5b 04                   -- noise_note(len=2,  vol=5, fade=-3, parameter=4)
04 68 13                   -- noise_note(len=4,  vol=6, fade=0,  parameter=19)
08 68 20                   -- noise_note(len=8,  vol=6, fade=0,  parameter=32)
04 68 13                   -- noise_note(len=4,  vol=6, fade=0,  parameter=19)
10 51 04                   -- noise_note(len=16, vol=5, fade=1,  parameter=4)
ff                         -- sound_ret
```

(fade decode: packed byte's low nibble N; if N has bit 3 set, `fade = -(N &
7)`, else `fade = N` — the same formula both `ChipSynth.lua`'s `fadeValue`
and `ChipAsm.lua`'s `Cursor:fade` already use, confirmed to round-trip
exactly.)

`Cry_Wooper`'s pitch/length row is already resolved and verified correct in
the stashed Task 5 attempt (`git stash list` — "Task 5 (Wooper cry)
manifest/import plumbing"): `pitch = 147`, `length = 175`, read from
`data/pokemon/cries.asm`'s `mon_cry CRY_WOOPER, 147, 175 ; WOOPER` row.

---

### Task 1: Manifest additions — Wooper's channel symbols and pitch/length

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py`
- Modify: `tools/rom_manifest_crystal.json` (regenerated, not hand-edited)

**Interfaces:**
- Produces: three new entries in the manifest's `symbols` map —
  `Cry_Wooper_Ch5`, `Cry_Wooper_Ch6`, `Cry_Wooper_Ch8` (each `[bank,
  address]`, same shape every other symbol already uses) — plus top-level
  `cryPitch` (int) and `cryLength` (int) fields. Task 3 reads these via
  `self:symbol("Cry_Wooper_Ch5")` etc. and `self.manifest.cryPitch` /
  `self.manifest.cryLength`, exactly like every other `self:symbol(...)` /
  `self.manifest.<field>` call already in `RomExtractorGen2.lua`.

This plan does **not** need `Cry_Wooper`'s own header symbol or
`WaveSamples` (both were in the stashed Task 5 attempt): reading the three
channel symbols directly is simpler and sufficient for this one hardcoded
species, and the `chip`-blob mounting mechanism Task 3 uses (see its
research note) never touches the wave-channel sample table at all, so
`WaveSamples` is not needed this time.

- [ ] **Step 1: Add the three channel symbols to `REQUIRED_SYMBOLS`**

In `tools/make_rom_manifest_crystal.py`, extend the `REQUIRED_SYMBOLS`
tuple:

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
    "PokemonProfPic",
    "WooperFrontpic",
    # Wooper's three real cry channel programs (pulse 1, pulse 2, noise).
    # Read directly by name rather than via Cry_Wooper's own header table
    # (a 3-byte-per-channel {channel_number, address} list) -- confirmed
    # against the real .sym file: Cry_Wooper_Ch5 3c:722e, Cry_Wooper_Ch6
    # 3c:7249, Cry_Wooper_Ch8 3c:7264 (all bank $3c). See
    # docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md's
    # "Research already done" section for the fully-verified byte decode.
    "Cry_Wooper_Ch5",
    "Cry_Wooper_Ch6",
    "Cry_Wooper_Ch8",
)
```

- [ ] **Step 2: Add `resolve_wooper_cry`**

Add this function anywhere below `parse_new_bark_town` and above
`embed_symbols`:

```python
def resolve_wooper_cry(pokecrystal):
    """Wooper's row in data/pokemon/cries.asm's PokemonCries table:
    `mon_cry CRY_WOOPER, 147, 175 ; WOOPER`. `mon_cry`'s macro body is
    `dw \\1, \\2, \\3` (three 16-bit words = 6 bytes/row, confirmed by
    reading the macro definition at the top of cries.asm) -- NOT Gen1's
    one-byte pitch/length (src/import/RomExtractor.lua's extractAudio
    reads a 3-byte-per-row table there). Both fields can be negative
    (e.g. QUAGSIRE's row is `CRY_WOOPER, -198, 320`), so this reads them
    as plain signed decimal literals straight off the source line --
    exactly the value the assembler would encode as `dw`, no byte
    packing/unpacking needed since this never touches raw ROM bytes.

    Every row carries its species name as a trailing comment
    (`; WOOPER`), an unambiguous single-match anchor for the one species
    this skeleton's intro needs (confirmed exactly one `; WOOPER$` line
    in the file). extract/util.py's read_asm strips `;` comments before
    a caller ever sees a line, which would remove that anchor, so this
    reads the raw file text directly instead.
    """
    path = os.path.join(pokecrystal, "data/pokemon/cries.asm")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(
        r"mon_cry\s+CRY_\w+,\s*(-?\d+),\s*(-?\d+)\s*;\s*WOOPER\s*$",
        text, re.MULTILINE)
    if not m:
        raise SystemExit("WOOPER row not found in data/pokemon/cries.asm")
    return {"pitch": int(m.group(1)), "length": int(m.group(2))}
```

- [ ] **Step 3: Wire it into `main()`**

```python
    symbols = SymbolTable(os.path.abspath(args.symbols))
    wooper_cry = resolve_wooper_cry(pokecrystal)
    data = {
        "romSha1": CRYSTAL_SHA1,
        "symbols": embed_symbols(symbols),
        "newBarkTown": parse_new_bark_town(pokecrystal),
        "fontCharmap": parse_charmap(pokecrystal),
        "charmap": text_charmap(pokecrystal),
        "palettes": resolve_palettes(pokecrystal),
        "cryPitch": wooper_cry["pitch"],
        "cryLength": wooper_cry["length"],
    }
```

(`wooper_cry = resolve_wooper_cry(pokecrystal)` must run before building
`data`, same as the other `resolve_*`/`parse_*` calls already inlined into
the dict literal.)

- [ ] **Step 4: Regenerate the manifest**

```bash
python3 tools/make_rom_manifest_crystal.py \
  --pokecrystal /private/tmp/pokecrystal \
  --symbols /private/tmp/pokecrystal/pokecrystal.sym
```

Expected: `wrote tools/rom_manifest_crystal.json`. Confirm the diff adds
exactly `cryPitch: 147`, `cryLength: 175`, and three new `symbols` entries
(`Cry_Wooper_Ch5: [60, 29230]`, `Cry_Wooper_Ch6: [60, 29257]`,
`Cry_Wooper_Ch8: [60, 29284]` — decimal forms of `3c:722e`/`3c:7249`/
`3c:7264`) with **no other lines changed**.

- [ ] **Step 5: Commit**

```bash
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json
git commit -m "gen2: resolve Wooper's cry channel symbols and pitch/length"
```

---

### Task 2: `CrystalCryTranscoder` — decode Crystal bytecode, re-encode via ChipAsm

**Files:**
- Create: `src/audio/CrystalCryTranscoder.lua`
- Modify: `tests/run_tests.lua` (new fixture block, appended after the
  existing Gen2 sections — see the file's own `-- Gen2 (Crystal) skeleton`
  banner around line 3399 for where those begin)

**Interfaces:**
- Consumes: `src/audio/ChipAsm.lua`'s existing public API —
  `ChipAsm.sfx(spec)` where `spec = {channels = {{hw = 1-4, program =
  {...events...}}, ...}}`, returning `{chip = {blob, channels, engine =
  1}}` (see `src/audio/ChipAsm.lua:359-406`). Event shapes used:
  `{duty = 0-3}`, `{dutyPattern = {a,b,c,d}}` (each 0-3),
  `{squareNote = {len, volume, fade, frequency}}`,
  `{noiseNote = {len, volume, fade, parameter}}`, `{ret = true}` — all
  already implemented by `ChipAsm.lua`'s `emitters()` (lines 84-225).
- Produces: `CrystalCryTranscoder.decodeChannel(bytes, noise) ->
  events` and `CrystalCryTranscoder.buildCry(channels) -> {chip = {...}}`
  (`channels = {{hw = 1-4, bytes = <1-indexed array of byte values>},
  ...}`). Task 3 calls `buildCry` directly with the byte arrays
  `Rom:bytes(bank, address, length)` already returns (see
  `src/import/Rom.lua:32-41` — that method returns a plain 1-indexed Lua
  array of byte values, not a string, which is exactly the shape
  `decodeChannel` consumes).

- [ ] **Step 1: Write `src/audio/CrystalCryTranscoder.lua`**

```lua
-- Translates Pokemon Crystal's real sound-engine bytecode into the Lua
-- event-table shape src/audio/ChipAsm.lua already knows how to assemble
-- into a Gen1-dialect chip program. Scoped narrowly to the four opcodes
-- Wooper's three real cry channels use (duty_cycle, duty_cycle_pattern, a
-- plain note record, and the terminator) -- see
-- docs/superpowers/specs/2026-08-04-gen2-crystal-cry-transcoder-design.md
-- and docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md's
-- "Research already done" section for the verified opcode table this is
-- built from. Not a general Crystal-dialect decoder: any opcode outside
-- that set is out of scope and raises rather than guessing.

local bit = require("bit")
local ChipAsm = require("src.audio.ChipAsm")

local CrystalCryTranscoder = {}

-- packed low nibble -> signed fade, identical to src/core/ChipSynth.lua's
-- fadeValue and src/audio/ChipAsm.lua's Cursor:fade (bit 3 set means a
-- decay of the low three bits)
local function fadeValue(nibble)
  if bit.band(nibble, 8) ~= 0 then return -bit.band(nibble, 7) end
  return nibble
end

-- Decodes one Crystal-dialect cry channel program into a ChipAsm event
-- list. `bytes` is a 1-indexed array of byte values starting exactly at
-- the channel's first byte (the shape Rom:bytes(...) returns). `noise`
-- selects the noise channel's 3-byte note record (length, packed
-- volume/fade, drum parameter) over the pulse channels' 4-byte record
-- (length, packed volume/fade, 2-byte little-endian frequency register).
-- Stops at the sound_ret ($FF) terminator and returns the event list
-- (its last entry is always {ret = true}).
function CrystalCryTranscoder.decodeChannel(bytes, noise)
  local events = {}
  local i = 1
  while true do
    local cmd = bytes[i]
    if cmd == nil then
      error("CrystalCryTranscoder: ran off the end of the byte window "
        .. "before a sound_ret ($FF) terminator")
    elseif cmd == 0xFF then
      events[#events + 1] = { ret = true }
      return events
    elseif cmd == 0xDB then
      events[#events + 1] = { duty = bytes[i + 1] }
      i = i + 2
    elseif cmd == 0xDE then
      local packed = bytes[i + 1]
      events[#events + 1] = { dutyPattern = {
        bit.band(bit.rshift(packed, 6), 3),
        bit.band(bit.rshift(packed, 4), 3),
        bit.band(bit.rshift(packed, 2), 3),
        bit.band(packed, 3),
      } }
      i = i + 2
    elseif cmd < 0xD0 then
      local len = cmd
      local packed = bytes[i + 1]
      local volume = bit.rshift(packed, 4)
      local fade = fadeValue(bit.band(packed, 0x0F))
      if noise then
        events[#events + 1] = { noiseNote = {
          len = len, volume = volume, fade = fade, parameter = bytes[i + 2],
        } }
        i = i + 3
      else
        local frequency = bytes[i + 2] + bytes[i + 3] * 0x100
        events[#events + 1] = { squareNote = {
          len = len, volume = volume, fade = fade, frequency = frequency,
        } }
        i = i + 4
      end
    else
      error(("CrystalCryTranscoder: unsupported opcode $%02X at byte %d "
        .. "-- outside the set Wooper's real channels use"):format(cmd, i))
    end
  end
end

-- channels: array of {hw = 1-4, bytes = <Rom:bytes(...) array>}, one entry
-- per real Crystal channel. Returns {chip = {blob, channels, engine = 1}},
-- ready to sit directly on a data.audio.cries[SPECIES] entry (as the
-- sibling `chip` field -- see src/core/ChipAudio.lua's newCry: `cry.chip
-- and cry or cry.header`).
function CrystalCryTranscoder.buildCry(channels)
  local specs = {}
  for index, channel in ipairs(channels) do
    specs[index] = {
      hw = channel.hw,
      program = CrystalCryTranscoder.decodeChannel(channel.bytes, channel.hw == 4),
    }
  end
  return ChipAsm.sfx({ channels = specs })
end

return CrystalCryTranscoder
```

- [ ] **Step 2: Add the fixture test to `tests/run_tests.lua`**

Append after the existing Gen2 palette fixture block (the file's tail end
of the `-- Gen2 (Crystal) skeleton` section). Match the surrounding file's
existing `local function ...() ... end` + call pattern for each fixture
(see the Gen2 font/palette blocks immediately above for the exact style —
each is a `do ... end` or bare block using the file's shared `eq(...)`
harness).

```lua
-- ------------------------------------------------- Gen2 cry transcoder
-- Wooper's three real Cry_Wooper_Ch5/_Ch6/_Ch8 channel byte streams
-- (docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md's
-- "Research already done" section has the full verified decode this
-- fixture data comes from) fed through CrystalCryTranscoder, proving both
-- (a) the decode produces the exact expected ChipAsm events, and (b) the
-- resulting chip program renders audible (non-inaudible-floor) samples
-- through the real, unmodified ChipSynth.lua -- no ROM needed.
do
  local CrystalCryTranscoder = require("src.audio.CrystalCryTranscoder")
  local ChipSynth = require("src.core.ChipSynth")

  local ch5Bytes = {
    0xDB, 0x02,
    0x02, 0x99, 0x18, 0x07,
    0x04, 0xAB, 0x22, 0x07,
    0x08, 0xAB, 0x34, 0x07,
    0x04, 0xD6, 0x16, 0x07,
    0x08, 0xD1, 0x12, 0x07,
    0x08, 0x00, 0x00, 0x00,
    0xFF,
  }
  local ch6Bytes = {
    0xDE, 0x07,
    0x02, 0xB9, 0x38, 0x07,
    0x04, 0xCB, 0x42, 0x07,
    0x08, 0xCB, 0x54, 0x07,
    0x04, 0xF6, 0x36, 0x07,
    0x08, 0xF1, 0x32, 0x07,
    0x08, 0x00, 0x00, 0x00,
    0xFF,
  }
  local ch8Bytes = {
    0x02, 0x5B, 0x04,
    0x04, 0x68, 0x13,
    0x08, 0x68, 0x20,
    0x04, 0x68, 0x13,
    0x10, 0x51, 0x04,
    0xFF,
  }

  local ch5Events = CrystalCryTranscoder.decodeChannel(ch5Bytes, false)
  eq(#ch5Events, 8, "Cry transcoder: Ch5 decodes to 8 events")
  eq(ch5Events[1].duty, 2, "Cry transcoder: Ch5 first event is duty_cycle(2)")
  eq(ch5Events[2].squareNote.len, 2, "Cry transcoder: Ch5 note 1 len")
  eq(ch5Events[2].squareNote.volume, 9, "Cry transcoder: Ch5 note 1 volume")
  eq(ch5Events[2].squareNote.fade, -1, "Cry transcoder: Ch5 note 1 fade")
  eq(ch5Events[2].squareNote.frequency, 1816, "Cry transcoder: Ch5 note 1 frequency")
  eq(ch5Events[5].squareNote.fade, 6, "Cry transcoder: Ch5 note 4 positive fade")
  eq(ch5Events[8].ret, true, "Cry transcoder: Ch5 ends with sound_ret")

  local ch6Events = CrystalCryTranscoder.decodeChannel(ch6Bytes, false)
  eq(#ch6Events, 8, "Cry transcoder: Ch6 decodes to 8 events")
  T.same(ch6Events[1].dutyPattern, { 0, 0, 1, 3 },
    "Cry transcoder: Ch6 duty_cycle_pattern unpacks 0x07 as {0,0,1,3}")
  eq(ch6Events[3].squareNote.volume, 12, "Cry transcoder: Ch6 note 2 volume")
  eq(ch6Events[3].squareNote.fade, -3, "Cry transcoder: Ch6 note 2 fade")

  local ch8Events = CrystalCryTranscoder.decodeChannel(ch8Bytes, true)
  eq(#ch8Events, 6, "Cry transcoder: Ch8 decodes to 6 events")
  eq(ch8Events[1].noiseNote.len, 2, "Cry transcoder: Ch8 note 1 len")
  eq(ch8Events[1].noiseNote.parameter, 4, "Cry transcoder: Ch8 note 1 parameter")
  eq(ch8Events[5].noiseNote.len, 16, "Cry transcoder: Ch8 note 5 max length")
  eq(ch8Events[6].ret, true, "Cry transcoder: Ch8 ends with sound_ret")

  local cry = CrystalCryTranscoder.buildCry({
    { hw = 1, bytes = ch5Bytes },
    { hw = 2, bytes = ch6Bytes },
    { hw = 4, bytes = ch8Bytes },
  })
  check(cry.chip and cry.chip.blob ~= nil, "Cry transcoder: buildCry produces a chip blob")
  local channelNumbers = {}
  for _, channel in ipairs(cry.chip.channels) do
    channelNumbers[#channelNumbers + 1] = channel.number
  end
  T.same(channelNumbers, { 5, 6, 8 },
    "Cry transcoder: buildCry tags channels 5/6/8 (pulse1/pulse2/noise)")

  local rendered = ChipSynth.renderEffectData({}, cry, {
    frequencyOffset = 147, cryLength = 175,
  })
  check(rendered ~= nil, "Cry transcoder: renders through the real ChipSynth (not inaudible)")
  check(rendered and rendered:getSampleCount() > 441,
    "Cry transcoder: renders more than the ~441-sample inaudible floor")
end
```

`check`, `eq`, and `T.same` are this file's shared assertion helpers
(`tests/harness.lua` — `check`/`eq` are locals already bound near the top
of `tests/run_tests.lua`, `T.same(got, want, msg)` does a structural/deep
compare, `check(cond, msg)` is the plain boolean assertion), the exact
same helpers the neighboring Gen2 font/palette blocks above already use —
no new helper needed.

- [ ] **Step 3: Run the test**

```bash
luajit tests/run_tests.lua 2>&1 | tail -40
```

(This is the project's own documented invocation — see the comment block
at the top of `tests/run_tests.lua` and `docs/architecture.md`. Every
prior Gen2 task in this branch ran this same suite.)

Expected: all new "Cry transcoder: ..." assertions pass, and the full
existing suite stays green (this step touches no engine code, only adds a
new module and new assertions).

- [ ] **Step 4: Commit**

```bash
git add src/audio/CrystalCryTranscoder.lua tests/run_tests.lua
git commit -m "gen2: add CrystalCryTranscoder, translating Crystal cry bytecode to Gen1's dialect"
```

---

### Task 3: Wire into `RomExtractorGen2:extractCry()`

**Files:**
- Modify: `src/import/RomExtractorGen2.lua`

**Interfaces:**
- Consumes: `CrystalCryTranscoder.buildCry(channels)` (Task 2),
  `self:symbol(name)` (existing, returns `{bank, address, name}`),
  `self.rom:bytes(bank, address, length)` (existing, `src/import/Rom.lua:32`),
  `self.manifest.cryPitch` / `self.manifest.cryLength` (Task 1),
  `self:write(name, value)` (existing, writes
  `data/generated/<name>.lua`).
- Produces: `RomExtractorGen2:extractCry()`, called from `:run()`, writing
  `data/generated/audio.lua` shaped `{cries = {WOOPER = {chip = {blob,
  channels, engine = 1}, pitch = 147, length = 175}}}` — the exact shape
  `src/core/Sound.lua:293`'s `Sound.playCry` and `src/core/ChipAudio.lua:412`'s
  `ChipAudio.newCry` already expect (`cry.chip and cry or cry.header`
  dispatch), confirmed against `src/mods/Schemas.lua`'s `R.cries` union
  (`f.rec{chip = chipProgram, pitch = f.opt(...), length = f.opt(...)}`).

Recovers the stashed Task 5 attempt (`git stash list` —
"Task 5 (Wooper cry) manifest/import plumbing") only for its
already-verified pitch/length resolution (now folded into Task 1). The
stash's own `extractCry` dumped whole ROM banks and wired
`programFile`/`bankOrder`/`waveBanks` because it addressed Wooper's
program directly inside a reconstructed ROM bank space (`header = {bank,
address}`) — this plan's `chip`-blob approach (`header.chip = {blob,
channels}`, mounted as pseudo-bank-0 by `Engine.new`,
`src/core/ChipSynth.lua:712-758`) needs neither: `chip.waves` is never
read from ROM at all when absent (`Engine.new`'s `elseif chip then` branch
`pcall`s `readWaves` and tolerates failure, returning `waves = {}}` —
harmless, since none of Wooper's three channels use the wave hardware
channel). Do **not** resurrect the stash's bank-dump code or its
`WaveSamples` symbol; this task replaces that approach entirely with the
simpler one below.

- [ ] **Step 1: Add the `CrystalCryTranscoder` require**

In `src/import/RomExtractorGen2.lua`, alongside the file's other
top-of-file requires:

```lua
local CrystalCryTranscoder = require("src.audio.CrystalCryTranscoder")
```

- [ ] **Step 2: Bump `STAGE_COUNT`**

```lua
local STAGE_COUNT = 7
```

- [ ] **Step 3: Add `extractCry`**

Add after `extractField` (mirrors the stashed attempt's placement):

```lua
-- Wooper's cry: Cry_Wooper_Ch5/_Ch6/_Ch8's three real channel programs
-- (ROM bank $3c) translated from Crystal's opcode dialect into Gen1's via
-- CrystalCryTranscoder, then assembled into a self-contained chip blob by
-- src/audio/ChipAsm.lua -- the same pseudo-bank-0 mechanism mod-authored
-- ChipAsm songs/sfx already use, so no ROM bank dump or wave-sample table
-- is needed (Engine.new only reads WaveSamples when a header lacks a
-- `chip` field; ours always has one). See
-- docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md.
function RomExtractorGen2:extractCry()
  self:beginStage("Wooper cry")
  local ch5 = self:symbol("Cry_Wooper_Ch5")
  local ch6 = self:symbol("Cry_Wooper_Ch6")
  local ch8 = self:symbol("Cry_Wooper_Ch8")
  local cry = CrystalCryTranscoder.buildCry({
    { hw = 1, bytes = self.rom:bytes(ch5.bank, ch5.address, 40) },
    { hw = 2, bytes = self.rom:bytes(ch6.bank, ch6.address, 40) },
    { hw = 4, bytes = self.rom:bytes(ch8.bank, ch8.address, 20) },
  })
  cry.pitch = self.manifest.cryPitch
  cry.length = self.manifest.cryLength
  local audio = { cries = { WOOPER = cry } }
  self:write("audio", audio)
  self:tick("Wooper cry", 1, 1)
  return audio
end
```

(The `40`/`40`/`20` byte-window lengths are generous margins over the real
27/27/16-byte programs confirmed in this plan's research section —
`decodeChannel` stops at the `sound_ret` terminator regardless of how much
extra trailing data the window includes, so exact sizing isn't load-bearing,
just enough to guarantee the real terminator is inside the window.)

- [ ] **Step 4: Call it from `:run()`**

```lua
  results.palettes = self:extractPalettes()
  results.text = self:extractIntroText()
  results.field = self:extractField(results.maps.NEW_BARK_TOWN)
  results.audio = self:extractCry()
  self:extractStubs()
```

- [ ] **Step 5: Run the existing Gen2 fixture tests**

```bash
luajit tests/run_tests.lua 2>&1 | tail -40
```

Expected: still green (this task only adds a new function and one new
`:run()` call; it changes no existing behavior).

- [ ] **Step 6: Commit**

```bash
git add src/import/RomExtractorGen2.lua
git commit -m "gen2: extract and translate Wooper's cry via RomExtractorGen2"
```

---

### Task 4: Real-ROM verification and stash cleanup

**Files:** none (verification only)

**Interfaces:** none new.

- [ ] **Step 1: Re-run the full test suite**

```bash
scripts/test.sh
```

(The project's unified entry point — runs every tier this checkout can
run, `luajit tests/run_tests.lua` among them, and exits non-zero on any
failure. `scripts/test.sh --quick` skips the slow content tier if a
faster signal is wanted first.)

Expected: 100% green, including every existing Gen1 audio test
(`tests/mod_audio_tests.lua`, `tests/engine/fanfare_music_hold.lua`,
`tests/engine/wave_channel_mix_bug429.lua`, `tests/engine/quit_thread_shutdown.lua`,
`tests/engine/effect_stereo_bug626.lua`) — proving zero regression to
Gen1's own audio (spec Acceptance Criterion 5).

- [ ] **Step 2: Confirm zero diff on the three off-limits files**

```bash
git diff dev...HEAD -- src/core/ChipSynth.lua src/core/ChipAudio.lua src/core/Sound.lua
```

Expected: empty output (spec Acceptance Criterion 3). If this is
non-empty, stop and investigate before proceeding — something in Tasks 1-3
touched a file this plan promised not to.

- [ ] **Step 3: Reimport Crystal and manually verify the cry plays**

Run the project the same way every prior Gen2 task in this branch verified
real-ROM behavior (`love .`, pointing the ROM importer at
`roms/Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc` — reuse
whichever concrete launch steps Task 9's real-ROM checks in
`docs/superpowers/plans/2026-08-04-gen2-crystal-intro.md` already
established, since this is the same running game). Trigger
`Sound.playCry(Game.data, "WOOPER")` — either directly (a debug console /
REPL if the project has one) or by temporarily calling it from a point in
the boot flow already reached in manual testing — and confirm it produces
actual audible sound (spec Acceptance Criterion 2). Report what was heard,
not just "no error": a silently-wrong translation rendering to a handful
of samples above the floor would still look clean without this listening
check, exactly as the blocked Task 5 attempt's own experience showed.

- [ ] **Step 4: Drop the now-superseded stash**

```bash
git stash list
git stash drop stash@{0}
```

(Only after Step 3 confirms the cry is actually audible — the stash is the
recovery point if verification instead reveals a problem. Confirm the
`stash@{0}` message still reads "Task 5 (Wooper cry) manifest/import
plumbing..." before dropping it, in case other stash entries have
accumulated.)

- [ ] **Step 5: Report completion**

This plan's own scope ends here. It does **not** re-enable the Gen2 intro
plan's Task 5 (Wooper cry, `docs/superpowers/plans/2026-08-04-gen2-crystal-intro.md`)
— that is separate follow-on work, using this plan's `CrystalCryTranscoder`
+ `RomExtractorGen2:extractCry()` as its now-unblocked foundation.
