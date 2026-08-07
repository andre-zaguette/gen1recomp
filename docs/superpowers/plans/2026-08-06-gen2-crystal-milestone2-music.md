# Milestone 2: Early-Game Crystal Music Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every Crystal map registered by Milestone 1 (New Bark Town's cluster, Elm's Lab, Route 29, the Route29/46 gate, Cherrygrove City, Route 30, Mr. Pokémon's House) its own real ROM music, replacing the current "title theme plays forever" bug.

**Architecture:** Extend `src/audio/CrystalMusicTranscoder.lua` (already proven for `Music_TitleScreen`) to decode Game Boy hardware channel 3 (wave) — every one of the 5 songs this milestone needs uses it, and the transcoder currently only handles channels 1/2 (pulse) and 4 (noise). Then add one `RomExtractorGen2:extractXMusic()` function per song, mirroring `extractTitleMusic`'s exact structure, feeding `results.audio.songs`. Finally, extend `tools/make_rom_manifest_crystal.py`'s existing `MAP_SPECS` with each map's song label and use it to build `results.audio.mapSongs` (currently absent for Crystal), which `src/core/Music.lua:Music.playMap` already reads on every map entry — no changes needed to the playback/map-transition side, only to what data it's given.

**Tech Stack:** Lua (LÖVE2D), Python 3 (manifest generation), the existing `ChipAsm`/`ChipSynth` chip-audio playback pipeline (unchanged).

## Global Constraints

- No ROM bytes may ever be committed (`.gitignore`'s `/roms/` entry) — `tools/rom_manifest_crystal.json` carries only derived text/metadata (song label strings, symbol bank:address pairs), never raw song bytes.
- `GameVersion.isCrystal()` gates all Gen1/Gen2 divergence; this milestone touches Gen2-only code paths (`RomExtractorGen2.lua`, `make_rom_manifest_crystal.py`) and does not modify Gen1's own `RomExtractor.lua`/`make_rom_manifest.py`/`make_yellow_manifest.py`.
- Every regenerated `tools/rom_manifest_crystal.json` diff must be reviewed (`diff` against the committed file) before applying — expect additive-only changes (new `"music"` fields on already-registered maps), never a change to any other field.
- Full test suite (`LUA=luajit scripts/test.sh`) must report `ALL TIERS PASSED` before every commit.
- `CrystalMusicTranscoder.decodeChannel`'s existing "raise on anything unverified" stance (hard `error()` on an unsupported opcode or an unresolvable `sound_call`/`sound_loop` target) must be preserved — do not add a silent fallback for a byte pattern nobody has verified against the real ROM.
- `Music.play`'s existing graceful-no-op behavior (`if not songDef(data, song) then return end`, `src/core/Music.lua`) means a `mapSongs` entry pointing at a song not yet extracted is safe, not a crash — this lets each task in this plan land independently playable/testable without waiting for every song to exist.

## Research already done

**The core finding that changes this milestone's scope from the roadmap's original estimate:** the roadmap note (`docs/superpowers/plans/2026-08-06-gen2-crystal-roadmap.md`, Milestone 2 bullet) assumed this milestone was "do the title-screen work two more times, not new engine work" and estimated 2-3 songs. Both are wrong in ways that matter:

1. **5 songs, not 2-3.** Two more maps (Cherrygrove City, Route 30) were registered by Milestone 1's Tasks 5/7 after that note was written. Verified directly against `roms/pokecrystal/data/maps/maps.asm`'s `map` macro (5th field) for all 11 currently-registered Crystal maps:

   | Map (this project's id) | Real `MUSIC_*` constant | `maps.asm` line |
   |---|---|---|
   | `NEW_BARK_TOWN` | `MUSIC_NEW_BARK_TOWN` | 494 |
   | `PLAYERS_HOUSE_1F` | `MUSIC_NEW_BARK_TOWN` | 496 |
   | `PLAYERS_HOUSE_2F` | `MUSIC_NEW_BARK_TOWN` | 497 |
   | `PLAYERS_NEIGHBORS_HOUSE` | `MUSIC_NEW_BARK_TOWN` | 498 |
   | `ELMS_HOUSE` | `MUSIC_NEW_BARK_TOWN` | 499 |
   | `ELMS_LAB` | `MUSIC_PROF_ELM` | 495 |
   | `ROUTE_29` | `MUSIC_ROUTE_29` | 493 |
   | `ROUTE_29_ROUTE_46_GATE` | `MUSIC_ROUTE_29` | 503 |
   | `CHERRYGROVE_CITY` | `MUSIC_CHERRYGROVE_CITY` | 529 |
   | `ROUTE_30` | `MUSIC_ROUTE_30` | 527 |
   | `MR_POKEMONS_HOUSE` | `MUSIC_CHERRYGROVE_CITY` | 536 |

   Exactly **5 distinct songs** cover all 11 maps: `MUSIC_NEW_BARK_TOWN`, `MUSIC_PROF_ELM`, `MUSIC_ROUTE_29`, `MUSIC_CHERRYGROVE_CITY`, `MUSIC_ROUTE_30`.

2. **This IS new engine work, not pure repetition — every one of the 5 songs uses Channel 3 (wave), which `CrystalMusicTranscoder.lua` explicitly does not decode** (its own header comment: "Channel 3 (wave) is out of scope... never 3"). `Music_TitleScreen` happens to be a 3-channel song (Ch1/Ch2/Ch4 only, confirmed: no `Music_TitleScreen_Ch3` symbol exists in `pokecrystal.sym`) — that's *why* wave decoding was never needed before, not evidence it's unnecessary going forward. Confirmed via `pokecrystal.sym`: every one of `Music_ElmsLab`, `Music_NewBarkTown`, `Music_Route29`, `Music_Route30`, `Music_CherrygroveCity` has a `_Ch3` symbol.

3. **The wave-channel gap is small, not a new opcode dialect.** Read the real, human-authored disassembly source for all 5 songs' Ch3 sections directly (`roms/pokecrystal/audio/music/{elmslab,newbarktown,route29,route30,cherrygrovecity}.asm`) and enumerated every distinct command macro used on Channel 3 across all 5:
   ```
   note, note_type, octave, rest, sound_loop, stereo_panning, vibrato, volume_envelope
   ```
   Every one of these is **already a supported opcode** in `CrystalMusicTranscoder.decodeChannel` (0xD0-D7 octave, 0xD8 note_type, 0xDC volume_envelope, 0xE1 vibrato, 0xEF stereo_panning, <0xD0 plain note/rest, 0xFD sound_loop) for hw 1/2/4. The *only* channel-3-specific difference is the meaning of `note_type`'s (and `volume_envelope`'s) packed third byte: `src/audio/ChipAsm.lua`'s own `E.notetype` function already documents and implements this exact distinction — "none on noise, wave level plus instrument on channel 3, volume plus fade on the two square channels" (`ChipAsm.lua:112-125`) — packing `waveLevel * 16 + waveInstrument` for hw==3 vs. `volume * 16 + fade` otherwise. `decodeChannel` just needs to branch the same way `ChipAsm` already does on the *decode* side; the *assembly* (ChipAsm) and *playback* (`src/core/ChipSynth.lua`, which already fully implements `hardware == 3`/`waveInstrument`/`waveLevel`/`self.engine.waves[...]`, confirmed by reading it) sides need zero changes. This is genuinely "extend one function's two branches," not new infrastructure.

4. **A concrete, byte-verified test fixture already exists** from `Music_ElmsLab_Ch3`'s real, simplest-of-the-5 source (`roms/pokecrystal/audio/music/elmslab.asm`):
   ```
   Music_ElmsLab_Ch3:
   \tstereo_panning FALSE, TRUE
   \tnote_type 12, 2, 5
   \trest 8
   ```
   `note_type`'s opcode is `$D8`, followed by `speed` (12) then, on a non-noise channel, one packed byte. Per `ChipAsm.lua`'s own wave packing (`waveLevel * 16 + waveInstrument`), `note_type 12, 2, 5` (macro args: speed=12, waveLevel=2, waveInstrument=5) packs to byte `2*16+5 = 0x25 = 37`. `stereo_panning`'s opcode is `$EF` followed by one packed byte (`FALSE, TRUE` — `home/audio.asm`'s own `stereo_panning` macro packs the two 4-bit nibbles the same way Ch1/Ch2/Ch4 already use, unchanged from the existing 0xEF branch). This gives Task 1 real, ROM-derived byte values to test against, not invented ones.

