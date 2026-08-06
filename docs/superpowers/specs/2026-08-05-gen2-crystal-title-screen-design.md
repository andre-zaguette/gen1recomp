# Gen2 (Crystal) Title Screen — Visuals + Title Music

Status: proposed, 2026-08-05
Date: 2026-08-05

## Context

The Gen2 walking skeleton (`docs/superpowers/specs/2026-08-03-gen2-crystal-extraction-skeleton-design.md`)
proved the Crystal import pipeline end-to-end for New Bark Town, and a
follow-on slice (`docs/superpowers/specs/2026-08-04-gen2-crystal-cry-transcoder-design.md`)
proved it for one Pokémon cry (Wooper). Both explicitly scoped the title
screen and audio programs as non-goals.

Running the current build against a real Crystal ROM surfaces the gap
directly: the window title correctly reads "Pokemon Crystal" (`GameVersion`
and `CacheFs` both resolve Crystal correctly — verified via the mounted
cache under LÖVE's save directory, populated during Crystal import), but
the title *screen* shows Red's logo, "POKéMON RED" text, and no music.
Root cause, confirmed by reading the code: `src/ui/TitleState.lua` has no
Crystal branch — it only checks `GameVersion.isBlue()` / `isYellow()` — so
it falls straight through to the Red fallback path by construction. Crystal
audio only contains Wooper's cry; there is no `data.audio.songs` table for
any Crystal song, so `TitleState:startMusic()`'s existing guard
(`if data.audio and data.audio.songs and data.audio.songs[song] then`)
silently no-ops.

A local `pret/pokecrystal` checkout has now been cloned and built with
RGBDS (matching `.rgbds-version`, 1.0.3), producing `pokecrystal.sym` —
unblocking address-accurate extraction the same way the existing Gen1 and
Gen2-skeleton pipelines already work.

Reading the real title sequence (`engine/movie/title.asm`,
`engine/menus/intro_menu.asm`) shows it is simpler than it looks on
screen: the "wave" entrance is a 28-frame horizontal wipe (SCX 112 → 0)
with alternating scanlines offset in opposite directions — not a
raster/HDMA water-ripple effect — and Suicune's "running" animation is a
4-frame BG tile swap every 8 frames at a fixed position. Both are ordinary
2D animation, reproducible with ordinary blitting, no shader or hardware
raster emulation required. The three graphics involved
(`suicune.2bpp.lz`, `logo.2bpp.lz`, `crystal.2bpp.lz`) use the same LZ
scheme `RomExtractorGen2.lua`'s `Lz3.decompress` already decodes for other
Crystal assets.

The title music (`audio/music/titlescreen.asm`, `Music_TitleScreen`) is a
full 4-channel song using a materially richer opcode set than the cry
transcoder covers (`tempo`, `volume`, `duty_cycle`, `pitch_offset`,
`vibrato`, `stereo_panning`, `note_type`, `octave`, `rest`, `sound_call`,
`sound_loop`, plus `drum_note`/`drum_speed`/`toggle_noise` on the noise
channel), and channel 3 is a wave channel — a different mechanism
entirely from the pulse/noise channels `CrystalCryTranscoder.lua` knows.
`src/audio/ChipAsm.lua`, however, already supports essentially this whole
event vocabulary (`note`, `rest`, `notetype`, `octave`, `vibrato`, `duty`,
`tempo`, `pan`, `call`, `loop`, `ret`) and already has a `ChipAsm.song(...)`
assembler distinct from `.sfx(...)` — this is Gen1 music's own vocabulary,
built for real songs already. The new work is a decoder from Crystal's
bytecode into that existing shape, not new engine capability.

## Goal

1. When Crystal is the active version, the title screen shows Crystal's
   own presentation: the Pokémon logo with its interlaced wipe-in entrance,
   the falling crystal ornament, the "CRYSTAL VERSION" ribbon, Suicune's
   4-frame running animation loop, and the copyright line.
2. The title screen plays `Music_TitleScreen`, transcoded from the real
   ROM's bytecode, on channels 1 (lead), 2 (harmony), and 4 (noise/drums).

## Non-goals

- Channel 3 (wave) transcoding. The title theme's bass/harmony layer stays
  silent until a follow-on spec covers the wave channel mechanism, which is
  unrelated to the pulse/noise decoding this spec builds.
- The ~74-second idle timer that auto-returns to the intro sequence
  (`TitleScreenTimer` / `TitleScreenEnd` in `intro_menu.asm`). No existing
  version (Red/Blue/Yellow) implements this "attract mode" loop either, so
  this is not a new gap relative to what the engine already does.
- Gold/Silver support.
- Any unification of `CrystalCryTranscoder.lua` and the new music
  transcoder into one shared module. They decode meaningfully different
  opcode sets for different purposes; per the walking skeleton's own
  precedent, this project keeps Gen1/Gen2 (and now cry/song) pipelines
  parallel rather than guessing a shared abstraction early.
- Extending `RomExtractor.lua` (Gen1) or its title-screen code — this spec
  only touches the Gen2 (Crystal) path.

## Architecture

### Extraction (`tools/`, `RomExtractorGen2.lua`)

- Extend `tools/make_rom_manifest_crystal.py` / `tools/rom_manifest_crystal.json`
  with symbols for `TitleSuicuneGFX`, `TitleLogoGFX`, `TitleCrystalGFX`
  (the falling ornament — distinct from the "Crystal" version name),
  `TitleScreenPalettes`, and the addresses/lengths of
  `Music_TitleScreen_Ch1`/`_Ch2`/`_Ch4`.
- New `RomExtractorGen2:extractTitle()`: decompresses the three graphics
  via the existing `Lz3.decompress`, converts them to PNGs via
  `ImageWriter` (mirroring `extractIntroPics`'s pattern), and extracts the
  title palette. Writes into `data.field.title` in the exact shape
  `TitleState.lua:146-162` already reads (`logo`, `versionRibbon` /
  `version`, plus new keys for the Suicune frame set and the crystal
  ornament) — no new config surface, reusing the existing seed point.
- New `RomExtractorGen2:extractTitleMusic()`: reads the Ch1/Ch2/Ch4 byte
  streams and calls `CrystalMusicTranscoder.buildSong(...)`, writing the
  result into `data.audio.songs.Music_TitleScreen` (extending
  `extractCry`'s existing `audio` table rather than replacing it).

### `src/audio/CrystalMusicTranscoder.lua` (new)

A sibling to `CrystalCryTranscoder.lua`, not a rewrite of it. Decodes
Crystal's music-channel bytecode — the pulse-channel opcode set (`tempo`,
`volume`, `duty_cycle`, `pitch_offset`, `vibrato`, `stereo_panning`,
`note_type`, `octave`, `rest`, note records, `sound_call`, `sound_loop`,
`sound_ret`) and the noise-channel opcode set (`drum_note`, `drum_speed`,
`rest`, `toggle_noise`, `stereo_panning`, `sound_call`/`loop`/`ret`) — into
the ChipAsm event table shape `ChipAsm.song(...)` already assembles
(`note`, `rest`, `notetype`, `octave`, `vibrato`, `duty`, `tempo`, `pan`,
`call`, `loop`, `ret`, `noiseNote`/drum equivalents). `sound_call` /
`sound_loop` introduce non-linear control flow the cry transcoder never
had to handle (cries are a flat event list); this decoder resolves them
into ChipAsm's own `call`/`loop`/label events rather than inlining/
unrolling, so the assembled song can loop the way the original does.

### Playback

No changes needed to `TitleState:startMusic()` — its existing guard
(`src/ui/TitleState.lua:203-209`) already only plays a song if
`data.audio.songs[song]` is present; once extraction populates that key,
playback works unchanged. Implementation must confirm `ChipAsm.song()` and
the runtime channel player tolerate a 3-of-4-channel song (channel 3 absent
or explicitly silent) without assuming all four channels are populated.

### Title screen visuals (`src/ui/TitleState.lua`)

Add `self.crystalLayout = GameVersion.isCrystal()`, a third top-level
layout branch alongside the existing Red/Blue path and `yellowLayout` —
same shape as the existing pattern, not a new class:

- **Entrance**: the interlaced wipe-in, implemented as per-row (or small
  row-group) blits of the logo texture, each row's x-offset animating from
  ±112 to 0 over 28 frames (ordinary 2D blitting — no shader, no hardware
  raster emulation) — plus the crystal ornament sprite dropping in,
  reusing the shape of the existing `DROP_STEPS` bounce table Red's logo
  already uses.
- **Loop**: Suicune's 4-frame tile-swap animation (advancing every 8
  frames) at its fixed screen position, the "CRYSTAL VERSION" ribbon
  graphic, and the copyright line (reuses the existing `Strings`/`Font`
  calls already in this file).
- `sgbPalettes` returns `nil` for `crystalLayout` — Crystal is GBC-only,
  no SGB pack exists for it.

### Data flow

```
pokecrystal checkout + built pokecrystal.sym (local, dev-only, not committed)
        |
        v  tools/make_rom_manifest_crystal.py (extended)
tools/rom_manifest_crystal.json  (committed, extended)
        |
        v  RomExtractorGen2:extractTitle() / extractTitleMusic(), at import
player's real Crystal ROM ------------------+
        |                                   |
        v                                   v
   Lz3.decompress (graphics)      CrystalMusicTranscoder (Ch1/Ch2/Ch4 bytecode)
        |                                   |
        v                                   v
crystal/data/generated/field.lua      crystal/data/generated/audio.lua
  (.title: logo/version/suicune/         (.songs.Music_TitleScreen)
   crystal ornament/palette)
        |                                   |
        +------------------+----------------+
                            v
              src/ui/TitleState.lua (crystalLayout branch)
              reads field.title + data.audio.songs, same
              code path Red/Blue/Yellow already use
```

## Approaches considered

- **Chosen — extend `TitleState.lua` with a `crystalLayout` branch,
  extend `RomExtractorGen2` with new extraction methods, add a sibling
  `CrystalMusicTranscoder` module.** Directly mirrors precedent already
  established by `yellowLayout` (visuals) and `CrystalCryTranscoder.lua`
  (a scoped, narrow bytecode decoder for one job). Minimal new
  architecture; reuses `Lz3.decompress`, `ChipAsm.song()`, and the
  existing `field.title` / `data.audio.songs` seams verbatim.
- **Rejected — a separate `TitleStateGen2` class.** Would duplicate the
  menu, `ContinueInfo`, `Strings`/`Font`, and `Sound`/`Music` integration
  `TitleState.lua` already has, for no benefit: Crystal's title differs
  only in its entrance animation and idle-loop art, not in its menu
  behavior. The existing file already carries two layouts
  (Red/Blue vs. Yellow) this way.
- **Rejected — approximate the entrance/Suicune animation without
  reading the real ROM data (guessed timings/positions).** Reading the
  actual disassembly cost little (the checkout was already available) and
  removes any guesswork; this project's whole extraction philosophy is
  reading real addresses, not approximating.
- **Rejected — fold the wave channel into this spec's scope.** Channel 3
  uses a fundamentally different sample-playback mechanism than the
  pulse/noise channels this spec's transcoder covers; bundling it would
  block the rest of the title-music work on a separate, harder decoding
  problem. Deferred explicitly (see Non-goals).

## Risks

- **Cross-engine pitch/frequency scaling.** `CrystalCryTranscoder`'s own
  comments document that Wooper's cry pitch/length values were verified
  correct by ear, not by a structural formula, because the Gen1 engine's
  frequency-offset conventions weren't designed around Crystal's byte
  ranges. A full song, with `pitch_offset` events and a wider pitch range
  than one cry, may expose scaling mismatches a single cry never could.
  Mitigation: by-ear verification against the real ROM is part of this
  spec's testing, same as the cry precedent.
- **`sound_call`/`sound_loop` control flow.** The cry transcoder only ever
  emits a flat event list. Songs use subroutine calls and loop points;
  getting this wrong could hang playback or silently drop the loop.
  Mitigation: dedicated unit tests for `sound_call`/`sound_loop` decoding,
  and manual playback verification that the loop point sounds right.
- **Thinner sound without channel 3.** Deferring the wave channel means
  the transcoded title theme will audibly lack its bass/harmony layer
  compared to the real game until a follow-on spec lands. This is a known,
  accepted gap for this slice, not a bug.

## Testing

- `tests/fixture_data_gen2/` gains a small synthetic title fixture (fake
  logo/Suicune/crystal-ornament tiles, a fake short 3-channel song) so CI
  can exercise `extractTitle()` / `extractTitleMusic()` and
  `CrystalMusicTranscoder` without the real ROM, mirroring the existing
  fixture-based tier.
- `CrystalMusicTranscoder` gets direct unit coverage per opcode (`tempo`,
  `vibrato`, `octave`, `note_type`, `pitch_offset`, `stereo_panning`,
  `rest`, `sound_call`/`sound_loop`, `drum_note`/`drum_speed`,
  `toggle_noise`), plus a case covering a loop point round-tripping
  correctly.
- Manual/local verification against the real ROM: the title screen
  renders with Crystal's own art, the entrance wipe and Suicune animation
  play correctly, and the title theme is audibly recognizable as the real
  song (by-ear verification, same precedent as the Wooper cry).

## Acceptance criteria

1. Selecting/booting Crystal with the real ROM present shows the Crystal
   logo, version ribbon, falling crystal ornament, and animated Suicune —
   not the Red fallback.
2. The entrance wipe-in and Suicune's 4-frame loop play at the correct
   timing (28-frame wipe, 8-frame-per-tile-swap loop).
3. `Music_TitleScreen` plays on channels 1/2/4, audibly recognizable
   against the real game, with channel 3 silent (documented, not a bug).
4. `luajit tests/run_tests.lua` passes the new fixture-backed title/music
   cases with no ROM present.
5. Manual verification against the real ROM confirms the title screen and
   music match the source game structurally and audibly (channel 3
   excepted).

## Follow-on work (explicitly out of scope here)

- Channel 3 (wave channel) transcoding, to give the title theme its full
  4-channel sound.
- The ~74-second idle timer / auto-return-to-intro-sequence behavior.
- Applying `CrystalMusicTranscoder` to Crystal's other music/SFX beyond
  the title screen.
- Gold/Silver title screens (reusing this pipeline's shape once proven).
