-- Wooper's three real Cry_Wooper_Ch5/_Ch6/_Ch8 channel byte streams
-- (docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md's
-- "Research already done" section has the full verified decode this
-- fixture data comes from) fed through CrystalCryTranscoder, proving both
-- (a) the decode produces the exact expected ChipAsm events, and (b) the
-- resulting chip program renders audible (non-inaudible-floor, non-silent)
-- samples through the real, unmodified ChipSynth.lua -- no ROM needed.
-- ROM-free: ChipAsm blobs and hand-supplied byte fixtures, no
-- data/generated/.
--   luajit tests/engine/gen2_cry_transcoder.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local eq = T.eq

love = require("tests.love_stub")

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

-- The sample-count check above only proves the buffer is long enough, not
-- that it actually carries signal -- a fully silent buffer of the same
-- length would also pass it. Confirm real amplitude is present too (a
-- known-good render of this exact fixture measured peak 0.567, RMS 0.250,
-- so 0.1 is a safe, meaningful threshold that would catch a
-- "renders but silent" regression). See
-- tests/engine/effect_stereo_bug626.lua for the same getSample(index,
-- channel) iteration pattern.
if rendered then
  local loud = false
  for index = 0, rendered:getSampleCount() - 1 do
    for channel = 1, rendered:getChannelCount() do
      if math.abs(rendered:getSample(index, channel)) > 0.1 then
        loud = true
        break
      end
    end
    if loud then break end
  end
  check(loud, "Cry transcoder: rendered buffer carries real signal, not silence "
    .. "(some sample exceeds 0.1 in absolute value)")
end

T.finish("Gen2 cry transcoder")
