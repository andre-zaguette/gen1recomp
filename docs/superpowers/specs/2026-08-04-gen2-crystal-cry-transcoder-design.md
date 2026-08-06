# Gen2 (Crystal) Cry Bytecode Transcoder

Status: approved for planning
Date: 2026-08-04

## Context

The Gen2 (Crystal) new-game intro plan's Task 5 (extract Wooper's cry for
the Oak-speech demo beat) got as far as fully correct, real-ROM-verified
manifest and import plumbing — the right bank dumped, the right two-level
species→cry-index→bank:address indirection resolved, the right
`waveBanks`/`bankOrder` shape `src/core/ChipSynth.lua` already expects —
before discovering that the plan's own core premise was false: **Pokemon
Crystal's sound-engine bytecode uses a materially different, reorganized
opcode table than Pokemon Red/Blue's**, not just different ROM addresses.
Confirmed byte-for-byte against pokecrystal's own `macros/scripts/audio.asm`
and the real ROM, e.g.:

| meaning | Gen1 (`ChipSynth.lua`, from pokered) | Crystal (pokecrystal, real ROM) |
| --- | --- | --- |
| octave | `$E0`-`$E7` | `$D0`-`$D7` |
| note_type (speed+envelope) | `$D0`-`$D9` | `$D8` |
| duty cycle | `$EC` (+1 byte) | `$DB` (+1 byte) |
| SFX priority on/off | *(no equivalent)* | `$EC`/`$ED` (0 extra bytes) |

`ChipSynth.lua`'s existing, unmodified decoder — reading Crystal's real
bytes as if they were Gen1's dialect — desyncs within the first few bytes
of every one of Wooper's three cry channels and ends each channel almost
immediately, producing ~0 samples of audio (correctly rejected as
inaudible by the synth's own silence check, not a crash and not a
wrong-sounding cry — just no sound).

`src/core/ChipSynth.lua` (854 lines, a single large opcode-range dispatch
— `if command >= 0xE0 and command <= 0xE7 then ... elseif ...`) is shared,
load-bearing playback code for every Gen1 sound in this project. Retrofitting
it to understand a second, differently-organized opcode table throughout
that dispatch would touch nearly every branch and carries real regression
risk to Gen1's audio. This spec instead translates Crystal's bytecode into
Gen1's dialect once, at extraction time — the same place every other piece
of Gen2 work (font, palette, map, tileset) already does its format
translation — so `ChipSynth.lua` itself needs zero changes and Gen1
playback is provably unaffected.

## Goal

Wooper's cry (the Oak-speech intro demo beat's sound) plays correctly
through the existing, unmodified chip-synth engine, by translating its
three real Crystal-dialect channel programs into Gen1's dialect once, at
manifest-build time.

## Non-goals

- Any Crystal audio besides Wooper's cry (no music, no other species'
  cries, no sound effects). This spec covers exactly the opcodes Wooper's
  three cry channels use, not a general Crystal-to-Gen1 audio-engine port.
- Modifying `src/core/ChipSynth.lua`, `ChipAudio.lua`, or `Sound.lua` in
  any way. The whole point of the chosen approach is that these stay
  byte-for-byte unchanged.
- A general-purpose, config-driven "opcode dialect" system. This is a
  narrowly-scoped, hardcoded translation for one real program, matching
  this project's established "extract exactly what's needed" discipline
  — not infrastructure for hypothetical future Crystal audio content.
- Anything about *why* the two engines' opcodes differ, or porting
  Crystal's own audio *playback* engine (`audio/engine.asm`) — only its
  *data format* (the command bytes) matters here.

## Reference

Same ROM and local `pret/pokecrystal` checkout as every prior Gen2 spec.
Wooper's cry is a 3-channel program, all in bank `$3c` (already confirmed
by the blocked Task 5's research, re-verified against the real ROM):

- Header: `Cry_Wooper` (`3c:6df6`) — `channel_count=3` + one 3-byte
  `{channel_number, address_lo, address_hi}` entry per channel, pointing at:
  - `Cry_Wooper_Ch5` (`3c:722e`, pulse channel 1): real bytes
    `db 02 02 99 18 07 04 ab 22 07 08 ab 34 07 04 d6 16 07 08 d1 12 07 08 00 00 00 ff de 07 02`
  - `Cry_Wooper_Ch6` (`3c:7249`, pulse channel 2): real bytes
    `de 07 02 b9 38 07 04 cb 42 07 08 cb 54 07 04 f6 36 07 08 f1 32 07 08 00 00 00 ff 02 5b 04`
  - `Cry_Wooper_Ch8` (`3c:7264`, noise channel): real bytes
    `02 5b 04 04 68 13 08 68 20 04 68 13 10 51 04 ff 02 8b 59 04 a8 6a 08 a8 70 04 a8 69 10 92`
  (each channel's dump above runs a little past its own end into the next
  symbol; the real per-channel length is bounded by the terminator opcode
  discovered during planning, not by these dump lengths.)
- Plain note records (a length byte below the command range, followed by
  packed volume/envelope and frequency bytes) appear to be byte-compatible
  between the two dialects already, based on manually cross-checking
  `Cry_Wooper_Ch5`'s `02 99 18 07` against pokecrystal's own
  `square_note 2, 9, -1, 1816` source line. If confirmed true during
  planning, the transcoder only needs to remap *command* bytes (duty
  cycle, octave, note_type, SFX priority, and whatever else Wooper's
  three channels turn out to use), passing note-data bytes through
  unchanged — narrowing the work considerably. Verify, don't assume.