5. **Sub-label shapes differ per song per channel** — confirmed via `pokecrystal.sym` (full listing below, per song), so **each song needs its own hand-verified extraction function** (matching `extractTitleMusic`'s established per-song-hardcoded-symbols pattern), not a generalized/data-driven decoder. A song's own `.sym` labels are the single source of truth for what subroutines exist:

   ```
   Music_ElmsLab:         Ch1/Ch2/Ch3/Ch4, each ONLY .mainloop (no sub-labels)
   Music_CherrygroveCity: Ch1/Ch2/Ch3/Ch4, each ONLY .mainloop (no sub-labels)
   Music_Route29:         Ch1 .mainloop; Ch2 .mainloop + .sub1; Ch3 .mainloop; Ch4 .mainloop
   Music_NewBarkTown:     Ch1 .mainloop + .sub1 + .sub2; Ch2 .mainloop + .sub1 + .sub2;
                           Ch3 .mainloop; NO Ch4 (this song never uses the noise channel --
                           confirmed by its absence from pokecrystal.sym, not an oversight)
   Music_Route30:         Ch1/Ch2/Ch3 each ONLY .mainloop; Ch4 .mainloop + .sub1..sub5
   ```

   None of these 5 songs has a *nested* subroutine label (a `.subN.subM`-shaped address inside another subroutine's own byte window) the way `Music_TitleScreen_Ch1.sub1loop1` did — every sub-label here is a direct `sound_call`/`sound_loop` target at the top level, which simplifies each song's `labels` table to a flat address→name map exactly like `extractTitleMusic`'s `ch4Labels` already demonstrates.

6. **`results.audio.mapSongs` does not exist for Crystal today** (`RomExtractorGen2.lua:1693`'s `results.audio = { cries = ..., songs = { Music_TitleScreen = titleSong } }` — no `mapSongs` key at all), which is *why* `Music.playMap` (`src/core/Music.lua:339`, `local song = data.audio.mapSongs and mapId and data.audio.mapSongs[mapId] or nil`) finds nothing on every map entry and silently no-ops, leaving whatever was playing (the title theme) stuck. `tools/make_rom_manifest_crystal.py`'s `MAP_SPECS` has no `"music"` field on any map entry today (only `"label"`, `"asm"`, `"tileset"`) — this plan adds one, following the exact same "hand-transcribed, ROM-line-cited" convention `"tileset"` already established (not a new regex-parsed field).

## File Structure

- `src/audio/CrystalMusicTranscoder.lua` — gains hw==3 (wave) branches in `decodeChannel`'s existing `note_type_cmd` ($D8) and `volume_envelope_cmd` ($DC) handlers. No new file — same "parallel pipeline, not a rewrite" precedent its own header comment already establishes for staying separate from `CrystalCryTranscoder.lua`.
- `src/import/RomExtractorGen2.lua` — gains 5 new `extractXMusic()` functions (one per song, each ~40-70 lines mirroring `extractTitleMusic`'s exact shape), each called from `:run()` and folded into `results.audio.songs`; `:extractMap()`'s existing per-map `out[mapId] = {...}` table gains a `music` field sourced from the manifest; `:run()` gains a small loop building `results.audio.mapSongs` from every registered map's `music` field.
- `tools/make_rom_manifest_crystal.py` — each of the 11 already-registered `MAP_SPECS` entries gains a `"music"` string field (the song label, e.g. `"Music_NewBarkTown"`).
- `tools/rom_manifest_crystal.json` — regenerated, diffed, applied per task (only the touched maps' entries gain a `"music"` field each task).
- `tests/engine/gen2_crystal_music_ch3.lua` (new, Task 1) — pins wave-channel decoding against the real, byte-verified `Music_ElmsLab_Ch3` fixture from Research Finding 4.
- `tests/engine/gen2_map_songs.lua` (new, Task 2, extended each task after) — pins `results.audio.mapSongs`' shape and, per task, that each newly-extracted song's label resolves to a real (non-nil, structurally valid per `ChipAsm.song`'s own return shape) song definition.

## Task 1: Wave-channel (hw=3) decoding in CrystalMusicTranscoder

**Files:**
- Modify: `src/audio/CrystalMusicTranscoder.lua`
- Test: `tests/engine/gen2_crystal_music_ch3.lua` (new)

**Interfaces:**
- Consumes: nothing new — this task only changes `CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels)`'s existing signature's *behavior* when `hw == 3` (previously undocumented/unsupported).
- Produces: `decodeChannel` and `buildSong` both accept `hw = 3` without erroring; a wave-channel `note_type`/`volume_envelope` event carries `{waveLevel = N, waveInstrument = M}` instead of `{volume = N, fade = M}`, matching `src/audio/ChipAsm.lua`'s `E.notetype` (`ChipAsm.lua:112-125`) — the format Task 2 onward's `extractXMusic` functions will feed to `CrystalMusicTranscoder.buildSong({ {hw = 3, ...}, ... })`.

- [ ] **Step 1: Write the failing test**

Create `tests/engine/gen2_crystal_music_ch3.lua`:

```lua
-- Regression guard for CrystalMusicTranscoder's wave-channel (hw=3)
-- decoding, added for Milestone 2 (docs/superpowers/plans/
-- 2026-08-06-gen2-crystal-milestone2-music.md, Task 1). Every one of the
-- 5 songs this milestone needs uses Channel 3; the transcoder only
-- handled channels 1/2/4 before this task.
--
-- Fixture bytes derived directly from roms/pokecrystal/audio/music/
-- elmslab.asm's real Music_ElmsLab_Ch3 (the shortest/simplest of the 5
-- songs' wave channels):
--   stereo_panning FALSE, TRUE   -> $EF, packed(0,1) = $01
--   note_type 12, 2, 5           -> $D8, speed=12, packed(waveLevel=2,
--                                    waveInstrument=5) = 2*16+5 = $25
--   rest 8                       -> dn(0, 8-1) = $07
--   (no sound_ret in this excerpt -- appended $FF here so decodeChannel
--   has a real terminator; the ROM's own real Ch3 program continues with
--   octave/note/sound_loop bytes not needed to prove this task's fix)
--   luajit tests/engine/gen2_crystal_music_ch3.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Transcoder = require("src.audio.CrystalMusicTranscoder")

local ch3Bytes = { 0xEF, 0x01, 0xD8, 12, 0x25, 0x07, 0xFF }

local events = Transcoder.decodeChannel(ch3Bytes, 3, 0x6216, {})

eq(#events, 4, "4 events: pan, notetype, rest, ret")
eq(events[1].pan, 0x01, "stereo_panning decodes the same on hw=3 as hw=1/2/4")
check(events[2].notetype ~= nil, "note_type_cmd produces a notetype event on hw=3")
eq(events[2].notetype.speed, 12, "notetype.speed")
eq(events[2].notetype.waveLevel, 2, "hw=3 notetype packs waveLevel from the high nibble")
eq(events[2].notetype.waveInstrument, 5, "hw=3 notetype packs waveInstrument from the low nibble")
check(events[2].notetype.volume == nil,
  "hw=3 notetype must NOT carry a pulse-channel volume field")
check(events[2].notetype.fade == nil,
  "hw=3 notetype must NOT carry a pulse-channel fade field")
eq(events[3].rest, 8, "plain rest record decodes the same on hw=3")
check(events[4].ret == true, "terminates on sound_ret")

-- volume_envelope_cmd ($DC) must branch the same way: packed byte
-- 0x25 (waveLevel=2, waveInstrument=5) via the DC opcode instead of D8.
local envEvents = Transcoder.decodeChannel({ 0xDC, 0x25, 0xFF }, 3, 0x0000, {})
check(envEvents[1].notetype ~= nil, "volume_envelope_cmd also produces a notetype event on hw=3")
eq(envEvents[1].notetype.waveLevel, 2, "volume_envelope_cmd hw=3 waveLevel")
eq(envEvents[1].notetype.waveInstrument, 5, "volume_envelope_cmd hw=3 waveInstrument")

-- hw 1/2/4 behavior must be byte-for-byte unchanged (regression guard --
-- this task must not touch the existing volume/fade packing).
local pulseEvents = Transcoder.decodeChannel({ 0xD8, 10, 0x37, 0xFF }, 1, 0x0000, {})
eq(pulseEvents[1].notetype.speed, 10, "hw=1 notetype.speed unchanged")
eq(pulseEvents[1].notetype.volume, 3, "hw=1 notetype.volume unchanged (high nibble)")
eq(pulseEvents[1].notetype.fade, 7, "hw=1 notetype.fade unchanged (low nibble, unsigned case)")
check(pulseEvents[1].notetype.waveLevel == nil, "hw=1 notetype must NOT carry waveLevel")
check(pulseEvents[1].notetype.waveInstrument == nil, "hw=1 notetype must NOT carry waveInstrument")

T.finish("Gen2 CrystalMusicTranscoder wave-channel (hw=3) decoding")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `luajit tests/engine/gen2_crystal_music_ch3.lua`
Expected: FAIL — the current `hw == 4` / `else` branch in `note_type_cmd` (and the unconditional branch in `volume_envelope_cmd`) builds `{volume = ..., fade = ...}` for hw=3 too, so `events[2].notetype.volume` is non-nil (should be nil) and `waveLevel`/`waveInstrument` are nil (should be 2/5).

- [ ] **Step 3: Implement the fix**

In `src/audio/CrystalMusicTranscoder.lua`, update `decodeChannel`'s `note_type_cmd` ($D8) branch (currently lines ~123-136):

```lua
    elseif cmd == 0xD8 then -- note_type_cmd (also drum_speed on hw==4)
      local speed = bytes[i + 1]
      lastSpeed = speed
      if hw == 4 then
        events[#events + 1] = { notetype = { speed = speed, volume = 0, fade = 0 } }
        i = i + 2
      elseif hw == 3 then -- wave channel: packed byte is waveLevel/waveInstrument,
        -- not volume/fade -- matches ChipAsm.lua's own E.notetype dispatch
        -- ("wave level plus instrument on channel 3").
        local packed = bytes[i + 2]
        events[#events + 1] = { notetype = {
          speed = speed,
          waveLevel = bit.rshift(packed, 4), waveInstrument = bit.band(packed, 0x0F),
        } }
        i = i + 3
      else
        local packed = bytes[i + 2]
        events[#events + 1] = { notetype = {
          speed = speed,
          volume = bit.rshift(packed, 4), fade = fadeValue(bit.band(packed, 0x0F)),
        } }
        i = i + 3
      end
```

Update `volume_envelope_cmd` ($DC) (currently lines ~98-106):

```lua
    elseif cmd == 0xDC then -- volume_envelope_cmd: no direct ChipAsm event,
      -- re-emitted as a notetype carrying the last-known speed (see the
      -- plan's "Research already done" section). hw==3 packs
      -- waveLevel/waveInstrument here too, same distinction as note_type_cmd.
      local packed = bytes[i + 1]
      if hw == 3 then
        events[#events + 1] = { notetype = {
          speed = lastSpeed,
          waveLevel = bit.rshift(packed, 4), waveInstrument = bit.band(packed, 0x0F),
        } }
      else
        events[#events + 1] = { notetype = {
          speed = lastSpeed,
          volume = bit.rshift(packed, 4), fade = fadeValue(bit.band(packed, 0x0F)),
        } }
      end
      i = i + 2
```

Update the function's own doc comment (`decodeChannel`'s header, currently says `hw` is "1/2 (pulse) or 4 (noise) -- never 3 (wave), which this module does not decode") and the file's top-level header comment (currently says "Channel 3 (wave) is out of scope: this module only handles pulse (hw 1/2) and noise (hw 4)") to reflect that hw=3 is now supported, citing this milestone's plan and the 5 songs that required it.

- [ ] **Step 4: Run test to verify it passes**

Run: `luajit tests/engine/gen2_crystal_music_ch3.lua`
Expected: PASS, all checks green.

- [ ] **Step 5: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add src/audio/CrystalMusicTranscoder.lua tests/engine/gen2_crystal_music_ch3.lua
git commit -m "feat: decode Crystal's wave-channel (hw=3) music bytecode

Every song Milestone 2 needs (ElmsLab, NewBarkTown, Route29, Route30,
CherrygroveCity) uses Channel 3; only channels 1/2/4 were supported.
The gap was narrow: note_type_cmd/volume_envelope_cmd's packed byte
means waveLevel/waveInstrument on hw=3 rather than volume/fade, exactly
mirroring the distinction ChipAsm.lua's own E.notetype already encodes
on the assembly side. No other opcode differs on Channel 3 across any
of the 5 songs (verified against their real audio/music/*.asm source).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: Extract Music_ElmsLab and wire the mapSongs mechanism

This task does two things at once because they're cheapest to prove together: extracts the simplest of the 5 songs (all four channels are just `.mainloop`, no sub-labels — the smallest possible end-to-end proof that Task 1's wave decoding really works against a real full song), and builds the `mapSongs` plumbing every subsequent task reuses. Every map's `"music"` field gets added to the manifest in this task (cheap, mechanical, all 11 lines already verified in Research Finding 1) even though only `ELMS_LAB`'s song is actually extracted here — `Music.play`'s graceful no-op (Global Constraints) means the other 10 maps' `music` fields pointing at not-yet-extracted songs are inert, not broken, until their own task lands.

**Files:**
- Modify: `tools/make_rom_manifest_crystal.py` (`MAP_SPECS`, all 11 entries gain `"music"`)
- Modify: `tools/rom_manifest_crystal.json` (regenerated)
- Modify: `src/import/RomExtractorGen2.lua` (`extractElmsLabMusic`, `extractMap`'s `music` field, `run()`'s `mapSongs` build, `results.audio.songs` gains `Music_ElmsLab`)
- Test: `tests/engine/gen2_map_songs.lua` (new)

**Interfaces:**
- Consumes: `CrystalMusicTranscoder.buildSong`/`decodeChannel` (Task 1, now hw=3-capable); the manifest's new `expected.music` field (a string like `"Music_ElmsLab"`) already present per map's `MAP_SPECS` entry.
- Produces: `results.audio.songs.Music_ElmsLab` (a real, playable song def); `results.audio.mapSongs.ELMS_LAB = "Music_ElmsLab"`; the `mapSongs`-building mechanism in `RomExtractorGen2:run()` that every later task's new song automatically flows through once its own `extractXMusic` function exists and is added to `results.audio.songs`.

- [ ] **Step 1: Add the `music` field to every map's `MAP_SPECS` entry**

In `tools/make_rom_manifest_crystal.py`, add a `"music"` key to each of the 11 existing entries (values from Research Finding 1's table above):

```python
    "NEW_BARK_TOWN": {
        ...,
        "music": "Music_NewBarkTown",  # maps.asm:494, MUSIC_NEW_BARK_TOWN
    },
    "PLAYERS_HOUSE_1F": {
        ...,
        "music": "Music_NewBarkTown",  # maps.asm:496, MUSIC_NEW_BARK_TOWN
    },
    "PLAYERS_HOUSE_2F": {
        ...,
        "music": "Music_NewBarkTown",  # maps.asm:497, MUSIC_NEW_BARK_TOWN
    },
    "PLAYERS_NEIGHBORS_HOUSE": {
        ...,
        "music": "Music_NewBarkTown",  # maps.asm:498, MUSIC_NEW_BARK_TOWN
    },
    "ELMS_HOUSE": {
        ...,
        "music": "Music_NewBarkTown",  # maps.asm:499, MUSIC_NEW_BARK_TOWN
    },
    "ELMS_LAB": {
        ...,
        "music": "Music_ElmsLab",  # maps.asm:495, MUSIC_PROF_ELM
    },
    "ROUTE_29": {
        ...,
        "music": "Music_Route29",  # maps.asm:493, MUSIC_ROUTE_29
    },
    "ROUTE_29_ROUTE_46_GATE": {
        ...,
        "music": "Music_Route29",  # maps.asm:503, MUSIC_ROUTE_29
    },
    "CHERRYGROVE_CITY": {
        ...,
        "music": "Music_CherrygroveCity",  # maps.asm:529, MUSIC_CHERRYGROVE_CITY
    },
    "ROUTE_30": {
        ...,
        "music": "Music_Route30",  # maps.asm:527, MUSIC_ROUTE_30
    },
    "MR_POKEMONS_HOUSE": {
        ...,
        "music": "Music_CherrygroveCity",  # maps.asm:536, MUSIC_CHERRYGROVE_CITY
    },
```

(`...` is the entry's existing `"label"`/`"asm"`/`"tileset"` fields — add `"music"` as one more key alongside them, do not remove or reorder anything else.)

- [ ] **Step 2: Regenerate, diff, apply**

```bash
source .venv/bin/activate
python3 tools/make_rom_manifest_crystal.py --pokecrystal roms/pokecrystal --symbols roms/pokecrystal/pokecrystal.sym --out /tmp/manifest_music.json
diff tools/rom_manifest_crystal.json /tmp/manifest_music.json
cp /tmp/manifest_music.json tools/rom_manifest_crystal.json
```
Expected: exactly 11 lines added (one `"music": "..."` per already-registered map), nothing else changes.

- [ ] **Step 3: Write `extractElmsLabMusic`**

In `src/import/RomExtractorGen2.lua`, immediately after `extractTitleMusic` (so the two sit together as siblings):

```lua
-- Music_ElmsLab's four channels, all shaped identically to
-- Music_TitleScreen's own extraction: read a generous byte window per
-- channel (decodeChannel stops at sound_ret regardless of extra trailing
-- bytes), no subroutines on any channel (per pokecrystal.sym: every
-- channel here has only its own .mainloop, no .subN labels -- see the
-- plan's "Research already done" section).
function RomExtractorGen2:extractElmsLabMusic()
  self:beginStage("Elm's Lab music")

  local ch1 = self:symbol("Music_ElmsLab_Ch1")
  local ch1Loop = self:symbol("Music_ElmsLab_Ch1.mainloop")
  local ch2 = self:symbol("Music_ElmsLab_Ch2")
  local ch2Loop = self:symbol("Music_ElmsLab_Ch2.mainloop")
  local ch3 = self:symbol("Music_ElmsLab_Ch3")
  local ch3Loop = self:symbol("Music_ElmsLab_Ch3.mainloop")
  local ch4 = self:symbol("Music_ElmsLab_Ch4")
  local ch4Loop = self:symbol("Music_ElmsLab_Ch4.mainloop")

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      labels = { [ch1Loop.address] = "mainloop" } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      labels = { [ch2Loop.address] = "mainloop" } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
    { hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      labels = { [ch4Loop.address] = "mainloop" } },
  })

  self:tick("Elm's Lab music", 1, 1)
  return song
end
```

- [ ] **Step 4: Wire it into `results.audio` and the `mapSongs` table**

In `RomExtractorGen2:run()`, find the line that sets `results.audio` (currently `results.audio = { cries = cries.cries, songs = { Music_TitleScreen = titleSong } }`) and change it to build `mapSongs` from every registered map's `music` field, and add the new song:

```lua
  local titleSong = self:extractTitleMusic()
  local elmsLabSong = self:extractElmsLabMusic()
  local mapSongs = {}
  for mapId, expected in pairs(self.manifest.maps) do
    if expected.music then mapSongs[mapId] = expected.music end
  end
  results.audio = {
    cries = cries.cries,
    songs = {
      Music_TitleScreen = titleSong,
      Music_ElmsLab = elmsLabSong,
    },
    mapSongs = mapSongs,
  }
```

(This loop is written once, here, and every later task in this plan only adds one more `songs.Music_X = self:extractXMusic()` line — the `mapSongs` loop itself never changes again, since it already reads every map's `music` field from the manifest regardless of whether that song exists yet.)

- [ ] **Step 5: Write the test**

Create `tests/engine/gen2_map_songs.lua`:

```lua
-- Pins Milestone 2's mapSongs wiring end-to-end: every registered Crystal
-- map resolves to a song label via results.audio.mapSongs, and every
-- label this task has actually extracted resolves to a real ChipAsm song
-- def (not just a string). Extended in each subsequent Milestone 2 task
-- as more songs land -- see docs/superpowers/plans/
-- 2026-08-06-gen2-crystal-milestone2-music.md.
--   luajit tests/engine/gen2_map_songs.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- Real, ROM-verified per docs/superpowers/plans/
-- 2026-08-06-gen2-crystal-milestone2-music.md's Research Finding 1 table.
local EXPECTED_MAP_SONGS = {
  NEW_BARK_TOWN = "Music_NewBarkTown",
  PLAYERS_HOUSE_1F = "Music_NewBarkTown",
  PLAYERS_HOUSE_2F = "Music_NewBarkTown",
  PLAYERS_NEIGHBORS_HOUSE = "Music_NewBarkTown",
  ELMS_HOUSE = "Music_NewBarkTown",
  ELMS_LAB = "Music_ElmsLab",
  ROUTE_29 = "Music_Route29",
  ROUTE_29_ROUTE_46_GATE = "Music_Route29",
  CHERRYGROVE_CITY = "Music_CherrygroveCity",
  ROUTE_30 = "Music_Route30",
  MR_POKEMONS_HOUSE = "Music_CherrygroveCity",
}

-- This test cannot import a real ROM (no data/generated/ in this
-- checkout, gitignored /roms/), so it checks the manifest's own "music"
-- field directly -- the same source RomExtractorGen2.lua's mapSongs loop
-- reads from at runtime -- rather than a live Data:load().
local Json = require("src.link.Json")
local f = io.open("tools/rom_manifest_crystal.json", "r")
local manifest = Json.decode(f:read("*a"))
f:close()

for mapId, expectedSong in pairs(EXPECTED_MAP_SONGS) do
  local map = manifest.maps[mapId]
  check(map ~= nil, ("manifest has a %s entry"):format(mapId))
  eq(map.music, expectedSong,
    ("%s's manifest music field is %s"):format(mapId, expectedSong))
end

T.finish("Gen2 mapSongs manifest wiring")
```

- [ ] **Step 6: Run the test, then the full suite, then commit**

```bash
luajit tests/engine/gen2_map_songs.lua
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add tools/make_rom_manifest_crystal.py tools/rom_manifest_crystal.json src/import/RomExtractorGen2.lua tests/engine/gen2_map_songs.lua
git commit -m "feat: extract Music_ElmsLab, wire Crystal's mapSongs table

results.audio.mapSongs did not exist for Crystal at all, so
Music.playMap silently no-op'd on every map entry, leaving the title
theme stuck. Every registered map's manifest entry now carries its real
MUSIC_* song label (11 maps, 5 distinct songs -- see the plan's
Research Finding 1); RomExtractorGen2:run() builds mapSongs from it
once, reused by every later song this milestone adds. Music.play's
existing graceful no-op on an undefined song makes the other 4 maps'
music fields safe placeholders until their own extraction task lands.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: Extract Music_CherrygroveCity

**Files:**
- Modify: `src/import/RomExtractorGen2.lua` (`extractCherrygroveCityMusic`, one line in `run()`)
- Modify: `tests/engine/gen2_map_songs.lua` (extend, per this task's own new coverage)

**Interfaces:**
- Consumes: `CrystalMusicTranscoder.buildSong` (Task 1); `run()`'s existing `mapSongs` loop (Task 2, unchanged).
- Produces: `results.audio.songs.Music_CherrygroveCity`, which `CHERRYGROVE_CITY` and `MR_POKEMONS_HOUSE`'s already-wired `mapSongs` entries (Task 2) now resolve to a real song.

- [ ] **Step 1: Write `extractCherrygroveCityMusic`**

Same shape as `extractElmsLabMusic` — all four channels are `.mainloop`-only (per Research Finding 5):

```lua
-- Music_CherrygroveCity: same shape as Music_ElmsLab -- four channels,
-- each with only its own .mainloop, no sub-labels (pokecrystal.sym).
function RomExtractorGen2:extractCherrygroveCityMusic()
  self:beginStage("Cherrygrove City music")

  local ch1 = self:symbol("Music_CherrygroveCity_Ch1")
  local ch1Loop = self:symbol("Music_CherrygroveCity_Ch1.mainloop")
  local ch2 = self:symbol("Music_CherrygroveCity_Ch2")
  local ch2Loop = self:symbol("Music_CherrygroveCity_Ch2.mainloop")
  local ch3 = self:symbol("Music_CherrygroveCity_Ch3")
  local ch3Loop = self:symbol("Music_CherrygroveCity_Ch3.mainloop")
  local ch4 = self:symbol("Music_CherrygroveCity_Ch4")
  local ch4Loop = self:symbol("Music_CherrygroveCity_Ch4.mainloop")

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      labels = { [ch1Loop.address] = "mainloop" } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      labels = { [ch2Loop.address] = "mainloop" } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
    { hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      labels = { [ch4Loop.address] = "mainloop" } },
  })

  self:tick("Cherrygrove City music", 1, 1)
  return song
end
```

- [ ] **Step 2: Wire it into `run()`**

Add one line each in the two places Task 2 established:

```lua
  local cherrygroveCitySong = self:extractCherrygroveCityMusic()
```
(alongside `elmsLabSong`'s own line), and add `Music_CherrygroveCity = cherrygroveCitySong,` to the `songs = { ... }` table Task 2 built.

- [ ] **Step 3: Extend the test**

In `tests/engine/gen2_map_songs.lua`, this task's maps (`CHERRYGROVE_CITY`, `MR_POKEMONS_HOUSE`) already have their `EXPECTED_MAP_SONGS` entries from Task 2 — no test changes needed here beyond confirming the existing assertions still pass (they were already checking the manifest's `music` field, which doesn't change per-task; only `RomExtractorGen2.lua`'s *runtime* song availability changes, which this manifest-only test cannot observe without a real ROM import). Add one runtime-shape check instead, guarded the same way this project's other Gen2 tests handle the "no real ROM in this environment" limitation — skip with a clear message rather than fail:

```lua
-- Runtime song-def shape can only be checked against a real ROM import
-- (no data/generated/ in this checkout) -- if one exists locally, verify
-- Music_CherrygroveCity resolves to a real ChipAsm song def; otherwise
-- skip with a clear reason rather than silently passing nothing.
local ok, Data = pcall(function()
  return require("src.core.Data")
end)
if ok and love.filesystem and love.filesystem.getInfo
   and love.filesystem.getInfo("data/generated/audio.lua") then
  local audio = require("data.generated.audio")
  check(audio.songs.Music_CherrygroveCity ~= nil,
    "Music_CherrygroveCity resolves to a real song def when a ROM is imported")
else
  print("(skipped: no data/generated/audio.lua in this environment -- " ..
    "runtime song-def shape needs a real ROM import to verify)")
end
```

- [ ] **Step 4: Run the test, then the full suite, then commit**

```bash
luajit tests/engine/gen2_map_songs.lua
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add src/import/RomExtractorGen2.lua tests/engine/gen2_map_songs.lua
git commit -m "feat: extract Music_CherrygroveCity

Cherrygrove City and Mr. Pokémon's House (both already wired to this
song label in Task 2's manifest work) now resolve to a real song.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 4: Extract Music_Route29

**Files:**
- Modify: `src/import/RomExtractorGen2.lua` (`extractRoute29Music`, one line in `run()`)

**Interfaces:**
- Consumes: `CrystalMusicTranscoder.buildSong` (Task 1); `run()`'s `mapSongs` loop (Task 2, unchanged).
- Produces: `results.audio.songs.Music_Route29`, which `ROUTE_29` and `ROUTE_29_ROUTE_46_GATE` now resolve to.

- [ ] **Step 1: Write `extractRoute29Music`**

Per Research Finding 5: Ch1/Ch3/Ch4 are `.mainloop`-only; Ch2 has one extra `.sub1`:

```lua
-- Music_Route29: Ch1/Ch3/Ch4 are .mainloop-only; Ch2 has one extra
-- .sub1 (pokecrystal.sym) -- a flat, top-level sound_call/sound_loop
-- target, not nested inside another subroutine's own window.
function RomExtractorGen2:extractRoute29Music()
  self:beginStage("Route 29 music")

  local ch1 = self:symbol("Music_Route29_Ch1")
  local ch1Loop = self:symbol("Music_Route29_Ch1.mainloop")
  local ch2 = self:symbol("Music_Route29_Ch2")
  local ch2Loop = self:symbol("Music_Route29_Ch2.mainloop")
  local ch2Sub1 = self:symbol("Music_Route29_Ch2.sub1")
  local ch3 = self:symbol("Music_Route29_Ch3")
  local ch3Loop = self:symbol("Music_Route29_Ch3.mainloop")
  local ch4 = self:symbol("Music_Route29_Ch4")
  local ch4Loop = self:symbol("Music_Route29_Ch4.mainloop")

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      labels = { [ch1Loop.address] = "mainloop" } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch2Sub1.address,
                 bytes = self.rom:bytes(ch2Sub1.bank, ch2Sub1.address, 60) },
      },
      labels = { [ch2Loop.address] = "mainloop", [ch2Sub1.address] = "sub1" } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
    { hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      labels = { [ch4Loop.address] = "mainloop" } },
  })

  self:tick("Route 29 music", 1, 1)
  return song
