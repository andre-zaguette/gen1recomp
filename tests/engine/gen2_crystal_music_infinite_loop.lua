-- Regression guard for a real-ROM-import crash found while playtesting
-- Milestone 2 (docs/superpowers/plans/2026-08-06-gen2-crystal-milestone2-music.md):
-- `CrystalMusicTranscoder.lua:115: bad argument #1 to 'rshift' (number
-- expected, got nil)`, deep inside decodeChannel while extracting
-- Music_ElmsLab.
--
-- Root cause: sound_loop_cmd ($FD) with count 0 is Crystal's own "loop
-- forever" sentinel -- the real ROM bytecode has NOTHING after it (the
-- next bytes belong to the next song entirely). decodeChannel kept
-- scanning past it looking for a $FF terminator that was never coming,
-- eventually reading garbage/next-song bytes until an opcode's own
-- multi-byte operand ran past the extraction's byte window. Confirmed
-- against the real ROM (Music_ElmsLab's own Ch1-Ch4, all four of which
-- end this way, none with a trailing $FF) that all four channels decode
-- to their real, intended byte span once a zero-count loop stops the
-- scan -- see the plan's Task 2 fix-round history for the byte-level
-- trace. Music_TitleScreen's own channels happen not to end this way
-- (verified: none of its sound_loop calls use count 0), which is why
-- this went uncaught until a second, different song was extracted.
--
-- ChipAsm.lua's own assembler already anticipated this exact shape
-- (`endsItself`'s `last.loop.count == 0` check, ChipAsm.lua:265-272,
-- "a stream that cannot fall off its end needs no terminator") -- this
-- test only pins the DECODER side, which previously did not honor it.
--   luajit tests/engine/gen2_crystal_music_infinite_loop.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Transcoder = require("src.audio.CrystalMusicTranscoder")

-- A minimal channel: one note, then an infinite sound_loop back to a
-- label at the note's own address -- followed by bytes that belong to a
-- DIFFERENT, unrelated song (as real ROM data would have). If decodeChannel
-- keeps scanning past the zero-count loop, it will misdecode these bytes
-- and either error or return a wrong event count instead of stopping
-- cleanly right after the loop event.
local noteAddr = 0x1000
local labels = { [noteAddr] = "mainloop" }
local bytes = {
  0x1F,             -- note: pitch=1, len=16 (dn(1,15))
  0xFD, 0x00, 0x00, 0x10, -- sound_loop 0, mainloop ($1000 = 0x00,0x10 little-endian)
  0xFF, 0xFF, 0xFF, -- bytes that would belong to a different song's data;
                     -- must NOT be reached
}

local events = Transcoder.decodeChannel(bytes, 1, noteAddr, labels)

eq(#events, 3, "exactly 3 events: label, note, loop -- nothing past the infinite loop")
check(events[1].label == "mainloop", "first event is the mainloop label marker")
check(events[2].pitch ~= nil, "second event is the note")
check(events[3].loop ~= nil, "third (last) event is the loop")
eq(events[3].loop.count, 0, "loop count is 0 (infinite)")
eq(events[3].loop.to, "mainloop", "loop target resolves to the mainloop label")

-- A finite-count loop (count > 0) really does fall through to more real
-- bytes afterward in Crystal's own bytecode -- must NOT stop early.
local finiteBytes = {
  0xFD, 0x03, 0x00, 0x10, -- sound_loop 3, mainloop (finite, falls through)
  0xFF,                    -- the real terminator, reached only if scanning continues
}
local finiteEvents = Transcoder.decodeChannel(finiteBytes, 1, noteAddr, labels)
eq(#finiteEvents, 3, "finite loop: label, loop, AND the ret after it -- scanning continues")
eq(finiteEvents[2].loop.count, 3, "finite loop count preserved")
check(finiteEvents[3].ret == true, "finite loop falls through to the real ret byte")

T.finish("Gen2 CrystalMusicTranscoder infinite sound_loop terminates decode")
