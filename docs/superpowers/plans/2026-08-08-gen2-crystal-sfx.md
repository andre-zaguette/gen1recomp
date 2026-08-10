# Crystal SFX (First Batch) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Crystal's sound effects audible for the 9 SFX this project's own code already calls by name (`Collision`, `Cut`, `Denied`, `Ball_Poof`, `Ledge_Jump`, `Withdraw_Deposit`, `Go_Inside`, `Get_Key_Item`, `Intro_Whoosh`), which are currently silent no-ops because `RomExtractorGen2.lua` never writes `results.audio.sfx` at all.

**Architecture:** Extend `src/audio/CrystalMusicTranscoder.lua` with a new SFX-aware decode mode: Crystal's short "impact" sound effects are built almost entirely from `square_note`/`noise_note` records — a raw length+envelope+literal-GB-frequency encoding completely different from the octave/note_type/pitch scheme the music decoder already handles — plus the `pitch_sweep` opcode. Both already have a ready-made target: `src/audio/ChipAsm.lua` already defines `E.squareNote`/`E.noiseNote`/`E.pitchSweep` event emitters and a `ChipAsm.sfx(spec)` entrypoint (assembling onto hardware channels 5-8, matching Crystal's own `channel 5/6/7/8` SFX addressing) — this plan only has to decode Crystal's bytes into those already-existing event shapes, no changes needed in `ChipAsm.lua` or the playback engine (`src/core/ChipSynth.lua`, `src/core/Sound.lua`) at all. Then add one `RomExtractorGen2:extractSfx()` function producing `results.audio.sfx`, mirroring the established `extractXMusic()` pattern.

**Tech Stack:** Lua (LÖVE2D), Python 3 (manifest generation), the existing `ChipAsm`/`ChipSynth` chip-audio playback pipeline (unchanged).

## Global Constraints

