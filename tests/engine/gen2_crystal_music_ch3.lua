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
