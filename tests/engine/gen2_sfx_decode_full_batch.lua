-- Regression guard for the two Critical bugs the SFX plan's original two
-- fixtures (tests/engine/gen2_crystal_sfx_decode.lua, Sfx_Bump_Ch5 and
-- Sfx_EnterDoor_Ch8) both happened to miss -- each of those bodies has a
-- pace that already fits 3 bits and no toggle_sfx at all, so the shipped
-- code passed while breaking the whole Crystal ROM import. These two
-- fixtures are the members of this batch's 14 real channel symbols that
-- actually exercise the two bug classes:
--
--   C1a -- pitch_sweep's pace nibble must be masked to 3 bits (NR10's
--   pace field is bits 4-6; the byte's top bit is unused), exactly as
--   this project's own native reader already does (ChipSynth.lua:454).
--   Unmasked, a real pace of 9 reaches ChipAsm's E.pitchSweep, whose
--   0-7 range check errors out and takes the entire ROM import with it.
--
--   C1b -- toggle_sfx ($DF) is a real mode toggle, not a no-op:
--   _PlaySFX/PlayStereoSFX (audio/engine.asm:2561, :2614) SET
--   CHANNEL_FLAGS1's SOUND_SFX bit when a channel starts and
--   Music_ToggleSFX (engine.asm:1847-1853) TOGGLES it, so a leading
--   toggle_sfx CLEARS it and ParseMusic's .readnote branch
--   (engine.asm:1155-1160) parses the rest of the channel as normal
--   packed-note music. Sfx_KeyItem_Ch5/Ch6/Ch7 are fanfares that depend
--   on precisely this.
--
-- Fixture bytes hand-derived from real ROM data (roms/pokecrystal/
-- audio/sfx.asm + macros/scripts/audio.asm, gitignored, not committed):
--
--   Sfx_JumpOverLedge_Ch5 (hw=1, tone path) -- exercises C1a:
--     duty_cycle 2              -> DB 02
--     pitch_sweep 9, 5          -> DD 95   (pace 9 -- 9 & 7 = 1)
--     square_note 15,15,2,1024  -> 0F F2 00 04
--     pitch_sweep 0, 8          -> DD 08
--     sound_ret                 -> FF
--
--   Sfx_KeyItem_Ch5 (hw=1, fanfare) -- exercises C1b:
--     toggle_sfx                -> DF
--     tempo 120                 -> DA 00 78   (bigdw)
--     volume 7, 7               -> E5 77
--     duty_cycle 2              -> DB 02
--     note_type 6, 11, 1        -> D8 06 B1
--     octave 3                  -> D5          (octave_cmd + 8 - 3)
--     note B_, 4                -> C3          (dn B_=12, 4-1)
--     note B_, 2                -> C1
--     note B_, 2                -> C1
--     note B_, 4                -> C3
--     octave 4                  -> D4
--     note E_, 4                -> 53          (dn E_=5, 4-1)
--     volume_envelope 11, 3     -> DC B3
--     note G#, 16               -> 9F          (dn G#=9, 16-1)
--     sound_ret                 -> FF
--
--   luajit tests/engine/gen2_sfx_decode_full_batch.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Transcoder = require("src.audio.CrystalMusicTranscoder")

-- C1a: pitch_sweep pace masking ---------------------------------------------
local ledgeBytes = { 0xDB, 0x02, 0xDD, 0x95, 0x0F, 0xF2, 0x00, 0x04, 0xDD, 0x08, 0xFF }
local ledgeEvents = Transcoder.decodeChannel(ledgeBytes, 1, 0x5EBC, {}, true)

