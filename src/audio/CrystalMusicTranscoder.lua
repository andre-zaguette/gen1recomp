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
-- 0 on every channel) this is built from. Channel 3 (wave) support was
-- added for Milestone 2 (docs/superpowers/plans/2026-08-06-gen2-crystal-
-- milestone2-music.md, Task 1) -- all of the 5 songs required then use
-- Channel 3. Raw SFX decoding (square_note/noise_note/pitch_sweep) was
-- added for the SFX plan (docs/superpowers/plans/2026-08-08-gen2-crystal-sfx.md).
--
-- Two opcodes below (volume_cmd $E5, octave_cmd $D0-$D7) are NOT in the
-- task-3-brief.md code this module otherwise transcribes verbatim -- the
-- brief's own dispatch table omits both, even though its docstring lists
-- "volume... octave" as in-scope, the plan's "Research already done"
-- section byte-verifies both against real ROM data (`e5 77` = volume_cmd,
-- `d5`/`d6`/`d7` = octave_cmd), and the brief's own fixture bytes use
-- both. Running the brief's code as literally given errors out on the
-- fixture's first `$E5` byte. octave_cmd was verified empirically (not
-- guessed): decoding the fixture's real ROM bytes with it produces every
-- other field the fixture's own assertions check (tempo/duty/vibrato/
-- pan/notetype/octave/rest/pitch fields) exactly -- see task-3-report.md
-- for the full comparison. volume_cmd is handled below by dropping it,
-- not by re-emitting an event -- see its own branch's comment for why
-- (an earlier version of this file wrongly treated it as equivalent to
-- volume_envelope_cmd; code review caught that they are different
-- registers with different scope that only coincidentally share a byte
-- packing).
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
-- bytes[1]). `hw` is 1/2 (pulse), 3 (wave), or 4 (noise) -- all three are
-- now supported as of Milestone 2 (docs/superpowers/plans/
-- 2026-08-06-gen2-crystal-milestone2-music.md, Task 1), when the first 5
-- songs all required Channel 3. `labels` is an address -> name map: every
-- time the byte currently being read sits at an address present in
-- `labels`, a {label = name} marker is emitted first (covers both
-- self-referential loop points inside this same window and, when
-- decoding a subroutine, the subroutine's own start). Every sound_call/
-- sound_loop target address is looked up in the same map; a missing
-- entry is a hard error rather than a guess, matching
-- CrystalCryTranscoder's "raise on anything unverified" stance. `isSfx`
-- (optional, defaults to false) is the channel's STARTING note-decoding
-- mode, not a fixed whole-channel flag: when true, bytes below 0xD0
-- decode as raw squareNote/noiseNote records (depending on hw); when
-- false or omitted, they use the normal packed-note music scheme. A
-- toggle_sfx ($DF) byte flips that mode mid-stream, exactly as real
-- hardware does (see the $DF branch below) -- so an SFX channel that
-- opens with toggle_sfx (Sfx_KeyItem_Ch5/Ch6/Ch7) decodes as normal
-- music for its whole body. Stops at sound_ret ($FF, Crystal's own
-- value -- shared with
-- ChipAsm's dialect, unlike sound_call/sound_loop); the returned list's
-- last entry is always {ret = true}.
function CrystalMusicTranscoder.decodeChannel(bytes, hw, baseAddress, labels, isSfx)
  labels = labels or {}
  local events = {}
  local i = 1
  local lastSpeed = 12 -- audio/music/titlescreen.asm's own fresh-channel default
  -- Mutable per-channel note-decoding mode, seeded from `isSfx` and
  -- flipped by every toggle_sfx ($DF) byte -- mirrors ChipSynth.lua's own
  -- Channel.executeMusic (ChipSynth.lua:210 `executeMusic = not
  -- isSfxChannel`, toggled at ChipSynth.lua:399), which is the same
  -- state real hardware keeps in CHANNEL_FLAGS1's SOUND_SFX bit.
  local rawMode = isSfx and true or false

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
    elseif cmd == 0xE5 then -- volume_cmd: writes wVolume, the GLOBAL NR50
      -- hardware master left/right volume (0-7 per side) -- NOT the
      -- per-channel envelope volume/fade volume_envelope_cmd ($DC, above)
      -- writes. The two opcodes only coincidentally share the same
      -- dn(a, b) byte packing; they are different registers with
      -- different scope, so re-emitting this as a notetype (as an
      -- earlier version of this file did) was a false equivalence.
      -- ChipAsm's event vocabulary has no master-volume event at all (see
      -- src/audio/ChipAsm.lua's KEYS list), and this song's own usage
      -- (`volume 7, 7`) is already max-on-both-sides -- ChipSynth's
      -- default state anyway -- so dropping it is lossless here, same
      -- "no ChipAsm equivalent, drop the structural-only bytes" treatment
      -- as toggle_noise_cmd/pitch_offset_cmd below. This opcode is
      -- missing from task-3-brief.md's own dispatch table -- see this
      -- file's header comment for why it is handled here.
      i = i + 2
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
    elseif cmd == 0xD9 then -- transpose_cmd: persistently offsets future
      -- note pitches by N octaves + M semitones. ChipAsm/ChipSynth have no
      -- native Crystal opcode here, so this transcoder maps it to the
      -- project's own synthetic `transpose` event, encoded in an otherwise
      -- unused command byte on the assembled side.
      local packed = bytes[i + 1]
      events[#events + 1] = { transpose = {
        octaves = bit.rshift(packed, 4),
        pitches = bit.band(packed, 0x0F),
      } }
      i = i + 2
    elseif cmd >= 0xD0 and cmd <= 0xD7 then -- octave_cmd: octave_cmd = $D0 +
      -- 8-octave (plan's "Research already done" section, byte-verified:
      -- octave 3 -> d5, octave 2 -> d6, octave 1 -> d7). Missing from
      -- task-3-brief.md's own dispatch table -- see this file's header
      -- comment for why it is added here.
      events[#events + 1] = { octave = 8 - (cmd - 0xD0) }
      i = i + 1
    elseif cmd == 0xDD then -- pitch_sweep_cmd: same high-nibble-pace,
      -- low-nibble-signed-shift packing as ChipAsm.lua's own E.pitchSweep
      -- (verified against Sfx_Bump_Ch5's real bytes in the plan's
      -- "Research already done" section).
      local packed = bytes[i + 1]
      events[#events + 1] = { pitchSweep = {
        -- pace masked to 3 bits, matching this project's own native reader
        -- (ChipSynth.lua:454) -- NR10's pace field is bits 4-6 and the byte's
        -- top bit is unused, so real data like Sfx_JumpOverLedge_Ch5's
        -- `pitch_sweep 9, 5` ($95) must decode to pace 1, not an
        -- out-of-range 9 that ChipAsm's E.pitchSweep would reject.
        pace = bit.band(bit.rshift(packed, 4), 7),
        subtract = bit.band(packed, 8) ~= 0,
        shift = bit.band(packed, 7),
      } }
      i = i + 2
    elseif cmd == 0xDE then -- duty_cycle_pattern_cmd
      local packed = bytes[i + 1]
      events[#events + 1] = { dutyPattern = {
        bit.band(bit.rshift(packed, 6), 3),
        bit.band(bit.rshift(packed, 4), 3),
        bit.band(bit.rshift(packed, 2), 3),
        bit.band(packed, 3),
      } }
      i = i + 2
    elseif cmd == 0xDF then -- toggle_sfx_cmd: a REAL mode toggle, not a
      -- no-op. _PlaySFX/PlayStereoSFX (audio/engine.asm:2561, :2614) SET
      -- CHANNEL_FLAGS1's SOUND_SFX bit when an sfx channel starts, and
      -- Music_ToggleSFX (engine.asm:1847-1853) TOGGLES it -- so a leading
      -- toggle_sfx on an sfx channel CLEARS the bit, and ParseMusic's
      -- .readnote branch (engine.asm:1155-1160) then falls through to
      -- normal packed-note parsing for the rest of that channel. That is
      -- exactly what Sfx_KeyItem_Ch5/Ch6/Ch7 rely on: they are fanfares
      -- written in the octave/note_type/note scheme with no square_note/
      -- noise_note anywhere. Flip the decoder's own mode to match, and
      -- emit ChipAsm's executeMusic event so the assembled program carries
      -- the real $F8 byte the native playback engine toggles its own
      -- Channel.executeMusic on (ChipSynth.lua:399) -- emitted only where
      -- a real $DF byte occurs, keeping the output 1:1 with the ROM.
      rawMode = not rawMode
      events[#events + 1] = { executeMusic = true }
      i = i + 1
    elseif cmd == 0xE0 then -- pitch_slide_cmd: Crystal stores a one-byte
      -- slide duration-minus-1 plus a packed target octave/pitch nibble.
      -- This project's own audio engine already has a first-class synthetic
      -- `slide` event (ChipAsm E.slide -> ChipSynth pendingSlide), so decode
      -- straight into that existing representation instead of dropping the
      -- effect. The second byte's high nibble is `8 - octave`, low nibble is
      -- pitch 0-11 exactly like the plain note encoding before the
      -- transcoder's own "-1 because 0 means rest" adjustment.
      local packed = bytes[i + 2]
      events[#events + 1] = { slide = {
        len = bytes[i + 1],
        octave = 8 - bit.rshift(packed, 4),
        pitch = bit.band(packed, 0x0F),
      } }
      i = i + 3
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
    elseif rawMode and cmd < 0xD0 then -- ParseSFXOrCry (audio/engine.asm):
      -- while SOUND_SFX is set EVERY sub-$D0 byte is a raw square_note/
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
      -- count 0 is Crystal's own "loop forever" sentinel: the real ROM
      -- bytecode never falls through past this point (there is nothing
      -- after it but the next song's own data), matching ChipAsm.lua's
      -- own endsItself() check (`last.loop.count == 0` needs no $FF
      -- terminator either). Music_TitleScreen's own channels happen not
      -- to end this way (verified: none of its sound_loop calls use
      -- count 0), which is why this case went uncaught until a real ROM
      -- import against Music_ElmsLab crashed with a nil-argument error
      -- deep in garbage bytes read past the channel's real end -- a
      -- finite-count loop (count > 0) really does fall through to more
      -- real bytes afterward, so only the zero case stops the scan.
      if count == 0 then return events end
      i = i + 4
    elseif cmd == 0xFE then -- sound_call_cmd (Crystal) -> ChipAsm {call=...}
      events[#events + 1] = { call = targetName(bytes[i + 1], bytes[i + 2]) }
      i = i + 3
    elseif cmd == 0xF0 then -- sfx_toggle_noise_cmd: the SFX-side sibling of
      -- toggle_noise_cmd, with the same optional drum-kit byte. ChipSynth
      -- already treats the assembled 0xF0 as a consumed no-op parameter
      -- carrier, so preserve that behavior by skipping the single payload.
      i = i + 2
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
    local labels = {}
    for address, name in pairs(channel.labels or {}) do
      labels[address] = name
    end
    local subroutines
    if channel.subroutines then
      subroutines = {}
      for name, sub in pairs(channel.subroutines) do
        labels[sub.baseAddress] = labels[sub.baseAddress] or name
        subroutines[name] = CrystalMusicTranscoder.decodeChannel(
          sub.bytes, channel.hw, sub.baseAddress, labels)
      end
    end
    specs[index] = {
      hw = channel.hw,
      program = CrystalMusicTranscoder.decodeChannel(
        channel.bytes, channel.hw, channel.baseAddress, labels),
      subroutines = subroutines,
    }
  end
  return ChipAsm.song({ channels = specs })
end

-- Sibling to buildSong: assembles onto Crystal's own SFX channel range
-- (hardware+4, i.e. channels 5-8) via ChipAsm.sfx instead of
-- ChipAsm.song, and STARTS every channel in decodeChannel's raw
-- square_note/noise_note mode -- the same state _PlaySFX gives a real
-- channel (SOUND_SFX set). A channel whose body opens with toggle_sfx
-- flips straight back out of it, matching real hardware.
function CrystalMusicTranscoder.buildSfx(channels)
  local specs = {}
  for index, channel in ipairs(channels) do
    local labels = {}
    for address, name in pairs(channel.labels or {}) do
      labels[address] = name
    end
    local subroutines
    if channel.subroutines then
      subroutines = {}
      for name, sub in pairs(channel.subroutines) do
        labels[sub.baseAddress] = labels[sub.baseAddress] or name
        subroutines[name] = CrystalMusicTranscoder.decodeChannel(
          sub.bytes, channel.hw, sub.baseAddress, labels, true)
      end
    end
    specs[index] = {
      hw = channel.hw,
      program = CrystalMusicTranscoder.decodeChannel(
        channel.bytes, channel.hw, channel.baseAddress, labels, true),
      subroutines = subroutines,
    }
  end
  return ChipAsm.sfx({ channels = specs })
end

return CrystalMusicTranscoder