end
```

- [ ] **Step 2: Wire it into `run()`**

Same pattern as Task 3 Step 2: add `local route29Song = self:extractRoute29Music()` and `Music_Route29 = route29Song,`.

- [ ] **Step 3: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add src/import/RomExtractorGen2.lua
git commit -m "feat: extract Music_Route29

Route 29 and its Route 46 gate (both already wired to this song label
in Task 2's manifest work) now resolve to a real song.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5: Extract Music_NewBarkTown

**Files:**
- Modify: `src/import/RomExtractorGen2.lua` (`extractNewBarkTownMusic`, one line in `run()`)

**Interfaces:**
- Consumes: `CrystalMusicTranscoder.buildSong` (Task 1); `run()`'s `mapSongs` loop (Task 2, unchanged).
- Produces: `results.audio.songs.Music_NewBarkTown`, which 5 maps (`NEW_BARK_TOWN`, `PLAYERS_HOUSE_1F`, `PLAYERS_HOUSE_2F`, `PLAYERS_NEIGHBORS_HOUSE`, `ELMS_HOUSE`) resolve to — the most-used song in this milestone.

- [ ] **Step 1: Write `extractNewBarkTownMusic`**

Per Research Finding 5, this song is unusual in two ways: Ch1 and Ch2 each have two subroutines (`.sub1`, `.sub2`), and **this song has no Channel 4 at all** — confirmed by the total absence of a `Music_NewBarkTown_Ch4` symbol in `pokecrystal.sym` (not an extraction omission; the real ROM song genuinely only uses 3 of the 4 hardware channels). `CrystalMusicTranscoder.buildSong` takes an array of channel specs with no fixed length requirement — passing 3 channels instead of 4 is already supported without any code change (confirm this by reading `buildSong`'s own `for index, channel in ipairs(channels) do` loop, which has no arity check).

```lua
-- Music_NewBarkTown: Ch1 and Ch2 each have two extra subroutines
-- (.sub1, .sub2); Ch3 is .mainloop-only. This song has NO Channel 4 --
-- confirmed by the absence of Music_NewBarkTown_Ch4 in pokecrystal.sym,
-- not an omission (buildSong accepts any number of channels).
function RomExtractorGen2:extractNewBarkTownMusic()
  self:beginStage("New Bark Town music")

  local ch1 = self:symbol("Music_NewBarkTown_Ch1")
  local ch1Loop = self:symbol("Music_NewBarkTown_Ch1.mainloop")
  local ch1Sub1 = self:symbol("Music_NewBarkTown_Ch1.sub1")
  local ch1Sub2 = self:symbol("Music_NewBarkTown_Ch1.sub2")
  local ch2 = self:symbol("Music_NewBarkTown_Ch2")
  local ch2Loop = self:symbol("Music_NewBarkTown_Ch2.mainloop")
  local ch2Sub1 = self:symbol("Music_NewBarkTown_Ch2.sub1")
  local ch2Sub2 = self:symbol("Music_NewBarkTown_Ch2.sub2")
  local ch3 = self:symbol("Music_NewBarkTown_Ch3")
  local ch3Loop = self:symbol("Music_NewBarkTown_Ch3.mainloop")

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch1Sub1.address,
                 bytes = self.rom:bytes(ch1Sub1.bank, ch1Sub1.address, 60) },
        sub2 = { baseAddress = ch1Sub2.address,
                 bytes = self.rom:bytes(ch1Sub2.bank, ch1Sub2.address, 60) },
      },
      labels = {
        [ch1Loop.address] = "mainloop",
        [ch1Sub1.address] = "sub1", [ch1Sub2.address] = "sub2",
      } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch2Sub1.address,
                 bytes = self.rom:bytes(ch2Sub1.bank, ch2Sub1.address, 60) },
        sub2 = { baseAddress = ch2Sub2.address,
                 bytes = self.rom:bytes(ch2Sub2.bank, ch2Sub2.address, 60) },
      },
      labels = {
        [ch2Loop.address] = "mainloop",
        [ch2Sub1.address] = "sub1", [ch2Sub2.address] = "sub2",
      } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
  })

  self:tick("New Bark Town music", 1, 1)
  return song