- No ROM bytes may ever be committed (`.gitignore`'s `/roms/` entry) — `tools/rom_manifest_crystal.json` carries only derived text/metadata (symbol bank:address pairs), never raw SFX bytes.
- `GameVersion.isCrystal()` gates all Gen1/Gen2 divergence; this plan touches Gen2-only code paths (`RomExtractorGen2.lua`, `make_rom_manifest_crystal.py`) and does not modify Gen1's own `RomExtractor.lua`/`make_rom_manifest.py`/`make_yellow_manifest.py`.
- Every regenerated `tools/rom_manifest_crystal.json` diff must be reviewed with a semantic (parsed-JSON key-set, not line-diff) superset check before applying — Milestone 2 lost 19 already-shipped symbols twice by skipping this. Expect additive-only changes (14 new symbol entries), never a change to any other field.
- Every `tools/make_rom_manifest_crystal.py` (`REQUIRED_SYMBOLS`) change and its regenerated `tools/rom_manifest_crystal.json` must land in the **same commit** as the Lua code that depends on it — Milestone 2's Task 4/5 shipped these separately twice and both broke.
- Full test suite (`LUA=luajit scripts/test.sh`) must report `ALL TESTS PASSED` before every commit.
- `CrystalMusicTranscoder.decodeChannel`'s existing "raise on anything unverified" stance (hard `error()` on an unsupported opcode or an unresolvable `sound_call`/`sound_loop` target) must be preserved — do not add a silent fallback for a byte pattern nobody has verified against the real ROM.
- `Sound.play`'s existing graceful behavior (`local sfx = data.audio and data.audio.sfx; local def = sfx and sfx[name]`, `src/core/Sound.lua:176-186`) means a name this plan does not extract stays silent, not broken — this lets this batch land independently without needing every SFX this project references.

## Research already done

**Playback needs zero changes.** `Sound.play(data, name)` resolves `data.audio.sfx[name]` and hands it straight to `ChipAudio.newSfx` → `ChipSynth`'s `Engine.new`, which already dispatches on `header.chip ~= nil` (`ChipSynth.lua:717`) exactly the way `data.audio.songs[...]` already works — an extracted SFX just needs to be a `{chip = {...}}` table, precisely what `ChipAsm.song`/`ChipAsm.sfx` already return. Confirmed by reading `isChipDef` (`Sound.lua:81-83`), `ChipAudio.newSfx` (`ChipAudio.lua:401-407`), and `Engine.new`'s `local chip = header.chip` dispatch (`ChipSynth.lua:717`).

**This project's own SFX names don't map 1:1 onto Crystal's `SFX_*` catalog — they're inherited from Gen1's naming.** Grepped every `Sound.play`/`Sound.startLoop` literal-string call site across `src/` and `data/scripts/` (24 distinct names). Cross-referencing each against `roms/pokecrystal/constants/sfx_constants.asm` (207 `SFX_*` constants) and real callsites in `roms/pokecrystal/engine/`/`home/` found:

| This project's name | Real Crystal constant | Verified via |
|---|---|---|
| `Collision` | `SFX_BUMP` | `engine/overworld/player_movement.asm:774`, the literal collision-bump code path |
| `Cut` | `SFX_CUT` | direct name match |
| `Denied` | `SFX_WRONG` | `engine/battle/core.asm:2888` + `engine/pokemon/bills_pc.asm` invalid-selection paths |
| `Ball_Poof` | `SFX_BALL_POOF` | direct name match |
| `Ledge_Jump` | `SFX_JUMP_OVER_LEDGE` | direct name match |
| `Withdraw_Deposit` | `SFX_TRANSACTION` | `engine/pokemon/move_mon.asm:778,793`, literally the PC box withdraw/deposit routine |
| `Go_Inside` | `SFX_ENTER_DOOR` | `engine/overworld/tile_events.asm:94` (its counterpart `SFX_EXIT_BUILDING` fires leaving a building, :100) |
| `Get_Key_Item` | `SFX_KEY_ITEM` | direct name match; already in `Sound.lua`'s own `FANFARES` table, so it correctly ducks map music once extracted |
| `Intro_Whoosh` | `SFX_INTRO_WHOOSH` | direct name match |

Several other referenced names are explicitly **not** in this plan's scope, for reasons already confirmed rather than assumed:
- `Low_Health_Alarm` is synthesized procedurally by `ChipAudio.newLowHealthAlarm()` (`ChipAudio.lua:425-439`) — zero ROM dependency, already works regardless of Gen1/Crystal.
- `Heal_HP` is not an `SFX_*` in Crystal at all — the real source (`roms/pokecrystal/audio/music/healpokemon.asm`, `Music_HealPokemon`) lives in the **music** pointer table (`audio/music_pointers.asm:19`), a different namespace/extraction path, and its `Ch1` uses `pitch_slide` — an opcode this plan's `sfx.asm`-scoped research found zero real usages of anywhere in `sfx.asm` (confirmed: `grep -c "pitch_slide " audio/sfx.asm` → 0; it only appears in `audio/music/healpokemon.asm` and `audio/music/evolution.asm`). Out of scope for this plan; belongs with a future "SFX-as-jingle" or music-fanfare task.
- `Press_AB`, `Tink`, `Get_Item1`, `Get_Item2`, `Safari_Zone_PA`, `Shooting_Star`, `Shrink`, `Trade_Machine`, `Slots_New_Spin`, `Slots_Reward`, `Slots_Stop_Wheel` need their own real-constant verification this plan did not do (several are ambiguous between multiple candidate `SFX_*` names, and a few of their call sites — `TitleState.lua`'s logo-drop sequence, `OakSpeech.lua`'s `shrink` step — may be Gen1/Yellow-only paths not reached for Crystal at all, unconfirmed). Left for a follow-up SFX batch, not guessed at here.

**The real opcode gap: `square_note`/`noise_note`, not the command table.** Read `roms/pokecrystal/macros/scripts/audio.asm` (the full $D0-$FF music/sfx command table) end to end. Initially this looked like the main gap (`transpose $D9`, `pitch_sweep $DD`, `toggle_sfx $DF`, `pitch_slide $E0`, `force_stereo_panning $E4`, `sfx_priority_on/off $EC/$ED`, `sfx_toggle_noise $F0`, `set_condition`/`sound_jump_if`/`sound_jump $FA-$FC`), but grepping real usage across the whole ROM found most of these are never actually emitted anywhere:

```
force_stereo_panning: 0 real uses (only the macro definition + one dead reference in macros/legacy.asm)
set_condition:        0 real uses anywhere
sound_jump_if:        0 real uses anywhere
sound_jump (no _if):  used only in audio/cries.asm and one music file -- never in audio/sfx.asm
pitch_slide:          used only in audio/music/healpokemon.asm and evolution.asm -- never in sfx.asm
transpose:             1 use in the whole of sfx.asm (Sfx_GetBadge, not part of this batch)
pitch_sweep:         122 uses in sfx.asm -- real, needed
```

The actual dominant gap, found by parsing every one of the 325 channel blocks in `roms/pokecrystal/audio/sfx.asm`: **212 of 325 (65%) use only `square_note`/`noise_note`/`pitch_sweep`/`duty_cycle` — never `note`/`octave`/`note_type` at all.** All 8 of this batch's punchy "impact" SFX (everything except `Get_Key_Item`) are exactly this shape; only `Get_Key_Item` (a musical fanfare) uses the octave/note_type scheme `decodeChannel` already supports.

`square_note`/`noise_note` don't emit a leading $D0-$FF command byte — they're raw records starting directly with a plain length byte, which today's `decodeChannel` would silently misparse as a garbage one-byte packed note (not even an error). Confirmed real Crystal semantics by reading `roms/pokecrystal/audio/engine.asm`'s actual playback interpreter directly (`ParseMusic`'s `.readnote` branch, engine.asm:1155-1165, and `ParseSFXOrCry`, engine.asm:1270-1298): on an SFX channel (`SOUND_SFX` bit set on `CHANNEL_FLAGS1`), **every** byte below `FIRST_MUSIC_CMD` ($D0) is unconditionally read as `ParseSFXOrCry`'s raw record — full-byte length (masked `and $f`, then `+1`, confirmed via `SetNoteDuration`, engine.asm:2190-2194 — the exact same nibble+1 convention plain notes already use), a packed volume/fade envelope byte, then either 1 more parameter byte (noise channel) or 2 more raw-frequency bytes (tone channels) — there is no command-byte-range distinction the way Gen1's own native dialect uses ($20-$2F specifically, confirmed by reading `ChipSynth.lua`'s native `Channel:nextEvent()` dispatcher, lines 439-450). This project's transcoder must therefore decide raw-vs-packed **per channel, for the whole channel**, from context supplied by the caller (this batch's SFX never mix music-style and sfx-style notes on the same channel — confirmed against every real channel body used below), not by sniffing command bytes.

