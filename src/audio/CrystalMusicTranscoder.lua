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
--
-- Two opcodes below (volume_cmd $E5, octave_cmd $D0-$D7) are NOT in the
-- task-3-brief.md code this module otherwise transcribes verbatim -- the
-- brief's own dispatch table omits both, even though its docstring lists
-- "volume... octave" as in-scope, the plan's "Research already done"
-- section byte-verifies both against real ROM data (`e5 77` = volume_cmd,
-- `d5`/`d6`/`d7` = octave_cmd), and the brief's own fixture bytes use
-- both. Running the brief's code as literally given errors out on the
-- fixture's first `$E5` byte. The two branches added here were verified
-- empirically (not guessed): decoding the fixture's real ROM bytes with
-- them produces every other field the fixture's own assertions check
-- (tempo/duty/vibrato/pan/notetype x3/octave x2/rest/pitch, ~20 fields)
-- exactly -- see task-3-report.md for the full comparison. That match
-- across so many independent fields is what justifies adding these two
-- branches rather than treating the crash as a sign to drop the bytes.
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
    elseif cmd == 0xE5 then -- volume_cmd: same dn(volume, fade) packing and
      -- the same "no direct ChipAsm event, re-emit as notetype carrying
      -- the last-known speed" treatment as volume_envelope_cmd above (this
      -- opcode is missing from task-3-brief.md's own dispatch table --
      -- see this file's header comment for why it is added here)
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
    elseif cmd >= 0xD0 and cmd <= 0xD7 then -- octave_cmd: octave_cmd = $D0 +
      -- 8-octave (plan's "Research already done" section, byte-verified:
      -- octave 3 -> d5, octave 2 -> d6, octave 1 -> d7). Missing from
      -- task-3-brief.md's own dispatch table -- see this file's header
      -- comment for why it is added here.
      events[#events + 1] = { octave = 8 - (cmd - 0xD0) }
      i = i + 1
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