end
```

- [ ] **Step 2: Wire it into `run()`**

Same pattern: `local newBarkTownSong = self:extractNewBarkTownMusic()` and `Music_NewBarkTown = newBarkTownSong,`.

- [ ] **Step 3: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add src/import/RomExtractorGen2.lua
git commit -m "feat: extract Music_NewBarkTown

New Bark Town and its 4 indoor maps (all already wired to this song
label in Task 2's manifest work) now resolve to a real song. This song
has no Channel 4 -- confirmed against the real ROM, not an extraction
gap -- so its song spec only lists 3 channels.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6: Extract Music_Route30

**Files:**
- Modify: `src/import/RomExtractorGen2.lua` (`extractRoute30Music`, one line in `run()`)

**Interfaces:**
- Consumes: `CrystalMusicTranscoder.buildSong` (Task 1); `run()`'s `mapSongs` loop (Task 2, unchanged).
- Produces: `results.audio.songs.Music_Route30`, which `ROUTE_30` resolves to — the last of this milestone's 5 songs, closing it out.

- [ ] **Step 1: Write `extractRoute30Music`**

Per Research Finding 5, the most subroutine-heavy of the 5: Ch1/Ch2/Ch3 are `.mainloop`-only, but Ch4 has **five** subroutines (`.sub1` through `.sub5`):

```lua
-- Music_Route30: Ch1/Ch2/Ch3 are .mainloop-only; Ch4 has five
-- subroutines (.sub1-.sub5, pokecrystal.sym) -- the most of any of this
-- milestone's 5 songs, still all flat top-level sound_call/sound_loop
-- targets (no nesting).
function RomExtractorGen2:extractRoute30Music()
  self:beginStage("Route 30 music")

  local ch1 = self:symbol("Music_Route30_Ch1")
  local ch1Loop = self:symbol("Music_Route30_Ch1.mainloop")
  local ch2 = self:symbol("Music_Route30_Ch2")
  local ch2Loop = self:symbol("Music_Route30_Ch2.mainloop")
  local ch3 = self:symbol("Music_Route30_Ch3")
  local ch3Loop = self:symbol("Music_Route30_Ch3.mainloop")
  local ch4 = self:symbol("Music_Route30_Ch4")
  local ch4Loop = self:symbol("Music_Route30_Ch4.mainloop")
  local ch4Sub1 = self:symbol("Music_Route30_Ch4.sub1")
  local ch4Sub2 = self:symbol("Music_Route30_Ch4.sub2")
  local ch4Sub3 = self:symbol("Music_Route30_Ch4.sub3")
  local ch4Sub4 = self:symbol("Music_Route30_Ch4.sub4")
  local ch4Sub5 = self:symbol("Music_Route30_Ch4.sub5")
  local ch4Labels = {
    [ch4Loop.address] = "mainloop",
    [ch4Sub1.address] = "sub1", [ch4Sub2.address] = "sub2",
    [ch4Sub3.address] = "sub3", [ch4Sub4.address] = "sub4",
    [ch4Sub5.address] = "sub5",
  }

  local song = CrystalMusicTranscoder.buildSong({
    { hw = 1, baseAddress = ch1.address,
      bytes = self.rom:bytes(ch1.bank, ch1.address, 300),
      labels = { [ch1Loop.address] = "mainloop" } },
    { hw = 2, baseAddress = ch2.address,
      bytes = self.rom:bytes(ch2.bank, ch2.address, 300),
      labels = { [ch2Loop.address] = "mainloop" } },
    { hw = 3, baseAddress = ch3.address,
      bytes = self.rom:bytes(ch3.bank, ch3.address, 300),
      labels = { [ch3Loop.address] = "mainloop" } },
    { hw = 4, baseAddress = ch4.address,
      bytes = self.rom:bytes(ch4.bank, ch4.address, 300),
      subroutines = {
        sub1 = { baseAddress = ch4Sub1.address,
                 bytes = self.rom:bytes(ch4Sub1.bank, ch4Sub1.address, 30) },
        sub2 = { baseAddress = ch4Sub2.address,
                 bytes = self.rom:bytes(ch4Sub2.bank, ch4Sub2.address, 30) },
        sub3 = { baseAddress = ch4Sub3.address,
                 bytes = self.rom:bytes(ch4Sub3.bank, ch4Sub3.address, 30) },
        sub4 = { baseAddress = ch4Sub4.address,
                 bytes = self.rom:bytes(ch4Sub4.bank, ch4Sub4.address, 30) },
        sub5 = { baseAddress = ch4Sub5.address,
                 bytes = self.rom:bytes(ch4Sub5.bank, ch4Sub5.address, 30) },
      },
      labels = ch4Labels },
  })

  self:tick("Route 30 music", 1, 1)
  return song