**`ChipAsm.lua` already has the target event types — confirmed by reading the whole file.** `E.squareNote`/`E.noiseNote` (`ChipAsm.lua:199-215`) already assemble a `{squareNote = {len, volume, fade, frequency}}` / `{noiseNote = {len, volume, fade, parameter}}` Lua event into Gen1-native dialect bytes (`0x20 + len-1` prefix, packed envelope byte, then either a 2-byte little-endian frequency or a 1-byte parameter) — this is Gen1's own `$20-$2F` raw-SFX-note convention, which `ChipSynth.lua`'s native dispatcher (lines 439-450) already knows how to play back. `E.pitchSweep` (`ChipAsm.lua:217-223`) already assembles a `{pitchSweep = {pace, subtract, shift}}` event into Gen1's own `$10` sweep opcode, matched by `ChipSynth.lua`'s native dispatcher (`elseif command == 0x10`, line 451). And `ChipAsm.sfx(spec)` (`ChipAsm.lua:404-406`, calling `assemble(spec, true)`) already places every channel on hardware+4 (`built.number = sfx and hw + 4 or hw`, line 377) — channels 5-8, exactly Crystal's own SFX channel numbering. **None of this needs to change** — this plan is purely: decode Crystal's bytes into these already-existing event shapes, and call `ChipAsm.sfx` instead of `ChipAsm.song`.

**Byte-level verification of the exact packing, worked by hand against real ROM data, both directions:**
- Crystal's `pitch_sweep \1, \2` macro (`macros/scripts/audio.asm`) packs `dn(\1, sign-encoded \2)` — high nibble is `pace`, low nibble is `shift` with bit 3 as the sign/subtract flag when `\2 < 0` — structurally identical to `ChipAsm.lua`'s own `E.pitchSweep` packing (`pace*16 + subtract*8 + shift`). Verified round-trip against `Sfx_Bump_Ch5`'s real `pitch_sweep 5, -2` (packs to `0x5A`: pace=5, subtract=true, shift=2) and `pitch_sweep 0, 8` (packs to `0x08`: pace=0, subtract=true, shift=0 — the ROM's own "cancel the sweep" idiom, used at the tail of every impact SFX that opens with a real sweep).
- `square_note`'s length argument is **not** range-checked at author time (`roms/pokecrystal/audio/sfx.asm`'s `Sfx_Transaction_Ch6` has `square_note 24, ...` — 24 does not fit a nibble), because the real interpreter always masks it (`and $f`) before use — `24 & 0xF = 8`, `+1 = 9`. This project's decoder must replicate the same masking (`length = band(rawByte, 0x0F) + 1`), not reject or clamp it.

**One channel deliberately excluded from this batch, for a real, verified reason.** `Sfx_KeyItem_Ch8` (`toggle_sfx; sfx_toggle_noise 4; drum_speed 12; drum_note 1, 16; sound_ret`) ends with a bare one-byte `drum_note` record immediately followed by `sound_ret`. Hand-tracing `ParseSFXOrCry` against this exact byte sequence shows the real hardware interpreter reads the `drum_note` byte as a raw record's length, then reads the very next byte — `sound_ret`'s own `$FF` — as a bogus volume/fade envelope, consuming it before ever recognizing it as a terminator. Whether this is harmless on real hardware (e.g. because nothing ever calls back into this channel's program once its last real note's duration timer expires) is not something this plan can verify without deeper simulation, and reproducing the same ambiguity here would risk either "ran off the end of the byte window" (`decodeChannel`'s own hard-error guard) or, worse, silently decoding trailing garbage. `Get_Key_Item` therefore extracts only its 3 real musical channels (Ch5/Ch6/Ch7) — the exact same "fewer than 4 channels is fine" precedent `Music_NewBarkTown` already established in Milestone 2 (`CrystalMusicTranscoder.buildSong`/`buildSfx`'s channel loop has no arity check). This channel's own instrument is a short percussive tail, not the fanfare's main content.

**Two byte-verified test fixtures**, hand-derived from real ROM data (`roms/pokecrystal/audio/sfx.asm`), used in Task 1:

```
Sfx_Bump_Ch5 (hw=1, tone/square path):
  duty_cycle 2         -> DB 02
  pitch_sweep 5, -2     -> DD 5A
  square_note 15,15,1,768 -> 0F F1 00 03
  pitch_sweep 0, 8      -> DD 08
  sound_ret             -> FF

Sfx_EnterDoor_Ch8 (hw=4, noise path):
  noise_note 9,15,1,68  -> 09 F1 44
  noise_note 8,13,1,67  -> 08 D1 43
  sound_ret             -> FF
```

## File Structure