eq(#ledgeEvents, 5, "5 events: duty, sweep, squareNote, sweep, ret")
eq(ledgeEvents[1].duty, 2, "duty_cycle 2")
eq(ledgeEvents[2].pitchSweep.pace, 1,
  "pitch_sweep 9,5 -> pace masked to 3 bits: 9 & 7 = 1 (NR10's pace is bits 4-6)")
eq(ledgeEvents[2].pitchSweep.subtract, false, "pitch_sweep 9,5 -> positive, subtract=false")
eq(ledgeEvents[2].pitchSweep.shift, 5, "pitch_sweep 9,5 -> shift=5")
eq(ledgeEvents[3].squareNote.len, 16, "square_note 15,... -> length nibble 15, +1 = 16")
eq(ledgeEvents[3].squareNote.volume, 15, "square_note volume")
eq(ledgeEvents[3].squareNote.fade, 2, "square_note fade")
eq(ledgeEvents[3].squareNote.frequency, 1024, "square_note raw little-endian frequency")
eq(ledgeEvents[4].pitchSweep.pace, 0, "pitch_sweep 0,8 -> pace=0")
check(ledgeEvents[5].ret == true, "terminates on sound_ret")

-- ...and the masked pace must survive assembly: ChipAsm's E.pitchSweep
-- range-checks pace against 0-7 and errors otherwise, which is what took
-- down the whole ROM import before this fix.
local ledgeSfx = Transcoder.buildSfx({
  { hw = 1, baseAddress = 0x5EBC, bytes = ledgeBytes },
})
eq(ledgeSfx.chip.channels[1].number, 5, "Sfx_JumpOverLedge_Ch5 assembles onto channel 5")
check(#ledgeSfx.chip.blob > 0, "pace 9 assembles cleanly once masked to 1")

-- C1b: toggle_sfx flips into music decoding ---------------------------------
local keyItemBytes = {
  0xDF,             -- toggle_sfx
  0xDA, 0x00, 0x78, -- tempo 120
  0xE5, 0x77,       -- volume 7, 7
  0xDB, 0x02,       -- duty_cycle 2
  0xD8, 0x06, 0xB1, -- note_type 6, 11, 1
  0xD5,             -- octave 3
  0xC3, 0xC1, 0xC1, 0xC3, -- note B_,4 / B_,2 / B_,2 / B_,4
  0xD4,             -- octave 4
  0x53,             -- note E_, 4
  0xDC, 0xB3,       -- volume_envelope 11, 3
  0x9F,             -- note G#, 16
  0xFF,             -- sound_ret
}
local keyEvents = Transcoder.decodeChannel(keyItemBytes, 1, 0x4B92, {}, true)

-- 14 events: executeMusic, tempo, duty, notetype, octave, 4 notes,
-- octave, note, notetype, note, ret. (volume $E5 is dropped -- it writes
-- the global NR50 master volume, which ChipAsm has no event for.)
eq(#keyEvents, 14, "Sfx_KeyItem_Ch5 decodes to 14 events, not an unsupported-opcode error")
check(keyEvents[1].executeMusic == true, "leading toggle_sfx emits executeMusic ($F8)")
eq(keyEvents[2].tempo, 120, "tempo 120 (big-endian) decodes after the mode flip")
eq(keyEvents[3].duty, 2, "duty_cycle 2")
eq(keyEvents[4].notetype.speed, 6, "note_type 6,11,1 -> speed 6")
eq(keyEvents[4].notetype.volume, 11, "note_type 6,11,1 -> volume 11")
eq(keyEvents[4].notetype.fade, 1, "note_type 6,11,1 -> fade 1")
eq(keyEvents[5].octave, 3, "octave 3")

-- The four B_ notes are the proof the mode really flipped: as raw
-- square_note records these 0xC3/0xC1 bytes would each swallow 3 more
-- bytes and run the decoder straight off the channel's real end.
eq(keyEvents[6].pitch, 11, "note B_,4 -> pitch 11 (B_=12, minus the 1-indexed shift)")
eq(keyEvents[6].len, 4, "note B_,4 -> len 4")
check(keyEvents[6].squareNote == nil, "a note byte after toggle_sfx is NOT a raw squareNote")
eq(keyEvents[7].len, 2, "note B_,2 -> len 2")
eq(keyEvents[8].len, 2, "note B_,2 -> len 2")
eq(keyEvents[9].len, 4, "note B_,4 -> len 4")
eq(keyEvents[10].octave, 4, "octave 4")
eq(keyEvents[11].pitch, 4, "note E_,4 -> pitch 4 (E_=5)")
eq(keyEvents[12].notetype.volume, 11, "volume_envelope 11,3 -> volume 11")
eq(keyEvents[12].notetype.fade, 3, "volume_envelope 11,3 -> fade 3")
eq(keyEvents[12].notetype.speed, 6, "volume_envelope re-emits the last-known speed")
eq(keyEvents[13].pitch, 8, "note G#,16 -> pitch 8 (G#=9)")
eq(keyEvents[13].len, 16, "note G#,16 -> len 16")
check(keyEvents[14].ret == true, "terminates cleanly on its own sound_ret")

local keySfx = Transcoder.buildSfx({
  { hw = 1, baseAddress = 0x4B92, bytes = keyItemBytes },
})
eq(keySfx.chip.channels[1].number, 5, "Sfx_KeyItem_Ch5 assembles onto channel 5")
-- The assembled blob must carry the real $F8 executeMusic byte, since the
-- native playback engine starts an sfx channel with executeMusic = false
-- (ChipSynth.lua:210) and only $F8 flips it (ChipSynth.lua:399) -- without
-- it the fanfare's own notes would play back as raw sfx records.
eq(keySfx.chip.blob:byte(1), 0xF8, "the assembled program's first byte is the real $F8 toggle")

T.finish("Gen2 SFX full-batch decoding (pitch_sweep pace mask, toggle_sfx mode flip)")