- `macros/scripts/audio.asm` is pokecrystal's own authoritative source for
  every command's real byte encoding and parameter count — the transcoder's
  correctness depends entirely on reading this directly, not on inferring
  meaning from `ChipSynth.lua`'s Gen1-side comments.
- `Cry_Wooper`'s header, plus a `WaveSamples` dependency (`3a:4db2` — read
  unconditionally by `ChipSynth.lua`'s `Engine.new` regardless of whether
  a given header's channels use the hardware wave channel) and the
  two-level species→cry-index→header indirection, were already fully
  resolved and verified by the blocked Task 5 attempt. That plumbing is
  stashed (`git stash list`, message starting "Task 5 (Wooper cry)
  manifest/import plumbing") and should be recovered and reused as a
  starting point during planning, not redone from scratch.

## Architecture

New file:

| New file | Mirrors | Responsibility |
| --- | --- | --- |
| `tools/extract_gen2/cry_transcoder.py` (or a function within the existing manifest-builder script — exact split decided in planning, matching how palette/font resolution were structured) | This project's own established "resolve format differences from readable source at manifest-build time" pattern (font's charmap, the color spec's palette resolver) | Translates Crystal's real cry-channel command bytes into Gen1's dialect, producing plain byte sequences `ChipSynth.lua` already decodes correctly. |

Existing files, additions:

- `tools/make_rom_manifest_crystal.py`: the transcoder's output (translated
  channel bytes, or enough information to let the runtime extractor
  reconstruct them) added to the manifest, alongside the already-resolved
  `Cry_Wooper`/`WaveSamples` symbols and pitch/length values recovered
  from the stash.
- `src/import/RomExtractorGen2.lua`: recover Task 5's stashed
  `extractCry()` (bank dump, `waveBanks`, `cries.WOOPER` shape — already
  correct) and adjust it to write the *translated* channel bytes instead
  of (or alongside, if the translation is applied as a post-processing
  step over the raw dump rather than replacing specific symbol addresses)
  the raw Crystal ones. Exact mechanism — patch bytes into the dumped bank
  before writing `programs.bin`, or write a separately-assembled small
  program blob (`Engine.new`'s existing pseudo-bank-0 `chip` path, already
  used for mod-authored ChipAsm, confirmed to exist during Task 5's
  research) — decided in planning based on which is simpler and safer for
  a rewrite of exactly one program.

### Approaches considered

- **Chosen — translate the bytecode once, at extraction time.** Keeps
  `ChipSynth.lua` provably unchanged (verifiable by an empty diff on that
  file), matching this project's demonstrated preference throughout every
  Gen2 spec so far for doing format-reconciliation work in the extractor,
  never in shared runtime/rendering code.
- **Rejected — teach `ChipSynth.lua` a second opcode dialect.** Considered
  and explicitly declined by the human partner during brainstorming: the
  file's opcode dispatch is one large, tightly-coupled range-based
  `if/elseif` chain, not a table-driven dispatch a "dialect" parameter
  could cleanly thread through — retrofitting it touches nearly every
  branch and risks regressing Gen1's own, currently-correct audio.
- **Rejected — ship the Wooper demo beat silent, defer cry audio
  entirely.** Was the pragmatic fallback the blocked Task 5 report
  offered; the human partner chose to invest in real audio support now
  instead.

## Testing

- A hand-built fixture test (Python, mirroring `tools/extract_gen2/`'s
  existing `test_palettes.py`/`test_font.py` convention): feed the
  transcoder a small, synthetic byte sequence using Crystal's real opcode
  values for the specific commands Wooper's channels use, and assert the
  output matches the equivalent Gen1-dialect byte sequence by hand-deriving
  the expected translation from `macros/scripts/audio.asm`'s real command
  definitions — no ROM needed.
- Real-ROM manual verification: reimport Crystal, and confirm
  `Sound.playCry(Game.data, "WOOPER")` actually produces audible sound (not
  just "no error" — the blocked Task 5 attempt's own experience shows a
  silently-wrong translation can look clean while still rendering to
  near-zero samples). If this project has any way to capture/inspect
  rendered audio samples programmatically (worth checking during planning
  — `ChipAudio._renderMusicForTest`-style test helpers already exist for
  music; an analogous cry-rendering check would give a stronger,
  automatable signal than "a human presses play and listens").

## Acceptance criteria

1. The transcoder's output, fed through the real `ChipSynth.lua`
   unmodified, renders more than the "inaudible" sample-count floor
   `ChipAudio.lua`'s `renderEffectData` already checks for, for all three
   of Wooper's cry channels.
2. `Sound.playCry(Game.data, "WOOPER")` audibly plays a cry sound during
   real-ROM manual verification (not silence, not an error).
3. `src/core/ChipSynth.lua`, `ChipAudio.lua`, and `Sound.lua` show zero
   diff from before this spec's implementation.
4. The fixture-backed transcoder test passes with no ROM present.
5. Zero regression to Gen1's existing music/SFX/cry playback (full test
   suite stays green).
6. This unblocks the Gen2 intro plan's own Task 5, which resumes from its
   stashed plumbing once this spec lands.

## Follow-on work (explicitly out of scope here)

- Translating any other Crystal cry, sound effect, or music track.
- A general Crystal-dialect-aware audio pipeline, if this project ever
  wants broader Gen2 audio support.