- `src/audio/CrystalMusicTranscoder.lua` — `decodeChannel` gains a 5th parameter `isSfx` (default falsy, fully backward-compatible with every existing call site) and a raw-record branch that activates only when `isSfx` is true; gains a `pitch_sweep_cmd` ($DD) branch (independent of `isSfx`, since nothing stops a future music use); gains a `toggle_sfx_cmd` ($DF) branch that drops the byte (structural marker only — this transcoder decides raw-vs-packed per channel via `isSfx`, not via Crystal's own mid-stream toggle, so the byte carries no information this pipeline needs). Gains a new `CrystalMusicTranscoder.buildSfx(channels)` function, sibling to `buildSong`, that passes `isSfx = true` through to every `decodeChannel` call and calls `ChipAsm.sfx(...)` instead of `ChipAsm.song(...)`.
- `src/import/RomExtractorGen2.lua` — gains `extractSfx()`, called from `:run()`, feeding a new `results.audio.sfx` table (previously absent entirely for Crystal).
- `tools/make_rom_manifest_crystal.py` — `REQUIRED_SYMBOLS` gains the 14 real channel symbols this batch's 9 SFX need.
- `tools/rom_manifest_crystal.json` — regenerated, diffed (14 new symbol entries, additive only), applied.
- `tests/engine/gen2_crystal_sfx_decode.lua` (new, Task 1) — pins raw `square_note`/`noise_note`/`pitch_sweep`/`toggle_sfx` decoding and `buildSfx`'s channel numbering against the two byte-verified fixtures above.
- `tests/engine/gen2_sfx_names.lua` (new, Task 2) — pins the manifest's new symbol entries and, when a real ROM import is available locally, that each of the 9 names resolves to a real chip def.

## Task 1: SFX raw-note decoding (`square_note`/`noise_note`/`pitch_sweep`) in CrystalMusicTranscoder

**Files:**
- Modify: `src/audio/CrystalMusicTranscoder.lua`
- Test: `tests/engine/gen2_crystal_sfx_decode.lua` (new)

**Interfaces:**
- Consumes: nothing new — extends `CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels)`'s existing signature with an optional 5th parameter.
- Produces: `CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels, isSfx)` — when `isSfx` is true, every byte below `0xD0` decodes as `{squareNote = {len, volume, fade, frequency}}` (hw ~= 4) or `{noiseNote = {len, volume, fade, parameter}}` (hw == 4), matching `src/audio/ChipAsm.lua`'s existing `E.squareNote`/`E.noiseNote` event shapes exactly (`ChipAsm.lua:199-215`). A new `$DD` branch produces `{pitchSweep = {pace, subtract, shift}}`, matching `ChipAsm.lua`'s existing `E.pitchSweep` (`ChipAsm.lua:217-223`). A new `CrystalMusicTranscoder.buildSfx(channels)` function (same `channels` array shape as `buildSong`) is what Task 2's `extractSfx` will call.

- [ ] **Step 1: Write the failing test**

Create `tests/engine/gen2_crystal_sfx_decode.lua`:

```lua
-- Regression guard for Crystal SFX decoding, added for the SFX plan
-- (docs/superpowers/plans/2026-08-08-gen2-crystal-sfx.md, Task 1). Most of
-- Crystal's short "impact" SFX are built from square_note/noise_note --
-- a raw length+envelope+literal-GB-frequency record with no leading
-- command byte, completely different from the octave/note_type/pitch
-- scheme music uses -- decoded only when the caller marks a channel as
-- SFX (real hardware decides this per-channel via a CHANNEL_FLAGS1 bit,
-- not by sniffing command bytes -- see the plan's "Research already
-- done" section).
--
-- Fixture bytes hand-derived from real ROM data
-- (roms/pokecrystal/audio/sfx.asm, gitignored, not committed):
--   Sfx_Bump_Ch5 (hw=1, tone path):
--     duty_cycle 2            -> DB 02
--     pitch_sweep 5, -2        -> DD 5A
--     square_note 15,15,1,768  -> 0F F1 00 03
--     pitch_sweep 0, 8         -> DD 08
--     sound_ret                -> FF
--   Sfx_EnterDoor_Ch8 (hw=4, noise path):
--     noise_note 9,15,1,68     -> 09 F1 44
--     noise_note 8,13,1,67     -> 08 D1 43
--     sound_ret                -> FF
--   luajit tests/engine/gen2_crystal_sfx_decode.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Transcoder = require("src.audio.CrystalMusicTranscoder")

-- tone (square) path -------------------------------------------------------
local bumpBytes = { 0xDB, 0x02, 0xDD, 0x5A, 0x0F, 0xF1, 0x00, 0x03, 0xDD, 0x08, 0xFF }
local bumpEvents = Transcoder.decodeChannel(bumpBytes, 1, 0x5D6F, {}, true)

eq(#bumpEvents, 5, "5 events: duty, sweep, squareNote, sweep, ret")
eq(bumpEvents[1].duty, 2, "duty_cycle decodes the same on an sfx channel")

check(bumpEvents[2].pitchSweep ~= nil, "pitch_sweep_cmd produces a pitchSweep event")
eq(bumpEvents[2].pitchSweep.pace, 5, "pitch_sweep 5,-2 -> pace=5")
eq(bumpEvents[2].pitchSweep.subtract, true, "pitch_sweep 5,-2 -> subtract=true")
eq(bumpEvents[2].pitchSweep.shift, 2, "pitch_sweep 5,-2 -> shift=2")

check(bumpEvents[3].squareNote ~= nil, "a raw byte on an sfx tone channel produces a squareNote event")
eq(bumpEvents[3].squareNote.len, 16, "square_note 15,... masks to length nibble 15, +1 = 16")
eq(bumpEvents[3].squareNote.volume, 15, "square_note volume (high envelope nibble)")
eq(bumpEvents[3].squareNote.fade, 1, "square_note fade (low envelope nibble, positive case)")
eq(bumpEvents[3].squareNote.frequency, 768, "square_note raw little-endian frequency")

eq(bumpEvents[4].pitchSweep.pace, 0, "pitch_sweep 0,8 -> pace=0")
eq(bumpEvents[4].pitchSweep.subtract, true, "pitch_sweep 0,8 -> subtract=true (bit 3 of 0x08)")
eq(bumpEvents[4].pitchSweep.shift, 0, "pitch_sweep 0,8 -> shift=0")

check(bumpEvents[5].ret == true, "terminates on sound_ret")

-- noise path -----------------------------------------------------------
local doorBytes = { 0x09, 0xF1, 0x44, 0x08, 0xD1, 0x43, 0xFF }
local doorEvents = Transcoder.decodeChannel(doorBytes, 4, 0x5D08, {}, true)

eq(#doorEvents, 3, "3 events: 2 noiseNotes, ret")
check(doorEvents[1].noiseNote ~= nil, "a raw byte on an sfx noise channel produces a noiseNote event")
eq(doorEvents[1].noiseNote.len, 10, "noise_note 9,... masks to length nibble 9, +1 = 10")
eq(doorEvents[1].noiseNote.volume, 15, "noise_note volume")
eq(doorEvents[1].noiseNote.fade, 1, "noise_note fade")
eq(doorEvents[1].noiseNote.parameter, 68, "noise_note raw parameter byte")
eq(doorEvents[2].noiseNote.len, 9, "noise_note 8,... masks to length nibble 8, +1 = 9")
eq(doorEvents[2].noiseNote.parameter, 67, "second noise_note's parameter")
check(doorEvents[3].ret == true, "terminates on sound_ret")

-- toggle_sfx is a structural no-op for this pipeline (dropped, not an event)
local toggleBytes = { 0xDF, 0xFF }
local toggleEvents = Transcoder.decodeChannel(toggleBytes, 1, 0x0000, {}, true)
eq(#toggleEvents, 1, "toggle_sfx produces no event of its own")
check(toggleEvents[1].ret == true, "toggle_sfx is skipped, sound_ret still terminates")

-- regression guard: isSfx omitted/false must leave music decoding
-- byte-for-byte unchanged -- a plain note byte must NOT become a
-- squareNote just because it happens to be < 0xD0
local plainNoteBytes = { 0x1F, 0xFF } -- pitch=1, len=16 in the packed scheme
local plainEvents = Transcoder.decodeChannel(plainNoteBytes, 1, 0x0000, {})
check(plainEvents[1].pitch ~= nil, "without isSfx, a sub-0xD0 byte still decodes as a packed note")
eq(plainEvents[1].pitch, 0, "packed note pitch nibble (1) decodes to pitch 0 (1-indexed shift)")
eq(plainEvents[1].len, 16, "packed note length nibble (15) decodes to len 16")
check(plainEvents[1].squareNote == nil, "without isSfx, no squareNote event is ever produced")

-- buildSfx places channels on hardware+4 (Crystal's own 5-8 sfx numbering)
local sfxSong = Transcoder.buildSfx({
  { hw = 1, baseAddress = 0x5D6F, bytes = bumpBytes },
})
eq(sfxSong.chip.channels[1].number, 5, "buildSfx assembles hw=1 onto channel 5 (ChipAsm.sfx's own hw+4)")

T.finish("Gen2 CrystalMusicTranscoder SFX decoding (square_note/noise_note/pitch_sweep)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `luajit tests/engine/gen2_crystal_sfx_decode.lua`
Expected: FAIL — `decodeChannel` doesn't accept a 5th argument yet, `$DD`/`$DF` fall into the current catch-all `error("unsupported opcode")`, and `Transcoder.buildSfx` doesn't exist.

- [ ] **Step 3: Implement the fix**

In `src/audio/CrystalMusicTranscoder.lua`, change `decodeChannel`'s signature and add the raw-record branch. The raw-record check must come before the existing `cmd < 0xD0` packed-note branch, since both match the same byte range:

```lua
function CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels, isSfx)
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
    elseif isSfx and cmd < 0xD0 then -- ParseSFXOrCry (audio/engine.asm):
      -- on an sfx channel EVERY sub-$D0 byte is a raw square_note/
      -- noise_note record, not a packed one-byte note -- no command-byte
      -- distinction exists in Crystal's own dialect (unlike Gen1's native
      -- $20-$2F prefix); the plan's "Research already done" section
      -- verifies the exact masking against SetNoteDuration.
      local length = bit.band(cmd, 0x0F) + 1
      local packed = bytes[i + 1]
      local volume, fade = bit.rshift(packed, 4), fadeValue(bit.band(packed, 0x0F))
      if hw == 4 then
        events[#events + 1] = { noiseNote = {
          len = length, volume = volume, fade = fade, parameter = bytes[i + 2],
        } }
        i = i + 3
      else
        local frequency = bytes[i + 2] + bytes[i + 3] * 0x100
        events[#events + 1] = { squareNote = {
          len = length, volume = volume, fade = fade, frequency = frequency,
        } }
        i = i + 4
      end
    elseif cmd == 0xDD then -- pitch_sweep_cmd: same high-nibble-pace,
      -- low-nibble-signed-shift packing as ChipAsm.lua's own E.pitchSweep
      -- (verified against Sfx_Bump_Ch5's real bytes in the plan's
      -- "Research already done" section).
      local packed = bytes[i + 1]
      events[#events + 1] = { pitchSweep = {
        pace = bit.rshift(packed, 4),
        subtract = bit.band(packed, 8) ~= 0,
        shift = bit.band(packed, 7),
      } }
      i = i + 2
    elseif cmd == 0xDF then -- toggle_sfx_cmd: structural marker only. This
      -- pipeline decides raw-vs-packed per channel via the isSfx
      -- parameter (set by the caller for the whole channel), not via
      -- Crystal's own mid-stream toggle, so the byte carries no
      -- information this decoder needs -- dropped, same treatment as
      -- volume_cmd/toggle_noise_cmd below.
      i = i + 1