end
```

- [ ] **Step 2: Wire it into `run()`**

Same pattern: `local route30Song = self:extractRoute30Music()` and `Music_Route30 = route30Song,`. This is the last song — after this task, every one of the 11 registered maps' `mapSongs` entry resolves to a real, extracted song.

- [ ] **Step 3: Run the full suite and commit**

```bash
LUA=luajit scripts/test.sh 2>&1 | tail -20
git add src/import/RomExtractorGen2.lua
git commit -m "feat: extract Music_Route30, completing Milestone 2's 5 songs

Route 30 (already wired to this song label in Task 2's manifest work)
now resolves to a real song. Every one of the 11 maps registered by
Milestone 1 now has real Crystal music instead of the stuck title
theme -- closing the gap a live playtest found during Milestone 0/1.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** the roadmap's Milestone 2 note asked for "every map from here on" to stop being silent, scoped to "a small map set (2-3 songs)... before the map count makes the backlog feel unbounded." This plan covers all 11 currently-registered maps with the 5 songs they actually need (corrected up from the note's stale 2-3 estimate, with the exact count re-verified against `maps.asm` directly rather than assumed). The note's own open question — "does each song need its own hand-verified extraction, or can it generalize" — is resolved by Research Finding 5 (per-song hardcoded, matching `extractTitleMusic`'s established pattern; sub-label shapes genuinely differ per song).

**Placeholder scan:** every task has real symbol names (verified against `pokecrystal.sym`), real byte-packing math (verified against `ChipAsm.lua`'s own dispatch and a real ROM macro line), and real commit messages naming what closes. No task says "verify during implementation" for something this plan could pin down directly — the one thing genuinely left to the implementer (exact byte-window sizes beyond the "generous, decodeChannel stops at ret regardless" convention `extractTitleMusic` already established) is a deliberate, documented, self-verifying choice: too small a window makes `decodeChannel` raise its own `"ran off the end of the byte window"` error immediately, so an implementer would catch and fix it during Step 4's test run, not ship it silently wrong.

**Type consistency:** `CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels)`'s signature is unchanged across every task (Task 1 only changes internal branching, not the interface); every `extractXMusic` function returns exactly what `CrystalMusicTranscoder.buildSong` produces (matching `extractTitleMusic`'s own return shape) and is folded into `results.audio.songs` under its real `Music_X` label, matching `Music.songDef`'s lookup (`data.audio.songs[song]`) and `Music.playMap`'s `data.audio.mapSongs[mapId]` lookup exactly — both already-existing, unmodified consumer functions in `src/core/Music.lua`.
