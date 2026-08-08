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