```

(Every other existing branch — `tempo`, `duty_cycle`, `volume_envelope`, `volume`, `note_type`, `octave`, `vibrato`, `toggle_noise`, `pitch_offset`, `stereo_panning`, the packed-note branch, `sound_loop`, `sound_call`, the catch-all error — is unchanged; only inserted above.)

Add the new `buildSfx` function immediately after the existing `buildSong`:

```lua
-- Sibling to buildSong: assembles onto Crystal's own SFX channel range
-- (hardware+4, i.e. channels 5-8) via ChipAsm.sfx instead of
-- ChipAsm.song, and marks every channel isSfx so decodeChannel's raw
-- square_note/noise_note branch activates.
function CrystalMusicTranscoder.buildSfx(channels)
  local specs = {}
  for index, channel in ipairs(channels) do
    local subroutines
    if channel.subroutines then
      subroutines = {}
      for name, sub in pairs(channel.subroutines) do
        subroutines[name] = CrystalMusicTranscoder.decodeChannel(
          sub.bytes, channel.hw, sub.baseAddress, channel.labels, true)
      end
    end
    specs[index] = {
      hw = channel.hw,
      program = CrystalMusicTranscoder.decodeChannel(
        channel.bytes, channel.hw, channel.baseAddress, channel.labels, true),
      subroutines = subroutines,
    }
  end
  return ChipAsm.sfx({ channels = specs })
