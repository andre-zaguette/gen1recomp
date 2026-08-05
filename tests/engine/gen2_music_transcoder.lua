-- Music_TitleScreen_Ch1's real opening bytes (main body) plus its full
-- .sub1 (docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md's
-- "Research already done" section has the full verified decode this
-- fixture comes from), fed through CrystalMusicTranscoder, proving the
-- decode produces the exact expected ChipAsm events -- including the
-- pitch-nibble-minus-one correction, the note_type/volume_envelope/
-- volume_cmd/octave_cmd handling, and sound_call/sound_loop label
-- resolution -- with no ROM needed.
--
-- Sibling to tests/engine/gen2_cry_transcoder.lua (same fixture shape,
-- own process via tests/run_engine.lua's tier_runner, T.check/T.eq/
-- T.finish). task-3-brief.md's Step 2 said to append this fixture inline
-- to tests/run_tests.lua after a "-- Gen2 cry transcoder" block -- no
-- such block exists there; the cry-transcoder fixture actually lives
-- here, auto-discovered by tier_runner, which is the convention this
-- file follows instead. See task-3-report.md for the full account of
-- this and the other brief/reality mismatches this fixture's assertion
-- values had to be corrected for (all empirically verified against the
-- real byte arrays below via a throwaway probe script, not guessed):
--   1. The byte arrays are exactly as task-3-brief.md gave them (real,
--      ROM-verified bytes, unmodified) and are never edited to make an
--      assertion pass -- only the derived expected event count/order is.
--   2. In .sub1, the label sub1loop1 sits at the exact same address as
--      the very next command (a rest) -- decodeChannel checks for a
--      label at the current address *before* reading that address's
--      command byte, so the label event is emitted before that rest
--      event, not after (the brief's assertion order had this reversed).
--   3. `volume_cmd` ($E5, "volume 7, 7") writes the GLOBAL NR50 master
--      volume, not the per-channel envelope volume_envelope_cmd ($DC)
--      writes -- despite sharing the same dn(a, b) byte packing, they
--      are different registers with different scope. A code-review pass
--      caught that this file's decodeChannel originally (wrongly) re-
--      emitted volume_cmd as a notetype event, treating it as equivalent
--      to volume_envelope_cmd; src/audio/CrystalMusicTranscoder.lua now
--      drops it instead (no ChipAsm master-volume event exists, and this
--      song's own `7, 7` is already max-on-both-sides, ChipSynth's
--      default anyway, so dropping it is lossless here). That shifts
--      Ch1's event count/indices down by one from the count this file
--      originally asserted (17 -> 16): 17 real Crystal commands in the
--      30-byte prefix, minus 2 dropped (pitch_offset, volume_cmd), plus
--      1 for the terminal sound_ret = 16 events, asserted below.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local eq = T.eq

love = require("tests.love_stub")

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
eq(#events, 16, "Music transcoder: 17 real Crystal commands in the 30-byte prefix, minus "
  .. "2 dropped (pitch_offset, volume_cmd), plus 1 for the terminal sound_ret -> 16 events "
  .. "(tempo/duty/vibrato/pan/notetype x3/octave x2/rest x2/note x4/ret)")
eq(events[1].tempo, 134, "Music transcoder: tempo decodes to 134")
-- volume_cmd ("volume 7, 7", between tempo and duty_cycle in the byte
-- stream) is dropped -- see this file's header comment -- so duty_cycle
-- is the very next event after tempo, not a notetype standing in for it.
check(events[2].duty == 3, "Music transcoder: duty_cycle decodes to 3 "
  .. "(volume_cmd right before it was dropped, no event in between)")
check(events[3].vibrato and events[3].vibrato.delay == 16
  and events[3].vibrato.depth == 1 and events[3].vibrato.rate == 2,
  "Music transcoder: vibrato 16,1,2 decodes correctly")
eq(events[4].pan, 0xF0, "Music transcoder: stereo_panning packs to 0xF0")
check(events[5].notetype and events[5].notetype.speed == 12
  and events[5].notetype.volume == 10 and events[5].notetype.fade == 7,
  "Music transcoder: note_type 12,10,7 decodes correctly")
check(events[6].notetype and events[6].notetype.speed == 12
  and events[6].notetype.volume == 10 and events[6].notetype.fade == 0,
  "Music transcoder: volume_envelope 10,0 reuses the last note_type speed (12)")
eq(events[7].octave, 3, "Music transcoder: octave 3")
eq(events[8].rest, 4, "Music transcoder: rest 4")
check(events[9].notetype.volume == 10 and events[9].notetype.fade == 7,
  "Music transcoder: volume_envelope 10,7")
eq(events[10].octave, 2, "Music transcoder: octave 2")
eq(events[11].pitch, 7, "Music transcoder: note G_ decodes to pitch 7 (G, 0-indexed)")
eq(events[11].len, 1, "Music transcoder: note G_,1 length")
eq(events[12].rest, 2, "Music transcoder: rest 2")
eq(events[13].pitch, 9, "Music transcoder: note A_ decodes to pitch 9")
eq(events[13].len, 1, "Music transcoder: note A_,1 length")
eq(events[14].pitch, 11, "Music transcoder: note B_ decodes to pitch 11")
eq(events[14].len, 8, "Music transcoder: note B_,8 length")
eq(events[15].pitch, 7, "Music transcoder: note G_ decodes to pitch 7 again")
eq(events[15].len, 4, "Music transcoder: note G_,4 length")
eq(events[16].ret, true, "Music transcoder: ends with sound_ret")

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
-- .sub1loop1's address ($7971) is the *same* address as the rest command
-- that immediately follows it in the byte stream, and decodeChannel checks
-- for a label at the current address before reading that address's
-- command byte -- so the label event comes first, then the rest.
check(subEvents[3].label == "sub1loop1",
  "Music transcoder: sub1loop1 label emitted at address $7971, before the "
  .. "co-located rest command")
eq(subEvents[4].rest, 1, "Music transcoder: sub1 rest 1 (right after the sub1loop1 label)")
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

T.finish("Gen2 music transcoder")