end
```

Update `decodeChannel`'s own header comment (documenting the new `isSfx` parameter) and the file's top-level header comment (documenting that raw square_note/noise_note SFX decoding was added for this plan).

- [ ] **Step 4: Run test to verify it passes**

Run: `luajit tests/engine/gen2_crystal_sfx_decode.lua`
Expected: PASS, all checks green.

- [ ] **Step 5: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add src/audio/CrystalMusicTranscoder.lua tests/engine/gen2_crystal_sfx_decode.lua
git commit -m "feat: decode Crystal's raw square_note/noise_note SFX records

Most of Crystal's short SFX (bump, cut, wrong, ball poof, ledge jump,
transaction, enter door, intro whoosh -- 212 of 325 real sfx.asm
channel blocks) use a raw length+envelope+literal-frequency record with
no leading command byte, completely different from the octave/
note_type/pitch scheme music uses. ChipAsm.lua already had matching
squareNote/noiseNote/pitchSweep event types and a ChipAsm.sfx()
entrypoint (channels 5-8) -- this only teaches the decoder to produce
them, verified against real ROM engine.asm interpreter logic and two
hand-derived byte fixtures (Sfx_Bump_Ch5, Sfx_EnterDoor_Ch8).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: Extract the first 9 SFX and wire `results.audio.sfx`

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py` (`REQUIRED_SYMBOLS`, 14 new entries)
- Modify: `tools/rom_manifest_crystal.json` (regenerated)
- Modify: `src/import/RomExtractorGen2.lua` (`extractSfx`, one line in `run()`)
- Test: `tests/engine/gen2_sfx_names.lua` (new)

**Interfaces:**
- Consumes: `CrystalMusicTranscoder.buildSfx` (Task 1); the manifest's new symbol entries.
- Produces: `results.audio.sfx.Collision`, `.Cut`, `.Denied`, `.Ball_Poof`, `.Ledge_Jump`, `.Withdraw_Deposit`, `.Go_Inside`, `.Get_Key_Item`, `.Intro_Whoosh` — each a real, playable `{chip = {...}}` def that `Sound.play(data, name)` already resolves with zero further changes.

- [ ] **Step 1: Add the 14 new symbols to `REQUIRED_SYMBOLS`**

In `tools/make_rom_manifest_crystal.py`, add to the `REQUIRED_SYMBOLS` tuple (all 14 confirmed present in `roms/pokecrystal/pokecrystal.sym`, bank `3c`):

```python
    # SFX plan (docs/superpowers/plans/2026-08-08-gen2-crystal-sfx.md):
    # the 14 real Sfx_*_ChN channel symbols behind this project's own
    # Collision/Cut/Denied/Ball_Poof/Ledge_Jump/Withdraw_Deposit/
    # Go_Inside/Get_Key_Item/Intro_Whoosh names -- see the plan's
    # "Research already done" section for the name->constant mapping.
    "Sfx_Bump_Ch5",             # 3c:5d6f -- Collision
    "Sfx_Cut_Ch8",              # 3c:60c3 -- Cut
    "Sfx_Wrong_Ch5",            # 3c:5f05 -- Denied
    "Sfx_Wrong_Ch6",            # 3c:5f1c -- Denied
    "Sfx_BallPoof_Ch5",         # 3c:5ff4 -- Ball_Poof
    "Sfx_BallPoof_Ch8",         # 3c:5fff -- Ball_Poof
    "Sfx_JumpOverLedge_Ch5",    # 3c:5ebc -- Ledge_Jump
    "Sfx_Transaction_Ch5",      # 3c:5d55 -- Withdraw_Deposit
    "Sfx_Transaction_Ch6",      # 3c:5d60 -- Withdraw_Deposit
    "Sfx_EnterDoor_Ch8",        # 3c:5d08 -- Go_Inside
    "Sfx_KeyItem_Ch5",          # 3c:4b92 -- Get_Key_Item
    "Sfx_KeyItem_Ch6",          # 3c:4ba8 -- Get_Key_Item
    "Sfx_KeyItem_Ch7",          # 3c:4bb8 -- Get_Key_Item (Ch8 deliberately
                                # excluded -- see the plan's "Research
                                # already done" section)
    "Sfx_IntroWhoosh_Ch8",      # 3c:656c -- Intro_Whoosh
```

- [ ] **Step 2: Regenerate, diff, apply**

```bash
source .venv/bin/activate
python3 tools/make_rom_manifest_crystal.py --pokecrystal roms/pokecrystal --symbols roms/pokecrystal/pokecrystal.sym --out /tmp/manifest_sfx.json
python3 -c "
import json
old = json.load(open('tools/rom_manifest_crystal.json'))
new = json.load(open('/tmp/manifest_sfx.json'))
old_keys = set(old['symbols'].keys())
new_keys = set(new['symbols'].keys())
removed = old_keys - new_keys
added = new_keys - old_keys
assert not removed, f'REGRESSION: symbols removed: {removed}'
print(f'{len(added)} symbols added:', sorted(added))
"
cp /tmp/manifest_sfx.json tools/rom_manifest_crystal.json
```
Expected: the Python check prints exactly the 14 new symbol names, asserts nothing was removed. If it ever prints a non-empty `removed` set, STOP — that means `REQUIRED_SYMBOLS` is missing an entry some earlier task only hand-patched into the JSON (Milestone 2's Task 5 failure mode) — do not apply the regenerated file until the generator itself is fixed.

- [ ] **Step 3: Write `extractSfx`**

In `src/import/RomExtractorGen2.lua`, immediately after `extractRoute30Music` (so it sits with the other audio-extraction functions):

```lua
-- The first batch of Crystal SFX: the 9 names this project's own code
-- already calls by name (Sound.play/Sound.startLoop call sites across
-- src/ and data/scripts/), mapped to their real Crystal SFX_* constants
-- -- see the plan's "Research already done" section for each mapping's
-- verification. None of these channel bodies use sound_call/sound_loop
-- (confirmed against their real bytes), so no subroutines/labels table
-- is needed -- unlike every one of Milestone 2's music songs, which all
-- loop forever.
function RomExtractorGen2:extractSfx()
  self:beginStage("Sound effects")

  local function ch(symbolName, hw)
    local sym = self:symbol(symbolName)
    return { hw = hw, baseAddress = sym.address,
      bytes = self.rom:bytes(sym.bank, sym.address, 40) }
  end

  local sfx = {
    Collision = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_Bump_Ch5", 1),
    }),
    Cut = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_Cut_Ch8", 4),
    }),
    Denied = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_Wrong_Ch5", 1), ch("Sfx_Wrong_Ch6", 2),
    }),
    Ball_Poof = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_BallPoof_Ch5", 1), ch("Sfx_BallPoof_Ch8", 4),
    }),
    Ledge_Jump = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_JumpOverLedge_Ch5", 1),
    }),
    Withdraw_Deposit = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_Transaction_Ch5", 1), ch("Sfx_Transaction_Ch6", 2),
    }),
    Go_Inside = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_EnterDoor_Ch8", 4),
    }),
    -- Ch8 (a noise drum tail) deliberately excluded -- see the plan's
    -- "Research already done" section.
    Get_Key_Item = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_KeyItem_Ch5", 1), ch("Sfx_KeyItem_Ch6", 2), ch("Sfx_KeyItem_Ch7", 3),
    }),
    Intro_Whoosh = CrystalMusicTranscoder.buildSfx({
      ch("Sfx_IntroWhoosh_Ch8", 4),
    }),
  }

  self:tick("Sound effects", 1, 1)
  return sfx
end
```

- [ ] **Step 4: Wire it into `results.audio`**

In `RomExtractorGen2:run()`, add the call and the new `sfx` field:

```lua
  local route30Song = self:extractRoute30Music()
  local sfx = self:extractSfx()
  local mapSongs = {}
```

```lua
  results.audio = {
    cries = cries.cries,
    songs = {
      Music_TitleScreen = titleSong,
      Music_ElmsLab = elmsLabSong,
      Music_CherrygroveCity = cherrygroveCitySong,
      Music_Route29 = route29Song,
      Music_NewBarkTown = newBarkTownSong,
      Music_Route30 = route30Song,
    },
    mapSongs = mapSongs,
    sfx = sfx,
  }
```

- [ ] **Step 5: Write the test**

Create `tests/engine/gen2_sfx_names.lua`:

```lua
-- Pins the SFX plan's manifest symbol coverage end-to-end (docs/
-- superpowers/plans/2026-08-08-gen2-crystal-sfx.md, Task 2): every real
-- Sfx_*_ChN symbol RomExtractorGen2.lua's extractSfx references by
-- literal name must exist in the committed manifest -- the same
-- regression class Milestone 2's Task 4/5 hit twice (a Lua extractor
-- shipped without its matching manifest symbols).
--   luajit tests/engine/gen2_sfx_names.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Json = require("src.link.Json")
local f = io.open("tools/rom_manifest_crystal.json", "r")
local manifest = Json.decode(f:read("*a"))
f:close()

local EXPECTED_SYMBOLS = {
  "Sfx_Bump_Ch5", "Sfx_Cut_Ch8", "Sfx_Wrong_Ch5", "Sfx_Wrong_Ch6",
  "Sfx_BallPoof_Ch5", "Sfx_BallPoof_Ch8", "Sfx_JumpOverLedge_Ch5",
  "Sfx_Transaction_Ch5", "Sfx_Transaction_Ch6", "Sfx_EnterDoor_Ch8",
  "Sfx_KeyItem_Ch5", "Sfx_KeyItem_Ch6", "Sfx_KeyItem_Ch7",
  "Sfx_IntroWhoosh_Ch8",
}

for _, name in ipairs(EXPECTED_SYMBOLS) do
  check(manifest.symbols[name] ~= nil,
    ("manifest has a %s symbol entry"):format(name))
end

-- Runtime chip-def shape can only be checked against a real ROM import
-- (no data/generated/ in this checkout) -- if one exists locally, verify
-- every one of the 9 names resolves to a real chip def; otherwise skip
-- with a clear reason, matching gen2_map_songs.lua's own precedent.
if love.filesystem and love.filesystem.getInfo
   and love.filesystem.getInfo("data/generated/audio.lua") then
  local audio = require("data.generated.audio")
  local EXPECTED_NAMES = {
    "Collision", "Cut", "Denied", "Ball_Poof", "Ledge_Jump",
    "Withdraw_Deposit", "Go_Inside", "Get_Key_Item", "Intro_Whoosh",
  }
  for _, name in ipairs(EXPECTED_NAMES) do
    check(audio.sfx and audio.sfx[name] ~= nil,
      ("%s resolves to a real sfx def when a ROM is imported"):format(name))
  end
else
  print("(skipped: no data/generated/audio.lua in this environment -- " ..
    "runtime sfx-def shape needs a real ROM import to verify)")
end

T.finish("Gen2 SFX manifest symbol coverage")
```

- [ ] **Step 6: Run the test, then the full suite, then commit**

```bash
luajit tests/engine/gen2_sfx_names.lua
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json src/import/RomExtractorGen2.lua tests/engine/gen2_sfx_names.lua
git commit -m "feat: extract Crystal's first 9 sound effects

results.audio.sfx did not exist for Crystal at all, so every Sound.play
call (collision bumps, cut, denied, ball poof, ledge jump, PC
withdraw/deposit, entering a building, the key-item fanfare, the title
intro whoosh) was a silent no-op. Wires the 9 SFX this project's own
code already calls by name to their real Crystal SFX_* equivalents
(name mapping verified against real engine/ callsites -- see the
plan's Research section). The other ~198 SFX in Crystal's own catalog
are deliberately out of scope for this batch.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** the user's request ("SFX primeiro") is scoped, per the earlier scoping research in this session, to the SFX this project's own code already references rather than Crystal's full 207-entry catalog. This plan delivers exactly that for the 9 names whose real-constant mapping and byte encoding were fully verified; the remaining ~15 referenced names (ambiguous mappings, unconfirmed Crystal reachability, or a different namespace entirely) are explicitly listed with reasons in the Research section rather than silently dropped or guessed at, so a follow-up plan can pick them up without re-deriving this session's findings.

**Placeholder scan:** every task has real symbol names (verified present in `pokecrystal.sym`), real byte-packing math (hand-verified against `roms/pokecrystal/audio/engine.asm`'s actual interpreter and two full byte-level fixtures), and real commit messages. The one deliberate scope-narrowing decision (`Sfx_KeyItem_Ch8` excluded) is backed by a specific, named risk (a genuine byte-stream ambiguity found by tracing the real interpreter, not a guess), not a "TODO" — matching `Music_NewBarkTown`'s own precedent for a song legitimately shipping fewer than 4 channels.

**Type consistency:** `CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels, isSfx)`'s new 5th parameter is optional and additive — every existing call site (all 6 of Milestone 2's `extractXMusic` functions, calling `buildSong` which never passes `isSfx`) is unaffected, confirmed by the explicit regression check in Task 1's own test. `buildSfx`'s `channels` parameter shape is identical to `buildSong`'s (array of `{hw, baseAddress, bytes, subroutines, labels}`), and its output (`ChipAsm.sfx(...)`'s return value) is the same `{chip = {...}}` shape `buildSong`/`ChipAsm.song(...)` already produces — matching `isChipDef`'s check (`Sound.lua:81-83`) and `Sound.play`'s existing, unmodified lookup (`data.audio.sfx[name]`) exactly.
